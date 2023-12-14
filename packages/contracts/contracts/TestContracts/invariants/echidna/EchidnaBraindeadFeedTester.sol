// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@crytic/properties/contracts/util/PropertiesHelper.sol";
import "@crytic/properties/contracts/util/PropertiesConstants.sol";

import "../../../Interfaces/IOracleCaller.sol";
import "../../../PriceFeed.sol";
import "../../../BraindeadFeed.sol";
import "../../MockAggregator.sol";
import {MockFallbackCaller} from "../../MockFallbackCaller.sol";
import "../../../Dependencies/AuthNoOwner.sol";
import {PriceFeedOracleTester} from "../../PriceFeedOracleTester.sol";
import {MockAlwaysTrueAuthority} from "../../MockAlwaysTrueAuthority.sol";

import "../PropertiesDescriptions.sol";

import "@crytic/properties/contracts/util/Hevm.sol";

contract EchidnaBraindeadFeedTester is
    PropertiesConstants,
    PropertiesAsserts,
    PropertiesDescriptions
{
    BraindeadFeed internal braindeadFeed;
    PriceFeedOracleTester internal primaryTester;
    PriceFeedOracleTester internal secondaryTester;
    PriceFeed internal priceFeed;
    MockAggregator internal collEthCLFeed;
    MockAggregator internal ethBtcCLFeed;
    MockAlwaysTrueAuthority internal authority;
    MockFallbackCaller internal fallbackCaller;

    uint256 internal constant MAX_PRICE_CHANGE = 5e18;
    uint256 internal constant MAX_ROUND_ID_CHANGE = 5;
    uint256 internal constant MAX_UPDATE_TIME_CHANGE = 2 days;
    uint256 internal constant MAX_STATUS_HISTORY_OPERATIONS = 32;
    uint256 internal constant MAX_REVERT_PERCENTAGE = 0.1e18;

    // NOTE: These values imply BIAS, you should EDIT THESE based on the target application
    uint256 internal constant MAX_FALLBACK_VALUE = type(uint128).max;
    uint256 internal constant MIN_FALLBACK_VALUE = 0; // NOTE: 0 is important as it signals an error / broken to the price feed

    // https://etherscan.io/address/0x86392dc19c0b719886221c78ab11eb8cf5c52812#readContract
    // Aggregator is here: https://etherscan.io/address/0x716BB759A5f6faCdfF91F0AfB613133d510e1573#readContract
    // Max and Min are from the aggregator
    uint256 internal constant MAX_ETH_VALUE = 100000000000000000000;
    uint256 internal constant MIN_ETH_VALUE = 1000000000000000;

    // https://etherscan.io/address/0xac559f25b1619171cbc396a50854a3240b6a4e99#code
    // https://etherscan.io/address/0x0f00392FcB466c0E4E4310d81b941e07B4d5a079
    uint256 internal constant MAX_BTC_VALUE = 1000000000;
    uint256 internal constant MIN_BTC_VALUE = 10000;

    uint256 internal statusHistoryOperations = 0;
    IPriceFeed.Status[MAX_STATUS_HISTORY_OPERATIONS] internal statusHistory;

    constructor() payable {
        authority = new MockAlwaysTrueAuthority();
        collEthCLFeed = new MockAggregator();
        ethBtcCLFeed = new MockAggregator();

        hevm.roll(123123131);

        collEthCLFeed.setLatestRoundId(2);
        collEthCLFeed.setPrevRoundId(1);
        collEthCLFeed.setUpdateTime(block.timestamp);
        collEthCLFeed.setPrevUpdateTime(block.timestamp - 1);
        collEthCLFeed.setPrice(1 ether - 3);
        collEthCLFeed.setPrevPrice(1 ether - 1337);

        ethBtcCLFeed.setLatestRoundId(2);
        ethBtcCLFeed.setPrevRoundId(1);
        ethBtcCLFeed.setUpdateTime(block.timestamp);
        ethBtcCLFeed.setPrevUpdateTime(block.timestamp - 1);
        ethBtcCLFeed.setPrice(3 ether - 2);
        ethBtcCLFeed.setPrevPrice(3 ether - 42);

        // do we have a fallback caller?
        fallbackCaller = new MockFallbackCaller();

        priceFeed = new PriceFeed(
            address(fallbackCaller),
            address(authority),
            address(collEthCLFeed),
            address(ethBtcCLFeed)
        );

        primaryTester = new PriceFeedOracleTester(address(priceFeed));
        secondaryTester = new PriceFeedOracleTester(address(priceFeed));

        braindeadFeed = new BraindeadFeed(
            address(authority),
            address(primaryTester),
            address(secondaryTester)
        );

        fallbackCaller.setFallbackResponse(priceFeed.lastGoodPrice() - 10, block.timestamp, true);

        statusHistory[(statusHistoryOperations++) % MAX_STATUS_HISTORY_OPERATIONS] = priceFeed
            .status();
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

    function setFallbackCaller(bool flag) public {
        priceFeed.setFallbackCaller(flag ? address(fallbackCaller) : address(0));
    }

    function setFallbackResponse(uint256 answer, uint256 timestampRetrieved, bool success) public {
        // We should let prices go crazy instead of clamp them
        // But we should limit them by a max and min value
        answer = (
            clampBetween(
                answer,
                MIN_FALLBACK_VALUE, // THIS WAS ALWAYS ZERO
                MAX_FALLBACK_VALUE
            )
        );
        timestampRetrieved = (
            clampBetween(
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

    function setLatestRevert(bool flag) public {
        MockAggregator aggregator = flag ? collEthCLFeed : ethBtcCLFeed;
        aggregator.setLatestRevert();
    }

    function setPrevRevert(bool flag) public {
        MockAggregator aggregator = flag ? collEthCLFeed : ethBtcCLFeed;
        aggregator.setPrevRevert();
    }

    // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/7
    function setDecimals(uint8 decimals, bool flag) external {
        // https://github.com/d-xo/weird-erc20
        decimals = uint8(clampBetween(uint256(decimals), 2, 18));
        MockAggregator aggregator = flag ? collEthCLFeed : ethBtcCLFeed;
        aggregator.setDecimals(decimals);
    }

    function setPrimaryErrorState(uint8 errorState) external {
        errorState = uint8(
            clampBetween(
                uint256(errorState),
                uint256(PriceFeedOracleTester.ErrorState.NONE),
                uint256(PriceFeedOracleTester.ErrorState.SELF_DESTRUCT)
            )
        );
        primaryTester.setErrorState(PriceFeedOracleTester.ErrorState(errorState));
    }

    function setSecondaryErrorState(uint8 errorState) external {
        errorState = uint8(
            clampBetween(
                uint256(errorState),
                uint256(PriceFeedOracleTester.ErrorState.NONE),
                uint256(PriceFeedOracleTester.ErrorState.SELF_DESTRUCT)
            )
        );
        secondaryTester.setErrorState(PriceFeedOracleTester.ErrorState(errorState));
    }

    function setLatestEth(uint80 latestRoundId, uint256 price, uint256 updateTime) public {
        (uint80 roundId, int256 answer, , uint256 updatedAt, ) = collEthCLFeed.latestRoundData();

        latestRoundId = uint80(
            clampBetween(
                uint256(latestRoundId),
                uint256(roundId),
                uint256(roundId + MAX_ROUND_ID_CHANGE)
            )
        );
        // NOTE: Updated to clamp based on proper realistic prices
        price = clampBetween(price, MIN_ETH_VALUE, MAX_ETH_VALUE);

        updateTime = (
            clampBetween(
                updateTime,
                _getOldestAcceptableTimestamp(),
                _getNewestAcceptableTimestamp()
            )
        );

        collEthCLFeed.setLatestRoundId(latestRoundId);
        collEthCLFeed.setPrice(int256(price));
        collEthCLFeed.setUpdateTime(updateTime);
    }

    function setPreviousEth(
        uint80 prevRoundId,
        uint256 prevPrice,
        uint256 prevUpdateTime,
        bool flag
    ) public {
        (uint80 roundId, int256 answer, , uint256 updatedAt, ) = collEthCLFeed.getRoundData(0);
        prevRoundId = uint80(
            clampBetween(
                uint256(prevRoundId),
                uint256(roundId),
                uint256(roundId + MAX_ROUND_ID_CHANGE)
            )
        );
        prevPrice = (clampBetween(prevPrice, MIN_ETH_VALUE, MAX_ETH_VALUE));
        prevUpdateTime = (
            clampBetween(
                prevUpdateTime,
                _getOldestAcceptableTimestamp(),
                _getNewestAcceptableTimestamp()
            )
        );
        collEthCLFeed.setPrevRoundId(prevRoundId);
        collEthCLFeed.setPrevPrice(int256(prevPrice));
        collEthCLFeed.setPrevUpdateTime(prevUpdateTime);
    }

    function setLatestBTC(uint80 latestRoundId, uint256 price, uint256 updateTime) public {
        (uint80 roundId, int256 answer, , uint256 updatedAt, ) = ethBtcCLFeed.latestRoundData();

        latestRoundId = uint80(
            clampBetween(
                uint256(latestRoundId),
                uint256(roundId),
                uint256(roundId + MAX_ROUND_ID_CHANGE)
            )
        );
        // NOTE: Updated to clamp based on proper realistic prices
        price = (clampBetween(price, MIN_BTC_VALUE, MAX_BTC_VALUE));

        updateTime = (
            clampBetween(
                updateTime,
                _getOldestAcceptableTimestamp(),
                _getNewestAcceptableTimestamp()
            )
        );

        ethBtcCLFeed.setLatestRoundId(latestRoundId);
        ethBtcCLFeed.setPrice(int256(price));
        ethBtcCLFeed.setUpdateTime(updateTime);
    }

    function setPreviousBTC(
        uint80 prevRoundId,
        uint256 prevPrice,
        uint256 prevUpdateTime,
        bool flag
    ) public {
        (uint80 roundId, int256 answer, , uint256 updatedAt, ) = ethBtcCLFeed.getRoundData(0);
        prevRoundId = uint80(
            clampBetween(
                uint256(prevRoundId),
                uint256(roundId),
                uint256(roundId + MAX_ROUND_ID_CHANGE)
            )
        );
        prevPrice = (clampBetween(prevPrice, MIN_BTC_VALUE, MAX_BTC_VALUE));
        prevUpdateTime = (
            clampBetween(
                prevUpdateTime,
                _getOldestAcceptableTimestamp(),
                _getNewestAcceptableTimestamp()
            )
        );
        ethBtcCLFeed.setPrevRoundId(prevRoundId);
        ethBtcCLFeed.setPrevPrice(int256(prevPrice));
        ethBtcCLFeed.setPrevUpdateTime(prevUpdateTime);
    }

    function fetchPriceBraindead() public {
        uint256 lastGoodPrice = braindeadFeed.lastGoodPrice();

        try braindeadFeed.fetchPrice() returns (uint256 price) {
            PriceFeedOracleTester.ErrorState primaryErrorState = primaryTester.errorState();
            PriceFeedOracleTester.ErrorState secondaryErrorState = secondaryTester.errorState();

            if (primaryErrorState == PriceFeedOracleTester.ErrorState.NONE) {
                assertWithMsg(price == primaryTester.fetchPrice(), PF_07);
            } else {
                if (secondaryErrorState == PriceFeedOracleTester.ErrorState.NONE) {
                    assertWithMsg(price == secondaryTester.fetchPrice(), PF_08);
                } else {
                    assertWithMsg(price == lastGoodPrice, PF_09);
                }
            }
        } catch {
            assertWithMsg(false, PF_01);
        }
    }
}
