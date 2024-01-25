// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {AggregatorV3Interface} from "./Dependencies/AggregatorV3Interface.sol";

contract ChainlinkAdapter is AggregatorV3Interface {
    uint8 public constant override decimals = 18;
    uint256 public constant override version = 1;

    /**
     * @notice Maximum number of resulting and feed decimals
     */
    uint8 public constant MAX_DECIMALS = 18;
    uint80 public constant CURRENT_ROUND = 2;
    uint80 public constant PREVIOUS_ROUND = 1;
    int256 internal constant ADAPTER_PRECISION = int256(10 ** decimals);

    /**
     * @notice Price feed for (BTC / USD) pair
     */
    AggregatorV3Interface public immutable BTC_USD_CL_FEED;

    /**
     * @notice Price feed for (ETH / USD) pair
     */
    AggregatorV3Interface public immutable ETH_USD_CL_FEED;

    int256 internal immutable BTC_USD_PRECISION;
    int256 internal immutable ETH_USD_PRECISION;

    constructor(AggregatorV3Interface _btcUsdClFeed, AggregatorV3Interface _ethUsdClFeed) {
        BTC_USD_CL_FEED = AggregatorV3Interface(_btcUsdClFeed);
        ETH_USD_CL_FEED = AggregatorV3Interface(_ethUsdClFeed);

        require(BTC_USD_CL_FEED.decimals() <= MAX_DECIMALS);
        require(ETH_USD_CL_FEED.decimals() <= MAX_DECIMALS);

        BTC_USD_PRECISION = int256(10 ** BTC_USD_CL_FEED.decimals());
        ETH_USD_PRECISION = int256(10 ** ETH_USD_CL_FEED.decimals());
    }

    function description() external view returns (string memory) {
        return "BTC/ETH Chainlink Adapter";
    }

    function _min(uint256 _a, uint256 _b) private pure returns (uint256) {
        return _a < _b ? _a : _b;
    }

    function _convertAnswer(int256 ethUsdPrice, int256 btcUsdPrice) private view returns (int256) {
        return
            (ethUsdPrice * BTC_USD_PRECISION * ADAPTER_PRECISION) /
            (ETH_USD_PRECISION * btcUsdPrice);
    }

    function latestRound() external view returns (uint80) {
        return CURRENT_ROUND;
    }

    // getRoundData and latestRoundData should both raise "No data present"
    // if they do not have data to report, instead of returning unset values
    // which could be misinterpreted as actual reported values.
    function getRoundData(
        uint80 _roundId
    )
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        require(_roundId == CURRENT_ROUND || _roundId == PREVIOUS_ROUND);

        int256 btcUsdPrice;
        uint256 btcUsdUpdatedAt;
        uint80 latestRoundId = BTC_USD_CL_FEED.latestRound();
        (
            roundId,
            btcUsdPrice /* startedAt */,
            ,
            btcUsdUpdatedAt /* answeredInRound */,

        ) = BTC_USD_CL_FEED.getRoundData(
            _roundId == CURRENT_ROUND ? latestRoundId : latestRoundId - 1
        );
        require(roundId > 0);
        require(btcUsdPrice > 0);

        int256 ethUsdPrice;
        uint256 ethUsdUpdatedAt;
        latestRoundId = ETH_USD_CL_FEED.latestRound();
        (
            roundId,
            ethUsdPrice /* startedAt */,
            ,
            ethUsdUpdatedAt /* answeredInRound */,

        ) = ETH_USD_CL_FEED.getRoundData(
            _roundId == CURRENT_ROUND ? latestRoundId : latestRoundId - 1
        );
        require(roundId > 0);
        require(ethUsdPrice > 0);

        roundId = _roundId;
        updatedAt = _min(btcUsdUpdatedAt, ethUsdUpdatedAt);
        answer = _convertAnswer(ethUsdPrice, btcUsdPrice);
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        int256 btcUsdPrice;
        uint256 btcUsdUpdatedAt;
        (
            roundId,
            btcUsdPrice /* startedAt */,
            ,
            btcUsdUpdatedAt /* answeredInRound */,

        ) = BTC_USD_CL_FEED.latestRoundData();
        require(roundId > 0);
        require(btcUsdPrice > 0);

        int256 ethUsdPrice;
        uint256 ethUsdUpdatedAt;
        (
            roundId,
            ethUsdPrice /* startedAt */,
            ,
            ethUsdUpdatedAt /* answeredInRound */,

        ) = ETH_USD_CL_FEED.latestRoundData();
        require(roundId > 0);
        require(ethUsdPrice > 0);

        roundId = CURRENT_ROUND;
        updatedAt = _min(btcUsdUpdatedAt, ethUsdUpdatedAt);
        answer = _convertAnswer(ethUsdPrice, btcUsdPrice);
    }
}
