// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "../Interfaces/ISortedTroves.sol";


contract SortedTrovesTester {
    ISortedTroves sortedTroves;

    function setSortedTroves(address _sortedTrovesAddress) external {
        sortedTroves = ISortedTroves(_sortedTrovesAddress);
    }

    function insert(address _owner, uint256 _NICR, bytes32 _prevId, bytes32 _nextId) external {
        sortedTroves.insert(_owner, _NICR, _prevId, _nextId);
    }

    function remove(bytes32 _id) external {
        sortedTroves.remove(_id);
    }

    function reInsert(bytes32 _id, uint256 _newNICR, bytes32 _prevId, bytes32 _nextId) external {
        sortedTroves.reInsert(_id, _newNICR, _prevId, _nextId);
    }

    function getNominalICR(bytes32) external pure returns (uint) {
        return 1;
    }

    function getCurrentICR(bytes32, uint) external pure returns (uint) {
        return 1;
    }
}
