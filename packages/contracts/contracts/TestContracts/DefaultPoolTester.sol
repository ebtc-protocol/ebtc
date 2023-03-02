// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "../DefaultPool.sol";

contract DefaultPoolTester is DefaultPool {
    function unprotectedIncreaseEBTCDebt(uint _amount) external {
        EBTCDebt = EBTCDebt.add(_amount);
    }

    function unprotectedReceiveColl(uint _amount) external {
        ETH = ETH.add(_amount);
    }
}
