// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "../Interfaces/ITellorCaller.sol";
import "./ITellor.sol";
import "./SafeMath.sol";

/*
 * This contract is a mock that returns hardcoded price
 * Should not be used on mainnet
 */
contract TellorCallerMock is ITellorCaller {
    using SafeMath for uint256;

    ITellor public tellor;

    constructor(address _tellorMasterAddress) public {
        tellor = ITellor(_tellorMasterAddress);
    }

    // Mock price data
    function getTellorBufferValue(
        bytes32 _queryId,
        uint256 _bufferInSeconds
    ) external view override returns (bool, uint256, uint256) {
        return (true, 7428 * 1e13, block.timestamp);
    }
}
