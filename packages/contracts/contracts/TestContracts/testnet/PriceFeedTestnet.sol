// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "../../Interfaces/IPriceFeed.sol";
import "../../Interfaces/ITellorCaller.sol";

/*
 * PriceFeed placeholder for testnet and development. The price is simply set manually and saved in a state
 * variable. The contract does not connect to a live Chainlink price feed.
 */
contract PriceFeedTestnet is IPriceFeed {
    // ETH / BTC price == ~15.8118 ETH per BTC
    uint256 private _price = 6324 * 1e13;
    bool public _useTellor;

    bytes32 public constant STETHBTC_TELLOR_QUERY_ID =
        0x4a5d321c06b63cd85798f884f7d5a1d79d27c6c65756feda15e06742bd161e69; // keccak256(abi.encode("SpotPrice", abi.encode("steth", "btc")))

    // --- Functions ---

    // View price getter for simplicity in tests
    function getPrice() external view returns (uint256) {
        return _price;
    }

    function fetchPrice() external override returns (uint256) {
        // Fire an event just like the mainnet version would.
        // This lets the subgraph rely on events to get the latest price even when developing locally.
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
        _useTellor = !_userTellor;
        return _userTellor;
    }
}
