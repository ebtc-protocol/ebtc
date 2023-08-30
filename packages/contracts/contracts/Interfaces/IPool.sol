// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

// Common interface for the Pools.
interface IPool {
    // --- Events ---

    event ETHBalanceUpdated(uint _newBalance);
    event EBTCBalanceUpdated(uint _newBalance);
    event ActivePoolAddressChanged(address _newActivePoolAddress);
    event CollateralSent(address _to, uint _amount);

    // --- Functions ---

    function getSystemCollShares() external view returns (uint);

    function getSystemDebt() external view returns (uint);

    function increaseSystemDebt(uint _amount) external;

    function decreaseSystemDebt(uint _amount) external;
}
