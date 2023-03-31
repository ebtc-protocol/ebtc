// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "../../Interfaces/IPriceFeed.sol";
import "../../Interfaces/ITellorCaller.sol";
import "./../../Dependencies/Ownable.sol";
import "./../../Dependencies/CheckContract.sol";

/*
 * PriceFeed placeholder for testnet and development. The price can be manually input or fetched from
   Tellor's TestNet implementation. Backwards compatible with local test environment as it defaults to use
   the manual price.
 */
contract PriceFeedTestnet is IPriceFeed, Ownable, CheckContract {
    // --- Constants ---

    uint256 public constant tellorQueryBufferSeconds = 901;
    bytes32 public constant STETHBTC_TELLOR_QUERY_ID =
        0x4a5d321c06b63cd85798f884f7d5a1d79d27c6c65756feda15e06742bd161e69; // keccak256(abi.encode("SpotPrice", abi.encode("steth", "btc")))

    // --- variables ---

    uint256 private _price = 7428 * 1e13; // stETH/BTC price == ~15.8118 ETH per BTC
    bool public _useTellor;
    ITellorCaller public tellorCaller; // Wrapper contract that calls the Tellor system

    struct TellorResponse {
        bool ifRetrieve;
        uint256 value;
        uint256 timestamp;
        bool success;
    }

    // --- Dependency setters ---

    function setAddresses(
        address _tellorCallerAddress
    ) external onlyOwner {
        checkContract(_tellorCallerAddress);

        tellorCaller = ITellorCaller(_tellorCallerAddress);

        _renounceOwnership();
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
            TellorResponse memory tellorResponse = _getCurrentTellorResponse();
            if (tellorResponse.success) {
                _price = tellorResponse.value;
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

    // --- Oracle response wrapper functions ---
    /*
     * "_getCurrentTellorResponse" fetches stETH/BTC from Tellor, and returns it as a
     * TellorResponse struct.
     */
    function _getCurrentTellorResponse()
        internal
        view
        returns (TellorResponse memory tellorResponse)
    {
        uint stEthBtcValue;
        uint stEthBtcTimestamp;
        bool stEthBtcRetrieved;


        // Attempt to get Tellor's stETH/BTC price
        try
            tellorCaller.getTellorBufferValue(STETHBTC_TELLOR_QUERY_ID, tellorQueryBufferSeconds)
        returns (bool ifRetrieved, uint256 value, uint256 timestampRetrieved) {
            stEthBtcRetrieved = ifRetrieved;
            stEthBtcValue = value;
            stEthBtcTimestamp = timestampRetrieved;
        } catch {
            return (tellorResponse);
        }

        // If the price was not retrieved, return the TellorResponse struct with success = false.
        if (!stEthBtcRetrieved) {
            return (tellorResponse);
        }

        tellorResponse.value = stEthBtcValue;
        tellorResponse.timestamp = stEthBtcTimestamp;
        tellorResponse.success = true;
        tellorResponse.ifRetrieve = true;
        return (tellorResponse);
    }
}
