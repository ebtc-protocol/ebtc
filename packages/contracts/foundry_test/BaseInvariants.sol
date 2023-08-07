pragma solidity 0.8.17;

import {eBTCBaseFixture} from "./BaseFixture.sol";
import {Utilities} from "./utils/Utilities.sol";

contract eBTCBaseInvariants is eBTCBaseFixture {
    uint public _tolerance = 2000000; //compared to 1e18

    ////////////////////////////////////////////////////////////////////////////
    // Basic Invariants for ebtc system
    // - active_pool_1： collateral balance in active pool is greater than or equal to its accounting number
    // - active_pool_2： EBTC debt accounting number in active pool is less than or equal to EBTC total supply
    // - active_pool_3： sum of EBTC debt accounting numbers in active pool & default pool is equal to EBTC total supply
    // - active_pool_4： total collateral in active pool should be equal to the sum of all individual CDP collateral
    // - active_pool_5： sum of debt accounting in active pool should be equal to sum of debt accounting of individual CDPs
    // - cdp_manager_1： count of active CDPs is equal to SortedCdp list length
    // - cdp_manager_2： sum of active CDPs stake is equal to totalStakes
    // - cdp_manager_3： stFeePerUnit tracker for individual CDP is equal to or less than the global variable
    // - coll_surplus_pool_1： collateral balance in collSurplus pool is greater than or equal to its accounting number
    // - sorted_list_1： NICR ranking in the sorted list should follow descending order
    // - sorted_list_2： the first(highest) ICR in the sorted list should bigger or equal to TCR
    ////////////////////////////////////////////////////////////////////////////

    function _assert_active_pool_invariant_1() internal {
        assertGe(
            collateral.sharesOf(address(activePool)),
            activePool.getSystemCollShares(),
            "System Invariant: active_pool_1"
        );
    }

    function _assert_active_pool_invariant_2() internal {
        assertGe(
            eBTCToken.totalSupply(),
            activePool.getSystemDebt(),
            "System Invariant: active_pool_2"
        );
    }

    function _assert_active_pool_invariant_3() internal {
        assertEq(
            eBTCToken.totalSupply(),
            (activePool.getSystemDebt()),
            "System Invariant: active_pool_3"
        );
    }

    function _assert_active_pool_invariant_4() internal view {
        uint _cdpCount = cdpManager.getCdpIdsCount();
        uint _sum;
        for (uint i = 0; i < _cdpCount; ++i) {
            CdpState memory _cdpState = _getEntireDebtAndColl(cdpManager.CdpIds(i));
            _sum = (_sum + _cdpState.coll);
        }
        require(
            _utils.assertApproximateEq(activePool.getSystemCollShares(), _sum, _tolerance),
            "System Invariant: active_pool_4"
        );
    }

    function _assert_active_pool_invariant_5() internal view {
        uint _cdpCount = cdpManager.getCdpIdsCount();
        uint _sum;
        for (uint i = 0; i < _cdpCount; ++i) {
            (uint _debt, , ) = cdpManager.getEntireDebtAndColl(cdpManager.CdpIds(i));
            _sum = _sum + _debt;
        }
        require(
            _utils.assertApproximateEq(_sum, cdpManager.getSystemDebt(), _tolerance),
            "System Invariant: active_pool_5"
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
        uint _cdpCount = cdpManager.getCdpIdsCount();
        uint _sum;
        for (uint i = 0; i < _cdpCount; ++i) {
            _sum = (_sum + cdpManager.getCdpStake(cdpManager.CdpIds(i)));
        }
        assertEq(_sum, cdpManager.totalStakes(), "System Invariant: cdp_manager_2");
    }

    function _assert_cdp_manager_invariant_3() internal {
        uint _cdpCount = cdpManager.getCdpIdsCount();
        uint _stFeePerUnitg = cdpManager.stFeePerUnitg();
        for (uint i = 0; i < _cdpCount; ++i) {
            assertGe(
                _stFeePerUnitg,
                cdpManager.stFeePerUnitcdp(cdpManager.CdpIds(i)),
                "System Invariant: cdp_manager_3"
            );
        }
    }

    function _assert_cdp_manager_invariant_4() internal {
        assertEq(
            cdpManager.stFPPSg(),
            collateral.getPooledEthByShares(1e18),
            "System Invariant: stFPPSg is not synced to real collateral index"
        );
    }

    function _assert_coll_surplus_pool_invariant_1() internal {
        assertGe(
            collateral.sharesOf(address(collSurplusPool)),
            collSurplusPool.getSystemCollShares(),
            "System Invariant: coll_surplus_pool_1"
        );
    }

    function _assert_sorted_list_invariant_1() internal {
        bytes32 _prev = sortedCdps.getFirst();
        bytes32 _next = sortedCdps.getNext(_prev);
        while (_prev != sortedCdps.dummyId() && _next != sortedCdps.dummyId() && _prev != _next) {
            assertGe(
                cdpManager.getNominalICR(_prev),
                cdpManager.getNominalICR(_next),
                "System Invariant: sorted_list_1"
            );

            _prev = _next;
            _next = sortedCdps.getNext(_prev);
        }
    }

    function _assert_sorted_list_invariant_2() internal {
        bytes32 _first = sortedCdps.getFirst();
        uint _price = priceFeedMock.getPrice();
        if (_first != sortedCdps.dummyId() && _price > 0) {
            assertGe(
                cdpManager.getCurrentICR(_first, _price),
                cdpManager.getTCR(_price),
                "System Invariant: sorted_list_2"
            );
        }
    }

    function _ensureSystemInvariants() internal {
        _assert_active_pool_invariant_1();
        _assert_active_pool_invariant_2();
        _assert_active_pool_invariant_3();
        _assert_active_pool_invariant_4();
        _assert_active_pool_invariant_5();
        _assert_cdp_manager_invariant_1();
        _assert_cdp_manager_invariant_2();
        _assert_cdp_manager_invariant_3();
        _assert_cdp_manager_invariant_4();
        _assert_coll_surplus_pool_invariant_1();
        _assert_sorted_list_invariant_1();
        _assert_sorted_list_invariant_2();
    }
}
