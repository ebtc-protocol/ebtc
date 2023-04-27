// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./Interfaces/IActivePool.sol";
import "./Interfaces/IDefaultPool.sol";
import "./Interfaces/ICollSurplusPool.sol";
import "./Interfaces/IFeeRecipient.sol";
import "./Dependencies/ICollateralToken.sol";
import "./Dependencies/ERC3156FlashLender.sol";

/*
 * The Active Pool holds the collateral and EBTC debt (but not EBTC tokens) for all active cdps.
 *
 * When a cdp is liquidated, it's collateral and EBTC debt are transferred from the Active Pool, to either the
 * Stability Pool, the Default Pool, or both, depending on the liquidation conditions.
 *
 */
contract ActivePool is IActivePool, ERC3156FlashLender {
    string public constant NAME = "ActivePool";

    address public immutable borrowerOperationsAddress;
    address public immutable cdpManagerAddress;
    address public immutable defaultPoolAddress;
    address public immutable collSurplusPoolAddress;
    address public feeRecipientAddress;
    uint256 internal StEthColl; // deposited collateral tracker
    uint256 internal EBTCDebt;
    ICollateralToken public collateral;

    // --- Contract setters ---

    constructor(
        address _borrowerOperationsAddress,
        address _cdpManagerAddress,
        address _defaultPoolAddress,
        address _collTokenAddress,
        address _collSurplusAddress,
        address _feeRecipientAddress
    ) {
        borrowerOperationsAddress = _borrowerOperationsAddress;
        cdpManagerAddress = _cdpManagerAddress;
        defaultPoolAddress = _defaultPoolAddress;
        collateral = ICollateralToken(_collTokenAddress);
        collSurplusPoolAddress = _collSurplusAddress;
        feeRecipientAddress = _feeRecipientAddress;

        emit BorrowerOperationsAddressChanged(_borrowerOperationsAddress);
        emit CdpManagerAddressChanged(_cdpManagerAddress);
        emit DefaultPoolAddressChanged(_defaultPoolAddress);
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

    // --- Pool functionality ---

    function sendStEthColl(address _account, uint _shares) external override {
        _requireCallerIsBOorCdpM();
        require(StEthColl >= _shares, "!ActivePoolBal");
        StEthColl = StEthColl - _shares;
        emit ActivePoolETHBalanceUpdated(StEthColl);
        emit CollateralSent(_account, _shares);

        // NOTE: No need for safe transfer if the collateral asset is standard. Make sure this is the case!
        collateral.transferShares(_account, _shares);
        if (_account == defaultPoolAddress) {
            IDefaultPool(_account).receiveColl(_shares);
        } else if (_account == collSurplusPoolAddress) {
            ICollSurplusPool(_account).receiveColl(_shares);
        } else if (_account == feeRecipientAddress) {
            IFeeRecipient(feeRecipientAddress).receiveStEthFee(_shares);
        }
    }

    /**
        @notice Send shares
        @notice Liquidator reward shares are not tracked via internal accoutning in the active pool and are assumed to be present in expected amount as part of the intended behavior of bops and cdpm
        @dev Liquidator reward shares are added when a cdp is opened, and removed when it is closed
        @dev closeCdp() or liqudations result in the actor (borrower or liquidator respectively) receiving the liquidator reward shares
        @dev Redemptions result in the shares being sent to the coll surplus pool for claiming by the 
        @dev Note that funds in the coll surplus pool, just like liquidator reward shares, are not tracked as part of the system CR or coll of a CDP. 
     */
    function sendStEthCollAndLiquidatorReward(address _account, uint _shares, uint _liquidatorRewardShares) external override {
        _requireCallerIsBOorCdpM();
        require(StEthColl >= _shares, "!ActivePoolBal");
        StEthColl = StEthColl - _shares;
        emit ActivePoolETHBalanceUpdated(StEthColl);
        emit CollateralSent(_account, _shares);

        uint totalShares = _shares + _liquidatorRewardShares;

        // NOTE: No need for safe transfer if the collateral asset is standard. Make sure this is the case!
        collateral.transferShares(_account, totalShares);
        if (_account == defaultPoolAddress) {
            IDefaultPool(_account).receiveColl(totalShares);
        } else if (_account == collSurplusPoolAddress) {
            ICollSurplusPool(_account).receiveColl(totalShares);
        } else if (_account == feeRecipientAddress) {
            IFeeRecipient(feeRecipientAddress).receiveStEthFee(totalShares);
        }
    }
    

    function increaseEBTCDebt(uint _amount) external override {
        _requireCallerIsBOorCdpM();
        EBTCDebt = EBTCDebt + _amount;
        emit ActivePoolEBTCDebtUpdated(EBTCDebt);
    }

    function decreaseEBTCDebt(uint _amount) external override {
        _requireCallerIsBOorCdpM();
        EBTCDebt = EBTCDebt - _amount;
        emit ActivePoolEBTCDebtUpdated(EBTCDebt);
    }

    // --- 'require' functions ---

    function _requireCallerIsBorrowerOperationsOrDefaultPool() internal view {
        require(
            msg.sender == borrowerOperationsAddress || msg.sender == defaultPoolAddress,
            "ActivePool: Caller is neither BO nor Default Pool"
        );
    }

    function _requireCallerIsBOorCdpM() internal view {
        require(
            msg.sender == borrowerOperationsAddress || msg.sender == cdpManagerAddress,
            "ActivePool: Caller is neither BorrowerOperations nor CdpManager"
        );
    }

    function receiveColl(uint _value) external override {
        _requireCallerIsBorrowerOperationsOrDefaultPool();
        StEthColl = StEthColl + _value;
        emit ActivePoolETHBalanceUpdated(StEthColl);
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

        uint256 fee = (amount * FEE_AMT) / MAX_BPS;
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
        collateral.transfer(FEE_RECIPIENT, fee);

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

        return (amount * FEE_AMT) / MAX_BPS;
    }

    /// @dev Max flashloan, exclusively in collateral token equals to the current balance
    function maxFlashLoan(address token) public view override returns (uint256) {
        if (token != address(collateral)) {
            return 0;
        }

        return collateral.balanceOf(address(this));
    }
}
