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

    // Test: The address with the granted roles should be able to retrieve all roles
    function test_RolesRetrievalWithMaxAllowed() public {
        address testUser = address(0x1);

        vm.startPrank(defaultGovernance);
        for (uint8 i = 0; i <= type(uint8).max; ) {
            authority.setUserRole(testUser, i, true);
            authority.setRoleName(i, "TestRole");
            if (i < type(uint8).max) {
                i = i + 1;
            } else {
                break;
            }
        }
        vm.stopPrank();

        uint8[] memory rolesForUser = authority.getRolesForUser(testUser);
        for (uint8 i = 0; i <= type(uint8).max; ) {
            assertEq(rolesForUser[i], i, "!retrieved role msimatch");
            if (i < type(uint8).max) {
                i = i + 1;
            } else {
                break;
            }
        }
    }

    // Test: The address with the granted roles should be able to retrieve all roles via bitmap
    function test_RolesRetrievalWithMaxAllowedViaMap() public {
        uint8[] memory rolesForMapGiven = new uint8[](256);
        vm.startPrank(defaultGovernance);
        for (uint8 i = 0; i <= type(uint8).max; ) {
            authority.setRoleName(i, "TestRole");
            rolesForMapGiven[i] = i;
            if (i < type(uint8).max) {
                i = i + 1;
            } else {
                break;
            }
        }
        vm.stopPrank();

        bytes32 _roleMap = authority.getByteMapFromRoles(rolesForMapGiven);
        uint8[] memory rolesForMap = authority.getRolesFromByteMap(_roleMap);
        for (uint8 i = 0; i <= type(uint8).max; ) {
            assertEq(rolesForMap[i], i, "!retrieved role msimatch");
            if (i < type(uint8).max) {
                i = i + 1;
            } else {
                break;
            }
        }
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

    function test_GetEnabledFunctionsInTargetReturnsExpectedAfterRoleModification() public {
        // set all capabilities to two roles
        _grantAllGovernorCapabilitiesToRole(1);
        _grantAllGovernorCapabilitiesToRole(2);

        // retrieve all funcs enabled
        bytes4[] memory funcSigsOriginal = authority.getEnabledFunctionsInTarget(address(authority));
        bytes4 _firstFunc = bytes4(keccak256("setRoleName(uint8,string)"));
        bytes4 _lastFunc = bytes4(keccak256("burnCapability(address,bytes4)"));
        assertEq(funcSigsOriginal[0], _firstFunc, "!mismatch first enabled function sig");

        // now revoke capability from one role
        vm.startPrank(defaultGovernance);
        authority.setRoleCapability(1, address(authority), _firstFunc, false);
        vm.stopPrank();

        // check again the function, should still enabled since there is a second role 2 could call
        bytes4[] memory funcSigsAgain = authority.getEnabledFunctionsInTarget(address(authority));
        assertEq(funcSigsAgain[0], _firstFunc, "!!mismatch first enabled function sig");
        assertEq(funcSigsAgain.length, funcSigsOriginal.length, "!!mismatch enabled function count");

        // now revoke capability from the second role
        vm.startPrank(defaultGovernance);
        authority.setRoleCapability(2, address(authority), _firstFunc, false);
        vm.stopPrank();

        // check again the function, should disabled since there is no role could call
        bytes4[] memory funcSigsLast = authority.getEnabledFunctionsInTarget(address(authority));
        assertEq(funcSigsLast[0], _lastFunc, "!!!mismatch first enabled function sig");
        assertEq(
            funcSigsLast.length,
            funcSigsOriginal.length - 1,
            "!!!mismatch enabled function count"
        );
    }

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
