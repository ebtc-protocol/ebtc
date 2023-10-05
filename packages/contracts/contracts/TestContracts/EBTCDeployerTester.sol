// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../EbtcDeployer.sol";
import "../Governor.sol";
import "../LiquidationLibrary.sol";
import "../CdpManager.sol";
import "../BorrowerOperations.sol";
import "../SortedCdps.sol";
import "../ActivePool.sol";
import "../CollSurplusPool.sol";
import "../HintHelpers.sol";
import "../EbtcToken.sol";
import "../FeeRecipient.sol";
import "../MultiCdpGetter.sol";

// tester imports
import "./CDPManagerTester.sol";
import "./BorrowerOperationsTester.sol";
import "./testnet/PriceFeedTestnet.sol";
import "./ActivePoolTester.sol";
import "./EbtcTokenTester.sol";

contract EbtcDeployerTester is EbtcDeployer {
    // core contracts creation code
    bytes public authority_creationCode = type(Governor).creationCode;
    bytes public liquidationLibrary_creationCode = type(LiquidationLibrary).creationCode;
    bytes public cdpManager_creationCode = type(CdpManager).creationCode;
    bytes public borrowerOperations_creationCode = type(BorrowerOperations).creationCode;
    bytes public sortedCdps_creationCode = type(SortedCdps).creationCode;
    bytes public activePool_creationCode = type(ActivePool).creationCode;
    bytes public collSurplusPool_creationCode = type(CollSurplusPool).creationCode;
    bytes public hintHelpers_creationCode = type(HintHelpers).creationCode;
    bytes public ebtcToken_creationCode = type(EbtcToken).creationCode;
    bytes public feeRecipient_creationCode = type(FeeRecipient).creationCode;
    bytes public multiCdpGetter_creationCode = type(MultiCdpGetter).creationCode;

    // test contracts creation code
    bytes public cdpManagerTester_creationCode = type(CdpManagerTester).creationCode;
    bytes public borrowerOperationsTester_creationCode = type(BorrowerOperationsTester).creationCode;
    bytes public priceFeedTestnet_creationCode = type(PriceFeedTestnet).creationCode;
    bytes public activePoolTester_creationCode = type(ActivePoolTester).creationCode;
    bytes public ebtcTokenTester_creationCode = type(EbtcTokenTester).creationCode;
}
