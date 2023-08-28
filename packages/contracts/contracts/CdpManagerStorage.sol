// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./Interfaces/ICdpManager.sol";
import "./Interfaces/ICollSurplusPool.sol";
import "./Interfaces/IEBTCToken.sol";
import "./Interfaces/ISortedCdps.sol";
import "./Dependencies/LiquityBase.sol";
import "./Dependencies/ReentrancyGuard.sol";
import "./Dependencies/ICollateralTokenOracle.sol";
import "./Dependencies/AuthNoOwner.sol";

/**
    @notice CDP Manager storage and shared functions
    @dev CDP Manager was split to get around contract size limitations, liquidation related functions are delegated to LiquidationLibrary contract code.
    @dev Both must maintain the same storage layout, so shared storage components where placed here
    @dev Shared functions were also added here to de-dup code
 */
contract CdpManagerStorage is LiquityBase, ReentrancyGuard, ICdpManagerData, AuthNoOwner {
    // TODO: IMPROVE
    // NOTE: No packing cause it's the last var, no need for u64
    uint128 public constant UNSET_TIMESTAMP_FLAG = type(uint128).max;

    // TODO: IMPROVE THIS!!!
    uint128 public lastRecoveryModeTimestamp = UNSET_TIMESTAMP_FLAG; // use max to signify
    uint128 public waitTimeFromRMTriggerToLiquidations = 15 minutes;

    // TODO: Pitfal is fee split // NOTE: Solved by calling `checkLiquidateCoolDownAndReset` on external operations from BO

    /// @dev Trusted Function from BO
    /// @dev BO accrues totals before adjusting them
    ///     To maintain CEI compliance we use this trusted function
    function notifyBeginRM(uint256 tcr) external {
        _requireCallerIsBorrowerOperations();

        _notifyBeginRM(tcr);
    }

    /// @dev Internal notify called by Redemptions and Liquidations
    function _notifyBeginRM(uint256 tcr) internal {
        emit TCRNotified(tcr);

        _beginRMLiquidationCooldown();
    }

    /// @dev Trusted Function from BO
    /// @dev BO accrues totals before adjusting them
    ///     To maintain CEI compliance we use this trusted function
    function notifyEndRM(uint256 tcr) external {
        _requireCallerIsBorrowerOperations();

        _notifyEndRM(tcr);
    }

    /// @dev Internal notify called by Redemptions and Liquidations
    function _notifyEndRM(uint256 tcr) internal {
        emit TCRNotified(tcr);

        _stopRMLiquidationCooldown();
    }

    /// @dev Checks that the system is in RM
    function beginRMLiquidationCooldown() external {
        // Require we're in RM
        uint256 price = priceFeed.fetchPrice();
        bool isRecoveryMode = _checkRecoveryModeForTCR(_getTCR(price));
        require(isRecoveryMode, "Grace Period can only start in RM");

        _beginRMLiquidationCooldown();
    }

    function _beginRMLiquidationCooldown() internal {
        // Arm the countdown
        if (lastRecoveryModeTimestamp == UNSET_TIMESTAMP_FLAG) {
            lastRecoveryModeTimestamp = uint128(block.timestamp);

            emit GracePeriodStart();
        }
    }

    /// @dev Checks that the system is not in RM
    function stopRMLiquidationCooldown() external {
        // Require we're in RM
        uint256 price = priceFeed.fetchPrice();
        bool isRecoveryMode = _checkRecoveryModeForTCR(_getTCR(price));
        require(!isRecoveryMode, "Grace Period can end only outside RM");

        _stopRMLiquidationCooldown();
    }

    function _stopRMLiquidationCooldown() internal {
        // Disarm the countdown
        if (lastRecoveryModeTimestamp != UNSET_TIMESTAMP_FLAG) {
            lastRecoveryModeTimestamp = UNSET_TIMESTAMP_FLAG;

            emit GracePeriodEnd();
        }
    }

    /// TODO: obv optimizations
    function checkLiquidateCoolDownAndReset() public {
        uint256 price = priceFeed.fetchPrice();
        uint256 tcr = _getTCR(price);
        bool isRecoveryMode = _checkRecoveryModeForTCR(tcr);

        emit TCRNotified(tcr);

        if (isRecoveryMode) {
            _beginRMLiquidationCooldown();
        } else {
            _stopRMLiquidationCooldown();
        }
    }

    string public constant NAME = "CdpManager";

    // --- Connected contract declarations ---

    address public immutable borrowerOperationsAddress;

    ICollSurplusPool immutable collSurplusPool;

    IEBTCToken public immutable override ebtcToken;

    address public immutable liquidationLibrary;

    // A doubly linked list of Cdps, sorted by their sorted by their collateral ratios
    ISortedCdps public immutable sortedCdps;

    // --- Data structures ---

    uint public constant SECONDS_IN_ONE_MINUTE = 60;

    uint public constant MIN_REDEMPTION_FEE_FLOOR = (DECIMAL_PRECISION * 5) / 1000; // 0.5%
    uint public redemptionFeeFloor = MIN_REDEMPTION_FEE_FLOOR;
    bool public redemptionsPaused;
    /*
     * Half-life of 12h. 12h = 720 min
     * (1/2) = d^720 => d = (1/2)^(1/720)
     */
    uint public minuteDecayFactor = 999037758833783000;
    uint public constant MIN_MINUTE_DECAY_FACTOR = 1; // Non-zero
    uint public constant MAX_MINUTE_DECAY_FACTOR = 999999999999999999; // Corresponds to a very fast decay rate, but not too extreme

    // During bootsrap period redemptions are not allowed
    uint public constant BOOTSTRAP_PERIOD = 14 days;

    uint internal immutable deploymentStartTime;

    /*
     * BETA: 18 digit decimal. Parameter by which to divide the redeemed fraction,
     * in order to calc the new base rate from a redemption.
     * Corresponds to (1 / ALPHA) in the white paper.
     */
    uint public beta = 2;

    uint public baseRate;

    uint public stakingRewardSplit;

    // The timestamp of the latest fee operation (redemption or new EBTC issuance)
    uint public lastFeeOperationTime;

    mapping(bytes32 => Cdp) public Cdps;

    uint public override totalStakes;

    // Snapshot of the value of totalStakes, taken immediately after the latest liquidation and split fee claim
    uint public totalStakesSnapshot;

    // Snapshot of the total collateral across the ActivePool, immediately after the latest liquidation and split fee claim
    uint public totalCollateralSnapshot;

    /*
     * L_EBTCDebt track the sums of accumulated liquidation rewards per unit staked.
     * During its lifetime, each stake earns:
     *
     * A EBTCDebt increase  of ( stake * [L_EBTCDebt - L_EBTCDebt(0)] )
     *
     * Where L_EBTCDebt(0) are snapshots of L_EBTCDebt
     * for the active Cdp taken at the instant the stake was made
     */
    uint public L_EBTCDebt;

    /* Global Index for (Full Price Per Share) of underlying collateral token */
    uint256 public override stFPPSg;
    /* Global Fee accumulator (never decreasing) per stake unit in CDPManager, similar to L_EBTCDebt */
    uint256 public override stFeePerUnitg;
    /* Global Fee accumulator calculation error due to integer division, similar to redistribution calculation */
    uint256 public override stFeePerUnitgError;
    /* Individual CDP Fee accumulator tracker, used to calculate fee split distribution */
    mapping(bytes32 => uint256) public stFeePerUnitcdp;
    /* Update timestamp for global index */
    uint256 lastIndexTimestamp;
    // Map active cdps to their RewardSnapshot (eBTC debt redistributed)
    mapping(bytes32 => uint) public rewardSnapshots;

    // Array of all active cdp Ids - used to to compute an approximate hint off-chain, for the sorted list insertion
    bytes32[] public CdpIds;

    // Error trackers for the cdp redistribution calculation
    uint public lastETHError_Redistribution;
    uint public lastEBTCDebtError_Redistribution;

    constructor(
        address _liquidationLibraryAddress,
        address _authorityAddress,
        address _borrowerOperationsAddress,
        address _collSurplusPool,
        address _ebtcToken,
        address _sortedCdps,
        address _activePool,
        address _priceFeed,
        address _collateral
    ) LiquityBase(_activePool, _priceFeed, _collateral) {
        // TODO: Move to setAddresses or _tickInterest?
        deploymentStartTime = block.timestamp;
        liquidationLibrary = _liquidationLibraryAddress;

        _initializeAuthority(_authorityAddress);

        borrowerOperationsAddress = _borrowerOperationsAddress;
        collSurplusPool = ICollSurplusPool(_collSurplusPool);
        ebtcToken = IEBTCToken(_ebtcToken);
        sortedCdps = ISortedCdps(_sortedCdps);

        emit LiquidationLibraryAddressChanged(_liquidationLibraryAddress);
    }

    /**
        @notice BorrowerOperations and CdpManager share reentrancy status by confirming the other's locked flag before beginning operation
        @dev This is an alternative to the more heavyweight solution of both being able to set the reentrancy flag on a 3rd contract.
     */
    modifier nonReentrantSelfAndBOps() {
        require(locked == OPEN, "CdpManager: Reentrancy in nonReentrant call");
        require(
            ReentrancyGuard(borrowerOperationsAddress).locked() == OPEN,
            "BorrowerOperations: Reentrancy in nonReentrant call"
        );

        locked = LOCKED;

        _;

        locked = OPEN;
    }

    function _closeCdp(bytes32 _cdpId, Status closedStatus) internal {
        _closeCdpWithoutRemovingSortedCdps(_cdpId, closedStatus);
        sortedCdps.remove(_cdpId);
    }

    function _closeCdpWithoutRemovingSortedCdps(bytes32 _cdpId, Status closedStatus) internal {
        require(
            closedStatus != Status.nonExistent && closedStatus != Status.active,
            "CdpManagerStorage: close non-exist or non-active CDP!"
        );

        uint CdpIdsArrayLength = CdpIds.length;
        _requireMoreThanOneCdpInSystem(CdpIdsArrayLength);

        Cdps[_cdpId].status = closedStatus;
        Cdps[_cdpId].coll = 0;
        Cdps[_cdpId].debt = 0;
        Cdps[_cdpId].liquidatorRewardShares = 0;

        rewardSnapshots[_cdpId] = 0;
        stFeePerUnitcdp[_cdpId] = 0;

        _removeCdp(_cdpId, CdpIdsArrayLength);
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
    function _updateSystemSnapshots_excludeCollRemainder(uint _collRemainder) internal {
        uint _totalStakesSnapshot = totalStakes;
        totalStakesSnapshot = _totalStakesSnapshot;

        uint _totalCollateralSnapshot = activePool.getStEthColl() - _collRemainder;
        totalCollateralSnapshot = _totalCollateralSnapshot;

        emit SystemSnapshotsUpdated(_totalStakesSnapshot, _totalCollateralSnapshot);
    }

    /**
    get the pending Cdp debt "reward" (i.e. the amount of extra debt assigned to the Cdp) from liquidation redistribution events, earned by their stake
    */
    function _getRedistributedEBTCDebt(
        bytes32 _cdpId
    ) internal view returns (uint pendingEBTCDebtReward) {
        Cdp storage cdp = Cdps[_cdpId];

        if (cdp.status != Status.active) {
            return 0;
        }

        uint rewardPerUnitStaked = L_EBTCDebt - rewardSnapshots[_cdpId];

        if (rewardPerUnitStaked > 0) {
            pendingEBTCDebtReward = (cdp.stake * rewardPerUnitStaked) / DECIMAL_PRECISION;
        }
    }

    function _hasRedistributedDebt(bytes32 _cdpId) internal view returns (bool) {
        /*
         * A Cdp has pending rewards if its snapshot is less than the current rewards per-unit-staked sum:
         * this indicates that rewards have occured since the snapshot was made, and the user therefore has
         * pending rewards
         */
        if (Cdps[_cdpId].status != Status.active) {
            return false;
        }

        // Returns true if there have been any redemptions
        return (rewardSnapshots[_cdpId] < L_EBTCDebt);
    }

    function _updateRedistributedDebtSnapshot(bytes32 _cdpId) internal {
        uint _L_EBTCDebt = L_EBTCDebt;

        rewardSnapshots[_cdpId] = _L_EBTCDebt;
        emit CdpSnapshotsUpdated(_cdpId, _L_EBTCDebt);
    }

    // Add the borrowers's coll and debt rewards earned from redistributions, to their Cdp
    function _applyPendingState(bytes32 _cdpId) internal {
        _applyAccumulatedFeeSplit(_cdpId);

        // Compute pending rewards
        uint pendingEBTCDebtReward = _getRedistributedEBTCDebt(_cdpId);
        if (pendingEBTCDebtReward > 0) {
            Cdp storage _cdp = Cdps[_cdpId];
            uint prevDebt = _cdp.debt;
            uint prevColl = _cdp.coll;

            // Apply pending rewards to cdp's state
            uint _newDebt = prevDebt + pendingEBTCDebtReward;
            _cdp.debt = _newDebt;

            _updateRedistributedDebtSnapshot(_cdpId);

            address _borrower = ISortedCdps(sortedCdps).getOwnerAddress(_cdpId);
            emit CdpUpdated(
                _cdpId,
                _borrower,
                prevDebt,
                prevColl,
                _newDebt,
                prevColl,
                Cdps[_cdpId].stake,
                CdpOperation.applyPendingState
            );
        }
    }

    // Remove borrower's stake from the totalStakes sum, and set their stake to 0
    function _removeStake(bytes32 _cdpId) internal {
        uint _newTotalStakes = totalStakes - Cdps[_cdpId].stake;
        totalStakes = _newTotalStakes;
        Cdps[_cdpId].stake = 0;
        emit TotalStakesUpdated(_newTotalStakes);
    }

    // Update borrower's stake based on their latest collateral value
    // and update totalStakes accordingly as well
    function _updateStakeAndTotalStakes(bytes32 _cdpId) internal returns (uint) {
        (uint newStake, uint oldStake) = _updateStakeForCdp(_cdpId);

        uint _newTotalStakes = totalStakes + newStake - oldStake;
        totalStakes = _newTotalStakes;

        emit TotalStakesUpdated(_newTotalStakes);

        return newStake;
    }

    // Update borrower's stake based on their latest collateral value
    function _updateStakeForCdp(bytes32 _cdpId) internal returns (uint, uint) {
        Cdp storage _cdp = Cdps[_cdpId];
        uint newStake = _computeNewStake(_cdp.coll);
        uint oldStake = _cdp.stake;
        _cdp.stake = newStake;

        return (newStake, oldStake);
    }

    // Calculate a new stake based on the snapshots of the totalStakes and totalCollateral taken at the last liquidation
    function _computeNewStake(uint _coll) internal view returns (uint) {
        uint stake;
        if (totalCollateralSnapshot == 0) {
            stake = _coll;
        } else {
            /*
             * The following check holds true because:
             * - The system always contains >= 1 cdp
             * - When we close or liquidate a cdp, we redistribute the pending rewards,
             * so if all cdps were closed/liquidated,
             * rewards would’ve been emptied and totalCollateralSnapshot would be zero too.
             */
            require(totalStakesSnapshot > 0, "CdpManagerStorage: zero totalStakesSnapshot!");
            stake = (_coll * totalStakesSnapshot) / totalCollateralSnapshot;
        }
        return stake;
    }

    /*
     * Remove a Cdp owner from the CdpOwners array, not preserving array order. Removing owner 'B' does the following:
     * [A B C D E] => [A E C D], and updates E's Cdp struct to point to its new array index.
     */
    function _removeCdp(bytes32 _cdpId, uint CdpIdsArrayLength) internal {
        Status cdpStatus = Cdps[_cdpId].status;
        // It’s set in caller function `_closeCdp`
        require(
            cdpStatus != Status.nonExistent && cdpStatus != Status.active,
            "CdpManagerStorage: remove non-exist or non-active CDP!"
        );

        uint128 index = Cdps[_cdpId].arrayIndex;
        uint length = CdpIdsArrayLength;
        uint idxLast = length - 1;

        require(index <= idxLast, "CdpManagerStorage: CDP indexing overflow!");

        bytes32 idToMove = CdpIds[idxLast];

        CdpIds[index] = idToMove;
        Cdps[idToMove].arrayIndex = index;
        emit CdpIndexUpdated(idToMove, index);

        CdpIds.pop();
    }

    // --- Recovery Mode and TCR functions ---

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
    /// @dev BO can call this without trigggering a
    function applyPendingGlobalState() external {
        _requireCallerIsBorrowerOperations();
        _applyPendingGlobalState();
    }

    function _applyPendingGlobalState() internal {
        (uint _oldIndex, uint _newIndex) = _syncIndex();
        if (_newIndex > _oldIndex && totalStakes > 0) {
            (uint _feeTaken, uint _deltaFeePerUnit, uint _perUnitError) = calcFeeUponStakingReward(
                _newIndex,
                _oldIndex
            );
            _takeSplitAndUpdateFeePerUnit(_feeTaken, _deltaFeePerUnit, _perUnitError);
            _updateSystemSnapshots_excludeCollRemainder(0);
        }
    }

    /// @notice Claim Fee Split, toggles Grace Period accordingly
    /// @notice Call this if you want to accrue feeSplit
    function syncPendingGlobalState() public {
        _applyPendingGlobalState(); // Apply // Could trigger RM
        checkLiquidateCoolDownAndReset(); // Synch Grace Period
    }

    // Update the global index via collateral token
    function _syncIndex() internal returns (uint, uint) {
        uint _oldIndex = stFPPSg;
        uint _newIndex = collateral.getPooledEthByShares(DECIMAL_PRECISION);
        if (_newIndex != _oldIndex) {
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
    ) public view returns (uint256, uint256, uint256) {
        require(_newIndex > _prevIndex, "CDPManager: only take fee with bigger new index");
        uint256 deltaIndex = _newIndex - _prevIndex;
        uint256 deltaIndexFees = (deltaIndex * stakingRewardSplit) / MAX_REWARD_SPLIT;

        // we take the fee for all CDPs immediately which is scaled by index precision
        uint256 _deltaFeeSplit = deltaIndexFees * getEntireSystemColl();
        uint256 _cachedAllStakes = totalStakes;
        // return the values to update the global fee accumulator
        uint256 _feeTaken = collateral.getSharesByPooledEth(_deltaFeeSplit) / DECIMAL_PRECISION;
        uint256 _deltaFeeSplitShare = (_feeTaken * DECIMAL_PRECISION) + stFeePerUnitgError;
        uint256 _deltaFeePerUnit = _deltaFeeSplitShare / _cachedAllStakes;
        uint256 _perUnitError = _deltaFeeSplitShare - (_deltaFeePerUnit * _cachedAllStakes);
        return (_feeTaken, _deltaFeePerUnit, _perUnitError);
    }

    // Take the cut from staking reward
    // and update global fee-per-unit accumulator
    function _takeSplitAndUpdateFeePerUnit(
        uint256 _feeTaken,
        uint256 _deltaPerUnit,
        uint256 _newErrorPerUnit
    ) internal {
        uint _oldPerUnit = stFeePerUnitg;
        uint _newPerUnit = _oldPerUnit + _deltaPerUnit;

        stFeePerUnitg = _newPerUnit;
        stFeePerUnitgError = _newErrorPerUnit;

        require(activePool.getStEthColl() > _feeTaken, "CDPManager: fee split is too big");
        activePool.allocateFeeRecipientColl(_feeTaken);

        emit CollateralFeePerUnitUpdated(_oldPerUnit, _newPerUnit, _feeTaken);
    }

    // Apply accumulated fee split distributed to the CDP
    // and update its accumulator tracker accordingly
    function _applyAccumulatedFeeSplit(bytes32 _cdpId) internal {
        // TODO Ensure global states like stFeePerUnitg get timely updated
        // whenever there is a CDP modification operation,
        // such as opening, closing, adding collateral, repaying debt, or liquidating
        // OR Should we utilize some bot-keeper to work the routine job at fixed interval?
        _applyPendingGlobalState();

        uint _oldPerUnitCdp = stFeePerUnitcdp[_cdpId];
        uint _stFeePerUnitg = stFeePerUnitg;

        if (_oldPerUnitCdp == _stFeePerUnitg) {
            // @audit this case is much more frequent, so can be handled first
            return;
        }

        if (_oldPerUnitCdp == 0) {
            stFeePerUnitcdp[_cdpId] = _stFeePerUnitg;
            return;
        }

        (uint _feeSplitDistributed, uint _newColl) = getAccumulatedFeeSplitApplied(
            _cdpId,
            _stFeePerUnitg
        );
        Cdps[_cdpId].coll = _newColl;
        stFeePerUnitcdp[_cdpId] = _stFeePerUnitg;

        emit CdpFeeSplitApplied(
            _cdpId,
            _oldPerUnitCdp,
            _stFeePerUnitg,
            _feeSplitDistributed,
            _newColl
        );
    }

    // return the applied split fee(scaled by 1e18) and the resulting CDP collateral amount after applied
    function getAccumulatedFeeSplitApplied(
        bytes32 _cdpId,
        uint _stFeePerUnitg
    ) public view returns (uint, uint) {
        uint _stFeePerUnitcdp = stFeePerUnitcdp[_cdpId];
        uint _cdpCol = Cdps[_cdpId].coll;

        if (_stFeePerUnitcdp == 0 || _cdpCol == 0 || _stFeePerUnitcdp == _stFeePerUnitg) {
            return (0, _cdpCol);
        }

        uint _feeSplitDistributed = Cdps[_cdpId].stake * (_stFeePerUnitg - _stFeePerUnitcdp);

        uint _scaledCdpColl = _cdpCol * DECIMAL_PRECISION;

        if (_scaledCdpColl > _feeSplitDistributed) {
            return (
                _feeSplitDistributed,
                (_scaledCdpColl - _feeSplitDistributed) / DECIMAL_PRECISION
            );
        } else {
            // extreme unlikely case to skip fee split on this CDP to avoid revert
            return (0, _cdpCol);
        }
    }

    // -- Modifier functions --
    function _requireCdpIsActive(bytes32 _cdpId) internal view {
        require(Cdps[_cdpId].status == Status.active, "CdpManager: Cdp does not exist or is closed");
    }

    function _requireMoreThanOneCdpInSystem(uint CdpOwnersArrayLength) internal view {
        require(
            CdpOwnersArrayLength > 1 && sortedCdps.getSize() > 1,
            "CdpManager: Only one cdp in the system"
        );
    }

    function _requireCallerIsBorrowerOperations() internal view {
        require(
            msg.sender == borrowerOperationsAddress,
            "CdpManager: Caller is not the BorrowerOperations contract"
        );
    }

    // --- Helper functions ---

    // Return the nominal collateral ratio (ICR) of a given Cdp, without the price.
    // Takes a cdp's pending coll and debt rewards from redistributions into account.
    function getNominalICR(bytes32 _cdpId) external view returns (uint) {
        (uint currentEBTCDebt, uint currentETH, ) = getEntireDebtAndColl(_cdpId);

        uint NICR = LiquityMath._computeNominalCR(currentETH, currentEBTCDebt);
        return NICR;
    }

    // Return the current collateral ratio (ICR) of a given Cdp.
    //Takes a cdp's pending coll and debt rewards from redistributions into account.
    function getCurrentICR(bytes32 _cdpId, uint _price) public view returns (uint) {
        (uint currentEBTCDebt, uint currentETH, ) = getEntireDebtAndColl(_cdpId);

        uint _underlyingCollateral = collateral.getPooledEthByShares(currentETH);
        uint ICR = LiquityMath._computeCR(_underlyingCollateral, currentEBTCDebt, _price);
        return ICR;
    }

    /**
    get the pending Cdp debt "reward" (i.e. the amount of extra debt assigned to the Cdp) from liquidation redistribution events, earned by their stake
    */
    function getPendingEBTCDebtReward(
        bytes32 _cdpId
    ) public view returns (uint pendingEBTCDebtReward) {
        return _getRedistributedEBTCDebt(_cdpId);
    }

    function hasPendingRewards(bytes32 _cdpId) public view returns (bool) {
        return _hasRedistributedDebt(_cdpId);
    }

    // Return the Cdps entire debt and coll struct
    function _getEntireDebtAndColl(
        bytes32 _cdpId
    ) internal view returns (LocalVar_CdpDebtColl memory) {
        (uint256 entireDebt, uint256 entireColl, uint pendingDebtReward) = getEntireDebtAndColl(
            _cdpId
        );
        return LocalVar_CdpDebtColl(entireDebt, entireColl, pendingDebtReward);
    }

    // Return the Cdps entire debt and coll, including pending rewards from redistributions and collateral reduction from split fee.
    /// @notice pending rewards are included in the debt and coll totals returned.
    function getEntireDebtAndColl(
        bytes32 _cdpId
    ) public view returns (uint debt, uint coll, uint pendingEBTCDebtReward) {
        debt = Cdps[_cdpId].debt;
        (, uint _newColl) = getAccumulatedFeeSplitApplied(_cdpId, stFeePerUnitg);
        coll = _newColl;

        pendingEBTCDebtReward = getPendingEBTCDebtReward(_cdpId);

        debt = debt + pendingEBTCDebtReward;
    }
}
