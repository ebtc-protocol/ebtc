// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../Dependencies/AggregatorV3Interface.sol";

contract TenderlyAggregator is AggregatorV3Interface {
    AggregatorV3Interface public immutable BASE_ORACLE;

    constructor(address baseOracle) {
        BASE_ORACLE = AggregatorV3Interface(baseOracle);
    }

    function decimals() external view returns (uint8) {
        return BASE_ORACLE.decimals();
    }

    function description() external view returns (string memory) {
        return BASE_ORACLE.description();
    }

    function version() external view returns (uint256) {
        return BASE_ORACLE.version();
    }

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
        (roundId, answer, startedAt, updatedAt, answeredInRound) = BASE_ORACLE.getRoundData(
            _roundId
        );

        updatedAt = block.timestamp;
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
        (roundId, answer, startedAt, updatedAt, answeredInRound) = BASE_ORACLE.latestRoundData();

        updatedAt = block.timestamp;
    }
}
