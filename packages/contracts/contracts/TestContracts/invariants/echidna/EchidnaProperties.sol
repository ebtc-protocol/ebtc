pragma solidity 0.8.17;

import {EchidnaBaseTester} from "./EchidnaBaseTester.sol";
import {EchidnaLog} from "./EchidnaLog.sol";
import {Properties} from "../Properties.sol";

abstract contract EchidnaProperties is EchidnaBaseTester, EchidnaLog, Properties {
    function echidna_price() public log returns (bool) {
        return invariant_DUMMY_01(priceFeedTestnet);
    }

    function echidna_active_pool_invariant_1() public log returns (bool) {
        return invariant_AP_01(collateral, activePool);
    }

    function echidna_active_pool_invariant_2() public log returns (bool) {
        return invariant_AP_02(cdpManager, activePool);
    }

    function echidna_active_pool_invariant_3() public log returns (bool) {
        return invariant_AP_03(eBTCToken, activePool);
    }

    function echidna_active_pool_invariant_4() public log returns (bool) {
        return invariant_AP_04(cdpManager, activePool, diff_tolerance);
    }

    function echidna_active_pool_invariant_5() public log returns (bool) {
        return invariant_AP_05(cdpManager, diff_tolerance);
    }

    function echidna_cdp_manager_invariant_1() public log returns (bool) {
        return invariant_CDPM_01(cdpManager, sortedCdps);
    }

    function echidna_cdp_manager_invariant_2() public log returns (bool) {
        return invariant_CDPM_02(cdpManager);
    }

    function echidna_cdp_manager_invariant_3() public log returns (bool) {
        return invariant_CDPM_03(cdpManager);
    }

    function echidna_coll_surplus_pool_invariant_1() public log returns (bool) {
        return invariant_CSP_01(collateral, collSurplusPool);
    }

    function echidna_sorted_list_invariant_1() public log returns (bool) {
        return invariant_SL_01(cdpManager, sortedCdps, diff_tolerance);
    }

    function echidna_sorted_list_invariant_2() public log returns (bool) {
        return invariant_SL_02(cdpManager, sortedCdps, priceFeedTestnet, diff_tolerance);
    }

    function echidna_sorted_list_invariant_3() public log returns (bool) {
        return invariant_SL_03(cdpManager, priceFeedTestnet, sortedCdps);
    }

    function echidna_GENERAL_02() public log returns (bool) {
        return invariant_GENERAL_02(cdpManager, priceFeedTestnet, eBTCToken);
    }

    function echidna_GENERAL_03() public log returns (bool) {
        return invariant_GENERAL_03(cdpManager, borrowerOperations, eBTCToken, collateral);
    }

    function echidna_GENERAL_06() public log returns (bool) {
        return invariant_GENERAL_06(eBTCToken, cdpManager, sortedCdps);
    }
}
