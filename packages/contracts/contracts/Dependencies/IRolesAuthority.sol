// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "./EnumerableSet.sol";

/// @notice Role based Authority that supports up to 256 roles.
/// @author BadgerDAO
/// @author Modified from Solmate (https://github.com/transmissions11/solmate/blob/main/src/auth/authorities/RolesAuthority.sol)
/// @author Modified from Dappsys (https://github.com/dapphub/ds-roles/blob/master/src/roles.sol)
interface IRolesAuthority {
    event UserRoleUpdated(address indexed user, uint8 indexed role, bool enabled);

    event PublicCapabilityUpdated(address indexed target, bytes4 indexed functionSig, bool enabled);
    event CapabilityBurned(address indexed target, bytes4 indexed functionSig);

    event RoleCapabilityUpdated(
        uint8 indexed role,
        address indexed target,
        bytes4 indexed functionSig,
        bool enabled
    );

    enum CapabilityFlag {
        None,
        Public,
        Burned
    }
}
