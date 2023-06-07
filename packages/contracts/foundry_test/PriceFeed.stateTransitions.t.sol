// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {IPriceFeed} from "../contracts/Interfaces/IPriceFeed.sol";
import {PriceFeed} from "../contracts/PriceFeed.sol";
import {PriceFeedTester} from "../contracts/TestContracts/PriceFeedTester.sol";
import {MockTellor} from "../contracts/TestContracts/MockTellor.sol";
import {MockAggregator} from "../contracts/TestContracts/MockAggregator.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";
import {TellorCaller} from "../contracts/Dependencies/TellorCaller.sol";
import {AggregatorV3Interface} from "../contracts/Dependencies/AggregatorV3Interface.sol";

contract PriceFeedTest is eBTCBaseFixture {
    address constant STETH_ETH_CL_FEED = 0x86392dC19c0b719886221c78AB11eb8Cf5c52812;

    PriceFeedTester internal priceFeedTester;
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
        priceFeedTester = new PriceFeedTester(address(_tellorCaller), address(authority));
    }

    function testStateTransitions() public {
        // Pick a random starting state
        // Set variables to match that state
        // Fuzz actions
        // set prices
        // set broken or frozen statuses
        // setFallbackCaller
        // fetchPrice
        // Ensure the state after fetchPrice() is correct, given the inputs
    }

    function testStateTransitionsWithOracleFallback() public {}

    /// @dev We expect there to be a previous chainlink response on system init, real-world oracles used will have this property
    function getOracleResponses()
        public
        returns (
            PriceFeed.ChainlinkResponse memory chainlinkResponse,
            PriceFeed.ChainlinkResponse memory prevChainlinkResponse,
            PriceFeed.FallbackResponse memory fallbackResponse
        )
    {
        // Get oracle responses
        chainlinkResponse = priceFeedTester.getCurrentChainlinkResponse();

        prevChainlinkResponse = priceFeedTester.getPrevChainlinkResponse(
            chainlinkResponse.roundEthBtcId - 1,
            chainlinkResponse.roundStEthEthId - 1
        );

        fallbackResponse = priceFeedTester.getCurrentFallbackResponse();
    }

    /// @dev Get expected end status on fetchPrice() given current sysstem state
    function getExpectedStatusFromFetchPrice() public returns (IPriceFeed.Status newStatus) {
        PriceFeed.ChainlinkResponse memory chainlinkResponse;
        PriceFeed.ChainlinkResponse memory prevChainlinkResponse;
        PriceFeed.FallbackResponse memory fallbackResponse;

        (chainlinkResponse, prevChainlinkResponse, fallbackResponse) = getOracleResponses();
        /**
            - CL broken or frozen?
            - FB broken or frozen? If no fallback, we will return broken (timestamp is zero, and value is zero)
            - CL current price >50% deviation from previous price?
            - CL and FB prices valid and >5% difference?
         */

        bool chainlinkFrozen = priceFeedTester.chainlinkIsFrozen(chainlinkResponse);
        bool chainlinkBroken = priceFeedTester.chainlinkIsBroken(
            chainlinkResponse,
            prevChainlinkResponse
        );

        bool fallbackFrozen = priceFeedTester.fallbackIsFrozen(fallbackResponse);
        bool fallbackBroken = priceFeedTester.fallbackIsBroken(fallbackResponse);

        bool bothOraclesSimilarPrice = priceFeedTester.bothOraclesSimilarPrice(
            chainlinkResponse,
            fallbackResponse
        );
        bool chainlinkPriceChangeAboveMax = priceFeedTester.chainlinkPriceChangeAboveMax(
            chainlinkResponse,
            prevChainlinkResponse
        );

        IPriceFeed.Status currentStatus = priceFeedTester.status();

        uint256 price;

        if (currentStatus == IPriceFeed.Status.chainlinkWorking) {
            // Confirm that a broken and frozen oracle returns broken first, how do the conditions overlap?
            // CL Broken + FL Broken
            // CL Broken + FL Frozen
            // CL Broken + FL Working (not broken or frozen)
            // CL Frozen + FL Broken
            // CL Frozen + FL Frozen
            // CL Frozen + FL Frozen
            // CL >50% change from last round + FB Broken
            // CL >50% change from last round + FB Frozen
            // CL >50% change from last round + CL/FB Price >5% difference
            // CL >50% change from last round + CL/FB Price <=5% difference
            // CL Working
        } else if (currentStatus == IPriceFeed.Status.usingFallbackChainlinkUntrusted) {
            // CL and FB working, reporting similar prices (<5% difference)
            // Chainlink is now working, return to it
            // CL and FB working, reporting different prices (>5% difference)
            // Chainlink is untrusted, and so remain distrustful if reporting a different price
            // FB Broken
            // Fallback is now broken, and becomes untrusted
            // Use last good price as both oracles are untrusted
            // FB Frozen
            // Fallback is now frozen, but remains trusted as freezing can be temporary
            // Use last good price as we don't have a newer price to use
            // FB Working
            // Fallback is working, and CL still isn't. Stay in same state
            // Use our new valid fallback price
        } else if (currentStatus == IPriceFeed.Status.bothOraclesUntrusted) {
            // CL and FB working, reporting similar prices (<5% difference)
            // Chainlink is now working, return to it
            // Both oracles are now trusted again
            // CL is working.
            // Fallback isn't working so we can't compare the prices. Go ahead and trust CL for now that it's reporting and is the only valid oracle
            // Chainlink is now working, return to it, but note that fallback is still untrusted
        } else if (currentStatus == IPriceFeed.Status.usingFallbackChainlinkFrozen) {
            // CL and FB working, reporting similar prices (<5% difference)
            // Chainlink is now working, return to it
            // Both oracles are now trusted again
            /**
                If this isn't the case, one of a few things is true:
                - chainlink is frozen or broken
                - fallback is frozen or broken
                - the oracles are both working but reporting notably different prices
            */
            // FB Broken
            // Fallback is now broken, and becomes untrusted
            // Use last good price as both oracles are untrusted
            // FB Frozen
            // Fallback is now frozen, but remains trusted as freezing can be temporary
            // Use last good price as we don't have a newer price to use
            // FB is working
        } else if (currentStatus == IPriceFeed.Status.usingChainlinkFallbackUntrusted) {
            // CL Broken
            // Chainlink is now broken, and becomes untrusted. We still don't trust the FB here.
            newStatus = IPriceFeed.Status.bothOraclesUntrusted;
            price = priceFeedTester.lastGoodPrice();

            // CL Frozen
            // We still trust CL, but have no new price to report. Use last good price
            newStatus = IPriceFeed.Status.usingChainlinkFallbackUntrusted;
            price = priceFeedTester.lastGoodPrice();

            // CL and FB working, reporting similar prices (<5% difference)
            // Both oracles are trusted now, use latest CL price
            newStatus = IPriceFeed.Status.chainlinkWorking;
            price = chainlinkResponse.answer;

            // CL is working, reporting suspiciously different price since previous round (>50% difference)
            // Stop trusting CL, and use last good price as we don't trust FB either
            newStatus = IPriceFeed.Status.bothOraclesUntrusted;
            price = priceFeedTester.lastGoodPrice();

            // CL is working, but FB is still not trusted (it's not live and reporting within 5% of a valid updated CL price)
            // Use CL price, and maintain this state ("chainlinkWorking" really means both oracles are trusted)
            newStatus = IPriceFeed.Status.usingChainlinkFallbackUntrusted;
            price = chainlinkResponse.answer;
        }
    }
}
