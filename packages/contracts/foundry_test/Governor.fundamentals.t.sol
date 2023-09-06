// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;
import "forge-std/Test.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";

contract GovernorFundamentalsTest is eBTCBaseFixture {
    uint256 constant TEST_ROLE = 100;

    function setUp() public override {
        eBTCBaseFixture.setUp();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();
    }

    // Setup: Grant capabilities to a specific role, and assign that role to an address
    // Test: The address with the granted role should be able to call the Governor functions
    function test_RoleWithCapabilitiesCanCallGovernorFunctions(uint8 testRole) public {
        address testUser = address(0x1);

        vm.startPrank(defaultGovernance);
        authority.setUserRole(testUser, testRole, true);
        authority.setRoleName(testRole, "TestRole");
        vm.stopPrank();

        _grantAllGovernorCapabilitiesToRole(testRole);
        _testRoleWithCapabilitiesCanCallGovernorFunctions(testUser, testRole);
    }

    // Setup: Assign capabilities for all functions to the contract owner and then renounce ownership
    // Test: The previous owner should still be able to call all Governor functions because of the granted capabilities
    function test_OwnerCanCallAllFunctionsAfterGainingProperCapabilitiesAndRenouncingOwnership(
        uint8 testRole
    ) public {
        vm.startPrank(defaultGovernance);
        authority.setUserRole(defaultGovernance, testRole, true);
        authority.setRoleName(testRole, "TestRole");
        vm.stopPrank();

        _grantAllGovernorCapabilitiesToRole(testRole);

        vm.prank(defaultGovernance);
        authority.transferOwnership(address(0));

        _testRoleWithCapabilitiesCanCallGovernorFunctions(defaultGovernance, testRole);
    }

    // Setup: Assign a few addresses with various roles
    // Test: getUsersByRole should return the expected list of addresses for each role

    function test_GetUsersByRoleReturnsExpected(uint256 usersWithRole) public {
        usersWithRole = bound(usersWithRole, 0, 100);
        uint8 testRole = 50;

        // create users
        address payable[] memory expectedUsers = _utils.createUsers(usersWithRole);

        // grant role to all users
        vm.startPrank(defaultGovernance);
        for (uint256 i = 0; i < expectedUsers.length; i++) {
            authority.setUserRole(expectedUsers[i], testRole, true);
        }
        vm.stopPrank();

        address[] memory actualUsers = authority.getUsersByRole(testRole);

        assertEq(actualUsers.length, expectedUsers.length, "Returned users length mismatch");

        for (uint256 i = 0; i < expectedUsers.length; i++) {
            assertEq(actualUsers[i], address(expectedUsers[i]), "Returned user address mismatch");
        }
    }

    // Setup: Assign a few addresses with various roles, then add and remove users
    // Test: getUsersByRole should return the updated list of addresses for each role after additions and removals
    function test_GetUsersByRoleReturnsExpectedAfterAddingAndRemovingUsers(
        uint256 usersWithRole
    ) public {
        // usersWithRole = bound(0, usersWithRole, 100);
        // uint8 testRole = 50;
        // // create users
        // address payable[] memory expectedUsers = _utils.createUsers(usersWithRole);
        // // grant role to all users
        // vm.startPrank(defaultGovernance);
        // for (uint256 i = 0; i < expectedUsers.length; i++) {
        //     authority.setUserRole(expectedUsers[i], testRole, true);
        // }
        // vm.stopPrank();
        // // remove role from some users
        // // generate random value between expectedUsers - 1 and 0
        // uint256 usersToRemove = 0;
        // uint256 numUsersExpected = expectedUsers.length - usersToRemove;
        // // accumulate users that should have been removed into a new list
        // // create list of users that remain
        // address[] memory actualUsers = authority.getUsersByRole(testRole);
        // assertEq(actualUsers.length, expectedUsers.length - usersToRemove, "Returned users length mismatch");
        // // assert each user that was removed is not in the actual list
        // // asert each user that was not removed is in the actual list
        // for (uint256 i = 0; i < actualUsers.length; i++) {
        //     assertEq(actualUsers[i], expectedUsers[i], "Returned user address mismatch");
        // }
    }

    // Setup: Enable a few functions for a specific target address
    // Test: getEnabledFunctionsInTarget should return the expected list of function signatures
    function test_GetEnabledFunctionsInTargetReturnsExpected() public {
        // bytes4[] memory expectedFuncs = new bytes4[](1);
        // expectedFuncs[0] = bytes4(keccak256("setRoleName(uint8,string)"));
        // authority.setRoleCapability(address(authority), expectedFuncs[0], 1);
        // bytes4[] memory funcs = authority.getEnabledFunctionsInTarget(address(authority));
        // assertEq(funcs.length, expectedFuncs.length, "Returned function signatures length mismatch");
    }

    function test_GetEnabledFunctionsInTargetReturnsExpectedAfterAddingAndRemovingFunctions()
        public
    {}

    /// @dev Helper function to grant all Governor setter capabilities to a specific role
    /// @dev Assumes default governance still has ownerships
    function _grantAllGovernorCapabilitiesToRole(uint8 role) internal {
        vm.startPrank(defaultGovernance);

        // List of all setter function signatures in Governor contract
        bytes4[] memory funcSigs = new bytes4[](7);
        funcSigs[0] = bytes4(keccak256("setRoleName(uint8,string)"));
        funcSigs[1] = bytes4(keccak256("setUserRole(address,uint8,bool)"));
        funcSigs[2] = bytes4(keccak256("setRoleCapability(uint8,address,bytes4,bool)"));
        funcSigs[4] = bytes4(keccak256("setPublicCapability(address,bytes4,bool)"));
        funcSigs[6] = bytes4(keccak256("burnCapability(address,bytes4)"));

        // Grant testRole all setter capabilities on authority
        for (uint256 i = 0; i < funcSigs.length; i++) {
            authority.setRoleCapability(role, address(authority), funcSigs[i], true);
        }

        vm.stopPrank();
    }

    function _testRoleWithCapabilitiesCanCallGovernorFunctions(
        address testUser,
        uint8 testRole
    ) internal {
        vm.startPrank(testUser);

        // setRoleName
        authority.setRoleName(testRole, "NewTestRole"); // This should succeed
        string memory updatedRoleName = authority.getRoleName(testRole);
        assertEq(updatedRoleName, "NewTestRole", "Role name should have been updated");

        // setUserRole
        address newUser = address(0x2);
        authority.setUserRole(newUser, testRole, true); // This should succeed
        assertEq(
            authority.doesUserHaveRole(newUser, testRole),
            true,
            "New user should have the testRole"
        );

        // setRoleCapability
        bytes4 newFuncSig = bytes4(keccak256("newFunctionSignature()"));
        authority.setRoleCapability(testRole, address(authority), newFuncSig, true); // This should succeed
        assertEq(
            authority.canCall(testUser, address(authority), newFuncSig),
            true,
            "TestRole should have the new capability"
        );

        // setPublicCapability true
        authority.setPublicCapability(address(authority), newFuncSig, true); // This should succeed
        assertEq(
            authority.isPublicCapability(address(authority), newFuncSig),
            true,
            "New function signature should be public"
        );

        // setPublicCapability false
        authority.setPublicCapability(address(authority), newFuncSig, false); // This should succeed
        assertEq(
            authority.isPublicCapability(address(authority), newFuncSig),
            false,
            "New function signature should not be public"
        );

        vm.stopPrank();
    }
}
