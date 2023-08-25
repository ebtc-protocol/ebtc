// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@crytic/properties/contracts/util/PropertiesHelper.sol";
import "@crytic/properties/contracts/util/PropertiesConstants.sol";

import "../../MockAggregator.sol";
import "../../../Dependencies/AuthNoOwner.sol";
import "../../../Interfaces/IFallbackCaller.sol";
import "../../../PriceFeed.sol";

import "../PropertiesDescriptions.sol";

contract EchidnaPriceFeedTester is PropertiesConstants, PropertiesAsserts, PropertiesDescriptions {
    PriceFeed internal priceFeed;
    MockAggregator internal collEthCLFeed;
    MockAggregator internal ethBtcCLFeed;
    AuthNoOwner internal authority;
    IFallbackCaller internal fallbackCaller;

    uint256 internal MAX_PRICE_CHANGE = 0.8e18;
    uint256 internal MAX_ROUND_ID_CHANGE = 5;
    uint256 internal MAX_UPDATE_TIME_CHANGE = 2 days;

    constructor() payable {
        authority = new AuthNoOwner();
        collEthCLFeed = new MockAggregator();
        ethBtcCLFeed = new MockAggregator();

        collEthCLFeed.setLatestRoundId(2);
        collEthCLFeed.setPrevRoundId(1);
        collEthCLFeed.setUpdateTime(block.timestamp);
        collEthCLFeed.setPrevUpdateTime(block.timestamp - 100);
        collEthCLFeed.setPrice(1 ether - 3);
        collEthCLFeed.setPrevPrice(1 ether - 1337);

        ethBtcCLFeed.setLatestRoundId(2);
        ethBtcCLFeed.setPrevRoundId(1);
        ethBtcCLFeed.setUpdateTime(block.timestamp);
        ethBtcCLFeed.setPrevUpdateTime(block.timestamp - 77);
        ethBtcCLFeed.setPrice(3 ether - 2);
        ethBtcCLFeed.setPrevPrice(3 ether - 42);

        // do we have a fallback caller?
        fallbackCaller = IFallbackCaller(address(0));
        priceFeed = new PriceFeed(
            address(fallbackCaller),
            address(authority),
            address(collEthCLFeed),
            address(ethBtcCLFeed)
        );
    }

    // uint private updateTime;
    // uint private prevUpdateTime;

    function setDecimals(uint8 decimals, bool flag) external {
        MockAggregator aggregator = flag ? collEthCLFeed : ethBtcCLFeed;
        aggregator.setDecimals(decimals);
    }

    function setLatest(uint80 latestRoundId, int256 price, uint256 updateTime, bool flag) external {
        MockAggregator aggregator = flag ? collEthCLFeed : ethBtcCLFeed;
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = aggregator.latestRoundData();
        latestRoundId = uint80(
            clampBetween(
                uint256(latestRoundId),
                uint256(roundId),
                uint256(roundId + MAX_ROUND_ID_CHANGE)
            )
        );
        price = (
            clampBetween(
                price,
                (answer * int256(MAX_PRICE_CHANGE)) / 1e18,
                (answer * 1e18) / int256(MAX_PRICE_CHANGE)
            )
        );
        updateTime = (clampBetween(updateTime, updatedAt, updatedAt + MAX_UPDATE_TIME_CHANGE));
        aggregator.setLatestRoundId(latestRoundId);
        aggregator.setPrice(price);
        aggregator.setUpdateTime(updateTime);
    }

    function setPrevious(
        uint80 prevRoundId,
        int256 prevPrice,
        uint256 prevUpdateTime,
        bool flag
    ) external {
        MockAggregator aggregator = flag ? collEthCLFeed : ethBtcCLFeed;
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = aggregator.getRoundData(0);
        prevRoundId = uint80(
            clampBetween(
                uint256(prevRoundId),
                uint256(roundId),
                uint256(roundId + MAX_ROUND_ID_CHANGE)
            )
        );
        prevPrice = (
            clampBetween(
                prevPrice,
                (answer * int256(MAX_PRICE_CHANGE)) / 1e18,
                (answer * 1e18) / int256(MAX_PRICE_CHANGE)
            )
        );
        prevUpdateTime = (
            clampBetween(prevUpdateTime, updatedAt, updatedAt + MAX_UPDATE_TIME_CHANGE)
        );
        aggregator.setPrevRoundId(prevRoundId);
        aggregator.setPrevPrice(prevPrice);
        aggregator.setPrevUpdateTime(prevUpdateTime);
    }

    function fetchPrice() public {
        IPriceFeed.Status statusBefore = priceFeed.status();
        try priceFeed.fetchPrice() {
            IPriceFeed.Status statusAfter = priceFeed.status();
            assertWithMsg(_isValidStatusTransition(statusBefore, statusAfter), PF_02);
        } catch {
            // assertWithMsg(false, PF_01);
        }
    }

    function _isValidStatusTransition(
        IPriceFeed.Status statusBefore,
        IPriceFeed.Status statusAfter
    ) internal returns (bool) {
        emit LogUint256("statusBefore", uint256(statusBefore));
        emit LogUint256("statusAfter", uint256(statusAfter));
        return
            // CASE 1
            (statusBefore == IPriceFeed.Status.chainlinkWorking &&
                statusAfter == IPriceFeed.Status.bothOraclesUntrusted) ||
            (statusBefore == IPriceFeed.Status.chainlinkWorking &&
                statusAfter == IPriceFeed.Status.usingFallbackChainlinkUntrusted) ||
            (statusBefore == IPriceFeed.Status.chainlinkWorking &&
                statusAfter == IPriceFeed.Status.usingChainlinkFallbackUntrusted) ||
            (statusBefore == IPriceFeed.Status.chainlinkWorking &&
                statusAfter == IPriceFeed.Status.usingFallbackChainlinkFrozen) ||
            (statusBefore == IPriceFeed.Status.chainlinkWorking &&
                statusAfter == IPriceFeed.Status.chainlinkWorking) ||
            // CASE 2
            (statusBefore == IPriceFeed.Status.usingFallbackChainlinkUntrusted &&
                statusAfter == IPriceFeed.Status.chainlinkWorking) ||
            (statusBefore == IPriceFeed.Status.usingFallbackChainlinkUntrusted &&
                statusAfter == IPriceFeed.Status.bothOraclesUntrusted) ||
            (statusBefore == IPriceFeed.Status.usingFallbackChainlinkUntrusted &&
                statusAfter == IPriceFeed.Status.usingFallbackChainlinkUntrusted) ||
            // CASE 3
            (statusBefore == IPriceFeed.Status.bothOraclesUntrusted &&
                statusAfter == IPriceFeed.Status.usingChainlinkFallbackUntrusted) ||
            (statusBefore == IPriceFeed.Status.bothOraclesUntrusted &&
                statusAfter == IPriceFeed.Status.chainlinkWorking) ||
            (statusBefore == IPriceFeed.Status.bothOraclesUntrusted &&
                statusAfter == IPriceFeed.Status.bothOraclesUntrusted) ||
            // CASE 4
            (statusBefore == IPriceFeed.Status.usingFallbackChainlinkFrozen &&
                statusAfter == IPriceFeed.Status.bothOraclesUntrusted) ||
            (statusBefore == IPriceFeed.Status.usingFallbackChainlinkFrozen &&
                statusAfter == IPriceFeed.Status.usingFallbackChainlinkUntrusted) ||
            (statusBefore == IPriceFeed.Status.usingFallbackChainlinkFrozen &&
                statusAfter == IPriceFeed.Status.usingChainlinkFallbackUntrusted) ||
            (statusBefore == IPriceFeed.Status.usingFallbackChainlinkFrozen &&
                statusAfter == IPriceFeed.Status.chainlinkWorking) ||
            // CASE 5
            (statusBefore == IPriceFeed.Status.usingChainlinkFallbackUntrusted &&
                statusAfter == IPriceFeed.Status.bothOraclesUntrusted) ||
            (statusBefore == IPriceFeed.Status.usingChainlinkFallbackUntrusted &&
                statusAfter == IPriceFeed.Status.chainlinkWorking) ||
            (statusBefore == IPriceFeed.Status.usingChainlinkFallbackUntrusted &&
                statusAfter == IPriceFeed.Status.usingChainlinkFallbackUntrusted);
    }
}
