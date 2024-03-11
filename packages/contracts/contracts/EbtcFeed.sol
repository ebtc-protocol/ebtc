// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./Interfaces/IPriceFeed.sol";
import {IPriceFetcher} from "./Interfaces/IOracleCaller.sol";
import "./Dependencies/AuthNoOwner.sol";

/*
 * PriceFeed for mainnet deployment, it connects to two Chainlink's live feeds, ETH:BTC and
 * stETH:ETH, which are used to aggregate the price feed of stETH:BTC in conjuction.
 * It also allows for a fallback oracle to intervene in case that the primary Chainlink oracle fails.
 *
 * The PriceFeed uses Chainlink as primary oracle and allows for an optional fallback source. It contains logic for
 * switching oracles based on oracle failures, timeouts, and conditions for returning to the primary
 * Chainlink oracle. In addition, it contains the mechanism to add or remove the fallback oracle through governance.
 */
contract EbtcFeed is IPriceFeed, AuthNoOwner {
    string public constant NAME = "EbtcFeed";

    // The last good price seen from an oracle by Liquity
    uint256 public lastGoodPrice;

    address public primaryOracle;
    address public secondaryOracle;

    uint256 constant INVALID_PRICE = 0;
    address constant UNSET_ADDRESS = address(0);
    uint256 constant GAS_LIMIT = 2_000_000;

    // --- Events ---

    event PrimaryOracleUpdated(address indexed _oldOracle, address indexed _newOracle);
    event SecondaryOracleUpdated(address indexed _oldOracle, address indexed _newOracle);

    // NOTE: Could still use Status to signal current FSM

    // --- Dependency setters ---

    /// @notice Sets the addresses of the contracts and initializes the system
    constructor(address _authorityAddress, address _primaryOracle, address _secondaryOracle) {
        _initializeAuthority(_authorityAddress);

        uint256 firstPrice = IPriceFetcher(_primaryOracle).fetchPrice();
        require(firstPrice != INVALID_PRICE, "EbtcFeed: Primary Oracle Must Work");

        _storePrice(firstPrice);

        primaryOracle = _primaryOracle;

        // If secondaryOracle is known at deployment let's add it
        if (_secondaryOracle != UNSET_ADDRESS) {
            uint256 secondaryOraclePrice = IPriceFetcher(_secondaryOracle).fetchPrice();

            if (secondaryOraclePrice != INVALID_PRICE) {
                secondaryOracle = _secondaryOracle;
            }
        }
    }

    /// @notice Allows the owner to replace the primary oracle
    ///     The oracle must work (return non-zero value)
    function setPrimaryOracle(address _newPrimary) external requiresAuth {
        uint256 currentPrice = IPriceFetcher(_newPrimary).fetchPrice();
        require(currentPrice != INVALID_PRICE, "EbtcFeed: Primary Oracle Must Work");

        emit PrimaryOracleUpdated(primaryOracle, _newPrimary);
        primaryOracle = _newPrimary;
    }

    /// @notice Allows the owner to replace the secondary oracle
    ///     The oracle must work (return non-zero value), unless removed
    function setSecondaryOracle(address _newSecondary) external requiresAuth {
        // Allow governance to remove the secondary oracle
        if (_newSecondary != UNSET_ADDRESS) {
            uint256 currentPrice = IPriceFetcher(_newSecondary).fetchPrice();
            require(currentPrice != INVALID_PRICE, "EbtcFeed: Secondary Oracle Must Work");
        }

        emit SecondaryOracleUpdated(secondaryOracle, _newSecondary);
        secondaryOracle = _newSecondary;
    }

    /// @notice Fetch the Latest Valid Price
    ///     Assumes the oracle call will return 0 if the data is invalid
    ///     Any non-zero value will be interpreted as valid
    ///     The security checks must be performed by the OracleCallers
    ///
    ///     Logic Breakdown:
    ///
    ///     If primary works, use that and store it as last good price
    ///
    ///     If not, try using secondary, if secondary works, use that and store it as last good price
    ///
    ///     If neither work, use the last good price
    ///
    ///     @dev All calls are done via `tinfoilCall` to allow the maximum resiliency we are able to provide
    ///     Due to this, a OracleCaller has to be written, which will be responsible for calling the real oracle
    ///     this ensures all interfaces are the same and that the logic here is to handle:
    ///     - Functioning Case
    ///     - All types of DOSes by the Oracles
    function fetchPrice() external override returns (uint256) {
        // Tinfoil Call
        uint256 primaryResponse = tinfoilCall(
            primaryOracle,
            abi.encodeCall(IPriceFetcher.fetchPrice, ())
        );

        if (primaryResponse != INVALID_PRICE) {
            _storePrice(primaryResponse);
            return primaryResponse;
        }

        if (secondaryOracle == UNSET_ADDRESS) {
            return lastGoodPrice; // No fallback, just return latest
        }

        // Let's try secondary
        uint256 secondaryResponse = tinfoilCall(
            secondaryOracle,
            abi.encodeCall(IPriceFetcher.fetchPrice, ())
        );

        if (secondaryResponse != INVALID_PRICE) {
            _storePrice(secondaryResponse);
            return secondaryResponse;
        }

        // No valid price, return last
        // NOTE: We could emit something here as this means both oracles are dead
        return lastGoodPrice;
    }

    /// @notice Stores the latest valid price.
    /// @param _currentPrice The price to be stored.
    function _storePrice(uint256 _currentPrice) internal {
        lastGoodPrice = _currentPrice;
        emit LastGoodPriceUpdated(_currentPrice);
    }

    /// @dev Performs a TinfoilCall, with all known protections
    ///     Against:
    ///     GasGriefing (burning all the gas)
    ///     Return and Revert Bombing (sending insane amounts of data to trigger memory expansion)
    ///     Self-Destruction of contract
    ///
    ///     Also attempts to protect against returning incorrect data
    ///    `excessivelySafeCall` is modified to only load data if the length is the expected one
    ///     This would avoid against receiving gibberish data, most often arrays
    function tinfoilCall(address _target, bytes memory _calldata) public returns (uint256) {
        // Cap gas at 2 MLN, we don't care about 1/64 cause we expect oracles to consume way less than 200k gas
        uint256 gasLeft = gasleft();
        uint256 cappedGas = gasLeft > GAS_LIMIT ? GAS_LIMIT : gasLeft;

        // NOTE: We could also just check for contract existence here to avoid more issues later

        (bool success, bytes memory res) = excessivelySafeCall(_target, cappedGas, 0, 32, _calldata);

        // Check of success and length allows to ignore checking for contract existence
        //  since non-existent contract cannot return value
        if (success && res.length == 32) {
            // Parse return value as uint256
            return abi.decode(res, (uint256));
        }

        return INVALID_PRICE;
    }

    /// @dev MODIFIED excessivelySafeCall to perform generic calls without getting gas bombed
    ///     Modified to only load the response if it has the intended length
    /// @custom:credits to: https://github.com/nomad-xyz/ExcessivelySafeCall/blob/main/src/ExcessivelySafeCall.sol
    function excessivelySafeCall(
        address _target,
        uint256 _gas,
        uint256 _value,
        uint16 _expectedLength,
        bytes memory _calldata
    ) internal returns (bool, bytes memory) {
        // set up for assembly call
        uint256 _receivedLength; // Length of data we receive
        bool _success;
        bytes memory _returnData = new bytes(_expectedLength);
        // dispatch message to recipient
        // by assembly calling "handle" function
        // we call via assembly to avoid memcopying a very large returndata
        // returned by a malicious contract
        assembly {
            _success := call(
                _gas, // gas
                _target, // recipient
                _value, // ether value
                add(_calldata, 0x20), // inloc
                mload(_calldata), // inlen
                0, // outloc
                0 // outlen
            )
            // limit our copy to 256 bytes
            _receivedLength := returndatasize()
            // NOTE: Read the data only if it's the expected length, else it must be some weird stuff
            if eq(_receivedLength, _expectedLength) {
                // Store the length of the copied bytes
                mstore(_returnData, _receivedLength)
                // copy the bytes from returndata[0:_receivedLength]
                returndatacopy(add(_returnData, 0x20), 0, _receivedLength)
            }
        }
        return (_success, _returnData);
    }
}
