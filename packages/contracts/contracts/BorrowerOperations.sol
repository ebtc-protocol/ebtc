// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import {LeverageMacro} from "./LeverageMacro.sol";

import "./Interfaces/IBorrowerOperations.sol";
import "./Interfaces/ICdpManager.sol";
import "./Interfaces/IEBTCToken.sol";
import "./Interfaces/ICollSurplusPool.sol";
import "./Interfaces/ISortedCdps.sol";
import "./Interfaces/IFeeRecipient.sol";
import "./Dependencies/LiquityBase.sol";

import "./Dependencies/ERC3156FlashLender.sol";

contract BorrowerOperations is LiquityBase, IBorrowerOperations, ERC3156FlashLender {
    string public constant NAME = "BorrowerOperations";

    // --- Connected contract declarations ---

    LeverageMacro public immutable theMacro;

    ICdpManager public cdpManager;

    address immutable gasPoolAddress;

    ICollSurplusPool immutable collSurplusPool;

    IFeeRecipient public feeRecipient;

    IEBTCToken public immutable ebtcToken;

    // A doubly linked list of Cdps, sorted by their collateral ratios
    ISortedCdps public immutable sortedCdps;

    /* --- Variable container structs  ---

    Used to hold, return and assign variables inside a function, in order to avoid the error:
    "CompilerError: Stack too deep". */

    struct LocalVariables_adjustCdp {
        uint256 price;
        uint256 collChange;
        uint256 netDebtChange;
        bool isCollIncrease;
        uint256 debt;
        uint256 coll;
        uint256 oldICR;
        uint256 newICR;
        uint256 newTCR;
        uint256 newDebt;
        uint256 newColl;
        uint256 stake;
    }

    struct LocalVariables_openCdp {
        uint256 price;
        uint256 netDebt;
        uint256 compositeDebt;
        uint256 ICR;
        uint256 NICR;
        uint256 stake;
        uint256 arrayIndex;
    }

    struct LocalVariables_moveTokens {
        address user;
        uint256 collChange;
        uint256 collAddUnderlying; // ONLY for isCollIncrease=true
        bool isCollIncrease;
        uint256 EBTCChange;
        bool isDebtIncrease;
        uint256 netDebtChange;
    }

    struct ContractsCache {
        ICdpManager cdpManager;
        IActivePool activePool;
        IEBTCToken ebtcToken;
    }

    // --- Dependency setters ---
    constructor(
        address _cdpManagerAddress,
        address _activePoolAddress,
        address _defaultPoolAddress,
        address _gasPoolAddress,
        address _collSurplusPoolAddress,
        address _priceFeedAddress,
        address _sortedCdpsAddress,
        address _ebtcTokenAddress,
        address _feeRecipientAddress,
        address _collTokenAddress,
        address _macroAddress
    ) LiquityBase(_activePoolAddress, _defaultPoolAddress, _priceFeedAddress, _collTokenAddress) {
        // We no longer checkContract() here, because the contracts we depend on may not yet be deployed.

        // This makes impossible to open a cdp with zero withdrawn EBTC
        assert(MIN_NET_DEBT > 0);

        cdpManager = ICdpManager(_cdpManagerAddress);
        gasPoolAddress = _gasPoolAddress;
        collSurplusPool = ICollSurplusPool(_collSurplusPoolAddress);
        sortedCdps = ISortedCdps(_sortedCdpsAddress);
        ebtcToken = IEBTCToken(_ebtcTokenAddress);
        feeRecipient = IFeeRecipient(_feeRecipientAddress);
        theMacro = LeverageMacro(_macroAddress);

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

        // No longer need a concept of ownership if there is no initializer
    }

    // --- Borrower Cdp Operations ---

    /**
     * @notice Function that creates a Cdp for the caller with the requested debt, and the stETH received as collateral. 
     * @notice Successful execution is conditional mainly on the resulting collateralization ratio which must exceed the minimum (110% in Normal Mode, 150% in Recovery Mode). 
     * @notice In addition to the requested debt, extra debt is issued to cover the gas compensation.
     */
    function openCdp(uint256 _EBTCAmount, bytes32 _upperHint, bytes32 _lowerHint, uint256 _collAmount)
        external
        override
        returns (bytes32)
    {
        return _openCdp(_EBTCAmount, _upperHint, _lowerHint, _collAmount, msg.sender);
    }

    /**
     * LEVERAGE MACRO FUNCTIONS
     */

    /// @dev Ensures that the caller is macro and the forwarded caller is the owner
    function _requireForwardedCdpOwner(bytes32 _cdpId, address owner) internal view {
        // Only macro
        require(msg.sender == address(theMacro));

        address _owner = sortedCdps.existCdpOwners(_cdpId);
        require(owner == _owner, "BorrowerOps: Caller must be cdp owner");
    }
    /**
     * @notice Function that creates a Cdp for a specified borrower with the requested debt, and the stETH received as collateral. 
     * @notice Successful execution is conditional mainly on the resulting collateralization ratio which must exceed the minimum (110% in Normal Mode, 150% in Recovery Mode). 
     * @notice In addition to the requested debt, extra debt is issued to cover the gas compensation.
     */

    function openCdpFor(
        uint256 _EBTCAmount,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _collAmount,
        address _borrower
    ) external override returns (bytes32) {
        return _openCdp(_EBTCAmount, _upperHint, _lowerHint, _collAmount, _borrower);
    }

    function adjustCdpFor(
        bytes32 _cdpId,
        uint256 _collWithdrawal,
        uint256 _EBTCChange,
        bool _isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _collAddAmount,
        address forwardedCaller
    ) external {
        _requireForwardedCdpOwner(_cdpId, forwardedCaller);
        _adjustCdpInternal(
            _cdpId, _collWithdrawal, _EBTCChange, _isDebtIncrease, _upperHint, _lowerHint, _collAddAmount
        );
    }

    function closeCdpFor(bytes32 _cdpId, address forwardedCaller) external {
        _requireForwardedCdpOwner(_cdpId, forwardedCaller);
        _closeCdp(_cdpId);
    }

    /**
     * END LEVERAGE MACRO FUNCTIONS
     */

    // Function that adds the received stETH to the caller's specified Cdp.
    function addColl(bytes32 _cdpId, bytes32 _upperHint, bytes32 _lowerHint, uint256 _collAmount) external override {
        _adjustCdp(_cdpId, 0, 0, false, _upperHint, _lowerHint, _collAmount);
    }

    /**
     * Withdraws `_collWithdrawal` amount of collateral from the caller’s Cdp. Executes only if the user has an active Cdp, the withdrawal would not pull the user’s Cdp below the minimum collateralization ratio, and the resulting total collateralization ratio of the system is above 150%.
     */
    function withdrawColl(bytes32 _cdpId, uint256 _collWithdrawal, bytes32 _upperHint, bytes32 _lowerHint)
        external
        override
    {
        _adjustCdp(_cdpId, _collWithdrawal, 0, false, _upperHint, _lowerHint, 0);
    }

    // Withdraw EBTC tokens from a cdp: mint new EBTC tokens to the owner, and increase the cdp's debt accordingly
    /**
     * Issues `_amount` of eBTC from the caller’s Cdp to the caller. Executes only if the Cdp's collateralization ratio would remain above the minimum, and the resulting total collateralization ratio is above 150%.
     */
    function withdrawEBTC(bytes32 _cdpId, uint256 _EBTCAmount, bytes32 _upperHint, bytes32 _lowerHint)
        external
        override
    {
        _adjustCdp(_cdpId, 0, _EBTCAmount, true, _upperHint, _lowerHint, 0);
    }

    // Repay EBTC tokens to a Cdp: Burn the repaid EBTC tokens, and reduce the cdp's debt accordingly
    /**
     * repay `_amount` of eBTC to the caller’s Cdp, subject to leaving 50 debt in the Cdp (which corresponds to the 50 eBTC gas compensation).
     */
    function repayEBTC(bytes32 _cdpId, uint256 _EBTCAmount, bytes32 _upperHint, bytes32 _lowerHint) external override {
        _adjustCdp(_cdpId, 0, _EBTCAmount, false, _upperHint, _lowerHint, 0);
    }

    function adjustCdp(
        bytes32 _cdpId,
        uint256 _collWithdrawal,
        uint256 _EBTCChange,
        bool _isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external override {
        _adjustCdp(_cdpId, _collWithdrawal, _EBTCChange, _isDebtIncrease, _upperHint, _lowerHint, 0);
    }

    /**
     * enables a borrower to simultaneously change both their collateral and debt, subject to all the restrictions that apply to individual increases/decreases of each quantity with the following particularity: if the adjustment reduces the collateralization ratio of the Cdp, the function only executes if the resulting total collateralization ratio is above 150%. The borrower has to provide a `_maxFeePercentage` that he/she is willing to accept in case of a fee slippage, i.e. when a redemption transaction is processed first, driving up the issuance fee. The parameter is ignored if the debt is not increased with the transaction.
     */
    // TODO optimization candidate
    function adjustCdpWithColl(
        bytes32 _cdpId,
        uint256 _collWithdrawal,
        uint256 _EBTCChange,
        bool _isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _collAddAmount
    ) external override {
        _adjustCdp(_cdpId, _collWithdrawal, _EBTCChange, _isDebtIncrease, _upperHint, _lowerHint, _collAddAmount);
    }

    function _adjustCdp(
        bytes32 _cdpId,
        uint256 _collWithdrawal,
        uint256 _EBTCChange,
        bool _isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _collAddAmount
    ) internal {
        _requireCdpOwner(_cdpId);
        _adjustCdpInternal(
            _cdpId, _collWithdrawal, _EBTCChange, _isDebtIncrease, _upperHint, _lowerHint, _collAddAmount
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
        uint256 _collWithdrawal,
        uint256 _EBTCChange,
        bool _isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _collAddAmount
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
        uint256 _cdpCollAmt = collateral.getPooledEthByShares(vars.coll);
        vars.oldICR = LiquityMath._computeCR(_cdpCollAmt, vars.debt, vars.price);
        vars.newICR = _getNewICRFromCdpChange(
            vars.coll, vars.debt, vars.collChange, vars.isCollIncrease, vars.netDebtChange, _isDebtIncrease, vars.price
        );
        assert(_collWithdrawal <= _cdpCollAmt);

        // Check the adjustment satisfies all conditions for the current system mode
        _requireValidAdjustmentInCurrentMode(isRecoveryMode, _collWithdrawal, _isDebtIncrease, vars);

        // When the adjustment is a debt repayment, check it's a valid amount and that the caller has enough EBTC
        if (!_isDebtIncrease && _EBTCChange > 0) {
            uint256 _netDebt = _getNetDebt(vars.debt) - vars.netDebtChange;
            _requireAtLeastMinNetDebt(_convertDebtDenominationToEth(_netDebt, vars.price));
            _requireValidEBTCRepayment(vars.debt, vars.netDebtChange);
            _requireSufficientEBTCBalance(contractsCache.ebtcToken, _borrower, vars.netDebtChange);
        }

        (vars.newColl, vars.newDebt) = _updateCdpFromAdjustment(
            contractsCache.cdpManager, _cdpId, vars.collChange, vars.isCollIncrease, vars.netDebtChange, _isDebtIncrease
        );
        vars.stake = contractsCache.cdpManager.updateStakeAndTotalStakes(_cdpId);

        // Re-insert cdp in to the sorted list
        {
            uint256 newNICR = _getNewNominalICRFromCdpChange(vars, _isDebtIncrease);
            sortedCdps.reInsert(_cdpId, newNICR, _upperHint, _lowerHint);
        }

        emit CdpUpdated(
            _cdpId, _borrower, vars.debt, vars.coll, vars.newDebt, vars.newColl, vars.stake, BorrowerOperation.adjustCdp
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
            _moveTokensAndETHfromAdjustment(contractsCache.activePool, contractsCache.ebtcToken, _varMvTokens);
        }
    }

    function _openCdp(
        uint256 _EBTCAmount,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _collAmount,
        address _borrower
    ) internal returns (bytes32) {
        require(_collAmount > 0, "BorrowerOps: collateral for CDP is zero");

        ContractsCache memory contractsCache = ContractsCache(cdpManager, activePool, ebtcToken);
        LocalVariables_openCdp memory vars;

        vars.price = priceFeed.fetchPrice();
        // Reverse ETH/BTC price to BTC/ETH
        bool isRecoveryMode = _checkRecoveryMode(vars.price);

        vars.netDebt = _EBTCAmount;

        _requireAtLeastMinNetDebt(_convertDebtDenominationToEth(vars.netDebt, vars.price));

        // ICR is based on the composite debt, i.e. the requested EBTC amount + EBTC gas comp.
        vars.compositeDebt = _getCompositeDebt(vars.netDebt);
        assert(vars.compositeDebt > 0);

        uint256 _collShareAmt = collateral.getSharesByPooledEth(_collAmount);
        vars.ICR = LiquityMath._computeCR(_collAmount, vars.compositeDebt, vars.price);
        vars.NICR = LiquityMath._computeNominalCR(_collShareAmt, vars.compositeDebt);

        if (isRecoveryMode) {
            _requireICRisAboveCCR(vars.ICR);
        } else {
            _requireICRisAboveMCR(vars.ICR);
            uint256 newTCR = _getNewTCRFromCdpChange(_collAmount, true, vars.compositeDebt, true, vars.price); // bools: coll increase, debt increase
            _requireNewTCRisAboveCCR(newTCR);
        }

        // Set the cdp struct's properties
        bytes32 _cdpId = sortedCdps.insert(_borrower, vars.NICR, _upperHint, _lowerHint);

        contractsCache.cdpManager.setCdpStatus(_cdpId, 1);
        contractsCache.cdpManager.increaseCdpColl(_cdpId, _collShareAmt);
        contractsCache.cdpManager.increaseCdpDebt(_cdpId, vars.compositeDebt);

        contractsCache.cdpManager.updateCdpRewardSnapshots(_cdpId);
        vars.stake = contractsCache.cdpManager.updateStakeAndTotalStakes(_cdpId);

        vars.arrayIndex = contractsCache.cdpManager.addCdpIdToArray(_cdpId);
        emit CdpCreated(_cdpId, _borrower, msg.sender, vars.arrayIndex);

        // Mint the EBTCAmount to the borrower
        _withdrawEBTC(contractsCache.activePool, contractsCache.ebtcToken, _borrower, _EBTCAmount, vars.netDebt);
        // Move the EBTC gas compensation to the Gas Pool
        _withdrawEBTC(
            contractsCache.activePool,
            contractsCache.ebtcToken,
            gasPoolAddress,
            EBTC_GAS_COMPENSATION,
            EBTC_GAS_COMPENSATION
        );

        emit CdpUpdated(
            _cdpId, _borrower, 0, 0, vars.compositeDebt, _collShareAmt, vars.stake, BorrowerOperation.openCdp
        );

        // CEI: Move the collateral to the Active Pool
        _activePoolAddColl(contractsCache.activePool, _collAmount, _collShareAmt);

        return _cdpId;
    }

    function _closeCdp(bytes32 _cdpId) internal {
        ICdpManager cdpManagerCached = cdpManager;
        IActivePool activePoolCached = activePool;
        IEBTCToken ebtcTokenCached = ebtcToken;

        _requireCdpisActive(cdpManagerCached, _cdpId);
        uint256 price = priceFeed.fetchPrice();
        _requireNotInRecoveryMode(price);

        cdpManagerCached.applyPendingRewards(_cdpId);

        uint256 coll = cdpManagerCached.getCdpColl(_cdpId);
        uint256 debt = cdpManagerCached.getCdpDebt(_cdpId);

        _requireSufficientEBTCBalance(ebtcTokenCached, msg.sender, debt - EBTC_GAS_COMPENSATION);

        uint256 newTCR = _getNewTCRFromCdpChange(collateral.getPooledEthByShares(coll), false, debt, false, price);
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
     * allows a borrower to repay all debt, withdraw all their collateral, and close their Cdp. Requires the borrower have a eBTC balance sufficient to repay their cdp's debt, excluding gas compensation - i.e. `(debt - 50)` eBTC.
     */
    function closeCdp(bytes32 _cdpId) external override {
        _requireCdpOwner(_cdpId);
        _closeCdp(_cdpId);
    }

    /**
     * Claim remaining collateral from a redemption or from a liquidation with ICR > MCR in Recovery Mode
     * 
     *   when a borrower’s Cdp has been fully redeemed from and closed, or liquidated in Recovery Mode with a collateralization ratio above 110%, this function allows the borrower to claim their stETH collateral surplus that remains in the system (collateral - debt upon redemption; collateral - 110% of the debt upon liquidation).
     */
    function claimCollateral() external override {
        // send ETH from CollSurplus Pool to owner
        collSurplusPool.claimColl(msg.sender);
    }

    // --- Helper functions ---

    function _getUSDValue(uint256 _coll, uint256 _price) internal pure returns (uint256) {
        uint256 usdValue = (_price * _coll) / DECIMAL_PRECISION;

        return usdValue;
    }

    function _getCollChange(uint256 _collReceived, uint256 _requestedCollWithdrawal)
        internal
        view
        returns (uint256 collChange, bool isCollIncrease)
    {
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
        uint256 _collChange,
        bool _isCollIncrease,
        uint256 _debtChange,
        bool _isDebtIncrease
    ) internal returns (uint256, uint256) {
        uint256 newColl = (_isCollIncrease)
            ? _cdpManager.increaseCdpColl(_cdpId, _collChange)
            : _cdpManager.decreaseCdpColl(_cdpId, _collChange);
        uint256 newDebt = (_isDebtIncrease)
            ? _cdpManager.increaseCdpDebt(_cdpId, _debtChange)
            : _cdpManager.decreaseCdpDebt(_cdpId, _debtChange);

        return (newColl, newDebt);
    }

    function _moveTokensAndETHfromAdjustment(
        IActivePool _activePool,
        IEBTCToken _ebtcToken,
        LocalVariables_moveTokens memory _varMvTokens
    ) internal {
        if (_varMvTokens.isDebtIncrease) {
            _withdrawEBTC(
                _activePool, _ebtcToken, _varMvTokens.user, _varMvTokens.EBTCChange, _varMvTokens.netDebtChange
            );
        } else {
            _repayEBTC(_activePool, _ebtcToken, _varMvTokens.user, _varMvTokens.EBTCChange);
        }

        if (_varMvTokens.isCollIncrease) {
            _activePoolAddColl(_activePool, _varMvTokens.collAddUnderlying, _varMvTokens.collChange);
        } else {
            _activePool.sendStEthColl(_varMvTokens.user, _varMvTokens.collChange);
        }
    }

    // Send ETH to Active Pool and increase its recorded ETH balance
    function _activePoolAddColl(IActivePool _activePool, uint256 _amount, uint256 _shareAmt) internal {
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
        uint256 _EBTCAmount,
        uint256 _netDebtIncrease
    ) internal {
        _activePool.increaseEBTCDebt(_netDebtIncrease);
        _ebtcToken.mint(_account, _EBTCAmount);
    }

    // Burn the specified amount of EBTC from _account and decreases the total active debt
    function _repayEBTC(IActivePool _activePool, IEBTCToken _ebtcToken, address _account, uint256 _EBTC) internal {
        _activePool.decreaseEBTCDebt(_EBTC);
        _ebtcToken.burn(_account, _EBTC);
    }

    // --- 'Require' wrapper functions ---

    function _requireCdpOwner(bytes32 _cdpId) internal view {
        address _owner = sortedCdps.existCdpOwners(_cdpId);
        require(msg.sender == _owner, "BorrowerOps: Caller must be cdp owner");
    }

    function _requireSingularCollChange(uint256 _collAdd, uint256 _collWithdrawal) internal pure {
        require(_collAdd == 0 || _collWithdrawal == 0, "BorrowerOperations: Cannot withdraw and add coll");
    }

    function _requireCallerIsBorrower(address _borrower) internal view {
        require(msg.sender == _borrower, "BorrowerOps: Caller must be the borrower for a withdrawal");
    }

    function _requireNonZeroAdjustment(uint256 _collAddAmount, uint256 _EBTCChange, uint256 _collWithdrawal)
        internal
        pure
    {
        require(
            _collAddAmount != 0 || _collWithdrawal != 0 || _EBTCChange != 0,
            "BorrowerOps: There must be either a collateral change or a debt change"
        );
    }

    function _requireCdpisActive(ICdpManager _cdpManager, bytes32 _cdpId) internal view {
        uint256 status = _cdpManager.getCdpStatus(_cdpId);
        require(status == 1, "BorrowerOps: Cdp does not exist or is closed");
    }

    //    function _requireCdpisNotActive(ICdpManager _cdpManager, address _borrower) internal view {
    //        uint status = _cdpManager.getCdpStatus(_borrower);
    //        require(status != 1, "BorrowerOps: Cdp is active");
    //    }

    function _requireNonZeroDebtChange(uint256 _EBTCChange) internal pure {
        require(_EBTCChange > 0, "BorrowerOps: Debt increase requires non-zero debtChange");
    }

    function _requireNotInRecoveryMode(uint256 _price) internal view {
        require(!_checkRecoveryMode(_price), "BorrowerOps: Operation not permitted during Recovery Mode");
    }

    function _requireNoCollWithdrawal(uint256 _collWithdrawal) internal pure {
        require(_collWithdrawal == 0, "BorrowerOps: Collateral withdrawal not permitted Recovery Mode");
    }

    function _requireValidAdjustmentInCurrentMode(
        bool _isRecoveryMode,
        uint256 _collWithdrawal,
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

    function _requireICRisAboveMCR(uint256 _newICR) internal pure {
        require(_newICR >= MCR, "BorrowerOps: An operation that would result in ICR < MCR is not permitted");
    }

    function _requireICRisAboveCCR(uint256 _newICR) internal pure {
        require(_newICR >= CCR, "BorrowerOps: Operation must leave cdp with ICR >= CCR");
    }

    function _requireNewICRisAboveOldICR(uint256 _newICR, uint256 _oldICR) internal pure {
        require(_newICR >= _oldICR, "BorrowerOps: Cannot decrease your Cdp's ICR in Recovery Mode");
    }

    function _requireNewTCRisAboveCCR(uint256 _newTCR) internal pure {
        require(_newTCR >= CCR, "BorrowerOps: An operation that would result in TCR < CCR is not permitted");
    }

    function _requireAtLeastMinNetDebt(uint256 _netDebt) internal pure {
        require(_netDebt >= MIN_NET_DEBT, "BorrowerOps: Cdp's net debt must be greater than minimum");
    }

    function _requireValidEBTCRepayment(uint256 _currentDebt, uint256 _debtRepayment) internal pure {
        require(
            _debtRepayment <= _currentDebt - EBTC_GAS_COMPENSATION,
            "BorrowerOps: Amount repaid must not be larger than the Cdp's debt"
        );
    }

    function _requireSufficientEBTCBalance(IEBTCToken _ebtcToken, address _borrower, uint256 _debtRepayment)
        internal
        view
    {
        require(
            _ebtcToken.balanceOf(_borrower) >= _debtRepayment,
            "BorrowerOps: Caller doesnt have enough EBTC to make repayment"
        );
    }

    // --- ICR and TCR getters ---

    // Compute the new collateral ratio, considering the change in coll and debt. Assumes 0 pending rewards.
    function _getNewNominalICRFromCdpChange(LocalVariables_adjustCdp memory vars, bool _isDebtIncrease)
        internal
        pure
        returns (uint256)
    {
        (uint256 newColl, uint256 newDebt) = _getNewCdpAmounts(
            vars.coll, vars.debt, vars.collChange, vars.isCollIncrease, vars.netDebtChange, _isDebtIncrease
        );

        uint256 newNICR = LiquityMath._computeNominalCR(newColl, newDebt);
        return newNICR;
    }

    // Compute the new collateral ratio, considering the change in coll and debt. Assumes 0 pending rewards.
    function _getNewICRFromCdpChange(
        uint256 _coll,
        uint256 _debt,
        uint256 _collChange,
        bool _isCollIncrease,
        uint256 _debtChange,
        bool _isDebtIncrease,
        uint256 _price
    ) internal view returns (uint256) {
        (uint256 newColl, uint256 newDebt) =
            _getNewCdpAmounts(_coll, _debt, _collChange, _isCollIncrease, _debtChange, _isDebtIncrease);

        uint256 newICR = LiquityMath._computeCR(collateral.getPooledEthByShares(newColl), newDebt, _price);
        return newICR;
    }

    function _getNewCdpAmounts(
        uint256 _coll,
        uint256 _debt,
        uint256 _collChange,
        bool _isCollIncrease,
        uint256 _debtChange,
        bool _isDebtIncrease
    ) internal pure returns (uint256, uint256) {
        uint256 newColl = _coll;
        uint256 newDebt = _debt;

        newColl = _isCollIncrease ? _coll + _collChange : _coll - _collChange;
        newDebt = _isDebtIncrease ? _debt + _debtChange : _debt - _debtChange;

        return (newColl, newDebt);
    }

    function _getNewTCRFromCdpChange(
        uint256 _collChange,
        bool _isCollIncrease,
        uint256 _debtChange,
        bool _isDebtIncrease,
        uint256 _price
    ) internal view returns (uint256) {
        uint256 _shareColl = getEntireSystemColl();
        uint256 totalColl = collateral.getPooledEthByShares(_shareColl);
        uint256 totalDebt = _getEntireSystemDebt();

        totalColl = _isCollIncrease ? totalColl + _collChange : totalColl - _collChange;
        totalDebt = _isDebtIncrease ? totalDebt + _debtChange : totalDebt - _debtChange;

        uint256 newTCR = LiquityMath._computeCR(totalColl, totalDebt, _price);
        return newTCR;
    }

    function getCompositeDebt(uint256 _debt) external pure override returns (uint256) {
        return _getCompositeDebt(_debt);
    }

    // === Flash Loans === //
    function flashLoan(IERC3156FlashBorrower receiver, address token, uint256 amount, bytes calldata data)
        external
        override
        returns (bool)
    {
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
