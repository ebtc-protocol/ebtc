// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./EbtcFeedTesterBase.sol";
import "./EchidnaAsserts.sol";

contract EchidnaEbtcFeedTester is EbtcFeedTesterBase, EchidnaAsserts {
    constructor() payable {
        super.setUp();
    }
}
