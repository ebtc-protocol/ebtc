// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "../CdpManager.sol";
import "../BorrowerOperations.sol";
import "../EBTCToken.sol";
import "./CollateralTokenTester.sol";

contract EchidnaProxy {
    CdpManager cdpManager;
    BorrowerOperations borrowerOperations;
    EBTCToken ebtcToken;
    CollateralTokenTester collateral;

    constructor(
        CdpManager _cdpManager,
        BorrowerOperations _borrowerOperations,
        EBTCToken _ebtcToken,
        CollateralTokenTester _collateral
    ) public payable {
        cdpManager = _cdpManager;
        borrowerOperations = _borrowerOperations;
        ebtcToken = _ebtcToken;
        collateral = _collateral;
        collateral.approve(address(borrowerOperations), type(uint256).max);
    }

    receive() external payable {
        // do nothing
    }

    // CdpManager

    function liquidatePrx(bytes32 _cdpId) external {
        cdpManager.liquidate(_cdpId);
    }

    function partialLiquidatePrx(bytes32 _cdpId, uint _partialAmount) external {
        cdpManager.partiallyLiquidate(_cdpId, _partialAmount, _cdpId, _cdpId);
    }

    function liquidateCdpsPrx(uint _n) external {
        cdpManager.liquidateCdps(_n);
    }

    function batchLiquidateCdpsPrx(bytes32[] calldata _cdpIdArray) external {
        cdpManager.batchLiquidateCdps(_cdpIdArray);
    }

    function redeemCollateralPrx(
        uint _EBTCAmount,
        bytes32 _firstRedemptionHint,
        bytes32 _upperPartialRedemptionHint,
        bytes32 _lowerPartialRedemptionHint,
        uint _partialRedemptionHintNICR,
        uint _maxIterations,
        uint _maxFee
    ) external {
        cdpManager.redeemCollateral(
            _EBTCAmount,
            _firstRedemptionHint,
            _upperPartialRedemptionHint,
            _lowerPartialRedemptionHint,
            _partialRedemptionHintNICR,
            _maxIterations,
            _maxFee
        );
    }

    // Borrower Operations
    function openCdpPrx(
        uint _coll,
        uint _EBTCAmount,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint _maxFee
    ) external {
        borrowerOperations.openCdp(_maxFee, _EBTCAmount, _upperHint, _lowerHint, _coll);
    }

    function addCollPrx(
        bytes32 _cdpId,
        uint _coll,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external {
        borrowerOperations.addColl(_cdpId, _upperHint, _lowerHint, _coll);
    }

    function withdrawCollPrx(
        bytes32 _cdpId,
        uint _amount,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external {
        borrowerOperations.withdrawColl(_cdpId, _amount, _upperHint, _lowerHint);
    }

    function withdrawEBTCPrx(
        bytes32 _cdpId,
        uint _amount,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint _maxFee
    ) external {
        borrowerOperations.withdrawEBTC(_cdpId, _maxFee, _amount, _upperHint, _lowerHint);
    }

    function repayEBTCPrx(
        bytes32 _cdpId,
        uint _amount,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external {
        borrowerOperations.repayEBTC(_cdpId, _amount, _upperHint, _lowerHint);
    }

    function closeCdpPrx(bytes32 _cdpId) external {
        borrowerOperations.closeCdp(_cdpId);
    }

    function adjustCdpPrx(
        bytes32 _cdpId,
        uint _collWithdrawal,
        uint _debtChange,
        bool _isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint _maxFee
    ) external {
        borrowerOperations.adjustCdp(
            _cdpId,
            _maxFee,
            _collWithdrawal,
            _debtChange,
            _isDebtIncrease,
            _upperHint,
            _lowerHint
        );
    }

    function adjustCdpWithCollPrx(
        bytes32 _cdpId,
        uint _collAddAmount,
        uint _collWithdrawal,
        uint _debtChange,
        bool _isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint _maxFee
    ) external {
        borrowerOperations.adjustCdpWithColl(
            _cdpId,
            _maxFee,
            _collWithdrawal,
            _debtChange,
            _isDebtIncrease,
            _upperHint,
            _lowerHint,
            _collAddAmount
        );
    }

    // EBTC Token

    function transferPrx(address recipient, uint256 amount) external returns (bool) {
        return ebtcToken.transfer(recipient, amount);
    }

    function approvePrx(address spender, uint256 amount) external returns (bool) {
        return ebtcToken.approve(spender, amount);
    }

    function transferFromPrx(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool) {
        return ebtcToken.transferFrom(sender, recipient, amount);
    }

    function increaseAllowancePrx(address spender, uint256 addedValue) external returns (bool) {
        return ebtcToken.increaseAllowance(spender, addedValue);
    }

    function decreaseAllowancePrx(address spender, uint256 subtractedValue) external returns (bool) {
        return ebtcToken.decreaseAllowance(spender, subtractedValue);
    }

    // Collateral
    function dealCollateral(uint _amount) public returns (uint) {
        uint _balBefore = collateral.balanceOf(address(this));

        collateral.deposit{value: _amount}();

        uint _balAfter = collateral.balanceOf(address(this));
        return _balAfter - _balBefore;
    }
}
