pragma solidity 0.8.17;

import {TargetContractSetup} from "../TargetContractSetup.sol";
import {Properties} from "../Properties.sol";

abstract contract EchidnaForkAssertions is TargetContractSetup, Properties {
    function asserts_canary_price() public {
        t(invariant_DUMMY_01(priceFeedMock), "Dummy");
    }

    function asserts_active_pool_invariant_1() public {
        t(invariant_AP_01(collateral, activePool), AP_01);
    }

    function asserts_active_pool_invariant_2() public {
        t(invariant_AP_02(cdpManager, activePool), AP_02);
    }

    function asserts_active_pool_invariant_3() public {
        t(invariant_AP_03(eBTCToken, activePool), AP_03);
    }

    function asserts_active_pool_invariant_4() public {
        t(invariant_AP_04(cdpManager, activePool, diff_tolerance), AP_04);
    }

    function asserts_active_pool_invariant_5() public {
        t(invariant_AP_05(cdpManager, diff_tolerance), AP_05);
    }

    function asserts_cdp_manager_invariant_1() public {
        t(invariant_CDPM_01(cdpManager, sortedCdps), CDPM_01);
    }

    function asserts_cdp_manager_invariant_2() public {
        t(invariant_CDPM_02(cdpManager), CDPM_02);
    }

    function asserts_cdp_manager_invariant_3() public {
        t(invariant_CDPM_03(cdpManager), CDPM_03);
    }

    function asserts_cdp_manager_invariant_10() public {
        t(invariant_CDPM_10(cdpManager), CDPM_10);
    }

    function asserts_cdp_manager_invariant_11() public {
        t(invariant_CDPM_11(cdpManager), CDPM_11);
    }

    function asserts_cdp_manager_invariant_12() public {
        t(invariant_CDPM_12(sortedCdps, vars), CDPM_12);
    }

    // CDPM_04 is a vars invariant

    function asserts_coll_surplus_pool_invariant_1() public {
        t(invariant_CSP_01(collateral, collSurplusPool), CSP_01);
    }

    function asserts_coll_surplus_pool_invariant_2() public {
        t(invariant_CSP_02(collSurplusPool), CSP_02);
    }

    function asserts_sorted_list_invariant_1() public {
        t(invariant_SL_01(cdpManager, sortedCdps), SL_01);
    }

    function asserts_sorted_list_invariant_2() public {
        t(invariant_SL_02(cdpManager, sortedCdps, priceFeedMock), SL_02);
    }

    function asserts_sorted_list_invariant_3() public {
        t(invariant_SL_03(cdpManager, priceFeedMock, sortedCdps), SL_03);
    }

    // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/15
    function asserts_sorted_list_invariant_5() public {
        t(invariant_SL_05(crLens, sortedCdps), SL_05);
    }

    // invariant_GENERAL_01 is a vars invariant

    function asserts_GENERAL_02() public {
        t(invariant_GENERAL_02(cdpManager, priceFeedMock, eBTCToken, collateral), GENERAL_02);
    }

    function asserts_GENERAL_03() public {
        t(invariant_GENERAL_03(cdpManager, borrowerOperations, eBTCToken, collateral), GENERAL_03);
    }

    function asserts_GENERAL_05() public {
        t(invariant_GENERAL_05(activePool, cdpManager, collateral), GENERAL_05);
    }

    function asserts_GENERAL_05_B() public {
        t(invariant_GENERAL_05_B(collSurplusPool, collateral), GENERAL_05);
    }

    function asserts_GENERAL_06() public {
        t(invariant_GENERAL_06(eBTCToken, cdpManager, sortedCdps), GENERAL_06);
    }

    function asserts_GENERAL_08() public {
        t(invariant_GENERAL_08(cdpManager, sortedCdps, priceFeedMock, collateral), GENERAL_08);
    }

    // invariant_GENERAL_09 is a vars

    function asserts_GENERAL_12() public {
        t(invariant_GENERAL_12(cdpManager, priceFeedMock, crLens), GENERAL_12);
    }

    function asserts_GENERAL_13() public {
        t(invariant_GENERAL_13(crLens, cdpManager, priceFeedMock, sortedCdps), GENERAL_13);
    }

    function asserts_GENERAL_14() public {
        t(invariant_GENERAL_14(crLens, cdpManager, sortedCdps), GENERAL_14);
    }

    // function asserts_GENERAL_15() public {
    //     t(invariant_GENERAL_15(), "Failed");
    // }

    function asserts_GENERAL_17() public {
        t(invariant_GENERAL_17(cdpManager, sortedCdps, priceFeedMock, collateral), GENERAL_17);
    }

    // @audit Not testable on fork
    // function asserts_GENERAL_18() public {
    //    t(invariant_GENERAL_18(cdpManager, sortedCdps, priceFeedMock, collateral), "Failed");
    //}

    function asserts_GENERAL_19() public {
        t(invariant_GENERAL_19(activePool), GENERAL_19);
    }

    function asserts_LS_01() public {
        t(invariant_LS_01(
                cdpManager,
                liquidationSequencer,
                syncedLiquidationSequencer,
                priceFeedMock
            ), L_01);
    }
}
