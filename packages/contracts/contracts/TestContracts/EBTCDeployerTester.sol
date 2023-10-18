// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../EBTCDeployer.sol";
import "../Governor.sol";
import "../LiquidationLibrary.sol";
import "../CdpManager.sol";
import "../BorrowerOperations.sol";
import "../SortedCdps.sol";
import "../ActivePool.sol";
import "../CollSurplusPool.sol";
import "../HintHelpers.sol";
import "../EBTCToken.sol";
import "../FeeRecipient.sol";
import "../MultiCdpGetter.sol";

// tester imports
import "./CDPManagerTester.sol";
import "./BorrowerOperationsTester.sol";
import "./testnet/PriceFeedTestnet.sol";
import "./ActivePoolTester.sol";
import "./EBTCTokenTester.sol";

contract EBTCDeployerTester is EBTCDeployer {
    // core contracts creation code
    bytes public authority_creationCode = type(Governor).creationCode;
    bytes public liquidationLibrary_creationCode = type(LiquidationLibrary).creationCode;
    /// NOTE: RE CHECK if this is the one you want to use!!
    bytes public cdpManager_creationCode = type(CdpManager).creationCode;
    bytes public borrowerOperations_creationCode = type(BorrowerOperations).creationCode;
    bytes public sortedCdps_creationCode = type(SortedCdps).creationCode;
    bytes public activePool_creationCode = type(ActivePool).creationCode;
    bytes public collSurplusPool_creationCode = type(CollSurplusPool).creationCode;
    bytes public hintHelpers_creationCode = type(HintHelpers).creationCode;
    bytes public ebtcToken_creationCode = type(EBTCToken).creationCode;
    bytes public feeRecipient_creationCode = type(FeeRecipient).creationCode;
    bytes public multiCdpGetter_creationCode = type(MultiCdpGetter).creationCode;

    // test contracts creation code
    bytes public cdpManagerTester_creationCode = type(CdpManagerTester).creationCode;
    bytes public borrowerOperationsTester_creationCode = type(BorrowerOperationsTester).creationCode;
    bytes public priceFeedTestnet_creationCode = type(PriceFeedTestnet).creationCode;
    bytes public activePoolTester_creationCode = type(ActivePoolTester).creationCode;
    bytes public ebtcTokenTester_creationCode = type(EBTCTokenTester).creationCode;
}
