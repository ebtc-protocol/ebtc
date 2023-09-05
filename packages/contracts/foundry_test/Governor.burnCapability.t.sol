// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;
import "forge-std/Test.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";
import {IRolesAuthority} from "../contracts/Dependencies/IRolesAuthority.sol";

/*
 * Test suite that tests exactly one thing: opening CDPs
 * It tests different cases and also does random testing against random coll amounts and amount of users
 */
contract GovernorBurnCapabilityTest is eBTCBaseFixture {
    mapping(bytes32 => bool) private _cdpIdsExist;

    function setUp() public override {
        eBTCBaseFixture.setUp();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();
    }

    function test_BurnCapability() public {
        vm.startPrank(defaultGovernance);

        IRolesAuthority.CapabilityFlag flag = authority.capabilityFlag(
            address(borrowerOperations),
            SET_FEE_BPS_SIG
        );
        assertEq(uint256(flag), uint256(IRolesAuthority.CapabilityFlag.None));

        // burn
        authority.burnCapability(address(borrowerOperations), SET_FEE_BPS_SIG);

        // confirm burned
        flag = authority.capabilityFlag(address(borrowerOperations), SET_FEE_BPS_SIG);
        assertEq(uint256(flag), uint256(IRolesAuthority.CapabilityFlag.Burned));

        vm.stopPrank();
    }

    function test_CapabilityCannotBeBurnedTwice() public {
        vm.startPrank(defaultGovernance);

        // burn
        authority.burnCapability(address(borrowerOperations), SET_FEE_BPS_SIG);

        // attempt to burn again
        vm.expectRevert("RolesAuthority: Capability Burned");
        authority.burnCapability(address(borrowerOperations), SET_FEE_BPS_SIG);

        vm.stopPrank();
    }

    function test_BurnedCapabilityCannotBeMadePublic() public {
        vm.startPrank(defaultGovernance);

        // burn
        authority.burnCapability(address(borrowerOperations), SET_FEE_BPS_SIG);

        // attempt to make public
        vm.expectRevert("RolesAuthority: Capability Burned");
        authority.setPublicCapability(address(borrowerOperations), SET_FEE_BPS_SIG, true);

        vm.stopPrank();
    }

    function test_BurnedCapabilityCannotBeMadeNone() public {
        vm.startPrank(defaultGovernance);

        // burn
        authority.burnCapability(address(borrowerOperations), SET_FEE_BPS_SIG);

        // attempt to make public
        vm.expectRevert("RolesAuthority: Capability Burned");
        authority.setPublicCapability(address(borrowerOperations), SET_FEE_BPS_SIG, false);

        vm.stopPrank();
    }

    function test_PublicCapabilityCanBeBurned() public {
        vm.startPrank(defaultGovernance);

        // make public
        authority.setPublicCapability(address(borrowerOperations), SET_FEE_BPS_SIG, true);

        // confirm public
        IRolesAuthority.CapabilityFlag flag = authority.capabilityFlag(
            address(borrowerOperations),
            SET_FEE_BPS_SIG
        );
        assertEq(uint256(flag), uint256(IRolesAuthority.CapabilityFlag.Public));

        // burn
        authority.burnCapability(address(borrowerOperations), SET_FEE_BPS_SIG);

        // confirm burned
        flag = authority.capabilityFlag(address(borrowerOperations), SET_FEE_BPS_SIG);
        assertEq(uint256(flag), uint256(IRolesAuthority.CapabilityFlag.Burned));

        vm.stopPrank();
    }

    function test_BurnedCapabilityCannotBeCalledByRoleWithCapability() public {
        // generate user
        address testUser = address(0x1);

        vm.startPrank(defaultGovernance);

        // grant user proper role
        authority.setUserRole(testUser, 5, true);

        // burn
        authority.burnCapability(address(borrowerOperations), SET_FEE_BPS_SIG);
        vm.stopPrank();

        // attempt to call as user with proper role
        assertEq(authority.canCall(testUser, address(borrowerOperations), SET_FEE_BPS_SIG), false);
    }

    function test_BurnedCapabilityCannotBeCalledByRoleWithoutCapability() public {
        // generate user
        address testUser = address(0x1);

        vm.startPrank(defaultGovernance);

        // burn
        authority.burnCapability(address(borrowerOperations), SET_FEE_BPS_SIG);
        vm.stopPrank();

        // attempt to call as user without proper role
        assertEq(authority.canCall(testUser, address(borrowerOperations), SET_FEE_BPS_SIG), false);
    }

    /// Invariant: a capability that is burned should never be able to become unburned.
}
