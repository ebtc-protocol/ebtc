// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./Interfaces/IPriceFeed.sol";
import "./Interfaces/IFallbackCaller.sol";
import "./Dependencies/AggregatorV3Interface.sol";
import "./Dependencies/BaseMath.sol";
import "./Dependencies/EbtcMath.sol";
import "./Dependencies/AuthNoOwner.sol";
import "./FixedAdapter.sol";

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

    // Chainlink oracles in mainnet
    AggregatorV3Interface public immutable ETH_BTC_CL_FEED;
    AggregatorV3Interface public immutable STETH_ETH_CL_FEED;
    // STETH_ETH_FIXED_FEED must have the same decimals as STETH_ETH_CL_FEED
    AggregatorV3Interface public immutable STETH_ETH_FIXED_FEED;

    uint256 public immutable DENOMINATOR;
    uint256 public immutable SCALED_DECIMAL;

    // Fallback feed
    IFallbackCaller public fallbackCaller; // Wrapper contract that calls the fallback system

    // Maximum time period allowed since Chainlink's latest round data timestamp, beyond which Chainlink is considered frozen.
    uint256 public constant TIMEOUT_ETH_BTC_FEED = 4800; // 1 hours & 20min: 60 * 80
    uint256 public constant TIMEOUT_STETH_ETH_FEED = 90000; // 25 hours: 60 * 60 * 25
    uint256 constant INVALID_PRICE = 0;

    /**
     * @notice Maximum number of resulting and feed decimals
     */
    uint8 public constant MAX_DECIMALS = 18;

    // Maximum deviation allowed between two consecutive Chainlink oracle prices. 18-digit precision.
    uint256 public constant MAX_PRICE_DEVIATION_FROM_PREVIOUS_ROUND = 5e17; // 50%

    /*
     * The maximum relative price difference between two oracle responses allowed in order for the PriceFeed
     * to return to using the Chainlink oracle. 18-digit precision.
     */
    uint256 public constant MAX_PRICE_DIFFERENCE_BETWEEN_ORACLES = 5e16; // 5%

    // The last good price seen from an oracle by eBTC
    uint256 public lastGoodPrice;

    // The current status of the PriceFeed, which determines the conditions for the next price fetch attempt
    Status public status;

    // Dynamic feed = Chainlink stETH/ETH feed
    // Static feed = 1:1 FixedAdapter
    // defaults to static feed
    bool public useDynamicFeed;

    // --- Dependency setters ---

    /// @notice Sets the addresses of the contracts and initializes the system
    /// @param _fallbackCallerAddress The address of the Fallback oracle contract
    /// @param _authorityAddress The address of the Authority contract
    /// @param _collEthCLFeed The address of the collateral-ETH ChainLink feed
    /// @param _ethBtcCLFeed The address of the ETH-BTC ChainLink feed
    constructor(
        address _fallbackCallerAddress,
        address _authorityAddress,
        address _collEthCLFeed,
        address _ethBtcCLFeed,
        bool _useDynamicFeed
    ) {
        fallbackCaller = IFallbackCaller(_fallbackCallerAddress);

        _initializeAuthority(_authorityAddress);

        emit FallbackCallerChanged(address(0), _fallbackCallerAddress);

        ETH_BTC_CL_FEED = AggregatorV3Interface(_ethBtcCLFeed);
        STETH_ETH_CL_FEED = AggregatorV3Interface(_collEthCLFeed);
        STETH_ETH_FIXED_FEED = new FixedAdapter();

        uint8 ethBtcDecimals = ETH_BTC_CL_FEED.decimals();
        require(ethBtcDecimals <= MAX_DECIMALS);
        uint8 stEthEthDecimals = STETH_ETH_CL_FEED.decimals();
        require(stEthEthDecimals <= MAX_DECIMALS);
        require(stEthEthDecimals == STETH_ETH_FIXED_FEED.decimals());

        DENOMINATOR =
            10 ** ((stEthEthDecimals > ethBtcDecimals ? stEthEthDecimals : ethBtcDecimals) * 2);
        SCALED_DECIMAL = stEthEthDecimals > ethBtcDecimals
            ? 10 ** (stEthEthDecimals - ethBtcDecimals)
            : 10 ** (ethBtcDecimals - stEthEthDecimals);

        useDynamicFeed = _useDynamicFeed;

        // Get an initial price from Chainlink to serve as first reference for lastGoodPrice
        ChainlinkResponse memory chainlinkResponse = _getCurrentChainlinkResponse();
        ChainlinkResponse memory prevChainlinkResponse = _getPrevChainlinkResponse(
            chainlinkResponse.roundEthBtcId,
            chainlinkResponse.roundStEthEthId
        );

        require(
            !_chainlinkIsBroken(chainlinkResponse, prevChainlinkResponse) &&
                !_chainlinkIsFrozen(chainlinkResponse),
            "PriceFeed: Chainlink must be working and current"
        );

        _storeChainlinkPrice(chainlinkResponse.answer);

        // Explicitly set initial system status after `require` checks
        status = Status.chainlinkWorking;

        // emit STETH_ETH_FIXED_FEED address
        emit CollateralFeedSourceUpdated(address(_collateralFeed()));
    }

    // --- Functions ---

    function setCollateralFeedSource(bool _useDynamicFeed) external requiresAuth {
        useDynamicFeed = _useDynamicFeed;
        emit CollateralFeedSourceUpdated(address(_collateralFeed()));
    }

    /// @notice Returns the latest price obtained from the Oracle
    /// @dev Called by eBTC functions that require a current price. Also callable permissionlessly.
    /// @dev Non-view function - it updates and stores the last good price seen by eBTC.
    /// @dev Uses a main oracle (Chainlink) and a fallback oracle in case Chainlink fails. If both fail, it uses the last good price seen by eBTC.
    /// @dev The fallback oracle address can be swapped by the Authority. The fallback oracle must conform to the IFallbackCaller interface.
    /// @return The latest price fetched from the Oracle
    function fetchPrice() external override returns (uint256) {
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
                    return INVALID_PRICE;
                }
                /*
                 * If Fallback is only frozen but otherwise returning valid data, return the last good price.
                 * Fallback may need to be tipped to return current data.
                 */
                if (_fallbackIsFrozen(fallbackResponse)) {
                    _changeStatus(Status.usingFallbackChainlinkUntrusted);
                    return INVALID_PRICE;
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
                    return INVALID_PRICE;
                }

                // If Fallback is frozen or working, remember Chainlink froze, and switch to Fallback
                _changeStatus(Status.usingFallbackChainlinkFrozen);

                if (_fallbackIsFrozen(fallbackResponse)) {
                    return INVALID_PRICE;
                }

                // If Fallback is working, use it
                return _storeFallbackPrice(fallbackResponse);
            }

            // If Chainlink price has changed by > 50% between two consecutive rounds, compare it to Fallback's price
            if (_chainlinkPriceChangeAboveMax(chainlinkResponse, prevChainlinkResponse)) {
                // If Fallback is broken, both oracles are untrusted, and return last good price
                // We don't trust CL for now given this large price differential
                if (_fallbackIsBroken(fallbackResponse)) {
                    _changeStatus(Status.bothOraclesUntrusted);
                    return INVALID_PRICE;
                }

                // If Fallback is frozen, switch to Fallback and return last good price
                // We don't trust CL for now given this large price differential
                if (_fallbackIsFrozen(fallbackResponse)) {
                    _changeStatus(Status.usingFallbackChainlinkUntrusted);
                    return INVALID_PRICE;
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
            if (_fallbackIsBroken(fallbackResponse)) {
                _changeStatus(Status.bothOraclesUntrusted);
                return INVALID_PRICE;
            }

            /*
             * If Fallback is only frozen but otherwise returning valid data, just return the last good price.
             * Fallback may need to be tipped to return current data.
             */
            if (_fallbackIsFrozen(fallbackResponse)) {
                return INVALID_PRICE;
            }

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

            // Otherwise, use Fallback price
            return _storeFallbackPrice(fallbackResponse);
        }

        // --- CASE 3: Both oracles were untrusted at the last price fetch ---
        if (status == Status.bothOraclesUntrusted) {
            /*
             * If there's no fallback, only use Chainlink
             */
            if (address(fallbackCaller) == address(0)) {
                // If CL has resumed working
                if (
                    !_chainlinkIsBroken(chainlinkResponse, prevChainlinkResponse) &&
                    !_chainlinkIsFrozen(chainlinkResponse) &&
                    !_chainlinkPriceChangeAboveMax(chainlinkResponse, prevChainlinkResponse)
                ) {
                    _changeStatus(Status.usingChainlinkFallbackUntrusted);
                    return _storeChainlinkPrice(chainlinkResponse.answer);
                } else {
                    return INVALID_PRICE;
                }
            }

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
            return INVALID_PRICE;
        }

        // --- CASE 4: Using Fallback, and Chainlink is frozen ---
        if (status == Status.usingFallbackChainlinkFrozen) {
            if (_chainlinkIsBroken(chainlinkResponse, prevChainlinkResponse)) {
                // If both Oracles are broken, return last good price
                if (_fallbackIsBroken(fallbackResponse)) {
                    _changeStatus(Status.bothOraclesUntrusted);
                    return INVALID_PRICE;
                }

                // If Chainlink is broken, remember it and switch to using Fallback
                _changeStatus(Status.usingFallbackChainlinkUntrusted);

                if (_fallbackIsFrozen(fallbackResponse)) {
                    return INVALID_PRICE;
                }

                // If Fallback is working, return Fallback current price
                return _storeFallbackPrice(fallbackResponse);
            }

            if (_chainlinkIsFrozen(chainlinkResponse)) {
                // if Chainlink is frozen and Fallback is broken, remember Fallback broke, and return last good price
                if (_fallbackIsBroken(fallbackResponse)) {
                    _changeStatus(Status.usingChainlinkFallbackUntrusted);
                    return INVALID_PRICE;
                }

                // If both are frozen, just use lastGoodPrice
                if (_fallbackIsFrozen(fallbackResponse)) {
                    return INVALID_PRICE;
                }

                // if Chainlink is frozen and Fallback is working, keep using Fallback (no status change)
                return _storeFallbackPrice(fallbackResponse);
            }

            if (_chainlinkPriceChangeAboveMax(chainlinkResponse, prevChainlinkResponse)) {
                // if Chainlink price is deviated between rounds and fallback is broken, just use lastGoodPrice
                if (_fallbackIsBroken(fallbackResponse)) {
                    _changeStatus(Status.bothOraclesUntrusted);
                    return INVALID_PRICE;
                }

                // If Chainlink price is deviated between rounds, remember it and keep using fallback
                _changeStatus(Status.usingFallbackChainlinkUntrusted);

                // If fallback is frozen, just use lastGoodPrice
                if (_fallbackIsFrozen(fallbackResponse)) {
                    return INVALID_PRICE;
                }

                // otherwise fallback is working and keep using its latest response
                return _storeFallbackPrice(fallbackResponse);
            }

            // if Chainlink is live and Fallback is broken, remember Fallback broke, and return Chainlink price
            if (_fallbackIsBroken(fallbackResponse)) {
                _changeStatus(Status.usingChainlinkFallbackUntrusted);
                return _storeChainlinkPrice(chainlinkResponse.answer);
            }

            // If Chainlink is live and Fallback is frozen, just use last good price (no status change) since we have no basis for comparison
            if (_fallbackIsFrozen(fallbackResponse)) {
                return INVALID_PRICE;
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
                return INVALID_PRICE;
            }

            // If Chainlink is frozen, return last good price (no status change)
            if (_chainlinkIsFrozen(chainlinkResponse)) {
                return INVALID_PRICE;
            }

            // If Chainlink is live but deviated >50% from it's previous price and Fallback is still untrusted, switch
            // to bothOraclesUntrusted and return last good price
            if (_chainlinkPriceChangeAboveMax(chainlinkResponse, prevChainlinkResponse)) {
                _changeStatus(Status.bothOraclesUntrusted);
                return INVALID_PRICE;
            }

            // If Chainlink and Fallback are both live, unbroken and similar price, switch back to chainlinkWorking and return Chainlink price
            if (
                _bothOraclesLiveAndUnbrokenAndSimilarPrice(
                    chainlinkResponse,
                    prevChainlinkResponse,
                    fallbackResponse
                )
            ) {
                if (address(fallbackCaller) != address(0)) {
                    _changeStatus(Status.chainlinkWorking);
                }
                return _storeChainlinkPrice(chainlinkResponse.answer);
            }

            // Otherwise if Chainlink is live and deviated <50% from it's previous price and Fallback is still untrusted,
            // return Chainlink price (no status change)
            return _storeChainlinkPrice(chainlinkResponse.answer);
        }

        /// @audit This should never be used, but we added it for the Certora Prover
        return INVALID_PRICE;
    }

    // --- Governance Functions ---
    /// @notice Sets a new fallback oracle
    /// @dev Healthy response of new oracle is checked, with extra event emitted on failure
    /// @param _fallbackCaller The address of the new IFallbackCaller compliant oracle\
    function setFallbackCaller(address _fallbackCaller) external requiresAuth {
        // health check-up before officially set it up
        IFallbackCaller newFallbackCaler = IFallbackCaller(_fallbackCaller);
        FallbackResponse memory fallbackResponse;

        if (_fallbackCaller != address(0)) {
            try newFallbackCaler.getFallbackResponse() returns (
                uint256 answer,
                uint256 timestampRetrieved,
                bool success
            ) {
                fallbackResponse.answer = answer;
                fallbackResponse.timestamp = timestampRetrieved;
                fallbackResponse.success = success;
                if (
                    !_fallbackIsBroken(fallbackResponse) &&
                    !_responseTimeout(fallbackResponse.timestamp, newFallbackCaler.fallbackTimeout())
                ) {
                    address oldFallbackCaller = address(fallbackCaller);
                    fallbackCaller = newFallbackCaler;
                    emit FallbackCallerChanged(oldFallbackCaller, _fallbackCaller);
                }
            } catch {
                emit UnhealthyFallbackCaller(_fallbackCaller, block.timestamp);
            }
        } else {
            address oldFallbackCaller = address(fallbackCaller);
            // NOTE: assume intentionally bricking fallback!!!
            fallbackCaller = newFallbackCaler;
            emit FallbackCallerChanged(oldFallbackCaller, _fallbackCaller);
        }
    }

    // --- Helper functions ---

    /// @notice Checks if Chainlink oracle is broken by checking both the current and previous responses
    /// @dev Chainlink is considered broken if its current or previous round data is in any way bad. We check the previous round for two reasons.
    /// @dev 1. It is necessary data for the price deviation check in case 1
    /// @dev 2. Chainlink is the PriceFeed's preferred primary oracle - having two consecutive valid round responses adds peace of mind when using or returning to Chainlink.
    /// @param _currentResponse The latest response from the Chainlink oracle
    /// @param _prevResponse The previous response from the Chainlink oracle
    /// @return A boolean indicating whether the Chainlink oracle is broken
    function _chainlinkIsBroken(
        ChainlinkResponse memory _currentResponse,
        ChainlinkResponse memory _prevResponse
    ) internal view returns (bool) {
        return _badChainlinkResponse(_currentResponse) || _badChainlinkResponse(_prevResponse);
    }

    /// @notice Checks for a bad response from the Chainlink oracle
    /// @dev A response is considered bad if the success value reports failure, or if the timestamp is invalid (0 or in the future)
    /// @param _response The response from the Chainlink oracle to evaluate
    /// @return A boolean indicating whether the Chainlink oracle response is bad

    function _badChainlinkResponse(ChainlinkResponse memory _response) internal view returns (bool) {
        // Check for response call reverted
        if (!_response.success) {
            return true;
        }

        // Check for an invalid timestamp that is 0, or in the future
        if (
            _response.timestampEthBtc == 0 ||
            _response.timestampEthBtc > block.timestamp ||
            _response.timestampStEthEth == 0 ||
            _response.timestampStEthEth > block.timestamp
        ) {
            return true;
        }

        return false;
    }

    /// @notice Checks if the Chainlink oracle is frozen
    /// @dev The oracle is considered frozen if either of the feed timestamps are older than the threshold specified by the static timeout thresholds
    /// @param _response The response from the Chainlink oracle to evaluate
    /// @return A boolean indicating whether the Chainlink oracle is frozen
    function _chainlinkIsFrozen(ChainlinkResponse memory _response) internal view returns (bool) {
        return
            _responseTimeout(_response.timestampEthBtc, TIMEOUT_ETH_BTC_FEED) ||
            _responseTimeout(_response.timestampStEthEth, TIMEOUT_STETH_ETH_FEED);
    }

    /// @notice Checks if the price change between Chainlink oracle rounds is above the maximum threshold allowed
    /// @param _currentResponse The latest response from the Chainlink oracle
    /// @param _prevResponse The previous response from the Chainlink oracle
    /// @return A boolean indicating whether the price change from Chainlink oracle is above the maximum threshold allowed
    function _chainlinkPriceChangeAboveMax(
        ChainlinkResponse memory _currentResponse,
        ChainlinkResponse memory _prevResponse
    ) internal pure returns (bool) {
        uint256 minPrice = EbtcMath._min(_currentResponse.answer, _prevResponse.answer);
        uint256 maxPrice = EbtcMath._max(_currentResponse.answer, _prevResponse.answer);

        /*
         * Use the larger price as the denominator:
         * - If price decreased, the percentage deviation is in relation to the the previous price.
         * - If price increased, the percentage deviation is in relation to the current price.
         */
        uint256 percentDeviation = maxPrice > 0
            ? ((maxPrice - minPrice) * EbtcMath.DECIMAL_PRECISION) / maxPrice
            : 0;

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

    /// @notice Checks if the fallback oracle is frozen by comparing the current timestamp with the timeout value.
    /// @param _fallbackResponse Response from the fallback oracle to check
    /// @return A boolean indicating whether the fallback oracle is frozen.
    function _fallbackIsFrozen(
        FallbackResponse memory _fallbackResponse
    ) internal view returns (bool) {
        return
            _fallbackResponse.timestamp > 0 &&
            _responseTimeout(_fallbackResponse.timestamp, fallbackCaller.fallbackTimeout());
    }

    function _responseTimeout(uint256 _timestamp, uint256 _timeout) internal view returns (bool) {
        return block.timestamp - _timestamp > _timeout;
    }

    /// @notice Checks if both the Chainlink and fallback oracles are live, unbroken, and reporting similar prices.
    /// @param _chainlinkResponse The latest response from the Chainlink oracle.
    /// @param _prevChainlinkResponse The previous response from the Chainlink oracle.
    /// @param _fallbackResponse The latest response from the fallback oracle.
    /// @return A boolean indicating whether both oracles are live, unbroken, and reporting similar prices.

    function _bothOraclesLiveAndUnbrokenAndSimilarPrice(
        ChainlinkResponse memory _chainlinkResponse,
        ChainlinkResponse memory _prevChainlinkResponse,
        FallbackResponse memory _fallbackResponse
    ) internal view returns (bool) {
        // Return false if either oracle is broken or frozen
        if (
            (address(fallbackCaller) != address(0) &&
                (_fallbackIsBroken(_fallbackResponse) || _fallbackIsFrozen(_fallbackResponse))) ||
            _chainlinkIsBroken(_chainlinkResponse, _prevChainlinkResponse) ||
            _chainlinkIsFrozen(_chainlinkResponse)
        ) {
            return false;
        }

        return _bothOraclesSimilarPrice(_chainlinkResponse, _fallbackResponse);
    }

    /// @notice Checks if the prices reported by the Chainlink and fallback oracles are similar, within the maximum deviation specified by MAX_PRICE_DIFFERENCE_BETWEEN_ORACLES.
    /// @param _chainlinkResponse The response from the Chainlink oracle.
    /// @param _fallbackResponse The response from the fallback oracle.
    /// @return A boolean indicating whether the prices reported by both oracles are similar.

    function _bothOraclesSimilarPrice(
        ChainlinkResponse memory _chainlinkResponse,
        FallbackResponse memory _fallbackResponse
    ) internal view returns (bool) {
        if (address(fallbackCaller) == address(0)) {
            return true;
        }
        // Get the relative price difference between the oracles. Use the lower price as the denominator, i.e. the reference for the calculation.
        uint256 minPrice = EbtcMath._min(_fallbackResponse.answer, _chainlinkResponse.answer);
        if (minPrice == 0) return false;
        uint256 maxPrice = EbtcMath._max(_fallbackResponse.answer, _chainlinkResponse.answer);
        uint256 percentPriceDifference = ((maxPrice - minPrice) * EbtcMath.DECIMAL_PRECISION) /
            minPrice;

        /*
         * Return true if the relative price difference is <= MAX_PRICE_DIFFERENCE_BETWEEN_ORACLES: if so, we assume both oracles are probably reporting
         * the honest market price, as it is unlikely that both have been broken/hacked and are still in-sync.
         */
        return percentPriceDifference <= MAX_PRICE_DIFFERENCE_BETWEEN_ORACLES;
    }

    /// @notice Changes the status of the oracle state machine
    /// @param _status The new status of the contract.
    function _changeStatus(Status _status) internal {
        status = _status;
        emit PriceFeedStatusChanged(_status);
    }

    /// @notice Stores the latest valid price.
    /// @param _currentPrice The price to be stored.
    function _storePrice(uint256 _currentPrice) internal {
        emit LastGoodPriceUpdated(_currentPrice);
    }

    /// @notice Stores the price reported by the fallback oracle.
    /// @param _fallbackResponse The latest response from the fallback oracle.
    /// @return The price reported by the fallback oracle.
    function _storeFallbackPrice(
        FallbackResponse memory _fallbackResponse
    ) internal returns (uint256) {
        _storePrice(_fallbackResponse.answer);
        return _fallbackResponse.answer;
    }

    /// @notice Stores the price reported by the Chainlink oracle.
    /// @param _answer The latest price reported by the Chainlink oracle.
    /// @return The price reported by the Chainlink oracle.
    function _storeChainlinkPrice(uint256 _answer) internal returns (uint256) {
        _storePrice(_answer);
        return _answer;
    }

    // --- Oracle response wrapper functions ---

    /// @notice Retrieves the latest response from the fallback oracle. If the fallback oracle address is set to the zero address, it returns a failing struct.
    /// @return fallbackResponse The latest response from the fallback oracle.

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
            } catch {
                // If call to Fallback reverts, return a zero response with success = false
            }
        } // If unset we return a zero response with success = false

        // Return is implicit
    }

    function _collateralFeed() private view returns (AggregatorV3Interface) {
        return useDynamicFeed ? STETH_ETH_CL_FEED : STETH_ETH_FIXED_FEED;
    }

    /// @notice Fetches Chainlink responses for the current round of data for both ETH-BTC and stETH-ETH price feeds.
    /// @return chainlinkResponse A struct containing data retrieved from the price feeds, including the round IDs, timestamps, aggregated price, and a success flag.
    function _getCurrentChainlinkResponse()
        internal
        view
        returns (ChainlinkResponse memory chainlinkResponse)
    {
        // Try to get latest prices data:
        int256 ethBtcAnswer;
        int256 stEthEthAnswer;
        try ETH_BTC_CL_FEED.latestRoundData() returns (
            uint80 roundId,
            int256 answer,
            uint256,
            /* startedAt */
            uint256 timestamp,
            uint80 /* answeredInRound */
        ) {
            ethBtcAnswer = answer;
            chainlinkResponse.roundEthBtcId = roundId;
            chainlinkResponse.timestampEthBtc = timestamp;
        } catch {
            // If call to Chainlink aggregator reverts, return a zero response with success = false
            return chainlinkResponse;
        }

        try _collateralFeed().latestRoundData() returns (
            uint80 roundId,
            int256 answer,
            uint256,
            /* startedAt */
            uint256 timestamp,
            uint80 /* answeredInRound */
        ) {
            stEthEthAnswer = answer;
            chainlinkResponse.roundStEthEthId = roundId;
            chainlinkResponse.timestampStEthEth = timestamp;
        } catch {
            // If call to Chainlink aggregator reverts, return a zero response with success = false
            return chainlinkResponse;
        }

        if (
            _checkHealthyCLResponse(chainlinkResponse.roundEthBtcId, ethBtcAnswer) &&
            _checkHealthyCLResponse(chainlinkResponse.roundStEthEthId, stEthEthAnswer)
        ) {
            chainlinkResponse.answer = _formatClAggregateAnswer(ethBtcAnswer, stEthEthAnswer);
        } else {
            return chainlinkResponse;
        }

        chainlinkResponse.success = true;
    }

    /// @notice Returns if the CL feed is healthy or not, based on: negative value and null round id. For price aggregation
    /// @param _roundId The aggregator round of the target CL feed
    /// @param _answer CL price price reported for target feeds
    /// @return The boolean state indicating CL response health for aggregation
    function _checkHealthyCLResponse(uint80 _roundId, int256 _answer) internal view returns (bool) {
        if (_answer <= 0) return false;
        if (_roundId == 0) return false;

        return true;
    }

    /// @notice Fetches Chainlink responses for the previous round of data for both ETH-BTC and stETH-ETH price feeds.
    /// @param _currentRoundEthBtcId The current round ID for the ETH-BTC price feed.
    /// @param _currentRoundStEthEthId The current round ID for the stETH-ETH price feed.
    /// @return prevChainlinkResponse A struct containing data retrieved from the price feeds, including the round IDs, timestamps, aggregated price, and a success flag.
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
        int256 ethBtcAnswer;
        int256 stEthEthAnswer;
        try ETH_BTC_CL_FEED.getRoundData(_currentRoundEthBtcId - 1) returns (
            uint80 roundId,
            int256 answer,
            uint256,
            /* startedAt */
            uint256 timestamp,
            uint80 /* answeredInRound */
        ) {
            ethBtcAnswer = answer;
            prevChainlinkResponse.roundEthBtcId = roundId;
            prevChainlinkResponse.timestampEthBtc = timestamp;
        } catch {
            // If call to Chainlink aggregator reverts, return a zero response with success = false
            return prevChainlinkResponse;
        }

        try _collateralFeed().getRoundData(_currentRoundStEthEthId - 1) returns (
            uint80 roundId,
            int256 answer,
            uint256,
            /* startedAt */
            uint256 timestamp,
            uint80 /* answeredInRound */
        ) {
            stEthEthAnswer = answer;
            prevChainlinkResponse.roundStEthEthId = roundId;
            prevChainlinkResponse.timestampStEthEth = timestamp;
        } catch {
            // If call to Chainlink aggregator reverts, return a zero response with success = false
            return prevChainlinkResponse;
        }

        if (
            _checkHealthyCLResponse(prevChainlinkResponse.roundEthBtcId, ethBtcAnswer) &&
            _checkHealthyCLResponse(prevChainlinkResponse.roundStEthEthId, stEthEthAnswer)
        ) {
            prevChainlinkResponse.answer = _formatClAggregateAnswer(ethBtcAnswer, stEthEthAnswer);
        } else {
            return prevChainlinkResponse;
        }

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
            (SCALED_DECIMAL *
                uint256(_ethBtcAnswer) *
                uint256(_stEthEthAnswer) *
                EbtcMath.DECIMAL_PRECISION) / DENOMINATOR;
    }
}
