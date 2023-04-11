// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "../Interfaces/IPriceFeed.sol";
import "../Interfaces/ITellorCaller.sol";
import "../Dependencies/Authv06.sol";


/*
 * PriceFeed placeholder for testnet and development. The price is simply set manually and saved in a state
 * variable. The contract does not connect to a live Chainlink price feed.
 */
contract PriceFeedTestnet is IPriceFeed, Auth {
    // ETH / BTC price == ~13.4517 ETH per BTC
    uint256 private _price = 7428 * 1e13;

    // -- Permissioned Function Signatures --
    bytes4 private constant SET_TELLOR_CALLER_SIG = bytes4(keccak256(bytes("setTellorCaller(address)")));

    ITellorCaller public tellorCaller; 

    event TellorCallerChanged(address _tellorCaller);

    function setAddresses(address _authority) public {
        // Set the contract's authority to the provided address
        _initializeAuthority(_authority);
    }

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

    function setTellorCaller(address _tellorCaller) external {
        require(isAuthorized(msg.sender, SET_TELLOR_CALLER_SIG), "PriceFeed: sender not authorized for setTellorCaller(address)");
        tellorCaller = ITellorCaller(_tellorCaller);
        emit TellorCallerChanged(_tellorCaller);
    }
}
