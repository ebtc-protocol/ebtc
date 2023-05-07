// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../DefaultPool.sol";

contract DefaultPoolTester is DefaultPool {
    constructor(
        address _cdpManagerAddress,
        address _activePoolAddress,
        address _collTokenAddress
    ) DefaultPool(_cdpManagerAddress, _activePoolAddress, _collTokenAddress) {}

    bytes4 public constant FUNC_SIG1 = 0xe90a182f; //sweepToken(address,uint256)

    function unprotectedIncreaseEBTCDebt(uint _amount) external {
        EBTCDebt = EBTCDebt + _amount;
    }

    function unprotectedReceiveColl(uint _amount) external {
        StEthColl = StEthColl + _amount;
    }

    function initAuthority(address _initAuthority) external {
        _initializeAuthority(_initAuthority);
    }

    // dummy test functions for sweepToken()
    function balanceOf(address account) external view returns (uint256) {
        return 1234567890;
    }
}
