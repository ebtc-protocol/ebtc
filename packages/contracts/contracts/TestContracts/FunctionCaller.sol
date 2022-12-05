// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import '../Interfaces/ITroveManager.sol';
import '../Interfaces/ISortedTroves.sol';
import '../Interfaces/IPriceFeed.sol';
import '../Dependencies/LiquityMath.sol';

/* Wrapper contract - used for calculating gas of read-only and internal functions. 
Not part of the Liquity application. */
contract FunctionCaller {

    ITroveManager cdpManager;
    address public cdpManagerAddress;

    ISortedTroves sortedTroves;
    address public sortedTrovesAddress;

    IPriceFeed priceFeed;
    address public priceFeedAddress;

    // --- Dependency setters ---

    function setTroveManagerAddress(address _cdpManagerAddress) external {
        cdpManagerAddress = _cdpManagerAddress;
        cdpManager = ITroveManager(_cdpManagerAddress);
    }
    
    function setSortedTrovesAddress(address _sortedTrovesAddress) external {
        cdpManagerAddress = _sortedTrovesAddress;
        sortedTroves = ISortedTroves(_sortedTrovesAddress);
    }

     function setPriceFeedAddress(address _priceFeedAddress) external {
        priceFeedAddress = _priceFeedAddress;
        priceFeed = IPriceFeed(_priceFeedAddress);
    }

    // --- Non-view wrapper functions used for calculating gas ---
    
    function cdpManager_getCurrentICR(bytes32 _cdpId, uint _price) external returns (uint) {
        return cdpManager.getCurrentICR(_cdpId, _price);  
    }

    function sortedTroves_findInsertPosition(uint _NICR, bytes32 _prevId, bytes32 _nextId) external returns (bytes32, bytes32) {
        return sortedTroves.findInsertPosition(_NICR, _prevId, _nextId);
    }
}
