// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface IFallbackCaller {
    // --- Events ---
    event FallbackTimeOutChanged(uint256 _oldTimeOut, uint256 _newTimeOut);

    // --- Function External View ---

    // NOTE: The fallback oracle must always return its answer scaled to 18 decimals where applicable
    //       The system will assume an 18 decimal response for efficiency.
    function getFallbackResponse() external view returns (uint256, uint256, bool);

    // NOTE: this returns the timeout window interval for the fallback oracle instead
    // of storing in the `PriceFeed` contract is retrieve for the `FallbackCaller`
    function fallbackTimeout() external view returns (uint256);

    // --- Function External Setter ---

    function setFallbackTimeout(uint256 newFallbackTimeout) external;
}
