// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./Interfaces/ISortedCdps.sol";
import "./Interfaces/ICdpManager.sol";
import "./Interfaces/IBorrowerOperations.sol";

/*
 * A sorted doubly linked list with nodes sorted in descending order.
 *
 * Nodes map to active Cdps in the system by Id.
 * Nodes are ordered according to their current nominal individual collateral ratio (NICR),
 * which is like the ICR but without the price, i.e., just collateral / debt.
 *
 * The list optionally accepts insert position hints.
 *
 * NICRs are computed dynamically at runtime, and not stored on the Node. This is because NICRs of active Cdps
 * change dynamically as liquidation events occur.
 *
 * The list relies on the fact that liquidation events preserve ordering: a liquidation decreases the NICRs of all active Cdps,
 * but maintains their order. A node inserted based on current NICR will maintain the correct position,
 * relative to it's peers, as rewards accumulate, as long as it's raw collateral and debt have not changed.
 * Thus, Nodes remain sorted by current NICR.
 *
 * Nodes need only be re-inserted upon a CDP operation - when the owner adds or removes collateral or debt
 * to their position.
 *
 * The list is a modification of the following audited SortedDoublyLinkedList:
 * https://github.com/livepeer/protocol/blob/master/contracts/libraries/SortedDoublyLL.sol
 *
 *
 * Changes made in the Liquity implementation:
 *
 * - Keys have been removed from nodes
 *
 * - Ordering checks for insertion are performed by comparing an NICR argument to the current NICR, calculated at runtime.
 *   The list relies on the property that ordering by ICR is maintained as the stETH:BTC price varies.
 *
 * - Public functions with parameters have been made internal to save gas, and given an external wrapper function for external access
 *
 *
 * Changes made in the Ebtc implementation:
 *
 * - Positions are now indexed by Ids, not addresses. Functions to generate Ids are provided.
 *
 * - Added batchRemove functions to optimize redemptions.
 *
 * - Added more O(n) getter functions and pagination-flavor variants, intended for off-chain use.
 */
contract SortedCdps is ISortedCdps {
    string public constant NAME = "SortedCdps";

    address public immutable borrowerOperationsAddress;

    ICdpManager public immutable cdpManager;

    uint256 public immutable maxSize;

    uint256 constant ADDRESS_SHIFT = 96; // 8 * 12; Puts the address at leftmost bytes32 position
    uint256 constant BLOCK_SHIFT = 64; // 8 * 8; Puts the block value after the address

    // Information for a node in the list
    struct Node {
        bytes32 nextId; // Id of next node (smaller NICR) in the list
        bytes32 prevId; // Id of previous node (larger NICR) in the list
    }

    // Information for the list
    struct Data {
        bytes32 head; // Head of the list. Also the node in the list with the largest NICR
        bytes32 tail; // Tail of the list. Also the node in the list with the smallest NICR
        mapping(bytes32 => Node) nodes; // Track the corresponding ids for each node in the list
    }

    uint256 public size; // Current size of the list

    Data public data;

    uint256 public nextCdpNonce;
    bytes32 public constant dummyId =
        0x0000000000000000000000000000000000000000000000000000000000000000;

    /// @notice Constructor
    /// @dev Sets max list size
    /// @param _size Max number of nodes allowed in the list
    /// @param _cdpManagerAddress Address of CdpManager contract
    /// @param _borrowerOperationsAddress Address of BorrowerOperations contract
    constructor(uint256 _size, address _cdpManagerAddress, address _borrowerOperationsAddress) {
        if (_size == 0) {
            _size = type(uint256).max;
        }

        maxSize = _size;

        cdpManager = ICdpManager(_cdpManagerAddress);
        borrowerOperationsAddress = _borrowerOperationsAddress;
    }

    /// @notice Encodes a unique CDP Id from owner, block and nonce
    /// @dev Inspired https://github.com/balancer-labs/balancer-v2-monorepo/blob/18bd5fb5d87b451cc27fbd30b276d1fb2987b529/pkg/vault/contracts/PoolRegistry.sol
    /// @param owner Owner address of the CDP
    /// @param blockHeight Block number when CDP opened
    /// @param nonce Unique nonce for CDP
    /// @return Unique bytes32 CDP Id
    function toCdpId(
        address owner,
        uint256 blockHeight,
        uint256 nonce
    ) public pure returns (bytes32) {
        bytes32 serialized;

        serialized |= bytes32(nonce);
        serialized |= bytes32(blockHeight) << BLOCK_SHIFT; // to accommendate more than 4.2 billion blocks
        serialized |= bytes32(uint256(uint160(owner))) << ADDRESS_SHIFT;

        return serialized;
    }

    /// @notice Get owner address of a given CDP, given CdpId.
    /// @dev The owner address is stored in the first 20 bytes of the CdpId
    /// @param cdpId cdpId of CDP to get owner of
    /// @return owner address of the CDP
    function getOwnerAddress(bytes32 cdpId) public pure override returns (address) {
        uint256 _tmp = uint256(cdpId) >> ADDRESS_SHIFT;
        return address(uint160(_tmp));
    }

    /// @notice Get dummy non-existent CDP Id
    /// @return Dummy non-existent CDP Id
    function nonExistId() public pure override returns (bytes32) {
        return dummyId;
    }

    /// @notice Find a specific CDP for a given owner, indexed by it's place in the linked list relative to other Cdps owned by the same address
    /// @notice Reverts if the index exceeds the number of active Cdps owned by the given owner
    /// @dev Intended for off-chain use, O(n) operation on size of SortedCdps linked list
    /// @param owner address of CDP owner
    /// @param index index of CDP, ordered by position in linked list relative to Cdps of the same owner
    /// @return CDP Id if found
    function cdpOfOwnerByIndex(
        address owner,
        uint256 index
    ) external view override returns (bytes32) {
        (bytes32 _cdpId, ) = _cdpOfOwnerByIndex(owner, index, dummyId, 0);
        return _cdpId;
    }

    /// @dev a pagination-flavor search (from least ICR to biggest ICR) for CDP owned by given owner and specified index (starting at given CDP)
    /// @param owner address of CDP owner
    /// @param index index of CDP, ordered by position in linked list relative to Cdps of the same owner
    /// @param startNodeId the seach traversal will start at this given CDP instead of the tail of the list
    /// @param maxNodes the traversal will go through the list by this given maximum limit of number of Cdps
    /// @return CDP Id if found, else return last seen CDP
    /// @return True if CDP found, false otherwise
    function cdpOfOwnerByIdx(
        address owner,
        uint256 index,
        bytes32 startNodeId,
        uint maxNodes
    ) external view override returns (bytes32, bool) {
        return _cdpOfOwnerByIndex(owner, index, startNodeId, maxNodes);
    }

    /// @notice Get a user CDP by index using pagination
    /// @dev return EITHER the found CDP owned by given owner & index with a true indicator OR
    /// @dev current lastly-visited CDP as the startNode for next pagination with a false indicator
    /// @param owner Owner address to get CDP for
    /// @param index Index of CDP amongst user's Cdps
    /// @param startNodeId Start position CDP Id
    /// @param maxNodes Max number of Cdps to traverse
    /// @return cdpId The CDP Id if found, otherwise return current lastly-visited CDP as the startNode for next pagination
    /// @return found True if the CDP was found, false otherwise
    function _cdpOfOwnerByIndex(
        address owner,
        uint256 index,
        bytes32 startNodeId,
        uint maxNodes
    ) internal view returns (bytes32, bool) {
        // walk the list, until we get to the indexed CDP
        // start at the given node or from the tail of list
        bytes32 _currentCdpId = (startNodeId == dummyId ? data.tail : startNodeId);
        uint _currentIndex = 0;
        uint i;

        while (_currentCdpId != dummyId) {
            // if the current CDP is owned by specified owner
            if (getOwnerAddress(_currentCdpId) == owner) {
                // if the current index of the owner CDP matches specified index
                if (_currentIndex == index) {
                    return (_currentCdpId, true);
                } else {
                    // if not, increment the owner index as we've seen a CDP owned by them
                    _currentIndex = _currentIndex + 1;
                }
            }
            ++i;

            // move to the next CDP in the list
            _currentCdpId = data.nodes[_currentCdpId].prevId;

            // cut the run if we exceed expected iterations through the loop
            if (maxNodes > 0 && i >= maxNodes) {
                break;
            }
        }
        // if we reach maximum iteration or end of list
        // without seeing the specified index for the owner
        // then maybe a new pagination is needed
        return (_currentCdpId, false);
    }

    /// @notice Get active CDP count for an owner address
    /// @dev Intended for off-chain use, O(n) operation on size of linked list
    /// @param owner Owner address to count Cdps for
    /// @return count Number of active Cdps owned by the address
    function cdpCountOf(address owner) external view override returns (uint256) {
        (uint256 _cnt, ) = _cdpCountOf(owner, dummyId, 0);
        return _cnt;
    }

    /// @notice a Pagination-flavor search for the count of Cdps owned by given owner
    /// @notice Starts from a given CdpId in the sorted list, and moves from lowest ICR to highest ICR
    /// @param startNodeId the count traversal will start at this given CDP instead of the tail of the list
    /// @param maxNodes the traversal will go through the list by this given maximum limit of number of Cdps
    /// @return count Number of active Cdps owned by the address in the segment of the list traversed
    /// @return last seen CDP for the startNode for next pagination
    function getCdpCountOf(
        address owner,
        bytes32 startNodeId,
        uint maxNodes
    ) external view override returns (uint256, bytes32) {
        return _cdpCountOf(owner, startNodeId, maxNodes);
    }

    /// @dev return the found CDP count owned by given owner with
    /// @dev current lastly-visited CDP as the startNode for next pagination
    function _cdpCountOf(
        address owner,
        bytes32 startNodeId,
        uint maxNodes
    ) internal view returns (uint256, bytes32) {
        // walk the list, until we get to the count
        // start at the given node or from the tail of list
        bytes32 _currentCdpId = (startNodeId == dummyId ? data.tail : startNodeId);
        uint _ownedCount = 0;
        uint i = 0;

        while (_currentCdpId != dummyId) {
            // if the current CDP is owned by specified owner
            if (getOwnerAddress(_currentCdpId) == owner) {
                _ownedCount = _ownedCount + 1;
            }
            ++i;

            // move to the next CDP in the list
            _currentCdpId = data.nodes[_currentCdpId].prevId;

            // cut the run if we exceed expected iterations through the loop
            if (maxNodes > 0 && i >= maxNodes) {
                break;
            }
        }
        return (_ownedCount, _currentCdpId);
    }

    /// @notice Get all active Cdps for a given address
    /// @dev Intended for off-chain use, O(n) operation on size of linked list
    /// @param owner address of CDP owner
    /// @return cdps all CdpIds of the specified owner
    function getCdpsOf(address owner) external view override returns (bytes32[] memory cdps) {
        // Naive method uses two-pass strategy to determine exactly how many Cdps are owned by owner
        // This roughly halves the amount of Cdps we can process before relying on pagination or off-chain methods
        (uint _ownedCount, ) = _cdpCountOf(owner, dummyId, 0);
        if (_ownedCount > 0) {
            (bytes32[] memory _allCdps, , ) = _getCdpsOf(owner, dummyId, 0, _ownedCount);
            cdps = _allCdps;
        }
    }

    /// @dev a pagination-flavor search retrieval of (from least ICR to biggest ICR) Cdps owned by given owner (starting at given CDP)
    /// @param startNodeId the traversal will start at this given CDP instead of the tail of the list
    /// @param maxNodes the traversal will go through the list by this given maximum limit of number of Cdps
    /// @return all CdpIds of the specified owner found by search starting at the specified startNodeId for the specified maximum iteration count
    /// @return found number of Cdp for the owner
    /// @return starting CdpId for next pagination within current SortedCdps
    function getAllCdpsOf(
        address owner,
        bytes32 startNodeId,
        uint maxNodes
    ) external view override returns (bytes32[] memory, uint256, bytes32) {
        // Naive method uses two-pass strategy to determine exactly how many Cdps are owned by owner
        // This roughly halves the amount of Cdps we can process before relying on pagination or off-chain methods
        (uint _ownedCount, ) = _cdpCountOf(owner, startNodeId, maxNodes);
        return _getCdpsOf(owner, startNodeId, maxNodes, _ownedCount);
    }

    /// @dev return EITHER the found Cdps (also the count) owned by given owner OR empty array with
    /// @dev current lastly-visited CDP as the startNode for next pagination
    function _getCdpsOf(
        address owner,
        bytes32 startNodeId,
        uint maxNodes,
        uint maxArraySize
    ) internal view returns (bytes32[] memory, uint256, bytes32) {
        if (maxArraySize == 0) {
            return (new bytes32[](0), 0, dummyId);
        }

        // Two-pass strategy, halving the amount of Cdps we can process before relying on pagination or off-chain methods
        bytes32[] memory userCdps = new bytes32[](maxArraySize);
        uint i = 0;
        uint _cdpRetrieved;

        // walk the list, until we get to the index
        // start at the given node or from the tail of list
        bytes32 _currentCdpId = (startNodeId == dummyId ? data.tail : startNodeId);

        while (_currentCdpId != dummyId) {
            // if the current CDP is owned by specified owner
            if (getOwnerAddress(_currentCdpId) == owner) {
                userCdps[_cdpRetrieved] = _currentCdpId;
                ++_cdpRetrieved;
            }
            ++i;

            // move to the next CDP in the list
            _currentCdpId = data.nodes[_currentCdpId].prevId;

            // cut the run if we exceed expected iterations through the loop
            if (maxNodes > 0 && i >= maxNodes) {
                break;
            }
        }

        return (userCdps, _cdpRetrieved, _currentCdpId);
    }

    /// @notice Add a node to the list
    /// @param owner CDP owner for corresponding Id
    /// @param _NICR Node's NICR
    /// @param _prevId Id of previous node for the insert position
    /// @param _nextId Id of next node for the insert position
    /// @return _id Id of the new node
    function insert(
        address owner,
        uint256 _NICR,
        bytes32 _prevId,
        bytes32 _nextId
    ) external override returns (bytes32) {
        _requireCallerIsBOorCdpM();
        bytes32 _id = toCdpId(owner, block.number, nextCdpNonce);
        require(cdpManager.getCdpStatus(_id) == 0, "SortedCdps: new id is NOT nonExistent!");

        _insert(_id, _NICR, _prevId, _nextId);

        unchecked {
            ++nextCdpNonce;
        }

        return _id;
    }

    function _insert(bytes32 _id, uint256 _NICR, bytes32 _prevId, bytes32 _nextId) internal {
        // List must not be full
        require(!isFull(), "SortedCdps: List is full");
        // List must not already contain node
        require(!contains(_id), "SortedCdps: List already contains the node");
        // Node id must not be null
        require(_id != dummyId, "SortedCdps: Id cannot be zero");
        // NICR must be non-zero
        require(_NICR > 0, "SortedCdps: NICR must be positive");

        bytes32 prevId = _prevId;
        bytes32 nextId = _nextId;

        if (!_validInsertPosition(_NICR, prevId, nextId)) {
            // Sender's hint was not a valid insert position
            // Use sender's hint to find a valid insert position
            (prevId, nextId) = _findInsertPosition(_NICR, prevId, nextId);
        }

        if (prevId == dummyId && nextId == dummyId) {
            // Insert as head and tail
            data.head = _id;
            data.tail = _id;
        } else if (prevId == dummyId) {
            // Insert before `prevId` as the head
            data.nodes[_id].nextId = data.head;
            data.nodes[data.head].prevId = _id;
            data.head = _id;
        } else if (nextId == dummyId) {
            // Insert after `nextId` as the tail
            data.nodes[_id].prevId = data.tail;
            data.nodes[data.tail].nextId = _id;
            data.tail = _id;
        } else {
            // Insert at insert position between `prevId` and `nextId`
            data.nodes[_id].nextId = nextId;
            data.nodes[_id].prevId = prevId;
            data.nodes[prevId].nextId = _id;
            data.nodes[nextId].prevId = _id;
        }

        size = size + 1;
        emit NodeAdded(_id, _NICR);
    }

    /// @notice Remove a node from the sorted list, by Id
    /// @param _id The CdpId to be removed
    function remove(bytes32 _id) external override {
        _requireCallerIsCdpManager();
        _remove(_id);
    }

    /// @notice Batch a node from the sorted list, by Id
    /// @notice Strong trust assumption that the specified nodes are sorted in the same order as in the input array
    /// @dev Optimization to reduce gas cost for removing multiple nodes on redemption
    /// @param _ids Array of CdpIds to remove
    function batchRemove(bytes32[] memory _ids) external override {
        _requireCallerIsCdpManager();
        uint256 _len = _ids.length;
        require(_len > 1, "SortedCdps: batchRemove() only apply to multiple cdpIds!");

        bytes32 _firstPrev = data.nodes[_ids[0]].prevId;
        bytes32 _lastNext = data.nodes[_ids[_len - 1]].nextId;

        require(
            _firstPrev != dummyId || _lastNext != dummyId,
            "SortedCdps: batchRemove() leave ZERO node left!"
        );

        for (uint256 i = 0; i < _len; ++i) {
            require(contains(_ids[i]), "SortedCdps: List does not contain the id");
        }

        // orphan nodes in between to save gas
        if (_firstPrev != dummyId) {
            data.nodes[_firstPrev].nextId = _lastNext;
        } else {
            data.head = _lastNext;
        }
        if (_lastNext != dummyId) {
            data.nodes[_lastNext].prevId = _firstPrev;
        } else {
            data.tail = _firstPrev;
        }

        // delete node & owner storages to get gas refund
        for (uint i = 0; i < _len; ++i) {
            delete data.nodes[_ids[i]];
            emit NodeRemoved(_ids[i]);
        }
        size = size - _len;
    }

    function _remove(bytes32 _id) internal {
        // List must contain the node
        require(contains(_id), "SortedCdps: List does not contain the id");

        if (size > 1) {
            // List contains more than a single node
            if (_id == data.head) {
                // The removed node is the head
                // Set head to next node
                data.head = data.nodes[_id].nextId;
                // Set prev pointer of new head to null
                data.nodes[data.head].prevId = dummyId;
            } else if (_id == data.tail) {
                // The removed node is the tail
                // Set tail to previous node
                data.tail = data.nodes[_id].prevId;
                // Set next pointer of new tail to null
                data.nodes[data.tail].nextId = dummyId;
            } else {
                // The removed node is neither the head nor the tail
                // Set next pointer of previous node to the next node
                data.nodes[data.nodes[_id].prevId].nextId = data.nodes[_id].nextId;
                // Set prev pointer of next node to the previous node
                data.nodes[data.nodes[_id].nextId].prevId = data.nodes[_id].prevId;
            }
        } else {
            // List contains a single node
            // Set the head and tail to null
            data.head = dummyId;
            data.tail = dummyId;
        }

        delete data.nodes[_id];
        size = size - 1;
        emit NodeRemoved(_id);
    }

    /// @notice Re-insert an existing node at a new position, based on its new NICR
    /// @param _id Node's id
    /// @param _newNICR Node's new NICR
    /// @param _prevId Id of previous node for the new insert position
    /// @param _nextId Id of next node for the new insert position
    function reInsert(
        bytes32 _id,
        uint256 _newNICR,
        bytes32 _prevId,
        bytes32 _nextId
    ) external override {
        _requireCallerIsBOorCdpM();
        // List must contain the node
        require(contains(_id), "SortedCdps: List does not contain the id");
        // NICR must be non-zero
        require(_newNICR > 0, "SortedCdps: NICR must be positive");

        // Remove node from the list
        _remove(_id);

        _insert(_id, _newNICR, _prevId, _nextId);
    }

    /// @dev Checks if the list contains a given node Id
    /// @param _id The Id of the node
    /// @return true if the node exists, false otherwise
    function contains(bytes32 _id) public view override returns (bool) {
        bool _exist = _id != dummyId && (data.head == _id || data.tail == _id);
        if (!_exist) {
            Node memory _node = data.nodes[_id];
            _exist = _id != dummyId && (_node.nextId != dummyId && _node.prevId != dummyId);
        }
        return _exist;
    }

    /// @dev Checks if the list is full
    /// @return true if the list is full, false otherwise
    function isFull() public view override returns (bool) {
        return size == maxSize;
    }

    /// @dev Checks if the list is empty
    /// @return true if the list is empty, false otherwise
    function isEmpty() public view override returns (bool) {
        return size == 0;
    }

    /// @dev Returns the current size of the list
    /// @return The current size of the list
    function getSize() external view override returns (uint256) {
        return size;
    }

    /// @dev Returns the maximum size of the list
    /// @return The maximum size of the list
    function getMaxSize() external view override returns (uint256) {
        return maxSize;
    }

    /// @dev Returns the first node in the list (node with the largest NICR)
    /// @return The Id of the first node
    function getFirst() external view override returns (bytes32) {
        return data.head;
    }

    /// @dev Returns the last node in the list (node with the smallest NICR)
    /// @return The Id of the last node
    function getLast() external view override returns (bytes32) {
        return data.tail;
    }

    /// @dev Returns the next node (with a smaller NICR) in the list for a given node
    /// @param _id The Id of the node
    /// @return The Id of the next node
    function getNext(bytes32 _id) external view override returns (bytes32) {
        return data.nodes[_id].nextId;
    }

    /// @dev Returns the previous node (with a larger NICR) in the list for a given node
    /// @param _id The Id of the node
    /// @return The Id of the previous node
    function getPrev(bytes32 _id) external view override returns (bytes32) {
        return data.nodes[_id].prevId;
    }

    /// @dev Check if a pair of nodes is a valid insertion point for a new node with the given NICR
    /// @param _NICR Node's NICR
    /// @param _prevId Id of previous node for the insert position
    /// @param _nextId Id of next node for the insert position
    /// @return true if the position is valid, false otherwise
    function validInsertPosition(
        uint256 _NICR,
        bytes32 _prevId,
        bytes32 _nextId
    ) external view override returns (bool) {
        return _validInsertPosition(_NICR, _prevId, _nextId);
    }

    function _validInsertPosition(
        uint256 _NICR,
        bytes32 _prevId,
        bytes32 _nextId
    ) internal view returns (bool) {
        if (_prevId == dummyId && _nextId == dummyId) {
            // `(null, null)` is a valid insert position if the list is empty
            return isEmpty();
        } else if (_prevId == dummyId) {
            // `(null, _nextId)` is a valid insert position if `_nextId` is the head of the list
            return data.head == _nextId && _NICR >= cdpManager.getCachedNominalICR(_nextId);
        } else if (_nextId == dummyId) {
            // `(_prevId, null)` is a valid insert position if `_prevId` is the tail of the list
            return data.tail == _prevId && _NICR <= cdpManager.getCachedNominalICR(_prevId);
        } else {
            // `(_prevId, _nextId)` is a valid insert position if they are adjacent nodes and `_NICR` falls between the two nodes' NICRs
            return
                data.nodes[_prevId].nextId == _nextId &&
                cdpManager.getCachedNominalICR(_prevId) >= _NICR &&
                _NICR >= cdpManager.getCachedNominalICR(_nextId);
        }
    }

    /// @dev Descend the list (larger NICRs to smaller NICRs) to find a valid insert position
    /// @param _NICR Node's NICR
    /// @param _startId Id of node to start descending the list from
    /// @return The previous node Id for the inserted node
    /// @return The next node Id for the inserted node
    function _descendList(uint256 _NICR, bytes32 _startId) internal view returns (bytes32, bytes32) {
        // If `_startId` is the head, check if the insert position is before the head
        if (data.head == _startId && _NICR >= cdpManager.getCachedNominalICR(_startId)) {
            return (dummyId, _startId);
        }

        bytes32 prevId = _startId;
        bytes32 nextId = data.nodes[prevId].nextId;

        // Descend the list until we reach the end or until we find a valid insert position
        while (prevId != dummyId && !_validInsertPosition(_NICR, prevId, nextId)) {
            prevId = data.nodes[prevId].nextId;
            nextId = data.nodes[prevId].nextId;
        }

        return (prevId, nextId);
    }

    /// @dev Ascend the list (smaller NICRs to larger NICRs) to find a valid insert position
    /// @param _NICR Node's NICR
    /// @param _startId Id of node to start ascending the list from
    /// @return The previous node Id for the inserted node
    /// @return The next node Id for the inserted node
    function _ascendList(uint256 _NICR, bytes32 _startId) internal view returns (bytes32, bytes32) {
        // If `_startId` is the tail, check if the insert position is after the tail
        if (data.tail == _startId && _NICR <= cdpManager.getCachedNominalICR(_startId)) {
            return (_startId, dummyId);
        }

        bytes32 nextId = _startId;
        bytes32 prevId = data.nodes[nextId].prevId;

        // Ascend the list until we reach the end or until we find a valid insertion point
        while (nextId != dummyId && !_validInsertPosition(_NICR, prevId, nextId)) {
            nextId = data.nodes[nextId].prevId;
            prevId = data.nodes[nextId].prevId;
        }

        return (prevId, nextId);
    }

    /// @dev Find the insert position for a node with the given NICR
    /// @param _NICR Node's NICR
    /// @param _prevId Id of previous node for the insert position
    /// @param _nextId Id of next node for the insert position
    /// @return The previous node Id for the inserted node
    /// @return The next node Id for the inserted node
    function findInsertPosition(
        uint256 _NICR,
        bytes32 _prevId,
        bytes32 _nextId
    ) external view override returns (bytes32, bytes32) {
        return _findInsertPosition(_NICR, _prevId, _nextId);
    }

    function _findInsertPosition(
        uint256 _NICR,
        bytes32 _prevId,
        bytes32 _nextId
    ) internal view returns (bytes32, bytes32) {
        bytes32 prevId = _prevId;
        bytes32 nextId = _nextId;

        if (prevId != dummyId) {
            if (!contains(prevId) || _NICR > cdpManager.getCachedNominalICR(prevId)) {
                // `prevId` does not exist anymore or now has a smaller NICR than the given NICR
                prevId = dummyId;
            }
        }

        if (nextId != dummyId) {
            if (!contains(nextId) || _NICR < cdpManager.getCachedNominalICR(nextId)) {
                // `nextId` does not exist anymore or now has a larger NICR than the given NICR
                nextId = dummyId;
            }
        }

        if (prevId == dummyId && nextId == dummyId) {
            // No hint - descend list starting from head
            return _descendList(_NICR, data.head);
        } else if (prevId == dummyId) {
            // No `prevId` for hint - ascend list starting from `nextId`
            return _ascendList(_NICR, nextId);
        } else if (nextId == dummyId) {
            // No `nextId` for hint - descend list starting from `prevId`
            return _descendList(_NICR, prevId);
        } else {
            // Descend list starting from `prevId`
            return _descendList(_NICR, prevId);
        }
    }

    // === Modifiers ===

    /// @dev Asserts that the caller of the function is the CdpManager
    function _requireCallerIsCdpManager() internal view {
        require(msg.sender == address(cdpManager), "SortedCdps: Caller is not the CdpManager");
    }

    /// @dev Asserts that the caller of the function is either the BorrowerOperations contract or the CdpManager
    function _requireCallerIsBOorCdpM() internal view {
        require(
            msg.sender == borrowerOperationsAddress || msg.sender == address(cdpManager),
            "SortedCdps: Caller is neither BO nor CdpM"
        );
    }
}
