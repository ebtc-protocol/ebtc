// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface ITellorCaller {
    function getTellorBufferValue(
        bytes32 _queryId,
        uint256 _bufferInSeconds
    ) external view returns (bool, uint256, uint256);
}
