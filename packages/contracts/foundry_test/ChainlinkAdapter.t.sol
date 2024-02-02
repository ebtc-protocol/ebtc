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
        usdBtcAggregator.setPrice(3983705362408);
        usdBtcAggregator.setUpdateTime(1706208947);

        ethUsdAggregator.setLatestRoundId(110680464442257320665);
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
    }
}
