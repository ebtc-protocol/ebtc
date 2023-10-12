// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

// Common interface for the Pools.
interface IPool {
    // --- Events ---

    event ETHBalanceUpdated(uint256 _newBalance);
    event EBTCBalanceUpdated(uint256 _newBalance);
    event CollSharesTransferred(address indexed _to, uint256 _amount);

    // --- Functions ---

    function getSystemCollShares() external view returns (uint256);

    function getSystemDebt() external view returns (uint256);

    function increaseSystemDebt(uint256 _amount) external;

    function decreaseSystemDebt(uint256 _amount) external;
}
