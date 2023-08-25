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
        assertTrue(invariant_AP_01(collateral, activePool), AP_01);
        assertTrue(invariant_AP_03(eBTCToken, activePool), AP_03);
        assertTrue(invariant_AP_04(cdpManager, activePool, _tolerance), AP_04);
        assertTrue(invariant_AP_05(cdpManager, _tolerance), AP_05);
        assertTrue(invariant_CDPM_01(cdpManager, sortedCdps), CDPM_01);
        assertTrue(invariant_CDPM_02(cdpManager), CDPM_02);
        assertTrue(invariant_CDPM_03(cdpManager), CDPM_03);
        assertTrue(invariant_CSP_01(collateral, collSurplusPool), CSP_01);
        assertTrue(invariant_SL_01(cdpManager, sortedCdps, 0.01e18), SL_01);
        assertTrue(invariant_SL_02(cdpManager, sortedCdps, priceFeedMock, 0.01e18), SL_02);
    }
}
