// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "./Interfaces/ICdpManager.sol";
import "./Interfaces/ICollSurplusPool.sol";
import "./Interfaces/IEBTCToken.sol";
import "./Interfaces/ISortedCdps.sol";
import "./Interfaces/ILQTYToken.sol";
import "./Interfaces/ILQTYStaking.sol";
import "./Dependencies/LiquityBase.sol";
import "./Dependencies/Ownable.sol";
import "./Dependencies/CheckContract.sol";
import "./Dependencies/console.sol";

contract CdpManager is LiquityBase, Ownable, CheckContract, ICdpManager {
    string public constant NAME = "CdpManager";

    // --- Connected contract declarations ---

    address public borrowerOperationsAddress;

    address gasPoolAddress;

    ICollSurplusPool collSurplusPool;

    IEBTCToken public override ebtcToken;

    ILQTYToken public override lqtyToken;

    ILQTYStaking public override lqtyStaking;

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

    // During bootsrap period redemptions are not allowed
    uint public constant BOOTSTRAP_PERIOD = 14 days;

    /*
     * BETA: 18 digit decimal. Parameter by which to divide the redeemed fraction,
     * in order to calc the new base rate from a redemption.
     * Corresponds to (1 / ALPHA) in the white paper.
     */
    uint public constant BETA = 2;

    uint public baseRate;

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

    uint public totalStakes;

    // Snapshot of the value of totalStakes, taken immediately after the latest liquidation
    uint public totalStakesSnapshot;

    // Snapshot of the total collateral across the ActivePool and DefaultPool, immediately after the latest liquidation.
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

    struct LocalVariables_OuterLiquidationFunction {
        uint price;
        uint EBTCInStabPool;
        bool recoveryModeAtStart;
        uint liquidatedDebt;
        uint liquidatedColl;
    }

    struct LocalVariables_InnerSingleLiquidateFunction {
        uint collToLiquidate;
        uint pendingDebtReward;
        uint pendingCollReward;
    }

    struct LocalVariables_LiquidationSequence {
        uint remainingEBTCInStabPool;
        uint i;
        uint ICR;
        bytes32 user;
        bool backToNormalMode;
        uint entireSystemDebt;
        uint entireSystemColl;
    }

    struct LiquidationValues {
        uint entireCdpDebt;
        uint entireCdpColl;
        uint collGasCompensation;
        uint EBTCGasCompensation;
        uint debtToOffset;
        uint collToSendToSP;
        uint debtToRedistribute;
        uint collToRedistribute;
        uint collSurplus;
    }

    struct LiquidationTotals {
        uint totalCollInSequence;
        uint totalDebtInSequence;
        uint totalCollGasCompensation;
        uint totalEBTCGasCompensation;
        uint totalDebtToOffset;
        uint totalCollToSendToSP;
        uint totalDebtToRedistribute;
        uint totalCollToRedistribute;
        uint totalCollSurplus;
    }

    struct ContractsCache {
        IActivePool activePool;
        IDefaultPool defaultPool;
        IEBTCToken ebtcToken;
        ILQTYStaking lqtyStaking;
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
    event LQTYTokenAddressChanged(address _lqtyTokenAddress);
    event LQTYStakingAddressChanged(address _lqtyStakingAddress);

    event Liquidation(
        uint _liquidatedDebt,
        uint _liquidatedColl,
        uint _collGasCompensation,
        uint _EBTCGasCompensation
    );
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
    event BaseRateUpdated(uint _baseRate);
    event LastFeeOpTimeUpdated(uint _lastFeeOpTime);
    event TotalStakesUpdated(uint _newTotalStakes);
    event SystemSnapshotsUpdated(uint _totalStakesSnapshot, uint _totalCollateralSnapshot);
    event LTermsUpdated(uint _L_ETH, uint _L_EBTCDebt);
    event CdpSnapshotsUpdated(uint _L_ETH, uint _L_EBTCDebt);
    event CdpIndexUpdated(bytes32 _cdpId, uint _newIndex);

    enum CdpManagerOperation {
        applyPendingRewards,
        liquidateInNormalMode,
        liquidateInRecoveryMode,
        redeemCollateral
    }

    // --- Dependency setter ---

    function setAddresses(
        address _borrowerOperationsAddress,
        address _activePoolAddress,
        address _defaultPoolAddress,
        address _gasPoolAddress,
        address _collSurplusPoolAddress,
        address _priceFeedAddress,
        address _btcPriceFeedAddress,
        address _ebtcTokenAddress,
        address _sortedCdpsAddress,
        address _lqtyTokenAddress,
        address _lqtyStakingAddress
    ) external override onlyOwner {
        checkContract(_borrowerOperationsAddress);
        checkContract(_activePoolAddress);
        checkContract(_defaultPoolAddress);
        checkContract(_gasPoolAddress);
        checkContract(_collSurplusPoolAddress);
        checkContract(_priceFeedAddress);
        checkContract(_btcPriceFeedAddress);
        checkContract(_ebtcTokenAddress);
        checkContract(_sortedCdpsAddress);
        checkContract(_lqtyTokenAddress);
        checkContract(_lqtyStakingAddress);

        borrowerOperationsAddress = _borrowerOperationsAddress;
        activePool = IActivePool(_activePoolAddress);
        defaultPool = IDefaultPool(_defaultPoolAddress);
        gasPoolAddress = _gasPoolAddress;
        collSurplusPool = ICollSurplusPool(_collSurplusPoolAddress);
        priceFeed = IPriceFeed(_priceFeedAddress);
        btcPriceFeed = IPriceFeed(_btcPriceFeedAddress);
        ebtcToken = IEBTCToken(_ebtcTokenAddress);
        sortedCdps = ISortedCdps(_sortedCdpsAddress);
        lqtyToken = ILQTYToken(_lqtyTokenAddress);
        lqtyStaking = ILQTYStaking(_lqtyStakingAddress);

        emit BorrowerOperationsAddressChanged(_borrowerOperationsAddress);
        emit ActivePoolAddressChanged(_activePoolAddress);
        emit DefaultPoolAddressChanged(_defaultPoolAddress);
        emit GasPoolAddressChanged(_gasPoolAddress);
        emit CollSurplusPoolAddressChanged(_collSurplusPoolAddress);
        emit PriceFeedAddressChanged(_priceFeedAddress);
        emit EBTCTokenAddressChanged(_ebtcTokenAddress);
        emit SortedCdpsAddressChanged(_sortedCdpsAddress);
        emit LQTYTokenAddressChanged(_lqtyTokenAddress);
        emit LQTYStakingAddressChanged(_lqtyStakingAddress);

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

    // Single liquidation function. Closes the cdp if its ICR is lower than the minimum collateral ratio.
    function liquidate(bytes32 _cdpId) external override {
        _requireCdpIsActive(_cdpId);

        bytes32[] memory cdpIds = new bytes32[](1);
        cdpIds[0] = _cdpId;
        batchLiquidateCdps(cdpIds);
    }

    // --- Inner single liquidation functions ---

    // Liquidate one cdp, in Normal Mode.
    function _liquidateNormalMode(
        IActivePool _activePool,
        IDefaultPool _defaultPool,
        bytes32 _cdpId,
        uint _EBTCInStabPool
    ) internal returns (LiquidationValues memory singleLiquidation) {
        LocalVariables_InnerSingleLiquidateFunction memory vars;

        (
            singleLiquidation.entireCdpDebt,
            singleLiquidation.entireCdpColl,
            vars.pendingDebtReward,
            vars.pendingCollReward
        ) = getEntireDebtAndColl(_cdpId);

        _movePendingCdpRewardsToActivePool(
            _activePool,
            _defaultPool,
            vars.pendingDebtReward,
            vars.pendingCollReward
        );
        _removeStake(_cdpId);

        singleLiquidation.collGasCompensation = _getCollGasCompensation(
            singleLiquidation.entireCdpColl
        );
        singleLiquidation.EBTCGasCompensation = EBTC_GAS_COMPENSATION;
        uint collToLiquidate = singleLiquidation.entireCdpColl.sub(
            singleLiquidation.collGasCompensation
        );

        (
            singleLiquidation.debtToOffset,
            singleLiquidation.collToSendToSP,
            singleLiquidation.debtToRedistribute,
            singleLiquidation.collToRedistribute
        ) = _getOffsetAndRedistributionVals(
            singleLiquidation.entireCdpDebt,
            collToLiquidate,
            _EBTCInStabPool
        );

        _closeCdp(_cdpId, Status.closedByLiquidation);

        address _borrower = ISortedCdps(sortedCdps).getOwnerAddress(_cdpId);
        emit CdpLiquidated(
            _cdpId,
            _borrower,
            singleLiquidation.entireCdpDebt,
            singleLiquidation.entireCdpColl,
            CdpManagerOperation.liquidateInNormalMode
        );
        emit CdpUpdated(_cdpId, _borrower, 0, 0, 0, CdpManagerOperation.liquidateInNormalMode);
        return singleLiquidation;
    }

    // Liquidate one cdp, in Recovery Mode.
    function _liquidateRecoveryMode(
        IActivePool _activePool,
        IDefaultPool _defaultPool,
        bytes32 _cdpId,
        uint _ICR,
        uint _EBTCInStabPool,
        uint _TCR,
        uint _price
    ) internal returns (LiquidationValues memory singleLiquidation) {
        LocalVariables_InnerSingleLiquidateFunction memory vars;
        if (CdpIds.length <= 1) {
            return singleLiquidation;
        } // don't liquidate if last cdp
        (
            singleLiquidation.entireCdpDebt,
            singleLiquidation.entireCdpColl,
            vars.pendingDebtReward,
            vars.pendingCollReward
        ) = getEntireDebtAndColl(_cdpId);

        singleLiquidation.collGasCompensation = _getCollGasCompensation(
            singleLiquidation.entireCdpColl
        );
        singleLiquidation.EBTCGasCompensation = EBTC_GAS_COMPENSATION;
        vars.collToLiquidate = singleLiquidation.entireCdpColl.sub(
            singleLiquidation.collGasCompensation
        );

        // If ICR <= 100%, purely redistribute the Cdp across all active Cdps
        if (_ICR <= _100pct) {
            _movePendingCdpRewardsToActivePool(
                _activePool,
                _defaultPool,
                vars.pendingDebtReward,
                vars.pendingCollReward
            );
            _removeStake(_cdpId);

            singleLiquidation.debtToOffset = 0;
            singleLiquidation.collToSendToSP = 0;
            singleLiquidation.debtToRedistribute = singleLiquidation.entireCdpDebt;
            singleLiquidation.collToRedistribute = vars.collToLiquidate;

            _closeCdp(_cdpId, Status.closedByLiquidation);

            address _borrower = ISortedCdps(sortedCdps).getOwnerAddress(_cdpId);
            emit CdpLiquidated(
                _cdpId,
                _borrower,
                singleLiquidation.entireCdpDebt,
                singleLiquidation.entireCdpColl,
                CdpManagerOperation.liquidateInRecoveryMode
            );
            emit CdpUpdated(_cdpId, _borrower, 0, 0, 0, CdpManagerOperation.liquidateInRecoveryMode);

            // If 100% < ICR < MCR, offset as much as possible, and redistribute the remainder
        } else if ((_ICR > _100pct) && (_ICR < MCR)) {
            _movePendingCdpRewardsToActivePool(
                _activePool,
                _defaultPool,
                vars.pendingDebtReward,
                vars.pendingCollReward
            );
            _removeStake(_cdpId);

            (
                singleLiquidation.debtToOffset,
                singleLiquidation.collToSendToSP,
                singleLiquidation.debtToRedistribute,
                singleLiquidation.collToRedistribute
            ) = _getOffsetAndRedistributionVals(
                singleLiquidation.entireCdpDebt,
                vars.collToLiquidate,
                _EBTCInStabPool
            );

            _closeCdp(_cdpId, Status.closedByLiquidation);

            address _borrower = ISortedCdps(sortedCdps).getOwnerAddress(_cdpId);
            emit CdpLiquidated(
                _cdpId,
                _borrower,
                singleLiquidation.entireCdpDebt,
                singleLiquidation.entireCdpColl,
                CdpManagerOperation.liquidateInRecoveryMode
            );
            emit CdpUpdated(_cdpId, _borrower, 0, 0, 0, CdpManagerOperation.liquidateInRecoveryMode);
            /*
             * If 110% <= ICR < current TCR (accounting for the preceding liquidations in the current sequence)
             * and there is EBTC in the Stability Pool, only offset, with no redistribution,
             * but at a capped rate of 1.1 and only if the whole debt can be liquidated.
             * The remainder due to the capped rate will be claimable as collateral surplus.
             */
        } else if (
            (_ICR >= MCR) && (_ICR < _TCR) && (singleLiquidation.entireCdpDebt <= _EBTCInStabPool)
        ) {
            _movePendingCdpRewardsToActivePool(
                _activePool,
                _defaultPool,
                vars.pendingDebtReward,
                vars.pendingCollReward
            );
            assert(_EBTCInStabPool != 0);

            _removeStake(_cdpId);
            singleLiquidation = _getCappedOffsetVals(
                singleLiquidation.entireCdpDebt,
                singleLiquidation.entireCdpColl,
                _price
            );

            address _borrower = ISortedCdps(sortedCdps).getOwnerAddress(_cdpId);
            _closeCdp(_cdpId, Status.closedByLiquidation);
            if (singleLiquidation.collSurplus > 0) {
                collSurplusPool.accountSurplus(_borrower, singleLiquidation.collSurplus);
            }

            emit CdpLiquidated(
                _cdpId,
                _borrower,
                singleLiquidation.entireCdpDebt,
                singleLiquidation.collToSendToSP,
                CdpManagerOperation.liquidateInRecoveryMode
            );
            emit CdpUpdated(_cdpId, _borrower, 0, 0, 0, CdpManagerOperation.liquidateInRecoveryMode);
        } else {
            // if (_ICR >= MCR && ( _ICR >= _TCR || singleLiquidation.entireCdpDebt > _EBTCInStabPool))
            LiquidationValues memory zeroVals;
            return zeroVals;
        }

        return singleLiquidation;
    }

    /* In a full liquidation, returns the values for a cdp's coll and debt to be offset, and coll and debt to be
     * redistributed to active cdps.
     */
    function _getOffsetAndRedistributionVals(
        uint _debt,
        uint _coll,
        uint _EBTCInStabPool
    )
        internal
        pure
        returns (
            uint debtToOffset,
            uint collToSendToSP,
            uint debtToRedistribute,
            uint collToRedistribute
        )
    {
        if (_EBTCInStabPool > 0) {
            /*
             * Offset as much debt & collateral as possible against the Stability Pool, and redistribute the remainder
             * between all active cdps.
             *
             *  If the cdp's debt is larger than the deposited EBTC in the Stability Pool:
             *
             *  - Offset an amount of the cdp's debt equal to the EBTC in the Stability Pool
             *  - Send a fraction of the cdp's collateral to the Stability Pool,
             *  equal to the fraction of its offset debt
             *
             */
            debtToOffset = LiquityMath._min(_debt, _EBTCInStabPool);
            collToSendToSP = _coll.mul(debtToOffset).div(_debt);
            debtToRedistribute = _debt.sub(debtToOffset);
            collToRedistribute = _coll.sub(collToSendToSP);
        } else {
            debtToOffset = 0;
            collToSendToSP = 0;
            debtToRedistribute = _debt;
            collToRedistribute = _coll;
        }
    }

    /*
     *  Get its offset coll/debt and ETH gas comp, and close the cdp.
     */
    function _getCappedOffsetVals(
        uint _entireCdpDebt,
        uint _entireCdpColl,
        uint _price
    ) internal pure returns (LiquidationValues memory singleLiquidation) {
        singleLiquidation.entireCdpDebt = _entireCdpDebt;
        singleLiquidation.entireCdpColl = _entireCdpColl;
        uint cappedCollPortion = _entireCdpDebt.mul(MCR).div(_price);

        singleLiquidation.collGasCompensation = _getCollGasCompensation(cappedCollPortion);
        singleLiquidation.EBTCGasCompensation = EBTC_GAS_COMPENSATION;

        singleLiquidation.debtToOffset = _entireCdpDebt;
        singleLiquidation.collToSendToSP = cappedCollPortion.sub(
            singleLiquidation.collGasCompensation
        );
        singleLiquidation.collSurplus = _entireCdpColl.sub(cappedCollPortion);
        singleLiquidation.debtToRedistribute = 0;
        singleLiquidation.collToRedistribute = 0;
    }

    /*
     * Liquidate a sequence of cdps. Closes a maximum number of n under-collateralized Cdps,
     * starting from the one with the lowest collateral ratio in the system, and moving upwards
     */
    function liquidateCdps(uint _n) external override {
        ContractsCache memory contractsCache = ContractsCache(
            activePool,
            defaultPool,
            IEBTCToken(address(0)),
            ILQTYStaking(address(0)),
            sortedCdps,
            ICollSurplusPool(address(0)),
            address(0)
        );

        LocalVariables_OuterLiquidationFunction memory vars;

        LiquidationTotals memory totals;

        vars.price = priceFeed.fetchPrice();
        vars.EBTCInStabPool = _tmpGetReserveInLiquidation();
        vars.recoveryModeAtStart = _checkRecoveryMode(vars.price);

        // Perform the appropriate liquidation sequence - tally the values, and obtain their totals
        if (vars.recoveryModeAtStart) {
            totals = _getTotalsFromLiquidateCdpsSequence_RecoveryMode(
                contractsCache,
                vars.price,
                vars.EBTCInStabPool,
                _n
            );
        } else {
            // if !vars.recoveryModeAtStart
            totals = _getTotalsFromLiquidateCdpsSequence_NormalMode(
                contractsCache.activePool,
                contractsCache.defaultPool,
                vars.price,
                vars.EBTCInStabPool,
                _n
            );
        }

        require(totals.totalDebtInSequence > 0, "CdpManager: nothing to liquidate");

        // Move liquidated ETH and EBTC to the appropriate pools
        _tmpOffsetInLiquidation(totals.totalDebtToOffset, totals.totalCollToSendToSP);
        _redistributeDebtAndColl(
            contractsCache.activePool,
            contractsCache.defaultPool,
            totals.totalDebtToRedistribute,
            totals.totalCollToRedistribute
        );
        if (totals.totalCollSurplus > 0) {
            contractsCache.activePool.sendETH(address(collSurplusPool), totals.totalCollSurplus);
        }

        // Update system snapshots
        _updateSystemSnapshots_excludeCollRemainder(
            contractsCache.activePool,
            totals.totalCollGasCompensation
        );

        vars.liquidatedDebt = totals.totalDebtInSequence;
        vars.liquidatedColl = totals.totalCollInSequence.sub(totals.totalCollGasCompensation).sub(
            totals.totalCollSurplus
        );
        emit Liquidation(
            vars.liquidatedDebt,
            vars.liquidatedColl,
            totals.totalCollGasCompensation,
            totals.totalEBTCGasCompensation
        );

        // Send gas compensation to caller
        _sendGasCompensation(
            contractsCache.activePool,
            msg.sender,
            totals.totalEBTCGasCompensation,
            totals.totalCollGasCompensation
        );
    }

    /*
     * This function is used when the liquidateCdps sequence starts during Recovery Mode. However, it
     * handle the case where the system *leaves* Recovery Mode, part way through the liquidation sequence
     */
    function _getTotalsFromLiquidateCdpsSequence_RecoveryMode(
        ContractsCache memory _contractsCache,
        uint _price,
        uint _EBTCInStabPool,
        uint _n
    ) internal returns (LiquidationTotals memory totals) {
        LocalVariables_LiquidationSequence memory vars;
        LiquidationValues memory singleLiquidation;

        vars.remainingEBTCInStabPool = _EBTCInStabPool;
        vars.backToNormalMode = false;
        vars.entireSystemDebt = getEntireSystemDebt();
        vars.entireSystemColl = getEntireSystemColl();

        vars.user = _contractsCache.sortedCdps.getLast();
        bytes32 firstId = _contractsCache.sortedCdps.getFirst();
        for (vars.i = 0; vars.i < _n && vars.user != firstId; vars.i++) {
            // we need to cache it, because current user is likely going to be deleted
            bytes32 nextUser = _contractsCache.sortedCdps.getPrev(vars.user);

            vars.ICR = getCurrentICR(vars.user, _price);

            if (!vars.backToNormalMode) {
                // Break the loop if ICR is greater than MCR and Stability Pool is empty
                if (vars.ICR >= MCR && vars.remainingEBTCInStabPool == 0) {
                    break;
                }

                uint TCR = LiquityMath._computeCR(
                    vars.entireSystemColl,
                    vars.entireSystemDebt,
                    _price
                );

                singleLiquidation = _liquidateRecoveryMode(
                    _contractsCache.activePool,
                    _contractsCache.defaultPool,
                    vars.user,
                    vars.ICR,
                    vars.remainingEBTCInStabPool,
                    TCR,
                    _price
                );

                // Update aggregate trackers
                vars.remainingEBTCInStabPool = vars.remainingEBTCInStabPool.sub(
                    singleLiquidation.debtToOffset
                );
                vars.entireSystemDebt = vars.entireSystemDebt.sub(singleLiquidation.debtToOffset);
                vars.entireSystemColl = vars
                    .entireSystemColl
                    .sub(singleLiquidation.collToSendToSP)
                    .sub(singleLiquidation.collGasCompensation)
                    .sub(singleLiquidation.collSurplus);

                // Add liquidation values to their respective running totals
                totals = _addLiquidationValuesToTotals(totals, singleLiquidation);

                vars.backToNormalMode = !_checkPotentialRecoveryMode(
                    vars.entireSystemColl,
                    vars.entireSystemDebt,
                    _price
                );
            } else if (vars.backToNormalMode && vars.ICR < MCR) {
                singleLiquidation = _liquidateNormalMode(
                    _contractsCache.activePool,
                    _contractsCache.defaultPool,
                    vars.user,
                    vars.remainingEBTCInStabPool
                );

                vars.remainingEBTCInStabPool = vars.remainingEBTCInStabPool.sub(
                    singleLiquidation.debtToOffset
                );

                // Add liquidation values to their respective running totals
                totals = _addLiquidationValuesToTotals(totals, singleLiquidation);
            } else break; // break if the loop reaches a Cdp with ICR >= MCR

            vars.user = nextUser;
        }
    }

    function _getTotalsFromLiquidateCdpsSequence_NormalMode(
        IActivePool _activePool,
        IDefaultPool _defaultPool,
        uint _price,
        uint _EBTCInStabPool,
        uint _n
    ) internal returns (LiquidationTotals memory totals) {
        LocalVariables_LiquidationSequence memory vars;
        LiquidationValues memory singleLiquidation;
        ISortedCdps sortedCdpsCached = sortedCdps;

        vars.remainingEBTCInStabPool = _EBTCInStabPool;

        for (vars.i = 0; vars.i < _n; vars.i++) {
            vars.user = sortedCdpsCached.getLast();
            vars.ICR = getCurrentICR(vars.user, _price);

            if (vars.ICR < MCR) {
                singleLiquidation = _liquidateNormalMode(
                    _activePool,
                    _defaultPool,
                    vars.user,
                    vars.remainingEBTCInStabPool
                );

                vars.remainingEBTCInStabPool = vars.remainingEBTCInStabPool.sub(
                    singleLiquidation.debtToOffset
                );

                // Add liquidation values to their respective running totals
                totals = _addLiquidationValuesToTotals(totals, singleLiquidation);
            } else break; // break if the loop reaches a Cdp with ICR >= MCR
        }
    }

    /*
     * Attempt to liquidate a custom list of cdps provided by the caller.
     */
    function batchLiquidateCdps(bytes32[] memory _cdpArray) public override {
        require(_cdpArray.length != 0, "CdpManager: Calldata address array must not be empty");

        IActivePool activePoolCached = activePool;
        IDefaultPool defaultPoolCached = defaultPool;

        LocalVariables_OuterLiquidationFunction memory vars;
        LiquidationTotals memory totals;

        vars.price = priceFeed.fetchPrice();
        vars.EBTCInStabPool = _tmpGetReserveInLiquidation();
        vars.recoveryModeAtStart = _checkRecoveryMode(vars.price);

        // Perform the appropriate liquidation sequence - tally values and obtain their totals.
        if (vars.recoveryModeAtStart) {
            totals = _getTotalFromBatchLiquidate_RecoveryMode(
                activePoolCached,
                defaultPoolCached,
                vars.price,
                vars.EBTCInStabPool,
                _cdpArray
            );
        } else {
            //  if !vars.recoveryModeAtStart
            totals = _getTotalsFromBatchLiquidate_NormalMode(
                activePoolCached,
                defaultPoolCached,
                vars.price,
                vars.EBTCInStabPool,
                _cdpArray
            );
        }

        require(totals.totalDebtInSequence > 0, "CdpManager: nothing to liquidate");

        // Move liquidated ETH and EBTC to the appropriate pools
        _tmpOffsetInLiquidation(totals.totalDebtToOffset, totals.totalCollToSendToSP);
        _redistributeDebtAndColl(
            activePoolCached,
            defaultPoolCached,
            totals.totalDebtToRedistribute,
            totals.totalCollToRedistribute
        );
        if (totals.totalCollSurplus > 0) {
            activePoolCached.sendETH(address(collSurplusPool), totals.totalCollSurplus);
        }

        // Update system snapshots
        _updateSystemSnapshots_excludeCollRemainder(
            activePoolCached,
            totals.totalCollGasCompensation
        );

        vars.liquidatedDebt = totals.totalDebtInSequence;
        vars.liquidatedColl = totals.totalCollInSequence.sub(totals.totalCollGasCompensation).sub(
            totals.totalCollSurplus
        );
        emit Liquidation(
            vars.liquidatedDebt,
            vars.liquidatedColl,
            totals.totalCollGasCompensation,
            totals.totalEBTCGasCompensation
        );

        // Send gas compensation to caller
        _sendGasCompensation(
            activePoolCached,
            msg.sender,
            totals.totalEBTCGasCompensation,
            totals.totalCollGasCompensation
        );
    }

    /*
     * This function is used when the batch liquidation sequence starts during Recovery Mode. However, it
     * handle the case where the system *leaves* Recovery Mode, part way through the liquidation sequence
     */
    function _getTotalFromBatchLiquidate_RecoveryMode(
        IActivePool _activePool,
        IDefaultPool _defaultPool,
        uint _price,
        uint _EBTCInStabPool,
        bytes32[] memory _cdpArray
    ) internal returns (LiquidationTotals memory totals) {
        LocalVariables_LiquidationSequence memory vars;
        LiquidationValues memory singleLiquidation;

        vars.remainingEBTCInStabPool = _EBTCInStabPool;
        vars.backToNormalMode = false;
        vars.entireSystemDebt = getEntireSystemDebt();
        vars.entireSystemColl = getEntireSystemColl();

        for (vars.i = 0; vars.i < _cdpArray.length; vars.i++) {
            vars.user = _cdpArray[vars.i];
            // Skip non-active cdps
            if (Cdps[vars.user].status != Status.active) {
                continue;
            }
            vars.ICR = getCurrentICR(vars.user, _price);

            if (!vars.backToNormalMode) {
                // Skip this cdp if ICR is greater than MCR and Stability Pool is empty
                if (vars.ICR >= MCR && vars.remainingEBTCInStabPool == 0) {
                    continue;
                }

                uint TCR = LiquityMath._computeCR(
                    vars.entireSystemColl,
                    vars.entireSystemDebt,
                    _price
                );

                singleLiquidation = _liquidateRecoveryMode(
                    _activePool,
                    _defaultPool,
                    vars.user,
                    vars.ICR,
                    vars.remainingEBTCInStabPool,
                    TCR,
                    _price
                );

                // Update aggregate trackers
                vars.remainingEBTCInStabPool = vars.remainingEBTCInStabPool.sub(
                    singleLiquidation.debtToOffset
                );
                vars.entireSystemDebt = vars.entireSystemDebt.sub(singleLiquidation.debtToOffset);
                vars.entireSystemColl = vars
                    .entireSystemColl
                    .sub(singleLiquidation.collToSendToSP)
                    .sub(singleLiquidation.collGasCompensation)
                    .sub(singleLiquidation.collSurplus);

                // Add liquidation values to their respective running totals
                totals = _addLiquidationValuesToTotals(totals, singleLiquidation);

                vars.backToNormalMode = !_checkPotentialRecoveryMode(
                    vars.entireSystemColl,
                    vars.entireSystemDebt,
                    _price
                );
            } else if (vars.backToNormalMode && vars.ICR < MCR) {
                singleLiquidation = _liquidateNormalMode(
                    _activePool,
                    _defaultPool,
                    vars.user,
                    vars.remainingEBTCInStabPool
                );
                vars.remainingEBTCInStabPool = vars.remainingEBTCInStabPool.sub(
                    singleLiquidation.debtToOffset
                );

                // Add liquidation values to their respective running totals
                totals = _addLiquidationValuesToTotals(totals, singleLiquidation);
            } else continue; // In Normal Mode skip cdps with ICR >= MCR
        }
    }

    function _getTotalsFromBatchLiquidate_NormalMode(
        IActivePool _activePool,
        IDefaultPool _defaultPool,
        uint _price,
        uint _EBTCInStabPool,
        bytes32[] memory _cdpArray
    ) internal returns (LiquidationTotals memory totals) {
        LocalVariables_LiquidationSequence memory vars;
        LiquidationValues memory singleLiquidation;

        vars.remainingEBTCInStabPool = _EBTCInStabPool;

        for (vars.i = 0; vars.i < _cdpArray.length; vars.i++) {
            vars.user = _cdpArray[vars.i];
            vars.ICR = getCurrentICR(vars.user, _price);

            if (vars.ICR < MCR) {
                singleLiquidation = _liquidateNormalMode(
                    _activePool,
                    _defaultPool,
                    vars.user,
                    vars.remainingEBTCInStabPool
                );
                vars.remainingEBTCInStabPool = vars.remainingEBTCInStabPool.sub(
                    singleLiquidation.debtToOffset
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
        newTotals.totalCollGasCompensation = oldTotals.totalCollGasCompensation.add(
            singleLiquidation.collGasCompensation
        );
        newTotals.totalEBTCGasCompensation = oldTotals.totalEBTCGasCompensation.add(
            singleLiquidation.EBTCGasCompensation
        );
        newTotals.totalDebtInSequence = oldTotals.totalDebtInSequence.add(
            singleLiquidation.entireCdpDebt
        );
        newTotals.totalCollInSequence = oldTotals.totalCollInSequence.add(
            singleLiquidation.entireCdpColl
        );
        newTotals.totalDebtToOffset = oldTotals.totalDebtToOffset.add(
            singleLiquidation.debtToOffset
        );
        newTotals.totalCollToSendToSP = oldTotals.totalCollToSendToSP.add(
            singleLiquidation.collToSendToSP
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

    function _sendGasCompensation(
        IActivePool _activePool,
        address _liquidator,
        uint _EBTC,
        uint _ETH
    ) internal {
        if (_EBTC > 0) {
            ebtcToken.returnFromPool(gasPoolAddress, _liquidator, _EBTC);
        }

        if (_ETH > 0) {
            _activePool.sendETH(_liquidator, _ETH);
        }
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
        singleRedemption.ETHLot = singleRedemption.EBTCLot.mul(DECIMAL_PRECISION).div(
            _redeemColFromCdp._price
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
                _getNetDebt(newDebt).mul(btcPriceFeed.fetchPrice()).div(DECIMAL_PRECISION) < MIN_NET_DEBT
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
        bytes32 _cdpId,
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
            lqtyStaking,
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

        totals.totalEBTCSupplyAtStart = getEntireSystemDebt();
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
        contractsCache.activePool.sendETH(address(contractsCache.lqtyStaking), totals.ETHFee);
        contractsCache.lqtyStaking.increaseF_ETH(totals.ETHFee);

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
        (uint currentETH, uint currentEBTCDebt) = _getCurrentCdpAmounts(_cdpId);

        uint NICR = LiquityMath._computeNominalCR(currentETH, currentEBTCDebt);
        return NICR;
    }

    // Return the current collateral ratio (ICR) of a given Cdp.
    //Takes a cdp's pending coll and debt rewards from redistributions into account.
    function getCurrentICR(bytes32 _cdpId, uint _price) public view override returns (uint) {
        (uint currentETH, uint currentEBTCDebt) = _getCurrentCdpAmounts(_cdpId);

        uint ICR = LiquityMath._computeCR(currentETH, currentEBTCDebt, _price);
        return ICR;
    }

    function _getCurrentCdpAmounts(bytes32 _cdpId) internal view returns (uint, uint) {
        uint pendingETHReward = getPendingETHReward(_cdpId);
        uint pendingEBTCDebtReward = getPendingEBTCDebtReward(_cdpId);

        uint currentETH = Cdps[_cdpId].coll.add(pendingETHReward);
        uint currentEBTCDebt = Cdps[_cdpId].debt.add(pendingEBTCDebtReward);

        return (currentETH, currentEBTCDebt);
    }

    function applyPendingRewards(bytes32 _cdpId) external override {
        _requireCallerIsBorrowerOperations();
        return _applyPendingRewards(activePool, defaultPool, _cdpId);
    }

    // Add the borrowers's coll and debt rewards earned from redistributions, to their Cdp
    function _applyPendingRewards(
        IActivePool _activePool,
        IDefaultPool _defaultPool,
        bytes32 _cdpId
    ) internal {
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

    // Get the borrower's pending accumulated EBTC reward, earned by their stake
    function getPendingEBTCDebtReward(bytes32 _cdpId) public view override returns (uint) {
        uint snapshotEBTCDebt = rewardSnapshots[_cdpId].EBTCDebt;
        uint rewardPerUnitStaked = L_EBTCDebt.sub(snapshotEBTCDebt);

        if (rewardPerUnitStaked == 0 || Cdps[_cdpId].status != Status.active) {
            return 0;
        }

        uint stake = Cdps[_cdpId].stake;

        uint pendingEBTCDebtReward = stake.mul(rewardPerUnitStaked).div(DECIMAL_PRECISION);

        return pendingEBTCDebtReward;
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

        return (rewardSnapshots[_cdpId].ETH < L_ETH);
    }

    // Return the Cdps entire debt and coll, including pending rewards from redistributions.
    function getEntireDebtAndColl(
        bytes32 _cdpId
    )
        public
        view
        override
        returns (uint debt, uint coll, uint pendingEBTCDebtReward, uint pendingETHReward)
    {
        debt = Cdps[_cdpId].debt;
        coll = Cdps[_cdpId].coll;

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
    }

    function updateStakeAndTotalStakes(bytes32 _cdpId) external override returns (uint) {
        _requireCallerIsBorrowerOperations();
        return _updateStakeAndTotalStakes(_cdpId);
    }

    // Update borrower's stake based on their latest collateral value
    function _updateStakeAndTotalStakes(bytes32 _cdpId) internal returns (uint) {
        uint newStake = _computeNewStake(Cdps[_cdpId].coll);
        uint oldStake = Cdps[_cdpId].stake;
        Cdps[_cdpId].stake = newStake;

        totalStakes = totalStakes.sub(oldStake).add(newStake);
        emit TotalStakesUpdated(totalStakes);

        return newStake;
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
        _activePool.sendETH(address(_defaultPool), _coll);
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
        uint _collRemainder
    ) internal {
        totalStakesSnapshot = totalStakes;

        uint activeColl = _activePool.getETH();
        uint liquidatedColl = defaultPool.getETH();
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
    ) internal pure returns (bool) {
        uint TCR = LiquityMath._computeCR(_entireSystemColl, _entireSystemDebt, _price);

        return TCR < CCR;
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
        uint redeemedEBTCFraction = _ETHDrawn.mul(_price).div(_totalEBTCSupply);

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
        return
            LiquityMath._min(
                REDEMPTION_FEE_FLOOR.add(_baseRate),
                DECIMAL_PRECISION // cap at a maximum of 100%
            );
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
        return LiquityMath._min(BORROWING_FEE_FLOOR.add(_baseRate), MAX_BORROWING_FEE);
    }

    function getBorrowingFee(uint _EBTCDebt) external view override returns (uint) {
        return _calcBorrowingFee(getBorrowingRate(), _EBTCDebt);
    }

    function getBorrowingFeeWithDecay(uint _EBTCDebt) external view override returns (uint) {
        return _calcBorrowingFee(getBorrowingRateWithDecay(), _EBTCDebt);
    }

    function _calcBorrowingFee(uint _borrowingRate, uint _EBTCDebt) internal pure returns (uint) {
        return _borrowingRate.mul(_EBTCDebt).div(DECIMAL_PRECISION);
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
        uint timePassed = block.timestamp.sub(lastFeeOperationTime);

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
        return (block.timestamp.sub(lastFeeOperationTime)).div(SECONDS_IN_ONE_MINUTE);
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
        uint systemDeploymentTime = lqtyToken.getDeploymentStartTime();
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

    // --- Temporary functions to be removed after new Liquidation code in-place ---

    // Dummy temporary function before liquidation rewrite code kick-in. Should be removed afterwards
    function _tmpOffsetInLiquidation(uint _debtToOffset, uint _collToAdd) internal {
        IActivePool activePoolCached = activePool;

        // decrease the liquidated EBTC debt from the active pool
        activePoolCached.decreaseEBTCDebt(_debtToOffset);

        // No Burn of the debt, i.e., debt token total supply keep same

        // Just burn the collateral
        activePoolCached.sendETH(address(0x000000000000000000000000000000000000dEaD), _collToAdd);
    }

    // Dummy temporary function before liquidation rewrite code kick-in. Should be removed afterwards
    function _tmpGetReserveInLiquidation() internal returns (uint) {
        return type(uint256).max;
    }
}
