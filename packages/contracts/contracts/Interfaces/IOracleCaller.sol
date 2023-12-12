// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./IPool.sol";

interface IOracleCaller {
    function getLatestPrice() external view returns (uint256);
}

interface IPriceFetcher {
    function fetchPrice() external returns (uint256);
}
