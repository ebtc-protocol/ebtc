// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "./Interfaces/IActivePool.sol";
import "./Interfaces/IDefaultPool.sol";
import "./Interfaces/ICollSurplusPool.sol";
import "./Dependencies/SafeMath.sol";
import "./Dependencies/Ownable.sol";
import "./Dependencies/CheckContract.sol";
import "./Dependencies/console.sol";
import "./Dependencies/ICollateralToken.sol";

/*
 * The Active Pool holds the ETH collateral and EBTC debt (but not EBTC tokens) for all active cdps.
 *
 * When a cdp is liquidated, it's ETH and EBTC debt are transferred from the Active Pool, to either the
 * Stability Pool, the Default Pool, or both, depending on the liquidation conditions.
 *
 */
contract ActivePool is Ownable, CheckContract, IActivePool {
    using SafeMath for uint256;

    string public constant NAME = "ActivePool";

    address public borrowerOperationsAddress;
    address public cdpManagerAddress;
    address public defaultPoolAddress;
    address public collSurplusPoolAddress;
    uint256 internal ETH; // deposited ether tracker
    uint256 internal EBTCDebt;
    ICollateralToken public collateral;

    // --- Events ---

    event BorrowerOperationsAddressChanged(address _newBorrowerOperationsAddress);
    event CdpManagerAddressChanged(address _newCdpManagerAddress);
    event ActivePoolEBTCDebtUpdated(uint _EBTCDebt);
    event ActivePoolETHBalanceUpdated(uint _ETH);
    event CollateralAddressChanged(address _collTokenAddress);
    event CollSurplusPoolAddressChanged(address _collSurplusPoolAddress);

    // --- Contract setters ---

    function setAddresses(
        address _borrowerOperationsAddress,
        address _cdpManagerAddress,
        address _defaultPoolAddress,
        address _collTokenAddress,
        address _collSurplusAddress
    ) external onlyOwner {
        checkContract(_borrowerOperationsAddress);
        checkContract(_cdpManagerAddress);
        checkContract(_defaultPoolAddress);
        checkContract(_collTokenAddress);
        checkContract(_collSurplusAddress);

        borrowerOperationsAddress = _borrowerOperationsAddress;
        cdpManagerAddress = _cdpManagerAddress;
        defaultPoolAddress = _defaultPoolAddress;
        collateral = ICollateralToken(_collTokenAddress);
        collSurplusPoolAddress = _collSurplusAddress;

        emit BorrowerOperationsAddressChanged(_borrowerOperationsAddress);
        emit CdpManagerAddressChanged(_cdpManagerAddress);
        emit DefaultPoolAddressChanged(_defaultPoolAddress);
        emit CollateralAddressChanged(_collTokenAddress);
        emit CollSurplusPoolAddressChanged(_collSurplusAddress);

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
        _requireCallerIsBOorCdpM();
        require(ETH >= _amount, "!ActivePoolBal");
        ETH = ETH.sub(_amount);
        emit ActivePoolETHBalanceUpdated(ETH);
        emit EtherSent(_account, _amount);

        bool success = collateral.transfer(_account, _amount); //_account.call{value: _amount}("");
        require(success, "ActivePool: sending ETH failed");
        if (_account == defaultPoolAddress) {
            IDefaultPool(_account).receiveColl(_amount);
        } else if (_account == collSurplusPoolAddress) {
            ICollSurplusPool(_account).receiveColl(_amount);
        }
    }

    function increaseEBTCDebt(uint _amount) external override {
        _requireCallerIsBOorCdpM();
        EBTCDebt = EBTCDebt.add(_amount);
        ActivePoolEBTCDebtUpdated(EBTCDebt);
    }

    function decreaseEBTCDebt(uint _amount) external override {
        _requireCallerIsBOorCdpM();
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

    function _requireCallerIsBOorCdpM() internal view {
        require(
            msg.sender == borrowerOperationsAddress || msg.sender == cdpManagerAddress,
            "ActivePool: Caller is neither BorrowerOperations nor CdpManager"
        );
    }

    function receiveColl(uint _value) external override {
        _requireCallerIsBorrowerOperationsOrDefaultPool();
        ETH = ETH.add(_value);
        emit ActivePoolETHBalanceUpdated(ETH);
    }

    // --- Fallback function ---

    receive() external payable {
        _requireCallerIsBorrowerOperationsOrDefaultPool();
        revert("no more ETH");
    }
}
