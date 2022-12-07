// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.11;

import "forge-std/Test.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";

contract DummyTest is eBTCBaseFixture {
    uint256 private testNumber;

    function setUp() public override {
        eBTCBaseFixture.setUp();
    }

    function testCdpsCountEqToZero() public {
        assertEq(cdpManager.getCdpIdsCount(), 0);
    }
}