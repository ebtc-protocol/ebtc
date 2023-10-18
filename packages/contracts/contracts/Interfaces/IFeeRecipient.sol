// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface IFeeRecipient {
    // --- Events --
    event ReceiveFee(address indexed _sender, address indexed _token, uint256 _amount);
    event CollSharesTransferred(address indexed _account, uint256 _amount);

    // --- Functions ---

    function receiveStEthFee(uint256 _ETHFee) external;

    function receiveEbtcFee(uint256 _EBTCFee) external;

    function syncGlobalAccounting() external;
}
