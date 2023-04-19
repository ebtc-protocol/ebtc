// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../CollSurplusPool.sol";

contract CollSurplusPoolTester is CollSurplusPool {
    using SafeMath for uint256;
    bytes4 public constant FUNC_SIG1 = 0xe90a182f; //sweepToken(address,uint256)

    function unprotectedReceiveColl(uint _amount) external {
        StEthColl = StEthColl.add(_amount);
    }

    function initAuthority(address _initAuthority) external {
        _initializeAuthority(_initAuthority);
    }

    // dummy test functions for sweepToken()
    function balanceOf(address account) external view returns (uint256) {
        return 1234567890;
    }
}
