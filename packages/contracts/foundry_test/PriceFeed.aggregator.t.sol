// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {IPriceFeed} from "../contracts/Interfaces/IPriceFeed.sol";
import {PriceFeed} from "../contracts/PriceFeed.sol";
import {PriceFeedTester} from "../contracts/TestContracts/PriceFeedTester.sol";
import {PriceFeedTestnet} from "../contracts/TestContracts/testnet/PriceFeedTestnet.sol";
import {PriceFeedOracleTester} from "../contracts/TestContracts/PriceFeedOracleTester.sol";
import {MockTellor} from "../contracts/TestContracts/MockTellor.sol";
import {MockAggregator} from "../contracts/TestContracts/MockAggregator.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";
import {TellorCaller} from "../contracts/Dependencies/TellorCaller.sol";
import {AggregatorV3Interface} from "../contracts/Dependencies/AggregatorV3Interface.sol";

contract PriceFeedAggregatorTest is eBTCBaseFixture {
    address constant STETH_ETH_CL_FEED = 0x86392dC19c0b719886221c78AB11eb8Cf5c52812;

    PriceFeedTester internal priceFeedTester;
    PriceFeedTestnet internal priceFeedSecondary;
    PriceFeedOracleTester internal secondaryOracle;
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
        _mockChainLinkEthBTC = new MockAggregator(8);
        _initMockChainLinkFeed(
            _mockChainLinkEthBTC,
            latestRoundId,
            initEthBTCPrice,
            initEthBTCPrevPrice
        );
        _mockChainLinkStEthETH = new MockAggregator(18);
        _initMockChainLinkFeed(
            _mockChainLinkStEthETH,
            latestRoundId,
            initStEthETHPrice,
            initStEthETHPrevPrice
        );

        priceFeedTester = new PriceFeedTester(
            address(0),
            address(authority),
            address(_mockChainLinkStEthETH),
            address(_mockChainLinkEthBTC),
            true
        );

        // Grant permission on pricefeed
        authUser = _utils.getNextUserAddress();
        vm.startPrank(defaultGovernance);
        authority.setUserRole(authUser, 4, true);
        authority.setRoleCapability(4, address(priceFeedTester), SET_FALLBACK_CALLER_SIG, true);
        vm.stopPrank();

        priceFeedSecondary = new PriceFeedTestnet(address(authority));
        secondaryOracle = new PriceFeedOracleTester(address(priceFeedSecondary));
    }

    function _initMockChainLinkFeed(
        MockAggregator _mockFeed,
        uint80 _latestRoundId,
        int256 _price,
        int256 _prevPrice
    ) internal {
        _mockFeed.setLatestRoundId(_latestRoundId);
        _mockFeed.setPrevRoundId(_latestRoundId - 1);
        _mockFeed.setPrice(_price);
        _mockFeed.setPrevPrice(_prevPrice);
        _mockFeed.setUpdateTime(block.timestamp);
    }

    function testPrimaryFeedSuccess() public {
        priceFeedMock.setPrice(1e18);
        assertEq(ebtcFeed.fetchPrice(), 1e18);
    }

    function testPrimaryFeedFail() public {
        priceFeedMock.setPrice(1e18);

        // Store last good price (1e18)
        ebtcFeed.fetchPrice();

        // Updating primary price should have no effect
        priceFeedMock.setPrice(1.15e18);

        // Check all error states (no fallback, returns last known state)
        for (uint256 i = 1; i < uint256(PriceFeedOracleTester.ErrorState.COUNT); i++) {
            primaryOracle.setErrorState(PriceFeedOracleTester.ErrorState(i));
            assertEq(ebtcFeed.fetchPrice(), 1e18);
        }

        vm.prank(defaultGovernance);
        ebtcFeed.setSecondaryOracle(address(secondaryOracle));

        // Updating prices should have no effect
        priceFeedMock.setPrice(1.2e18);
        priceFeedSecondary.setPrice(1.1e18);

        // Check all error states (with secondary, returns secondary price = 1.1e18)
        for (uint256 i = 1; i < uint256(PriceFeedOracleTester.ErrorState.COUNT); i++) {
            primaryOracle.setErrorState(PriceFeedOracleTester.ErrorState(i));
            assertEq(ebtcFeed.fetchPrice(), 1.1e18);
        }

        // Updating prices should have no effect
        priceFeedMock.setPrice(1.25e18);
        priceFeedSecondary.setPrice(1.15e18);

        // Both primary and secondary failing, return last known price 1.1e18
        for (uint256 i = 1; i < uint256(PriceFeedOracleTester.ErrorState.COUNT); i++) {
            primaryOracle.setErrorState(PriceFeedOracleTester.ErrorState(i));
            for (uint256 j = 1; j < uint256(PriceFeedOracleTester.ErrorState.COUNT); j++) {
                secondaryOracle.setErrorState(PriceFeedOracleTester.ErrorState(j));
                assertEq(ebtcFeed.fetchPrice(), 1.1e18);
            }
        }
    }

    function testCollateralFeedSources() public {
        _mockChainLinkEthBTC.setPrice(0.05e8);
        _mockChainLinkEthBTC.setPrevPrice(0.05e8);
        _mockChainLinkStEthETH.setPrice(0.9e18);
        _mockChainLinkStEthETH.setPrevPrice(0.9e18);

        // Dynamic feed price (0.05 * 0.9)
        assertEq(priceFeedTester.fetchPrice(), 45000000000000000);

        // Can't set collateral feed source without auth
        vm.startPrank(authUser);
        vm.expectRevert("Auth: UNAUTHORIZED");
        priceFeedTester.setCollateralFeedSource(false);
        vm.stopPrank();

        // Give auth
        vm.startPrank(defaultGovernance);
        authority.setRoleCapability(
            4,
            address(priceFeedTester),
            SET_COLLATERAL_FEED_SOURCE_SIG,
            true
        );
        vm.stopPrank();

        // Can set collateral feed source
        vm.startPrank(authUser);
        priceFeedTester.setCollateralFeedSource(false);
        vm.stopPrank();

        // Fixed feed price (0.05 * 1.0)
        assertEq(priceFeedTester.fetchPrice(), 50000000000000000);

        vm.startPrank(authUser);
        priceFeedTester.setCollateralFeedSource(true);
        vm.stopPrank();

        // Back to dynamic price (0.05 * 0.9)
        assertEq(priceFeedTester.fetchPrice(), 45000000000000000);
    }
}
