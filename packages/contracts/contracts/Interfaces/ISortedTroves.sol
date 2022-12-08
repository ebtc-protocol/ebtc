// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

// Common interface for the SortedTroves Doubly Linked List.
interface ISortedTroves {

    // --- Events ---
    
    event SortedTrovesAddressChanged(address _sortedDoublyLLAddress);
    event BorrowerOperationsAddressChanged(address _borrowerOperationsAddress);
    event NodeAdded(bytes32 _id, uint _NICR);
    event NodeRemoved(bytes32 _id);

    // --- Functions ---
    
    function setParams(uint256 _size, address _TroveManagerAddress, address _borrowerOperationsAddress) external;

    function insert(address owner, bytes32 _id, uint256 _ICR, bytes32 _prevId, bytes32 _nextId) external;

    function remove(bytes32 _id) external;

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

    function validInsertPosition(uint256 _ICR, bytes32 _prevId, bytes32 _nextId) external view returns (bool);

    function findInsertPosition(uint256 _ICR, bytes32 _prevId, bytes32 _nextId) external view returns (bytes32, bytes32);

    function insert(address owner, uint256 _ICR, bytes32 _prevId, bytes32 _nextId) external returns (bytes32);

    function getOwnerAddress(bytes32 troveId) external pure returns (address);
	
    function existTroveOwners(bytes32 _id) external view returns (address);

    function nonExistId() external view returns (bytes32);

    function troveCountOf(address owner) external view returns (uint256);

    function troveOfOwnerByIndex(address owner, uint256 index) external view returns (bytes32);

    // Mapping from trove owner to list of owned trove IDs
    // mapping(address => mapping(uint256 => bytes32)) public _ownedTroves;
    function _ownedTroves(address, uint256) external view returns (bytes32);

    // Mapping from trove ID to index within owner trove list
    // mapping(bytes32 => uint256) public _ownedTroveIndex;
    function _ownedTroveIndex(bytes32) external view returns (uint256);

    // Mapping from trove owner to its owned troves count
    // mapping(address => uint256) public _ownedCount;
    function _ownedCount(address) external view returns (uint256);
}
