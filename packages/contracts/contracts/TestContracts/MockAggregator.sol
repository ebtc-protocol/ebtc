// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../Dependencies/AggregatorV3Interface.sol";

contract MockAggregator is AggregatorV3Interface {
    // storage variables to hold the mock data
    uint8 private decimalsVal;
    int private price;
    int private prevPrice;
    uint256 private updateTime;
    uint256 private prevUpdateTime;

    uint80 private latestRoundId;
    uint80 private prevRoundId;

    bool public latestRevert;
    bool public prevRevert;
    bool public decimalsRevert;

    constructor(uint8 _decimals) {
        decimalsVal = _decimals;
    }

    // --- Functions ---

    function setDecimals(uint8 _decimals) external {
        decimalsVal = _decimals;
    }

    function setPrice(int _price) external {
        price = _price;
    }

    function setPrevPrice(int _prevPrice) external {
        prevPrice = _prevPrice;
    }

    function setPrevUpdateTime(uint256 _prevUpdateTime) external {
        prevUpdateTime = _prevUpdateTime;
    }

    function setUpdateTime(uint256 _updateTime) external {
        updateTime = _updateTime;
    }

    function setLatestRevert() external {
        latestRevert = !latestRevert;
    }

    function setPrevRevert() external {
        prevRevert = !prevRevert;
    }

    function setDecimalsRevert() external {
        decimalsRevert = !decimalsRevert;
    }

    function setLatestRoundId(uint80 _latestRoundId) external {
        latestRoundId = _latestRoundId;
    }

    function setPrevRoundId(uint80 _prevRoundId) external {
        prevRoundId = _prevRoundId;
    }

    function getPrice() public view returns (int) {
        return price;
    }

    function getPrevPrice() public view returns (int) {
        return prevPrice;
    }

    // --- Getters that adhere to the AggregatorV3 interface ---

    function decimals() external view override returns (uint8) {
        if (decimalsRevert) {
            require(1 == 0, "decimals reverted");
        }

        return decimalsVal;
    }

    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        if (latestRevert) {
            require(1 == 0, "latestRoundData reverted");
        }

        return (latestRoundId, price, 0, updateTime, 0);
    }

    function getRoundData(
        uint80 _roundId
    )
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        if (_roundId == latestRoundId) {
            if (latestRevert) {
                require(1 == 0, "latestRoundData reverted");
            }

            return (latestRoundId, price, 0, updateTime, 0);
        }

        if (prevRevert) {
            require(1 == 0, "getRoundData reverted");
        }

        return (prevRoundId, prevPrice, 0, updateTime, 0);
    }

    function description() external pure override returns (string memory) {
        return "";
    }

    function version() external pure override returns (uint256) {
        return 1;
    }
}
