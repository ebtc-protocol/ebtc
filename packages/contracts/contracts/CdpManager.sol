// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./Interfaces/ICdpManager.sol";
import "./Interfaces/ICollSurplusPool.sol";
import "./Interfaces/IEBTCToken.sol";
import "./Interfaces/ISortedCdps.sol";
import "./Interfaces/IFeeRecipient.sol";
import "./Dependencies/ICollateralTokenOracle.sol";
import "./CdpManagerStorage.sol";
import "./EBTCDeployer.sol";
import "./Dependencies/Proxy.sol";

contract CdpManager is CdpManagerStorage, ICdpManager, Proxy {
    // --- Dependency setter ---
    constructor(
        EBTCDeployer.EbtcAddresses memory _addresses,
        address collTokenAddress
    )
        CdpManagerStorage(
            _addresses.liquidationLibraryAddress,
            _addresses.authorityAddress,
            _addresses.borrowerOperationsAddress,
            _addresses.collSurplusPoolAddress,
            _addresses.ebtcTokenAddress,
            _addresses.feeRecipientAddress,
            _addresses.sortedCdpsAddress,
            _addresses.activePoolAddress,
            _addresses.defaultPoolAddress,
            _addresses.priceFeedAddress,
            collTokenAddress
        )
    {
        emit BorrowerOperationsAddressChanged(_addresses.borrowerOperationsAddress);
        emit ActivePoolAddressChanged(_addresses.activePoolAddress);
        emit DefaultPoolAddressChanged(_addresses.defaultPoolAddress);
        emit CollSurplusPoolAddressChanged(_addresses.collSurplusPoolAddress);
        emit PriceFeedAddressChanged(_addresses.priceFeedAddress);
        emit EBTCTokenAddressChanged(_addresses.ebtcTokenAddress);
        emit SortedCdpsAddressChanged(_addresses.sortedCdpsAddress);
        emit FeeRecipientAddressChanged(_addresses.feeRecipientAddress);
        emit CollateralAddressChanged(collTokenAddress);

        stakingRewardSplit = 2500;
        // Emit initial value for analytics
        emit StakingRewardSplitSet(stakingRewardSplit);

        _syncIndex();
        syncUpdateIndexInterval();
        stFeePerUnitg = 1e18;
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
    /**
    callable by anyone, attempts to liquidate the CdpId. Executes successfully if Cdp meets the conditions for liquidation (e.g. in Normal Mode, it liquidates if the Cdp's ICR < the system MCR).  
    @dev forwards msg.data directly to the liquidation library using OZ proxy core delegation function
     */
    function liquidate(bytes32 _cdpId) external override {
        _delegate(liquidationLibrary);
    }

    // Single CDP liquidation function (partially).
    /// @dev forwards msg.data directly to the liquidation library using OZ proxy core delegation function
    function partiallyLiquidate(
        bytes32 _cdpId,
        uint256 _partialAmount,
        bytes32 _upperPartialHint,
        bytes32 _lowerPartialHint
    ) external override {
        _delegate(liquidationLibrary);
    }

    // --- Batch/Sequence liquidation functions ---

    /*
     * Liquidate a sequence of cdps. Closes a maximum number of n cdps with their CR < MCR or CR < TCR in reocvery mode,
     * starting from the one with the lowest collateral ratio in the system, and moving upwards

     callable by anyone, checks for under-collateralized Cdps below MCR and liquidates up to `n`, starting from the Cdp with the lowest collateralization ratio; subject to gas constraints and the actual number of under-collateralized Cdps. The gas costs of `liquidateCdps(uint n)` mainly depend on the number of Cdps that are liquidated, and whether the Cdps are offset against the Stability Pool or redistributed. For n=1, the gas costs per liquidated Cdp are roughly between 215K-400K, for n=5 between 80K-115K, for n=10 between 70K-82K, and for n=50 between 60K-65K.

     @dev forwards msg.data directly to the liquidation library using OZ proxy core delegation function
     */
    function liquidateCdps(uint _n) external override {
        _delegate(liquidationLibrary);
    }

    /*
     * Attempt to liquidate a custom list of cdps provided by the caller.

     callable by anyone, accepts a custom list of Cdps addresses as an argument. Steps through the provided list and attempts to liquidate every Cdp, until it reaches the end or it runs out of gas. A Cdp is liquidated only if it meets the conditions for liquidation. For a batch of 10 Cdps, the gas costs per liquidated Cdp are roughly between 75K-83K, for a batch of 50 Cdps between 54K-69K.
     @dev forwards msg.data directly to the liquidation library using OZ proxy core delegation function
     */
    function batchLiquidateCdps(bytes32[] memory _cdpArray) public override {
        _delegate(liquidationLibrary);
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

    // Redeem as much collateral as possible from given Cdp in exchange for EBTC up to _maxEBTCamount
    function _redeemCollateralFromCdp(
        LocalVariables_RedeemCollateralFromCdp memory _redeemColFromCdp
    ) internal returns (SingleRedemptionValues memory singleRedemption) {
        // Determine the remaining amount (lot) to be redeemed,
        // capped by the entire debt of the Cdp minus the liquidation reserve
        singleRedemption.eBtcToRedeem = LiquityMath._min(
            _redeemColFromCdp._maxEBTCamount,
            Cdps[_redeemColFromCdp._cdpId].debt
        );

        // Get the stEthToRecieve of equivalent value in USD
        singleRedemption.stEthToRecieve = collateral.getSharesByPooledEth(
            (singleRedemption.eBtcToRedeem * DECIMAL_PRECISION) / _redeemColFromCdp._price
        );

        // Repurposing this struct here to avoid stack too deep.
        LocalVar_CdpDebtColl memory _oldDebtAndColl = LocalVar_CdpDebtColl(
            Cdps[_redeemColFromCdp._cdpId].debt,
            Cdps[_redeemColFromCdp._cdpId].coll,
            0,
            0
        );

        // Decrease the debt and collateral of the current Cdp according to the EBTC lot and corresponding ETH to send
        uint newDebt = _oldDebtAndColl.entireDebt - singleRedemption.eBtcToRedeem;
        uint newColl = _oldDebtAndColl.entireColl - singleRedemption.stEthToRecieve;

        if (newDebt == 0) {
            // No debt remains, close CDP
            // No debt left in the Cdp, therefore the cdp gets closed

            address _borrower = sortedCdps.getOwnerAddress(_redeemColFromCdp._cdpId);
            _redeemCloseCdp(_redeemColFromCdp._cdpId, 0, newColl, _borrower);
            singleRedemption.fullRedemption = true;

            emit CdpUpdated(
                _redeemColFromCdp._cdpId,
                _borrower,
                _oldDebtAndColl.entireDebt,
                _oldDebtAndColl.entireColl,
                0,
                0,
                0,
                CdpManagerOperation.redeemCollateral
            );
        } else {
            // Debt remains, reinsert CDP
            uint newNICR = LiquityMath._computeNominalCR(newColl, newDebt);

            /*
             * If the provided hint is out of date, we bail since trying to reinsert without a good hint will almost
             * certainly result in running out of gas.
             *
             * If the resultant net coll of the partial is less than the minimum, we bail.
             */
            if (newNICR != _redeemColFromCdp._partialRedemptionHintNICR || newColl < MIN_NET_COLL) {
                singleRedemption.cancelledPartial = true;
                return singleRedemption;
            }

            sortedCdps.reInsert(
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
                _oldDebtAndColl.entireDebt,
                _oldDebtAndColl.entireColl,
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
     * The redeemer swaps (debt) EBTC for (debt)
     * worth of stETH, so the stETH liquidation reserve is all that remains.
     * In order to close the cdp, the stETH liquidation reserve is returned to the CDP owner,
     * The debt recorded on the cdp's struct is zero'd elswhere, in _closeCdp.
     * Any surplus stETH left in the cdp, is sent to the Coll surplus pool, and can be later claimed by the borrower.
     */
    function _redeemCloseCdp(
        bytes32 _cdpId, // TODO: Remove?
        uint _EBTC,
        uint _stEth,
        address _borrower
    ) internal {
        uint _liquidatorRewardShares = Cdps[_cdpId].liquidatorRewardShares;

        _removeStake(_cdpId);
        _closeCdpWithoutRemovingSortedCdps(_cdpId, Status.closedByRedemption);

        // Update Active Pool EBTC, and send ETH to account
        activePool.decreaseEBTCDebt(_EBTC);

        // Register stETH surplus from upcoming transfers of stETH from Active Pool and Gas Pool
        collSurplusPool.accountSurplus(_borrower, _stEth + _liquidatorRewardShares);

        // CEI: send stETH coll and liquidator reward shares from Active Pool to CollSurplus Pool
        activePool.sendStEthCollAndLiquidatorReward(
            address(collSurplusPool),
            _stEth,
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
            getCurrentICR(_firstRedemptionHint, _price) < MCR
        ) {
            return false;
        }

        bytes32 nextCdp = _sortedCdps.getNext(_firstRedemptionHint);
        return nextCdp == _sortedCdps.nonExistId() || getCurrentICR(nextCdp, _price) < MCR;
    }

    /** 
    redeems `_EBTCamount` of eBTC for stETH from the system. Decreases the caller’s eBTC balance, and sends them the corresponding amount of stETH. Executes successfully if the caller has sufficient eBTC to redeem. The number of Cdps redeemed from is capped by `_maxIterations`. The borrower has to provide a `_maxFeePercentage` that he/she is willing to accept in case of a fee slippage, i.e. when another redemption transaction is processed first, driving up the redemption fee.
    */

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
        RedemptionTotals memory totals;

        _requireValidMaxFeePercentage(_maxFeePercentage);
        _requireAfterBootstrapPeriod();
        totals.price = priceFeed.fetchPrice();
        _requireTCRoverMCR(totals.price);
        _requireAmountGreaterThanZero(_EBTCamount);
        _requireEBTCBalanceCoversRedemption(ebtcToken, msg.sender, _EBTCamount);

        totals.totalEBTCSupplyAtStart = _getEntireSystemDebt();
        // Confirm redeemer's balance is less than total EBTC supply
        assert(ebtcToken.balanceOf(msg.sender) <= totals.totalEBTCSupplyAtStart);

        totals.remainingEBTC = _EBTCamount;
        address currentBorrower;
        bytes32 _cId = _firstRedemptionHint;

        if (_isValidFirstRedemptionHint(sortedCdps, _firstRedemptionHint, totals.price)) {
            currentBorrower = sortedCdps.existCdpOwners(_firstRedemptionHint);
        } else {
            _cId = sortedCdps.getLast();
            currentBorrower = sortedCdps.getOwnerAddress(_cId);
            // Find the first cdp with ICR >= MCR
            while (currentBorrower != address(0) && getCurrentICR(_cId, totals.price) < MCR) {
                _cId = sortedCdps.getPrev(_cId);
                currentBorrower = sortedCdps.getOwnerAddress(_cId);
            }
        }

        // Loop through the Cdps starting from the one with lowest collateral
        // ratio until _amount of EBTC is exchanged for collateral
        if (_maxIterations == 0) {
            _maxIterations = type(uint256).max;
        }
        bytes32 _firstRedeemed = _cId;
        bytes32 _lastRedeemed = _cId;
        uint _fullRedeemed;
        while (currentBorrower != address(0) && totals.remainingEBTC > 0 && _maxIterations > 0) {
            _maxIterations--;
            // Save the address of the Cdp preceding the current one, before potentially modifying the list
            {
                bytes32 _nextId = sortedCdps.getPrev(_cId);
                address nextUserToCheck = sortedCdps.getOwnerAddress(_nextId);

                _applyPendingRewards(activePool, defaultPool, _cId);

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
                    _redeemColFromCdp
                );
                // Partial redemption was cancelled (out-of-date hint, or new net debt < minimum),
                // therefore we could not redeem from the last Cdp
                if (singleRedemption.cancelledPartial) break;

                totals.totalEBTCToRedeem = totals.totalEBTCToRedeem + singleRedemption.eBtcToRedeem;
                totals.totalETHDrawn = totals.totalETHDrawn + singleRedemption.stEthToRecieve;

                totals.remainingEBTC = totals.remainingEBTC - singleRedemption.eBtcToRedeem;
                currentBorrower = nextUserToCheck;
                if (singleRedemption.fullRedemption) {
                    _lastRedeemed = _cId;
                    _fullRedeemed = _fullRedeemed + 1;
                }
                _cId = _nextId;
            }
        }
        require(totals.totalETHDrawn > 0, "CdpManager: Unable to redeem any amount");

        // remove from sortedCdps
        if (_fullRedeemed == 1) {
            sortedCdps.remove(_firstRedeemed);
        } else if (_fullRedeemed > 1) {
            bytes32[] memory _toRemoveIds = _getCdpIdsToRemove(
                _lastRedeemed,
                _fullRedeemed,
                _firstRedeemed
            );
            sortedCdps.batchRemove(_toRemoveIds);
        }

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

        totals.ETHToSendToRedeemer = totals.totalETHDrawn - totals.ETHFee;

        emit Redemption(_EBTCamount, totals.totalEBTCToRedeem, totals.totalETHDrawn, totals.ETHFee);

        // Burn the total eBTC that is redeemed
        ebtcToken.burn(msg.sender, totals.totalEBTCToRedeem);

        // Update Active Pool eBTC debt internal accounting
        activePool.decreaseEBTCDebt(totals.totalEBTCToRedeem);

        // CEI: Send the stETH drawn to the redeemer
        activePool.sendStEthColl(msg.sender, totals.ETHToSendToRedeemer);

        // CEI: Send the stETH fee to the FeeRecipient
        activePool.sendStEthColl(address(feeRecipient), totals.ETHFee);

        // TODO: an alternative is we could track a variable on the activePool and avoid the transfer, for claim at-will be feeRecipient
        // Then we can avoid the whole feeRecipient contract in every other contract. It can then be governable and switched out. ActivePool can handle sending any extra metadata to the recipient
    }

    // --- Helper functions ---

    function _getCdpIdsToRemove(
        bytes32 _start,
        uint _total,
        bytes32 _end
    ) internal returns (bytes32[] memory) {
        uint _cnt = _total;
        bytes32 _id = _start;
        bytes32[] memory _toRemoveIds = new bytes32[](_total);
        while (_cnt > 0 && _id != bytes32(0)) {
            _toRemoveIds[_total - _cnt] = _id;
            _cnt = _cnt - 1;
            _id = sortedCdps.getNext(_id);
        }
        require(
            _toRemoveIds[0] == _start,
            "LiquidationLibrary: batchRemoveSortedCdpIds check start error!"
        );
        require(
            _toRemoveIds[_total - 1] == _end,
            "LiquidationLibrary: batchRemoveSortedCdpIds check end error!"
        );
        return _toRemoveIds;
    }

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

            uint prevDebt = Cdps[_cdpId].debt;
            uint prevColl = Cdps[_cdpId].coll;

            // Apply pending rewards to cdp's state
            Cdps[_cdpId].debt = prevDebt + pendingEBTCDebtReward;
            Cdps[_cdpId].coll = prevColl + pendingETHReward;

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
                prevDebt,
                prevColl,
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

    // get the pending stETH reward from liquidation redistribution events, for the given Cdp., earned by their stake
    function getPendingETHReward(bytes32 _cdpId) public view override returns (uint) {
        uint snapshotETH = rewardSnapshots[_cdpId].ETH;
        uint rewardPerUnitStaked = L_ETH - snapshotETH;

        if (rewardPerUnitStaked == 0 || Cdps[_cdpId].status != Status.active) {
            return 0;
        }

        uint stake = Cdps[_cdpId].stake;

        uint pendingETHReward = (stake * rewardPerUnitStaked) / DECIMAL_PRECISION;

        return pendingETHReward;
    }

    /**
    get the pending Cdp debt "reward" (i.e. the amount of extra debt assigned to the Cdp) from liquidation redistribution events, earned by their stake
    */
    function getPendingEBTCDebtReward(
        bytes32 _cdpId
    ) public view override returns (uint pendingEBTCDebtReward) {
        uint snapshotEBTCDebt = rewardSnapshots[_cdpId].EBTCDebt;
        Cdp memory cdp = Cdps[_cdpId];

        if (cdp.status != Status.active) {
            return 0;
        }

        uint stake = cdp.stake;

        uint rewardPerUnitStaked = L_EBTCDebt - snapshotEBTCDebt;

        if (rewardPerUnitStaked > 0) {
            pendingEBTCDebtReward = (stake * rewardPerUnitStaked) / DECIMAL_PRECISION;
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
        return (rewardSnapshots[_cdpId].ETH < L_ETH ||
            rewardSnapshots[_cdpId].EBTCDebt < L_EBTCDebt);
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
    /// @notice pending rewards are included in the debt and coll totals returned.
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

        debt = debt + pendingEBTCDebtReward;
        coll = coll + pendingETHReward;
    }

    function removeStake(bytes32 _cdpId) external override {
        _requireCallerIsBorrowerOperations();
        return _removeStake(_cdpId);
    }

    // Remove borrower's stake from the totalStakes sum, and set their stake to 0
    function _removeStake(bytes32 _cdpId) internal {
        uint stake = Cdps[_cdpId].stake;
        totalStakes = totalStakes - stake;
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
        uint _newTotalStakes = totalStakes - stake;
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

        totalStakes = totalStakes + newStake - oldStake;
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
            stake = (_coll * totalStakesSnapshot) / totalCollateralSnapshot;
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
        uint ETHNumerator = (_coll * DECIMAL_PRECISION) + lastETHError_Redistribution;
        uint EBTCDebtNumerator = (_debt * DECIMAL_PRECISION) + lastEBTCDebtError_Redistribution;

        // Get the per-unit-staked terms
        uint ETHRewardPerUnitStaked = ETHNumerator / totalStakes;
        uint EBTCDebtRewardPerUnitStaked = EBTCDebtNumerator / totalStakes;

        lastETHError_Redistribution = ETHNumerator - (ETHRewardPerUnitStaked * totalStakes);
        lastEBTCDebtError_Redistribution =
            EBTCDebtNumerator -
            (EBTCDebtRewardPerUnitStaked * totalStakes);

        // Add per-unit-staked terms to the running totals
        L_ETH = L_ETH + ETHRewardPerUnitStaked;
        L_EBTCDebt = L_EBTCDebt + EBTCDebtRewardPerUnitStaked;

        emit LTermsUpdated(L_ETH, L_EBTCDebt);

        // Transfer coll and debt from ActivePool to DefaultPool
        _activePool.decreaseEBTCDebt(_debt);
        _defaultPool.increaseEBTCDebt(_debt);
        if (_coll > 0) {
            _activePool.sendStEthColl(address(_defaultPool), _coll);
        }
    }

    function closeCdp(bytes32 _cdpId) external override {
        _requireCallerIsBorrowerOperations();
        return _closeCdp(_cdpId, Status.closedByOwner);
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
    function _updateSystemSnapshots_excludeCollRemainder(
        IActivePool _activePool,
        IDefaultPool _defaultPool,
        uint _collRemainder
    ) internal {
        totalStakesSnapshot = totalStakes;

        uint activeColl = _activePool.getStEthColl();
        uint liquidatedColl = _defaultPool.getStEthColl();
        totalCollateralSnapshot = (activeColl - _collRemainder) + liquidatedColl;

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
        index = uint128(CdpIds.length - 1);
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
        uint idxLast = length - 1;

        assert(index <= idxLast);

        bytes32 idToMove = CdpIds[idxLast];

        CdpIds[index] = idToMove;
        Cdps[idToMove].arrayIndex = index;
        emit CdpIndexUpdated(idToMove, index);

        CdpIds.pop();
    }

    // --- Recovery Mode and TCR functions ---

    /**
    Returns the systemic entire debt assigned to Cdps, i.e. the sum of the EBTCDebt in the Active Pool and the Default Pool.
     */
    function getEntireSystemDebt() public view returns (uint entireSystemDebt) {
        return _getEntireSystemDebt();
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
            _takeSplitAndUpdateFeePerUnit(_feeTaken, _deltaFeePerUnit, _perUnitError);
            _updateSystemSnapshots_excludeCollRemainder(activePool, defaultPool, 0);
        }
    }

    function syncUpdateIndexInterval() public override returns (uint) {
        ICollateralTokenOracle _oracle = ICollateralTokenOracle(collateral.getOracle());
        (uint256 epochsPerFrame, uint256 slotsPerEpoch, uint256 secondsPerSlot, ) = _oracle
            .getBeaconSpec();
        uint256 _newInterval = (epochsPerFrame * slotsPerEpoch * secondsPerSlot) / 2;
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
        uint redeemedEBTCFraction = (collateral.getPooledEthByShares(_ETHDrawn) * _price) /
            _totalEBTCSupply;

        uint newBaseRate = decayedBaseRate + (redeemedEBTCFraction / beta);
        newBaseRate = LiquityMath._min(newBaseRate, DECIMAL_PRECISION); // cap baseRate at a maximum of 100%
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

    function _calcRedemptionRate(uint _baseRate) internal view returns (uint) {
        return
            LiquityMath._min(
                redemptionFeeFloor + _baseRate,
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
        uint redemptionFee = (_redemptionRate * _ETHDrawn) / DECIMAL_PRECISION;
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

        _decayBaseRate();
    }

    function _decayBaseRate() internal {
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
            ? block.timestamp - lastFeeOperationTime
            : 0;

        if (timePassed >= SECONDS_IN_ONE_MINUTE) {
            lastFeeOperationTime = block.timestamp;
            emit LastFeeOpTimeUpdated(block.timestamp);
        }
    }

    function _calcDecayedBaseRate() internal view returns (uint) {
        uint minutesPassed = _minutesPassedSinceLastFeeOp();
        uint decayFactor = LiquityMath._decPow(minuteDecayFactor, minutesPassed);

        return (baseRate * decayFactor) / DECIMAL_PRECISION;
    }

    function _minutesPassedSinceLastFeeOp() internal view returns (uint) {
        return
            block.timestamp > lastFeeOperationTime
                ? ((block.timestamp - lastFeeOperationTime) / SECONDS_IN_ONE_MINUTE)
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
        address _feeRecipient = address(feeRecipient); // TODO choose other fee recipient?
        activePool.sendStEthColl(_feeRecipient, _feeTaken);

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

        uint _diffPerUnit = _stFeePerUnitg - stFeePerUnitcdp[_cdpId];
        uint _feeSplitDistributed = _diffPerUnit > 0 ? _oldStake * _diffPerUnit : 0;

        uint _scaledCdpColl = Cdps[_cdpId].coll * DECIMAL_PRECISION;
        require(_scaledCdpColl > _feeSplitDistributed, "CdpManager: fee split is too big for CDP");

        return (_feeSplitDistributed, (_scaledCdpColl - _feeSplitDistributed) / DECIMAL_PRECISION);
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
            block.timestamp >= systemDeploymentTime + BOOTSTRAP_PERIOD,
            "CdpManager: Redemptions are not allowed during bootstrap phase"
        );
    }

    function _requireValidMaxFeePercentage(uint _maxFeePercentage) internal view {
        require(
            _maxFeePercentage >= redemptionFeeFloor && _maxFeePercentage <= DECIMAL_PRECISION,
            "Max fee percentage must be between redemption fee floor and 100%"
        );
    }

    function _requireValidUpdateInterval() internal {
        require(
            block.timestamp - lastIndexTimestamp > INDEX_UPD_INTERVAL,
            "CdpManager: update index too frequent"
        );
    }

    // --- Governance Parameters ---

    function setStakingRewardSplit(uint _stakingRewardSplit) external requiresAuth {
        require(
            _stakingRewardSplit <= MAX_REWARD_SPLIT,
            "CDPManager: new staking reward split exceeds max"
        );

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

        // decay first according to previous factor
        _decayBaseRate();

        // set new factor after decaying
        minuteDecayFactor = _minuteDecayFactor;
        emit MinuteDecayFactorSet(_minuteDecayFactor);
    }

    function setBeta(uint _beta) external requiresAuth {
        _decayBaseRate();

        beta = _beta;
        emit BetaSet(_beta);
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
    function getCdpColl(bytes32 _cdpId) external view override returns (uint) {
        return Cdps[_cdpId].coll;
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

    // --- Cdp property setters, called by BorrowerOperations ---

    /**
     * @notice Set the status of a CDP
     * @param _cdpId The ID of the CDP
     * @param _num The new ICdpManagerData.Satus, as an integer
     */
    function setCdpStatus(bytes32 _cdpId, uint _num) external override {
        _requireCallerIsBorrowerOperations();
        Cdps[_cdpId].status = Status(_num);
    }

    /**
     * @notice Increase the collateral of a CDP
     * @param _cdpId The ID of the CDP
     * @param _collIncrease The amount to collateral to increase, in stETH shares
     * @return The new collateral amount in stETH shares
     */
    function increaseCdpColl(bytes32 _cdpId, uint _collIncrease) external override returns (uint) {
        _requireCallerIsBorrowerOperations();
        uint newColl = Cdps[_cdpId].coll + _collIncrease;
        Cdps[_cdpId].coll = newColl;
        return newColl;
    }

    /**
     * @notice Decrease the collateral of a CDP
     * @param _cdpId The ID of the CDP
     * @param _collDecrease The amount of collateral to decrease, in stETH sharse
     * @return The new collateral amount in stETH shares
     */
    function decreaseCdpColl(bytes32 _cdpId, uint _collDecrease) external override returns (uint) {
        _requireCallerIsBorrowerOperations();
        uint newColl = Cdps[_cdpId].coll - _collDecrease;
        Cdps[_cdpId].coll = newColl;
        return newColl;
    }

    /**
     * @notice Increase the debt of a CDP
     * @param _cdpId The ID of the CDP
     * @param _debtIncrease The amount of debt to increase
     * @return The new debt amount
     */
    function increaseCdpDebt(bytes32 _cdpId, uint _debtIncrease) external override returns (uint) {
        _requireCallerIsBorrowerOperations();
        uint newDebt = Cdps[_cdpId].debt + _debtIncrease;
        Cdps[_cdpId].debt = newDebt;
        return newDebt;
    }

    /**
     * @notice Decrease the debt of a CDP
     * @param _cdpId The ID of the CDP
     * @param _debtDecrease The amount of debt to decrease
     * @return The new debt amount
     */
    function decreaseCdpDebt(bytes32 _cdpId, uint _debtDecrease) external override returns (uint) {
        _requireCallerIsBorrowerOperations();
        uint newDebt = Cdps[_cdpId].debt - _debtDecrease;
        Cdps[_cdpId].debt = newDebt;
        return newDebt;
    }

    /**
     * @notice Set the liquidator reward shares of a CDP
     * @param _cdpId The ID of the CDP
     * @param _liquidatorRewardShares The new liquidator reward shares
     */
    function setCdpLiquidatorRewardShares(
        bytes32 _cdpId,
        uint _liquidatorRewardShares
    ) external override {
        _requireCallerIsBorrowerOperations();
        Cdps[_cdpId].liquidatorRewardShares = _liquidatorRewardShares;
    }
}
