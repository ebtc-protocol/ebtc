// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./Interfaces/IActivePool.sol";
import "./Interfaces/ICollSurplusPool.sol";
import "./Dependencies/ICollateralToken.sol";
import "./Dependencies/ERC3156FlashLender.sol";
import "./Dependencies/SafeERC20.sol";
import "./Dependencies/ReentrancyGuard.sol";
import "./Dependencies/AuthNoOwner.sol";

/**
 * The Active Pool holds the collateral and EBTC debt (but not EBTC tokens) for all active cdps.
 *
 * When a cdp is liquidated, it's collateral and EBTC debt are transferred from the Active Pool, to either the
 * Stability Pool, the Default Pool, or both, depending on the liquidation conditions.
 */
contract ActivePool is IActivePool, ERC3156FlashLender, ReentrancyGuard {
    using SafeERC20 for IERC20;
    string public constant NAME = "ActivePool";

    address public immutable borrowerOperationsAddress;
    address public immutable cdpManagerAddress;
    address public immutable collSurplusPoolAddress;
    address public feeRecipientAddress;

    uint256 internal StEthColl; // deposited collateral tracker
    uint256 internal EBTCDebt;
    uint256 internal FeeRecipientColl; // coll shares claimable by fee recipient
    ICollateralToken public collateral;

    // --- Contract setters ---

    /// @notice Constructor for the ActivePool contract
    /// @dev Initializes the contract with the borrowerOperationsAddress, cdpManagerAddress, collateral token address, collSurplusAddress, and feeRecipientAddress
    /// @param _borrowerOperationsAddress The address of the Borrower Operations contract
    /// @param _cdpManagerAddress The address of the Cdp Manager contract
    /// @param _collTokenAddress The address of the collateral token
    /// @param _collSurplusAddress The address of the collateral surplus pool
    /// @param _feeRecipientAddress The address of the fee recipient

    constructor(
        address _borrowerOperationsAddress,
        address _cdpManagerAddress,
        address _collTokenAddress,
        address _collSurplusAddress,
        address _feeRecipientAddress
    ) {
        borrowerOperationsAddress = _borrowerOperationsAddress;
        cdpManagerAddress = _cdpManagerAddress;
        collateral = ICollateralToken(_collTokenAddress);
        collSurplusPoolAddress = _collSurplusAddress;
        feeRecipientAddress = _feeRecipientAddress;

        // TEMP: read authority to avoid signature change
        address _authorityAddress = address(AuthNoOwner(cdpManagerAddress).authority());
        if (_authorityAddress != address(0)) {
            _initializeAuthority(_authorityAddress);
        }

        emit BorrowerOperationsAddressChanged(_borrowerOperationsAddress);
        emit CdpManagerAddressChanged(_cdpManagerAddress);
        emit CollateralAddressChanged(_collTokenAddress);
        emit CollSurplusPoolAddressChanged(_collSurplusAddress);
        emit FeeRecipientAddressChanged(_feeRecipientAddress);
    }

    // --- Getters for public variables. Required by IPool interface ---

    /// @notice Amount of stETH collateral shares in the contract
    /// @dev Not necessarily equal to the the contract's raw StEthColl balance - tokens can be forcibly sent to contracts
    /// @return uint256 The amount of StEthColl allocated to the pool

    function getStEthColl() external view override returns (uint256) {
        return StEthColl;
    }

    /// @notice Returns the EBTCDebt state variable
    /// @dev The amount of EBTC debt in the pool. Like StEthColl, this is not necessarily equal to the contract's EBTC token balance - tokens can be forcibly sent to contracts
    /// @return uint256 The amount of EBTC debt in the pool

    function getEBTCDebt() external view override returns (uint256) {
        return EBTCDebt;
    }

    /// @notice The amount of stETH collateral shares claimable by the fee recipient
    /// @return uint256 The amount of collateral shares claimable by the fee recipient

    function getFeeRecipientClaimableColl() external view override returns (uint256) {
        return FeeRecipientColl;
    }

    // --- Pool functionality ---

    /// @notice Sends stETH collateral shares to a specified account
    /// @dev Only for use by system contracts, the caller must be either BorrowerOperations or CdpManager
    /// @param _account The address of the account to send stETH to
    /// @param _shares The amount of stETH shares to send

    function sendStEthColl(address _account, uint256 _shares) public override {
        _requireCallerIsBOorCdpM();

        uint256 cachedStEthColl = StEthColl;
        require(cachedStEthColl >= _shares, "!ActivePoolBal");
        unchecked {
            // Can use unchecked due to above
            cachedStEthColl -= _shares; // Updating here avoids an SLOAD
        }

        StEthColl = cachedStEthColl;

        emit ActivePoolCollBalanceUpdated(cachedStEthColl);
        emit CollateralSent(_account, _shares);

        _transferSharesWithContractHooks(_account, _shares);
    }

    /// @notice Sends stETH to a specified account, drawing from both core shares and liquidator rewards shares
    /// @notice Liquidator reward shares are not tracked via internal accounting in the active pool and are assumed to be present in expected amount as part of the intended behavior of BorowerOperations and CdpManager
    /// @dev Liquidator reward shares are added when a cdp is opened, and removed when it is closed
    /// @dev closeCdp() or liqudations result in the actor (borrower or liquidator respectively) receiving the liquidator reward shares
    /// @dev Redemptions result in the shares being sent to the coll surplus pool for claiming by the CDP owner
    /// @dev Note that funds in the coll surplus pool, just like liquidator reward shares, are not tracked as part of the system CR or coll of a CDP.
    /// @dev Requires that the caller is either BorrowerOperations or CdpManager
    /// @param _account The address of the account to send StEthColl and the liquidator reward to
    /// @param _shares The amount of StEthColl to send
    /// @param _liquidatorRewardShares The amount of the liquidator reward shares to send

    function sendStEthCollAndLiquidatorReward(
        address _account,
        uint256 _shares,
        uint256 _liquidatorRewardShares
    ) external override {
        _requireCallerIsBOorCdpM();

        uint256 cachedStEthColl = StEthColl;
        require(cachedStEthColl >= _shares, "ActivePool: Insufficient collateral shares");
        uint256 totalShares = _shares + _liquidatorRewardShares; // TODO: Is this safe?
        unchecked {
            // Safe per the check above
            cachedStEthColl -= _shares;
        }
        StEthColl = cachedStEthColl;

        emit ActivePoolCollBalanceUpdated(cachedStEthColl);
        emit CollateralSent(_account, totalShares);

        _transferSharesWithContractHooks(_account, totalShares);
    }

    /// @notice Allocate stETH shares from the system to the fee recipient to claim at-will (pull model)
    /// @dev Requires that the caller is CdpManager
    /// @dev Only the current fee recipient address is able to claim the shares
    /// @dev If the fee recipient address is changed while outstanding claimable coll is available, only the new fee recipient will be able to claim the outstanding coll
    /// @param _shares The amount of StEthColl to allocate to the fee recipient

    function allocateFeeRecipientColl(uint256 _shares) external override {
        _requireCallerIsCdpManager();

        uint256 cachedStEthColl = StEthColl;
        uint256 _FeeRecipientColl = FeeRecipientColl;

        require(cachedStEthColl >= _shares, "ActivePool: Insufficient collateral shares");
        unchecked {
            // Safe per the check above
            cachedStEthColl -= _shares;
        }

        StEthColl = cachedStEthColl;
        FeeRecipientColl = _FeeRecipientColl + _shares;

        emit ActivePoolCollBalanceUpdated(cachedStEthColl);
        emit ActivePoolFeeRecipientClaimableCollIncreased(FeeRecipientColl, _shares);
    }

    /// @notice Helper function to transfer stETH shares to another address, ensuring to call hooks into other system pools if they are the recipient
    /// @param _account The address to transfer shares to
    /// @param _shares The amount of shares to transfer

    function _transferSharesWithContractHooks(address _account, uint256 _shares) internal {
        // NOTE: No need for safe transfer if the collateral asset is standard. Make sure this is the case!
        collateral.transferShares(_account, _shares);

        if (_account == collSurplusPoolAddress) {
            ICollSurplusPool(_account).receiveColl(_shares);
        }
    }

    /// @notice Increases the tracked EBTC debt of the system by a specified amount
    /// @dev Managed by system contracts - requires that the caller is either BorrowerOperations or CdpManager
    /// @param _amount: The amount to increase the system EBTC debt by

    function increaseEBTCDebt(uint256 _amount) external override {
        _requireCallerIsBOorCdpM();

        uint256 cachedEBTCDebt = EBTCDebt + _amount;

        EBTCDebt = cachedEBTCDebt;
        emit ActivePoolEBTCDebtUpdated(cachedEBTCDebt);
    }

    /// @notice Decreases the tracked EBTC debt of the system by a specified amount
    /// @dev Managed by system contracts - requires that the caller is either BorrowerOperations or CdpManager
    /// @param _amount: The amount to decrease the system EBTC debt by

    function decreaseEBTCDebt(uint256 _amount) external override {
        _requireCallerIsBOorCdpM();

        uint256 cachedEBTCDebt = EBTCDebt - _amount;

        EBTCDebt = cachedEBTCDebt;
        emit ActivePoolEBTCDebtUpdated(cachedEBTCDebt);
    }

    // --- 'require' functions ---

    /// @notice Checks if the caller is BorrowerOperations
    function _requireCallerIsBorrowerOperations() internal view {
        require(
            msg.sender == borrowerOperationsAddress,
            "ActivePool: Caller is not BorrowerOperations"
        );
    }

    /// @notice Checks if the caller is either BorrowerOperations or CdpManager
    function _requireCallerIsBOorCdpM() internal view {
        require(
            msg.sender == borrowerOperationsAddress || msg.sender == cdpManagerAddress,
            "ActivePool: Caller is neither BorrowerOperations nor CdpManager"
        );
    }

    /// @notice Checks if the caller is CdpManager
    function _requireCallerIsCdpManager() internal view {
        require(msg.sender == cdpManagerAddress, "ActivePool: Caller is not CdpManager");
    }

    /// @notice Notify that stETH collateral shares have been recieved, updating internal accounting accordingly
    /// @param _value The amount of collateral to receive

    function receiveColl(uint256 _value) external override {
        _requireCallerIsBorrowerOperations();

        uint256 cachedStEthColl = StEthColl + _value;
        StEthColl = cachedStEthColl;
        emit ActivePoolCollBalanceUpdated(cachedStEthColl);
    }

    // === Flashloans === //

    /// @notice Borrow assets with a flash loan
    /// @param receiver The address to receive the flash loan
    /// @param token The address of the token to loan
    /// @param amount The amount of tokens to loan
    /// @param data Additional data
    /// @return A boolean value indicating whether the operation was successful

    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) external override returns (bool) {
        require(amount > 0, "ActivePool: 0 Amount");
        require(amount <= maxFlashLoan(token), "ActivePool: Too much");
        // NOTE: Check for `token` is implicit in the requires above

        require(flashLoansPaused == false, "ActivePool: Flash Loans Paused");
        uint256 fee = (amount * feeBps) / MAX_BPS;

        uint256 amountWithFee = amount + fee;
        uint256 oldRate = collateral.getPooledEthByShares(1e18);

        collateral.transfer(address(receiver), amount);

        // Callback
        require(
            receiver.onFlashLoan(msg.sender, token, amount, fee, data) == FLASH_SUCCESS_VALUE,
            "ActivePool: IERC3156: Callback failed"
        );

        // Transfer of (principal + Fee) from flashloan receiver
        collateral.transferFrom(address(receiver), address(this), amountWithFee);

        // Send earned fee to designated recipient
        collateral.transfer(feeRecipientAddress, fee);

        // Check new balance
        // NOTE: Invariant Check, technically breaks CEI but I think we must use it
        // NOTE: This means any balance > StEthColl is stuck, this is also present in LUSD as is

        // NOTE: This check effectively prevents running 2 FL at the same time
        //  You technically could, but you'd be having to repay any amount below StEthColl to get Fl2 to not revert
        require(
            collateral.balanceOf(address(this)) >= collateral.getPooledEthByShares(StEthColl),
            "ActivePool: Must repay Balance"
        );
        require(collateral.sharesOf(address(this)) >= StEthColl, "ActivePool: Must repay Share");
        require(
            collateral.getPooledEthByShares(1e18) == oldRate,
            "ActivePool: Should keep same collateral share rate"
        );

        emit FlashLoanSuccess(address(receiver), token, amount, fee);

        return true;
    }

    /// @notice Calculate the flash loan fee for a given token and amount loaned
    /// @param token The address of the token to calculate the fee for
    /// @param amount The amount of tokens to calculate the fee for
    /// @return The amount of the flash loan fee

    function flashFee(address token, uint256 amount) external view override returns (uint256) {
        require(token == address(collateral), "ActivePool: collateral Only");

        return (amount * feeBps) / MAX_BPS;
    }

    /// @notice Get the maximum flash loan amount for a specific token
    /// @dev Exclusively used here for stETH collateral, equal to the current balance of the pool
    /// @param token The address of the token to get the maximum flash loan amount for
    /// @return The maximum flash loan amount for the token
    function maxFlashLoan(address token) public view override returns (uint256) {
        if (token != address(collateral)) {
            return 0;
        }

        return collateral.balanceOf(address(this));
    }

    // === Governed Functions === //

    /// @notice Claim outstanding shares for fee recipient, updating internal accounting and transferring the shares.
    /// @dev Call permissinos are managed via authority for flexibility, rather than gating call to just feeRecipient.
    /// @dev Is likely safe as an open permission though caution should be taken.
    /// @param _shares The amount of shares to claim to feeRecipient

    function claimFeeRecipientColl(uint256 _shares) external override requiresAuth {
        uint256 _FeeRecipientColl = FeeRecipientColl;
        require(_FeeRecipientColl >= _shares, "ActivePool: Insufficient fee recipient coll");
        unchecked {
            _FeeRecipientColl -= _shares;
        }

        FeeRecipientColl = _FeeRecipientColl;
        emit ActivePoolFeeRecipientClaimableCollDecreased(_FeeRecipientColl, _shares);

        collateral.transferShares(feeRecipientAddress, _shares);
    }

    /// @dev Function to move unintended dust that are not protected
    /// @notice moves given amount of given token (collateral is NOT allowed)
    /// @notice because recipient are fixed, this function is safe to be called by anyone

    function sweepToken(address token, uint256 amount) public nonReentrant requiresAuth {
        require(token != address(collateral), "ActivePool: Cannot Sweep Collateral");

        uint256 balance = IERC20(token).balanceOf(address(this));
        require(amount <= balance, "ActivePool: Attempt to sweep more than balance");

        address cachedFeeRecipientAddress = feeRecipientAddress; // Saves an SLOAD

        IERC20(token).safeTransfer(cachedFeeRecipientAddress, amount);

        emit SweepTokenSuccess(token, amount, cachedFeeRecipientAddress);
    }

    function setFeeRecipientAddress(address _feeRecipientAddress) external requiresAuth {
        require(
            _feeRecipientAddress != address(0),
            "ActivePool: cannot set fee recipient to zero address"
        );
        feeRecipientAddress = _feeRecipientAddress;
        emit FeeRecipientAddressChanged(_feeRecipientAddress);
    }
}
