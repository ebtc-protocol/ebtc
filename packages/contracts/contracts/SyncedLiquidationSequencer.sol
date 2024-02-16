// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./Interfaces/IPriceFeed.sol";
import "./Interfaces/ICdpManager.sol";
import "./Interfaces/ISortedCdps.sol";
import "./Interfaces/ICdpManagerData.sol";
import "./Dependencies/EbtcBase.sol";

/// @notice Helper to turn a sequence into CDP id array for batch liquidation
contract SyncedLiquidationSequencer is EbtcBase {
    ICdpManager public immutable cdpManager;
    ISortedCdps public immutable sortedCdps;

    /// @param _cdpManagerAddress Address of CdpManager contract
    /// @param _sortedCdpsAddress Address of SortedCdps contract
    /// @param _priceFeedAddress Address of price feed
    /// @param _activePoolAddress Address of ActivePool
    /// @param _collateralAddress Address of collateral contract
    constructor(
        address _cdpManagerAddress,
        address _sortedCdpsAddress,
        address _priceFeedAddress,
        address _activePoolAddress,
        address _collateralAddress
    ) EbtcBase(_activePoolAddress, _priceFeedAddress, _collateralAddress) {
        cdpManager = ICdpManager(_cdpManagerAddress);
        sortedCdps = ISortedCdps(_sortedCdpsAddress);
    }

    /// @notice Get first N batch of liquidatable Cdps at current price, starting at lowest ICR
    /// @dev Non-view function that updates and returns live price at execution time
    /// @param _n Number of Cdps to retrieve
    /// @return _array Array of CDP IDs to batch liquidate
    function sequenceLiqToBatchLiq(uint256 _n) external returns (bytes32[] memory _array) {
        uint256 _price = priceFeed.fetchPrice();
        return sequenceLiqToBatchLiqWithPrice(_n, _price);
    }

    /// @notice Get first N batch of liquidatable Cdps at specified price, starting at lowest ICR
    /// @param _n Number of Cdps to retrieve
    /// @param _price stETH/BTC price
    /// @return _array Array of CDP IDs
    function sequenceLiqToBatchLiqWithPrice(
        uint256 _n,
        uint256 _price
    ) public view returns (bytes32[] memory _array) {
        (uint256 _TCR, , ) = _getTCRWithSystemDebtAndCollShares(_price);
        bool _recoveryModeAtStart = _TCR < CCR ? true : false;
        return _sequenceLiqToBatchLiq(_n, _recoveryModeAtStart, _price);
    }

    /// @notice Returns array of liquidatable CDP ids
    /// @param _n Number of Cdps to retrieve
    /// @param _recoveryModeAtStart Initial recovery mode state
    /// @param _price stETH/BTC price
    /// @return _array Array of CDP IDs for batch liquidation (in NICR-decreasing order, same as SortedCdps)
    function _sequenceLiqToBatchLiq(
        uint256 _n,
        bool _recoveryModeAtStart,
        uint256 _price
    ) internal view returns (bytes32[] memory _array) {
        if (_n > 0) {
            bytes32 _last = sortedCdps.getLast();
            bytes32 _first = sortedCdps.getFirst();
            bytes32 _cdpId = _last;

            uint256 _TCR = cdpManager.getSyncedTCR(_price);

            // get count of liquidatable Cdps
            uint256 _cnt;
            for (uint256 i = 0; i < _n && _cdpId != _first; ++i) {
                uint256 _icr = cdpManager.getSyncedICR(_cdpId, _price); /// @audit This is view ICR and not real ICR
                uint256 _cdpStatus = cdpManager.getCdpStatus(_cdpId);
                bool _liquidatable = _canLiquidateInCurrentMode(_recoveryModeAtStart, _icr, _TCR);
                if (_liquidatable && _cdpStatus == 1) {
                    _cnt += 1;
                }
                _cdpId = sortedCdps.getPrev(_cdpId);
            }

            // retrieve liquidatable Cdps
            _array = new bytes32[](_cnt);
            _cdpId = _last;
            uint256 _j;
            for (uint256 i = 0; i < _n && _cdpId != _first; ++i) {
                uint256 _icr = cdpManager.getSyncedICR(_cdpId, _price);
                uint256 _cdpStatus = cdpManager.getCdpStatus(_cdpId);
                bool _liquidatable = _canLiquidateInCurrentMode(_recoveryModeAtStart, _icr, _TCR);
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

    /// @notice Internal helper function to check if given ICR value can be liquidated in current mode
    /// @dev Assumes correct input values
    /// @param _recovery Current recovery mode state
    /// @param _icr CDP's current ICR
    /// @param _TCR Current total system collateralization ratio
    /// @return True if liquidatable
    function _canLiquidateInCurrentMode(
        bool _recovery,
        uint256 _icr,
        uint256 _TCR
    ) internal view returns (bool) {
        bool _liquidatable = _recovery ? (_icr < MCR || _icr <= _TCR) : _icr < MCR;

        return _liquidatable;
    }
}
