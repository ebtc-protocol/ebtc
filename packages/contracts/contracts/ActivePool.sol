// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "./Interfaces/IActivePool.sol";
import "./Dependencies/SafeMath.sol";
import "./Dependencies/Ownable.sol";
import "./Dependencies/CheckContract.sol";
import "./Dependencies/console.sol";

import "./Dependencies/ERC3156FlashLender.sol";

/*
 * The Active Pool holds the ETH collateral and EBTC debt (but not EBTC tokens) for all active cdps.
 *
 * When a cdp is liquidated, it's ETH and EBTC debt are transferred from the Active Pool, to either the
 * Stability Pool, the Default Pool, or both, depending on the liquidation conditions.
 *
 */
contract ActivePool is Ownable, CheckContract, IActivePool, ERC3156FlashLender {
    using SafeMath for uint256;

    string public constant NAME = "ActivePool";

    address public borrowerOperationsAddress;
    address public cdpManagerAddress;
    address public stabilityPoolAddress;
    address public defaultPoolAddress;
    uint256 internal ETH; // deposited ether tracker
    uint256 internal EBTCDebt;

    // --- Events ---

    event BorrowerOperationsAddressChanged(address _newBorrowerOperationsAddress);
    event CdpManagerAddressChanged(address _newCdpManagerAddress);
    event ActivePoolEBTCDebtUpdated(uint _EBTCDebt);
    event ActivePoolETHBalanceUpdated(uint _ETH);

    // --- Contract setters ---

    function setAddresses(
        address _borrowerOperationsAddress,
        address _cdpManagerAddress,
        address _stabilityPoolAddress,
        address _defaultPoolAddress
    ) external onlyOwner {
        checkContract(_borrowerOperationsAddress);
        checkContract(_cdpManagerAddress);
        checkContract(_stabilityPoolAddress);
        checkContract(_defaultPoolAddress);

        borrowerOperationsAddress = _borrowerOperationsAddress;
        cdpManagerAddress = _cdpManagerAddress;
        stabilityPoolAddress = _stabilityPoolAddress;
        defaultPoolAddress = _defaultPoolAddress;

        emit BorrowerOperationsAddressChanged(_borrowerOperationsAddress);
        emit CdpManagerAddressChanged(_cdpManagerAddress);
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

    function getEBTCDebt() external view override returns (uint) {
        return EBTCDebt;
    }

    // --- Pool functionality ---

    function sendETH(address _account, uint _amount) external override {
        _requireCallerIsBOorCdpMorSP();
        ETH = ETH.sub(_amount);
        emit ActivePoolETHBalanceUpdated(ETH);
        emit EtherSent(_account, _amount);

        (bool success, ) = _account.call{value: _amount}("");
        require(success, "ActivePool: sending ETH failed");
    }

    function increaseEBTCDebt(uint _amount) external override {
        _requireCallerIsBOorCdpM();
        EBTCDebt = EBTCDebt.add(_amount);
        ActivePoolEBTCDebtUpdated(EBTCDebt);
    }

    function decreaseEBTCDebt(uint _amount) external override {
        _requireCallerIsBOorCdpMorSP();
        EBTCDebt = EBTCDebt.sub(_amount);
        ActivePoolEBTCDebtUpdated(EBTCDebt);
    }

    // --- 'require' functions ---

    function _requireCallerIsBorrowerOperationsOrDefaultPool() internal view {
        require(
            msg.sender == borrowerOperationsAddress || msg.sender == defaultPoolAddress,
            "ActivePool: Caller is neither BO nor Default Pool"
        );
    }

    function _requireCallerIsBOorCdpMorSP() internal view {
        require(
            msg.sender == borrowerOperationsAddress ||
                msg.sender == cdpManagerAddress ||
                msg.sender == stabilityPoolAddress,
            "ActivePool: Caller is neither BorrowerOperations nor CdpManager nor StabilityPool"
        );
    }

    function _requireCallerIsBOorCdpM() internal view {
        require(
            msg.sender == borrowerOperationsAddress || msg.sender == cdpManagerAddress,
            "ActivePool: Caller is neither BorrowerOperations nor CdpManager"
        );
    }

    // --- Fallback function ---

    receive() external payable {
        // FlashETH idea
        // We can just remove this check 
        // Then add a confirming FlashLoan Operation
        // Then receive via receive

        // NOTE: Changed to allow WETH
        if (msg.sender == address(WETH)) {
            // Notice: WETH at the top to save gas and allow ETH.transfer to work
            return;
        }

        // Previous code
        require(
            msg.sender == borrowerOperationsAddress ||
            msg.sender == defaultPoolAddress,
            "ActivePool: Caller is neither BO nor Default Pool"
        );

        ETH = ETH.add(msg.value);
        emit ActivePoolETHBalanceUpdated(ETH);
    }

    // === Flashloans === //

    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) external override returns (bool) {
        require(token == address(WETH), "WETH only");
        require(amount > 0, "0 Amount");
        uint256 fee = amount * FEE_AMT / MAX_BPS;

        uint256 requiredNewBalance = address(this).balance;

        uint256 amountWithFee = amount + fee;

        
        // Deposit Eth into WETH
        // Send WETH to receiver
        WETH.deposit{value: amount}();

        WETH.transfer(address(receiver), amount);

        // Callback
        require(
            receiver.onFlashLoan(msg.sender, token, amount, fee, data) == FLASH_SUCCESS_VALUE,
            "IERC3156: Callback failed"
        );

        // Transfer of WETH to Fee recipient
        WETH.transferFrom(address(receiver), address(this), amountWithFee);

        // SEnd weth to fee recipient
        WETH.transfer(FEE_RECIPIENT, fee);
        
        // Withdraw principal to this
        WETH.withdraw(amount);

        // Check new balance
        // NOTE: Invariant Check, technically breaks CEI but I think we must use it
        require(address(this).balance == requiredNewBalance, "Must send Exact Balance");

        return true;
    }

    function flashFee(
        address token,
        uint256 amount
    ) external view override returns (uint256) {
        require(token == address(WETH), "WETH only");

        return amount * FEE_AMT / MAX_BPS;
    }

    /// @dev Max flashloan, exclusively in ETH equals to the current balance
    function maxFlashLoan(
        address token
    ) external view override returns (uint256) {
        if(token != address(WETH)) {
            return 0;
        }

        return address(this).balance;
    }
}
