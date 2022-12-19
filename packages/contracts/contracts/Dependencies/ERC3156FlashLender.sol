// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "../Interfaces/IERC3156FlashLender.sol";
import "../Interfaces/IWETH.sol";

abstract contract ERC3156FlashLender is IERC3156FlashLender {
    // TODO: Fix
    address constant internal FEE_RECIPIENT  = address(0);
    uint256 constant internal FEE_AMT  = 50; // 50 BPS
    uint256 constant internal MAX_BPS  = 10_000;
    
    // NOTE: Mainnet WETH
    IWETH public constant WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
}