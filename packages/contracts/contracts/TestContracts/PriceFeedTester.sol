// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../PriceFeed.sol";

contract PriceFeedTester is PriceFeed {
    constructor(
        address _tellorCallerAddress,
        address _authorityAddress,
        address _collEthCLFeed,
        address _ethBtcCLFeed
    ) PriceFeed(_tellorCallerAddress, _authorityAddress, _collEthCLFeed, _ethBtcCLFeed) {}

    function setLastGoodPrice(uint _lastGoodPrice) external {
        lastGoodPrice = _lastGoodPrice;
    }

    function setStatus(Status _status) external {
        status = _status;
    }

    function formatClAggregateAnswer(
        int256 _ethBtcAnswer,
        int256 _stEthEthAnswer,
        uint8 _ethBtcDecimals,
        uint8 _stEthEthDecimals
    ) external view returns (uint256) {
        return
            _formatClAggregateAnswer(
                _ethBtcAnswer,
                _stEthEthAnswer,
                _ethBtcDecimals,
                _stEthEthDecimals
            );
    }
}
