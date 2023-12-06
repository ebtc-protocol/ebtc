// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {console2 as console} from "forge-std/console2.sol";

import {eBTCBaseInvariants} from "./BaseInvariants.sol";

contract CdpManagerDebtRedistributionTest is eBTCBaseInvariants {
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
        for (uint256 i = 0; i < cdpManager.getActiveCdpsCount(); ++i) {
            bytes32 _cdpId = cdpManager.CdpIds(i);
            (, uint256 _coll, , , , ) = cdpManager.Cdps(_cdpId);
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

    function test_DebtRedistributionVarianceBetweenSyncedAndUnsyncedCdps() public {
        uint256 DAYS_DURATION = 365;
        uint256 REBASE_VALUE_PER_DAY = 109589040000000; // estimated rebase value per day is (4% / 365) = 0.00010958904
        uint256 TO_LIQUIDATE_ICR = 130e16;
        uint256 TO_LIQUIDATE_ICR_AFTER_PRICE_DROP = 50e16;
        uint256 USER_ICR = 500e16;

        (, bytes32 toLiquidateCdpId) = _singleCdpSetup(users[3], TO_LIQUIDATE_ICR);
        (address user0, bytes32 cdpId0) = _singleCdpSetup(users[0], USER_ICR);

        console.log("Initial Setup");
        _printSortedCdps();
        
        // run rebases for virtual share reduction
        // for (uint i = 0; i < DAYS_DURATION; i++) {
        //     collateral.setEthPerShare(collateral.getPooledEthByShares(1e18) + REBASE_VALUE_PER_DAY);
        //     console.log("Rebase %s", collateral.getPooledEthByShares(1e18));
        // }

        collateral.setEthPerShare(collateral.getPooledEthByShares(1e18) * 2);
        console.log("Rebase %s", collateral.getPooledEthByShares(1e18));

        (address user1, bytes32 cdpId1) = _singleCdpSetup(users[1], USER_ICR);

        console.log("Second Cdp Created");
        _printSortedCdps();

        // price drop
        console.log("Prepared for Liquidation");
        _printSortedCdps();

        uint256 _originalPrice = priceFeedMock.fetchPrice();
        uint256 _newPrice = (_originalPrice * TO_LIQUIDATE_ICR_AFTER_PRICE_DROP) / TO_LIQUIDATE_ICR;
        priceFeedMock.setPrice(_newPrice);
        _utils.assertApproximateEq(
            cdpManager.getCachedICR(toLiquidateCdpId, _newPrice),
            TO_LIQUIDATE_ICR_AFTER_PRICE_DROP,
            ICR_COMPARE_TOLERANCE
        );

        // prepare liquidation
        address _liquidator = users[users.length - 1];
        deal(address(eBTCToken), _liquidator, cdpManager.getCdpDebt(toLiquidateCdpId)); // sugardaddy liquidator

        vm.prank(_liquidator);
        cdpManager.liquidate(toLiquidateCdpId);
        assertTrue(sortedCdps.contains(toLiquidateCdpId) == false);

        console.log("After Liquidation");
        _printSortedCdps();

        // check debt redistribution values

        _ensureSystemInvariants();
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
}
