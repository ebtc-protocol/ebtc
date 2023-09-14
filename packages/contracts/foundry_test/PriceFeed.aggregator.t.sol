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

contract PriceFeedAggregatorTest is eBTCBaseFixture {
    address constant STETH_ETH_CL_FEED = 0x86392dC19c0b719886221c78AB11eb8Cf5c52812;

    PriceFeedTester internal priceFeedTester;
    TellorCaller internal _tellorCaller;
    MockTellor internal _mockTellor;
    MockAggregator internal _mockChainLinkEthBTC;
    MockAggregator internal _mockChainLinkStEthETH;
    uint80 internal latestRoundId = 321;
    int256 internal initEthBTCPrice = 1 ether - 3;
    int256 internal initStEthETHPrice = 3 ether - 2;
    int256 internal initEthBTCPrevPrice = 1 ether - 1337;
    int256 internal initStEthETHPrevPrice = 3 ether - 42;

    address internal authUser;
    event FeedActionOption(uint _action);

    function setUp() public override {
        eBTCBaseFixture.setUp();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();

        // Set current and prev prices in both oracles
        _mockChainLinkEthBTC = new MockAggregator();
        _initMockChainLinkFeed(
            _mockChainLinkEthBTC,
            latestRoundId,
            initEthBTCPrice,
            initEthBTCPrevPrice,
            8
        );
        _mockChainLinkStEthETH = new MockAggregator();
        _initMockChainLinkFeed(
            _mockChainLinkStEthETH,
            latestRoundId,
            initStEthETHPrice,
            initStEthETHPrevPrice,
            18
        );

        priceFeedTester = new PriceFeedTester(
            address(0),
            address(authority),
            address(_mockChainLinkStEthETH),
            address(_mockChainLinkEthBTC)
        );

        // Grant permission on pricefeed
        authUser = _utils.getNextUserAddress();
        vm.startPrank(defaultGovernance);
        authority.setUserRole(authUser, 4, true);
        authority.setRoleCapability(4, address(priceFeedTester), SET_FALLBACK_CALLER_SIG, true);
        vm.stopPrank();
    }

    function _initMockChainLinkFeed(
        MockAggregator _mockFeed,
        uint80 _latestRoundId,
        int256 _price,
        int256 _prevPrice,
        uint8 _decimal
    ) internal {
        _mockFeed.setLatestRoundId(_latestRoundId);
        _mockFeed.setPrevRoundId(_latestRoundId - 1);
        _mockFeed.setPrice(_price);
        _mockFeed.setPrevPrice(_prevPrice);
        _mockFeed.setDecimals(_decimal);
        _mockFeed.setUpdateTime(block.timestamp);
    }

    function testSetDecimals() public {
        _mockChainLinkEthBTC.setDecimals(31);
        _mockChainLinkStEthETH.setDecimals(8);

        // 10**31 *
        // 10**18 *
        // 10**18 *
        // 10**18 / 10 ** (31 * 2);

        vm.expectRevert();
        priceFeedTester.fetchPrice();
    }
}
