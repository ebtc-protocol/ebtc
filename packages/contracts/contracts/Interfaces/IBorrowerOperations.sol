// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

// Common interface for the Cdp Manager.
interface IBorrowerOperations {
    // --- Events ---

    event CdpManagerAddressChanged(address _newCdpManagerAddress);
    event ActivePoolAddressChanged(address _activePoolAddress);
    event DefaultPoolAddressChanged(address _defaultPoolAddress);
    event GasPoolAddressChanged(address _gasPoolAddress);
    event CollSurplusPoolAddressChanged(address _collSurplusPoolAddress);
    event PriceFeedAddressChanged(address _newPriceFeedAddress);
    event SortedCdpsAddressChanged(address _sortedCdpsAddress);
    event EBTCTokenAddressChanged(address _ebtcTokenAddress);
    event LQTYStakingAddressChanged(address _lqtyStakingAddress);

    event CdpCreated(bytes32 indexed _cdpId, address indexed _borrower, uint arrayIndex);
    event CdpUpdated(
        bytes32 indexed _cdpId,
        address indexed _borrower,
        uint _debt,
        uint _coll,
        uint stake,
        uint8 operation
    );
    event EBTCBorrowingFeePaid(bytes32 indexed _cdpId, uint _EBTCFee);

    // --- Functions ---

    function setAddresses(
        address _cdpManagerAddress,
        address _activePoolAddress,
        address _defaultPoolAddress,
        address _gasPoolAddress,
        address _collSurplusPoolAddress,
        address _priceFeedAddress,
        address _btcPriceFeedAddress,
        address _sortedCdpsAddress,
        address _ebtcTokenAddress,
        address _lqtyStakingAddress
    ) external;

    function openCdp(
        uint _maxFee,
        uint _EBTCAmount,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external payable;

    function addColl(bytes32 _cdpId, bytes32 _upperHint, bytes32 _lowerHint) external payable;

    function withdrawColl(
        bytes32 _cdpId,
        uint _amount,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external;

    function withdrawEBTC(
        bytes32 _cdpId,
        uint _maxFee,
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
        uint _maxFee,
        uint _collWithdrawal,
        uint _debtChange,
        bool isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external payable;

    function claimCollateral() external;

    function getCompositeDebt(uint _debt) external pure returns (uint);
}
