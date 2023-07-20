// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../BorrowerOperations.sol";

/* Tester contract inherits from BorrowerOperations, and provides external functions 
for testing the parent's internal functions. */
contract BorrowerOperationsTester is BorrowerOperations {
    constructor(
        address _cdpManagerAddress,
        address _activePoolAddress,
        address _collSurplusPoolAddress,
        address _priceFeedAddress,
        address _sortedCdpsAddress,
        address _ebtcTokenAddress,
        address _feeRecipientAddress,
        address _collTokenAddress
    )
        BorrowerOperations(
            _cdpManagerAddress,
            _activePoolAddress,
            _collSurplusPoolAddress,
            _priceFeedAddress,
            _sortedCdpsAddress,
            _ebtcTokenAddress,
            _feeRecipientAddress,
            _collTokenAddress
        )
    {}

    bytes4 public constant FUNC_SIG_FL_FEE = 0x72c27b62; //setFeeBps(uint256)
    bytes4 public constant FUNC_SIG_MAX_FL_FEE = 0x246d4569; //setMaxFeeBps(uint256)

    function getNewICRFromCdpChange(
        uint _coll,
        uint _debt,
        uint _collChange,
        bool isCollIncrease,
        uint _debtChange,
        bool isDebtIncrease,
        uint _price
    ) external view returns (uint) {
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

    function unprotectedActivePoolReceiveColl(uint _amt) external {
        activePool.receiveColl(_amt);
    }

    // Payable fallback function
    receive() external payable {}
}
