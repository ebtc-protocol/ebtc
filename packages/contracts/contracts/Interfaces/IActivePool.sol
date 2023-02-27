// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "./IPool.sol";

interface IActivePool is IPool {
    // --- Events ---
    event BorrowerOperationsAddressChanged(address _newBorrowerOperationsAddress);
    event CdpManagerAddressChanged(address _newCdpManagerAddress);
    event ActivePoolEBTCDebtUpdated(uint _EBTCDebt);
    event ActivePoolETHBalanceUpdated(uint _ETH);
    event CollateralAddressChanged(address _collTokenAddress);

    // --- Functions ---
    function sendETH(address _account, uint _amount) external;

    function receiveColl(uint _value) external;
}
