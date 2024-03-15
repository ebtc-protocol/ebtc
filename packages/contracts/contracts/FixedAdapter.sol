// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {AggregatorV3Interface} from "./Dependencies/AggregatorV3Interface.sol";

contract FixedAdapter is AggregatorV3Interface {
    uint8 public constant override decimals = 18;
    uint256 public constant override version = 1;

    /// @notice PriceFeed always fetches current and previous rounds. It's ok to
    /// hardcode round IDs as long as they are greater than 0.
    uint80 public constant CURRENT_ROUND = 2;
    uint80 public constant PREVIOUS_ROUND = 1;
    int256 internal constant ADAPTER_PRECISION = int256(10 ** decimals);

    function description() external view returns (string memory) {
        return "stETH/ETH Fixed Adapter";
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

        roundId = _roundId;
        updatedAt = _roundId == CURRENT_ROUND ? block.timestamp : block.timestamp - 1;
        answer = ADAPTER_PRECISION;
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
        roundId = CURRENT_ROUND;
        updatedAt = block.timestamp;
        answer = ADAPTER_PRECISION;
    }
}
