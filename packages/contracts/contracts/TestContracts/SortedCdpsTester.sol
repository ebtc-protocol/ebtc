// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../Interfaces/ISortedCdps.sol";

contract SortedCdpsTester {
    ISortedCdps sortedCdps;

    function setSortedCdps(address _sortedCdpsAddress) external {
        sortedCdps = ISortedCdps(_sortedCdpsAddress);
    }

    function insert(
        address _owner,
        bytes32 _cdpId,
        uint256 _NICR,
        bytes32 _prevId,
        bytes32 _nextId
    ) external {
        sortedCdps.insert(_owner, _cdpId, _NICR, _prevId, _nextId);
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

    function getNominalICR(bytes32) external pure returns (uint) {
        return 1;
    }

    function getCurrentICR(bytes32, uint) external pure returns (uint) {
        return 1;
    }
}
