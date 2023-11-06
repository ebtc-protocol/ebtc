// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Constants } from "./Constants.sol";

library Deployments {
    uint256 internal constant CHAIN_ID = Constants.CHAIN_ID_MAINNET;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant stETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address internal constant wstETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
}
