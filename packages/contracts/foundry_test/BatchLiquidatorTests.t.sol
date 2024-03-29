// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import {SortedCdps} from "../contracts/SortedCdps.sol";
import {CdpManager} from "../contracts/CdpManager.sol";
import {ActivePool} from "../contracts/ActivePool.sol";
import {BorrowerOperations} from "../contracts/BorrowerOperations.sol";
import {SyncedLiquidationSequencer} from "../contracts/SyncedLiquidationSequencer.sol";
import {CollateralTokenTester} from "../contracts/TestContracts/CollateralTokenTester.sol";
import {PriceFeedTestnet} from "../contracts/TestContracts/testnet/PriceFeedTestnet.sol";
import {EBTCTokenTester} from "../contracts/TestContracts/EBTCTokenTester.sol";
import {BatchLiquidator} from "./BatchLiquidator.sol";
import {IERC20} from "../contracts/Dependencies/IERC20.sol";
import "forge-std/Test.sol";

contract BatchLiquidatorTests is Test {
    CdpManager internal cdpManager;
    SortedCdps internal sortedCdps;
    ActivePool internal activePool;
    BorrowerOperations internal borrowerOperations;
    PriceFeedTestnet internal priceFeedMock;
    CollateralTokenTester internal collateral;
    SyncedLiquidationSequencer internal syncedLiquidationSequencer;
    EBTCTokenTester internal eBTCToken;
    IERC20 internal wstEth;
    IERC20 internal weth;
    IERC20 internal wbtc;
    BatchLiquidator internal batchLiq;

    function setUp() public {
        //       vm.selectFork(vm.createFork(vm.envString("MAINNET_RPC_URL")));
        //     vm.rollFork(19521269);

        borrowerOperations = BorrowerOperations(0xd366e016Ae0677CdCE93472e603b75051E022AD0);
        cdpManager = CdpManager(0xc4cbaE499bb4Ca41E78f52F07f5d98c375711774);
        sortedCdps = SortedCdps(0x591AcB5AE192c147948c12651a0a5f24f0529BE3);
        activePool = ActivePool(0x6dBDB6D420c110290431E863A1A978AE53F69ebC);
        priceFeedMock = PriceFeedTestnet(0xa9a65B1B1dDa8376527E89985b221B6bfCA1Dc9a);
        eBTCToken = EBTCTokenTester(0x661c70333AA1850CcDBAe82776Bb436A0fCfeEfB);
        collateral = CollateralTokenTester(payable(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84));
        wstEth = IERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
        weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        wbtc = IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
        syncedLiquidationSequencer = new SyncedLiquidationSequencer(
            address(cdpManager),
            address(sortedCdps),
            address(priceFeedMock),
            address(activePool),
            address(collateral)
        );

        batchLiq = new BatchLiquidator(
            address(syncedLiquidationSequencer),
            address(borrowerOperations),
            address(wstEth), // wstETH
            address(weth), // weth
            address(wbtc), // wbtc
            0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45, // univ3
            0x2CEB95D4A67Bf771f1165659Df3D11D8871E906f // Fee recipient multisig
        );
    }

    function test_batchLiq() public {
        assertEq(eBTCToken.balanceOf(batchLiq.owner()), 0);
        batchLiq.batchLiquidate(1, 0.95e5);
        assertEq(eBTCToken.balanceOf(batchLiq.owner()), 19826187002610045);
    }
}
