// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {console2 as console} from "forge-std/console2.sol";

import {eBTCBaseInvariants} from "./BaseInvariants.sol";

contract CdpManagerLiquidationTest is eBTCBaseInvariants {
    address payable[] users;

    mapping(bytes32 => bool) private _cdpLeftActive;
    uint private ICR_COMPARE_TOLERANCE = 1000000; //in the scale of 1e18

    ////////////////////////////////////////////////////////////////////////////
    // Liquidation Invariants for ebtc system
    // - cdp_manager_liq1： total collateral snapshot is equal to whatever in active pool
    // - cdp_manager_liq2： total collateral snapshot is equal to sum of individual CDP accounting number
    ////////////////////////////////////////////////////////////////////////////

    function _assert_cdp_manager_invariant_liq1() internal {
        assertEq(
            cdpManager.totalCollateralSnapshot(),
            activePool.getStEthColl(),
            "System Invariant: cdp_manager_liq1"
        );
    }

    function _assert_cdp_manager_invariant_liq2() internal {
        uint _sumColl;
        for (uint i = 0; i < cdpManager.getCdpIdsCount(); ++i) {
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
        uint _ICR = cdpManager.getCurrentICR(_cdpId, _price);
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
        CdpState memory _cdpState0 = _getEntireDebtAndColl(cdpId1);

        // Price falls
        priceFeedMock.setPrice(price);

        _ensureSystemInvariants();

        // Liquidate cdp1
        bool _availableToLiq1 = _checkAvailableToLiq(cdpId1, price);
        if (_availableToLiq1) {
            CdpState memory _cdpState = _getEntireDebtAndColl(cdpId1);
            assertEq(_cdpState.debt, _cdpState0.debt, "!interest should not accrue");

            uint _ICR = cdpManager.getCurrentICR(cdpId1, price);
            uint _expectedLiqDebt = _ICR > cdpManager.LICR()
                ? _cdpState.debt
                : ((_cdpState.coll * price) / cdpManager.LICR());

            deal(address(eBTCToken), users[0], _cdpState.debt); // sugardaddy liquidator
            uint _debtLiquidatorBefore = eBTCToken.balanceOf(users[0]);
            uint _debtSystemBefore = cdpManager.getEntireSystemDebt();
            vm.prank(users[0]);
            cdpManager.liquidate(cdpId1);
            uint _debtLiquidatorAfter = eBTCToken.balanceOf(users[0]);
            uint _debtSystemAfter = cdpManager.getEntireSystemDebt();
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
        CdpState memory _cdpState0 = _getEntireDebtAndColl(cdpId1);

        // Price falls
        uint _newPrice = _curPrice / 2;
        priceFeedMock.setPrice(_newPrice);

        _ensureSystemInvariants();

        // Partially Liquidate cdp1
        bool _availableToLiq1 = _checkAvailableToLiq(cdpId1, _newPrice);
        if (_availableToLiq1) {
            CdpState memory _cdpState = _getEntireDebtAndColl(cdpId1);
            assertEq(_cdpState.debt, _cdpState0.debt, "!interest should not accrue");

            LocalVar_PartialLiq memory _partialLiq;
            _partialLiq._ratio = _icrGtLICR ? cdpManager.MCR() : cdpManager.LICR();
            _partialLiq._repaidDebt = (_cdpState.debt * partialRatioBps) / 10000;
            if (
                (_cdpState.coll - cdpManager.MIN_NET_COLL()) <=
                ((_partialLiq._repaidDebt * _partialLiq._ratio) / _newPrice)
            ) {
                _partialLiq._repaidDebt =
                    ((_cdpState.coll - cdpManager.MIN_NET_COLL() * 3) * _newPrice) /
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
            bool _fully = _partialLiq._collToLiquidator >= _cdpState.coll;
            if (_fully) {
                _partialLiq._collToLiquidator = _cdpState.coll;
                _expectedLiqDebt = (_partialLiq._collToLiquidator * _newPrice) / cdpManager.LICR();
            }

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

        // calc debt in system by summing up all CDPs debt
        uint _leftTotalDebt;
        for (uint i = 0; i < cdpManager.getCdpIdsCount(); ++i) {
            (uint _cdpDebt, , ) = cdpManager.getEntireDebtAndColl(cdpManager.CdpIds(i));
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
        console.log("activePool.getEBTCDebt()", activePool.getEBTCDebt());
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

    /// @dev Test a sequence of liquidations where RM is exited during the sequence
    /// @dev All subsequent CDPs in the sequence that are only liquidatable in RM should be skipped
    function test_SequenceLiqRecoveryModeSwitch() public {
        (bytes32[] memory cdpIds, uint _newPrice) = _sequenceRecoveryModeSwitchSetup();

        // ensure we are in RM now
        uint _currentTCR = cdpManager.getTCR(_newPrice);
        assertTrue(_currentTCR < cdpManager.CCR());

        // prepare sequence liquidation
        address _liquidator = users[users.length - 1];
        deal(address(eBTCToken), _liquidator, cdpManager.getEntireSystemDebt()); // sugardaddy liquidator
        // FIXME _waitUntilRMColldown();

        uint _liquidatorBalBefore = collateral.balanceOf(_liquidator);
        uint _expectedReward = cdpManager.getCdpColl(cdpIds[0]) +
            cdpManager.getCdpLiquidatorRewardShares(cdpIds[0]) +
            ((cdpManager.getCdpDebt(cdpIds[1]) * (cdpManager.getCurrentICR(cdpIds[1], _newPrice))) /
                _newPrice) +
            cdpManager.getCdpLiquidatorRewardShares(cdpIds[1]);

        vm.prank(_liquidator);
        cdpManager.liquidateCdps(4);
        assertTrue(sortedCdps.contains(cdpIds[0]) == false);
        assertTrue(sortedCdps.contains(cdpIds[1]) == false);
        assertTrue(sortedCdps.contains(cdpIds[2]) == true);
        assertTrue(sortedCdps.contains(cdpIds[3]) == true);

        // ensure RM is exited
        assertTrue(cdpManager.getTCR(_newPrice) > cdpManager.CCR());
        uint _liquidatorBalAfter = collateral.balanceOf(_liquidator);
        assertEq(
            _liquidatorBalAfter,
            _liquidatorBalBefore + _expectedReward,
            "Liquidator balance mismatch after sequence liquidation in RM!!!"
        );
    }

    /// @dev Test a batch of liquidations where RM is exited during the batch
    /// @dev All subsequent CDPs in the batch that are only liquidatable in RM should be skipped
    function test_BatchLiqRecoveryModeSwitch() public {
        (bytes32[] memory cdpIds, uint _newPrice) = _sequenceRecoveryModeSwitchSetup();

        // ensure we are in RM now
        uint _currentTCR = cdpManager.getTCR(_newPrice);
        assertTrue(_currentTCR < cdpManager.CCR());

        // prepare batch liquidation
        address _liquidator = users[users.length - 1];
        deal(address(eBTCToken), _liquidator, cdpManager.getEntireSystemDebt()); // sugardaddy liquidator
        // FIXME _waitUntilRMColldown();

        uint _liquidatorBalBefore = collateral.balanceOf(_liquidator);
        uint _expectedReward = cdpManager.getCdpColl(cdpIds[0]) +
            cdpManager.getCdpLiquidatorRewardShares(cdpIds[0]) +
            ((cdpManager.getCdpDebt(cdpIds[1]) * (cdpManager.getCurrentICR(cdpIds[1], _newPrice))) /
                _newPrice) +
            cdpManager.getCdpLiquidatorRewardShares(cdpIds[1]);

        vm.prank(_liquidator);
        cdpManager.batchLiquidateCdps(cdpIds);
        assertTrue(sortedCdps.contains(cdpIds[0]) == false);
        assertTrue(sortedCdps.contains(cdpIds[1]) == false);
        assertTrue(sortedCdps.contains(cdpIds[2]) == true);
        assertTrue(sortedCdps.contains(cdpIds[3]) == true);

        // ensure RM is exited
        assertTrue(cdpManager.getTCR(_newPrice) > cdpManager.CCR());
        uint _liquidatorBalAfter = collateral.balanceOf(_liquidator);
        assertEq(
            _liquidatorBalAfter,
            _liquidatorBalBefore + _expectedReward,
            "Liquidator balance mismatch after sequence liquidation in RM!!!"
        );
    }

    /// @dev Cdp ICR below 100%
    /// @dev premium = 3%
    /// @dev bad debt redistribution
    function test_LiqPremiumWithCdpUndercollaterlized() public {
        // ensure there is more than one CDP
        _singleCdpSetup(users[0], 126e16);
        (address user, bytes32 userCdpid) = _singleCdpSetup(users[0], 130e16);

        // price drop
        uint _originalPrice = priceFeedMock.fetchPrice();
        uint _newPrice = (_originalPrice * 1e18) / 130e16;
        priceFeedMock.setPrice(_newPrice);
        _utils.assertApproximateEq(
            cdpManager.getCurrentICR(userCdpid, _newPrice),
            1e18,
            ICR_COMPARE_TOLERANCE
        );

        // prepare liquidation
        address _liquidator = users[users.length - 1];
        deal(address(eBTCToken), _liquidator, cdpManager.getCdpDebt(userCdpid)); // sugardaddy liquidator

        uint _liquidatorBalBefore = collateral.balanceOf(_liquidator);
        uint _expectedReward = cdpManager.getCdpColl(userCdpid) +
            cdpManager.getCdpLiquidatorRewardShares(userCdpid);

        vm.prank(_liquidator);
        cdpManager.liquidate(userCdpid);
        assertTrue(sortedCdps.contains(userCdpid) == false);
        uint _liquidatorBalAfter = collateral.balanceOf(_liquidator);
        assertEq(
            _liquidatorBalAfter,
            _liquidatorBalBefore + _expectedReward,
            "Liquidator balance mismatch after Deeply-Under-Collaterlized CDP liquidation!!!"
        );
    }

    /// @dev Cdp ICR below 3%
    /// @dev premium = 3%
    /// @dev bad debt redistribution
    function test_LiqPremiumWithCdpDeeplyUndercollateralized_BelowMinPremium() public {
        // ensure there is more than one CDP
        _singleCdpSetup(users[0], 126e16);
        (address user, bytes32 userCdpid) = _singleCdpSetup(users[0], 130e16);

        // price drop
        uint _originalPrice = priceFeedMock.fetchPrice();
        uint _newPrice = (_originalPrice * 3e16) / 130e16;
        priceFeedMock.setPrice(_newPrice);
        _utils.assertApproximateEq(
            cdpManager.getCurrentICR(userCdpid, _newPrice),
            3e16,
            ICR_COMPARE_TOLERANCE
        );

        // prepare liquidation
        address _liquidator = users[users.length - 1];
        deal(address(eBTCToken), _liquidator, cdpManager.getCdpDebt(userCdpid)); // sugardaddy liquidator

        uint _liquidatorBalBefore = collateral.balanceOf(_liquidator);
        uint _expectedReward = cdpManager.getCdpColl(userCdpid) +
            cdpManager.getCdpLiquidatorRewardShares(userCdpid);

        vm.prank(_liquidator);
        cdpManager.liquidate(userCdpid);
        assertTrue(sortedCdps.contains(userCdpid) == false);
        uint _liquidatorBalAfter = collateral.balanceOf(_liquidator);
        assertEq(
            _liquidatorBalAfter,
            _liquidatorBalBefore + _expectedReward,
            "Liquidator balance mismatch after Under-Collaterlized CDP liquidation!!!"
        );
    }

    /// @dev Cdp ICR between 110% (MCR) and 100%
    /// @dev premium = ICR-100%
    function test_LiqPremiumWithCdpOvercollateralized_BelowMaxPremium(uint ICR) public {
        vm.assume(ICR > cdpManager.MCR());
        vm.assume(ICR <= cdpManager.CCR());

        // ensure there is more than one CDP
        _singleCdpSetup(users[0], 156e16);
        (address user, bytes32 userCdpid) = _singleCdpSetup(users[0], ICR);

        // price drop
        uint _originalPrice = priceFeedMock.fetchPrice();
        uint _newPrice = (_originalPrice * 105e16) / ICR;
        priceFeedMock.setPrice(_newPrice);
        uint _currentICR = cdpManager.getCurrentICR(userCdpid, _newPrice);
        _utils.assertApproximateEq(_currentICR, 105e16, ICR_COMPARE_TOLERANCE);
        assertTrue(_currentICR > 103e16);

        // prepare liquidation
        address _liquidator = users[users.length - 1];
        deal(address(eBTCToken), _liquidator, cdpManager.getCdpDebt(userCdpid)); // sugardaddy liquidator

        uint _liquidatorBalBefore = collateral.balanceOf(_liquidator);
        uint _expectedReward = ((cdpManager.getCdpDebt(userCdpid) * _currentICR) / _newPrice) +
            cdpManager.getCdpLiquidatorRewardShares(userCdpid);

        vm.prank(_liquidator);
        cdpManager.liquidate(userCdpid);
        uint _liquidatorBalAfter = collateral.balanceOf(_liquidator);
        assertTrue(sortedCdps.contains(userCdpid) == false);
        assertEq(
            _liquidatorBalAfter,
            _liquidatorBalBefore + _expectedReward,
            "Liquidator balance mismatch after Over-Collaterlized CDP liquidation!!!"
        );
    }

    /// @dev Cdp ICR between 125% (CCR) and 110% (MCR)
    /// @dev premium = 110%
    function test_LiqPremiumWithCdpOvercollateralized_AboveMaxPremium(uint ICR) public {
        vm.assume(ICR >= 111e16);
        vm.assume(ICR <= 120e16);

        // ensure there is more than one CDP
        _singleCdpSetup(users[0], 170e16);
        _singleCdpSetup(users[0], ICR);
        (, bytes32 userCdpid) = _singleCdpSetup(users[0], ICR);

        // price drop to trigger RM
        uint _originalPrice = priceFeedMock.fetchPrice();
        uint _newPrice = (_originalPrice * 1102e15) / ICR;
        priceFeedMock.setPrice(_newPrice);
        uint _currentICR = cdpManager.getCurrentICR(userCdpid, _newPrice);
        _utils.assertApproximateEq(_currentICR, 1102e15, ICR_COMPARE_TOLERANCE);
        uint _currentTCR = cdpManager.getTCR(_newPrice);
        assertTrue(_currentTCR < cdpManager.CCR());
        assertTrue(_currentICR < _currentTCR);

        // prepare liquidation
        address _liquidator = users[users.length - 1];
        deal(address(eBTCToken), _liquidator, cdpManager.getCdpDebt(userCdpid)); // sugardaddy liquidator
        // FIXME _waitUntilRMColldown();

        uint _liquidatorBalBefore = collateral.balanceOf(_liquidator);
        uint _expectedReward = ((cdpManager.getCdpDebt(userCdpid) * cdpManager.MCR()) / _newPrice) +
            cdpManager.getCdpLiquidatorRewardShares(userCdpid);

        vm.prank(_liquidator);
        cdpManager.liquidate(userCdpid);
        uint _liquidatorBalAfter = collateral.balanceOf(_liquidator);
        assertTrue(sortedCdps.contains(userCdpid) == false);
        assertEq(
            _liquidatorBalAfter,
            _liquidatorBalBefore + _expectedReward,
            "Liquidator balance mismatch after Over-Collaterlized CDP liquidation in RM!!!"
        );
    }

    /// @dev open Cdp then with price change to a fuzzed _liqICR
    /// @dev According to the specific range for given _liqICR
    /// @dev full liquidation premium should match expected calculation:
    /// @dev Cdps <3% ICR: all Coll as incentive, all debt redistributed
    /// @dev Cdps [3% < ICR < 100%]: 3% as incentive, all remaining debt redistributed
    /// @dev Cdps [100% <= ICR < 110%]: min(3%, 110%-ICR) as incentive, all remaining debt redistributed if below 103%
    /// @dev Cdps [110% <= ICR < TCR]: 10% as Incentive, no debt redistribution
    function test_SingleLiqPremiumFuzz(uint _liqICR) public {
        uint _goodICR = 135e16;
        uint _belowCCR = 124e16;

        // ensure liquidation ICR falls in reasonable range
        vm.assume(_liqICR >= 1e15);
        vm.assume(_liqICR < _belowCCR);

        // ensure price change would give expected fuzz ICR
        uint _originalPrice = priceFeedMock.fetchPrice();
        uint _newPrice = (_originalPrice * _liqICR) / _goodICR;
        (address user, bytes32 userCdpid) = _singleCdpSetup(users[0], _goodICR);
        bool _noNeedRM = _liqICR < cdpManager.MCR();

        // ensure more than one CDP
        uint _userColl = cdpManager.getCdpColl(userCdpid);
        uint _userDebt = cdpManager.getCdpDebt(userCdpid);
        if (_noNeedRM) {
            _singleCdpSetup(users[0], 8000e16);
        } else {
            uint _debt = ((_userColl * 2 * _newPrice) / _belowCCR) - _userDebt;
            _openTestCDP(users[0], _userColl + cdpManager.LIQUIDATOR_REWARD(), _debt);
        }

        // price drop
        priceFeedMock.setPrice(_newPrice);
        _utils.assertApproximateEq(
            cdpManager.getCurrentICR(userCdpid, _newPrice),
            _liqICR,
            ICR_COMPARE_TOLERANCE
        );

        if (!_noNeedRM) {
            assertTrue(cdpManager.getTCR(_newPrice) < cdpManager.CCR());
            // FIXME _waitUntilRMColldown();
        }

        // prepare liquidation
        address _liquidator = users[users.length - 1];
        deal(address(eBTCToken), _liquidator, cdpManager.getCdpDebt(userCdpid)); // sugardaddy liquidator

        uint _liquidatorBalBefore = collateral.balanceOf(_liquidator);
        uint _liqStipend = cdpManager.getCdpLiquidatorRewardShares(userCdpid);
        uint _maxReward = _userColl + _liqStipend;
        uint _expectedReward;
        if (_noNeedRM) {
            _expectedReward = _maxReward;
        } else {
            _expectedReward = _liqStipend + ((_userDebt * cdpManager.MCR()) / _newPrice);
            if (_expectedReward > _maxReward) {
                _expectedReward = _maxReward;
            }
        }

        vm.prank(_liquidator);
        if (_liqICR % 2 == 0) {
            cdpManager.liquidate(userCdpid);
        } else {
            bytes32[] memory _cids = new bytes32[](1);
            _cids[0] = userCdpid;
            cdpManager.batchLiquidateCdps(_cids);
        }
        assertTrue(sortedCdps.contains(userCdpid) == false);
        uint _liquidatorBalAfter = collateral.balanceOf(_liquidator);
        assertEq(
            _liquidatorBalAfter,
            _liquidatorBalBefore + _expectedReward,
            "Liquidator balance mismatch after fuzz-premium single CDP liquidation!!!"
        );
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

    function _singleCdpSetup(address _usr, uint _icr) internal returns (address, bytes32) {
        uint _price = priceFeedMock.fetchPrice();
        uint _coll = cdpManager.MIN_NET_COLL() * 2;
        uint _debt = (_coll * _price) / _icr;
        bytes32 _cdpId = _openTestCDP(_usr, _coll + cdpManager.LIQUIDATOR_REWARD(), _debt);
        uint _cdpICR = cdpManager.getCurrentICR(_cdpId, _price);
        _utils.assertApproximateEq(_icr, _cdpICR, ICR_COMPARE_TOLERANCE); // in the scale of 1e18
        return (_usr, _cdpId);
    }

    function _sequenceRecoveryModeSwitchSetup() internal returns (bytes32[] memory, uint) {
        address user = users[0];
        bytes32[] memory cdpIds = new bytes32[](4);

        /** 
            open a sequence of Cdps. once we enter recovery mode, they will have the following status:

            [1] < 100%
            [2] < MCR
            ...
			
            once a few CDPs are liquidated, the system should _switch_ to normal mode. the rest CDP should therefore not be liquidated from the sequence
        */
        uint _price = priceFeedMock.fetchPrice();

        // [1] 190%
        (, cdpIds[0]) = _singleCdpSetup(user, 190e16);
        _utils.assertApproximateEq(
            cdpManager.getCurrentICR(cdpIds[0], _price),
            190e16,
            ICR_COMPARE_TOLERANCE
        );

        // [2] 210%
        (, cdpIds[1]) = _singleCdpSetup(user, 210e16);
        _utils.assertApproximateEq(
            cdpManager.getCurrentICR(cdpIds[1], _price),
            210e16,
            ICR_COMPARE_TOLERANCE
        );

        // [3] 270%
        (, cdpIds[2]) = _singleCdpSetup(user, 270e16);
        _utils.assertApproximateEq(
            cdpManager.getCurrentICR(cdpIds[2], _price),
            270e16,
            ICR_COMPARE_TOLERANCE
        );

        // [4] 290%
        (, cdpIds[3]) = _singleCdpSetup(user, 290e16);
        _utils.assertApproximateEq(
            cdpManager.getCurrentICR(cdpIds[3], _price),
            290e16,
            ICR_COMPARE_TOLERANCE
        );

        // price drop to half
        uint _newPrice = _price / 2;
        priceFeedMock.setPrice(_newPrice);

        return (cdpIds, _newPrice);
    }
}
