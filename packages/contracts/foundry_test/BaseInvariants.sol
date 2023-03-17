pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "../contracts/Dependencies/SafeMath.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";
import {Utilities} from "./utils/Utilities.sol";

contract eBTCBaseInvariants is eBTCBaseFixture {
    using SafeMath for uint256;
    using SafeMath for uint96;
    using SafeMath for uint64;
    using SafeMath for uint32;
    using SafeMath for uint16;
    using SafeMath for uint8;

    Utilities internal _utils;
    uint public _tolerance = 2000000; //compared to 1e18

    ////////////////////////////////////////////////////////////////////////////
    // Basic Invariants for ebtc system
    // - active_pool_1： collateral balance in active pool is greater than or equal to its accounting number
    // - active_pool_2： EBTC debt accounting number in active pool is less than or equal to EBTC total supply
    // - active_pool_3： sum of EBTC debt accounting numbers in active pool & default pool is equal to EBTC total supply
    // - active_pool_4： total collateral in active pool should be equal to the sum of all individual CDP collateral
    // - cdp_manager_1： count of active CDPs is equal to SortedCdp list length
    // - default_pool_1： collateral balance in default pool is greater than or equal to its accounting number
    // - coll_surplus_pool_1： collateral balance in collSurplus pool is greater than or equal to its accounting number
    ////////////////////////////////////////////////////////////////////////////

    function _assert_active_pool_invariant_1() internal {
        assertGe(
            collateral.sharesOf(address(activePool)),
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

    function _assert_active_pool_invariant_4() internal {
        uint _cdpCount = cdpManager.getCdpIdsCount();
        uint _sum;
        for (uint i = 0; i < _cdpCount; ++i) {
            CdpState memory _cdpState = _getEntireDebtAndColl(cdpManager.CdpIds(i));
            _sum = _sum.add(_cdpState.coll);
        }
        require(
            _utils.assertApproximateEq(activePool.getETH(), _sum, _tolerance),
            "System Invariant: active_pool_4"
        );
    }

    function _assert_cdp_manager_invariant_1() internal {
        assertEq(
            cdpManager.getCdpIdsCount(),
            sortedCdps.getSize(),
            "System Invariant: cdp_manager_1"
        );
    }

    function _assert_default_pool_invariant_1() internal {
        assertGe(
            collateral.balanceOf(address(defaultPool)),
            defaultPool.getETH(),
            "System Invariant: default_pool_1"
        );
    }

    function _assert_coll_surplus_pool_invariant_1() internal {
        assertGe(
            collateral.balanceOf(address(collSurplusPool)),
            collSurplusPool.getETH(),
            "System Invariant: coll_surplus_pool_1"
        );
    }

    function _ensureSystemInvariants() internal {
        _assert_active_pool_invariant_1();
        _assert_active_pool_invariant_2();
        _assert_active_pool_invariant_3();
        _assert_active_pool_invariant_4();
        _assert_cdp_manager_invariant_1();
        _assert_default_pool_invariant_1();
        _assert_coll_surplus_pool_invariant_1();
    }
}
