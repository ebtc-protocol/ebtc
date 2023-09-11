// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "../contracts/Dependencies/LiquityMath.sol";
import {eBTCBaseInvariants} from "./BaseInvariants.sol";

contract CDPManagerRedemptionsTest is eBTCBaseInvariants {
    address payable[] users;

    function setUp() public override {
        super.setUp();
        connectCoreContracts();
        connectLQTYContractsToCore();
        vm.warp(3 weeks);
    }

    function test_AdjustCdp_SyncedStateIsAccurate() public {}

    function test_LiquidationOfOtherCdp_SycnedStateIsAccurate() public {}

    function test_RedemptionOfOtherCdp_SycnedStateIsAccurate() public {}
}
