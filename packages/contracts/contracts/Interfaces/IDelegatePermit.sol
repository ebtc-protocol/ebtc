// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface IDelegatePermit {
    enum DelegateStatus {
        None,
        OneTime,
        Persistent
    }

    event DelegateStatusSet(address _borrower, address _delegate, DelegateStatus _status);

    function getDelegateStatus(
        address _borrower,
        address _delegate
    ) external view returns (DelegateStatus);

    function setDelegateStatus(address _delegate, DelegateStatus _status) external;

    function renounceDelegation(address _borrower) external;

    function permitDelegate(
        address _borrower,
        address _delegate,
        DelegateStatus _status,
        uint _deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function nonces(address owner) external view returns (uint256);

    function version() external view returns (string memory);

    function permitTypeHash() external view returns (bytes32);

    function domainSeparator() external view returns (bytes32);
}
