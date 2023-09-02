// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface IFeeRecipient {
    // --- Events --

    event EBTCTokenAddressSet(address _ebtcTokenAddress);
    event CdpManagerAddressSet(address _cdpManager);
    event BorrowerOperationsAddressSet(address _borrowerOperationsAddress);
    event ActivePoolAddressSet(address _activePoolAddress);
    event CollateralAddressSet(address _collTokenAddress);

    event ReceiveFee(address indexed _sender, address indexed _token, uint256 _amount);
    event CollSharesTransferred(address _account, uint256 _amount);

    // --- Functions ---

    function receiveStEthFee(uint256 _ETHFee) external;

    function receiveEbtcFee(uint256 _EBTCFee) external;

    function applyPendingGlobalState() external;
}
