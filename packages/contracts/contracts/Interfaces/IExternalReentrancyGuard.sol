// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface IExternalReentrancyGuard {
    function locked() external virtual returns (uint256);
    function setLocked(uint256 value) external virtual;
}
