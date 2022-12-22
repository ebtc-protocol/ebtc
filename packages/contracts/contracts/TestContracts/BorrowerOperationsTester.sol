// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "../BorrowerOperations.sol";

/* Tester contract inherits from BorrowerOperations, and provides external functions 
for testing the parent's internal functions. */
contract BorrowerOperationsTester is BorrowerOperations {
    function getNewICRFromCdpChange(
        uint _coll,
        uint _debt,
        uint _collChange,
        bool isCollIncrease,
        uint _debtChange,
        bool isDebtIncrease,
        uint _price
    ) external pure returns (uint) {
        return
            _getNewICRFromCdpChange(
                _coll,
                _debt,
                _collChange,
                isCollIncrease,
                _debtChange,
                isDebtIncrease,
                _price
            );
    }

    function getNewTCRFromCdpChange(
        uint _collChange,
        bool isCollIncrease,
        uint _debtChange,
        bool isDebtIncrease,
        uint _price
    ) external view returns (uint) {
        return
            _getNewTCRFromCdpChange(
                _collChange,
                isCollIncrease,
                _debtChange,
                isDebtIncrease,
                _price
            );
    }

    function getUSDValue(uint _coll, uint _price) external pure returns (uint) {
        return _getUSDValue(_coll, _price);
    }

    function callInternalAdjustLoan(
        address _borrower,
        uint _collWithdrawal,
        uint _debtChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint
    ) external {
        //_adjustCdp(_borrower, _collWithdrawal, _debtChange, _isDebtIncrease, _upperHint, _lowerHint, 0);
    }

    // Set interest rate as 0 for js tests
    function _calcUnitAmountAfterInterest(uint) internal pure override returns (uint) {
        return DECIMAL_PRECISION;
    }

    // Payable fallback function
    receive() external payable {}
}
