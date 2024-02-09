// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {MockAggregator} from "../contracts/TestContracts/MockAggregator.sol";
import {ChainlinkAdapter} from "../contracts/ChainlinkAdapter.sol";
import {PriceFeedTester} from "../contracts/TestContracts/PriceFeedTester.sol";

// Integration test of the Price Feed
contract PriceFeedChainlinkAdapterTest is Test {
    MockAggregator internal usdBtcAggregator;
    MockAggregator internal ethUsdAggregator;
    MockAggregator internal stEthEthAggregator;
    ChainlinkAdapter internal chainlinkAdapter;
    PriceFeedTester internal priceFeed;

    function setUp() public {
        vm.warp(3);

        usdBtcAggregator = new MockAggregator(8);
        ethUsdAggregator = new MockAggregator(8);
        stEthEthAggregator = new MockAggregator(18);
        chainlinkAdapter = new ChainlinkAdapter(usdBtcAggregator, ethUsdAggregator);

        stEthEthAggregator.setLatestRoundId(2);
        stEthEthAggregator.setPrevRoundId(1);
        stEthEthAggregator.setPrice(1 ether - 3);
        stEthEthAggregator.setPrevPrice(1 ether - 1337);
        stEthEthAggregator.setUpdateTime(block.timestamp);
        stEthEthAggregator.setPrevUpdateTime(block.timestamp);

        usdBtcAggregator.setLatestRoundId(110680464442257320246);
        usdBtcAggregator.setPrevRoundId(110680464442257320245);
        usdBtcAggregator.setPrice(3983705362408);
        usdBtcAggregator.setPrevPrice(3983705362408);
        usdBtcAggregator.setUpdateTime(block.timestamp);

        ethUsdAggregator.setLatestRoundId(110680464442257320664);
        ethUsdAggregator.setPrevRoundId(110680464442257320663);
        ethUsdAggregator.setPrice(221026137517);
        ethUsdAggregator.setPrevPrice(221026137517);
        ethUsdAggregator.setUpdateTime(block.timestamp);

        priceFeed = new PriceFeedTester(
            address(0),
            address(0),
            address(stEthEthAggregator),
            address(chainlinkAdapter),
            false // Use fixed adapter
        );
    }

    function testIntegrationLatestRound() public {
        usdBtcAggregator.setLatestRoundId(110680464442257320247);
        usdBtcAggregator.setPrevRoundId(110680464442257320246);
        usdBtcAggregator.setPrice(3983705362408);
        usdBtcAggregator.setUpdateTime(1706208946);

        ethUsdAggregator.setLatestRoundId(110680464442257320665);
        ethUsdAggregator.setPrevRoundId(110680464442257320664);
        ethUsdAggregator.setPrice(221026137517);
        ethUsdAggregator.setUpdateTime(1706208947);

        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = chainlinkAdapter.latestRoundData();

        assertEq(answer, 55482551396170026);
        assertEq(roundId, chainlinkAdapter.CURRENT_ROUND());
        assertEq(updatedAt, 1706208946);

        priceFeed.fetchPrice();
    }
}
