// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.11;

import "forge-std/Test.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";
import {Utilities} from "./utils/Utilities.sol";

contract CDPTest is eBTCBaseFixture {
    uint256 private testNumber;
    address user;
    Utilities internal utils;
    address payable[] internal users;

    function setUp() public override {
        eBTCBaseFixture.setUp();
        eBTCBaseFixture.connectLQTYContracts();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();
        user = msg.sender;
        utils = new Utilities();
    }

    /* Open CDPs for fuzzed amount of users
    */
    function testCdpsForManyUsers(uint8 amountUsers) public {
        users = utils.createUsers(amountUsers);
        uint collateral = 30 ether;
        // Iterate thru all users and open CDP for each of them
        for (uint userIx = 0; userIx < users.length; userIx++) {
            vm.deal(users[userIx], 300 ether);
            vm.prank(users[userIx]);
            borrowerOperations.openCdp{value : collateral}(
                5e17,
                // TODO: Minted eBTC value should change as we will use another CL for btc/eth prices
                1800e18,
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