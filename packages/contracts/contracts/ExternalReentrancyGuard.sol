// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ReentrancyGuard} from "./Dependencies/ReentrancyGuard.sol";
import {EnumerableSet} from "./Dependencies/EnumerableSet.sol";
import {IExternalReentrancyGuard} from "./Interfaces/IExternalReentrancyGuard.sol";

/**
    @notice This contract is an extended version of solmates ReentrancyGuard.sol. 
    @notice Authorized contracts can set re-entrancy status here to maintain a reentrancy status between multiple contracts.
*/
contract ExternalReentrancyGuard is ReentrancyGuard, IExternalReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet internal authorizedCallers;

    /**
        @dev Expects a sufficiently small list of authorized callers that constructor can execute within gas limit
    */
    constructor(address[] memory _authorizedCallers) {
        require(_authorizedCallers.length > 0, "ExternalReentrancyGuard: Authorized callers cannot be empty");
        
        for (uint i = 0; i < _authorizedCallers.length; i++) {
            authorizedCallers.add(_authorizedCallers[i]);
        }
    }

    modifier requiresAuth() {
        require(authorizedCallers.contains(msg.sender), "UNAUTHORIZED");
        _;
    }

    /**
        @dev Expects a sufficiently small list of authorized callers
    */
    function getAuthorizedCallers() external view returns (address[] memory callers) {
        return authorizedCallers.values();
    }

    function locked() external override returns (uint256) {
        return locked;
    }

    function setLocked(uint256 value) external override requiresAuth {
        locked = value;
    }
}

