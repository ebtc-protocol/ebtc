// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "./BaseMath.sol";
import "./LiquityMath.sol";
import "../Interfaces/IActivePool.sol";
import "../Interfaces/IDefaultPool.sol";
import "../Interfaces/IPriceFeed.sol";
import "../Interfaces/ILiquityBase.sol";

/*
 * Base contract for CdpManager, BorrowerOperations. Contains global system constants and
 * common functions.
 */
contract LiquityBase is BaseMath, ILiquityBase {
    using SafeMath for uint;

    uint public constant _100pct = 1000000000000000000; // 1e18 == 100%

    // Minimum collateral ratio for individual cdps
    uint public constant MCR = 1100000000000000000; // 110%

    // Critical system collateral ratio. If the system's total collateral ratio (TCR) falls below the CCR, Recovery Mode is triggered.
    uint public constant CCR = 1500000000000000000; // 150%

    // Amount of EBTC to be locked in gas pool on opening cdps
    uint public constant EBTC_GAS_COMPENSATION = 200e18;

    // Minimum amount of net EBTC debt in USD a cdp must have
    uint public constant MIN_NET_DEBT = 2000e18;
    // uint constant public MIN_NET_DEBT = 0;

    uint public constant PERCENT_DIVISOR = 200; // dividing by 200 yields 0.5%

    uint public constant BORROWING_FEE_FLOOR = (DECIMAL_PRECISION / 1000) * 5; // 0.5%

    IActivePool public activePool;

    IDefaultPool public defaultPool;

    IPriceFeed public override priceFeed;
    IPriceFeed public override btcPriceFeed;

    // --- Gas compensation functions ---

    // Returns the composite debt (drawn debt + gas compensation) of a cdp, for the purpose of ICR calculation
    function _getCompositeDebt(uint _debt) internal pure returns (uint) {
        return _debt.add(EBTC_GAS_COMPENSATION);
    }

    function _getNetDebt(uint _debt) internal pure returns (uint) {
        return _debt.sub(EBTC_GAS_COMPENSATION);
    }

    // Return the amount of ETH to be drawn from a cdp's collateral and sent as gas compensation.
    function _getCollGasCompensation(uint _entireColl) internal pure returns (uint) {
        return _entireColl / PERCENT_DIVISOR;
    }

    function getEntireSystemColl() public view returns (uint entireSystemColl) {
        uint activeColl = activePool.getETH();
        uint liquidatedColl = defaultPool.getETH();

        return activeColl.add(liquidatedColl);
    }

    function getEntireSystemDebt() public view returns (uint entireSystemDebt) {
        uint activeDebt = activePool.getEBTCDebt();
        uint closedDebt = defaultPool.getEBTCDebt();

        return activeDebt.add(closedDebt);
    }

    function _getTCR(uint _price) internal view returns (uint TCR) {
        uint entireSystemColl = getEntireSystemColl();
        uint entireSystemDebt = getEntireSystemDebt();

        TCR = LiquityMath._computeCR(entireSystemColl, entireSystemDebt, _price);

        return TCR;
    }

    function _checkRecoveryMode(uint _price) internal view returns (bool) {
        uint TCR = _getTCR(_price);

        return TCR < CCR;
    }

    function _getDebtInUsd(uint _debt, uint _btcPrice) internal pure returns (uint) {
        return _debt.mul(_btcPrice).div(DECIMAL_PRECISION);
    }

    function _requireUserAcceptsFee(uint _fee, uint _amount, uint _maxFeePercentage) internal pure {
        uint feePercentage = _fee.mul(DECIMAL_PRECISION).div(_amount);
        require(feePercentage <= _maxFeePercentage, "Fee exceeded provided maximum");
    }
}
