// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;
import "./Interfaces/ICdpManagerData.sol";
import "./Interfaces/ICollSurplusPool.sol";
import "./Interfaces/IEBTCToken.sol";
import "./Interfaces/ISortedCdps.sol";
import "./Dependencies/ICollateralTokenOracle.sol";
import "./CdpManagerStorage.sol";

contract LiquidationLibrary is CdpManagerStorage {
    constructor(
        address _borrowerOperationsAddress,
        address _collSurplusPool,
        address _ebtcToken,
        address _sortedCdps,
        address _activePool,
        address _priceFeed,
        address _collateral
    )
        CdpManagerStorage(
            address(0),
            address(0),
            _borrowerOperationsAddress,
            _collSurplusPool,
            _ebtcToken,
            _sortedCdps,
            _activePool,
            _priceFeed,
            _collateral
        )
    {}

    /// @notice Single CDP liquidation function (fully).
    /// @notice callable by anyone, attempts to liquidate the CdpId. Executes successfully if Cdp meets the conditions for liquidation (e.g. in Normal Mode, it liquidates if the Cdp's ICR < the system MCR).
    function liquidate(bytes32 _cdpId) external nonReentrantSelfAndBOps {
        _liquidateSingle(_cdpId, 0, _cdpId, _cdpId);
    }

    // Single CDP liquidation function (partially).
    function partiallyLiquidate(
        bytes32 _cdpId,
        uint256 _partialAmount,
        bytes32 _upperPartialHint,
        bytes32 _lowerPartialHint
    ) external nonReentrantSelfAndBOps {
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
        uint256 _ICR = getICR(_cdpId, _price);
        (uint _TCR, uint systemColl, uint systemDebt) = _getTCRWithTotalCollAndDebt(_price);

        // If CDP is above MCR
        if (_ICR >= MCR) {
            // We must be in RM
            require(
                _TCR < CCR,
                "CdpManager: ICR is not below liquidation threshold in current mode"
            );

            // == Grace Period == //
            require(
                lastGracePeriodStartTimestamp != UNSET_TIMESTAMP,
                "CdpManager: Recovery Mode grace period not started"
            );
            require(
                block.timestamp > lastGracePeriodStartTimestamp + recoveryModeGracePeriod,
                "CdpManager: Recovery mode grace period still in effect"
            );
        } // Implicit Else Case, Implies ICR < MRC, meaning the CDP is liquidatable

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
            0,
            0,
            false
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
            0,
            0,
            false
        );

        _liquidateSingleCDP(_liqState, _rs);
    }

    // liquidate given CDP by repaying debt in full or partially if its ICR is below MCR or TCR in recovery mode.
    // For partial liquidation, caller should use HintHelper smart contract to get correct hints for reinsertion into sorted CDP list
    function _liquidateSingleCDP(
        LocalVar_InternalLiquidate memory _liqState,
        LocalVar_RecoveryLiquidate memory _recoveryState
    ) internal {
        LiquidationValues memory liquidationValues;

        uint256 startingSystemDebt = _recoveryState.entireSystemDebt;
        uint256 startingSystemColl = _recoveryState.entireSystemColl;

        if (_liqState._partialAmount == 0) {
            (
                liquidationValues.debtToOffset,
                liquidationValues.totalCollToSendToLiquidator,
                liquidationValues.debtToRedistribute,
                liquidationValues.collReward,
                liquidationValues.collSurplus
            ) = _liquidateCDPByExternalLiquidator(_liqState, _recoveryState);
        } else {
            (
                liquidationValues.debtToOffset,
                liquidationValues.totalCollToSendToLiquidator
            ) = _liquidateCDPPartially(_liqState);
            if (
                liquidationValues.totalCollToSendToLiquidator == 0 &&
                liquidationValues.debtToOffset == 0
            ) {
                // retry with fully liquidation
                (
                    liquidationValues.debtToOffset,
                    liquidationValues.totalCollToSendToLiquidator,
                    liquidationValues.debtToRedistribute,
                    liquidationValues.collReward,
                    liquidationValues.collSurplus
                ) = _liquidateCDPByExternalLiquidator(_liqState, _recoveryState);
            }
        }

        _finalizeExternalLiquidation(
            liquidationValues.debtToOffset,
            liquidationValues.totalCollToSendToLiquidator,
            liquidationValues.debtToRedistribute,
            liquidationValues.collReward,
            liquidationValues.collSurplus,
            startingSystemColl,
            startingSystemDebt,
            _liqState._price
        );
    }

    // liquidate (and close) the CDP from an external liquidator
    // this function would return the liquidated debt and collateral of the given CDP
    function _liquidateCDPByExternalLiquidator(
        LocalVar_InternalLiquidate memory _liqState,
        LocalVar_RecoveryLiquidate memory _recoveryState
    ) private returns (uint256, uint256, uint256, uint256, uint256) {
        if (_liqState._recoveryModeAtStart) {
            LocalVar_RecoveryLiquidate memory _outputState = _liquidateSingleCDPInRecoveryMode(
                _recoveryState
            );

            // housekeeping leftover collateral for liquidated CDP
            if (_outputState.totalColSurplus > 0) {
                activePool.sendStEthColl(address(collSurplusPool), _outputState.totalColSurplus);
            }

            return (
                _outputState.totalDebtToBurn,
                _outputState.totalColToSend,
                _outputState.totalDebtToRedistribute,
                _outputState.totalColReward,
                _outputState.totalColSurplus
            );
        } else {
            LocalVar_InternalLiquidate memory _outputState = _liquidateSingleCDPInNormalMode(
                _liqState
            );
            return (
                _outputState.totalDebtToBurn,
                _outputState.totalColToSend,
                _outputState.totalDebtToRedistribute,
                _outputState.totalColReward,
                _outputState.totalColSurplus
            );
        }
    }

    function _liquidateSingleCDPInNormalMode(
        LocalVar_InternalLiquidate memory _liqState
    ) private returns (LocalVar_InternalLiquidate memory) {
        // liquidate entire debt
        (
            uint256 _totalDebtToBurn,
            uint256 _totalColToSend,
            uint256 _liquidatorReward
        ) = _liquidateCDPByExternalLiquidatorWithoutEvent(_liqState._cdpId, _liqState.sequenceLiq);
        uint256 _cappedColPortion;
        uint256 _collSurplus;
        uint256 _debtToRedistribute;
        address _borrower = sortedCdps.getOwnerAddress(_liqState._cdpId);

        // I don't see an issue emitting the CdpUpdated() event up here and avoiding this extra cache, any objections?
        emit CdpUpdated(
            _liqState._cdpId,
            _borrower,
            _totalDebtToBurn,
            _totalColToSend,
            0,
            0,
            0,
            CdpOperation.liquidateInNormalMode
        );

        {
            (_cappedColPortion, _collSurplus, _debtToRedistribute) = _calculateSurplusAndCap(
                _liqState._ICR,
                _liqState._price,
                _totalDebtToBurn,
                _totalColToSend,
                true
            );
            if (_collSurplus > 0) {
                // due to division precision loss, should be zero surplus in normal mode
                _cappedColPortion = _cappedColPortion + _collSurplus;
                _collSurplus = 0;
            }
            if (_debtToRedistribute > 0) {
                _totalDebtToBurn = _totalDebtToBurn - _debtToRedistribute;
            }
        }
        _liqState.totalDebtToBurn = _liqState.totalDebtToBurn + _totalDebtToBurn;
        _liqState.totalColToSend = _liqState.totalColToSend + _cappedColPortion;
        _liqState.totalDebtToRedistribute = _liqState.totalDebtToRedistribute + _debtToRedistribute;
        _liqState.totalColReward = _liqState.totalColReward + _liquidatorReward;

        // Emit events
        emit CdpLiquidated(
            _liqState._cdpId,
            _borrower,
            _totalDebtToBurn,
            _cappedColPortion,
            CdpOperation.liquidateInNormalMode
        );

        return _liqState;
    }

    function _liquidateSingleCDPInRecoveryMode(
        LocalVar_RecoveryLiquidate memory _recoveryState
    ) private returns (LocalVar_RecoveryLiquidate memory) {
        // liquidate entire debt
        (
            uint256 _totalDebtToBurn,
            uint256 _totalColToSend,
            uint256 _liquidatorReward
        ) = _liquidateCDPByExternalLiquidatorWithoutEvent(
                _recoveryState._cdpId,
                _recoveryState.sequenceLiq
            );

        // cap the liquidated collateral if required
        uint256 _cappedColPortion;
        uint256 _collSurplus;
        uint256 _debtToRedistribute;
        address _borrower = sortedCdps.getOwnerAddress(_recoveryState._cdpId);

        // I don't see an issue emitting the CdpUpdated() event up here and avoiding an extra cache of the values, any objections?
        emit CdpUpdated(
            _recoveryState._cdpId,
            _borrower,
            _totalDebtToBurn,
            _totalColToSend,
            0,
            0,
            0,
            CdpOperation.liquidateInRecoveryMode
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
                collSurplusPool.accountSurplus(_borrower, _collSurplus);
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
        _recoveryState.totalColReward = _recoveryState.totalColReward + _liquidatorReward;

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
            CdpOperation.liquidateInRecoveryMode
        );

        return _recoveryState;
    }

    // liquidate (and close) the CDP from an external liquidator
    // this function would return the liquidated debt and collateral of the given CDP
    // without emmiting events
    function _liquidateCDPByExternalLiquidatorWithoutEvent(
        bytes32 _cdpId,
        bool _sequenceLiq
    ) private returns (uint256, uint256, uint256) {
        // calculate entire debt to repay
        (uint256 entireDebt, uint256 entireColl, ) = getEntireDebtAndColl(_cdpId);

        // housekeeping after liquidation by closing the CDP
        _removeStake(_cdpId);
        uint _liquidatorReward = Cdps[_cdpId].liquidatorRewardShares;
        if (_sequenceLiq) {
            _closeCdpWithoutRemovingSortedCdps(_cdpId, Status.closedByLiquidation);
        } else {
            _closeCdp(_cdpId, Status.closedByLiquidation);
        }

        return (entireDebt, entireColl, _liquidatorReward);
    }

    // Liquidate partially the CDP by an external liquidator
    // This function would return the liquidated debt and collateral of the given CDP
    function _liquidateCDPPartially(
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

        // early return: if new collateral is zero, we have a full liqudiation
        if (newColl == 0) {
            return (0, 0);
        }

        // If we have coll remaining, it must meet minimum CDP size requirements
        _requirePartialLiqCollSize(collateral.getPooledEthByShares(newColl));

        // apply pending debt if any
        // and update CDP internal accounting for debt
        // if there is liquidation redistribution
        uint256 _cachedDebt = Cdps[_cdpId].debt;
        {
            if (_debtAndColl.pendingDebtReward > 0) {
                Cdps[_cdpId].debt = _cachedDebt + _debtAndColl.pendingDebtReward;
            }
        }

        // updating the CDP accounting for partial liquidation
        _partiallyReduceCdpDebt(_cdpId, _partialDebt, _partialColl);

        // reInsert into sorted CDP list after partial liquidation
        {
            _reInsertPartialLiquidation(
                _partialState,
                LiquityMath._computeNominalCR(newColl, newDebt),
                _cachedDebt,
                _debtAndColl.entireColl
            );
            emit CdpPartiallyLiquidated(
                _cdpId,
                sortedCdps.getOwnerAddress(_cdpId),
                _partialDebt,
                _partialColl,
                CdpOperation.partiallyLiquidate
            );
        }
        return (_partialDebt, _partialColl);
    }

    // return CdpId array (in NICR-decreasing order same as SortedCdps)
    // including the last N CDPs in sortedCdps for batch liquidation
    function _sequenceLiqToBatchLiq(
        uint _n,
        bool _recovery,
        uint _price
    ) internal view returns (bytes32[] memory _array) {
        if (_n > 0) {
            bytes32 _last = sortedCdps.getLast();
            bytes32 _first = sortedCdps.getFirst();
            bytes32 _cdpId = _last;

            uint _TCR = _getTCR(_price);

            // get count of liquidatable CDPs
            uint _cnt;
            for (uint i = 0; i < _n && _cdpId != _first; ++i) {
                uint _icr = getICR(_cdpId, _price);
                bool _liquidatable = _canLiquidateInCurrentMode(_recovery, _icr, _TCR);
                if (_liquidatable && Cdps[_cdpId].status == Status.active) {
                    _cnt += 1;
                }
                _cdpId = sortedCdps.getPrev(_cdpId);
            }

            // retrieve liquidatable CDPs
            _array = new bytes32[](_cnt);
            _cdpId = _last;
            uint _j;
            for (uint i = 0; i < _n && _cdpId != _first; ++i) {
                uint _icr = getICR(_cdpId, _price);
                bool _liquidatable = _canLiquidateInCurrentMode(_recovery, _icr, _TCR);
                if (_liquidatable && Cdps[_cdpId].status == Status.active) {
                    _array[_cnt - _j - 1] = _cdpId;
                    _j += 1;
                }
                _cdpId = sortedCdps.getPrev(_cdpId);
            }
            require(_j == _cnt, "LiquidationLibrary: wrong sequence conversion!");
        }
    }

    function _partiallyReduceCdpDebt(bytes32 _cdpId, uint _partialDebt, uint _partialColl) internal {
        Cdp storage _cdp = Cdps[_cdpId];

        uint _coll = _cdp.coll;
        uint _debt = _cdp.debt;

        _cdp.coll = _coll - _partialColl;
        _cdp.debt = _debt - _partialDebt;
        _updateStakeAndTotalStakes(_cdpId);

        _updateRedistributedDebtSnapshot(_cdpId);
    }

    // Re-Insertion into SortedCdp list after partial liquidation
    function _reInsertPartialLiquidation(
        LocalVar_InternalLiquidate memory _partialState,
        uint _newNICR,
        uint _oldDebt,
        uint _oldColl
    ) internal {
        bytes32 _cdpId = _partialState._cdpId;

        // ensure new ICR does NOT decrease due to partial liquidation
        // if original ICR is above LICR
        if (_partialState._ICR > LICR) {
            require(getICR(_cdpId, _partialState._price) >= _partialState._ICR, "!_newICR>=_ICR");
        }

        // reInsert into sorted CDP list
        sortedCdps.reInsert(
            _cdpId,
            _newNICR,
            _partialState._upperPartialHint,
            _partialState._lowerPartialHint
        );
        emit CdpUpdated(
            _cdpId,
            sortedCdps.getOwnerAddress(_cdpId),
            _oldDebt,
            _oldColl,
            Cdps[_cdpId].debt,
            Cdps[_cdpId].coll,
            Cdps[_cdpId].stake,
            CdpOperation.partiallyLiquidate
        );
    }

    function _finalizeExternalLiquidation(
        uint256 totalDebtToBurn,
        uint256 totalColToSend,
        uint256 totalDebtToRedistribute,
        uint256 totalColReward,
        uint256 totalColSurplus,
        uint256 systemInitialCollShares,
        uint256 systemInitialDebt,
        uint256 price
    ) internal {
        // update the staking and collateral snapshots
        _updateSystemSnapshots_excludeCollRemainder(totalColToSend);

        emit Liquidation(totalDebtToBurn, totalColToSend, totalColReward);

        _syncGracePeriodForGivenValues(
            systemInitialCollShares - totalColToSend - totalColSurplus,
            systemInitialDebt - totalDebtToBurn,
            price
        );

        // redistribute debt if any
        if (totalDebtToRedistribute > 0) {
            _redistributeDebt(totalDebtToRedistribute);
        }

        // burn the debt from liquidator
        ebtcToken.burn(msg.sender, totalDebtToBurn);

        // offset debt from Active Pool
        activePool.decreaseEBTCDebt(totalDebtToBurn);

        // CEI: ensure sending back collateral to liquidator is last thing to do
        activePool.sendStEthCollAndLiquidatorReward(msg.sender, totalColToSend, totalColReward);
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
    function liquidateCdps(uint _n) external nonReentrantSelfAndBOps {
        require(_n > 0, "LiquidationLibrary: can't liquidate zero CDP in sequence");

        LocalVariables_OuterLiquidationFunction memory vars;

        LiquidationTotals memory totals;

        // taking fee to avoid accounted for the calculation of the TCR
        _applyPendingGlobalState();

        vars.price = priceFeed.fetchPrice();
        (uint _TCR, uint systemColl, uint systemDebt) = _getTCRWithTotalCollAndDebt(vars.price);
        vars.recoveryModeAtStart = _TCR < CCR ? true : false;

        // Perform the appropriate liquidation sequence - tally the values, and obtain their totals
        bytes32[] memory _batchedCdps;
        if (vars.recoveryModeAtStart) {
            _batchedCdps = _sequenceLiqToBatchLiq(_n, true, vars.price);
            require(_batchedCdps.length > 0, "LiquidationLibrary: nothing to liquidate");
            totals = _getTotalFromBatchLiquidate_RecoveryMode(
                vars.price,
                systemColl,
                systemDebt,
                _batchedCdps,
                true
            );
        } else {
            // if !vars.recoveryModeAtStart
            _batchedCdps = _sequenceLiqToBatchLiq(_n, false, vars.price);
            require(_batchedCdps.length > 0, "LiquidationLibrary: nothing to liquidate");
            totals = _getTotalsFromBatchLiquidate_NormalMode(vars.price, _TCR, _batchedCdps, true);
        }

        require(totals.totalDebtInSequence > 0, "LiquidationLibrary: nothing to liquidate");

        // housekeeping leftover collateral for liquidated CDPs
        if (totals.totalCollSurplus > 0) {
            activePool.sendStEthColl(address(collSurplusPool), totals.totalCollSurplus);
        }

        _finalizeExternalLiquidation(
            totals.totalDebtToOffset,
            totals.totalCollToSendToLiquidator,
            totals.totalDebtToRedistribute,
            totals.totalCollReward,
            totals.totalCollSurplus,
            systemColl,
            systemDebt,
            vars.price
        );
    }

    function _getLiquidationValuesNormalMode(
        uint _price,
        uint _TCR,
        LocalVariables_LiquidationSequence memory vars,
        LiquidationValues memory singleLiquidation,
        bool sequenceLiq
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
            0,
            0,
            sequenceLiq
        );

        LocalVar_InternalLiquidate memory _outputState = _liquidateSingleCDPInNormalMode(_liqState);

        singleLiquidation.entireCdpDebt = _outputState.totalDebtToBurn;
        singleLiquidation.debtToOffset = _outputState.totalDebtToBurn;
        singleLiquidation.totalCollToSendToLiquidator = _outputState.totalColToSend;
        singleLiquidation.collSurplus = _outputState.totalColSurplus;
        singleLiquidation.debtToRedistribute = _outputState.totalDebtToRedistribute;
        singleLiquidation.collReward = _outputState.totalColReward;
    }

    function _getLiquidationValuesRecoveryMode(
        uint _price,
        uint _systemDebt,
        uint _systemColl,
        LocalVariables_LiquidationSequence memory vars,
        LiquidationValues memory singleLiquidation,
        bool sequenceLiq
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
            0,
            0,
            sequenceLiq
        );

        LocalVar_RecoveryLiquidate memory _outputState = _liquidateSingleCDPInRecoveryMode(
            _recState
        );

        singleLiquidation.entireCdpDebt = _outputState.totalDebtToBurn;
        singleLiquidation.debtToOffset = _outputState.totalDebtToBurn;
        singleLiquidation.totalCollToSendToLiquidator = _outputState.totalColToSend;
        singleLiquidation.collSurplus = _outputState.totalColSurplus;
        singleLiquidation.debtToRedistribute = _outputState.totalDebtToRedistribute;
        singleLiquidation.collReward = _outputState.totalColReward;
    }

    /*
     * Attempt to liquidate a custom list of cdps provided by the caller.

     callable by anyone, accepts a custom list of Cdps addresses as an argument. Steps through the provided list and attempts to liquidate every Cdp, until it reaches the end or it runs out of gas. A Cdp is liquidated only if it meets the conditions for liquidation. For a batch of 10 Cdps, the gas costs per liquidated Cdp are roughly between 75K-83K, for a batch of 50 Cdps between 54K-69K.
     */
    function batchLiquidateCdps(bytes32[] memory _cdpArray) external nonReentrantSelfAndBOps {
        require(
            _cdpArray.length != 0,
            "LiquidationLibrary: Calldata address array must not be empty"
        );

        LocalVariables_OuterLiquidationFunction memory vars;
        LiquidationTotals memory totals;

        // taking fee to avoid accounted for the calculation of the TCR
        _applyPendingGlobalState();

        vars.price = priceFeed.fetchPrice();
        (uint _TCR, uint systemColl, uint systemDebt) = _getTCRWithTotalCollAndDebt(vars.price);
        vars.recoveryModeAtStart = _TCR < CCR ? true : false;

        // Perform the appropriate liquidation sequence - tally values and obtain their totals.
        if (vars.recoveryModeAtStart) {
            totals = _getTotalFromBatchLiquidate_RecoveryMode(
                vars.price,
                systemColl,
                systemDebt,
                _cdpArray,
                false
            );
        } else {
            //  if !vars.recoveryModeAtStart
            totals = _getTotalsFromBatchLiquidate_NormalMode(vars.price, _TCR, _cdpArray, false);
        }

        require(totals.totalDebtInSequence > 0, "LiquidationLibrary: nothing to liquidate");

        // housekeeping leftover collateral for liquidated CDPs
        if (totals.totalCollSurplus > 0) {
            activePool.sendStEthColl(address(collSurplusPool), totals.totalCollSurplus);
        }

        _finalizeExternalLiquidation(
            totals.totalDebtToOffset,
            totals.totalCollToSendToLiquidator,
            totals.totalDebtToRedistribute,
            totals.totalCollReward,
            totals.totalCollSurplus,
            systemColl,
            systemDebt,
            vars.price
        );
    }

    /*
     * This function is used when the batch liquidation sequence starts during Recovery Mode. However, it
     * handle the case where the system *leaves* Recovery Mode, part way through the liquidation sequence
     */
    function _getTotalFromBatchLiquidate_RecoveryMode(
        uint _price,
        uint _systemColl,
        uint _systemDebt,
        bytes32[] memory _cdpArray,
        bool sequenceLiq
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
        uint _cnt = _cdpArray.length;
        bool[] memory _liqFlags = new bool[](_cnt);
        uint _liqCnt;
        uint _start = sequenceLiq ? _cnt - 1 : 0;
        for (vars.i = _start; ; ) {
            vars.cdpId = _cdpArray[vars.i];
            // only for active cdps
            if (vars.cdpId != bytes32(0) && Cdps[vars.cdpId].status == Status.active) {
                vars.ICR = getICR(vars.cdpId, _price);

                if (
                    !vars.backToNormalMode &&
                    (vars.ICR < MCR || canLiquidateRecoveryMode(vars.ICR, _TCR))
                ) {
                    vars.price = _price;
                    _applyAccumulatedFeeSplit(vars.cdpId);
                    _getLiquidationValuesRecoveryMode(
                        _price,
                        vars.entireSystemDebt,
                        vars.entireSystemColl,
                        vars,
                        singleLiquidation,
                        sequenceLiq
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
                    _liqFlags[vars.i] = true;
                    _liqCnt += 1;
                } else if (vars.backToNormalMode && vars.ICR < MCR) {
                    _applyAccumulatedFeeSplit(vars.cdpId);
                    _getLiquidationValuesNormalMode(
                        _price,
                        _TCR,
                        vars,
                        singleLiquidation,
                        sequenceLiq
                    );

                    // Add liquidation values to their respective running totals
                    totals = _addLiquidationValuesToTotals(totals, singleLiquidation);
                    _liqFlags[vars.i] = true;
                    _liqCnt += 1;
                }
                // In Normal Mode skip cdps with ICR >= MCR
            }
            if (sequenceLiq) {
                if (vars.i == 0) {
                    break;
                }
                --vars.i;
            } else {
                ++vars.i;
                if (vars.i == _cnt) {
                    break;
                }
            }
        }

        // remove from sortedCdps for sequence liquidation
        if (sequenceLiq) {
            bytes32[] memory _toRemoveIds = _cdpArray;
            if (_liqCnt > 0 && _liqCnt != _cnt) {
                _toRemoveIds = new bytes32[](_liqCnt);
                uint _j;
                for (uint i = 0; i < _cnt; ++i) {
                    if (_liqFlags[i]) {
                        _toRemoveIds[_j] = _cdpArray[i];
                        _j += 1;
                    }
                }
                require(
                    _j == _liqCnt,
                    "LiquidationLibrary: sequence liquidation (recovery mode) count error!"
                );
            }
            if (_liqCnt > 1) {
                sortedCdps.batchRemove(_toRemoveIds);
            } else if (_liqCnt == 1) {
                sortedCdps.remove(_toRemoveIds[0]);
            }
        }
    }

    function _getTotalsFromBatchLiquidate_NormalMode(
        uint _price,
        uint _TCR,
        bytes32[] memory _cdpArray,
        bool sequenceLiq
    ) internal returns (LiquidationTotals memory totals) {
        LocalVariables_LiquidationSequence memory vars;
        LiquidationValues memory singleLiquidation;
        uint _cnt = _cdpArray.length;
        uint _liqCnt;
        uint _start = sequenceLiq ? _cnt - 1 : 0;
        for (vars.i = _start; ; ) {
            vars.cdpId = _cdpArray[vars.i];
            // only for active cdps
            if (vars.cdpId != bytes32(0) && Cdps[vars.cdpId].status == Status.active) {
                vars.ICR = getICR(vars.cdpId, _price);

                if (vars.ICR < MCR) {
                    _applyAccumulatedFeeSplit(vars.cdpId);
                    _getLiquidationValuesNormalMode(
                        _price,
                        _TCR,
                        vars,
                        singleLiquidation,
                        sequenceLiq
                    );

                    // Add liquidation values to their respective running totals
                    totals = _addLiquidationValuesToTotals(totals, singleLiquidation);
                    _liqCnt += 1;
                }
            }
            if (sequenceLiq) {
                if (vars.i == 0) {
                    break;
                }
                --vars.i;
            } else {
                ++vars.i;
                if (vars.i == _cnt) {
                    break;
                }
            }
        }

        // remove from sortedCdps for sequence liquidation
        if (sequenceLiq) {
            require(
                _liqCnt == _cnt,
                "LiquidationLibrary: sequence liquidation (normal mode) count error!"
            );
            if (_cnt > 1) {
                sortedCdps.batchRemove(_cdpArray);
            } else if (_cnt == 1) {
                sortedCdps.remove(_cdpArray[0]);
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
        newTotals.totalCollSurplus = oldTotals.totalCollSurplus + singleLiquidation.collSurplus;
        newTotals.totalCollReward = oldTotals.totalCollReward + singleLiquidation.collReward;

        return newTotals;
    }

    function _redistributeDebt(uint _debt) internal {
        if (_debt == 0) {
            return;
        }

        /*
         * Add distributed debt rewards-per-unit-staked to the running totals. Division uses a "feedback"
         * error correction, to keep the cumulative error low in the running totals systemDebtRedistributionIndex:
         *
         * 1) Form numerators which compensate for the floor division errors that occurred the last time this
         * function was called.
         * 2) Calculate "per-unit-staked" ratios.
         * 3) Multiply each ratio back by its denominator, to reveal the current floor division error.
         * 4) Store these errors for use in the next correction when this function is called.
         * 5) Note: static analysis tools complain about this "division before multiplication", however, it is intended.
         */
        uint EBTCDebtNumerator = (_debt * DECIMAL_PRECISION) + lastEBTCDebtErrorRedistribution;

        // Get the per-unit-staked terms
        uint _totalStakes = totalStakes;
        uint EBTCDebtRewardPerUnitStaked = EBTCDebtNumerator / _totalStakes;

        lastEBTCDebtErrorRedistribution =
            EBTCDebtNumerator -
            (EBTCDebtRewardPerUnitStaked * _totalStakes);

        // Add per-unit-staked terms to the running totals
        systemDebtRedistributionIndex = systemDebtRedistributionIndex + EBTCDebtRewardPerUnitStaked;

        emit LTermsUpdated(systemDebtRedistributionIndex);
    }

    // --- 'require' wrapper functions ---

    function _requirePartialLiqDebtSize(
        uint _partialDebt,
        uint _entireDebt,
        uint _price
    ) internal view {
        require(
            (_partialDebt + _convertDebtDenominationToBtc(MIN_NET_COLL, _price)) <= _entireDebt,
            "LiquidationLibrary: Partial debt liquidated must be less than total debt"
        );
    }

    function _requirePartialLiqCollSize(uint _entireColl) internal pure {
        require(
            _entireColl >= MIN_NET_COLL,
            "LiquidationLibrary: Coll remaining in partially liquidated CDP must be >= minimum"
        );
    }

    // Can liquidate in RM if ICR < TCR AND Enough time has passed
    function canLiquidateRecoveryMode(uint256 icr, uint256 tcr) public view returns (bool) {
        // ICR < TCR and we have waited enough
        return
            icr < tcr &&
            lastGracePeriodStartTimestamp != UNSET_TIMESTAMP &&
            block.timestamp > lastGracePeriodStartTimestamp + recoveryModeGracePeriod;
    }

    function _canLiquidateInCurrentMode(
        bool _recovery,
        uint256 _icr,
        uint256 _TCR
    ) internal view returns (bool) {
        bool _liquidatable = _recovery
            ? (_icr < MCR || canLiquidateRecoveryMode(_icr, _TCR))
            : _icr < MCR;

        return _liquidatable;
    }
}
