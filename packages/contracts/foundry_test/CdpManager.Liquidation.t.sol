// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.11;

import {console2 as console} from "forge-std/console2.sol";

import {eBTCBaseFixture} from "./BaseFixture.sol";
import {Utilities} from "./utils/Utilities.sol";

contract CdpManagerLiquidationTest is eBTCBaseFixture {
    struct CdpState {
        uint256 debt;
        uint256 coll;
        uint256 pendingEBTCDebtReward;
        uint256 pendingEBTCInterest;
        uint256 pendingETHReward;
    }

    address payable[] users;

    Utilities internal _utils;

    uint public constant DECIMAL_PRECISION = 1e18;

    ////////////////////////////////////////////////////////////////////////////
    // Helper functions
    ////////////////////////////////////////////////////////////////////////////

    function _getEntireDebtAndColl(bytes32 cdpId) internal view returns (CdpState memory) {
        (
            uint256 debt,
            uint256 coll,
            uint256 pendingEBTCDebtReward,
            uint256 pendingEBTCDebtInterest,
            uint256 pendingETHReward
        ) = cdpManager.getEntireDebtAndColl(cdpId);
        return
            CdpState(debt, coll, pendingEBTCDebtReward, pendingEBTCDebtInterest, pendingETHReward);
    }

    ////////////////////////////////////////////////////////////////////////////
    // Invariants for ebtc system
    // - active_pool_1： collateral balance in active pool is greater than or equal to its accounting number
    // - active_pool_2： EBTC debt accounting number in active pool is less than or equal to EBTC total supply
    // - active_pool_3： sum of EBTC debt accounting numbers in active pool & default pool is equal to EBTC total supply
    // - cdp_manager_1： count of active CDPs is equal to SortedCdp list length
    // - cdp_manager_2： total collateral snapshot is equal to whatever in active pool & default pool
    // - cdp_manager_3： total collateral snapshot is equal to sum of individual CDP accounting number
    ////////////////////////////////////////////////////////////////////////////

    function _assert_active_pool_invariant_1() internal {
        assertGe(
            address(activePool).balance,
            activePool.getETH(),
            "System Invariant: active_pool_1"
        );
    }

    function _assert_active_pool_invariant_2() internal {
        assertGe(
            eBTCToken.totalSupply(),
            activePool.getEBTCDebt(),
            "System Invariant: active_pool_2"
        );
    }

    function _assert_active_pool_invariant_3() internal {
        assertEq(
            eBTCToken.totalSupply(),
            activePool.getEBTCDebt().add(defaultPool.getEBTCDebt()),
            "System Invariant: active_pool_3"
        );
    }

    function _assert_cdp_manager_invariant_1() internal {
        assertEq(
            cdpManager.getCdpIdsCount(),
            sortedCdps.getSize(),
            "System Invariant: cdp_manager_1"
        );
    }

    function _assert_cdp_manager_invariant_2() internal {
        assertEq(
            cdpManager.totalCollateralSnapshot(),
            activePool.getETH().add(defaultPool.getETH()),
            "System Invariant: cdp_manager_2"
        );
    }

    function _assert_cdp_manager_invariant_3() internal {
        uint _sumColl;
        for (uint i = 0; i < cdpManager.getCdpIdsCount(); ++i) {
            bytes32 _cdpId = cdpManager.CdpIds(i);
            (uint _debt, uint _coll, , , ) = cdpManager.Cdps(_cdpId);
            _sumColl = _sumColl.add(_coll);
        }
        assertEq(cdpManager.totalCollateralSnapshot(), _sumColl, "System Invariant: cdp_manager_3");
    }

    function _ensureSystemInvariants() internal {
        _assert_active_pool_invariant_1();
        _assert_active_pool_invariant_2();
        _assert_active_pool_invariant_3();
        _assert_cdp_manager_invariant_1();
    }

    function _ensureSystemInvariants_Liquidation() internal {
        _assert_cdp_manager_invariant_2();
        _assert_cdp_manager_invariant_3();
    }

    ////////////////////////////////////////////////////////////////////////////
    // Tests
    ////////////////////////////////////////////////////////////////////////////

    function setUp() public override {
        eBTCBaseFixture.setUp();

        eBTCBaseFixture.connectLQTYContracts();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();

        _utils = new Utilities();
        users = _utils.createUsers(1);
    }

    // Test single CDP liquidation with price fluctuation
    function testLiquidateSingleCDP(uint256 price, uint256 debtAmt) public {
        vm.assume(debtAmt > 1e18);
        vm.assume(debtAmt < 10000e18);

        uint _curPrice = priceFeedMock.getPrice();
        vm.assume(price > _curPrice / 10000);
        vm.assume(_curPrice > price * 2);

        uint256 coll1 = _utils.calculateCollAmount(debtAmt, _curPrice, 297e16);

        vm.startPrank(users[0]);
        borrowerOperations.openCdp{value: 10000 ether}(
            DECIMAL_PRECISION,
            _utils.calculateBorrowAmountFromDebt(
                2e17,
                cdpManager.EBTC_GAS_COMPENSATION(),
                cdpManager.getBorrowingRateWithDecay()
            ),
            bytes32(0),
            bytes32(0)
        );
        bytes32 cdpId1 = borrowerOperations.openCdp{value: coll1}(
            DECIMAL_PRECISION,
            debtAmt,
            bytes32(0),
            bytes32(0)
        );
        vm.stopPrank();

        // get original debt upon CDP open
        CdpState memory _cdpState0 = _getEntireDebtAndColl(cdpId1);

        // accrue some interest before liquidation
        skip(365 days);

        // Price falls
        priceFeedMock.setPrice(price);

        _ensureSystemInvariants();

        // Liquidate cdp1
        uint _TCR = cdpManager.getTCR(price);
        uint _ICR = cdpManager.getCurrentICR(cdpId1, price);
        bool _recoveryMode = _TCR < cdpManager.CCR();
        if (_ICR < cdpManager.MCR() || (_recoveryMode && _ICR < _TCR)) {
            CdpState memory _cdpState = _getEntireDebtAndColl(cdpId1);
            assertGt(_cdpState.debt, _cdpState0.debt, "!interest should accrue");

            deal(address(eBTCToken), users[0], _cdpState.debt); // sugardaddy liquidator
            uint _debtLiquidatorBefore = eBTCToken.balanceOf(users[0]);
            uint _debtSystemBefore = cdpManager.getEntireSystemDebt();
            vm.prank(users[0]);
            cdpManager.liquidate(cdpId1);
            uint _debtLiquidatorAfter = eBTCToken.balanceOf(users[0]);
            uint _debtSystemAfter = cdpManager.getEntireSystemDebt();
            assertEq(
                _cdpState.debt,
                _debtLiquidatorBefore.sub(_debtLiquidatorAfter),
                "!liquidator repayment"
            );
            assertEq(
                _cdpState.debt,
                _debtSystemBefore.sub(_debtSystemAfter),
                "!system debt reduction"
            );

            // target CDP got liquidated
            assertFalse(sortedCdps.contains(cdpId1));

            // check state is closedByLiquidation
            assertTrue(cdpManager.getCdpStatus(cdpId1) == 3);
            _ensureSystemInvariants_Liquidation();
        }

        _ensureSystemInvariants();
    }

    struct LocalVar_PartialLiq {
        uint _ratio;
        uint _repaidDebt;
        uint _collToLiquidator;
    }

    // Test single CDP partial liquidation with variable ratio for partial repayment:
    // - when its ICR is higher than LICR then the collateral to liquidator is (repaidDebt * LICR) / price
    // - when its ICR is lower than LICR then the collateral to liquidator is (repaidDebt * ICR) / price
    function testPartiallyLiquidateSingleCDP(uint256 debtAmt, uint256 partialRatioBps) public {
        vm.assume(debtAmt > 1e17);
        vm.assume(debtAmt < 10000e18);
        vm.assume(partialRatioBps < 10000);
        vm.assume(partialRatioBps > 0);

        uint _curPrice = priceFeedMock.getPrice();

        // in this test, simply use if debtAmt is a multiple of 2 to simulate two scenarios
        bool _icrGtLICR = (debtAmt % 2 == 0) ? true : false;
        uint256 coll1 = _utils.calculateCollAmount(debtAmt, _curPrice, _icrGtLICR ? 297e16 : 206e16);

        vm.startPrank(users[0]);
        borrowerOperations.openCdp{value: 10000 ether}(
            DECIMAL_PRECISION,
            _utils.calculateBorrowAmountFromDebt(
                2e17,
                cdpManager.EBTC_GAS_COMPENSATION(),
                cdpManager.getBorrowingRateWithDecay()
            ),
            bytes32(0),
            bytes32(0)
        );
        bytes32 cdpId1 = borrowerOperations.openCdp{value: coll1}(
            DECIMAL_PRECISION,
            debtAmt,
            bytes32(0),
            bytes32(0)
        );
        vm.stopPrank();

        // get original debt upon CDP open
        CdpState memory _cdpState0 = _getEntireDebtAndColl(cdpId1);

        // accrue some interest before liquidation
        skip(365 days);

        // Price falls
        uint _newPrice = _curPrice / 2;
        priceFeedMock.setPrice(_newPrice);

        _ensureSystemInvariants();

        // Partially Liquidate cdp1
        uint _ICR = cdpManager.getCurrentICR(cdpId1, _newPrice);
        uint _TCR = cdpManager.getTCR(_newPrice);
        bool _recoveryMode = _TCR < cdpManager.CCR();
        if (_ICR < cdpManager.MCR() || (_recoveryMode && _ICR < _TCR)) {
            CdpState memory _cdpState = _getEntireDebtAndColl(cdpId1);
            assertGt(_cdpState.debt, _cdpState0.debt, "!interest should accrue");

            LocalVar_PartialLiq memory _partialLiq;
            _partialLiq._ratio = _icrGtLICR ? cdpManager.LICR() : _ICR;
            _partialLiq._repaidDebt = (_cdpState.debt * partialRatioBps) / 10000;
            if (_cdpState.debt - _partialLiq._repaidDebt < cdpManager.MIN_NET_DEBT()) {
                _partialLiq._repaidDebt = _cdpState.debt - cdpManager.MIN_NET_DEBT();
            }
            _partialLiq._collToLiquidator =
                (_partialLiq._repaidDebt * _partialLiq._ratio) /
                _newPrice;

            deal(address(eBTCToken), users[0], _cdpState.debt); // sugardaddy liquidator
            {
                uint _debtLiquidatorBefore = eBTCToken.balanceOf(users[0]);
                uint _debtSystemBefore = cdpManager.getEntireSystemDebt();
                uint _collSystemBefore = cdpManager.getEntireSystemColl();
                vm.prank(users[0]);
                cdpManager.partiallyLiquidate(cdpId1, _partialLiq._repaidDebt, cdpId1, cdpId1);
                uint _debtLiquidatorAfter = eBTCToken.balanceOf(users[0]);
                uint _debtSystemAfter = cdpManager.getEntireSystemDebt();
                uint _collSystemAfter = cdpManager.getEntireSystemColl();
                assertEq(
                    _partialLiq._repaidDebt,
                    _debtLiquidatorBefore.sub(_debtLiquidatorAfter),
                    "!liquidator repayment"
                );
                assertEq(
                    _partialLiq._repaidDebt,
                    _debtSystemBefore.sub(_debtSystemAfter),
                    "!system debt reduction"
                );
                assertEq(
                    _partialLiq._collToLiquidator,
                    _collSystemBefore.sub(_collSystemAfter),
                    "!system coll reduction"
                );
            }

            // target CDP got partially liquidated but still active
            assertTrue(sortedCdps.contains(cdpId1));

            // check state is active
            assertTrue(cdpManager.getCdpStatus(cdpId1) == 1);
            _ensureSystemInvariants_Liquidation();
        }

        _ensureSystemInvariants();
    }
}
