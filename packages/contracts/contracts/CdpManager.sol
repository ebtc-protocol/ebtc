// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./Interfaces/ICdpManager.sol";
import "./Interfaces/ICollSurplusPool.sol";
import "./Interfaces/IEBTCToken.sol";
import "./Interfaces/ISortedCdps.sol";
import "./Dependencies/ICollateralTokenOracle.sol";
import "./CdpManagerStorage.sol";
import "./Dependencies/Proxy.sol";
import "./Dependencies/EbtcBase.sol";
import "./Dependencies/EbtcMath.sol";

/// @title CdpManager is mainly in charge of all Cdp related core processing like collateral & debt accounting, split fee calculation, redemption, etc
/// @notice Except for redemption, end user typically will interact with BorrowerOeprations for individual Cdp actions
/// @dev CdpManager also handles liquidation through delegatecall to LiquidationLibrary
contract CdpManager is CdpManagerStorage, ICdpManager, Proxy {
    // --- Dependency setter ---

    /// @notice Constructor for CdpManager contract.
    /// @dev Sets up dependencies and initial staking reward split.
    /// @param _liquidationLibraryAddress Address of the liquidation library.
    /// @param _authorityAddress Address of the authority.
    /// @param _borrowerOperationsAddress Address of BorrowerOperations.
    /// @param _collSurplusPoolAddress Address of CollSurplusPool.
    /// @param _ebtcTokenAddress Address of the eBTC token.
    /// @param _sortedCdpsAddress Address of the SortedCDPs.
    /// @param _activePoolAddress Address of the ActivePool.
    /// @param _priceFeedAddress Address of the price feed.
    /// @param _collTokenAddress Address of the collateral token.
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

        (uint256 _oldIndex, uint256 _newIndex) = _readStEthIndex();
        _syncStEthIndex(_oldIndex, _newIndex);
        systemStEthFeePerUnitIndex = DECIMAL_PRECISION;
    }

    // --- Cdp Liquidation functions ---
    // -----------------------------------------------------------------
    //    Cdp ICR     |       Liquidation Behavior (TODO gas compensation?)
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

    /// @notice Fully liquidate a single Cdp by ID. Cdp must meet the criteria for liquidation at the time of execution.
    /// @notice callable by anyone, attempts to liquidate the CdpId. Executes successfully if Cdp meets the conditions for liquidation (e.g. in Normal Mode, it liquidates if the Cdp's ICR < the system MCR).
    /// @dev forwards msg.data directly to the liquidation library using OZ proxy core delegation function
    /// @param _cdpId ID of the Cdp to liquidate.
    function liquidate(bytes32 _cdpId) external override {
        _delegate(liquidationLibrary);
    }

    /// @notice Partially liquidate a single Cdp.
    /// @dev forwards msg.data directly to the liquidation library using OZ proxy core delegation function
    /// @param _cdpId ID of the Cdp to partially liquidate.
    /// @param _partialAmount Amount to partially liquidate.
    /// @param _upperPartialHint Upper hint for reinsertion of the Cdp into the linked list.
    /// @param _lowerPartialHint Lower hint for reinsertion of the Cdp into the linked list.
    function partiallyLiquidate(
        bytes32 _cdpId,
        uint256 _partialAmount,
        bytes32 _upperPartialHint,
        bytes32 _lowerPartialHint
    ) external override {
        _requireAmountGreaterThanMin(_partialAmount);
        _delegate(liquidationLibrary);
    }

    // --- Batch/Sequence liquidation functions ---

    /// @notice Attempt to liquidate a custom list of Cdps provided by the caller
    /// @notice Callable by anyone, accepts a custom list of Cdps addresses as an argument.
    /// @notice Steps through the provided list and attempts to liquidate every Cdp, until it reaches the end or it runs out of gas.
    /// @notice A Cdp is liquidated only if it meets the conditions for liquidation.
    /// @dev forwards msg.data directly to the liquidation library using OZ proxy core delegation function
    /// @param _cdpArray Array of Cdps to liquidate.
    function batchLiquidateCdps(bytes32[] memory _cdpArray) external override {
        _delegate(liquidationLibrary);
    }

    // --- Redemption functions ---

    /// @notice // Redeem as much collateral as possible from given Cdp in exchange for EBTC up to specified maximum
    /// @param _redeemColFromCdp Struct containing variables for redeeming collateral.
    /// @return singleRedemption Struct containing redemption values.
    function _redeemCollateralFromCdp(
        SingleRedemptionInputs memory _redeemColFromCdp
    ) internal returns (SingleRedemptionValues memory singleRedemption) {
        // Determine the remaining amount (lot) to be redeemed,
        // capped by the entire debt of the Cdp minus the liquidation reserve
        singleRedemption.debtToRedeem = EbtcMath._min(
            _redeemColFromCdp.maxEBTCamount,
            Cdps[_redeemColFromCdp.cdpId].debt /// @audit Redeem everything
        );

        singleRedemption.collSharesDrawn = collateral.getSharesByPooledEth(
            (singleRedemption.debtToRedeem * DECIMAL_PRECISION) / _redeemColFromCdp.price
        );

        // Repurposing this struct here to avoid stack too deep.
        CdpDebtAndCollShares memory _oldDebtAndColl = CdpDebtAndCollShares(
            Cdps[_redeemColFromCdp.cdpId].debt,
            Cdps[_redeemColFromCdp.cdpId].coll
        );

        // Decrease the debt and collateral of the current Cdp according to the EBTC lot and corresponding ETH to send
        uint256 newDebt = _oldDebtAndColl.debt - singleRedemption.debtToRedeem;
        uint256 newColl = _oldDebtAndColl.collShares - singleRedemption.collSharesDrawn;

        if (newDebt == 0) {
            // No debt remains, close Cdp
            // No debt left in the Cdp, therefore the cdp gets closed
            {
                address _borrower = sortedCdps.getOwnerAddress(_redeemColFromCdp.cdpId);
                uint256 _liquidatorRewardShares = uint256(
                    Cdps[_redeemColFromCdp.cdpId].liquidatorRewardShares
                );

                singleRedemption.collSurplus = newColl; // Collateral surplus processed on full redemption
                singleRedemption.liquidatorRewardShares = _liquidatorRewardShares;
                singleRedemption.fullRedemption = true;

                _closeCdpByRedemption(
                    _redeemColFromCdp.cdpId,
                    0,
                    newColl,
                    _liquidatorRewardShares,
                    _borrower
                );

                emit CdpUpdated(
                    _redeemColFromCdp.cdpId,
                    _borrower,
                    msg.sender,
                    _oldDebtAndColl.debt,
                    _oldDebtAndColl.collShares,
                    0,
                    0,
                    0,
                    CdpOperation.redeemCollateral
                );
            }
        } else {
            // Debt remains, reinsert Cdp
            uint256 newNICR = EbtcMath._computeNominalCR(newColl, newDebt);

            /*
             * If the provided hint is out of date, we bail since trying to reinsert without a good hint will almost
             * certainly result in running out of gas.
             *
             * If the resultant net coll of the partial is less than the minimum, we bail.
             */
            if (
                newNICR != _redeemColFromCdp.partialRedemptionHintNICR ||
                collateral.getPooledEthByShares(newColl) < MIN_NET_STETH_BALANCE ||
                newDebt < MIN_CHANGE
            ) {
                _updateStakeAndTotalStakes(_redeemColFromCdp.cdpId);

                emit CdpUpdated(
                    _redeemColFromCdp.cdpId,
                    ISortedCdps(sortedCdps).getOwnerAddress(_redeemColFromCdp.cdpId),
                    msg.sender,
                    _oldDebtAndColl.debt,
                    _oldDebtAndColl.collShares,
                    _oldDebtAndColl.debt,
                    _oldDebtAndColl.collShares,
                    Cdps[_redeemColFromCdp.cdpId].stake,
                    CdpOperation.failedPartialRedemption
                );

                singleRedemption.cancelledPartial = true;
                return singleRedemption;
            }

            singleRedemption.newPartialNICR = newNICR;

            Cdps[_redeemColFromCdp.cdpId].debt = newDebt;
            Cdps[_redeemColFromCdp.cdpId].coll = newColl;
            _updateStakeAndTotalStakes(_redeemColFromCdp.cdpId);

            emit CdpUpdated(
                _redeemColFromCdp.cdpId,
                ISortedCdps(sortedCdps).getOwnerAddress(_redeemColFromCdp.cdpId),
                msg.sender,
                _oldDebtAndColl.debt,
                _oldDebtAndColl.collShares,
                newDebt,
                newColl,
                Cdps[_redeemColFromCdp.cdpId].stake,
                CdpOperation.redeemCollateral
            );
        }

        return singleRedemption;
    }

    /*
     * Called when a full redemption occurs, and closes the cdp.
     * The redeemer swaps (debt) EBTC for (debt)
     * worth of stETH, so the stETH liquidation reserve is all that remains.
     * In order to close the cdp, the stETH liquidation reserve is returned to the Cdp owner,
     * The debt recorded on the cdp's struct is zero'd elswhere, in _closeCdp.
     * Any surplus stETH left in the cdp, is sent to the Coll surplus pool, and can be later claimed by the borrower.
     */
    function _closeCdpByRedemption(
        bytes32 _cdpId,
        uint256 _EBTC,
        uint256 _collSurplus,
        uint256 _liquidatorRewardShares,
        address _borrower
    ) internal {
        _closeCdpWithoutRemovingSortedCdps(_cdpId, Status.closedByRedemption);

        // Update Active Pool EBTC, and send ETH to account
        activePool.decreaseSystemDebt(_EBTC);

        // Register stETH surplus from upcoming transfers of stETH collateral and liquidator reward shares
        collSurplusPool.increaseSurplusCollShares(
            _cdpId,
            _borrower,
            _collSurplus,
            _liquidatorRewardShares
        );

        // CEI: send stETH coll and liquidator reward shares from Active Pool to CollSurplus Pool
        activePool.transferSystemCollSharesAndLiquidatorReward(
            address(collSurplusPool),
            _collSurplus,
            _liquidatorRewardShares
        );
    }

    /// @notice Returns true if the CdpId specified is the lowest-ICR Cdp in the linked list that still has MCR > ICR
    /// @dev Returns false if the specified CdpId hint is blank
    /// @dev Returns false if the specified CdpId hint doesn't exist in the list
    /// @dev Returns false if the ICR of the specified CdpId is < MCR
    /// @dev Returns true if the specified CdpId is not blank, exists in the list, has an ICR > MCR, and the next lower Cdp in the list is either blank or has an ICR < MCR.
    function _isValidFirstRedemptionHint(
        bytes32 _firstRedemptionHint,
        uint256 _price
    ) internal view returns (bool) {
        if (
            _firstRedemptionHint == sortedCdps.nonExistId() ||
            !sortedCdps.contains(_firstRedemptionHint) ||
            getSyncedICR(_firstRedemptionHint, _price) < MCR
        ) {
            return false;
        }

        bytes32 nextCdp = sortedCdps.getNext(_firstRedemptionHint);
        return nextCdp == sortedCdps.nonExistId() || getSyncedICR(nextCdp, _price) < MCR;
    }

    /// @notice Send _debt EBTC to the system and redeem the corresponding amount of collateral
    /// @notice from as many Cdps as are needed to fill the redemption request.
    /// @notice
    /// @notice Note that if _debt is very large, this function can run out of gas, specially if traversed cdps are small (meaning many small Cdps are redeemed against).
    /// @notice This can be easily avoided by splitting the total _debt in appropriate chunks and calling the function multiple times.
    /// @notice
    /// @notice There is a optional parameter `_maxIterations` which can also be provided, so the loop through Cdps is capped (if it’s zero, it will be ignored).
    /// @notice This makes it easier to avoid OOG for the frontend, as only knowing approximately the average cost of an iteration is enough,
    /// @notice without needing to know the "topology" of the cdp list. It also avoids the need to set the cap in stone in the contract,
    /// @notice nor doing gas calculations, as both gas price and opcode costs can vary.
    /// @notice
    /// @notice All Cdps that are redeemed from -- with the likely exception of the last one -- will end up with no debt left,
    /// @notice therefore they will be closed.
    /// @notice If the last Cdp does have some remaining debt & collateral (it has a valid meaningful ICR) then reinsertion of the CDP
    /// @notice could be anywhere in the entire SortedCdps list, therefore this redemption requires a hint.
    /// @notice
    /// @notice A frontend should use HintHelper.getRedemptionHints() to calculate what the ICR of this Cdp will be after redemption,
    /// @notice and pass a hint for its position in the SortedCdps list along with the ICR value that the hint was found for.
    /// @notice
    /// @notice If another transaction modifies the list between calling getRedemptionHints()
    /// @notice and passing the hints to redeemCollateral(), it is very likely that the last (partially)
    /// @notice redeemed Cdp would end up with a different ICR than what the hint is for.
    /// @notice
    /// @notice In this case, the redemption will stop after the last completely redeemed Cdp and the sender will keep the
    /// @notice remaining EBTC amount, which they can attempt to redeem later.
    /// @param _debt The total eBTC debt amount to be redeemed
    /// @param _firstRedemptionHint The first CdpId to be considered for redemption, could get from HintHelper.getRedemptionHints()
    /// @param _upperPartialRedemptionHint The first CdpId to be considered for redemption, could get from HintHelper.getApproxHint(_partialRedemptionHintNICR) then SortedCdps.findInsertPosition(_partialRedemptionHintNICR)
    /// @param _lowerPartialRedemptionHint The first CdpId to be considered for redemption, could get from HintHelper.getApproxHint(_partialRedemptionHintNICR) then SortedCdps.findInsertPosition(_partialRedemptionHintNICR)
    /// @param _partialRedemptionHintNICR The new Nominal Collateral Ratio (NICR) of the last redeemed CDP after partial redemption, could get from HintHelper.getRedemptionHints()
    /// @param _maxIterations The maximum allowed iteration along the SortedCdps loop, if zero then there is no limit
    /// @param _maxFeePercentage The maximum allowed redemption fee for this redemption
    function redeemCollateral(
        uint256 _debt,
        bytes32 _firstRedemptionHint,
        bytes32 _upperPartialRedemptionHint,
        bytes32 _lowerPartialRedemptionHint,
        uint256 _partialRedemptionHintNICR,
        uint256 _maxIterations,
        uint256 _maxFeePercentage
    ) external override nonReentrantSelfAndBOps {
        RedemptionTotals memory totals;

        // early check to ensure redemption is not paused
        require(redemptionsPaused == false, "CdpManager: Redemptions Paused");

        _requireValidMaxFeePercentage(_maxFeePercentage);

        _syncGlobalAccounting(); // Apply state, we will syncGracePeriod at end of function

        totals.price = priceFeed.fetchPrice();
        {
            (
                uint256 tcrAtStart,
                uint256 systemCollSharesAtStart,
                uint256 systemDebtAtStart
            ) = _getTCRWithSystemDebtAndCollShares(totals.price);
            totals.tcrAtStart = tcrAtStart;
            totals.systemCollSharesAtStart = systemCollSharesAtStart;
            totals.systemDebtAtStart = systemDebtAtStart;

            if (!activePool.twapDisabled()) {
                try activePool.observe() returns (uint256 _twapSystemDebtAtStart) {
                    // @audit Return the smaller value of the two, bias towards a larger redemption scaling fee
                    totals.twapSystemDebtAtStart = EbtcMath._min(
                        _twapSystemDebtAtStart,
                        systemDebtAtStart
                    );
                } catch {
                    totals.twapSystemDebtAtStart = systemDebtAtStart;
                }
            } else {
                totals.twapSystemDebtAtStart = systemDebtAtStart;
            }
        }

        _requireTCRisNotBelowMCR(totals.price, totals.tcrAtStart);
        _requireAmountGreaterThanMin(_debt);

        _requireEbtcBalanceCoversRedemptionAndWithinSupply(
            msg.sender,
            _debt,
            totals.systemDebtAtStart
        );

        totals.remainingDebtToRedeem = _debt;
        address currentBorrower;
        bytes32 _cId = _firstRedemptionHint;

        if (_isValidFirstRedemptionHint(_firstRedemptionHint, totals.price)) {
            currentBorrower = sortedCdps.getOwnerAddress(_firstRedemptionHint);
        } else {
            _cId = sortedCdps.getLast();
            currentBorrower = sortedCdps.getOwnerAddress(_cId);
            // Find the first cdp with ICR >= MCR
            while (currentBorrower != address(0) && getSyncedICR(_cId, totals.price) < MCR) {
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
        uint256 _numCdpsFullyRedeemed;

        /**
            Core Redemption Loop
        */
        uint256 _partialRedeemedNewNICR;
        while (
            currentBorrower != address(0) && totals.remainingDebtToRedeem > 0 && _maxIterations > 0
        ) {
            // Save the address of the Cdp preceding the current one, before potentially modifying the list
            {
                _syncAccounting(_cId); /// @audit This happens even if the re-insertion doesn't

                SingleRedemptionInputs memory _redeemColFromCdp = SingleRedemptionInputs(
                    _cId,
                    totals.remainingDebtToRedeem,
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

                // prepare for reinsertion if there is partial redemption
                if (singleRedemption.newPartialNICR > 0) {
                    _partialRedeemedNewNICR = singleRedemption.newPartialNICR;
                }

                totals.debtToRedeem = totals.debtToRedeem + singleRedemption.debtToRedeem;
                totals.collSharesDrawn = totals.collSharesDrawn + singleRedemption.collSharesDrawn;
                totals.remainingDebtToRedeem =
                    totals.remainingDebtToRedeem -
                    singleRedemption.debtToRedeem;
                totals.totalCollSharesSurplus =
                    totals.totalCollSharesSurplus +
                    singleRedemption.collSurplus;

                bytes32 _nextId = sortedCdps.getPrev(_cId);
                if (singleRedemption.fullRedemption) {
                    _lastRedeemed = _cId;
                    _numCdpsFullyRedeemed = _numCdpsFullyRedeemed + 1;
                    _cId = _nextId;
                }

                address nextUserToCheck = sortedCdps.getOwnerAddress(_nextId);
                currentBorrower = nextUserToCheck;
            }
            _maxIterations--;
        }
        require(totals.collSharesDrawn > 0, "CdpManager: Unable to redeem any amount");

        // remove from sortedCdps
        if (_numCdpsFullyRedeemed == 1) {
            sortedCdps.remove(_firstRedeemed);
        } else if (_numCdpsFullyRedeemed > 1) {
            bytes32[] memory _toRemoveIds = _getCdpIdsToRemove(
                _lastRedeemed,
                _numCdpsFullyRedeemed,
                _firstRedeemed
            );
            sortedCdps.batchRemove(_toRemoveIds);
        }

        // reinsert partially redemeed CDP if any
        if (_cId != bytes32(0) && _partialRedeemedNewNICR > 0) {
            sortedCdps.reInsert(
                _cId,
                _partialRedeemedNewNICR,
                _upperPartialRedemptionHint,
                _lowerPartialRedemptionHint
            );
        }

        // Decay the baseRate due to time passed, and then increase it according to the size of this redemption.
        // Use the saved total EBTC supply value, from before it was reduced by the redemption.
        _updateBaseRateFromRedemption(
            totals.collSharesDrawn,
            totals.price,
            totals.twapSystemDebtAtStart
        );

        // Calculate the ETH fee
        totals.feeCollShares = _getRedemptionFee(totals.collSharesDrawn);

        _requireUserAcceptsFee(totals.feeCollShares, totals.collSharesDrawn, _maxFeePercentage);

        totals.collSharesToRedeemer = totals.collSharesDrawn - totals.feeCollShares;

        _syncGracePeriodForGivenValues(
            totals.systemCollSharesAtStart - totals.collSharesDrawn - totals.totalCollSharesSurplus,
            totals.systemDebtAtStart - totals.debtToRedeem,
            totals.price
        );

        emit Redemption(
            _debt,
            totals.debtToRedeem,
            totals.collSharesDrawn,
            totals.feeCollShares,
            msg.sender
        );

        // Burn the total eBTC that is redeemed
        ebtcToken.burn(msg.sender, totals.debtToRedeem);

        // Update Active Pool eBTC debt internal accounting
        activePool.decreaseSystemDebt(totals.debtToRedeem);

        // Allocate the stETH fee to the FeeRecipient
        activePool.allocateSystemCollSharesToFeeRecipient(totals.feeCollShares);

        // CEI: Send the stETH drawn to the redeemer
        activePool.transferSystemCollShares(msg.sender, totals.collSharesToRedeemer);

        // final check if we not in RecoveryMode at redemption start
        if (!_checkRecoveryModeForTCR(totals.tcrAtStart)) {
            require(
                !_checkRecoveryMode(totals.price),
                "CdpManager: redemption should not trigger RecoveryMode"
            );
        }
    }

    // --- Helper functions ---

    function _getCdpIdsToRemove(
        bytes32 _start,
        uint256 _total,
        bytes32 _end
    ) internal view returns (bytes32[] memory) {
        uint256 _cnt = _total;
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

    /// @notice Synchorize the accounting for the specified Cdp
    /// @notice It will synchronize global accounting with stETH share index first
    /// @notice then apply split fee and debt redistribution if any
    /// @param _cdpId cdpId to sync pending accounting state for
    function syncAccounting(bytes32 _cdpId) external virtual override {
        /// @audit Opening can cause invalid reordering of Cdps due to changing values without reInserting into sortedCdps
        _requireCallerIsBorrowerOperations();
        return _syncAccounting(_cdpId);
    }

    /// @notice Update stake for the specified Cdp and total stake within the system.
    /// @dev Only BorrowerOperations is allowed to call this function
    /// @param _cdpId cdpId to update stake for
    function updateStakeAndTotalStakes(bytes32 _cdpId) external override returns (uint256) {
        _requireCallerIsBorrowerOperations();
        return _updateStakeAndTotalStakes(_cdpId);
    }

    /// @notice Close the specified Cdp by ID.
    /// @dev Only BorrowerOperations is allowed to call this function.
    /// @dev This will close the Cdp and update its status to `closedByOwner`
    /// @dev The collateral and debt will be zero'd out
    /// @dev The Cdp will be removed from the sorted list
    /// @dev The close will emit a `CdpUpdated` event containing closing details
    /// @param _cdpId ID of the Cdp to close
    /// @param _borrower Address of the Cdp borrower
    /// @param _debt The recorded Cdp debt prior to closing
    /// @param _coll The recorded Cdp collateral shares prior to closing
    function closeCdp(
        bytes32 _cdpId,
        address _borrower,
        uint256 _debt,
        uint256 _coll
    ) external override {
        _requireCallerIsBorrowerOperations();
        emit CdpUpdated(_cdpId, _borrower, msg.sender, _debt, _coll, 0, 0, 0, CdpOperation.closeCdp);
        return _closeCdp(_cdpId, Status.closedByOwner);
    }

    // --- Recovery Mode and TCR functions ---

    /// @notice Get the sum of debt units assigned to all Cdps within eBTC system
    /// @dev It is actually the `systemDebt` value of the ActivePool.
    /// @return entireSystemDebt entire system debt accounting value
    function getSystemDebt() public view returns (uint256 entireSystemDebt) {
        return _getSystemDebt();
    }

    /// @notice The total collateralization ratio (TCR) of the system as a cached "view" (maybe outdated)
    /// @dev It is based on the current recorded system debt and collateral.
    /// @dev Possible split fee is not considered with this function.
    /// @dev Please use getSyncedTCR() otherwise
    /// @param _price The current stETH:BTC price
    /// @return TCR The cached total collateralization ratio (TCR) of the system (does not take into account pending global state)
    function getCachedTCR(uint256 _price) external view override returns (uint256) {
        return _getCachedTCR(_price);
    }

    /// @notice Whether or not the system is in Recovery Mode (TCR is below the CCR)
    /// @dev Possible split fee is not considered with this function.
    /// @dev Please use getSyncedTCR() otherwise
    /// @param _price The current stETH:BTC price
    /// @return True if system is in recovery mode with cached values (TCR < CCR), false otherwise
    function checkRecoveryMode(uint256 _price) external view override returns (bool) {
        return _checkRecoveryMode(_price);
    }

    // Check whether or not the system *would be* in Recovery Mode,
    // given an ETH:USD price, and the entire system coll and debt.
    function _checkPotentialRecoveryMode(
        uint256 _systemCollShares,
        uint256 _systemDebt,
        uint256 _price
    ) internal view returns (bool) {
        uint256 TCR = _computeTCRWithGivenSystemValues(_systemCollShares, _systemDebt, _price);
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
        uint256 _ETHDrawn,
        uint256 _price,
        uint256 _totalEBTCSupply
    ) internal returns (uint256) {
        uint256 decayedBaseRate = _calcDecayedBaseRate();

        /* Convert the drawn ETH back to EBTC at face value rate (1 EBTC:1 USD), in order to get
         * the fraction of total supply that was redeemed at face value. */
        uint256 redeemedEBTCFraction = (collateral.getPooledEthByShares(_ETHDrawn) * _price) /
            _totalEBTCSupply;

        uint256 newBaseRate = decayedBaseRate + (redeemedEBTCFraction / beta);
        newBaseRate = EbtcMath._min(newBaseRate, DECIMAL_PRECISION); // cap baseRate at a maximum of 100%
        require(newBaseRate > 0, "CdpManager: new baseRate is zero!"); // Base rate is always non-zero after redemption

        // Update the baseRate state variable
        baseRate = newBaseRate;
        emit BaseRateUpdated(newBaseRate);

        _updateLastRedemptionTimestamp();

        return newBaseRate;
    }

    /// @return current fee rate for redemption with base rate
    function getRedemptionRate() public view override returns (uint256) {
        return _calcRedemptionRate(baseRate);
    }

    /// @return current fee rate for redemption with decayed base rate
    function getRedemptionRateWithDecay() public view override returns (uint256) {
        return _calcRedemptionRate(_calcDecayedBaseRate());
    }

    function _calcRedemptionRate(uint256 _baseRate) internal view returns (uint256) {
        return
            EbtcMath._min(
                redemptionFeeFloor + _baseRate,
                DECIMAL_PRECISION // cap at a maximum of 100%
            );
    }

    function _getRedemptionFee(uint256 _ETHDrawn) internal view returns (uint256) {
        return _calcRedemptionFee(getRedemptionRate(), _ETHDrawn);
    }

    /// @return redemption fee for the specified collateral amount
    /// @param _stETHToRedeem The total expected stETH amount to redeem
    function getRedemptionFeeWithDecay(
        uint256 _stETHToRedeem
    ) external view override returns (uint256) {
        return _calcRedemptionFee(getRedemptionRateWithDecay(), _stETHToRedeem);
    }

    function _calcRedemptionFee(
        uint256 _redemptionRate,
        uint256 _ETHDrawn
    ) internal pure returns (uint256) {
        uint256 redemptionFee = (_redemptionRate * _ETHDrawn) / DECIMAL_PRECISION;
        require(redemptionFee < _ETHDrawn, "CdpManager: Fee would eat up all returned collateral");
        return redemptionFee;
    }

    function _decayBaseRate() internal {
        uint256 decayedBaseRate = _calcDecayedBaseRate();
        require(decayedBaseRate <= DECIMAL_PRECISION, "CdpManager: baseRate too large!"); // The baseRate can decay to 0

        baseRate = decayedBaseRate;
        emit BaseRateUpdated(decayedBaseRate);

        _updateLastRedemptionTimestamp();
    }

    // --- Internal fee functions ---

    // Update the last fee operation time only if time passed >= decay interval. This prevents base rate griefing.
    function _updateLastRedemptionTimestamp() internal {
        uint256 timePassed = block.timestamp > lastRedemptionTimestamp
            ? block.timestamp - lastRedemptionTimestamp
            : 0;

        if (timePassed >= SECONDS_IN_ONE_MINUTE) {
            // Using the effective elapsed time that is consumed so far to update lastRedemptionTimestamp
            // instead block.timestamp for consistency with _calcDecayedBaseRate()
            lastRedemptionTimestamp += _minutesPassedSinceLastRedemption() * SECONDS_IN_ONE_MINUTE;
            emit LastRedemptionTimestampUpdated(block.timestamp);
        }
    }

    function _calcDecayedBaseRate() internal view returns (uint256) {
        uint256 minutesPassed = _minutesPassedSinceLastRedemption();
        uint256 decayFactor = EbtcMath._decPow(minuteDecayFactor, minutesPassed);

        return (baseRate * decayFactor) / DECIMAL_PRECISION;
    }

    function _minutesPassedSinceLastRedemption() internal view returns (uint256) {
        return
            block.timestamp > lastRedemptionTimestamp
                ? ((block.timestamp - lastRedemptionTimestamp) / SECONDS_IN_ONE_MINUTE)
                : 0;
    }

    /// @return timestamp when this contract is deployed
    function getDeploymentStartTime() public view returns (uint256) {
        return deploymentStartTime;
    }

    /// @notice Check whether or not the system *would be* in Recovery Mode,
    /// @notice given an ETH:eBTC price, and the entire system coll and debt.
    /// @param _systemCollShares The total collateral of the system to be used for the TCR calculation
    /// @param _systemDebt The total debt of the system to be used for the TCR calculation
    /// @param _price The ETH:eBTC price to be used for the TCR calculation
    /// @return flag (true or false) whether the system would be in Recovery Mode for specified status parameters
    function checkPotentialRecoveryMode(
        uint256 _systemCollShares,
        uint256 _systemDebt,
        uint256 _price
    ) external view returns (bool) {
        return _checkPotentialRecoveryMode(_systemCollShares, _systemDebt, _price);
    }

    // --- 'require' wrapper functions ---

    function _requireEbtcBalanceCoversRedemptionAndWithinSupply(
        address _redeemer,
        uint256 _amount,
        uint256 _totalSupply
    ) internal view {
        uint256 callerBalance = ebtcToken.balanceOf(_redeemer);
        require(
            callerBalance >= _amount,
            "CdpManager: Requested redemption amount must be <= user's EBTC token balance"
        );
        require(
            callerBalance <= _totalSupply,
            "CdpManager: redeemer's EBTC balance exceeds total supply!"
        );
    }

    function _requireAmountGreaterThanMin(uint256 _amount) internal pure {
        require(_amount >= MIN_CHANGE, "CdpManager: Amount must be greater than min");
    }

    function _requireTCRisNotBelowMCR(uint256 _price, uint256 _TCR) internal view {
        require(_TCR >= MCR, "CdpManager: Cannot redeem when TCR < MCR");
    }

    function _requireValidMaxFeePercentage(uint256 _maxFeePercentage) internal view {
        require(
            _maxFeePercentage >= redemptionFeeFloor && _maxFeePercentage <= DECIMAL_PRECISION,
            "Max fee percentage must be between redemption fee floor and 100%"
        );
    }

    // --- Governance Parameters ---

    /// @notice Set the staking reward split percentage
    /// @dev Only callable by authorized addresses
    /// @param _stakingRewardSplit New staking reward split percentage value
    function setStakingRewardSplit(uint256 _stakingRewardSplit) external requiresAuth {
        require(
            _stakingRewardSplit <= MAX_REWARD_SPLIT,
            "CDPManager: new staking reward split exceeds max"
        );

        syncGlobalAccountingAndGracePeriod();

        stakingRewardSplit = _stakingRewardSplit;
        emit StakingRewardSplitSet(_stakingRewardSplit);
    }

    /// @notice Set the minimum redemption fee floor percentage
    /// @dev Only callable by authorized addresses
    /// @param _redemptionFeeFloor New minimum redemption fee floor percentage
    function setRedemptionFeeFloor(uint256 _redemptionFeeFloor) external requiresAuth {
        require(
            _redemptionFeeFloor >= MIN_REDEMPTION_FEE_FLOOR,
            "CDPManager: new redemption fee floor is lower than minimum"
        );
        require(
            _redemptionFeeFloor <= DECIMAL_PRECISION,
            "CDPManager: new redemption fee floor is higher than maximum"
        );

        syncGlobalAccountingAndGracePeriod();

        redemptionFeeFloor = _redemptionFeeFloor;
        emit RedemptionFeeFloorSet(_redemptionFeeFloor);
    }

    /// @notice Set the minute decay factor for the redemption fee rate
    /// @dev Only callable by authorized addresses
    /// @param _minuteDecayFactor New minute decay factor value
    function setMinuteDecayFactor(uint256 _minuteDecayFactor) external requiresAuth {
        require(
            _minuteDecayFactor >= MIN_MINUTE_DECAY_FACTOR,
            "CDPManager: new minute decay factor out of range"
        );
        require(
            _minuteDecayFactor <= MAX_MINUTE_DECAY_FACTOR,
            "CDPManager: new minute decay factor out of range"
        );

        syncGlobalAccountingAndGracePeriod();

        // decay first according to previous factor
        _decayBaseRate();

        // set new factor after decaying
        minuteDecayFactor = _minuteDecayFactor;
        emit MinuteDecayFactorSet(_minuteDecayFactor);
    }

    /// @notice Set the beta value that controls redemption fee rate
    /// @dev Only callable by authorized addresses
    /// @param _beta New beta value
    function setBeta(uint256 _beta) external requiresAuth {
        syncGlobalAccountingAndGracePeriod();

        _decayBaseRate();

        beta = _beta;
        emit BetaSet(_beta);
    }

    /// @notice Pause or unpause redemptions
    /// @dev Only callable by authorized addresses
    /// @param _paused True to pause redemptions, false to unpause

    function setRedemptionsPaused(bool _paused) external requiresAuth {
        syncGlobalAccountingAndGracePeriod();
        _decayBaseRate();

        redemptionsPaused = _paused;
        emit RedemptionsPaused(_paused);
    }

    // --- Cdp property getters ---

    /// @notice Get status of a Cdp. Named enum values can be found in ICdpManagerData.Status
    /// @param _cdpId ID of the Cdp to get status for
    /// @return Status code of the Cdp
    function getCdpStatus(bytes32 _cdpId) external view override returns (uint256) {
        return uint256(Cdps[_cdpId].status);
    }

    /// @notice Get stake value of a Cdp
    /// @param _cdpId ID of the Cdp to get stake for
    /// @return Stake value of the Cdp
    function getCdpStake(bytes32 _cdpId) external view override returns (uint256) {
        return Cdps[_cdpId].stake;
    }

    /// @notice Get stored debt value of a Cdp, in eBTC units
    /// @notice Cached value - does not include pending changes from redistributions
    /// @param _cdpId ID of the Cdp to get debt for
    /// @return Debt value of the Cdp in eBTC
    function getCdpDebt(bytes32 _cdpId) external view override returns (uint256) {
        return Cdps[_cdpId].debt;
    }

    /// @notice Get stored collateral value of a Cdp, in stETH shares
    /// @notice Cached value - does not include pending changes from staking yield
    /// @param _cdpId ID of the Cdp to get collateral for
    /// @return Collateral value of the Cdp in stETH shares
    function getCdpCollShares(bytes32 _cdpId) external view override returns (uint256) {
        return Cdps[_cdpId].coll;
    }

    /// @notice Get shares value of the liquidator gas incentive reward stored for a Cdp.
    /// @notice The value stored is processed when a Cdp closes.
    /// @dev Upon closing by borrower, This value is returned directly to the borrower.
    /// @dev Upon closing by a position manager, This value is returned directly to the position manager.
    /// @dev Upon a full liquidation, This value is given to liquidators upon fully liquidating the Cdp
    /// @dev Upon redemption, This value is sent to the CollSurplusPool for reclaiming by the borrower.
    /// @param _cdpId ID of the Cdp to get liquidator reward shares for
    /// @return Liquidator reward shares value of the Cdp
    function getCdpLiquidatorRewardShares(bytes32 _cdpId) external view override returns (uint256) {
        return uint256(Cdps[_cdpId].liquidatorRewardShares);
    }

    // --- Cdp property setters, called by BorrowerOperations ---

    /// @notice Initialize all state for new Cdp
    /// @dev Only callable by BorrowerOperations, critical trust assumption
    /// @dev Requires Cdp to be already inserted into linked list correctly
    /// @param _cdpId ID of Cdp to initialize state for
    /// @param _debt Initial debt units of Cdp
    /// @param _coll Initial collateral shares of Cdp
    /// @param _liquidatorRewardShares Liquidator reward shares for Cdp liquidation gas stipend
    /// @param _borrower Address of the Cdp borrower
    function initializeCdp(
        bytes32 _cdpId,
        uint256 _debt,
        uint256 _coll,
        uint256 _liquidatorRewardShares,
        address _borrower
    ) external {
        _requireCallerIsBorrowerOperations();

        Cdps[_cdpId].debt = _debt;
        Cdps[_cdpId].coll = _coll;
        Cdps[_cdpId].status = Status.active;
        Cdps[_cdpId].liquidatorRewardShares = EbtcMath.toUint128(_liquidatorRewardShares);

        cdpStEthFeePerUnitIndex[_cdpId] = systemStEthFeePerUnitIndex; /// @audit We critically assume global accounting is synced here
        _updateRedistributedDebtIndex(_cdpId);
        uint256 stake = _updateStakeAndTotalStakes(_cdpId);

        // Previous debt and coll are known to be zero upon opening a new Cdp
        emit CdpUpdated(
            _cdpId,
            _borrower,
            msg.sender,
            0,
            0,
            _debt,
            _coll,
            stake,
            CdpOperation.openCdp
        );
    }

    /// @notice Set new Cdp debt and collateral values, updating stake accordingly
    /// @dev Only callable by BorrowerOperations, critical trust assumption
    /// @param _cdpId ID of Cdp to update state for
    /// @param _borrower Address of the Cdp borrower
    /// @param _coll Previous collateral shares of Cdp, before update
    /// @param _debt Previous debt units of Cdp, before update.
    /// @param _newColl New collateral shares of Cdp after update operation
    /// @param _newDebt New debt units of Cdp after update operation
    function updateCdp(
        bytes32 _cdpId,
        address _borrower,
        uint256 _coll,
        uint256 _debt,
        uint256 _newColl,
        uint256 _newDebt
    ) external {
        _requireCallerIsBorrowerOperations();

        _setCdpCollShares(_cdpId, _newColl);
        _setCdpDebt(_cdpId, _newDebt);

        uint256 stake = _updateStakeAndTotalStakes(_cdpId);

        emit CdpUpdated(
            _cdpId,
            _borrower,
            msg.sender,
            _debt,
            _coll,
            _newDebt,
            _newColl,
            stake,
            CdpOperation.adjustCdp
        );
    }

    /// @notice Set the collateral of a Cdp
    /// @param _cdpId The ID of the Cdp
    /// @param _newColl New collateral value, in stETH shares
    function _setCdpCollShares(bytes32 _cdpId, uint256 _newColl) internal {
        Cdps[_cdpId].coll = _newColl;
    }

    /// @notice Set the debt of a Cdp
    /// @param _cdpId The ID of the Cdp
    /// @param _newDebt New debt units value
    function _setCdpDebt(bytes32 _cdpId, uint256 _newDebt) internal {
        Cdps[_cdpId].debt = _newDebt;
    }
}
