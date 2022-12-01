// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "../Interfaces/IERC3156FlashLender.sol";

abstract contract ERC3156FlashLender is IERC3156FlashLender {
    address constant internal FEE_RECIPIENT  = address(0);
    uint256 constant internal FEE_AMT  = 50; // 50 BPS
    uint256 constant internal MAX_BPS  = 10_000;
}