// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./Interfaces/IActivePool.sol";
import "./Interfaces/ICollSurplusPool.sol";
import "./Dependencies/ICollateralToken.sol";
import "./Dependencies/ERC3156FlashLender.sol";
import "./Dependencies/SafeERC20.sol";
import "./Dependencies/ReentrancyGuard.sol";
import "./Dependencies/AuthNoOwner.sol";

/*
 * The Active Pool holds the collateral and EBTC debt (but not EBTC tokens) for all active cdps.
 *
 * When a cdp is liquidated, it's collateral and EBTC debt are transferred from the Active Pool, to either the
 * Stability Pool, the Default Pool, or both, depending on the liquidation conditions.
 *
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

    /*
     * Returns the StEthColl state variable.
     *
     *Not necessarily equal to the the contract's raw StEthColl balance - ether can be forcibly sent to contracts.
     */
    function getStEthColl() external view override returns (uint) {
        return StEthColl;
    }

    function getEBTCDebt() external view override returns (uint) {
        return EBTCDebt;
    }

    function getFeeRecipientClaimableColl() external view override returns (uint) {
        return FeeRecipientColl;
    }

    // --- Pool functionality ---

    function sendStEthColl(address _account, uint _shares) public override {
        _requireCallerIsBOorCdpM();

        uint _StEthColl = StEthColl;
        require(_StEthColl >= _shares, "!ActivePoolBal");

        StEthColl = _StEthColl - _shares;

        emit ActivePoolCollBalanceUpdated(_StEthColl);
        emit CollateralSent(_account, _shares);

        _transferSharesWithContractHooks(_account, _shares);
    }

    /**
        @notice Send shares
        @notice Liquidator reward shares are not tracked via internal accoutning in the active pool and are assumed to be present in expected amount as part of the intended behavior of bops and cdpm
        @dev Liquidator reward shares are added when a cdp is opened, and removed when it is closed
        @dev closeCdp() or liqudations result in the actor (borrower or liquidator respectively) receiving the liquidator reward shares
        @dev Redemptions result in the shares being sent to the coll surplus pool for claiming by the 
        @dev Note that funds in the coll surplus pool, just like liquidator reward shares, are not tracked as part of the system CR or coll of a CDP. 
     */
    function sendStEthCollAndLiquidatorReward(
        address _account,
        uint _shares,
        uint _liquidatorRewardShares
    ) external override {
        _requireCallerIsBOorCdpM();

        uint _StEthColl = StEthColl;
        require(_StEthColl >= _shares, "ActivePool: Insufficient collateral shares");
        uint totalShares = _shares + _liquidatorRewardShares;

        StEthColl = _StEthColl - _shares;

        emit ActivePoolCollBalanceUpdated(_StEthColl);
        emit CollateralSent(_account, totalShares);

        _transferSharesWithContractHooks(_account, totalShares);
    }

    /**
        @notice Allocate stETH shares from the system to the fee recipient to claim at-will (pull model)
        @dev Only the current fee recipient address is able to claim the shares
        @dev If the fee recipient address is changed while outstanding claimable coll is available, only the new fee recipient will be able to claim the outstanding coll
     */
    function allocateFeeRecipientColl(uint _shares) external override {
        _requireCallerIsCdpManager();

        uint _StEthColl = StEthColl;
        uint _FeeRecipientColl = FeeRecipientColl;

        require(StEthColl >= _shares, "ActivePool: Insufficient collateral shares");

        StEthColl = _StEthColl - _shares;
        FeeRecipientColl = _FeeRecipientColl + _shares;

        emit ActivePoolCollBalanceUpdated(_StEthColl);
        emit ActivePoolFeeRecipientClaimableCollUpdated(_FeeRecipientColl);
    }

    /// @dev Transfer shares to another address, ensuring to update the internal accounting of other system pools if they are the recipient
    function _transferSharesWithContractHooks(address _account, uint _shares) internal {
        // NOTE: No need for safe transfer if the collateral asset is standard. Make sure this is the case!
        collateral.transferShares(_account, _shares);

        if (_account == collSurplusPoolAddress) {
            ICollSurplusPool(_account).receiveColl(_shares);
        }
    }

    function increaseEBTCDebt(uint _amount) external override {
        _requireCallerIsBOorCdpM();

        uint _EBTCDebt = EBTCDebt;

        EBTCDebt = _EBTCDebt + _amount;
        emit ActivePoolEBTCDebtUpdated(_EBTCDebt);
    }

    function decreaseEBTCDebt(uint _amount) external override {
        _requireCallerIsBOorCdpM();

        uint _EBTCDebt = EBTCDebt;

        EBTCDebt = _EBTCDebt - _amount;
        emit ActivePoolEBTCDebtUpdated(_EBTCDebt);
    }

    // --- 'require' functions ---

    function _requireCallerIsBorrowerOperations() internal view {
        require(
            msg.sender == borrowerOperationsAddress,
            "ActivePool: Caller is neither BO nor Default Pool"
        );
    }

    function _requireCallerIsBOorCdpM() internal view {
        require(
            msg.sender == borrowerOperationsAddress || msg.sender == cdpManagerAddress,
            "ActivePool: Caller is neither BorrowerOperations nor CdpManager"
        );
    }

    function _requireCallerIsCdpManager() internal view {
        require(msg.sender == cdpManagerAddress, "ActivePool: Caller is not CdpManager");
    }

    function receiveColl(uint _value) external override {
        _requireCallerIsBorrowerOperations();

        uint _StEthColl = StEthColl;
        StEthColl = _StEthColl + _value;
        emit ActivePoolCollBalanceUpdated(_StEthColl);
    }

    // === Flashloans === //

    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) external override returns (bool) {
        require(token == address(collateral), "ActivePool: collateral Only");
        require(amount > 0, "ActivePool: 0 Amount");
        require(amount <= maxFlashLoan(token), "ActivePool: Too much");

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
        // NOTE: Must be > as otherwise you can self-destruct donate to brick the functionality forever
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

        return true;
    }

    function flashFee(address token, uint256 amount) external view override returns (uint256) {
        require(token == address(collateral), "ActivePool: collateral Only");

        return (amount * feeBps) / MAX_BPS;
    }

    /// @dev Max flashloan, exclusively in collateral token equals to the current balance
    function maxFlashLoan(address token) public view override returns (uint256) {
        if (token != address(collateral)) {
            return 0;
        }

        return collateral.balanceOf(address(this));
    }

    // === Governed Functions === //

    /**
        @notice Claim outstanding shares for fee recipient, updating internal accounting and transferring the shares.
        @dev Call permissinos are managed via authority for flexibility, rather than gating call to just feeRecipient.
        @dev Is likely safe as an open permission though caution should be taken.
     */
    function claimFeeRecipientColl(uint _shares) external override requiresAuth {
        uint _FeeRecipientColl = FeeRecipientColl;
        require(_FeeRecipientColl >= _shares, "ActivePool: Insufficient fee recipient coll");

        FeeRecipientColl = _FeeRecipientColl - _shares;
        emit ActivePoolFeeRecipientClaimableCollUpdated(_FeeRecipientColl);

        collateral.transferShares(feeRecipientAddress, _shares);
    }

    /// @dev Function to move unintended dust that are not protected
    /// @notice moves given amount of given token (collateral is NOT allowed)
    /// @notice because recipient are fixed, this function is safe to be called by anyone
    function sweepToken(address token, uint amount) public nonReentrant requiresAuth {
        require(token != address(collateral), "ActivePool: Cannot Sweep Collateral");

        uint256 balance = IERC20(token).balanceOf(address(this));
        require(amount <= balance, "ActivePool: Attempt to sweep more than balance");

        IERC20(token).safeTransfer(feeRecipientAddress, amount);
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
