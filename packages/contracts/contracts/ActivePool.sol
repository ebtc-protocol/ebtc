// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./Interfaces/IActivePool.sol";
import "./Interfaces/ICollSurplusPool.sol";
import "./Dependencies/ICollateralToken.sol";
import "./Interfaces/ICdpManagerData.sol";
import "./Interfaces/IBorrowerOperations.sol";
import "./Dependencies/ERC3156FlashLender.sol";
import "./Dependencies/SafeERC20.sol";
import "./Dependencies/ReentrancyGuard.sol";
import "./Dependencies/AuthNoOwner.sol";
import "./Dependencies/BaseMath.sol";
import "./Dependencies/TwapWeightedObserver.sol";
import "./Dependencies/EbtcMath.sol";

/**
 * @title The Active Pool holds the collateral and EBTC debt (only accounting but not EBTC tokens) for all active cdps.
 *
 * @notice When a cdp is liquidated, it's collateral will be transferred from the Active Pool
 * @notice (destination may vary depending on the liquidation conditions).
 * @dev ActivePool also allows ERC3156 compatible flashloan of stETH token
 */
contract ActivePool is
    IActivePool,
    ERC3156FlashLender,
    ReentrancyGuard,
    BaseMath,
    AuthNoOwner,
    TwapWeightedObserver
{
    using SafeERC20 for IERC20;
    string public constant NAME = "ActivePool";

    address public immutable borrowerOperationsAddress;
    address public immutable cdpManagerAddress;
    address public immutable collSurplusPoolAddress;
    address public immutable feeRecipientAddress;

    uint256 internal systemCollShares; // deposited collateral tracker
    uint256 internal systemDebt;
    uint256 internal feeRecipientCollShares; // coll shares claimable by fee recipient
    ICollateralToken public immutable collateral;

    // --- Contract setters ---

    /// @notice Constructor for the ActivePool contract
    /// @dev Initializes the contract with the borrowerOperationsAddress, cdpManagerAddress, collateral token address, collSurplusAddress, and feeRecipientAddress
    /// @param _borrowerOperationsAddress The address of the Borrower Operations contract
    /// @param _cdpManagerAddress The address of the Cdp Manager contract
    /// @param _collTokenAddress The address of the collateral token
    /// @param _collSurplusAddress The address of the collateral surplus pool

    constructor(
        address _borrowerOperationsAddress,
        address _cdpManagerAddress,
        address _collTokenAddress,
        address _collSurplusAddress
    ) TwapWeightedObserver(0) {
        borrowerOperationsAddress = _borrowerOperationsAddress;
        cdpManagerAddress = _cdpManagerAddress;
        collateral = ICollateralToken(_collTokenAddress);
        collSurplusPoolAddress = _collSurplusAddress;
        feeRecipientAddress = IBorrowerOperations(borrowerOperationsAddress).feeRecipientAddress();

        // TEMP: read authority to avoid signature change
        address _authorityAddress = address(AuthNoOwner(cdpManagerAddress).authority());
        if (_authorityAddress != address(0)) {
            _initializeAuthority(_authorityAddress);
        }

        require(systemDebt == 0, "ActivePool: systemDebt should be 0 for TWAP initialization");
    }

    // --- Getters for public variables. Required by IPool interface ---

    /// @notice Amount of stETH collateral shares in the contract
    /// @dev Not necessarily equal to the the contract's raw systemCollShares balance - tokens can be forcibly sent to contracts
    /// @return uint256 The amount of systemCollShares allocated to the pool

    function getSystemCollShares() external view override returns (uint256) {
        return systemCollShares;
    }

    /// @notice Returns the systemDebt state variable
    /// @dev The amount of EBTC debt in the pool. Like systemCollShares, this is not necessarily equal to the contract's EBTC token balance - tokens can be forcibly sent to contracts
    /// @return uint256 The amount of EBTC debt in the pool

    function getSystemDebt() external view override returns (uint256) {
        return systemDebt;
    }

    /// @notice The amount of stETH collateral shares claimable by the fee recipient
    /// @return uint256 The amount of collateral shares claimable by the fee recipient

    function getFeeRecipientClaimableCollShares() external view override returns (uint256) {
        return feeRecipientCollShares;
    }

    // --- Pool functionality ---

    /// @notice Sends stETH collateral shares to a specified account
    /// @dev Only for use by system contracts, the caller must be either BorrowerOperations or CdpManager
    /// @param _account The address of the account to send stETH to
    /// @param _shares The amount of stETH shares to send

    function transferSystemCollShares(address _account, uint256 _shares) public override {
        _requireCallerIsBOorCdpM();

        uint256 cachedSystemCollShares = systemCollShares;
        require(cachedSystemCollShares >= _shares, "!ActivePoolBal");
        unchecked {
            // Can use unchecked due to above
            cachedSystemCollShares -= _shares; // Updating here avoids an SLOAD
        }

        systemCollShares = cachedSystemCollShares;

        emit SystemCollSharesUpdated(cachedSystemCollShares);
        emit CollSharesTransferred(_account, _shares);

        _transferCollSharesWithContractHooks(_account, _shares);
    }

    /// @notice Sends stETH to a specified account, drawing from both core shares and liquidator rewards shares
    /// @notice Liquidator reward shares are not tracked via internal accounting in the active pool and are assumed to be present in expected amount as part of the intended behavior of BorowerOperations and CdpManager
    /// @dev Liquidator reward shares are added when a cdp is opened, and removed when it is closed
    /// @dev closeCdp() or liqudations result in the actor (borrower or liquidator respectively) receiving the liquidator reward shares
    /// @dev Redemptions result in the shares being sent to the coll surplus pool for claiming by the CDP owner
    /// @dev Note that funds in the coll surplus pool, just like liquidator reward shares, are not tracked as part of the system CR or coll of a CDP.
    /// @dev Requires that the caller is either BorrowerOperations or CdpManager
    /// @param _account The address of the account to send systemCollShares and the liquidator reward to
    /// @param _shares The amount of systemCollShares to send
    /// @param _liquidatorRewardShares The amount of the liquidator reward shares to send

    function transferSystemCollSharesAndLiquidatorReward(
        address _account,
        uint256 _shares,
        uint256 _liquidatorRewardShares
    ) external override {
        _requireCallerIsBOorCdpM();

        uint256 cachedSystemCollShares = systemCollShares;
        require(cachedSystemCollShares >= _shares, "ActivePool: Insufficient collateral shares");
        uint256 totalShares = _shares + _liquidatorRewardShares;
        unchecked {
            // Safe per the check above
            cachedSystemCollShares -= _shares;
        }
        systemCollShares = cachedSystemCollShares;

        emit SystemCollSharesUpdated(cachedSystemCollShares);
        emit CollSharesTransferred(_account, totalShares);

        _transferCollSharesWithContractHooks(_account, totalShares);
    }

    /// @notice Allocate stETH shares from the system to the fee recipient to claim at-will (pull model)
    /// @dev Requires that the caller is CdpManager
    /// @dev Only the current fee recipient address is able to claim the shares
    /// @dev If the fee recipient address is changed while outstanding claimable coll is available, only the new fee recipient will be able to claim the outstanding coll
    /// @param _shares The amount of systemCollShares to allocate to the fee recipient

    function allocateSystemCollSharesToFeeRecipient(uint256 _shares) external override {
        _requireCallerIsCdpManager();

        uint256 cachedSystemCollShares = systemCollShares;

        require(cachedSystemCollShares >= _shares, "ActivePool: Insufficient collateral shares");
        unchecked {
            // Safe per the check above
            cachedSystemCollShares -= _shares;
        }

        systemCollShares = cachedSystemCollShares;

        uint256 cachedFeeRecipientCollShares = feeRecipientCollShares + _shares;
        feeRecipientCollShares = cachedFeeRecipientCollShares;

        emit SystemCollSharesUpdated(cachedSystemCollShares);
        emit FeeRecipientClaimableCollSharesIncreased(cachedFeeRecipientCollShares, _shares);
    }

    /// @notice Helper function to transfer stETH shares to another address, ensuring to call hooks into other system pools if they are the recipient
    /// @param _account The address to transfer shares to
    /// @param _shares The amount of shares to transfer

    function _transferCollSharesWithContractHooks(address _account, uint256 _shares) internal {
        // NOTE: No need for safe transfer if the collateral asset is standard. Make sure this is the case!
        collateral.transferShares(_account, _shares);

        if (_account == collSurplusPoolAddress) {
            ICollSurplusPool(_account).increaseTotalSurplusCollShares(_shares);
        }
    }

    /// @notice Increases the tracked EBTC debt of the system by a specified amount
    /// @dev Managed by system contracts - requires that the caller is either BorrowerOperations or CdpManager
    /// @param _amount: The amount to increase the system EBTC debt by

    function increaseSystemDebt(uint256 _amount) external override {
        _requireCallerIsBOorCdpM();

        uint256 cachedSystemDebt = systemDebt + _amount;
        uint128 castedSystemDebt = EbtcMath.toUint128(cachedSystemDebt);

        if (!twapDisabled) {
            /// @audit If TWAP fails it should allow transaction to continue. Failure is preferrable to permanent DOS and can practically be mitigated by managing the redemption baseFee.
            try this.setValueAndUpdate(castedSystemDebt) {} catch {
                twapDisabled = true;
                emit TwapDisabled();
            }
        }

        /// @audit If above uint128 max, will have reverted in safeCast
        systemDebt = cachedSystemDebt;
        emit ActivePoolEBTCDebtUpdated(cachedSystemDebt);
    }

    /// @notice Decreases the tracked EBTC debt of the system by a specified amount
    /// @dev Managed by system contracts - requires that the caller is either BorrowerOperations or CdpManager
    /// @param _amount: The amount to decrease the system EBTC debt by

    function decreaseSystemDebt(uint256 _amount) external override {
        _requireCallerIsBOorCdpM();

        uint256 cachedSystemDebt = systemDebt - _amount;
        uint128 castedSystemDebt = EbtcMath.toUint128(cachedSystemDebt);

        if (!twapDisabled) {
            /// @audit If TWAP fails it should allow transaction to continue. Failure is preferrable to permanent DOS and can practically be mitigated by managing the redemption baseFee.
            try this.setValueAndUpdate(EbtcMath.toUint128(castedSystemDebt)) {} catch {
                twapDisabled = true;
                emit TwapDisabled();
            }
        }

        /// @audit If above uint128 max, will have reverted in safeCast
        systemDebt = cachedSystemDebt;
        emit ActivePoolEBTCDebtUpdated(cachedSystemDebt);
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

    function increaseSystemCollShares(uint256 _value) external override {
        _requireCallerIsBorrowerOperations();

        uint256 cachedSystemCollShares = systemCollShares + _value;
        systemCollShares = cachedSystemCollShares;
        emit SystemCollSharesUpdated(cachedSystemCollShares);
    }

    // === Flashloans === //

    /// @notice Borrow assets with a flash loan
    /// @dev The Collateral checks may cause reverts if you trigger a fee change big enough
    ///         consider calling `cdpManagerAddress.syncGlobalAccountingAndGracePeriod()`
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
        uint256 fee = flashFee(token, amount); // NOTE: Check for `token` is implicit in the requires above // also checks for paused
        require(amount <= maxFlashLoan(token), "ActivePool: Too much");

        uint256 amountWithFee = amount + fee;
        uint256 oldRate = collateral.getPooledEthByShares(DECIMAL_PRECISION);

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
        // NOTE: This means any balance > systemCollShares is stuck, this is also present in LUSD as is

        // NOTE: This check effectively prevents running 2 FL at the same time
        //  You technically could, but you'd be having to repay any amount below systemCollShares to get Fl2 to not revert
        require(
            collateral.balanceOf(address(this)) >= collateral.getPooledEthByShares(systemCollShares),
            "ActivePool: Must repay Balance"
        );
        require(
            collateral.sharesOf(address(this)) >= systemCollShares,
            "ActivePool: Must repay Share"
        );
        require(
            collateral.getPooledEthByShares(DECIMAL_PRECISION) == oldRate,
            "ActivePool: Should keep same collateral share rate"
        );

        emit FlashLoanSuccess(address(receiver), token, amount, fee);

        return true;
    }

    /// @notice Calculate the flash loan fee for a given token and amount loaned
    /// @param token The address of the token to calculate the fee for
    /// @param amount The amount of tokens to calculate the fee for
    /// @return The flashloan fee calcualted for given token and loan amount

    function flashFee(address token, uint256 amount) public view override returns (uint256) {
        require(token == address(collateral), "ActivePool: collateral Only");
        require(!flashLoansPaused, "ActivePool: Flash Loans Paused");

        return (amount * feeBps) / MAX_BPS;
    }

    /// @notice Get the maximum flash loan amount for a specific token
    /// @dev Exclusively used here for stETH collateral, equal to the current balance of the pool
    /// @param token The address of the token to get the maximum flash loan amount for
    /// @return The maximum available flashloan amount for the token
    function maxFlashLoan(address token) public view override returns (uint256) {
        if (token != address(collateral)) {
            return 0;
        }

        if (flashLoansPaused) {
            return 0;
        }

        return collateral.balanceOf(address(this));
    }

    // === Governed Functions === //

    /// @notice Claim outstanding shares for fee recipient, updating internal accounting and transferring the shares.
    /// @dev Call permissinos are managed via authority for flexibility, rather than gating call to just feeRecipient.
    /// @dev Is likely safe as an open permission though caution should be taken.
    /// @param _shares The amount of shares to claim to feeRecipient
    function claimFeeRecipientCollShares(uint256 _shares) external override requiresAuth {
        ICdpManagerData(cdpManagerAddress).syncGlobalAccountingAndGracePeriod(); // Calling this increases shares so do it first

        uint256 cachedFeeRecipientCollShares = feeRecipientCollShares;
        require(
            cachedFeeRecipientCollShares >= _shares,
            "ActivePool: Insufficient fee recipient coll"
        );

        unchecked {
            cachedFeeRecipientCollShares -= _shares;
        }

        feeRecipientCollShares = cachedFeeRecipientCollShares;
        emit FeeRecipientClaimableCollSharesDecreased(cachedFeeRecipientCollShares, _shares);

        collateral.transferShares(feeRecipientAddress, _shares);
    }

    /// @dev Function to move unintended dust that are not protected
    /// @notice moves given amount of given token (collateral is NOT allowed)
    /// @notice because recipient are fixed, this function is safe to be called by anyone
    /// @param token The token address to be swept
    /// @param amount The token amount to be swept

    function sweepToken(address token, uint256 amount) public nonReentrant requiresAuth {
        ICdpManagerData(cdpManagerAddress).syncGlobalAccountingAndGracePeriod(); // Accrue State First

        require(token != address(collateral), "ActivePool: Cannot Sweep Collateral");

        uint256 balance = IERC20(token).balanceOf(address(this));
        require(amount <= balance, "ActivePool: Attempt to sweep more than balance");

        address cachedFeeRecipientAddress = feeRecipientAddress; // Saves an SLOAD

        IERC20(token).safeTransfer(cachedFeeRecipientAddress, amount);

        emit SweepTokenSuccess(token, amount, cachedFeeRecipientAddress);
    }

    /// @notice Sets new Fee for FlashLoans
    /// @param _newFee The new flashloan fee to be set
    function setFeeBps(uint256 _newFee) external requiresAuth {
        ICdpManagerData(cdpManagerAddress).syncGlobalAccountingAndGracePeriod(); // Accrue State First

        require(_newFee <= MAX_FEE_BPS, "ERC3156FlashLender: _newFee should <= MAX_FEE_BPS");

        // set new flash fee
        uint256 _oldFee = feeBps;
        feeBps = uint16(_newFee);
        emit FlashFeeSet(msg.sender, _oldFee, _newFee);
    }

    /// @notice Should Flashloans be paused?
    /// @param _paused The flag (true or false) whether flashloan will be paused
    function setFlashLoansPaused(bool _paused) external requiresAuth {
        ICdpManagerData(cdpManagerAddress).syncGlobalAccountingAndGracePeriod(); // Accrue State First

        flashLoansPaused = _paused;
        emit FlashLoansPaused(msg.sender, _paused);
    }
}
