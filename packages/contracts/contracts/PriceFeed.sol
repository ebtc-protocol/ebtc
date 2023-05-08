// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./Interfaces/IPriceFeed.sol";
import "./Interfaces/ITellorCaller.sol";
import "./Dependencies/AggregatorV3Interface.sol";
import "./Dependencies/BaseMath.sol";
import "./Dependencies/LiquityMath.sol";
import "./Dependencies/AuthNoOwner.sol";

/*
 * PriceFeed for mainnet deployment, its connected to two Chainlink's live aggreators ETH:BTC and
 * stETH:ETH, which are used to aggregate the price feed of stETH:BTC in conjuction.
 * and allows a fallback oracle in case that primary Chainlink's fail.
 *
 * The PriceFeed uses Chainlink as primary oracle, and fallback source. It contains logic for
 * switching oracles based on oracle failures, timeouts, and conditions for returning to the primary
 * Chainlink oracle.
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

    // Tellor feed
    ITellorCaller public tellorCaller; // Wrapper contract that calls the Tellor system

    uint public constant ETHUSD_TELLOR_REQ_ID = 1;
    // TODO: Use new Tellor query ID for stETH/BTC when available
    bytes32 public constant STETH_BTC_TELLOR_QUERY_ID =
        0x4a5d321c06b63cd85798f884f7d5a1d79d27c6c65756feda15e06742bd161e69; // keccak256(abi.encode("SpotPrice", abi.encode("steth", "btc")))
    uint256 public constant TELLOR_QUERY_BUFFER_SECONDS = 901; // default 15 minutes, soft governance might help to change this default configuration if required

    // Use to convert a price answer to an 18-digit precision uint
    uint public constant TARGET_DIGITS = 18;

    // Maximum time period allowed since Chainlink's latest round data timestamp, beyond which Chainlink is considered frozen.
    uint public constant TIMEOUT = 14400; // 4 hours: 60 * 60 * 4

    // -- Permissioned Function Signatures --
    bytes4 private constant SET_TELLOR_CALLER_SIG =
        bytes4(keccak256(bytes("setTellorCaller(address)")));

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
        @param _tellorCallerAddress The address of the Tellor oracle contract
        @param _authorityAddress The address of the Authority contract
        @dev One time initiailziation function. The caller must be the PriceFeed contract's owner (i.e. eBTC Deployer contract) for security. Ownership is renounced after initialization. 
    **/
    constructor(address _tellorCallerAddress, address _authorityAddress) {
        tellorCaller = ITellorCaller(_tellorCallerAddress);

        _initializeAuthority(_authorityAddress);

        emit TellorCallerChanged(_tellorCallerAddress);

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
        @dev Uses a main oracle (Chainlink) and a fallback oracle (Tellor) in case Chainlink fails. If both fail, it uses the last good price seen by eBTC.
        @dev The fallback oracle address can be swapped by the Authority. The fallback oracle must conform to the ITellorCaller interface.
        @return The latest price fetched from the Oracle
    **/
    function fetchPrice() external override returns (uint) {
        // Get current and previous price data from Chainlink, and current price data from Tellor
        ChainlinkResponse memory chainlinkResponse = _getCurrentChainlinkResponse();
        ChainlinkResponse memory prevChainlinkResponse = _getPrevChainlinkResponse(
            chainlinkResponse.roundEthBtcId,
            chainlinkResponse.roundStEthEthId
        );
        TellorResponse memory tellorResponse = _getCurrentTellorResponse();

        // --- CASE 1: System fetched last price from Chainlink  ---
        if (status == Status.chainlinkWorking) {
            // If Chainlink is broken, try Tellor
            if (_chainlinkIsBroken(chainlinkResponse, prevChainlinkResponse)) {
                // If Tellor is broken then both oracles are untrusted, so return the last good price
                if (_tellorIsBroken(tellorResponse)) {
                    _changeStatus(Status.bothOraclesUntrusted);
                    return lastGoodPrice;
                }
                /*
                 * If Tellor is only frozen but otherwise returning valid data, return the last good price.
                 * Tellor may need to be tipped to return current data.
                 */
                if (_tellorIsFrozen(tellorResponse)) {
                    _changeStatus(Status.usingTellorChainlinkUntrusted);
                    return lastGoodPrice;
                }

                // If Chainlink is broken and Tellor is working, switch to Tellor and return current Tellor price
                _changeStatus(Status.usingTellorChainlinkUntrusted);
                return _storeTellorPrice(tellorResponse);
            }

            // If Chainlink is frozen, try Tellor
            if (_chainlinkIsFrozen(chainlinkResponse.timestamp)) {
                // If Tellor is broken too, remember Tellor broke, and return last good price
                if (_tellorIsBroken(tellorResponse)) {
                    _changeStatus(Status.usingChainlinkTellorUntrusted);
                    return lastGoodPrice;
                }

                // If Tellor is frozen or working, remember Chainlink froze, and switch to Tellor
                _changeStatus(Status.usingTellorChainlinkFrozen);

                if (_tellorIsFrozen(tellorResponse)) {
                    return lastGoodPrice;
                }

                // If Tellor is working, use it
                return _storeTellorPrice(tellorResponse);
            }

            // If Chainlink price has changed by > 50% between two consecutive rounds, compare it to Tellor's price
            if (_chainlinkPriceChangeAboveMax(chainlinkResponse, prevChainlinkResponse)) {
                // If Tellor is broken, both oracles are untrusted, and return last good price
                if (_tellorIsBroken(tellorResponse)) {
                    _changeStatus(Status.bothOraclesUntrusted);
                    return lastGoodPrice;
                }

                // If Tellor is frozen, switch to Tellor and return last good price
                if (_tellorIsFrozen(tellorResponse)) {
                    _changeStatus(Status.usingTellorChainlinkUntrusted);
                    return lastGoodPrice;
                }

                /*
                 * If Tellor is live and both oracles have a similar price, conclude that Chainlink's large price deviation between
                 * two consecutive rounds was likely a legitmate market price movement, and so continue using Chainlink
                 */
                if (_bothOraclesSimilarPrice(chainlinkResponse, tellorResponse)) {
                    return _storeChainlinkPrice(chainlinkResponse.answer);
                }

                // If Tellor is live but the oracles differ too much in price, conclude that Chainlink's initial price deviation was
                // an oracle failure. Switch to Tellor, and use Tellor price
                _changeStatus(Status.usingTellorChainlinkUntrusted);
                return _storeTellorPrice(tellorResponse);
            }

            // If Chainlink is working and Tellor is broken, remember Tellor is broken
            if (_tellorIsBroken(tellorResponse)) {
                _changeStatus(Status.usingChainlinkTellorUntrusted);
            }

            // If Chainlink is working, return Chainlink current price (no status change)
            return _storeChainlinkPrice(chainlinkResponse.answer);
        }

        // --- CASE 2: The system fetched last price from Tellor ---
        if (status == Status.usingTellorChainlinkUntrusted) {
            // If both Tellor and Chainlink are live, unbroken, and reporting similar prices, switch back to Chainlink
            if (
                _bothOraclesLiveAndUnbrokenAndSimilarPrice(
                    chainlinkResponse,
                    prevChainlinkResponse,
                    tellorResponse
                )
            ) {
                _changeStatus(Status.chainlinkWorking);
                return _storeChainlinkPrice(chainlinkResponse.answer);
            }

            if (_tellorIsBroken(tellorResponse)) {
                _changeStatus(Status.bothOraclesUntrusted);
                return lastGoodPrice;
            }

            /*
             * If Tellor is only frozen but otherwise returning valid data, just return the last good price.
             * Tellor may need to be tipped to return current data.
             */
            if (_tellorIsFrozen(tellorResponse)) {
                return lastGoodPrice;
            }

            // Otherwise, use Tellor price
            return _storeTellorPrice(tellorResponse);
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
                    tellorResponse
                )
            ) {
                _changeStatus(Status.chainlinkWorking);
                return _storeChainlinkPrice(chainlinkResponse.answer);
            }

            // Otherwise, return the last good price - both oracles are still untrusted (no status change)
            return lastGoodPrice;
        }

        // --- CASE 4: Using Tellor, and Chainlink is frozen ---
        if (status == Status.usingTellorChainlinkFrozen) {
            if (_chainlinkIsBroken(chainlinkResponse, prevChainlinkResponse)) {
                // If both Oracles are broken, return last good price
                if (_tellorIsBroken(tellorResponse)) {
                    _changeStatus(Status.bothOraclesUntrusted);
                    return lastGoodPrice;
                }

                // If Chainlink is broken, remember it and switch to using Tellor
                _changeStatus(Status.usingTellorChainlinkUntrusted);

                if (_tellorIsFrozen(tellorResponse)) {
                    return lastGoodPrice;
                }

                // If Tellor is working, return Tellor current price
                return _storeTellorPrice(tellorResponse);
            }

            if (_chainlinkIsFrozen(chainlinkResponse.timestamp)) {
                // if Chainlink is frozen and Tellor is broken, remember Tellor broke, and return last good price
                if (_tellorIsBroken(tellorResponse)) {
                    _changeStatus(Status.usingChainlinkTellorUntrusted);
                    return lastGoodPrice;
                }

                // If both are frozen, just use lastGoodPrice
                if (_tellorIsFrozen(tellorResponse)) {
                    return lastGoodPrice;
                }

                // if Chainlink is frozen and Tellor is working, keep using Tellor (no status change)
                return _storeTellorPrice(tellorResponse);
            }

            // if Chainlink is live and Tellor is broken, remember Tellor broke, and return Chainlink price
            if (_tellorIsBroken(tellorResponse)) {
                _changeStatus(Status.usingChainlinkTellorUntrusted);
                return _storeChainlinkPrice(chainlinkResponse.answer);
            }

            // If Chainlink is live and Tellor is frozen, just use last good price (no status change) since we have no basis for comparison
            if (_tellorIsFrozen(tellorResponse)) {
                return lastGoodPrice;
            }

            // If Chainlink is live and Tellor is working, compare prices. Switch to Chainlink
            // if prices are within 5%, and return Chainlink price.
            if (_bothOraclesSimilarPrice(chainlinkResponse, tellorResponse)) {
                _changeStatus(Status.chainlinkWorking);
                return _storeChainlinkPrice(chainlinkResponse.answer);
            }

            // Otherwise if Chainlink is live but price not within 5% of Tellor, distrust Chainlink, and return Tellor price
            _changeStatus(Status.usingTellorChainlinkUntrusted);
            return _storeTellorPrice(tellorResponse);
        }

        // --- CASE 5: Using Chainlink, Tellor is untrusted ---
        if (status == Status.usingChainlinkTellorUntrusted) {
            // If Chainlink breaks, now both oracles are untrusted
            if (_chainlinkIsBroken(chainlinkResponse, prevChainlinkResponse)) {
                _changeStatus(Status.bothOraclesUntrusted);
                return lastGoodPrice;
            }

            // If Chainlink is frozen, return last good price (no status change)
            if (_chainlinkIsFrozen(chainlinkResponse.timestamp)) {
                return lastGoodPrice;
            }

            // If Chainlink and Tellor are both live, unbroken and similar price, switch back to chainlinkWorking and return Chainlink price
            if (
                _bothOraclesLiveAndUnbrokenAndSimilarPrice(
                    chainlinkResponse,
                    prevChainlinkResponse,
                    tellorResponse
                )
            ) {
                _changeStatus(Status.chainlinkWorking);
                return _storeChainlinkPrice(chainlinkResponse.answer);
            }

            // If Chainlink is live but deviated >50% from it's previous price and Tellor is still untrusted, switch
            // to bothOraclesUntrusted and return last good price
            if (_chainlinkPriceChangeAboveMax(chainlinkResponse, prevChainlinkResponse)) {
                _changeStatus(Status.bothOraclesUntrusted);
                return lastGoodPrice;
            }

            // Otherwise if Chainlink is live and deviated <50% from it's previous price and Tellor is still untrusted,
            // return Chainlink price (no status change)
            return _storeChainlinkPrice(chainlinkResponse.answer);
        }
    }

    // --- Governance Functions ---
    /*
        @notice Sets a new fallback oracle 
        @param _tellorCaller The new ITellorCaller-compliant oracle address
    **/
    function setTellorCaller(address _tellorCaller) external {
        require(
            isAuthorized(msg.sender, SET_TELLOR_CALLER_SIG),
            "PriceFeed: sender not authorized for setTellorCaller(address)"
        );
        tellorCaller = ITellorCaller(_tellorCaller);
        emit TellorCallerChanged(_tellorCaller);
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
        uint percentDeviation = ((maxPrice - minPrice) * DECIMAL_PRECISION) / maxPrice;

        // Return true if price has more than doubled, or more than halved.
        return percentDeviation > MAX_PRICE_DEVIATION_FROM_PREVIOUS_ROUND;
    }

    function _tellorIsBroken(TellorResponse memory _response) internal view returns (bool) {
        // Check for response call reverted
        if (!_response.success) {
            return true;
        }
        // Check for an invalid timeStamp that is 0, or in the future
        if (_response.timestamp == 0 || _response.timestamp > block.timestamp) {
            return true;
        }
        // Check for zero price
        if (_response.value == 0) {
            return true;
        }

        return false;
    }

    function _tellorIsFrozen(TellorResponse memory _tellorResponse) internal view returns (bool) {
        return block.timestamp - _tellorResponse.timestamp > TIMEOUT;
    }

    function _bothOraclesLiveAndUnbrokenAndSimilarPrice(
        ChainlinkResponse memory _chainlinkResponse,
        ChainlinkResponse memory _prevChainlinkResponse,
        TellorResponse memory _tellorResponse
    ) internal view returns (bool) {
        // Return false if either oracle is broken or frozen
        if (
            _tellorIsBroken(_tellorResponse) ||
            _tellorIsFrozen(_tellorResponse) ||
            _chainlinkIsBroken(_chainlinkResponse, _prevChainlinkResponse) ||
            _chainlinkIsFrozen(_chainlinkResponse.timestamp)
        ) {
            return false;
        }

        return _bothOraclesSimilarPrice(_chainlinkResponse, _tellorResponse);
    }

    function _bothOraclesSimilarPrice(
        ChainlinkResponse memory _chainlinkResponse,
        TellorResponse memory _tellorResponse
    ) internal pure returns (bool) {
        // Get the relative price difference between the oracles. Use the lower price as the denominator, i.e. the reference for the calculation.
        uint minPrice = LiquityMath._min(_tellorResponse.value, _chainlinkResponse.answer);
        uint maxPrice = LiquityMath._max(_tellorResponse.value, _chainlinkResponse.answer);
        uint percentPriceDifference = ((maxPrice - minPrice) * DECIMAL_PRECISION) / minPrice;

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

    function _storeTellorPrice(TellorResponse memory _tellorResponse) internal returns (uint) {
        _storePrice(_tellorResponse.value);
        return _tellorResponse.value;
    }

    function _storeChainlinkPrice(uint256 _answer) internal returns (uint) {
        _storePrice(_answer);

        return _answer;
    }

    // --- Oracle response wrapper functions ---
    /*
     * "_getCurrentTellorResponse" fetches ETH/USD and BTC/USD prices from Tellor, and returns them as a
     * TellorResponse struct. ETH/BTC price is calculated as (ETH/USD) / (BTC/USD).
     */
    function _getCurrentTellorResponse()
        internal
        view
        returns (TellorResponse memory tellorResponse)
    {
        try
            tellorCaller.getTellorBufferValue(STETH_BTC_TELLOR_QUERY_ID, TELLOR_QUERY_BUFFER_SECONDS)
        returns (bool ifRetrieved, uint256 value, uint256 timestampRetrieved) {
            tellorResponse.retrieved = ifRetrieved;
            tellorResponse.value = value;
            tellorResponse.timestamp = timestampRetrieved;
            tellorResponse.success = true;
            return (tellorResponse);
        } catch {
            // If call to Tellor reverts, return a zero response with success = false
            return (tellorResponse);
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
        chainlinkResponse.answer =
            ((uint256(ethBtcAnswer) * DECIMAL_PRECISION) / uint256(stEthEthAnswer)) *
            (10 ** (STETH_ETH_CL_FEED_DECIMAL - ETH_BTC_CL_FEED_DECIMAL));
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
        prevChainlinkResponse.answer =
            ((uint256(ethBtcAnswer) * DECIMAL_PRECISION) / uint256(stEthEthAnswer)) *
            (10 ** (STETH_ETH_CL_FEED_DECIMAL - ETH_BTC_CL_FEED_DECIMAL));
        // NOTE: stick with the `Min` for `TIMEOUT` check-ups
        prevChainlinkResponse.timestamp = LiquityMath._min(ethBtcTimestamp, stEthEtTimestamp);
        prevChainlinkResponse.success = true;
    }
}
