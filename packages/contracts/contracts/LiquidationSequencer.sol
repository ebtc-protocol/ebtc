// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./Interfaces/IPriceFeed.sol";
import "./Interfaces/ICdpManager.sol";
import "./Interfaces/ISortedCdps.sol";
import "./Interfaces/ICdpManagerData.sol";
import "./Dependencies/LiquityBase.sol";

/// @notice Helper to turn a sequence into CDP id array for batch liquidation
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
    function sequenceLiqToBatchLiq(uint256 _n) external returns (bytes32[] memory _array) {
        uint256 _price = priceFeed.fetchPrice();
        return sequenceLiqToBatchLiqWithPrice(_n, _price);
    }

    /// @dev Get first N batch of liquidatable Cdps at specified price
    function sequenceLiqToBatchLiqWithPrice(
        uint256 _n,
        uint256 _price
    ) public view returns (bytes32[] memory _array) {
        (uint256 _TCR, , ) = _getTCRWithSystemDebtAndCollShares(_price);
        bool _recoveryModeAtStart = _TCR < CCR ? true : false;
        return _sequenceLiqToBatchLiq(_n, _recoveryModeAtStart, _price);
    }

    // return CdpId array (in NICR-decreasing order same as SortedCdps)
    // including the last N CDPs in sortedCdps for batch liquidation
    function _sequenceLiqToBatchLiq(
        uint256 _n,
        bool _recoveryModeAtStart,
        uint256 _price
    ) internal view returns (bytes32[] memory _array) {
        if (_n > 0) {
            bytes32 _last = sortedCdps.getLast();
            bytes32 _first = sortedCdps.getFirst();
            bytes32 _cdpId = _last;

            uint256 _TCR = cdpManager.getTCR(_price);

            // get count of liquidatable CDPs
            uint256 _cnt;
            for (uint256 i = 0; i < _n && _cdpId != _first; ++i) {
                uint256 _icr = cdpManager.getICR(_cdpId, _price); /// @audit This is view ICR and not real ICR
                uint256 _cdpStatus = cdpManager.getCdpStatus(_cdpId);
                bool _liquidatable = _checkICRAgainstLiqThreshold(_icr, _TCR);
                if (_liquidatable && _cdpStatus == 1) {
                    _cnt += 1;
                }
                _cdpId = sortedCdps.getPrev(_cdpId);
            }

            // retrieve liquidatable CDPs
            _array = new bytes32[](_cnt);
            _cdpId = _last;
            uint256 _j;
            for (uint256 i = 0; i < _n && _cdpId != _first; ++i) {
                uint256 _icr = cdpManager.getICR(_cdpId, _price);
                uint256 _cdpStatus = cdpManager.getCdpStatus(_cdpId);
                bool _liquidatable = _checkICRAgainstLiqThreshold(_icr, _TCR);
                if (_liquidatable && _cdpStatus == 1) {
                    // 1 = ICdpManagerData.Status.active
                    _array[_cnt - _j - 1] = _cdpId;
                    _j += 1;
                }
                _cdpId = sortedCdps.getPrev(_cdpId);
            }
            require(_j == _cnt, "LiquidationLibrary: wrong sequence conversion!");
        }
    }
}
