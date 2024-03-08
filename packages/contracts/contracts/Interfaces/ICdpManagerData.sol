// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./ICollSurplusPool.sol";
import "./IEBTCToken.sol";
import "./ISortedCdps.sol";
import "./IActivePool.sol";
import "./IRecoveryModeGracePeriod.sol";
import "../Dependencies/ICollateralTokenOracle.sol";

// Common interface for the Cdp Manager.
interface ICdpManagerData is IRecoveryModeGracePeriod {
    // --- Events ---

    event StakingRewardSplitSet(uint256 _stakingRewardSplit);
    event RedemptionFeeFloorSet(uint256 _redemptionFeeFloor);
    event MinuteDecayFactorSet(uint256 _minuteDecayFactor);
    event BetaSet(uint256 _beta);
    event RedemptionsPaused(bool _paused);

    event Liquidation(uint256 _liquidatedDebt, uint256 _liquidatedColl, uint256 _liqReward);
    event Redemption(
        uint256 _debtToRedeemExpected,
        uint256 _debtToRedeemActual,
        uint256 _collSharesSent,
        uint256 _feeCollShares,
        address indexed _redeemer
    );
    event CdpUpdated(
        bytes32 indexed _cdpId,
        address indexed _borrower,
        address indexed _executor,
        uint256 _oldDebt,
        uint256 _oldCollShares,
        uint256 _debt,
        uint256 _collShares,
        uint256 _stake,
        CdpOperation _operation
    );
    event CdpLiquidated(
        bytes32 indexed _cdpId,
        address indexed _borrower,
        uint _debt,
        uint _collShares,
        CdpOperation _operation,
        address indexed _liquidator,
        uint _premiumToLiquidator
    );
    event CdpPartiallyLiquidated(
        bytes32 indexed _cdpId,
        address indexed _borrower,
        uint256 _debt,
        uint256 _collShares,
        CdpOperation operation,
        address indexed _liquidator,
        uint _premiumToLiquidator
    );
    event BaseRateUpdated(uint256 _baseRate);
    event LastRedemptionTimestampUpdated(uint256 _lastFeeOpTime);
    event TotalStakesUpdated(uint256 _newTotalStakes);
    event SystemSnapshotsUpdated(uint256 _totalStakesSnapshot, uint256 _totalCollateralSnapshot);
    event SystemDebtRedistributionIndexUpdated(uint256 _systemDebtRedistributionIndex);
    event CdpDebtRedistributionIndexUpdated(bytes32 _cdpId, uint256 _cdpDebtRedistributionIndex);
    event CdpArrayIndexUpdated(bytes32 _cdpId, uint256 _newIndex);
    event StEthIndexUpdated(uint256 _oldIndex, uint256 _newIndex, uint256 _updTimestamp);
    event CollateralFeePerUnitUpdated(uint256 _oldPerUnit, uint256 _newPerUnit, uint256 _feeTaken);
    event CdpFeeSplitApplied(
        bytes32 _cdpId,
        uint256 _oldPerUnitCdp,
        uint256 _newPerUnitCdp,
        uint256 _collReduced,
        uint256 _collLeft
    );

    enum CdpOperation {
        openCdp,
        closeCdp,
        adjustCdp,
        syncAccounting,
        liquidateInNormalMode,
        liquidateInRecoveryMode,
        redeemCollateral,
        partiallyLiquidate,
        failedPartialRedemption
    }

    enum Status {
        nonExistent,
        active,
        closedByOwner,
        closedByLiquidation,
        closedByRedemption
    }

    // Store the necessary data for a cdp
    struct Cdp {
        uint256 debt;
        uint256 coll;
        uint256 stake;
        uint128 liquidatorRewardShares;
        Status status;
    }

    /*
     * --- Variable container structs for liquidations ---
     *
     * These structs are used to hold, return and assign variables inside the liquidation functions,
     * in order to avoid the error: "CompilerError: Stack too deep".
     **/

    struct CdpDebtAndCollShares {
        uint256 debt;
        uint256 collShares;
    }

    struct LiquidationLocals {
        bytes32 cdpId;
        uint256 partialAmount; // used only for partial liquidation, default 0 means full liquidation
        uint256 price;
        uint256 ICR;
        bytes32 upperPartialHint;
        bytes32 lowerPartialHint;
        bool recoveryModeAtStart;
        uint256 TCR;
        uint256 totalSurplusCollShares;
        uint256 totalCollSharesToSend;
        uint256 totalDebtToBurn;
        uint256 totalDebtToRedistribute;
        uint256 totalLiquidatorRewardCollShares;
    }

    struct LiquidationRecoveryModeLocals {
        uint256 entireSystemDebt;
        uint256 entireSystemColl;
        uint256 totalDebtToBurn;
        uint256 totalCollSharesToSend;
        uint256 totalSurplusCollShares;
        bytes32 cdpId;
        uint256 price;
        uint256 ICR;
        uint256 totalDebtToRedistribute;
        uint256 totalLiquidatorRewardCollShares;
    }

    struct LocalVariables_OuterLiquidationFunction {
        uint256 price;
        bool recoveryModeAtStart;
        uint256 liquidatedDebt;
        uint256 liquidatedColl;
    }

    struct LocalVariables_LiquidationSequence {
        uint256 i;
        uint256 ICR;
        bytes32 cdpId;
        bool backToNormalMode;
        uint256 entireSystemDebt;
        uint256 entireSystemColl;
        uint256 price;
        uint256 TCR;
    }

    struct SingleRedemptionInputs {
        bytes32 cdpId;
        uint256 maxEBTCamount;
        uint256 price;
        bytes32 upperPartialRedemptionHint;
        bytes32 lowerPartialRedemptionHint;
        uint256 partialRedemptionHintNICR;
    }

    struct LiquidationValues {
        uint256 entireCdpDebt;
        uint256 debtToBurn;
        uint256 totalCollToSendToLiquidator;
        uint256 debtToRedistribute;
        uint256 collSurplus;
        uint256 liquidatorCollSharesReward;
    }

    struct LiquidationTotals {
        uint256 totalDebtInSequence;
        uint256 totalDebtToBurn;
        uint256 totalCollToSendToLiquidator;
        uint256 totalDebtToRedistribute;
        uint256 totalCollSurplus;
        uint256 totalCollReward;
    }

    // --- Variable container structs for redemptions ---

    struct RedemptionTotals {
        uint256 remainingDebtToRedeem;
        uint256 debtToRedeem;
        uint256 collSharesDrawn;
        uint256 totalCollSharesSurplus;
        uint256 feeCollShares;
        uint256 collSharesToRedeemer;
        uint256 decayedBaseRate;
        uint256 price;
        uint256 systemDebtAtStart;
        uint256 twapSystemDebtAtStart;
        uint256 systemCollSharesAtStart;
        uint256 tcrAtStart;
    }

    struct SingleRedemptionValues {
        uint256 debtToRedeem;
        uint256 collSharesDrawn;
        uint256 collSurplus;
        uint256 liquidatorRewardShares;
        bool cancelledPartial;
        bool fullRedemption;
        uint256 newPartialNICR;
    }

    function getActiveCdpsCount() external view returns (uint256);

    function totalStakes() external view returns (uint256);

    function ebtcToken() external view returns (IEBTCToken);

    function systemStEthFeePerUnitIndex() external view returns (uint256);

    function systemStEthFeePerUnitIndexError() external view returns (uint256);

    function stEthIndex() external view returns (uint256);

    function calcFeeUponStakingReward(
        uint256 _newIndex,
        uint256 _prevIndex
    ) external view returns (uint256, uint256, uint256);

    function syncGlobalAccounting() external; // Accrues StEthFeeSplit without influencing Grace Period

    function syncGlobalAccountingAndGracePeriod() external; // Accrues StEthFeeSplit and influences Grace Period

    function getAccumulatedFeeSplitApplied(
        bytes32 _cdpId,
        uint256 _systemStEthFeePerUnitIndex
    ) external view returns (uint256, uint256);

    function getCachedNominalICR(bytes32 _cdpId) external view returns (uint256);

    function getCachedICR(bytes32 _cdpId, uint256 _price) external view returns (uint256);

    function getSyncedCdpDebt(bytes32 _cdpId) external view returns (uint256);

    function getSyncedCdpCollShares(bytes32 _cdpId) external view returns (uint256);

    function getSyncedICR(bytes32 _cdpId, uint256 _price) external view returns (uint256);

    function getSyncedTCR(uint256 _price) external view returns (uint256);

    function getSyncedSystemCollShares() external view returns (uint256);

    function getSyncedNominalICR(bytes32 _cdpId) external view returns (uint256);

    function getPendingRedistributedDebt(bytes32 _cdpId) external view returns (uint256);

    function hasPendingRedistributedDebt(bytes32 _cdpId) external view returns (bool);

    function getSyncedDebtAndCollShares(
        bytes32 _cdpId
    ) external view returns (uint256 debt, uint256 collShares);

    function canLiquidateRecoveryMode(uint256 icr, uint256 tcr) external view returns (bool);

    function totalCollateralSnapshot() external view returns (uint256);

    function totalStakesSnapshot() external view returns (uint256);
}
