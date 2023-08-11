pragma solidity 0.8.17;

import {eBTCBaseFixture} from "./BaseFixture.sol";
import {Utilities} from "./utils/Utilities.sol";
import {Properties} from "../contracts/TestContracts/invariants/Properties.sol";

contract eBTCBaseInvariants is eBTCBaseFixture, Properties {
    uint public _tolerance = 2000000; //compared to 1e18

    ////////////////////////////////////////////////////////////////////////////
    // See PROPERTIES.md for the invariants of the eBTC system
    ////////////////////////////////////////////////////////////////////////////
    function _ensureSystemInvariants() internal {
        assertTrue(invariant_AP_01(collateral, activePool), "AP-01");
        assertTrue(invariant_AP_03(eBTCToken, activePool), "AP-03");
        assertTrue(invariant_AP_04(cdpManager, activePool, _tolerance), "AP-04");
        assertTrue(invariant_AP_05(cdpManager, _tolerance), "AP-05");
        assertTrue(invariant_CDPM_01(cdpManager, sortedCdps), "CDPM-01");
        assertTrue(invariant_CDPM_02(cdpManager), "CDPM-02");
        assertTrue(invariant_CDPM_03(cdpManager), "CDPM-03");
        assertTrue(invariant_CSP_01(collateral, collSurplusPool), "CSP-01");
        assertTrue(invariant_SL_01(cdpManager, sortedCdps, 0.01e18), "SL-01");
        assertTrue(invariant_SL_02(cdpManager, sortedCdps, priceFeedMock, 0.01e18), "SL-02");
    }
}
