// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./EchidnaAsserts.sol";
import "./EchidnaProperties.sol";
import "../TargetFunctions.sol";

contract EchidnaForkTester is EchidnaAsserts, EchidnaProperties, TargetFunctions {
    constructor() payable {
        _setUpFork();
        _setUpActors();
        // https://etherscan.io/tx/0x3d20c053b83d4d49ba12c3251f14546511f8af7b5b99dbeb692f6f9458c075ab
        hevm.roll(19258626);
        hevm.warp(1708307303);
    }
}
