// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "./IPool.sol";

interface IDefaultPool is IPool {
    // --- Events ---
    event CdpManagerAddressChanged(address _newCdpManagerAddress);
    event DefaultPoolEBTCDebtUpdated(uint _EBTCDebt);
    event DefaultPoolETHBalanceUpdated(uint _ETH);
    event CollateralAddressChanged(address _collTokenAddress);

    // --- Functions ---
    function sendETHToActivePool(uint _amount) external;

    function receiveColl(uint _value) external;
}
