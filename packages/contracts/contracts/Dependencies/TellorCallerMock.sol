// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../Interfaces/IFallbackCaller.sol";
import "./ITellor.sol";

/*
 * This contract is a mock that returns hardcoded price
 * Should not be used on mainnet
 */
contract TellorCallerMock is IFallbackCaller {
    ITellor public tellor;
    uint256 timeOut;

    constructor(address _tellorMasterAddress) public {
        tellor = ITellor(_tellorMasterAddress);

        // NOTE: random value for completeness purposes
        timeOut = 4800;
    }

    // Mock price data
    function getFallbackResponse() external view override returns (uint256, uint256, bool) {
        return (7428 * 1e13, block.timestamp, true);
    }

    function fallbackTimeout() external view returns (uint256) {
        return timeOut;
    }

    function setFallbackTimeout(uint256 _newFallbackTimeout) external {
        uint256 oldTimeOut = timeOut;
        timeOut = _newFallbackTimeout;
        emit FallbackTimeOutChanged(oldTimeOut, _newFallbackTimeout);
    }
}
