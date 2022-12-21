// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.11;

import {eBTCBaseFixture} from "./BaseFixture.sol";
import {console2 as console} from "forge-std/console2.sol";

contract InterestRateTest is eBTCBaseFixture {
    uint256 private testNumber;
    address user1;
    address user2;

    function setUp() public override {
        eBTCBaseFixture.setUp();

        eBTCBaseFixture.connectLQTYContracts();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();

        user1 = address(1);
        user2 = address(2);
        vm.deal(user1, 1000 ether);
        vm.deal(user2, 1000 ether);
    }

    function testInterestIsApplied() public {
        vm.prank(user1);
        bytes32 cdpId1 = borrowerOperations.openCdp{value: user1.balance}(
            5e17,
            2000e18,
            bytes32(0),
            bytes32(0)
        );
        assertTrue(cdpId1 != "");
        assertEq(cdpManager.getCdpIdsCount(), 1);

        // Make sure valid cdpId returned
        bytes32 cdpId2 = sortedCdps.getLast();
        assertEq(cdpId1, cdpId2);

        uint256 debt;
        (debt, , , , ) = cdpManager.getEntireDebtAndColl(cdpId1);
        // Borrowed + borrow fee + gas compensation
        assertEq(debt, 2210e18);

        skip(365 days);

        (debt, , , , ) = cdpManager.getEntireDebtAndColl(cdpId1);
        // Expected interest over a year is 2%
        assertApproxEqRel(debt, 1.02 * 2210e18, 0.01e18); // Error in interest is <1% of the expected value
    }

    function testInterestIsSameForInteractingAndNonInteractingUsers() public {
        vm.prank(user1);
        bytes32 cdpId1 = borrowerOperations.openCdp{value: 100 ether}(
            5e17,
            2000e18,
            bytes32(0),
            bytes32(0)
        );
        vm.prank(user2);
        bytes32 cdpId2 = borrowerOperations.openCdp{value: 100 ether}(
            5e17,
            2000e18,
            bytes32(0),
            bytes32(0)
        );
        assertEq(cdpManager.getCdpIdsCount(), 2);

        uint256 debt1;
        uint256 debt2;
        uint256 pendingReward1;
        uint256 pendingInterest1;
        uint256 pendingReward2;
        uint256 pendingInterest2;

        (debt1, , , , ) = cdpManager.getEntireDebtAndColl(cdpId1);
        (debt2, , , , ) = cdpManager.getEntireDebtAndColl(cdpId2);

        assertEq(debt1, debt2);

        skip(100 days);

        (debt1, , pendingReward1, pendingInterest1, ) = cdpManager.getEntireDebtAndColl(cdpId1);
        (debt2, , pendingReward2, pendingInterest2, ) = cdpManager.getEntireDebtAndColl(cdpId2);

        assertEq(pendingReward1, 0);
        assertEq(pendingReward2, 0);

        assertGt(pendingInterest1, 0);
        assertEq(pendingInterest1, pendingInterest2);

        assertEq(debt1, debt2);

        // Realize pending debt
        vm.prank(user1);
        borrowerOperations.addColl{value: 1}(cdpId1, bytes32(0), bytes32(0));

        (debt1, , , pendingInterest1, ) = cdpManager.getEntireDebtAndColl(cdpId1);
        assertEq(pendingInterest1, 0);
        assertEq(debt1, debt2);

        skip(100 days);

        (debt1, , pendingReward1, pendingInterest1, ) = cdpManager.getEntireDebtAndColl(cdpId1);
        (debt2, , pendingReward2, pendingInterest2, ) = cdpManager.getEntireDebtAndColl(cdpId2);

        assertGt(pendingInterest1, 0);
        // TODO: Check why loss of precision
        assertApproxEqAbs(debt1, debt2, 1);

        // Realize pending debt
        vm.prank(user1);
        borrowerOperations.addColl{value: 1}(cdpId1, bytes32(0), bytes32(0));

        (debt1, , , pendingInterest1, ) = cdpManager.getEntireDebtAndColl(cdpId1);
        assertEq(pendingInterest1, 0);
        // TODO: Check why loss of precision
        assertApproxEqAbs(debt1, debt2, 1);
    }

    function testInterestIsAppliedOnRedistributedDebt() public {
        vm.prank(user1);
        bytes32 cdpId1 = borrowerOperations.openCdp{value: 100 ether}(
            5e17,
            2000e18,
            bytes32(0),
            bytes32(0)
        );
        vm.prank(user2);
        bytes32 cdpId2 = borrowerOperations.openCdp{value: 100 ether}(
            5e17,
            2000e18,
            bytes32(0),
            bytes32(0)
        );

        // Price falls from 200e18 to 100e18
        priceFeedMock.setPrice(100e18);
    }
}
