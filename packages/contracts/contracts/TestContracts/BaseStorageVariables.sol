// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {WETH9} from "./WETH9.sol";
import {BorrowerOperations} from "../BorrowerOperations.sol";
import {PriceFeedTestnet} from "./testnet/PriceFeedTestnet.sol";
import {SortedCdps} from "../SortedCdps.sol";
import {CdpManager} from "../CdpManager.sol";
import {LiquidationLibrary} from "../LiquidationLibrary.sol";
import {LiquidationSequencer} from "../LiquidationSequencer.sol";
import {SyncedLiquidationSequencer} from "../SyncedLiquidationSequencer.sol";
import {ActivePool} from "../ActivePool.sol";
import {HintHelpers} from "../HintHelpers.sol";
import {FeeRecipient} from "../FeeRecipient.sol";
import {EbtcToken} from "../EbtcToken.sol";
import {CollSurplusPool} from "../CollSurplusPool.sol";
import {FunctionCaller} from "./FunctionCaller.sol";
import {CollateralTokenTester} from "./CollateralTokenTester.sol";
import {Governor} from "../Governor.sol";
import {EbtcDeployer} from "../EbtcDeployer.sol";
import {Actor} from "./invariants/Actor.sol";
import {CRLens} from "../CRLens.sol";
import {Simulator} from "./invariants/Simulator.sol";

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
    EbtcToken internal eBTCToken;
    CollateralTokenTester internal collateral;
    Governor internal authority;
    LiquidationLibrary internal liqudationLibrary;
    LiquidationSequencer internal liquidationSequencer;
    SyncedLiquidationSequencer internal syncedLiquidationSequencer;
    EbtcDeployer internal ebtcDeployer;
    address internal defaultGovernance;

    // LQTY Stuff
    FeeRecipient internal feeRecipient;

    mapping(address => Actor) internal actors;
    Actor internal actor;

    CRLens internal crLens;
    Simulator internal simulator;

    uint internal constant NUMBER_OF_ACTORS = 3;
    uint internal constant INITIAL_ETH_BALANCE = 1e24;
    uint internal constant INITIAL_COLL_BALANCE = 1e21;

    uint internal constant diff_tolerance = 0.000000000002e18; //compared to 1e18
    uint internal constant MAX_PRICE_CHANGE_PERCENT = 1.05e18; //compared to 1e18
    uint internal constant MAX_REBASE_PERCENT = 1.1e18; //compared to 1e18
    uint internal constant MAX_FLASHLOAN_ACTIONS = 4;
}
