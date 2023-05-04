// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../Interfaces/IFallbackCaller.sol";
import "./ITellor.sol";
import "./SafeMath.sol";

/*
 * This contract is a mock that returns hardcoded price
 * Should not be used on mainnet
 */
contract TellorCallerMock is IFallbackCaller {
    using SafeMath for uint256;

    ITellor public tellor;

    constructor(address _tellorMasterAddress) public {
        tellor = ITellor(_tellorMasterAddress);
    }

    // Mock price data
    function getFallbackResponse() external view override returns (uint256, uint256, bool, uint8) {
        return (7428 * 1e13, block.timestamp, true, 18);
    }
}
