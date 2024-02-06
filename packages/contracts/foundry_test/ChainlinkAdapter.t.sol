// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {MockAggregator} from "../contracts/TestContracts/MockAggregator.sol";
import {ChainlinkAdapter} from "../contracts/ChainlinkAdapter.sol";

contract ChainlinkAdapterTest is Test {
    MockAggregator internal usdBtcAggregator;
    MockAggregator internal ethUsdAggregator;
    ChainlinkAdapter internal chainlinkAdapter;

    function setUp() public {
        usdBtcAggregator = new MockAggregator(8);
        ethUsdAggregator = new MockAggregator(8);
        chainlinkAdapter = new ChainlinkAdapter(usdBtcAggregator, ethUsdAggregator);
    }

    function testGetLatestRound() public {
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
    }

    function testGetRoundDataCurrent() public {
        usdBtcAggregator.setLatestRoundId(110680464442257320247);
        usdBtcAggregator.setPrevRoundId(110680464442257320246);
        usdBtcAggregator.setPrice(3983705362408);
        usdBtcAggregator.setPrevPrice(3983705362407);
        usdBtcAggregator.setUpdateTime(1706208946);

        ethUsdAggregator.setLatestRoundId(110680464442257320665);
        ethUsdAggregator.setPrevRoundId(110680464442257320664);
        ethUsdAggregator.setPrice(221026137517);
        ethUsdAggregator.setPrevPrice(221026137516);
        ethUsdAggregator.setUpdateTime(1706208947);

        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = chainlinkAdapter.getRoundData(chainlinkAdapter.CURRENT_ROUND());

        assertEq(answer, 55482551396170026);
        assertEq(roundId, chainlinkAdapter.CURRENT_ROUND());
        assertEq(updatedAt, 1706208946);
    }

    function testGetRoundDataPrevious() public {
        usdBtcAggregator.setLatestRoundId(110680464442257320247);
        usdBtcAggregator.setPrevRoundId(110680464442257320246);
        usdBtcAggregator.setPrice(3983705362408);
        usdBtcAggregator.setPrevPrice(3983705362407);
        usdBtcAggregator.setUpdateTime(1706208947);

        ethUsdAggregator.setLatestRoundId(110680464442257320665);
        ethUsdAggregator.setPrevRoundId(110680464442257320664);
        ethUsdAggregator.setPrice(221026137517);
        ethUsdAggregator.setPrevPrice(221026137516);
        ethUsdAggregator.setUpdateTime(1706208947);

        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = chainlinkAdapter.getRoundData(chainlinkAdapter.PREVIOUS_ROUND());

        assertEq(answer, 55482551395932930);
        assertEq(roundId, chainlinkAdapter.PREVIOUS_ROUND());
    }

    function testGetRoundDataBadRoundId() public {
        vm.expectRevert();
        chainlinkAdapter.getRoundData(0);

        vm.expectRevert();
        chainlinkAdapter.getRoundData(3);
    }
}
