// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";
import {Properties} from "../contracts/TestContracts/invariants/Properties.sol";

contract CDPOpsTest is eBTCBaseFixture, Properties {
    function setUp() public override {
        eBTCBaseFixture.setUp();

        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();
    }

    function testGetCdpsOfUser() public {
        uint collAmount = 30 ether;
        address user = _utils.getNextUserAddress();
        vm.startPrank(user);
        vm.deal(user, type(uint96).max);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 10000 ether}();
        uint borrowedAmount = _utils.calculateBorrowAmount(
            collAmount,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );
        // Open X amount of CDPs
        for (uint cdpIx = 0; cdpIx < AMOUNT_OF_CDPS; cdpIx++) {
            borrowerOperations.openCdp(borrowedAmount, HINT, HINT, collAmount);
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
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 10000 ether}();
        uint borrowedAmount = _utils.calculateBorrowAmount(
            collAmount,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );
        // Open X amount of CDPs
        for (uint cdpIx = 0; cdpIx < amntOfCdps; cdpIx++) {
            borrowerOperations.openCdp(borrowedAmount, HINT, HINT, collAmount);
        }
        vm.stopPrank();
        bytes32[] memory cdps = sortedCdps.getCdpsOf(user);
        // And check that amount of CDPs as expected
        assertEq(amntOfCdps, cdps.length);
        for (uint cdpIx = 0; cdpIx < amntOfCdps; cdpIx++) {
            bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, cdpIx);
            bytes32 cdp = cdps[cdpIx];
            assertEq(cdp, cdpId);
        }
    }

    function testSortedCdpsInvariants() public {
        uint256 coll = borrowerOperations.MIN_NET_COLL() + borrowerOperations.LIQUIDATOR_REWARD() + 16;

        address user = _utils.getNextUserAddress();
        vm.startPrank(user);
        vm.deal(user, type(uint96).max);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: coll * 2}();

        borrowerOperations.openCdp(1, HINT, HINT, coll);
        borrowerOperations.openCdp(1, HINT, HINT, coll);
        collateral.setEthPerShare(collateral.getEthPerShare() * 1 ether / 1.1 ether);

        emit log_uint(cdpManager.getTCR(priceFeedMock.getPrice()));
        emit log_uint(cdpManager.getCurrentICR(sortedCdps.getFirst(), priceFeedMock.getPrice()));
        emit log_uint(cdpManager.getCdpColl(sortedCdps.getFirst()));

        assertTrue(invariant_SL_01(cdpManager, sortedCdps), "SL-01");
        assertTrue(invariant_SL_02(cdpManager, sortedCdps, priceFeedMock), "SL-02");
    }
}
