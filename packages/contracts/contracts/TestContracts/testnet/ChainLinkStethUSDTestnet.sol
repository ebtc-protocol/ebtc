// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../../Interfaces/IFallbackCaller.sol";
import "../../Dependencies/Ownable.sol";
import "../../Dependencies/CheckContract.sol";
import "../../Dependencies/AuthNoOwner.sol";

/*
 * Chainlink stEth/USD oracle for testnet and development. The usd price can be manually inputed. Backwards compatible with local test environment as it defaults to use
   the manual price.
 */
contract ChainLinkStethUSDTestnet is Ownable, CheckContract, AuthNoOwner {
    // --- variables ---

    int256 private _price = 183738405600; // current price $1_837.38
    uint80 private _roundId = 1;
    uint256 private _startedAt = 1631664000;
    uint256 private _updatedAt = 1631664000;
    uint80 private _answeredInRound = 1;

    constructor(address _authorityAddress) {
        _initializeAuthority(_authorityAddress);
    }

    // --- Dependency setters ---

    function setAddresses(address _authorityAddress) external onlyOwner {
        _initializeAuthority(_authorityAddress);

        renounceOwnership();
    }

    // --- Functions ---uint256

    // View price getter for simplicity in tests
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint256) {
        return (_roundId, _price, _startedAt, _updatedAt, _answeredInRound);
    }

    // View price getter for simplicity in tests
    function latestAnswer() external view returns (int256) {
        return _price;
    }

    // Manual external price setter.
    function setPrice(int256 price) external returns (bool) {
        _price = price;
        _roundId = _roundId + 1;
        _startedAt = block.timestamp;
        _updatedAt = block.timestamp;
        return true;
    }
}
