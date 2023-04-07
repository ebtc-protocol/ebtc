// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import {console2 as console} from "forge-std/console2.sol";

import {eBTCBaseFixture} from "../BaseFixture.sol";
import {Utilities} from "../utils/Utilities.sol";

import "./interfaces/IStablePoolFactory.sol";
import "./interfaces/IBalancerPool.sol";
import "./interfaces/IBalancerVault.sol";
import "../../contracts/Dependencies/IERC20.sol";

contract TVLResearchTest is eBTCBaseFixture {
    // ebtc test inheritance
    Utilities internal _utils;

    // ebtc cdp pos.
    uint256 LEV_BPS = 4_000;

    // misc.
    uint256 MAX_BPS = 10_000;
    uint256 SLIPPAGE_CONTROL = 9_700;

    // balancer
    IStablePoolFactory STABLE_POOL_FACTORY = IStablePoolFactory(0x8df6EfEc5547e31B0eb7d1291B511FF8a2bf987c);
    IBalancerVault BALANCER_VAULT = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    uint256 AMPLIFICATION_FACTOR = 25;

    // tokens
    address WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    address constant seeder_agent = address(1);
    address constant leverage_agent = address(2);

    // liq amounts
    uint256 FAKE_MINTING_AMOUNT = 10_000e18;
    uint256 WBTC_AMOUNT = 10_000e8;
    uint256 LIQ_STEP_EBTC = 100e18;
    uint256 LIQ_STEP_WBTC = 100e8;

    // swap amounts
    uint256 EBTC_SWAP_AMOUNT = 177e18;
    uint256 TARGET_WBTC_AMOUNT = 177e8;

    IBalancerPool balancerPool;
    bytes32 poolId;

    function setUp() public override {
        // Block: Mar-04-2023
        vm.createSelectFork("mainnet", 16757226);

        // ebtc system hook-up
        eBTCBaseFixture.setUp();
        eBTCBaseFixture.connectLQTYContracts();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();
        _utils = new Utilities();

        // balancer pool creation
        string memory name = "Balancer eBTC Stable Pool";
        string memory symbol = "B-eBTC-STABLE";
        address[] memory tokens = new address[](2);
        // Careful with unsorted_array err code. BAL#101
        tokens[0] = address(eBTCToken);
        tokens[1] = WBTC;
        uint256 amplificationParameter = AMPLIFICATION_FACTOR;
        uint256 swapFeePercentage = 6000000000000000;
        address poolOwner = address(0);

        vm.startPrank(seeder_agent);
        address pool =
            STABLE_POOL_FACTORY.create(name, symbol, tokens, amplificationParameter, swapFeePercentage, poolOwner);
        vm.stopPrank();

        balancerPool = IBalancerPool(pool);
        poolId = balancerPool.getPoolId();

        // hand-over tokens - `seeder`
        deal(address(eBTCToken), seeder_agent, FAKE_MINTING_AMOUNT);
        deal(WBTC, seeder_agent, WBTC_AMOUNT);

        // hand-over tokens - `leverage_agent`
        vm.deal(leverage_agent, 1000 ether);
    }

    function test_pool_config() public {
        (address[] memory tokens,,) = BALANCER_VAULT.getPoolTokens(poolId);

        assertEq(tokens[0], address(eBTCToken));
        assertEq(tokens[1], WBTC);

        assertEq(eBTCToken.balanceOf(seeder_agent), FAKE_MINTING_AMOUNT);
    }

    function test_optimal_liquidity() public {
        _addLiquidity(2_000e8, 2000e18, true);

        uint256 amountOut;

        // sim case for A=25
        while (amountOut < TARGET_WBTC_AMOUNT * SLIPPAGE_CONTROL / MAX_BPS) {
            amountOut = _swap(seeder_agent, EBTC_SWAP_AMOUNT);
            _addLiquidity(LIQ_STEP_WBTC, LIQ_STEP_EBTC, false);
        }

        (, uint256[] memory balances,) = BALANCER_VAULT.getPoolTokens(poolId);

        // explore file in path: `packages/contracts/foundry_test/pool_research/pool_optimal_liquidity.json`
        _jsonCreation(balances[0], balances[1], AMPLIFICATION_FACTOR);
    }

    function test_leverage() public {
        // 1. pool set-up based on outputs from `pool_optimal_liquidity.json` for target initial test size
        _addLiquidity(192465951034, 2276468999997978669218, true);

        // 2. open pos.cpd -> ebtc
        _openCdp(leverage_agent, 1000 ether);
        uint256 ebtcBalance = eBTCToken.balanceOf(leverage_agent);

        // 3. swap ebtc <> wbtc stable pool balancer
        assertEq(IERC20(WBTC).balanceOf(leverage_agent), 0);
        _swap(leverage_agent, ebtcBalance);
        assertGt(IERC20(WBTC).balanceOf(leverage_agent), 0);

        uint256 wbtcBalancer = IERC20(WBTC).balanceOf(leverage_agent);

        // 4. get more coll. via swap
    }

    // Internal helpers
    function _addLiquidity(uint256 wbtcAmount, uint256 ebtcAmount, bool initialSeed) internal {
        vm.startPrank(seeder_agent);
        IERC20(WBTC).approve(address(BALANCER_VAULT), wbtcAmount);
        eBTCToken.approve(address(BALANCER_VAULT), ebtcAmount);

        (address[] memory tokens,,) = BALANCER_VAULT.getPoolTokens(poolId);

        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[0] = ebtcAmount;
        amountsIn[1] = wbtcAmount;

        bytes memory userData;
        // https://docs.balancer.fi/reference/joins-and-exits/pool-joins.html
        if (initialSeed) {
            userData = abi.encode(IBalancerVault.JoinKind.INIT, amountsIn);
        } else {
            userData = abi.encode(IBalancerVault.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT, amountsIn, 0);
        }

        IVault.JoinPoolRequest memory request = IVault.JoinPoolRequest({
            assets: tokens,
            maxAmountsIn: amountsIn,
            userData: userData,
            fromInternalBalance: false
        });

        BALANCER_VAULT.joinPool(poolId, seeder_agent, seeder_agent, request);
        vm.stopPrank();
    }

    function _swap(address agent, uint256 ebtcAmount) internal returns (uint256 amountOut) {
        // https://docs.balancer.fi/reference/swaps/single-swap.html
        IVault.SingleSwap memory singleSwap = IVault.SingleSwap({
            poolId: poolId,
            kind: uint8(IBalancerVault.SwapKind.GIVEN_IN),
            assetIn: address(eBTCToken),
            assetOut: WBTC,
            amount: ebtcAmount,
            userData: abi.encode(0)
        });

        IVault.FundManagement memory funds = IVault.FundManagement({
            sender: agent,
            fromInternalBalance: false,
            recipient: agent,
            toInternalBalance: false
        });
        vm.startPrank(agent);
        eBTCToken.approve(address(BALANCER_VAULT), 0);
        eBTCToken.approve(address(BALANCER_VAULT), ebtcAmount);
        amountOut = BALANCER_VAULT.swap(singleSwap, funds, 0, type(uint256).max);
        vm.stopPrank();
    }

    function _openCdp(address agent, uint256 collAmount) internal {
        vm.startPrank(agent);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: collAmount}();

        uint256 currentPrice = priceFeedMock.getPrice();

        uint256 debtAmount = ((collAmount * currentPrice) / 1 ether) * LEV_BPS / MAX_BPS;

        assertEq(eBTCToken.balanceOf(agent), 0);
        borrowerOperations.openCdp(1e18, debtAmount, bytes32(0), bytes32(0), collAmount);

        assertGt(eBTCToken.balanceOf(agent), 0);
        vm.stopPrank();
    }

    function _jsonCreation(uint256 balance0, uint256 balance1, uint256 amplFactor) internal {
        // NOTE: hardcoded for simplicity of getting usd expression
        uint256 btcPrice = 28_000;
        string memory key1 = "key1";
        vm.serializeUint(key1, "balance0", balance0);
        vm.serializeUint(key1, "balance1", balance1);

        uint256 usdValue = balance0 / 1e18 * btcPrice + balance1 / 1e8 * btcPrice;
        vm.serializeUint(key1, "usd_value", usdValue);

        string memory key2 = "key2";
        string memory output = vm.serializeUint(key2, "value", amplFactor);

        string memory finalJson = vm.serializeString(key1, "amplification", output);

        vm.writeJson(finalJson, "./foundry_test/pool_research/pool_optimal_liquidity.json");
    }
}
