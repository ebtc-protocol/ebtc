// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "./Interfaces/ICdpManager.sol";
import "./Interfaces/ICollSurplusPool.sol";
import "./Interfaces/IEBTCToken.sol";
import "./Interfaces/ISortedCdps.sol";
import "./Interfaces/IFeeRecipient.sol";
import "./Dependencies/LiquityBase.sol";
import "./Dependencies/Ownable.sol";
import "./Dependencies/CheckContract.sol";
import "./Dependencies/console.sol";
import "./Dependencies/ICollateralTokenOracle.sol";
import "./Dependencies/Authv06.sol";

contract CdpManager is LiquityBase, Ownable, CheckContract, ICdpManager, Auth {
    string public constant NAME = "CdpManager";

    // --- Connected contract declarations ---

    address public borrowerOperationsAddress;

    address gasPoolAddress;

    ICollSurplusPool collSurplusPool;

    IEBTCToken public override ebtcToken;

    IFeeRecipient public override feeRecipient;

    // A doubly linked list of Cdps, sorted by their sorted by their collateral ratios
    ISortedCdps public sortedCdps;

    // --- Data structures ---

    uint public constant SECONDS_IN_ONE_MINUTE = 60;
    /*
     * Half-life of 12h. 12h = 720 min
     * (1/2) = d^720 => d = (1/2)^(1/720)
     */
    uint public constant MINUTE_DECAY_FACTOR = 999037758833783000;
    uint public constant REDEMPTION_FEE_FLOOR = (DECIMAL_PRECISION / 1000) * 5; // 0.5%
    uint public constant MAX_BORROWING_FEE = (DECIMAL_PRECISION / 100) * 5; // 5%

    // -- Permissioned Function Signatures --
    bytes4 private constant SET_STAKING_REWARD_SPLIT_SIG =
        bytes4(keccak256(bytes("setStakingRewardSplit(uint256)")));

    // During bootsrap period redemptions are not allowed
    uint public constant BOOTSTRAP_PERIOD = 14 days;

    uint internal immutable deploymentStartTime;

    /*
     * BETA: 18 digit decimal. Parameter by which to divide the redeemed fraction,
     * in order to calc the new base rate from a redemption.
     * Corresponds to (1 / ALPHA) in the white paper.
     */
    uint public constant BETA = 2;

    uint public baseRate;

    uint public stakingRewardSplit;

    // The timestamp of the latest fee operation (redemption or new EBTC issuance)
    uint public lastFeeOperationTime;

    enum Status {
        nonExistent,
        active,
        closedByOwner,
        closedByLiquidation,
        closedByRedemption
    }

    // Store the necessary data for a cdp
    struct Cdp {
        uint debt;
        uint coll;
        uint stake;
        Status status;
        uint128 arrayIndex;
    }

    mapping(bytes32 => Cdp) public Cdps;

    uint public override totalStakes;

    // Snapshot of the value of totalStakes, taken immediately after the latest liquidation and split fee claim
    uint public totalStakesSnapshot;

    // Snapshot of the total collateral across the ActivePool and DefaultPool, immediately after the latest liquidation and split fee claim
    uint public totalCollateralSnapshot;

    /*
     * L_ETH and L_EBTCDebt track the sums of accumulated liquidation rewards per unit staked.
     * During its lifetime, each stake earns:
     *
     * An ETH gain of ( stake * [L_ETH - L_ETH(0)] )
     * A EBTCDebt increase  of ( stake * [L_EBTCDebt - L_EBTCDebt(0)] )
     *
     * Where L_ETH(0) and L_EBTCDebt(0) are snapshots of L_ETH and L_EBTCDebt
     * for the active Cdp taken at the instant the stake was made
     */
    uint public L_ETH;
    uint public L_EBTCDebt;

    /* Global Index for (Full Price Per Share) of underlying collateral token */
    uint256 public override stFPPSg;
    /* Global Fee accumulator (never decreasing) per stake unit in CDPManager, similar to L_ETH & L_EBTCdebt */
    uint256 public override stFeePerUnitg;
    /* Global Fee accumulator calculation error due to integer division, similar to redistribution calculation */
    uint256 public override stFeePerUnitgError;
    /* Individual CDP Fee accumulator tracker, used to calculate fee split distribution */
    mapping(bytes32 => uint256) public stFeePerUnitcdp;
    /* Update timestamp for global index */
    uint256 lastIndexTimestamp;
    /* Global Index update minimal interval, typically it is updated once per day  */
    uint256 public INDEX_UPD_INTERVAL;

    // Map active cdps to their RewardSnapshot
    mapping(bytes32 => RewardSnapshot) public rewardSnapshots;

    // Object containing the ETH and EBTC snapshots for a given active cdp
    struct RewardSnapshot {
        uint ETH;
        uint EBTCDebt;
    }

    // Array of all active cdp Ids - used to to compute an approximate hint off-chain, for the sorted list insertion
    bytes32[] public CdpIds;

    // Error trackers for the cdp redistribution calculation
    uint public lastETHError_Redistribution;
    uint public lastEBTCDebtError_Redistribution;

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
        uint pendingCollReward;
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
    }

    struct LocalVariables_OuterLiquidationFunction {
        uint price;
        bool recoveryModeAtStart;
        uint liquidatedDebt;
        uint liquidatedColl;
    }

    struct LocalVariables_LiquidationSequence {
        uint i;
        uint ICR;
        bytes32 cdpId;
        bool backToNormalMode;
        uint entireSystemDebt;
        uint entireSystemColl;
        uint price;
        uint TCR;
    }

    struct LiquidationValues {
        uint entireCdpDebt;
        uint debtToOffset;
        uint totalCollToSendToLiquidator;
        uint debtToRedistribute;
        uint collToRedistribute;
        uint collSurplus;
    }

    struct LiquidationTotals {
        uint totalDebtInSequence;
        uint totalDebtToOffset;
        uint totalCollToSendToLiquidator;
        uint totalDebtToRedistribute;
        uint totalCollToRedistribute;
        uint totalCollSurplus;
    }

    struct ContractsCache {
        IActivePool activePool;
        IDefaultPool defaultPool;
        IEBTCToken ebtcToken;
        IFeeRecipient feeRecipient;
        ISortedCdps sortedCdps;
        ICollSurplusPool collSurplusPool;
        address gasPoolAddress;
    }
    // --- Variable container structs for redemptions ---

    struct RedemptionTotals {
        uint remainingEBTC;
        uint totalEBTCToRedeem;
        uint totalETHDrawn;
        uint ETHFee;
        uint ETHToSendToRedeemer;
        uint decayedBaseRate;
        uint price;
        uint totalEBTCSupplyAtStart;
    }

    struct SingleRedemptionValues {
        uint EBTCLot;
        uint ETHLot;
        bool cancelledPartial;
    }

    // --- Events ---

    event BorrowerOperationsAddressChanged(address _newBorrowerOperationsAddress);
    event PriceFeedAddressChanged(address _newPriceFeedAddress);
    event EBTCTokenAddressChanged(address _newEBTCTokenAddress);
    event ActivePoolAddressChanged(address _activePoolAddress);
    event DefaultPoolAddressChanged(address _defaultPoolAddress);
    event GasPoolAddressChanged(address _gasPoolAddress);
    event CollSurplusPoolAddressChanged(address _collSurplusPoolAddress);
    event SortedCdpsAddressChanged(address _sortedCdpsAddress);
    event FeeRecipientAddressChanged(address _feeRecipientAddress);
    event CollateralAddressChanged(address _collTokenAddress);
    event StakingRewardSplitSet(uint256 _stakingRewardSplit);

    event Liquidation(uint _liquidatedDebt, uint _liquidatedColl);
    event Redemption(uint _attemptedEBTCAmount, uint _actualEBTCAmount, uint _ETHSent, uint _ETHFee);
    event CdpUpdated(
        bytes32 indexed _cdpId,
        address indexed _borrower,
        uint _debt,
        uint _coll,
        uint _stake,
        CdpManagerOperation _operation
    );
    event CdpLiquidated(
        bytes32 indexed _cdpId,
        address indexed _borrower,
        uint _debt,
        uint _coll,
        CdpManagerOperation _operation
    );
    event CdpPartiallyLiquidated(
        bytes32 indexed _cdpId,
        address indexed _borrower,
        uint _debt,
        uint _coll,
        CdpManagerOperation operation
    );
    event BaseRateUpdated(uint _baseRate);
    event LastFeeOpTimeUpdated(uint _lastFeeOpTime);
    event TotalStakesUpdated(uint _newTotalStakes);
    event SystemSnapshotsUpdated(uint _totalStakesSnapshot, uint _totalCollateralSnapshot);
    event LTermsUpdated(uint _L_ETH, uint _L_EBTCDebt);
    event CdpSnapshotsUpdated(uint _L_ETH, uint _L_EBTCDebt);
    event CdpIndexUpdated(bytes32 _cdpId, uint _newIndex);
    event CollateralGlobalIndexUpdated(uint _oldIndex, uint _newIndex, uint _updTimestamp);
    event CollateralIndexUpdateIntervalUpdated(uint _oldInterval, uint _newInterval);
    event CollateralFeePerUnitUpdated(
        uint _oldPerUnit,
        uint _newPerUnit,
        address _feeRecipient,
        uint _feeTaken
    );
    event CdpFeeSplitApplied(
        bytes32 _cdpId,
        uint _oldPerUnitCdp,
        uint _newPerUnitCdp,
        uint _collReduced,
        uint collLeft
    );

    enum CdpManagerOperation {
        applyPendingRewards,
        liquidateInNormalMode,
        liquidateInRecoveryMode,
        redeemCollateral,
        partiallyLiquidate
    }

    // --- Dependency setter ---

    constructor() public {
        // TODO: Move to setAddresses or _tickInterest?
        deploymentStartTime = block.timestamp;
    }

    function setAddresses(
        address _borrowerOperationsAddress,
        address _activePoolAddress,
        address _defaultPoolAddress,
        address _gasPoolAddress,
        address _collSurplusPoolAddress,
        address _priceFeedAddress,
        address _ebtcTokenAddress,
        address _sortedCdpsAddress,
        address _feeRecipientAddress,
        address _collTokenAddress,
        address _authorityAddress
    ) external override onlyOwner {
        checkContract(_borrowerOperationsAddress);
        checkContract(_activePoolAddress);
        checkContract(_defaultPoolAddress);
        checkContract(_gasPoolAddress);
        checkContract(_collSurplusPoolAddress);
        checkContract(_priceFeedAddress);
        checkContract(_ebtcTokenAddress);
        checkContract(_sortedCdpsAddress);
        checkContract(_feeRecipientAddress);
        checkContract(_collTokenAddress);
        checkContract(_authorityAddress);

        borrowerOperationsAddress = _borrowerOperationsAddress;
        activePool = IActivePool(_activePoolAddress);
        defaultPool = IDefaultPool(_defaultPoolAddress);
        gasPoolAddress = _gasPoolAddress;
        collSurplusPool = ICollSurplusPool(_collSurplusPoolAddress);
        priceFeed = IPriceFeed(_priceFeedAddress);
        ebtcToken = IEBTCToken(_ebtcTokenAddress);
        sortedCdps = ISortedCdps(_sortedCdpsAddress);
        feeRecipient = IFeeRecipient(_feeRecipientAddress);
        collateral = ICollateralToken(_collTokenAddress);

        emit BorrowerOperationsAddressChanged(_borrowerOperationsAddress);
        emit ActivePoolAddressChanged(_activePoolAddress);
        emit DefaultPoolAddressChanged(_defaultPoolAddress);
        emit GasPoolAddressChanged(_gasPoolAddress);
        emit CollSurplusPoolAddressChanged(_collSurplusPoolAddress);
        emit PriceFeedAddressChanged(_priceFeedAddress);
        emit EBTCTokenAddressChanged(_ebtcTokenAddress);
        emit SortedCdpsAddressChanged(_sortedCdpsAddress);
        emit FeeRecipientAddressChanged(_feeRecipientAddress);
        emit CollateralAddressChanged(_collTokenAddress);

        _initializeAuthority(_authorityAddress);

        stakingRewardSplit = 2500;
        // Emit initial value for analytics
        emit StakingRewardSplitSet(stakingRewardSplit);

        _syncIndex();
        syncUpdateIndexInterval();
        stFeePerUnitg = 1e18;

        _renounceOwnership();
    }

    // --- Getters ---

    function getCdpIdsCount() external view override returns (uint) {
        return CdpIds.length;
    }

    function getIdFromCdpIdsArray(uint _index) external view override returns (bytes32) {
        return CdpIds[_index];
    }

    // --- Cdp Liquidation functions ---
    // -----------------------------------------------------------------
    //    CDP ICR     |       Liquidation Behavior (TODO gas compensation?)
    //
    //  < MCR         |  debt could be fully repaid by liquidator
    //                |  and ALL collateral transferred to liquidator
    //                |  OR debt could be partially repaid by liquidator and
    //                |  liquidator could get collateral of (repaidDebt * max(LICR, min(ICR, MCR)) / price)
    //
    //  > MCR & < TCR |  only liquidatable in Recovery Mode (TCR < CCR)
    //                |  debt could be fully repaid by liquidator
    //                |  and up to (repaid debt * MCR) worth of collateral
    //                |  transferred to liquidator while the residue of collateral
    //                |  will be available in CollSurplusPool for owner to claim
    //                |  OR debt could be partially repaid by liquidator and
    //                |  liquidator could get collateral of (repaidDebt * max(LICR, min(ICR, MCR)) / price)
    // -----------------------------------------------------------------

    // Single CDP liquidation function (fully).
    function liquidate(bytes32 _cdpId) external override {
        _liquidateSingle(_cdpId, 0, _cdpId, _cdpId);
    }

    // Single CDP liquidation function (partially).
    function partiallyLiquidate(
        bytes32 _cdpId,
        uint256 _partialAmount,
        bytes32 _upperPartialHint,
        bytes32 _lowerPartialHint
    ) external override {
        _liquidateSingle(_cdpId, _partialAmount, _upperPartialHint, _lowerPartialHint);
    }

    // Single CDP liquidation function.
    function _liquidateSingle(
        bytes32 _cdpId,
        uint _partialAmount,
        bytes32 _upperPartialHint,
        bytes32 _lowerPartialHint
    ) internal {
        _requireCdpIsActive(_cdpId);

        _applyAccumulatedFeeSplit(_cdpId);

        uint256 _price = priceFeed.fetchPrice();

        // prepare local variables
        uint256 _ICR = getCurrentICR(_cdpId, _price);
        (uint _TCR, uint systemColl, uint systemDebt) = _getTCRWithTotalCollAndDebt(_price);

        require(_ICR < MCR || (_TCR < CCR && _ICR < _TCR), "!_ICR");

        bool _recoveryModeAtStart = _TCR < CCR ? true : false;
        LocalVar_InternalLiquidate memory _liqState = LocalVar_InternalLiquidate(
            _cdpId,
            _partialAmount,
            _price,
            _ICR,
            _upperPartialHint,
            _lowerPartialHint,
            (_recoveryModeAtStart),
            _TCR,
            0,
            0,
            0,
            0
        );

        LocalVar_RecoveryLiquidate memory _rs = LocalVar_RecoveryLiquidate(
            systemDebt,
            systemColl,
            0,
            0,
            0,
            _cdpId,
            _price,
            _ICR,
            0
        );

        ContractsCache memory _contractsCache = ContractsCache(
            activePool,
            defaultPool,
            ebtcToken,
            feeRecipient,
            sortedCdps,
            collSurplusPool,
            gasPoolAddress
        );
        _liquidateSingleCDP(_contractsCache, _liqState, _rs);
    }

    // liquidate given CDP by repaying debt in full or partially if its ICR is below MCR or TCR in recovery mode.
    // For partial liquidation, caller should use HintHelper smart contract to get correct hints for reinsertion into sorted CDP list
    function _liquidateSingleCDP(
        ContractsCache memory _contractsCache,
        LocalVar_InternalLiquidate memory _liqState,
        LocalVar_RecoveryLiquidate memory _recoveryState
    ) internal {
        uint256 totalDebtToBurn;
        uint256 totalColToSend;
        uint256 totalDebtToRedistribute;

        if (_liqState._partialAmount == 0) {
            (
                totalDebtToBurn,
                totalColToSend,
                totalDebtToRedistribute
            ) = _liquidateCDPByExternalLiquidator(_contractsCache, _liqState, _recoveryState);
        } else {
            (totalDebtToBurn, totalColToSend) = _liquidateCDPPartially(_contractsCache, _liqState);
            if (totalColToSend == 0 && totalDebtToBurn == 0) {
                // retry with fully liquidation
                (
                    totalDebtToBurn,
                    totalColToSend,
                    totalDebtToRedistribute
                ) = _liquidateCDPByExternalLiquidator(_contractsCache, _liqState, _recoveryState);
            }
        }

        _finalizeExternalLiquidation(
            _contractsCache,
            totalDebtToBurn,
            totalColToSend,
            totalDebtToRedistribute
        );
    }

    // liquidate (and close) the CDP from an external liquidator
    // this function would return the liquidated debt and collateral of the given CDP
    function _liquidateCDPByExternalLiquidator(
        ContractsCache memory _contractsCache,
        LocalVar_InternalLiquidate memory _liqState,
        LocalVar_RecoveryLiquidate memory _recoveryState
    ) private returns (uint256, uint256, uint256) {
        if (_liqState._recoveryModeAtStart) {
            LocalVar_RecoveryLiquidate memory _outputState = _liquidateSingleCDPInRecoveryMode(
                _contractsCache,
                _recoveryState
            );

            // housekeeping leftover collateral for liquidated CDP
            if (_outputState.totalColSurplus > 0) {
                _contractsCache.activePool.sendETH(
                    address(_contractsCache.collSurplusPool),
                    _outputState.totalColSurplus
                );
            }

            return (
                _outputState.totalDebtToBurn,
                _outputState.totalColToSend,  
                _outputState.totalDebtToRedistribute
            );
        } else {
            LocalVar_InternalLiquidate memory _outputState = _liquidateSingleCDPInNormalMode(
                _contractsCache,
                _liqState
            );
            return (
                _outputState.totalDebtToBurn,
                _outputState.totalColToSend,
                _outputState.totalDebtToRedistribute
            );
        }
    }

    function _liquidateSingleCDPInNormalMode(
        ContractsCache memory _contractsCache,
        LocalVar_InternalLiquidate memory _liqState
    ) private returns (LocalVar_InternalLiquidate memory) {
        // liquidate entire debt
        (
            uint256 _totalDebtToBurn,
            uint256 _totalColToSend
        ) = _liquidateCDPByExternalLiquidatorWithoutEvent(_contractsCache, _liqState._cdpId);
        uint256 _cappedColPortion;
        uint256 _collSurplus;
        uint256 _debtToRedistribute;
        address _borrower = _contractsCache.sortedCdps.getOwnerAddress(_liqState._cdpId);
        {
            (_cappedColPortion, _collSurplus, _debtToRedistribute) = _calculateSurplusAndCap(
                _liqState._ICR,
                _liqState._price,
                _totalDebtToBurn,
                _totalColToSend,
                true
            );
            if (_debtToRedistribute > 0) {
                _totalDebtToBurn = _totalDebtToBurn.sub(_debtToRedistribute);
            }
        }
        _liqState.totalDebtToBurn = _liqState.totalDebtToBurn.add(_totalDebtToBurn);
        _liqState.totalColToSend = _liqState.totalColToSend.add(_cappedColPortion);
        _liqState.totalDebtToRedistribute = _liqState.totalDebtToRedistribute.add(
            _debtToRedistribute
        );
        // Emit events
        emit CdpLiquidated(
            _liqState._cdpId,
            _borrower,
            _totalDebtToBurn,
            _cappedColPortion,
            CdpManagerOperation.liquidateInNormalMode
        );
        emit CdpUpdated(
            _liqState._cdpId,
            _borrower,
            0,
            0,
            0,
            CdpManagerOperation.liquidateInNormalMode
        );
        return _liqState;
    }

    function _liquidateSingleCDPInRecoveryMode(
        ContractsCache memory _contractsCache,
        LocalVar_RecoveryLiquidate memory _recoveryState
    ) private returns (LocalVar_RecoveryLiquidate memory) {
        // liquidate entire debt
        (
            uint256 _totalDebtToBurn,
            uint256 _totalColToSend
        ) = _liquidateCDPByExternalLiquidatorWithoutEvent(_contractsCache, _recoveryState._cdpId);

        // cap the liquidated collateral if required
        uint256 _cappedColPortion;
        uint256 _collSurplus;
        uint256 _debtToRedistribute;
        address _borrower = _contractsCache.sortedCdps.getOwnerAddress(_recoveryState._cdpId);

        // avoid stack too deep
        {
            (_cappedColPortion, _collSurplus, _debtToRedistribute) = _calculateSurplusAndCap(
                _recoveryState._ICR,
                _recoveryState._price,
                _totalDebtToBurn,
                _totalColToSend,
                true
            );
            if (_collSurplus > 0) {
                _contractsCache.collSurplusPool.accountSurplus(_borrower, _collSurplus);
                _recoveryState.totalColSurplus = _recoveryState.totalColSurplus.add(_collSurplus);
            }
            if (_debtToRedistribute > 0) {
                _totalDebtToBurn = _totalDebtToBurn.sub(_debtToRedistribute);
            }
        }
        _recoveryState.totalDebtToBurn = _recoveryState.totalDebtToBurn.add(_totalDebtToBurn);
        _recoveryState.totalColToSend = _recoveryState.totalColToSend.add(_cappedColPortion);
        _recoveryState.totalDebtToRedistribute = _recoveryState.totalDebtToRedistribute.add(
            _debtToRedistribute
        );

        // check if system back to normal mode
        _recoveryState.entireSystemDebt = _recoveryState.entireSystemDebt > _totalDebtToBurn
            ? _recoveryState.entireSystemDebt.sub(_totalDebtToBurn)
            : 0;
        _recoveryState.entireSystemColl = _recoveryState.entireSystemColl > _totalColToSend
            ? _recoveryState.entireSystemColl.sub(_totalColToSend)
            : 0;

        emit CdpLiquidated(
            _recoveryState._cdpId,
            _borrower,
            _totalDebtToBurn,
            _cappedColPortion,
            CdpManagerOperation.liquidateInRecoveryMode
        );
        emit CdpUpdated(
            _recoveryState._cdpId,
            _borrower,
            0,
            0,
            0,
            CdpManagerOperation.liquidateInRecoveryMode
        );

        return _recoveryState;
    }

    // liquidate (and close) the CDP from an external liquidator
    // this function would return the liquidated debt and collateral of the given CDP
    // without emmiting events
    function _liquidateCDPByExternalLiquidatorWithoutEvent(
        ContractsCache memory _contractsCache,
        bytes32 _cdpId
    ) private returns (uint256, uint256) {
        // calculate entire debt to repay
        (
            uint256 entireDebt,
            uint256 entireColl,
            uint256 pendingDebtReward,
            uint pendingCollReward
        ) = getEntireDebtAndColl(_cdpId);

        // move around distributed debt and collateral if any
        if (pendingDebtReward > 0 || pendingCollReward > 0) {
            _movePendingCdpRewardsToActivePool(
                _contractsCache.activePool,
                _contractsCache.defaultPool,
                pendingDebtReward,
                pendingCollReward
            );
        }

        // housekeeping after liquidation by closing the CDP
        _removeStake(_cdpId);
        _closeCdp(_cdpId, Status.closedByLiquidation);

        return (entireDebt, entireColl);
    }

    // Liquidate partially the CDP by an external liquidator
    // This function would return the liquidated debt and collateral of the given CDP
    function _liquidateCDPPartially(
        ContractsCache memory _contractsCache,
        LocalVar_InternalLiquidate memory _partialState
    ) private returns (uint256, uint256) {
        bytes32 _cdpId = _partialState._cdpId;
        uint _partialDebt = _partialState._partialAmount;

        // calculate entire debt to repay
        LocalVar_CdpDebtColl memory _debtAndColl = _getEntireDebtAndColl(_cdpId);
        _requirePartialLiqDebtSize(_partialDebt, _debtAndColl.entireDebt, _partialState._price);
        uint newDebt = _debtAndColl.entireDebt.sub(_partialDebt);

        // credit to https://arxiv.org/pdf/2212.07306.pdf for details
        (uint _partialColl, uint newColl, ) = _calculateSurplusAndCap(
            _partialState._ICR,
            _partialState._price,
            _partialDebt,
            _debtAndColl.entireColl,
            false
        );

        // return early if new collateral is zero
        if (newColl == 0) {
            return (0, 0);
        }

        // apply pending debt and collateral if any
        // and update CDP internal accounting for debt and collateral
        // if there is liquidation redistribution
        {
            if (_debtAndColl.pendingDebtReward > 0) {
                Cdps[_cdpId].debt = Cdps[_cdpId].debt.add(_debtAndColl.pendingDebtReward);
            }
            if (_debtAndColl.pendingCollReward > 0) {
                Cdps[_cdpId].coll = Cdps[_cdpId].coll.add(_debtAndColl.pendingCollReward);
            }
            if (_debtAndColl.pendingDebtReward > 0 || _debtAndColl.pendingCollReward > 0) {
                _movePendingCdpRewardsToActivePool(
                    _contractsCache.activePool,
                    _contractsCache.defaultPool,
                    _debtAndColl.pendingDebtReward,
                    _debtAndColl.pendingCollReward
                );
            }
        }

        // updating the CDP accounting for partial liquidation
        _partiallyReduceCdpDebt(_cdpId, _partialDebt, _partialColl);

        // reInsert into sorted CDP list after partial liquidation
        {
            _reInsertPartialLiquidation(
                _contractsCache,
                _partialState,
                LiquityMath._computeNominalCR(newColl, newDebt)
            );
            emit CdpPartiallyLiquidated(
                _cdpId,
                _contractsCache.sortedCdps.getOwnerAddress(_cdpId),
                _partialDebt,
                _partialColl,
                CdpManagerOperation.partiallyLiquidate
            );
        }
        return (_partialDebt, _partialColl);
    }

    function _partiallyReduceCdpDebt(bytes32 _cdpId, uint _partialDebt, uint _partialColl) internal {
        uint _coll = Cdps[_cdpId].coll;
        uint _debt = Cdps[_cdpId].debt;

        Cdps[_cdpId].coll = _coll.sub(_partialColl);
        Cdps[_cdpId].debt = _debt.sub(_partialDebt);
        _updateStakeAndTotalStakes(_cdpId);

        _updateCdpRewardSnapshots(_cdpId);
    }

    // Re-Insertion into SortedCdp list after partial liquidation
    function _reInsertPartialLiquidation(
        ContractsCache memory _contractsCache,
        LocalVar_InternalLiquidate memory _partialState,
        uint _newNICR
    ) internal {
        bytes32 _cdpId = _partialState._cdpId;

        // ensure new ICR does NOT decrease due to partial liquidation
        // if original ICR is above LICR
        if (_partialState._ICR > LICR) {
            require(
                getCurrentICR(_cdpId, _partialState._price) >= _partialState._ICR,
                "!_newICR>=_ICR"
            );
        }

        // reInsert into sorted CDP list
        _contractsCache.sortedCdps.reInsert(
            _cdpId,
            _newNICR,
            _partialState._upperPartialHint,
            _partialState._lowerPartialHint
        );
        emit CdpUpdated(
            _cdpId,
            _contractsCache.sortedCdps.getOwnerAddress(_cdpId),
            Cdps[_cdpId].debt,
            Cdps[_cdpId].coll,
            Cdps[_cdpId].stake,
            CdpManagerOperation.partiallyLiquidate
        );
    }

    function _finalizeExternalLiquidation(
        ContractsCache memory _contractsCache,
        uint256 totalDebtToBurn,
        uint256 totalColToSend,
        uint256 totalDebtToRedistribute
    ) internal {
        // update the staking and collateral snapshots
        _updateSystemSnapshots_excludeCollRemainder(
            _contractsCache.activePool,
            _contractsCache.defaultPool,
            totalColToSend
        );

        emit Liquidation(totalDebtToBurn, totalColToSend);

        // redistribute debt if any
        if (totalDebtToRedistribute > 0) {
            _redistributeDebtAndColl(
                _contractsCache.activePool,
                _contractsCache.defaultPool,
                totalDebtToRedistribute,
                0
            );
        }

        // burn the debt from liquidator
        _contractsCache.ebtcToken.burn(msg.sender, totalDebtToBurn);

        // offset debt from Active Pool
        _contractsCache.activePool.decreaseEBTCDebt(totalDebtToBurn);

        // CEI: ensure sending back collateral to liquidator is last thing to do
        _contractsCache.activePool.sendETH(msg.sender, totalColToSend);
    }

    // Function that calculates the amount of collateral to send to liquidator (plus incentive) and the amount of collateral surplus
    function _calculateSurplusAndCap(
        uint _ICR,
        uint _price,
        uint _totalDebtToBurn,
        uint _totalColToSend,
        bool _fullLiquidation
    ) private view returns (uint cappedColPortion, uint collSurplus, uint debtToRedistribute) {
        // Calculate liquidation incentive for liquidator:
        // If ICR is less than 103%: give away 103% worth of collateral to liquidator, i.e., repaidDebt.mul(103%).div(price)
        // If ICR is more than 103%: give away min(ICR, 110%) worth of collateral to liquidator, i.e., repaidDebt.mul(min(ICR, 110%)).div(price)
        // Add LIQUIDATOR_REWARD in case not giving entire collateral away
        uint _incentiveColl;
        if (_ICR > LICR) {
            _incentiveColl = _totalDebtToBurn.mul(_ICR > MCR ? MCR : _ICR).div(_price);
        } else {
            if (_fullLiquidation) {
                // for full liquidation, there would be some bad debt to redistribute
                _incentiveColl = collateral.getPooledEthByShares(_totalColToSend);
                uint _debtToRepay = _incentiveColl.mul(_price).div(LICR);
                debtToRedistribute = _debtToRepay < _totalDebtToBurn
                    ? _totalDebtToBurn.sub(_debtToRepay)
                    : 0;
            } else {
                // for partial liquidation, new ICR would deteriorate
                // since we give more incentive (103%) than current _ICR allowed
                _incentiveColl = _totalDebtToBurn.mul(LICR).div(_price);
            }
        }
        _incentiveColl = _incentiveColl.add(_fullLiquidation ? LIQUIDATOR_REWARD : 0);
        cappedColPortion = collateral.getSharesByPooledEth(_incentiveColl);
        cappedColPortion = cappedColPortion < _totalColToSend ? cappedColPortion : _totalColToSend;
        collSurplus = (cappedColPortion == _totalColToSend)
            ? 0
            : _totalColToSend.sub(cappedColPortion);
    }

    // --- Batch/Sequence liquidation functions ---

    /*
     * Liquidate a sequence of cdps. Closes a maximum number of n cdps with their CR < MCR or CR < TCR in reocvery mode,
     * starting from the one with the lowest collateral ratio in the system, and moving upwards
     */
    function liquidateCdps(uint _n) external override {
        require(_n > 0, "CdpManager: can't liquidate zero CDP in sequence");

        ContractsCache memory contractsCache = ContractsCache(
            activePool,
            defaultPool,
            ebtcToken,
            lqtyStaking,
            sortedCdps,
            collSurplusPool,
            gasPoolAddress
        );

        LocalVariables_OuterLiquidationFunction memory vars;

        LiquidationTotals memory totals;

        // taking fee to avoid accounted for the calculation of the TCR
        claimStakingSplitFee();

        vars.price = priceFeed.fetchPrice();
        (uint _TCR, uint systemColl, uint systemDebt) = _getTCRWithTotalCollAndDebt(
            vars.price,
            lastInterestRateUpdateTime
        );
        vars.recoveryModeAtStart = _TCR < CCR ? true : false;

        // Perform the appropriate liquidation sequence - tally the values, and obtain their totals
        if (vars.recoveryModeAtStart) {
            totals = _getTotalsFromLiquidateCdpsSequence_RecoveryMode(
                contractsCache,
                vars.price,
                systemColl,
                systemDebt,
                _n
            );
        } else {
            // if !vars.recoveryModeAtStart
            totals = _getTotalsFromLiquidateCdpsSequence_NormalMode(
                contractsCache,
                vars.price,
                _TCR,
                _n
            );
        }

        require(totals.totalDebtInSequence > 0, "CdpManager: nothing to liquidate");

        // housekeeping leftover collateral for liquidated CDPs
        if (totals.totalCollSurplus > 0) {
            contractsCache.activePool.sendETH(
                address(contractsCache.collSurplusPool),
                totals.totalCollSurplus
            );
        }

        _finalizeExternalLiquidation(
            contractsCache,
            totals.totalDebtToOffset,
            totals.totalCollToSendToLiquidator,
            totals.totalDebtToRedistribute
        );
    }

    /*
     * This function is used when the liquidateCdps sequence starts during Recovery Mode. However, it
     * handle the case where the system *leaves* Recovery Mode, part way through the liquidation sequence
     */
    function _getTotalsFromLiquidateCdpsSequence_RecoveryMode(
        ContractsCache memory _contractsCache,
        uint _price,
        uint _systemColl,
        uint _systemDebt,
        uint _n
    ) internal returns (LiquidationTotals memory totals) {
        LocalVariables_LiquidationSequence memory vars;
        LiquidationValues memory singleLiquidation;

        vars.backToNormalMode = false;
        vars.entireSystemDebt = _systemDebt;
        vars.entireSystemColl = _systemColl;

        vars.cdpId = _contractsCache.sortedCdps.getLast();
        bytes32 firstId = _contractsCache.sortedCdps.getFirst();
        uint _TCR = _computeTCRWithGivenSystemValues(
            vars.entireSystemColl,
            vars.entireSystemDebt,
            _price
        );
        for (vars.i = 0; vars.i < _n && vars.cdpId != firstId; ++vars.i) {
            // we need to cache it, because current CDP is likely going to be deleted
            bytes32 nextCdp = _contractsCache.sortedCdps.getPrev(vars.cdpId);

            vars.ICR = getCurrentICR(vars.cdpId, _price);

            if (!vars.backToNormalMode && (vars.ICR < MCR || vars.ICR < _TCR)) {
                vars.price = _price;
                _applyAccumulatedFeeSplit(vars.cdpId);
                _getLiquidationValuesRecoveryMode(
                    _contractsCache,
                    _price,
                    vars.entireSystemDebt,
                    vars.entireSystemColl,
                    vars,
                    singleLiquidation
                );

                // Update aggregate trackers
                vars.entireSystemDebt = vars.entireSystemDebt.sub(singleLiquidation.debtToOffset);
                vars.entireSystemColl = vars
                    .entireSystemColl
                    .sub(singleLiquidation.totalCollToSendToLiquidator)
                    .sub(singleLiquidation.collSurplus);

                // Add liquidation values to their respective running totals
                totals = _addLiquidationValuesToTotals(totals, singleLiquidation);

                _TCR = _computeTCRWithGivenSystemValues(
                    vars.entireSystemColl,
                    vars.entireSystemDebt,
                    _price
                );
                vars.backToNormalMode = _TCR < CCR ? false : true;
            } else if (vars.backToNormalMode && vars.ICR < MCR) {
                _applyAccumulatedFeeSplit(vars.cdpId);
                _getLiquidationValuesNormalMode(
                    _contractsCache,
                    _price,
                    _TCR,
                    vars,
                    singleLiquidation
                );

                // Add liquidation values to their respective running totals
                totals = _addLiquidationValuesToTotals(totals, singleLiquidation);
            } else break; // break if the loop reaches a Cdp with ICR >= MCR

            vars.cdpId = nextCdp;
        }
    }

    function _getTotalsFromLiquidateCdpsSequence_NormalMode(
        ContractsCache memory _contractsCache,
        uint _price,
        uint _TCR,
        uint _n
    ) internal returns (LiquidationTotals memory totals) {
        LocalVariables_LiquidationSequence memory vars;
        LiquidationValues memory singleLiquidation;
        ISortedCdps sortedCdpsCached = _contractsCache.sortedCdps;

        for (vars.i = 0; vars.i < _n; ++vars.i) {
            vars.cdpId = sortedCdpsCached.getLast();
            vars.ICR = getCurrentICR(vars.cdpId, _price);

            if (vars.ICR < MCR) {
                _applyAccumulatedFeeSplit(vars.cdpId);
                _getLiquidationValuesNormalMode(
                    _contractsCache,
                    _price,
                    _TCR,
                    vars,
                    singleLiquidation
                );

                // Add liquidation values to their respective running totals
                totals = _addLiquidationValuesToTotals(totals, singleLiquidation);
            } else break; // break if the loop reaches a Cdp with ICR >= MCR
        }
    }

    function _getLiquidationValuesNormalMode(
        ContractsCache memory _contractsCache,
        uint _price,
        uint _TCR,
        LocalVariables_LiquidationSequence memory vars,
        LiquidationValues memory singleLiquidation
    ) internal {
        LocalVar_InternalLiquidate memory _liqState = LocalVar_InternalLiquidate(
            vars.cdpId,
            0,
            _price,
            vars.ICR,
            vars.cdpId,
            vars.cdpId,
            (false),
            _TCR,
            0,
            0,
            0,
            0
        );

        LocalVar_InternalLiquidate memory _outputState = _liquidateSingleCDPInNormalMode(
            _contractsCache,
            _liqState
        );

        singleLiquidation.entireCdpDebt = _outputState.totalDebtToBurn;
        singleLiquidation.debtToOffset = _outputState.totalDebtToBurn;
        singleLiquidation.totalCollToSendToLiquidator = _outputState.totalColToSend;
        singleLiquidation.collSurplus = _outputState.totalColSurplus;
        singleLiquidation.debtToRedistribute = _outputState.totalDebtToRedistribute;
    }

    function _getLiquidationValuesRecoveryMode(
        ContractsCache memory _contractsCache,
        uint _price,
        uint _systemDebt,
        uint _systemColl,
        LocalVariables_LiquidationSequence memory vars,
        LiquidationValues memory singleLiquidation
    ) internal {
        LocalVar_RecoveryLiquidate memory _recState = LocalVar_RecoveryLiquidate(
            _systemDebt,
            _systemColl,
            0,
            0,
            0,
            vars.cdpId,
            _price,
            vars.ICR,
            0
        );

        LocalVar_RecoveryLiquidate memory _outputState = _liquidateSingleCDPInRecoveryMode(
            _contractsCache,
            _recState
        );

        singleLiquidation.entireCdpDebt = _outputState.totalDebtToBurn;
        singleLiquidation.debtToOffset = _outputState.totalDebtToBurn;
        singleLiquidation.totalCollToSendToLiquidator = _outputState.totalColToSend;
        singleLiquidation.collSurplus = _outputState.totalColSurplus;
        singleLiquidation.debtToRedistribute = _outputState.totalDebtToRedistribute;
    }

    /*
     * Attempt to liquidate a custom list of cdps provided by the caller.
     */
    function batchLiquidateCdps(bytes32[] memory _cdpArray) public override {
        require(_cdpArray.length != 0, "CdpManager: Calldata address array must not be empty");

        ContractsCache memory contractsCache = ContractsCache(
            activePool,
            defaultPool,
            ebtcToken,
            lqtyStaking,
            sortedCdps,
            collSurplusPool,
            gasPoolAddress
        );

        LocalVariables_OuterLiquidationFunction memory vars;
        LiquidationTotals memory totals;

        // taking fee to avoid accounted for the calculation of the TCR
        claimStakingSplitFee();

        vars.price = priceFeed.fetchPrice();
        (uint _TCR, uint systemColl, uint systemDebt) = _getTCRWithTotalCollAndDebt(
            vars.price,
            lastInterestRateUpdateTime
        );
        vars.recoveryModeAtStart = _TCR < CCR ? true : false;

        // Perform the appropriate liquidation sequence - tally values and obtain their totals.
        if (vars.recoveryModeAtStart) {
            totals = _getTotalFromBatchLiquidate_RecoveryMode(
                contractsCache,
                vars.price,
                systemColl,
                systemDebt,
                _cdpArray
            );
        } else {
            //  if !vars.recoveryModeAtStart
            totals = _getTotalsFromBatchLiquidate_NormalMode(
                contractsCache,
                vars.price,
                _TCR,
                _cdpArray
            );
        }

        require(totals.totalDebtInSequence > 0, "CdpManager: nothing to liquidate");

        // housekeeping leftover collateral for liquidated CDPs
        if (totals.totalCollSurplus > 0) {
            contractsCache.activePool.sendETH(
                address(contractsCache.collSurplusPool),
                totals.totalCollSurplus
            );
        }

        _finalizeExternalLiquidation(
            contractsCache,
            totals.totalDebtToOffset,
            totals.totalCollToSendToLiquidator,
            totals.totalDebtToRedistribute
        );
    }

    /*
     * This function is used when the batch liquidation sequence starts during Recovery Mode. However, it
     * handle the case where the system *leaves* Recovery Mode, part way through the liquidation sequence
     */
    function _getTotalFromBatchLiquidate_RecoveryMode(
        ContractsCache memory _contractsCache,
        uint _price,
        uint _systemColl,
        uint _systemDebt,
        bytes32[] memory _cdpArray
    ) internal returns (LiquidationTotals memory totals) {
        LocalVariables_LiquidationSequence memory vars;
        LiquidationValues memory singleLiquidation;

        vars.backToNormalMode = false;
        vars.entireSystemDebt = _systemDebt;
        vars.entireSystemColl = _systemColl;
        uint _TCR = _computeTCRWithGivenSystemValues(
            vars.entireSystemColl,
            vars.entireSystemDebt,
            _price
        );
        for (vars.i = 0; vars.i < _cdpArray.length; ++vars.i) {
            vars.cdpId = _cdpArray[vars.i];
            // Skip non-active cdps
            if (Cdps[vars.cdpId].status != Status.active) {
                continue;
            }
            vars.ICR = getCurrentICR(vars.cdpId, _price);

            if (!vars.backToNormalMode && (vars.ICR < MCR || vars.ICR < _TCR)) {
                vars.price = _price;
                _applyAccumulatedFeeSplit(vars.cdpId);
                _getLiquidationValuesRecoveryMode(
                    _contractsCache,
                    _price,
                    vars.entireSystemDebt,
                    vars.entireSystemColl,
                    vars,
                    singleLiquidation
                );

                // Update aggregate trackers
                vars.entireSystemDebt = vars.entireSystemDebt.sub(singleLiquidation.debtToOffset);
                vars.entireSystemColl = vars
                    .entireSystemColl
                    .sub(singleLiquidation.totalCollToSendToLiquidator)
                    .sub(singleLiquidation.collSurplus);

                // Add liquidation values to their respective running totals
                totals = _addLiquidationValuesToTotals(totals, singleLiquidation);

                _TCR = _computeTCRWithGivenSystemValues(
                    vars.entireSystemColl,
                    vars.entireSystemDebt,
                    _price
                );
                vars.backToNormalMode = _TCR < CCR ? false : true;
            } else if (vars.backToNormalMode && vars.ICR < MCR) {
                _applyAccumulatedFeeSplit(vars.cdpId);
                _getLiquidationValuesNormalMode(
                    _contractsCache,
                    _price,
                    _TCR,
                    vars,
                    singleLiquidation
                );

                // Add liquidation values to their respective running totals
                totals = _addLiquidationValuesToTotals(totals, singleLiquidation);
            } else continue; // In Normal Mode skip cdps with ICR >= MCR
        }
    }

    function _getTotalsFromBatchLiquidate_NormalMode(
        ContractsCache memory _contractsCache,
        uint _price,
        uint _TCR,
        bytes32[] memory _cdpArray
    ) internal returns (LiquidationTotals memory totals) {
        LocalVariables_LiquidationSequence memory vars;
        LiquidationValues memory singleLiquidation;

        for (vars.i = 0; vars.i < _cdpArray.length; ++vars.i) {
            vars.cdpId = _cdpArray[vars.i];
            // Skip non-active cdps
            if (Cdps[vars.cdpId].status != Status.active) {
                continue;
            }
            vars.ICR = getCurrentICR(vars.cdpId, _price);

            if (vars.ICR < MCR) {
                _applyAccumulatedFeeSplit(vars.cdpId);
                _getLiquidationValuesNormalMode(
                    _contractsCache,
                    _price,
                    _TCR,
                    vars,
                    singleLiquidation
                );

                // Add liquidation values to their respective running totals
                totals = _addLiquidationValuesToTotals(totals, singleLiquidation);
            }
        }
    }

    // --- Liquidation helper functions ---

    function _addLiquidationValuesToTotals(
        LiquidationTotals memory oldTotals,
        LiquidationValues memory singleLiquidation
    ) internal pure returns (LiquidationTotals memory newTotals) {
        // Tally all the values with their respective running totals
        newTotals.totalDebtInSequence = oldTotals.totalDebtInSequence.add(
            singleLiquidation.entireCdpDebt
        );
        newTotals.totalDebtToOffset = oldTotals.totalDebtToOffset.add(
            singleLiquidation.debtToOffset
        );
        newTotals.totalCollToSendToLiquidator = oldTotals.totalCollToSendToLiquidator.add(
            singleLiquidation.totalCollToSendToLiquidator
        );
        newTotals.totalDebtToRedistribute = oldTotals.totalDebtToRedistribute.add(
            singleLiquidation.debtToRedistribute
        );
        newTotals.totalCollToRedistribute = oldTotals.totalCollToRedistribute.add(
            singleLiquidation.collToRedistribute
        );
        newTotals.totalCollSurplus = oldTotals.totalCollSurplus.add(singleLiquidation.collSurplus);

        return newTotals;
    }

    // Move a Cdp's pending debt and collateral rewards from distributions, from the Default Pool to the Active Pool
    function _movePendingCdpRewardsToActivePool(
        IActivePool _activePool,
        IDefaultPool _defaultPool,
        uint _EBTC,
        uint _ETH
    ) internal {
        _defaultPool.decreaseEBTCDebt(_EBTC);
        _activePool.increaseEBTCDebt(_EBTC);
        _defaultPool.sendETHToActivePool(_ETH);
    }

    // --- Redemption functions ---

    struct LocalVariables_RedeemCollateralFromCdp {
        bytes32 _cdpId;
        uint _maxEBTCamount;
        uint _price;
        bytes32 _upperPartialRedemptionHint;
        bytes32 _lowerPartialRedemptionHint;
        uint _partialRedemptionHintNICR;
    }

    // Redeem as much collateral as possible from given Cdp in exchange for EBTC up to _maxEBTCamount
    function _redeemCollateralFromCdp(
        ContractsCache memory _contractsCache,
        LocalVariables_RedeemCollateralFromCdp memory _redeemColFromCdp
    ) internal returns (SingleRedemptionValues memory singleRedemption) {
        // Determine the remaining amount (lot) to be redeemed,
        // capped by the entire debt of the Cdp minus the liquidation reserve
        singleRedemption.EBTCLot = LiquityMath._min(
            _redeemColFromCdp._maxEBTCamount,
            Cdps[_redeemColFromCdp._cdpId].debt.sub(EBTC_GAS_COMPENSATION)
        );

        // Get the ETHLot of equivalent value in USD
        singleRedemption.ETHLot = collateral.getSharesByPooledEth(
            singleRedemption.EBTCLot.mul(DECIMAL_PRECISION).div(_redeemColFromCdp._price)
        );
        // Decrease the debt and collateral of the current Cdp according to the EBTC lot and corresponding ETH to send
        uint newDebt = (Cdps[_redeemColFromCdp._cdpId].debt).sub(singleRedemption.EBTCLot);
        uint newColl = (Cdps[_redeemColFromCdp._cdpId].coll).sub(singleRedemption.ETHLot);

        if (newDebt == EBTC_GAS_COMPENSATION) {
            // No debt left in the Cdp (except for the liquidation reserve), therefore the cdp gets closed
            _removeStake(_redeemColFromCdp._cdpId);
            address _borrower = _contractsCache.sortedCdps.getOwnerAddress(_redeemColFromCdp._cdpId);
            _closeCdp(_redeemColFromCdp._cdpId, Status.closedByRedemption);
            _redeemCloseCdp(
                _contractsCache,
                _redeemColFromCdp._cdpId,
                EBTC_GAS_COMPENSATION,
                newColl,
                _borrower
            );
            emit CdpUpdated(
                _redeemColFromCdp._cdpId,
                _borrower,
                0,
                0,
                0,
                CdpManagerOperation.redeemCollateral
            );
        } else {
            uint newNICR = LiquityMath._computeNominalCR(newColl, newDebt);

            /*
             * If the provided hint is out of date, we bail since trying to reinsert without a good hint will almost
             * certainly result in running out of gas.
             *
             * If the resultant net debt of the partial is less than the minimum, net debt we bail.
             */
            if (
                newNICR != _redeemColFromCdp._partialRedemptionHintNICR ||
                _convertDebtDenominationToEth(_getNetDebt(newDebt), _redeemColFromCdp._price) <
                MIN_NET_DEBT
            ) {
                singleRedemption.cancelledPartial = true;
                return singleRedemption;
            }

            _contractsCache.sortedCdps.reInsert(
                _redeemColFromCdp._cdpId,
                newNICR,
                _redeemColFromCdp._upperPartialRedemptionHint,
                _redeemColFromCdp._lowerPartialRedemptionHint
            );

            Cdps[_redeemColFromCdp._cdpId].debt = newDebt;
            Cdps[_redeemColFromCdp._cdpId].coll = newColl;
            _updateStakeAndTotalStakes(_redeemColFromCdp._cdpId);

            address _borrower = ISortedCdps(sortedCdps).getOwnerAddress(_redeemColFromCdp._cdpId);
            emit CdpUpdated(
                _redeemColFromCdp._cdpId,
                _borrower,
                newDebt,
                newColl,
                Cdps[_redeemColFromCdp._cdpId].stake,
                CdpManagerOperation.redeemCollateral
            );
        }

        return singleRedemption;
    }

    /*
     * Called when a full redemption occurs, and closes the cdp.
     * The redeemer swaps (debt - liquidation reserve) EBTC for (debt - liquidation reserve)
     * worth of ETH, so the EBTC liquidation reserve left corresponds to the remaining debt.
     * In order to close the cdp, the EBTC liquidation reserve is burned,
     * and the corresponding debt is removed from the active pool.
     * The debt recorded on the cdp's struct is zero'd elswhere, in _closeCdp.
     * Any surplus ETH left in the cdp, is sent to the Coll surplus pool, and can be later claimed by the borrower.
     */
    function _redeemCloseCdp(
        ContractsCache memory _contractsCache,
        bytes32 _cdpId, // TODO: Remove?
        uint _EBTC,
        uint _ETH,
        address _borrower
    ) internal {
        _contractsCache.ebtcToken.burn(gasPoolAddress, _EBTC);
        // Update Active Pool EBTC, and send ETH to account
        _contractsCache.activePool.decreaseEBTCDebt(_EBTC);

        // send ETH from Active Pool to CollSurplus Pool
        _contractsCache.collSurplusPool.accountSurplus(_borrower, _ETH);
        _contractsCache.activePool.sendETH(address(_contractsCache.collSurplusPool), _ETH);
    }

    function _isValidFirstRedemptionHint(
        ISortedCdps _sortedCdps,
        bytes32 _firstRedemptionHint,
        uint _price
    ) internal view returns (bool) {
        if (
            _firstRedemptionHint == _sortedCdps.nonExistId() ||
            !_sortedCdps.contains(_firstRedemptionHint) ||
            getCurrentICR(_firstRedemptionHint, _price) < MCR
        ) {
            return false;
        }

        bytes32 nextCdp = _sortedCdps.getNext(_firstRedemptionHint);
        return nextCdp == _sortedCdps.nonExistId() || getCurrentICR(nextCdp, _price) < MCR;
    }

    /* Send _EBTCamount EBTC to the system and redeem the corresponding amount of collateral
     * from as many Cdps as are needed to fill the redemption
     * request.  Applies pending rewards to a Cdp before reducing its debt and coll.
     *
     * Note that if _amount is very large, this function can run out of gas, specially if traversed cdps are small.
     * This can be easily avoided by
     * splitting the total _amount in appropriate chunks and calling the function multiple times.
     *
     * Param `_maxIterations` can also be provided, so the loop through Cdps is capped
     * (if it’s zero, it will be ignored).This makes it easier to
     * avoid OOG for the frontend, as only knowing approximately the average cost of an iteration is enough,
     * without needing to know the “topology”
     * of the cdp list. It also avoids the need to set the cap in stone in the contract,
     * nor doing gas calculations, as both gas price and opcode costs can vary.
     *
     * All Cdps that are redeemed from -- with the likely exception of the last one -- will end up with no debt left,
     * therefore they will be closed.
     * If the last Cdp does have some remaining debt, it has a finite ICR, and the reinsertion
     * could be anywhere in the list, therefore it requires a hint.
     * A frontend should use getRedemptionHints() to calculate what the ICR of this Cdp will be after redemption,
     * and pass a hint for its position
     * in the sortedCdps list along with the ICR value that the hint was found for.
     *
     * If another transaction modifies the list between calling getRedemptionHints()
     * and passing the hints to redeemCollateral(), it is very likely that the last (partially)
     * redeemed Cdp would end up with a different ICR than what the hint is for. In this case the
     * redemption will stop after the last completely redeemed Cdp and the sender will keep the
     * remaining EBTC amount, which they can attempt to redeem later.
     */
    function redeemCollateral(
        uint _EBTCamount,
        bytes32 _firstRedemptionHint,
        bytes32 _upperPartialRedemptionHint,
        bytes32 _lowerPartialRedemptionHint,
        uint _partialRedemptionHintNICR,
        uint _maxIterations,
        uint _maxFeePercentage
    ) external override {
        ContractsCache memory contractsCache = ContractsCache(
            activePool,
            defaultPool,
            ebtcToken,
            feeRecipient,
            sortedCdps,
            collSurplusPool,
            gasPoolAddress
        );
        RedemptionTotals memory totals;

        _requireValidMaxFeePercentage(_maxFeePercentage);
        _requireAfterBootstrapPeriod();
        totals.price = priceFeed.fetchPrice();
        _requireTCRoverMCR(totals.price);
        _requireAmountGreaterThanZero(_EBTCamount);
        _requireEBTCBalanceCoversRedemption(contractsCache.ebtcToken, msg.sender, _EBTCamount);

        totals.totalEBTCSupplyAtStart = _getEntireSystemDebt();
        // Confirm redeemer's balance is less than total EBTC supply
        assert(contractsCache.ebtcToken.balanceOf(msg.sender) <= totals.totalEBTCSupplyAtStart);

        totals.remainingEBTC = _EBTCamount;
        address currentBorrower;
        bytes32 _cId = _firstRedemptionHint;

        if (
            _isValidFirstRedemptionHint(
                contractsCache.sortedCdps,
                _firstRedemptionHint,
                totals.price
            )
        ) {
            currentBorrower = contractsCache.sortedCdps.existCdpOwners(_firstRedemptionHint);
        } else {
            _cId = contractsCache.sortedCdps.getLast();
            currentBorrower = contractsCache.sortedCdps.getOwnerAddress(_cId);
            // Find the first cdp with ICR >= MCR
            while (currentBorrower != address(0) && getCurrentICR(_cId, totals.price) < MCR) {
                _cId = contractsCache.sortedCdps.getPrev(_cId);
                currentBorrower = contractsCache.sortedCdps.getOwnerAddress(_cId);
            }
        }

        // Loop through the Cdps starting from the one with lowest collateral
        // ratio until _amount of EBTC is exchanged for collateral
        if (_maxIterations == 0) {
            _maxIterations = uint(-1);
        }
        while (currentBorrower != address(0) && totals.remainingEBTC > 0 && _maxIterations > 0) {
            _maxIterations--;
            // Save the address of the Cdp preceding the current one, before potentially modifying the list
            {
                bytes32 _nextId = contractsCache.sortedCdps.getPrev(_cId);
                address nextUserToCheck = contractsCache.sortedCdps.getOwnerAddress(_nextId);

                _applyPendingRewards(contractsCache.activePool, contractsCache.defaultPool, _cId);

                LocalVariables_RedeemCollateralFromCdp
                    memory _redeemColFromCdp = LocalVariables_RedeemCollateralFromCdp(
                        _cId,
                        totals.remainingEBTC,
                        totals.price,
                        _upperPartialRedemptionHint,
                        _lowerPartialRedemptionHint,
                        _partialRedemptionHintNICR
                    );
                SingleRedemptionValues memory singleRedemption = _redeemCollateralFromCdp(
                    contractsCache,
                    _redeemColFromCdp
                );
                // Partial redemption was cancelled (out-of-date hint, or new net debt < minimum),
                // therefore we could not redeem from the last Cdp
                if (singleRedemption.cancelledPartial) break;

                totals.totalEBTCToRedeem = totals.totalEBTCToRedeem.add(singleRedemption.EBTCLot);
                totals.totalETHDrawn = totals.totalETHDrawn.add(singleRedemption.ETHLot);

                totals.remainingEBTC = totals.remainingEBTC.sub(singleRedemption.EBTCLot);
                currentBorrower = nextUserToCheck;
                _cId = _nextId;
            }
        }
        require(totals.totalETHDrawn > 0, "CdpManager: Unable to redeem any amount");

        // Decay the baseRate due to time passed, and then increase it according to the size of this redemption.
        // Use the saved total EBTC supply value, from before it was reduced by the redemption.
        _updateBaseRateFromRedemption(
            totals.totalETHDrawn,
            totals.price,
            totals.totalEBTCSupplyAtStart
        );

        // Calculate the ETH fee
        totals.ETHFee = _getRedemptionFee(totals.totalETHDrawn);

        _requireUserAcceptsFee(totals.ETHFee, totals.totalETHDrawn, _maxFeePercentage);

        // Send the ETH fee to the LQTY staking contract
        contractsCache.activePool.sendETH(address(contractsCache.feeRecipient), totals.ETHFee);

        totals.ETHToSendToRedeemer = totals.totalETHDrawn.sub(totals.ETHFee);

        emit Redemption(_EBTCamount, totals.totalEBTCToRedeem, totals.totalETHDrawn, totals.ETHFee);

        // Burn the total EBTC that is cancelled with debt, and send the redeemed ETH to msg.sender
        contractsCache.ebtcToken.burn(msg.sender, totals.totalEBTCToRedeem);
        // Update Active Pool EBTC, and send ETH to account
        contractsCache.activePool.decreaseEBTCDebt(totals.totalEBTCToRedeem);
        contractsCache.activePool.sendETH(msg.sender, totals.ETHToSendToRedeemer);
    }

    // --- Helper functions ---

    // Return the nominal collateral ratio (ICR) of a given Cdp, without the price.
    // Takes a cdp's pending coll and debt rewards from redistributions into account.
    function getNominalICR(bytes32 _cdpId) public view override returns (uint) {
        (uint currentEBTCDebt, uint currentETH, , ) = getEntireDebtAndColl(_cdpId);

        uint NICR = LiquityMath._computeNominalCR(currentETH, currentEBTCDebt);
        return NICR;
    }

    // Return the current collateral ratio (ICR) of a given Cdp.
    //Takes a cdp's pending coll and debt rewards from redistributions into account.
    function getCurrentICR(bytes32 _cdpId, uint _price) public view override returns (uint) {
        (uint currentEBTCDebt, uint currentETH, , ) = getEntireDebtAndColl(_cdpId);

        uint _underlyingCollateral = collateral.getPooledEthByShares(currentETH);
        uint ICR = LiquityMath._computeCR(_underlyingCollateral, currentEBTCDebt, _price);
        return ICR;
    }

    function applyPendingRewards(bytes32 _cdpId) external override {
        // TODO: Open this up for anyone?
        _requireCallerIsBorrowerOperations();
        return _applyPendingRewards(activePool, defaultPool, _cdpId);
    }

    // Add the borrowers's coll and debt rewards earned from redistributions, to their Cdp
    function _applyPendingRewards(
        IActivePool _activePool,
        IDefaultPool _defaultPool,
        bytes32 _cdpId
    ) internal {
        _applyAccumulatedFeeSplit(_cdpId);

        if (hasPendingRewards(_cdpId)) {
            _requireCdpIsActive(_cdpId);

            // Compute pending rewards
            uint pendingETHReward = getPendingETHReward(_cdpId);
            uint pendingEBTCDebtReward = getPendingEBTCDebtReward(_cdpId);

            // Apply pending rewards to cdp's state
            Cdps[_cdpId].coll = Cdps[_cdpId].coll.add(pendingETHReward);
            Cdps[_cdpId].debt = Cdps[_cdpId].debt.add(pendingEBTCDebtReward);

            _updateCdpRewardSnapshots(_cdpId);

            // Transfer from DefaultPool to ActivePool
            _movePendingCdpRewardsToActivePool(
                _activePool,
                _defaultPool,
                pendingEBTCDebtReward,
                pendingETHReward
            );

            address _borrower = ISortedCdps(sortedCdps).getOwnerAddress(_cdpId);
            emit CdpUpdated(
                _cdpId,
                _borrower,
                Cdps[_cdpId].debt,
                Cdps[_cdpId].coll,
                Cdps[_cdpId].stake,
                CdpManagerOperation.applyPendingRewards
            );
        }
    }

    // Update borrower's snapshots of L_ETH and L_EBTCDebt to reflect the current values
    function updateCdpRewardSnapshots(bytes32 _cdpId) external override {
        _requireCallerIsBorrowerOperations();
        _applyAccumulatedFeeSplit(_cdpId);
        return _updateCdpRewardSnapshots(_cdpId);
    }

    function _updateCdpRewardSnapshots(bytes32 _cdpId) internal {
        rewardSnapshots[_cdpId].ETH = L_ETH;
        rewardSnapshots[_cdpId].EBTCDebt = L_EBTCDebt;
        emit CdpSnapshotsUpdated(L_ETH, L_EBTCDebt);
    }

    // Get the borrower's pending accumulated ETH reward, earned by their stake
    function getPendingETHReward(bytes32 _cdpId) public view override returns (uint) {
        uint snapshotETH = rewardSnapshots[_cdpId].ETH;
        uint rewardPerUnitStaked = L_ETH.sub(snapshotETH);

        if (rewardPerUnitStaked == 0 || Cdps[_cdpId].status != Status.active) {
            return 0;
        }

        uint stake = Cdps[_cdpId].stake;

        uint pendingETHReward = stake.mul(rewardPerUnitStaked).div(DECIMAL_PRECISION);

        return pendingETHReward;
    }

    // Get the borrower's pending accumulated EBTC debt reward, earned by their stake
    function getPendingEBTCDebtReward(
        bytes32 _cdpId
    ) public view override returns (uint pendingEBTCDebtReward) {
        uint snapshotEBTCDebt = rewardSnapshots[_cdpId].EBTCDebt;
        Cdp memory cdp = Cdps[_cdpId];

        if (cdp.status != Status.active) {
            return 0;
        }

        uint stake = cdp.stake;

        uint rewardPerUnitStaked = L_EBTCDebt.sub(snapshotEBTCDebt);

        if (rewardPerUnitStaked > 0) {
            pendingEBTCDebtReward = stake.mul(rewardPerUnitStaked).div(DECIMAL_PRECISION);
        }
    }

    function hasPendingRewards(bytes32 _cdpId) public view override returns (bool) {
        /*
         * A Cdp has pending rewards if its snapshot is less than the current rewards per-unit-staked sum:
         * this indicates that rewards have occured since the snapshot was made, and the user therefore has
         * pending rewards
         */
        if (Cdps[_cdpId].status != Status.active) {
            return false;
        }

        // Returns true if there have been any redemptions
        return (rewardSnapshots[_cdpId].ETH < L_ETH);
    }

    // Return the Cdps entire debt and coll struct
    function _getEntireDebtAndColl(
        bytes32 _cdpId
    ) internal view returns (LocalVar_CdpDebtColl memory) {
        (
            uint256 entireDebt,
            uint256 entireColl,
            uint pendingDebtReward,
            uint pendingCollReward
        ) = getEntireDebtAndColl(_cdpId);
        return LocalVar_CdpDebtColl(entireDebt, entireColl, pendingDebtReward, pendingCollReward);
    }

    // Return the Cdps entire debt and coll, including pending rewards from redistributions and collateral reduction from split fee.
    function getEntireDebtAndColl(
        bytes32 _cdpId
    )
        public
        view
        override
        returns (uint debt, uint coll, uint pendingEBTCDebtReward, uint pendingETHReward)
    {
        debt = Cdps[_cdpId].debt;
        (uint _feeSplitDistributed, uint _newColl) = getAccumulatedFeeSplitApplied(
            _cdpId,
            stFeePerUnitg,
            stFeePerUnitgError,
            totalStakes
        );
        coll = _newColl;

        pendingEBTCDebtReward = getPendingEBTCDebtReward(_cdpId);
        pendingETHReward = getPendingETHReward(_cdpId);

        debt = debt.add(pendingEBTCDebtReward);
        coll = coll.add(pendingETHReward);
    }

    function removeStake(bytes32 _cdpId) external override {
        _requireCallerIsBorrowerOperations();
        return _removeStake(_cdpId);
    }

    // Remove borrower's stake from the totalStakes sum, and set their stake to 0
    function _removeStake(bytes32 _cdpId) internal {
        uint stake = Cdps[_cdpId].stake;
        totalStakes = totalStakes.sub(stake);
        Cdps[_cdpId].stake = 0;
        emit TotalStakesUpdated(totalStakes);
    }

    // Remove stake from the totalStakes sum according to split fee taken
    function _removeTotalStakeForFeeTaken(uint _feeTaken) internal {
        (uint _newTotalStakes, uint stake) = getTotalStakeForFeeTaken(_feeTaken);
        totalStakes = _newTotalStakes;
        emit TotalStakesUpdated(_newTotalStakes);
    }

    // get totalStakes after split fee taken removed
    function getTotalStakeForFeeTaken(uint _feeTaken) public view override returns (uint, uint) {
        uint stake = _computeNewStake(_feeTaken);
        uint _newTotalStakes = totalStakes.sub(stake);
        return (_newTotalStakes, stake);
    }

    function updateStakeAndTotalStakes(bytes32 _cdpId) external override returns (uint) {
        _requireCallerIsBorrowerOperations();
        return _updateStakeAndTotalStakes(_cdpId);
    }

    // Update borrower's stake based on their latest collateral value
    // and update otalStakes accordingly as well
    function _updateStakeAndTotalStakes(bytes32 _cdpId) internal returns (uint) {
        (uint newStake, uint oldStake) = _updateStakeForCdp(_cdpId);

        totalStakes = totalStakes.add(newStake).sub(oldStake);
        emit TotalStakesUpdated(totalStakes);

        return newStake;
    }

    // Update borrower's stake based on their latest collateral value
    function _updateStakeForCdp(bytes32 _cdpId) internal returns (uint, uint) {
        uint newStake = _computeNewStake(Cdps[_cdpId].coll);
        uint oldStake = Cdps[_cdpId].stake;
        Cdps[_cdpId].stake = newStake;

        return (newStake, oldStake);
    }

    // Calculate a new stake based on the snapshots of the totalStakes and totalCollateral taken at the last liquidation
    function _computeNewStake(uint _coll) internal view returns (uint) {
        uint stake;
        if (totalCollateralSnapshot == 0) {
            stake = _coll;
        } else {
            /*
             * The following assert() holds true because:
             * - The system always contains >= 1 cdp
             * - When we close or liquidate a cdp, we redistribute the pending rewards,
             * so if all cdps were closed/liquidated,
             * rewards would’ve been emptied and totalCollateralSnapshot would be zero too.
             */
            assert(totalStakesSnapshot > 0);
            stake = _coll.mul(totalStakesSnapshot).div(totalCollateralSnapshot);
        }
        return stake;
    }

    function _redistributeDebtAndColl(
        IActivePool _activePool,
        IDefaultPool _defaultPool,
        uint _debt,
        uint _coll
    ) internal {
        if (_debt == 0) {
            return;
        }

        /*
         * Add distributed coll and debt rewards-per-unit-staked to the running totals. Division uses a "feedback"
         * error correction, to keep the cumulative error low in the running totals L_ETH and L_EBTCDebt:
         *
         * 1) Form numerators which compensate for the floor division errors that occurred the last time this
         * function was called.
         * 2) Calculate "per-unit-staked" ratios.
         * 3) Multiply each ratio back by its denominator, to reveal the current floor division error.
         * 4) Store these errors for use in the next correction when this function is called.
         * 5) Note: static analysis tools complain about this "division before multiplication", however, it is intended.
         */
        uint ETHNumerator = _coll.mul(DECIMAL_PRECISION).add(lastETHError_Redistribution);
        uint EBTCDebtNumerator = _debt.mul(DECIMAL_PRECISION).add(lastEBTCDebtError_Redistribution);

        // Get the per-unit-staked terms
        uint ETHRewardPerUnitStaked = ETHNumerator.div(totalStakes);
        uint EBTCDebtRewardPerUnitStaked = EBTCDebtNumerator.div(totalStakes);

        lastETHError_Redistribution = ETHNumerator.sub(ETHRewardPerUnitStaked.mul(totalStakes));
        lastEBTCDebtError_Redistribution = EBTCDebtNumerator.sub(
            EBTCDebtRewardPerUnitStaked.mul(totalStakes)
        );

        // Add per-unit-staked terms to the running totals
        L_ETH = L_ETH.add(ETHRewardPerUnitStaked);
        L_EBTCDebt = L_EBTCDebt.add(EBTCDebtRewardPerUnitStaked);

        emit LTermsUpdated(L_ETH, L_EBTCDebt);

        // Transfer coll and debt from ActivePool to DefaultPool
        _activePool.decreaseEBTCDebt(_debt);
        _defaultPool.increaseEBTCDebt(_debt);
        if (_coll > 0) {
            _activePool.sendETH(address(_defaultPool), _coll);
        }
    }

    function closeCdp(bytes32 _cdpId) external override {
        _requireCallerIsBorrowerOperations();
        return _closeCdp(_cdpId, Status.closedByOwner);
    }

    function _closeCdp(bytes32 _cdpId, Status closedStatus) internal {
        assert(closedStatus != Status.nonExistent && closedStatus != Status.active);

        uint CdpIdsArrayLength = CdpIds.length;
        _requireMoreThanOneCdpInSystem(CdpIdsArrayLength);

        Cdps[_cdpId].status = closedStatus;
        Cdps[_cdpId].coll = 0;
        Cdps[_cdpId].debt = 0;

        rewardSnapshots[_cdpId].ETH = 0;
        rewardSnapshots[_cdpId].EBTCDebt = 0;

        _removeCdp(_cdpId, CdpIdsArrayLength);
        sortedCdps.remove(_cdpId);
    }

    /*
     * Updates snapshots of system total stakes and total collateral,
     * excluding a given collateral remainder from the calculation.
     * Used in a liquidation sequence.
     *
     * The calculation excludes a portion of collateral that is in the ActivePool:
     *
     * the total ETH gas compensation from the liquidation sequence
     *
     * The ETH as compensation must be excluded as it is always sent out at the very end of the liquidation sequence.
     */
    function _updateSystemSnapshots_excludeCollRemainder(
        IActivePool _activePool,
        IDefaultPool _defaultPool,
        uint _collRemainder
    ) internal {
        totalStakesSnapshot = totalStakes;

        uint activeColl = _activePool.getETH();
        uint liquidatedColl = _defaultPool.getETH();
        totalCollateralSnapshot = activeColl.sub(_collRemainder).add(liquidatedColl);

        emit SystemSnapshotsUpdated(totalStakesSnapshot, totalCollateralSnapshot);
    }

    // Push the owner's address to the Cdp owners list, and record the corresponding array index on the Cdp struct
    function addCdpIdToArray(bytes32 _cdpId) external override returns (uint index) {
        _requireCallerIsBorrowerOperations();
        return _addCdpIdToArray(_cdpId);
    }

    function _addCdpIdToArray(bytes32 _cdpId) internal returns (uint128 index) {
        /* Max array size is 2**128 - 1, i.e. ~3e30 cdps. No risk of overflow, since cdps have minimum EBTC
        debt of liquidation reserve plus MIN_NET_DEBT.
        3e30 EBTC dwarfs the value of all wealth in the world ( which is < 1e15 USD). */

        // Push the Cdpowner to the array
        CdpIds.push(_cdpId);

        // Record the index of the new Cdpowner on their Cdp struct
        index = uint128(CdpIds.length.sub(1));
        Cdps[_cdpId].arrayIndex = index;

        return index;
    }

    /*
     * Remove a Cdp owner from the CdpOwners array, not preserving array order. Removing owner 'B' does the following:
     * [A B C D E] => [A E C D], and updates E's Cdp struct to point to its new array index.
     */
    function _removeCdp(bytes32 _cdpId, uint CdpIdsArrayLength) internal {
        Status cdpStatus = Cdps[_cdpId].status;
        // It’s set in caller function `_closeCdp`
        assert(cdpStatus != Status.nonExistent && cdpStatus != Status.active);

        uint128 index = Cdps[_cdpId].arrayIndex;
        uint length = CdpIdsArrayLength;
        uint idxLast = length.sub(1);

        assert(index <= idxLast);

        bytes32 idToMove = CdpIds[idxLast];

        CdpIds[index] = idToMove;
        Cdps[idToMove].arrayIndex = index;
        emit CdpIndexUpdated(idToMove, index);

        CdpIds.pop();
    }

    // --- Recovery Mode and TCR functions ---

    function getEntireSystemDebt() public view returns (uint entireSystemDebt) {
        return _getEntireSystemDebt();
    }

    function getTCR(uint _price) external view override returns (uint) {
        return _getTCR(_price);
    }

    function checkRecoveryMode(uint _price) external view override returns (bool) {
        return _checkRecoveryMode(_price);
    }

    // Check whether or not the system *would be* in Recovery Mode,
    // given an ETH:USD price, and the entire system coll and debt.
    function _checkPotentialRecoveryMode(
        uint _entireSystemColl,
        uint _entireSystemDebt,
        uint _price
    ) internal view returns (bool) {
        uint TCR = _computeTCRWithGivenSystemValues(_entireSystemColl, _entireSystemDebt, _price);
        return TCR < CCR;
    }

    // Calculate TCR given an price, and the entire system coll and debt.
    function _computeTCRWithGivenSystemValues(
        uint _entireSystemColl,
        uint _entireSystemDebt,
        uint _price
    ) internal view returns (uint) {
        uint _totalColl = collateral.getPooledEthByShares(_entireSystemColl);
        return LiquityMath._computeCR(_totalColl, _entireSystemDebt, _price);
    }

    // --- Staking-Reward Fee split functions ---

    // Claim split fee if there is staking-reward coming
    // and update global index & fee-per-unit variables
    function claimStakingSplitFee() public override {
        (uint _oldIndex, uint _newIndex) = _syncIndex();
        if (_newIndex > _oldIndex && totalStakes > 0) {
            (uint _feeTaken, uint _deltaFeePerUnit, uint _perUnitError) = calcFeeUponStakingReward(
                _newIndex,
                _oldIndex
            );
            ContractsCache memory _contractsCache = ContractsCache(
                activePool,
                defaultPool,
                ebtcToken,
                feeRecipient,
                sortedCdps,
                collSurplusPool,
                gasPoolAddress
            );
            _takeSplitAndUpdateFeePerUnit(
                _contractsCache,
                _feeTaken,
                _deltaFeePerUnit,
                _perUnitError
            );
            _updateSystemSnapshots_excludeCollRemainder(
                _contractsCache.activePool,
                _contractsCache.defaultPool,
                0
            );
        }
    }

    function syncUpdateIndexInterval() public override returns (uint) {
        ICollateralTokenOracle _oracle = ICollateralTokenOracle(collateral.getOracle());
        (uint256 epochsPerFrame, uint256 slotsPerEpoch, uint256 secondsPerSlot, ) = _oracle
            .getBeaconSpec();
        uint256 _newInterval = epochsPerFrame.mul(slotsPerEpoch).mul(secondsPerSlot).div(2);
        if (_newInterval != INDEX_UPD_INTERVAL) {
            emit CollateralIndexUpdateIntervalUpdated(INDEX_UPD_INTERVAL, _newInterval);
            INDEX_UPD_INTERVAL = _newInterval;
            // Ensure growth of index from last update to the time this function gets called will be charged
            claimStakingSplitFee();
        }
        return INDEX_UPD_INTERVAL;
    }

    // --- Redemption fee functions ---

    /*
     * This function has two impacts on the baseRate state variable:
     * 1) decays the baseRate based on time passed since last redemption or EBTC borrowing operation.
     * then,
     * 2) increases the baseRate based on the amount redeemed, as a proportion of total supply
     */
    function _updateBaseRateFromRedemption(
        uint _ETHDrawn,
        uint _price,
        uint _totalEBTCSupply
    ) internal returns (uint) {
        uint decayedBaseRate = _calcDecayedBaseRate();

        /* Convert the drawn ETH back to EBTC at face value rate (1 EBTC:1 USD), in order to get
         * the fraction of total supply that was redeemed at face value. */
        uint redeemedEBTCFraction = collateral.getPooledEthByShares(_ETHDrawn).mul(_price).div(
            _totalEBTCSupply
        );

        uint newBaseRate = decayedBaseRate.add(redeemedEBTCFraction.div(BETA));
        newBaseRate = LiquityMath._min(newBaseRate, DECIMAL_PRECISION); // cap baseRate at a maximum of 100%
        //assert(newBaseRate <= DECIMAL_PRECISION); // This is already enforced in the line above
        assert(newBaseRate > 0); // Base rate is always non-zero after redemption

        // Update the baseRate state variable
        baseRate = newBaseRate;
        emit BaseRateUpdated(newBaseRate);

        _updateLastFeeOpTime();

        return newBaseRate;
    }

    function getRedemptionRate() public view override returns (uint) {
        return _calcRedemptionRate(baseRate);
    }

    function getRedemptionRateWithDecay() public view override returns (uint) {
        return _calcRedemptionRate(_calcDecayedBaseRate());
    }

    function _calcRedemptionRate(uint _baseRate) internal pure returns (uint) {
        return REDEMPTION_FEE_FLOOR;
    }

    function _getRedemptionFee(uint _ETHDrawn) internal view returns (uint) {
        return _calcRedemptionFee(getRedemptionRate(), _ETHDrawn);
    }

    function getRedemptionFeeWithDecay(uint _ETHDrawn) external view override returns (uint) {
        return _calcRedemptionFee(getRedemptionRateWithDecay(), _ETHDrawn);
    }

    function _calcRedemptionFee(uint _redemptionRate, uint _ETHDrawn) internal pure returns (uint) {
        uint redemptionFee = _redemptionRate.mul(_ETHDrawn).div(DECIMAL_PRECISION);
        require(redemptionFee < _ETHDrawn, "CdpManager: Fee would eat up all returned collateral");
        return redemptionFee;
    }

    // --- Borrowing fee functions ---

    function getBorrowingRate() public view override returns (uint) {
        return _calcBorrowingRate(baseRate);
    }

    function getBorrowingRateWithDecay() public view override returns (uint) {
        return _calcBorrowingRate(_calcDecayedBaseRate());
    }

    function _calcBorrowingRate(uint _baseRate) internal pure returns (uint) {
        return BORROWING_FEE_FLOOR;
    }

    function getBorrowingFee(uint _EBTCDebt) external view override returns (uint) {
        return _calcBorrowingFee(getBorrowingRate(), _EBTCDebt);
    }

    function getBorrowingFeeWithDecay(uint _EBTCDebt) external view override returns (uint) {
        return _calcBorrowingFee(getBorrowingRateWithDecay(), _EBTCDebt);
    }

    function _calcBorrowingFee(uint _borrowingRate, uint _EBTCDebt) internal pure returns (uint) {
        return BORROWING_FEE_FLOOR;
    }

    // Updates the baseRate state variable based on time elapsed since the last redemption or EBTC borrowing operation.
    function decayBaseRateFromBorrowing() external override {
        _requireCallerIsBorrowerOperations();

        uint decayedBaseRate = _calcDecayedBaseRate();
        assert(decayedBaseRate <= DECIMAL_PRECISION); // The baseRate can decay to 0

        baseRate = decayedBaseRate;
        emit BaseRateUpdated(decayedBaseRate);

        _updateLastFeeOpTime();
    }

    // --- Internal fee functions ---

    // Update the last fee operation time only if time passed >= decay interval. This prevents base rate griefing.
    function _updateLastFeeOpTime() internal {
        uint timePassed = block.timestamp > lastFeeOperationTime
            ? block.timestamp.sub(lastFeeOperationTime)
            : 0;

        if (timePassed >= SECONDS_IN_ONE_MINUTE) {
            lastFeeOperationTime = block.timestamp;
            emit LastFeeOpTimeUpdated(block.timestamp);
        }
    }

    function _calcDecayedBaseRate() internal view returns (uint) {
        uint minutesPassed = _minutesPassedSinceLastFeeOp();
        uint decayFactor = LiquityMath._decPow(MINUTE_DECAY_FACTOR, minutesPassed);

        return baseRate.mul(decayFactor).div(DECIMAL_PRECISION);
    }

    function _minutesPassedSinceLastFeeOp() internal view returns (uint) {
        return
            block.timestamp > lastFeeOperationTime
                ? ((block.timestamp.sub(lastFeeOperationTime)).div(SECONDS_IN_ONE_MINUTE))
                : 0;
    }

    // Update the global index via collateral token
    function _syncIndex() internal returns (uint, uint) {
        uint _oldIndex = stFPPSg;
        uint _newIndex = collateral.getPooledEthByShares(DECIMAL_PRECISION);
        if (_newIndex != _oldIndex) {
            _requireValidUpdateInterval();
            stFPPSg = _newIndex;
            lastIndexTimestamp = block.timestamp;
            emit CollateralGlobalIndexUpdated(_oldIndex, _newIndex, block.timestamp);
        }
        return (_oldIndex, _newIndex);
    }

    // Calculate fee for given pair of collateral indexes, following are returned values:
    // - fee split in collateral token which will be deduced from current total system collateral
    // - fee split increase per unit, used to update stFeePerUnitg
    // - fee split calculation error, used to update stFeePerUnitgError
    function calcFeeUponStakingReward(
        uint256 _newIndex,
        uint256 _prevIndex
    ) public view override returns (uint256, uint256, uint256) {
        require(_newIndex > _prevIndex, "CdpManager: only take fee with bigger new index");
        uint256 deltaIndex = _newIndex.sub(_prevIndex);
        uint256 deltaIndexFees = deltaIndex.mul(stakingRewardSplit).div(MAX_REWARD_SPLIT);

        // we take the fee for all CDPs immediately which is scaled by index precision
        uint256 _deltaFeeSplit = deltaIndexFees.mul(getEntireSystemColl());
        uint256 _cachedAllStakes = totalStakes;
        // return the values to update the global fee accumulator
        uint256 _feeTaken = collateral.getSharesByPooledEth(_deltaFeeSplit).div(DECIMAL_PRECISION);
        uint256 _deltaFeeSplitShare = _feeTaken.mul(DECIMAL_PRECISION).add(stFeePerUnitgError);
        //.mul(collateral.getSharesByPooledEth(DECIMAL_PRECISION))
        //.div(DECIMAL_PRECISION)
        uint256 _deltaFeePerUnit = _deltaFeeSplitShare.div(_cachedAllStakes);
        uint256 _perUnitError = _deltaFeeSplitShare.sub(_deltaFeePerUnit.mul(_cachedAllStakes));
        return (_feeTaken, _deltaFeePerUnit, _perUnitError);
    }

    // Take the cut from staking reward
    // and update global fee-per-unit accumulator
    function _takeSplitAndUpdateFeePerUnit(
        ContractsCache memory _cachedContracts,
        uint256 _feeTaken,
        uint256 _deltaPerUnit,
        uint256 _newErrorPerUnit
    ) internal {
        uint _oldPerUnit = stFeePerUnitg;
        stFeePerUnitg = stFeePerUnitg.add(_deltaPerUnit);
        stFeePerUnitgError = _newErrorPerUnit;

        require(
            _cachedContracts.activePool.getETH() > _feeTaken,
            "CDPManager: fee split is too big"
        );
        address _feeRecipient = address(feeRecipient); // TODO choose other fee recipient?
        _cachedContracts.activePool.sendETH(_feeRecipient, _feeTaken);

        emit CollateralFeePerUnitUpdated(_oldPerUnit, stFeePerUnitg, _feeRecipient, _feeTaken);
    }

    // Apply accumulated fee split distributed to the CDP
    // and update its accumulator tracker accordingly
    function _applyAccumulatedFeeSplit(bytes32 _cdpId) internal {
        // TODO Ensure global states like stFeePerUnitg get timely updated
        // whenever there is a CDP modification operation,
        // such as opening, closing, adding collateral, repaying debt, or liquidating
        // OR Should we utilize some bot-keeper to work the routine job at fixed interval?
        claimStakingSplitFee();

        uint _oldPerUnitCdp = stFeePerUnitcdp[_cdpId];
        if (_oldPerUnitCdp == 0) {
            stFeePerUnitcdp[_cdpId] = stFeePerUnitg;
            return;
        } else if (_oldPerUnitCdp == stFeePerUnitg) {
            return;
        }

        (uint _feeSplitDistributed, uint _newColl) = getAccumulatedFeeSplitApplied(
            _cdpId,
            stFeePerUnitg,
            stFeePerUnitgError,
            totalStakes
        );
        Cdps[_cdpId].coll = _newColl;
        stFeePerUnitcdp[_cdpId] = stFeePerUnitg;

        emit CdpFeeSplitApplied(
            _cdpId,
            _oldPerUnitCdp,
            stFeePerUnitcdp[_cdpId],
            _feeSplitDistributed,
            Cdps[_cdpId].coll
        );
    }

    // return the applied split fee(scaled by 1e18) and the resulting CDP collateral amount after applied
    function getAccumulatedFeeSplitApplied(
        bytes32 _cdpId,
        uint _stFeePerUnitg,
        uint _stFeePerUnitgError,
        uint _totalStakes
    ) public view override returns (uint, uint) {
        if (
            stFeePerUnitcdp[_cdpId] == 0 ||
            Cdps[_cdpId].coll == 0 ||
            stFeePerUnitcdp[_cdpId] == _stFeePerUnitg
        ) {
            return (0, Cdps[_cdpId].coll);
        }

        uint _oldStake = Cdps[_cdpId].stake;

        uint _diffPerUnit = _stFeePerUnitg.sub(stFeePerUnitcdp[_cdpId]);
        uint _feeSplitDistributed = _diffPerUnit > 0 ? _oldStake.mul(_diffPerUnit) : 0;

        uint _scaledCdpColl = Cdps[_cdpId].coll.mul(DECIMAL_PRECISION);
        require(_scaledCdpColl > _feeSplitDistributed, "CdpManager: fee split is too big for CDP");

        return (
            _feeSplitDistributed,
            _scaledCdpColl.sub(_feeSplitDistributed).div(DECIMAL_PRECISION)
        );
    }

    function getDeploymentStartTime() public view returns (uint256) {
        return deploymentStartTime;
    }

    // --- 'require' wrapper functions ---

    function _requireCallerIsBorrowerOperations() internal view {
        require(
            msg.sender == borrowerOperationsAddress,
            "CdpManager: Caller is not the BorrowerOperations contract"
        );
    }

    function _requireCdpIsActive(bytes32 _cdpId) internal view {
        require(Cdps[_cdpId].status == Status.active, "CdpManager: Cdp does not exist or is closed");
    }

    function _requireEBTCBalanceCoversRedemption(
        IEBTCToken _ebtcToken,
        address _redeemer,
        uint _amount
    ) internal view {
        require(
            _ebtcToken.balanceOf(_redeemer) >= _amount,
            "CdpManager: Requested redemption amount must be <= user's EBTC token balance"
        );
    }

    function _requireMoreThanOneCdpInSystem(uint CdpOwnersArrayLength) internal view {
        require(
            CdpOwnersArrayLength > 1 && sortedCdps.getSize() > 1,
            "CdpManager: Only one cdp in the system"
        );
    }

    function _requireAmountGreaterThanZero(uint _amount) internal pure {
        require(_amount > 0, "CdpManager: Amount must be greater than zero");
    }

    function _requireTCRoverMCR(uint _price) internal view {
        require(_getTCR(_price) >= MCR, "CdpManager: Cannot redeem when TCR < MCR");
    }

    function _requireAfterBootstrapPeriod() internal view {
        uint systemDeploymentTime = getDeploymentStartTime();
        require(
            block.timestamp >= systemDeploymentTime.add(BOOTSTRAP_PERIOD),
            "CdpManager: Redemptions are not allowed during bootstrap phase"
        );
    }

    function _requireValidMaxFeePercentage(uint _maxFeePercentage) internal pure {
        require(
            _maxFeePercentage >= REDEMPTION_FEE_FLOOR && _maxFeePercentage <= DECIMAL_PRECISION,
            "Max fee percentage must be between 0.5% and 100%"
        );
    }

    function _requirePartialLiqDebtSize(uint _partialDebt, uint _entireDebt, uint _price) internal {
        require(
            (_partialDebt + _convertDebtDenominationToBtc(MIN_NET_DEBT, _price)) <= _entireDebt,
            "!maxDebtByPartialLiq"
        );
    }

    function _requireValidUpdateInterval() internal {
        require(
            block.timestamp - lastIndexTimestamp > INDEX_UPD_INTERVAL,
            "CdpManager: update index too frequent"
        );
    }

    // --- Cdp property getters ---

    function getCdpStatus(bytes32 _cdpId) external view override returns (uint) {
        return uint(Cdps[_cdpId].status);
    }

    function getCdpStake(bytes32 _cdpId) external view override returns (uint) {
        return Cdps[_cdpId].stake;
    }

    function getCdpDebt(bytes32 _cdpId) external view override returns (uint) {
        return Cdps[_cdpId].debt;
    }

    function getCdpColl(bytes32 _cdpId) external view override returns (uint) {
        return Cdps[_cdpId].coll;
    }

    // --- Cdp property setters, called by BorrowerOperations ---

    function setCdpStatus(bytes32 _cdpId, uint _num) external override {
        _requireCallerIsBorrowerOperations();
        Cdps[_cdpId].status = Status(_num);
    }

    function increaseCdpColl(bytes32 _cdpId, uint _collIncrease) external override returns (uint) {
        _requireCallerIsBorrowerOperations();
        uint newColl = Cdps[_cdpId].coll.add(_collIncrease);
        Cdps[_cdpId].coll = newColl;
        return newColl;
    }

    function decreaseCdpColl(bytes32 _cdpId, uint _collDecrease) external override returns (uint) {
        _requireCallerIsBorrowerOperations();
        uint newColl = Cdps[_cdpId].coll.sub(_collDecrease);
        Cdps[_cdpId].coll = newColl;
        return newColl;
    }

    function increaseCdpDebt(bytes32 _cdpId, uint _debtIncrease) external override returns (uint) {
        _requireCallerIsBorrowerOperations();
        uint newDebt = Cdps[_cdpId].debt.add(_debtIncrease);
        Cdps[_cdpId].debt = newDebt;
        return newDebt;
    }

    function decreaseCdpDebt(bytes32 _cdpId, uint _debtDecrease) external override returns (uint) {
        _requireCallerIsBorrowerOperations();
        uint newDebt = Cdps[_cdpId].debt.sub(_debtDecrease);
        Cdps[_cdpId].debt = newDebt;
        return newDebt;
    }
}
