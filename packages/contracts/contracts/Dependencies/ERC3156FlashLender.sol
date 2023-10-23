// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../Interfaces/IERC3156FlashLender.sol";
import "../Interfaces/IWETH.sol";

abstract contract ERC3156FlashLender is IERC3156FlashLender {
    uint256 public constant MAX_BPS = 10_000;
    uint256 public constant MAX_FEE_BPS = 1_000; // 10%
    bytes32 public constant FLASH_SUCCESS_VALUE = keccak256("ERC3156FlashBorrower.onFlashLoan");

    // Functions to modify these variables must be included in impelemnting contracts if desired
    uint16 public feeBps = 3; // may be subject to future adjustments through protocol governance
    bool public flashLoansPaused;
}
