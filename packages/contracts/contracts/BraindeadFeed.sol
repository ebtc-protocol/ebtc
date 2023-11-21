// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./Interfaces/IPriceFeed.sol";
import "./Interfaces/IOracleCaller.sol";
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
contract BraindeadFeed is IPriceFeed, AuthNoOwner {
    string public constant NAME = "PriceFeed";

    // The last good price seen from an oracle by Liquity
    uint256 public lastGoodPrice;

    address public primaryOracle;
    address public secondaryOracle;

    uint256 INVALID_PRICE = 0;

    // NOTE: Could still use Status to signal current FSM

    // --- Dependency setters ---

    /// @notice Sets the addresses of the contracts and initializes the system
    constructor(
        address _primaryOracle,
        address _secondaryOracle
    ) {
        uint256 firstPrice = IOracleCaller(_primaryOracle).getLatestPrice();
        require(firstPrice != 0, "Primary Oracle Must Work");

        _storePrice(firstPrice);

        primaryOracle = _primaryOracle;

        // If secondaryOracle is known at deployment let's add it
        if(_secondaryOracle != address(0)) {
            uint256 secondaryOraclePrice = IOracleCaller(_secondaryOracle).getLatestPrice();

            if(secondaryOraclePrice != 0) {
                secondaryOracle = _secondaryOracle;
            }
        }
    }

    function setPrimaryOracle(address _newPrimary) external requiresAuth {
        uint256 currentPrice = IOracleCaller(_newPrimary).getLatestPrice();
        require(currentPrice != 0, "Primary Oracle Must Work");

        primaryOracle = _newPrimary;

    }

    function setSecondaryOracle(address _newSecondary) external requiresAuth {
        uint256 currentPrice = IOracleCaller(_newSecondary).getLatestPrice();
        require(currentPrice != 0, "Primary Oracle Must Work");

        secondaryOracle = _newSecondary;
    }


    function fetchPrice() external override returns (uint256) {
        // Tinfoil Call
        uint256 primaryResponse = tinfoilCall(primaryOracle, abi.encodeCall(IOracleCaller.getLatestPrice, ()));

        if(primaryResponse != INVALID_PRICE) {
            _storePrice(primaryResponse);
            return primaryResponse;
        }

        if(secondaryOracle == address(0)){
            return lastGoodPrice; // No fallback, just return latest
        }

        // Let's try secondary
        uint256 secondaryResponse = tinfoilCall(secondaryOracle, abi.encodeCall(IOracleCaller.getLatestPrice, ()));

        if(secondaryResponse != INVALID_PRICE) {
            _storePrice(secondaryResponse);
            return secondaryResponse;
        }

        // No valid price, return last
        // NOTE: We could emit something here as this means both oracles are dead
        return lastGoodPrice;
    }

    // function _getCurrentChainlinkResponse() internal view returns (ChainlinkResponse memory chainlinkResponse) {
    //     // Fetch decimals for both feeds:
    //     uint8 ethBtcDecimals;
    //     uint8 stEthEthDecimals;

    //     try ETH_BTC_CL_FEED.decimals() returns (uint8 decimals) {
    //         // If call to Chainlink succeeds, record the current decimal precision
    //         ethBtcDecimals = decimals;
    //     } catch {
    //         // If call to Chainlink aggregator reverts, return a zero response with success = false
    //         return chainlinkResponse;
    //     }

    //     try STETH_ETH_CL_FEED.decimals() returns (uint8 decimals) {
    //         // If call to Chainlink succeeds, record the current decimal precision
    //         stEthEthDecimals = decimals;
    //     } catch {
    //         // If call to Chainlink aggregator reverts, return a zero response with success = false
    //         return chainlinkResponse;
    //     }

    //     // Try to get latest prices data:
    //     int256 ethBtcAnswer;
    //     int256 stEthEthAnswer;
    //     try ETH_BTC_CL_FEED.latestRoundData() returns (
    //         uint80 roundId,
    //         int256 answer,
    //         uint256,
    //         /* startedAt */
    //         uint256 timestamp,
    //         uint80 /* answeredInRound */
    //     ) {
    //         ethBtcAnswer = answer;
    //         chainlinkResponse.roundEthBtcId = roundId;
    //         chainlinkResponse.timestampEthBtc = timestamp;
    //     } catch {
    //         // If call to Chainlink aggregator reverts, return a zero response with success = false
    //         return chainlinkResponse;
    //     }

    //     try STETH_ETH_CL_FEED.latestRoundData() returns (
    //         uint80 roundId,
    //         int256 answer,
    //         uint256,
    //         /* startedAt */
    //         uint256 timestamp,
    //         uint80 /* answeredInRound */
    //     ) {
    //         stEthEthAnswer = answer;
    //         chainlinkResponse.roundStEthEthId = roundId;
    //         chainlinkResponse.timestampStEthEth = timestamp;
    //     } catch {
    //         // If call to Chainlink aggregator reverts, return a zero response with success = false
    //         return chainlinkResponse;
    //     }

    //     if (
    //         _checkHealthyCLResponse(chainlinkResponse.roundEthBtcId, ethBtcAnswer)
    //             && _checkHealthyCLResponse(chainlinkResponse.roundStEthEthId, stEthEthAnswer)
    //     ) {
    //         chainlinkResponse.answer =
    //             _formatClAggregateAnswer(ethBtcAnswer, stEthEthAnswer, ethBtcDecimals, stEthEthDecimals);
    //     } else {
    //         return chainlinkResponse;
    //     }

    //     chainlinkResponse.success = true;
    // }

    // function _formatClAggregateAnswer(
    //     int256 _ethBtcAnswer,
    //     int256 _stEthEthAnswer,
    //     uint8 _ethBtcDecimals,
    //     uint8 _stEthEthDecimals
    // ) internal view returns (uint256) {
    //     uint256 _decimalDenominator = _stEthEthDecimals > _ethBtcDecimals ? _stEthEthDecimals : _ethBtcDecimals;
    //     uint256 _scaledDecimal = _stEthEthDecimals > _ethBtcDecimals
    //         ? 10 ** (_stEthEthDecimals - _ethBtcDecimals)
    //         : 10 ** (_ethBtcDecimals - _stEthEthDecimals);
    //     return (_scaledDecimal * uint256(_ethBtcAnswer) * uint256(_stEthEthAnswer) * LiquityMath.DECIMAL_PRECISION)
    //         / 10 ** (_decimalDenominator * 2);
    // }

    // function _getCurrentFallbackResponse() internal view returns (FallbackResponse memory fallbackResponse) {
    //     if (address(fallbackCaller) != address(0)) {
    //         try fallbackCaller.getFallbackResponse() returns (uint256 answer, uint256 timestampRetrieved, bool success)
    //         {
    //             fallbackResponse.answer = answer;
    //             fallbackResponse.timestamp = timestampRetrieved;
    //             fallbackResponse.success = success;
    //         } catch {
    //             // If call to Fallback reverts, return a zero response with success = false
    //         }
    //     } // If unset we return a zero response with success = false

    //     // Return is implicit
    // }

    /// @notice Stores the latest valid price.
    /// @param _currentPrice The price to be stored.
    function _storePrice(uint256 _currentPrice) internal {
        lastGoodPrice = _currentPrice;
        emit LastGoodPriceUpdated(_currentPrice);
    }

    // Tinfoil Mode
    // Give up to 2_M gas

    function tinfoilCall(address _target, bytes memory _calldata) public returns (uint256) {
        // Cap gas at 2 MLN, we don't care about 1/64 cause we expect oracles to consume way less than 200k gas
        uint256 cappedGas = gasleft() > 2_000_000 ? 2_000_000 : gasleft();

        (bool success, bytes memory res) = excessivelySafeCall(_target, cappedGas, 0, 32, _calldata);

        if(success) {
            // Parse return value as uint256
            return abi.decode(res, (uint256));
        }

        return INVALID_PRICE;
    }

    /**
     * excessivelySafeCall to perform generic calls without getting gas bombed | useful if you don't care about return value
     */
    // Credits to: https://github.com/nomad-xyz/ExcessivelySafeCall/blob/main/src/ExcessivelySafeCall.sol
    function excessivelySafeCall(
        address _target,
        uint256 _gas,
        uint256 _value,
        uint16 _maxCopy,
        bytes memory _calldata
    ) internal returns (bool, bytes memory) {
        // set up for assembly call
        uint256 _toCopy;
        bool _success;
        bytes memory _returnData = new bytes(_maxCopy);
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
            _toCopy := returndatasize()
            if gt(_toCopy, _maxCopy) {
                _toCopy := _maxCopy
            }
            // Store the length of the copied bytes
            mstore(_returnData, _toCopy)
            // copy the bytes from returndata[0:_toCopy]
            returndatacopy(add(_returnData, 0x20), 0, _toCopy)
        }
        return (_success, _returnData);
    }

}
