// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../CollSurplusPool.sol";

contract CollSurplusPoolTester is CollSurplusPool {
    bytes4 public constant FUNC_SIG1 = 0xe90a182f; //sweepToken(address,uint256)

    constructor(
        address _borrowerOperationsAddress,
        address _cdpManagerAddress,
        address _activePoolAddress,
        address _collTokenAddress
    )
        CollSurplusPool(
            _borrowerOperationsAddress,
            _cdpManagerAddress,
            _activePoolAddress,
            _collTokenAddress
        )
    {}

    function unprotectedReceiveColl(uint256 _amount) external {
        totalSurplusCollShares = totalSurplusCollShares + _amount;
    }

    // dummy test functions for sweepToken()
    function balanceOf(address account) external view returns (uint256) {
        return 1234567890;
    }
}
