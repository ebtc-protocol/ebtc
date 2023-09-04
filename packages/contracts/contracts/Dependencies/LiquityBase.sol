// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./BaseMath.sol";
import "./LiquityMath.sol";
import "../Interfaces/IActivePool.sol";
import "../Interfaces/IPriceFeed.sol";
import "../Interfaces/ILiquityBase.sol";
import "../Dependencies/ICollateralToken.sol";

/*
 * Base contract for CdpManager, BorrowerOperations. Contains global system constants and
 * common functions.
 */
contract LiquityBase is BaseMath, ILiquityBase {
    // Collateral Ratio applied for Liquidation Incentive
    // i.e., liquidator repay $1 worth of debt to get back $1.03 worth of collateral
    uint256 public constant LICR = 1030000000000000000; // 103%

    // Minimum collateral ratio for individual cdps
    uint256 public constant MCR = 1100000000000000000; // 110%

    // Critical system collateral ratio. If the system's total collateral ratio (TCR) falls below the CCR, Recovery Mode is triggered.
    uint256 public constant CCR = 1250000000000000000; // 125%

    // Amount of stETH collateral to be locked in active pool on opening cdps
    uint256 public constant LIQUIDATOR_REWARD = 2e17;

    // Minimum amount of stETH collateral a CDP must have
    uint256 public constant MIN_NET_COLL = 2e18;

    uint256 public constant PERCENT_DIVISOR = 200; // dividing by 200 yields 0.5%

    uint256 public constant BORROWING_FEE_FLOOR = 0; // 0.5%

    uint256 public constant STAKING_REWARD_SPLIT = 5_000; // taking 50% cut from staking reward

    uint256 public constant MAX_REWARD_SPLIT = 10_000;

    IActivePool public immutable activePool;

    IPriceFeed public immutable override priceFeed;

    // the only collateral token allowed in CDP
    ICollateralToken public immutable collateral;

    constructor(address _activePoolAddress, address _priceFeedAddress, address _collateralAddress) {
        activePool = IActivePool(_activePoolAddress);
        priceFeed = IPriceFeed(_priceFeedAddress);
        collateral = ICollateralToken(_collateralAddress);
    }

    // --- Gas compensation functions ---

    function _getNetColl(uint256 _coll) internal pure returns (uint256) {
        return _coll - LIQUIDATOR_REWARD;
    }

    /**
        @notice Get the entire system collateral
        @notice Entire system collateral = collateral stored in ActivePool, using their internal accounting
        @dev Coll stored for liquidator rewards or coll in CollSurplusPool are not included
     */
    function getEntireSystemColl() public view returns (uint256 entireSystemColl) {
        return (activePool.getSystemCollShares());
    }

    /**
        @notice Get the entire system debt
        @notice Entire system collateral = collateral stored in ActivePool, using their internal accounting
     */
    function _getEntireSystemDebt() internal view returns (uint256 entireSystemDebt) {
        return (activePool.getSystemDebt());
    }

    function _getTCR(uint256 _price) internal view returns (uint256 TCR) {
        (TCR, , ) = _getTCRWithSystemDebtAndCollShares(_price);
    }

    function _getTCRWithSystemDebtAndCollShares(
        uint256 _price
    ) internal view returns (uint256 TCR, uint256 _coll, uint256 _debt) {
        uint256 entireSystemColl = getEntireSystemColl();
        uint256 entireSystemDebt = _getEntireSystemDebt();

        uint256 _underlyingCollateral = collateral.getPooledEthByShares(entireSystemColl);
        TCR = LiquityMath._computeCR(_underlyingCollateral, entireSystemDebt, _price);

        return (TCR, entireSystemColl, entireSystemDebt);
    }

    function _checkRecoveryMode(uint256 _price) internal view returns (bool) {
        return _checkRecoveryModeForTCR(_getTCR(_price));
    }

    function _checkRecoveryModeForTCR(uint256 _tcr) internal view returns (bool) {
        return _tcr < CCR;
    }

    function _requireUserAcceptsFee(
        uint256 _fee,
        uint256 _amount,
        uint256 _maxFeePercentage
    ) internal pure {
        uint256 feePercentage = (_fee * DECIMAL_PRECISION) / _amount;
        require(feePercentage <= _maxFeePercentage, "Fee exceeded provided maximum");
    }

    // Convert debt denominated in ETH to debt denominated in BTC given that _price is ETH/BTC
    // _debt is denominated in ETH
    // _price is ETH/BTC
    function _convertDebtDenominationToBtc(
        uint256 _debt,
        uint256 _price
    ) internal pure returns (uint256) {
        return (_debt * _price) / DECIMAL_PRECISION;
    }
}
