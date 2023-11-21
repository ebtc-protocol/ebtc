// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./Interfaces/IPriceFeed.sol";
import "./Interfaces/IFallbackCaller.sol";
import "./Dependencies/AggregatorV3Interface.sol";
import "./Dependencies/BaseMath.sol";
import "./Dependencies/AuthNoOwner.sol";
import "./Dependencies/LiquityMath.sol";

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

    // Fallback feed
    IFallbackCaller public fallbackCaller; // Wrapper contract that calls the fallback system

    // Maximum time period allowed since Chainlink's latest round data timestamp, beyond which Chainlink is considered frozen.
    uint256 public constant TIMEOUT_ETH_BTC_FEED = 4800; // 1 hours & 20min: 60 * 80
    uint256 public constant TIMEOUT_STETH_ETH_FEED = 90000; // 25 hours: 60 * 60 * 25

    // Maximum deviation allowed between two consecutive Chainlink oracle prices. 18-digit precision.
    uint256 public constant MAX_PRICE_DEVIATION_FROM_PREVIOUS_ROUND = 5e17; // 50%

    /*
     * The maximum relative price difference between two oracle responses allowed in order for the PriceFeed
     * to return to using the Chainlink oracle. 18-digit precision.
     */
    uint256 public constant MAX_PRICE_DIFFERENCE_BETWEEN_ORACLES = 5e16; // 5%

    // The last good price seen from an oracle by Liquity
    uint256 public lastGoodPrice;

    // The current status of the PriceFeed, which determines the conditions for the next price fetch attempt
    Status public status;

    // --- Dependency setters ---

    /// @notice Sets the addresses of the contracts and initializes the system
    /// @param _fallbackCallerAddress The address of the Fallback oracle contract
    /// @param _authorityAddress The address of the Authority contract
    /// @param _collEthCLFeed The address of the collateral-ETH ChainLink feed
    /// @param _ethBtcCLFeed The address of the ETH-BTC ChainLink feed
    /// @dev One time initiailziation function. The caller must be the PriceFeed contract's owner (i.e. eBTC Deployer contract) for security. Ownership is renounced after initialization.
    constructor(
        address _fallbackCallerAddress,
        address _authorityAddress,
        address _collEthCLFeed,
        address _ethBtcCLFeed
    ) {
        fallbackCaller = IFallbackCaller(_fallbackCallerAddress);

        _initializeAuthority(_authorityAddress);

        emit FallbackCallerChanged(address(0), _fallbackCallerAddress);

        ETH_BTC_CL_FEED = AggregatorV3Interface(_ethBtcCLFeed);
        STETH_ETH_CL_FEED = AggregatorV3Interface(_collEthCLFeed);

        // Explicitly set initial system status after `require` checks
        status = Status.chainlinkWorking;
    }

    function fetchPrice() external override returns (uint256) {
        ChainlinkResponse memory chainlinkResponse = _getCurrentChainlinkResponse();

        // If chainlink is working, use CL
        if (chainlinkResponse.success) {
            _storePrice(chainlinkResponse.answer);

            return chainlinkResponse.answer;
        }

        // CL Not working, get Fallback
        FallbackResponse memory fallbackResponse = _getCurrentFallbackResponse();

        if (fallbackResponse.success) {
            _storePrice(fallbackResponse.answer);

            return fallbackResponse.answer;
        }

        // Default to last good price, most likely best to repay and close for everyone
        return lastGoodPrice;
    }

    function _getCurrentChainlinkResponse() internal view returns (ChainlinkResponse memory chainlinkResponse) {
        // Fetch decimals for both feeds:
        uint8 ethBtcDecimals;
        uint8 stEthEthDecimals;

        try ETH_BTC_CL_FEED.decimals() returns (uint8 decimals) {
            // If call to Chainlink succeeds, record the current decimal precision
            ethBtcDecimals = decimals;
        } catch {
            // If call to Chainlink aggregator reverts, return a zero response with success = false
            return chainlinkResponse;
        }

        try STETH_ETH_CL_FEED.decimals() returns (uint8 decimals) {
            // If call to Chainlink succeeds, record the current decimal precision
            stEthEthDecimals = decimals;
        } catch {
            // If call to Chainlink aggregator reverts, return a zero response with success = false
            return chainlinkResponse;
        }

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

        try STETH_ETH_CL_FEED.latestRoundData() returns (
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
            _checkHealthyCLResponse(chainlinkResponse.roundEthBtcId, ethBtcAnswer)
                && _checkHealthyCLResponse(chainlinkResponse.roundStEthEthId, stEthEthAnswer)
        ) {
            chainlinkResponse.answer =
                _formatClAggregateAnswer(ethBtcAnswer, stEthEthAnswer, ethBtcDecimals, stEthEthDecimals);
        } else {
            return chainlinkResponse;
        }

        chainlinkResponse.success = true;
    }

    function _checkHealthyCLResponse(uint80 _roundId, int256 _answer) internal view returns (bool) {
        if (_answer <= 0) return false;
        if (_roundId == 0) return false;

        return true;
    }

    function _formatClAggregateAnswer(
        int256 _ethBtcAnswer,
        int256 _stEthEthAnswer,
        uint8 _ethBtcDecimals,
        uint8 _stEthEthDecimals
    ) internal view returns (uint256) {
        uint256 _decimalDenominator = _stEthEthDecimals > _ethBtcDecimals ? _stEthEthDecimals : _ethBtcDecimals;
        uint256 _scaledDecimal = _stEthEthDecimals > _ethBtcDecimals
            ? 10 ** (_stEthEthDecimals - _ethBtcDecimals)
            : 10 ** (_ethBtcDecimals - _stEthEthDecimals);
        return (_scaledDecimal * uint256(_ethBtcAnswer) * uint256(_stEthEthAnswer) * LiquityMath.DECIMAL_PRECISION)
            / 10 ** (_decimalDenominator * 2);
    }

    function _bothOraclesSimilarPrice(
        ChainlinkResponse memory _chainlinkResponse,
        FallbackResponse memory _fallbackResponse
    ) internal pure returns (bool) {
        // Get the relative price difference between the oracles. Use the lower price as the denominator, i.e. the reference for the calculation.
        uint256 minPrice = LiquityMath._min(_fallbackResponse.answer, _chainlinkResponse.answer);
        if (minPrice == 0) return false;
        uint256 maxPrice = LiquityMath._max(_fallbackResponse.answer, _chainlinkResponse.answer);
        uint256 percentPriceDifference = ((maxPrice - minPrice) * LiquityMath.DECIMAL_PRECISION) / minPrice;

        /*
         * Return true if the relative price difference is <= MAX_PRICE_DIFFERENCE_BETWEEN_ORACLES: if so, we assume both oracles are probably reporting
         * the honest market price, as it is unlikely that both have been broken/hacked and are still in-sync.
         */
        return percentPriceDifference <= MAX_PRICE_DIFFERENCE_BETWEEN_ORACLES;
    }

    function _getCurrentFallbackResponse() internal view returns (FallbackResponse memory fallbackResponse) {
        if (address(fallbackCaller) != address(0)) {
            try fallbackCaller.getFallbackResponse() returns (uint256 answer, uint256 timestampRetrieved, bool success)
            {
                fallbackResponse.answer = answer;
                fallbackResponse.timestamp = timestampRetrieved;
                fallbackResponse.success = success;
            } catch {
                // If call to Fallback reverts, return a zero response with success = false
            }
        } // If unset we return a zero response with success = false

        // Return is implicit
    }

    /// @notice Stores the latest valid price.
    /// @param _currentPrice The price to be stored.
    function _storePrice(uint256 _currentPrice) internal {
        lastGoodPrice = _currentPrice;
        emit LastGoodPriceUpdated(_currentPrice);
    }
}
