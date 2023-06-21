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

    /// @notice The contract constructor initializes RolesAuthority with the given owner.
    /// @param _owner The address of the owner, who gains all permissions by default.
    constructor(address _owner) RolesAuthority(_owner, Authority(address(this))) {}

    /*//////////////////////////////////////////////////////////////
                            GETTERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns a list of users that are assigned a specific role.
    /// @dev This function searches all users and checks if they are assigned the given role.
    /// @dev Intended for off-chain utility only due to inefficiency.
    /// @param role The role ID to find users for.
    /// @return usersWithRole An array of addresses that are assigned the given role.

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
            address[] memory _usrs = users.values();
            for (uint i = 0; i < _usrs.length; i++) {
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

    function getRolesFromByteMap(bytes32 byteMap) public pure returns (uint8[] memory roleIds) {
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
    function getByteMapFromRoles(uint8[] memory roleIds) public pure returns (bytes32) {
        bytes32 _data;
        for (uint8 i = 0; i < roleIds.length; i++) {
            _data |= bytes32(1 << uint(roleIds[i]));
        }
        return _data;
    }

    // helper function to return every authorization-enabled function signatures for given target address
    function getEnabledFunctionsInTarget(
        address _target
    ) public view returns (bytes4[] memory _funcs) {
        bytes32[] memory _sigs = enabledFunctionSigsByTarget[_target].values();
        if (_sigs.length > 0) {
            _funcs = new bytes4[](_sigs.length);
            for (uint i = 0; i < _sigs.length; ++i) {
                _funcs[i] = bytes4(_sigs[i]);
            }
        }
    }

    /// @notice return all role IDs that have at least one capability enabled
    function getActiveRoles() external view returns (Role[] memory activeRoles) {
        revert("Planned off-chain QOL function, not yet implemented, please ignore for audit");
    }

    // If a role exists, flip enabled

    // Return all roles that are enabled anywhere

    function getCapabilitiesForTarget(
        address target
    ) external view returns (Capability[] memory capabilities) {
        revert("Planned off-chain QOL function, not yet implemented, please ignore for audit");
    }

    function getCapabilitiesByRole(
        uint8 role
    ) external view returns (Capability[] memory capabilities) {
        revert("Planned off-chain QOL function, not yet implemented, please ignore for audit");
    }

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
