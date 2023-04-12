// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "./Interfaces/IActivePool.sol";
import "./Interfaces/IDefaultPool.sol";
import "./Interfaces/ICollSurplusPool.sol";
import "./Interfaces/IFeeRecipient.sol";
import "./Dependencies/SafeMath.sol";
import "./Dependencies/Ownable.sol";
import "./Dependencies/CheckContract.sol";
import "./Dependencies/ICollateralToken.sol";

import "./Dependencies/ERC3156FlashLender.sol";

/*
 * The Active Pool holds the collateral and EBTC debt (but not EBTC tokens) for all active cdps.
 *
 * When a cdp is liquidated, it's collateral and EBTC debt are transferred from the Active Pool, to either the
 * Stability Pool, the Default Pool, or both, depending on the liquidation conditions.
 *
 */
contract ActivePool is Ownable, CheckContract, IActivePool, ERC3156FlashLender {
    using SafeMath for uint256;

    string public constant NAME = "ActivePool";

    address public borrowerOperationsAddress;
    address public cdpManagerAddress;
    address public defaultPoolAddress;
    address public collSurplusPoolAddress;
    address public feeRecipientAddress;
    uint256 internal ETH; // deposited ether tracker
    uint256 internal EBTCDebt;
    ICollateralToken public collateral;

    constructor() {}

    // --- Contract setters ---

    function setAddresses(
        address _borrowerOperationsAddress,
        address _cdpManagerAddress,
        address _defaultPoolAddress,
        address _collTokenAddress,
        address _collSurplusAddress,
        address _feeRecipientAddress
    ) external onlyOwner {
        checkContract(_borrowerOperationsAddress);
        checkContract(_cdpManagerAddress);
        checkContract(_defaultPoolAddress);
        checkContract(_collTokenAddress);
        checkContract(_collSurplusAddress);
        checkContract(_feeRecipientAddress);

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

        renounceOwnership();
    }

    // --- Getters for public variables. Required by IPool interface ---

    /*
     * Returns the ETH state variable.
     *
     *Not necessarily equal to the the contract's raw ETH balance - ether can be forcibly sent to contracts.
     */
    function getETH() external view override returns (uint) {
        return ETH;
    }

    function getEBTCDebt() external view override returns (uint) {
        return EBTCDebt;
    }

    // --- Pool functionality ---

    function sendETH(address _account, uint _amount) external override {
        _requireCallerIsBOorCdpM();
        require(ETH >= _amount, "!ActivePoolBal");
        ETH = ETH - _amount;
        emit ActivePoolETHBalanceUpdated(ETH);
        emit CollateralSent(_account, _amount);

        // NOTE: No need for safe transfer if the collateral asset is standard. Make sure this is the case!
        collateral.transferShares(_account, _amount);
        if (_account == defaultPoolAddress) {
            IDefaultPool(_account).receiveColl(_amount);
        } else if (_account == collSurplusPoolAddress) {
            ICollSurplusPool(_account).receiveColl(_amount);
        } else if (_account == feeRecipientAddress) {
            IFeeRecipient(feeRecipientAddress).receiveStEthFee(_amount);
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
        ETH = ETH + _value;
        emit ActivePoolETHBalanceUpdated(ETH);
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
        // NOTE: This means any balance > ETH is stuck, this is also present in LUSD as is

        // NOTE: This check effectively prevents running 2 FL at the same time
        //  You technically could, but you'd be having to repay any amount below ETH to get Fl2 to not revert
        require(
            collateral.balanceOf(address(this)) >= collateral.getPooledEthByShares(ETH),
            "ActivePool: Must repay Balance"
        );
        require(collateral.sharesOf(address(this)) >= ETH, "ActivePool: Must repay Share");
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
