// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "../Dependencies/CheckContract.sol";
import "../Interfaces/IBorrowerOperations.sol";


contract BorrowerOperationsScript is CheckContract {
    IBorrowerOperations immutable borrowerOperations;

    constructor(IBorrowerOperations _borrowerOperations) public {
        checkContract(address(_borrowerOperations));
        borrowerOperations = _borrowerOperations;
    }

    function openTrove(uint _maxFee, uint _EBTCAmount, bytes32 _upperHint, bytes32 _lowerHint) external payable {
        borrowerOperations.openTrove{ value: msg.value }(_maxFee, _EBTCAmount, _upperHint, _lowerHint);
    }

    function addColl(bytes32 _troveId, bytes32 _upperHint, bytes32 _lowerHint) external payable {
        borrowerOperations.addColl{ value: msg.value }(_troveId, _upperHint, _lowerHint);
    }

    function withdrawColl(bytes32 _troveId, uint _amount, bytes32 _upperHint, bytes32 _lowerHint) external {
        borrowerOperations.withdrawColl(_troveId, _amount, _upperHint, _lowerHint);
    }

    function withdrawEBTC(bytes32 _troveId, uint _maxFee, uint _amount, bytes32 _upperHint, bytes32 _lowerHint) external {
        borrowerOperations.withdrawEBTC(_troveId, _maxFee, _amount, _upperHint, _lowerHint);
    }

    function repayEBTC(bytes32 _troveId, uint _amount, bytes32 _upperHint, bytes32 _lowerHint) external {
        borrowerOperations.repayEBTC(_troveId, _amount, _upperHint, _lowerHint);
    }

    function closeTrove(bytes32 _troveId) external {
        borrowerOperations.closeTrove(_troveId);
    }

    function adjustTrove(bytes32 _troveId, uint _maxFee, uint _collWithdrawal, uint _debtChange, bool isDebtIncrease, bytes32 _upperHint, bytes32 _lowerHint) external payable {
        borrowerOperations.adjustTrove{ value: msg.value }(_troveId, _maxFee, _collWithdrawal, _debtChange, isDebtIncrease, _upperHint, _lowerHint);
    }

    function claimCollateral() external {
        borrowerOperations.claimCollateral();
    }
}
