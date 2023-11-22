// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./Interfaces/IPriceFeed.sol";
import "./Interfaces/IFallbackCaller.sol";
import "./Dependencies/AggregatorV3Interface.sol";
import "./Dependencies/BaseMath.sol";
import "./Dependencies/EbtcMath.sol";
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
contract ChainlinkCaller is BaseMath, IPriceFeed, AuthNoOwner {
    string public constant NAME = "PriceFeed";

    // Chainlink oracles in mainnet
    AggregatorV3Interface public immutable ETH_BTC_CL_FEED;
    AggregatorV3Interface public immutable STETH_ETH_CL_FEED;

    // Maximum time period allowed since Chainlink's latest round data timestamp, beyond which Chainlink is considered frozen.
    uint256 public constant TIMEOUT_ETH_BTC_FEED = 4800; // 1 hours & 20min: 60 * 80
    uint256 public constant TIMEOUT_STETH_ETH_FEED = 90000; // 25 hours: 60 * 60 * 25

    // Maximum deviation allowed between two consecutive Chainlink oracle prices. 18-digit precision.
    uint256 public constant MAX_PRICE_DEVIATION_FROM_PREVIOUS_ROUND = 5e17; // 50%

    uint256 INVALID_PRICE = 0;

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
        address _ethBtcCLFeed
    ) {
        _initializeAuthority(_authorityAddress);

        ETH_BTC_CL_FEED = AggregatorV3Interface(_ethBtcCLFeed);
        STETH_ETH_CL_FEED = AggregatorV3Interface(_collEthCLFeed);

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
    }

    // --- Functions ---

    /// @notice Returns the latest price obtained from the Oracle
    /// @dev Called by eBTC functions that require a current price. Also callable permissionlessly.
    /// @dev Non-view function - it updates and stores the last good price seen by eBTC.
    /// @dev Uses a main oracle (Chainlink) and a fallback oracle in case Chainlink fails. If both fail, it uses the last good price seen by eBTC.
    /// @dev The fallback oracle address can be swapped by the Authority. The fallback oracle must conform to the IFallbackCaller interface.
    /// @return The latest price fetched from the Oracle
    function fetchPrice() external override returns (uint256) {
        // Get current and previous price data from Chainlink, and current price data from Fallback
        ChainlinkResponse memory chainlinkResponse = _getCurrentChainlinkResponse();

        // Early failure
        if (_chainlinkIsFrozen(chainlinkResponse)) {
            return INVALID_PRICE;
        }

        // TODO: Maybe add max and min checks as well
        // Feed.aggregator.minAnswer
        // Feed.aggregator.maxAnswer

        ChainlinkResponse memory prevChainlinkResponse = _getPrevChainlinkResponse(
            chainlinkResponse.roundEthBtcId,
            chainlinkResponse.roundStEthEthId
        );

        if (_chainlinkIsFrozen(prevChainlinkResponse)) {
            return INVALID_PRICE;
        }

        if (_chainlinkIsBroken(chainlinkResponse, prevChainlinkResponse)) {
            return INVALID_PRICE;
        }

        if (_chainlinkPriceChangeAboveMax(chainlinkResponse, prevChainlinkResponse)) {
            return INVALID_PRICE;
        }

        return chainlinkResponse.answer;
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

    function _responseTimeout(uint256 _timestamp, uint256 _timeout) internal view returns (bool) {
        return block.timestamp - _timestamp > _timeout;
    }

    /// @notice Fetches Chainlink responses for the current round of data for both ETH-BTC and stETH-ETH price feeds.
    /// @return chainlinkResponse A struct containing data retrieved from the price feeds, including the round IDs, timestamps, aggregated price, and a success flag.
    function _getCurrentChainlinkResponse()
        internal
        view
        returns (ChainlinkResponse memory chainlinkResponse)
    {
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
            _checkHealthyCLResponse(chainlinkResponse.roundEthBtcId, ethBtcAnswer) &&
            _checkHealthyCLResponse(chainlinkResponse.roundStEthEthId, stEthEthAnswer)
        ) {
            chainlinkResponse.answer = _formatClAggregateAnswer(
                ethBtcAnswer,
                stEthEthAnswer,
                ethBtcDecimals,
                stEthEthDecimals
            );
        } else {
            return chainlinkResponse;
        }

        chainlinkResponse.success = true;
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

        // Fetch decimals for both feeds:
        uint8 ethBtcDecimals;
        uint8 stEthEthDecimals;

        try ETH_BTC_CL_FEED.decimals() returns (uint8 decimals) {
            // If call to Chainlink succeeds, record the current decimal precision
            ethBtcDecimals = decimals;
        } catch {
            // If call to Chainlink aggregator reverts, return a zero response with success = false
            return prevChainlinkResponse;
        }

        try STETH_ETH_CL_FEED.decimals() returns (uint8 decimals) {
            // If call to Chainlink succeeds, record the current decimal precision
            stEthEthDecimals = decimals;
        } catch {
            // If call to Chainlink aggregator reverts, return a zero response with success = false
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

        try STETH_ETH_CL_FEED.getRoundData(_currentRoundStEthEthId - 1) returns (
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
            prevChainlinkResponse.answer = _formatClAggregateAnswer(
                ethBtcAnswer,
                stEthEthAnswer,
                ethBtcDecimals,
                stEthEthDecimals
            );
        } else {
            return prevChainlinkResponse;
        }

        prevChainlinkResponse.success = true;
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

    // @notice Returns the price of stETH:BTC in 18 decimals denomination
    // @param _ethBtcAnswer CL price retrieve from ETH:BTC feed
    // @param _stEthEthAnswer CL price retrieve from stETH:BTC feed
    // @param _ethBtcDecimals ETH:BTC feed decimals
    // @param _stEthEthDecimals stETH:BTC feed decimalss
    // @return The aggregated calculated price for stETH:BTC
    function _formatClAggregateAnswer(
        int256 _ethBtcAnswer,
        int256 _stEthEthAnswer,
        uint8 _ethBtcDecimals,
        uint8 _stEthEthDecimals
    ) internal view returns (uint256) {
        uint256 _decimalDenominator = _stEthEthDecimals > _ethBtcDecimals
            ? _stEthEthDecimals
            : _ethBtcDecimals;
        uint256 _scaledDecimal = _stEthEthDecimals > _ethBtcDecimals
            ? 10 ** (_stEthEthDecimals - _ethBtcDecimals)
            : 10 ** (_ethBtcDecimals - _stEthEthDecimals);
        return
            (_scaledDecimal *
                uint256(_ethBtcAnswer) *
                uint256(_stEthEthAnswer) *
                EbtcMath.DECIMAL_PRECISION) / 10 ** (_decimalDenominator * 2);
    }
}
