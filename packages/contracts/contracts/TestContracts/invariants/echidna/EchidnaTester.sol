// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../../../Interfaces/ICdpManagerData.sol";
import "../../../Dependencies/SafeMath.sol";
import "../../../CdpManager.sol";
import "../../../LiquidationLibrary.sol";
import "../../../BorrowerOperations.sol";
import "../../../ActivePool.sol";
import "../../../CollSurplusPool.sol";
import "../../../SortedCdps.sol";
import "../../../HintHelpers.sol";
import "../../../FeeRecipient.sol";
import "../../testnet/PriceFeedTestnet.sol";
import "../../CollateralTokenTester.sol";
import "../../EBTCTokenTester.sol";
import "../../../Governor.sol";
import "../../../EBTCDeployer.sol";

import "../IHevm.sol";
import "../Properties.sol";
import "../Actor.sol";
import "./EchidnaProperties.sol";
import "../BeforeAfter.sol";
import "./EchidnaAsserts.sol";
import "../TargetFunctions.sol";

contract EchidnaTester is EchidnaAsserts, EchidnaProperties, TargetFunctions {
    constructor() payable {
        _setUp();
        _setUpActors();
    }
}
