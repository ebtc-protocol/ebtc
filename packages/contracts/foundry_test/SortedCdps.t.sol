// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.11;

import "forge-std/Test.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";
import {Utilities} from "./utils/Utilities.sol";


contract CDPOpsTest is eBTCBaseFixture {
    Utilities internal _utils;

    function setUp() public override {
        eBTCBaseFixture.setUp();
        eBTCBaseFixture.connectLQTYContracts();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();
        _utils = new Utilities();
    }

    function testGetCdpsOfUser() public {
        uint collAmount = 30 ether;
        address user = _utils.getNextUserAddress();
        vm.startPrank(user);
        vm.deal(user, type(uint96).max);
        uint borrowedAmount = _utils.calculateBorrowAmount(
            collAmount,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );
        // Open X amount of CDPs
        for (uint cdpIx = 0; cdpIx < AMOUNT_OF_CDPS; cdpIx++) {
            borrowerOperations.openCdp{value: collAmount}(FEE, borrowedAmount, HINT, HINT);
        }
        vm.stopPrank();
        bytes32[] memory cdps = sortedCdps.getCdpsOf(user);
        for (uint cdpIx = 0; cdpIx < AMOUNT_OF_CDPS; cdpIx++) {
            bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, cdpIx);
            bytes32 cdp = cdps[cdpIx];
            assertEq(cdp, cdpId);
        }
    }

    // Make sure if user didn't open CDP, cdps array is empty
    function testGetCdpsOfUserDoesNotExist() public {
        address user = _utils.getNextUserAddress();
        bytes32[] memory cdps = sortedCdps.getCdpsOf(user);
        assertEq(0, cdps.length);
    }

    // Keep amntOfCdps reasonable, as it will eat all the memory
    // Change to fuzzed uint16 with caution, as it can consume > 10Gb of Memory
    function testGetCdpsOfUserFuzz(uint8 amntOfCdps) public {
        uint collAmount = 30 ether;
        address user = _utils.getNextUserAddress();
        vm.startPrank(user);
        vm.deal(user, type(uint96).max);
        uint borrowedAmount = _utils.calculateBorrowAmount(
            collAmount,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );
        // Open X amount of CDPs
        for (uint cdpIx = 0; cdpIx < amntOfCdps; cdpIx++) {
            borrowerOperations.openCdp{value: collAmount}(FEE, borrowedAmount, HINT, HINT);
        }
        vm.stopPrank();
        bytes32[] memory cdps = sortedCdps.getCdpsOf(user);
        // And check that amount of CDPs as expected
        assertEq(amntOfCdps, cdps.length);
    }
}