// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./IEbtcBase.sol";
import "./ICdpManagerData.sol";

// Common interface for the Cdp Manager.
interface ICdpManager is IEbtcBase, ICdpManagerData {
    // --- Functions ---
    function liquidate(bytes32 _cdpId) external;

    function partiallyLiquidate(
        bytes32 _cdpId,
        uint256 _partialAmount,
        bytes32 _upperPartialHint,
        bytes32 _lowerPartialHint
    ) external;

    function batchLiquidateCdps(bytes32[] calldata _cdpArray) external;

    function redeemCollateral(
        uint256 _EBTCAmount,
        bytes32 _firstRedemptionHint,
        bytes32 _upperPartialRedemptionHint,
        bytes32 _lowerPartialRedemptionHint,
        uint256 _partialRedemptionHintNICR,
        uint256 _maxIterations,
        uint256 _maxFee
    ) external;

    function updateStakeAndTotalStakes(bytes32 _cdpId) external returns (uint256);

    function syncAccounting(bytes32 _cdpId) external;

    function closeCdp(bytes32 _cdpId, address _borrower, uint256 _debt, uint256 _coll) external;

    function getRedemptionRate() external view returns (uint256);

    function getRedemptionRateWithDecay() external view returns (uint256);

    function getRedemptionFeeWithDecay(uint256 _stETHToRedeem) external view returns (uint256);

    function getCdpStatus(bytes32 _cdpId) external view returns (uint256);

    function getCdpStake(bytes32 _cdpId) external view returns (uint256);

    function getCdpDebt(bytes32 _cdpId) external view returns (uint256);

    function getCdpCollShares(bytes32 _cdpId) external view returns (uint256);

    function getCdpLiquidatorRewardShares(bytes32 _cdpId) external view returns (uint);

    function initializeCdp(
        bytes32 _cdpId,
        uint256 _debt,
        uint256 _coll,
        uint256 _liquidatorRewardShares,
        address _borrower
    ) external;

    function updateCdp(
        bytes32 _cdpId,
        address _borrower,
        uint256 _coll,
        uint256 _debt,
        uint256 _newColl,
        uint256 _newDebt
    ) external;

    function getCachedTCR(uint256 _price) external view returns (uint256);

    function checkRecoveryMode(uint256 _price) external view returns (bool);
}
