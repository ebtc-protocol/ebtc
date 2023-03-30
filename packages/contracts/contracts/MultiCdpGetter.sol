// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "./CdpManager.sol";
import "./SortedCdps.sol";

/*  Helper contract for grabbing Cdp data for the front end. Not part of the core Liquity system. */
contract MultiCdpGetter {
    struct CombinedCdpData {
        bytes32 id;
        uint debt;
        uint coll;
        uint stake;
        uint snapshotETH;
        uint snapshotEBTCDebt;
    }

    CdpManager public cdpManager; // XXX Cdps missing from ICdpManager?
    ISortedCdps public sortedCdps;

    constructor(CdpManager _cdpManager, ISortedCdps _sortedCdps) public {
        cdpManager = _cdpManager;
        sortedCdps = _sortedCdps;
    }

    function getMultipleSortedCdps(
        int _startIdx,
        uint _count
    ) external view returns (CombinedCdpData[] memory _cdps) {
        uint startIdx;
        bool descend;

        if (_startIdx >= 0) {
            startIdx = uint(_startIdx);
            descend = true;
        } else {
            startIdx = uint(-(_startIdx + 1));
            descend = false;
        }

        uint sortedCdpsSize = sortedCdps.getSize();

        if (startIdx >= sortedCdpsSize) {
            _cdps = new CombinedCdpData[](0);
        } else {
            uint maxCount = sortedCdpsSize - startIdx;

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

    function _getMultipleSortedCdpsFromHead(
        uint _startIdx,
        uint _count
    ) internal view returns (CombinedCdpData[] memory _cdps) {
        bytes32 currentCdpId = sortedCdps.getFirst();

        for (uint idx = 0; idx < _startIdx; ++idx) {
            currentCdpId = sortedCdps.getNext(currentCdpId);
        }

        _cdps = new CombinedCdpData[](_count);

        for (uint idx = 0; idx < _count; ++idx) {
            _cdps[idx].id = currentCdpId;
            (
                _cdps[idx].debt,
                _cdps[idx].coll,
                _cdps[idx].stake,
                /* status */
                /* arrayIndex */
                ,

            ) = cdpManager.Cdps(currentCdpId);

            (_cdps[idx].snapshotETH, _cdps[idx].snapshotEBTCDebt) = cdpManager.rewardSnapshots(
                currentCdpId
            );

            currentCdpId = sortedCdps.getNext(currentCdpId);
        }
    }

    function _getMultipleSortedCdpsFromTail(
        uint _startIdx,
        uint _count
    ) internal view returns (CombinedCdpData[] memory _cdps) {
        bytes32 currentCdpId = sortedCdps.getLast();

        for (uint idx = 0; idx < _startIdx; ++idx) {
            currentCdpId = sortedCdps.getPrev(currentCdpId);
        }

        _cdps = new CombinedCdpData[](_count);

        for (uint idx = 0; idx < _count; ++idx) {
            _cdps[idx].id = currentCdpId;
            (
                _cdps[idx].debt,
                _cdps[idx].coll,
                _cdps[idx].stake,
                /* status */
                /* arrayIndex */
                ,

            ) = cdpManager.Cdps(currentCdpId);

            (_cdps[idx].snapshotETH, _cdps[idx].snapshotEBTCDebt) = cdpManager.rewardSnapshots(
                currentCdpId
            );

            currentCdpId = sortedCdps.getPrev(currentCdpId);
        }
    }
}
