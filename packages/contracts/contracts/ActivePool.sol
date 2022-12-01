// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import './Interfaces/IActivePool.sol';
import "./Dependencies/SafeMath.sol";
import "./Dependencies/Ownable.sol";
import "./Dependencies/CheckContract.sol";
import "./Dependencies/console.sol";

import "./Dependencies/ERC3156FlashLender.sol";


/*
 * The Active Pool holds the ETH collateral and LUSD debt (but not LUSD tokens) for all active troves.
 *
 * When a trove is liquidated, it's ETH and LUSD debt are transferred from the Active Pool, to either the
 * Stability Pool, the Default Pool, or both, depending on the liquidation conditions.
 *
 */
contract ActivePool is Ownable, CheckContract, IActivePool, ERC3156FlashLender {
    using SafeMath for uint256;

    string constant public NAME = "ActivePool";

    address public borrowerOperationsAddress;
    address public troveManagerAddress;
    address public stabilityPoolAddress;
    address public defaultPoolAddress;
    uint256 internal ETH;  // deposited ether tracker
    uint256 internal LUSDDebt;

    // --- Events ---

    event BorrowerOperationsAddressChanged(address _newBorrowerOperationsAddress);
    event TroveManagerAddressChanged(address _newTroveManagerAddress);
    event ActivePoolLUSDDebtUpdated(uint _LUSDDebt);
    event ActivePoolETHBalanceUpdated(uint _ETH);

    // --- Contract setters ---

    function setAddresses(
        address _borrowerOperationsAddress,
        address _troveManagerAddress,
        address _stabilityPoolAddress,
        address _defaultPoolAddress
    )
        external
        onlyOwner
    {
        checkContract(_borrowerOperationsAddress);
        checkContract(_troveManagerAddress);
        checkContract(_stabilityPoolAddress);
        checkContract(_defaultPoolAddress);

        borrowerOperationsAddress = _borrowerOperationsAddress;
        troveManagerAddress = _troveManagerAddress;
        stabilityPoolAddress = _stabilityPoolAddress;
        defaultPoolAddress = _defaultPoolAddress;

        emit BorrowerOperationsAddressChanged(_borrowerOperationsAddress);
        emit TroveManagerAddressChanged(_troveManagerAddress);
        emit StabilityPoolAddressChanged(_stabilityPoolAddress);
        emit DefaultPoolAddressChanged(_defaultPoolAddress);

        _renounceOwnership();
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

    function getLUSDDebt() external view override returns (uint) {
        return LUSDDebt;
    }

    // --- Pool functionality ---

    function sendETH(address _account, uint _amount) external override {
        _requireCallerIsBOorTroveMorSP();
        ETH = ETH.sub(_amount);
        emit ActivePoolETHBalanceUpdated(ETH);
        emit EtherSent(_account, _amount);

        (bool success, ) = _account.call{ value: _amount }("");
        require(success, "ActivePool: sending ETH failed");
    }

    function increaseLUSDDebt(uint _amount) external override {
        _requireCallerIsBOorTroveM();
        LUSDDebt  = LUSDDebt.add(_amount);
        ActivePoolLUSDDebtUpdated(LUSDDebt);
    }

    function decreaseLUSDDebt(uint _amount) external override {
        _requireCallerIsBOorTroveMorSP();
        LUSDDebt = LUSDDebt.sub(_amount);
        ActivePoolLUSDDebtUpdated(LUSDDebt);
    }

    // --- 'require' functions ---

    function _requireCallerIsBorrowerOperationsOrDefaultPool() internal view {
        require(
            msg.sender == borrowerOperationsAddress ||
            msg.sender == defaultPoolAddress,
            "ActivePool: Caller is neither BO nor Default Pool");
    }

    function _requireCallerIsBOorTroveMorSP() internal view {
        require(
            msg.sender == borrowerOperationsAddress ||
            msg.sender == troveManagerAddress ||
            msg.sender == stabilityPoolAddress,
            "ActivePool: Caller is neither BorrowerOperations nor TroveManager nor StabilityPool");
    }

    function _requireCallerIsBOorTroveM() internal view {
        require(
            msg.sender == borrowerOperationsAddress ||
            msg.sender == troveManagerAddress,
            "ActivePool: Caller is neither BorrowerOperations nor TroveManager");
    }

    // --- Fallback function ---

    receive() external payable {
        // FlashETH idea
        // We can just remove this check 
        // Then add a confirming FlashLoan Operation
        // Then receive via receive
        _requireCallerIsBorrowerOperationsOrDefaultPool();
        ETH = ETH.add(msg.value);
        emit ActivePoolETHBalanceUpdated(ETH);
    }

    // === Flashloans === //

    // TODO: Prob we will just allow WETH to save the check above
    // OR: Rewrite receive

    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) external override returns (bool) {
        require(token == address(0), "ETH only");
        uint256 fee = amount * FEE_AMT / MAX_BPS;
        
        // TODO Send
        // Deposit Eth into WETH
        // Send WETH to receiver

        // Callback
        require(
            receiver.onFlashLoan(msg.sender, token, amount, fee, data) == keccak256("ERC3156FlashBorrower.onFlashLoan"),
            "IERC3156: Callback failed"
        );

        // TODO: Repay via:
        // Withdraw to this
        // Transfer of WETH to Fee recipient
    }

    function flashFee(
        address token,
        uint256 amount
    ) external view override returns (uint256) {
        require(token == address(0), "ETH only");

        return amount * FEE_AMT / MAX_BPS;
    }

    /// @dev Max flashloan, exclusively in ETH equals to the current balance
    function maxFlashLoan(
        address token
    ) external view override returns (uint256) {
        require(token == address(0), "ETH only");

        return address(this).balance;
    }
}
