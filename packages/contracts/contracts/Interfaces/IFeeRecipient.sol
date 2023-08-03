// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface IFeeRecipient {
    // --- Events --

    event EBTCTokenAddressSet(address _ebtcTokenAddress);
    event CdpManagerAddressSet(address _cdpManager);
    event BorrowerOperationsAddressSet(address _borrowerOperationsAddress);
    event ActivePoolAddressSet(address _activePoolAddress);
    event CollateralAddressSet(address _collTokenAddress);

    event ReceiveFee(address indexed _sender, address indexed _token, uint _amount);
    event CollateralSent(address _account, uint _amount);

    // --- Functions ---

    function receiveStEthFee(uint _ETHFee) external;

    function receiveEbtcFee(uint _EBTCFee) external;

    function applyPendingGlobalState() external;
}
