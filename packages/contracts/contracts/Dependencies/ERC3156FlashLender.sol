// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../Interfaces/IERC3156FlashLender.sol";
import "../Interfaces/IWETH.sol";
import "./AuthNoOwner.sol";

abstract contract ERC3156FlashLender is IERC3156FlashLender, AuthNoOwner {
    // TODO: Fix / Finalize
    address public constant FEE_RECIPIENT = address(1);
    uint256 public constant MAX_BPS = 10_000;

    uint256 public flashFee = 50; // 50 BPS
    uint256 public maxFlashFee = MAX_BPS; // 1000 BPS

    bytes32 public constant FLASH_SUCCESS_VALUE = keccak256("ERC3156FlashBorrower.onFlashLoan");

    bytes4 internal constant SET_FLASH_FEE_SIG = bytes4(keccak256(bytes("setFlashFee(uint256)")));
    bytes4 internal constant SET_MAX_FLASH_FEE_SIG =
        bytes4(keccak256(bytes("setMaxFlashFee(uint256)")));

    function setFlashFee(uint _newFee) external {
        require(
            isAuthorized(msg.sender, SET_FLASH_FEE_SIG),
            "ERC3156FlashLender: sender not authorized for setFlashFee(uint256)"
        );

        require(_newFee <= maxFlashFee, "ERC3156FlashLender: _newFee should <= maxFlashFee");

        // set new flash fee
        uint _oldFee = flashFee;
        flashFee = _newFee;
        emit FlashFeeSet(msg.sender, _oldFee, _newFee);
    }

    function setMaxFlashFee(uint _newMaxFlashFee) external {
        require(
            isAuthorized(msg.sender, SET_MAX_FLASH_FEE_SIG),
            "ERC3156FlashLender: sender not authorized for setMaxFlashFee(uint256)"
        );

        require(_newMaxFlashFee <= MAX_BPS, "ERC3156FlashLender: _newMaxFlashFee should <= 10000");

        // set new max flash fee
        uint _oldMaxFlashFee = maxFlashFee;
        maxFlashFee = _newMaxFlashFee;
        emit MaxFlashFeeSet(msg.sender, _oldMaxFlashFee, _newMaxFlashFee);
    }
}
