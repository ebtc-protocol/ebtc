// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "forge-std/Test.sol";

import {PriceFeed} from "../contracts/PriceFeed.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";
import {TellorCaller} from "../contracts/Dependencies/TellorCaller.sol";

contract PriceFeedTester is PriceFeed {

    function getCurrentTellorResponse()
        public
        view
        returns (TellorResponse memory tellorResponse) {
            return _getCurrentTellorResponse();
    }
}


contract PriceFeedTest is eBTCBaseFixture {
    PriceFeedTester internal _priceFeed;
    TellorCaller internal _tellorCaller;
    bytes32[] cdpIds;

    function setUp() public override {
        _priceFeed = new PriceFeedTester();
        _tellorCaller = new TellorCaller(0xB3B662644F8d3138df63D2F43068ea621e2981f9);
        _priceFeed.setAddresses(0xAc559F25B1619171CbC396a50854A3240b6A4e99, address(_tellorCaller));
    }

    function testDummy() public {
        PriceFeed.TellorResponse memory tellorResponse = _priceFeed.getCurrentTellorResponse();
        console.log(tellorResponse.value);

        console.log(_priceFeed.fetchPrice());
    }
}