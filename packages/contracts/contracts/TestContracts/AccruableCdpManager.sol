// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../CdpManager.sol";

contract AccruableCdpManager is CdpManager {
    constructor(
        address _liquidationLibraryAddress,
        address _authorityAddress,
        address _borrowerOperationsAddress,
        address _collSurplusPoolAddress,
        address _ebtcTokenAddress,
        address _sortedCdpsAddress,
        address _activePoolAddress,
        address _priceFeedAddress,
        address _collTokenAddress
    )
        CdpManager(
            _liquidationLibraryAddress,
            _authorityAddress,
            _borrowerOperationsAddress,
            _collSurplusPoolAddress,
            _ebtcTokenAddress,
            _sortedCdpsAddress,
            _activePoolAddress,
            _priceFeedAddress,
            _collTokenAddress
        )
    {
        /// @audit Based on the idea that Foundry and Echidna will not fork mainnet
        // require(block.chainid != 1, "No prod!!!!"); /// @audit CANNOT SET, PLS HAAAALP
    }

    function syncGlobalAccountingInternal() external {
        _syncGlobalAccounting();
    }

    function syncAccounting(bytes32 _cdpId) external virtual override {
        return _syncAccounting(_cdpId);
    }
}
