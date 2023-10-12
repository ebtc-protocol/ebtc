// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface IPositionManagers {
    enum PositionManagerApproval {
        None,
        OneTime,
        Persistent
    }

    event PositionManagerApprovalSet(
        address indexed _borrower,
        address indexed _positionManager,
        PositionManagerApproval _approval
    );

    function getPositionManagerApproval(
        address _borrower,
        address _positionManager
    ) external view returns (PositionManagerApproval);

    function setPositionManagerApproval(
        address _positionManager,
        PositionManagerApproval _approval
    ) external;

    function revokePositionManagerApproval(address _positionManager) external;

    function renouncePositionManagerApproval(address _borrower) external;

    function permitPositionManagerApproval(
        address _borrower,
        address _positionManager,
        PositionManagerApproval _approval,
        uint _deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function version() external view returns (string memory);

    function permitTypeHash() external view returns (bytes32);

    function domainSeparator() external view returns (bytes32);
}
