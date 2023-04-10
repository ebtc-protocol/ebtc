// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

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

    /*//////////////////////////////////////////////////////////////
                            STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(uint8 => string) internal roleNames;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event RoleNameSet(uint8 indexed role, string indexed name);

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(address _owner) public RolesAuthority(_owner, Authority(address(this))) {}

    /*//////////////////////////////////////////////////////////////
                            GETTERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Convenience function intended for off-chain
    function getUsersByRole(uint8 role) external view returns (address[] memory usersWithRole) {
        // Search over all users: O(n) * 2
        uint count;
        for (uint i = 0; i < users.length(); i++) {
            address user = users.at(i);
            bool _canCall = doesUserHaveRole(user, role);
            if (_canCall) {
                count += 1;
            }
        }
        if (count > 0) {
            uint j = 0;
            usersWithRole = new address[](count);
            for (uint i = 0; i < users.length(); i++) {
                address user = users.at(i);
                bool _canCall = doesUserHaveRole(user, role);
                if (_canCall) {
                    usersWithRole[j] = user;
                    j++;
                }
            }
        }
    }

    function getRolesForUser(address user) external view returns (uint8[] memory rolesForUser) {
        // Enumerate over all possible roles and check if enabled
        uint count;
        for (uint8 i = 0; i < type(uint8).max; i++) {
            if (doesUserHaveRole(user, i)) {
                count += 1;
            }
        }
        if (count > 0) {
            uint j = 0;
            rolesForUser = new uint8[](count);
            for (uint8 i = 0; i < type(uint8).max; i++) {
                if (doesUserHaveRole(user, i)) {
                    rolesForUser[j] = i;
                    j++;
                }
            }
        }
    }

    function getRolesFromByteMap(bytes32 byteMap) public view returns (uint8[] memory roleIds) {
        uint count;
        for (uint8 i = 0; i < type(uint8).max; i++) {
            bool roleEnabled = (uint(byteMap >> i) & 1) != 0;
            if (roleEnabled) {
                count += 1;
            }
        }
        if (count > 0) {
            uint j = 0;
            roleIds = new uint8[](count);
            for (uint8 i = 0; i < type(uint8).max; i++) {
                bool roleEnabled = (uint(byteMap >> i) & 1) != 0;
                if (roleEnabled) {
                    roleIds[j] = i;
                    j++;
                }
            }
        }
    }

    // helper function to generate bytes32 cache data for given roleIds array
    function getByteMapFromRoles(uint8[] memory roleIds) public view returns (bytes32) {
        bytes32 _data;
        for (uint8 i = 0; i < roleIds.length; i++) {
            _data |= bytes32(1 << uint(roleIds[i]));
        }
        return _data;
    }

    /// @notice return all role IDs that have at least one capability enabled
    function getActiveRoles() external view returns (Role[] memory activeRoles) {}

    // If a role exists, flip enabled

    // Return all roles that are enabled anywhere

    function getCapabilitiesForTarget(
        address target
    ) external view returns (Capability[] memory capabilities) {}

    function getCapabilitiesByRole(
        uint8 role
    ) external view returns (Capability[] memory capabilities) {}

    function getRoleName(uint8 role) external view returns (string memory roleName) {
        return roleNames[role];
    }

    /*//////////////////////////////////////////////////////////////
                            AUTHORIZED SETTERS
    //////////////////////////////////////////////////////////////*/

    function setRoleName(uint8 role, string memory roleName) external requiresAuth {
        // TODO: require maximum size for a name
        roleNames[role] = roleName;

        emit RoleNameSet(role, roleName);
    }
}
