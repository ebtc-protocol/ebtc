// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;
import "forge-std/Test.sol";
import {eBTCBaseFixture} from "../foundry_test/BaseFixture.sol";

import "./interfaces/IStablePoolFactory.sol";
import "./interfaces/IBalancerPool.sol";
import "./interfaces/IBalancerVault.sol";

contract TVLResearchTest is eBTCBaseFixture {
    IStablePoolFactory STABLE_POOL_FACTORY = IStablePoolFactory(0x8df6EfEc5547e31B0eb7d1291B511FF8a2bf987c);
    IBalancerVault BALANCER_VAULT = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    IBalancerPool balancerPool;
    
    function setUp() {
        eBTCBaseFixture.setUp();

        // 1. Deploy balancer stable pool ideal for near parity tokens
        string name = "Balancer eBTC Stable Pool";
        string symbol = "B-eBTC-STABLE";
        address[2] tokens;
        tokens[0] = address(eBTCToken);
        tokens[1] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        uint256 amplificationParameter = 25; // TODO: test with 50?
        uint256 swapFeePercentage = 0;
        address poolOwner = address(0);

        address pool = STABLE_POOL_FACTORY.create(name, symbol, tokens, amplificationParameter, swapFeePercentage, poolOwner);

        balancerPool = IBalancerPool(pool);
    }

    function test_poolConfig() {
        bytes32 poolId = balancerPool.getPoolId();

        (address[] memory tokens,,)= BALANCER_VAULT.getPoolTokens(poolId);

        console.logAddress(tokens[0]);
        console.logAddress(tokens[1]);
    }
}


