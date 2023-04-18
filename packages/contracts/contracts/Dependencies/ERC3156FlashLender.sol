// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../Interfaces/IERC3156FlashLender.sol";
import "../Interfaces/IWETH.sol";

abstract contract ERC3156FlashLender is IERC3156FlashLender {
    // TODO: Fix / Finalize
    address public constant FEE_RECIPIENT = address(1);
    uint256 public constant FEE_AMT = 50; // 50 BPS
    uint256 public constant MAX_BPS = 10_000;

    bytes32 public constant FLASH_SUCCESS_VALUE = keccak256("ERC3156FlashBorrower.onFlashLoan");
}
