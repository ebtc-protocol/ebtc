// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../DefaultPool.sol";

contract DefaultPoolTester is DefaultPool {

    constructor(
        address _cdpManagerAddress,
        address _activePoolAddress,
        address _collTokenAddress
    ) DefaultPool(_cdpManagerAddress, _activePoolAddress, _collTokenAddress) {}

    function unprotectedIncreaseEBTCDebt(uint _amount) external {
        EBTCDebt = EBTCDebt + _amount;
    }

    function unprotectedReceiveColl(uint _amount) external {
        StEthColl = StEthColl + _amount;
    }
}
