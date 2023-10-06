// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;
import "../Interfaces/IPermitNonce.sol";

/**
 * @dev This abstract contract provides a mapping from address to nonce (uint256) used for permit signature
 */
contract PermitNonce is IPermitNonce {
    mapping(address => uint256) internal _nonces;

    /// @dev Increase current nonce for msg.sender by one.
    /// @notice This function could be used to invalidate any signed permit out there
    function increasePermitNonce() external returns (uint256) {
        return ++_nonces[msg.sender];
    }

    /// @dev Return current nonce for msg.sender fOR EIP-2612 compatibility
    function nonces(address owner) external view virtual returns (uint256) {
        return _nonces[owner];
    }
}
