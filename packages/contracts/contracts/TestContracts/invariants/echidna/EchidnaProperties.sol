pragma solidity 0.8.17;

import {EchidnaBaseTester} from "./EchidnaBaseTester.sol";
import {Properties} from "../Properties.sol";

abstract contract EchidnaProperties is EchidnaBaseTester, Properties {
    function echidna_canary_active_pool_balance() public view returns (bool) {
        return invariant_P_47(cdpManager, collateral, activePool);
    }

    function echidna_cdp_properties() public view returns (bool) {
        return invariant_SL_03(cdpManager, priceFeedTestnet, sortedCdps);
    }

    function echidna_accounting_balances() public view returns (bool) {
        return
            invariant_P_22(collateral, borrowerOperations, eBTCToken, sortedCdps, priceFeedTestnet);
    }

    function echidna_price() public view returns (bool) {
        return invariant_DUMMY_01(priceFeedTestnet);
    }

    function echidna_EBTC_global_balances() public view returns (bool) {
        return invariant_P_36(eBTCToken, cdpManager, sortedCdps);
    }

    function echidna_active_pool_invariant_1() public view returns (bool) {
        return invariant_AP_01(collateral, activePool);
    }

    function echidna_active_pool_invariant_3() public view returns (bool) {
        return invariant_AP_03(eBTCToken, activePool);
    }

    function echidna_active_pool_invariant_4() public view returns (bool) {
        return invariant_AP_04(cdpManager, activePool, diff_tolerance);
    }

    function echidna_active_pool_invariant_5() public view returns (bool) {
        return invariant_AP_05(cdpManager, diff_tolerance);
    }

    function echidna_cdp_manager_invariant_1() public view returns (bool) {
        return invariant_CDPM_01(cdpManager, sortedCdps);
    }

    function echidna_cdp_manager_invariant_2() public view returns (bool) {
        return invariant_CDPM_02(cdpManager);
    }

    function echidna_cdp_manager_invariant_3() public view returns (bool) {
        return invariant_CDPM_03(cdpManager);
    }

    function echidna_coll_surplus_pool_invariant_1() public view returns (bool) {
        return invariant_CSP_01(collateral, collSurplusPool);
    }

    function echidna_sorted_list_invariant_1() public view returns (bool) {
        return invariant_SL_01(cdpManager, sortedCdps);
    }

    function echidna_sorted_list_invariant_2() public view returns (bool) {
        return invariant_SL_02(cdpManager, sortedCdps, priceFeedTestnet);
    }
}