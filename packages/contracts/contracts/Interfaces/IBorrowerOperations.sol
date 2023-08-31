// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

// Common interface for the Cdp Manager.
interface IBorrowerOperations {
    // --- Events ---

    event CdpManagerAddressChanged(address _newCdpManagerAddress);
    event ActivePoolAddressChanged(address _activePoolAddress);
    event CollSurplusPoolAddressChanged(address _collSurplusPoolAddress);
    event PriceFeedAddressChanged(address _newPriceFeedAddress);
    event SortedCdpsAddressChanged(address _sortedCdpsAddress);
    event EBTCTokenAddressChanged(address _ebtcTokenAddress);
    event FeeRecipientAddressChanged(address _feeRecipientAddress);
    event CollateralAddressChanged(address _collTokenAddress);
    event FlashLoanSuccess(address _receiver, address _token, uint _amount, uint _fee);
    event DelegateSet(address _borrower, address _delegate, bool _isDelegate);

    // --- Functions ---

    function openCdp(
        uint _EBTCAmount,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint _collAmount
    ) external returns (bytes32);

    function openCdpFor(
        uint _EBTCAmount,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint _collAmount,
        address _borrower
    ) external returns (bytes32);

    function addColl(
        bytes32 _cdpId,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint _collAmount
    ) external;

    function withdrawColl(
        bytes32 _cdpId,
        uint _amount,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external;

    function withdrawEBTC(
        bytes32 _cdpId,
        uint _amount,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external;

    function repayEBTC(
        bytes32 _cdpId,
        uint _amount,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external;

    function closeCdp(bytes32 _cdpId) external;

    function adjustCdp(
        bytes32 _cdpId,
        uint _collWithdrawal,
        uint _debtChange,
        bool isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external;

    function adjustCdpWithColl(
        bytes32 _cdpId,
        uint _collWithdrawal,
        uint _debtChange,
        bool isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint _collAddAmount
    ) external;

    function claimCollateral() external;

    function feeRecipientAddress() external view returns (address);

    function isDelegate(address _borrower, address _delegate) external view returns (bool);

    function setDelegate(address _delegate, bool _isDelegate) external;
}
