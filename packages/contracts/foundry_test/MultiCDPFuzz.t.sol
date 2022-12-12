// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.11;

import "forge-std/Test.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";
import {Utilities} from "./utils/Utilities.sol";

contract CDPTest is eBTCBaseFixture {
    uint256 private testNumber;
    Utilities internal utils;

    function setUp() public override {
        eBTCBaseFixture.setUp();
        eBTCBaseFixture.connectLQTYContracts();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();
        user = msg.sender;
        utils = new Utilities();
    }
    /* Open CDPs for fuzzed amount of users
    BorrowedAmount is calculated as: (Collateral * eBTC Price) / CR
    */
    function testCdpsForManyUsers(uint8 amountUsers) public {
        // Skip case when amount of Users is 0
        vm.assume(amountUsers > 1);

        // Populate users
        address payable[] memory users;
        users = utils.createUsers(amountUsers);

        uint collateral = 30 ether;
        uint collateralRatio = 160e16;  // 160% take higher CR as CCR is 150%
        uint borrowedAmount = collateral.mul(priceFeedMock.fetchPrice()).div(collateralRatio);
        // Iterate thru all users and open CDP for each of them
        for (uint userIx = 0; userIx < users.length; userIx++) {
            vm.deal(users[userIx], 300 ether);
            vm.prank(users[userIx]);
            borrowerOperations.openCdp{value : collateral}(
                5e17,
                borrowedAmount,
                "some hint",
                "some hint"
            );
            // Make sure that each user has now CDP opened
            assertEq(sortedCdps.cdpCountOf(users[userIx]), 1);
        }
        // Make sure amount of SortedCDPs equals to `amountUsers`
        assertEq(sortedCdps.getSize(), amountUsers);
    }
}
