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

    function openCdp(
        uint _maxFee,
        uint _EBTCAmount,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external payable {
        borrowerOperations.openCdp{value: msg.value}(_maxFee, _EBTCAmount, _upperHint, _lowerHint);
    }

    function addColl(bytes32 _cdpId, bytes32 _upperHint, bytes32 _lowerHint) external payable {
        borrowerOperations.addColl{value: msg.value}(_cdpId, _upperHint, _lowerHint);
    }

    function withdrawColl(
        bytes32 _cdpId,
        uint _amount,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external {
        borrowerOperations.withdrawColl(_cdpId, _amount, _upperHint, _lowerHint);
    }

    function withdrawEBTC(
        bytes32 _cdpId,
        uint _maxFee,
        uint _amount,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external {
        borrowerOperations.withdrawEBTC(_cdpId, _maxFee, _amount, _upperHint, _lowerHint);
    }

    function repayEBTC(
        bytes32 _cdpId,
        uint _amount,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external {
        borrowerOperations.repayEBTC(_cdpId, _amount, _upperHint, _lowerHint);
    }

    function closeCdp(bytes32 _cdpId) external {
        borrowerOperations.closeCdp(_cdpId);
    }

    function adjustCdp(
        bytes32 _cdpId,
        uint _maxFee,
        uint _collWithdrawal,
        uint _debtChange,
        bool isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external payable {
        borrowerOperations.adjustCdp{value: msg.value}(
            _cdpId,
            _maxFee,
            _collWithdrawal,
            _debtChange,
            isDebtIncrease,
            _upperHint,
            _lowerHint
        );
    }

    function claimCollateral() external {
        borrowerOperations.claimCollateral();
    }
}
