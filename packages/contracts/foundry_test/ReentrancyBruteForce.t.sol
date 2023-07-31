// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";

contract ReentrantBruteforcer is Test {

  function startReentrancy() external {
    revert("TODO");
    // You have to set this up
  }

  uint256 reEntrancyContractSelector;
  uint256 reentrancyFunctionSelector;
  bool isSetup; 

  function setupCallback(uint256 entropyTarget, uint256 entropyFunction) external{
    isSetup = true;

    // Pick Contract
    reEntrancyContractSelector = entropyTarget;
    reentrancyFunctionSelector = entropyFunction;
  }

  // Pick Function from Contract

  // for each contract
  function contractPicker(uint256 contractIndex) {

    contractIndex = contractsIndex.length; // VAR
    
    // Modulo logic from TS

  }
  function CONTRACT_NAME_Function_Picker(uint256 ) {
      // First Modulo for Contract to Pick

      // Second Modulo for Function to Call (with Contract)

      // Each Contract call with individual default value
  }

  function _handleFallback() internal {
    address contractToCall = 
  }


  fallback() external payable {
    require(isSetup, "Not Setup, tests are not properly set");
    handleFallback();
  }
    
}

contract SCTestBasic is Test {

  ReentrantBruteforcer c;

  function setUp() {
    c = new ReentrantBruteforcer()
  }


  function testBruteForceReentrancies(uint256 entropyTarget, uint256 entropyFunction) {

    // Setup for fuzzing
    c.setupCallback(entropyTarget, entropyFunction);

    // You must set this up
    c.startReentrancy();
  }
}