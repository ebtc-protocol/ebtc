// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./IPriceFeed.sol";

interface IEbtcBase {
    function priceFeed() external view returns (IPriceFeed);
}
