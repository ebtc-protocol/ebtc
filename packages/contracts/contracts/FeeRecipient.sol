// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./Dependencies/Ownable.sol";
import "./Dependencies/AuthNoOwner.sol";
import "./Dependencies/IERC20.sol";
import "./Dependencies/SafeERC20.sol";

/// @notice Minimal fee recipient
/// @notice Tokens can be swept to owner address by authorized user
contract FeeRecipient is Ownable, AuthNoOwner {
    using SafeERC20 for IERC20;

    event SweepTokenSuccess(address indexed _token, uint256 _amount, address indexed _recipient);

    string public constant NAME = "FeeRecipient";

    /// @dev Contract constructor that sets the owner and authority of the contract.
    /// @param _ownerAddress Address of the contract owner.
    /// @param _authorityAddress Address of the authority.
    constructor(address _ownerAddress, address _authorityAddress) {
        _transferOwnership(_ownerAddress);
        _initializeAuthority(_authorityAddress);
    }

    // === Governed Functions === //

    /// @dev Function to move unintended dust that are not protected
    /// @notice moves given amount of given token (collateral is NOT allowed)
    /// @notice because recipient are fixed, this function is safe to be called by anyone
    function sweepToken(address token, uint256 amount) public requiresAuth {
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(amount <= balance, "FeeRecipient: Attempt to sweep more than balance");

        address _owner = owner();
        IERC20(token).safeTransfer(_owner, amount);

        emit SweepTokenSuccess(token, amount, _owner);
    }
}
