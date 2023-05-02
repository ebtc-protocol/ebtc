// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../../Interfaces/IPriceFeed.sol";
import "../../Interfaces/ITellorCaller.sol";
import "./../../Dependencies/Ownable.sol";
import "./../../Dependencies/CheckContract.sol";
import "./../../Dependencies/AuthNoOwner.sol";

/*
 * PriceFeed placeholder for testnet and development. The price can be manually input or fetched from
   Tellor's TestNet implementation. Backwards compatible with local test environment as it defaults to use
   the manual price.
 */
contract PriceFeedTestnet is IPriceFeed, Ownable, CheckContract, AuthNoOwner {
    // --- Constants ---

    uint256 public constant tellorQueryBufferSeconds = 901;
    bytes32 public constant STETHBTC_TELLOR_QUERY_ID =
        0x4a5d321c06b63cd85798f884f7d5a1d79d27c6c65756feda15e06742bd161e69; // keccak256(abi.encode("SpotPrice", abi.encode("steth", "btc")))

    // -- Permissioned Function Signatures --
    bytes4 private constant SET_TELLOR_CALLER_SIG =
        bytes4(keccak256(bytes("setTellorCaller(address)")));

    // --- variables ---

    uint256 private _price = 7428 * 1e13; // stETH/BTC price == ~15.8118 ETH per BTC
    bool public _useTellor;
    ITellorCaller public tellorCaller; // Wrapper contract that calls the Tellor system

    // --- Dependency setters ---

    function setAddresses(
        address _priceAggregatorAddress, // Not used but kept for compatibility with deployment script
        address _tellorCallerAddress,
        address _authorityAddress
    ) external onlyOwner {
        checkContract(_tellorCallerAddress);

        tellorCaller = ITellorCaller(_tellorCallerAddress);

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

    function setTellorCaller(address _tellorCaller) external {
        require(
            isAuthorized(msg.sender, SET_TELLOR_CALLER_SIG),
            "PriceFeed: sender not authorized for setTellorCaller(address)"
        );
        tellorCaller = ITellorCaller(_tellorCaller);
        emit TellorCallerChanged(_tellorCaller);
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
        tellorResponse.retrieved = true;
        return (tellorResponse);
    }
}
