// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./Interfaces/IPriceFeed.sol";
import "./Interfaces/IFallbackCaller.sol";
import "./Dependencies/AggregatorV3Interface.sol";
import "./Dependencies/BaseMath.sol";
import "./Dependencies/LiquityMath.sol";
import "./Dependencies/AuthNoOwner.sol";

/*
 * PriceFeed for mainnet deployment, it connects to two Chainlink's live feeds, ETH:BTC and
 * stETH:ETH, which are used to aggregate the price feed of stETH:BTC in conjuction.
 * It also allows for a fallback oracle to intervene in case that the primary Chainlink oracle fails.
 *
 * The PriceFeed uses Chainlink as primary oracle and allows for an optional fallback source. It contains logic for
 * switching oracles based on oracle failures, timeouts, and conditions for returning to the primary
 * Chainlink oracle. In addition, it contains the mechanism to add or remove the fallback oracle through governance.
 */
contract PriceFeed is BaseMath, IPriceFeed, AuthNoOwner {
    string public constant NAME = "PriceFeed";

    // Chainlink oracles
    AggregatorV3Interface public constant ETH_BTC_CL_FEED =
        AggregatorV3Interface(0xAc559F25B1619171CbC396a50854A3240b6A4e99);
    uint256 internal constant ETH_BTC_CL_FEED_DECIMAL = 8;
    AggregatorV3Interface public constant STETH_ETH_CL_FEED =
        AggregatorV3Interface(0x86392dC19c0b719886221c78AB11eb8Cf5c52812);
    uint256 internal constant STETH_ETH_CL_FEED_DECIMAL = 18;

    // Fallback feed
    IFallbackCaller public fallbackCaller; // Wrapper contract that calls the fallback system

    // Maximum time period allowed since Chainlink's latest round data timestamp, beyond which Chainlink is considered frozen.
    uint public constant TIMEOUT = 14400; // 4 hours: 60 * 60 * 4

    // -- Permissioned Function Signatures --
    bytes4 private constant SET_FALLBACK_CALLER_SIG =
        bytes4(keccak256(bytes("setFallbackCaller(address)")));

    // Maximum deviation allowed between two consecutive Chainlink oracle prices. 18-digit precision.
    uint public constant MAX_PRICE_DEVIATION_FROM_PREVIOUS_ROUND = 5e17; // 50%

    /*
     * The maximum relative price difference between two oracle responses allowed in order for the PriceFeed
     * to return to using the Chainlink oracle. 18-digit precision.
     */
    uint public constant MAX_PRICE_DIFFERENCE_BETWEEN_ORACLES = 5e16; // 5%

    // The last good price seen from an oracle by Liquity
    uint public lastGoodPrice;

    // The current status of the PriceFeed, which determines the conditions for the next price fetch attempt
    Status public status;

    // --- Dependency setters ---

    /*
        @notice Sets the addresses of the contracts and initializes the system
        @param _fallbackCallerAddress The address of the Fallback oracle contract
        @param _authorityAddress The address of the Authority contract
        @dev One time initiailziation function. The caller must be the PriceFeed contract's owner (i.e. eBTC Deployer contract) for security. Ownership is renounced after initialization. 
    **/
    constructor(address _fallbackCallerAddress, address _authorityAddress) {
        fallbackCaller = IFallbackCaller(_fallbackCallerAddress);

        _initializeAuthority(_authorityAddress);

        emit FallbackCallerChanged(_fallbackCallerAddress);

        // Get an initial price from Chainlink to serve as first reference for lastGoodPrice
        ChainlinkResponse memory chainlinkResponse = _getCurrentChainlinkResponse();
        ChainlinkResponse memory prevChainlinkResponse = _getPrevChainlinkResponse(
            chainlinkResponse.roundEthBtcId,
            chainlinkResponse.roundStEthEthId
        );

        require(
            !_chainlinkIsBroken(chainlinkResponse, prevChainlinkResponse) &&
                !_chainlinkIsFrozen(chainlinkResponse.timestamp),
            "PriceFeed: Chainlink must be working and current"
        );

        _storeChainlinkPrice(chainlinkResponse.answer);

        // Explicitly set initial system status after `require` checks
        status = Status.chainlinkWorking;
    }

    // --- Functions ---
    /*
        @notice Returns the latest price obtained from the Oracle
        @dev Called by eBTC functions that require a current price. Also callable by anyone externally.
        @dev Non-view function - it stores the last good price seen by eBTC.
        @dev Uses a main oracle (Chainlink) and a fallback oracle in case Chainlink fails. If both fail, it uses the last good price seen by eBTC.
        @dev The fallback oracle address can be swapped by the Authority. The fallback oracle must conform to the IFallbackCaller interface.
        @return The latest price fetched from the Oracle
    **/
    function fetchPrice() external override returns (uint) {
        // Get current and previous price data from Chainlink, and current price data from Fallback
        ChainlinkResponse memory chainlinkResponse = _getCurrentChainlinkResponse();
        ChainlinkResponse memory prevChainlinkResponse = _getPrevChainlinkResponse(
            chainlinkResponse.roundEthBtcId,
            chainlinkResponse.roundStEthEthId
        );
        FallbackResponse memory fallbackResponse = _getCurrentFallbackResponse();

        // --- CASE 1: System fetched last price from Chainlink  ---
        if (status == Status.chainlinkWorking) {
            // If Chainlink is broken, try Fallback
            if (_chainlinkIsBroken(chainlinkResponse, prevChainlinkResponse)) {
                // If Fallback is broken then both oracles are untrusted, so return the last good price
                if (_fallbackIsBroken(fallbackResponse)) {
                    _changeStatus(Status.bothOraclesUntrusted);
                    return lastGoodPrice;
                }
                /*
                 * If Fallback is only frozen but otherwise returning valid data, return the last good price.
                 * Fallback may need to be tipped to return current data.
                 */
                if (_fallbackIsFrozen(fallbackResponse)) {
                    _changeStatus(Status.usingFallbackChainlinkUntrusted);
                    return lastGoodPrice;
                }

                // If Chainlink is broken and Fallback is working, switch to Fallback and return current Fallback price
                _changeStatus(Status.usingFallbackChainlinkUntrusted);
                return _storeFallbackPrice(fallbackResponse);
            }

            // If Chainlink is frozen, try Fallback
            if (_chainlinkIsFrozen(chainlinkResponse.timestamp)) {
                // If Fallback is broken too, remember Fallback broke, and return last good price
                if (_fallbackIsBroken(fallbackResponse)) {
                    _changeStatus(Status.usingChainlinkFallbackUntrusted);
                    return lastGoodPrice;
                }

                // If Fallback is frozen or working, remember Chainlink froze, and switch to Fallback
                _changeStatus(Status.usingFallbackChainlinkFrozen);

                if (_fallbackIsFrozen(fallbackResponse)) {
                    return lastGoodPrice;
                }

                // If Fallback is working, use it
                return _storeFallbackPrice(fallbackResponse);
            }

            // If Chainlink price has changed by > 50% between two consecutive rounds, compare it to Fallback's price
            if (_chainlinkPriceChangeAboveMax(chainlinkResponse, prevChainlinkResponse)) {
                // If Fallback is broken, both oracles are untrusted, and return last good price
                if (_fallbackIsBroken(fallbackResponse)) {
                    _changeStatus(Status.bothOraclesUntrusted);
                    return lastGoodPrice;
                }

                // If Fallback is frozen, switch to Fallback and return last good price
                if (_fallbackIsFrozen(fallbackResponse)) {
                    _changeStatus(Status.usingFallbackChainlinkUntrusted);
                    return lastGoodPrice;
                }

                /*
                 * If Fallback is live and both oracles have a similar price, conclude that Chainlink's large price deviation between
                 * two consecutive rounds was likely a legitmate market price movement, and so continue using Chainlink
                 */
                if (_bothOraclesSimilarPrice(chainlinkResponse, fallbackResponse)) {
                    return _storeChainlinkPrice(chainlinkResponse.answer);
                }

                // If Fallback is live but the oracles differ too much in price, conclude that Chainlink's initial price deviation was
                // an oracle failure. Switch to Fallback, and use Fallback price
                _changeStatus(Status.usingFallbackChainlinkUntrusted);
                return _storeFallbackPrice(fallbackResponse);
            }

            // If Chainlink is working and Fallback is broken, remember Fallback is broken
            if (_fallbackIsBroken(fallbackResponse)) {
                _changeStatus(Status.usingChainlinkFallbackUntrusted);
            }

            // If Chainlink is working, return Chainlink current price (no status change)
            return _storeChainlinkPrice(chainlinkResponse.answer);
        }

        // --- CASE 2: The system fetched last price from Fallback ---
        if (status == Status.usingFallbackChainlinkUntrusted) {
            // If both Fallback and Chainlink are live, unbroken, and reporting similar prices, switch back to Chainlink
            if (
                _bothOraclesLiveAndUnbrokenAndSimilarPrice(
                    chainlinkResponse,
                    prevChainlinkResponse,
                    fallbackResponse
                )
            ) {
                _changeStatus(Status.chainlinkWorking);
                return _storeChainlinkPrice(chainlinkResponse.answer);
            }

            if (_fallbackIsBroken(fallbackResponse)) {
                _changeStatus(Status.bothOraclesUntrusted);
                return lastGoodPrice;
            }

            /*
             * If Fallback is only frozen but otherwise returning valid data, just return the last good price.
             * Fallback may need to be tipped to return current data.
             */
            if (_fallbackIsFrozen(fallbackResponse)) {
                return lastGoodPrice;
            }

            // Otherwise, use Fallback price
            return _storeFallbackPrice(fallbackResponse);
        }

        // --- CASE 3: Both oracles were untrusted at the last price fetch ---
        if (status == Status.bothOraclesUntrusted) {
            /*
             * If both oracles are now live, unbroken and similar price, we assume that they are reporting
             * accurately, and so we switch back to Chainlink.
             */
            if (
                _bothOraclesLiveAndUnbrokenAndSimilarPrice(
                    chainlinkResponse,
                    prevChainlinkResponse,
                    fallbackResponse
                )
            ) {
                _changeStatus(Status.chainlinkWorking);
                return _storeChainlinkPrice(chainlinkResponse.answer);
            }

            // Otherwise, return the last good price - both oracles are still untrusted (no status change)
            return lastGoodPrice;
        }

        // --- CASE 4: Using Fallback, and Chainlink is frozen ---
        if (status == Status.usingFallbackChainlinkFrozen) {
            if (_chainlinkIsBroken(chainlinkResponse, prevChainlinkResponse)) {
                // If both Oracles are broken, return last good price
                if (_fallbackIsBroken(fallbackResponse)) {
                    _changeStatus(Status.bothOraclesUntrusted);
                    return lastGoodPrice;
                }

                // If Chainlink is broken, remember it and switch to using Fallback
                _changeStatus(Status.usingFallbackChainlinkUntrusted);

                if (_fallbackIsFrozen(fallbackResponse)) {
                    return lastGoodPrice;
                }

                // If Fallback is working, return Fallback current price
                return _storeFallbackPrice(fallbackResponse);
            }

            if (_chainlinkIsFrozen(chainlinkResponse.timestamp)) {
                // if Chainlink is frozen and Fallback is broken, remember Fallback broke, and return last good price
                if (_fallbackIsBroken(fallbackResponse)) {
                    _changeStatus(Status.usingChainlinkFallbackUntrusted);
                    return lastGoodPrice;
                }

                // If both are frozen, just use lastGoodPrice
                if (_fallbackIsFrozen(fallbackResponse)) {
                    return lastGoodPrice;
                }

                // if Chainlink is frozen and Fallback is working, keep using Fallback (no status change)
                return _storeFallbackPrice(fallbackResponse);
            }

            // if Chainlink is live and Fallback is broken, remember Fallback broke, and return Chainlink price
            if (_fallbackIsBroken(fallbackResponse)) {
                _changeStatus(Status.usingChainlinkFallbackUntrusted);
                return _storeChainlinkPrice(chainlinkResponse.answer);
            }

            // If Chainlink is live and Fallback is frozen, just use last good price (no status change) since we have no basis for comparison
            if (_fallbackIsFrozen(fallbackResponse)) {
                return lastGoodPrice;
            }

            // If Chainlink is live and Fallback is working, compare prices. Switch to Chainlink
            // if prices are within 5%, and return Chainlink price.
            if (_bothOraclesSimilarPrice(chainlinkResponse, fallbackResponse)) {
                _changeStatus(Status.chainlinkWorking);
                return _storeChainlinkPrice(chainlinkResponse.answer);
            }

            // Otherwise if Chainlink is live but price not within 5% of Fallback, distrust Chainlink, and return Fallback price
            _changeStatus(Status.usingFallbackChainlinkUntrusted);
            return _storeFallbackPrice(fallbackResponse);
        }

        // --- CASE 5: Using Chainlink, Fallback is untrusted ---
        if (status == Status.usingChainlinkFallbackUntrusted) {
            // If Chainlink breaks, now both oracles are untrusted
            if (_chainlinkIsBroken(chainlinkResponse, prevChainlinkResponse)) {
                _changeStatus(Status.bothOraclesUntrusted);
                return lastGoodPrice;
            }

            // If Chainlink is frozen, return last good price (no status change)
            if (_chainlinkIsFrozen(chainlinkResponse.timestamp)) {
                return lastGoodPrice;
            }

            // If Chainlink and Fallback are both live, unbroken and similar price, switch back to chainlinkWorking and return Chainlink price
            if (
                _bothOraclesLiveAndUnbrokenAndSimilarPrice(
                    chainlinkResponse,
                    prevChainlinkResponse,
                    fallbackResponse
                )
            ) {
                _changeStatus(Status.chainlinkWorking);
                return _storeChainlinkPrice(chainlinkResponse.answer);
            }

            // If Chainlink is live but deviated >50% from it's previous price and Fallback is still untrusted, switch
            // to bothOraclesUntrusted and return last good price
            if (_chainlinkPriceChangeAboveMax(chainlinkResponse, prevChainlinkResponse)) {
                _changeStatus(Status.bothOraclesUntrusted);
                return lastGoodPrice;
            }

            // Otherwise if Chainlink is live and deviated <50% from it's previous price and Fallback is still untrusted,
            // return Chainlink price (no status change)
            return _storeChainlinkPrice(chainlinkResponse.answer);
        }
    }

    // --- Governance Functions ---
    /*
        @notice Sets a new fallback oracle 
        @param _fallbackCaller The new IFallbackCaller-compliant oracle address
    **/
    function setFallbackCaller(address _fallbackCaller) external requiresAuth {
        require(
            isAuthorized(msg.sender, SET_FALLBACK_CALLER_SIG),
            "PriceFeed: sender not authorized for setFallbackCaller(address)"
        );
        fallbackCaller = IFallbackCaller(_fallbackCaller);
        emit FallbackCallerChanged(_fallbackCaller);
    }

    // --- Helper functions ---

    /* Chainlink is considered broken if its current or previous round data is in any way bad. We check the previous round
     * for two reasons:
     *
     * 1) It is necessary data for the price deviation check in case 1,
     * and
     * 2) Chainlink is the PriceFeed's preferred primary oracle - having two consecutive valid round responses adds
     * peace of mind when using or returning to Chainlink.
     */
    function _chainlinkIsBroken(
        ChainlinkResponse memory _currentResponse,
        ChainlinkResponse memory _prevResponse
    ) internal view returns (bool) {
        return _badChainlinkResponse(_currentResponse) || _badChainlinkResponse(_prevResponse);
    }

    function _badChainlinkResponse(ChainlinkResponse memory _response) internal view returns (bool) {
        // Check for response call reverted
        if (!_response.success) {
            return true;
        }

        // Check for an invalid timeStamp that is 0, or in the future
        if (_response.timestamp == 0 || _response.timestamp > block.timestamp) {
            return true;
        }

        return false;
    }

    function _chainlinkIsFrozen(uint256 _updateTime) internal view returns (bool) {
        return block.timestamp - _updateTime > TIMEOUT;
    }

    function _chainlinkPriceChangeAboveMax(
        ChainlinkResponse memory _currentResponse,
        ChainlinkResponse memory _prevResponse
    ) internal pure returns (bool) {
        uint minPrice = LiquityMath._min(_currentResponse.answer, _prevResponse.answer);
        uint maxPrice = LiquityMath._max(_currentResponse.answer, _prevResponse.answer);

        /*
         * Use the larger price as the denominator:
         * - If price decreased, the percentage deviation is in relation to the the previous price.
         * - If price increased, the percentage deviation is in relation to the current price.
         */
        uint percentDeviation = ((maxPrice - minPrice) * LiquityMath.DECIMAL_PRECISION) / maxPrice;

        // Return true if price has more than doubled, or more than halved.
        return percentDeviation > MAX_PRICE_DEVIATION_FROM_PREVIOUS_ROUND;
    }

    function _fallbackIsBroken(FallbackResponse memory _response) internal view returns (bool) {
        // Check for response call reverted
        if (!_response.success) {
            return true;
        }
        // Check for an invalid timeStamp that is 0, or in the future
        if (_response.timestamp == 0 || _response.timestamp > block.timestamp) {
            return true;
        }
        // Check for zero price (FallbackCaller must ensure that the price is not negative and return 0 if it is)
        if (_response.answer == 0) {
            return true;
        }

        return false;
    }

    function _fallbackIsFrozen(
        FallbackResponse memory _fallbackResponse
    ) internal view returns (bool) {
        return block.timestamp - _fallbackResponse.timestamp > TIMEOUT;
    }

    function _bothOraclesLiveAndUnbrokenAndSimilarPrice(
        ChainlinkResponse memory _chainlinkResponse,
        ChainlinkResponse memory _prevChainlinkResponse,
        FallbackResponse memory _fallbackResponse
    ) internal view returns (bool) {
        // Return false if either oracle is broken or frozen
        if (
            _fallbackIsBroken(_fallbackResponse) ||
            _fallbackIsBroken(_fallbackResponse) ||
            _chainlinkIsBroken(_chainlinkResponse, _prevChainlinkResponse) ||
            _chainlinkIsFrozen(_chainlinkResponse.timestamp)
        ) {
            return false;
        }

        return _bothOraclesSimilarPrice(_chainlinkResponse, _fallbackResponse);
    }

    function _bothOraclesSimilarPrice(
        ChainlinkResponse memory _chainlinkResponse,
        FallbackResponse memory _fallbackResponse
    ) internal pure returns (bool) {
        // Get the relative price difference between the oracles. Use the lower price as the denominator, i.e. the reference for the calculation.
        uint minPrice = LiquityMath._min(_fallbackResponse.answer, _chainlinkResponse.answer);
        uint maxPrice = LiquityMath._max(_fallbackResponse.answer, _chainlinkResponse.answer);
        uint percentPriceDifference = ((maxPrice - minPrice) * LiquityMath.DECIMAL_PRECISION) /
            minPrice;

        /*
         * Return true if the relative price difference is <= 3%: if so, we assume both oracles are probably reporting
         * the honest market price, as it is unlikely that both have been broken/hacked and are still in-sync.
         */
        return percentPriceDifference <= MAX_PRICE_DIFFERENCE_BETWEEN_ORACLES;
    }

    function _changeStatus(Status _status) internal {
        status = _status;
        emit PriceFeedStatusChanged(_status);
    }

    function _storePrice(uint _currentPrice) internal {
        lastGoodPrice = _currentPrice;
        emit LastGoodPriceUpdated(_currentPrice);
    }

    function _storeFallbackPrice(FallbackResponse memory _fallbackResponse) internal returns (uint) {
        _storePrice(_fallbackResponse.answer);
        return _fallbackResponse.answer;
    }

    function _storeChainlinkPrice(uint256 _answer) internal returns (uint) {
        _storePrice(_answer);

        return _answer;
    }

    // --- Oracle response wrapper functions ---
    /*
     * "_getCurrentFallbackResponse" fetches stETH/BTC price from Fallback, and returns them as a
     * FallbackResponse struct. If the Fallback is set to the ADDRESS_ZERO, return failing struct.
     */
    function _getCurrentFallbackResponse()
        internal
        view
        returns (FallbackResponse memory fallbackResponse)
    {
        if (address(fallbackCaller) != address(0)) {
            try fallbackCaller.getFallbackResponse() returns (
                uint256 answer,
                uint256 timestampRetrieved,
                bool success
            ) {
                fallbackResponse.answer = answer;
                fallbackResponse.timestamp = timestampRetrieved;
                fallbackResponse.success = success;
                return (fallbackResponse);
            } catch {
                // If call to Fallback reverts, return a zero response with success = false
                return (fallbackResponse);
            }
        } else {
            return fallbackResponse;
        }
    }

    function _getCurrentChainlinkResponse()
        public
        view
        returns (ChainlinkResponse memory chainlinkResponse)
    {
        // Try to get latest prices data:
        (uint80 roundEthBtcId, int256 ethBtcAnswer, , uint256 ethBtcTimestamp, ) = ETH_BTC_CL_FEED
            .latestRoundData();
        if (ethBtcAnswer < 0) return chainlinkResponse;
        if (_chainlinkIsFrozen(ethBtcTimestamp)) return chainlinkResponse;
        if (roundEthBtcId == 0) return chainlinkResponse;

        (
            uint80 roundstEthEthId,
            int256 stEthEthAnswer,
            ,
            uint256 stEthEtTimestamp,

        ) = STETH_ETH_CL_FEED.latestRoundData();
        if (stEthEthAnswer < 0) return chainlinkResponse;
        if (_chainlinkIsFrozen(stEthEtTimestamp)) return chainlinkResponse;
        if (roundstEthEthId == 0) return chainlinkResponse;

        // NOTE: after initial checks then we write into memory
        chainlinkResponse.roundEthBtcId = roundEthBtcId;
        chainlinkResponse.roundStEthEthId = roundstEthEthId;

        // If call to Chainlink succeeds, return the response and success = true
        chainlinkResponse.answer = _formatClAggregateAnswer(ethBtcAnswer, stEthEthAnswer);
        // NOTE: stick with the `Min` for `TIMEOUT` check-ups
        chainlinkResponse.timestamp = LiquityMath._min(ethBtcTimestamp, stEthEtTimestamp);
        chainlinkResponse.success = true;

        return chainlinkResponse;
    }

    function _getPrevChainlinkResponse(
        uint80 _currentRoundEthBtcId,
        uint80 _currentRoundStEthEthId
    ) internal view returns (ChainlinkResponse memory prevChainlinkResponse) {
        // If first round, early return
        // Handles revert from underflow in _currentRoundEthBtcId - 1
        // and _currentRoundStEthEthId - 1
        // Behavior should be indentical to following block if this revert was caught
        if (_currentRoundEthBtcId == 0 || _currentRoundStEthEthId == 0) {
            return prevChainlinkResponse;
        }

        // Try to get latest prices data from prev round:
        (uint80 roundEthBtcId, int256 ethBtcAnswer, , uint256 ethBtcTimestamp, ) = ETH_BTC_CL_FEED
            .getRoundData(_currentRoundEthBtcId - 1);
        if (ethBtcAnswer < 0) return prevChainlinkResponse;
        if (_chainlinkIsFrozen(ethBtcTimestamp)) return prevChainlinkResponse;
        if (roundEthBtcId == 0) return prevChainlinkResponse;

        (
            uint80 roundstEthEthId,
            int256 stEthEthAnswer,
            ,
            uint256 stEthEtTimestamp,

        ) = STETH_ETH_CL_FEED.getRoundData(_currentRoundStEthEthId - 1);
        if (stEthEthAnswer < 0) return prevChainlinkResponse;
        if (_chainlinkIsFrozen(stEthEtTimestamp)) return prevChainlinkResponse;
        if (roundstEthEthId == 0) return prevChainlinkResponse;

        // NOTE: after initial checks then we write into memory
        prevChainlinkResponse.roundEthBtcId = roundEthBtcId;
        prevChainlinkResponse.roundStEthEthId = roundstEthEthId;

        // If call to Chainlink succeeds, return the response and success = true
        prevChainlinkResponse.answer = _formatClAggregateAnswer(ethBtcAnswer, stEthEthAnswer);
        // NOTE: stick with the `Min` for `TIMEOUT` check-ups
        prevChainlinkResponse.timestamp = LiquityMath._min(ethBtcTimestamp, stEthEtTimestamp);
        prevChainlinkResponse.success = true;
    }

    // @notice Returns the price of stETH:BTC in 18 decimals denomination
    // @param _ethBtcAnswer CL price retrieve from ETH:BTC feed
    // @param _stEthEthAnswer CL price retrieve from stETH:BTC feed
    // @return The aggregated calculated price for stETH:BTC
    function _formatClAggregateAnswer(
        int256 _ethBtcAnswer,
        int256 _stEthEthAnswer
    ) internal view returns (uint256) {
        return
            ((uint256(_ethBtcAnswer) * LiquityMath.DECIMAL_PRECISION) / uint256(_stEthEthAnswer)) *
            (10 ** (STETH_ETH_CL_FEED_DECIMAL - ETH_BTC_CL_FEED_DECIMAL));
    }
}
