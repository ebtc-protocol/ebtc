// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {eBTCBaseInvariants} from "./BaseInvariants.sol";

contract CloseLastCdpTest is eBTCBaseInvariants {
    uint public constant OPEN_COLL_SHARES = 10 ether;
    uint public constant OPEN_DEBT = 5 ether;

    function setUp() public override {
        super.setUp();

        connectCoreContracts();
        connectLQTYContractsToCore();

        priceFeedMock.setPrice(1 ether);
    }

    function test_CloseLastCdpRevertsByRedemption() public {
        address user = _utils.getNextUserAddress();
        address marketActor = _utils.getNextUserAddress();

        // open one CDP
        bytes32 userCdpId = _openTestCDP(user, OPEN_COLL_SHARES, OPEN_DEBT);

        vm.prank(user);
        eBTCToken.transfer(marketActor, OPEN_DEBT);

        // make redemptions available
        vm.warp(3 weeks);

        // expect revert on close
        assertTrue(eBTCToken.balanceOf(marketActor) >= OPEN_DEBT);
        vm.prank(marketActor);
        vm.expectRevert("CdpManager: Zero Cdps remain in the system");
        cdpManager.redeemCollateral(
            OPEN_DEBT,
            bytes32(0),
            bytes32(0),
            bytes32(0),
            0,
            0,
            DECIMAL_PRECISION
        );

        assertTrue(cdpManager.getActiveCdpsCount() == 1);

        _ensureSystemInvariants();
    }

    function test_CloseLastCdpRevertsByLiquidation() public {
        address user = _utils.getNextUserAddress();
        address marketActor = _utils.getNextUserAddress();

        // open one CDP
        bytes32 userCdpId = _openTestCDP(user, OPEN_COLL_SHARES, OPEN_DEBT);

        // make liquidatable
        priceFeedMock.setPrice(0.5 ether);

        // expect revert on close
        vm.prank(marketActor);
        vm.expectRevert("CdpManager: Zero Cdps remain in the system");
        cdpManager.liquidate(userCdpId);

        _ensureSystemInvariants();
    }

    function test_CloseLastCdpRevertsByOwner() public {
        address user = _utils.getNextUserAddress();

        // open one CDP
        bytes32 userCdpId = _openTestCDP(user, OPEN_COLL_SHARES, OPEN_DEBT);

        // expect revert on close
        vm.prank(user);
        vm.expectRevert("CdpManager: Zero Cdps remain in the system");
        borrowerOperations.closeCdp(userCdpId);

        _ensureSystemInvariants();
    }

    function test_CloseLastCdpRevertsByRedemptionAfterMultipleSequentialCloses() public {
        address user = _utils.getNextUserAddress();
        address marketActor = _utils.getNextUserAddress();
        address closer = _utils.getNextUserAddress();

        // open Cdp before
        bytes32 beforeId = _openTestCDP(closer, OPEN_COLL_SHARES, OPEN_DEBT);

        // open one Cdp
        bytes32 userCdpId = _openTestCDP(user, OPEN_COLL_SHARES, OPEN_DEBT);

        // open Cdp after
        bytes32 afterId = _openTestCDP(closer, OPEN_COLL_SHARES, OPEN_DEBT);

        // close other Cdps
        vm.startPrank(closer);
        borrowerOperations.closeCdp(beforeId);
        borrowerOperations.closeCdp(afterId);
        vm.stopPrank();

        vm.prank(user);
        eBTCToken.transfer(marketActor, OPEN_DEBT);

        // make redemptions available
        vm.warp(3 weeks);

        // expect revert on close
        assertTrue(eBTCToken.balanceOf(marketActor) >= OPEN_DEBT);
        vm.prank(marketActor);
        vm.expectRevert("CdpManager: Zero Cdps remain in the system");
        cdpManager.redeemCollateral(
            OPEN_DEBT,
            bytes32(0),
            bytes32(0),
            bytes32(0),
            0,
            0,
            DECIMAL_PRECISION
        );

        assertTrue(cdpManager.getActiveCdpsCount() == 1);
        _ensureSystemInvariants();
    }

    function test_CloseLastCdpRevertsByLiquidationsAfterMultipleSequentialCloses() public {
        address user = _utils.getNextUserAddress();
        address marketActor = _utils.getNextUserAddress();
        address closer = _utils.getNextUserAddress();

        // open Cdp before
        bytes32 beforeId = _openTestCDP(closer, OPEN_COLL_SHARES, OPEN_DEBT);

        // open one Cdp
        bytes32 userCdpId = _openTestCDP(user, OPEN_COLL_SHARES, OPEN_DEBT);

        // open Cdp after
        bytes32 afterId = _openTestCDP(closer, OPEN_COLL_SHARES, OPEN_DEBT);

        // close other Cdps
        vm.startPrank(closer);
        borrowerOperations.closeCdp(beforeId);
        borrowerOperations.closeCdp(afterId);
        vm.stopPrank();

        // make liquidatable
        priceFeedMock.setPrice(0.5 ether);

        // expect revert on close
        vm.prank(marketActor);
        vm.expectRevert("CdpManager: Zero Cdps remain in the system");
        cdpManager.liquidate(userCdpId);

        _ensureSystemInvariants();
    }

    function test_CloseLastCdpRevertsByOwnerAfterMultipleSequentialCloses() public {
        address user = _utils.getNextUserAddress();
        address marketActor = _utils.getNextUserAddress();
        address closer = _utils.getNextUserAddress();

        // open Cdp before
        bytes32 beforeId = _openTestCDP(closer, OPEN_COLL_SHARES, OPEN_DEBT);

        // open one Cdp
        bytes32 userCdpId = _openTestCDP(user, OPEN_COLL_SHARES, OPEN_DEBT);

        // open Cdp after
        bytes32 afterId = _openTestCDP(closer, OPEN_COLL_SHARES, OPEN_DEBT);

        // close other Cdps
        vm.startPrank(closer);
        borrowerOperations.closeCdp(beforeId);
        borrowerOperations.closeCdp(afterId);
        vm.stopPrank();

        // expect revert on close
        vm.prank(user);
        vm.expectRevert("CdpManager: Zero Cdps remain in the system");
        borrowerOperations.closeCdp(userCdpId);

        _ensureSystemInvariants();
    }
}
