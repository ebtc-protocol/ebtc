// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./BaseMath.sol";
import "./EbtcMath.sol";
import "../Interfaces/IActivePool.sol";
import "../Interfaces/IPriceFeed.sol";
import "../Interfaces/IEbtcBase.sol";
import "../Dependencies/ICollateralToken.sol";

/*
 * Base contract for CdpManager, BorrowerOperations. Contains global system constants and
 * common functions.
 */
contract EbtcBase is BaseMath, IEbtcBase {
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
    uint256 public constant MIN_NET_STETH_BALANCE = 2e18;

    uint256 public constant PERCENT_DIVISOR = 200; // dividing by 200 yields 0.5%

    uint256 public constant BORROWING_FEE_FLOOR = 0; // 0.5%

    uint256 public constant STAKING_REWARD_SPLIT = 5_000; // taking 50% cut from staking reward

    uint256 public constant MAX_REWARD_SPLIT = 10_000;

    uint256 public constant MIN_CHANGE = 1000;

    IActivePool public immutable activePool;

    IPriceFeed public immutable override priceFeed;

    // the only collateral token allowed in CDP
    ICollateralToken public immutable collateral;

    /// @notice Initializes the contract with the provided addresses
    /// @param _activePoolAddress The address of the ActivePool contract
    /// @param _priceFeedAddress The address of the PriceFeed contract
    /// @param _collateralAddress The address of the CollateralToken contract
    constructor(address _activePoolAddress, address _priceFeedAddress, address _collateralAddress) {
        activePool = IActivePool(_activePoolAddress);
        priceFeed = IPriceFeed(_priceFeedAddress);
        collateral = ICollateralToken(_collateralAddress);
    }

    // --- Gas compensation functions ---

    function _calcNetStEthBalance(uint256 _stEthBalance) internal pure returns (uint256) {
        return _stEthBalance - LIQUIDATOR_REWARD;
    }

    /// @notice Get the entire system collateral
    /// @notice Entire system collateral = collateral allocated to system in ActivePool, using it's internal accounting
    /// @dev Collateral tokens stored in ActivePool for liquidator rewards, fees, or coll in CollSurplusPool, are not included
    function getSystemCollShares() public view returns (uint256 entireSystemColl) {
        return (activePool.getSystemCollShares());
    }

    /**
        @notice Get the entire system debt
        @notice Entire system collateral = collateral stored in ActivePool, using their internal accounting
     */
    function _getSystemDebt() internal view returns (uint256 entireSystemDebt) {
        return (activePool.getSystemDebt());
    }

    function _getCachedTCR(uint256 _price) internal view returns (uint256 TCR) {
        (TCR, , ) = _getTCRWithSystemDebtAndCollShares(_price);
    }

    function _getTCRWithSystemDebtAndCollShares(
        uint256 _price
    ) internal view returns (uint256 TCR, uint256 _coll, uint256 _debt) {
        uint256 systemCollShares = getSystemCollShares();
        uint256 systemDebt = _getSystemDebt();

        uint256 _systemStEthBalance = collateral.getPooledEthByShares(systemCollShares);
        TCR = EbtcMath._computeCR(_systemStEthBalance, systemDebt, _price);

        return (TCR, systemCollShares, systemDebt);
    }

    function _checkRecoveryMode(uint256 _price) internal view returns (bool) {
        return _checkRecoveryModeForTCR(_getCachedTCR(_price));
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

    /// @dev return true if given ICR is qualified for liquidation compared to configured threshold
    /// @dev this function ONLY checks numbers not check grace period switch for Recovery Mode
    function _checkICRAgainstLiqThreshold(uint256 _icr, uint _tcr) internal view returns (bool) {
        // Either undercollateralized
        // OR, it's RM AND they meet the requirement
        // Swapped Requirement && RM to save gas
        return
            _checkICRAgainstMCR(_icr) ||
            (_checkICRAgainstTCR(_icr, _tcr) && _checkRecoveryModeForTCR(_tcr));
    }

    /// @dev return true if given ICR is qualified for liquidation compared to MCR
    function _checkICRAgainstMCR(uint256 _icr) internal view returns (bool) {
        return _icr < MCR;
    }

    /// @dev return true if given ICR is qualified for liquidation compared to TCR
    /// @dev typically used in Recovery Mode
    function _checkICRAgainstTCR(uint256 _icr, uint _tcr) internal view returns (bool) {
        /// @audit is _icr <= _tcr more dangerous for overal system safety?
        /// @audit Should we use _icr < CCR to allow any risky CDP being liquidated?
        return _icr <= _tcr;
    }
}
