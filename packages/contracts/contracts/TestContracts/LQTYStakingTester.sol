// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "../LQTY/FeeRecipient.sol";

contract LQTYStakingTester is FeeRecipient {
    function requireCallerIsCdpManager() external view {
        _requireCallerIsCdpManager();
    }
}
