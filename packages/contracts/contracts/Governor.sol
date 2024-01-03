// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {EnumerableSet} from "./Dependencies/EnumerableSet.sol";
import {Authority} from "./Dependencies/Auth.sol";
import {RolesAuthority} from "./Dependencies/RolesAuthority.sol";

/// @notice Role based Authority that supports up to 256 roles.
/// @notice We have taken the tradeoff of additional storage usage for easier readabiliy without using off-chain / indexing services.
/// @author BadgerDAO Expanded from Solmate RolesAuthority
/// @author Modified from Solmate (https://github.com/transmissions11/solmate/blob/main/src/auth/authorities/RolesAuthority.sol)
/// @author Modified from Dappsys (https://github.com/dapphub/ds-roles/blob/master/src/roles.sol)
contract Governor is RolesAuthority {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 NO_ROLES = bytes32(0);

    struct Role {
        uint8 roleId;
        string roleName;
    }

    struct Capability {
        address target;
        bytes4 functionSig;
        uint8[] roles;
    }

    mapping(uint8 => string) internal roleNames;

    event RoleNameSet(uint8 indexed role, string indexed name);

    /// @notice The contract constructor initializes RolesAuthority with the given owner.
    /// @param _owner The address of the owner, who gains all permissions by default.
    constructor(address _owner) RolesAuthority(_owner, Authority(address(this))) {}

    /// @notice Returns a list of users that are assigned a specific role.
    /// @dev This function searches all users and checks if they are assigned the given role.
    /// @dev Intended for off-chain utility only due to inefficiency.
    /// @param role The role ID to find users for.
    /// @return usersWithRole An array of addresses that are assigned the given role.
    function getUsersByRole(uint8 role) external view returns (address[] memory usersWithRole) {
        // Search over all users: O(n) * 2
        uint256 count;
        for (uint256 i = 0; i < users.length(); i++) {
            address user = users.at(i);
            bool _canCall = doesUserHaveRole(user, role);
            if (_canCall) {
                count += 1;
            }
        }
        if (count > 0) {
            uint256 j = 0;
            usersWithRole = new address[](count);
            address[] memory _usrs = users.values();
            for (uint256 i = 0; i < _usrs.length; i++) {
                address user = _usrs[i];
                bool _canCall = doesUserHaveRole(user, role);
                if (_canCall) {
                    usersWithRole[j] = user;
                    j++;
                }
            }
        }
    }

    /// @notice Returns a list of roles that an address has.
    /// @dev This function searches all roles and checks if they are assigned to the given user.
    /// @dev Intended for off-chain utility only due to inefficiency.
    /// @param user The address of the user.
    /// @return rolesForUser An array of role IDs that the user has.
    function getRolesForUser(address user) external view returns (uint8[] memory rolesForUser) {
        // Enumerate over all possible roles and check if enabled
        uint256 count;
        for (uint8 i = 0; i <= type(uint8).max; ) {
            if (doesUserHaveRole(user, i)) {
                count += 1;
            }
            if (i < type(uint8).max) {
                i = i + 1;
            } else {
                break;
            }
        }
        if (count > 0) {
            uint256 j = 0;
            rolesForUser = new uint8[](count);
            for (uint8 i = 0; i <= type(uint8).max; ) {
                if (doesUserHaveRole(user, i)) {
                    rolesForUser[j] = i;
                    j++;
                }
                if (i < type(uint8).max) {
                    i = i + 1;
                } else {
                    break;
                }
            }
        }
    }

    /// @notice Converts a byte map representation to an array of role IDs.
    /// @param byteMap The bytes32 value encoding the roles.
    /// @return roleIds An array of role IDs extracted from the byte map.
    function getRolesFromByteMap(bytes32 byteMap) public pure returns (uint8[] memory roleIds) {
        uint256 count;
        for (uint8 i = 0; i <= type(uint8).max; ) {
            bool roleEnabled = (uint256(byteMap >> i) & 1) != 0;
            if (roleEnabled) {
                count += 1;
            }
            if (i < type(uint8).max) {
                i = i + 1;
            } else {
                break;
            }
        }
        if (count > 0) {
            uint256 j = 0;
            roleIds = new uint8[](count);
            for (uint8 i = 0; i <= type(uint8).max; ) {
                bool roleEnabled = (uint256(byteMap >> i) & 1) != 0;
                if (roleEnabled) {
                    roleIds[j] = i;
                    j++;
                }
                if (i < type(uint8).max) {
                    i = i + 1;
                } else {
                    break;
                }
            }
        }
    }

    /// @notice Converts an array of role IDs to a byte map representation.
    /// @param roleIds An array of role IDs.
    /// @return A bytes32 value encoding the roles.
    function getByteMapFromRoles(uint8[] memory roleIds) public pure returns (bytes32) {
        bytes32 _data;
        for (uint256 i = 0; i < roleIds.length; i++) {
            _data |= bytes32(1 << uint256(roleIds[i]));
        }
        return _data;
    }

    /// @notice Retrieves all function signatures enabled for a target address.
    /// @param _target The target contract address.
    /// @return _funcs An array of function signatures enabled for the target.
    function getEnabledFunctionsInTarget(
        address _target
    ) public view returns (bytes4[] memory _funcs) {
        bytes32[] memory _sigs = enabledFunctionSigsByTarget[_target].values();
        if (_sigs.length > 0) {
            _funcs = new bytes4[](_sigs.length);
            for (uint256 i = 0; i < _sigs.length; ++i) {
                _funcs[i] = bytes4(_sigs[i]);
            }
        }
    }

    /// @notice Retrieves the name associated with a role ID
    /// @param role The role ID
    /// @return roleName The name of the role
    function getRoleName(uint8 role) external view returns (string memory roleName) {
        return roleNames[role];
    }

    /// @notice Sets the name for a specific role ID for better readability
    /// @dev This function requires authorization
    /// @param role The role ID
    /// @param roleName The name to assign to the role
    function setRoleName(uint8 role, string memory roleName) external requiresAuth {
        roleNames[role] = roleName;

        emit RoleNameSet(role, roleName);
    }
}
