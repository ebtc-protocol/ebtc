// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IPriceFetcher} from "./Interfaces/IOracleCaller.sol";
import {IChronicle} from "./Interfaces/IChronicle.sol";

/// @notice Chronicle oracle adapter for EbtcFeed
/// @notice https://etherscan.io/address/0x02238bb0085395ae52cd4755456891fc2fd5934d
contract ChronicleAdapter is IPriceFetcher {
    uint256 public constant MAX_STALENESS = 24 hours;
    uint256 public constant ADAPTER_PRECISION = 1e18;

    address public immutable BTC_STETH_FEED;
    uint256 public immutable FEED_PRECISION;

    constructor(address _btcStEthFeed) {
        BTC_STETH_FEED = _btcStEthFeed;

        uint256 feedDecimals = IChronicle(BTC_STETH_FEED).decimals();
        require(feedDecimals > 0 && feedDecimals <= 18);

        FEED_PRECISION = 10 ** feedDecimals;
    }

    function fetchPrice() external returns (uint256) {
        (uint256 price, uint256 age) = IChronicle(BTC_STETH_FEED).readWithAge();
        uint256 staleness = block.timestamp - age;
        if (staleness > MAX_STALENESS) revert("ChronicleAdapter: stale price");

        return (price * ADAPTER_PRECISION) / FEED_PRECISION;
    }
}
