// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
import {IExternalReentrancyGuard} from "./Interfaces/IExternalReentrancyGuard.sol";

contract ExternalReentrancyGuardUser {
    IExternalReentrancyGuard public immutable reentrancyGuard;

    constructor(address _externalReentrancyGuard) {
        reentrancyGuard  = IExternalReentrancyGuard(_externalReentrancyGuard);
    }

    modifier nonReentrant() virtual {
        require(reentrancyGuard.locked() == 1, "REENTRANCY");

        reentrancyGuard.setLocked(2);

        _;

        reentrancyGuard.setLocked(1);
    }
}

