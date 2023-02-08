// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "./BaseMath.sol";
import "./LiquityMath.sol";
import "./FixedPointMathLib.sol";
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
    uint public constant EBTC_GAS_COMPENSATION = 1e16;

    // Minimum amount of net EBTC debt denominated in ETH a cdp must have
    uint public constant MIN_NET_DEBT = 2e18;

    uint public constant PERCENT_DIVISOR = 200; // dividing by 200 yields 0.5%

    uint public constant BORROWING_FEE_FLOOR = (DECIMAL_PRECISION / 1000) * 5; // 0.5%

    uint public constant INTEREST_RATE_PER_SECOND = 627520278; // 2% per year

    IActivePool public activePool;

    IDefaultPool public defaultPool;

    IPriceFeed public override priceFeed;

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

    function _getEntireSystemDebt(
        uint _lastInterestRateUpdateTime
    ) internal view returns (uint entireSystemDebt) {
        uint activeDebt = activePool.getEBTCDebt();
        uint closedDebt = defaultPool.getEBTCDebt();

        uint timeElapsed = block.timestamp.sub(_lastInterestRateUpdateTime);
        if (timeElapsed > 0) {
            uint unitAmountAfterInterest = _calcUnitAmountAfterInterest(timeElapsed);

            activeDebt = activeDebt.mul(unitAmountAfterInterest).div(DECIMAL_PRECISION);
            closedDebt = closedDebt.mul(unitAmountAfterInterest).div(DECIMAL_PRECISION);
        }

        return activeDebt.add(closedDebt);
    }

    function _getTCR(
        uint _price,
        uint _lastInterestRateUpdateTime
    ) internal view returns (uint TCR) {
        (uint TCR, uint entireSystemColl, uint entireSystemDebt) = _getTCRWithTotalCollAndDebt(
            _price,
            _lastInterestRateUpdateTime
        );

        return TCR;
    }

    function _getTCRWithTotalCollAndDebt(
        uint _price,
        uint _lastInterestRateUpdateTime
    ) internal view returns (uint TCR, uint _coll, uint _debt) {
        uint entireSystemColl = getEntireSystemColl();
        uint entireSystemDebt = _getEntireSystemDebt(_lastInterestRateUpdateTime);

        TCR = LiquityMath._computeCR(entireSystemColl, entireSystemDebt, _price);

        return (TCR, entireSystemColl, entireSystemDebt);
    }

    function _checkRecoveryMode(
        uint _price,
        uint _lastInterestRateUpdateTime
    ) internal view returns (bool) {
        uint TCR = _getTCR(_price, _lastInterestRateUpdateTime);

        return TCR < CCR;
    }

    function _requireUserAcceptsFee(uint _fee, uint _amount, uint _maxFeePercentage) internal pure {
        uint feePercentage = _fee.mul(DECIMAL_PRECISION).div(_amount);
        require(feePercentage <= _maxFeePercentage, "Fee exceeded provided maximum");
    }

    function _calcUnitAmountAfterInterest(uint _time) internal pure virtual returns (uint) {
        // TODO: Fuzz to check overflows/underflows
        return
            FixedPointMathLib.fpow(
                DECIMAL_PRECISION.add(INTEREST_RATE_PER_SECOND),
                _time,
                DECIMAL_PRECISION
            );
    }
}
