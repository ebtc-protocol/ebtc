#!/bin/bash

# env flag to make difference on the collateral being tester or real mainnet `stETH`
export MAINNET_FORK=true

forge test --mp foundry_test/pool_research/TVLResearchTest.t.sol -vvv