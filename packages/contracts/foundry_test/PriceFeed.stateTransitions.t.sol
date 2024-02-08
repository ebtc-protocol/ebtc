// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {IPriceFeed} from "../contracts/Interfaces/IPriceFeed.sol";
import {PriceFeed} from "../contracts/PriceFeed.sol";
import {PriceFeedTester} from "../contracts/TestContracts/PriceFeedTester.sol";
import {MockTellor} from "../contracts/TestContracts/MockTellor.sol";
import {MockAggregator} from "../contracts/TestContracts/MockAggregator.sol";
import {eBTCBaseInvariants} from "./BaseInvariants.sol";
import {TellorCaller} from "../contracts/Dependencies/TellorCaller.sol";
import {AggregatorV3Interface} from "../contracts/Dependencies/AggregatorV3Interface.sol";

contract PriceFeedStateTransitionTest is eBTCBaseInvariants {
    address constant STETH_ETH_CL_FEED = 0x86392dC19c0b719886221c78AB11eb8Cf5c52812;

    PriceFeedTester internal priceFeedTester;
    TellorCaller internal _tellorCaller;
    MockTellor internal _mockTellor;
    MockAggregator internal _mockChainLinkEthBTC;
    MockAggregator internal _mockChainLinkStEthETH;
    uint80 internal latestRoundId = 321;
    int256 internal initEthBTCPrice = 7428000;
    int256 internal initStEthETHPrice = 9999e14;
    uint256 internal initStEthBTCPrice = 7428e13;
    uint256 internal tellorTimeout = 600;
    address internal authUser;
    event FeedActionOption(uint256 _action);

    function setUp() public override {
        super.setUp();
        super.connectCoreContracts();
        super.connectLQTYContractsToCore();

        // Set current and prev prices in both oracles
        _mockChainLinkEthBTC = new MockAggregator(8);
        _initMockChainLinkFeed(_mockChainLinkEthBTC, latestRoundId, initEthBTCPrice);
        _mockChainLinkStEthETH = new MockAggregator(18);
        _initMockChainLinkFeed(_mockChainLinkStEthETH, latestRoundId, initStEthETHPrice);
        _mockTellor = new MockTellor();
        _initMockTellor(initStEthBTCPrice);
        _tellorCaller = new TellorCaller(address(_mockTellor));
        _tellorCaller.setFallbackTimeout(tellorTimeout);

        // NOTE: fork at `17210175`. my local timestamp is playing funny
        //        vm.warp(1683478511);
        //        uint256 prevRoundId = 18446744073709552244;
        // NOTE: force to mock it up, since `updateAt` was 1d old, triggers `TIMEOUT`
        //        vm.mockCall(
        //            STETH_ETH_CL_FEED,
        //            abi.encodeWithSelector(AggregatorV3Interface.getRoundData.selector, prevRoundId),
        //            abi.encode(prevRoundId, 966009470097829100, 1662456296, 1683478511, prevRoundId)
        //        );
        priceFeedTester = new PriceFeedTester(
            address(_tellorCaller),
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
        authority.setRoleCapability(
            4,
            address(priceFeedTester),
            SET_COLLATERAL_FEED_SOURCE_SIG,
            true
        );
        vm.stopPrank();
    }

    function _initMockChainLinkFeed(
        MockAggregator _mockFeed,
        uint80 _latestRoundId,
        int256 _price
    ) internal {
        _mockFeed.setLatestRoundId(_latestRoundId);
        _mockFeed.setPrevRoundId(_latestRoundId - 1);
        _mockFeed.setPrice(_price);
        _mockFeed.setPrevPrice(_price);
        _mockFeed.setUpdateTime(block.timestamp);
    }

    function _initMockTellor(uint256 _price) internal {
        _mockTellor.setPrice(_price);
        _mockTellor.setUpdateTime(block.timestamp);
    }

    function testRandomPriceFeedActions(int256 _actions, int128 _rnd) public {
        _actions = int128(bound(_actions, 1, 5));
        _rnd = int128(bound(_rnd, 1, type(int128).max));

        IPriceFeed.Status startStatus = priceFeedTester.status();

        for (int i = 0; i < _actions; i++) {
            uint256 _choice = (
                _utils.generateRandomNumber(
                    uint256(i),
                    uint256(int256(_rnd) + _actions),
                    address(this)
                )
            ) % 10;
            emit FeedActionOption(_choice);
            if (_choice == 0) {
                _breakChainlinkResponse(_mockChainLinkStEthETH);
            } else if (_choice == 1) {
                _breakFallbackResponse();
            } else if (_choice == 2) {
                _frozeChainlink(_mockChainLinkStEthETH);
            } else if (_choice == 3) {
                _frozeFallback();
            } else if (_choice == 4) {
                _makeChainlinkPriceChangeAboveMax(_mockChainLinkStEthETH);
            } else if (_choice == 5) {
                _makeFeedsDeviate();
            } else if (_choice == 6) {
                _brickFallackFeed();
            } else if (_choice == 7) {
                _restoreFallackFeed();
            } else if (_choice == 8) {
                _restoreChainlinkPriceAndTimestamp(_mockChainLinkStEthETH, initStEthETHPrice);
                _restoreChainlinkPriceAndTimestamp(_mockChainLinkEthBTC, initEthBTCPrice);
            } else if (_choice == 9) {
                _restoreFallbackPriceAndTimestamp(initStEthBTCPrice);
            }
            priceFeedTester.fetchPrice();

            IPriceFeed.Status expectedStatus = _getExpectedStatusFromFetchPrice(startStatus);
            IPriceFeed.Status endStatus = priceFeedTester.status();
            require(expectedStatus == endStatus, "!PriceFeed end status mismatch from expectation");
            startStatus = endStatus;
        }
    }

    function testStateTransitions() public {
        // Pick a random starting state
        // Set variables to match that state
        // Fuzz actions
        // set prices
        // set broken or frozen statuses
        // setFallbackCaller
        // fetchPrice
        // Ensure the state after fetchPrice() is correct, given the inputs
    }

    function testStateTransitionsWithOracleFallback() public {}

    function testPriceChangeOver50PerCentWithoutFallback() public {
        // set empty fallback
        _brickFallackFeed();

        uint256 lastGoodPrice = priceFeedTester.lastGoodPrice();

        // Price change over 50%
        int256 newEthBTCPrice = (initEthBTCPrice * 2) + 1;
        _mockChainLinkEthBTC.setPrice(newEthBTCPrice);

        // Get price
        uint256 newPrice = priceFeedTester.fetchPrice();
        IPriceFeed.Status status = priceFeedTester.status();
        assertEq(newPrice, lastGoodPrice); // last good price is used
        assertEq(uint256(status), 2); // bothOraclesUntrusted

        // Get price again in the same block (no changes in ChainLink price)
        newPrice = priceFeedTester.fetchPrice();
        status = priceFeedTester.status();
        assertEq(newPrice, lastGoodPrice); // still lastGoodPrice is used
        assertEq(uint256(status), 2); // still bothOraclesUntrusted due to CL report 50% deviation
    }

    function testPriceChangeOver50PerCentWithFallback() public {
        // froze CL
        _frozeChainlink(_mockChainLinkEthBTC);

        // update state machine
        priceFeedTester.fetchPrice();
        IPriceFeed.Status status = priceFeedTester.status();
        assertEq(uint256(status), 3); // usingFallbackChainlinkFrozen
        uint256 lastGoodPrice = priceFeedTester.lastGoodPrice();

        // Now restore CL response time but with price change over 50%
        int256 newEthBTCPrice = (initEthBTCPrice * 2) + 1;
        _restoreChainlinkPriceAndTimestamp(_mockChainLinkEthBTC, newEthBTCPrice);
        _restoreChainlinkPriceAndTimestamp(_mockChainLinkStEthETH, initStEthETHPrice);

        // update fallback price
        uint256 _newPrice = lastGoodPrice + 1234567890123;
        _restoreFallbackPriceAndTimestamp(_newPrice);

        // update state machine again
        uint256 _price = priceFeedTester.fetchPrice();
        status = priceFeedTester.status();
        assertEq(_price, _newPrice); // still using fallback price
        assertEq(uint256(status), 1); // usingFallbackChainlinkUntrusted
    }

    /// @dev We expect there to be a previous chainlink response on system init, real-world oracles used will have this property
    function _getOracleResponses()
        internal
        returns (
            PriceFeed.ChainlinkResponse memory chainlinkResponse,
            PriceFeed.ChainlinkResponse memory prevChainlinkResponse,
            PriceFeed.FallbackResponse memory fallbackResponse
        )
    {
        // Get oracle responses
        chainlinkResponse = priceFeedTester.getCurrentChainlinkResponse();

        prevChainlinkResponse = priceFeedTester.getPrevChainlinkResponse(
            chainlinkResponse.roundEthBtcId - 1,
            chainlinkResponse.roundStEthEthId - 1
        );

        fallbackResponse = priceFeedTester.getCurrentFallbackResponse();
    }

    /// @dev Get expected end status on fetchPrice() given current sysstem state
    function _getExpectedStatusFromFetchPrice(
        IPriceFeed.Status _status
    ) internal returns (IPriceFeed.Status newStatus) {
        PriceFeed.ChainlinkResponse memory chainlinkResponse;
        PriceFeed.ChainlinkResponse memory prevChainlinkResponse;
        PriceFeed.FallbackResponse memory fallbackResponse;

        (chainlinkResponse, prevChainlinkResponse, fallbackResponse) = _getOracleResponses();
        /**
            - CL broken or frozen?
            - FB broken or frozen? If no fallback, we will return broken (timestamp is zero, and value is zero)
            - CL current price >50% deviation from previous price?
            - CL and FB prices valid and >5% difference?
         */

        // Confirm that a broken and frozen oracle returns broken first, how do the conditions overlap?
        bool chainlinkFrozen = priceFeedTester.chainlinkIsFrozen(chainlinkResponse);
        bool chainlinkBroken = priceFeedTester.chainlinkIsBroken(
            chainlinkResponse,
            prevChainlinkResponse
        );

        bool fallbackFrozen = address(priceFeedTester.fallbackCaller()) == address(0)
            ? false
            : priceFeedTester.fallbackIsFrozen(fallbackResponse);
        bool fallbackBroken = priceFeedTester.fallbackIsBroken(fallbackResponse);

        bool bothOraclesSimilarPrice = priceFeedTester.bothOraclesSimilarPrice(
            chainlinkResponse,
            fallbackResponse
        );
        bool bothOraclesAliveAndUnrokenSimilarPrice = priceFeedTester
            .bothOraclesAliveAndUnbrokenAndSimilarPrice(
                chainlinkResponse,
                prevChainlinkResponse,
                fallbackResponse
            );
        bool chainlinkPriceChangeAboveMax = priceFeedTester.chainlinkPriceChangeAboveMax(
            chainlinkResponse,
            prevChainlinkResponse
        );

        IPriceFeed.Status currentStatus = _status;

        // --- CASE 1: System fetched last price from Chainlink  ---
        if (currentStatus == IPriceFeed.Status.chainlinkWorking) {
            if (chainlinkBroken) {
                if (fallbackBroken) {
                    // CL Broken + FL Broken
                    newStatus = IPriceFeed.Status.bothOraclesUntrusted;
                } else {
                    // CL Broken + [FL Frozen OR FL Working]
                    newStatus = IPriceFeed.Status.usingFallbackChainlinkUntrusted;
                }
            } else if (chainlinkFrozen) {
                if (fallbackBroken) {
                    // CL Frozen + FL Broken
                    newStatus = IPriceFeed.Status.usingChainlinkFallbackUntrusted;
                } else {
                    // [FL is working OR frozen] + [CL Frozen OR FL Working]
                    newStatus = IPriceFeed.Status.usingFallbackChainlinkFrozen;
                }
            } else if (chainlinkPriceChangeAboveMax) {
                if (fallbackBroken) {
                    // CL >50% change from last round + FB Broken
                    newStatus = IPriceFeed.Status.bothOraclesUntrusted;
                } else if (fallbackFrozen) {
                    // CL >50% change from last round + FB Frozen
                    newStatus = IPriceFeed.Status.usingFallbackChainlinkUntrusted;
                } else if (bothOraclesSimilarPrice) {
                    // CL >50% change from last round + CL/FB Price <=5% difference
                    newStatus = currentStatus;
                } else {
                    // CL >50% change from last round + CL/FB Price >5% difference
                    newStatus = IPriceFeed.Status.usingFallbackChainlinkUntrusted;
                }
            }
            // CL Working
            else if (fallbackBroken) {
                newStatus = IPriceFeed.Status.usingChainlinkFallbackUntrusted;
            } else {
                newStatus = currentStatus;
            }
        }
        // --- CASE 2: The system fetched last price from Fallback ---
        else if (currentStatus == IPriceFeed.Status.usingFallbackChainlinkUntrusted) {
            if (fallbackBroken) {
                // Fallback is now broken, and becomes untrusted
                // Use last good price as both oracles are untrusted
                newStatus = IPriceFeed.Status.bothOraclesUntrusted;
            } else if (bothOraclesAliveAndUnrokenSimilarPrice) {
                // CL and FB working, reporting similar prices (<5% difference)
                // Chainlink is now working, return to it
                newStatus = IPriceFeed.Status.chainlinkWorking;
            } else {
                // Fallback is working, and CL still isn't. Stay in same state
                // Use our new valid fallback price
                newStatus = currentStatus;
            }
        }
        // --- CASE 3: Both oracles were untrusted at the last price fetch ---
        else if (currentStatus == IPriceFeed.Status.bothOraclesUntrusted) {
            // Fallback isn't working so we can't compare the prices. Go ahead and trust CL for now that it's reporting and is the only valid oracle
            if (address(priceFeedTester.fallbackCaller()) == address(0)) {
                if (!chainlinkFrozen && !chainlinkBroken && !chainlinkPriceChangeAboveMax) {
                    // Chainlink is now working, return to it, but note that fallback is still untrusted
                    newStatus = IPriceFeed.Status.usingChainlinkFallbackUntrusted;
                } else {
                    newStatus = currentStatus;
                }
            } else if (bothOraclesAliveAndUnrokenSimilarPrice) {
                // CL and FB working, reporting similar prices (<5% difference)
                // Chainlink is now working, return to it
                // Both oracles are now trusted again
                newStatus = IPriceFeed.Status.chainlinkWorking;
            } else {
                newStatus = currentStatus;
            }
        }
        // --- CASE 4: Using Fallback, and Chainlink is frozen ---
        else if (currentStatus == IPriceFeed.Status.usingFallbackChainlinkFrozen) {
            if (chainlinkBroken) {
                if (fallbackBroken) {
                    // FB Broken
                    // Fallback is now broken, and becomes untrusted
                    // Use last good price as both oracles are untrusted
                    newStatus = IPriceFeed.Status.bothOraclesUntrusted;
                } else {
                    newStatus = IPriceFeed.Status.usingFallbackChainlinkUntrusted;
                }
            } else if (chainlinkFrozen) {
                if (fallbackBroken) {
                    newStatus = IPriceFeed.Status.usingChainlinkFallbackUntrusted;
                } else {
                    // FB Frozen
                    // Fallback is now frozen, but remains trusted as freezing can be temporary
                    // Use last good price as we don't have a newer price to use
                    newStatus = currentStatus;
                }
            } else if (chainlinkPriceChangeAboveMax) {
                if (fallbackBroken) {
                    // FB Broken
                    // Fallback is now broken, and becomes untrusted
                    // Use last good price as both oracles are untrusted
                    newStatus = IPriceFeed.Status.bothOraclesUntrusted;
                } else {
                    newStatus = IPriceFeed.Status.usingFallbackChainlinkUntrusted;
                }
            } else if (fallbackBroken) {
                // Chainlink is now working, return to it
                newStatus = IPriceFeed.Status.usingChainlinkFallbackUntrusted;
            } else if (fallbackFrozen) {
                // FB is working
                newStatus = currentStatus;
            } else if (bothOraclesSimilarPrice) {
                // CL and FB working, reporting similar prices (<5% difference)
                // Both oracles are now trusted again
                newStatus = IPriceFeed.Status.chainlinkWorking;
            } else {
                // the oracles are both working but reporting notably different prices
                newStatus = IPriceFeed.Status.usingFallbackChainlinkUntrusted;
            }
        }
        // --- CASE 5: Using Chainlink, Fallback is untrusted ---
        else if (currentStatus == IPriceFeed.Status.usingChainlinkFallbackUntrusted) {
            // CL Broken
            // Chainlink is now broken, and becomes untrusted. We still don't trust the FB here.
            if (chainlinkBroken) {
                newStatus = IPriceFeed.Status.bothOraclesUntrusted;
            }
            // CL Frozen
            // We still trust CL, but have no new price to report. Use last good price
            else if (chainlinkFrozen) {
                newStatus = currentStatus;
            }
            // CL is working, reporting suspiciously different price since previous round (>50% difference)
            // Stop trusting CL, and use last good price as we don't trust FB either
            else if (chainlinkPriceChangeAboveMax) {
                newStatus = IPriceFeed.Status.bothOraclesUntrusted;
            }
            // CL and FB working, reporting similar prices (<5% difference)
            // Both oracles are trusted now, use latest CL price
            else if (bothOraclesAliveAndUnrokenSimilarPrice) {
                if (address(priceFeedTester.fallbackCaller()) != address(0)) {
                    newStatus = IPriceFeed.Status.chainlinkWorking;
                } else {
                    newStatus = currentStatus;
                }
            }
            // CL is working, but FB is still not trusted (it's not live and reporting within 5% of a valid updated CL price)
            // Use CL price, and maintain this state ("chainlinkWorking" really means both oracles are trusted)
            else {
                newStatus = currentStatus;
            }
        }
    }

    ////////////////////////////////////////////////////////////////////////
    // Helper functions to price feed state transitions:
    // 1 - break CL feed
    // 2 - break FL feed
    // 3 - froze CL feed
    // 4 - froze FL feed
    // 5 - make CL feeds deviate
    // 6 - make CL & FL feeds deviate
    // 7 - brick FL feed
    // 8 - restore FL feed
    // 9 - restore CL feed price
    // 10 - restore FL feed price
    ////////////////////////////////////////////////////////////////////////

    function _breakChainlinkResponse(MockAggregator _mockFeed) internal {
        _mockFeed.setUpdateTime(0);
    }

    function _breakFallbackResponse() internal {
        _mockTellor.setUpdateTime(0);
    }

    function _frozeChainlink(MockAggregator _mockFeed) internal {
        _mockFeed.setUpdateTime(1);
        vm.warp(block.timestamp + priceFeedTester.TIMEOUT_STETH_ETH_FEED() + 1);
    }

    function _frozeFallback() internal {
        _mockTellor.setUpdateTime(1);
        vm.warp(block.timestamp + tellorTimeout + 1);
    }

    function _makeChainlinkPriceChangeAboveMax(MockAggregator _mockFeed) internal {
        if (_mockFeed.getPrice() < _mockFeed.getPrevPrice()) {
            _mockFeed.setPrice(1);
        } else {
            _mockFeed.setPrevPrice(1);
        }
    }

    function _makeFeedsDeviate() internal {
        int _clEthBTCPrice = _mockChainLinkEthBTC.getPrice();
        uint8 _clEthBTCDecimal = _mockChainLinkEthBTC.decimals();
        uint256 _clAnswer = priceFeedTester.formatClAggregateAnswer(
            _clEthBTCPrice,
            _mockChainLinkStEthETH.getPrice()
        );
        uint256 _flAnswer = _mockTellor.retrieveData(0, 0);
        if (_clAnswer < _flAnswer && _clAnswer > 0) {
            _mockTellor.setPrice(_clAnswer * 2);
        } else if (_clAnswer > _flAnswer && _flAnswer > 0) {
            _mockChainLinkStEthETH.setPrice(
                int256((_flAnswer * 2 * _clEthBTCDecimal) / uint256(_clEthBTCPrice))
            );
        }
    }

    function _brickFallackFeed() internal {
        vm.prank(authUser);
        priceFeedTester.setFallbackCaller(address(0));
        require(address(priceFeedTester.fallbackCaller()) == address(0), "!brickFallback");
    }

    function _restoreFallackFeed() internal {
        _restoreFallbackPriceAndTimestamp(initStEthBTCPrice);
        vm.prank(authUser);
        priceFeedTester.setFallbackCaller(address(_tellorCaller));
        require(
            address(priceFeedTester.fallbackCaller()) == address(_tellorCaller),
            "!restoreFallback"
        );
    }

    function _restoreChainlinkPriceAndTimestamp(MockAggregator _mockFeed, int256 _price) internal {
        _mockFeed.setPrice(_price);
        _mockFeed.setPrevPrice(_price);
        _mockFeed.setUpdateTime(block.timestamp);
    }

    function _restoreFallbackPriceAndTimestamp(uint256 _price) internal {
        _mockTellor.setPrice(_price);
        _mockTellor.setUpdateTime(block.timestamp);
    }
}
