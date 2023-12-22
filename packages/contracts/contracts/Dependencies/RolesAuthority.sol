// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {IRolesAuthority} from "./IRolesAuthority.sol";
import {Auth, Authority} from "./Auth.sol";
import "./EnumerableSet.sol";

/// @notice Role based Authority that supports up to 256 roles.
/// @author BadgerDAO
/// @author Modified from Solmate (https://github.com/transmissions11/solmate/blob/main/src/auth/authorities/RolesAuthority.sol)
/// @author Modified from Dappsys (https://github.com/dapphub/ds-roles/blob/master/src/roles.sol)
contract RolesAuthority is IRolesAuthority, Auth, Authority {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.AddressSet;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _owner, Authority _authority) Auth(_owner, _authority) {}

    /*//////////////////////////////////////////////////////////////
                            ROLE/USER STORAGE
    //////////////////////////////////////////////////////////////*/

    EnumerableSet.AddressSet internal users;
    EnumerableSet.AddressSet internal targets;
    mapping(address => EnumerableSet.Bytes32Set) internal enabledFunctionSigsByTarget;

    EnumerableSet.Bytes32Set internal enabledFunctionSigsPublic;

    mapping(address => bytes32) public getUserRoles;

    mapping(address => mapping(bytes4 => CapabilityFlag)) public capabilityFlag;

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

    function isPublicCapability(address target, bytes4 functionSig) public view returns (bool) {
        return capabilityFlag[target][functionSig] == CapabilityFlag.Public;
    }

    /*//////////////////////////////////////////////////////////////
                           AUTHORIZATION LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
        @notice A user can call a given function signature on a given target address if:
            - The capability has not been burned
            - That capability is public, or the user has a role that has been granted the capability to call the function
     */
    function canCall(
        address user,
        address target,
        bytes4 functionSig
    ) public view virtual override returns (bool) {
        CapabilityFlag flag = capabilityFlag[target][functionSig];

        if (flag == CapabilityFlag.Burned) {
            return false;
        } else if (flag == CapabilityFlag.Public) {
            return true;
        } else {
            return bytes32(0) != getUserRoles[user] & getRolesWithCapability[target][functionSig];
        }
    }

    /*//////////////////////////////////////////////////////////////
                   ROLE CAPABILITY CONFIGURATION LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Set a capability flag as public, meaning any account can call it. Or revoke this capability.
    /// @dev A capability cannot be made public if it has been burned.
    function setPublicCapability(
        address target,
        bytes4 functionSig,
        bool enabled
    ) public virtual requiresAuth {
        require(
            capabilityFlag[target][functionSig] != CapabilityFlag.Burned,
            "RolesAuthority: Capability Burned"
        );

        if (enabled) {
            capabilityFlag[target][functionSig] = CapabilityFlag.Public;
        } else {
            capabilityFlag[target][functionSig] = CapabilityFlag.None;
        }

        emit PublicCapabilityUpdated(target, functionSig, enabled);
    }

    /// @notice Grant a specified role the ability to call a function on a target.
    /// @notice Has no effect
    function setRoleCapability(
        uint8 role,
        address target,
        bytes4 functionSig,
        bool enabled
    ) public virtual requiresAuth {
        if (enabled) {
            getRolesWithCapability[target][functionSig] |= bytes32(1 << role);
            enabledFunctionSigsByTarget[target].add(bytes32(functionSig));

            if (!targets.contains(target)) {
                targets.add(target);
            }
        } else {
            getRolesWithCapability[target][functionSig] &= ~bytes32(1 << role);

            // If no role exist for this target & functionSig, mark it as disabled
            if (getRolesWithCapability[target][functionSig] == bytes32(0)) {
                enabledFunctionSigsByTarget[target].remove(bytes32(functionSig));
            }

            // If no enabled function signatures exist for this target, remove target
            if (enabledFunctionSigsByTarget[target].length() == 0) {
                targets.remove(target);
            }
        }

        emit RoleCapabilityUpdated(role, target, functionSig, enabled);
    }

    /// @notice Permanently burns a capability for a target.
    function burnCapability(address target, bytes4 functionSig) public virtual requiresAuth {
        require(
            capabilityFlag[target][functionSig] != CapabilityFlag.Burned,
            "RolesAuthority: Capability Burned"
        );
        capabilityFlag[target][functionSig] = CapabilityFlag.Burned;

        emit CapabilityBurned(target, functionSig);
    }

    /*//////////////////////////////////////////////////////////////
                       USER ROLE ASSIGNMENT LOGIC
    //////////////////////////////////////////////////////////////*/

    function setUserRole(address user, uint8 role, bool enabled) public virtual requiresAuth {
        if (enabled) {
            getUserRoles[user] |= bytes32(1 << role);

            if (!users.contains(user)) {
                users.add(user);
            }
        } else {
            getUserRoles[user] &= ~bytes32(1 << role);

            // Remove user if no more roles
            if (getUserRoles[user] == bytes32(0)) {
                users.remove(user);
            }
        }

        emit UserRoleUpdated(user, role, enabled);
    }
}
