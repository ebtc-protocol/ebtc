// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "../DefaultPool.sol";

contract DefaultPoolTester is DefaultPool {
    using SafeMath for uint256;

    function unprotectedIncreaseEBTCDebt(uint _amount) external {
        EBTCDebt = EBTCDebt.add(_amount);
    }

    function unprotectedReceiveColl(uint _amount) external {
        ETH = ETH.add(_amount);
    }
}
