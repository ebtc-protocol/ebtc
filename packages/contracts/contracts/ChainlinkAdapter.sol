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

    /**
     * @notice Price feed for (BTC / USD) pair
     */
    AggregatorV3Interface public immutable USD_BTC_CL_FEED;

    /**
     * @notice Price feed for (USD / ETH) pair
     */
    AggregatorV3Interface public immutable ETH_USD_CL_FEED;

    /**
     * @notice This is a parameter to bring the resulting answer with the proper precision.
     * @notice will be equal to 10 to the power of the sum decimals of feeds
     */
    int256 public immutable DENOMINATOR;

    constructor(AggregatorV3Interface _usdBtcClFeed, AggregatorV3Interface _ethUsdClFeed) {
        USD_BTC_CL_FEED = AggregatorV3Interface(_usdBtcClFeed);
        ETH_USD_CL_FEED = AggregatorV3Interface(_ethUsdClFeed);

        require(USD_BTC_CL_FEED.decimals() <= MAX_DECIMALS);
        require(ETH_USD_CL_FEED.decimals() <= MAX_DECIMALS);

        // equal to 10 to the power of the sum decimals of feeds
        unchecked {
            DENOMINATOR = int256(10 ** (USD_BTC_CL_FEED.decimals() + ETH_USD_CL_FEED.decimals()));
        }
    }

    function description() external view returns (string memory) {
        return "BTC/ETH Chainlink Adapter";
    }

    function _min(uint256 _a, uint256 _b) private pure returns (uint256) {
        return _a < _b ? _a : _b;
    }

    function _convertAnswer(
        int256 assetToPegPrice,
        int256 pegToBasePrice
    ) private view returns (int256) {
        // TODO: figure out if one of these prices needs to be inverted
        return (assetToPegPrice * pegToBasePrice * int256(10 ** decimals)) / (DENOMINATOR);
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

        int256 pegToBasePrice;
        uint256 pegToBaseUpdatedAt;
        uint80 latestRoundId = USD_BTC_CL_FEED.latestRound();
        (roundId, pegToBasePrice, /* startedAt */, pegToBaseUpdatedAt, /* answeredInRound */) = USD_BTC_CL_FEED
            .getRoundData(_roundId == CURRENT_ROUND ? latestRoundId : latestRoundId - 1);
        require(roundId > 0);
        require(pegToBasePrice > 0);

        int256 assetToPegPrice;
        uint256 assetToPegUpdatedAt;
        latestRoundId = ETH_USD_CL_FEED.latestRound();
        (roundId, assetToPegPrice, /* startedAt */, assetToPegUpdatedAt, /* answeredInRound */) = ETH_USD_CL_FEED
            .getRoundData(_roundId == CURRENT_ROUND ? latestRoundId : latestRoundId - 1);
        require(roundId > 0);
        require(assetToPegPrice > 0);

        roundId = _roundId;
        updatedAt = _min(pegToBaseUpdatedAt, assetToPegUpdatedAt);
        answer = _convertAnswer(assetToPegPrice, pegToBasePrice);
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
        int256 pegToBasePrice;
        uint256 pegToBaseUpdatedAt;
        (roundId, pegToBasePrice, /* startedAt */, pegToBaseUpdatedAt, /* answeredInRound */) = USD_BTC_CL_FEED
            .latestRoundData();
        require(roundId > 0);
        require(pegToBasePrice > 0);

        int256 assetToPegPrice;
        uint256 assetToPegUpdatedAt;
        (roundId, assetToPegPrice, /* startedAt */, assetToPegUpdatedAt, /* answeredInRound */) = ETH_USD_CL_FEED
            .latestRoundData();
        require(roundId > 0);
        require(assetToPegPrice > 0);

        roundId = CURRENT_ROUND;
        answer = _convertAnswer(assetToPegPrice, pegToBasePrice);
    }
}
