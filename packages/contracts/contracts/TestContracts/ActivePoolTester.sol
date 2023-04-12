// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "../ActivePool.sol";

contract ActivePoolTester is ActivePool {
    constructor() public ActivePool() {}

    function unprotectedIncreaseEBTCDebt(uint _amount) external {
        EBTCDebt = EBTCDebt + _amount;
    }

    function unprotectedReceiveColl(uint _amount) external {
        StEthColl = StEthColl + _amount;
    }
}
