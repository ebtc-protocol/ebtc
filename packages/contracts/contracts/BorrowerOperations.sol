// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./Interfaces/IBorrowerOperations.sol";
import "./Interfaces/ICdpManager.sol";
import "./Interfaces/ICdpManagerData.sol";
import "./Interfaces/IEBTCToken.sol";
import "./Interfaces/ICollSurplusPool.sol";
import "./Interfaces/ISortedCdps.sol";
import "./Dependencies/LiquityBase.sol";
import "./Dependencies/ReentrancyGuard.sol";
import "./Dependencies/Ownable.sol";
import "./Dependencies/AuthNoOwner.sol";
import "./Dependencies/ERC3156FlashLender.sol";

contract BorrowerOperations is
    LiquityBase,
    ReentrancyGuard,
    IBorrowerOperations,
    ERC3156FlashLender,
    AuthNoOwner
{
    string public constant NAME = "BorrowerOperations";

    // --- Connected contract declarations ---

    ICdpManager public immutable cdpManager;

    ICollSurplusPool public immutable collSurplusPool;

    address public feeRecipientAddress;

    IEBTCToken public immutable ebtcToken;

    // A doubly linked list of Cdps, sorted by their collateral ratios
    ISortedCdps public immutable sortedCdps;

    /* --- Variable container structs  ---

    Used to hold, return and assign variables inside a function, in order to avoid the error:
    "CompilerError: Stack too deep". */

    struct LocalVariables_adjustCdp {
        uint price;
        uint collSharesChange;
        uint debtChange;
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
        uint netStEthBalance;
        uint ICR;
        uint NICR;
        uint stake;
        uint arrayIndex;
    }

    struct LocalVariables_moveTokens {
        address user;
        uint collSharesChange;
        uint collAddUnderlying; // ONLY for isCollIncrease=true
        bool isCollIncrease;
        uint EBTCChange;
        bool isDebtIncrease;
        uint debtChange;
    }

    // --- Dependency setters ---
    constructor(
        address _cdpManagerAddress,
        address _activePoolAddress,
        address _collSurplusPoolAddress,
        address _priceFeedAddress,
        address _sortedCdpsAddress,
        address _ebtcTokenAddress,
        address _feeRecipientAddress,
        address _collTokenAddress
    ) LiquityBase(_activePoolAddress, _priceFeedAddress, _collTokenAddress) {
        // This makes impossible to open a cdp with zero withdrawn EBTC
        // TODO: Re-evaluate this

        cdpManager = ICdpManager(_cdpManagerAddress);
        collSurplusPool = ICollSurplusPool(_collSurplusPoolAddress);
        sortedCdps = ISortedCdps(_sortedCdpsAddress);
        ebtcToken = IEBTCToken(_ebtcTokenAddress);
        feeRecipientAddress = _feeRecipientAddress;

        address _authorityAddress = address(AuthNoOwner(_cdpManagerAddress).authority());
        if (_authorityAddress != address(0)) {
            _initializeAuthority(_authorityAddress);
        }

        emit CdpManagerAddressChanged(_cdpManagerAddress);
        emit ActivePoolAddressChanged(_activePoolAddress);
        emit CollSurplusPoolAddressChanged(_collSurplusPoolAddress);
        emit PriceFeedAddressChanged(_priceFeedAddress);
        emit SortedCdpsAddressChanged(_sortedCdpsAddress);
        emit EBTCTokenAddressChanged(_ebtcTokenAddress);
        emit FeeRecipientAddressChanged(_feeRecipientAddress);
        emit CollateralAddressChanged(_collTokenAddress);

        // No longer need a concept of ownership if there is no initializer
    }

    /**
        @notice BorrowerOperations and CdpManager share reentrancy status by confirming the other's locked flag before beginning operation
        @dev This is an alternative to the more heavyweight solution of both being able to set the reentrancy flag on a 3rd contract.
        @dev Prevents multi-contract reentrancy between these two contracts
     */
    modifier nonReentrantSelfAndCdpM() {
        require(locked == OPEN, "BorrowerOperations: Reentrancy in nonReentrant call");
        require(
            ReentrancyGuard(address(cdpManager)).locked() == OPEN,
            "CdpManager: Reentrancy in nonReentrant call"
        );

        locked = LOCKED;

        _;

        locked = OPEN;
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
        uint _stEthBalance
    ) external override nonReentrantSelfAndCdpM returns (bytes32) {
        return _openCdp(_EBTCAmount, _upperHint, _lowerHint, _stEthBalance, msg.sender);
    }

    // Function that adds the received stETH to the caller's specified Cdp.
    function addColl(
        bytes32 _cdpId,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint _stEthBalanceToIncrease
    ) external override nonReentrantSelfAndCdpM {
        _adjustCdpInternal(_cdpId, 0, 0, false, _upperHint, _lowerHint, _stEthBalanceToIncrease);
    }

    /**
    Withdraws `_stEthBalanceToDecrease` amount of collateral from the caller’s Cdp. Executes only if the user has an active Cdp, the withdrawal would not pull the user’s Cdp below the minimum collateralization ratio, and the resulting total collateralization ratio of the system is above 150%.
    */
    function withdrawColl(
        bytes32 _cdpId,
        uint _stEthBalanceToDecrease,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external override nonReentrantSelfAndCdpM {
        _adjustCdpInternal(_cdpId, _stEthBalanceToDecrease, 0, false, _upperHint, _lowerHint, 0);
    }

    // Withdraw EBTC tokens from a cdp: mint new EBTC tokens to the owner, and increase the cdp's debt accordingly
    /**
    Issues `_amount` of eBTC from the caller’s Cdp to the caller. Executes only if the Cdp's collateralization ratio would remain above the minimum, and the resulting total collateralization ratio is above 150%.
     */
    function withdrawEBTC(
        bytes32 _cdpId,
        uint _debtToRepay,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external override nonReentrantSelfAndCdpM {
        _adjustCdpInternal(_cdpId, 0, _debtToRepay, true, _upperHint, _lowerHint, 0);
    }

    // Repay EBTC tokens to a Cdp: Burn the repaid EBTC tokens, and reduce the cdp's debt accordingly
    /**
    repay `_amount` of eBTC to the caller’s Cdp, subject to leaving 50 debt in the Cdp (which corresponds to the 50 eBTC gas compensation).
    */
    function repayEBTC(
        bytes32 _cdpId,
        uint _debtToRepay,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external override nonReentrantSelfAndCdpM {
        _adjustCdpInternal(_cdpId, 0, _debtToRepay, false, _upperHint, _lowerHint, 0);
    }

    function adjustCdp(
        bytes32 _cdpId,
        uint _stEthBalanceToDecrease,
        uint _debtChange,
        bool _isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external override nonReentrantSelfAndCdpM {
        _adjustCdpInternal(
            _cdpId,
            _stEthBalanceToDecrease,
            _debtChange,
            _isDebtIncrease,
            _upperHint,
            _lowerHint,
            0
        );
    }

    /**
    enables a borrower to simultaneously change both their collateral and debt, subject to all the restrictions that apply to individual increases/decreases of each quantity with the following particularity: if the adjustment reduces the collateralization ratio of the Cdp, the function only executes if the resulting total collateralization ratio is above 150%. The borrower has to provide a `_maxFeePercentage` that he/she is willing to accept in case of a fee slippage, i.e. when a redemption transaction is processed first, driving up the issuance fee. The parameter is ignored if the debt is not increased with the transaction.
    */
    // TODO optimization candidate
    function adjustCdpWithColl(
        bytes32 _cdpId,
        uint _stEthBalanceToDecrease,
        uint _debtChange,
        bool _isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint _stEthBalanceToIncrease
    ) external override nonReentrantSelfAndCdpM {
        _adjustCdpInternal(
            _cdpId,
            _stEthBalanceToDecrease,
            _debtChange,
            _isDebtIncrease,
            _upperHint,
            _lowerHint,
            _stEthBalanceToIncrease
        );
    }

    /*
     * _adjustCdpInternal(): Alongside a debt change, this function can perform either
     * a collateral top-up or a collateral withdrawal.
     *
     * It therefore expects either a positive _collAddAmount, or a positive _stEthBalanceToDecrease argument.
     *
     * If both are positive, it will revert.
     */
    function _adjustCdpInternal(
        bytes32 _cdpId,
        uint _stEthBalanceToDecrease,
        uint _debtChange,
        bool _isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint _stEthBalanceToIncrease
    ) internal {
        _requireCdpOwner(_cdpId);
        _requireCdpisActive(cdpManager, _cdpId);

        cdpManager.applyPendingState(_cdpId);

        LocalVariables_adjustCdp memory vars;

        vars.price = priceFeed.fetchPrice();
        bool isRecoveryMode = _checkRecoveryModeForTCR(_getTCR(vars.price));

        if (_isDebtIncrease) {
            _requireNonZeroDebtChange(_debtChange);
        }
        _requireSingularCollChange(_stEthBalanceToIncrease, _stEthBalanceToDecrease);
        _requireNonZeroAdjustment(_stEthBalanceToIncrease, _stEthBalanceToDecrease, _debtChange);

        // Confirm the operation is the borrower adjusting its own cdp
        address _borrower = sortedCdps.getOwnerAddress(_cdpId);
        require(msg.sender == _borrower, "BorrowerOperations: only allow CDP owner to adjust!");

        // Get the collSharesChange based on the collateral value transferred in the transaction
        (vars.collSharesChange, vars.isCollIncrease) = _getCollSharesChangeFromStEthBalanceChange(
            _stEthBalanceToIncrease,
            _stEthBalanceToDecrease
        );

        vars.debtChange = _debtChange;

        vars.debt = cdpManager.getCdpDebt(_cdpId);
        vars.coll = cdpManager.getCdpCollShares(_cdpId);

        // Get the cdp's old ICR before the adjustment, and what its new ICR will be after the adjustment
        uint _stEthBalanceOfCdpCollShares = collateral.getPooledEthByShares(vars.coll); //@audit why do we get this from the contract rather than cached state? it's up to date and everything else uses it
        require(
            _stEthBalanceToDecrease <= _stEthBalanceOfCdpCollShares,
            "BorrowerOperations: withdraw more collateral than CDP has!"
        );
        vars.oldICR = LiquityMath._computeCR(_stEthBalanceOfCdpCollShares, vars.debt, vars.price);
        vars.newICR = _getNewICRFromCdpChange(
            vars.coll,
            vars.debt,
            vars.collSharesChange,
            vars.isCollIncrease,
            vars.debtChange,
            _isDebtIncrease,
            vars.price
        );

        // Check the adjustment satisfies all conditions for the current system mode
        _requireValidAdjustmentInCurrentMode(
            isRecoveryMode,
            _stEthBalanceToDecrease,
            _isDebtIncrease,
            vars
        );

        // When the adjustment is a debt repayment, check it's a valid amount, that the caller has enough EBTC, and that the resulting debt is >0
        if (!_isDebtIncrease && _debtChange > 0) {
            _requireValidEBTCRepayment(vars.debt, vars.debtChange);
            _requireSufficientEBTCBalance(ebtcToken, _borrower, vars.debtChange);
            _requireNonZeroDebt(vars.debt - vars.debtChange);
        }

        (vars.newColl, vars.newDebt) = _getNewCdpAmounts(
            vars.coll,
            vars.debt,
            vars.collSharesChange,
            vars.isCollIncrease,
            vars.debtChange,
            _isDebtIncrease
        );

        // Only check when the collateral exchange rate from share is above 1e18
        // If there is big decrease due to slashing, some CDP might already fall below minimum collateral requirements
        if (collateral.getPooledEthByShares(DECIMAL_PRECISION) >= DECIMAL_PRECISION) {
            //@audit why do we get this value again? we can calculate it locally
            _requireAtLeastMinNetStEthBalance(collateral.getPooledEthByShares(vars.newColl));
        }

        cdpManager.updateCdp(_cdpId, _borrower, vars.coll, vars.debt, vars.newColl, vars.newDebt);

        // Re-insert cdp in to the sorted list
        {
            uint newNICR = _getNewNominalICRFromCdpChange(vars, _isDebtIncrease);
            sortedCdps.reInsert(_cdpId, newNICR, _upperHint, _lowerHint);
        }

        // Use the unmodified _debtChange here, as we don't send the fee to the user
        {
            LocalVariables_moveTokens memory _varMvTokens = LocalVariables_moveTokens(
                msg.sender,
                vars.collSharesChange,
                (vars.isCollIncrease ? _stEthBalanceToIncrease : 0),
                vars.isCollIncrease,
                _debtChange,
                _isDebtIncrease,
                vars.debtChange
            );
            _processTokenMovesFromAdjustment(_varMvTokens);
        }
    }

    function _openCdp(
        uint _EBTCAmount,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint _stEthBalance,
        address _borrower
    ) internal returns (bytes32) {
        _requireNonZeroDebt(_EBTCAmount);

        LocalVariables_openCdp memory vars;

        // ICR is based on the net collateral balance, i.e. the inputted balance amount - fixed liquidator incentive gas comp.
        vars.netStEthBalance = _getNetStEthBalance(_stEthBalance);

        // will revert if _stEthBalance is less than MIN_CDP_STETH_BALANCE + LIQUIDATOR_REWARD
        _requireAtLeastMinNetStEthBalance(vars.netStEthBalance);

        // Update global pending index before any operations
        cdpManager.applyPendingGlobalState();

        vars.price = priceFeed.fetchPrice();
        bool isRecoveryMode = _checkRecoveryModeForTCR(_getTCR(vars.price));

        vars.debt = _EBTCAmount;

        // Sanity check
        require(vars.netStEthBalance > 0, "BorrowerOperations: zero collateral for openCdp()!");

        uint _netCollShares = collateral.getSharesByPooledEth(vars.netStEthBalance);
        uint _liquidatorRewardShares = collateral.getSharesByPooledEth(LIQUIDATOR_REWARD);

        // ICR is based on the net coll, i.e. the requested coll amount - fixed liquidator incentive gas comp.
        vars.ICR = LiquityMath._computeCR(vars.netStEthBalance, vars.debt, vars.price);

        // NICR uses shares to normalize NICR across CDPs opened at different pooled ETH / shares ratios
        vars.NICR = LiquityMath._computeNominalCR(_netCollShares, vars.debt);

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
            uint newTCR = _getNewTCRFromCdpChange(
                vars.netStEthBalance,
                true,
                vars.debt,
                true,
                vars.price
            ); // bools: coll increase, debt increase
            _requireNewTCRisAboveCCR(newTCR);
        }

        // Set the cdp struct's properties
        bytes32 _cdpId = sortedCdps.insert(_borrower, vars.NICR, _upperHint, _lowerHint);

        // Collateral is stored in shares form for normalization
        cdpManager.initializeCdp(
            _cdpId,
            vars.debt,
            _netCollShares,
            _liquidatorRewardShares,
            _borrower
        );

        // Mint the full EBTCAmount to the borrower
        _withdrawEBTC(_borrower, _EBTCAmount, _EBTCAmount);

        /**
            Note that only NET coll (as shares) is considered part of the CDP.
            The static liqudiation incentive is stored in the gas pool and can be considered a deposit / voucher to be returned upon CDP close, to the closer.
            The close can happen from the borrower closing their own CDP, a full liquidation, or a redemption.
        */

        // CEI: Move the net collateral and liquidator gas compensation to the Active Pool. Track only net collateral shares for TCR purposes.
        _sendCollSharesToActivePool(_stEthBalance, _netCollShares);

        // Invariant check
        require(
            vars.netStEthBalance + LIQUIDATOR_REWARD == _stEthBalance,
            "BorrowerOperations: deposited collateral mismatch!"
        );

        return _cdpId;
    }

    /**
    allows a borrower to repay all debt, withdraw all their collateral, and close their Cdp. Requires the borrower have a eBTC balance sufficient to repay their cdp's debt, excluding gas compensation - i.e. `(debt - 50)` eBTC.
    */
    function closeCdp(bytes32 _cdpId) external override {
        _requireCdpOwner(_cdpId);
        _requireCdpisActive(cdpManager, _cdpId);

        cdpManager.applyPendingState(_cdpId);

        uint price = priceFeed.fetchPrice();
        _requireNotInRecoveryMode(_getTCR(price));

        uint coll = cdpManager.getCdpCollShares(_cdpId);
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

        // We already verified msg.sender is the borrower
        cdpManager.closeCdp(_cdpId, msg.sender, debt, coll);

        // Burn the repaid EBTC from the user's balance
        _repayEBTC(msg.sender, debt);

        // CEI: Send the collateral and liquidator reward shares back to the user
        activePool.transferSystemCollSharesAndLiquidatorRewardShares(
            msg.sender,
            coll,
            liquidatorRewardShares
        );
    }

    /**
     * Claim remaining collateral from a redemption or from a liquidation with ICR > MCR in Recovery Mode

      when a borrower’s Cdp has been fully redeemed from and closed, or liquidated in Recovery Mode with a collateralization ratio above 110%, this function allows the borrower to claim their stETH collateral surplus that remains in the system (collateral - debt upon redemption; collateral - 110% of the debt upon liquidation).
     */
    function claimSurplusCollShares() external override {
        // send ETH from CollSurplus Pool to owner
        collSurplusPool.claimColl(msg.sender);
    }

    // --- Helper functions ---

    /**
        @notice Calculate collateral shares change for a CDP from stEth balance change. Determine whether this change is positive or negative
        @dev This function is used in the context of a CDP adjustment, where the collateral change is either a top-up or a withdrawal
        @dev A given change in this context can only be a top-up OR a withdrawal, not both at once
        @param _stEthBalanceToIncrease stEth balance to increase CDP collateral by 
        @param _stEthBalanceToIncrease stEth balance to decrease CDP collateral by
     */
    function _getCollSharesChangeFromStEthBalanceChange(
        uint _stEthBalanceToIncrease,
        uint _stEthBalanceToDecrease
    ) internal view returns (uint collSharesChange, bool isCollIncrease) {
        // If balance to increase is positive, this is an increase
        if (_stEthBalanceToIncrease != 0) {
            collSharesChange = collateral.getSharesByPooledEth(_stEthBalanceToIncrease);
            isCollIncrease = true;
        } else {
            // Otherwise, this is a decrease. The calling function must have already determined one of these two input values is zero
            collSharesChange = collateral.getSharesByPooledEth(_stEthBalanceToDecrease);
        }
    }

    /**
        @notice Process the token movements required by a CDP adjustment.
        @notice Handles the cases of a debt increase / decrease, and/or a collateral increase / decrease.
     */
    function _processTokenMovesFromAdjustment(
        LocalVariables_moveTokens memory _varMvTokens
    ) internal {
        // Debt increase: mint change value of new eBTC to user, increment ActivePool eBTC internal accounting
        if (_varMvTokens.isDebtIncrease) {
            _withdrawEBTC(_varMvTokens.user, _varMvTokens.EBTCChange, _varMvTokens.debtChange);
        } else {
            // Debt decrease: burn change value of eBTC from user, decrement ActivePool eBTC internal accounting
            _repayEBTC(_varMvTokens.user, _varMvTokens.EBTCChange);
        }

        if (_varMvTokens.isCollIncrease) {
            // Coll increase: send change value of stETH to Active Pool, increment ActivePool stETH internal accounting
            _sendCollSharesToActivePool(
                _varMvTokens.collAddUnderlying,
                _varMvTokens.collSharesChange
            );
        } else {
            // Coll decrease: send change value of stETH to user, decrement ActivePool stETH internal accounting
            activePool.transferSystemCollShares(_varMvTokens.user, _varMvTokens.collSharesChange);
        }
    }

    /// @notice Send a given stETH balance to Active Pool and increase the system collateral shares accordingly
    /// @param _stEthBalance total balance of stETH to send, inclusive of coll and liquidatorRewardShares
    /// @param _collShares coll as shares (exclsuive of liquidator reward shares)
    /// @dev Liquidator reward shares are not explictly tracked by internal account and are  not considered as part of the system for CR purposes.
    /// @dev These number of liquidator shares associated with each CDP are stored in the CDP, while the actual tokens float in the active pool
    function _sendCollSharesToActivePool(uint _stEthBalance, uint _collShares) internal {
        // NOTE: No need for safe transfer if the collateral asset is standard. Make sure this is the case!
        collateral.transferFrom(msg.sender, address(activePool), _stEthBalance);
        activePool.receiveCollShares(_collShares);
    }

    // Issue the specified amount of EBTC to _account and increases
    // the total active debt
    function _withdrawEBTC(address _account, uint _EBTCAmount, uint _netDebtIncrease) internal {
        activePool.increaseSystemDebt(_netDebtIncrease);
        ebtcToken.mint(_account, _EBTCAmount);
    }

    // Burn the specified amount of EBTC from _account and decreases the total active debt
    function _repayEBTC(address _account, uint _EBTC) internal {
        activePool.decreaseSystemDebt(_EBTC);
        ebtcToken.burn(_account, _EBTC);
    }

    // --- 'Require' wrapper functions ---

    function _requireCdpOwner(bytes32 _cdpId) internal view {
        address _owner = sortedCdps.existCdpOwners(_cdpId);
        require(msg.sender == _owner, "BorrowerOperations: Caller must be cdp owner");
    }

    function _requireSingularCollChange(uint _stEthBalanceToIncrease, uint _stEthBalanceToDecrease) internal pure {
        require(
            _stEthBalanceToIncrease == 0 || _stEthBalanceToDecrease == 0,
            "BorrowerOperations: Cannot add and withdraw collateral in same operation"
        );
    }

    function _requireCallerIsBorrower(address _borrower) internal view {
        require(
            msg.sender == _borrower,
            "BorrowerOperations: Caller must be the borrower for a withdrawal"
        );
    }

    function _requireNonZeroAdjustment(
        uint _collAddAmount,
        uint _debtChange,
        uint _stEthBalanceToDecrease
    ) internal pure {
        require(
            _collAddAmount != 0 || _stEthBalanceToDecrease != 0 || _debtChange != 0,
            "BorrowerOperations: There must be either a collateral change or a debt change"
        );
    }

    function _requireCdpisActive(ICdpManager _cdpManager, bytes32 _cdpId) internal view {
        uint status = _cdpManager.getCdpStatus(_cdpId);
        require(status == 1, "BorrowerOperations: Cdp does not exist or is closed");
    }

    function _requireNonZeroDebtChange(uint _debtChange) internal pure {
        require(_debtChange > 0, "BorrowerOperations: Debt increase requires non-zero debtChange");
    }

    function _requireNotInRecoveryMode(uint _tcr) internal view {
        require(
            !_checkRecoveryModeForTCR(_tcr),
            "BorrowerOperations: Operation not permitted during Recovery Mode"
        );
    }

    function _requireNoCollWithdrawal(uint _stEthBalanceToDecrease) internal pure {
        require(
            _stEthBalanceToDecrease == 0,
            "BorrowerOperations: Collateral withdrawal not permitted Recovery Mode"
        );
    }

    function _requireValidAdjustmentInCurrentMode(
        bool _isRecoveryMode,
        uint _stEthBalanceToDecrease,
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
            _requireNoCollWithdrawal(_stEthBalanceToDecrease);
            if (_isDebtIncrease) {
                _requireICRisAboveCCR(_vars.newICR);
                _requireNewICRisAboveOldICR(_vars.newICR, _vars.oldICR);
            }
        } else {
            // if Normal Mode
            _requireICRisAboveMCR(_vars.newICR);
            _vars.newTCR = _getNewTCRFromCdpChange(
                collateral.getPooledEthByShares(_vars.collSharesChange),
                _vars.isCollIncrease,
                _vars.debtChange,
                _isDebtIncrease,
                _vars.price
            );
            _requireNewTCRisAboveCCR(_vars.newTCR);
        }
    }

    function _requireICRisAboveMCR(uint _newICR) internal pure {
        require(
            _newICR >= MCR,
            "BorrowerOperations: An operation that would result in ICR < MCR is not permitted"
        );
    }

    function _requireICRisAboveCCR(uint _newICR) internal pure {
        require(_newICR >= CCR, "BorrowerOperations: Operation must leave cdp with ICR >= CCR");
    }

    function _requireNewICRisAboveOldICR(uint _newICR, uint _oldICR) internal pure {
        require(
            _newICR >= _oldICR,
            "BorrowerOperations: Cannot decrease your Cdp's ICR in Recovery Mode"
        );
    }

    function _requireNewTCRisAboveCCR(uint _newTCR) internal pure {
        require(
            _newTCR >= CCR,
            "BorrowerOperations: An operation that would result in TCR < CCR is not permitted"
        );
    }

    function _requireNonZeroDebt(uint _debt) internal pure {
        require(_debt > 0, "BorrowerOperations: Debt must be non-zero");
    }

    function _requireAtLeastMinNetStEthBalance(uint _coll) internal pure {
        require(
            _coll >= MIN_CDP_STETH_BALANCE,
            "BorrowerOperations: Cdp's net coll must be greater than minimum"
        );
    }

    function _requireValidEBTCRepayment(uint _currentDebt, uint _debtRepayment) internal pure {
        require(
            _debtRepayment <= _currentDebt,
            "BorrowerOperations: Amount repaid must not be larger than the Cdp's debt"
        );
    }

    function _requireSufficientEBTCBalance(
        IEBTCToken _ebtcToken,
        address _borrower,
        uint _debtRepayment
    ) internal view {
        require(
            _ebtcToken.balanceOf(_borrower) >= _debtRepayment,
            "BorrowerOperations: Caller doesnt have enough EBTC to make repayment"
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
            vars.collSharesChange,
            vars.isCollIncrease,
            vars.debtChange,
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
        uint _systemCollShares = getEntireSystemColl();
        uint _systemStEthBalance = collateral.getPooledEthByShares(_systemCollShares);
        uint totalDebt = _getSystemDebt();

        _systemStEthBalance = _isCollIncrease
            ? _systemStEthBalance + _collChange
            : _systemStEthBalance - _collChange;
        totalDebt = _isDebtIncrease ? totalDebt + _debtChange : totalDebt - _debtChange;

        uint newTCR = LiquityMath._computeCR(_systemStEthBalance, totalDebt, _price);
        return newTCR;
    }

    // === Flash Loans === //
    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) external override returns (bool) {
        require(!flashLoansPaused, "BorrowerOperations: Flash Loans Paused");
        require(amount > 0, "BorrowerOperations: 0 Amount");
        uint256 fee = flashFee(token, amount); // NOTE: Check for `eBTCToken` is implicit here
        require(amount <= maxFlashLoan(token), "BorrowerOperations: Too much");

        // Issue EBTC
        ebtcToken.mint(address(receiver), amount);

        // Callback
        require(
            receiver.onFlashLoan(msg.sender, token, amount, fee, data) == FLASH_SUCCESS_VALUE,
            "IERC3156: Callback failed"
        );

        // Gas: Repay from user balance, so we don't trigger a new SSTORE
        // Safe to use transferFrom and unchecked as it's a standard token
        // Also saves gas
        // Send both fee and amount to FEE_RECIPIENT, to burn allowance per EIP-3156
        ebtcToken.transferFrom(address(receiver), feeRecipientAddress, fee + amount);

        // Burn amount, from FEE_RECIPIENT
        ebtcToken.burn(feeRecipientAddress, amount);

        emit FlashLoanSuccess(address(receiver), token, amount, fee);

        return true;
    }

    function flashFee(address token, uint256 amount) public view override returns (uint256) {
        require(token == address(ebtcToken), "BorrowerOperations: EBTC Only");

        return (amount * feeBps) / MAX_BPS;
    }

    /// @dev Max flashloan, exclusively in ETH equals to the current balance
    function maxFlashLoan(address token) public view override returns (uint256) {
        if (token != address(ebtcToken)) {
            return 0;
        }
        return type(uint112).max;
    }

    // === Governed Functions ==

    function setFeeRecipientAddress(address _feeRecipientAddress) external requiresAuth {
        require(
            _feeRecipientAddress != address(0),
            "BorrowerOperations: Cannot set feeRecipient to zero address"
        );

        cdpManager.applyPendingGlobalState();

        feeRecipientAddress = _feeRecipientAddress;
        emit FeeRecipientAddressChanged(_feeRecipientAddress);
    }

    function setFeeBps(uint _newFee) external requiresAuth {
        require(_newFee <= MAX_FEE_BPS, "ERC3156FlashLender: _newFee should <= MAX_FEE_BPS");

        cdpManager.applyPendingGlobalState();

        // set new flash fee
        uint _oldFee = feeBps;
        feeBps = uint16(_newFee);
        emit FlashFeeSet(msg.sender, _oldFee, _newFee);
    }

    function setFlashLoansPaused(bool _paused) external requiresAuth {
        cdpManager.applyPendingGlobalState();

        flashLoansPaused = _paused;
        emit FlashLoansPaused(msg.sender, _paused);
    }
}
