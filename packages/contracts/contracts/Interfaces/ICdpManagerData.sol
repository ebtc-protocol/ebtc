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

    event FeeRecipientAddressChanged(address _feeRecipientAddress);
    event StakingRewardSplitSet(uint256 _stakingRewardSplit);
    event RedemptionFeeFloorSet(uint256 _redemptionFeeFloor);
    event MinuteDecayFactorSet(uint256 _minuteDecayFactor);
    event BetaSet(uint256 _beta);
    event RedemptionsPaused(bool _paused);

    event Liquidation(uint256 _liquidatedDebt, uint256 _liquidatedColl, uint256 _liqReward);
    event Redemption(
        uint256 _attemptedEBTCAmount,
        uint256 _actualEBTCAmount,
        uint256 _ETHSent,
        uint256 _ETHFee,
        address _redeemer
    );
    event CdpUpdated(
        bytes32 indexed _cdpId,
        address indexed _borrower,
        uint256 _oldDebt,
        uint256 _oldColl,
        uint256 _debt,
        uint256 _coll,
        uint256 _stake,
        CdpOperation _operation
    );
    event CdpLiquidated(
        bytes32 indexed _cdpId,
        address indexed _borrower,
        uint _debt,
        uint _coll,
        CdpOperation _operation,
        address _liquidator,
        uint _premiumToLiquidator
    );
    event CdpPartiallyLiquidated(
        bytes32 indexed _cdpId,
        address indexed _borrower,
        uint256 _debt,
        uint256 _coll,
        CdpOperation operation,
        address _liquidator,
        uint _premiumToLiquidator
    );
    event BaseRateUpdated(uint256 _baseRate);
    event LastRedemptionTimestampUpdated(uint256 _lastFeeOpTime);
    event TotalStakesUpdated(uint256 _newTotalStakes);
    event SystemSnapshotsUpdated(uint256 _totalStakesSnapshot, uint256 _totalCollateralSnapshot);
    event SystemDebtRedistributionIndexUpdated(uint256 _systemDebtRedistributionIndex);
    event CdpDebtRedistributionIndexUpdated(bytes32 _cdpId, uint256 _debtRedistributionIndex);
    event CdpArrayIndexUpdated(bytes32 _cdpId, uint256 _newIndex);
    event StEthIndexUpdated(uint256 _oldIndex, uint256 _newIndex, uint256 _updTimestamp);
    event CollateralFeePerUnitUpdated(uint256 _oldPerUnit, uint256 _newPerUnit, uint256 _feeTaken);
    event CdpFeeSplitApplied(
        bytes32 _cdpId,
        uint256 _oldPerUnitCdp,
        uint256 _newPerUnitCdp,
        uint256 _collReduced,
        uint256 collLeft
    );

    enum CdpOperation {
        openCdp,
        closeCdp,
        adjustCdp,
        syncAccounting,
        liquidateInNormalMode,
        liquidateInRecoveryMode,
        redeemCollateral,
        partiallyLiquidate
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
        uint256 liquidatorRewardShares;
        Status status;
        uint128 arrayIndex;
    }

    /*
     * --- Variable container structs for liquidations ---
     *
     * These structs are used to hold, return and assign variables inside the liquidation functions,
     * in order to avoid the error: "CompilerError: Stack too deep".
     **/

    struct LocalVar_CdpDebtColl {
        uint256 entireDebt;
        uint256 entireColl;
        uint256 pendingDebtReward;
    }

    struct LocalVar_InternalLiquidate {
        bytes32 _cdpId;
        uint256 _partialAmount; // used only for partial liquidation, default 0 means full liquidation
        uint256 _price;
        uint256 _ICR;
        bytes32 _upperPartialHint;
        bytes32 _lowerPartialHint;
        bool _recoveryModeAtStart;
        uint256 _TCR;
        uint256 totalColSurplus;
        uint256 totalColToSend;
        uint256 totalDebtToBurn;
        uint256 totalDebtToRedistribute;
        uint256 totalColReward;
        bool sequenceLiq;
    }

    struct LocalVar_RecoveryLiquidate {
        uint256 entireSystemDebt;
        uint256 entireSystemColl;
        uint256 totalDebtToBurn;
        uint256 totalColToSend;
        uint256 totalColSurplus;
        bytes32 _cdpId;
        uint256 _price;
        uint256 _ICR;
        uint256 totalDebtToRedistribute;
        uint256 totalColReward;
        bool sequenceLiq;
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

    struct LocalVariables_RedeemCollateralFromCdp {
        bytes32 _cdpId;
        uint256 _maxEBTCamount;
        uint256 _price;
        bytes32 _upperPartialRedemptionHint;
        bytes32 _lowerPartialRedemptionHint;
        uint256 _partialRedemptionHintNICR;
    }

    struct LiquidationValues {
        uint256 entireCdpDebt;
        uint256 debtToOffset;
        uint256 totalCollToSendToLiquidator;
        uint256 debtToRedistribute;
        uint256 collSurplus;
        uint256 collReward;
    }

    struct LiquidationTotals {
        uint256 totalDebtInSequence;
        uint256 totalDebtToOffset;
        uint256 totalCollToSendToLiquidator;
        uint256 totalDebtToRedistribute;
        uint256 totalCollSurplus;
        uint256 totalCollReward;
    }

    // --- Variable container structs for redemptions ---

    struct RedemptionTotals {
        uint256 remainingEBTC;
        uint256 totalEBTCToRedeem;
        uint256 totalETHDrawn;
        uint256 totalCollSharesSurplus;
        uint256 ETHFee;
        uint256 ETHToSendToRedeemer;
        uint256 decayedBaseRate;
        uint256 price;
        uint256 totalEBTCSupplyAtStart;
        uint256 totalCollSharesAtStart;
        uint256 tcrAtStart;
    }

    struct SingleRedemptionValues {
        uint256 eBtcToRedeem;
        uint256 stEthToRecieve;
        uint256 collSurplus;
        uint256 liquidatorRewardShares;
        bool cancelledPartial;
        bool fullRedemption;
    }

    function totalStakes() external view returns (uint256);

    function ebtcToken() external view returns (IEBTCToken);

    function systemStEthFeePerUnitIndex() external view returns (uint256);

    function systemStEthFeePerUnitIndexError() external view returns (uint256);

    function stEthIndex() external view returns (uint256);

    function calcFeeUponStakingReward(
        uint256 _newIndex,
        uint256 _prevIndex
    ) external view returns (uint256, uint256, uint256);

    function applyPendingGlobalState() external; // Accrues StEthFeeSplit without influencing Grace Period

    function syncGlobalAccountingAndGracePeriod() external; // Accrues StEthFeeSplit and influences Grace Period

    function getAccumulatedFeeSplitApplied(
        bytes32 _cdpId,
        uint256 _systemStEthFeePerUnitIndex
    ) external view returns (uint256, uint256);

    function getNominalICR(bytes32 _cdpId) external view returns (uint256);

    function getICR(bytes32 _cdpId, uint256 _price) external view returns (uint256);

    function getPendingRedistributedDebt(bytes32 _cdpId) external view returns (uint256);

    function hasPendingRedistributedDebt(bytes32 _cdpId) external view returns (bool);

    function getDebtAndCollShares(
        bytes32 _cdpId
    ) external view returns (uint256 debt, uint256 coll, uint256 pendingEBTCDebtReward);
}
