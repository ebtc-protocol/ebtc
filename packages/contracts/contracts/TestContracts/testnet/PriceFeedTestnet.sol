// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../../Interfaces/IPriceFeed.sol";
import "../../Interfaces/IFallbackCaller.sol";
import "../../Dependencies/Ownable.sol";
import "../../Dependencies/AuthNoOwner.sol";

/*
 * PriceFeed placeholder for testnet and development. The price can be manually input or fetched from
   the Fallback's TestNet implementation. Backwards compatible with local test environment as it defaults to use
   the manual price.
 */
contract PriceFeedTestnet is IPriceFeed, Ownable, AuthNoOwner {
    // --- variables ---

    uint256 private _price = 7428 * 1e13; // stETH/BTC price == ~15.8118 ETH per BTC
    bool public _useFallback;
    IFallbackCaller public fallbackCaller; // Wrapper contract that calls the Fallback system

    constructor(address _authorityAddress) {
        _initializeAuthority(_authorityAddress);
    }

    // --- Dependency setters ---

    function setAddresses(
        address _priceAggregatorAddress, // Not used but kept for compatibility with deployment script
        address _fallbackCallerAddress,
        address _authorityAddress
    ) external onlyOwner {
        fallbackCaller = IFallbackCaller(_fallbackCallerAddress);

        _initializeAuthority(_authorityAddress);

        renounceOwnership();
    }

    // --- Functions ---

    // View price getter for simplicity in tests
    function getPrice() external view returns (uint256) {
        return _price;
    }

    function fetchPrice() external override returns (uint256) {
        // Fire an event just like the mainnet version would.
        // This lets the subgraph rely on events to get the latest price even when developing locally.
        if (_useFallback) {
            FallbackResponse memory fallbackResponse = _getCurrentFallbackResponse();
            if (fallbackResponse.success) {
                _price = fallbackResponse.answer;
            }
        }
        emit LastGoodPriceUpdated(_price);
        return _price;
    }

    // Manual external price setter.
    function setPrice(uint256 price) external returns (bool) {
        _price = price;
        return true;
    }

    // Manual toggle use of Tellor testnet feed
    function toggleUseFallback() external returns (bool) {
        _useFallback = !_useFallback;
        return _useFallback;
    }

    function setFallbackCaller(address _fallbackCaller) external requiresAuth {
        address oldFallbackCaller = address(fallbackCaller);
        fallbackCaller = IFallbackCaller(_fallbackCaller);
        emit FallbackCallerChanged(oldFallbackCaller, _fallbackCaller);
    }

    // --- Oracle response wrapper functions ---
    /*
     * "_getCurrentFallbackResponse" fetches stETH/BTC from the Fallback, and returns it as a
     * FallbackResponse struct.
     */
    function _getCurrentFallbackResponse()
        internal
        view
        returns (FallbackResponse memory fallbackResponse)
    {
        uint256 stEthBtcValue;
        uint256 stEthBtcTimestamp;
        bool stEthBtcRetrieved;

        // Attempt to get the Fallback's stETH/BTC price
        try fallbackCaller.getFallbackResponse() returns (
            uint256 answer,
            uint256 timestampRetrieved,
            bool success
        ) {
            fallbackResponse.answer = answer;
            fallbackResponse.timestamp = timestampRetrieved;
            fallbackResponse.success = success;
        } catch {
            return (fallbackResponse);
        }
        return (fallbackResponse);
    }
}
