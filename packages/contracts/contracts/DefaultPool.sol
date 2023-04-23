// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./Interfaces/IDefaultPool.sol";
import "./Interfaces/IActivePool.sol";
import "./Dependencies/SafeMath.sol";
import "./Dependencies/Ownable.sol";
import "./Dependencies/CheckContract.sol";
import "./Dependencies/ICollateralToken.sol";

/*
 * The Default Pool holds the stETH collateral and EBTC debt (but not EBTC tokens) from liquidations that have been redistributed
 * to active cdps but not yet "applied", i.e. not yet recorded on a recipient active cdp's struct.
 *
 * When a cdp makes an operation that applies its pending stETH collateral and EBTC debt, its pending stETH collateral and EBTC debt is moved
 * from the Default Pool to the Active Pool.
 */

/**
 * @title Default Pool Contract
 * @dev The Default Pool holds the stETH collateral and EBTC debt (but not EBTC tokens) from liquidations that have been redistributed to active cdps but not yet "applied", i.e. not yet recorded on a recipient active cdp's struct.
 * When a cdp makes an operation that applies its pending stETH collateral and EBTC debt, its pending stETH collateral and EBTC debt is moved from the Default Pool to the Active Pool.
 */
contract DefaultPool is Ownable, CheckContract, IDefaultPool {
    using SafeMath for uint256;

    string public constant NAME = "DefaultPool";

    address public cdpManagerAddress;
    address public activePoolAddress;
    uint256 internal StEthColl; // deposited stETH collateral tracker
    uint256 internal EBTCDebt; // debt
    ICollateralToken public collateral;

    // --- Dependency setters ---

    /**
     * @notice Sets the addresses for the contract's dependencies.
     * @param _cdpManagerAddress The address of the cdp manager contract
     * @param _activePoolAddress The address of the active pool contract
     * @param _collTokenAddress The address of the collateral token contract
     */
    constructor(address _cdpManagerAddress, address _activePoolAddress, address _collTokenAddress) {
        cdpManagerAddress = _cdpManagerAddress;
        activePoolAddress = _activePoolAddress;
        collateral = ICollateralToken(_collTokenAddress);

        emit CdpManagerAddressChanged(_cdpManagerAddress);
        emit ActivePoolAddressChanged(_activePoolAddress);
        emit CollateralAddressChanged(_collTokenAddress);
    }

    // --- Getters for public variables. Required by IPool interface ---

    /*
     * Returns the StEthColl state variable.
     *
     * Not necessarily equal to the the contract's raw stETH collateral balance - ether can be forcibly sent to contracts.
     */

    /**
     * @notice Returns the value of the StEthColl state variable
     * @return The value of the StEthColl state variable
     */
    function getStEthColl() external view override returns (uint) {
        return StEthColl;
    }

    /**
     * @notice Returns the value of the EBTCDebt state variable
     * @return The value of the EBTCDebt state variable
     */
    function getEBTCDebt() external view override returns (uint) {
        return EBTCDebt;
    }

    // --- Pool functionality ---

    /**
     * @notice Sends ETH to the active pool contract
     * @param _amount The amount of ETH to send
     */
    function sendETHToActivePool(uint _amount) external override {
        _requireCallerIsCdpManager();
        address activePool = activePoolAddress; // cache to save an SLOAD
        require(StEthColl >= _amount, "!DefaultPoolBal");
        StEthColl = StEthColl - _amount;
        emit DefaultPoolETHBalanceUpdated(StEthColl);
        emit CollateralSent(activePool, _amount);

        // NOTE: No need for safe transfer if the collateral asset is standard. Make sure this is the case!
        collateral.transferShares(activePool, _amount);
        IActivePool(activePool).receiveColl(_amount);
    }

    /**
     * @notice Increases the value of the EBTCDebt state variable
     * @param _amount The amount to increase by
     */
    function increaseEBTCDebt(uint _amount) external override {
        _requireCallerIsCdpManager();
        EBTCDebt = EBTCDebt + _amount;
        emit DefaultPoolEBTCDebtUpdated(EBTCDebt);
    }

    /**
     * @notice Decreases the value of the EBTCDebt state variable
     * @param _amount The amount to decrease by
     */
    function decreaseEBTCDebt(uint _amount) external override {
        _requireCallerIsCdpManager();
        EBTCDebt = EBTCDebt - _amount;
        emit DefaultPoolEBTCDebtUpdated(EBTCDebt);
    }

    // --- 'require' functions ---

    /**
     * @notice Checks if the caller is the ActivePool contract
     */
    function _requireCallerIsActivePool() internal view {
        require(msg.sender == activePoolAddress, "DefaultPool: Caller is not the ActivePool");
    }

    /**
     * @notice Checks if the caller is the CdpManager contract
     */
    function _requireCallerIsCdpManager() internal view {
        require(msg.sender == cdpManagerAddress, "DefaultPool: Caller is not the CdpManager");
    }

    /**
     * @notice Receives collateral from the active pool contract
     * @param _value The amount of collateral to receive
     */
    function receiveColl(uint _value) external override {
        _requireCallerIsActivePool();
        StEthColl = StEthColl + _value;
        emit DefaultPoolETHBalanceUpdated(StEthColl);
    }
}
