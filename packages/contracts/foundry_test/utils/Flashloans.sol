// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {IERC3156FlashBorrower} from "../../contracts/Interfaces/IERC3156FlashBorrower.sol";
import {ICdpManagerData} from "../../contracts/Interfaces/ICdpManagerData.sol";
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
    ) external pure override returns (bytes32) {
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}

// Causes Fee Split to be distributed, does nothing else
contract FeeSplitClaimFlashReceiver is IERC3156FlashBorrower {
    ICdpManagerData cdpManager;

    constructor(address cdp) {
        cdpManager = ICdpManagerData(cdp);
    }

    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external override returns (bytes32) {
        // Move state (Causes CollShares to change downwads)
        cdpManager.syncGlobalAccountingAndGracePeriod();

        // Approve to repay (Should ensure this works)
        IERC20(token).approve(msg.sender, amount + fee);

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
        // Approve amount and fee
        IERC20(token).approve(msg.sender, amount + fee);

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}

contract STETHFlashReceiver is IERC3156FlashBorrower {
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

contract FlashLoanSpecReceiver is IERC3156FlashBorrower {
    // TODO: Write partial functions to verify those statements

    /// @notice Sets of flags to test internal state from the test
    ///   Ultimately a basic way to prove that things have happened, without creating overly complex code
    // 1)
    bool public called;
    // 2)
    uint256 public balanceReceived;

    address public caller;

    // Cached received data
    address public receivedToken;
    uint256 public receivedAmount;
    bytes public receivedData;

    uint256 public receivedFee;

    /// @dev Set the balance, so we can check delta for 2)
    function setBalanceAlready(address token) external {
        balanceReceived = IERC20(token).balanceOf(address(this));
    }

    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external override returns (bytes32) {
        // TODO: Create custom receiver, that reverts based on the checks below
        // Ultimately not reverting means the spec is follow based on the MUSTs

        // TODO: Add custom spec receiver
        // 1) The flashLoan function MUST include a callback to the onFlashLoan function in a IERC3156FlashBorrower contract.
        called = true;

        // 2) The flashLoan function MUST transfer amount of token to receiver before the callback to the receiver.
        balanceReceived = IERC20(token).balanceOf(address(this)) - balanceReceived;

        // The flashLoan function MUST include msg.sender as the initiator to onFlashLoan.
        caller = initiator;

        // The flashLoan function MUST NOT modify the token, amount and data parameter received, and MUST pass them on to onFlashLoan.
        receivedToken = token;
        receivedAmount = amount;
        receivedData = data;

        // The flashLoan function MUST include a fee argument to onFlashLoan with the fee to pay for the loan on top of the principal, ensuring that fee == flashFee(token, amount).
        receivedFee = fee;

        // TODO: Because of this we have to transfer both amounts and then burn them vs burning direcrly
        IERC20(token).approve(msg.sender, amount + fee);
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}

/// @dev Return the wrong value to test revert case
contract FlashLoanWrongReturn is IERC3156FlashBorrower {
    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external override returns (bytes32) {
        IERC20(token).approve(msg.sender, fee);
        return keccak256("THE WRONG VALUE");
    }
}
