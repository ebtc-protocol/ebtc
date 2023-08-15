// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./Interfaces/ICdpManager.sol";
import "./Interfaces/ICollSurplusPool.sol";
import "./Interfaces/IEBTCToken.sol";
import "./Interfaces/ISortedCdps.sol";
import "./Dependencies/ICollateralTokenOracle.sol";
import "./CdpManagerStorage.sol";
import "./EBTCDeployer.sol";
import "./Dependencies/Proxy.sol";

contract CdpManager is CdpManagerStorage, ICdpManager, Proxy {
    // --- Dependency setter ---

    /**
     * @notice Constructor for CdpManager contract.
     * @dev Sets up dependencies and initial staking reward split.
     * @param _liquidationLibraryAddress Address of the liquidation library.
     * @param _authorityAddress Address of the authority.
     * @param _borrowerOperationsAddress Address of BorrowerOperations.
     * @param _collSurplusPoolAddress Address of CollSurplusPool.
     * @param _ebtcTokenAddress Address of the eBTC token.
     * @param _sortedCdpsAddress Address of the SortedCDPs.
     * @param _activePoolAddress Address of the ActivePool.
     * @param _priceFeedAddress Address of the price feed.
     * @param _collTokenAddress Address of the collateral token.
     */
    constructor(
        address _liquidationLibraryAddress,
        address _authorityAddress,
        address _borrowerOperationsAddress,
        address _collSurplusPoolAddress,
        address _ebtcTokenAddress,
        address _sortedCdpsAddress,
        address _activePoolAddress,
        address _priceFeedAddress,
        address _collTokenAddress
    )
        CdpManagerStorage(
            _liquidationLibraryAddress,
            _authorityAddress,
            _borrowerOperationsAddress,
            _collSurplusPoolAddress,
            _ebtcTokenAddress,
            _sortedCdpsAddress,
            _activePoolAddress,
            _priceFeedAddress,
            _collTokenAddress
        )
    {
        stakingRewardSplit = STAKING_REWARD_SPLIT;
        // Emit initial value for analytics
        emit StakingRewardSplitSet(stakingRewardSplit);

        _syncStEthIndex();
        stFeePerUnitg = DECIMAL_PRECISION;
    }

    // --- Getters ---

    /**
        @notice Get the count of active CDPs in the system
        @return The number of CDPs.
     */

    function getActiveCdpsCount() external view override returns (uint) {
        return sortedCdps.getSize();
    }

    /**
     * @notice Get the CdpId at a given index in the CdpIds array.
     * @param _index Index of the CdpIds array.
     * @return CDP ID.
     */
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

    /// @notice Fully liquidate a single CDP by ID. CDP must meet the criteria for liquidation at the time of execution.
    /// @notice callable by anyone, attempts to liquidate the CdpId. Executes successfully if Cdp meets the conditions for liquidation (e.g. in Normal Mode, it liquidates if the Cdp's ICR < the system MCR).
    /// @dev forwards msg.data directly to the liquidation library using OZ proxy core delegation function
    /// @param _cdpId ID of the CDP to liquidate.

    function liquidate(bytes32 _cdpId) external override {
        _delegate(liquidationLibrary);
    }

    /// @notice Partially liquidate a single CDP.
    /// @dev forwards msg.data directly to the liquidation library using OZ proxy core delegation function
    /// @param _cdpId ID of the CDP to partially liquidate.
    /// @param _partialAmount Amount to partially liquidate.
    /// @param _upperPartialHint Upper hint for reinsertion of the CDP into the linked list.
    /// @param _lowerPartialHint Lower hint for reinsertion of the CDP into the linked list.
    function partiallyLiquidate(
        bytes32 _cdpId,
        uint256 _partialAmount,
        bytes32 _upperPartialHint,
        bytes32 _lowerPartialHint
    ) external override {
        _delegate(liquidationLibrary);
    }

    // --- Batch/Sequence liquidation functions ---

    /// @notice Liquidate a sequence of cdps.
    /// @notice Closes a maximum number of n cdps with their CR < MCR in normla mode, or CR < TCR in recovery mode, starting from the one with the lowest collateral ratio in the system, and moving upwards.
    /// @notice Callable by anyone, checks for under-collateralized Cdps below MCR and liquidates up to `n`, starting from the Cdp with the lowest collateralization ratio; subject to gas constraints and the actual number of under-collateralized Cdps. The gas costs of `liquidateCdps(uint n)` mainly depend on the number of Cdps that are liquidated, and whether the Cdps are offset against the Stability Pool or redistributed. For n=1, the gas costs per liquidated Cdp are roughly between 215K-400K, for n=5 between 80K-115K, for n=10 between 70K-82K, and for n=50 between 60K-65K.
    /// @dev forwards msg.data directly to the liquidation library using OZ proxy core delegation function
    /// @param _n Maximum number of CDPs to liquidate.
    function liquidateCdps(uint _n) external override {
        _delegate(liquidationLibrary);
    }

    /// @notice Attempt to liquidate a custom list of CDPs provided by the caller
    /// @notice Callable by anyone, accepts a custom list of Cdps addresses as an argument. Steps through the provided list and attempts to liquidate every Cdp, until it reaches the end or it runs out of gas. A Cdp is liquidated only if it meets the conditions for liquidation. For a batch of 10 Cdps, the gas costs per liquidated Cdp are roughly between 75K-83K, for a batch of 50 Cdps between 54K-69K.
    /// @dev forwards msg.data directly to the liquidation library using OZ proxy core delegation function
    /// @param _cdpArray Array of CDPs to liquidate.
    function batchLiquidateCdps(bytes32[] memory _cdpArray) external override {
        _delegate(liquidationLibrary);
    }

    // --- Redemption functions ---

    /// @notice // Redeem as much collateral as possible from given Cdp in exchange for EBTC up to specified maximum
    /// @param _inputs Struct containing variables for redeeming collateral.
    /// @return singleRedemption Struct containing redemption values.
    function _redeemCollateralFromCdp(
        SingleCdpRedemptionInputs memory _inputs
    ) internal returns (SingleRedemptionValues memory singleRedemption) {
        address _borrower = sortedCdps.getOwnerAddress(_inputs.cdpId);
        uint _oldDebt = Cdps[_inputs.cdpId].debt;
        uint _oldCollShares = Cdps[_inputs.cdpId].collShares;

        // Determine the remaining amount (lot) to be redeemed,
        // capped by the entire debt of the Cdp minus the liquidation reserve
        singleRedemption.eBtcToRedeem = LiquityMath._min(_inputs.maxEBTCToRedeem, _oldDebt);

        // Get the collSharesToRecieve of equivalent value in USD
        singleRedemption.collSharesToRecieve = collateral.getSharesByPooledEth(
            (singleRedemption.eBtcToRedeem * DECIMAL_PRECISION) / _inputs.price
        );

        // Decrease the debt and collateral of the current Cdp according to the EBTC lot and corresponding ETH to send
        uint _newDebt = _oldDebt - singleRedemption.eBtcToRedeem;
        uint _newCollShares = _oldCollShares - singleRedemption.collSharesToRecieve;

        if (_newDebt == 0) {
            // No debt remains, close CDP
            // No debt left in the Cdp, therefore the cdp gets closed

            _closeCdpByRedemption(_inputs.cdpId, 0, _newCollShares, _borrower);
            singleRedemption.fullRedemption = true;

            emit CdpUpdated(
                _inputs.cdpId,
                _borrower,
                _oldDebt,
                _oldCollShares,
                0,
                0,
                0,
                CdpOperation.redeemCollateral
            );
        } else {
            // Debt remains, reinsert CDP
            uint _newNICR = LiquityMath._computeNominalCR(_newCollShares, _newDebt);

            /*
             * If the provided hint is out of date, we bail since trying to reinsert without a good hint will almost
             * certainly result in running out of gas.
             *
             * If the resultant net coll of the partial is less than the minimum, we bail.
             */
            if (
                _newNICR != _inputs.partialRedemptionHintNICR ||
                collateral.getPooledEthByShares(_newCollShares) < MIN_CDP_STETH_BALANCE
            ) {
                singleRedemption.cancelledPartial = true;
                return singleRedemption;
            }

            sortedCdps.reInsert(
                _inputs.cdpId,
                _newNICR,
                _inputs.upperPartialRedemptionHint,
                _inputs.lowerPartialRedemptionHint
            );

            _updateCdp(
                _inputs.cdpId,
                _borrower,
                _oldCollShares,
                _oldDebt,
                _newCollShares,
                _newDebt,
                CdpOperation.redeemCollateral
            );
        }
        return singleRedemption;
    }

    /*
     * Called when a full redemption occurs, and closes the cdp.
     * The redeemer swaps (debt) EBTC for (debt)
     * worth of stETH, so the stETH liquidation reserve is all that remains.
     * In order to close the cdp, the stETH liquidation reserve is returned to the CDP owner,
     * The debt recorded on the cdp's struct is zero'd elswhere, in _closeCdp.
     * Any surplus stETH left in the cdp, is sent to the Coll surplus pool, and can be later claimed by the borrower.
     */
    function _closeCdpByRedemption(
        bytes32 _cdpId,
        uint _cdpDebt,
        uint _cdpStEthBalance,
        address _borrower
    ) internal {
        uint _liquidatorRewardShares = Cdps[_cdpId].liquidatorRewardShares;

        _removeStake(_cdpId);
        _closeCdpWithoutRemovingSortedCdps(_cdpId, Status.closedByRedemption);

        // Update Active Pool EBTC, and send ETH to account
        activePool.decreaseSystemDebt(_cdpDebt);

        // Register stETH surplus from upcoming transfers of stETH collateral and liquidator reward shares
        collSurplusPool.setSurplusCollSharesFor(
            _borrower,
            _cdpStEthBalance + _liquidatorRewardShares
        );

        // CEI: send stETH coll and liquidator reward shares from Active Pool to CollSurplus Pool
        activePool.transferSystemCollSharesAndLiquidatorRewardShares(
            address(collSurplusPool),
            _cdpStEthBalance,
            _liquidatorRewardShares
        );
    }

    function _isValidFirstRedemptionHint(
        ISortedCdps _sortedCdps,
        bytes32 _firstRedemptionHint,
        uint _price
    ) internal view returns (bool) {
        if (
            _firstRedemptionHint == _sortedCdps.nonExistId() ||
            !_sortedCdps.contains(_firstRedemptionHint) ||
            getICR(_firstRedemptionHint, _price) < MCR
        ) {
            return false;
        }

        bytes32 nextCdp = _sortedCdps.getNext(_firstRedemptionHint);
        return nextCdp == _sortedCdps.nonExistId() || getICR(nextCdp, _price) < MCR;
    }

    /* 
        @notice Redeems `_eBTCToRedeem` of eBTC for stETH collateral from the system. Decreases the caller’s eBTC balance, and sends them the corresponding amount of stETH. 
        @notice Executes successfully if the caller has sufficient eBTC to redeem. The number of Cdps redeemed from is capped by `_maxIterations`. 
        @notice The borrower has to provide a `_maxFeePercentage` that he/she is willing to accept in case of a fee slippage, i.e. when another redemption transaction is processed first, driving up the redemption fee.
        @notice Send _eBTCToRedeem EBTC to the system and redeem the corresponding amount of collateral from as many Cdps as are needed to fill the redemption request. 
        @dev Applies pending state to a Cdp before reducing its debt and coll.
        @dev Note that if _amount is very large, this function can run out of gas, specially if traversed cdps are small.
        @dev This can be easily avoided by splitting the total _amount in appropriate chunks and calling the function multiple times.
        @dev Param `_maxIterations` can also be provided, so the loop through Cdps is capped (if it’s zero, it will be ignored).
        @dev This makes it easier to avoid OOG for the frontend, as only knowing approximately the average cost of an iteration is enough, without needing to know the “topology” of the cdp list. 
        @dev It also avoids the need to set the cap in stone in the contract, nor doing gas calculations, as both gas price and opcode costs can vary.
        @dev All Cdps that are redeemed from -- with the likely exception of the last one -- will end up with no debt left, therefore they will be closed.
        @dev If the last Cdp does have some remaining debt, it has a finite ICR, and the reinsertion could be anywhere in the list, therefore it requires a hint.
        @dev A frontend should use getRedemptionHints() to calculate what the ICR of this Cdp will be after redemption, and pass a hint for its position in the sortedCdps list along with the ICR value that the hint was found for.
        @dev If another transaction modifies the list between calling getRedemptionHints() and passing the hints to redeemCollateral(), it is very likely that the last (partially) redeemed Cdp would end up with a different ICR than what the hint is for.
        @dev In this case the redemption will stop after the last completely redeemed Cdp and the sender will keep the remaining EBTC amount, which they can attempt to redeem later.
     */
    function redeemCollateral(
        uint _eBTCToRedeem,
        bytes32 _firstRedemptionHint,
        bytes32 _upperPartialRedemptionHint,
        bytes32 _lowerPartialRedemptionHint,
        uint _partialRedemptionHintNICR,
        uint _maxIterations,
        uint _maxFeePercentage
    ) external override nonReentrantSelfAndBOps {
        _requireRedemptionsNotPaused();
        _requireValidMaxFeePercentage(_maxFeePercentage);
        _requireAfterBootstrapPeriod();
        _requireAmountGreaterThanZero(_eBTCToRedeem);

        applyPendingGlobalState();

        RedemptionTotals memory totals;
        totals.price = priceFeed.fetchPrice();
        _requireTCRoverMCR(totals.price);

        totals.totalEBTCSupplyAtStart = _getSystemDebt();
        _requireCallerEBTCBalanceCoversRedemptionAndWithinSupply(
            msg.sender,
            _eBTCToRedeem,
            totals.totalEBTCSupplyAtStart
        );

        totals.remainingEBTCToRedeem = _eBTCToRedeem;
        address _currentBorrower;
        bytes32 _currentCdpId = _firstRedemptionHint;

        if (_isValidFirstRedemptionHint(sortedCdps, _firstRedemptionHint, totals.price)) {
            _currentBorrower = sortedCdps.getOwnerAddress(_firstRedemptionHint);
        } else {
            _currentCdpId = sortedCdps.getLast();
            _currentBorrower = sortedCdps.getOwnerAddress(_currentCdpId);
            // Find the first cdp with ICR >= MCR
            while (_currentBorrower != address(0) && getICR(_currentCdpId, totals.price) < MCR) {
                _currentCdpId = sortedCdps.getPrev(_currentCdpId);
                _currentBorrower = sortedCdps.getOwnerAddress(_currentCdpId);
            }
        }

        // Loop through the Cdps starting from the one with lowest collateral
        // ratio until _amount of EBTC is exchanged for collateral
        if (_maxIterations == 0) {
            _maxIterations = type(uint256).max;
        }

        // These will be used when batching SortedCdps linked list removals at the end of the redemption sequence
        bytes32 _firstRedeemedCdpId = _currentCdpId;
        bytes32 _lastRedeemedCdpId = _currentCdpId;
        uint _fullyRedeemedCdpCount;

        while (
            _currentBorrower != address(0) && totals.remainingEBTCToRedeem > 0 && _maxIterations > 0
        ) {
            _maxIterations--;
            // Save the address of the Cdp preceding the current one, before potentially modifying the list
            {
                _applyPendingState(_currentCdpId);

                // Helper struct for single CDP redemption function inputs due to stack too deep limitation
                SingleCdpRedemptionInputs memory inputs = SingleCdpRedemptionInputs(
                    _currentCdpId,
                    totals.remainingEBTCToRedeem,
                    totals.price,
                    _upperPartialRedemptionHint,
                    _lowerPartialRedemptionHint,
                    _partialRedemptionHintNICR
                );

                SingleRedemptionValues memory singleRedemption = _redeemCollateralFromCdp(inputs);

                // Partial redemption was cancelled (out-of-date hint, or new net collShares < minimum stEth balance, when converted shares -> balance),
                // therefore we could not redeem from the last Cdp
                if (singleRedemption.cancelledPartial) break;

                // Adjust totals for redemption sequence from single Cdp results
                totals.totalEBTCToRedeem = totals.totalEBTCToRedeem + singleRedemption.eBtcToRedeem;
                totals.remainingEBTCToRedeem =
                    totals.remainingEBTCToRedeem -
                    singleRedemption.eBtcToRedeem;

                totals.totalStEthToSend =
                    totals.totalStEthToSend +
                    singleRedemption.collSharesToRecieve;

                if (singleRedemption.fullRedemption) {
                    _lastRedeemedCdpId = _currentCdpId;
                    _fullyRedeemedCdpCount = _fullyRedeemedCdpCount + 1;
                }

                // Get next Cdp for next loop iteration
                bytes32 _nextCdpId = sortedCdps.getPrev(_currentCdpId);
                _currentBorrower = sortedCdps.getOwnerAddress(_nextCdpId);
                _currentCdpId = _nextCdpId;
            }
        }

        require(totals.totalStEthToSend > 0, "CdpManager: Unable to redeem any amount");

        // Batch remove fully redeemed Cdps from the SortedCdps linked list
        if (_fullyRedeemedCdpCount == 1) {
            sortedCdps.remove(_firstRedeemedCdpId);
        } else if (_fullyRedeemedCdpCount > 1) {
            bytes32[] memory _toRemoveIds = _getCdpIdsToRemove(
                _lastRedeemedCdpId,
                _fullyRedeemedCdpCount,
                _firstRedeemedCdpId
            );
            sortedCdps.batchRemove(_toRemoveIds);
        }

        // Decay the baseRate due to time passed, and then increase it according to the size of this redemption.
        // Use the saved total EBTC supply value, from before it was reduced by the redemption.
        _updateBaseRateFromRedemption(
            totals.totalStEthToSend,
            totals.price,
            totals.totalEBTCSupplyAtStart
        );

        // Calculate the ETH fee
        totals.stEthRedemptionFee = _getRedemptionFee(totals.totalStEthToSend);

        _requireUserAcceptsFee(
            totals.stEthRedemptionFee,
            totals.totalStEthToSend,
            _maxFeePercentage
        );

        totals.stEthToSend = totals.totalStEthToSend - totals.stEthRedemptionFee;

        emit Redemption(
            _eBTCToRedeem,
            totals.totalEBTCToRedeem,
            totals.totalStEthToSend,
            totals.stEthRedemptionFee
        );

        // Burn the total eBTC that is redeemed
        ebtcToken.burn(msg.sender, totals.totalEBTCToRedeem);

        // Update Active Pool eBTC debt internal accounting
        activePool.decreaseSystemDebt(totals.totalEBTCToRedeem);

        // Allocate the stETH fee, denominated in shares, to the FeeRecipient
        activePool.allocateSystemCollSharesToFeeRecipient(totals.stEthRedemptionFee);

        // CEI: Send the stETH shares drawn to the redeemer
        activePool.transferSystemCollShares(msg.sender, totals.stEthToSend);
    }

    // --- Helper functions ---

    function _getCdpIdsToRemove(
        bytes32 _start,
        uint _total,
        bytes32 _end
    ) internal view returns (bytes32[] memory) {
        uint _cnt = _total;
        bytes32 _id = _start;
        bytes32[] memory _toRemoveIds = new bytes32[](_total);
        while (_cnt > 0 && _id != bytes32(0)) {
            _toRemoveIds[_total - _cnt] = _id;
            _cnt = _cnt - 1;
            _id = sortedCdps.getNext(_id);
        }
        require(_toRemoveIds[0] == _start, "CdpManager: batchRemoveSortedCdpIds check start error");
        require(
            _toRemoveIds[_total - 1] == _end,
            "CdpManager: batchRemoveSortedCdpIds check end error"
        );
        return _toRemoveIds;
    }

    /**
        @notice Apply pending index snapshot state to a CDP (realizing changes in stETH pooledEthPerShare or eBTC debt redistribution index)
        @notice Applies pending global snapshot states as well if necessary
        @dev Global snapshot state should be synced before CDP state and before any other operations in the calling function
        @param _cdpId CDP ID to apply update index states for
    */
    function applyPendingState(bytes32 _cdpId) external override {
        // TODO: Open this up for anyone?
        _requireCallerIsBorrowerOperations();
        return _applyPendingState(_cdpId);
    }

    function removeStake(bytes32 _cdpId) external override {
        _requireCallerIsBorrowerOperations();
        return _removeStake(_cdpId);
    }

    // get totalStakes after split fee taken removed
    function getTotalStakeForFeeTaken(uint _feeTaken) public view override returns (uint, uint) {
        uint stake = _computeNewStake(_feeTaken);
        uint _newTotalStakes = totalStakes - stake;
        return (_newTotalStakes, stake);
    }

    function updateStakeAndTotalStakes(bytes32 _cdpId) external override returns (uint) {
        _requireCallerIsBorrowerOperations();
        return _updateStakeAndTotalStakes(_cdpId);
    }

    function closeCdp(
        bytes32 _cdpId,
        address _borrower,
        uint _debt,
        uint _collShares
    ) external override {
        _requireCallerIsBorrowerOperations();
        emit CdpUpdated(_cdpId, _borrower, _debt, _collShares, 0, 0, 0, CdpOperation.closeCdp);
        return _closeCdp(_cdpId, Status.closedByOwner);
    }

    // Push the owner's address to the Cdp owners list, and record the corresponding array index on the Cdp struct
    function _addCdpIdToArray(bytes32 _cdpId) internal returns (uint128 index) {
        /* Max array size is 2**128 - 1, i.e. ~3e30 cdps. No risk of overflow, since cdps have minimum EBTC
        debt of liquidation reserve plus MIN_NET_DEBT.
        3e30 EBTC dwarfs the value of all wealth in the world ( which is < 1e15 USD). */

        // Push the Cdpowner to the array
        CdpIds.push(_cdpId);

        // Record the index of the new Cdpowner on their Cdp struct
        index = uint128(CdpIds.length - 1);
        Cdps[_cdpId].arrayIndex = index;

        return index;
    }

    // --- Recovery Mode and TCR functions ---

    /**
    Returns the systemic entire debt assigned to Cdps, i.e. the debt in the Active Pool.
     */
    function getSystemDebt() public view returns (uint systemDebt) {
        return _getSystemDebt();
    }

    /**
    returns the total collateralization ratio (TCR) of the system.  The TCR is based on the the entire system debt and collateral (including pending rewards). */
    function getTCR(uint _price) external view override returns (uint) {
        return _getTCR(_price);
    }

    /**
    reveals whether or not the system is in Recovery Mode (i.e. whether the Total Collateralization Ratio (TCR) is below the Critical Collateralization Ratio (CCR)).
    */
    function checkRecoveryMode(uint _price) external view override returns (bool) {
        return _checkRecoveryMode(_price);
    }

    // Check whether or not the system *would be* in Recovery Mode,
    // given an stETH:BTC price, and the entire system coll and debt.
    function _checkPotentialRecoveryMode(
        uint _systemCollShares,
        uint _systemDebt,
        uint _price
    ) internal view returns (bool) {
        uint TCR = _computeTCRWithGivenSystemValues(_systemCollShares, _systemDebt, _price);
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
        uint _stEthBalance,
        uint _price,
        uint _totalEBTCSupply
    ) internal returns (uint) {
        uint decayedBaseRate = _calcDecayedBaseRate();

        /* Convert the drawn stEth back to eBTC at face value rate (1:1 value with oracle price), in order to get
         * the fraction of total supply that was redeemed at face value. */
        uint redeemedEBTCFraction = (collateral.getPooledEthByShares(_stEthBalance) * _price) /
            _totalEBTCSupply;

        uint newBaseRate = decayedBaseRate + (redeemedEBTCFraction / beta);
        newBaseRate = LiquityMath._min(newBaseRate, DECIMAL_PRECISION); // cap baseRate at a maximum of 100%
        require(newBaseRate > 0, "CdpManager: new baseRate is zero!"); // Base rate is always non-zero after redemption

        // Update the baseRate state variable
        baseRate = newBaseRate;
        emit BaseRateUpdated(newBaseRate);

        _updateLastRedemptionFeeOperationTimestamp();

        return newBaseRate;
    }

    function getRedemptionRate() public view override returns (uint) {
        return _calcRedemptionRate(baseRate);
    }

    function getRedemptionRateWithDecay() public view override returns (uint) {
        return _calcRedemptionRate(_calcDecayedBaseRate());
    }

    function _calcRedemptionRate(uint _baseRate) internal view returns (uint) {
        return
            LiquityMath._min(
                redemptionFeeFloor + _baseRate,
                DECIMAL_PRECISION // cap at a maximum of 100%
            );
    }

    function _getRedemptionFee(uint _stEthBalance) internal view returns (uint) {
        return _calcRedemptionFee(_calcRedemptionRate(baseRate), _stEthBalance);
    }

    function getRedemptionFeeWithDecay(uint _stEthBalance) external view override returns (uint) {
        return _calcRedemptionFee(getRedemptionRateWithDecay(), _stEthBalance);
    }

    function _calcRedemptionFee(
        uint _redemptionRate,
        uint _stEthBalance
    ) internal pure returns (uint) {
        uint redemptionFee = (_redemptionRate * _stEthBalance) / DECIMAL_PRECISION;
        require(
            redemptionFee < _stEthBalance,
            "CdpManager: Fee would eat up all returned collateral"
        );
        return redemptionFee;
    }

    // Updates the baseRate state variable based on time elapsed since the last redemption or EBTC borrowing operation.
    function decayBaseRateFromBorrowing() external override {
        _requireCallerIsBorrowerOperations();

        _decayBaseRate();
    }

    function _decayBaseRate() internal {
        uint decayedBaseRate = _calcDecayedBaseRate();
        require(decayedBaseRate <= DECIMAL_PRECISION, "CdpManager: baseRate too large!"); // The baseRate can decay to 0

        baseRate = decayedBaseRate;
        emit BaseRateUpdated(decayedBaseRate);

        _updateLastRedemptionFeeOperationTimestamp();
    }

    // --- Internal fee functions ---

    // Update the last fee operation time only if time passed >= decay interval. This prevents base rate griefing.
    function _updateLastRedemptionFeeOperationTimestamp() internal {
        uint timePassed = block.timestamp > lastRedemptionFeeOperationTimestamp
            ? block.timestamp - lastRedemptionFeeOperationTimestamp
            : 0;

        if (timePassed >= SECONDS_IN_ONE_MINUTE) {
            // Using the effective elapsed time that is consumed so far to update lastRedemptionFeeOperationTimestamp
            // instead block.timestamp for consistency with _calcDecayedBaseRate()
            lastRedemptionFeeOperationTimestamp +=
                _minutesPassedSinceLastRedemptionFeeOperation() *
                SECONDS_IN_ONE_MINUTE;
            emit LastRedemptionFeeOperationTimestampUpdated(block.timestamp);
        }
    }

    function _calcDecayedBaseRate() internal view returns (uint) {
        uint minutesPassed = _minutesPassedSinceLastRedemptionFeeOperation();
        uint decayFactor = LiquityMath._decPow(minuteDecayFactor, minutesPassed);

        return (baseRate * decayFactor) / DECIMAL_PRECISION;
    }

    function _minutesPassedSinceLastRedemptionFeeOperation() internal view returns (uint) {
        return
            block.timestamp > lastRedemptionFeeOperationTimestamp
                ? ((block.timestamp - lastRedemptionFeeOperationTimestamp) / SECONDS_IN_ONE_MINUTE)
                : 0;
    }

    function getDeploymentStartTime() public view returns (uint256) {
        return deploymentStartTime;
    }

    // Check whether or not the system *would be* in Recovery Mode,
    // given an ETH:USD price, and the entire system coll and debt.
    function checkPotentialRecoveryMode(
        uint _systemCollShares,
        uint _systemDebt,
        uint _price
    ) external view returns (bool) {
        return _checkPotentialRecoveryMode(_systemCollShares, _systemDebt, _price);
    }

    // --- 'require' wrapper functions ---

    function _requireCallerIsBorrowerOperations() internal view {
        require(
            msg.sender == borrowerOperationsAddress,
            "CdpManager: Caller is not the BorrowerOperations contract"
        );
    }

    function _requireCallerEBTCBalanceCoversRedemptionAndWithinSupply(
        address _redeemer,
        uint _amount,
        uint _totalSupply
    ) internal view {
        uint callerBalance = ebtcToken.balanceOf(_redeemer);
        require(
            callerBalance >= _amount,
            "CdpManager: Requested redemption amount must be <= user's EBTC token balance"
        );
        require(
            callerBalance <= _totalSupply,
            "CdpManager: redeemer's EBTC balance exceeds total supply!"
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
            block.timestamp >= systemDeploymentTime + BOOTSTRAP_PERIOD,
            "CdpManager: Redemptions are not allowed during bootstrap phase"
        );
    }

    function _requireRedemptionsNotPaused() internal view {
        require(redemptionsPaused == false, "CdpManager: Redemptions Paused");
    }

    function _requireValidMaxFeePercentage(uint _maxFeePercentage) internal view {
        require(
            _maxFeePercentage >= redemptionFeeFloor && _maxFeePercentage <= DECIMAL_PRECISION,
            "Max fee percentage must be between redemption fee floor and 100%"
        );
    }

    // --- Governance Parameters ---

    function setStakingRewardSplit(uint _stakingRewardSplit) external requiresAuth {
        require(
            _stakingRewardSplit <= MAX_REWARD_SPLIT,
            "CDPManager: new staking reward split exceeds max"
        );

        applyPendingGlobalState();

        stakingRewardSplit = _stakingRewardSplit;
        emit StakingRewardSplitSet(_stakingRewardSplit);
    }

    function setRedemptionFeeFloor(uint _redemptionFeeFloor) external requiresAuth {
        require(
            _redemptionFeeFloor >= MIN_REDEMPTION_FEE_FLOOR,
            "CDPManager: new redemption fee floor is lower than minimum"
        );
        require(
            _redemptionFeeFloor <= DECIMAL_PRECISION,
            "CDPManager: new redemption fee floor is higher than maximum"
        );

        applyPendingGlobalState();

        redemptionFeeFloor = _redemptionFeeFloor;
        emit RedemptionFeeFloorSet(_redemptionFeeFloor);
    }

    function setMinuteDecayFactor(uint _minuteDecayFactor) external requiresAuth {
        require(
            _minuteDecayFactor >= MIN_MINUTE_DECAY_FACTOR,
            "CDPManager: new minute decay factor out of range"
        );
        require(
            _minuteDecayFactor <= MAX_MINUTE_DECAY_FACTOR,
            "CDPManager: new minute decay factor out of range"
        );

        applyPendingGlobalState();
        _decayBaseRate();

        // set new factor after decaying
        minuteDecayFactor = _minuteDecayFactor;
        emit MinuteDecayFactorSet(_minuteDecayFactor);
    }

    function setBeta(uint _beta) external requiresAuth {
        applyPendingGlobalState();
        _decayBaseRate();

        beta = _beta;
        emit BetaSet(_beta);
    }

    function setRedemptionsPaused(bool _paused) external requiresAuth {
        applyPendingGlobalState();
        _decayBaseRate();

        redemptionsPaused = _paused;
        emit RedemptionsPaused(_paused);
    }

    // --- Cdp property getters ---

    /// @notice Get status of a CDP. Named values can be found in ICdpManagerData.Status.
    function getCdpStatus(bytes32 _cdpId) external view override returns (uint) {
        return uint(Cdps[_cdpId].status);
    }

    /// @notice Get stake value of a CDP.
    function getCdpStake(bytes32 _cdpId) external view override returns (uint) {
        return Cdps[_cdpId].stake;
    }

    /// @notice Get stored debt value of a CDP, in eBTC units. Does not include pending changes from redistributions
    function getCdpDebt(bytes32 _cdpId) external view override returns (uint) {
        return Cdps[_cdpId].debt;
    }

    /// @notice Get stored collateral value of a CDP, in stETH shares. Does not include pending changes from redistributions or unprocessed staking yield.
    function getCdpCollShares(bytes32 _cdpId) external view override returns (uint) {
        return Cdps[_cdpId].collShares;
    }

    /**
        @notice Get shares value of the liquidator gas incentive reward stored for a CDP. 
        @notice This value is processed when a CDP closes. 
        @dev This value is returned to the borrower when they close their own CDP
        @dev This value is given to liquidators upon fully liquidating a CDP
        @dev This value is sent to the CollSurplusPool for reclaiming by the borrower when their CDP is redeemed
    */
    function getCdpLiquidatorRewardShares(bytes32 _cdpId) external view override returns (uint) {
        return Cdps[_cdpId].liquidatorRewardShares;
    }

    /**
        @notice Get data struct for a given CDP
        @param _cdpId ID of CDP to fetch data struct for
        @return cdpData CDP data struct
    */
    function getCdpData(bytes32 _cdpId) external view override returns (Cdp memory cdpData) {
        cdpData = Cdps[_cdpId];
        return cdpData;
    }

    /**
        @notice Get index snapshots (stETH pooledEthByShare and eBTC debt redistribution)
        @param _cdpId ID of CDP to fetch snapshots for
        @return indexSnapshots CDP snapshots struct
    */
    function getCdpIndexSnapshots(
        bytes32 _cdpId
    ) external view override returns (CdpIndexSnapshots memory indexSnapshots) {
        indexSnapshots.pooledEthPerShareIndex = stFeePerUnitcdp[_cdpId];
        indexSnapshots.debtRedistributionIndex = debtRedistributionIndex[_cdpId];
        return indexSnapshots;
    }

    // --- Cdp property setters, called by BorrowerOperations ---

    /**
        @notice Initiailze all state for new CDP
        @dev Only callable by BorrowerOperations, critical trust assumption 
        @dev Requires CDP to be already inserted into linked list correctly
        @param _cdpId id of CDP to initialize state for. Inserting the blank CDP into the linked list grants this ID
        @param _debt debt units of CDP
        @param _collShares collateral shares of CDP
        @param _liquidatorRewardShares collateral shares for CDP gas stipend
        @param _borrower borrower address
     */
    function initializeCdp(
        bytes32 _cdpId,
        uint _debt,
        uint _collShares,
        uint _liquidatorRewardShares,
        address _borrower
    ) external {
        _requireCallerIsBorrowerOperations();

        Cdps[_cdpId].debt = _debt;
        Cdps[_cdpId].collShares = _collShares;
        Cdps[_cdpId].status = Status.active;
        Cdps[_cdpId].liquidatorRewardShares = _liquidatorRewardShares;

        _applyAccumulatedFeeSplit(_cdpId);
        _updateRedistributedDebtSnapshot(_cdpId);
        uint stake = _updateStakeAndTotalStakes(_cdpId);
        uint index = _addCdpIdToArray(_cdpId);

        // Previous debt and coll are by definition zero upon opening a new CDP
        emit CdpUpdated(_cdpId, _borrower, 0, 0, _debt, _collShares, stake, CdpOperation.openCdp);
    }

    /**
        @notice Set new CDP debt and collateral values via a user adjust CDP operation, updating stake accordingly.
        @dev Only callable by BorrowerOperations, critical trust assumption 
        @param _cdpId Id of CDP to update state for
        @param _borrower borrower of CDP. Passed along in function to avoid an extra storage read.
        @param _collShares collateral shares of CDP before update operation. Passed in function to avoid an extra stroage read.
        @param _debt debt units of CDP before update operation. Passed in function to avoid an extra stroage read.
        @param _newCollShares collateral shares of CDP after update operation.
        @param _newDebt debt units of CDP after update operation.
        @dev _operation is always a user adjustment, CdpOperation.adjustCdp, when called by BorrowerOperations
     */
    function updateCdp(
        bytes32 _cdpId,
        address _borrower,
        uint _collShares,
        uint _debt,
        uint _newCollShares,
        uint _newDebt
    ) external {
        _requireCallerIsBorrowerOperations();
        _updateCdp(
            _cdpId,
            _borrower,
            _collShares,
            _debt,
            _newCollShares,
            _newDebt,
            CdpOperation.adjustCdp
        );
    }

    /**
        @notice Set new CDP debt and collateral values, updating stake accordingly.
        @dev Only callable by BorrowerOperations, critical trust assumption 
        @param _cdpId Id of CDP to update state for
        @param _borrower borrower of CDP. Passed along in function to avoid an extra storage read.
        @param _collShares collateral shares of CDP before update operation. Passed in function to avoid an extra stroage read.
        @param _debt debt units of CDP before update operation. Passed in function to avoid an extra stroage read.
        @param _newCollShares collateral shares of CDP after update operation.
        @param _newDebt debt units of CDP after update operation.
        @param _operation type of update operation, for logging purposes.
     */
    function _updateCdp(
        bytes32 _cdpId,
        address _borrower,
        uint _collShares,
        uint _debt,
        uint _newCollShares,
        uint _newDebt,
        CdpOperation _operation
    ) internal {
        _setCdpCollShares(_cdpId, _newCollShares);
        _setCdpDebt(_cdpId, _newDebt);

        uint _newStake = _updateStakeAndTotalStakes(_cdpId);

        emit CdpUpdated(
            _cdpId,
            _borrower,
            _debt,
            _collShares,
            _newDebt,
            _newCollShares,
            _newStake,
            _operation
        );
    }

    /**
     * @notice Set the collateral of a CDP
     * @param _cdpId The ID of the CDP
     * @param _newCollShares New collateral value, in stETH shares
     */
    function _setCdpCollShares(bytes32 _cdpId, uint _newCollShares) internal {
        Cdps[_cdpId].collShares = _newCollShares;
    }

    /**
     * @notice Set the debt of a CDP
     * @param _cdpId The ID of the CDP
     * @param _newDebt New debt units value
     */
    function _setCdpDebt(bytes32 _cdpId, uint _newDebt) internal {
        Cdps[_cdpId].debt = _newDebt;
    }
}
