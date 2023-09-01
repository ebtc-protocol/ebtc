// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../../../Interfaces/ICdpManagerData.sol";
import "../../../Dependencies/SafeMath.sol";
import "../../../CdpManager.sol";
import "../../../LiquidationLibrary.sol";
import "../../../BorrowerOperations.sol";
import "../../../ActivePool.sol";
import "../../../CollSurplusPool.sol";
import "../../../SortedCdps.sol";
import "../../../HintHelpers.sol";
import "../../../FeeRecipient.sol";
import "../../testnet/PriceFeedTestnet.sol";
import "../../CollateralTokenTester.sol";
import "../../EBTCTokenTester.sol";
import "../../../Governor.sol";
import "../../../EBTCDeployer.sol";

import "../IHevm.sol";
import "../Properties.sol";
import "../Actor.sol";
import "./EchidnaBaseTester.sol";
import "./EchidnaProperties.sol";
import "../BeforeAfter.sol";
import "./EchidnaAssertionHelper.sol";

contract EchidnaTester is BeforeAfter, EchidnaProperties, EchidnaAssertionHelper {
    constructor() payable {
        _setUp();
        _setUpActors();
    }

    ///////////////////////////////////////////////////////
    // Helper functions
    ///////////////////////////////////////////////////////

    function _totalCdpsBelowMcr() internal returns (uint256) {
        uint256 ans;
        bytes32 currentCdp = sortedCdps.getFirst();

        uint256 _price = priceFeedMock.getPrice();

        while (currentCdp != bytes32(0)) {
            if (cdpManager.getCurrentICR(currentCdp, _price) < cdpManager.MCR()) {
                ++ans;
            }

            currentCdp = sortedCdps.getNext(currentCdp);
        }

        return ans;
    }

    function _getCdpIdsAndICRs() internal returns (Cdp[] memory ans) {
        ans = new Cdp[](sortedCdps.getSize());
        uint256 i = 0;
        bytes32 currentCdp = sortedCdps.getFirst();

        uint256 _price = priceFeedMock.getPrice();

        while (currentCdp != bytes32(0)) {
            ans[i++] = Cdp({id: currentCdp, icr: cdpManager.getCurrentICR(currentCdp, _price)});

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
        uint _cdpIdx = _i % cdpManager.getCdpIdsCount();
        return cdpManager.CdpIds(_cdpIdx);
    }

    event FlashLoanAction(uint, uint);

    function _getFlashLoanActions(uint256 value) internal returns (bytes memory) {
        uint256 _actions = clampBetween(value, 1, MAX_FLASHLOAN_ACTIONS);
        uint256 _EBTCAmount = clampBetween(value, 1, eBTCToken.totalSupply() / 2);
        uint256 _col = clampBetween(value, 1, cdpManager.getEntireSystemColl() / 2);
        uint256 _n = clampBetween(value, 1, cdpManager.getCdpIdsCount());

        uint256 numberOfCdps = sortedCdps.cdpCountOf(address(actor));
        require(numberOfCdps > 0, "Actor must have at least one CDP open");
        uint256 _i = clampBetween(value, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(actor), _i);
        assertWithMsg(_cdpId != bytes32(0), "CDP ID must not be null if the index is valid");

        address[] memory _targets = new address[](_actions);
        bytes[] memory _calldatas = new bytes[](_actions);

        address[] memory _allTargets = new address[](7);
        bytes[] memory _allCalldatas = new bytes[](7);

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
            BorrowerOperations.withdrawEBTC.selector,
            _cdpId,
            _EBTCAmount,
            _cdpId,
            _cdpId
        );

        _allTargets[5] = address(borrowerOperations);
        _allCalldatas[5] = abi.encodeWithSelector(
            BorrowerOperations.repayEBTC.selector,
            _cdpId,
            _EBTCAmount,
            _cdpId,
            _cdpId
        );

        _allTargets[6] = address(cdpManager);
        _allCalldatas[6] = abi.encodeWithSelector(CdpManager.liquidateCdps.selector, _n);

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
            cdpManager.getCurrentICR(_cId, priceFeedMock.getPrice()) < cdpManager.MCR()
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

    function liquidate(uint _i) internal log {
        actor = actors[msg.sender];

        bool success;
        bytes memory returnData;

        require(cdpManager.getCdpIdsCount() > 1, "Cannot liquidate last CDP");

        bytes32 _cdpId = _getRandomCdp(_i);

        (uint256 entireDebt, , ) = cdpManager.getEntireDebtAndColl(_cdpId);
        require(entireDebt > 0, "CDP must have debt");

        uint256 _price = priceFeedMock.getPrice();

        _before(_cdpId);

        (success, returnData) = actor.proxy(
            address(cdpManager),
            abi.encodeWithSelector(CdpManager.liquidate.selector, _cdpId)
        );

        _after(_cdpId);

        if (success) {
            if (vars.icrBefore > cdpManager.LICR()) {
                // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/5
                assertGt(
                    vars.newTcrSyncPendingGlobalStateAfter,
                    vars.newTcrSyncPendingGlobalStateBefore,
                    L_12
                );
            }
            // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/12
            // assertWithMsg(
            //     vars.icrBefore < cdpManager.MCR() ||
            //         (vars.icrBefore < cdpManager.CCR() && vars.isRecoveryModeBefore),
            //     L_01
            // );
            if (
                vars.lastGracePeriodStartTimestampIsSetBefore &&
                vars.isRecoveryModeBefore &&
                vars.isRecoveryModeAfter
            ) {
                assertEq(
                    vars.lastGracePeriodStartTimestampBefore,
                    vars.lastGracePeriodStartTimestampAfter,
                    L_14
                );
            }

            if (!vars.isRecoveryModeBefore && vars.isRecoveryModeAfter) {
                assertWithMsg(
                    !vars.lastGracePeriodStartTimestampIsSetBefore &&
                        vars.lastGracePeriodStartTimestampIsSetAfter,
                    L_15
                );
            }

            if (vars.isRecoveryModeBefore && !vars.isRecoveryModeAfter) {
                assertWithMsg(!vars.lastGracePeriodStartTimestampIsSetAfter, L_16);
            }
        } else if (vars.sortedCdpsSizeBefore > _i) {
            assertRevertReasonNotEqual(returnData, "Panic(17)");
        }
    }

    function partialLiquidate(uint _i, uint _partialAmount) external log {
        actor = actors[msg.sender];

        bool success;
        bytes memory returnData;

        require(cdpManager.getCdpIdsCount() > 1, "Cannot liquidate last CDP");

        bytes32 _cdpId = _getRandomCdp(_i);

        (uint256 entireDebt, , ) = cdpManager.getEntireDebtAndColl(_cdpId);
        require(entireDebt > 0, "CDP must have debt");

        _partialAmount = clampBetween(_partialAmount, 0, entireDebt - 1);

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
            (uint256 _newEntireDebt, , ) = cdpManager.getEntireDebtAndColl(_cdpId);
            assertLt(_newEntireDebt, entireDebt, "Partial liquidation must reduce CDP debt");

            if (vars.icrBefore > cdpManager.LICR()) {
                // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/5
                assertGt(
                    vars.newTcrSyncPendingGlobalStateAfter,
                    vars.newTcrSyncPendingGlobalStateBefore,
                    L_12
                );
            }
            // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/12
            // assertWithMsg(
            //     vars.icrBefore < cdpManager.MCR() ||
            //         (vars.icrBefore < cdpManager.CCR() && vars.isRecoveryModeBefore),
            //     L_01
            // );

            // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/4
            assertGte(
                collateral.getPooledEthByShares(cdpManager.getCdpColl(_cdpId)),
                borrowerOperations.MIN_NET_COLL(),
                GENERAL_10
            );

            if (
                vars.lastGracePeriodStartTimestampIsSetBefore &&
                vars.isRecoveryModeBefore &&
                vars.isRecoveryModeAfter
            ) {
                assertEq(
                    vars.lastGracePeriodStartTimestampBefore,
                    vars.lastGracePeriodStartTimestampAfter,
                    L_14
                );
            }

            if (!vars.isRecoveryModeBefore && vars.isRecoveryModeAfter) {
                assertWithMsg(
                    !vars.lastGracePeriodStartTimestampIsSetBefore &&
                        vars.lastGracePeriodStartTimestampIsSetAfter,
                    L_15
                );
            }

            if (vars.isRecoveryModeBefore && !vars.isRecoveryModeAfter) {
                assertWithMsg(!vars.lastGracePeriodStartTimestampIsSetAfter, L_16);
            }
        } else {
            assertRevertReasonNotEqual(returnData, "Panic(17)");
        }
    }

    function liquidateCdps(uint _n) external log {
        actor = actors[msg.sender];

        bool success;
        bytes memory returnData;

        require(cdpManager.getCdpIdsCount() > 1, "Cannot liquidate last CDP");

        _n = clampBetween(_n, 1, cdpManager.getCdpIdsCount());

        uint256 totalCdpsBelowMcr = _totalCdpsBelowMcr();
        uint256 _price = priceFeedMock.getPrice();
        Cdp[] memory cdpsBefore = _getCdpIdsAndICRs();

        _before(bytes32(0));

        (success, returnData) = actor.proxy(
            address(cdpManager),
            abi.encodeWithSelector(CdpManager.liquidateCdps.selector, _n)
        );

        _after(bytes32(0));

        if (success) {
            Cdp[] memory cdpsAfter = _getCdpIdsAndICRs();

            Cdp[] memory cdpsLiquidated = _cdpIdsAndICRsDiff(cdpsBefore, cdpsAfter);
            assertGte(
                cdpsLiquidated.length,
                1,
                "liquidateCdps must liquidate at least 1 CDP when successful"
            );
            assertLte(
                cdpsLiquidated.length,
                _n,
                "liquidateCdps must not liquidate more than n CDPs"
            );
            uint256 minIcrBefore = type(uint256).max;
            for (uint256 i = 0; i < cdpsLiquidated.length; ++i) {
                emit L3(i, cdpsLiquidated[i].icr, vars.isRecoveryModeBefore ? 1 : 0);
                // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/12
                // assertWithMsg(
                //     cdpsLiquidated[i].icr < cdpManager.MCR() ||
                //         (cdpsLiquidated[i].icr < cdpManager.CCR() && vars.isRecoveryModeBefore),
                //     L_01
                // );
                if (cdpsLiquidated[i].icr < minIcrBefore) {
                    minIcrBefore = cdpsLiquidated[i].icr;
                }
            }

            if (minIcrBefore > cdpManager.LICR()) {
                emit LogUint256("minIcrBefore", minIcrBefore);
                // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/5
                assertGt(
                    vars.newTcrSyncPendingGlobalStateAfter,
                    vars.newTcrSyncPendingGlobalStateBefore,
                    L_12
                );
            }

            if (
                vars.lastGracePeriodStartTimestampIsSetBefore &&
                vars.isRecoveryModeBefore &&
                vars.isRecoveryModeAfter
            ) {
                assertEq(
                    vars.lastGracePeriodStartTimestampBefore,
                    vars.lastGracePeriodStartTimestampAfter,
                    L_14
                );
            }

            if (!vars.isRecoveryModeBefore && vars.isRecoveryModeAfter) {
                assertWithMsg(
                    !vars.lastGracePeriodStartTimestampIsSetBefore &&
                        vars.lastGracePeriodStartTimestampIsSetAfter,
                    L_15
                );
            }

            if (vars.isRecoveryModeBefore && !vars.isRecoveryModeAfter) {
                assertWithMsg(!vars.lastGracePeriodStartTimestampIsSetAfter, L_16);
            }
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
    ) external log {
        require(
            block.timestamp > cdpManager.getDeploymentStartTime() + cdpManager.BOOTSTRAP_PERIOD(),
            "CdpManager: Redemptions are not allowed during bootstrap phase"
        );

        actor = actors[msg.sender];

        bool success;
        bytes memory returnData;

        _EBTCAmount = clampBetween(_EBTCAmount, 0, eBTCToken.balanceOf(address(actor)));
        _maxIterations = clampBetween(_maxIterations, 0, 1);

        _maxFeePercentage = clampBetween(
            _maxFeePercentage,
            cdpManager.redemptionFeeFloor(),
            cdpManager.DECIMAL_PRECISION()
        );

        bytes32 _cdpId = _getFirstCdpWithIcrGteMcr();
        bool _atLeastOneCdpIsLiquidatableBefore = _atLeastOneCdpIsLiquidatable(
            _getCdpIdsAndICRs(),
            cdpManager.checkRecoveryMode(priceFeedMock.getPrice())
        );

        _before(_cdpId);

        (success, returnData) = actor.proxy(
            address(cdpManager),
            abi.encodeWithSelector(
                CdpManager.redeemCollateral.selector,
                _EBTCAmount,
                bytes32(0),
                bytes32(0),
                bytes32(0),
                _partialRedemptionHintNICR,
                _maxIterations,
                _maxFeePercentage
            )
        );

        require(success);

        _after(_cdpId);

        assertGt(vars.tcrBefore, cdpManager.MCR(), EBTC_02);
        if (_maxIterations == 1) {
            assertGte(vars.debtBefore, vars.debtAfter, CDPM_05);
            // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/10#issuecomment-1702685732
            // if (!_atLeastOneCdpIsLiquidatableBefore) {
            //     // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/10
            //     assertGt(
            //         vars.newTcrSyncPendingGlobalStateAfter,
            //         vars.newTcrSyncPendingGlobalStateBefore,
            //         R_07
            //     );
            // }
            // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/6#issuecomment-1702653146
            // assertWithMsg(invariant_CDPM_04(vars), CDPM_04);
        }
        assertGt(vars.actorEbtcBefore, vars.actorEbtcAfter, R_08);

        if (
            vars.lastGracePeriodStartTimestampIsSetBefore &&
            vars.isRecoveryModeBefore &&
            vars.isRecoveryModeAfter
        ) {
            assertEq(
                vars.lastGracePeriodStartTimestampBefore,
                vars.lastGracePeriodStartTimestampAfter,
                L_14
            );
        }

        if (!vars.isRecoveryModeBefore && vars.isRecoveryModeAfter) {
            assertWithMsg(
                !vars.lastGracePeriodStartTimestampIsSetBefore &&
                    vars.lastGracePeriodStartTimestampIsSetAfter,
                L_15
            );
        }

        if (vars.isRecoveryModeBefore && !vars.isRecoveryModeAfter) {
            assertWithMsg(!vars.lastGracePeriodStartTimestampIsSetAfter, L_16);
        }
    }

    ///////////////////////////////////////////////////////
    // ActivePool
    ///////////////////////////////////////////////////////

    function flashLoanColl(uint _amount) internal log {
        actor = actors[msg.sender];

        bool success;
        bytes memory returnData;

        _amount = clampBetween(_amount, 0, activePool.maxFlashLoan(address(collateral)));
        uint _fee = activePool.flashFee(address(collateral), _amount);

        _before(bytes32(0));

        // take the flashloan which should always cost the fee paid by caller
        uint _balBefore = collateral.balanceOf(activePool.feeRecipientAddress());
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

        uint _balAfter = collateral.balanceOf(activePool.feeRecipientAddress());
        // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/9
        assertEq(_balAfter - _balBefore, _fee, "Flashloan should send fee to recipient");

        if (
            vars.lastGracePeriodStartTimestampIsSetBefore &&
            vars.isRecoveryModeBefore &&
            vars.isRecoveryModeAfter
        ) {
            assertEq(
                vars.lastGracePeriodStartTimestampBefore,
                vars.lastGracePeriodStartTimestampAfter,
                L_14
            );
        }

        if (!vars.isRecoveryModeBefore && vars.isRecoveryModeAfter) {
            assertWithMsg(
                !vars.lastGracePeriodStartTimestampIsSetBefore &&
                    vars.lastGracePeriodStartTimestampIsSetAfter,
                L_15
            );
        }

        if (vars.isRecoveryModeBefore && !vars.isRecoveryModeAfter) {
            assertWithMsg(!vars.lastGracePeriodStartTimestampIsSetAfter, L_16);
        }
    }

    ///////////////////////////////////////////////////////
    // BorrowerOperations
    ///////////////////////////////////////////////////////

    function flashLoanEBTC(uint _amount) internal log {
        actor = actors[msg.sender];

        bool success;
        bytes memory returnData;

        _amount = clampBetween(_amount, 0, borrowerOperations.maxFlashLoan(address(eBTCToken)));

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
        assertEq(_balAfter - _balBefore, _fee, "Flashloan should send fee to recipient");

        if (
            vars.lastGracePeriodStartTimestampIsSetBefore &&
            vars.isRecoveryModeBefore &&
            vars.isRecoveryModeAfter
        ) {
            assertEq(
                vars.lastGracePeriodStartTimestampBefore,
                vars.lastGracePeriodStartTimestampAfter,
                L_14
            );
        }

        if (!vars.isRecoveryModeBefore && vars.isRecoveryModeAfter) {
            assertWithMsg(
                !vars.lastGracePeriodStartTimestampIsSetBefore &&
                    vars.lastGracePeriodStartTimestampIsSetAfter,
                L_15
            );
        }

        if (vars.isRecoveryModeBefore && !vars.isRecoveryModeAfter) {
            assertWithMsg(!vars.lastGracePeriodStartTimestampIsSetAfter, L_16);
        }
    }

    function openCdp(uint256 _col, uint256 _EBTCAmount) external log {
        actor = actors[msg.sender];

        bool success;
        bytes memory returnData;

        // we pass in CCR instead of MCR in case it's the first one
        uint price = priceFeedMock.getPrice();

        uint256 requiredCollAmount = (_EBTCAmount * cdpManager.CCR()) / (price);
        uint256 minCollAmount = max(
            cdpManager.MIN_NET_COLL() + borrowerOperations.LIQUIDATOR_REWARD(),
            requiredCollAmount
        );
        uint256 maxCollAmount = min(2 * minCollAmount, INITIAL_COLL_BALANCE / 10);
        _col = clampBetween(requiredCollAmount, minCollAmount, maxCollAmount);

        (success, ) = actor.proxy(
            address(collateral),
            abi.encodeWithSelector(
                CollateralTokenTester.approve.selector,
                address(borrowerOperations),
                _col
            )
        );
        assertWithMsg(success, "Approve never fails");

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
            bytes32 _cdpId = abi.decode(returnData, (bytes32));
            _after(_cdpId);

            assertWithMsg(invariant_GENERAL_01(vars), GENERAL_01);

            assertEq(vars.newTcrSyncPendingGlobalStateAfter, vars.tcrAfter, GENERAL_11);

            // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/3
            assertWithMsg(invariant_GENERAL_09(cdpManager, vars), GENERAL_09);
            // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/4
            assertGte(
                collateral.getPooledEthByShares(cdpManager.getCdpColl(_cdpId)),
                borrowerOperations.MIN_NET_COLL(),
                GENERAL_10
            );
            assertEq(
                vars.sortedCdpsSizeBefore + 1,
                vars.sortedCdpsSizeAfter,
                "CDPs count must have increased"
            );
            if (
                vars.lastGracePeriodStartTimestampIsSetBefore &&
                vars.isRecoveryModeBefore &&
                vars.isRecoveryModeAfter
            ) {
                assertEq(
                    vars.lastGracePeriodStartTimestampBefore,
                    vars.lastGracePeriodStartTimestampAfter,
                    L_14
                );
            }

            if (!vars.isRecoveryModeBefore && vars.isRecoveryModeAfter) {
                assertWithMsg(
                    !vars.lastGracePeriodStartTimestampIsSetBefore &&
                        vars.lastGracePeriodStartTimestampIsSetAfter,
                    L_15
                );
            }

            if (vars.isRecoveryModeBefore && !vars.isRecoveryModeAfter) {
                assertWithMsg(!vars.lastGracePeriodStartTimestampIsSetAfter, L_16);
            }
        } else {
            assertRevertReasonNotEqual(returnData, "Panic(17)");
        }
    }

    function addColl(uint _coll, uint256 _i) external log {
        actor = actors[msg.sender];

        bool success;
        bytes memory returnData;

        uint256 numberOfCdps = sortedCdps.cdpCountOf(address(actor));
        require(numberOfCdps > 0, "Actor must have at least one CDP open");

        _i = clampBetween(_i, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(actor), _i);
        assertWithMsg(_cdpId != bytes32(0), "CDP ID must not be null if the index is valid");

        _coll = clampBetween(_coll, 0, INITIAL_COLL_BALANCE / 10);

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
        assertWithMsg(success, "Approve never fails");

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
                cdpManager.recoveryModeGracePeriod()
            );

            assertEq(vars.newTcrSyncPendingGlobalStateAfter, vars.tcrAfter, GENERAL_11);
            assertWithMsg(
                vars.nicrAfter > vars.nicrBefore || collateral.getEthPerShare() != 1e18,
                BO_03
            );
            // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/3
            assertWithMsg(invariant_GENERAL_09(cdpManager, vars), GENERAL_09);
            // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/4
            assertGte(
                collateral.getPooledEthByShares(cdpManager.getCdpColl(_cdpId)),
                borrowerOperations.MIN_NET_COLL(),
                GENERAL_10
            );

            assertWithMsg(invariant_GENERAL_01(vars), GENERAL_01);

            if (
                vars.lastGracePeriodStartTimestampIsSetBefore &&
                vars.isRecoveryModeBefore &&
                vars.isRecoveryModeAfter
            ) {
                assertEq(
                    vars.lastGracePeriodStartTimestampBefore,
                    vars.lastGracePeriodStartTimestampAfter,
                    L_14
                );
            }

            if (!vars.isRecoveryModeBefore && vars.isRecoveryModeAfter) {
                assertWithMsg(
                    !vars.lastGracePeriodStartTimestampIsSetBefore &&
                        vars.lastGracePeriodStartTimestampIsSetAfter,
                    L_15
                );
            }

            if (vars.isRecoveryModeBefore && !vars.isRecoveryModeAfter) {
                assertWithMsg(!vars.lastGracePeriodStartTimestampIsSetAfter, L_16);
            }
        } else {
            assertRevertReasonNotEqual(returnData, "Panic(17)");
        }
    }

    function withdrawColl(uint _amount, uint256 _i) external {
        actor = actors[msg.sender];

        bool success;
        bytes memory returnData;

        uint256 numberOfCdps = sortedCdps.cdpCountOf(address(actor));
        require(numberOfCdps > 0, "Actor must have at least one CDP open");

        _i = clampBetween(_i, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(actor), _i);
        assertWithMsg(_cdpId != bytes32(0), "CDP ID must not be null if the index is valid");

        // Can only withdraw up to CDP collateral amount, otherwise will revert with assert
        _amount = clampBetween(
            _amount,
            0,
            collateral.getPooledEthByShares(cdpManager.getCdpColl(_cdpId))
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
            assertEq(vars.newTcrSyncPendingGlobalStateAfter, vars.tcrAfter, GENERAL_11);
            assertLte(vars.nicrAfter, vars.nicrBefore, BO_04);
            // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/3
            assertWithMsg(invariant_GENERAL_09(cdpManager, vars), GENERAL_09);
            assertWithMsg(invariant_GENERAL_01(vars), GENERAL_01);
            // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/4
            assertGte(
                collateral.getPooledEthByShares(cdpManager.getCdpColl(_cdpId)),
                borrowerOperations.MIN_NET_COLL(),
                GENERAL_10
            );

            if (
                vars.lastGracePeriodStartTimestampIsSetBefore &&
                vars.isRecoveryModeBefore &&
                vars.isRecoveryModeAfter
            ) {
                assertEq(
                    vars.lastGracePeriodStartTimestampBefore,
                    vars.lastGracePeriodStartTimestampAfter,
                    L_14
                );
            }

            if (!vars.isRecoveryModeBefore && vars.isRecoveryModeAfter) {
                assertWithMsg(
                    !vars.lastGracePeriodStartTimestampIsSetBefore &&
                        vars.lastGracePeriodStartTimestampIsSetAfter,
                    L_15
                );
            }

            if (vars.isRecoveryModeBefore && !vars.isRecoveryModeAfter) {
                assertWithMsg(!vars.lastGracePeriodStartTimestampIsSetAfter, L_16);
            }
        } else {
            assertRevertReasonNotEqual(returnData, "Panic(17)");
        }
    }

    function withdrawEBTC(uint _amount, uint256 _i) external {
        actor = actors[msg.sender];

        bool success;
        bytes memory returnData;

        uint256 numberOfCdps = sortedCdps.cdpCountOf(address(actor));
        require(numberOfCdps > 0, "Actor must have at least one CDP open");

        _i = clampBetween(_i, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(actor), _i);
        assertWithMsg(_cdpId != bytes32(0), "CDP ID must not be null if the index is valid");

        // TODO verify the assumption below, maybe there's a more sensible (or Governance-defined/hardcoded) limit for the maximum amount of minted eBTC at a single operation
        // Can only withdraw up to type(uint128).max eBTC, so that `BorrwerOperations._getNewCdpAmounts` does not overflow
        _amount = clampBetween(_amount, 0, type(uint128).max);

        _before(_cdpId);

        (success, returnData) = actor.proxy(
            address(borrowerOperations),
            abi.encodeWithSelector(
                BorrowerOperations.withdrawEBTC.selector,
                _cdpId,
                _amount,
                _cdpId,
                _cdpId
            )
        );

        require(success);

        _after(_cdpId);

        assertEq(vars.newTcrSyncPendingGlobalStateAfter, vars.tcrAfter, GENERAL_11);
        assertGte(vars.debtAfter, vars.debtBefore, "withdrawEBTC must not decrease debt");
        assertEq(
            vars.actorEbtcAfter,
            vars.actorEbtcBefore + _amount,
            "withdrawEBTC must increase debt by requested amount"
        );
        // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/4
        assertGte(
            collateral.getPooledEthByShares(cdpManager.getCdpColl(_cdpId)),
            borrowerOperations.MIN_NET_COLL(),
            GENERAL_10
        );

        if (
            vars.lastGracePeriodStartTimestampIsSetBefore &&
            vars.isRecoveryModeBefore &&
            vars.isRecoveryModeAfter
        ) {
            assertEq(
                vars.lastGracePeriodStartTimestampBefore,
                vars.lastGracePeriodStartTimestampAfter,
                L_14
            );
        }

        if (!vars.isRecoveryModeBefore && vars.isRecoveryModeAfter) {
            assertWithMsg(
                !vars.lastGracePeriodStartTimestampIsSetBefore &&
                    vars.lastGracePeriodStartTimestampIsSetAfter,
                L_15
            );
        }

        if (vars.isRecoveryModeBefore && !vars.isRecoveryModeAfter) {
            assertWithMsg(!vars.lastGracePeriodStartTimestampIsSetAfter, L_16);
        }
    }

    function repayEBTC(uint _amount, uint256 _i) external log {
        actor = actors[msg.sender];

        bool success;
        bytes memory returnData;

        uint256 numberOfCdps = sortedCdps.cdpCountOf(address(actor));
        require(numberOfCdps > 0, "Actor must have at least one CDP open");

        _i = clampBetween(_i, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(actor), _i);
        assertWithMsg(_cdpId != bytes32(0), "CDP ID must not be null if the index is valid");

        (uint256 entireDebt, , ) = cdpManager.getEntireDebtAndColl(_cdpId);
        _amount = clampBetween(_amount, 0, entireDebt);

        _before(_cdpId);

        (success, returnData) = actor.proxy(
            address(borrowerOperations),
            abi.encodeWithSelector(
                BorrowerOperations.repayEBTC.selector,
                _cdpId,
                _amount,
                _cdpId,
                _cdpId
            )
        );
        require(success);

        _after(_cdpId);

        assertEq(vars.newTcrSyncPendingGlobalStateAfter, vars.tcrAfter, GENERAL_11);

        // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/3
        assertGt(
            vars.newTcrSyncPendingGlobalStateAfter,
            vars.newTcrSyncPendingGlobalStateBefore,
            BO_08
        );

        assertEq(vars.ebtcTotalSupplyBefore - _amount, vars.ebtcTotalSupplyAfter, BO_07);
        assertEq(vars.actorEbtcBefore - _amount, vars.actorEbtcAfter, BO_07);
        // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/3
        assertWithMsg(invariant_GENERAL_09(cdpManager, vars), GENERAL_09);
        assertWithMsg(invariant_GENERAL_01(vars), GENERAL_01);
        // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/4
        assertGte(
            collateral.getPooledEthByShares(cdpManager.getCdpColl(_cdpId)),
            borrowerOperations.MIN_NET_COLL(),
            GENERAL_10
        );

        if (
            vars.lastGracePeriodStartTimestampIsSetBefore &&
            vars.isRecoveryModeBefore &&
            vars.isRecoveryModeAfter
        ) {
            assertEq(
                vars.lastGracePeriodStartTimestampBefore,
                vars.lastGracePeriodStartTimestampAfter,
                L_14
            );
        }

        if (!vars.isRecoveryModeBefore && vars.isRecoveryModeAfter) {
            assertWithMsg(
                !vars.lastGracePeriodStartTimestampIsSetBefore &&
                    vars.lastGracePeriodStartTimestampIsSetAfter,
                L_15
            );
        }

        if (vars.isRecoveryModeBefore && !vars.isRecoveryModeAfter) {
            assertWithMsg(!vars.lastGracePeriodStartTimestampIsSetAfter, L_16);
        }
    }

    function closeCdp(uint _i) external log {
        actor = actors[msg.sender];

        bool success;
        bytes memory returnData;

        require(cdpManager.getCdpIdsCount() > 1, "Cannot close last CDP");

        uint256 numberOfCdps = sortedCdps.cdpCountOf(address(actor));
        require(numberOfCdps > 0, "Actor must have at least one CDP open");

        _i = clampBetween(_i, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(actor), _i);
        assertWithMsg(_cdpId != bytes32(0), "CDP ID must not be null if the index is valid");

        _before(_cdpId);

        (success, returnData) = actor.proxy(
            address(borrowerOperations),
            abi.encodeWithSelector(BorrowerOperations.closeCdp.selector, _cdpId)
        );

        _after(_cdpId);

        if (success) {
            assertEq(vars.newTcrSyncPendingGlobalStateAfter, vars.tcrAfter, GENERAL_11);
            assertEq(
                vars.sortedCdpsSizeBefore - 1,
                vars.sortedCdpsSizeAfter,
                "closeCdp reduces list size by 1"
            );
            assertGt(
                vars.actorCollAfter,
                vars.actorCollBefore,
                "closeCdp increases the collateral balance of the user"
            );
            // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/3
            assertWithMsg(invariant_GENERAL_09(cdpManager, vars), GENERAL_09);
            emit L4(
                vars.actorCollBefore,
                vars.cdpCollBefore,
                vars.liquidatorRewardSharesBefore,
                vars.actorCollAfter
            );
            assertGt(
                // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/11
                // Note: not checking for strict equality since split fee is difficult to calculate a-priori, so the CDP collateral value may not be sent back to the user in full
                vars.actorCollAfter,
                vars.actorCollBefore +
                    // ActivePool transfer SHARES not ETH directly
                    collateral.getPooledEthByShares(vars.liquidatorRewardSharesBefore),
                BO_05
            );
            assertWithMsg(invariant_GENERAL_01(vars), GENERAL_01);

            if (
                vars.lastGracePeriodStartTimestampIsSetBefore &&
                vars.isRecoveryModeBefore &&
                vars.isRecoveryModeAfter
            ) {
                assertEq(
                    vars.lastGracePeriodStartTimestampBefore,
                    vars.lastGracePeriodStartTimestampAfter,
                    L_14
                );
            }

            if (!vars.isRecoveryModeBefore && vars.isRecoveryModeAfter) {
                assertWithMsg(
                    !vars.lastGracePeriodStartTimestampIsSetBefore &&
                        vars.lastGracePeriodStartTimestampIsSetAfter,
                    L_15
                );
            }

            if (vars.isRecoveryModeBefore && !vars.isRecoveryModeAfter) {
                assertWithMsg(!vars.lastGracePeriodStartTimestampIsSetAfter, L_16);
            }
        } else {
            assertRevertReasonNotEqual(returnData, "Panic(17)");
        }
    }

    function adjustCdp(
        uint _i,
        uint _collWithdrawal,
        uint _EBTCChange,
        bool _isDebtIncrease
    ) external log {
        actor = actors[msg.sender];

        bool success;
        bytes memory returnData;

        uint256 numberOfCdps = sortedCdps.cdpCountOf(address(actor));
        require(numberOfCdps > 0, "Actor must have at least one CDP open");

        _i = clampBetween(_i, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(actor), _i);
        assertWithMsg(_cdpId != bytes32(0), "CDP ID must not be null if the index is valid");

        (uint256 entireDebt, uint256 entireColl, ) = cdpManager.getEntireDebtAndColl(_cdpId);
        _collWithdrawal = clampBetween(_collWithdrawal, 0, entireColl);
        _EBTCChange = clampBetween(_EBTCChange, 0, entireDebt);

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

        assertEq(vars.newTcrSyncPendingGlobalStateAfter, vars.tcrAfter, GENERAL_11);
        // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/3
        assertWithMsg(invariant_GENERAL_09(cdpManager, vars), GENERAL_09);

        assertWithMsg(invariant_GENERAL_01(vars), GENERAL_01);
        // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/4
        assertGte(
            collateral.getPooledEthByShares(cdpManager.getCdpColl(_cdpId)),
            borrowerOperations.MIN_NET_COLL(),
            GENERAL_10
        );

        if (
            vars.lastGracePeriodStartTimestampIsSetBefore &&
            vars.isRecoveryModeBefore &&
            vars.isRecoveryModeAfter
        ) {
            assertEq(
                vars.lastGracePeriodStartTimestampBefore,
                vars.lastGracePeriodStartTimestampAfter,
                L_14
            );
        }

        if (!vars.isRecoveryModeBefore && vars.isRecoveryModeAfter) {
            assertWithMsg(
                !vars.lastGracePeriodStartTimestampIsSetBefore &&
                    vars.lastGracePeriodStartTimestampIsSetAfter,
                L_15
            );
        }

        if (vars.isRecoveryModeBefore && !vars.isRecoveryModeAfter) {
            assertWithMsg(!vars.lastGracePeriodStartTimestampIsSetAfter, L_16);
        }
    }

    ///////////////////////////////////////////////////////
    // Collateral Token (Test)
    ///////////////////////////////////////////////////////

    // Example for real world slashing: https://twitter.com/LidoFinance/status/1646505631678107649
    // > There are 11 slashing ongoing with the RockLogic GmbH node operator in Lido.
    // > the total projected impact is around 20 ETH,
    // > or about 3% of average daily protocol rewards/0.0004% of TVL.
    function setEthPerShare(uint256 _newEthPerShare) external {
        uint256 currentEthPerShare = collateral.getEthPerShare();
        _newEthPerShare = clampBetween(
            _newEthPerShare,
            (currentEthPerShare * 1e18) / MAX_REBASE_PERCENT,
            (currentEthPerShare * MAX_REBASE_PERCENT) / 1e18
        );
        collateral.setEthPerShare(_newEthPerShare);
    }

    ///////////////////////////////////////////////////////
    // PriceFeed
    ///////////////////////////////////////////////////////

    function setPrice(uint256 _newPrice) external {
        uint256 currentPrice = priceFeedMock.getPrice();
        _newPrice = clampBetween(
            _newPrice,
            (currentPrice * 1e18) / MAX_PRICE_CHANGE_PERCENT,
            (currentPrice * MAX_PRICE_CHANGE_PERCENT) / 1e18
        );
        priceFeedMock.setPrice(_newPrice);
    }
}
