// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

interface IFeeManager {
    // --- Functions ---

    function setAddresses
    (
        address _lusdTokenAddress,
        address _troveManagerAddress, 
        address _feeRecipient
    )  external;

    function onOpenTrove(bytes32 _troveId, address _troveOwner, uint _amount, bytes32 _referralId) external;
    function onAdjustTrove(bytes32 _troveId) external;
    function onMint(bytes32 _troveId, address _troveOwner, uint _amount, bytes32 _referralId) external;

    function collectFees() external;
}