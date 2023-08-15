// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface ICollSurplusPool {
    // --- Events ---

    event BorrowerOperationsAddressChanged(address _newBorrowerOperationsAddress);
    event CdpManagerAddressChanged(address _newCdpManagerAddress);
    event ActivePoolAddressChanged(address _newActivePoolAddress);
    event CollateralAddressChanged(address _collTokenAddress);

    event CollBalanceUpdated(address indexed _account, uint _newBalance);
    event CollateralSent(address _to, uint _amount);

    event SweepTokenSuccess(address indexed _token, uint _amount, address indexed _recipient);

    // --- Contract setters ---

    function getSystemCollShares() external view returns (uint);

    function getSurplusCollSharesFor(address _account) external view returns (uint);

    function setSurplusCollSharesFor(address _account, uint _amount) external;

    function claimSurplusCollShares(address _account) external;

    function receiveCollShares(uint _value) external;
}
