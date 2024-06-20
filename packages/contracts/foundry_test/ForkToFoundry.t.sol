// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import {Properties} from "../contracts/TestContracts/invariants/Properties.sol";
import {IERC20} from "../contracts/Dependencies/IERC20.sol";
import {EchidnaProperties} from "../contracts/TestContracts/invariants/echidna/EchidnaProperties.sol";
import {EchidnaForkTester} from "../contracts/TestContracts/invariants/echidna/EchidnaForkTester.sol";
import {TargetFunctions} from "../contracts/TestContracts/invariants/TargetFunctions.sol";
import {TargetContractSetup} from "../contracts/TestContracts/invariants/TargetContractSetup.sol";
import {FoundryAsserts} from "./utils/FoundryAsserts.sol";
import {BeforeAfterWithLogging} from "./utils/BeforeAfterWithLogging.sol";

/*
 * Test suite that converts from echidna "fuzz tests" to foundry "unit tests"
 * The objective is to go from random values to hardcoded values that can be analyzed more easily
 */
contract ForkToFoundry is
    Test,
    TargetContractSetup,
    FoundryAsserts,
    TargetFunctions,
    EchidnaProperties,
    BeforeAfterWithLogging
{
    function setUp() public {
        vm.createSelectFork("YOUR_RPC_URL_HERE");
        _setUpFork();
        _setUpActors();
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
        vars.cumulativeCdpsAtTimeOfRebase = 200;
    }

    /*
    function test_GENERAL_18() public {
        t(echidna_GENERAL_18(), "Not Passing");
    }
*/
}
