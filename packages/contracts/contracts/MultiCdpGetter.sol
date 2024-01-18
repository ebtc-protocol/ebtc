// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./CdpManager.sol";
import "./SortedCdps.sol";

/*  Helper contract for grabbing Cdp data for the front end. Not part of the core Ebtc system. */
contract MultiCdpGetter {
    struct CombinedCdpData {
        bytes32 id;
        uint256 debt;
        uint256 coll;
        uint256 stake;
        uint256 snapshotEBTCDebt;
    }

    CdpManager public immutable cdpManager;
    ISortedCdps public immutable sortedCdps;

    /// @notice Creates a new MultiCdpGetter contract
    /// @param _cdpManager The CdpManager contract
    /// @param _sortedCdps The ISortedCdps contract
    constructor(CdpManager _cdpManager, ISortedCdps _sortedCdps) {
        cdpManager = _cdpManager;
        sortedCdps = _sortedCdps;
    }

    /// @notice Retrieves multiple sorted Cdps
    /// @param _startIdx The start index for the linked list. The sign determines whether to start from the head or tail of the list.
    /// @dev Positive values start from the _head_ of the list and walk towards the _tail_, negative values start from the _tail_ of the list and walk towards the _head_
    /// @param _count The count of Cdps to retrieve. If the requested count exceeds the number of available Cdps starting from the _startIdx, the function will only retrieve the available Cdps.
    /// @return _cdps An array of CombinedCdpData structs
    function getMultipleSortedCdps(
        int _startIdx,
        uint256 _count
    ) external view returns (CombinedCdpData[] memory _cdps) {
        uint256 startIdx;
        bool descend;

        if (_startIdx >= 0) {
            startIdx = uint256(_startIdx);
            descend = true;
        } else {
            startIdx = uint256(-(_startIdx + 1));
            descend = false;
        }

        uint256 sortedCdpsSize = sortedCdps.getSize();

        if (startIdx >= sortedCdpsSize) {
            _cdps = new CombinedCdpData[](0);
        } else {
            uint256 maxCount = sortedCdpsSize - startIdx;

            if (_count > maxCount) {
                _count = maxCount;
            }

            if (descend) {
                _cdps = _getMultipleSortedCdpsFromHead(startIdx, _count);
            } else {
                _cdps = _getMultipleSortedCdpsFromTail(startIdx, _count);
            }
        }
    }

    /// @notice Internal function to retrieve multiple sorted Cdps from head
    /// @param _startIdx The start index
    /// @param _count The count of Cdps to retrieve
    /// @return _cdps An array of CombinedCdpData structs
    function _getMultipleSortedCdpsFromHead(
        uint256 _startIdx,
        uint256 _count
    ) internal view returns (CombinedCdpData[] memory _cdps) {
        bytes32 currentCdpId = sortedCdps.getFirst();

        for (uint256 idx = 0; idx < _startIdx; ++idx) {
            currentCdpId = sortedCdps.getNext(currentCdpId);
        }

        _cdps = new CombinedCdpData[](_count);

        for (uint256 idx = 0; idx < _count; ++idx) {
            _cdps[idx].id = currentCdpId;
            (, , _cdps[idx].stake, , ) = cdpManager.Cdps(currentCdpId);

            (_cdps[idx].debt, _cdps[idx].coll) = cdpManager.getSyncedDebtAndCollShares(currentCdpId);
            (_cdps[idx].snapshotEBTCDebt) = cdpManager.cdpDebtRedistributionIndex(currentCdpId);

            currentCdpId = sortedCdps.getNext(currentCdpId);
        }
    }

    /// @notice Internal function to retrieve multiple sorted Cdps from tail
    /// @param _startIdx The start index
    /// @param _count The count of Cdps to retrieve
    /// @return _cdps An array of CombinedCdpData structs
    function _getMultipleSortedCdpsFromTail(
        uint256 _startIdx,
        uint256 _count
    ) internal view returns (CombinedCdpData[] memory _cdps) {
        bytes32 currentCdpId = sortedCdps.getLast();

        for (uint256 idx = 0; idx < _startIdx; ++idx) {
            currentCdpId = sortedCdps.getPrev(currentCdpId);
        }

        _cdps = new CombinedCdpData[](_count);

        for (uint256 idx = 0; idx < _count; ++idx) {
            _cdps[idx].id = currentCdpId;
            (, , _cdps[idx].stake, , ) = cdpManager.Cdps(currentCdpId);

            (_cdps[idx].debt, _cdps[idx].coll) = cdpManager.getSyncedDebtAndCollShares(currentCdpId);
            (_cdps[idx].snapshotEBTCDebt) = cdpManager.cdpDebtRedistributionIndex(currentCdpId);

            currentCdpId = sortedCdps.getPrev(currentCdpId);
        }
    }
}
