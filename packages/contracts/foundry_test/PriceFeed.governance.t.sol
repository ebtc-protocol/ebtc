// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;
import "forge-std/Test.sol";
import "../contracts/Dependencies/LiquityMath.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";

/*
    Test governance around swapping the backup price feed
 */
contract PriceFeedGovernanceTest is eBTCBaseFixture {

    function setUp() public override {
        eBTCBaseFixture.setUp();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();
    }

    // -------- eBTC Minting governance cases --------

    function testSetTellorCallerNoPermission() public {
        address user = _utils.getNextUserAddress();
        address mockOracle = _utils.getNextUserAddress();

        vm.startPrank(user);
        vm.expectRevert("PriceFeed: sender not authorized for setTellorCaller(address)");
        priceFeedMock.setTellorCaller(mockOracle);
        vm.stopPrank();
    }

    function testSetTellorCallerWithPermission() public {
        address user = _utils.getNextUserAddress();
        address mockOracle = _utils.getNextUserAddress();

        // Grant permission
        vm.prank(defaultGovernance);
        authority.setUserRole(user, 4, true);

        assertEq(authority.doesUserHaveRole(user, 4), true);
        assertEq(authority.doesRoleHaveCapability(4, address(priceFeedMock), SET_TELLOR_CALLER_SIG), true);

        vm.startPrank(user);
        priceFeedMock.setTellorCaller(mockOracle);
        vm.stopPrank();

        // Confirm variable set
        assertEq(address(priceFeedMock.tellorCaller()), mockOracle);
    }
}
