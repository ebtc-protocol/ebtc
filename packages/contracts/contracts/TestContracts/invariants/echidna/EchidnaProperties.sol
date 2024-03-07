pragma solidity 0.8.17;

import {TargetContractSetup} from "../TargetContractSetup.sol";
import {Properties} from "../Properties.sol";

abstract contract EchidnaProperties is TargetContractSetup, Properties {
    function echidna_price() public returns (bool) {
        return invariant_DUMMY_01(priceFeedMock);
    }

    function echidna_active_pool_invariant_1() public returns (bool) {
        return invariant_AP_01(collateral, activePool);
    }

    function echidna_active_pool_invariant_2() public returns (bool) {
        return invariant_AP_02(cdpManager, activePool);
    }

    function echidna_active_pool_invariant_3() public returns (bool) {
        return invariant_AP_03(eBTCToken, activePool);
    }

    function echidna_active_pool_invariant_4() public returns (bool) {
        return invariant_AP_04(cdpManager, activePool, diff_tolerance);
    }

    function echidna_active_pool_invariant_5() public returns (bool) {
        return invariant_AP_05(cdpManager, diff_tolerance);
    }

    function echidna_cdp_manager_invariant_1() public returns (bool) {
        return invariant_CDPM_01(cdpManager, sortedCdps);
    }

    function echidna_cdp_manager_invariant_2() public returns (bool) {
        return invariant_CDPM_02(cdpManager);
    }

    function echidna_cdp_manager_invariant_3() public returns (bool) {
        return invariant_CDPM_03(cdpManager);
    }

    function echidna_cdp_manager_invariant_10() public returns (bool) {
        return invariant_CDPM_10(cdpManager);
    }

    function echidna_cdp_manager_invariant_11() public returns (bool) {
        return invariant_CDPM_11(cdpManager);
    }

    function echidna_cdp_manager_invariant_12() public returns (bool) {
        return invariant_CDPM_12(sortedCdps, vars);
    }

    // CDPM_04 is a vars invariant

    function echidna_coll_surplus_pool_invariant_1() public returns (bool) {
        return invariant_CSP_01(collateral, collSurplusPool);
    }

    function echidna_coll_surplus_pool_invariant_2() public returns (bool) {
        return invariant_CSP_02(collSurplusPool);
    }

    function echidna_sorted_list_invariant_1() public returns (bool) {
        return invariant_SL_01(cdpManager, sortedCdps);
    }

    function echidna_sorted_list_invariant_2() public returns (bool) {
        return invariant_SL_02(cdpManager, sortedCdps, priceFeedMock);
    }

    function echidna_sorted_list_invariant_3() public returns (bool) {
        return invariant_SL_03(cdpManager, priceFeedMock, sortedCdps);
    }

    // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/15
    function echidna_sorted_list_invariant_5() public returns (bool) {
        return invariant_SL_05(crLens, sortedCdps);
    }

    // invariant_GENERAL_01 is a vars invariant

    function echidna_GENERAL_02() public returns (bool) {
        return invariant_GENERAL_02(cdpManager, priceFeedMock, eBTCToken, collateral);
    }

    function echidna_GENERAL_03() public returns (bool) {
        return invariant_GENERAL_03(cdpManager, borrowerOperations, eBTCToken, collateral);
    }

    function echidna_GENERAL_05() public returns (bool) {
        return invariant_GENERAL_05(activePool, cdpManager, collateral);
    }

    function echidna_GENERAL_05_B() public returns (bool) {
        return invariant_GENERAL_05_B(collSurplusPool, collateral);
    }

    function echidna_GENERAL_06() public returns (bool) {
        return invariant_GENERAL_06(eBTCToken, cdpManager, sortedCdps);
    }

    function echidna_GENERAL_08() public returns (bool) {
        return invariant_GENERAL_08(cdpManager, sortedCdps, priceFeedMock, collateral);
    }

    // invariant_GENERAL_09 is a vars

    function echidna_GENERAL_12() public returns (bool) {
        return invariant_GENERAL_12(cdpManager, priceFeedMock, crLens);
    }

    function echidna_GENERAL_13() public returns (bool) {
        return invariant_GENERAL_13(crLens, cdpManager, priceFeedMock, sortedCdps);
    }

    function echidna_GENERAL_14() public returns (bool) {
        return invariant_GENERAL_14(crLens, cdpManager, sortedCdps);
    }

    // function echidna_GENERAL_15() public returns (bool) {
    //     return invariant_GENERAL_15();
    // }

    function echidna_GENERAL_17() public returns (bool) {
        return invariant_GENERAL_17(cdpManager, sortedCdps, priceFeedMock, collateral);
    }

    function echidna_GENERAL_18() public returns (bool) {
        return invariant_GENERAL_18(cdpManager, sortedCdps, priceFeedMock, collateral);
    }

    function echidna_GENERAL_19() public returns (bool) {
        return invariant_GENERAL_19(activePool);
    }

    function echidna_LS_01() public returns (bool) {
        return
            invariant_LS_01(
                cdpManager,
                liquidationSequencer,
                syncedLiquidationSequencer,
                priceFeedMock
            );
    }
}
