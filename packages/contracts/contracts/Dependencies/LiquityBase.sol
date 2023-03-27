// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "./BaseMath.sol";
import "./LiquityMath.sol";
import "./FixedPointMathLib.sol";
import "../Interfaces/IActivePool.sol";
import "../Interfaces/IDefaultPool.sol";
import "../Interfaces/IPriceFeed.sol";
import "../Interfaces/ILiquityBase.sol";
import "../Dependencies/ICollateralToken.sol";

/*
 * Base contract for CdpManager, BorrowerOperations. Contains global system constants and
 * common functions.
 */
contract LiquityBase is BaseMath, ILiquityBase {
    using SafeMath for uint;

    uint public constant _100pct = 1000000000000000000; // 1e18 == 100%
    uint public constant _105pct = 1050000000000000000; // 1.05e18 == 105%
    uint public constant _5pct = 50000000000000000; // 5e16 == 5%

    // Collateral Ratio applied for Liquidation Incentive
    // i.e., liquidator repay $1 worth of debt to get back $1.05 worth of collateral
    uint public constant LICR = 1050000000000000000; // 105%

    // Minimum collateral ratio for individual cdps
    uint public constant MCR = 1100000000000000000; // 110%

    // Critical system collateral ratio. If the system's total collateral ratio (TCR) falls below the CCR, Recovery Mode is triggered.
    uint public constant CCR = 1500000000000000000; // 150%

    // Amount of EBTC to be locked in gas pool on opening cdps
    uint public constant EBTC_GAS_COMPENSATION = 1e16;

    uint public constant LIQUIDATOR_REWARD = 2e17;

    // Minimum amount of net EBTC debt denominated in ETH a cdp must have
    uint public constant MIN_NET_DEBT = 2e18;

    uint public constant PERCENT_DIVISOR = 200; // dividing by 200 yields 0.5%

    uint public constant BORROWING_FEE_FLOOR = 0; // 0.5%

    uint public constant STAKING_REWARD_SPLIT = 2_500; // taking 25% cut from staking reward

    uint public constant MAX_REWARD_SPLIT = 10_000;

    IActivePool public activePool;

    IDefaultPool public defaultPool;

    IPriceFeed public override priceFeed;

    // the only collateral token allowed in CDP
    ICollateralToken public collateral;

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

    function _getEntireSystemDebt() internal view returns (uint entireSystemDebt) {
        uint activeDebt = activePool.getEBTCDebt();
        uint closedDebt = defaultPool.getEBTCDebt();

        return activeDebt.add(closedDebt);
    }

    function _getTCR(uint256 _price) internal view returns (uint TCR) {
        (TCR, , ) = _getTCRWithTotalCollAndDebt(_price);
    }

    function _getTCRWithTotalCollAndDebt(
        uint256 _price
    ) internal view returns (uint TCR, uint _coll, uint _debt) {
        uint entireSystemColl = getEntireSystemColl();
        uint entireSystemDebt = _getEntireSystemDebt();

        uint _underlyingCollateral = collateral.getPooledEthByShares(entireSystemColl);
        TCR = LiquityMath._computeCR(_underlyingCollateral, entireSystemDebt, _price);

        return (TCR, entireSystemColl, entireSystemDebt);
    }

    function _checkRecoveryMode(uint256 _price) internal view returns (bool) {
        return _getTCR(_price) < CCR;
    }

    function _requireUserAcceptsFee(uint _fee, uint _amount, uint _maxFeePercentage) internal pure {
        uint feePercentage = _fee.mul(DECIMAL_PRECISION).div(_amount);
        require(feePercentage <= _maxFeePercentage, "Fee exceeded provided maximum");
    }

    // Convert ETH/BTC price to BTC/ETH price
    function _getPriceReciprocal(uint _price) internal view returns (uint) {
        return DECIMAL_PRECISION.mul(DECIMAL_PRECISION).div(_price);
    }

    // Convert debt denominated in BTC to debt denominated in ETH given that _price is ETH/BTC
    // _debt is denominated in BTC
    // _price is ETH/BTC
    function _convertDebtDenominationToEth(uint _debt, uint _price) internal view returns (uint) {
        uint priceReciprocal = _getPriceReciprocal(_price);
        return _debt.mul(priceReciprocal).div(DECIMAL_PRECISION);
    }

    // Convert debt denominated in ETH to debt denominated in BTC given that _price is ETH/BTC
    // _debt is denominated in ETH
    // _price is ETH/BTC
    function _convertDebtDenominationToBtc(uint _debt, uint _price) internal view returns (uint) {
        return _debt.mul(_price).div(DECIMAL_PRECISION);
    }
}
