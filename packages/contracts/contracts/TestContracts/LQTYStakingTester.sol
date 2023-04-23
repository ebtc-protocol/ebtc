// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../LQTY/FeeRecipient.sol";

contract LQTYStakingTester is FeeRecipient {
    constructor(
        address _ebtcTokenAddress,
        address _cdpManagerAddress,
        address _borrowerOperationsAddress,
        address _activePoolAddress,
        address _collTokenAddress
    )
        FeeRecipient(
            _ebtcTokenAddress,
            _cdpManagerAddress,
            _borrowerOperationsAddress,
            _activePoolAddress,
            _collTokenAddress
        )
    {}

    function requireCallerIsCdpManager() external view {
        _requireCallerIsCdpManager();
    }
}
