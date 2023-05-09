// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./Interfaces/ICdpManager.sol";
import "./Interfaces/ICollSurplusPool.sol";
import "./Interfaces/IEBTCToken.sol";
import "./Interfaces/ISortedCdps.sol";
import "./Interfaces/IFeeRecipient.sol";
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
    string public constant NAME = "CdpManager";

    // --- Connected contract declarations ---

    address public immutable borrowerOperationsAddress;

    ICollSurplusPool immutable collSurplusPool;

    IEBTCToken public immutable override ebtcToken;

    IFeeRecipient public immutable override feeRecipient;

    address public immutable liquidationLibrary;

    // A doubly linked list of Cdps, sorted by their sorted by their collateral ratios
    ISortedCdps public immutable sortedCdps;

    // --- Data structures ---

    uint public constant SECONDS_IN_ONE_MINUTE = 60;

    uint public constant MIN_REDEMPTION_FEE_FLOOR = (DECIMAL_PRECISION * 5) / 1000; // 0.5%
    uint public redemptionFeeFloor = MIN_REDEMPTION_FEE_FLOOR;

    /*
     * Half-life of 12h. 12h = 720 min
     * (1/2) = d^720 => d = (1/2)^(1/720)
     */
    uint public minuteDecayFactor = 999037758833783000;
    uint public constant MIN_MINUTE_DECAY_FACTOR = 1; // Non-zero
    uint public constant MAX_MINUTE_DECAY_FACTOR = 999999999999999999; // Corresponds to a very fast decay rate, but not too extreme

    // -- Permissioned Function Signatures --
    bytes4 internal constant SET_STAKING_REWARD_SPLIT_SIG =
        bytes4(keccak256(bytes("setStakingRewardSplit(uint256)")));
    bytes4 internal constant SET_REDEMPTION_FEE_FLOOR_SIG =
        bytes4(keccak256(bytes("setRedemptionFeeFloor(uint256)")));
    bytes4 internal constant SET_MINUTE_DECAY_FACTOR_SIG =
        bytes4(keccak256(bytes("setMinuteDecayFactor(uint256)")));
    bytes4 internal constant SET_BETA_SIG = bytes4(keccak256(bytes("setBeta(uint256)")));

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

    constructor(
        address _liquidationLibraryAddress,
        address _authorityAddress,
        address _borrowerOperationsAddress,
        address _collSurplusPool,
        address _ebtcToken,
        address _feeRecipient,
        address _sortedCdps,
        address _activePool,
        address _defaultPool,
        address _priceFeed,
        address _collateral
    ) LiquityBase(_activePool, _defaultPool, _priceFeed, _collateral) {
        // TODO: Move to setAddresses or _tickInterest?
        deploymentStartTime = block.timestamp;
        liquidationLibrary = _liquidationLibraryAddress;

        _initializeAuthority(_authorityAddress);

        borrowerOperationsAddress = _borrowerOperationsAddress;
        collSurplusPool = ICollSurplusPool(_collSurplusPool);
        ebtcToken = IEBTCToken(_ebtcToken);
        feeRecipient = IFeeRecipient(_feeRecipient);
        sortedCdps = ISortedCdps(_sortedCdps);

        emit LiquidationLibraryAddressChanged(_liquidationLibraryAddress);
    }

    /**
        @notice BorrowerOperations and CdpManager share reentrancy status by confirming the other's locked flag before beginning operation
        @dev This is an alternative to the more heavyweight solution of both being able to set the reentrancy flag on a 3rd contract.
     */
    modifier nonReentrantSelfAndBOps() {
        require(locked == OPEN, "CdpManager: REENTRANCY");
        require(
            ReentrancyGuard(borrowerOperationsAddress).locked() == OPEN,
            "BorrowerOperations: REENTRANCY"
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
        assert(closedStatus != Status.nonExistent && closedStatus != Status.active);

        uint CdpIdsArrayLength = CdpIds.length;
        _requireMoreThanOneCdpInSystem(CdpIdsArrayLength);

        Cdps[_cdpId].status = closedStatus;
        Cdps[_cdpId].coll = 0;
        Cdps[_cdpId].debt = 0;
        Cdps[_cdpId].liquidatorRewardShares = 0;

        rewardSnapshots[_cdpId].ETH = 0;
        rewardSnapshots[_cdpId].EBTCDebt = 0;

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
        totalStakesSnapshot = totalStakes;

        uint activeColl = activePool.getStEthColl();
        uint liquidatedColl = defaultPool.getStEthColl();
        totalCollateralSnapshot = (activeColl - _collRemainder) + liquidatedColl;

        emit SystemSnapshotsUpdated(totalStakesSnapshot, totalCollateralSnapshot);
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
        uint idxLast = length - 1;

        assert(index <= idxLast);

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
    function claimStakingSplitFee() public {
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
    ) public view returns (uint256, uint256, uint256) {
        require(_newIndex > _prevIndex, "LiquidationLibrary: only take fee with bigger new index");
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
        stFeePerUnitg = stFeePerUnitg + _deltaPerUnit;
        stFeePerUnitgError = _newErrorPerUnit;

        require(activePool.getStEthColl() > _feeTaken, "CDPManager: fee split is too big");
        activePool.allocateFeeRecipientColl(_feeTaken);

        emit CollateralFeePerUnitUpdated(
            _oldPerUnit,
            stFeePerUnitg,
            address(feeRecipient),
            _feeTaken
        );
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
    ) public view returns (uint, uint) {
        if (
            stFeePerUnitcdp[_cdpId] == 0 ||
            Cdps[_cdpId].coll == 0 ||
            stFeePerUnitcdp[_cdpId] == _stFeePerUnitg
        ) {
            return (0, Cdps[_cdpId].coll);
        }

        uint _oldStake = Cdps[_cdpId].stake;

        uint _diffPerUnit = _stFeePerUnitg - stFeePerUnitcdp[_cdpId];
        uint _feeSplitDistributed = _diffPerUnit > 0 ? _oldStake * _diffPerUnit : 0;

        uint _scaledCdpColl = Cdps[_cdpId].coll * DECIMAL_PRECISION;
        require(
            _scaledCdpColl > _feeSplitDistributed,
            "LiquidationLibrary: fee split is too big for CDP"
        );

        return (_feeSplitDistributed, (_scaledCdpColl - _feeSplitDistributed) / DECIMAL_PRECISION);
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

    function _requireValidUpdateInterval() internal {
        require(
            block.timestamp - lastIndexTimestamp > INDEX_UPD_INTERVAL,
            "CdpManager: update index too frequent"
        );
    }
}
