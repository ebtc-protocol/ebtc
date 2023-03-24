// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;
import {console2 as console} from "forge-std/console2.sol";

import {eBTCBaseInvariants} from "./BaseInvariants.sol";
import {Utilities} from "./utils/Utilities.sol";

contract CdpManagerLiquidationTest is eBTCBaseInvariants {
    address payable[] users;

    uint public constant DECIMAL_PRECISION = 1e18;
    mapping(bytes32 => bool) private _cdpLeftActive;

    ////////////////////////////////////////////////////////////////////////////
    // Liquidation Invariants for ebtc system
    // - cdp_manager_liq1： total collateral snapshot is equal to whatever in active pool & default pool
    // - cdp_manager_liq2： total collateral snapshot is equal to sum of individual CDP accounting number
    ////////////////////////////////////////////////////////////////////////////

    function _assert_cdp_manager_invariant_liq1() internal {
        assertEq(
            cdpManager.totalCollateralSnapshot(),
            activePool.getETH().add(defaultPool.getETH()),
            "System Invariant: cdp_manager_liq1"
        );
    }

    function _assert_cdp_manager_invariant_liq2() internal {
        uint _sumColl;
        for (uint i = 0; i < cdpManager.getCdpIdsCount(); ++i) {
            bytes32 _cdpId = cdpManager.CdpIds(i);
            (uint _debt, uint _coll, , , ) = cdpManager.Cdps(_cdpId);
            _sumColl = _sumColl.add(_coll);
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

        connectLQTYContracts();
        connectCoreContracts();
        connectLQTYContractsToCore();

        _utils = new Utilities();
        users = _utils.createUsers(4);
    }

    function _ensureDebtAmountValidity(uint _debtAmt) internal {
        vm.assume(_debtAmt > 1e18);
        vm.assume(_debtAmt < 10000e18);
    }

    function _openTestCDP(address _user, uint _coll, uint _debt) internal returns (bytes32) {
        dealCollateral(_user, _coll);
        vm.startPrank(_user);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        bytes32 _cdpId = borrowerOperations.openCdp(
            DECIMAL_PRECISION,
            _debt,
            bytes32(0),
            bytes32(0),
            _coll
        );
        vm.stopPrank();
        return _cdpId;
    }

    function _checkAvailableToLiq(bytes32 _cdpId, uint _price) internal view returns (bool) {
        uint _TCR = cdpManager.getTCR(_price);
        uint _ICR = cdpManager.getCurrentICR(_cdpId, _price);
        bool _recoveryMode = _TCR < cdpManager.CCR();
        return (_ICR < cdpManager.MCR() || (_recoveryMode && _ICR < _TCR));
    }

    // Test single CDP liquidation with price fluctuation
    function testLiquidateSingleCDP(uint256 price, uint256 debtAmt) public {
        _ensureDebtAmountValidity(debtAmt);

        uint _curPrice = priceFeedMock.getPrice();
        vm.assume(price > _curPrice / 10000);
        vm.assume(_curPrice > price * 2);

        uint256 coll1 = _utils.calculateCollAmount(debtAmt, _curPrice, 297e16);

        vm.prank(users[0]);
        collateral.approve(address(borrowerOperations), type(uint256).max);

        _openTestCDP(
            users[0],
            10000 ether,
            _utils.calculateBorrowAmountFromDebt(
                2e17,
                cdpManager.EBTC_GAS_COMPENSATION(),
                cdpManager.getBorrowingRateWithDecay()
            )
        );
        bytes32 cdpId1 = _openTestCDP(users[0], coll1, debtAmt);

        // get original debt upon CDP open
        CdpState memory _cdpState0 = _getEntireDebtAndColl(cdpId1);

        // accrue some interest before liquidation
        skip(365 days);

        // Price falls
        priceFeedMock.setPrice(price);

        _ensureSystemInvariants();

        // Liquidate cdp1
        bool _availableToLiq1 = _checkAvailableToLiq(cdpId1, price);
        if (_availableToLiq1) {
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
        _ensureDebtAmountValidity(debtAmt);
        vm.assume(partialRatioBps < 10000);
        vm.assume(partialRatioBps > 0);

        uint _curPrice = priceFeedMock.getPrice();

        // in this test, simply use if debtAmt is a multiple of 2 to simulate two scenarios
        bool _icrGtLICR = (debtAmt % 2 == 0) ? true : false;
        uint256 coll1 = _utils.calculateCollAmount(debtAmt, _curPrice, _icrGtLICR ? 297e16 : 206e16);

        vm.prank(users[0]);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        _openTestCDP(
            users[0],
            10000 ether,
            _utils.calculateBorrowAmountFromDebt(
                2e17,
                cdpManager.EBTC_GAS_COMPENSATION(),
                cdpManager.getBorrowingRateWithDecay()
            )
        );
        bytes32 cdpId1 = _openTestCDP(users[0], coll1, debtAmt);

        // get original debt upon CDP open
        CdpState memory _cdpState0 = _getEntireDebtAndColl(cdpId1);

        // accrue some interest before liquidation
        skip(365 days);

        // Price falls
        uint _newPrice = _curPrice / 2;
        priceFeedMock.setPrice(_newPrice);

        _ensureSystemInvariants();

        // Partially Liquidate cdp1
        bool _availableToLiq1 = _checkAvailableToLiq(cdpId1, _newPrice);
        if (_availableToLiq1) {
            CdpState memory _cdpState = _getEntireDebtAndColl(cdpId1);
            assertGt(_cdpState.debt, _cdpState0.debt, "!interest should accrue");

            LocalVar_PartialLiq memory _partialLiq;
            _partialLiq._ratio = _icrGtLICR
                ? cdpManager.LICR()
                : cdpManager.getCurrentICR(cdpId1, _newPrice);
            _partialLiq._repaidDebt = (_cdpState.debt * partialRatioBps) / 10000;
            if (
                (_cdpState.debt - _partialLiq._repaidDebt) <
                ((cdpManager.MIN_NET_DEBT() * _newPrice) / 1e18)
            ) {
                _partialLiq._repaidDebt =
                    _cdpState.debt -
                    ((cdpManager.MIN_NET_DEBT() * _newPrice) / 1e18);
                if (_partialLiq._repaidDebt >= 2) {
                    _partialLiq._repaidDebt = _partialLiq._repaidDebt - 1;
                }
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

    function _checkCdpStatus(bytes32 _cdpId) internal {
        assertTrue(sortedCdps.contains(_cdpId) == _cdpLeftActive[_cdpId]);
        assertTrue(cdpManager.getCdpStatus(_cdpId) == (_cdpLeftActive[_cdpId] ? 1 : 3));
    }

    function _multipleCDPsLiq(uint _n, bytes32[] memory _cdps, address _liquidator) internal {
        uint _debtSystemBefore = cdpManager.getEntireSystemDebt();

        deal(address(eBTCToken), _liquidator, _debtSystemBefore); // sugardaddy liquidator
        uint _debtLiquidatorBefore = eBTCToken.balanceOf(_liquidator);

        vm.prank(_liquidator);
        if (_n > 0) {
            cdpManager.liquidateCdps(_n);
        } else {
            cdpManager.batchLiquidateCdps(_cdps);
        }

        uint _debtLiquidatorAfter = eBTCToken.balanceOf(_liquidator);
        uint _debtSystemAfter = cdpManager.getEntireSystemDebt();

        uint _leftTotalDebt;
        for (uint i = 0; i < cdpManager.getCdpIdsCount(); ++i) {
            _leftTotalDebt = _leftTotalDebt.add(cdpManager.getCdpDebt(cdpManager.CdpIds(i)));
            _cdpLeftActive[cdpManager.CdpIds(i)] = true;
        }
        uint _liquidatedDebt = _debtSystemBefore.sub(_debtSystemAfter);

        assertEq(
            _liquidatedDebt,
            _debtLiquidatorBefore.sub(_debtLiquidatorAfter),
            "!liquidator repayment"
        );
        assertEq(_leftTotalDebt, _debtSystemAfter, "!system debt left");
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
        vm.assume(_curPrice > price * 2);

        uint256 coll1 = _utils.calculateCollAmount(debtAmt1, _curPrice, 297e16);
        uint256 coll2 = _utils.calculateCollAmount(debtAmt2, _curPrice, 297e16);

        vm.prank(users[1]);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        vm.prank(users[2]);
        collateral.approve(address(borrowerOperations), type(uint256).max);

        _openTestCDP(
            users[0],
            10000 ether,
            _utils.calculateBorrowAmountFromDebt(
                2e17,
                cdpManager.EBTC_GAS_COMPENSATION(),
                cdpManager.getBorrowingRateWithDecay()
            )
        );
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
            CdpState memory _cdpState1 = _getEntireDebtAndColl(cdpId1);
            CdpState memory _cdpState2 = _getEntireDebtAndColl(cdpId2);

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
        vm.assume(_curPrice > price * 2);

        uint256 coll1 = _utils.calculateCollAmount(debtAmt1, _curPrice, 297e16);
        uint256 coll2 = _utils.calculateCollAmount(debtAmt2, _curPrice, 297e16);

        vm.prank(users[1]);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        vm.prank(users[2]);
        collateral.approve(address(borrowerOperations), type(uint256).max);

        _openTestCDP(
            users[0],
            10000 ether,
            _utils.calculateBorrowAmountFromDebt(
                2e17,
                cdpManager.EBTC_GAS_COMPENSATION(),
                cdpManager.getBorrowingRateWithDecay()
            )
        );
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
            CdpState memory _cdpState1 = _getEntireDebtAndColl(cdpId1);
            CdpState memory _cdpState2 = _getEntireDebtAndColl(cdpId2);

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
}
