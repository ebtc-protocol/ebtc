// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {console2 as console} from "forge-std/console2.sol";

import {eBTCBaseInvariants} from "./BaseInvariants.sol";

contract CdpManagerLiquidationTest is eBTCBaseInvariants {
    address payable[] users;

    mapping(bytes32 => bool) private _cdpLeftActive;
    uint256 private ICR_COMPARE_TOLERANCE = 1000000; //in the scale of 1e18

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
        uint256 _sumColl;
        bytes32[] memory cdpIds = hintHelpers.sortedCdpsToArray();
        for (uint256 i = 0; i < cdpManager.getActiveCdpsCount(); ++i) {
            bytes32 _cdpId = cdpIds[i];
            (, uint256 _coll, , , ) = cdpManager.Cdps(_cdpId);
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

    function _checkAvailableToLiq(bytes32 _cdpId, uint256 _price) internal view returns (bool) {
        uint256 _TCR = cdpManager.getCachedTCR(_price);
        uint256 _ICR = cdpManager.getCachedICR(_cdpId, _price);
        bool _recoveryMode = _TCR < cdpManager.CCR();
        return (_ICR < cdpManager.MCR() || (_recoveryMode && _ICR < _TCR));
    }

    // Test single CDP liquidation with price fluctuation
    function testLiquidateSingleCDP(uint256 price, uint256 debtAmt) public {
        debtAmt = bound(debtAmt, 1e18, 10000e18);

        uint256 _curPrice = priceFeedMock.getPrice();
        price = bound(price, _curPrice / 10000, _curPrice / 2);

        uint256 coll1 = _utils.calculateCollAmount(debtAmt, _curPrice, 297e16);
        coll1 = bound(coll1, 22e17, type(uint256).max);

        vm.prank(users[0]);
        collateral.approve(address(borrowerOperations), type(uint256).max);

        _openTestCDP(users[0], 10000 ether, 2e17);
        bytes32 cdpId1 = _openTestCDP(users[0], coll1, debtAmt);

        // get original debt upon CDP open
        CdpState memory _cdpState0 = _getSyncedDebtAndCollShares(cdpId1);

        // Price falls
        priceFeedMock.setPrice(price);

        _ensureSystemInvariants();

        // Liquidate cdp1
        bool _availableToLiq1 = _checkAvailableToLiq(cdpId1, price);
        if (_availableToLiq1) {
            CdpState memory _cdpState = _getSyncedDebtAndCollShares(cdpId1);
            assertEq(_cdpState.debt, _cdpState0.debt, "!interest should not accrue");

            uint256 _ICR = cdpManager.getCachedICR(cdpId1, price);
            uint256 _expectedLiqDebt = _ICR > cdpManager.LICR()
                ? _cdpState.debt
                : ((_cdpState.coll * price) / cdpManager.LICR());

            deal(address(eBTCToken), users[0], _cdpState.debt); // sugardaddy liquidator
            uint256 _debtLiquidatorBefore = eBTCToken.balanceOf(users[0]);
            uint256 _debtSystemBefore = cdpManager.getSystemDebt();

            _waitUntilRMColldown();

            vm.prank(users[0]);
            cdpManager.liquidate(cdpId1);
            uint256 _debtLiquidatorAfter = eBTCToken.balanceOf(users[0]);
            uint256 _debtSystemAfter = cdpManager.getSystemDebt();
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
        uint256 _ratio;
        uint256 _repaidDebt;
        uint256 _collToLiquidator;
    }

    // Test single CDP partial liquidation with variable ratio for partial repayment:
    // - when its ICR is higher than LICR then the collateral to liquidator is (repaidDebt * LICR) / price
    // - when its ICR is lower than LICR then the collateral to liquidator is (repaidDebt * ICR) / price
    function testPartiallyLiquidateSingleCDP(uint256 debtAmt, uint256 partialRatioBps) public {
        debtAmt = bound(debtAmt, 1e18, 10000e18);
        partialRatioBps = bound(partialRatioBps, 1, 10000 - 1);

        uint256 _curPrice = priceFeedMock.getPrice();

        // in this test, simply use if debtAmt is a multiple of 2 to simulate two scenarios
        bool _icrGtLICR = (debtAmt % 2 == 0) ? true : false;
        uint256 coll1 = _utils.calculateCollAmount(debtAmt, _curPrice, _icrGtLICR ? 249e16 : 205e16);

        vm.prank(users[0]);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        _openTestCDP(users[0], 10000 ether, 2e17);
        bytes32 cdpId1 = _openTestCDP(users[0], coll1, debtAmt);

        // get original debt upon CDP open
        CdpState memory _cdpState0 = _getSyncedDebtAndCollShares(cdpId1);

        // Price falls
        uint256 _newPrice = _curPrice / 2;
        priceFeedMock.setPrice(_newPrice);

        _ensureSystemInvariants();

        // Partially Liquidate cdp1
        bool _availableToLiq1 = _checkAvailableToLiq(cdpId1, _newPrice);
        if (_availableToLiq1) {
            CdpState memory _cdpState = _getSyncedDebtAndCollShares(cdpId1);
            assertEq(_cdpState.debt, _cdpState0.debt, "!interest should not accrue");

            LocalVar_PartialLiq memory _partialLiq;
            _partialLiq._ratio = _icrGtLICR ? cdpManager.MCR() : cdpManager.LICR();
            _partialLiq._repaidDebt = (_cdpState.debt * partialRatioBps) / 10000;
            if (
                (_cdpState.coll - cdpManager.MIN_NET_STETH_BALANCE()) <=
                ((_partialLiq._repaidDebt * _partialLiq._ratio) / _newPrice)
            ) {
                _partialLiq._repaidDebt =
                    ((_cdpState.coll - cdpManager.MIN_NET_STETH_BALANCE() * 3) * _newPrice) /
                    _partialLiq._ratio;
                if (_partialLiq._repaidDebt >= 2) {
                    _partialLiq._repaidDebt = _partialLiq._repaidDebt - 1;
                }
            }
            _partialLiq._collToLiquidator =
                (_partialLiq._repaidDebt * _partialLiq._ratio) /
                _newPrice;

            // fully liquidate instead
            uint256 _expectedLiqDebt = _partialLiq._repaidDebt;
            bool _fully = _partialLiq._collToLiquidator >= _cdpState.coll;
            if (_fully) {
                _partialLiq._collToLiquidator = _cdpState.coll;
                _expectedLiqDebt = (_partialLiq._collToLiquidator * _newPrice) / cdpManager.LICR();
            }

            deal(address(eBTCToken), users[0], _cdpState.debt); // sugardaddy liquidator
            {
                uint256 _debtLiquidatorBefore = eBTCToken.balanceOf(users[0]);
                uint256 _debtSystemBefore = cdpManager.getSystemDebt();
                uint256 _collSystemBefore = cdpManager.getSystemCollShares();
                _waitUntilRMColldown();
                vm.prank(users[0]);

                cdpManager.partiallyLiquidate(cdpId1, _partialLiq._repaidDebt, cdpId1, cdpId1);
                uint256 _debtLiquidatorAfter = eBTCToken.balanceOf(users[0]);
                uint256 _debtSystemAfter = cdpManager.getSystemDebt();
                uint256 _collSystemAfter = cdpManager.getSystemCollShares();
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

    function _multipleCDPsLiq(uint256 _n, bytes32[] memory _cdps, address _liquidator) internal {
        /// entire systme debt = activePool
        uint256 _debtSystemBefore = cdpManager.getSystemDebt();

        deal(address(eBTCToken), _liquidator, _debtSystemBefore); // sugardaddy liquidator
        uint256 _debtLiquidatorBefore = eBTCToken.balanceOf(_liquidator);

        _waitUntilRMColldown();

        vm.startPrank(_liquidator);
        if (_n > 0) {
            console.log("liquidateCdps(n)");
            console.log("n:", _n);
            console.log("cdps:", _cdps.length);
            _printCdpArray(_cdps);
            _liquidateCdps(_n);
        } else {
            console.log("batchLiquidateCdps(_cdps)");
            console.log(_n);
            console.log(_cdps.length);
            _printCdpArray(_cdps);
            cdpManager.batchLiquidateCdps(_cdps);
        }
        vm.stopPrank();

        uint256 _debtLiquidatorAfter = eBTCToken.balanceOf(_liquidator);
        uint256 _debtSystemAfter = cdpManager.getSystemDebt();

        // calc debt in system by summing up all CDPs debt
        uint256 _leftTotalDebt;
        bytes32[] memory cdpIds = hintHelpers.sortedCdpsToArray();
        for (uint256 i = 0; i < cdpManager.getActiveCdpsCount(); ++i) {
            (uint256 _cdpDebt, ) = cdpManager.getSyncedDebtAndCollShares(cdpIds[i]);
            _leftTotalDebt = (_leftTotalDebt + _cdpDebt);
            _cdpLeftActive[cdpIds[i]] = true;
        }

        console.log("_leftTotalDebt from system", _leftTotalDebt);

        uint256 _liquidatedDebt = (_debtSystemBefore - _debtSystemAfter);

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
        debtAmt1 = bound(debtAmt1, 1e18, 10000e18);
        debtAmt2 = bound(debtAmt2, 1e18, 10000e18);

        uint256 _curPrice = priceFeedMock.getPrice();
        price = bound(price, _curPrice / 10000, _curPrice / 2);

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
            CdpState memory _cdpState1 = _getSyncedDebtAndCollShares(cdpId1);
            CdpState memory _cdpState2 = _getSyncedDebtAndCollShares(cdpId2);

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
        debtAmt1 = bound(debtAmt1, 1e18, 10000e18);
        debtAmt2 = bound(debtAmt2, 1e18, 10000e18);

        uint256 _curPrice = priceFeedMock.getPrice();
        price = bound(price, _curPrice / 10000, _curPrice / 2);

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
            CdpState memory _cdpState1 = _getSyncedDebtAndCollShares(cdpId1);
            CdpState memory _cdpState2 = _getSyncedDebtAndCollShares(cdpId2);

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
        (bytes32[] memory cdpIds, uint256 _newPrice) = _sequenceRecoveryModeSwitchSetup();

        // ensure we are in RM now
        uint256 _currentTCR = cdpManager.getCachedTCR(_newPrice);
        assertTrue(_currentTCR < cdpManager.CCR());

        // prepare sequence liquidation
        address _liquidator = users[users.length - 1];
        deal(address(eBTCToken), _liquidator, cdpManager.getSystemDebt()); // sugardaddy liquidator
        _waitUntilRMColldown();

        uint256 _liquidatorBalBefore = collateral.balanceOf(_liquidator);
        uint256 _expectedReward = cdpManager.getCdpCollShares(cdpIds[0]) +
            cdpManager.getCdpLiquidatorRewardShares(cdpIds[0]) +
            ((cdpManager.getCdpDebt(cdpIds[1]) * (cdpManager.getCachedICR(cdpIds[1], _newPrice))) /
                _newPrice) +
            cdpManager.getCdpLiquidatorRewardShares(cdpIds[1]);

        vm.startPrank(_liquidator);
        _liquidateCdps(4);
        assertTrue(sortedCdps.contains(cdpIds[0]) == false);
        assertTrue(sortedCdps.contains(cdpIds[1]) == false);
        assertTrue(sortedCdps.contains(cdpIds[2]) == true);
        assertTrue(sortedCdps.contains(cdpIds[3]) == true);
        vm.stopPrank();

        // ensure RM is exited
        assertTrue(cdpManager.getCachedTCR(_newPrice) > cdpManager.CCR());
        uint256 _liquidatorBalAfter = collateral.balanceOf(_liquidator);
        _utils.assertApproximateEq(
            _liquidatorBalAfter,
            _liquidatorBalBefore + _expectedReward,
            ICR_COMPARE_TOLERANCE
        );
    }

    /// @dev Test a batch of liquidations where RM is exited during the batch
    /// @dev All subsequent CDPs in the batch that are only liquidatable in RM should be skipped
    function test_BatchLiqRecoveryModeSwitch() public {
        (bytes32[] memory cdpIds, uint256 _newPrice) = _sequenceRecoveryModeSwitchSetup();

        // ensure we are in RM now
        uint256 _currentTCR = cdpManager.getCachedTCR(_newPrice);
        assertTrue(_currentTCR < cdpManager.CCR());

        // prepare batch liquidation
        address _liquidator = users[users.length - 1];
        deal(address(eBTCToken), _liquidator, cdpManager.getSystemDebt()); // sugardaddy liquidator
        _waitUntilRMColldown();

        uint256 _liquidatorBalBefore = collateral.balanceOf(_liquidator);
        uint256 _expectedReward = cdpManager.getCdpCollShares(cdpIds[0]) +
            cdpManager.getCdpLiquidatorRewardShares(cdpIds[0]) +
            ((cdpManager.getCdpDebt(cdpIds[1]) * (cdpManager.getCachedICR(cdpIds[1], _newPrice))) /
                _newPrice) +
            cdpManager.getCdpLiquidatorRewardShares(cdpIds[1]);

        vm.prank(_liquidator);
        cdpManager.batchLiquidateCdps(cdpIds);
        assertTrue(sortedCdps.contains(cdpIds[0]) == false);
        assertTrue(sortedCdps.contains(cdpIds[1]) == false);
        assertTrue(sortedCdps.contains(cdpIds[2]) == true);
        assertTrue(sortedCdps.contains(cdpIds[3]) == true);

        // ensure RM is exited
        assertTrue(cdpManager.getCachedTCR(_newPrice) > cdpManager.CCR());
        uint256 _liquidatorBalAfter = collateral.balanceOf(_liquidator);
        _utils.assertApproximateEq(
            _liquidatorBalAfter,
            _liquidatorBalBefore + _expectedReward,
            ICR_COMPARE_TOLERANCE
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
        uint256 _originalPrice = priceFeedMock.fetchPrice();
        uint256 _newPrice = (_originalPrice * 1e18) / 130e16;
        priceFeedMock.setPrice(_newPrice);
        _utils.assertApproximateEq(
            cdpManager.getCachedICR(userCdpid, _newPrice),
            1e18,
            ICR_COMPARE_TOLERANCE
        );

        // prepare liquidation
        address _liquidator = users[users.length - 1];
        deal(address(eBTCToken), _liquidator, cdpManager.getCdpDebt(userCdpid)); // sugardaddy liquidator

        uint256 _liquidatorBalBefore = collateral.balanceOf(_liquidator);
        uint256 _expectedReward = cdpManager.getCdpCollShares(userCdpid) +
            cdpManager.getCdpLiquidatorRewardShares(userCdpid);

        vm.prank(_liquidator);
        cdpManager.liquidate(userCdpid);
        assertTrue(sortedCdps.contains(userCdpid) == false);
        uint256 _liquidatorBalAfter = collateral.balanceOf(_liquidator);
        _utils.assertApproximateEq(
            _liquidatorBalAfter,
            _liquidatorBalBefore + _expectedReward,
            ICR_COMPARE_TOLERANCE
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
        uint256 _originalPrice = priceFeedMock.fetchPrice();
        uint256 _newPrice = (_originalPrice * 3e16) / 130e16;
        priceFeedMock.setPrice(_newPrice);
        _utils.assertApproximateEq(
            cdpManager.getCachedICR(userCdpid, _newPrice),
            3e16,
            ICR_COMPARE_TOLERANCE
        );

        // prepare liquidation
        address _liquidator = users[users.length - 1];
        deal(address(eBTCToken), _liquidator, cdpManager.getCdpDebt(userCdpid)); // sugardaddy liquidator

        uint256 _liquidatorBalBefore = collateral.balanceOf(_liquidator);
        uint256 _expectedReward = cdpManager.getCdpCollShares(userCdpid) +
            cdpManager.getCdpLiquidatorRewardShares(userCdpid);

        vm.prank(_liquidator);
        cdpManager.liquidate(userCdpid);
        assertTrue(sortedCdps.contains(userCdpid) == false);
        uint256 _liquidatorBalAfter = collateral.balanceOf(_liquidator);
        _utils.assertApproximateEq(
            _liquidatorBalAfter,
            _liquidatorBalBefore + _expectedReward,
            ICR_COMPARE_TOLERANCE
        );
    }

    /// @dev Cdp ICR between 110% (MCR) and 100%
    /// @dev premium = ICR-100%
    function test_LiqPremiumWithCdpOvercollateralized_BelowMaxPremium(uint256 ICR) public {
        ICR = bound(ICR, cdpManager.MCR() + 1, cdpManager.CCR());

        // ensure there is more than one CDP
        _singleCdpSetup(users[0], 156e16);
        (address user, bytes32 userCdpid) = _singleCdpSetup(users[0], ICR);

        // price drop
        uint256 _originalPrice = priceFeedMock.fetchPrice();
        uint256 _newPrice = (_originalPrice * 105e16) / ICR;
        priceFeedMock.setPrice(_newPrice);
        uint256 _currentICR = cdpManager.getCachedICR(userCdpid, _newPrice);
        _utils.assertApproximateEq(_currentICR, 105e16, ICR_COMPARE_TOLERANCE);
        assertTrue(_currentICR > 103e16);

        // prepare liquidation
        address _liquidator = users[users.length - 1];
        deal(address(eBTCToken), _liquidator, cdpManager.getCdpDebt(userCdpid)); // sugardaddy liquidator

        uint256 _liquidatorBalBefore = collateral.balanceOf(_liquidator);
        uint256 _expectedReward = ((cdpManager.getCdpDebt(userCdpid) * _currentICR) / _newPrice) +
            cdpManager.getCdpLiquidatorRewardShares(userCdpid);

        vm.prank(_liquidator);
        cdpManager.liquidate(userCdpid);
        uint256 _liquidatorBalAfter = collateral.balanceOf(_liquidator);
        assertTrue(sortedCdps.contains(userCdpid) == false);
        _utils.assertApproximateEq(
            _liquidatorBalAfter,
            _liquidatorBalBefore + _expectedReward,
            ICR_COMPARE_TOLERANCE
        );
    }

    /// @dev Cdp ICR between 125% (CCR) and 110% (MCR)
    /// @dev premium = 110%
    function test_LiqPremiumWithCdpOvercollateralized_AboveMaxPremium(uint256 ICR) public {
        ICR = bound(ICR, 111e16, 120e16);

        // ensure there is more than one CDP
        _singleCdpSetup(users[0], 170e16);
        _singleCdpSetup(users[0], ICR);
        (, bytes32 userCdpid) = _singleCdpSetup(users[0], ICR);

        // price drop to trigger RM
        uint256 _originalPrice = priceFeedMock.fetchPrice();
        uint256 _newPrice = (_originalPrice * 1102e15) / ICR;
        priceFeedMock.setPrice(_newPrice);
        uint256 _currentICR = cdpManager.getCachedICR(userCdpid, _newPrice);
        _utils.assertApproximateEq(_currentICR, 1102e15, ICR_COMPARE_TOLERANCE);
        uint256 _currentTCR = cdpManager.getCachedTCR(_newPrice);
        assertTrue(_currentTCR < cdpManager.CCR());
        assertTrue(_currentICR < _currentTCR);

        // prepare liquidation
        address _liquidator = users[users.length - 1];
        deal(address(eBTCToken), _liquidator, cdpManager.getCdpDebt(userCdpid)); // sugardaddy liquidator
        _waitUntilRMColldown();

        uint256 _liquidatorBalBefore = collateral.balanceOf(_liquidator);
        uint256 _expectedReward = ((cdpManager.getCdpDebt(userCdpid) * cdpManager.MCR()) /
            _newPrice) + cdpManager.getCdpLiquidatorRewardShares(userCdpid);

        vm.prank(_liquidator);
        cdpManager.liquidate(userCdpid);
        uint256 _liquidatorBalAfter = collateral.balanceOf(_liquidator);
        assertTrue(sortedCdps.contains(userCdpid) == false);
        _utils.assertApproximateEq(
            _liquidatorBalAfter,
            _liquidatorBalBefore + _expectedReward,
            ICR_COMPARE_TOLERANCE
        );
    }

    // == FSM TEST ==//
    // Can NEVER liquidate if CDP above CCR
    // NOTE: Capped ICR to u64 because infinitely high values are not meaningful
    function testCanNeverLiquidateIfCdpAboveCCR(uint64 victimICR) public {
        // Calculate the TCR that they will have after the price decrease
        // Not the one they have on open
        // The one on open is a consequence

        vm.assume(victimICR > cdpManager.CCR());
        uint256 currentPrice = priceFeedMock.fetchPrice();
        uint256 endICR = 1.20e18; // In RM

        // We always decrease price by 10%
        uint256 newPrice = (currentPrice * 90) / 100;

        // Find ICRs we need
        uint256 whaleICR = (endICR * currentPrice) / newPrice;

        // Open Whale CDP
        (, bytes32 vulnerableCdpId) = _singleCdpSetup(users[0], whaleICR);

        // Trigger RM for Whale
        priceFeedMock.setPrice(newPrice);

        // Open Safe CDP
        (, bytes32 safeCdpId) = _singleCdpSetup(users[0], victimICR);

        // Go through Grace Period
        _waitUntilRMColldown();
        vm.startPrank(users[0]);

        // Show it cannot be liquidated
        vm.expectRevert(
            "LiquidationLibrary: ICR is not below liquidation threshold in current mode"
        );
        cdpManager.liquidate(safeCdpId);

        vm.expectRevert(
            "LiquidationLibrary: ICR is not below liquidation threshold in current mode"
        );
        cdpManager.partiallyLiquidate(safeCdpId, 1234, bytes32(0), bytes32(0));
    }

    // Can NEVER liquidate if CDP above TCR
    /**
        Open Whale, trigger RM open safe show it cannot
     */

    function testCanNeverLiquidateIfCdpAboveTCR(uint64 victimICR) public {
        uint256 currentPrice = priceFeedMock.fetchPrice();
        uint256 endICR = 1.20e18; // In RM

        // We always decrease price by 10%
        uint256 newPrice = (currentPrice * 85) / 100;

        uint256 whaleICR = (endICR * currentPrice) / newPrice;

        vm.assume(victimICR > endICR); // Strictly greater than whale, which will be <= TCR which means this CDP is always > TCR
        vm.assume(victimICR < cdpManager.CCR());

        uint256 victimOpenICR = (victimICR * currentPrice) / newPrice;

        // Open Safe CDP
        (, bytes32 safeCdpId) = _singleCdpSetup(users[0], victimOpenICR);

        // Open Whale CDP
        (, bytes32 vulnerableCdpId) = _singleCdpSetup(users[0], whaleICR);

        // Trigger RM for Whale
        priceFeedMock.setPrice(newPrice);

        // We are in RM
        uint256 _TCR = cdpManager.getCachedTCR(newPrice);
        bool _recoveryMode = _TCR < cdpManager.CCR();
        vm.assume(_recoveryMode);

        // Go through Grace Period
        _waitUntilRMColldown();
        vm.startPrank(users[0]);

        // Show it cannot be liquidated
        vm.expectRevert(
            "LiquidationLibrary: ICR is not below liquidation threshold in current mode"
        );
        cdpManager.liquidate(safeCdpId);

        vm.expectRevert(
            "LiquidationLibrary: ICR is not below liquidation threshold in current mode"
        );
        cdpManager.partiallyLiquidate(safeCdpId, 1234, bytes32(0), bytes32(0));

        uint256 liquidationCheckpoint = vm.snapshot();
        // Liquidate the Whale
        cdpManager.partiallyLiquidate(vulnerableCdpId, 1234, bytes32(0), bytes32(0));

        vm.revertTo(liquidationCheckpoint); // Revert to ensure we can always liquidate
        // Some liquidations could end up undoing RM

        cdpManager.liquidate(vulnerableCdpId);
    }

    // Can Always liquidate if CDP below MCR
    /**
        Open Whale, open victim at risk, trigger victim < MCR, show that it can always be liquidated
     */
    function testCanAlwaysLiquidateifBelowMCR(uint64 victimICR) public {
        uint256 currentPrice = priceFeedMock.fetchPrice();
        uint256 endICR = 1.35e18; // SAFE

        // We always decrease price by 25%
        uint256 newPrice = (currentPrice * 25) / 100;

        uint256 whaleICR = (endICR * currentPrice) / newPrice;

        vm.assume(victimICR < cdpManager.MCR()); // Must be liquidatable after price drop
        console.log("victimICR", victimICR);

        uint256 victimOpenICR = (victimICR * currentPrice) / newPrice;
        console.log("victimOpenICR", victimOpenICR);

        vm.assume(victimOpenICR > cdpManager.CCR()); // Must be able to open

        // Open Unsafe CDP
        (, bytes32 liquidatableCdp) = _singleCdpSetup(users[0], victimOpenICR);

        // Open Whale CDP
        (, bytes32 whaleCdpId) = _singleCdpSetup(users[0], whaleICR);

        // Trigger Price Change Which causes Victim to be liquidatable
        priceFeedMock.setPrice(newPrice);

        // Go through Grace Period
        _waitUntilRMColldown();

        vm.startPrank(users[0]);
        // Liquidate the Whale
        cdpManager.partiallyLiquidate(liquidatableCdp, 1234, bytes32(0), bytes32(0));

        cdpManager.liquidate(liquidatableCdp);
    }

    // == END FSM TEST == //

    /// @dev open Cdp then with price change to a fuzzed _liqICR
    /// @dev According to the specific range for given _liqICR
    /// @dev full liquidation premium should match expected calculation:
    /// @dev Cdps <3% ICR: all Coll as incentive, all debt redistributed
    /// @dev Cdps [3% < ICR < 100%]: 3% as incentive, all remaining debt redistributed
    /// @dev Cdps [100% <= ICR < 110%]: min(3%, 110%-ICR) as incentive, all remaining debt redistributed if below 103%
    /// @dev Cdps [110% <= ICR < TCR]: 10% as Incentive, no debt redistribution
    function test_SingleLiqPremiumFuzz(uint256 _liqICR) public {
        uint256 _goodICR = 135e16;
        uint256 _belowCCR = 124e16;

        // ensure liquidation ICR falls in reasonable range
        _liqICR = bound(_liqICR, 1e15, _belowCCR - 1);

        // ensure price change would give expected fuzz ICR
        uint256 _originalPrice = priceFeedMock.fetchPrice();
        uint256 _newPrice = (_originalPrice * _liqICR) / _goodICR;
        (address user, bytes32 userCdpid) = _singleCdpSetup(users[0], _goodICR);
        bool _noNeedRM = _liqICR < cdpManager.MCR();

        // ensure more than one CDP
        uint256 _userColl = cdpManager.getCdpCollShares(userCdpid);
        uint256 _userDebt = cdpManager.getCdpDebt(userCdpid);
        if (_noNeedRM) {
            _singleCdpSetup(users[0], 8000e16);
        } else {
            uint256 _debt = ((_userColl * 2 * _newPrice) / _belowCCR) - _userDebt;
            _openTestCDP(users[0], _userColl + cdpManager.LIQUIDATOR_REWARD(), _debt);
        }

        // price drop
        priceFeedMock.setPrice(_newPrice);
        _utils.assertApproximateEq(
            cdpManager.getCachedICR(userCdpid, _newPrice),
            _liqICR,
            ICR_COMPARE_TOLERANCE
        );

        if (!_noNeedRM) {
            assertTrue(cdpManager.getCachedTCR(_newPrice) < cdpManager.CCR());
            _waitUntilRMColldown();
        }

        // prepare liquidation
        address _liquidator = users[users.length - 1];
        deal(address(eBTCToken), _liquidator, cdpManager.getCdpDebt(userCdpid)); // sugardaddy liquidator

        uint256 _liquidatorBalBefore = collateral.balanceOf(_liquidator);
        uint256 _expectedReward;
        {
            uint256 _liqStipend = cdpManager.getCdpLiquidatorRewardShares(userCdpid);
            uint256 _maxReward = _userColl + _liqStipend;
            if (_noNeedRM) {
                _expectedReward = _maxReward;
            } else {
                _expectedReward = _liqStipend + ((_userDebt * cdpManager.MCR()) / _newPrice);
                if (_expectedReward > _maxReward) {
                    _expectedReward = _maxReward;
                }
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
        uint256 _liquidatorBalAfter = collateral.balanceOf(_liquidator);
        _utils.assertApproximateEq(
            _liquidatorBalAfter,
            _liquidatorBalBefore + _expectedReward,
            ICR_COMPARE_TOLERANCE
        );
    }

    function test_ZeroSurplus_WithFullLiq_ForICRLessThanLICR(uint256 ICR) public {
        ICR = bound(ICR, cdpManager.MCR() + 1, cdpManager.CCR());

        // ensure there is more than one CDP
        _singleCdpSetup(users[0], 156e16);
        (address user, bytes32 userCdpid) = _singleCdpSetup(users[0], ICR);

        // price drop to trigger liquidation
        uint256 _originalPrice = priceFeedMock.fetchPrice();
        uint256 _newPrice = (_originalPrice * (cdpManager.LICR() - 1234567890123)) / ICR;
        priceFeedMock.setPrice(_newPrice);
        uint256 _currentICR = cdpManager.getCachedICR(userCdpid, _newPrice);
        assertTrue(cdpManager.getSyncedICR(userCdpid, _newPrice) < cdpManager.LICR());

        // prepare liquidation
        address _liquidator = users[users.length - 1];
        deal(address(eBTCToken), _liquidator, cdpManager.getCdpDebt(userCdpid)); // sugardaddy liquidator

        // ensure there is no surplus for full liquidation if bad debt generated
        uint256 _surplusBalBefore = collSurplusPool.getSurplusCollShares(user);
        uint256 _redistributedIndexBefore = cdpManager.systemDebtRedistributionIndex();
        vm.prank(_liquidator);
        cdpManager.liquidate(userCdpid);
        uint256 _surplusBalAfter = collSurplusPool.getSurplusCollShares(user);
        uint256 _redistributedIndexAfter = cdpManager.systemDebtRedistributionIndex();
        assertTrue(_surplusBalBefore == _surplusBalAfter);
        assertTrue(_redistributedIndexAfter > _redistributedIndexBefore);
    }

    function testFullLiquidation() public {
        // Set up a test case where the CDP is fully liquidated, with ICR below MCR or TCR in recovery mode
        // Call _liquidateIndividualCdpSetupCDP with the appropriate arguments
        // Assert that the correct total debt was burned, collateral was sent, and any remaining debt was redistributed
    }

    function testPartialLiquidation() public {
        // Set up a test case where the CDP is only partially liquidated using HintHelper, with ICR below MCR or TCR in recovery mode
        // Call _liquidateIndividualCdpSetupCDP with the appropriate arguments
        // Assert that the correct total debt was burned and collateral was sent, and that no remaining debt was redistributed
    }

    function testRetryFullLiquidation() public {
        // Set up a test case where the CDP is partially liquidated but the amount of collateral sent is 0, resulting in a retry with full liquidation
        // Call _liquidateIndividualCdpSetupCDP with the appropriate arguments
        // Assert that the correct total debt was burned, collateral was sent, and any remaining debt was redistributed
    }

    function _singleCdpSetup(address _usr, uint256 _icr) internal returns (address, bytes32) {
        uint256 _price = priceFeedMock.fetchPrice();
        uint256 _coll = cdpManager.MIN_NET_STETH_BALANCE() * 2;
        uint256 _debt = (_coll * _price) / _icr;
        bytes32 _cdpId = _openTestCDP(_usr, _coll + cdpManager.LIQUIDATOR_REWARD(), _debt);
        uint256 _cdpICR = cdpManager.getCachedICR(_cdpId, _price);
        _utils.assertApproximateEq(_icr, _cdpICR, ICR_COMPARE_TOLERANCE); // in the scale of 1e18
        return (_usr, _cdpId);
    }

    function _sequenceRecoveryModeSwitchSetup() internal returns (bytes32[] memory, uint256) {
        address user = users[0];
        bytes32[] memory cdpIds = new bytes32[](4);

        /** 
            open a sequence of Cdps. once we enter recovery mode, they will have the following status:

            [1] < 100%
            [2] < MCR
            ...
			
            once a few CDPs are liquidated, the system should _switch_ to normal mode. the rest CDP should therefore not be liquidated from the sequence
        */
        uint256 _price = priceFeedMock.fetchPrice();

        // [1] 190%
        (, cdpIds[0]) = _singleCdpSetup(user, 190e16);
        _utils.assertApproximateEq(
            cdpManager.getCachedICR(cdpIds[0], _price),
            190e16,
            ICR_COMPARE_TOLERANCE
        );

        // [2] 210%
        (, cdpIds[1]) = _singleCdpSetup(user, 210e16);
        _utils.assertApproximateEq(
            cdpManager.getCachedICR(cdpIds[1], _price),
            210e16,
            ICR_COMPARE_TOLERANCE
        );

        // [3] 270%
        (, cdpIds[2]) = _singleCdpSetup(user, 270e16);
        _utils.assertApproximateEq(
            cdpManager.getCachedICR(cdpIds[2], _price),
            270e16,
            ICR_COMPARE_TOLERANCE
        );

        // [4] 290%
        (, cdpIds[3]) = _singleCdpSetup(user, 290e16);
        _utils.assertApproximateEq(
            cdpManager.getCachedICR(cdpIds[3], _price),
            290e16,
            ICR_COMPARE_TOLERANCE
        );

        // price drop to half
        uint256 _newPrice = _price / 2;
        priceFeedMock.setPrice(_newPrice);

        return (cdpIds, _newPrice);
    }

    function testSurplusInRMWhenICRBelowMCR() public {
        address wallet = users[0];

        // set eth per stETH share
        collateral.setEthPerShare(1158379174506084879);

        // fetch price before open
        uint256 oldprice = priceFeedMock.fetchPrice();

        // open five cdps
        _openTestCDP(wallet, 2e18 + 2e17, ((2e18 * oldprice) / 240e16));
        _openTestCDP(wallet, 2e18 + 2e17, ((2e18 * oldprice) / 240e16));
        _openTestCDP(wallet, 2e18 + 2e17, ((2e18 * oldprice) / 240e16));
        _openTestCDP(wallet, 2e18 + 2e17, ((2e18 * oldprice) / 240e16));
        bytes32 underwater = _openTestCDP(wallet, 2e18 + 2e17, ((2e18 * oldprice) / 210e16));

        // reduce the price by half to make underwater cdp
        priceFeedMock.setPrice(oldprice / 2);

        // fetch new price after reduce
        uint256 newPrice = priceFeedMock.fetchPrice();

        // ensure the system is in recovery mode
        assert(cdpManager.getSyncedTCR(newPrice) < CCR);

        // liquidate underwater cdp with ICR < MCR
        vm.startPrank(wallet);
        cdpManager.liquidate(underwater);
        vm.stopPrank();

        // make sure the cdp is no longer in the sorted list
        assert(!sortedCdps.contains(underwater));

        // fetch the surplus after the liquidation
        uint256 surplus = collSurplusPool.getSurplusCollShares(wallet);

        // console log the surplus coll
        console.log("Surplus:", surplus);

        // ensure that the surplus is zero
        assert(surplus == 0);
    }
}
