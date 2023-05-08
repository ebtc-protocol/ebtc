// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface IPriceFeed {
    // --- Events ---
    event LastGoodPriceUpdated(uint _lastGoodPrice);
    event PriceFeedStatusChanged(Status newStatus);
    event FallbackCallerChanged(address _fallbackCaller);

    // --- Structs ---
    struct ChainlinkResponse {
        uint80 roundId;
        int256 answer;
        uint256 timestamp;
        bool success;
        uint8 decimals;
    }

    struct FallbackResponse {
        uint256 answer;
        uint256 timestamp;
        bool success;
    }

    enum Status {
        chainlinkWorking,
        usingFallbackChainlinkUntrusted,
        bothOraclesUntrusted,
        usingFallbackChainlinkFrozen,
        usingChainlinkFallbackUntrusted
    }

    // --- Function ---
    function fetchPrice() external returns (uint);
}
