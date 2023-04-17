// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../ActivePool.sol";

contract ActivePoolTester is ActivePool {
    bytes4 public constant FUNC_SIG1 = 0xe90a182f; //sweepToken(address,uint256)

    constructor() public ActivePool() {}

    function unprotectedIncreaseEBTCDebt(uint _amount) external {
        EBTCDebt = EBTCDebt + _amount;
    }

    function unprotectedReceiveColl(uint _amount) external {
        StEthColl = StEthColl + _amount;
    }

    function initAuthority(address _initAuthority) external {
        _initializeAuthority(_initAuthority);
    }
}
