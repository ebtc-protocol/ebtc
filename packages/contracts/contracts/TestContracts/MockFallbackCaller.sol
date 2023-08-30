// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import {IFallbackCaller} from "../interfaces/IFallbackCaller.sol";

contract MockFallbackCaller is IFallbackCaller {
    uint256 public _answer;
    uint256 public _timestampRetrieved;
    uint256 public _fallbackTimeout;
    bool public _success;

    bool public getFallbackResponseRevert;
    bool public fallbackTimeoutRevert;

    function setGetFallbackResponseRevert() external {
        getFallbackResponseRevert = !getFallbackResponseRevert;
    }

    function setFallbackTimeoutRevert() external {
        fallbackTimeoutRevert = !fallbackTimeoutRevert;
    }

    function setFallbackResponse(uint256 answer, uint256 timestampRetrieved, bool success) external {
        _answer = answer;
        _timestampRetrieved = timestampRetrieved;
        _success = success;
    }

    function setFallbackTimeout(uint256 newFallbackTimeout) external {
        uint256 oldTimeOut = _fallbackTimeout;
        _fallbackTimeout = newFallbackTimeout;
        emit FallbackTimeOutChanged(oldTimeOut, newFallbackTimeout);
    }

    function getFallbackResponse() external view returns (uint256, uint256, bool) {
        if (getFallbackResponseRevert) {
            require(1 == 0, "getFallbackResponse reverted");
        }
        return (_answer, _timestampRetrieved, _success);
    }

    function fallbackTimeout() external view returns (uint256) {
        if (fallbackTimeoutRevert) {
            require(1 == 0, "fallbackTimeout reverted");
        }
        return _fallbackTimeout;
    }
}
