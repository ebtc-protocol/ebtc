// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.11;

import "forge-std/Test.sol";
import "../contracts/Dependencies/SafeMath.sol";
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
    using SafeMath for uint256;
    uint256 constant maxBytes32 = 0;

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

    /* setUp() - basic function to call when setting up new Foundry test suite
    Use in pair with connectCoreContracts to wire up infrastructure

    Consider overriding this function if in need of custom setup
    */
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
    /* connectCoreContracts() - wiring up deployed contracts and setting up infrastructure
    */
    function connectCoreContracts() public virtual {
        // set CdpManager addr in SortedCdps
        sortedCdps.setParams(
            maxBytes32, address(cdpManager), address(borrowerOperations)
        );

        // set contracts in the Cdp Manager
        cdpManager.setAddresses(
            address(borrowerOperations),
            address(activePool),
            address(defaultPool),
            address(stabilityPool),
            address(gasPool),
            address(collSurplusPool),
            address(priceFeedMock),
            address(eBTCToken),
            address(sortedCdps),
            // Liquity Token Address
            address(0),
            // Liquity Staking Address
            address(0)
        );

        // set contracts in BorrowerOperations
        borrowerOperations.setAddresses(
            address(cdpManager),
            address(activePool),
            address(defaultPool),
            address(stabilityPool),
            address(gasPool),
            address(collSurplusPool),
            address(priceFeedMock),
            address(sortedCdps),
            address(eBTCToken),
            // Liquity Staking Address
            address(0)
        );

        // set contracts in stabilityPool
        stabilityPool.setAddresses(
            address(borrowerOperations),
            address(cdpManager),
            address(activePool),
            address(eBTCToken),
            address(sortedCdps),
            address(priceFeedMock),
            // Liquity Community Issuance Address
            address(0)
        );

        // set contracts in activePool
        activePool.setAddresses(
            address(borrowerOperations),
            address(cdpManager),
            address(stabilityPool),
            address(defaultPool)
        );

        // set contracts in defaultPool
        defaultPool.setAddresses(address(cdpManager), address(activePool));

        // set contracts in collSurplusPool
        collSurplusPool.setAddresses(
            address(borrowerOperations),
            address(cdpManager),
            address(activePool)
        );

        // set contracts in HintHelpers
        hintHelpers.setAddresses(address(sortedCdps), address(cdpManager));
    }
}