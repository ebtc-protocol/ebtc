// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@crytic/properties/contracts/util/PropertiesHelper.sol";
import "@crytic/properties/contracts/util/PropertiesConstants.sol";

import "../../../Interfaces/IOracleCaller.sol";
import "../../../PriceFeed.sol";
import "../../../EbtcFeed.sol";
import "../../../ChainlinkAdapter.sol";
import "../../MockAggregator.sol";
import "../Asserts.sol";
import "./EchidnaAsserts.sol";
import {MockFallbackCaller} from "../../MockFallbackCaller.sol";
import "../../../Dependencies/AuthNoOwner.sol";
import {PriceFeedOracleTester} from "../../PriceFeedOracleTester.sol";
import {MockAlwaysTrueAuthority} from "../../MockAlwaysTrueAuthority.sol";

import "../PropertiesDescriptions.sol";

import "@crytic/properties/contracts/util/Hevm.sol";

abstract contract EbtcFeedTesterBase is PropertiesConstants, Asserts, PropertiesDescriptions {
    EbtcFeed internal ebtcFeed;
    PriceFeedOracleTester internal primaryTester;
    PriceFeedOracleTester internal secondaryTester;
    PriceFeed internal priceFeed;
    MockAggregator internal collEthCLFeed;
    MockAggregator internal btcUsdCLFeed;
    MockAggregator internal ethUsdCLFeed;
    ChainlinkAdapter internal chainlinkAdapter;
    MockAlwaysTrueAuthority internal authority;
    MockFallbackCaller internal fallbackCaller;

    uint256 internal constant MAX_PRICE_CHANGE = 5e18;
    uint256 internal constant MAX_ROUND_ID_CHANGE = 5;
    uint256 internal constant MAX_UPDATE_TIME_CHANGE = 2 days;
    uint256 internal constant MAX_REVERT_PERCENTAGE = 0.1e18;
    uint256 internal constant INVALID_PRICE = 0;

    // NOTE: These values imply BIAS, you should EDIT THESE based on the target application
    uint256 internal constant MAX_FALLBACK_VALUE = type(uint128).max;
    uint256 internal constant MIN_FALLBACK_VALUE = 0; // NOTE: 0 is important as it signals an error / broken to the price feed

    // https://etherscan.io/address/0x86392dc19c0b719886221c78ab11eb8cf5c52812#readContract
    // Aggregator is here: https://etherscan.io/address/0x716BB759A5f6faCdfF91F0AfB613133d510e1573#readContract
    // Max and Min are from the aggregator
    uint256 internal constant MAX_ETH_VALUE = 100000000000000000000;
    uint256 internal constant MIN_ETH_VALUE = 1000000000000000;

    uint256 internal constant MAX_BTC_USD_VALUE = 10000000000000000000000;
    uint256 internal constant MIN_BTC_USD_VALUE = 1;

    uint256 internal constant MAX_ETH_USD_VALUE = 10000000000000000000000;
    uint256 internal constant MIN_ETH_USD_VALUE = 1;

    function setUp() public virtual {
        authority = new MockAlwaysTrueAuthority();
        collEthCLFeed = new MockAggregator(18);
        btcUsdCLFeed = new MockAggregator(8);
        ethUsdCLFeed = new MockAggregator(8);

        hevm.roll(123123131);

        collEthCLFeed.setLatestRoundId(2);
        collEthCLFeed.setPrevRoundId(1);
        collEthCLFeed.setUpdateTime(block.timestamp);
        collEthCLFeed.setPrevUpdateTime(block.timestamp);
        collEthCLFeed.setPrice(1 ether - 3);
        collEthCLFeed.setPrevPrice(1 ether - 1337);

        btcUsdCLFeed.setLatestRoundId(2);
        btcUsdCLFeed.setPrevRoundId(1);
        btcUsdCLFeed.setUpdateTime(block.timestamp);
        btcUsdCLFeed.setPrevUpdateTime(block.timestamp);
        btcUsdCLFeed.setPrice(3 ether - 2);
        btcUsdCLFeed.setPrevPrice(3 ether - 42);

        ethUsdCLFeed.setLatestRoundId(2);
        ethUsdCLFeed.setPrevRoundId(1);
        ethUsdCLFeed.setUpdateTime(block.timestamp);
        ethUsdCLFeed.setPrevUpdateTime(block.timestamp);
        ethUsdCLFeed.setPrice(3 ether - 2);
        ethUsdCLFeed.setPrevPrice(3 ether - 42);

        chainlinkAdapter = new ChainlinkAdapter(btcUsdCLFeed, ethUsdCLFeed);

        priceFeed = new PriceFeed(
            address(fallbackCaller),
            address(authority),
            address(collEthCLFeed),
            address(chainlinkAdapter),
            true
        );

        // do we have a fallback caller?
        fallbackCaller = new MockFallbackCaller(priceFeed.fetchPrice());

        primaryTester = new PriceFeedOracleTester(address(priceFeed));
        secondaryTester = new PriceFeedOracleTester(address(priceFeed));

        ebtcFeed = new EbtcFeed(
            address(authority),
            address(primaryTester),
            address(secondaryTester)
        );

        fallbackCaller.setFallbackResponse(ebtcFeed.lastGoodPrice() - 10, block.timestamp, true);
    }

    // Risk of overflow, so we cap to 0
    function _getOldestAcceptableTimestamp() internal returns (uint256) {
        return
            block.timestamp > MAX_UPDATE_TIME_CHANGE ? block.timestamp - MAX_UPDATE_TIME_CHANGE : 0;
    }

    // Future is always fine
    function _getNewestAcceptableTimestamp() internal returns (uint256) {
        return block.timestamp + MAX_UPDATE_TIME_CHANGE;
    }

    function _selectFeed(uint256 feedId) private returns (MockAggregator) {
        feedId = between(feedId, 0, 2);
        if (feedId == 0) {
            return collEthCLFeed;
        } else if (feedId == 1) {
            return btcUsdCLFeed;
        } else {
            return ethUsdCLFeed;
        }
    }

    function setFallbackCaller(bool useFallbackCallerFlag) public {
        priceFeed.setFallbackCaller(useFallbackCallerFlag ? address(fallbackCaller) : address(0));
    }

    function setFallbackResponse(uint256 answer, uint256 timestampRetrieved, bool success) public {
        // We should let prices go crazy instead of clamp them
        // But we should limit them by a max and min value
        answer = (
            between(
                answer,
                MIN_FALLBACK_VALUE, // THIS WAS ALWAYS ZERO
                MAX_FALLBACK_VALUE
            )
        );
        timestampRetrieved = (
            between(
                timestampRetrieved,
                _getOldestAcceptableTimestamp(),
                _getNewestAcceptableTimestamp()
            )
        );
        fallbackCaller.setFallbackResponse(answer, timestampRetrieved, success);
    }

    function setGetFallbackResponseRevert() public {
        fallbackCaller.setGetFallbackResponseRevert();
    }

    function setLatestRevert(uint8 feedId) public {
        MockAggregator aggregator = _selectFeed(feedId);
        aggregator.setLatestRevert();
    }

    function setPrevRevert(uint8 feedId) public {
        MockAggregator aggregator = _selectFeed(feedId);
        aggregator.setPrevRevert();
    }

    function setPrimaryErrorState(uint8 errorState) external {
        errorState = uint8(
            between(
                uint256(errorState),
                uint256(PriceFeedOracleTester.ErrorState.NONE),
                uint256(PriceFeedOracleTester.ErrorState.SELF_DESTRUCT)
            )
        );
        primaryTester.setErrorState(PriceFeedOracleTester.ErrorState(errorState));
    }

    function setSecondaryErrorState(uint8 errorState) external {
        errorState = uint8(
            between(
                uint256(errorState),
                uint256(PriceFeedOracleTester.ErrorState.NONE),
                uint256(PriceFeedOracleTester.ErrorState.SELF_DESTRUCT)
            )
        );
        secondaryTester.setErrorState(PriceFeedOracleTester.ErrorState(errorState));
    }

    function setSecondaryOracle(bool useSecondaryOracleFlag) public {
        ebtcFeed.setSecondaryOracle(useSecondaryOracleFlag ? address(secondaryTester) : address(0));
    }

    function setLatestEth(uint80 latestRoundId, uint256 price, uint256 updateTime) public {
        (uint80 roundId, int256 answer, , uint256 updatedAt, ) = collEthCLFeed.latestRoundData();

        latestRoundId = uint80(
            between(uint256(latestRoundId), uint256(roundId), uint256(roundId + MAX_ROUND_ID_CHANGE))
        );
        // NOTE: Updated to clamp based on proper realistic prices
        price = between(price, MIN_ETH_VALUE, MAX_ETH_VALUE);

        updateTime = (
            between(updateTime, _getOldestAcceptableTimestamp(), _getNewestAcceptableTimestamp())
        );

        collEthCLFeed.setLatestRoundId(latestRoundId);
        collEthCLFeed.setPrice(int256(price));
        collEthCLFeed.setUpdateTime(updateTime);
    }

    function setPreviousEth(uint80 prevRoundId, uint256 prevPrice, uint256 prevUpdateTime) public {
        (uint80 roundId, int256 answer, , uint256 updatedAt, ) = collEthCLFeed.getRoundData(0);
        prevRoundId = uint80(
            between(uint256(prevRoundId), uint256(roundId), uint256(roundId + MAX_ROUND_ID_CHANGE))
        );
        prevPrice = (between(prevPrice, MIN_ETH_VALUE, MAX_ETH_VALUE));
        prevUpdateTime = (
            between(prevUpdateTime, _getOldestAcceptableTimestamp(), _getNewestAcceptableTimestamp())
        );
        collEthCLFeed.setPrevRoundId(prevRoundId);
        collEthCLFeed.setPrevPrice(int256(prevPrice));
        collEthCLFeed.setPrevUpdateTime(prevUpdateTime);
    }

    function setLatestBTCUSD(uint80 latestRoundId, uint256 price, uint256 updateTime) public {
        (uint80 roundId, int256 answer, , uint256 updatedAt, ) = btcUsdCLFeed.latestRoundData();

        latestRoundId = uint80(
            between(uint256(latestRoundId), uint256(roundId), uint256(roundId + MAX_ROUND_ID_CHANGE))
        );
        // NOTE: Updated to clamp based on proper realistic prices
        price = (between(price, MIN_BTC_USD_VALUE, MAX_BTC_USD_VALUE));

        updateTime = (
            between(updateTime, _getOldestAcceptableTimestamp(), _getNewestAcceptableTimestamp())
        );

        btcUsdCLFeed.setLatestRoundId(latestRoundId);
        btcUsdCLFeed.setPrice(int256(price));
        btcUsdCLFeed.setUpdateTime(updateTime);
    }

    function setLatestETHUSD(uint80 latestRoundId, uint256 price, uint256 updateTime) public {
        (uint80 roundId, int256 answer, , uint256 updatedAt, ) = ethUsdCLFeed.latestRoundData();

        latestRoundId = uint80(
            between(uint256(latestRoundId), uint256(roundId), uint256(roundId + MAX_ROUND_ID_CHANGE))
        );
        // NOTE: Updated to clamp based on proper realistic prices
        price = (between(price, MIN_ETH_USD_VALUE, MAX_ETH_USD_VALUE));

        updateTime = (
            between(updateTime, _getOldestAcceptableTimestamp(), _getNewestAcceptableTimestamp())
        );

        ethUsdCLFeed.setLatestRoundId(latestRoundId);
        ethUsdCLFeed.setPrice(int256(price));
        ethUsdCLFeed.setUpdateTime(updateTime);
    }

    function setPreviousBTCUSD(
        uint80 prevRoundId,
        uint256 prevPrice,
        uint256 prevUpdateTime
    ) public {
        (uint80 roundId, int256 answer, , uint256 updatedAt, ) = btcUsdCLFeed.getRoundData(0);
        prevRoundId = uint80(
            between(uint256(prevRoundId), uint256(roundId), uint256(roundId + MAX_ROUND_ID_CHANGE))
        );
        prevPrice = (between(prevPrice, MIN_BTC_USD_VALUE, MAX_BTC_USD_VALUE));
        prevUpdateTime = (
            between(prevUpdateTime, _getOldestAcceptableTimestamp(), _getNewestAcceptableTimestamp())
        );
        btcUsdCLFeed.setPrevRoundId(prevRoundId);
        btcUsdCLFeed.setPrevPrice(int256(prevPrice));
        btcUsdCLFeed.setPrevUpdateTime(prevUpdateTime);
    }

    function setPreviousETHUSD(
        uint80 prevRoundId,
        uint256 prevPrice,
        uint256 prevUpdateTime
    ) public {
        (uint80 roundId, int256 answer, , uint256 updatedAt, ) = ethUsdCLFeed.getRoundData(0);
        prevRoundId = uint80(
            between(uint256(prevRoundId), uint256(roundId), uint256(roundId + MAX_ROUND_ID_CHANGE))
        );
        prevPrice = (between(prevPrice, MIN_ETH_USD_VALUE, MAX_ETH_USD_VALUE));
        prevUpdateTime = (
            between(prevUpdateTime, _getOldestAcceptableTimestamp(), _getNewestAcceptableTimestamp())
        );
        ethUsdCLFeed.setPrevRoundId(prevRoundId);
        ethUsdCLFeed.setPrevPrice(int256(prevPrice));
        ethUsdCLFeed.setPrevUpdateTime(prevUpdateTime);
    }

    function fetchPriceEbtcFeed() public {
        uint256 lastGoodPrice = ebtcFeed.lastGoodPrice();

        try ebtcFeed.fetchPrice() returns (uint256 price) {
            PriceFeedOracleTester.ErrorState primaryErrorState = primaryTester.errorState();
            PriceFeedOracleTester.ErrorState secondaryErrorState = secondaryTester.errorState();

            if (primaryErrorState == PriceFeedOracleTester.ErrorState.NONE) {
                uint256 primaryFeedPrice = primaryTester.fetchPrice();
                // INVALID_PRICE == lastGoodPrice if errorState is NONE
                if (primaryFeedPrice == INVALID_PRICE) {
                    primaryFeedPrice = lastGoodPrice;
                }
                t(price == primaryFeedPrice, PF_07);
            } else {
                if (ebtcFeed.secondaryOracle() != address(0)) {
                    if (secondaryErrorState == PriceFeedOracleTester.ErrorState.NONE) {
                        uint256 secondaryFeedPrice = secondaryTester.fetchPrice();
                        // INVALID_PRICE == lastGoodPrice if errorState is NONE
                        if (secondaryFeedPrice == INVALID_PRICE) {
                            secondaryFeedPrice = lastGoodPrice;
                        }
                        t(price == secondaryFeedPrice, PF_08);
                    } else {
                        t(price == lastGoodPrice, PF_09);
                    }
                } else {
                    t(price == lastGoodPrice, PF_09);
                }
            }
        } catch {
            t(false, PF_01);
        }
    }
}
