pragma solidity 0.8.17;

import {eBTCBaseFixture} from "./BaseFixture.sol";
import {Utilities} from "./utils/Utilities.sol";
import {Properties} from "../contracts/TestContracts/invariants/Properties.sol";

contract eBTCBaseInvariants is eBTCBaseFixture, Properties {
    uint256 public _tolerance = 2000000; //compared to 1e18

    ////////////////////////////////////////////////////////////////////////////
    // See PROPERTIES.md for the invariants of the eBTC system
    ////////////////////////////////////////////////////////////////////////////
    function _ensureSystemInvariants() internal {
        assertTrue(invariant_AP_01(collateral, activePool), AP_01);
        assertTrue(invariant_AP_02(cdpManager, activePool), AP_02);
        assertTrue(invariant_AP_03(eBTCToken, activePool), AP_03);
        assertTrue(invariant_AP_04(cdpManager, activePool, _tolerance), AP_04);
        assertTrue(invariant_AP_05(cdpManager, _tolerance), AP_05);
        assertTrue(invariant_CDPM_01(cdpManager, sortedCdps), CDPM_01);
        assertTrue(invariant_CDPM_02(cdpManager), CDPM_02);
        assertTrue(invariant_CDPM_03(cdpManager), CDPM_03);
        // CDPM_04 -> VARS
        assertTrue(invariant_CSP_01(collateral, collSurplusPool), CSP_01);
        // assertTrue(invariant_CSP_02(collSurplusPool), CSP_02); /// @audit Only on Echidna due to how is coded
        assertTrue(invariant_SL_01(cdpManager, sortedCdps), SL_01);
        assertTrue(invariant_SL_02(cdpManager, sortedCdps, priceFeedMock), SL_02);
        assertTrue(invariant_SL_03(cdpManager, priceFeedMock, sortedCdps), SL_03);
        assertTrue(invariant_SL_05(crLens, sortedCdps), SL_05);

        // invariant_GENERAL_01 -> Vars
        assertTrue(
            invariant_GENERAL_02(cdpManager, priceFeedMock, eBTCToken, collateral),
            GENERAL_02
        );
        assertTrue(
            invariant_GENERAL_03(cdpManager, borrowerOperations, eBTCToken, collateral),
            GENERAL_03
        );
        assertTrue(invariant_GENERAL_05(activePool, cdpManager, collateral), GENERAL_05);
        assertTrue(invariant_GENERAL_05_B(collSurplusPool, collateral), "GENERAL_05_B");
        assertTrue(invariant_GENERAL_06(eBTCToken, cdpManager, sortedCdps), GENERAL_06);
        assertTrue(
            invariant_GENERAL_08(cdpManager, sortedCdps, priceFeedMock, collateral),
            GENERAL_08
        );
        // invariant_GENERAL_09 -> Vars

        assertTrue(invariant_GENERAL_12(cdpManager, priceFeedMock, crLens), GENERAL_12);
        assertTrue(invariant_GENERAL_13(crLens, cdpManager, priceFeedMock, sortedCdps), GENERAL_13);
        assertTrue(invariant_GENERAL_14(crLens, cdpManager, sortedCdps), GENERAL_14);
        assertTrue(
            invariant_GENERAL_17(cdpManager, sortedCdps, priceFeedMock, collateral),
            GENERAL_17
        );
    }
}
