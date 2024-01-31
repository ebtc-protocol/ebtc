// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./Interfaces/ICdpManager.sol";
import "./Interfaces/ICollSurplusPool.sol";
import "./Interfaces/IEBTCToken.sol";
import "./Interfaces/ISortedCdps.sol";
import "./Dependencies/EbtcBase.sol";
import "./Dependencies/ReentrancyGuard.sol";
import "./Dependencies/ICollateralTokenOracle.sol";
import "./Dependencies/AuthNoOwner.sol";

/// @title CDP Manager storage and shared functions with LiquidationLibrary
/// @dev All features around Cdp management are split into separate parts to get around contract size limitations.
/// @dev Liquidation related functions are delegated to LiquidationLibrary contract code.
/// @dev Both CdpManager and LiquidationLibrary must maintain **the same storage layout**, so shared storage components
/// @dev and shared functions are added here in CdpManagerStorage to de-dup code
contract CdpManagerStorage is EbtcBase, ReentrancyGuard, ICdpManagerData, AuthNoOwner {
    // NOTE: No packing cause it's the last var, no need for u64
    uint128 public constant UNSET_TIMESTAMP = type(uint128).max;
    uint128 public constant MINIMUM_GRACE_PERIOD = 15 minutes;

    uint128 public lastGracePeriodStartTimestamp = UNSET_TIMESTAMP; // use max to signify
    uint128 public recoveryModeGracePeriodDuration = MINIMUM_GRACE_PERIOD;

    /// @notice Start the recovery mode grace period, if the system is in RM and the grace period timestamp has not already been set
    /// @dev Trusted function to allow BorrowerOperations actions to set RM Grace Period
    /// @dev Assumes BorrowerOperations has correctly calculated and passed in the new system TCR
    /// @dev To maintain CEI compliance we use this trusted function
    /// @param tcr The TCR to be checked whether Grace Period should be started
    function notifyStartGracePeriod(uint256 tcr) external {
        _requireCallerIsBorrowerOperations();
        _startGracePeriod(tcr);
    }

    /// @notice End the recovery mode grace period, if the system is no longer in RM
    /// @dev Trusted function to allow BorrowerOperations actions to set RM Grace Period
    /// @dev Assumes BorrowerOperations has correctly calculated and passed in the new system TCR
    /// @dev To maintain CEI compliance we use this trusted function
    /// @param tcr The TCR to be checked whether Grace Period should be ended
    function notifyEndGracePeriod(uint256 tcr) external {
        _requireCallerIsBorrowerOperations();
        _endGracePeriod(tcr);
    }

    /// @dev Internal notify called by Redemptions and Liquidations
    /// @dev Specified TCR is emitted for notification pruposes regardless of whether the Grace Period timestamp is set
    function _startGracePeriod(uint256 _tcr) internal {
        emit TCRNotified(_tcr);

        if (lastGracePeriodStartTimestamp == UNSET_TIMESTAMP) {
            lastGracePeriodStartTimestamp = uint128(block.timestamp);

            emit GracePeriodStart();
        }
    }

    /// @notice Clear RM Grace Period timestamp if it has been set
    /// @notice No input validation, calling function must confirm that the system is not in recovery mode to be valid
    /// @dev Specified TCR is emitted for notification pruposes regardless of whether the Grace Period timestamp is set
    /// @dev Internal notify called by Redemptions and Liquidations
    function _endGracePeriod(uint256 _tcr) internal {
        emit TCRNotified(_tcr);

        if (lastGracePeriodStartTimestamp != UNSET_TIMESTAMP) {
            lastGracePeriodStartTimestamp = UNSET_TIMESTAMP;

            emit GracePeriodEnd();
        }
    }

    function _syncGracePeriod() internal {
        uint256 price = priceFeed.fetchPrice();
        uint256 tcr = _getCachedTCR(price);
        bool isRecoveryMode = _checkRecoveryModeForTCR(tcr);

        if (isRecoveryMode) {
            _startGracePeriod(tcr);
        } else {
            _endGracePeriod(tcr);
        }
    }

    /// @dev Set RM grace period based on specified system collShares, system debt, and price
    /// @dev Variant for internal use in redemptions and liquidations
    function _syncGracePeriodForGivenValues(
        uint256 systemCollShares,
        uint256 systemDebt,
        uint256 price
    ) internal {
        // Compute TCR with specified values
        uint256 newTCR = EbtcMath._computeCR(
            collateral.getPooledEthByShares(systemCollShares),
            systemDebt,
            price
        );

        if (newTCR < CCR) {
            // Notify system is in RM
            _startGracePeriod(newTCR);
        } else {
            // Notify system is outside RM
            _endGracePeriod(newTCR);
        }
    }

    /// @notice Set grace period duratin
    /// @notice Permissioned governance function, must set grace period duration above hardcoded minimum
    /// @param _gracePeriod new grace period duration, in seconds
    function setGracePeriod(uint128 _gracePeriod) external requiresAuth {
        require(
            _gracePeriod >= MINIMUM_GRACE_PERIOD,
            "CdpManager: Grace period below minimum duration"
        );

        syncGlobalAccountingAndGracePeriod();
        recoveryModeGracePeriodDuration = _gracePeriod;
        emit GracePeriodDurationSet(_gracePeriod);
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

    uint256 public constant SECONDS_IN_ONE_MINUTE = 60;

    uint256 public constant MIN_REDEMPTION_FEE_FLOOR = (DECIMAL_PRECISION * 5) / 1000; // 0.5%
    uint256 public redemptionFeeFloor = MIN_REDEMPTION_FEE_FLOOR;
    bool public redemptionsPaused;
    /*
     * Half-life of 12h. 12h = 720 min
     * (1/2) = d^720 => d = (1/2)^(1/720)
     */
    uint256 public minuteDecayFactor = 999037758833783000;
    uint256 public constant MIN_MINUTE_DECAY_FACTOR = 1; // Non-zero
    uint256 public constant MAX_MINUTE_DECAY_FACTOR = 999999999999999999; // Corresponds to a very fast decay rate, but not too extreme

    uint256 internal immutable deploymentStartTime;

    /*
     * BETA: 18 digit decimal. Parameter by which to divide the redeemed fraction,
     * in order to calc the new base rate from a redemption.
     * Corresponds to (1 / ALPHA) in the Liquity white paper.
     */
    uint256 public beta = 2;

    uint256 public baseRate;

    uint256 public stakingRewardSplit;

    // The timestamp of the latest fee operation (redemption or new EBTC issuance)
    uint256 public lastRedemptionTimestamp;

    mapping(bytes32 => Cdp) public Cdps;

    uint256 public override totalStakes;

    // Snapshot of the value of totalStakes, taken immediately after the latest liquidation and split fee claim
    uint256 public totalStakesSnapshot;

    // Snapshot of the total collateral across the ActivePool, immediately after the latest liquidation and split fee claim
    uint256 public totalCollateralSnapshot;

    /*
     * systemDebtRedistributionIndex track the sums of accumulated socialized liquidations per unit staked.
     * During its lifetime, each stake earns:
     *
     * A systemDebt increase  of ( stake * [systemDebtRedistributionIndex - systemDebtRedistributionIndex(0)] )
     *
     * Where systemDebtRedistributionIndex(0) are snapshots of systemDebtRedistributionIndex
     * for the active Cdp taken at the instant the stake was made
     */
    uint256 public systemDebtRedistributionIndex;

    // Map active cdps to their RewardSnapshot (eBTC debt redistributed)
    mapping(bytes32 => uint256) public cdpDebtRedistributionIndex;

    // Error trackers for the cdp redistribution calculation
    uint256 public lastEBTCDebtErrorRedistribution;

    /* Global Index for (Full Price Per Share) of underlying collateral token */
    uint256 public override stEthIndex;
    /* Global Fee accumulator (never decreasing) per stake unit in CDPManager, similar to systemDebtRedistributionIndex */
    uint256 public override systemStEthFeePerUnitIndex;
    /* Global Fee accumulator calculation error due to integer division, similar to redistribution calculation */
    uint256 public override systemStEthFeePerUnitIndexError;
    /* Individual CDP Fee accumulator tracker, used to calculate fee split distribution */
    mapping(bytes32 => uint256) public cdpStEthFeePerUnitIndex;

    /// @notice Initializes the contract with the provided addresses and sets up the required initial state
    /// @param _liquidationLibraryAddress The address of the Liquidation Library
    /// @param _authorityAddress The address of the Authority
    /// @param _borrowerOperationsAddress The address of Borrower Operations
    /// @param _collSurplusPool The address of the Collateral Surplus Pool
    /// @param _ebtcToken The address of the eBTC Token contract
    /// @param _sortedCdps The address of the Sorted CDPs contract
    /// @param _activePool The address of the Active Pool
    /// @param _priceFeed The address of the Price Feed
    /// @param _collateral The address of the Collateral token
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
    ) EbtcBase(_activePool, _priceFeed, _collateral) {
        deploymentStartTime = block.timestamp;
        liquidationLibrary = _liquidationLibraryAddress;

        _initializeAuthority(_authorityAddress);

        borrowerOperationsAddress = _borrowerOperationsAddress;
        collSurplusPool = ICollSurplusPool(_collSurplusPool);
        ebtcToken = IEBTCToken(_ebtcToken);
        sortedCdps = ISortedCdps(_sortedCdps);
    }

    /// @notice BorrowerOperations and CdpManager share reentrancy status by confirming the other's locked flag before beginning operation
    /// @dev This is an alternative to the more heavyweight solution of both being able to set the reentrancy flag on a 3rd contract.
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

        uint256 cdpIdsArrayLength = getActiveCdpsCount();
        _requireMoreThanOneCdpInSystem(cdpIdsArrayLength);

        _removeStake(_cdpId);

        Cdps[_cdpId].status = closedStatus;
        Cdps[_cdpId].coll = 0;
        Cdps[_cdpId].debt = 0;
        Cdps[_cdpId].liquidatorRewardShares = 0;

        cdpDebtRedistributionIndex[_cdpId] = 0;
        cdpStEthFeePerUnitIndex[_cdpId] = 0;
    }

    /*
     * Updates snapshots of system total stakes and total collateral,
     * excluding a given collateral remainder from the calculation.
     * Used in a liquidation sequence.
     *
     * The calculation excludes a portion of collateral that is in the ActivePool:
     *
     * the total stETH liquidator reward compensation from the liquidation sequence
     *
     * The stETH as compensation must be excluded as it is always sent out at the very end of the liquidation sequence.
     */
    function _updateSystemSnapshotsExcludeCollRemainder(uint256 _collRemainder) internal {
        uint256 _totalStakesSnapshot = totalStakes;
        totalStakesSnapshot = _totalStakesSnapshot;

        uint256 _totalCollateralSnapshot = activePool.getSystemCollShares() - _collRemainder;
        totalCollateralSnapshot = _totalCollateralSnapshot;

        emit SystemSnapshotsUpdated(_totalStakesSnapshot, _totalCollateralSnapshot);
    }

    /// @dev get the pending Cdp debt "reward" (i.e. the amount of extra debt assigned to the Cdp) from liquidation redistribution events, earned by their stake
    function _getPendingRedistributedDebt(
        bytes32 _cdpId
    ) internal view returns (uint256 pendingEBTCDebtReward, uint256 _debtIndexDiff) {
        Cdp storage cdp = Cdps[_cdpId];

        if (cdp.status != Status.active) {
            return (0, 0);
        }

        _debtIndexDiff = systemDebtRedistributionIndex - cdpDebtRedistributionIndex[_cdpId];

        if (_debtIndexDiff > 0) {
            pendingEBTCDebtReward = (cdp.stake * _debtIndexDiff) / DECIMAL_PRECISION;
        } else {
            return (0, 0);
        }
    }

    /*
     * A Cdp has pending redistributed debt if its snapshot is less than the current rewards per-unit-staked sum:
     * this indicates that redistributions have occured since the snapshot was made, and the user therefore has
     * pending debt
     */
    function _hasRedistributedDebt(bytes32 _cdpId) internal view returns (bool) {
        if (Cdps[_cdpId].status != Status.active) {
            return false;
        }

        return (cdpDebtRedistributionIndex[_cdpId] < systemDebtRedistributionIndex);
    }

    /// @dev Sync Cdp debt redistribution index to global value
    function _updateRedistributedDebtIndex(bytes32 _cdpId) internal {
        uint256 _systemDebtRedistributionIndex = systemDebtRedistributionIndex;

        cdpDebtRedistributionIndex[_cdpId] = _systemDebtRedistributionIndex;
        emit CdpDebtRedistributionIndexUpdated(_cdpId, _systemDebtRedistributionIndex);
    }

    /// @dev Calculate the new collateral and debt values for a given CDP, based on pending state changes
    function _syncAccounting(bytes32 _cdpId) internal {
        // Ensure global states like systemStEthFeePerUnitIndex get updated in a timely fashion
        // whenever there is a CDP modification operation,
        // such as opening, closing, adding collateral, repaying debt, or liquidating
        _syncGlobalAccounting();

        uint256 _oldPerUnitCdp = cdpStEthFeePerUnitIndex[_cdpId];
        uint256 _systemStEthFeePerUnitIndex = systemStEthFeePerUnitIndex;

        (
            uint256 _newColl,
            uint256 _newDebt,
            uint256 _feeSplitDistributed,
            uint _pendingDebt,
            uint256 _debtIndexDelta
        ) = _calcSyncedAccounting(_cdpId, _oldPerUnitCdp, _systemStEthFeePerUnitIndex);

        // If any collShares or debt changes occured
        if (_feeSplitDistributed > 0 || _debtIndexDelta > 0) {
            Cdp storage _cdp = Cdps[_cdpId];

            uint prevCollShares = _cdp.coll;
            uint256 prevDebt = _cdp.debt;

            // Apply Fee Split
            if (_feeSplitDistributed > 0) {
                _applyAccumulatedFeeSplit(
                    _cdpId,
                    _newColl,
                    _feeSplitDistributed,
                    _oldPerUnitCdp,
                    _systemStEthFeePerUnitIndex
                );
            }

            // Apply Debt Redistribution
            if (_debtIndexDelta > 0) {
                _updateRedistributedDebtIndex(_cdpId);

                if (prevDebt != _newDebt) {
                    {
                        // Apply pending debt redistribution to this CDP
                        _cdp.debt = _newDebt;
                    }
                }
            }
            emit CdpUpdated(
                _cdpId,
                ISortedCdps(sortedCdps).getOwnerAddress(_cdpId),
                msg.sender,
                prevDebt,
                prevCollShares,
                _newDebt,
                _newColl,
                _cdp.stake,
                CdpOperation.syncAccounting
            );
        }

        // sync per stake index for given CDP
        if (_oldPerUnitCdp != _systemStEthFeePerUnitIndex) {
            cdpStEthFeePerUnitIndex[_cdpId] = _systemStEthFeePerUnitIndex;
        }
    }

    // Remove borrower's stake from the totalStakes sum, and set their stake to 0
    function _removeStake(bytes32 _cdpId) internal {
        uint256 _newTotalStakes = totalStakes - Cdps[_cdpId].stake;
        totalStakes = _newTotalStakes;
        Cdps[_cdpId].stake = 0;
        emit TotalStakesUpdated(_newTotalStakes);
    }

    // Update borrower's stake based on their latest collateral value
    // and update totalStakes accordingly as well
    function _updateStakeAndTotalStakes(bytes32 _cdpId) internal returns (uint256) {
        (uint256 newStake, uint256 oldStake) = _updateStakeForCdp(_cdpId);

        uint256 _newTotalStakes = totalStakes + newStake - oldStake;
        totalStakes = _newTotalStakes;

        emit TotalStakesUpdated(_newTotalStakes);

        return newStake;
    }

    // Update borrower's stake based on their latest collateral value
    function _updateStakeForCdp(bytes32 _cdpId) internal returns (uint256, uint256) {
        Cdp storage _cdp = Cdps[_cdpId];
        uint256 newStake = _computeNewStake(_cdp.coll);
        uint256 oldStake = _cdp.stake;
        _cdp.stake = newStake;

        return (newStake, oldStake);
    }

    // Calculate a new stake based on the snapshots of the totalStakes and totalCollateral taken at the last liquidation
    function _computeNewStake(uint256 _coll) internal view returns (uint256) {
        uint256 stake;
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

    // --- Recovery Mode and TCR functions ---

    // Calculate TCR given an price, and the entire system coll and debt.
    function _computeTCRWithGivenSystemValues(
        uint256 _systemCollShares,
        uint256 _systemDebt,
        uint256 _price
    ) internal view returns (uint256) {
        uint256 _totalColl = collateral.getPooledEthByShares(_systemCollShares);
        return EbtcMath._computeCR(_totalColl, _systemDebt, _price);
    }

    // --- Staking-Reward Fee split functions ---

    /// @notice Claim split fee if there is staking-reward coming
    /// @notice and update global index & fee-per-unit variables
    /// @dev only BorrowerOperations is allowed to call this
    /// @dev otherwise use syncGlobalAccountingAndGracePeriod()
    function syncGlobalAccounting() external {
        _requireCallerIsBorrowerOperations();
        _syncGlobalAccounting();
    }

    function _syncGlobalAccounting() internal {
        (uint256 _oldIndex, uint256 _newIndex) = _readStEthIndex();
        _syncStEthIndex(_oldIndex, _newIndex);
        if (_newIndex > _oldIndex && totalStakes > 0) {
            (
                uint256 _feeTaken,
                uint256 _newFeePerUnit,
                uint256 _perUnitError
            ) = _calcSyncedGlobalAccounting(_newIndex, _oldIndex);
            _takeSplitAndUpdateFeePerUnit(_feeTaken, _newFeePerUnit, _perUnitError);
            _updateSystemSnapshotsExcludeCollRemainder(0);
        }
    }

    /// @notice Claim fee split, if there is staking-reward coming
    /// @notice and update global index & fee-per-unit variables
    /// @notice and toggles Grace Period accordingly.
    /// @dev Call this if you want to help eBTC system to accrue split fee
    function syncGlobalAccountingAndGracePeriod() public {
        _syncGlobalAccounting(); // Apply // Could trigger RM
        _syncGracePeriod(); // Synch Grace Period
    }

    /// @return existing(old) local stETH index AND
    /// @return current(new) stETH index from collateral token
    function _readStEthIndex() internal view returns (uint256, uint256) {
        return (stEthIndex, collateral.getPooledEthByShares(DECIMAL_PRECISION));
    }

    // Update the global index via collateral token
    function _syncStEthIndex(uint256 _oldIndex, uint256 _newIndex) internal {
        if (_newIndex != _oldIndex) {
            stEthIndex = _newIndex;
            emit StEthIndexUpdated(_oldIndex, _newIndex, block.timestamp);
        }
    }

    /// @notice Calculate fee for given pair of collateral indexes
    /// @param _newIndex The value synced with stETH.getPooledEthByShares(1e18)
    /// @param _prevIndex The cached global value of `stEthIndex`
    /// @return _feeTaken The fee split in collateral token which will be deduced from current total system collateral
    /// @return _deltaFeePerUnit The fee split increase per unit, used to added to `systemStEthFeePerUnitIndex`
    /// @return _perUnitError The fee split calculation error, used to update `systemStEthFeePerUnitIndexError`
    function calcFeeUponStakingReward(
        uint256 _newIndex,
        uint256 _prevIndex
    ) public view returns (uint256, uint256, uint256) {
        require(_newIndex > _prevIndex, "CDPManager: only take fee with bigger new index");
        uint256 deltaIndex = _newIndex - _prevIndex;
        uint256 deltaIndexFees = (deltaIndex * stakingRewardSplit) / MAX_REWARD_SPLIT;

        // we take the fee for all CDPs immediately which is scaled by index precision
        uint256 _deltaFeeSplit = deltaIndexFees * getSystemCollShares();
        uint256 _cachedAllStakes = totalStakes;
        // return the values to update the global fee accumulator
        uint256 _feeTaken = collateral.getSharesByPooledEth(_deltaFeeSplit) / DECIMAL_PRECISION;
        uint256 _deltaFeeSplitShare = (_feeTaken * DECIMAL_PRECISION) +
            systemStEthFeePerUnitIndexError;
        uint256 _deltaFeePerUnit = _deltaFeeSplitShare / _cachedAllStakes;
        uint256 _perUnitError = _deltaFeeSplitShare - (_deltaFeePerUnit * _cachedAllStakes);
        return (_feeTaken, _deltaFeePerUnit, _perUnitError);
    }

    // Take the cut from staking reward
    // and update global fee-per-unit accumulator
    function _takeSplitAndUpdateFeePerUnit(
        uint256 _feeTaken,
        uint256 _newPerUnit,
        uint256 _newErrorPerUnit
    ) internal {
        uint256 _oldPerUnit = systemStEthFeePerUnitIndex;

        systemStEthFeePerUnitIndex = _newPerUnit;
        systemStEthFeePerUnitIndexError = _newErrorPerUnit;

        require(activePool.getSystemCollShares() > _feeTaken, "CDPManager: fee split is too big");
        activePool.allocateSystemCollSharesToFeeRecipient(_feeTaken);

        emit CollateralFeePerUnitUpdated(_oldPerUnit, _newPerUnit, _feeTaken);
    }

    // Apply accumulated fee split distributed to the CDP
    // and update its accumulator tracker accordingly
    function _applyAccumulatedFeeSplit(
        bytes32 _cdpId,
        uint256 _newColl,
        uint256 _feeSplitDistributed,
        uint256 _oldPerUnitCdp,
        uint256 _systemStEthFeePerUnitIndex
    ) internal {
        // apply split fee to given CDP
        Cdps[_cdpId].coll = _newColl;

        emit CdpFeeSplitApplied(
            _cdpId,
            _oldPerUnitCdp,
            _systemStEthFeePerUnitIndex,
            _feeSplitDistributed,
            _newColl
        );
    }

    /// @notice Calculate the applied split fee(scaled by 1e18) and the resulting CDP collateral share after applied
    /// @param _cdpId The Cdp to which the calculated split fee is going to be applied
    /// @param _systemStEthFeePerUnitIndex The fee-per-stake-unit value to be used in fee split calculation, could be result of calcFeeUponStakingReward()
    /// @return _feeSplitDistributed The applied fee split to the specified Cdp (scaled up by 1e18)
    /// @return _cdpCol The new collateral share of the specified Cdp after fe split applied
    function getAccumulatedFeeSplitApplied(
        bytes32 _cdpId,
        uint256 _systemStEthFeePerUnitIndex
    ) public view returns (uint256, uint256) {
        uint256 _cdpStEthFeePerUnitIndex = cdpStEthFeePerUnitIndex[_cdpId];
        uint256 _cdpCol = Cdps[_cdpId].coll;

        if (
            _cdpStEthFeePerUnitIndex == 0 ||
            _cdpCol == 0 ||
            _cdpStEthFeePerUnitIndex == _systemStEthFeePerUnitIndex
        ) {
            return (0, _cdpCol);
        }

        uint256 _feeSplitDistributed = Cdps[_cdpId].stake *
            (_systemStEthFeePerUnitIndex - _cdpStEthFeePerUnitIndex);

        uint256 _scaledCdpColl = _cdpCol * DECIMAL_PRECISION;

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

    function _requireMoreThanOneCdpInSystem(uint256 CdpOwnersArrayLength) internal view {
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

    /// @notice Return the Nominal Collateral Ratio (NICR) of the specified Cdp as "cached view" (maybe outdated).
    /// @dev Takes a cdp's pending coll and debt rewards from redistributions into account.
    /// @param _cdpId The CdpId whose NICR to be queried
    /// @return The Nominal Collateral Ratio (NICR) of the specified Cdp.
    /// @dev Use getSyncedNominalICR() instead if pending fee split and debt redistribution should be considered
    function getCachedNominalICR(bytes32 _cdpId) external view returns (uint256) {
        (uint256 currentEBTCDebt, uint256 currentCollShares) = getSyncedDebtAndCollShares(_cdpId);

        uint256 NICR = EbtcMath._computeNominalCR(currentCollShares, currentEBTCDebt);
        return NICR;
    }

    /// @notice Return the Nominal Collateral Ratio (NICR) of the specified Cdp.
    /// @dev Takes a cdp's pending coll and debt rewards as well as stETH Index into account.
    /// @param _cdpId The CdpId whose NICR to be queried
    /// @return The Nominal Collateral Ratio (NICR) of the specified Cdp with fee split and debt redistribution considered.
    function getSyncedNominalICR(bytes32 _cdpId) external view returns (uint256) {
        (uint256 _oldIndex, uint256 _newIndex) = _readStEthIndex();
        (, uint256 _newGlobalSplitIdx, ) = _calcSyncedGlobalAccounting(_newIndex, _oldIndex);
        (uint256 _newColl, uint256 _newDebt, , uint256 _pendingDebt, ) = _calcSyncedAccounting(
            _cdpId,
            cdpStEthFeePerUnitIndex[_cdpId],
            _newGlobalSplitIdx /// NOTE: This is latest index
        );

        uint256 NICR = EbtcMath._computeNominalCR(_newColl, _newDebt);
        return NICR;
    }

    /// @notice Return the Individual Collateral Ratio (ICR) of the specified Cdp as "cached view" (maybe outdated).
    /// @param _cdpId The CdpId whose ICR to be queried
    /// @return The Individual Collateral Ratio (ICR) of the specified Cdp.
    /// @dev Use getSyncedICR() instead if pending fee split and debt redistribution should be considered
    function getCachedICR(bytes32 _cdpId, uint256 _price) public view returns (uint256) {
        (uint256 currentEBTCDebt, uint256 currentCollShares) = getSyncedDebtAndCollShares(_cdpId);
        uint256 ICR = _calculateCR(currentCollShares, currentEBTCDebt, _price);
        return ICR;
    }

    function _calculateCR(
        uint256 currentCollShare,
        uint256 currentDebt,
        uint256 _price
    ) internal view returns (uint256) {
        uint256 _underlyingCollateral = collateral.getPooledEthByShares(currentCollShare);
        return EbtcMath._computeCR(_underlyingCollateral, currentDebt, _price);
    }

    /// @notice Return the pending extra debt assigned to the Cdp from liquidation redistribution, calcualted by Cdp's stake
    /// @param _cdpId The CdpId whose pending debt redistribution to be queried
    /// @return pendingEBTCDebtReward The pending debt redistribution of the specified Cdp.
    function getPendingRedistributedDebt(
        bytes32 _cdpId
    ) public view returns (uint256 pendingEBTCDebtReward) {
        (uint256 _pendingDebt, ) = _getPendingRedistributedDebt(_cdpId);
        return _pendingDebt;
    }

    /// @return Whether the debt redistribution tracking index of the specified Cdp is less than the global tracking one (meaning it might get pending debt redistribution)
    /// @param _cdpId The CdpId whose debt redistribution tracking index to be queried against the gloabl one
    function hasPendingRedistributedDebt(bytes32 _cdpId) public view returns (bool) {
        return _hasRedistributedDebt(_cdpId);
    }

    // Return the Cdps entire debt and coll struct
    function _getSyncedDebtAndCollShares(
        bytes32 _cdpId
    ) internal view returns (CdpDebtAndCollShares memory) {
        (uint256 entireDebt, uint256 entireColl) = getSyncedDebtAndCollShares(_cdpId);
        return CdpDebtAndCollShares(entireDebt, entireColl);
    }

    /// @notice Calculate the Cdps entire debt and coll, including pending debt redistributions and collateral reduction from split fee.
    /// @param _cdpId The CdpId to be queried
    /// @return debt The total debt value of the Cdp including debt redistribution considered
    /// @return coll The total collateral value of the Cdp including possible fee split considered
    /// @dev Should always use this as the first(default) choice for Cdp position size query
    function getSyncedDebtAndCollShares(
        bytes32 _cdpId
    ) public view returns (uint256 debt, uint256 coll) {
        (uint256 _newColl, uint256 _newDebt, , , ) = _calcSyncedAccounting(
            _cdpId,
            cdpStEthFeePerUnitIndex[_cdpId],
            systemStEthFeePerUnitIndex
        );
        coll = _newColl;
        debt = _newDebt;
    }

    /// @dev calculate pending global state change to be applied:
    /// @return split fee taken (if any) AND
    /// @return new split index per stake unit AND
    /// @return new split index error
    function _calcSyncedGlobalAccounting(
        uint256 _newIndex,
        uint256 _oldIndex
    ) internal view returns (uint256, uint256, uint256) {
        if (_newIndex > _oldIndex && totalStakes > 0) {
            /// @audit-ok We don't take the fee if we had a negative rebase
            (
                uint256 _feeTaken,
                uint256 _deltaFeePerUnit,
                uint256 _perUnitError
            ) = calcFeeUponStakingReward(_newIndex, _oldIndex);

            // calculate new split per stake unit
            uint256 _newPerUnit = systemStEthFeePerUnitIndex + _deltaFeePerUnit;
            return (_feeTaken, _newPerUnit, _perUnitError);
        } else {
            return (0, systemStEthFeePerUnitIndex, systemStEthFeePerUnitIndexError);
        }
    }

    /// @dev calculate pending state change to be applied for given CDP and global split index(typically already synced):
    /// @return new CDP collateral share after pending change applied
    /// @return new CDP debt after pending change applied
    /// @return split fee applied to given CDP
    /// @return redistributed debt applied to given CDP
    /// @return delta between debt redistribution index of given CDP and global tracking index
    function _calcSyncedAccounting(
        bytes32 _cdpId,
        uint256 _cdpPerUnitIdx,
        uint256 _systemStEthFeePerUnitIndex
    ) internal view returns (uint256, uint256, uint256, uint256, uint256) {
        uint256 _feeSplitApplied;
        uint256 _newCollShare = Cdps[_cdpId].coll;

        // processing split fee to be applied
        if (_cdpPerUnitIdx != _systemStEthFeePerUnitIndex && _cdpPerUnitIdx > 0) {
            (
                uint256 _feeSplitDistributed,
                uint256 _newCollShareAfter
            ) = getAccumulatedFeeSplitApplied(_cdpId, _systemStEthFeePerUnitIndex);
            _feeSplitApplied = _feeSplitDistributed;
            _newCollShare = _newCollShareAfter;
        }

        // processing redistributed debt to be applied
        (
            uint256 _newDebt,
            uint256 pendingDebtRedistributed,
            uint256 _debtIndexDelta
        ) = _getSyncedCdpDebtAndRedistribution(_cdpId);

        return (
            _newCollShare,
            _newDebt,
            _feeSplitApplied,
            pendingDebtRedistributed,
            _debtIndexDelta
        );
    }

    /// @return CDP debt and pending redistribution from liquidation applied
    function _getSyncedCdpDebtAndRedistribution(
        bytes32 _cdpId
    ) internal view returns (uint256, uint256, uint256) {
        (uint256 pendingDebtRedistributed, uint256 _debtIndexDelta) = _getPendingRedistributedDebt(
            _cdpId
        );
        uint256 _newDebt = Cdps[_cdpId].debt;
        if (pendingDebtRedistributed > 0) {
            _newDebt = _newDebt + pendingDebtRedistributed;
        }
        return (_newDebt, pendingDebtRedistributed, _debtIndexDelta);
    }

    /// @notice Calculate the Cdps entire debt, including pending debt redistributions.
    /// @param _cdpId The CdpId to be queried
    /// @return _newDebt The total debt value of the Cdp including debt redistribution considered
    /// @dev Should always use this as the first(default) choice for Cdp debt query
    function getSyncedCdpDebt(bytes32 _cdpId) public view returns (uint256) {
        (uint256 _newDebt, , ) = _getSyncedCdpDebtAndRedistribution(_cdpId);
        return _newDebt;
    }

    /// @notice Calculate the Cdps entire collateral, including pending fee split to be applied
    /// @param _cdpId The CdpId to be queried
    /// @return _newColl The total collateral value of the Cdp including fee split considered
    /// @dev Should always use this as the first(default) choice for Cdp collateral query
    function getSyncedCdpCollShares(bytes32 _cdpId) public view returns (uint256) {
        (uint256 _oldIndex, uint256 _newIndex) = _readStEthIndex();
        (, uint256 _newGlobalSplitIdx, ) = _calcSyncedGlobalAccounting(_newIndex, _oldIndex);
        (uint256 _newColl, , , , ) = _calcSyncedAccounting(
            _cdpId,
            cdpStEthFeePerUnitIndex[_cdpId],
            _newGlobalSplitIdx
        );
        return _newColl;
    }

    /// @notice Calculate the Cdps ICR, including pending debt distribution and fee split to be applied
    /// @param _cdpId The CdpId to be queried
    /// @param _price The ETH:eBTC price to be used in ICR calculation
    /// @return The ICR of the Cdp including debt distribution and fee split considered
    /// @dev Should always use this as the first(default) choice for Cdp ICR query
    function getSyncedICR(bytes32 _cdpId, uint256 _price) public view returns (uint256) {
        uint256 _debt = getSyncedCdpDebt(_cdpId);
        uint256 _collShare = getSyncedCdpCollShares(_cdpId);
        return _calculateCR(_collShare, _debt, _price);
    }

    /// @notice return system collateral share, including pending fee split to be taken
    function getSyncedSystemCollShares() public view returns (uint256) {
        (uint256 _oldIndex, uint256 _newIndex) = _readStEthIndex();
        (uint256 _feeTaken, , ) = _calcSyncedGlobalAccounting(_newIndex, _oldIndex);

        uint256 _systemCollShare = activePool.getSystemCollShares();
        if (_feeTaken > 0) {
            _systemCollShare = _systemCollShare - _feeTaken;
        }
        return _systemCollShare;
    }

    /// @notice Calculate the TCR, including pending debt distribution and fee split to be taken
    /// @param _price The ETH:eBTC price to be used in TCR calculation
    /// @return The TCR of the eBTC system including debt distribution and fee split considered
    /// @dev Should always use this as the first(default) choice for TCR query
    function getSyncedTCR(uint256 _price) public view returns (uint256) {
        uint256 _systemCollShare = getSyncedSystemCollShares();
        uint256 _systemDebt = activePool.getSystemDebt();
        return _calculateCR(_systemCollShare, _systemDebt, _price);
    }

    /// @notice Get the count of active Cdps in the system
    /// @return The number of current active Cdps (not closed) in the system.
    function getActiveCdpsCount() public view override returns (uint256) {
        return sortedCdps.getSize();
    }

    /// @param icr The ICR of a Cdp to check if liquidatable
    /// @param tcr The TCR of the eBTC system used to determine if Recovery Mode is triggered
    /// @return whether the Cdp of specified icr is liquidatable with specified tcr
    /// @dev The flag will only be set to true if enough time has passed since Grace Period starts
    function canLiquidateRecoveryMode(uint256 icr, uint256 tcr) public view returns (bool) {
        return _checkICRAgainstTCR(icr, tcr) && _recoveryModeGracePeriodPassed();
    }

    /// @dev Check if enough time has passed for grace period after enabled
    function _recoveryModeGracePeriodPassed() internal view returns (bool) {
        // we have waited enough
        uint128 cachedLastGracePeriodStartTimestamp = lastGracePeriodStartTimestamp;
        return
            cachedLastGracePeriodStartTimestamp != UNSET_TIMESTAMP &&
            block.timestamp > cachedLastGracePeriodStartTimestamp + recoveryModeGracePeriodDuration;
    }
}
