// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface IPermitNonce {
    // --- Functions ---
    function increasePermitNonce() external returns (uint256);

    function nonces(address owner) external view returns (uint256);
}
