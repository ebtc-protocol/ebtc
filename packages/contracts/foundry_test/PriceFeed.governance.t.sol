// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "../contracts/Dependencies/EbtcMath.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";
import {PriceFeedTestnet} from "../contracts/TestContracts/testnet/PriceFeedTestnet.sol";

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

    function testSetFallbackCallerNoPermission() public {
        address user = _utils.getNextUserAddress();
        address mockOracle = _utils.getNextUserAddress();

        vm.startPrank(user);
        vm.expectRevert("Auth: UNAUTHORIZED");
        priceFeedMock.setFallbackCaller(mockOracle);
        vm.stopPrank();
    }

    function testSetFallbackCallerWithPermission() public {
        address user = _utils.getNextUserAddress();
        address mockOracle = _utils.getNextUserAddress();

        // Grant permission
        vm.prank(defaultGovernance);
        authority.setUserRole(user, 4, true);

        assertEq(authority.doesUserHaveRole(user, 4), true);
        assertEq(
            authority.doesRoleHaveCapability(4, address(priceFeedMock), SET_FALLBACK_CALLER_SIG),
            true
        );

        //vm.prank(priceFeedMock.owner());
        //priceFeedMock.setAddresses(address(0), address(authority), address(authority));

        vm.startPrank(user);
        priceFeedMock.setFallbackCaller(mockOracle);
        vm.stopPrank();

        // Confirm variable set
        assertEq(address(priceFeedMock.fallbackCaller()), mockOracle);
    }

    function testSetPrimaryOracleNoPermission() public {
        address user = _utils.getNextUserAddress();
        PriceFeedTestnet mockOracle = new PriceFeedTestnet(defaultGovernance);

        vm.startPrank(user);
        vm.expectRevert("Auth: UNAUTHORIZED");
        ebtcFeed.setPrimaryOracle(address(mockOracle));
        vm.stopPrank();
    }

    function testSetSecondaryOracleNoPermission() public {
        address user = _utils.getNextUserAddress();
        PriceFeedTestnet mockOracle = new PriceFeedTestnet(defaultGovernance);

        vm.startPrank(user);
        vm.expectRevert("Auth: UNAUTHORIZED");
        ebtcFeed.setSecondaryOracle(address(mockOracle));
        vm.stopPrank();
    }

    function testSetPrimaryOracleWithPermission() public {
        address user = _utils.getNextUserAddress();
        PriceFeedTestnet mockOracle = new PriceFeedTestnet(defaultGovernance);

        // Grant permission
        vm.prank(defaultGovernance);
        authority.setUserRole(user, 4, true);

        assertEq(authority.doesUserHaveRole(user, 4), true);
        assertEq(
            authority.doesRoleHaveCapability(4, address(ebtcFeed), SET_PRIMARY_ORACLE_SIG),
            true
        );

        vm.startPrank(user);
        ebtcFeed.setPrimaryOracle(address(mockOracle));
        vm.stopPrank();

        // Confirm variable set
        assertEq(address(ebtcFeed.primaryOracle()), address(mockOracle));
    }

    function testSetSecondaryOracleWithPermission() public {
        address user = _utils.getNextUserAddress();
        PriceFeedTestnet mockOracle = new PriceFeedTestnet(defaultGovernance);

        // Grant permission
        vm.prank(defaultGovernance);
        authority.setUserRole(user, 4, true);

        assertEq(authority.doesUserHaveRole(user, 4), true);
        assertEq(
            authority.doesRoleHaveCapability(4, address(ebtcFeed), SET_SECONDARY_ORACLE_SIG),
            true
        );

        vm.startPrank(user);
        ebtcFeed.setSecondaryOracle(address(mockOracle));
        vm.stopPrank();

        // Confirm variable set
        assertEq(address(ebtcFeed.secondaryOracle()), address(mockOracle));
    }

    function testCannotRemovePrimaryOracle() public {
        vm.prank(defaultGovernance);
        vm.expectRevert();
        ebtcFeed.setPrimaryOracle(address(0));
    }

    function testCanRemoveSecondaryOracle() public {
        vm.prank(defaultGovernance);
        ebtcFeed.setSecondaryOracle(address(0));

        assertEq(address(ebtcFeed.secondaryOracle()), address(0));
    }
}
