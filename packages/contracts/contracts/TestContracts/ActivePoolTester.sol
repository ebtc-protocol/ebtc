// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../ActivePool.sol";

contract ActivePoolTester is ActivePool {
    constructor(
        address _borrowerOperationsAddress,
        address _cdpManagerAddress,
        address _collTokenAddress,
        address _collSurplusAddress,
        address _feeRecipientAddress
    )
        ActivePool(
            _borrowerOperationsAddress,
            _cdpManagerAddress,
            _collTokenAddress,
            _collSurplusAddress,
            _feeRecipientAddress
        )
    {}

    bytes4 public constant FUNC_SIG1 = 0xe90a182f; //sweepToken(address,uint256)
    bytes4 public constant FUNC_SIG_FL_FEE = 0x72c27b62; //setFeeBps(uint256)
    bytes4 public constant FUNC_SIG_MAX_FL_FEE = 0x246d4569; //setMaxFeeBps(uint256)

    function unprotectedIncreaseEBTCDebt(uint _amount) external {
        EBTCDebt = EBTCDebt + _amount;
    }

    function unprotectedReceiveColl(uint _amount) external {
        StEthColl = StEthColl + _amount;
    }

    function unprotectedAllocateFeeRecipientColl(uint _shares) external {
        StEthColl = StEthColl - _shares;
        FeeRecipientColl = FeeRecipientColl + _shares;

        emit ActivePoolCollBalanceUpdated(StEthColl);
        emit ActivePoolFeeRecipientClaimableCollUpdated(FeeRecipientColl);
    }

    // dummy test functions for sweepToken()
    function balanceOf(address account) external view returns (uint256) {
        return 1234567890;
    }
}
