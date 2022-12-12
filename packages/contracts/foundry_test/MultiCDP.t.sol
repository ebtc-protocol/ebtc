// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.11;

import "forge-std/Test.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";

// TODO: Add fuzz tests here
contract CDPTest is eBTCBaseFixture {
    uint256 private testNumber;
    address user;

    function setUp() public override {
        eBTCBaseFixture.setUp();
        eBTCBaseFixture.connectLQTYContracts();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();
        user = msg.sender;
        vm.deal(user, 300 ether);
    }

    function testCdpsCountEqToZero() public {
        assertEq(cdpManager.getCdpIdsCount(), 0);
    }

    function testOpenCDPsHappy() public {
        // Make sure there is no CDPs in the system yet
        assert(sortedCdps.getLast() == "");
        vm.prank(user);
        borrowerOperations.openCdp{value : address(user).balance}(
            5e17,
            // TODO: Random number still based on fixed LUSD price. Change once peg to BTC
            170e20,
            "some hint",
            "some hint"
        );
        assertEq(cdpManager.getCdpIdsCount(), 1);
        // Make sure valid cdpId returned
        assert(sortedCdps.getLast() != "");
    }

    function testFailICRTooLow() public {
        assert(sortedCdps.getLast() == "");
        vm.prank(user);
        borrowerOperations.openCdp{value : address(user).balance}(
            5e17,
            // Borrowed eBTC amount is too high compared to Collateral
            20000e20,
            "some hint",
            "some hint"
        );
    }
}
