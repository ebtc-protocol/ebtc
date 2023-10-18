// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../Interfaces/ISortedCdps.sol";

contract SortedCdpsTester {
    ISortedCdps sortedCdps;

    function setSortedCdps(address _sortedCdpsAddress) external {
        sortedCdps = ISortedCdps(_sortedCdpsAddress);
    }

    function insert(address _owner, uint256 _NICR, bytes32 _prevId, bytes32 _nextId) external {
        sortedCdps.insert(_owner, _NICR, _prevId, _nextId);
    }

    function remove(bytes32 _id) external {
        sortedCdps.remove(_id);
    }

    function reInsert(bytes32 _id, uint256 _newNICR, bytes32 _prevId, bytes32 _nextId) external {
        sortedCdps.reInsert(_id, _newNICR, _prevId, _nextId);
    }

    function getCachedNominalICR(bytes32) external pure returns (uint256) {
        return 1;
    }

    function getCachedICR(bytes32, uint256) external pure returns (uint256) {
        return 1;
    }

    // dummy return 0 for nonExistent check
    function getCdpStatus(bytes32 _id) external view returns (uint256) {
        return 0;
    }
}
