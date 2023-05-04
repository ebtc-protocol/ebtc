// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../../Interfaces/IPriceFeed.sol";
import "../../Interfaces/IFallbackCaller.sol";
import "./../../Dependencies/Ownable.sol";
import "./../../Dependencies/CheckContract.sol";
import "./../../Dependencies/AuthNoOwner.sol";

/*
 * PriceFeed placeholder for testnet and development. The price can be manually input or fetched from
   Tellor's TestNet implementation. Backwards compatible with local test environment as it defaults to use
   the manual price.
 */
contract PriceFeedTestnet is IPriceFeed, Ownable, CheckContract, AuthNoOwner {
    // -- Permissioned Function Signatures --
    bytes4 private constant SET_FALLBACK_CALLER_SIG =
        bytes4(keccak256(bytes("setFallbackCaller(address)")));

    // --- variables ---

    uint256 private _price = 7428 * 1e13; // stETH/BTC price == ~15.8118 ETH per BTC
    bool public _useTellor;
    IFallbackCaller public tellorCaller; // Wrapper contract that calls the Tellor system

    struct FallbackResponse {
        bool ifRetrieve;
        uint256 value;
        uint256 timestamp;
        bool success;
    }

    event FallbackCallerChanged(address _fallbackCaller);

    // --- Dependency setters ---

    function setAddresses(
        address _priceAggregatorAddress, // Not used but kept for compatibility with deployment script
        address _tellorCallerAddress,
        address _authorityAddress
    ) external onlyOwner {
        checkContract(_tellorCallerAddress);

        tellorCaller = IFallbackCaller(_tellorCallerAddress);

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
        if (_useTellor) {
            FallbackResponse memory fallbackResponse = _getCurrentFallbackResponse();
            if (fallbackResponse.success) {
                _price = fallbackResponse.value;
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
    function toggleUseTellor() external returns (bool) {
        _useTellor = !_useTellor;
        return _useTellor;
    }

    function setFallbackCaller(address _fallbackCaller) external {
        require(
            isAuthorized(msg.sender, SET_FALLBACK_CALLER_SIG),
            "PriceFeed: sender not authorized for setFallbackCaller(address)"
        );
        fallbackCaller = IFallbackCaller(_fallbackCaller);
        emit FallbackCallerChanged(fallbackCaller);
    }

    // --- Oracle response wrapper functions ---
    /*
     * "_getCurrentFallbackResponse" fetches stETH/BTC from Tellor, and returns it as a
     * FallbackResponse struct.
     */
    function _getCurrentFallbackResponse()
        internal
        view
        returns (FallbackResponse memory fallbackResponse)
    {
        uint stEthBtcValue;
        uint stEthBtcTimestamp;
        bool stEthBtcRetrieved;


        // Attempt to get the Fallback's stETH/BTC price
        try
            tellorCaller.getFallbackResponse()
        returns (uint256 answer, uint256 timestampRetrieved, bool success, uint8 decimals) {
            fallbackResponse.answer = answer;
            fallbackResponse.timestamp = timestampRetrieved;
            fallbackResponse.success = success;
            fallbackResponse.decimals = decimals;
        } catch {
            return (fallbackResponse);
        }

        // If the price was not retrieved, return the FallbackResponse struct with success = false.
        if (!stEthBtcRetrieved) {
            return (fallbackResponse);
        }

        fallbackResponse.value = stEthBtcValue;
        fallbackResponse.timestamp = stEthBtcTimestamp;
        fallbackResponse.success = true;
        fallbackResponse.ifRetrieve = true;
        return (fallbackResponse);
    }
}
