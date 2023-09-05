// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {WETH9} from "./WETH9.sol";
import {BorrowerOperations} from "../BorrowerOperations.sol";
import {PriceFeedTestnet} from "./testnet/PriceFeedTestnet.sol";
import {SortedCdps} from "../SortedCdps.sol";
import {CdpManager} from "../CdpManager.sol";
import {LiquidationLibrary} from "../LiquidationLibrary.sol";
import {ActivePool} from "../ActivePool.sol";
import {HintHelpers} from "../HintHelpers.sol";
import {FeeRecipient} from "../FeeRecipient.sol";
import {EBTCToken} from "../EBTCToken.sol";
import {CollSurplusPool} from "../CollSurplusPool.sol";
import {FunctionCaller} from "./FunctionCaller.sol";
import {CollateralTokenTester} from "./CollateralTokenTester.sol";
import {Governor} from "../Governor.sol";
import {EBTCDeployer} from "../EBTCDeployer.sol";
import {Actor} from "./invariants/Actor.sol";

abstract contract BaseStorageVariables {
    PriceFeedTestnet internal priceFeedMock;
    SortedCdps internal sortedCdps;
    CdpManager internal cdpManager;
    WETH9 internal weth;
    ActivePool internal activePool;
    CollSurplusPool internal collSurplusPool;
    FunctionCaller internal functionCaller;
    BorrowerOperations internal borrowerOperations;
    HintHelpers internal hintHelpers;
    EBTCToken internal eBTCToken;
    CollateralTokenTester internal collateral;
    Governor internal authority;
    LiquidationLibrary internal liqudationLibrary;
    EBTCDeployer internal ebtcDeployer;
    address internal defaultGovernance;

    // LQTY Stuff
    FeeRecipient internal feeRecipient;

    mapping(address => Actor) internal actors;
    Actor internal actor;
}
