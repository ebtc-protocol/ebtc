// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@crytic/properties/contracts/util/PropertiesHelper.sol";
import "@crytic/properties/contracts/util/PropertiesConstants.sol";

import "../../../PriceFeed.sol";
import "../../../ChainlinkAdapter.sol";
import "../../MockAggregator.sol";
import {MockFallbackCaller} from "../../MockFallbackCaller.sol";
import "../../../Dependencies/AuthNoOwner.sol";

import "../PropertiesDescriptions.sol";

contract MockAlwaysTrueAuthority {
    function canCall(address user, address target, bytes4 functionSig) external view returns (bool) {
        return true;
    }
}

contract EchidnaPriceFeedTester is PropertiesConstants, PropertiesAsserts, PropertiesDescriptions {
    event Log2(string, uint256, uint256);
    PriceFeed internal priceFeed;
    MockAggregator internal collEthCLFeed;
    MockAggregator internal btcUsdCLFeed;
    MockAggregator internal ethUsdCLFeed;
    ChainlinkAdapter internal chainlinkAdapter;
    MockAlwaysTrueAuthority internal authority;
    MockFallbackCaller internal fallbackCaller;

    uint256 internal constant MAX_PRICE_CHANGE = 1.2e18;
    uint256 internal constant MAX_ROUND_ID_CHANGE = 5;
    uint256 internal constant MAX_UPDATE_TIME_CHANGE = 2 days;
    uint256 internal constant MAX_STATUS_HISTORY_OPERATIONS = 32;
    uint256 internal constant MAX_REVERT_PERCENTAGE = 0.1e18;

    uint256 internal statusHistoryOperations = 0;
    IPriceFeed.Status[MAX_STATUS_HISTORY_OPERATIONS] internal statusHistory;

    constructor() payable {
        authority = new MockAlwaysTrueAuthority();
        collEthCLFeed = new MockAggregator(18);
        btcUsdCLFeed = new MockAggregator(8);
        ethUsdCLFeed = new MockAggregator(8);

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
            address(0),
            address(authority),
            address(collEthCLFeed),
            address(chainlinkAdapter),
            true
        );

        fallbackCaller = new MockFallbackCaller(priceFeed.fetchPrice());

        priceFeed.setFallbackCaller(address(fallbackCaller));

        statusHistory[(statusHistoryOperations++) % MAX_STATUS_HISTORY_OPERATIONS] = priceFeed
            .status();
    }

    function setFallbackCaller(bool flag) public {
        priceFeed.setFallbackCaller(flag ? address(fallbackCaller) : address(0));
    }

    function setFallbackResponse(uint256 answer, uint256 timestampRetrieved, bool success) public {
        uint256 fallbackAnswer = fallbackCaller._answer() == 0
            ? fallbackCaller._initAnswer()
            : fallbackCaller._answer();
        uint256 fallbackTs = fallbackCaller._timestampRetrieved() == 0
            ? block.timestamp
            : fallbackCaller._timestampRetrieved();
        answer = (
            clampBetween(
                answer,
                (fallbackAnswer * 1e18) / MAX_PRICE_CHANGE,
                (fallbackAnswer * MAX_PRICE_CHANGE) / 1e18
            )
        );
        timestampRetrieved = (
            clampBetween(timestampRetrieved, fallbackTs, fallbackTs + MAX_UPDATE_TIME_CHANGE)
        );
        fallbackCaller.setFallbackResponse(answer, timestampRetrieved, success);
    }

    function setGetFallbackResponseRevert(uint256 seed) public {
        seed = clampBetween(seed, 0, 1e18);
        bool reverted = fallbackCaller.getFallbackResponseRevert();
        if (seed <= (reverted ? (1e18 - MAX_REVERT_PERCENTAGE) : MAX_REVERT_PERCENTAGE)) {
            fallbackCaller.setFallbackTimeoutRevert();
        }
    }

    function setFallbackTimeoutRevert(uint256 seed) public {
        seed = clampBetween(seed, 0, 1e18);
        bool reverted = fallbackCaller.fallbackTimeoutRevert();
        if (seed <= (reverted ? (1e18 - MAX_REVERT_PERCENTAGE) : MAX_REVERT_PERCENTAGE)) {
            fallbackCaller.setFallbackTimeoutRevert();
        }
    }

    function setLatestRevert(uint8 feedId, uint256 seed) public log {
        MockAggregator aggregator = _selectFeed(feedId);
        seed = clampBetween(seed, 0, 1e18);
        bool reverted = aggregator.latestRevert();
        if (seed <= (reverted ? (1e18 - MAX_REVERT_PERCENTAGE) : MAX_REVERT_PERCENTAGE)) {
            aggregator.setLatestRevert();
        }
    }

    function setPrevRevert(uint8 feedId, uint256 seed) public log {
        MockAggregator aggregator = _selectFeed(feedId);
        seed = clampBetween(seed, 0, 1e18);
        bool reverted = aggregator.prevRevert();
        if (seed <= (reverted ? (1e18 - MAX_REVERT_PERCENTAGE) : MAX_REVERT_PERCENTAGE)) {
            aggregator.setPrevRevert();
        }
    }

    function setLatest(
        uint80 latestRoundId,
        int256 price,
        uint256 updateTime,
        uint8 feedId
    ) public log {
        MockAggregator aggregator = _selectFeed(feedId);
        (uint80 roundId, int256 answer, , uint256 updatedAt, ) = aggregator.latestRoundData();
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
                (answer * 1e18) / int256(MAX_PRICE_CHANGE),
                (answer * int256(MAX_PRICE_CHANGE)) / 1e18
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
        uint8 feedId
    ) public log {
        MockAggregator aggregator = _selectFeed(feedId);
        (uint80 roundId, int256 answer, , uint256 updatedAt, ) = aggregator.getRoundData(0);
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
                (answer * 1e18) / int256(MAX_PRICE_CHANGE),
                (answer * int256(MAX_PRICE_CHANGE)) / 1e18
            )
        );
        prevUpdateTime = (
            clampBetween(prevUpdateTime, updatedAt, updatedAt + MAX_UPDATE_TIME_CHANGE)
        );
        aggregator.setPrevRoundId(prevRoundId);
        aggregator.setPrevPrice(prevPrice);
        aggregator.setPrevUpdateTime(prevUpdateTime);
    }

    function fetchPriceBatch() public log {
        uint256 price = _fetchPrice();
        for (uint256 i; i < 2; i++) {
            uint256 newPrice = _fetchPrice();
            assertWithMsg(price == newPrice, PF_10);
        }
    }

    function fetchPrice() public log {
        _fetchPrice();
    }

    function _fetchPrice() private returns (uint256) {
        IPriceFeed.Status statusBefore = priceFeed.status();
        uint256 fallbackResponse;

        (fallbackResponse, , ) = fallbackCaller.getFallbackResponse();
        try priceFeed.fetchPrice() returns (uint256 price) {
            IPriceFeed.Status statusAfter = priceFeed.status();
            assertWithMsg(_isValidStatusTransition(statusBefore, statusAfter), PF_02);

            if (
                statusAfter == IPriceFeed.Status.chainlinkWorking ||
                statusAfter == IPriceFeed.Status.usingChainlinkFallbackUntrusted
            ) {
                assertEq(price, priceFeed.lastGoodPrice(), PF_04);

                if (address(priceFeed.fallbackCaller()) != address(0)) {
                    assertNeq(price, fallbackResponse, PF_05);
                }
            }

            if (address(priceFeed.fallbackCaller()) == address(0)) {
                assertWithMsg(
                    statusAfter == IPriceFeed.Status.chainlinkWorking ||
                        statusAfter == IPriceFeed.Status.usingChainlinkFallbackUntrusted ||
                        statusAfter == IPriceFeed.Status.bothOraclesUntrusted,
                    PF_06
                );
            }

            statusHistory[(statusHistoryOperations++) % MAX_STATUS_HISTORY_OPERATIONS] = statusAfter;
            if (statusHistoryOperations >= MAX_STATUS_HISTORY_OPERATIONS) {
                // TODO: this is hard to test, as we may have false positives due to the random nature of the tests
                // assertWithMsg(_hasNotDeadlocked(), PF_03);
            }

            return price;
        } catch {
            assertWithMsg(false, PF_01);
        }
    }

    function _isValidStatusTransition(
        IPriceFeed.Status statusBefore,
        IPriceFeed.Status statusAfter
    ) internal returns (bool) {
        emit Log2("status transition", uint256(statusBefore), uint256(statusAfter));
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

    function _hasNotDeadlocked() internal returns (bool) {
        uint256 statusSeen = 0;

        for (uint256 i = 0; i < MAX_STATUS_HISTORY_OPERATIONS; ++i) {
            IPriceFeed.Status status = statusHistory[i];
            statusSeen |= (1 << uint256(status));
        }

        // has not deadlocked if during past MAX_STATUS_HISTORY_OPERATIONS all statuses have been seen
        // Note: there is a probability of false positive
        return statusSeen == 31; // 0b1111
    }

    function _selectFeed(uint256 feedId) private returns (MockAggregator) {
        feedId = clampBetween(feedId, 0, 2);
        if (feedId == 0) {
            return collEthCLFeed;
        } else if (feedId == 1) {
            return btcUsdCLFeed;
        } else {
            return ethUsdCLFeed;
        }
    }

    modifier log() {
        for (uint256 i = 0; i < MAX_STATUS_HISTORY_OPERATIONS; ++i) {
            IPriceFeed.Status status = statusHistory[i];
            emit Log2("status", i, uint256(status));
        }
        _;
    }
}
