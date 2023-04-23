// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./Interfaces/ICdpManagerData.sol";
import "./Interfaces/ICollSurplusPool.sol";
import "./Interfaces/IEBTCToken.sol";
import "./Interfaces/ISortedCdps.sol";
import "./Interfaces/IFeeRecipient.sol";
import "./Dependencies/ICollateralTokenOracle.sol";
import "./CdpManagerStorage.sol";

contract LiquidationLibrary is CdpManagerStorage {
    constructor() CdpManagerStorage(address(0), address(0)) {}

    /// @notice Single CDP liquidation function (fully).
    /// @notice callable by anyone, attempts to liquidate the CdpId. Executes successfully if Cdp meets the conditions for liquidation (e.g. in Normal Mode, it liquidates if the Cdp's ICR < the system MCR).
    function liquidate(bytes32 _cdpId) external {
        _liquidateSingle(_cdpId, 0, _cdpId, _cdpId);
    }

    // Single CDP liquidation function (partially).
    function partiallyLiquidate(
        bytes32 _cdpId,
        uint256 _partialAmount,
        bytes32 _upperPartialHint,
        bytes32 _lowerPartialHint
    ) external {
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
                _contractsCache.activePool.sendStEthColl(
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

        // I don't see an issue emitting the CdpUpdated() event up here and avoiding this extra cache, any objections?
        emit CdpUpdated(
            _liqState._cdpId,
            _borrower,
            _totalDebtToBurn,
            _totalColToSend,
            0,
            0,
            0,
            CdpManagerOperation.liquidateInNormalMode
        );

        {
            (_cappedColPortion, _collSurplus, _debtToRedistribute) = _calculateSurplusAndCap(
                _liqState._ICR,
                _liqState._price,
                _totalDebtToBurn,
                _totalColToSend,
                true
            );
            if (_debtToRedistribute > 0) {
                _totalDebtToBurn = _totalDebtToBurn - _debtToRedistribute;
            }
        }
        _liqState.totalDebtToBurn = _liqState.totalDebtToBurn + _totalDebtToBurn;
        _liqState.totalColToSend = _liqState.totalColToSend + _cappedColPortion;
        _liqState.totalDebtToRedistribute = _liqState.totalDebtToRedistribute + _debtToRedistribute;

        // Emit events
        emit CdpLiquidated(
            _liqState._cdpId,
            _borrower,
            _totalDebtToBurn,
            _cappedColPortion,
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

        // I don't see an issue emitting the CdpUpdated() event up here and avoiding an extra cache of the values, any objections?
        emit CdpUpdated(
            _recoveryState._cdpId,
            _borrower,
            _totalDebtToBurn,
            _totalColToSend,
            0,
            0,
            0,
            CdpManagerOperation.liquidateInRecoveryMode
        );

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
                _recoveryState.totalColSurplus = _recoveryState.totalColSurplus + _collSurplus;
            }
            if (_debtToRedistribute > 0) {
                _totalDebtToBurn = _totalDebtToBurn - _debtToRedistribute;
            }
        }
        _recoveryState.totalDebtToBurn = _recoveryState.totalDebtToBurn + _totalDebtToBurn;
        _recoveryState.totalColToSend = _recoveryState.totalColToSend + _cappedColPortion;
        _recoveryState.totalDebtToRedistribute =
            _recoveryState.totalDebtToRedistribute +
            _debtToRedistribute;

        // check if system back to normal mode
        _recoveryState.entireSystemDebt = _recoveryState.entireSystemDebt > _totalDebtToBurn
            ? _recoveryState.entireSystemDebt - _totalDebtToBurn
            : 0;
        _recoveryState.entireSystemColl = _recoveryState.entireSystemColl > _totalColToSend
            ? _recoveryState.entireSystemColl - _totalColToSend
            : 0;

        emit CdpLiquidated(
            _recoveryState._cdpId,
            _borrower,
            _totalDebtToBurn,
            _cappedColPortion,
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
        uint newDebt = _debtAndColl.entireDebt - _partialDebt;

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
                Cdps[_cdpId].debt = Cdps[_cdpId].debt + _debtAndColl.pendingDebtReward;
            }
            if (_debtAndColl.pendingCollReward > 0) {
                Cdps[_cdpId].coll = Cdps[_cdpId].coll + _debtAndColl.pendingCollReward;
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
                LiquityMath._computeNominalCR(newColl, newDebt),
                _debtAndColl.entireDebt,
                _debtAndColl.entireColl
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

        Cdps[_cdpId].coll = _coll - _partialColl;
        Cdps[_cdpId].debt = _debt - _partialDebt;
        _updateStakeAndTotalStakes(_cdpId);

        _updateCdpRewardSnapshots(_cdpId);
    }

    // Re-Insertion into SortedCdp list after partial liquidation
    function _reInsertPartialLiquidation(
        ContractsCache memory _contractsCache,
        LocalVar_InternalLiquidate memory _partialState,
        uint _newNICR,
        uint _oldDebt,
        uint _oldColl
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
            _oldDebt,
            _oldColl,
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
        _contractsCache.activePool.sendStEthColl(msg.sender, totalColToSend);
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
        // If ICR is less than 103%: give away 103% worth of collateral to liquidator, i.e., repaidDebt * 103% / price
        // If ICR is more than 103%: give away min(ICR, 110%) worth of collateral to liquidator, i.e., repaidDebt * min(ICR, 110%) / price
        // Add LIQUIDATOR_REWARD in case not giving entire collateral away
        uint _incentiveColl;
        if (_ICR > LICR) {
            _incentiveColl = (_totalDebtToBurn * (_ICR > MCR ? MCR : _ICR)) / _price;
        } else {
            if (_fullLiquidation) {
                // for full liquidation, there would be some bad debt to redistribute
                _incentiveColl = collateral.getPooledEthByShares(_totalColToSend);
                uint _debtToRepay = (_incentiveColl * _price) / LICR;
                debtToRedistribute = _debtToRepay < _totalDebtToBurn
                    ? _totalDebtToBurn - _debtToRepay
                    : 0;
            } else {
                // for partial liquidation, new ICR would deteriorate
                // since we give more incentive (103%) than current _ICR allowed
                _incentiveColl = (_totalDebtToBurn * LICR) / _price;
            }
        }
        _incentiveColl = _incentiveColl + (_fullLiquidation ? LIQUIDATOR_REWARD : 0);
        cappedColPortion = collateral.getSharesByPooledEth(_incentiveColl);
        cappedColPortion = cappedColPortion < _totalColToSend ? cappedColPortion : _totalColToSend;
        collSurplus = (cappedColPortion == _totalColToSend) ? 0 : _totalColToSend - cappedColPortion;
    }

    // --- Batch/Sequence liquidation functions ---

    /*
     * Liquidate a sequence of cdps. Closes a maximum number of n cdps with their CR < MCR or CR < TCR in reocvery mode,
     * starting from the one with the lowest collateral ratio in the system, and moving upwards

     callable by anyone, checks for under-collateralized Cdps below MCR and liquidates up to `n`, starting from the Cdp with the lowest collateralization ratio; subject to gas constraints and the actual number of under-collateralized Cdps. The gas costs of `liquidateCdps(uint n)` mainly depend on the number of Cdps that are liquidated, and whether the Cdps are offset against the Stability Pool or redistributed. For n=1, the gas costs per liquidated Cdp are roughly between 215K-400K, for n=5 between 80K-115K, for n=10 between 70K-82K, and for n=50 between 60K-65K.
     */
    function liquidateCdps(uint _n) external {
        require(_n > 0, "CdpManager: can't liquidate zero CDP in sequence");

        ContractsCache memory contractsCache = ContractsCache(
            activePool,
            defaultPool,
            ebtcToken,
            feeRecipient,
            sortedCdps,
            collSurplusPool,
            gasPoolAddress
        );

        LocalVariables_OuterLiquidationFunction memory vars;

        LiquidationTotals memory totals;

        // taking fee to avoid accounted for the calculation of the TCR
        claimStakingSplitFee();

        vars.price = priceFeed.fetchPrice();
        (uint _TCR, uint systemColl, uint systemDebt) = _getTCRWithTotalCollAndDebt(vars.price);
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
            contractsCache.activePool.sendStEthColl(
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
                vars.entireSystemDebt = vars.entireSystemDebt - singleLiquidation.debtToOffset;
                vars.entireSystemColl =
                    vars.entireSystemColl -
                    singleLiquidation.totalCollToSendToLiquidator -
                    singleLiquidation.collSurplus;

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

     callable by anyone, accepts a custom list of Cdps addresses as an argument. Steps through the provided list and attempts to liquidate every Cdp, until it reaches the end or it runs out of gas. A Cdp is liquidated only if it meets the conditions for liquidation. For a batch of 10 Cdps, the gas costs per liquidated Cdp are roughly between 75K-83K, for a batch of 50 Cdps between 54K-69K.
     */
    function batchLiquidateCdps(bytes32[] memory _cdpArray) public {
        require(_cdpArray.length != 0, "CdpManager: Calldata address array must not be empty");

        ContractsCache memory contractsCache = ContractsCache(
            activePool,
            defaultPool,
            ebtcToken,
            feeRecipient,
            sortedCdps,
            collSurplusPool,
            gasPoolAddress
        );

        LocalVariables_OuterLiquidationFunction memory vars;
        LiquidationTotals memory totals;

        // taking fee to avoid accounted for the calculation of the TCR
        claimStakingSplitFee();

        vars.price = priceFeed.fetchPrice();
        (uint _TCR, uint systemColl, uint systemDebt) = _getTCRWithTotalCollAndDebt(vars.price);
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
            contractsCache.activePool.sendStEthColl(
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
                vars.entireSystemDebt = vars.entireSystemDebt - singleLiquidation.debtToOffset;
                vars.entireSystemColl =
                    vars.entireSystemColl -
                    singleLiquidation.totalCollToSendToLiquidator -
                    singleLiquidation.collSurplus;

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
        newTotals.totalDebtInSequence =
            oldTotals.totalDebtInSequence +
            singleLiquidation.entireCdpDebt;
        newTotals.totalDebtToOffset = oldTotals.totalDebtToOffset + singleLiquidation.debtToOffset;
        newTotals.totalCollToSendToLiquidator =
            oldTotals.totalCollToSendToLiquidator +
            singleLiquidation.totalCollToSendToLiquidator;
        newTotals.totalDebtToRedistribute =
            oldTotals.totalDebtToRedistribute +
            singleLiquidation.debtToRedistribute;
        newTotals.totalCollToRedistribute =
            oldTotals.totalCollToRedistribute +
            singleLiquidation.collToRedistribute;
        newTotals.totalCollSurplus = oldTotals.totalCollSurplus + singleLiquidation.collSurplus;

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

    // --- Helper functions ---

    // Return the nominal collateral ratio (ICR) of a given Cdp, without the price.
    // Takes a cdp's pending coll and debt rewards from redistributions into account.
    function getNominalICR(bytes32 _cdpId) public view returns (uint) {
        (uint currentEBTCDebt, uint currentETH, , ) = getEntireDebtAndColl(_cdpId);

        uint NICR = LiquityMath._computeNominalCR(currentETH, currentEBTCDebt);
        return NICR;
    }

    // Return the current collateral ratio (ICR) of a given Cdp.
    //Takes a cdp's pending coll and debt rewards from redistributions into account.
    function getCurrentICR(bytes32 _cdpId, uint _price) public view returns (uint) {
        (uint currentEBTCDebt, uint currentETH, , ) = getEntireDebtAndColl(_cdpId);

        uint _underlyingCollateral = collateral.getPooledEthByShares(currentETH);
        uint ICR = LiquityMath._computeCR(_underlyingCollateral, currentEBTCDebt, _price);
        return ICR;
    }

    function applyPendingRewards(bytes32 _cdpId) external {
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
    function updateCdpRewardSnapshots(bytes32 _cdpId) external {
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
    function getPendingETHReward(bytes32 _cdpId) public view returns (uint) {
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
    ) public view returns (uint pendingEBTCDebtReward) {
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

    function hasPendingRewards(bytes32 _cdpId) public view returns (bool) {
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
    ) public view returns (uint debt, uint coll, uint pendingEBTCDebtReward, uint pendingETHReward) {
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

    function removeStake(bytes32 _cdpId) external {
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
    function getTotalStakeForFeeTaken(uint _feeTaken) public view returns (uint, uint) {
        uint stake = _computeNewStake(_feeTaken);
        uint _newTotalStakes = totalStakes - stake;
        return (_newTotalStakes, stake);
    }

    function updateStakeAndTotalStakes(bytes32 _cdpId) external returns (uint) {
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

    function closeCdp(bytes32 _cdpId) external {
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

        uint activeColl = _activePool.getStEthColl();
        uint liquidatedColl = _defaultPool.getStEthColl();
        totalCollateralSnapshot = (activeColl - _collRemainder) + liquidatedColl;

        emit SystemSnapshotsUpdated(totalStakesSnapshot, totalCollateralSnapshot);
    }

    // Push the owner's address to the Cdp owners list, and record the corresponding array index on the Cdp struct
    function addCdpIdToArray(bytes32 _cdpId) external returns (uint index) {
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
    function getTCR(uint _price) external view returns (uint) {
        return _getTCR(_price);
    }

    /**
    reveals whether or not the system is in Recovery Mode (i.e. whether the Total Collateralization Ratio (TCR) is below the Critical Collateralization Ratio (CCR)).
    */
    function checkRecoveryMode(uint _price) external view returns (bool) {
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
    function claimStakingSplitFee() public {
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
        ContractsCache memory _cachedContracts,
        uint256 _feeTaken,
        uint256 _deltaPerUnit,
        uint256 _newErrorPerUnit
    ) internal {
        uint _oldPerUnit = stFeePerUnitg;
        stFeePerUnitg = stFeePerUnitg + _deltaPerUnit;
        stFeePerUnitgError = _newErrorPerUnit;

        require(
            _cachedContracts.activePool.getStEthColl() > _feeTaken,
            "CDPManager: fee split is too big"
        );
        address _feeRecipient = address(feeRecipient); // TODO choose other fee recipient?
        _cachedContracts.activePool.sendStEthColl(_feeRecipient, _feeTaken);

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
}
