// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {MockAggregator} from "../contracts/TestContracts/MockAggregator.sol";
import {ChronicleAdapter} from "../contracts/ChronicleAdapter.sol";

contract ChainlinkAdapterTest is Test {
    MockAggregator internal stEthBtcAggregator;
    ChronicleAdapter internal chronicleAdapter;

    constructor() {}

    function testSuccessPrecision8() public {
        stEthBtcAggregator = new MockAggregator(8);
        chronicleAdapter = new ChronicleAdapter(address(stEthBtcAggregator));

        stEthBtcAggregator.setUpdateTime(block.timestamp);
        stEthBtcAggregator.setPrice(5341495);

        assertEq(chronicleAdapter.fetchPrice(), 53414950000000000);
    }

    function testSuccessPrecision18() public {
        stEthBtcAggregator = new MockAggregator(18);
        chronicleAdapter = new ChronicleAdapter(address(stEthBtcAggregator));

        stEthBtcAggregator.setUpdateTime(block.timestamp);
        stEthBtcAggregator.setPrice(53414952714851023);

        assertEq(chronicleAdapter.fetchPrice(), 53414952714851023);
    }

    function testFailureFreshness() public {
        stEthBtcAggregator = new MockAggregator(18);
        chronicleAdapter = new ChronicleAdapter(address(stEthBtcAggregator));

        stEthBtcAggregator.setUpdateTime(block.timestamp - 24 hours - 1);
        stEthBtcAggregator.setPrice(100e18);

        vm.expectRevert("ChronicleAdapter: stale price");
        chronicleAdapter.fetchPrice();
    }
}
