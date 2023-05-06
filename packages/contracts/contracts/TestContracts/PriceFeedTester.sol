// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../PriceFeed.sol";

contract PriceFeedTester is PriceFeed {
    constructor(
        address _priceAggregatorAddress,
        address _tellorCallerAddress,
        address _authorityAddress
    ) PriceFeed(_priceAggregatorAddress, _tellorCallerAddress, _authorityAddress) {}

    function setLastGoodPrice(uint _lastGoodPrice) external {
        lastGoodPrice = _lastGoodPrice;
    }

    function setStatus(Status _status) external {
        status = _status;
    }
}
