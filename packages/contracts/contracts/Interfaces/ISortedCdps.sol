// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

// Common interface for the SortedCdps Doubly Linked List.
interface ISortedCdps {
    // --- Events ---

    event NodeAdded(bytes32 _id, uint _NICR);
    event NodeRemoved(bytes32 _id);

    // --- Functions ---

    function remove(bytes32 _id) external;

    function batchRemove(bytes32[] memory _ids) external;

    function reInsert(bytes32 _id, uint256 _newICR, bytes32 _prevId, bytes32 _nextId) external;

    function contains(bytes32 _id) external view returns (bool);

    function isFull() external view returns (bool);

    function isEmpty() external view returns (bool);

    function getSize() external view returns (uint256);

    function getMaxSize() external view returns (uint256);

    function getFirst() external view returns (bytes32);

    function getLast() external view returns (bytes32);

    function getNext(bytes32 _id) external view returns (bytes32);

    function getPrev(bytes32 _id) external view returns (bytes32);

    function validInsertPosition(
        uint256 _ICR,
        bytes32 _prevId,
        bytes32 _nextId
    ) external view returns (bool);

    function findInsertPosition(
        uint256 _ICR,
        bytes32 _prevId,
        bytes32 _nextId
    ) external view returns (bytes32, bytes32);

    function insert(
        address owner,
        uint256 _ICR,
        bytes32 _prevId,
        bytes32 _nextId
    ) external returns (bytes32);

    function getOwnerAddress(bytes32 _id) external pure returns (address);

    function nonExistId() external view returns (bytes32);

    function cdpCountOf(address owner) external view returns (uint256);

    function getCdpCountOf(
        address owner,
        bytes32 startNodeId,
        uint maxNodes
    ) external view returns (uint256, bytes32);

    function getCdpsOf(address owner) external view returns (bytes32[] memory);

    function getAllCdpsOf(
        address owner,
        bytes32 startNodeId,
        uint maxNodes
    ) external view returns (bytes32[] memory, uint256, bytes32);

    function cdpOfOwnerByIndex(address owner, uint256 index) external view returns (bytes32);

    function cdpOfOwnerByIdx(
        address owner,
        uint256 index,
        bytes32 startNodeId,
        uint maxNodes
    ) external view returns (bytes32, bool);

    function toCdpId(
        address owner,
        uint256 blockHeight,
        uint256 nonce
    ) external pure returns (bytes32);

    function nextCdpNonce() external view returns (uint256);
}
