// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.11;

import {IERC3156FlashBorrower} from "../../contracts/Interfaces/IERC3156FlashBorrower.sol";
import {IERC20} from "../../contracts/Dependencies/IERC20.sol";

// TODO: CODE THESE

/*
 * Unit Tests for Flashloans
 */

// Does Nothing
contract UselessFlashReceiver is IERC3156FlashBorrower {
    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external override returns (bytes32) {
      return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}
contract eBTCFlashReceiver is IERC3156FlashBorrower {
    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external override returns (bytes32) {
      
      // Approve fee
      IERC20(token).approve(msg.sender, fee);

      // Amount is burned directly
  

      return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}

contract WETHFlashReceiver is IERC3156FlashBorrower {
    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external override returns (bytes32) {

      // Set allowance to caller to repay
      IERC20(token).approve(msg.sender, amount + fee);

      return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}