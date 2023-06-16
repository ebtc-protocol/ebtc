// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
pragma experimental ABIEncoderV2;

import {console2 as console} from "forge-std/console2.sol";

import {eBTCBaseFixture} from "../BaseFixture.sol";
import {ICdpManagerData} from "../../contracts/Interfaces/ICdpManagerData.sol";
import {LeverageMacroReference} from "../../contracts/LeverageMacroReference.sol";
import {LeverageMacroBase} from "../../contracts/LeverageMacroBase.sol";

import {MainnetConstants} from "./MainnetConstants.sol";

import "./interfaces/IBalancerPool.sol";
import "./interfaces/IBalancerVault.sol";
import "./interfaces/ICurvePool.sol";
import "../../contracts/Dependencies/IERC20.sol";

contract TVLResearchTest is eBTCBaseFixture, MainnetConstants {
    // agents
    address constant seeder_agent = address(1);
    address constant leverage_agent = address(40e18);
    address constant leverage_agent_secondary = address(90e18);

    // liq amounts
    uint256 FAKE_MINTING_AMOUNT = 10_000e18;
    uint256 WBTC_AMOUNT = 10_000e8;
    uint256 LIQ_STEP_EBTC = 100e18;
    uint256 LIQ_STEP_WBTC = 100e8;

    // swap amounts
    uint256 EBTC_SWAP_AMOUNT = 177e18;
    uint256 TARGET_WBTC_AMOUNT = 177e8;

    // coll. seeding for agents
    uint256 COLL_INIT_AMOUNT = 20 ether; // NOTE: bump down temporality for test flow

    IBalancerPool balancerPool;
    bytes32 EBTC_WBTC_POOL_ID;
    address leverageMacroAddr;

    function setUp() public override {
        // Block: Mar-04-2023
        vm.createSelectFork("mainnet", 16757226);

        // labels
        vm.label(address(eBTCToken), "eBTC");
        vm.label(address(collateral), "collateralTest");
        vm.label(WBTC, "WBTC");
        vm.label(WETH, "WETH");
        vm.label(STETH, "STETH");
        vm.label(WSTETH, "WSTETH");

        // ebtc system hook-up
        eBTCBaseFixture.setUp();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();

        // NOTE: ensure we are forking with the right collateral for the live tests
        assertEq(address(collateral), STETH);

        // balancer pool creation
        string memory name = "Balancer eBTC Stable Pool";
        string memory symbol = "B-eBTC-STABLE";
        address[] memory tokens = new address[](2);
        // Careful with unsorted_array err code. BAL#101
        // https://docs.balancer.fi/reference/contracts/error-codes.html#input
        tokens[0] = WBTC;
        tokens[1] = address(eBTCToken);
        uint256 amplificationParameter = AMPLIFICATION_FACTOR;
        uint256 swapFeePercentage = 6000000000000000;
        address poolOwner = address(0);

        vm.startPrank(seeder_agent);
        address pool = STABLE_POOL_FACTORY.create(
            name,
            symbol,
            tokens,
            amplificationParameter,
            swapFeePercentage,
            poolOwner
        );
        vm.stopPrank();

        balancerPool = IBalancerPool(pool);
        EBTC_WBTC_POOL_ID = balancerPool.getPoolId();

        // hand-over tokens - `seeder`
        deal(address(eBTCToken), seeder_agent, FAKE_MINTING_AMOUNT);
        deal(WBTC, seeder_agent, WBTC_AMOUNT);

        // hand-over tokens - `leverage_agent`
        vm.deal(leverage_agent, COLL_INIT_AMOUNT);
        vm.deal(leverage_agent_secondary, COLL_INIT_AMOUNT);

        // create lev proxy to enable factor `x` leverage
        leverageMacroAddr = _createLeverageMacro(leverage_agent);
    }

    function test_pool_config() public {
        (address[] memory tokens, , ) = BALANCER_VAULT.getPoolTokens(EBTC_WBTC_POOL_ID);

        assertEq(tokens[0], WBTC);
        assertEq(tokens[1], address(eBTCToken));

        assertEq(eBTCToken.balanceOf(seeder_agent), FAKE_MINTING_AMOUNT);
    }

    function test_optimal_liquidity() public {
        _addLiquidity(2_000e8, 2000e18, true);

        uint256 amountOut;

        // sim case for A=25
        while (amountOut < (TARGET_WBTC_AMOUNT * SLIPPAGE_CONTROL) / MAX_BPS) {
            amountOut = _swap(seeder_agent, EBTC_SWAP_AMOUNT);
            _addLiquidity(LIQ_STEP_WBTC, LIQ_STEP_EBTC, false);
        }

        (, uint256[] memory balances, ) = BALANCER_VAULT.getPoolTokens(EBTC_WBTC_POOL_ID);

        // explore file in path: `packages/contracts/foundry_test/pool_research/pool_optimal_liquidity.json`
        _jsonCreation(balances[0], balances[1], AMPLIFICATION_FACTOR);
    }

    function test_leverage() public {
        // 1. pool set-up based on outputs from `pool_optimal_liquidity.json` for target initial test size
        _addLiquidity(192465951034, 2276468999997978669218, true);

        // 2. open pos.cpd -> ebtc
        _openCdp(leverage_agent, COLL_INIT_AMOUNT);
        uint256 ebtcBalance = eBTCToken.balanceOf(leverage_agent);

        // 3. swap ebtc <> wbtc stable pool balancer
        assertEq(IERC20(WBTC).balanceOf(leverage_agent), 0);
        _swap(leverage_agent, ebtcBalance);
        assertGt(IERC20(WBTC).balanceOf(leverage_agent), 0);

        uint256 wbtcBalancer = IERC20(WBTC).balanceOf(leverage_agent);
    }

    function test_leverage_fl_via_leverageMacro() public {
        // seed pool for test
        _addLiquidity(2_000e8, 2000e18, true);

        _openCdp(leverage_agent_secondary, COLL_INIT_AMOUNT);

        vm.prank(leverage_agent);
        collateral.submit{value: leverage_agent.balance}(address(0));
        vm.stopPrank();

        uint256 initialColl = collateral.balanceOf(leverage_agent);
        // TODO: test waters with [2x, 4x], can it be fuzz or constrained to an interval?
        uint256 leverageFactor = 2e18;

        // targets given current price
        uint256 currentPrice = priceFeedMock.getPrice();
        uint256 targetDebt = (initialColl * currentPrice * leverageFactor) / 1e36;

        // fl fee
        uint256 flFee = borrowerOperations.flashFee(address(eBTCToken), targetDebt);

        // cdp mcr
        uint256 mcr = borrowerOperations.MCR();

        bytes32 cdpId = _cdpLeverageTargetCreation(
            initialColl,
            targetDebt,
            flFee,
            leverageFactor,
            leverageMacroAddr
        );

        _checkLeverageTarget(cdpId, initialColl, leverageFactor);
    }

    // Internal helpers
    function _addLiquidity(uint256 wbtcAmount, uint256 ebtcAmount, bool initialSeed) internal {
        vm.startPrank(seeder_agent);
        IERC20(WBTC).approve(address(BALANCER_VAULT), wbtcAmount);
        eBTCToken.approve(address(BALANCER_VAULT), ebtcAmount);

        (address[] memory tokens, , ) = BALANCER_VAULT.getPoolTokens(EBTC_WBTC_POOL_ID);

        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[0] = wbtcAmount;
        amountsIn[1] = ebtcAmount;

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

        BALANCER_VAULT.joinPool(EBTC_WBTC_POOL_ID, seeder_agent, seeder_agent, request);
        vm.stopPrank();
    }

    function _swap(address agent, uint256 ebtcAmount) internal returns (uint256 amountOut) {
        // https://docs.balancer.fi/reference/swaps/single-swap.html
        IVault.SingleSwap memory singleSwap = IVault.SingleSwap({
            poolId: EBTC_WBTC_POOL_ID,
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
        collateral.submit{value: collAmount}(address(0));

        uint256 currentPrice = priceFeedMock.getPrice();

        uint256 debtAmount = (((collAmount * currentPrice) / 1 ether) * LEV_BPS) / MAX_BPS;

        assertEq(eBTCToken.balanceOf(agent), 0);
        borrowerOperations.openCdp(debtAmount, bytes32(0), bytes32(0), collAmount);

        assertGt(eBTCToken.balanceOf(agent), 0);
        vm.stopPrank();
    }

    function _createLeverageMacro(address _agent) internal returns (address) {
        vm.startPrank(_agent);

        // NOTE: that funds will be sweep to `owner` as default `_sweepToCaller` is true
        LeverageMacroBase proxy = new LeverageMacroReference(
            address(borrowerOperations),
            address(activePool),
            address(cdpManager),
            address(eBTCToken),
            address(collateral),
            address(sortedCdps),
            _agent
        );

        // approve tokens for proxy
        collateral.approve(address(proxy), type(uint256).max);
        eBTCToken.approve(address(proxy), type(uint256).max);

        vm.stopPrank();

        return address(proxy);
    }

    function _cdpLeverageTargetCreation(
        uint256 _initColl,
        uint256 _debtTarget,
        uint256 _flFee,
        uint256 _leverageTarget,
        address _leverageMacroAddr
    ) internal returns (bytes32) {
        // target coll on lev
        uint256 collSwapTarget = (_initColl * _leverageTarget) / 1e18;

        // swap after calldata generation
        uint256 collSwapMinOut = _calldataSwapMinOut(_debtTarget);

        // cdp opening details
        LeverageMacroBase.OpenCdpOperation memory openingCdpStruct = LeverageMacroBase
            .OpenCdpOperation(
                _debtTarget + _flFee,
                NULL_CDP_ID,
                NULL_CDP_ID,
                collSwapMinOut + _initColl
            );
        bytes memory openingCdpStructEncoded = abi.encode(openingCdpStruct);

        // NOTE: swaps, we do `before` swap, after is not req op
        LeverageMacroBase.SwapOperation[] memory levSwapsBefore;
        LeverageMacroBase.SwapOperation[] memory levSwapsAfter;

        // NOTE: watch-out for codes: https://docs.balancer.fi/reference/contracts/error-codes.html#error-codes
        levSwapsBefore = _balancerCalldataSwap(
            address(eBTCToken),
            _debtTarget,
            address(collateral),
            collSwapMinOut
        );

        // macro op struct
        LeverageMacroBase.LeverageMacroOperation memory opStruct = LeverageMacroBase
            .LeverageMacroOperation(
                address(collateral),
                _initColl,
                levSwapsBefore,
                levSwapsAfter,
                LeverageMacroBase.OperationType.OpenCdpOperation,
                openingCdpStructEncoded
            );

        // post-checks on cdp opening
        LeverageMacroBase.PostCheckParams memory postCheckParams = _getPostCheckStruct(
            _debtTarget + _flFee,
            collSwapMinOut + _initColl
        );

        // carry lev ops given the `_leverageTarget`
        vm.startPrank(leverage_agent);
        LeverageMacroBase(_leverageMacroAddr).doOperation(
            LeverageMacroBase.FlashLoanType.eBTC, // 1
            _debtTarget,
            opStruct,
            LeverageMacroBase.PostOperationCheck.openCdp, // 0
            postCheckParams
        );
        vm.stopPrank();

        return sortedCdps.cdpOfOwnerByIndex(_leverageMacroAddr, 0);
    }

    function _getPostCheckStruct(
        uint256 _debtTarget,
        uint256 _collTarget
    ) internal view returns (LeverageMacroBase.PostCheckParams memory) {
        // health-check on debt
        LeverageMacroBase.CheckValueAndType memory expectedDebt = LeverageMacroBase
            .CheckValueAndType(_debtTarget, LeverageMacroBase.Operator.equal);

        uint256 netColl = _collTarget - LIQUIDATOR_REWARD;
        uint256 shares = collateral.getSharesByPooledEth(netColl);

        //  health-check on coll
        LeverageMacroBase.CheckValueAndType memory expectedCollateral = LeverageMacroBase
            .CheckValueAndType(shares, LeverageMacroBase.Operator.equal);

        return
            LeverageMacroBase.PostCheckParams(
                expectedDebt,
                expectedCollateral,
                NULL_CDP_ID,
                ICdpManagerData.Status.active
            );
    }

    /// @dev it is not marked as `view` since `queryBatchSwap` modifies states internally
    function _calldataSwapMinOut(uint256 _ebtcAmount) internal returns (uint256 minStEthOut) {
        IAsset[] memory assetArr = new IAsset[](3);
        assetArr[0] = IAsset(address(eBTCToken));
        assetArr[1] = IAsset(WBTC);
        assetArr[2] = IAsset(WETH);

        IVault.BatchSwapStep[] memory batchSwapDetails = new IVault.BatchSwapStep[](2);
        // ebtc -> wbtc
        batchSwapDetails[0] = IVault.BatchSwapStep({
            poolId: EBTC_WBTC_POOL_ID,
            assetInIndex: 0,
            assetOutIndex: 1,
            amount: _ebtcAmount,
            userData: new bytes(0)
        });
        // wbtc -> (wstETH || weth)
        batchSwapDetails[1] = IVault.BatchSwapStep({
            poolId: WBTC_WETH_POOL_ID,
            assetInIndex: 1,
            assetOutIndex: 2,
            amount: 0,
            userData: new bytes(0)
        });

        IVault.FundManagement memory funds = IVault.FundManagement({
            sender: leverageMacroAddr,
            fromInternalBalance: false,
            recipient: payable(leverageMacroAddr),
            toInternalBalance: false
        });

        int256[] memory assetDeltas = BALANCER_VAULT.queryBatchSwap(
            IBalancerVault.SwapKind.GIVEN_IN,
            batchSwapDetails,
            assetArr,
            funds
        );

        uint256 wethOut = uint256(-assetDeltas[assetDeltas.length - 1]);

        minStEthOut =
            (STETH_ETH_CURVE_POOL.get_dy(int128(0), int128(1), wethOut) * SLIPPAGE_CONTROL_SWAP) /
            MAX_BPS;
    }

    function _balancerCalldataSwap(
        address _tokenIn,
        uint256 _amountTokenIn,
        address _tokenOut,
        uint256 _tokenMinOut
    ) internal view returns (LeverageMacroBase.SwapOperation[] memory) {
        // swap from ebtc -> wbtc -> (wstETH || weth)
        // NOTE: issue is the coll format in the test suite?
        LeverageMacroBase.SwapOperation[] memory swapOp = new LeverageMacroBase.SwapOperation[](2);

        LeverageMacroBase.SwapCheck[] memory safetyOutputChecks = new LeverageMacroBase.SwapCheck[](
            1
        );
        safetyOutputChecks[0] = LeverageMacroBase.SwapCheck(WETH, _tokenMinOut);

        // assets
        IAsset[] memory assetArr = new IAsset[](3);
        assetArr[0] = IAsset(address(eBTCToken));
        assetArr[1] = IAsset(WBTC);
        assetArr[2] = IAsset(WETH);

        // limits
        int256[] memory limits = new int256[](3);
        limits[0] = int256(_amountTokenIn);
        limits[2] = -int256(_tokenMinOut);
        // balancer batch swap args
        // https://docs.balancer.fi/reference/swaps/batch-swaps.html#batchswapstep-struct
        IVault.BatchSwapStep[] memory batchSwapDetails = new IVault.BatchSwapStep[](2);
        // ebtc -> wbtc
        batchSwapDetails[0] = IVault.BatchSwapStep({
            poolId: EBTC_WBTC_POOL_ID,
            assetInIndex: 0,
            assetOutIndex: 1,
            amount: _amountTokenIn,
            userData: new bytes(0)
        });
        // wbtc -> (wstETH || weth)
        batchSwapDetails[1] = IVault.BatchSwapStep({
            poolId: WBTC_WETH_POOL_ID,
            assetInIndex: 1,
            assetOutIndex: 2,
            amount: 0,
            userData: new bytes(0)
        });

        IVault.FundManagement memory funds = IVault.FundManagement({
            sender: leverageMacroAddr,
            fromInternalBalance: false,
            recipient: payable(leverageMacroAddr),
            toInternalBalance: false
        });

        bytes memory swapPayload = abi.encodeWithSelector(
            IBalancerVault.batchSwap.selector, // NOTE: multi-hop swap
            IBalancerVault.SwapKind.GIVEN_IN,
            batchSwapDetails,
            assetArr,
            funds,
            limits,
            type(uint256).max
        );

        swapOp[0] = LeverageMacroBase.SwapOperation(
            _tokenIn,
            address(BALANCER_VAULT),
            _amountTokenIn,
            address(BALANCER_VAULT),
            swapPayload,
            safetyOutputChecks
        );

        // play with another consecutive swap - curve (weth -> stETH)

        swapPayload = abi.encodeWithSelector(
            ICurvePool.exchange.selector,
            int128(0),
            int128(1),
            _tokenMinOut,
            0
        );

        LeverageMacroBase.SwapCheck[] memory safetyOutputChecksEmpty;

        swapOp[1] = LeverageMacroBase.SwapOperation(
            WETH,
            address(STETH_ETH_CURVE_POOL),
            _tokenMinOut,
            address(STETH_ETH_CURVE_POOL),
            swapPayload,
            safetyOutputChecksEmpty
        );

        return swapOp;
    }

    function _checkLeverageTarget(
        bytes32 _cdpId,
        uint256 initColl,
        uint256 targetLeverageFactor
    ) internal {
        (, uint256 coll, ) = cdpManager.getEntireDebtAndColl(_cdpId);

        uint256 currentPrice = priceFeedMock.getPrice();
        uint256 currentLeverage = (coll / initColl) * 1e18;

        // https://book.getfoundry.sh/reference/forge-std/assertApproxEqAbs
        assertApproxEqAbs(currentLeverage, targetLeverageFactor, MAX_DELTA);
    }

    function _jsonCreation(uint256 balance0, uint256 balance1, uint256 amplFactor) internal {
        // NOTE: hardcoded for simplicity of getting usd expression
        uint256 btcPrice = 28_000;
        string memory key1 = "key1";
        vm.serializeUint(key1, "balance0", balance0);
        vm.serializeUint(key1, "balance1", balance1);

        uint256 usdValue = (balance0 / 1e18) * btcPrice + (balance1 / 1e8) * btcPrice;
        vm.serializeUint(key1, "usd_value", usdValue);

        string memory key2 = "key2";
        string memory output = vm.serializeUint(key2, "value", amplFactor);

        string memory finalJson = vm.serializeString(key1, "amplification", output);

        vm.writeJson(finalJson, "./foundry_test/pool_research/pool_optimal_liquidity.json");
    }
}
