// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface IGasPool {
    // --- Events ---
    event BorrowerOperationsAddressChanged(address _newBorrowerOperationsAddress);
    event CdpManagerAddressChanged(address _newCdpManagerAddress);
    event GasPoolStEthBalanceUpdated(uint _stEth);
    event CollateralAddressChanged(address _collTokenAddress);
    event CollateralSent(address _to, uint _amount);

    // --- Functions ---
    function getStEthColl() external view returns (uint);

    function sendStEthColl(address _account, uint _amount) external;

    function receiveColl(uint _value) external;
}
