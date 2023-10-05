pragma solidity 0.8.17;

import {console2 as console} from "forge-std/console2.sol";

import {eBTCBaseFixture} from "./BaseFixture.sol";

contract MinCdpSizeOpeningPOCTest is eBTCBaseFixture {
    address payable[] users;
    address private splitFeeRecipient;

    ////////////////////////////////////////////////////////////////////////////
    // Tests
    ////////////////////////////////////////////////////////////////////////////

    function setUp() public override {
        super.setUp();

        connectCoreContracts();
        connectLQTYContractsToCore();

        users = _utils.createUsers(3);

        splitFeeRecipient = address(feeRecipient);

        collateral.setEthPerShare(0.9e18);
    }

    /**
        Proof that Split goes down after claiming
     */
    function test_OpenMinCdpSize_NormalMode() public {
        uint256 debtAmt = 1e20; // TODO: Consider fuzz

        uint256 _curPrice = priceFeedMock.getPrice();
        uint256 coll1 = _utils.calculateCollAmount(debtAmt, _curPrice, 126e16);

        bytes32 cdpId1 = _openTestCDP(users[0], coll1, debtAmt);
    }

    function test_OpenMinCdpSize_RecoveryMode() public {}
}
