// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../Interfaces/IERC3156FlashLender.sol";
import "../Interfaces/IWETH.sol";
import "./AuthNoOwner.sol";

abstract contract ERC3156FlashLender is IERC3156FlashLender, AuthNoOwner {
    // TODO: Fix / Finalize
    uint256 public constant MAX_BPS = 10_000;
    uint256 public constant MAX_FEE_BPS = 1_000; // 10%
    bytes32 public constant FLASH_SUCCESS_VALUE = keccak256("ERC3156FlashBorrower.onFlashLoan");

    uint16 public feeBps = 50; // 50 BP
    bool public flashLoansPaused;

    function setFeeBps(uint _newFee) external requiresAuth {
        require(_newFee <= MAX_FEE_BPS, "ERC3156FlashLender: _newFee should <= MAX_FEE_BPS");

        // set new flash fee
        uint _oldFee = feeBps;
        feeBps = uint16(_newFee);
        emit FlashFeeSet(msg.sender, _oldFee, _newFee);
    }

    function setFlashLoansPaused(bool _paused) external requiresAuth {
        flashLoansPaused = _paused;
        emit FlashLoansPaused(msg.sender, _paused);
    }
}
