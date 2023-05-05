// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../Interfaces/IERC3156FlashLender.sol";
import "../Interfaces/IWETH.sol";
import "./AuthNoOwner.sol";

abstract contract ERC3156FlashLender is IERC3156FlashLender, AuthNoOwner {
    // TODO: Fix / Finalize
    address public constant FEE_RECIPIENT = address(1);
    uint256 public FEE_AMT = 50; // 50 BPS
    uint256 public constant MAX_BPS = 10_000;

    bytes32 public constant FLASH_SUCCESS_VALUE = keccak256("ERC3156FlashBorrower.onFlashLoan");

    bytes4 private constant FUNC_SIG_FLASH_FEE = bytes4(keccak256(bytes("setFlashFee(uint256)")));

    event FlashFeeSet(address _setter, uint _oldFee, uint _newFee);

    function setFlashFee(uint _newFee) external {
        require(
            isAuthorized(msg.sender, FUNC_SIG_FLASH_FEE),
            "ERC3156FlashLender: sender not authorized for setFlashFee(uint256)"
        );

        require(_newFee < MAX_BPS, "ERC3156FlashLender: _newFee should < 10000");

        // set new flash fee
        uint _oldFee = FEE_AMT;
        FEE_AMT = _newFee;
        emit FlashFeeSet(msg.sender, FEE_AMT, _newFee);
    }
}
