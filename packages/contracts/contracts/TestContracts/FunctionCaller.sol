// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../Interfaces/ICdpManager.sol";
import "../Interfaces/ISortedCdps.sol";
import "../Interfaces/IPriceFeed.sol";
import "../Dependencies/EbtcMath.sol";

/* Wrapper contract - used for calculating gas of read-only and internal functions. 
Not part of the Liquity application. */
contract FunctionCaller {
    ICdpManager cdpManager;
    address public cdpManagerAddress;

    ISortedCdps sortedCdps;
    address public sortedCdpsAddress;

    IPriceFeed priceFeed;
    address public priceFeedAddress;

    // --- Dependency setters ---

    function setCdpManagerAddress(address _cdpManagerAddress) external {
        cdpManagerAddress = _cdpManagerAddress;
        cdpManager = ICdpManager(_cdpManagerAddress);
    }

    function setSortedCdpsAddress(address _sortedCdpsAddress) external {
        cdpManagerAddress = _sortedCdpsAddress;
        sortedCdps = ISortedCdps(_sortedCdpsAddress);
    }

    function setPriceFeedAddress(address _priceFeedAddress) external {
        priceFeedAddress = _priceFeedAddress;
        priceFeed = IPriceFeed(_priceFeedAddress);
    }

    // --- Non-view wrapper functions used for calculating gas ---

    function cdpManager_getCachedICR(
        bytes32 _cdpId,
        uint256 _price
    ) external view returns (uint256) {
        return cdpManager.getCachedICR(_cdpId, _price);
    }

    function sortedCdps_findInsertPosition(
        uint256 _NICR,
        bytes32 _prevId,
        bytes32 _nextId
    ) external view returns (bytes32, bytes32) {
        return sortedCdps.findInsertPosition(_NICR, _prevId, _nextId);
    }
}
