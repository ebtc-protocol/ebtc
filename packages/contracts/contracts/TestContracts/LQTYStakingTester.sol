// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "../LQTY/FeeRecipient.sol";

contract LQTYStakingTester is FeeRecipient {
    function requireCallerIsCdpManager() external view {
        _requireCallerIsCdpManager();
    }
}
