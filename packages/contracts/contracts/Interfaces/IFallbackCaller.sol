// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface IFallbackCaller {
    // NOTE: The fallback oracle must always return its answer scaled to 18 decimals where applicable
    //       The system will assume an 18 decimal response for efficiency.
    function getFallbackResponse() external view returns (uint256, uint256, bool);
}
