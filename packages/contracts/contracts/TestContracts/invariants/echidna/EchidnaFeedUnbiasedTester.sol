// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@crytic/properties/contracts/util/PropertiesHelper.sol";
import "@crytic/properties/contracts/util/PropertiesConstants.sol";

import "../../../PriceFeed.sol";
import "../../MockAggregator.sol";
import {MockFallbackCaller} from "../../MockFallbackCaller.sol";
import "../../../Dependencies/AuthNoOwner.sol";

import "../PropertiesDescriptions.sol";

import "@crytic/properties/contracts/util/Hevm.sol";

contract MockAlwaysTrueAuthority {
    function canCall(address user, address target, bytes4 functionSig) external view returns (bool){
        return true;
    }
}

contract EchidnaFeedUnbiasedTester is PropertiesConstants, PropertiesAsserts, PropertiesDescriptions {
    event Log2(string, uint256, uint256);
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
    uint256 internal constant MIN_FALLBACK_VALUE = 1;
    
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

        fallbackCaller.setFallbackResponse(priceFeed.lastGoodPrice() - 10, block.timestamp, true);

        statusHistory[(statusHistoryOperations++) % MAX_STATUS_HISTORY_OPERATIONS] = priceFeed
            .status();
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
                fallbackCaller._timestampRetrieved(),
                fallbackCaller._timestampRetrieved() + MAX_UPDATE_TIME_CHANGE
            )
        );
        fallbackCaller.setFallbackResponse(answer, timestampRetrieved, success);
    }

    function setGetFallbackResponseRevert() public {
        fallbackCaller.setGetFallbackResponseRevert();
    }

    function setLatestRevert(bool flag) public log {
        MockAggregator aggregator = flag ? collEthCLFeed : ethBtcCLFeed;
        aggregator.setLatestRevert();
    }

    function setPrevRevert(bool flag) public log {
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

    function setLatestEth(uint80 latestRoundId, uint256 price, uint256 updateTime) public log {
        (uint80 roundId, int256 answer, , uint256 updatedAt, ) = collEthCLFeed.latestRoundData();

        latestRoundId = uint80(
            clampBetween(
                uint256(latestRoundId),
                uint256(roundId),
                uint256(roundId + MAX_ROUND_ID_CHANGE)
            )
        );
        // NOTE: Updated to clamp based on proper realistic prices
        price = clampBetween(
                price,
                MIN_ETH_VALUE,
                MAX_ETH_VALUE
            );

        updateTime = (clampBetween(updateTime, updatedAt, updatedAt + MAX_UPDATE_TIME_CHANGE));
        
        collEthCLFeed.setLatestRoundId(latestRoundId);
        collEthCLFeed.setPrice(int256(price));
        collEthCLFeed.setUpdateTime(updateTime);
    }

    function setPreviousEth(
        uint80 prevRoundId,
        uint256 prevPrice,
        uint256 prevUpdateTime,
        bool flag
    ) public log {
        (uint80 roundId, int256 answer, , uint256 updatedAt, ) = collEthCLFeed.getRoundData(0);
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
                MIN_ETH_VALUE,
                MAX_ETH_VALUE
            )
        );
        prevUpdateTime = (
            clampBetween(prevUpdateTime, updatedAt, updatedAt + MAX_UPDATE_TIME_CHANGE)
        );
        collEthCLFeed.setPrevRoundId(prevRoundId);
        collEthCLFeed.setPrevPrice(int256(prevPrice));
        collEthCLFeed.setPrevUpdateTime(prevUpdateTime);
    }

    function setLatestBTC(uint80 latestRoundId, uint256 price, uint256 updateTime) public log {
        (uint80 roundId, int256 answer, , uint256 updatedAt, ) = ethBtcCLFeed.latestRoundData();

        latestRoundId = uint80(
            clampBetween(
                uint256(latestRoundId),
                uint256(roundId),
                uint256(roundId + MAX_ROUND_ID_CHANGE)
            )
        );
        // NOTE: Updated to clamp based on proper realistic prices
        price = (
            clampBetween(
                price,
                MIN_BTC_VALUE,
                MAX_BTC_VALUE
            )
        );

        updateTime = (clampBetween(updateTime, updatedAt, updatedAt + MAX_UPDATE_TIME_CHANGE));
        
        ethBtcCLFeed.setLatestRoundId(latestRoundId);
        ethBtcCLFeed.setPrice(int256(price));
        ethBtcCLFeed.setUpdateTime(updateTime);
    }


    function setPreviousBTC(
        uint80 prevRoundId,
        uint256 prevPrice,
        uint256 prevUpdateTime,
        bool flag
    ) public log {
        (uint80 roundId, int256 answer, , uint256 updatedAt, ) = ethBtcCLFeed.getRoundData(0);
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
                MIN_BTC_VALUE,
                MAX_BTC_VALUE
            )
        );
        prevUpdateTime = (
            clampBetween(prevUpdateTime, updatedAt, updatedAt + MAX_UPDATE_TIME_CHANGE)
        );
        ethBtcCLFeed.setPrevRoundId(prevRoundId);
        ethBtcCLFeed.setPrevPrice(int256(prevPrice));
        ethBtcCLFeed.setPrevUpdateTime(prevUpdateTime);
    }

    function fetchPriceBatch() public log {
        uint256 price = _fetchPrice();
        for (uint256 i; i < 2; i++) {
            uint256 newPrice = _fetchPrice();
            assertWithMsg(price == newPrice, "PRICE BAD");
        }
    }

    function fetchPrice() public log {
        _fetchPrice();
    }

    function _fetchPrice() private returns (uint256) {
        IPriceFeed.Status statusBefore = priceFeed.status();
        uint256 fallbackResponse;

        if (address(priceFeed.fallbackCaller()) != address(0)) {
            try fallbackCaller.getFallbackResponse() returns (uint256 res, uint256 , bool) {
                fallbackResponse = res;
            } catch {

            }
        }
        
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

    modifier log() {
        for (uint256 i = 0; i < MAX_STATUS_HISTORY_OPERATIONS; ++i) {
            IPriceFeed.Status status = statusHistory[i];
            emit Log2("status", i, uint256(status));
        }
        _;
    }
}