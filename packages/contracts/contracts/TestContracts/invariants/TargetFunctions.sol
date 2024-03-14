// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@crytic/properties/contracts/util/Hevm.sol";

import "../../Interfaces/ICdpManagerData.sol";
import "../../Dependencies/SafeMath.sol";
import "../../CdpManager.sol";
import "../../LiquidationLibrary.sol";
import "../../BorrowerOperations.sol";
import "../../ActivePool.sol";
import "../../CollSurplusPool.sol";
import "../../SortedCdps.sol";
import "../../HintHelpers.sol";
import "../../FeeRecipient.sol";
import "../testnet/PriceFeedTestnet.sol";
import "../CollateralTokenTester.sol";
import "../EBTCTokenTester.sol";
import "../../Governor.sol";
import "../../EBTCDeployer.sol";

import "./Properties.sol";
import "./Actor.sol";
import "./BeforeAfter.sol";
import "./TargetContractSetup.sol";
import "./Asserts.sol";
import "../BaseStorageVariables.sol";

abstract contract TargetFunctions is Properties {
    modifier setup() virtual {
        actor = actors[msg.sender];
        _;
    }

    ///////////////////////////////////////////////////////
    // Helper functions
    ///////////////////////////////////////////////////////

    function _totalCdpsBelowMcr() internal returns (uint256) {
        uint256 ans;
        bytes32 currentCdp = sortedCdps.getFirst();

        uint256 _price = priceFeedMock.getPrice();

        while (currentCdp != bytes32(0)) {
            if (cdpManager.getCachedICR(currentCdp, _price) < cdpManager.MCR()) {
                ++ans;
            }

            currentCdp = sortedCdps.getNext(currentCdp);
        }

        return ans;
    }

    function _getCdpIdsAndICRs() internal view returns (Cdp[] memory ans) {
        ans = new Cdp[](sortedCdps.getSize());
        uint256 i = 0;
        bytes32 currentCdp = sortedCdps.getFirst();

        uint256 _price = priceFeedMock.getPrice();

        while (currentCdp != bytes32(0)) {
            uint256 _currentCdpDebt = cdpManager.getSyncedCdpDebt(currentCdp);
            ans[i++] = Cdp({id: currentCdp, icr: cdpManager.getSyncedICR(currentCdp, _price)}); /// @audit NOTE: Synced to ensure it's realistic

            currentCdp = sortedCdps.getNext(currentCdp);
        }
    }

    function _cdpIdsAndICRsDiff(
        Cdp[] memory superset,
        Cdp[] memory subset
    ) internal returns (Cdp[] memory ans) {
        ans = new Cdp[](superset.length - subset.length);
        uint256 index = 0;
        for (uint256 i = 0; i < superset.length; i++) {
            bool duplicate = false;
            for (uint256 j = 0; j < subset.length; j++) {
                if (superset[i].id == subset[j].id) {
                    duplicate = true;
                }
            }
            if (!duplicate) {
                ans[index++] = superset[i];
            }
        }
    }

    function _getRandomCdp(uint _i) internal view returns (bytes32) {
        uint _cdpIdx = _i % cdpManager.getActiveCdpsCount();
        bytes32[] memory cdpIds = hintHelpers.sortedCdpsToArray();
        return cdpIds[_cdpIdx];
    }

    event FlashLoanAction(uint, uint);

    function _getFlashLoanActions(uint256 value) internal returns (bytes memory) {
        uint256 _actions = between(value, 1, MAX_FLASHLOAN_ACTIONS);
        uint256 _EBTCAmount = between(value, 1, eBTCToken.totalSupply() / 2);
        uint256 _col = between(value, 1, cdpManager.getSystemCollShares() / 2);
        uint256 _n = between(value, 1, cdpManager.getActiveCdpsCount());

        uint256 numberOfCdps = sortedCdps.cdpCountOf(address(actor));
        require(numberOfCdps > 0, "Actor must have at least one CDP open");
        uint256 _i = between(value, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(actor), _i);
        t(_cdpId != bytes32(0), "CDP ID must not be null if the index is valid");

        address[] memory _targets = new address[](_actions);
        bytes[] memory _calldatas = new bytes[](_actions);

        address[] memory _allTargets = new address[](6);
        bytes[] memory _allCalldatas = new bytes[](6);

        _allTargets[0] = address(borrowerOperations);
        _allCalldatas[0] = abi.encodeWithSelector(
            BorrowerOperations.openCdp.selector,
            _EBTCAmount,
            bytes32(0),
            bytes32(0),
            _col
        );

        _allTargets[1] = address(borrowerOperations);
        _allCalldatas[1] = abi.encodeWithSelector(BorrowerOperations.closeCdp.selector, _cdpId);

        _allTargets[2] = address(borrowerOperations);
        _allCalldatas[2] = abi.encodeWithSelector(
            BorrowerOperations.addColl.selector,
            _cdpId,
            _cdpId,
            _cdpId,
            _col
        );

        _allTargets[3] = address(borrowerOperations);
        _allCalldatas[3] = abi.encodeWithSelector(
            BorrowerOperations.withdrawColl.selector,
            _cdpId,
            _col,
            _cdpId,
            _cdpId
        );

        _allTargets[4] = address(borrowerOperations);
        _allCalldatas[4] = abi.encodeWithSelector(
            BorrowerOperations.withdrawDebt.selector,
            _cdpId,
            _EBTCAmount,
            _cdpId,
            _cdpId
        );

        _allTargets[5] = address(borrowerOperations);
        _allCalldatas[5] = abi.encodeWithSelector(
            BorrowerOperations.repayDebt.selector,
            _cdpId,
            _EBTCAmount,
            _cdpId,
            _cdpId
        );

        for (uint256 _j = 0; _j < _actions; ++_j) {
            _i = uint256(keccak256(abi.encodePacked(value, _j, _i))) % _allTargets.length;
            emit FlashLoanAction(_j, _i);

            _targets[_j] = _allTargets[_i];
            _calldatas[_j] = _allCalldatas[_i];
        }

        return abi.encode(_targets, _calldatas);
    }

    function _getFirstCdpWithIcrGteMcr() internal returns (bytes32) {
        bytes32 _cId = sortedCdps.getLast();
        address currentBorrower = sortedCdps.getOwnerAddress(_cId);
        // Find the first cdp with ICR >= MCR
        while (
            currentBorrower != address(0) &&
            cdpManager.getCachedICR(_cId, priceFeedMock.getPrice()) < cdpManager.MCR()
        ) {
            _cId = sortedCdps.getPrev(_cId);
            currentBorrower = sortedCdps.getOwnerAddress(_cId);
        }
        return _cId;
    }

    function _atLeastOneCdpIsLiquidatable(
        Cdp[] memory cdps,
        bool isRecoveryModeBefore
    ) internal view returns (bool atLeastOneCdpIsLiquidatable) {
        for (uint256 i = 0; i < cdps.length; ++i) {
            if (
                cdps[i].icr < cdpManager.MCR() ||
                (cdps[i].icr < cdpManager.CCR() && isRecoveryModeBefore)
            ) {
                atLeastOneCdpIsLiquidatable = true;
                break;
            }
        }
    }

    ///////////////////////////////////////////////////////
    // CdpManager
    ///////////////////////////////////////////////////////

    function _checkL_15IfRecoveryMode() internal {
        if (vars.isRecoveryModeAfter) {
            t(vars.lastGracePeriodStartTimestampIsSetAfter, L_15);
        }
    }

    function liquidate(uint _i) public setup {
        bool success;
        bytes memory returnData;

        require(cdpManager.getActiveCdpsCount() > 1, "Cannot liquidate last CDP");

        bytes32 _cdpId = _getRandomCdp(_i);

        (uint256 entireDebt, ) = cdpManager.getSyncedDebtAndCollShares(_cdpId);
        require(entireDebt > 0, "CDP must have debt");

        _before(_cdpId);

        uint256 _icrToLiq = cdpManager.getSyncedICR(_cdpId, priceFeedMock.getPrice());

        (success, returnData) = actor.proxy(
            address(cdpManager),
            abi.encodeWithSelector(CdpManager.liquidate.selector, _cdpId)
        );

        _after(_cdpId);

        if (success) {
            // SURPLUS-CHECK-1 | The surplus is capped at 4 wei | NOTE: Proxy of growth, storage var would further refine
            if (_icrToLiq <= cdpManager.MCR()) {
                gte(
                    vars.collSurplusPoolBefore + 12,
                    vars.collSurplusPoolAfter,
                    "SURPLUS-CHECK-1_12"
                );
                gte(vars.userSurplusBefore + 12, vars.userSurplusAfter, "SURPLUS-CHECK-2_12");

                gte(vars.collSurplusPoolBefore + 8, vars.collSurplusPoolAfter, "SURPLUS-CHECK-1_8");
                gte(vars.userSurplusBefore + 8, vars.userSurplusAfter, "SURPLUS-CHECK-2_8");

                gte(vars.collSurplusPoolBefore + 4, vars.collSurplusPoolAfter, "SURPLUS-CHECK-1_4");
                gte(vars.userSurplusBefore + 4, vars.userSurplusAfter, "SURPLUS-CHECK-2_4");
            }

            // if ICR >= TCR then we ignore
            // We could check that Liquidated is not above TCR
            if (
                vars.newIcrBefore >= cdpManager.LICR() // 103% else liquidating locks in bad debt
            ) {
                // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/5
                if (vars.newIcrBefore <= vars.newTcrBefore) {
                    gte(vars.newTcrAfter, vars.newTcrBefore, L_12);
                }
            }
            // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/12
            t(
                vars.newIcrBefore < cdpManager.MCR() ||
                    (vars.newIcrBefore < cdpManager.CCR() && vars.isRecoveryModeBefore),
                L_01
            );
            if (
                vars.lastGracePeriodStartTimestampIsSetBefore &&
                vars.isRecoveryModeBefore &&
                vars.isRecoveryModeAfter
            ) {
                eq(
                    vars.lastGracePeriodStartTimestampBefore,
                    vars.lastGracePeriodStartTimestampAfter,
                    L_14
                );
            }

            _checkL_15IfRecoveryMode();

            if (vars.isRecoveryModeBefore && !vars.isRecoveryModeAfter) {
                t(!vars.lastGracePeriodStartTimestampIsSetAfter, L_16);
            }

            gte(
                vars.actorCollAfter,
                vars.actorCollBefore +
                    collateral.getPooledEthByShares(vars.liquidatorRewardSharesBefore),
                L_09
            );

            if (_icrToLiq <= cdpManager.LICR()) {
                //bad debt to redistribute
                lt(cdpManager.lastEBTCDebtErrorRedistribution(), cdpManager.totalStakes(), L_17);
                totalCdpDustMaxCap += cdpManager.getActiveCdpsCount();
            }

            _checkStakeInvariants();
        } else if (vars.sortedCdpsSizeBefore > _i) {
            assertRevertReasonNotEqual(returnData, "Panic(17)");
        }
    }

    function partialLiquidate(uint _i, uint _partialAmount) public setup {
        bool success;
        bytes memory returnData;

        require(cdpManager.getActiveCdpsCount() > 1, "Cannot liquidate last CDP");

        bytes32 _cdpId = _getRandomCdp(_i);

        (uint256 entireDebt, ) = cdpManager.getSyncedDebtAndCollShares(_cdpId);
        require(entireDebt > 0, "CDP must have debt");

        _partialAmount = between(_partialAmount, 0, entireDebt);

        _before(_cdpId);

        (success, returnData) = actor.proxy(
            address(cdpManager),
            abi.encodeWithSelector(
                CdpManager.partiallyLiquidate.selector,
                _cdpId,
                _partialAmount,
                _cdpId,
                _cdpId
            )
        );

        _after(_cdpId);

        if (success) {
            lt(vars.cdpDebtAfter, vars.cdpDebtBefore, "Partial liquidation must reduce CDP debt");

            if (
                vars.newIcrBefore >= cdpManager.LICR() // 103% else liquidating locks in bad debt
            ) {
                // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/5
                if (vars.newIcrBefore <= vars.newTcrBefore) {
                    gte(vars.newTcrAfter, vars.newTcrBefore, L_12);
                }
            }
            // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/12
            t(
                vars.newIcrBefore < cdpManager.MCR() ||
                    (vars.newIcrBefore < cdpManager.CCR() && vars.isRecoveryModeBefore),
                L_01
            );

            eq(
                vars.sortedCdpsSizeAfter,
                vars.sortedCdpsSizeBefore,
                "L-17 : Partial Liquidations do not close Cdps"
            );

            // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/4
            if (vars.sortedCdpsSizeAfter == vars.sortedCdpsSizeBefore) {
                // CDP was not fully liquidated
                gte(
                    collateral.getPooledEthByShares(cdpManager.getCdpCollShares(_cdpId)),
                    borrowerOperations.MIN_NET_STETH_BALANCE(),
                    GENERAL_10
                );
            }

            if (
                vars.lastGracePeriodStartTimestampIsSetBefore &&
                vars.isRecoveryModeBefore &&
                vars.isRecoveryModeAfter
            ) {
                eq(
                    vars.lastGracePeriodStartTimestampBefore,
                    vars.lastGracePeriodStartTimestampAfter,
                    L_14
                );
            }

            _checkL_15IfRecoveryMode();

            if (vars.isRecoveryModeBefore && !vars.isRecoveryModeAfter) {
                t(!vars.lastGracePeriodStartTimestampIsSetAfter, L_16);
            }

            gte(_partialAmount, borrowerOperations.MIN_CHANGE(), GENERAL_16);
            gte(vars.cdpDebtAfter, borrowerOperations.MIN_CHANGE(), GENERAL_15);
        } else {
            assertRevertReasonNotEqual(returnData, "Panic(17)");
        }
    }

    function _checkStakeInvariants() private {
        if (vars.cdpCollAfter < vars.cdpCollBefore) {
            lt(vars.cdpStakeAfter, vars.cdpStakeBefore, CDPM_07);
        }

        if (vars.cdpCollAfter > vars.cdpCollBefore) {
            gt(vars.cdpStakeAfter, vars.cdpStakeBefore, CDPM_08);
        }

        if (vars.totalCollateralSnapshotAfter > 0) {
            eq(
                vars.cdpStakeAfter,
                (vars.cdpCollAfter * vars.totalStakesSnapshotAfter) /
                    vars.totalCollateralSnapshotAfter,
                CDPM_09
            );
        } else {
            eq(vars.cdpStakeAfter, vars.cdpCollAfter, CDPM_09);
        }
    }

    /** Active Pool TWAP Revert Checks */
    function observe() public {
        // We verify that any observation will never revert
        try activePool.observe() {} catch {
            t(false, "Observe Should Never Revert");
        }
    }

    function update() public {
        // We verify that any observation will never revert
        try activePool.update() {} catch {
            t(false, "Update Should Never Revert");
        }
    }

    // NOTE: Added a bunch of stuff in other function to check against overflow reverts

    /** END Active Pool TWAP Revert Checks */

    function liquidateCdps(uint _n) public setup {
        bool success;
        bytes memory returnData;

        require(cdpManager.getActiveCdpsCount() > 1, "Cannot liquidate last CDP");

        _n = between(_n, 1, cdpManager.getActiveCdpsCount());

        Cdp[] memory cdpsBefore = _getCdpIdsAndICRs();

        _before(bytes32(0));

        bytes32[] memory batch = liquidationSequencer.sequenceLiqToBatchLiqWithPrice(
            _n,
            vars.priceBefore
        );

        bool _badDebtToRedistribute = false;
        for (uint i; i < batch.length; i++) {
            bytes32 _idToLiq = batch[i];
        }

        (success, returnData) = actor.proxy(
            address(cdpManager),
            abi.encodeWithSelector(CdpManager.batchLiquidateCdps.selector, batch)
        );

        _after(bytes32(0));

        if (success) {
            Cdp[] memory cdpsAfter = _getCdpIdsAndICRs();

            Cdp[] memory cdpsLiquidated = _cdpIdsAndICRsDiff(cdpsBefore, cdpsAfter);
            gte(
                cdpsLiquidated.length,
                1,
                "liquidateCdps must liquidate at least 1 CDP when successful"
            );
            lte(cdpsLiquidated.length, _n, "liquidateCdps must not liquidate more than n CDPs");
            for (uint256 i = 0; i < cdpsLiquidated.length; ++i) {
                // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/12
                t(
                    cdpsLiquidated[i].icr < cdpManager.MCR() ||
                        (cdpsLiquidated[i].icr < cdpManager.CCR() && vars.isRecoveryModeBefore),
                    L_01
                );
                if (cdpsLiquidated[i].icr <= cdpManager.LICR()) {
                    _badDebtToRedistribute = true;
                }
            }

            // SURPLUS-CHECK-1 | The surplus is capped at 4 wei | NOTE: We use Liquidate for the exact CDP check
            bool hasCdpWithSurplus;
            for (uint256 i = 0; i < cdpsLiquidated.length; ++i) {
                if (cdpsLiquidated[i].icr > cdpManager.MCR()) {
                    hasCdpWithSurplus = true;
                    break;
                }
            }
            // At most, each liquidate cdp must generate 4 wei of rounding error in the surplus
            if (!hasCdpWithSurplus) {
                gte(
                    vars.collSurplusPoolBefore + 12 * cdpsLiquidated.length,
                    vars.collSurplusPoolAfter,
                    "SURPLUS-CHECK-1_12"
                );
                gte(
                    vars.collSurplusPoolBefore + 8 * cdpsLiquidated.length,
                    vars.collSurplusPoolAfter,
                    "SURPLUS-CHECK-1_8"
                );
                gte(
                    vars.collSurplusPoolBefore + 4 * cdpsLiquidated.length,
                    vars.collSurplusPoolAfter,
                    "SURPLUS-CHECK-1_4"
                );
            }

            if (
                vars.lastGracePeriodStartTimestampIsSetBefore &&
                vars.isRecoveryModeBefore &&
                vars.isRecoveryModeAfter
            ) {
                eq(
                    vars.lastGracePeriodStartTimestampBefore,
                    vars.lastGracePeriodStartTimestampAfter,
                    L_14
                );
            }

            _checkL_15IfRecoveryMode();

            if (vars.isRecoveryModeBefore && !vars.isRecoveryModeAfter) {
                t(!vars.lastGracePeriodStartTimestampIsSetAfter, L_16);
            }
            if (_badDebtToRedistribute) {
                lt(cdpManager.lastEBTCDebtErrorRedistribution(), cdpManager.totalStakes(), L_17);
                totalCdpDustMaxCap += cdpManager.getActiveCdpsCount();
            }

            _checkStakeInvariants();
        } else if (vars.sortedCdpsSizeBefore > _n) {
            if (_atLeastOneCdpIsLiquidatable(cdpsBefore, vars.isRecoveryModeBefore)) {
                assertRevertReasonNotEqual(returnData, "Panic(17)");
            }
        }
    }

    function redeemCollateral(
        uint _EBTCAmount,
        uint _partialRedemptionHintNICR,
        uint _maxFeePercentage,
        uint _maxIterations
    ) public setup {
        _redeemCollateral(
            _EBTCAmount,
            bytes32(0),
            _partialRedemptionHintNICR,
            false,
            false,
            false,
            _maxFeePercentage,
            _maxIterations
        );
    }

    function redeemCollateral(
        uint _EBTCAmount,
        bytes32 _firstRedemptionHintFromMedusa,
        uint256 _partialRedemptionHintNICRFromMedusa,
        bool useProperFirstHint,
        bool useProperPartialHint,
        bool failPartialRedemption,
        uint _maxFeePercentage,
        uint _maxIterations
    ) public setup {
        _redeemCollateral(
            _EBTCAmount,
            _firstRedemptionHintFromMedusa,
            _partialRedemptionHintNICRFromMedusa,
            useProperFirstHint,
            useProperPartialHint,
            failPartialRedemption,
            _maxFeePercentage,
            _maxIterations
        );
    }

    function _redeemCollateral(
        uint _EBTCAmount,
        bytes32 _firstRedemptionHintFromMedusa,
        uint256 _partialRedemptionHintNICRFromMedusa,
        bool useProperFirstHint,
        bool useProperPartialHint,
        bool failPartialRedemption,
        uint _maxFeePercentage,
        uint _maxIterations
    ) internal {
        require(cdpManager.getActiveCdpsCount() > 1, "Cannot redeem last CDP");

        _EBTCAmount = between(_EBTCAmount, 0, eBTCToken.balanceOf(address(actor)));

        _maxIterations = between(_maxIterations, 0, 10);

        _maxFeePercentage = between(
            _maxFeePercentage,
            cdpManager.redemptionFeeFloor(),
            cdpManager.DECIMAL_PRECISION()
        );

        bytes32 _cdpId = _getFirstCdpWithIcrGteMcr();

        _before(_cdpId);

        {
            uint price = priceFeedMock.getPrice();

            (bytes32 firstRedemptionHintVal, uint256 partialRedemptionHintNICR, , ) = hintHelpers
                .getRedemptionHints(_EBTCAmount, price, _maxIterations);

            _firstRedemptionHintFromMedusa = useProperFirstHint
                ? firstRedemptionHintVal
                : _firstRedemptionHintFromMedusa;

            _partialRedemptionHintNICRFromMedusa = useProperPartialHint
                ? partialRedemptionHintNICR
                : _partialRedemptionHintNICRFromMedusa;
        }

        _syncAPDebtTwapToSpotValue();

        {
            bool success;

            (success, ) = actor.proxy(
                address(cdpManager),
                abi.encodeWithSelector(
                    CdpManager.redeemCollateral.selector,
                    _EBTCAmount,
                    _firstRedemptionHintFromMedusa,
                    bytes32(0),
                    bytes32(0),
                    failPartialRedemption ? 0 : _partialRedemptionHintNICRFromMedusa,
                    _maxIterations,
                    _maxFeePercentage
                )
            );

            require(success);
        }

        _after(_cdpId);

        gt(vars.tcrBefore, cdpManager.MCR(), EBTC_02);
        if (_maxIterations == 1) {
            gte(vars.activePoolDebtBefore, vars.activePoolDebtAfter, CDPM_05);
            gte(vars.cdpDebtBefore, vars.cdpDebtAfter, CDPM_06);
            // TODO: CHECK THIS
            // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/10#issuecomment-1702685732
            if (vars.sortedCdpsSizeBefore == vars.sortedCdpsSizeAfter) {
                // Redemptions do not reduce TCR
                // If redemptions do not close any CDP that was healthy (low debt, high coll)
                gt(vars.newTcrAfter, vars.newTcrBefore, R_07);
            }
            t(invariant_CDPM_04(vars), CDPM_04);
        }
        gt(vars.actorEbtcBefore, vars.actorEbtcAfter, R_08);

        // Verify Fee Recipient Received the Fee
        gte(vars.feeRecipientCollSharesAfter, vars.feeRecipientCollSharesBefore, F_02);

        if (
            vars.lastGracePeriodStartTimestampIsSetBefore &&
            vars.isRecoveryModeBefore &&
            vars.isRecoveryModeAfter
        ) {
            eq(
                vars.lastGracePeriodStartTimestampBefore,
                vars.lastGracePeriodStartTimestampAfter,
                L_14
            );
        }

        _checkL_15IfRecoveryMode();

        if (vars.isRecoveryModeBefore && !vars.isRecoveryModeAfter) {
            t(!vars.lastGracePeriodStartTimestampIsSetAfter, L_16);
        }

        _checkStakeInvariants();
    }

    ///////////////////////////////////////////////////////
    // ActivePool
    ///////////////////////////////////////////////////////

    function _syncAPDebtTwapToSpotValue() internal {
        hevm.warp(block.timestamp + activePool.PERIOD());
        activePool.update();
    }

    function flashLoanColl(uint _amount) public setup {
        bool success;
        bytes memory returnData;

        _amount = between(_amount, 0, activePool.maxFlashLoan(address(collateral)));
        uint _fee = activePool.flashFee(address(collateral), _amount);

        _before(bytes32(0));

        // take the flashloan which should always cost the fee paid by caller
        uint _balBefore = collateral.sharesOf(activePool.feeRecipientAddress());
        (success, returnData) = actor.proxy(
            address(activePool),
            abi.encodeWithSelector(
                ActivePool.flashLoan.selector,
                IERC3156FlashBorrower(address(actor)),
                address(collateral),
                _amount,
                _getFlashLoanActions(_amount)
            )
        );

        require(success);

        _after(bytes32(0));

        uint _balAfter = collateral.sharesOf(activePool.feeRecipientAddress());
        eq(_balAfter - _balBefore, collateral.getSharesByPooledEth(_fee), F_03);

        if (
            vars.lastGracePeriodStartTimestampIsSetBefore &&
            vars.isRecoveryModeBefore &&
            vars.isRecoveryModeAfter
        ) {
            eq(
                vars.lastGracePeriodStartTimestampBefore,
                vars.lastGracePeriodStartTimestampAfter,
                L_14
            );
        }

        _checkL_15IfRecoveryMode();

        if (vars.isRecoveryModeBefore && !vars.isRecoveryModeAfter) {
            t(!vars.lastGracePeriodStartTimestampIsSetAfter, L_16);
        }

        _checkStakeInvariants();
    }

    ///////////////////////////////////////////////////////
    // BorrowerOperations
    ///////////////////////////////////////////////////////

    function flashLoanEBTC(uint _amount) public setup {
        bool success;
        bytes memory returnData;

        _amount = between(_amount, 0, borrowerOperations.maxFlashLoan(address(eBTCToken)));

        uint _fee = borrowerOperations.flashFee(address(eBTCToken), _amount);

        _before(bytes32(0));

        // take the flashloan which should always cost the fee paid by caller
        uint _balBefore = eBTCToken.balanceOf(borrowerOperations.feeRecipientAddress());
        (success, returnData) = actor.proxy(
            address(borrowerOperations),
            abi.encodeWithSelector(
                BorrowerOperations.flashLoan.selector,
                IERC3156FlashBorrower(address(actor)),
                address(eBTCToken),
                _amount,
                _getFlashLoanActions(_amount)
            )
        );

        // BorrowerOperations.flashLoan may revert due to reentrancy
        require(success);

        _after(bytes32(0));

        uint _balAfter = eBTCToken.balanceOf(borrowerOperations.feeRecipientAddress());
        eq(_balAfter - _balBefore, _fee, F_03);

        if (
            vars.lastGracePeriodStartTimestampIsSetBefore &&
            vars.isRecoveryModeBefore &&
            vars.isRecoveryModeAfter
        ) {
            eq(
                vars.lastGracePeriodStartTimestampBefore,
                vars.lastGracePeriodStartTimestampAfter,
                L_14
            );
        }

        _checkL_15IfRecoveryMode();

        if (vars.isRecoveryModeBefore && !vars.isRecoveryModeAfter) {
            t(!vars.lastGracePeriodStartTimestampIsSetAfter, L_16);
        }

        _checkStakeInvariants();
    }

    function openCdp(uint256 _col, uint256 _EBTCAmount) public setup returns (bytes32 _cdpId) {
        bool success;
        bytes memory returnData;

        // we pass in CCR instead of MCR in case it's the first one
        uint price = priceFeedMock.getPrice();

        uint256 requiredCollAmount = (_EBTCAmount * cdpManager.CCR()) / (price);
        uint256 minCollAmount = max(
            cdpManager.MIN_NET_STETH_BALANCE() + borrowerOperations.LIQUIDATOR_REWARD(),
            requiredCollAmount
        );
        uint256 maxCollAmount = min(2 * minCollAmount, INITIAL_COLL_BALANCE / 10);
        _col = between(requiredCollAmount, minCollAmount, maxCollAmount);

        (success, ) = actor.proxy(
            address(collateral),
            abi.encodeWithSelector(
                CollateralTokenTester.approve.selector,
                address(borrowerOperations),
                _col
            )
        );
        t(success, "Approve never fails");

        _before(bytes32(0));

        (success, returnData) = actor.proxy(
            address(borrowerOperations),
            abi.encodeWithSelector(
                BorrowerOperations.openCdp.selector,
                _EBTCAmount,
                bytes32(0),
                bytes32(0),
                _col
            )
        );

        if (success) {
            _cdpId = abi.decode(returnData, (bytes32));
            _after(_cdpId);

            t(invariant_GENERAL_01(vars), GENERAL_01);
            gt(vars.icrAfter, cdpManager.MCR(), BO_01);

            eq(vars.newTcrAfter, vars.tcrAfter, GENERAL_11);

            // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/3
            t(invariant_GENERAL_09(cdpManager, vars), GENERAL_09);
            // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/4
            gte(
                collateral.getPooledEthByShares(cdpManager.getCdpCollShares(_cdpId)),
                borrowerOperations.MIN_NET_STETH_BALANCE(),
                GENERAL_10
            );
            eq(
                vars.sortedCdpsSizeBefore + 1,
                vars.sortedCdpsSizeAfter,
                "CDPs count must have increased"
            );
            if (
                vars.lastGracePeriodStartTimestampIsSetBefore &&
                vars.isRecoveryModeBefore &&
                vars.isRecoveryModeAfter
            ) {
                eq(
                    vars.lastGracePeriodStartTimestampBefore,
                    vars.lastGracePeriodStartTimestampAfter,
                    L_14
                );
            }

            _checkL_15IfRecoveryMode();

            if (vars.isRecoveryModeBefore && !vars.isRecoveryModeAfter) {
                t(!vars.lastGracePeriodStartTimestampIsSetAfter, L_16);
            }

            gte(_EBTCAmount, borrowerOperations.MIN_CHANGE(), GENERAL_16);
            gte(vars.cdpDebtAfter, borrowerOperations.MIN_CHANGE(), GENERAL_15);
            require(invariant_BO_09(cdpManager, priceFeedMock.getPrice(), _cdpId), BO_09);

            _checkStakeInvariants();
        } else {
            assertRevertReasonNotEqual(returnData, "Panic(17)"); /// Done
        }
    }

    function addColl(uint _coll, uint256 _i) public setup {
        bool success;
        bytes memory returnData;

        uint256 numberOfCdps = sortedCdps.cdpCountOf(address(actor));
        require(numberOfCdps > 0, "Actor must have at least one CDP open");

        _i = between(_i, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(actor), _i);
        t(_cdpId != bytes32(0), "CDP ID must not be null if the index is valid");

        _coll = between(_coll, 0, INITIAL_COLL_BALANCE / 10);

        if (collateral.balanceOf(address(actor)) < _coll) {
            (success, ) = actor.proxy(
                address(collateral),
                abi.encodeWithSelector(CollateralTokenTester.deposit.selector, ""),
                (_coll - collateral.balanceOf(address(actor)))
            );
            require(success);
            require(
                collateral.balanceOf(address(actor)) > _coll,
                "Actor has high enough balance to add"
            );
        }

        (success, ) = actor.proxy(
            address(collateral),
            abi.encodeWithSelector(
                CollateralTokenTester.approve.selector,
                address(borrowerOperations),
                _coll
            )
        );
        t(success, "Approve never fails");

        _before(_cdpId);

        (success, returnData) = actor.proxy(
            address(borrowerOperations),
            abi.encodeWithSelector(
                BorrowerOperations.addColl.selector,
                _cdpId,
                _cdpId,
                _cdpId,
                _coll
            )
        );

        _after(_cdpId);

        if (success) {
            emit L3(
                vars.isRecoveryModeBefore ? 1 : 0,
                vars.hasGracePeriodPassedBefore ? 1 : 0,
                vars.icrAfter
            );
            emit L3(
                block.timestamp,
                cdpManager.lastGracePeriodStartTimestamp(),
                cdpManager.recoveryModeGracePeriodDuration()
            );

            eq(vars.newTcrAfter, vars.tcrAfter, GENERAL_11);
            gte(vars.nicrAfter, vars.nicrBefore, BO_03);
            // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/3
            t(invariant_GENERAL_09(cdpManager, vars), GENERAL_09);
            // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/4
            gte(
                collateral.getPooledEthByShares(cdpManager.getCdpCollShares(_cdpId)),
                borrowerOperations.MIN_NET_STETH_BALANCE(),
                GENERAL_10
            );

            t(invariant_GENERAL_01(vars), GENERAL_01);

            if (
                vars.lastGracePeriodStartTimestampIsSetBefore &&
                vars.isRecoveryModeBefore &&
                vars.isRecoveryModeAfter
            ) {
                eq(
                    vars.lastGracePeriodStartTimestampBefore,
                    vars.lastGracePeriodStartTimestampAfter,
                    L_14
                );
            }

            _checkL_15IfRecoveryMode();

            if (vars.isRecoveryModeBefore && !vars.isRecoveryModeAfter) {
                t(!vars.lastGracePeriodStartTimestampIsSetAfter, L_16);
            }

            gte(_coll, borrowerOperations.MIN_CHANGE(), GENERAL_16);

            _checkStakeInvariants();
        } else {
            assertRevertReasonNotEqual(returnData, "Panic(17)");
        }
    }

    function withdrawColl(uint _amount, uint256 _i) public setup {
        bool success;
        bytes memory returnData;

        uint256 numberOfCdps = sortedCdps.cdpCountOf(address(actor));
        require(numberOfCdps > 0, "Actor must have at least one CDP open");

        _i = between(_i, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(actor), _i);
        t(_cdpId != bytes32(0), "CDP ID must not be null if the index is valid");

        // Can only withdraw up to CDP collateral amount, otherwise will revert with assert
        _amount = between(
            _amount,
            0,
            collateral.getPooledEthByShares(cdpManager.getCdpCollShares(_cdpId))
        );

        _before(_cdpId);

        (success, returnData) = actor.proxy(
            address(borrowerOperations),
            abi.encodeWithSelector(
                BorrowerOperations.withdrawColl.selector,
                _cdpId,
                _amount,
                _cdpId,
                _cdpId
            )
        );

        _after(_cdpId);

        if (success) {
            eq(vars.newTcrAfter, vars.tcrAfter, GENERAL_11);
            lte(vars.nicrAfter, vars.nicrBefore, BO_04);
            // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/3
            t(invariant_GENERAL_09(cdpManager, vars), GENERAL_09);
            t(invariant_GENERAL_01(vars), GENERAL_01);
            // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/4
            gte(
                collateral.getPooledEthByShares(cdpManager.getCdpCollShares(_cdpId)),
                borrowerOperations.MIN_NET_STETH_BALANCE(),
                GENERAL_10
            );

            if (
                vars.lastGracePeriodStartTimestampIsSetBefore &&
                vars.isRecoveryModeBefore &&
                vars.isRecoveryModeAfter
            ) {
                eq(
                    vars.lastGracePeriodStartTimestampBefore,
                    vars.lastGracePeriodStartTimestampAfter,
                    L_14
                );
            }

            _checkL_15IfRecoveryMode();

            if (vars.isRecoveryModeBefore && !vars.isRecoveryModeAfter) {
                t(!vars.lastGracePeriodStartTimestampIsSetAfter, L_16);
            }

            gte(_amount, borrowerOperations.MIN_CHANGE(), GENERAL_16);

            _checkStakeInvariants();
        } else {
            assertRevertReasonNotEqual(returnData, "Panic(17)");
        }
    }

    function withdrawDebt(uint _amount, uint256 _i) public setup {
        bool success;
        bytes memory returnData;

        uint256 numberOfCdps = sortedCdps.cdpCountOf(address(actor));
        require(numberOfCdps > 0, "Actor must have at least one CDP open");

        _i = between(_i, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(actor), _i);
        t(_cdpId != bytes32(0), "CDP ID must not be null if the index is valid");

        // TODO verify the assumption below, maybe there's a more sensible (or Governance-defined/hardcoded) limit for the maximum amount of minted eBTC at a single operation
        // Can only withdraw up to type(uint128).max eBTC, so that `BorrwerOperations._getNewCdpAmounts` does not overflow
        _amount = between(_amount, 0, type(uint128).max); /// NOTE: Implicitly testing for caps

        _before(_cdpId);

        (success, returnData) = actor.proxy(
            address(borrowerOperations),
            abi.encodeWithSelector(
                BorrowerOperations.withdrawDebt.selector,
                _cdpId,
                _amount,
                _cdpId,
                _cdpId
            )
        );

        // Require(success) -> If success, we check same stuff
        // Else we ony verify no overflow
        if (success) {
            _after(_cdpId);

            eq(vars.newTcrAfter, vars.tcrAfter, GENERAL_11);
            gte(vars.cdpDebtAfter, vars.cdpDebtBefore, "withdrawDebt must not decrease debt");
            eq(
                vars.actorEbtcAfter,
                vars.actorEbtcBefore + _amount,
                "withdrawDebt must increase debt by requested amount"
            );
            // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/4
            gte(
                collateral.getPooledEthByShares(cdpManager.getCdpCollShares(_cdpId)),
                borrowerOperations.MIN_NET_STETH_BALANCE(),
                GENERAL_10
            );

            if (
                vars.lastGracePeriodStartTimestampIsSetBefore &&
                vars.isRecoveryModeBefore &&
                vars.isRecoveryModeAfter
            ) {
                eq(
                    vars.lastGracePeriodStartTimestampBefore,
                    vars.lastGracePeriodStartTimestampAfter,
                    L_14
                );
            }

            _checkL_15IfRecoveryMode();

            if (vars.isRecoveryModeBefore && !vars.isRecoveryModeAfter) {
                t(!vars.lastGracePeriodStartTimestampIsSetAfter, L_16);
            }

            gte(_amount, borrowerOperations.MIN_CHANGE(), GENERAL_16);
            gte(vars.cdpDebtAfter, borrowerOperations.MIN_CHANGE(), GENERAL_15);

            _checkStakeInvariants();
        } else {
            assertRevertReasonNotEqual(returnData, "Panic(17)");
        }
    }

    function repayDebt(uint _amount, uint256 _i) public setup {
        bool success;
        bytes memory returnData;

        uint256 numberOfCdps = sortedCdps.cdpCountOf(address(actor));
        require(numberOfCdps > 0, "Actor must have at least one CDP open");

        _i = between(_i, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(actor), _i);
        t(_cdpId != bytes32(0), "CDP ID must not be null if the index is valid");

        (uint256 entireDebt, ) = cdpManager.getSyncedDebtAndCollShares(_cdpId);

        _amount = between(_amount, 0, entireDebt);

        _before(_cdpId);

        (success, returnData) = actor.proxy(
            address(borrowerOperations),
            abi.encodeWithSelector(
                BorrowerOperations.repayDebt.selector,
                _cdpId,
                _amount,
                _cdpId,
                _cdpId
            )
        );
        if (success) {
            _after(_cdpId);

            eq(vars.newTcrAfter, vars.tcrAfter, GENERAL_11);

            // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/3
            gte(vars.newTcrAfter, vars.newTcrBefore, BO_08);

            eq(vars.ebtcTotalSupplyBefore - _amount, vars.ebtcTotalSupplyAfter, BO_07);
            eq(vars.actorEbtcBefore - _amount, vars.actorEbtcAfter, BO_07);
            // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/3
            t(invariant_GENERAL_09(cdpManager, vars), GENERAL_09);
            t(invariant_GENERAL_01(vars), GENERAL_01);
            // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/4
            gte(
                collateral.getPooledEthByShares(cdpManager.getCdpCollShares(_cdpId)),
                borrowerOperations.MIN_NET_STETH_BALANCE(),
                GENERAL_10
            );

            if (
                vars.lastGracePeriodStartTimestampIsSetBefore &&
                vars.isRecoveryModeBefore &&
                vars.isRecoveryModeAfter
            ) {
                eq(
                    vars.lastGracePeriodStartTimestampBefore,
                    vars.lastGracePeriodStartTimestampAfter,
                    L_14
                );
            }

            _checkL_15IfRecoveryMode();

            if (vars.isRecoveryModeBefore && !vars.isRecoveryModeAfter) {
                t(!vars.lastGracePeriodStartTimestampIsSetAfter, L_16);
            }

            gte(_amount, borrowerOperations.MIN_CHANGE(), GENERAL_16);
            gte(vars.cdpDebtAfter, borrowerOperations.MIN_CHANGE(), GENERAL_15);

            _checkStakeInvariants();
        } else {
            assertRevertReasonNotEqual(returnData, "Panic(17)");
        }
    }

    function closeCdp(uint _i) public setup {
        bool success;
        bytes memory returnData;

        require(cdpManager.getActiveCdpsCount() > 1, "Cannot close last CDP");

        uint256 numberOfCdps = sortedCdps.cdpCountOf(address(actor));
        require(numberOfCdps > 0, "Actor must have at least one CDP open");

        _i = between(_i, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(actor), _i);
        t(_cdpId != bytes32(0), "CDP ID must not be null if the index is valid");

        _before(_cdpId);

        (success, returnData) = actor.proxy(
            address(borrowerOperations),
            abi.encodeWithSelector(BorrowerOperations.closeCdp.selector, _cdpId)
        );

        _after(_cdpId);

        if (success) {
            eq(vars.newTcrAfter, vars.tcrAfter, GENERAL_11);
            eq(vars.cdpDebtAfter, 0, BO_02);
            eq(
                vars.sortedCdpsSizeBefore - 1,
                vars.sortedCdpsSizeAfter,
                "closeCdp reduces list size by 1"
            );
            gt(
                vars.actorCollAfter,
                vars.actorCollBefore,
                "closeCdp increases the collateral balance of the user"
            );
            // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/3
            t(invariant_GENERAL_09(cdpManager, vars), GENERAL_09);
            emit L4(
                vars.actorCollBefore,
                vars.cdpCollBefore,
                vars.liquidatorRewardSharesBefore,
                vars.actorCollAfter
            );
            gt(
                // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/11
                // Note: not checking for strict equality since split fee is difficult to calculate a-priori, so the CDP collateral value may not be sent back to the user in full
                vars.actorCollAfter,
                vars.actorCollBefore +
                    // ActivePool transfer SHARES not ETH directly
                    collateral.getPooledEthByShares(vars.liquidatorRewardSharesBefore),
                BO_05
            );
            t(invariant_GENERAL_01(vars), GENERAL_01);

            if (
                vars.lastGracePeriodStartTimestampIsSetBefore &&
                vars.isRecoveryModeBefore &&
                vars.isRecoveryModeAfter
            ) {
                eq(
                    vars.lastGracePeriodStartTimestampBefore,
                    vars.lastGracePeriodStartTimestampAfter,
                    L_14
                );
            }

            _checkL_15IfRecoveryMode();

            if (vars.isRecoveryModeBefore && !vars.isRecoveryModeAfter) {
                t(!vars.lastGracePeriodStartTimestampIsSetAfter, L_16);
            }

            _checkStakeInvariants();
        } else {
            assertRevertReasonNotEqual(returnData, "Panic(17)");
        }
    }

    function adjustCdp(
        uint _i,
        uint _collWithdrawal,
        uint _EBTCChange,
        bool _isDebtIncrease
    ) public setup {
        bool success;
        bytes memory returnData;

        uint256 numberOfCdps = sortedCdps.cdpCountOf(address(actor));
        require(numberOfCdps > 0, "Actor must have at least one CDP open");

        _i = between(_i, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(actor), _i);
        t(_cdpId != bytes32(0), "CDP ID must not be null if the index is valid");

        (uint256 entireDebt, uint256 entireColl) = cdpManager.getSyncedDebtAndCollShares(_cdpId);
        _collWithdrawal = between(_collWithdrawal, 0, entireColl);
        _EBTCChange = between(_EBTCChange, 0, entireDebt);

        _before(_cdpId);

        (success, returnData) = actor.proxy(
            address(borrowerOperations),
            abi.encodeWithSelector(
                BorrowerOperations.adjustCdp.selector,
                _cdpId,
                _collWithdrawal,
                _EBTCChange,
                _isDebtIncrease,
                _cdpId,
                _cdpId
            )
        );

        require(success);

        _after(_cdpId);

        eq(vars.newTcrAfter, vars.tcrAfter, GENERAL_11);
        // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/3
        t(invariant_GENERAL_09(cdpManager, vars), GENERAL_09);

        t(invariant_GENERAL_01(vars), GENERAL_01);
        // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/4
        gte(
            collateral.getPooledEthByShares(cdpManager.getCdpCollShares(_cdpId)),
            borrowerOperations.MIN_NET_STETH_BALANCE(),
            GENERAL_10
        );

        if (
            vars.lastGracePeriodStartTimestampIsSetBefore &&
            vars.isRecoveryModeBefore &&
            vars.isRecoveryModeAfter
        ) {
            eq(
                vars.lastGracePeriodStartTimestampBefore,
                vars.lastGracePeriodStartTimestampAfter,
                L_14
            );
        }

        _checkL_15IfRecoveryMode();

        if (vars.isRecoveryModeBefore && !vars.isRecoveryModeAfter) {
            t(!vars.lastGracePeriodStartTimestampIsSetAfter, L_16);
        }

        if (_collWithdrawal > 0) {
            gte(_collWithdrawal, borrowerOperations.MIN_CHANGE(), GENERAL_16);
        }

        if (_isDebtIncrease) {
            gte(_EBTCChange, borrowerOperations.MIN_CHANGE(), GENERAL_16);
        } else {
            // it's ok for _EBTCChange to be 0 if we are not increasing debt (coll only operation)
            if (_EBTCChange > 0) {
                gte(_EBTCChange, borrowerOperations.MIN_CHANGE(), GENERAL_16);
            }
        }
        gte(vars.cdpDebtAfter, borrowerOperations.MIN_CHANGE(), GENERAL_15);

        _checkStakeInvariants();
    }

    ///////////////////////////////////////////////////////
    // Collateral Token (Test)
    ///////////////////////////////////////////////////////

    // Example for real world slashing: https://twitter.com/LidoFinance/status/1646505631678107649
    // > There are 11 slashing ongoing with the RockLogic GmbH node operator in Lido.
    // > the total projected impact is around 20 ETH,
    // > or about 3% of average daily protocol rewards/0.0004% of TVL.
    function setEthPerShare(uint256 _newEthPerShare) public {
        uint256 currentEthPerShare = collateral.getEthPerShare();
        _newEthPerShare = between(
            _newEthPerShare,
            (currentEthPerShare * 1e18) / MAX_REBASE_PERCENT,
            (currentEthPerShare * MAX_REBASE_PERCENT) / 1e18
        );
        vars.prevStEthFeeIndex = cdpManager.systemStEthFeePerUnitIndex();
        collateral.setEthPerShare(_newEthPerShare);
        AccruableCdpManager(address(cdpManager)).syncGlobalAccountingInternal();
        vars.afterStEthFeeIndex = cdpManager.systemStEthFeePerUnitIndex();

        if (vars.afterStEthFeeIndex > vars.prevStEthFeeIndex) {
            vars.cumulativeCdpsAtTimeOfRebase += cdpManager.getActiveCdpsCount();
        }
    }

    ///////////////////////////////////////////////////////
    // PriceFeed
    ///////////////////////////////////////////////////////

    function setPrice(uint256 _newPrice) public {
        uint256 currentPrice = priceFeedMock.getPrice();
        _newPrice = between(
            _newPrice,
            (currentPrice * 1e18) / MAX_PRICE_CHANGE_PERCENT,
            (currentPrice * MAX_PRICE_CHANGE_PERCENT) / 1e18
        );
        priceFeedMock.setPrice(_newPrice);
    }

    ///////////////////////////////////////////////////////
    // Governance
    ///////////////////////////////////////////////////////

    function setGovernanceParameters(uint256 parameter, uint256 value) public {
        parameter = between(parameter, 0, 6);

        if (parameter == 0) {
            value = between(value, cdpManager.MINIMUM_GRACE_PERIOD(), type(uint128).max);
            hevm.prank(defaultGovernance);
            cdpManager.setGracePeriod(uint128(value));
        } else if (parameter == 1) {
            value = between(value, 0, activePool.getFeeRecipientClaimableCollShares());
            _before(bytes32(0));
            hevm.prank(defaultGovernance);
            activePool.claimFeeRecipientCollShares(value);
            _after(bytes32(0));
            // If there was something to claim
            if (value > 0) {
                // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/22
                // Claiming will increase the balance
                // Strictly GT
                gt(vars.feeRecipientCollSharesBalAfter, vars.feeRecipientCollSharesBalBefore, F_01);
                gte(vars.feeRecipientTotalCollAfter, vars.feeRecipientTotalCollBefore, F_01);
            }
        } else if (parameter == 2) {
            value = between(value, 0, cdpManager.MAX_REWARD_SPLIT());
            hevm.prank(defaultGovernance);
            cdpManager.setStakingRewardSplit(value);
        } else if (parameter == 3) {
            value = between(
                value,
                cdpManager.MIN_REDEMPTION_FEE_FLOOR(),
                cdpManager.DECIMAL_PRECISION()
            );
            hevm.prank(defaultGovernance);
            cdpManager.setRedemptionFeeFloor(value);
        } else if (parameter == 4) {
            value = between(
                value,
                cdpManager.MIN_MINUTE_DECAY_FACTOR(),
                cdpManager.MAX_MINUTE_DECAY_FACTOR()
            );
            hevm.prank(defaultGovernance);
            cdpManager.setMinuteDecayFactor(value);
        } else if (parameter == 5) {
            value = between(value, 0, cdpManager.DECIMAL_PRECISION());
            hevm.prank(defaultGovernance);
            cdpManager.setBeta(value);
        } else if (parameter == 6) {
            value = between(value, 0, 1);
            hevm.prank(defaultGovernance);
            cdpManager.setRedemptionsPaused(value == 1 ? true : false);
        }
    }
}
