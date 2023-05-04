// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;
pragma experimental ABIEncoderV2;

import "forge-std/Test.sol";

import {PriceFeed} from "../contracts/PriceFeed.sol";
import {MockTellor} from "../contracts/TestContracts/MockTellor.sol";
import {MockAggregator} from "../contracts/TestContracts/MockAggregator.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";
import {TellorCaller} from "../contracts/Dependencies/TellorCaller.sol";

contract PriceFeedTester is PriceFeed {
    function getCurrentFallbackResponse() public view returns (FallbackResponse memory fallbackResponse) {
        return _getCurrentFallbackResponse();
    }

    function getCurrentChainlinkResponse()
        public
        view
        returns (ChainlinkResponse memory chainlinkResponse)
    {
        return _getCurrentChainlinkResponse();
    }

    function scaleChainlinkPriceByDigits(uint _price, uint _decimals) public view returns (uint256) {
        return _scaleChainlinkPriceByDigits(_price, _decimals);
    }

    function bothOraclesSimilarPrice(
        ChainlinkResponse memory _chainlinkResponse,
        FallbackResponse memory _tellorResponse
    ) public view returns (bool) {
        return _bothOraclesSimilarPrice(_chainlinkResponse, _tellorResponse);
    }
}

contract PriceFeedTest is eBTCBaseFixture {
    PriceFeedTester internal _priceFeed;
    TellorCaller internal _tellorCaller;
    MockTellor internal _mockTellor;
    MockAggregator internal _mockChainlink;
    bytes32[] cdpIds;

    function setUp() public override {
        eBTCBaseFixture.setUp();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();

        _priceFeed = new PriceFeedTester();
        _mockTellor = new MockTellor();
        _mockChainlink = new MockAggregator();
        _tellorCaller = new TellorCaller(address(_mockTellor));
        // Set current and prev prices in both oracles
        _mockChainlink.setLatestRoundId(3);
        _mockChainlink.setPrevRoundId(2);
        _mockChainlink.setPrice(7018000);
        _mockChainlink.setPrevPrice(7018000);
        _mockTellor.setPrice(7432e13);

        _mockChainlink.setUpdateTime(block.timestamp);
        _mockTellor.setUpdateTime(block.timestamp);
        _priceFeed.setAddresses(address(_mockChainlink), address(_tellorCaller), address(authority));
    }

    function testMockedPrice() public {
        _priceFeed.fetchPrice();
        uint price = _priceFeed.lastGoodPrice();
        // Picks up scaled chainlink price
        assertEq(price, 70180000000000000);
    }

    // TODO: To run this forktest, make tests public instead of private
    function testPriceFeedFork() private {
        _priceFeed = new PriceFeedTester();
        _tellorCaller = new TellorCaller(0xB3B662644F8d3138df63D2F43068ea621e2981f9);
        _priceFeed.setAddresses(
            0xAc559F25B1619171CbC396a50854A3240b6A4e99,
            address(_tellorCaller),
            address(authority)
        );
        PriceFeed.FallbackResponse memory fallbackResponse = _priceFeed.getCurrentFallbackResponse();

        console.log("Fallback Response:");

        console.log(fallbackResponse.value);
        console.log("Chainlink Response:");
        PriceFeed.ChainlinkResponse memory chainlinkResponse = _priceFeed
            .getCurrentChainlinkResponse();
        console.log(uint256(chainlinkResponse.answer));
        console.log(
            _priceFeed.scaleChainlinkPriceByDigits(
                uint256(chainlinkResponse.answer),
                chainlinkResponse.decimals
            )
        );

        console.log("PriceFeed Response:");
        console.log(_priceFeed.fetchPrice());

        bool similar = _priceFeed.bothOraclesSimilarPrice(chainlinkResponse, fallbackResponse);
        console.log(similar);
    }
}
