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
import "./Dependencies/AuthNoOwner.sol";
import "./Dependencies/ERC3156FlashLender.sol";

contract BorrowerOperations is LiquityBase, IBorrowerOperations, ERC3156FlashLender {
    string public constant NAME = "BorrowerOperations";

    // --- Connected contract declarations ---

    ICdpManager public immutable cdpManager;

    ICollSurplusPool public immutable collSurplusPool;

    IFeeRecipient public immutable feeRecipient;

    IEBTCToken public immutable ebtcToken;

    // A doubly linked list of Cdps, sorted by their collateral ratios
    ISortedCdps public immutable sortedCdps;

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

    struct LocalVariables_openCdp {
        uint price;
        uint debt;
        uint totalColl;
        uint netColl;
        uint ICR;
        uint NICR;
        uint stake;
        uint arrayIndex;
    }

    struct LocalVariables_moveTokens {
        address user;
        uint collChange;
        uint collAddUnderlying; // ONLY for isCollIncrease=true
        bool isCollIncrease;
        uint EBTCChange;
        bool isDebtIncrease;
        uint netDebtChange;
    }

    // --- Dependency setters ---
    constructor(
        address _cdpManagerAddress,
        address _activePoolAddress,
        address _defaultPoolAddress,
        address _collSurplusPoolAddress,
        address _priceFeedAddress,
        address _sortedCdpsAddress,
        address _ebtcTokenAddress,
        address _feeRecipientAddress,
        address _collTokenAddress
    ) LiquityBase(_activePoolAddress, _defaultPoolAddress, _priceFeedAddress, _collTokenAddress) {
        // We no longer checkContract() here, because the contracts we depend on may not yet be deployed.

        // This makes impossible to open a cdp with zero withdrawn EBTC
        // assert(MIN_NET_DEBT > 0);
        // TODO: Re-evaluate this

        cdpManager = ICdpManager(_cdpManagerAddress);
        collSurplusPool = ICollSurplusPool(_collSurplusPoolAddress);
        sortedCdps = ISortedCdps(_sortedCdpsAddress);
        ebtcToken = IEBTCToken(_ebtcTokenAddress);
        feeRecipient = IFeeRecipient(_feeRecipientAddress);

        address _authorityAddress = address(AuthNoOwner(_cdpManagerAddress).authority());
        if (_authorityAddress != address(0)) {
            _initializeAuthority(_authorityAddress);
        }

        emit CdpManagerAddressChanged(_cdpManagerAddress);
        emit ActivePoolAddressChanged(_activePoolAddress);
        emit DefaultPoolAddressChanged(_defaultPoolAddress);
        emit CollSurplusPoolAddressChanged(_collSurplusPoolAddress);
        emit PriceFeedAddressChanged(_priceFeedAddress);
        emit SortedCdpsAddressChanged(_sortedCdpsAddress);
        emit EBTCTokenAddressChanged(_ebtcTokenAddress);
        emit FeeRecipientAddressChanged(_feeRecipientAddress);
        emit CollateralAddressChanged(_collTokenAddress);

        // No longer need a concept of ownership if there is no initializer
    }

    // --- Borrower Cdp Operations ---

    /**
    @notice Function that creates a Cdp for the caller with the requested debt, and the stETH received as collateral. 
    @notice Successful execution is conditional mainly on the resulting collateralization ratio which must exceed the minimum (110% in Normal Mode, 150% in Recovery Mode). 
    @notice In addition to the requested debt, extra debt is issued to cover the gas compensation. 
    */
    function openCdp(
        uint _EBTCAmount,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint _collAmount
    ) external override returns (bytes32) {
        return _openCdp(_EBTCAmount, _upperHint, _lowerHint, _collAmount, msg.sender);
    }

    // Function that adds the received stETH to the caller's specified Cdp.
    function addColl(
        bytes32 _cdpId,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint _collAmount
    ) external override {
        _adjustCdp(_cdpId, 0, 0, false, _upperHint, _lowerHint, _collAmount);
    }

    /**
    Withdraws `_collWithdrawal` amount of collateral from the caller’s Cdp. Executes only if the user has an active Cdp, the withdrawal would not pull the user’s Cdp below the minimum collateralization ratio, and the resulting total collateralization ratio of the system is above 150%. 
    */
    function withdrawColl(
        bytes32 _cdpId,
        uint _collWithdrawal,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external override {
        _adjustCdp(_cdpId, _collWithdrawal, 0, false, _upperHint, _lowerHint, 0);
    }

    // Withdraw EBTC tokens from a cdp: mint new EBTC tokens to the owner, and increase the cdp's debt accordingly
    /**
    Issues `_amount` of eBTC from the caller’s Cdp to the caller. Executes only if the Cdp's collateralization ratio would remain above the minimum, and the resulting total collateralization ratio is above 150%.
     */
    function withdrawEBTC(
        bytes32 _cdpId,
        uint _EBTCAmount,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external override {
        _adjustCdp(_cdpId, 0, _EBTCAmount, true, _upperHint, _lowerHint, 0);
    }

    // Repay EBTC tokens to a Cdp: Burn the repaid EBTC tokens, and reduce the cdp's debt accordingly
    /**
    repay `_amount` of eBTC to the caller’s Cdp, subject to leaving 50 debt in the Cdp (which corresponds to the 50 eBTC gas compensation).
    */
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

    /**
    enables a borrower to simultaneously change both their collateral and debt, subject to all the restrictions that apply to individual increases/decreases of each quantity with the following particularity: if the adjustment reduces the collateralization ratio of the Cdp, the function only executes if the resulting total collateralization ratio is above 150%. The borrower has to provide a `_maxFeePercentage` that he/she is willing to accept in case of a fee slippage, i.e. when a redemption transaction is processed first, driving up the issuance fee. The parameter is ignored if the debt is not increased with the transaction.
    */
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
        LocalVariables_adjustCdp memory vars;

        _requireCdpisActive(cdpManager, _cdpId);

        vars.price = priceFeed.fetchPrice();

        // Reversed BTC/ETH price
        bool isRecoveryMode = _checkRecoveryMode(vars.price);

        if (_isDebtIncrease) {
            _requireNonZeroDebtChange(_EBTCChange);
        }
        _requireSingularCollChange(_collAddAmount, _collWithdrawal);
        _requireNonZeroAdjustment(_collAddAmount, _collWithdrawal, _EBTCChange);

        // Confirm the operation is either a borrower adjusting their own cdp
        address _borrower = sortedCdps.getOwnerAddress(_cdpId);
        assert(msg.sender == _borrower);

        cdpManager.applyPendingRewards(_cdpId);

        // Get the collChange based on the collateral value transferred in the transaction
        (vars.collChange, vars.isCollIncrease) = _getCollChange(_collAddAmount, _collWithdrawal);

        vars.netDebtChange = _EBTCChange;

        vars.debt = cdpManager.getCdpDebt(_cdpId);
        vars.coll = cdpManager.getCdpColl(_cdpId);

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

        // When the adjustment is a debt repayment, check it's a valid amount, that the caller has enough EBTC, and that the resulting debt is >0
        if (!_isDebtIncrease && _EBTCChange > 0) {
            _requireValidEBTCRepayment(vars.debt, vars.netDebtChange);
            _requireSufficientEBTCBalance(ebtcToken, _borrower, vars.netDebtChange);
            _requireNonZeroDebt(vars.debt - vars.netDebtChange);
        }

        (vars.newColl, vars.newDebt) = _updateCdpFromAdjustment(
            cdpManager,
            _cdpId,
            vars.collChange,
            vars.isCollIncrease,
            vars.netDebtChange,
            _isDebtIncrease
        );

        _requireAtLeastMinNetColl(vars.newColl);

        vars.stake = cdpManager.updateStakeAndTotalStakes(_cdpId);

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
            LocalVariables_moveTokens memory _varMvTokens = LocalVariables_moveTokens(
                msg.sender,
                vars.collChange,
                (vars.isCollIncrease ? _collAddAmount : 0),
                vars.isCollIncrease,
                _EBTCChange,
                _isDebtIncrease,
                vars.netDebtChange
            );
            _processTokenMovesFromAdjustment(activePool, ebtcToken, _varMvTokens);
        }
    }

    function _openCdp(
        uint _EBTCAmount,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint _collAmount,
        address _borrower
    ) internal returns (bytes32) {
        require(_collAmount > 0, "BorrowerOps: collateral for CDP is zero");
        _requireNonZeroDebt(_EBTCAmount);

        LocalVariables_openCdp memory vars;

        // ICR is based on the net coll, i.e. the requested coll amount - fixed liquidator incentive gas comp.
        vars.netColl = _getNetColl(_collAmount);

        _requireAtLeastMinNetColl(vars.netColl);

        vars.price = priceFeed.fetchPrice();

        // Reverse ETH/BTC price to BTC/ETH
        bool isRecoveryMode = _checkRecoveryMode(vars.price);

        vars.debt = _EBTCAmount;

        // Sanity check
        assert(vars.netColl > 0);

        uint _netCollAsShares = collateral.getSharesByPooledEth(vars.netColl);
        uint _liquidatorRewardShares = collateral.getSharesByPooledEth(LIQUIDATOR_REWARD);

        // ICR is based on the net coll, i.e. the requested coll amount - fixed liquidator incentive gas comp.
        vars.ICR = LiquityMath._computeCR(vars.netColl, vars.debt, vars.price);

        // NICR uses shares to normalize NICR across CDPs opened at different pooled ETH / shares ratios
        vars.NICR = LiquityMath._computeNominalCR(_netCollAsShares, vars.debt);

        /**
            In recovery move, ICR must be greater than CCR
            CCR > MCR (125% vs 110%)

            In normal mode, ICR must be greater thatn MCR
            Additionally, the new system TCR after the CDPs addition must be >CCR
        */
        if (isRecoveryMode) {
            _requireICRisAboveCCR(vars.ICR);
        } else {
            _requireICRisAboveMCR(vars.ICR);
            uint newTCR = _getNewTCRFromCdpChange(vars.netColl, true, vars.debt, true, vars.price); // bools: coll increase, debt increase
            _requireNewTCRisAboveCCR(newTCR);
        }

        // Set the cdp struct's properties
        bytes32 _cdpId = sortedCdps.insert(_borrower, vars.NICR, _upperHint, _lowerHint);

        cdpManager.setCdpStatus(_cdpId, 1);
        cdpManager.increaseCdpColl(_cdpId, _netCollAsShares); // Collateral is stored in shares form for normalization
        cdpManager.increaseCdpDebt(_cdpId, vars.debt);
        cdpManager.setCdpLiquidatorRewardShares(_cdpId, _liquidatorRewardShares);

        cdpManager.updateCdpRewardSnapshots(_cdpId);
        vars.stake = cdpManager.updateStakeAndTotalStakes(_cdpId);

        vars.arrayIndex = cdpManager.addCdpIdToArray(_cdpId);
        emit CdpCreated(_cdpId, _borrower, msg.sender, vars.arrayIndex);

        // Mint the full EBTCAmount to the borrower
        _withdrawEBTC(activePool, ebtcToken, _borrower, _EBTCAmount, _EBTCAmount);

        /** 
            Note that only NET coll (as shares) is considered part of the CDP. 
            The static liqudiation incentive is stored in the gas pool and can be considered a deposit / voucher to be returned upon CDP close, to the closer.
            The close can happen from the borrower closing their own CDP, a full liquidation, or a redemption.
        */
        emit CdpUpdated(
            _cdpId,
            _borrower,
            0,
            0,
            vars.debt,
            _netCollAsShares,
            vars.stake,
            BorrowerOperation.openCdp
        );

        // CEI: Move the net collateral and liquidator gas compensation to the Active Pool. Track only net collateral shares for TCR purposes.
        _activePoolAddColl(_collAmount, _netCollAsShares, _liquidatorRewardShares);

        assert(vars.netColl + LIQUIDATOR_REWARD == _collAmount); // Invariant Assertion

        return _cdpId;
    }

    /**
    allows a borrower to repay all debt, withdraw all their collateral, and close their Cdp. Requires the borrower have a eBTC balance sufficient to repay their cdp's debt, excluding gas compensation - i.e. `(debt - 50)` eBTC. 
    */
    function closeCdp(bytes32 _cdpId) external override {
        _requireCdpOwner(_cdpId);

        _requireCdpisActive(cdpManager, _cdpId);
        uint price = priceFeed.fetchPrice();
        _requireNotInRecoveryMode(price);

        cdpManager.applyPendingRewards(_cdpId);

        uint coll = cdpManager.getCdpColl(_cdpId);
        uint debt = cdpManager.getCdpDebt(_cdpId);
        uint liquidatorRewardShares = cdpManager.getCdpLiquidatorRewardShares(_cdpId);

        _requireSufficientEBTCBalance(ebtcToken, msg.sender, debt);

        uint newTCR = _getNewTCRFromCdpChange(
            collateral.getPooledEthByShares(coll),
            false,
            debt,
            false,
            price
        );
        _requireNewTCRisAboveCCR(newTCR);

        cdpManager.removeStake(_cdpId);
        cdpManager.closeCdp(_cdpId);

        // We already verified msg.sender is the borrower
        emit CdpUpdated(_cdpId, msg.sender, debt, coll, 0, 0, 0, BorrowerOperation.closeCdp);

        // Burn the repaid EBTC from the user's balance
        _repayEBTC(activePool, ebtcToken, msg.sender, debt);

        // CEI: Send the collateral and liquidator reward shares back to the user
        activePool.sendStEthCollAndLiquidatorReward(msg.sender, coll, liquidatorRewardShares);
    }

    /**
     * Claim remaining collateral from a redemption or from a liquidation with ICR > MCR in Recovery Mode

      when a borrower’s Cdp has been fully redeemed from and closed, or liquidated in Recovery Mode with a collateralization ratio above 110%, this function allows the borrower to claim their stETH collateral surplus that remains in the system (collateral - debt upon redemption; collateral - 110% of the debt upon liquidation).
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

    /**
        @notice Process the token movements required by a CDP adjustment.
        @notice Handles the cases of a debt increase / decrease, and/or a collateral increase / decrease.
     */
    function _processTokenMovesFromAdjustment(
        IActivePool _activePool,
        IEBTCToken _ebtcToken,
        LocalVariables_moveTokens memory _varMvTokens
    ) internal {
        // Debt increase: mint change value of new eBTC to user, increment ActivePool eBTC internal accounting
        if (_varMvTokens.isDebtIncrease) {
            _withdrawEBTC(
                _activePool,
                _ebtcToken,
                _varMvTokens.user,
                _varMvTokens.EBTCChange,
                _varMvTokens.netDebtChange
            );
        } else {
            // Debt decrease: burn change value of eBTC from user, decrement ActivePool eBTC internal accounting
            _repayEBTC(_activePool, _ebtcToken, _varMvTokens.user, _varMvTokens.EBTCChange);
        }

        if (_varMvTokens.isCollIncrease) {
            // Coll increase: send change value of stETH to Active Pool, increment ActivePool stETH internal accounting
            _activePoolAddColl(_varMvTokens.collAddUnderlying, _varMvTokens.collChange, 0);
        } else {
            // Coll decrease: send change value of stETH to user, decrement ActivePool stETH internal accounting
            _activePool.sendStEthColl(_varMvTokens.user, _varMvTokens.collChange);
        }
    }

    /// @notice Send stETH to Active Pool and increase its recorded ETH balance
    /// @dev Liquidator reward shares are not considered as part of the system for CR purposes.
    /// @dev These number of liquidator shares associated with each CDP are stored in the CDP, while the actual tokens float in the active pool
    function _activePoolAddColl(
        uint _amount,
        uint _sharesToTrack,
        uint _liquidatorRewardShares
    ) internal {
        // NOTE: No need for safe transfer if the collateral asset is standard. Make sure this is the case!
        collateral.transferFrom(msg.sender, address(activePool), _amount);
        activePool.receiveColl(_sharesToTrack);
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

    function _requireNonZeroDebt(uint _debt) internal pure {
        require(_debt > 0, "BorrowerOps: Debt must be non-zero");
    }

    function _requireAtLeastMinNetColl(uint _coll) internal pure {
        require(_coll >= MIN_NET_COLL, "BorrowerOps: Cdp's net coll must be greater than minimum");
    }

    function _requireValidEBTCRepayment(uint _currentDebt, uint _debtRepayment) internal pure {
        require(
            _debtRepayment <= _currentDebt,
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

        uint256 fee = (amount * feeBps) / MAX_BPS;

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

        return (amount * feeBps) / MAX_BPS;
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
