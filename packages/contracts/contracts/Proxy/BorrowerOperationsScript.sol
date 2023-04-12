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
        uint _EBTCAmount,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint _collAmount
    ) external {
        borrowerOperations.openCdp(_EBTCAmount, _upperHint, _lowerHint, _collAmount);
    }

    function addColl(
        bytes32 _cdpId,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint _collAmount
    ) external {
        borrowerOperations.addColl(_cdpId, _upperHint, _lowerHint, _collAmount);
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
        uint _amount,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external {
        borrowerOperations.withdrawEBTC(_cdpId, _amount, _upperHint, _lowerHint);
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
        uint _collWithdrawal,
        uint _debtChange,
        bool isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external {
        borrowerOperations.adjustCdp(
            _cdpId,
            _collWithdrawal,
            _debtChange,
            isDebtIncrease,
            _upperHint,
            _lowerHint
        );
    }

    function adjustCdpWithColl(
        bytes32 _cdpId,
        uint _collWithdrawal,
        uint _debtChange,
        bool isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint _collAmount
    ) external {
        borrowerOperations.adjustCdpWithColl(
            _cdpId,
            _collWithdrawal,
            _debtChange,
            isDebtIncrease,
            _upperHint,
            _lowerHint,
            _collAmount
        );
    }

    function claimCollateral() external {
        borrowerOperations.claimCollateral();
    }
}
