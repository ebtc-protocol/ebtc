// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {PriceFeed} from "../contracts/PriceFeed.sol";
import {PriceFeedTester} from "../contracts/TestContracts/PriceFeedTester.sol";
import {MockTellor} from "../contracts/TestContracts/MockTellor.sol";
import {MockAggregator} from "../contracts/TestContracts/MockAggregator.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";
import {TellorCaller} from "../contracts/Dependencies/TellorCaller.sol";
import {AggregatorV3Interface} from "../contracts/Dependencies/AggregatorV3Interface.sol";

contract PriceFeedTest is eBTCBaseFixture {
    address constant STETH_ETH_CL_FEED = 0x86392dC19c0b719886221c78AB11eb8Cf5c52812;

    PriceFeedTester internal _priceFeed;
    TellorCaller internal _tellorCaller;
    MockTellor internal _mockTellor;
    MockAggregator internal _mockChainlink;
    bytes32[] cdpIds;

    function setUp() public override {
        eBTCBaseFixture.setUp();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();

        // TODO: do we need this now that we want to test the live cl feeds?
        /*
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
        */

        _tellorCaller = new TellorCaller(address(_mockTellor));

        // NOTE: fork at `17210175`. my local timestamp is playing funny
        vm.warp(1683478511);
        uint256 prevRoundId = 18446744073709552244;
        // NOTE: force to mock it up, since `updateAt` was 1d old, triggers `TIMEOUT`
        vm.mockCall(
            STETH_ETH_CL_FEED,
            abi.encodeWithSelector(AggregatorV3Interface.getRoundData.selector, prevRoundId),
            abi.encode(prevRoundId, 966009470097829100, 1662456296, 1683478511, prevRoundId)
        );
        _priceFeed = new PriceFeedTester(
            address(_tellorCaller),
            address(authority),
            0x86392dC19c0b719886221c78AB11eb8Cf5c52812,
            0xAc559F25B1619171CbC396a50854A3240b6A4e99,
            true
        );
    }

    // NOTE: now there is not mocking in constructor, since cl feeds are constants
    // only fork test focus!
    function testMockedPrice() private {
        _priceFeed.fetchPrice();
        uint256 price = _priceFeed.lastGoodPrice();
        // Picks up scaled chainlink price
        assertEq(price, 70180000000000000);
    }

    // TODO: To run this forktest, make tests public instead of private
    // and make sure you are forking the suggested `block_number=17210175`
    function testPriceFeedFork() private {
        PriceFeed.FallbackResponse memory fallbackResponse = _priceFeed.getCurrentFallbackResponse();

        // -- Fallback outputs --
        console.log("Fallback Response:");

        console.log(fallbackResponse.answer);

        // -- CL outputs --
        console.log("Chainlink Response:");
        PriceFeed.ChainlinkResponse memory chainlinkResponse = _priceFeed
            .getCurrentChainlinkResponse();
        console.log(uint256(chainlinkResponse.answer));
        console.log(_priceFeed.lastGoodPrice());

        console.log("PriceFeed Response:");
        console.log(_priceFeed.fetchPrice());

        // NOTE: `TellorFlex` in mainnet will return zero, and there will be a "SafeMath: division by zero" error
        //bool similar = _priceFeed.bothOraclesSimilarPrice(chainlinkResponse, tellorResponse);
        //console.log(similar);
    }
}
