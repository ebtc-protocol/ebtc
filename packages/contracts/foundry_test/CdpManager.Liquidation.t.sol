// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {console2 as console} from "forge-std/console2.sol";

import {eBTCBaseInvariants} from "./BaseInvariants.sol";

contract CdpManagerLiquidationTest is eBTCBaseInvariants {
    address payable[] users;

    mapping(bytes32 => bool) private _cdpLeftActive;

    ////////////////////////////////////////////////////////////////////////////
    // Liquidation Invariants for ebtc system
    // - cdp_manager_liq1： total collateral snapshot is equal to whatever in active pool
    // - cdp_manager_liq2： total collateral snapshot is equal to sum of individual CDP accounting number
    ////////////////////////////////////////////////////////////////////////////

    function _assert_cdp_manager_invariant_liq1() internal {
        assertEq(
            cdpManager.totalCollateralSnapshot(),
            activePool.getSystemCollShares(),
            "System Invariant: cdp_manager_liq1"
        );
    }

    function _assert_cdp_manager_invariant_liq2() internal {
        uint _sumColl;
        for (uint i = 0; i < cdpManager.getActiveCdpsCount(); ++i) {
            bytes32 _cdpId = cdpManager.CdpIds(i);
            (, uint _coll, , , , ) = cdpManager.Cdps(_cdpId);
            _sumColl = _sumColl + _coll;
        }
        assertEq(
            cdpManager.totalCollateralSnapshot(),
            _sumColl,
            "System Invariant: cdp_manager_liq2"
        );
    }

    function _ensureSystemInvariants_Liquidation() internal {
        _assert_cdp_manager_invariant_liq1();
        _assert_cdp_manager_invariant_liq2();
    }

    ////////////////////////////////////////////////////////////////////////////
    // Tests
    ////////////////////////////////////////////////////////////////////////////

    function setUp() public override {
        super.setUp();

        connectCoreContracts();
        connectLQTYContractsToCore();

        users = _utils.createUsers(4);
    }

    function _ensureDebtAmountValidity(uint _debtAmt) internal pure {
        vm.assume(_debtAmt > 1e18);
        vm.assume(_debtAmt < 10000e18);
    }

    function _ensureCollAmountValidity(uint _collAmt) internal pure {
        vm.assume(_collAmt > 22e17);
        vm.assume(_collAmt < 10000e18);
    }

    function _checkAvailableToLiq(bytes32 _cdpId, uint _price) internal view returns (bool) {
        uint _TCR = cdpManager.getTCR(_price);
        uint _ICR = cdpManager.getICR(_cdpId, _price);
        bool _recoveryMode = _TCR < cdpManager.CCR();
        return (_ICR < cdpManager.MCR() || (_recoveryMode && _ICR < _TCR));
    }

    // Test single CDP liquidation with price fluctuation
    function testLiquidateSingleCDP(uint256 price, uint256 debtAmt) public {
        _ensureDebtAmountValidity(debtAmt);

        uint _curPrice = priceFeedMock.getPrice();
        vm.assume(price > _curPrice / 10000);
        vm.assume(_curPrice / 2 > price);

        uint256 coll1 = _utils.calculateCollAmount(debtAmt, _curPrice, 297e16);

        vm.assume(coll1 > 22e17); // Must reach minimum coll threshold

        vm.prank(users[0]);
        collateral.approve(address(borrowerOperations), type(uint256).max);

        _openTestCDP(users[0], 10000 ether, 2e17);
        bytes32 cdpId1 = _openTestCDP(users[0], coll1, debtAmt);

        // get original debt upon CDP open
        CdpState memory _cdpState0 = _getVirtualDebtAndColl(cdpId1);

        // Price falls
        priceFeedMock.setPrice(price);

        _ensureSystemInvariants();

        // Liquidate cdp1
        bool _availableToLiq1 = _checkAvailableToLiq(cdpId1, price);
        if (_availableToLiq1) {
            CdpState memory _cdpState = _getVirtualDebtAndColl(cdpId1);
            assertEq(_cdpState.debt, _cdpState0.debt, "!interest should not accrue");

            uint _ICR = cdpManager.getICR(cdpId1, price);
            uint _expectedLiqDebt = _ICR > cdpManager.LICR()
                ? _cdpState.debt
                : ((_cdpState.collShares * price) / cdpManager.LICR());

            deal(address(eBTCToken), users[0], _cdpState.debt); // sugardaddy liquidator
            uint _debtLiquidatorBefore = eBTCToken.balanceOf(users[0]);
            uint _debtSystemBefore = cdpManager.getSystemDebt();
            vm.prank(users[0]);
            cdpManager.liquidate(cdpId1);
            uint _debtLiquidatorAfter = eBTCToken.balanceOf(users[0]);
            uint _debtSystemAfter = cdpManager.getSystemDebt();
            assertEq(
                _expectedLiqDebt,
                _debtLiquidatorBefore - _debtLiquidatorAfter,
                "!liquidator repayment"
            );
            assertEq(
                _expectedLiqDebt,
                _debtSystemBefore - _debtSystemAfter,
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
    function testPartiallyLiquidateSingleCDP(uint debtAmt, uint partialRatioBps) public {
        _ensureDebtAmountValidity(debtAmt);
        vm.assume(partialRatioBps < 10000);
        vm.assume(partialRatioBps > 0);

        uint _curPrice = priceFeedMock.getPrice();

        // in this test, simply use if debtAmt is a multiple of 2 to simulate two scenarios
        bool _icrGtLICR = (debtAmt % 2 == 0) ? true : false;
        uint256 coll1 = _utils.calculateCollAmount(debtAmt, _curPrice, _icrGtLICR ? 249e16 : 205e16);

        vm.prank(users[0]);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        _openTestCDP(users[0], 10000 ether, 2e17);
        bytes32 cdpId1 = _openTestCDP(users[0], coll1, debtAmt);

        // get original debt upon CDP open
        CdpState memory _cdpState0 = _getVirtualDebtAndColl(cdpId1);

        // Price falls
        uint _newPrice = _curPrice / 2;
        priceFeedMock.setPrice(_newPrice);

        _ensureSystemInvariants();

        // Partially Liquidate cdp1
        bool _availableToLiq1 = _checkAvailableToLiq(cdpId1, _newPrice);
        if (_availableToLiq1) {
            CdpState memory _cdpState = _getVirtualDebtAndColl(cdpId1);
            assertEq(_cdpState.debt, _cdpState0.debt, "!interest should not accrue");

            LocalVar_PartialLiq memory _partialLiq;
            _partialLiq._ratio = _icrGtLICR ? cdpManager.MCR() : cdpManager.LICR();
            _partialLiq._repaidDebt = (_cdpState.debt * partialRatioBps) / 10000;
            if (
                (_cdpState.collShares - cdpManager.MIN_CDP_STETH_BALANCE()) <=
                ((_partialLiq._repaidDebt * _partialLiq._ratio) / _newPrice)
            ) {
                _partialLiq._repaidDebt =
                    ((_cdpState.collShares - cdpManager.MIN_CDP_STETH_BALANCE() * 3) * _newPrice) /
                    _partialLiq._ratio;
                if (_partialLiq._repaidDebt >= 2) {
                    _partialLiq._repaidDebt = _partialLiq._repaidDebt - 1;
                }
            }
            _partialLiq._collToLiquidator =
                (_partialLiq._repaidDebt * _partialLiq._ratio) /
                _newPrice;

            // fully liquidate instead
            uint _expectedLiqDebt = _partialLiq._repaidDebt;
            bool _fully = _partialLiq._collToLiquidator >= _cdpState.collShares;
            if (_fully) {
                _partialLiq._collToLiquidator = _cdpState.collShares;
                _expectedLiqDebt = (_partialLiq._collToLiquidator * _newPrice) / cdpManager.LICR();
            }

            deal(address(eBTCToken), users[0], _cdpState.debt); // sugardaddy liquidator
            {
                uint _debtLiquidatorBefore = eBTCToken.balanceOf(users[0]);
                uint _debtSystemBefore = cdpManager.getSystemDebt();
                uint _collSystemBefore = cdpManager.getEntireSystemColl();
                vm.prank(users[0]);
                cdpManager.partiallyLiquidate(cdpId1, _partialLiq._repaidDebt, cdpId1, cdpId1);
                uint _debtLiquidatorAfter = eBTCToken.balanceOf(users[0]);
                uint _debtSystemAfter = cdpManager.getSystemDebt();
                uint _collSystemAfter = cdpManager.getEntireSystemColl();
                assertEq(
                    _expectedLiqDebt,
                    _debtLiquidatorBefore - _debtLiquidatorAfter,
                    "!liquidator repayment"
                );
                assertEq(
                    _expectedLiqDebt,
                    _debtSystemBefore - _debtSystemAfter,
                    "!system debt reduction"
                );
                assertEq(
                    _partialLiq._collToLiquidator,
                    _collSystemBefore - _collSystemAfter,
                    "!system coll reduction"
                );
            }

            // target CDP got partially liquidated but still active
            // OR target CDP got fully liquidated
            if (_fully) {
                assertFalse(sortedCdps.contains(cdpId1));
                assertTrue(cdpManager.getCdpStatus(cdpId1) == 3);

                _assertCdpClosed(cdpId1, 3);
                _assertCdpNotInSortedCdps(cdpId1);
            } else {
                assertTrue(sortedCdps.contains(cdpId1));
                assertTrue(cdpManager.getCdpStatus(cdpId1) == 1);
            }

            // check invariants
            _ensureSystemInvariants_Liquidation();
        }

        _ensureSystemInvariants();
    }

    function _checkCdpStatus(bytes32 _cdpId) internal {
        assertTrue(sortedCdps.contains(_cdpId) == _cdpLeftActive[_cdpId]);
        assertTrue(cdpManager.getCdpStatus(_cdpId) == (_cdpLeftActive[_cdpId] ? 1 : 3));
    }

    function _multipleCDPsLiq(uint _n, bytes32[] memory _cdps, address _liquidator) internal {
        /// entire systme debt = activePool
        uint _debtSystemBefore = cdpManager.getSystemDebt();

        deal(address(eBTCToken), _liquidator, _debtSystemBefore); // sugardaddy liquidator
        uint _debtLiquidatorBefore = eBTCToken.balanceOf(_liquidator);

        vm.prank(_liquidator);
        if (_n > 0) {
            cdpManager.liquidateCdps(_n);
        } else {
            cdpManager.batchLiquidateCdps(_cdps);
        }

        uint _debtLiquidatorAfter = eBTCToken.balanceOf(_liquidator);
        uint _debtSystemAfter = cdpManager.getSystemDebt();

        // calc debt in system by summing up all CDPs debt
        uint _leftTotalDebt;
        for (uint i = 0; i < cdpManager.getActiveCdpsCount(); ++i) {
            (uint _cdpDebt, , ) = cdpManager.getVirtualDebtAndColl(cdpManager.CdpIds(i));
            _leftTotalDebt = (_leftTotalDebt + _cdpDebt);
            _cdpLeftActive[cdpManager.CdpIds(i)] = true;
        }

        console.log("_leftTotalDebt from system", _leftTotalDebt);

        uint _liquidatedDebt = (_debtSystemBefore - _debtSystemAfter);

        console.log("_debtSystemBefore", _debtSystemBefore);
        console.log("_debtLiquidatorBefore", _debtLiquidatorBefore);
        console.log("_debtSystemAfter", _debtSystemAfter);
        console.log("_debtLiquidatorAfter", _debtLiquidatorAfter);
        console.log("_leftTotalDebt", _leftTotalDebt);
        console.log("activePool.getSystemDebt()", activePool.getSystemDebt());
        console.log("_liquidatedDebt", _liquidatedDebt);

        assertEq(
            _liquidatedDebt,
            (_debtLiquidatorBefore - _debtLiquidatorAfter),
            "!liquidator repayment"
        );
        _utils.assertApproximateEq(_leftTotalDebt, _debtSystemAfter, 1e6); //compared to 1e18
    }

    // Test multiple CDPs sequence liquidation with price fluctuation
    function testSequenceLiquidateMultipleCDPs(
        uint256 price,
        uint256 debtAmt1,
        uint256 debtAmt2
    ) public {
        _ensureDebtAmountValidity(debtAmt1);
        _ensureDebtAmountValidity(debtAmt2);

        uint _curPrice = priceFeedMock.getPrice();
        vm.assume(price > _curPrice / 10000);
        vm.assume(_curPrice / 2 > price);

        uint256 coll1 = _utils.calculateCollAmount(debtAmt1, _curPrice, 297e16);
        uint256 coll2 = _utils.calculateCollAmount(debtAmt2, _curPrice, 297e16);

        vm.prank(users[1]);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        vm.prank(users[2]);
        collateral.approve(address(borrowerOperations), type(uint256).max);

        _openTestCDP(users[0], 10000 ether, 2e17);
        bytes32 cdpId1 = _openTestCDP(users[1], coll1, debtAmt1);
        bytes32 cdpId2 = _openTestCDP(users[2], coll2, debtAmt2);

        // Price falls
        priceFeedMock.setPrice(price);

        _ensureSystemInvariants();

        // Liquidate All eligible cdps
        bool _availableToLiq1 = _checkAvailableToLiq(cdpId1, price);
        bool _availableToLiq2 = _checkAvailableToLiq(cdpId2, price);
        if (_availableToLiq1 || _availableToLiq2) {
            // get original debt
            CdpState memory _cdpState1 = _getVirtualDebtAndColl(cdpId1);
            CdpState memory _cdpState2 = _getVirtualDebtAndColl(cdpId2);

            bytes32[] memory _emptyCdps;
            _multipleCDPsLiq(2, _emptyCdps, users[0]);

            // check if CDP got liquidated
            _checkCdpStatus(cdpId1);
            _checkCdpStatus(cdpId2);

            _ensureSystemInvariants_Liquidation();
        }

        _ensureSystemInvariants();
    }

    // Test multiple CDPs batch liquidation with price fluctuation
    function testBatchLiquidateMultipleCDPs(
        uint256 price,
        uint256 debtAmt1,
        uint256 debtAmt2
    ) public {
        _ensureDebtAmountValidity(debtAmt1);
        _ensureDebtAmountValidity(debtAmt2);

        uint _curPrice = priceFeedMock.getPrice();
        vm.assume(price > _curPrice / 10000);
        vm.assume(_curPrice / 2 > price);

        uint256 coll1 = _utils.calculateCollAmount(debtAmt1, _curPrice, 297e16);
        uint256 coll2 = _utils.calculateCollAmount(debtAmt2, _curPrice, 297e16);

        vm.prank(users[1]);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        vm.prank(users[2]);
        collateral.approve(address(borrowerOperations), type(uint256).max);

        _openTestCDP(users[0], 10000 ether, 2e17);
        bytes32 cdpId1 = _openTestCDP(users[1], coll1, debtAmt1);
        bytes32 cdpId2 = _openTestCDP(users[2], coll2, debtAmt2);

        // Price falls
        priceFeedMock.setPrice(price);

        _ensureSystemInvariants();

        // Liquidate All eligible cdps
        bool _availableToLiq1 = _checkAvailableToLiq(cdpId1, price);
        bool _availableToLiq2 = _checkAvailableToLiq(cdpId2, price);
        if (_availableToLiq1 || _availableToLiq2) {
            // get original debt
            CdpState memory _cdpState1 = _getVirtualDebtAndColl(cdpId1);
            CdpState memory _cdpState2 = _getVirtualDebtAndColl(cdpId2);

            bytes32[] memory _cdps = new bytes32[](2);
            _cdps[0] = cdpId1;
            _cdps[1] = cdpId2;
            _multipleCDPsLiq(0, _cdps, users[0]);

            // check if CDP got liquidated
            _checkCdpStatus(cdpId1);
            _checkCdpStatus(cdpId2);

            _ensureSystemInvariants_Liquidation();
        }

        _ensureSystemInvariants();
    }

    function test_RedistributedDebtIsHandledProperlyOnPartialLiquidation() public {
        // create 2 CDPs
        address alice = users[0];
        address bob = users[1];
        address marketActor = users[2];

        priceFeedMock.setPrice(1 ether);

        uint collShares = 20 ether;
        uint debt = 10 ether;

        bytes32 aliceCdpId = _openTestCDP(alice, collShares, debt);
        bytes32 bobCdpId = _openTestCDP(bob, collShares, debt);

        vm.prank(alice);
        eBTCToken.transfer(marketActor, debt);

        vm.prank(bob);
        eBTCToken.transfer(marketActor, debt);

        // make liquidatable at price where ICR < 100
        priceFeedMock.setPrice(0.4 ether);

        // fully liquidate one CDP, distributing bad debt
        vm.startPrank(marketActor);
        cdpManager.liquidate(bobCdpId);

        // check bad debt status
        (uint aliceDebt, uint aliceCollShares, uint pendingBadDebt) = cdpManager.getVirtualDebtAndColl(aliceCdpId);

        console.log("aliceDebt:", aliceDebt);
        console.log("aliceCollShares:", aliceCollShares);
        console.log("pendingBadDebt:", pendingBadDebt);
        console.log("systemDebtRedistributionIndex:", cdpManager.systemDebtRedistributionIndex());
        console.log("alice debtRedistributionIndex:", cdpManager.debtRedistributionIndex(aliceCdpId));

        // bring to ICR < MCR && ICR > 100
        priceFeedMock.setPrice(0.52 ether);

        // partially liquidate remaining CDP
        cdpManager.partiallyLiquidate(aliceCdpId, debt / 2, bytes32(0), bytes32(0));

        (aliceDebt, aliceCollShares, pendingBadDebt) = cdpManager.getVirtualDebtAndColl(aliceCdpId);

        // ensure bad debt is accounted for properly
        console.log("aliceDebt:", aliceDebt);
        console.log("aliceCollShares:", aliceCollShares);
        console.log("pendingBadDebt:", pendingBadDebt);
        console.log("systemDebtRedistributionIndex:", cdpManager.systemDebtRedistributionIndex());
        console.log("alice debtRedistributionIndex:", cdpManager.debtRedistributionIndex(aliceCdpId));

        /**
            Check:
                bad debt global and Cdp index before & after
                pending bad debt before and after 
                print CDP state before and after to confirm

                The CDP should apply pending state before any operations
         */
    }

    function testFullLiquidation() public {
        // Set up a test case where the CDP is fully liquidated, with ICR below MCR or TCR in recovery mode
        // Call _liquidateSingleCDP with the appropriate arguments
        // Assert that the correct total debt was burned, collateral was sent, and any remaining debt was redistributed
    }

    function testPartialLiquidation() public {
        // Set up a test case where the CDP is only partially liquidated using HintHelper, with ICR below MCR or TCR in recovery mode
        // Call _liquidateSingleCDP with the appropriate arguments
        // Assert that the correct total debt was burned and collateral was sent, and that no remaining debt was redistributed
    }

    function testRetryFullLiquidation() public {
        // Set up a test case where the CDP is partially liquidated but the amount of collateral sent is 0, resulting in a retry with full liquidation
        // Call _liquidateSingleCDP with the appropriate arguments
        // Assert that the correct total debt was burned, collateral was sent, and any remaining debt was redistributed
    }
}
