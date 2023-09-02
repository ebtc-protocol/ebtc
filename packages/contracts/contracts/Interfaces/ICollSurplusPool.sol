// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface ICollSurplusPool {
    // --- Events ---

    event BorrowerOperationsAddressChanged(address _newBorrowerOperationsAddress);
    event CdpManagerAddressChanged(address _newCdpManagerAddress);
    event ActivePoolAddressChanged(address _newActivePoolAddress);
    event CollateralAddressChanged(address _collTokenAddress);

    event SurplusCollSharesUpdated(address indexed _account, uint256 _newBalance);
    event CollSharesTransferred(address _to, uint256 _amount);

    event SweepTokenSuccess(address indexed _token, uint256 _amount, address indexed _recipient);

    // --- Contract setters ---

    function getTotalSurplusCollShares() external view returns (uint256);

    function getSurplusCollShares(address _account) external view returns (uint256);

    function increaseSurplusCollShares(address _account, uint256 _amount) external;

    function claimSurplusCollShares(address _account) external;

    function increaseTotalSurplusCollShares(uint256 _value) external;
}
