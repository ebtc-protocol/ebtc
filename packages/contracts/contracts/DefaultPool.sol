// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "./Interfaces/IDefaultPool.sol";
import "./Interfaces/IActivePool.sol";
import "./Dependencies/SafeMath.sol";
import "./Dependencies/Ownable.sol";
import "./Dependencies/CheckContract.sol";
import "./Dependencies/console.sol";
import "./Dependencies/ICollateralToken.sol";

/*
 * The Default Pool holds the ETH and EBTC debt (but not EBTC tokens) from liquidations that have been redistributed
 * to active cdps but not yet "applied", i.e. not yet recorded on a recipient active cdp's struct.
 *
 * When a cdp makes an operation that applies its pending ETH and EBTC debt, its pending ETH and EBTC debt is moved
 * from the Default Pool to the Active Pool.
 */
contract DefaultPool is Ownable, CheckContract, IDefaultPool {
    using SafeMath for uint256;

    string public constant NAME = "DefaultPool";

    address public cdpManagerAddress;
    address public activePoolAddress;
    uint256 internal ETH; // deposited ETH tracker
    uint256 internal EBTCDebt; // debt
    ICollateralToken public collateral;

    event CdpManagerAddressChanged(address _newCdpManagerAddress);
    event DefaultPoolEBTCDebtUpdated(uint _EBTCDebt);
    event DefaultPoolETHBalanceUpdated(uint _ETH);
    event CollateralAddressChanged(address _collTokenAddress);

    // --- Dependency setters ---

    function setAddresses(
        address _cdpManagerAddress,
        address _activePoolAddress,
        address _collTokenAddress
    ) external onlyOwner {
        checkContract(_cdpManagerAddress);
        checkContract(_activePoolAddress);
        checkContract(_collTokenAddress);

        cdpManagerAddress = _cdpManagerAddress;
        activePoolAddress = _activePoolAddress;
        collateral = ICollateralToken(_collTokenAddress);

        emit CdpManagerAddressChanged(_cdpManagerAddress);
        emit ActivePoolAddressChanged(_activePoolAddress);
        emit CollateralAddressChanged(_collTokenAddress);

        _renounceOwnership();
    }

    // --- Getters for public variables. Required by IPool interface ---

    /*
     * Returns the ETH state variable.
     *
     * Not necessarily equal to the the contract's raw ETH balance - ether can be forcibly sent to contracts.
     */
    function getETH() external view override returns (uint) {
        return ETH;
    }

    function getEBTCDebt() external view override returns (uint) {
        return EBTCDebt;
    }

    // --- Pool functionality ---

    function sendETHToActivePool(uint _amount) external override {
        _requireCallerIsCdpManager();
        address activePool = activePoolAddress; // cache to save an SLOAD
        require(ETH >= _amount, "!DefaultPoolBal");
        ETH = ETH.sub(_amount);
        emit DefaultPoolETHBalanceUpdated(ETH);
        emit CollateralSent(activePool, _amount);
		
        // NOTE: No need for safe transfer if the collateral asset is standard. Make sure this is the case!
        collateral.transfer(activePool, _amount);
        IActivePool(activePool).receiveColl(_amount);
    }

    function increaseEBTCDebt(uint _amount) external override {
        _requireCallerIsCdpManager();
        EBTCDebt = EBTCDebt.add(_amount);
        emit DefaultPoolEBTCDebtUpdated(EBTCDebt);
    }

    function decreaseEBTCDebt(uint _amount) external override {
        _requireCallerIsCdpManager();
        EBTCDebt = EBTCDebt.sub(_amount);
        emit DefaultPoolEBTCDebtUpdated(EBTCDebt);
    }

    // --- 'require' functions ---

    function _requireCallerIsActivePool() internal view {
        require(msg.sender == activePoolAddress, "DefaultPool: Caller is not the ActivePool");
    }

    function _requireCallerIsCdpManager() internal view {
        require(msg.sender == cdpManagerAddress, "DefaultPool: Caller is not the CdpManager");
    }

    function receiveColl(uint _value) external override {
        _requireCallerIsActivePool();
        ETH = ETH.add(_value);
        emit DefaultPoolETHBalanceUpdated(ETH);
    }
}
