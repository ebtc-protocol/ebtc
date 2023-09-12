// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";

contract CDPOpsTest is eBTCBaseFixture {
    function setUp() public override {
        eBTCBaseFixture.setUp();

        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();
    }

    function testGetCdpsOfUser() public {
        uint256 collAmount = 30 ether;
        address user = _utils.getNextUserAddress();
        vm.startPrank(user);
        vm.deal(user, type(uint96).max);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 10000 ether}();
        uint256 borrowedAmount = _utils.calculateBorrowAmount(
            collAmount,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );
        // Open X amount of CDPs
        for (uint256 cdpIx = 0; cdpIx < AMOUNT_OF_CDPS; cdpIx++) {
            borrowerOperations.openCdp(borrowedAmount, HINT, HINT, collAmount);
        }
        vm.stopPrank();
        bytes32[] memory cdps = sortedCdps.getCdpsOf(user);
        bytes32[] memory cdpsByMaxNode = sortedCdps.getCdpsOf(
            user,
            sortedCdps.dummyId(),
            AMOUNT_OF_CDPS
        );
        bytes32[] memory cdpsByStartNode = sortedCdps.getCdpsOf(
            user,
            sortedCdps.getLast(),
            AMOUNT_OF_CDPS
        );
        for (uint256 cdpIx = 0; cdpIx < AMOUNT_OF_CDPS; cdpIx++) {
            bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, cdpIx);
            bytes32 _cdpId = sortedCdps.cdpOfOwnerByIdx(user, 0, cdpId, 1);
            assertEq(_cdpId, cdpId);
            assertEq(cdps[cdpIx], cdpId);
            assertEq(cdpsByMaxNode[cdpIx], cdpId);
            assertEq(cdpsByStartNode[cdpIx], cdpId);
        }
        // check count of CDP owned by the user
        uint _cdpCountOf = sortedCdps.cdpCountOf(user);
        uint _cdpCountOfByMaxNode = sortedCdps.cdpCountOf(
            user,
            sortedCdps.dummyId(),
            AMOUNT_OF_CDPS
        );
        uint _cdpCountOfByStartNode = sortedCdps.cdpCountOf(
            user,
            sortedCdps.getLast(),
            AMOUNT_OF_CDPS
        );
        assertEq(_cdpCountOf, AMOUNT_OF_CDPS);
        assertEq(_cdpCountOfByMaxNode, AMOUNT_OF_CDPS);
        assertEq(_cdpCountOfByStartNode, AMOUNT_OF_CDPS);
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
        uint256 collAmount = 30 ether;
        address user = _utils.getNextUserAddress();
        vm.startPrank(user);
        vm.deal(user, type(uint96).max);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 10000 ether}();
        uint256 borrowedAmount = _utils.calculateBorrowAmount(
            collAmount,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );
        // Open X amount of CDPs
        for (uint256 cdpIx = 0; cdpIx < amntOfCdps; cdpIx++) {
            borrowerOperations.openCdp(borrowedAmount, HINT, HINT, collAmount);
        }
        vm.stopPrank();
        bytes32[] memory cdps = sortedCdps.getCdpsOf(user);
        // And check that amount of CDPs as expected
        assertEq(amntOfCdps, cdps.length);
        for (uint256 cdpIx = 0; cdpIx < amntOfCdps; cdpIx++) {
            bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, cdpIx);
            bytes32 cdp = cdps[cdpIx];
            assertEq(cdp, cdpId);
        }
    }
}
