// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./Interfaces/IBorrowerOperations.sol";
import "./Interfaces/ICdpManager.sol";
import "./Interfaces/IEBTCToken.sol";
import "./Interfaces/ICollSurplusPool.sol";
import "./Interfaces/ISortedCdps.sol";
import "./Interfaces/IFeeRecipient.sol";
import "./Dependencies/LiquityBase.sol";
import "./Dependencies/Ownable.sol";
import "./Dependencies/CheckContract.sol";

import "./Dependencies/ERC3156FlashLender.sol";

contract BorrowerOperations is
    LiquityBase,
    Ownable,
    CheckContract,
    IBorrowerOperations,
    ERC3156FlashLender
{
    string public constant NAME = "BorrowerOperations";

    // --- Connected contract declarations ---

    ICdpManager public cdpManager;

    address gasPoolAddress;

    ICollSurplusPool collSurplusPool;

    IFeeRecipient public feeRecipient;
    address public lqtyStakingAddress;

    IEBTCToken public ebtcToken;

    // A doubly linked list of Cdps, sorted by their collateral ratios
    ISortedCdps public sortedCdps;

    /* --- Variable container structs  ---

    Used to hold, return and assign variables inside a function, in order to avoid the error:
    "CompilerError: Stack too deep". */

    struct LocalVariables_adjustCdp {
        uint price;
        uint collChange;
        uint netDebtChange;
        bool isCollIncrease;
        uint debt;
        uint coll;
        uint oldICR;
        uint newICR;
        uint newTCR;
        uint newDebt;
        uint newColl;
        uint stake;
    }

    // struct LocalVariables_openCdp {
    //     uint price;
    //     uint netDebt;
    //     uint compositeDebt;
    //     uint ICR;
    //     uint NICR;
    //     uint stake;
    //     uint arrayIndex;
    // }

    // struct LocalVariables_moveTokens {
    //     address user;
    //     uint collChange;
    //     uint collAddUnderlying; // ONLY for isCollIncrease=true
    //     bool isCollIncrease;
    //     uint EBTCChange;
    //     bool isDebtIncrease;
    //     uint netDebtChange;
    // }

    struct ContractsCache {
        ICdpManager cdpManager;
        IActivePool activePool;
        IEBTCToken ebtcToken;
    }

    // --- Dependency setters ---

    function setAddresses(
        address _cdpManagerAddress,
        address _activePoolAddress,
        address _defaultPoolAddress,
        address _gasPoolAddress,
        address _collSurplusPoolAddress,
        address _priceFeedAddress,
        address _sortedCdpsAddress,
        address _ebtcTokenAddress,
        address _feeRecipientAddress,
        address _collTokenAddress
    ) external override onlyOwner {
        // This makes impossible to open a cdp with zero withdrawn EBTC
        assert(MIN_NET_DEBT > 0);

        checkContract(_cdpManagerAddress);
        checkContract(_activePoolAddress);
        checkContract(_defaultPoolAddress);
        checkContract(_gasPoolAddress);
        checkContract(_collSurplusPoolAddress);
        checkContract(_priceFeedAddress);
        checkContract(_sortedCdpsAddress);
        checkContract(_ebtcTokenAddress);
        checkContract(_feeRecipientAddress);
        checkContract(_collTokenAddress);

        cdpManager = ICdpManager(_cdpManagerAddress);
        activePool = IActivePool(_activePoolAddress);
        defaultPool = IDefaultPool(_defaultPoolAddress);
        gasPoolAddress = _gasPoolAddress;
        collSurplusPool = ICollSurplusPool(_collSurplusPoolAddress);
        priceFeed = IPriceFeed(_priceFeedAddress);
        sortedCdps = ISortedCdps(_sortedCdpsAddress);
        ebtcToken = IEBTCToken(_ebtcTokenAddress);
        lqtyStakingAddress = _feeRecipientAddress;
        feeRecipient = IFeeRecipient(_feeRecipientAddress);
        collateral = ICollateralToken(_collTokenAddress);

        emit CdpManagerAddressChanged(_cdpManagerAddress);
        emit ActivePoolAddressChanged(_activePoolAddress);
        emit DefaultPoolAddressChanged(_defaultPoolAddress);
        emit GasPoolAddressChanged(_gasPoolAddress);
        emit CollSurplusPoolAddressChanged(_collSurplusPoolAddress);
        emit PriceFeedAddressChanged(_priceFeedAddress);
        emit SortedCdpsAddressChanged(_sortedCdpsAddress);
        emit EBTCTokenAddressChanged(_ebtcTokenAddress);
        emit FeeRecipientAddressChanged(_feeRecipientAddress);
        emit CollateralAddressChanged(_collTokenAddress);

        renounceOwnership();
    }

    // --- Borrower Cdp Operations ---

    function openCdp(
        uint _EBTCAmount,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint _collAmount
    ) external override returns (bytes32) {
        require(_collAmount > 0, "BorrowerOps: collateral for CDP is zero");

        ContractsCache memory contractsCache = ContractsCache(cdpManager, activePool, ebtcToken);

        uint256 NICR;
        uint256 _collShareAmt;
        uint256 netDebt;
        uint256 compositeDebt;
        {
            uint256 price = priceFeed.fetchPrice();
            // Reverse ETH/BTC price to BTC/ETH
            bool isRecoveryMode = _checkRecoveryMode(price);

            netDebt = _EBTCAmount;
            _requireAtLeastMinNetDebt(_convertDebtDenominationToEth(netDebt, price));

            // ICR is based on the composite debt, i.e. the requested EBTC amount + EBTC gas comp.
            compositeDebt = _getCompositeDebt(netDebt);
            assert(compositeDebt > 0);

            _collShareAmt = collateral.getSharesByPooledEth(_collAmount);

            uint256 ICR = LiquityMath._computeCR(_collAmount, compositeDebt, price);
            NICR = LiquityMath._computeNominalCR(_collShareAmt, compositeDebt);

            if (isRecoveryMode) {
                _requireICRisAboveCCR(ICR);
            } else {
                _requireICRisAboveMCR(ICR);
                uint newTCR = _getNewTCRFromCdpChange(_collAmount, true, compositeDebt, true, price); // bools: coll increase, debt increase
                _requireNewTCRisAboveCCR(newTCR);
            }
        }

        // Set the cdp struct's properties
        bytes32 _cdpId;
        {
            _cdpId = sortedCdps.insert(msg.sender, NICR, _upperHint, _lowerHint);

            contractsCache.cdpManager.setCdpStatus(_cdpId, 1);
            contractsCache.cdpManager.increaseCdpColl(_cdpId, _collShareAmt);
            contractsCache.cdpManager.increaseCdpDebt(_cdpId, compositeDebt);

            contractsCache.cdpManager.updateCdpRewardSnapshots(_cdpId);
            uint256 stake = contractsCache.cdpManager.updateStakeAndTotalStakes(_cdpId);

            uint256 arrayIndex = contractsCache.cdpManager.addCdpIdToArray(_cdpId);
            emit CdpCreated(_cdpId, msg.sender, arrayIndex);

            emit CdpUpdated(
                _cdpId,
                msg.sender,
                0,
                0,
                compositeDebt,
                _collShareAmt,
                stake,
                BorrowerOperation.openCdp
            );
        }

        {
            // Mint the EBTCAmount to the borrower
            _withdrawEBTC(
                contractsCache.activePool,
                contractsCache.ebtcToken,
                msg.sender,
                _EBTCAmount,
                netDebt
            );
            // Move the EBTC gas compensation to the Gas Pool
            _withdrawEBTC(
                contractsCache.activePool,
                contractsCache.ebtcToken,
                gasPoolAddress,
                EBTC_GAS_COMPENSATION,
                EBTC_GAS_COMPENSATION
            );
        }

        // CEI: Move the collateral to the Active Pool
        _activePoolAddColl(contractsCache.activePool, _collAmount, _collShareAmt);

        return _cdpId;
    }

    // Send ETH as collateral to a cdp
    function addColl(
        bytes32 _cdpId,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint _collAmount
    ) external override {
        _adjustCdp(_cdpId, 0, 0, false, _upperHint, _lowerHint, _collAmount);
    }

    // Withdraw ETH collateral from a cdp
    function withdrawColl(
        bytes32 _cdpId,
        uint _collWithdrawal,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external override {
        _adjustCdp(_cdpId, _collWithdrawal, 0, false, _upperHint, _lowerHint, 0);
    }

    // Withdraw EBTC tokens from a cdp: mint new EBTC tokens to the owner, and increase the cdp's debt accordingly
    function withdrawEBTC(
        bytes32 _cdpId,
        uint _EBTCAmount,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external override {
        _adjustCdp(_cdpId, 0, _EBTCAmount, true, _upperHint, _lowerHint, 0);
    }

    // Repay EBTC tokens to a Cdp: Burn the repaid EBTC tokens, and reduce the cdp's debt accordingly
    function repayEBTC(
        bytes32 _cdpId,
        uint _EBTCAmount,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external override {
        _adjustCdp(_cdpId, 0, _EBTCAmount, false, _upperHint, _lowerHint, 0);
    }

    function adjustCdp(
        bytes32 _cdpId,
        uint _collWithdrawal,
        uint _EBTCChange,
        bool _isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external override {
        _adjustCdp(_cdpId, _collWithdrawal, _EBTCChange, _isDebtIncrease, _upperHint, _lowerHint, 0);
    }

    // TODO optimization candidate
    function adjustCdpWithColl(
        bytes32 _cdpId,
        uint _collWithdrawal,
        uint _EBTCChange,
        bool _isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint _collAddAmount
    ) external override {
        _adjustCdp(
            _cdpId,
            _collWithdrawal,
            _EBTCChange,
            _isDebtIncrease,
            _upperHint,
            _lowerHint,
            _collAddAmount
        );
    }

    function _adjustCdp(
        bytes32 _cdpId,
        uint _collWithdrawal,
        uint _EBTCChange,
        bool _isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint _collAddAmount
    ) internal {
        _requireCdpOwner(_cdpId);
        _adjustCdpInternal(
            _cdpId,
            _collWithdrawal,
            _EBTCChange,
            _isDebtIncrease,
            _upperHint,
            _lowerHint,
            _collAddAmount
        );
    }

    /*
     * _adjustCdpInternal(): Alongside a debt change, this function can perform either
     * a collateral top-up or a collateral withdrawal.
     *
     * It therefore expects either a positive _collAddAmount, or a positive _collWithdrawal argument.
     *
     * If both are positive, it will revert.
     */
    function _adjustCdpInternal(
        bytes32 _cdpId,
        uint _collWithdrawal,
        uint _EBTCChange,
        bool _isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint _collAddAmount
    ) internal {
        ContractsCache memory contractsCache = ContractsCache(cdpManager, activePool, ebtcToken);
        LocalVariables_adjustCdp memory vars;

        _requireCdpisActive(contractsCache.cdpManager, _cdpId);

        vars.price = priceFeed.fetchPrice();
        // Reversed BTC/ETH price
        bool isRecoveryMode = _checkRecoveryMode(vars.price);

        if (_isDebtIncrease) {
            _requireNonZeroDebtChange(_EBTCChange);
        }
        _requireSingularCollChange(_collAddAmount, _collWithdrawal);
        _requireNonZeroAdjustment(_collAddAmount, _collWithdrawal, _EBTCChange);

        // Confirm the operation is either a borrower adjusting their own cdp,
        // or a pure ETH transfer from the Stability Pool to a cdp
        address _borrower = sortedCdps.getOwnerAddress(_cdpId);
        assert(msg.sender == _borrower);

        contractsCache.cdpManager.applyPendingRewards(_cdpId);

        // Get the collChange based on the collateral value transferred in the transaction
        (vars.collChange, vars.isCollIncrease) = _getCollChange(_collAddAmount, _collWithdrawal);

        vars.netDebtChange = _EBTCChange;

        vars.debt = contractsCache.cdpManager.getCdpDebt(_cdpId);
        vars.coll = contractsCache.cdpManager.getCdpColl(_cdpId);

        // Get the cdp's old ICR before the adjustment, and what its new ICR will be after the adjustment
        uint _cdpCollAmt = collateral.getPooledEthByShares(vars.coll);
        vars.oldICR = LiquityMath._computeCR(_cdpCollAmt, vars.debt, vars.price);
        vars.newICR = _getNewICRFromCdpChange(
            vars.coll,
            vars.debt,
            vars.collChange,
            vars.isCollIncrease,
            vars.netDebtChange,
            _isDebtIncrease,
            vars.price
        );
        assert(_collWithdrawal <= _cdpCollAmt);

        // Check the adjustment satisfies all conditions for the current system mode
        _requireValidAdjustmentInCurrentMode(isRecoveryMode, _collWithdrawal, _isDebtIncrease, vars);

        // When the adjustment is a debt repayment, check it's a valid amount and that the caller has enough EBTC
        if (!_isDebtIncrease && _EBTCChange > 0) {
            uint _netDebt = _getNetDebt(vars.debt) - vars.netDebtChange;
            _requireAtLeastMinNetDebt(_convertDebtDenominationToEth(_netDebt, vars.price));
            _requireValidEBTCRepayment(vars.debt, vars.netDebtChange);
            _requireSufficientEBTCBalance(contractsCache.ebtcToken, _borrower, vars.netDebtChange);
        }

        (vars.newColl, vars.newDebt) = _updateCdpFromAdjustment(
            contractsCache.cdpManager,
            _cdpId,
            vars.collChange,
            vars.isCollIncrease,
            vars.netDebtChange,
            _isDebtIncrease
        );
        vars.stake = contractsCache.cdpManager.updateStakeAndTotalStakes(_cdpId);

        // Re-insert cdp in to the sorted list
        {
            uint newNICR = _getNewNominalICRFromCdpChange(vars, _isDebtIncrease);
            sortedCdps.reInsert(_cdpId, newNICR, _upperHint, _lowerHint);
        }

        emit CdpUpdated(
            _cdpId,
            _borrower,
            vars.debt,
            vars.coll,
            vars.newDebt,
            vars.newColl,
            vars.stake,
            BorrowerOperation.adjustCdp
        );

        // Use the unmodified _EBTCChange here, as we don't send the fee to the user
        {
            _moveTokensAndETHfromAdjustment(
                contractsCache.activePool,
                contractsCache.ebtcToken,
                vars.collChange,
                (vars.isCollIncrease ? _collAddAmount : 0),
                vars.isCollIncrease,
                _EBTCChange,
                _isDebtIncrease,
                vars.netDebtChange
            );
        }
    }

    function closeCdp(bytes32 _cdpId) external override {
        _requireCdpOwner(_cdpId);

        ICdpManager cdpManagerCached = cdpManager;
        IActivePool activePoolCached = activePool;
        IEBTCToken ebtcTokenCached = ebtcToken;

        _requireCdpisActive(cdpManagerCached, _cdpId);
        uint price = priceFeed.fetchPrice();
        _requireNotInRecoveryMode(price);

        cdpManagerCached.applyPendingRewards(_cdpId);

        uint coll = cdpManagerCached.getCdpColl(_cdpId);
        uint debt = cdpManagerCached.getCdpDebt(_cdpId);

        _requireSufficientEBTCBalance(ebtcTokenCached, msg.sender, debt - EBTC_GAS_COMPENSATION);

        uint newTCR = _getNewTCRFromCdpChange(
            collateral.getPooledEthByShares(coll),
            false,
            debt,
            false,
            price
        );
        _requireNewTCRisAboveCCR(newTCR);

        cdpManagerCached.removeStake(_cdpId);
        cdpManagerCached.closeCdp(_cdpId);

        // We already verified msg.sender is the borrower
        emit CdpUpdated(_cdpId, msg.sender, debt, coll, 0, 0, 0, BorrowerOperation.closeCdp);

        // Burn the repaid EBTC from the user's balance and the gas compensation from the Gas Pool
        _repayEBTC(activePoolCached, ebtcTokenCached, msg.sender, debt - EBTC_GAS_COMPENSATION);
        _repayEBTC(activePoolCached, ebtcTokenCached, gasPoolAddress, EBTC_GAS_COMPENSATION);

        // Send the collateral back to the user
        activePoolCached.sendStEthColl(msg.sender, coll);
    }

    /**
     * Claim remaining collateral from a redemption or from a liquidation with ICR > MCR in Recovery Mode
     */
    function claimCollateral() external override {
        // send ETH from CollSurplus Pool to owner
        collSurplusPool.claimColl(msg.sender);
    }

    // --- Helper functions ---

    function _getUSDValue(uint _coll, uint _price) internal pure returns (uint) {
        uint usdValue = (_price * _coll) / DECIMAL_PRECISION;

        return usdValue;
    }

    function _getCollChange(
        uint _collReceived,
        uint _requestedCollWithdrawal
    ) internal view returns (uint collChange, bool isCollIncrease) {
        if (_collReceived != 0) {
            collChange = collateral.getSharesByPooledEth(_collReceived);
            isCollIncrease = true;
        } else {
            collChange = collateral.getSharesByPooledEth(_requestedCollWithdrawal);
        }
    }

    // Update cdp's coll and debt based on whether they increase or decrease
    function _updateCdpFromAdjustment(
        ICdpManager _cdpManager,
        bytes32 _cdpId,
        uint _collChange,
        bool _isCollIncrease,
        uint _debtChange,
        bool _isDebtIncrease
    ) internal returns (uint, uint) {
        uint newColl = (_isCollIncrease)
            ? _cdpManager.increaseCdpColl(_cdpId, _collChange)
            : _cdpManager.decreaseCdpColl(_cdpId, _collChange);
        uint newDebt = (_isDebtIncrease)
            ? _cdpManager.increaseCdpDebt(_cdpId, _debtChange)
            : _cdpManager.decreaseCdpDebt(_cdpId, _debtChange);

        return (newColl, newDebt);
    }

    function _moveTokensAndETHfromAdjustment(
        IActivePool _activePool,
        IEBTCToken _ebtcToken,
        uint collChange,
        uint collAddUnderlying,
        bool isCollIncrease,
        uint EBTCChange,
        bool isDebtIncrease,
        uint netDebtChange
    ) internal {
        if (isDebtIncrease) {
            _withdrawEBTC(_activePool, _ebtcToken, msg.sender, EBTCChange, netDebtChange);
        } else {
            _repayEBTC(_activePool, _ebtcToken, msg.sender, EBTCChange);
        }

        if (isCollIncrease) {
            _activePoolAddColl(_activePool, collAddUnderlying, collChange);
        } else {
            _activePool.sendStEthColl(msg.sender, collChange);
        }
    }

    // Send ETH to Active Pool and increase its recorded ETH balance
    function _activePoolAddColl(IActivePool _activePool, uint _amount, uint _shareAmt) internal {
        // NOTE: No need for safe transfer if the collateral asset is standard. Make sure this is the case!
        collateral.transferFrom(msg.sender, address(_activePool), _amount);
        _activePool.receiveColl(_shareAmt);
    }

    // Issue the specified amount of EBTC to _account and increases
    // the total active debt
    function _withdrawEBTC(
        IActivePool _activePool,
        IEBTCToken _ebtcToken,
        address _account,
        uint _EBTCAmount,
        uint _netDebtIncrease
    ) internal {
        _activePool.increaseEBTCDebt(_netDebtIncrease);
        _ebtcToken.mint(_account, _EBTCAmount);
    }

    // Burn the specified amount of EBTC from _account and decreases the total active debt
    function _repayEBTC(
        IActivePool _activePool,
        IEBTCToken _ebtcToken,
        address _account,
        uint _EBTC
    ) internal {
        _activePool.decreaseEBTCDebt(_EBTC);
        _ebtcToken.burn(_account, _EBTC);
    }

    // --- 'Require' wrapper functions ---

    function _requireCdpOwner(bytes32 _cdpId) internal view {
        address _owner = sortedCdps.existCdpOwners(_cdpId);
        require(msg.sender == _owner, "BorrowerOps: Caller must be cdp owner");
    }

    function _requireSingularCollChange(uint _collAdd, uint _collWithdrawal) internal pure {
        require(
            _collAdd == 0 || _collWithdrawal == 0,
            "BorrowerOperations: Cannot withdraw and add coll"
        );
    }

    function _requireCallerIsBorrower(address _borrower) internal view {
        require(
            msg.sender == _borrower,
            "BorrowerOps: Caller must be the borrower for a withdrawal"
        );
    }

    function _requireNonZeroAdjustment(
        uint _collAddAmount,
        uint _EBTCChange,
        uint _collWithdrawal
    ) internal pure {
        require(
            _collAddAmount != 0 || _collWithdrawal != 0 || _EBTCChange != 0,
            "BorrowerOps: There must be either a collateral change or a debt change"
        );
    }

    function _requireCdpisActive(ICdpManager _cdpManager, bytes32 _cdpId) internal view {
        uint status = _cdpManager.getCdpStatus(_cdpId);
        require(status == 1, "BorrowerOps: Cdp does not exist or is closed");
    }

    //    function _requireCdpisNotActive(ICdpManager _cdpManager, address _borrower) internal view {
    //        uint status = _cdpManager.getCdpStatus(_borrower);
    //        require(status != 1, "BorrowerOps: Cdp is active");
    //    }

    function _requireNonZeroDebtChange(uint _EBTCChange) internal pure {
        require(_EBTCChange > 0, "BorrowerOps: Debt increase requires non-zero debtChange");
    }

    function _requireNotInRecoveryMode(uint _price) internal view {
        require(
            !_checkRecoveryMode(_price),
            "BorrowerOps: Operation not permitted during Recovery Mode"
        );
    }

    function _requireNoCollWithdrawal(uint _collWithdrawal) internal pure {
        require(
            _collWithdrawal == 0,
            "BorrowerOps: Collateral withdrawal not permitted Recovery Mode"
        );
    }

    function _requireValidAdjustmentInCurrentMode(
        bool _isRecoveryMode,
        uint _collWithdrawal,
        bool _isDebtIncrease,
        LocalVariables_adjustCdp memory _vars
    ) internal view {
        /*
         *In Recovery Mode, only allow:
         *
         * - Pure collateral top-up
         * - Pure debt repayment
         * - Collateral top-up with debt repayment
         * - A debt increase combined with a collateral top-up which makes the
         * ICR >= 150% and improves the ICR (and by extension improves the TCR).
         *
         * In Normal Mode, ensure:
         *
         * - The new ICR is above MCR
         * - The adjustment won't pull the TCR below CCR
         */
        if (_isRecoveryMode) {
            _requireNoCollWithdrawal(_collWithdrawal);
            if (_isDebtIncrease) {
                _requireICRisAboveCCR(_vars.newICR);
                _requireNewICRisAboveOldICR(_vars.newICR, _vars.oldICR);
            }
        } else {
            // if Normal Mode
            _requireICRisAboveMCR(_vars.newICR);
            _vars.newTCR = _getNewTCRFromCdpChange(
                collateral.getPooledEthByShares(_vars.collChange),
                _vars.isCollIncrease,
                _vars.netDebtChange,
                _isDebtIncrease,
                _vars.price
            );
            _requireNewTCRisAboveCCR(_vars.newTCR);
        }
    }

    function _requireICRisAboveMCR(uint _newICR) internal pure {
        require(
            _newICR >= MCR,
            "BorrowerOps: An operation that would result in ICR < MCR is not permitted"
        );
    }

    function _requireICRisAboveCCR(uint _newICR) internal pure {
        require(_newICR >= CCR, "BorrowerOps: Operation must leave cdp with ICR >= CCR");
    }

    function _requireNewICRisAboveOldICR(uint _newICR, uint _oldICR) internal pure {
        require(_newICR >= _oldICR, "BorrowerOps: Cannot decrease your Cdp's ICR in Recovery Mode");
    }

    function _requireNewTCRisAboveCCR(uint _newTCR) internal pure {
        require(
            _newTCR >= CCR,
            "BorrowerOps: An operation that would result in TCR < CCR is not permitted"
        );
    }

    function _requireAtLeastMinNetDebt(uint _netDebt) internal pure {
        require(
            _netDebt >= MIN_NET_DEBT,
            "BorrowerOps: Cdp's net debt must be greater than minimum"
        );
    }

    function _requireValidEBTCRepayment(uint _currentDebt, uint _debtRepayment) internal pure {
        require(
            _debtRepayment <= _currentDebt - EBTC_GAS_COMPENSATION,
            "BorrowerOps: Amount repaid must not be larger than the Cdp's debt"
        );
    }

    function _requireSufficientEBTCBalance(
        IEBTCToken _ebtcToken,
        address _borrower,
        uint _debtRepayment
    ) internal view {
        require(
            _ebtcToken.balanceOf(_borrower) >= _debtRepayment,
            "BorrowerOps: Caller doesnt have enough EBTC to make repayment"
        );
    }

    // --- ICR and TCR getters ---

    // Compute the new collateral ratio, considering the change in coll and debt. Assumes 0 pending rewards.
    function _getNewNominalICRFromCdpChange(
        LocalVariables_adjustCdp memory vars,
        bool _isDebtIncrease
    ) internal pure returns (uint) {
        (uint newColl, uint newDebt) = _getNewCdpAmounts(
            vars.coll,
            vars.debt,
            vars.collChange,
            vars.isCollIncrease,
            vars.netDebtChange,
            _isDebtIncrease
        );

        uint newNICR = LiquityMath._computeNominalCR(newColl, newDebt);
        return newNICR;
    }

    // Compute the new collateral ratio, considering the change in coll and debt. Assumes 0 pending rewards.
    function _getNewICRFromCdpChange(
        uint _coll,
        uint _debt,
        uint _collChange,
        bool _isCollIncrease,
        uint _debtChange,
        bool _isDebtIncrease,
        uint _price
    ) internal view returns (uint) {
        (uint newColl, uint newDebt) = _getNewCdpAmounts(
            _coll,
            _debt,
            _collChange,
            _isCollIncrease,
            _debtChange,
            _isDebtIncrease
        );

        uint newICR = LiquityMath._computeCR(
            collateral.getPooledEthByShares(newColl),
            newDebt,
            _price
        );
        return newICR;
    }

    function _getNewCdpAmounts(
        uint _coll,
        uint _debt,
        uint _collChange,
        bool _isCollIncrease,
        uint _debtChange,
        bool _isDebtIncrease
    ) internal pure returns (uint, uint) {
        uint newColl = _coll;
        uint newDebt = _debt;

        newColl = _isCollIncrease ? _coll + _collChange : _coll - _collChange;
        newDebt = _isDebtIncrease ? _debt + _debtChange : _debt - _debtChange;

        return (newColl, newDebt);
    }

    function _getNewTCRFromCdpChange(
        uint _collChange,
        bool _isCollIncrease,
        uint _debtChange,
        bool _isDebtIncrease,
        uint _price
    ) internal view returns (uint) {
        uint _shareColl = getEntireSystemColl();
        uint totalColl = collateral.getPooledEthByShares(_shareColl);
        uint totalDebt = _getEntireSystemDebt();

        totalColl = _isCollIncrease ? totalColl + _collChange : totalColl - _collChange;
        totalDebt = _isDebtIncrease ? totalDebt + _debtChange : totalDebt - _debtChange;

        uint newTCR = LiquityMath._computeCR(totalColl, totalDebt, _price);
        return newTCR;
    }

    function getCompositeDebt(uint _debt) external pure override returns (uint) {
        return _getCompositeDebt(_debt);
    }

    // === Flash Loans === //
    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) external override returns (bool) {
        require(amount > 0, "BorrowerOperations: 0 Amount");
        IEBTCToken cachedEbtc = ebtcToken;
        require(token == address(cachedEbtc), "BorrowerOperations: EBTC Only");

        uint256 fee = (amount * FEE_AMT) / MAX_BPS;

        // Issue EBTC
        cachedEbtc.mint(address(receiver), amount);

        // Callback
        require(
            receiver.onFlashLoan(msg.sender, token, amount, fee, data) == FLASH_SUCCESS_VALUE,
            "BorrowerOperations: IERC3156: Callback failed"
        );

        // Gas: Repay from user balance, so we don't trigger a new SSTORE
        // Safe to use transferFrom and unchecked as it's a standard token
        // Also saves gas
        // Send both fee and amount to FEE_RECIPIENT, to burn allowance per EIP-3156
        cachedEbtc.transferFrom(address(receiver), FEE_RECIPIENT, fee + amount);

        // Burn amount, from FEE_RECIPIENT
        cachedEbtc.burn(address(FEE_RECIPIENT), amount);

        return true;
    }

    function flashFee(address token, uint256 amount) external view override returns (uint256) {
        require(token == address(ebtcToken), "BorrowerOperations: EBTC Only");

        return (amount * FEE_AMT) / MAX_BPS;
    }

    /// @dev Max flashloan, exclusively in ETH equals to the current balance
    function maxFlashLoan(address token) external view override returns (uint256) {
        if (token != address(ebtcToken)) {
            return 0;
        }

        // TODO: Decide if max, or w/e
        // For now return 112 which is UniV3 compatible
        // Source: I made it up
        return type(uint112).max;
    }
}
