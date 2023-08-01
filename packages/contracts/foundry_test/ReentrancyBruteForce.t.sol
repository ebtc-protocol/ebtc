// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";

contract ReentrantBruteforcer is Test {
    address exploitTarget;
    bytes exploitData;

    // You compare this
    bool public status;
    bytes public response;

    constructor(address target, bytes memory data) {
        // Set them up
        exploitTarget = target;
        exploitData = data;
    }

    function startReentrancy(address startTarget, bytes memory startCalldata) external {
        startTarget.call(startCalldata);
    }

    function _handleFallback() internal {
        console2.log("Handle Fallback First");
        (bool success, bytes memory retval) = exploitTarget.call(exploitData); // I think this should revert either way

        // Store the result and revert here since this is where we need to do stuff
        status = success;
        response = retval;

        console2.log("Handle Fallback End");
    }

    fallback() external payable {
        _handleFallback();
    }
}

contract FakeReentrancyGuardTool {
    uint256 lock;

    function doTheOp(uint256 a) external {
        console2.log("doTheOp a", a);
        if (lock == 0) {
            lock = 1;
            payable(msg.sender).call{value: address(this).balance}("");
        } else {
            revert("Error");
        }

        lock = 0;
    }

    function doTheOpFive(uint256 a, uint256 b, uint256 c, uint256 d, uint256 e) external {
        console2.log("doTheOpFive a", a);
        if (lock == 0) {
            lock = 1;
            payable(msg.sender).call{value: address(this).balance}("");
        } else {
            revert("Error");
        }

        lock = 0;
    }

    receive() external payable {}
}

contract SCTestBasic is Test {
    // Maybe we set it up here
    // At the end of the day the reentrant brute forcer just needs address + calldata

    ReentrantBruteforcer c;
    FakeReentrancyGuardTool demoTarget;

    bytes ZERO; // Used to pass empty values to ANY function

    string constant EXPECTED_REENTRANCY_ERROR = "Error";

    // TODO: Add real contracts here
    function setUp() public {
        demoTarget = new FakeReentrancyGuardTool();

        // Given max length of input you just encode this, so you have some gibberish value
        // Notice that Array have bigger length so you prob need to increase this
        // NOTE: as of Solidity 0.8.X you can pass extra calldata and solidity ignores it, this allows us to pass empty values
        // These will be sufficient to get early reverts at the reentrancy modifier
        {
            ZERO = bytes.concat(
                abi.encode(""), abi.encode(""), abi.encode(""), abi.encode(""), abi.encode(""), abi.encode("")
            );

            ZERO = bytes.concat(ZERO, ZERO, ZERO, ZERO);
        }
    }

    // We iterate over each of these
    // {
    //   target
    //   [selectors]
    // }[]

    struct ContractAndTargets {
        address contractAddress;
        bytes[] calldatasList; // e.g. abi.encodeWithSelector(demoTarget.doTheOp.selector, ZERO)
    }

    function allStartingTargetsAndCalldatas() public returns (ContractAndTargets[] memory contractsAndCalldatas) {
        contractsAndCalldatas = new ContractAndTargets[](1);
        contractsAndCalldatas[0].contractAddress = address(demoTarget); // E.g.

        contractsAndCalldatas[0].calldatasList = new bytes[](2);
        contractsAndCalldatas[0].calldatasList[0] = abi.encodeWithSelector(demoTarget.doTheOpFive.selector, ZERO);
        contractsAndCalldatas[0].calldatasList[1] = abi.encodeWithSelector(demoTarget.doTheOp.selector, ZERO);
    }

    function allReentrantTargetsAndCalldatas() public returns (ContractAndTargets[] memory) {
        // Pro tip: Return allStartingTargetsAndCalldatas, to try every combination
        return allStartingTargetsAndCalldatas();
    }

    // And all of the possible combinations

    function oneBruteForceReentrancyCheck(
        address rentrantTarget,
        bytes memory reentrantData,
        address initialTarget,
        bytes memory initialData
    )
        // TODO: Could also add the custom error message but I think you can just check via GLOBAL
        internal
    {
        c = new ReentrantBruteforcer(rentrantTarget, reentrantData);

        // == Reentrancy Setup == //
        // NOTE: You have to customize this so you can reEnter
        vm.deal(address(this), 1);
        payable(address(demoTarget)).call{value: 1}("");
        console2.log("Dealt");

        // You must set this up
        // TODO: Place as reparate piece of code you have to handle
        console2.log("Calling Reentrancy on doTheOP");
        c.startReentrancy(initialTarget, initialData); // Start Input
        // == END Reentrancy Setup == //

        // == VERIFY RESULT == //
        // Fetch results from fallback
        {
            bool outcome = c.status();
            bytes memory response = c.response();

            assertEq(outcome, false, "Call must revert"); // Must have reverted in the fallback

            // Verifies the error matches the intended one
            bytes4 errorString = 0x08c379a0; // This is added by Solidity compiler: https://trustchain.medium.com/reversing-and-debugging-evm-the-end-of-time-part-4-3eafe5b0511a
            assertEq(response, bytes.concat(errorString, abi.encode(EXPECTED_REENTRANCY_ERROR)), "Error Must Match");
        }
    }

    function testBruteForceReentrancies() public {
        ContractAndTargets[] memory startingCalldatasAndTargets = allReentrantTargetsAndCalldatas();
        ContractAndTargets[] memory contractsAndCalldatas = allReentrantTargetsAndCalldatas();

        for (uint256 i = 0; i < startingCalldatasAndTargets.length; i++) {
            for (uint256 n = 0; n < contractsAndCalldatas[i].calldatasList.length; n++) {
                for (uint256 x = 0; x < contractsAndCalldatas.length; x++) {
                    for (uint256 y = 0; y < contractsAndCalldatas[x].calldatasList.length; y++) {
                        oneBruteForceReentrancyCheck(
                            // It
                            contractsAndCalldatas[x].contractAddress,
                            contractsAndCalldatas[x].calldatasList[y],
                            startingCalldatasAndTargets[i].contractAddress,
                            startingCalldatasAndTargets[i].calldatasList[n]
                        );
                    }
                }
            }
        }
    }
}
