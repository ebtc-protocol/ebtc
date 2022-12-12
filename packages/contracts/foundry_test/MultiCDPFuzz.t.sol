// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.11;

import "forge-std/Test.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";


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
//    function testCdpsAmounts(uint8 cdpAmount) public {
//        for (uint i = 0; i < cdpAmount; i++) {
//            vm.prank(user);
//            borrowerOperations.openCdp{value : address(user).balance}(
//                5e17,
//                170e20,
//                "some hint",
//                "some hint"
//            );
//        }
//    }
}