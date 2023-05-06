// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;
import "forge-std/Test.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";

/*
 * Test suite that tests exactly one thing: opening CDPs
 * It tests different cases and also does random testing against random coll amounts and amount of users
 */
contract GovernorBurnCapabilityTest is eBTCBaseFixture {
    mapping(bytes32 => bool) private _cdpIdsExist;

    function setUp() public override {
        eBTCBaseFixture.setUp();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();
    }

    function test_BurnCapability() public {
        // burn
        // confirm burn happened
    }

    function test_CapabilityCannotBeBurnedTwice() public {
        // burn
        // confirm burn happened
        // attempt to burn again
    }

    function test_BurnedCapabilityCannotBeMadePublic() public {
        // burn
        // confirm burn happened
        // attempt to make public
    }

    function test_PublicCapabilityCanBeBurned() public {
        // make public
        // burn
        // confirm burn happened
    }

    function test_BurnedCapabilityCannotBeCalled() public {
        // burn
        // confirm burn happened
        // attempt to call as user with proper role
        // attempt to call as user without proper role
    }

    /// Invariant: a capability that is burned should never be able to become unburned.
}
