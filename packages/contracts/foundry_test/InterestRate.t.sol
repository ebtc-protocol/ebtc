// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.11;

import {eBTCBaseFixture} from "./BaseFixture.sol";
import {console2 as console} from "forge-std/console2.sol";

contract InterestRateTest is eBTCBaseFixture {
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

    function testInterestIsApplied() public {
        // Make sure there is no CDPs in the system yet
        assertEq(sortedCdps.getLast(), "");

        vm.prank(user);
        borrowerOperations.openCdp{value: address(user).balance}(
            5e17,
            2000e18,
            bytes32(0),
            bytes32(0)
        );
        assertEq(cdpManager.getCdpIdsCount(), 1);
        // Make sure valid cdpId returned

        bytes32 cdpId = sortedCdps.getLast();
        assertTrue(cdpId != "");

        uint256 debt;
        (debt, , , , ) = cdpManager.getEntireDebtAndColl(cdpId);
        // Borrowed + borrow fee + gas compensation
        assertEq(debt, 2210e18);

        skip(365 days);

        (debt, , , , ) = cdpManager.getEntireDebtAndColl(cdpId);
        assertApproxEqRel(debt, 1.02 * 2210e18, 0.01e18); // within 1%
    }
}
