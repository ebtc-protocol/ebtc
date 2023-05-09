// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../Interfaces/IERC3156FlashLender.sol";
import "../Interfaces/IWETH.sol";
import "./AuthNoOwner.sol";

abstract contract ERC3156FlashLender is IERC3156FlashLender, AuthNoOwner {
    // TODO: Fix / Finalize
    uint256 public constant MAX_BPS = 10_000;

    uint256 public feeBps = 50; // 50 BPS
    uint256 public maxFeeBps = MAX_BPS; // 1000 BPS

    bytes32 public constant FLASH_SUCCESS_VALUE = keccak256("ERC3156FlashBorrower.onFlashLoan");

    bytes4 internal constant SET_FEE_BPS_SIG = bytes4(keccak256(bytes("setFeeBps(uint256)")));
    bytes4 internal constant SET_MAX_FEE_BPS_SIG = bytes4(keccak256(bytes("setMaxFeeBps(uint256)")));

    function setFeeBps(uint _newFee) external requiresAuth {
        require(_newFee <= maxFeeBps, "ERC3156FlashLender: _newFee should <= maxFeeBps");

        // set new flash fee
        uint _oldFee = feeBps;
        feeBps = _newFee;
        emit FlashFeeSet(msg.sender, _oldFee, _newFee);
    }

    function setMaxFeeBps(uint _newMaxFlashFee) external requiresAuth {
        require(_newMaxFlashFee <= MAX_BPS, "ERC3156FlashLender: _newMaxFlashFee should <= 10000");

        // set new max flash fee
        uint _oldMaxFlashFee = maxFeeBps;
        maxFeeBps = _newMaxFlashFee;
        emit MaxFlashFeeSet(msg.sender, _oldMaxFlashFee, _newMaxFlashFee);
    }
}
