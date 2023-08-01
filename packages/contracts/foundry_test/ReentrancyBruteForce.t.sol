// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";

contract ReentrantBruteforcer is Test {

  address exploitTarget;
  bytes exploitData;

  constructor(address target, bytes memory data) {
    // Set them up
    exploitTarget = target;
    exploitData = data;
  }

  function startReentrancy(address startTarget, bytes memory startCalldata) external returns (bool, bytes memory) {
    (bool success, bytes memory retval) = startTarget.call(startCalldata);

    return (success, retval);
  }


  function _handleFallback() internal {
    exploitTarget.call(exploitData); // I think this should revert either way
  }


  fallback() external payable {
    _handleFallback();
  }
    
}

contract FakeReentrancyGuardTool {
  uint256 lock;

  function doTheOp() external {
    if(lock == 0) {
      lock = 1;
      payable(msg.sender).call{value: address(this).balance}(""); // Trigger reentrancy here
    } else {
      revert("Error");
    }
  }

  receive() external payable {

  }
}

contract SCTestBasic is Test {

  // Maybe we set it up here
  // At the end of the day the reentrant brute forcer just needs address + calldata

  ReentrantBruteforcer c;
  FakeReentrancyGuardTool demoTarget;

  function setUp() public {
    demoTarget = new FakeReentrancyGuardTool();
  }


  function testBruteForceReentrancies(uint256 entropyTarget, uint256 entropyFunction) public {

    // On each iteration we deploy a new contract for exploit
    c = new ReentrantBruteforcer(address(demoTarget), abi.encodeCall(demoTarget.doTheOp, ()));

    vm.deal(address(this), 1);
    payable(address(c)).call{value: 1}("");

    // You must set this up
    (bool s, bytes memory retval) = c.startReentrancy(address(demoTarget), abi.encodeCall(demoTarget.doTheOp, ()));
    assertEq(s, false); // Must have reverted
    string memory expectedVal = "Error";
    bytes4 errorString = 0x08c379a0; // This is added by Solidity compiler: https://trustchain.medium.com/reversing-and-debugging-evm-the-end-of-time-part-4-3eafe5b0511a
    assertEq(retval, bytes.concat(errorString, abi.encode(expectedVal))); // Error must match
  }
}