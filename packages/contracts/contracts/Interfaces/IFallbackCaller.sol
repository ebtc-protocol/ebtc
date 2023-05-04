// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface IFallbackCaller {
    function getFallbackResponse() external view returns (
        uint256,
        uint256,
        bool,
        uint8
    );
}
