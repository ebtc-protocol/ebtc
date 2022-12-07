// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.11;

import "forge-std/Test.sol";
import {BorrowerOperations} from "../contracts/BorrowerOperations.sol";
import {PriceFeedTestnet} from "../contracts/TestContracts/PriceFeedTestnet.sol";
import {SortedCdps} from "../contracts/SortedCdps.sol";
import {CdpManager} from "../contracts/CdpManager.sol";
import {ActivePool} from "../contracts/ActivePool.sol";
import {StabilityPool} from "../contracts/StabilityPool.sol";
import {GasPool} from "../contracts/GasPool.sol";
import {DefaultPool} from "../contracts/DefaultPool.sol";
import {HintHelpers} from "../contracts/HintHelpers.sol";
import {EBTCToken} from "../contracts/EBTCToken.sol";
import {CollSurplusPool} from "../contracts/CollSurplusPool.sol";
import {FunctionCaller} from "../contracts/TestContracts/FunctionCaller.sol";

contract eBTCBaseFixture is Test {
    PriceFeedTestnet priceFeedMock;
    SortedCdps sortedCdps;
    CdpManager cdpManager;
    ActivePool activePool;
    StabilityPool stabilityPool;
    GasPool gasPool;
    DefaultPool defaultPool;
    CollSurplusPool collSurplusPool;
    FunctionCaller functionCaller;
    BorrowerOperations borrowerOperations;
    HintHelpers hintHelpers;
    EBTCToken eBTCToken;

    function setUp() public virtual {
        borrowerOperations = new BorrowerOperations();
        priceFeedMock = new PriceFeedTestnet();
        sortedCdps = new SortedCdps();
        cdpManager = new CdpManager();
        activePool = new ActivePool();
        stabilityPool = new StabilityPool();
        gasPool = new GasPool();
        defaultPool = new DefaultPool();
        collSurplusPool = new CollSurplusPool();
        functionCaller = new FunctionCaller();
        hintHelpers = new HintHelpers();
        eBTCToken = new EBTCToken(
            address(cdpManager), address(stabilityPool), address(borrowerOperations)
        );
    }
}