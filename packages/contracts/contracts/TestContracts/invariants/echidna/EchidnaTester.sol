// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./EchidnaAsserts.sol";
import "./EchidnaProperties.sol";
import "../TargetFunctions.sol";

contract EchidnaTester is EchidnaAsserts, EchidnaProperties, TargetFunctions {
    constructor() payable {
        _setUp();
        _setUpActors();
    }
}
