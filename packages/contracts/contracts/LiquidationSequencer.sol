// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./Interfaces/IPriceFeed.sol";
import "./Interfaces/ICdpManager.sol";
import "./Interfaces/ISortedCdps.sol";
import "./Interfaces/ICdpManagerData.sol";
import "./Dependencies/LiquityBase.sol";

/// @notice Helper to turn a sequence into CDP id array for batch liquidation
/// @dev Note this sequencer only serves as an approximation tool to provide "best-effort"
/// @dev that return a list of CDP ids which could be consumed by "CdpManager.batchLiquidateCdps()".
/// @dev It is possible that some of the returned CDPs might be skipped (not liquidatable any more)
/// @dev during liquidation execution due to change of the system states
/// @dev e.g., TCR brought back from Recovery Mode to Normal Mode
contract LiquidationSequencer is LiquityBase {
    ICdpManager public immutable cdpManager;
    ISortedCdps public immutable sortedCdps;

    constructor(
        address _cdpManagerAddress,
        address _sortedCdpsAddress,
        address _priceFeedAddress,
        address _activePoolAddress,
        address _collateralAddress
    ) LiquityBase(_activePoolAddress, _priceFeedAddress, _collateralAddress) {
        cdpManager = ICdpManager(_cdpManagerAddress);
        sortedCdps = ISortedCdps(_sortedCdpsAddress);
    }

    /// @dev Get first N batch of liquidatable Cdps at current price
    /// @dev Non-view function that updates and returns live price at execution time
    /// @dev could use callStatic offline to save gas
    function sequenceLiqToBatchLiq(uint256 _n) external returns (bytes32[] memory _array) {
        uint256 _price = priceFeed.fetchPrice();
        return sequenceLiqToBatchLiqWithPrice(_n, _price);
    }

    /// @dev Get first N batch of liquidatable Cdps at specified price
    /// @dev Non-view function that will sync global state
    /// @dev could use callStatic offline to save gas
    function sequenceLiqToBatchLiqWithPrice(
        uint256 _n,
        uint256 _price
    ) public returns (bytes32[] memory _array) {
        cdpManager.syncGlobalAccountingAndGracePeriod();
        (uint256 _TCR, , ) = _getTCRWithSystemDebtAndCollShares(_price);
        return _sequenceLiqToBatchLiq(_n, _price, _TCR);
    }

    // return CdpId array (in NICR-decreasing order same as SortedCdps)
    // including the last N CDPs in sortedCdps for batch liquidation
    function _sequenceLiqToBatchLiq(
        uint256 _n,
        uint256 _price,
        uint256 _TCR
    ) internal view returns (bytes32[] memory _array) {
        if (_n > 0) {
            bool _recoveryMode = _TCR < CCR ? true : false;
            // get count of liquidatable CDPs with 1st iteration
            (uint256 _cnt, ) = _iterateOverSortedCdps(0, _TCR, _n, _price, _recoveryMode);

            // retrieve liquidatable CDPs with 2nd iteration
            (uint256 _j, bytes32[] memory _returnedArray) = _iterateOverSortedCdps(
                _cnt,
                _TCR,
                _n,
                _price,
                _recoveryMode
            );
            require(_j == _cnt, "LiquidationSequencer: wrong sequence conversion!");
            _array = _returnedArray;
        }
    }

    function _iterateOverSortedCdps(
        uint256 _realCount,
        uint256 _TCR,
        uint256 _n,
        uint256 _price,
        bool _recoveryMode
    ) internal view returns (uint256 _cnt, bytes32[] memory _array) {
        // if there is already a count (calculated from previous iteration)
        // we use the value to initialize CDP id array for return
        if (_realCount > 0) {
            _array = new bytes32[](_realCount);
        }

        // initialize variables for this iteration
        bytes32 _last = sortedCdps.getLast();
        bytes32 _first = sortedCdps.getFirst();
        bytes32 _cdpId = _last;

        for (uint256 i = 0; i < (_realCount > 0 ? _realCount : _n) && _cdpId != _first; ++i) {
            bool _liquidatable = _checkCdpLiquidability(_cdpId, _TCR, _price, _recoveryMode);
            if (_liquidatable) {
                if (_realCount > 0) {
                    _array[_realCount - _cnt - 1] = _cdpId;
                }
                _cnt += 1;
                _cdpId = sortedCdps.getPrev(_cdpId);
            } else {
                // breaking loop early if not liquidatable due to sorted (descending) list of CDPs
                break;
            }
        }
    }

    function _checkCdpLiquidability(
        bytes32 _cdpId,
        uint256 _TCR,
        uint256 _price,
        bool _recoveryMode
    ) internal view returns (bool) {
        uint256 _icr = cdpManager.getSyncedICR(_cdpId, _price);
        bool _liquidatable = _canLiquidateInCurrentMode(_recoveryMode, _icr, _TCR);
        return _liquidatable;
    }

    function _canLiquidateInCurrentMode(
        bool _recovery,
        uint256 _icr,
        uint256 _TCR
    ) internal view returns (bool) {
        bool _liquidatable = _recovery ? (_icr < MCR || _icr < _TCR) : _icr < MCR;

        return _liquidatable;
    }
}
