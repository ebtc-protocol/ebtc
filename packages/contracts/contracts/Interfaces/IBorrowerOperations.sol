// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;
import "./IPositionManagers.sol";

// Common interface for the Cdp Manager.
interface IBorrowerOperations is IPositionManagers {
    // --- Events ---

    event FeeRecipientAddressChanged(address indexed _feeRecipientAddress);
    event FlashLoanSuccess(
        address indexed _receiver,
        address indexed _token,
        uint256 _amount,
        uint256 _fee
    );

    // --- Functions ---

    function openCdp(
        uint256 _EBTCAmount,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthBalance
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
        uint256 _stEthBalanceIncrease
    ) external;

    function withdrawColl(
        bytes32 _cdpId,
        uint256 _stEthBalanceDecrease,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external;

    function withdrawDebt(
        bytes32 _cdpId,
        uint256 _amount,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external;

    function repayDebt(
        bytes32 _cdpId,
        uint256 _amount,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external;

    function closeCdp(bytes32 _cdpId) external;

    function adjustCdp(
        bytes32 _cdpId,
        uint256 _stEthBalanceDecrease,
        uint256 _debtChange,
        bool isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external;

    function adjustCdpWithColl(
        bytes32 _cdpId,
        uint256 _stEthBalanceDecrease,
        uint256 _debtChange,
        bool isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthBalanceIncrease
    ) external;

    function claimSurplusCollShares() external;

    function feeRecipientAddress() external view returns (address);
}
