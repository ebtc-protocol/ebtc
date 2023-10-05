// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../Interfaces/IBorrowerOperations.sol";

contract BorrowerOperationsScript {
    IBorrowerOperations immutable borrowerOperations;

    constructor(IBorrowerOperations _borrowerOperations) public {
        borrowerOperations = _borrowerOperations;
    }

    function openCdp(
        uint256 _EBTCAmount,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthBalance
    ) external {
        borrowerOperations.openCdp(_EBTCAmount, _upperHint, _lowerHint, _stEthBalance);
    }

    function addColl(
        bytes32 _cdpId,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthBalanceIncrease
    ) external {
        borrowerOperations.addColl(_cdpId, _upperHint, _lowerHint, _stEthBalanceIncrease);
    }

    function withdrawColl(
        bytes32 _cdpId,
        uint256 _stEthBalanceDecrease,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external {
        borrowerOperations.withdrawColl(_cdpId, _stEthBalanceDecrease, _upperHint, _lowerHint);
    }

    function withdrawDebt(
        bytes32 _cdpId,
        uint256 _amount,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external {
        borrowerOperations.withdrawDebt(_cdpId, _amount, _upperHint, _lowerHint);
    }

    function repayDebt(
        bytes32 _cdpId,
        uint256 _amount,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external {
        borrowerOperations.repayDebt(_cdpId, _amount, _upperHint, _lowerHint);
    }

    function closeCdp(bytes32 _cdpId) external {
        borrowerOperations.closeCdp(_cdpId);
    }

    function adjustCdp(
        bytes32 _cdpId,
        uint256 _stEthBalanceDecrease,
        uint256 _debtChange,
        bool isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external {
        borrowerOperations.adjustCdp(
            _cdpId,
            _stEthBalanceDecrease,
            _debtChange,
            isDebtIncrease,
            _upperHint,
            _lowerHint
        );
    }

    function adjustCdpWithColl(
        bytes32 _cdpId,
        uint256 _stEthBalanceDecrease,
        uint256 _debtChange,
        bool isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthBalanceIncrease
    ) external {
        borrowerOperations.adjustCdpWithColl(
            _cdpId,
            _stEthBalanceDecrease,
            _debtChange,
            isDebtIncrease,
            _upperHint,
            _lowerHint,
            _stEthBalanceIncrease
        );
    }

    function claimSurplusCollShares() external {
        borrowerOperations.claimSurplusCollShares();
    }
}
