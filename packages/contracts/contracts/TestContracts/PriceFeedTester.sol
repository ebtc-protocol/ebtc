// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../PriceFeed.sol";

contract PriceFeedTester is PriceFeed {
    constructor(
        address _tellorCallerAddress,
        address _authorityAddress,
        address _collEthCLFeed,
        address _ethBtcCLFeed,
        bool _useDynamicFeed
    )
        PriceFeed(
            _tellorCallerAddress,
            _authorityAddress,
            _collEthCLFeed,
            _ethBtcCLFeed,
            _useDynamicFeed
        )
    {}

    function setLastGoodPrice(uint256 _lastGoodPrice) external {
        lastGoodPrice = _lastGoodPrice;
    }

    function setStatus(Status _status) external {
        status = _status;
    }

    function getCurrentFallbackResponse()
        public
        view
        returns (FallbackResponse memory fallbackResponse)
    {
        return _getCurrentFallbackResponse();
    }

    function getCurrentChainlinkResponse() public view returns (ChainlinkResponse memory) {
        return _getCurrentChainlinkResponse();
    }

    function getPrevChainlinkResponse(
        uint80 _currentRoundEthBtcId,
        uint80 _currentRoundStEthEthId
    ) public view returns (ChainlinkResponse memory) {
        return _getPrevChainlinkResponse(_currentRoundEthBtcId, _currentRoundStEthEthId);
    }

    function bothOraclesSimilarPrice(
        ChainlinkResponse memory _chainlinkResponse,
        FallbackResponse memory _fallbackResponse
    ) public view returns (bool) {
        return _bothOraclesSimilarPrice(_chainlinkResponse, _fallbackResponse);
    }

    function bothOraclesAliveAndUnbrokenAndSimilarPrice(
        ChainlinkResponse memory _chainlinkResponse,
        ChainlinkResponse memory _prevChainlinkResponse,
        FallbackResponse memory _fallbackResponse
    ) public view returns (bool) {
        return
            _bothOraclesLiveAndUnbrokenAndSimilarPrice(
                _chainlinkResponse,
                _prevChainlinkResponse,
                _fallbackResponse
            );
    }

    function chainlinkIsFrozen(ChainlinkResponse memory _response) public view returns (bool) {
        return _chainlinkIsFrozen(_response);
    }

    function chainlinkIsBroken(
        ChainlinkResponse memory _currentResponse,
        ChainlinkResponse memory _prevResponse
    ) public view returns (bool) {
        return _chainlinkIsBroken(_currentResponse, _prevResponse);
    }

    function fallbackIsFrozen(FallbackResponse memory _fallbackResponse) public view returns (bool) {
        return _fallbackIsFrozen(_fallbackResponse);
    }

    function fallbackIsBroken(FallbackResponse memory _response) public view returns (bool) {
        return _fallbackIsBroken(_response);
    }

    function chainlinkPriceChangeAboveMax(
        ChainlinkResponse memory _currentResponse,
        ChainlinkResponse memory _prevResponse
    ) public view returns (bool) {
        return _chainlinkPriceChangeAboveMax(_currentResponse, _prevResponse);
    }

    function formatClAggregateAnswer(
        int256 _ethBtcAnswer,
        int256 _stEthEthAnswer
    ) external view returns (uint256) {
        return _formatClAggregateAnswer(_ethBtcAnswer, _stEthEthAnswer);
    }
}
