// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../CdpManager.sol";
import "../BorrowerOperations.sol";
import "../ActivePool.sol";
import "./CollateralTokenTester.sol";
import "./testnet/PriceFeedTestnet.sol";
import "./EBTCTokenTester.sol";
import "../Interfaces/IERC3156FlashBorrower.sol";
import "../Dependencies/IERC20.sol";

contract EchidnaProxy is IERC3156FlashBorrower {
    CdpManager cdpManager;
    BorrowerOperations borrowerOperations;
    EBTCTokenTester ebtcToken;
    CollateralTokenTester collateral;
    ActivePool activePool;
    PriceFeedTestnet priceFeed;

    constructor(
        CdpManager _cdpManager,
        BorrowerOperations _borrowerOperations,
        EBTCTokenTester _ebtcToken,
        CollateralTokenTester _collateral,
        ActivePool _activePool,
        PriceFeedTestnet _priceFeed
    ) payable {
        cdpManager = _cdpManager;
        borrowerOperations = _borrowerOperations;
        ebtcToken = _ebtcToken;
        collateral = _collateral;
        activePool = _activePool;
        priceFeed = _priceFeed;

        collateral.approve(address(borrowerOperations), type(uint256).max);
    }

    receive() external payable {
        // do nothing
    }

    // helper functions
    function _ensureNoLiquidationTriggered(bytes32 _cdpId) internal view {
        uint _price = priceFeed.getPrice();
        if (_price > 0) {
            bool _recovery = cdpManager.checkRecoveryMode(_price);
            uint _icr = cdpManager.getICR(_cdpId, _price);
            if (_recovery) {
                require(_icr > cdpManager.getTCR(_price), "liquidationTriggeredInRecoveryMode");
            } else {
                require(_icr > cdpManager.MCR(), "liquidationTriggeredInNormalMode");
            }
        }
    }

    function _ensureNoRecoveryModeTriggered() internal view {
        uint _price = priceFeed.getPrice();
        if (_price > 0) {
            require(!cdpManager.checkRecoveryMode(_price), "!recoveryModeTriggered");
        }
    }

    function _ensureMinCollInCdp(bytes32 _cdpId) internal view {
        uint _collWorth = collateral.getPooledEthByShares(cdpManager.getCdpCollShares(_cdpId));
        require(_collWorth < cdpManager.MIN_NET_COLL(), "!minimum CDP collateral");
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

    // ActivePool

    function flashloanColl(uint _amount) external {
        require(_amount < activePool.maxFlashLoan(address(collateral)), "!tooMuchCollToFL");

        // sugardaddy fee
        uint _fee = activePool.flashFee(address(collateral), _amount);
        require(_fee < address(this).balance, "!tooMuchFeeCollFL");
        collateral.deposit{value: _fee}();

        // take the flashloan which should always cost the fee paid by caller
        uint _balBefore = collateral.balanceOf(activePool.feeRecipientAddress());
        activePool.flashLoan(
            IERC3156FlashBorrower(address(this)),
            address(collateral),
            _amount,
            abi.encodePacked(uint256(0))
        );
        uint _balAfter = collateral.balanceOf(activePool.feeRecipientAddress());
        require(_balAfter - _balBefore == _fee, "!flFeeColl");
    }

    // Borrower Operations

    function flashloanEBTC(uint _amount) external {
        require(_amount < borrowerOperations.maxFlashLoan(address(ebtcToken)), "!tooMuchEBTCToFL");

        // sugardaddy fee
        uint _fee = borrowerOperations.flashFee(address(ebtcToken), _amount);
        ebtcToken.unprotectedMint(address(this), _fee);

        // take the flashloan which should always cost the fee paid by caller
        uint _balBefore = ebtcToken.balanceOf(borrowerOperations.feeRecipientAddress());
        borrowerOperations.flashLoan(
            IERC3156FlashBorrower(address(this)),
            address(ebtcToken),
            _amount,
            abi.encodePacked(uint256(0))
        );
        uint _balAfter = ebtcToken.balanceOf(borrowerOperations.feeRecipientAddress());
        require(_balAfter - _balBefore == _fee, "!flFeeEBTC");
        ebtcToken.unprotectedBurn(borrowerOperations.feeRecipientAddress(), _fee);
    }

    function openCdpPrx(
        uint _coll,
        uint _EBTCAmount,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external {
        bytes32 _cdpId = borrowerOperations.openCdp(_EBTCAmount, _upperHint, _lowerHint, _coll);
        _ensureNoLiquidationTriggered(_cdpId);
        _ensureNoRecoveryModeTriggered();
        _ensureMinCollInCdp(_cdpId);
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
        _ensureNoLiquidationTriggered(_cdpId);
        _ensureNoRecoveryModeTriggered();
    }

    function withdrawEBTCPrx(
        bytes32 _cdpId,
        uint _amount,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external {
        borrowerOperations.withdrawEBTC(_cdpId, _amount, _upperHint, _lowerHint);
        _ensureNoLiquidationTriggered(_cdpId);
        _ensureNoRecoveryModeTriggered();
    }

    function repayEBTCPrx(
        bytes32 _cdpId,
        uint _amount,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external {
        if (_amount > 0) {
            uint _price = priceFeed.fetchPrice();
            uint _tcrBefore = cdpManager.getTCR(_price);
            borrowerOperations.repayEBTC(_cdpId, _amount, _upperHint, _lowerHint);
            uint _tcrAfter = cdpManager.getTCR(_price);
            require(_tcrAfter > _tcrBefore, "!tcrAfterRepay");
        }
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
        bytes32 _lowerHint
    ) external {
        borrowerOperations.adjustCdp(
            _cdpId,
            _collWithdrawal,
            _debtChange,
            _isDebtIncrease,
            _upperHint,
            _lowerHint
        );
        if (_collWithdrawal > 0 || _isDebtIncrease) {
            _ensureNoLiquidationTriggered(_cdpId);
            _ensureNoRecoveryModeTriggered();
        }
    }

    function adjustCdpWithCollPrx(
        bytes32 _cdpId,
        uint _collAddAmount,
        uint _collWithdrawal,
        uint _debtChange,
        bool _isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external {
        borrowerOperations.adjustCdpWithColl(
            _cdpId,
            _collWithdrawal,
            _debtChange,
            _isDebtIncrease,
            _upperHint,
            _lowerHint,
            _collAddAmount
        );
        if (_collWithdrawal > 0 || _isDebtIncrease) {
            _ensureNoLiquidationTriggered(_cdpId);
            _ensureNoRecoveryModeTriggered();
        }
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

    // callback for flashloan
    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external override returns (bytes32) {
        if (token == address(ebtcToken)) {
            require(msg.sender == address(borrowerOperations), "!borrowerOperationsFLSender");
        } else {
            require(msg.sender == address(activePool), "!activePoolFLSender");
        }

        IERC20(token).approve(msg.sender, amount + fee);
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}
