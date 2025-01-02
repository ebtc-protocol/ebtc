// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import {Properties} from "../contracts/TestContracts/invariants/Properties.sol";
import {IERC20} from "../contracts/Dependencies/IERC20.sol";
import {EchidnaProperties} from "../contracts/TestContracts/invariants/echidna/EchidnaProperties.sol";
import {EchidnaForkAssertions} from "../contracts/TestContracts/invariants/echidna/EchidnaForkAssertions.sol";
import {EchidnaForkTester} from "../contracts/TestContracts/invariants/echidna/EchidnaForkTester.sol";
import {TargetFunctions} from "../contracts/TestContracts/invariants/TargetFunctions.sol";
import {Setup} from "../contracts/TestContracts/invariants/Setup.sol";
import {FoundryAsserts} from "./utils/FoundryAsserts.sol";
import {BeforeAfterWithLogging} from "./utils/BeforeAfterWithLogging.sol";

/*
 * Test suite that converts from echidna "fuzz tests" to foundry "unit tests"
 * The objective is to go from random values to hardcoded values that can be analyzed more easily
 */
contract ForkToFoundry is
    Test,
    Setup,
    FoundryAsserts,
    TargetFunctions,
    EchidnaForkAssertions,
    BeforeAfterWithLogging
{
    function setUp() public {
        string memory MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
        // TODO: when testing locally change this block with block from coverage report set inside _setUpFork
        vm.createSelectFork(MAINNET_RPC_URL, 20996709); 
        
        _setUpFork();
        _setUpActorsFork();
        actor = actors[address(USER1)];

        // If the accounting hasn't been synced since the last rebase
        bytes32 currentCdp = sortedCdps.getFirst();

        while (currentCdp != bytes32(0)) {
            vm.prank(address(borrowerOperations));
            cdpManager.syncAccounting(currentCdp);
            currentCdp = sortedCdps.getNext(currentCdp);
        }

        // Previous cumulative CDPs per each rebase
        // Will need to be adjusted
        // @audit removed because inconsistent with EchidnaForkTester setup
        // vars.cumulativeCdpsAtTimeOfRebase = 200;

        _setUpCdpFork();
    }

    // forge test --match-test test_asserts_GENERAL_13_1 -vv 
    function test_asserts_GENERAL_13_1() public {

        //vm.roll(30256);
        //vm.warp(16802);
        asserts_GENERAL_13();

    }

    // forge test --match-test test_asserts_GENERAL_12_0 -vv 
    function test_asserts_GENERAL_12_0() public {
        vm.roll(block.number + 4963);
        vm.warp(block.timestamp + 50417);
        asserts_GENERAL_12();
    }

    // forge test --match-test test_asserts_GENERAL_12_1 -vv 
    function test_asserts_GENERAL_12_1() public {
        // NOTE: from reproducer test immediately breaks but when asserts_test_fail is commented it doesn't
        // vm.roll(block.number + 60364);
        // vm.warp(block.timestamp + 11077);
        // asserts_active_pool_invariant_5();

        // // NOTE: removing this assertion and warp causes a failure
        // // vm.roll(block.number + 1984);
        // // vm.warp(block.timestamp + 322370);
        // // asserts_test_fail();

        // vm.roll(block.number + 33560);
        // vm.warp(block.timestamp + 95);
        // asserts_GENERAL_12();
        // ========================

        // NOTE: from shrunken logs breaks immediately
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 2973);
        asserts_GENERAL_12();
    }

    // forge test --match-test test_asserts_GENERAL_13_2 -vv 
    function test_asserts_GENERAL_13_2() public {
        // NOTE: from shrunken logs
        // vm.roll(block.number + 1);
        // vm.warp(block.timestamp + 2963);

        // NOTE: from reproducer
        vm.roll(block.number + 60471);
        vm.warp(block.timestamp + 6401);

        asserts_GENERAL_13();
    }
}
