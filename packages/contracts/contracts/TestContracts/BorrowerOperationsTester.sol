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
        uint256 _coll,
        uint256 _debt,
        uint256 _collChange,
        bool isCollIncrease,
        uint256 _debtChange,
        bool isDebtIncrease,
        uint256 _price
    ) external view returns (uint256) {
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
        uint256 _collChange,
        bool isCollIncrease,
        uint256 _debtChange,
        bool isDebtIncrease,
        uint256 _price
    ) external view returns (uint256) {
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
        uint256 _collWithdrawal,
        uint256 _debtChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint
    ) external {
        //_adjustCdp(_borrower, _collWithdrawal, _debtChange, _isDebtIncrease, _upperHint, _lowerHint, 0);
    }

    function unprotectedActivePoolReceiveColl(uint256 _amt) external {
        activePool.increaseSystemCollShares(_amt);
    }

    // Payable fallback function
    receive() external payable {}
}
