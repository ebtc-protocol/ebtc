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
        braindeadFeed.setPrimaryOracle(address(mockOracle));
        vm.stopPrank();
    }

    function testSetSecondaryOracleNoPermission() public {
        address user = _utils.getNextUserAddress();
        PriceFeedTestnet mockOracle = new PriceFeedTestnet(defaultGovernance);

        vm.startPrank(user);
        vm.expectRevert("Auth: UNAUTHORIZED");
        braindeadFeed.setSecondaryOracle(address(mockOracle));
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
            authority.doesRoleHaveCapability(4, address(braindeadFeed), SET_PRIMARY_ORACLE_SIG),
            true
        );

        vm.startPrank(user);
        braindeadFeed.setPrimaryOracle(address(mockOracle));
        vm.stopPrank();

        // Confirm variable set
        assertEq(address(braindeadFeed.primaryOracle()), address(mockOracle));
    }

    function testSetSecondaryOracleWithPermission() public {
        address user = _utils.getNextUserAddress();
        PriceFeedTestnet mockOracle = new PriceFeedTestnet(defaultGovernance);

        // Grant permission
        vm.prank(defaultGovernance);
        authority.setUserRole(user, 4, true);

        assertEq(authority.doesUserHaveRole(user, 4), true);
        assertEq(
            authority.doesRoleHaveCapability(4, address(braindeadFeed), SET_SECONDARY_ORACLE_SIG),
            true
        );

        vm.startPrank(user);
        braindeadFeed.setSecondaryOracle(address(mockOracle));
        vm.stopPrank();

        // Confirm variable set
        assertEq(address(braindeadFeed.secondaryOracle()), address(mockOracle));
    }
}
