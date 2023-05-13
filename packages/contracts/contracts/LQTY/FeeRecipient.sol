// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../Dependencies/Ownable.sol";
import "../Dependencies/AuthNoOwner.sol";
import "../Dependencies/IERC20.sol";
import "../Dependencies/SafeERC20.sol";

/**
    @notice Minimal fee recipient
    @notice Tokens can be swept to owner address by authorized user
 */
contract FeeRecipient is Ownable, AuthNoOwner {
    using SafeERC20 for IERC20;
    // --- Data ---
    string public constant NAME = "FeeRecipient";

    constructor(address _ownerAddress, address _authorityAddress) {
        _transferOwnership(_ownerAddress);
        _initializeAuthority(_authorityAddress);
    }

    // === Governed Functions === //

    /// @dev Function to move unintended dust that are not protected
    /// @notice moves given amount of given token (collateral is NOT allowed)
    /// @notice because recipient are fixed, this function is safe to be called by anyone
    function sweepToken(address token, uint amount) public requiresAuth {
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(amount <= balance, "FeeRecipient: Attempt to sweep more than balance");

        IERC20(token).safeTransfer(owner(), amount);
    }
}
