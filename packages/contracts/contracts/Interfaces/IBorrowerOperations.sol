// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

// Common interface for the Trove Manager.
interface IBorrowerOperations {

    // --- Events ---

    event TroveManagerAddressChanged(address _newTroveManagerAddress);
    event ActivePoolAddressChanged(address _activePoolAddress);
    event DefaultPoolAddressChanged(address _defaultPoolAddress);
    event StabilityPoolAddressChanged(address _stabilityPoolAddress);
    event GasPoolAddressChanged(address _gasPoolAddress);
    event CollSurplusPoolAddressChanged(address _collSurplusPoolAddress);
    event PriceFeedAddressChanged(address  _newPriceFeedAddress);
    event SortedTrovesAddressChanged(address _sortedTrovesAddress);
    event EBTCTokenAddressChanged(address _lusdTokenAddress);
    event LQTYStakingAddressChanged(address _lqtyStakingAddress);

    event TroveCreated(bytes32 indexed _troveId, address indexed _borrower, uint arrayIndex);
    event TroveUpdated(bytes32 indexed _troveId, address indexed _borrower, uint _debt, uint _coll, uint stake, uint8 operation);
    event EBTCBorrowingFeePaid(bytes32 indexed _troveId, uint _EBTCFee);

    // --- Functions ---

    function setAddresses(
        address _troveManagerAddress,
        address _activePoolAddress,
        address _defaultPoolAddress,
        address _stabilityPoolAddress,
        address _gasPoolAddress,
        address _collSurplusPoolAddress,
        address _priceFeedAddress,
        address _sortedTrovesAddress,
        address _lusdTokenAddress,
        address _lqtyStakingAddress
    ) external;

    function openTrove(uint _maxFee, uint _EBTCAmount, bytes32 _upperHint, bytes32 _lowerHint) external payable;

    function addColl(bytes32 _troveId, bytes32 _upperHint, bytes32 _lowerHint) external payable;

    function moveETHGainToTrove(bytes32 _troveId, bytes32 _upperHint, bytes32 _lowerHint) external payable;

    function withdrawColl(bytes32 _troveId, uint _amount, bytes32 _upperHint, bytes32 _lowerHint) external;

    function withdrawEBTC(bytes32 _troveId, uint _maxFee, uint _amount, bytes32 _upperHint, bytes32 _lowerHint) external;

    function repayEBTC(bytes32 _troveId, uint _amount, bytes32 _upperHint, bytes32 _lowerHint) external;

    function closeTrove(bytes32 _troveId) external;

    function adjustTrove(bytes32 _troveId, uint _maxFee, uint _collWithdrawal, uint _debtChange, bool isDebtIncrease, bytes32 _upperHint, bytes32 _lowerHint) external payable;

    function claimCollateral() external;

    function getCompositeDebt(uint _debt) external pure returns (uint);
}
