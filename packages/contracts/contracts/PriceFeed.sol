// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./Interfaces/IPriceFeed.sol";
import "./Interfaces/IFallbackCaller.sol";
import "./Dependencies/AggregatorV3Interface.sol";
import "./Dependencies/SafeMath.sol";
import "./Dependencies/BaseMath.sol";
import "./Dependencies/LiquityMath.sol";
import "./Dependencies/AuthNoOwner.sol";

/*
 * PriceFeed for mainnet deployment, to be connected to Chainlink's live stETH:BTC aggregator reference
 * contracts (ETH/BTC + stETH/ETH), and allows for the connection to a fallback Oracle source.
 *
 * The PriceFeed uses Chainlink as primary oracle, and Tellor as the current fallback. It contains logic for
 * switching oracles based on oracle failures, timeouts, and conditions for returning to the primary
 * Chainlink oracle. The fallback Oracle can be switched or removed by the Authority.
 */
contract PriceFeed is BaseMath, IPriceFeed, AuthNoOwner {
    using SafeMath for uint256;

    string public constant NAME = "PriceFeed";

    // TODO: Make priceAggregator immutable when we move to 0.8
    AggregatorV3Interface public priceAggregator; // Mainnet Chainlink aggregator
    IFallbackCaller public fallbackCaller; // Wrapper contract that calls the fallback system

    // Use to convert a price answer to an 18-digit precision uint
    uint public constant TARGET_DIGITS = 18;

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

    // The current status of the PricFeed, which determines the conditions for the next price fetch attempt
    Status public status;

    // --- Dependency setters ---

    /*
        @notice Sets the addresses of the contracts and initializes the system
        @param _priceAggregatorAddress The address of the Chainlink oracle contract
        @param _fallbackCallerAddress The address of the Fallback oracle contract
        @param _authorityAddress The address of the Authority contract
        @dev One time initiailziation function. The caller must be the PriceFeed contract's owner (i.e. eBTC Deployer contract) for security. Ownership is renounced after initialization. 
    **/
    constructor(
        address _priceAggregatorAddress,
        address _fallbackCallerAddress,
        address _authorityAddress
    ) {
        priceAggregator = AggregatorV3Interface(_priceAggregatorAddress);
        fallbackCaller = IFallbackCaller(_fallbackCallerAddress);

        _initializeAuthority(_authorityAddress);

        emit FallbackCallerChanged(_fallbackCallerAddress);

        // Explicitly set initial system status
        status = Status.chainlinkWorking;

        // Get an initial price from Chainlink to serve as first reference for lastGoodPrice
        ChainlinkResponse memory chainlinkResponse = _getCurrentChainlinkResponse();
        ChainlinkResponse memory prevChainlinkResponse = _getPrevChainlinkResponse(
            chainlinkResponse.roundId,
            chainlinkResponse.decimals
        );

        require(
            !_chainlinkIsBroken(chainlinkResponse, prevChainlinkResponse) &&
                !_chainlinkIsFrozen(chainlinkResponse),
            "PriceFeed: Chainlink must be working and current"
        );

        _storeChainlinkPrice(chainlinkResponse);
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
            chainlinkResponse.roundId,
            chainlinkResponse.decimals
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
                 * If Fallback is Tellor, it may need to be tipped to return current data.
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
            if (_chainlinkIsFrozen(chainlinkResponse)) {
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
                    return _storeChainlinkPrice(chainlinkResponse);
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
            return _storeChainlinkPrice(chainlinkResponse);
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
                return _storeChainlinkPrice(chainlinkResponse);
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
                return _storeChainlinkPrice(chainlinkResponse);
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

            if (_chainlinkIsFrozen(chainlinkResponse)) {
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
                return _storeChainlinkPrice(chainlinkResponse);
            }

            // If Chainlink is live and Fallback is frozen, just use last good price (no status change) since we have no basis for comparison
            if (_fallbackIsFrozen(fallbackResponse)) {
                return lastGoodPrice;
            }

            // If Chainlink is live and Fallback is working, compare prices. Switch to Chainlink
            // if prices are within 5%, and return Chainlink price.
            if (_bothOraclesSimilarPrice(chainlinkResponse, fallbackResponse)) {
                _changeStatus(Status.chainlinkWorking);
                return _storeChainlinkPrice(chainlinkResponse);
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
            if (_chainlinkIsFrozen(chainlinkResponse)) {
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
                return _storeChainlinkPrice(chainlinkResponse);
            }

            // If Chainlink is live but deviated >50% from it's previous price and Fallback is still untrusted, switch
            // to bothOraclesUntrusted and return last good price
            if (_chainlinkPriceChangeAboveMax(chainlinkResponse, prevChainlinkResponse)) {
                _changeStatus(Status.bothOraclesUntrusted);
                return lastGoodPrice;
            }

            // Otherwise if Chainlink is live and deviated <50% from it's previous price and Fallback is still untrusted,
            // return Chainlink price (no status change)
            return _storeChainlinkPrice(chainlinkResponse);
        }
    }

    // --- Governance Functions ---
    /*
        @notice Sets a new fallback oracle 
        @param _fallbackCaller The new IFallbackCaller-compliant oracle address
    **/
    function setFallbackCaller(address _fallbackCaller) external {
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
        // Check for an invalid roundId that is 0
        if (_response.roundId == 0) {
            return true;
        }
        // Check for an invalid timeStamp that is 0, or in the future
        if (_response.timestamp == 0 || _response.timestamp > block.timestamp) {
            return true;
        }
        // Check for non-positive price
        if (_response.answer <= 0) {
            return true;
        }

        return false;
    }

    function _chainlinkIsFrozen(ChainlinkResponse memory _response) internal view returns (bool) {
        return block.timestamp.sub(_response.timestamp) > TIMEOUT;
    }

    function _chainlinkPriceChangeAboveMax(
        ChainlinkResponse memory _currentResponse,
        ChainlinkResponse memory _prevResponse
    ) internal pure returns (bool) {
        uint currentScaledPrice = _scaleChainlinkPriceByDigits(
            uint256(_currentResponse.answer),
            _currentResponse.decimals
        );
        uint prevScaledPrice = _scaleChainlinkPriceByDigits(
            uint256(_prevResponse.answer),
            _prevResponse.decimals
        );

        uint minPrice = LiquityMath._min(currentScaledPrice, prevScaledPrice);
        uint maxPrice = LiquityMath._max(currentScaledPrice, prevScaledPrice);

        /*
         * Use the larger price as the denominator:
         * - If price decreased, the percentage deviation is in relation to the the previous price.
         * - If price increased, the percentage deviation is in relation to the current price.
         */
        uint percentDeviation = maxPrice.sub(minPrice).mul(DECIMAL_PRECISION).div(maxPrice);

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
        return block.timestamp.sub(_fallbackResponse.timestamp) > TIMEOUT;
    }

    function _bothOraclesLiveAndUnbrokenAndSimilarPrice(
        ChainlinkResponse memory _chainlinkResponse,
        ChainlinkResponse memory _prevChainlinkResponse,
        FallbackResponse memory _fallbackResponse
    ) internal view returns (bool) {
        // Return false if either oracle is broken or frozen
        if (
            _fallbackIsBroken(_fallbackResponse) ||
            _fallbackIsFrozen(_fallbackResponse) ||
            _chainlinkIsBroken(_chainlinkResponse, _prevChainlinkResponse) ||
            _chainlinkIsFrozen(_chainlinkResponse)
        ) {
            return false;
        }

        return _bothOraclesSimilarPrice(_chainlinkResponse, _fallbackResponse);
    }

    function _bothOraclesSimilarPrice(
        ChainlinkResponse memory _chainlinkResponse,
        FallbackResponse memory _fallbackResponse
    ) internal pure returns (bool) {
        uint scaledChainlinkPrice = _scaleChainlinkPriceByDigits(
            uint256(_chainlinkResponse.answer),
            _chainlinkResponse.decimals
        );

        // Get the relative price difference between the oracles. Use the lower price as the denominator, i.e. the reference for the calculation.
        uint minPrice = LiquityMath._min(_fallbackResponse.answer, scaledChainlinkPrice);
        uint maxPrice = LiquityMath._max(_fallbackResponse.answer, scaledChainlinkPrice);
        uint percentPriceDifference = maxPrice.sub(minPrice).mul(DECIMAL_PRECISION).div(minPrice);

        /*
         * Return true if the relative price difference is <= 3%: if so, we assume both oracles are probably reporting
         * the honest market price, as it is unlikely that both have been broken/hacked and are still in-sync.
         */
        return percentPriceDifference <= MAX_PRICE_DIFFERENCE_BETWEEN_ORACLES;
    }

    function _scaleChainlinkPriceByDigits(
        uint _price,
        uint _answerDigits
    ) internal pure returns (uint) {
        /*
         * Convert the price returned by the Chainlink oracle to an 18-digit decimal for use by Liquity.
         * At date of Liquity launch, Chainlink uses an 8-digit price, but we also handle the possibility of
         * future changes.
         *
         */
        uint price;
        if (_answerDigits >= TARGET_DIGITS) {
            // Scale the returned price value down to Liquity's target precision
            price = _price.div(10 ** (_answerDigits - TARGET_DIGITS));
        } else if (_answerDigits < TARGET_DIGITS) {
            // Scale the returned price value up to Liquity's target precision
            price = _price.mul(10 ** (TARGET_DIGITS - _answerDigits));
        }
        return price;
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

    function _storeChainlinkPrice(
        ChainlinkResponse memory _chainlinkResponse
    ) internal returns (uint) {
        uint scaledChainlinkPrice = _scaleChainlinkPriceByDigits(
            uint256(_chainlinkResponse.answer),
            _chainlinkResponse.decimals
        );
        _storePrice(scaledChainlinkPrice);

        return scaledChainlinkPrice;
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
        internal
        view
        returns (ChainlinkResponse memory chainlinkResponse)
    {
        // First, try to get current decimal precision:
        try priceAggregator.decimals() returns (uint8 decimals) {
            // If call to Chainlink succeeds, record the current decimal precision
            chainlinkResponse.decimals = decimals;
        } catch {
            // If call to Chainlink aggregator reverts, return a zero response with success = false
            return chainlinkResponse;
        }

        // Secondly, try to get latest price data:
        try priceAggregator.latestRoundData() returns (
            uint80 roundId,
            int256 answer,
            uint256 /* startedAt */,
            uint256 timestamp,
            uint80 /* answeredInRound */
        ) {
            // If call to Chainlink succeeds, return the response and success = true
            chainlinkResponse.roundId = roundId;
            chainlinkResponse.answer = answer;
            chainlinkResponse.timestamp = timestamp;
            chainlinkResponse.success = true;
            return chainlinkResponse;
        } catch {
            // If call to Chainlink aggregator reverts, return a zero response with success = false
            return chainlinkResponse;
        }
    }

    function _getPrevChainlinkResponse(
        uint80 _currentRoundId,
        uint8 _currentDecimals
    ) internal view returns (ChainlinkResponse memory prevChainlinkResponse) {
        /*
         * NOTE: Chainlink only offers a current decimals() value - there is no way to obtain the decimal precision used in a
         * previous round.  We assume the decimals used in the previous round are the same as the current round.
         */

        // If first round, early return
        // Handles revert from underflow in _currentRoundId - 1
        // Behavior should be indentical to following block if this revert was caught
        if (_currentRoundId == 0) {
            return prevChainlinkResponse;
        }

        // Try to get the price data from the previous round:
        try priceAggregator.getRoundData(_currentRoundId - 1) returns (
            uint80 roundId,
            int256 answer,
            uint256 /* startedAt */,
            uint256 timestamp,
            uint80 /* answeredInRound */
        ) {
            // If call to Chainlink succeeds, return the response and success = true
            prevChainlinkResponse.roundId = roundId;
            prevChainlinkResponse.answer = answer;
            prevChainlinkResponse.timestamp = timestamp;
            prevChainlinkResponse.decimals = _currentDecimals;
            prevChainlinkResponse.success = true;
            return prevChainlinkResponse;
        } catch {
            // If call to Chainlink aggregator reverts, return a zero response with success = false
            return prevChainlinkResponse;
        }
    }
}