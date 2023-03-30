// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.6.0;

import {Auth, Authority} from "./Auth.sol";
import "./EnumerableSet.sol";

/// @notice Role based Authority that supports up to 256 roles.
/// @author BadgerDAO
/// @author Modified from Solmate (https://github.com/transmissions11/solmate/blob/main/src/auth/authorities/RolesAuthority.sol)
/// @author Modified from Dappsys (https://github.com/dapphub/ds-roles/blob/master/src/roles.sol)
contract RolesAuthority is Auth, Authority {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.AddressSet;

    
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event UserRoleUpdated(address indexed user, uint8 indexed role, bool enabled);

    event PublicCapabilityUpdated(address indexed target, bytes4 indexed functionSig, bool enabled);

    event RoleCapabilityUpdated(uint8 indexed role, address indexed target, bytes4 indexed functionSig, bool enabled);

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _owner, Authority _authority) Auth(_owner, _authority) public {}

    /*//////////////////////////////////////////////////////////////
                            ROLE/USER STORAGE
    //////////////////////////////////////////////////////////////*/

    EnumerableSet.AddressSet internal users;
    EnumerableSet.AddressSet internal targets;
    mapping(address => EnumerableSet.Bytes32Set) internal enabledFunctionSigsByTarget;

    EnumerableSet.Bytes32Set internal enabledFunctionSigsPublic;

    mapping(address => bytes32) public getUserRoles;
    
    mapping(address => mapping(bytes4 => bool)) public isCapabilityPublic;

    mapping(address => mapping(bytes4 => bytes32)) public getRolesWithCapability;

    function doesUserHaveRole(address user, uint8 role) public view virtual returns (bool) {
        return (uint256(getUserRoles[user]) >> role) & 1 != 0;
    }

    function doesRoleHaveCapability(
        uint8 role,
        address target,
        bytes4 functionSig
    ) public view virtual returns (bool) {
        return (uint256(getRolesWithCapability[target][functionSig]) >> role) & 1 != 0;
    }

    /*//////////////////////////////////////////////////////////////
                           AUTHORIZATION LOGIC
    //////////////////////////////////////////////////////////////*/

    function canCall(
        address user,
        address target,
        bytes4 functionSig
    ) public view virtual override returns (bool) {
        return
            isCapabilityPublic[target][functionSig] ||
            bytes32(0) != getUserRoles[user] & getRolesWithCapability[target][functionSig];
    }

    /*//////////////////////////////////////////////////////////////
                   ROLE CAPABILITY CONFIGURATION LOGIC
    //////////////////////////////////////////////////////////////*/

    function setPublicCapability(
        address target,
        bytes4 functionSig,
        bool enabled
    ) public virtual requiresAuth {
        isCapabilityPublic[target][functionSig] = enabled;

        emit PublicCapabilityUpdated(target, functionSig, enabled);
    }

    function setRoleCapability(
        uint8 role,
        address target,
        bytes4 functionSig,
        bool enabled
    ) public virtual requiresAuth {
        if (enabled) {
            getRolesWithCapability[target][functionSig] |= bytes32(1 << uint(role));
            enabledFunctionSigsByTarget[target].add(bytes32(functionSig));

            if (!targets.contains(target)) {
                targets.add(target);
            }

        } else {
            getRolesWithCapability[target][functionSig] &= ~bytes32(1 << uint(role));enabledFunctionSigsByTarget[target].remove(bytes32(functionSig));

            // If no enabled function signatures exist for this target, remove target
            if (enabledFunctionSigsByTarget[target].length() == 0) {
                targets.remove(target);
            }
        }

        emit RoleCapabilityUpdated(role, target, functionSig, enabled);
    }

    /*//////////////////////////////////////////////////////////////
                       USER ROLE ASSIGNMENT LOGIC
    //////////////////////////////////////////////////////////////*/

    function setUserRole(
        address user,
        uint8 role,
        bool enabled
    ) public virtual requiresAuth {
        if (enabled) {
            getUserRoles[user] |= bytes32(1 << uint(role));

            if (!users.contains(user)) {
                users.add(user);
            }
        } else {
            getUserRoles[user] &= ~bytes32(1 << uint(role));

            // Remove user if no more roles
            if (getUserRoles[user] == bytes32(0)) {
                users.remove(user);
            } 
        }

        emit UserRoleUpdated(user, role, enabled);
    }
}