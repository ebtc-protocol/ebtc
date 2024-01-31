// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import {EbtcFeedTesterBase} from "../contracts/TestContracts/invariants/echidna/EchidnaEbtcFeedTester.sol";
import {FoundryAsserts} from "./utils/FoundryAsserts.sol";
import "forge-std/Test.sol";

contract EbtcFeedTesterToFoundry is Test, EbtcFeedTesterBase, FoundryAsserts {
    function setUp() public override {
        super.setUp();
    }

    function testPriceFeed() public {
        console2.log(primaryTester.fetchPrice());
        console2.log(ebtcFeed.fetchPrice());
        console2.log(primaryTester.fetchPrice());

        //fetchPriceEbtcFeed();
    }
}
