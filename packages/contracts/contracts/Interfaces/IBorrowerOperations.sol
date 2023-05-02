// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

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
    event FeeRecipientAddressChanged(address _feeRecipientAddress);
    event CollateralAddressChanged(address _collTokenAddress);

    event CdpCreated(
        bytes32 indexed _cdpId,
        address indexed _borrower,
        address indexed _creator,
        uint arrayIndex
    );
    event CdpUpdated(
        bytes32 indexed _cdpId,
        address indexed _borrower,
        uint _oldDebt,
        uint _oldColl,
        uint _debt,
        uint _coll,
        uint _stake,
        BorrowerOperation _operation
    );

    enum BorrowerOperation {
        openCdp,
        closeCdp,
        adjustCdp
    }

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
    
    function closeCdpFor(bytes32 _cdpId, address _forwardedCaller) external;

    function adjustCdpFor(
        bytes32 _cdpId,
        uint256 _collWithdrawal,
        uint256 _EBTCChange,
        bool _isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _collAddAmount,
        address _forwardedCaller
    ) external;


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

    function getCompositeDebt(uint _debt) external pure returns (uint);
}
