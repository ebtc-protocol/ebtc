// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "./Interfaces/IBorrowerOperations.sol";
import "./Interfaces/ITroveManager.sol";
import "./Interfaces/IEBTCToken.sol";
import "./Interfaces/ICollSurplusPool.sol";
import "./Interfaces/ISortedTroves.sol";
import "./Interfaces/ILQTYStaking.sol";
import "./Dependencies/LiquityBase.sol";
import "./Dependencies/Ownable.sol";
import "./Dependencies/CheckContract.sol";
import "./Dependencies/console.sol";

contract BorrowerOperations is LiquityBase, Ownable, CheckContract, IBorrowerOperations {
    string constant public NAME = "BorrowerOperations";

    // --- Connected contract declarations ---

    ITroveManager public troveManager;

    address stabilityPoolAddress;

    address gasPoolAddress;

    ICollSurplusPool collSurplusPool;

    ILQTYStaking public lqtyStaking;
    address public lqtyStakingAddress;

    IEBTCToken public ebtcToken;

    // A doubly linked list of Troves, sorted by their collateral ratios
    ISortedTroves public sortedTroves;

    /* --- Variable container structs  ---

    Used to hold, return and assign variables inside a function, in order to avoid the error:
    "CompilerError: Stack too deep". */

     struct LocalVariables_adjustTrove {
        uint price;
        uint collChange;
        uint netDebtChange;
        bool isCollIncrease;
        uint debt;
        uint coll;
        uint oldICR;
        uint newICR;
        uint newTCR;
        uint EBTCFee;
        uint newDebt;
        uint newColl;
        uint stake;
    }

    struct LocalVariables_openTrove {
        uint price;
        uint EBTCFee;
        uint netDebt;
        uint compositeDebt;
        uint ICR;
        uint NICR;
        uint stake;
        uint arrayIndex;
    }

    struct ContractsCache {
        ITroveManager troveManager;
        IActivePool activePool;
        IEBTCToken ebtcToken;
    }

    enum BorrowerOperation {
        openTrove,
        closeTrove,
        adjustTrove
    }

    event TroveManagerAddressChanged(address _newTroveManagerAddress);
    event ActivePoolAddressChanged(address _activePoolAddress);
    event DefaultPoolAddressChanged(address _defaultPoolAddress);
    event StabilityPoolAddressChanged(address _stabilityPoolAddress);
    event GasPoolAddressChanged(address _gasPoolAddress);
    event CollSurplusPoolAddressChanged(address _collSurplusPoolAddress);
    event PriceFeedAddressChanged(address  _newPriceFeedAddress);
    event SortedTrovesAddressChanged(address _sortedTrovesAddress);
    event EBTCTokenAddressChanged(address _ebtcTokenAddress);
    event LQTYStakingAddressChanged(address _lqtyStakingAddress);

    event TroveCreated(bytes32 indexed _troveId, address indexed _borrower, uint arrayIndex);
    event TroveUpdated(bytes32 indexed _troveId, address indexed _borrower, uint _debt, uint _coll, uint stake, BorrowerOperation operation);
    event EBTCBorrowingFeePaid(bytes32 indexed _troveId, uint _EBTCFee);
    
    // --- Dependency setters ---

    function setAddresses(
        address _troveManagerAddress,
        address _activePoolAddress,
        address _defaultPoolAddress,
        address _stabilityPoolAddress,
        address _gasPoolAddress,
        address _collSurplusPoolAddress,
        address _priceFeedAddress,
        address _sortedTrovesAddress,
        address _ebtcTokenAddress,
        address _lqtyStakingAddress
    )
        external
        override
        onlyOwner
    {
        // This makes impossible to open a trove with zero withdrawn EBTC
        assert(MIN_NET_DEBT > 0);

        checkContract(_troveManagerAddress);
        checkContract(_activePoolAddress);
        checkContract(_defaultPoolAddress);
        checkContract(_stabilityPoolAddress);
        checkContract(_gasPoolAddress);
        checkContract(_collSurplusPoolAddress);
        checkContract(_priceFeedAddress);
        checkContract(_sortedTrovesAddress);
        checkContract(_ebtcTokenAddress);
        checkContract(_lqtyStakingAddress);

        troveManager = ITroveManager(_troveManagerAddress);
        activePool = IActivePool(_activePoolAddress);
        defaultPool = IDefaultPool(_defaultPoolAddress);
        stabilityPoolAddress = _stabilityPoolAddress;
        gasPoolAddress = _gasPoolAddress;
        collSurplusPool = ICollSurplusPool(_collSurplusPoolAddress);
        priceFeed = IPriceFeed(_priceFeedAddress);
        sortedTroves = ISortedTroves(_sortedTrovesAddress);
        ebtcToken = IEBTCToken(_ebtcTokenAddress);
        lqtyStakingAddress = _lqtyStakingAddress;
        lqtyStaking = ILQTYStaking(_lqtyStakingAddress);

        emit TroveManagerAddressChanged(_troveManagerAddress);
        emit ActivePoolAddressChanged(_activePoolAddress);
        emit DefaultPoolAddressChanged(_defaultPoolAddress);
        emit StabilityPoolAddressChanged(_stabilityPoolAddress);
        emit GasPoolAddressChanged(_gasPoolAddress);
        emit CollSurplusPoolAddressChanged(_collSurplusPoolAddress);
        emit PriceFeedAddressChanged(_priceFeedAddress);
        emit SortedTrovesAddressChanged(_sortedTrovesAddress);
        emit EBTCTokenAddressChanged(_ebtcTokenAddress);
        emit LQTYStakingAddressChanged(_lqtyStakingAddress);

        _renounceOwnership();
    }

    // --- Borrower Trove Operations ---

    function openTrove(uint _maxFeePercentage, uint _EBTCAmount, bytes32 _upperHint, bytes32 _lowerHint) external payable override {
        ContractsCache memory contractsCache = ContractsCache(troveManager, activePool, ebtcToken);
        LocalVariables_openTrove memory vars;

        vars.price = priceFeed.fetchPrice();
        bool isRecoveryMode = _checkRecoveryMode(vars.price);

        _requireValidMaxFeePercentage(_maxFeePercentage, isRecoveryMode);
//        _requireTroveisNotActive(contractsCache.troveManager, msg.sender);

        vars.EBTCFee;
        vars.netDebt = _EBTCAmount;

        if (!isRecoveryMode) {
            vars.EBTCFee = _triggerBorrowingFee(contractsCache.troveManager, contractsCache.ebtcToken, _EBTCAmount, _maxFeePercentage);
            vars.netDebt = vars.netDebt.add(vars.EBTCFee);
        }
        _requireAtLeastMinNetDebt(vars.netDebt);

        // ICR is based on the composite debt, i.e. the requested EBTC amount + EBTC borrowing fee + EBTC gas comp.
        vars.compositeDebt = _getCompositeDebt(vars.netDebt);
        assert(vars.compositeDebt > 0);
        
        vars.ICR = LiquityMath._computeCR(msg.value, vars.compositeDebt, vars.price);
        vars.NICR = LiquityMath._computeNominalCR(msg.value, vars.compositeDebt);

        if (isRecoveryMode) {
            _requireICRisAboveCCR(vars.ICR);
        } else {
            _requireICRisAboveMCR(vars.ICR);
            uint newTCR = _getNewTCRFromTroveChange(msg.value, true, vars.compositeDebt, true, vars.price);  // bools: coll increase, debt increase
            _requireNewTCRisAboveCCR(newTCR); 
        }

        // Set the trove struct's properties
        bytes32 _troveId = sortedTroves.insert(msg.sender, vars.NICR, _upperHint, _lowerHint);
		
        contractsCache.troveManager.setTroveStatus(_troveId, 1);
        contractsCache.troveManager.increaseTroveColl(_troveId, msg.value);
        contractsCache.troveManager.increaseTroveDebt(_troveId, vars.compositeDebt);

        contractsCache.troveManager.updateTroveRewardSnapshots(_troveId);
        vars.stake = contractsCache.troveManager.updateStakeAndTotalStakes(_troveId);

        vars.arrayIndex = contractsCache.troveManager.addTroveIdToArray(_troveId);
        emit TroveCreated(_troveId, msg.sender, vars.arrayIndex);

        // Move the ether to the Active Pool, and mint the EBTCAmount to the borrower
        _activePoolAddColl(contractsCache.activePool, msg.value);
        _withdrawEBTC(contractsCache.activePool, contractsCache.ebtcToken, msg.sender, _EBTCAmount, vars.netDebt);
        // Move the EBTC gas compensation to the Gas Pool
        _withdrawEBTC(contractsCache.activePool, contractsCache.ebtcToken, gasPoolAddress, EBTC_GAS_COMPENSATION, EBTC_GAS_COMPENSATION);

        emit TroveUpdated(_troveId, msg.sender, vars.compositeDebt, msg.value, vars.stake, BorrowerOperation.openTrove);
        emit EBTCBorrowingFeePaid(_troveId, vars.EBTCFee);
    }

    // Send ETH as collateral to a trove
    function addColl(bytes32 _troveId, bytes32 _upperHint, bytes32 _lowerHint) external payable override {
        _adjustTrove(_troveId, 0, 0, false, _upperHint, _lowerHint, 0);
    }

    // Send ETH as collateral to a trove. Called by only the Stability Pool.
    function moveETHGainToTrove(bytes32 _troveId, bytes32 _upperHint, bytes32 _lowerHint) external payable override {
        _requireCallerIsStabilityPool();
        _adjustTroveInternal(_troveId, 0, 0, false, _upperHint, _lowerHint, 0);
    }

    // Withdraw ETH collateral from a trove
    function withdrawColl(bytes32 _troveId, uint _collWithdrawal, bytes32 _upperHint, bytes32 _lowerHint) external override {
        _adjustTrove(_troveId, _collWithdrawal, 0, false, _upperHint, _lowerHint, 0);
    }

    // Withdraw EBTC tokens from a trove: mint new EBTC tokens to the owner, and increase the trove's debt accordingly
    function withdrawEBTC(bytes32 _troveId, uint _maxFeePercentage, uint _EBTCAmount, bytes32 _upperHint, bytes32 _lowerHint) external override {
        _adjustTrove(_troveId, 0, _EBTCAmount, true, _upperHint, _lowerHint, _maxFeePercentage);
    }

    // Repay EBTC tokens to a Trove: Burn the repaid EBTC tokens, and reduce the trove's debt accordingly
    function repayEBTC(bytes32 _troveId, uint _EBTCAmount, bytes32 _upperHint, bytes32 _lowerHint) external override {
        _adjustTrove(_troveId, 0, _EBTCAmount, false, _upperHint, _lowerHint, 0);
    }

    function adjustTrove(bytes32 _troveId, uint _maxFeePercentage, uint _collWithdrawal, uint _EBTCChange, bool _isDebtIncrease, bytes32 _upperHint, bytes32 _lowerHint) external payable override {
        _adjustTrove(_troveId, _collWithdrawal, _EBTCChange, _isDebtIncrease, _upperHint, _lowerHint, _maxFeePercentage);
    }
	
    function _adjustTrove(bytes32 _troveId, uint _collWithdrawal, uint _EBTCChange, bool _isDebtIncrease, bytes32 _upperHint, bytes32 _lowerHint, uint _maxFeePercentage) internal {
        _requireTroveOwner(_troveId);	
        _adjustTroveInternal(_troveId, _collWithdrawal, _EBTCChange, _isDebtIncrease, _upperHint, _lowerHint, _maxFeePercentage);
    }

    /*
    * _adjustTrove(): Alongside a debt change, this function can perform either a collateral top-up or a collateral withdrawal. 
    *
    * It therefore expects either a positive msg.value, or a positive _collWithdrawal argument.
    *
    * If both are positive, it will revert.
    */
    function _adjustTroveInternal(bytes32 _troveId, uint _collWithdrawal, uint _EBTCChange, bool _isDebtIncrease, bytes32 _upperHint, bytes32 _lowerHint, uint _maxFeePercentage) internal {
		
        ContractsCache memory contractsCache = ContractsCache(troveManager, activePool, ebtcToken);
        LocalVariables_adjustTrove memory vars;

        _requireTroveisActive(contractsCache.troveManager, _troveId);

        vars.price = priceFeed.fetchPrice();
        bool isRecoveryMode = _checkRecoveryMode(vars.price);

        if (_isDebtIncrease) {
            _requireValidMaxFeePercentage(_maxFeePercentage, isRecoveryMode);
            _requireNonZeroDebtChange(_EBTCChange);
        }
        _requireSingularCollChange(_collWithdrawal);
        _requireNonZeroAdjustment(_collWithdrawal, _EBTCChange);
        

        // Confirm the operation is either a borrower adjusting their own trove, or a pure ETH transfer from the Stability Pool to a trove
        address _borrower = sortedTroves.existTroveOwners(_troveId);
        assert(msg.sender == _borrower || (msg.sender == stabilityPoolAddress && msg.value > 0 && _EBTCChange == 0));

        contractsCache.troveManager.applyPendingRewards(_troveId);

        // Get the collChange based on whether or not ETH was sent in the transaction
        (vars.collChange, vars.isCollIncrease) = _getCollChange(msg.value, _collWithdrawal);

        vars.netDebtChange = _EBTCChange;

        // If the adjustment incorporates a debt increase and system is in Normal Mode, then trigger a borrowing fee
        if (_isDebtIncrease && !isRecoveryMode) { 
            vars.EBTCFee = _triggerBorrowingFee(contractsCache.troveManager, contractsCache.ebtcToken, _EBTCChange, _maxFeePercentage);
            vars.netDebtChange = vars.netDebtChange.add(vars.EBTCFee); // The raw debt change includes the fee
        }

        vars.debt = contractsCache.troveManager.getTroveDebt(_troveId);
        vars.coll = contractsCache.troveManager.getTroveColl(_troveId);
        
        // Get the trove's old ICR before the adjustment, and what its new ICR will be after the adjustment
        vars.oldICR = LiquityMath._computeCR(vars.coll, vars.debt, vars.price);
        vars.newICR = _getNewICRFromTroveChange(vars.coll, vars.debt, vars.collChange, vars.isCollIncrease, vars.netDebtChange, _isDebtIncrease, vars.price);
        assert(_collWithdrawal <= vars.coll); 

        // Check the adjustment satisfies all conditions for the current system mode
        _requireValidAdjustmentInCurrentMode(isRecoveryMode, _collWithdrawal, _isDebtIncrease, vars);
            
        // When the adjustment is a debt repayment, check it's a valid amount and that the caller has enough EBTC
        if (!_isDebtIncrease && _EBTCChange > 0) {
            _requireAtLeastMinNetDebt(_getNetDebt(vars.debt).sub(vars.netDebtChange));
            _requireValidEBTCRepayment(vars.debt, vars.netDebtChange);
            _requireSufficientEBTCBalance(contractsCache.ebtcToken, _borrower, vars.netDebtChange);
        }

        (vars.newColl, vars.newDebt) = _updateTroveFromAdjustment(contractsCache.troveManager, _troveId, vars.collChange, vars.isCollIncrease, vars.netDebtChange, _isDebtIncrease);
        vars.stake = contractsCache.troveManager.updateStakeAndTotalStakes(_troveId);

        // Re-insert trove in to the sorted list
        uint newNICR = _getNewNominalICRFromTroveChange(vars.coll, vars.debt, vars.collChange, vars.isCollIncrease, vars.netDebtChange, _isDebtIncrease);
        sortedTroves.reInsert(_troveId, newNICR, _upperHint, _lowerHint);

        emit TroveUpdated(_troveId, _borrower, vars.newDebt, vars.newColl, vars.stake, BorrowerOperation.adjustTrove);
        emit EBTCBorrowingFeePaid(_troveId,  vars.EBTCFee);

        // Use the unmodified _EBTCChange here, as we don't send the fee to the user
        _moveTokensAndETHfromAdjustment(
            contractsCache.activePool,
            contractsCache.ebtcToken,
            msg.sender,
            vars.collChange,
            vars.isCollIncrease,
            _EBTCChange,
            _isDebtIncrease,
            vars.netDebtChange
        );
    }

    function closeTrove(bytes32 _troveId) external override {
        _requireTroveOwner(_troveId);
		
        ITroveManager troveManagerCached = troveManager;
        IActivePool activePoolCached = activePool;
        IEBTCToken ebtcTokenCached = ebtcToken;

        _requireTroveisActive(troveManagerCached, _troveId);
        uint price = priceFeed.fetchPrice();
        _requireNotInRecoveryMode(price);

        troveManagerCached.applyPendingRewards(_troveId);

        uint coll = troveManagerCached.getTroveColl(_troveId);
        uint debt = troveManagerCached.getTroveDebt(_troveId);

        _requireSufficientEBTCBalance(ebtcTokenCached, msg.sender, debt.sub(EBTC_GAS_COMPENSATION));

        uint newTCR = _getNewTCRFromTroveChange(coll, false, debt, false, price);
        _requireNewTCRisAboveCCR(newTCR);

        troveManagerCached.removeStake(_troveId);
        troveManagerCached.closeTrove(_troveId);

        // We already verified msg.sender is the borrower
        emit TroveUpdated(_troveId, msg.sender, 0, 0, 0, BorrowerOperation.closeTrove);

        // Burn the repaid EBTC from the user's balance and the gas compensation from the Gas Pool
        _repayEBTC(activePoolCached, ebtcTokenCached, msg.sender, debt.sub(EBTC_GAS_COMPENSATION));
        _repayEBTC(activePoolCached, ebtcTokenCached, gasPoolAddress, EBTC_GAS_COMPENSATION);

        // Send the collateral back to the user
        activePoolCached.sendETH(msg.sender, coll);
    }

    /**
     * Claim remaining collateral from a redemption or from a liquidation with ICR > MCR in Recovery Mode
     */
    function claimCollateral() external override {
        // send ETH from CollSurplus Pool to owner
        collSurplusPool.claimColl(msg.sender);
    }

    // --- Helper functions ---

    function _triggerBorrowingFee(ITroveManager _troveManager, IEBTCToken _ebtcToken, uint _EBTCAmount, uint _maxFeePercentage) internal returns (uint) {
        _troveManager.decayBaseRateFromBorrowing(); // decay the baseRate state variable
        uint EBTCFee = _troveManager.getBorrowingFee(_EBTCAmount);

        _requireUserAcceptsFee(EBTCFee, _EBTCAmount, _maxFeePercentage);
        
        // Send fee to LQTY staking contract
        lqtyStaking.increaseF_EBTC(EBTCFee);
        _ebtcToken.mint(lqtyStakingAddress, EBTCFee);

        return EBTCFee;
    }

    function _getUSDValue(uint _coll, uint _price) internal pure returns (uint) {
        uint usdValue = _price.mul(_coll).div(DECIMAL_PRECISION);

        return usdValue;
    }

    function _getCollChange(
        uint _collReceived,
        uint _requestedCollWithdrawal
    )
        internal
        pure
        returns(uint collChange, bool isCollIncrease)
    {
        if (_collReceived != 0) {
            collChange = _collReceived;
            isCollIncrease = true;
        } else {
            collChange = _requestedCollWithdrawal;
        }
    }

    // Update trove's coll and debt based on whether they increase or decrease
    function _updateTroveFromAdjustment
    (
        ITroveManager _troveManager,
        bytes32 _troveId,
        uint _collChange,
        bool _isCollIncrease,
        uint _debtChange,
        bool _isDebtIncrease
    )
        internal
        returns (uint, uint)
    {
        uint newColl = (_isCollIncrease) ? _troveManager.increaseTroveColl(_troveId, _collChange)
                                        : _troveManager.decreaseTroveColl(_troveId, _collChange);
        uint newDebt = (_isDebtIncrease) ? _troveManager.increaseTroveDebt(_troveId, _debtChange)
                                        : _troveManager.decreaseTroveDebt(_troveId, _debtChange);

        return (newColl, newDebt);
    }

    function _moveTokensAndETHfromAdjustment
    (
        IActivePool _activePool,
        IEBTCToken _ebtcToken,
        address _borrower,
        uint _collChange,
        bool _isCollIncrease,
        uint _EBTCChange,
        bool _isDebtIncrease,
        uint _netDebtChange
    )
        internal
    {
        if (_isDebtIncrease) {
            _withdrawEBTC(_activePool, _ebtcToken, _borrower, _EBTCChange, _netDebtChange);
        } else {
            _repayEBTC(_activePool, _ebtcToken, _borrower, _EBTCChange);
        }

        if (_isCollIncrease) {
            _activePoolAddColl(_activePool, _collChange);
        } else {
            _activePool.sendETH(_borrower, _collChange);
        }
    }

    // Send ETH to Active Pool and increase its recorded ETH balance
    function _activePoolAddColl(IActivePool _activePool, uint _amount) internal {
        (bool success, ) = address(_activePool).call{value: _amount}("");
        require(success, "BorrowerOps: Sending ETH to ActivePool failed");
    }

    // Issue the specified amount of EBTC to _account and increases the total active debt (_netDebtIncrease potentially includes a EBTCFee)
    function _withdrawEBTC(IActivePool _activePool, IEBTCToken _ebtcToken, address _account, uint _EBTCAmount, uint _netDebtIncrease) internal {
        _activePool.increaseEBTCDebt(_netDebtIncrease);
        _ebtcToken.mint(_account, _EBTCAmount);
    }

    // Burn the specified amount of EBTC from _account and decreases the total active debt
    function _repayEBTC(IActivePool _activePool, IEBTCToken _ebtcToken, address _account, uint _EBTC) internal {
        _activePool.decreaseEBTCDebt(_EBTC);
        _ebtcToken.burn(_account, _EBTC);
    }

    // --- 'Require' wrapper functions ---

    function _requireTroveOwner(bytes32 _troveId) internal view {
        address _owner = sortedTroves.existTroveOwners(_troveId);
        require(msg.sender == _owner, "BorrowerOps: Caller must be trove owner");
    }

    function _requireSingularCollChange(uint _collWithdrawal) internal view {
        require(msg.value == 0 || _collWithdrawal == 0, "BorrowerOperations: Cannot withdraw and add coll");
    }

    function _requireCallerIsBorrower(address _borrower) internal view {
        require(msg.sender == _borrower, "BorrowerOps: Caller must be the borrower for a withdrawal");
    }

    function _requireNonZeroAdjustment(uint _collWithdrawal, uint _EBTCChange) internal view {
        require(msg.value != 0 || _collWithdrawal != 0 || _EBTCChange != 0, "BorrowerOps: There must be either a collateral change or a debt change");
    }

    function _requireTroveisActive(ITroveManager _troveManager, bytes32 _troveId) internal view {
        uint status = _troveManager.getTroveStatus(_troveId);
        require(status == 1, "BorrowerOps: Trove does not exist or is closed");
    }

//    function _requireTroveisNotActive(ITroveManager _troveManager, address _borrower) internal view {
//        uint status = _troveManager.getTroveStatus(_borrower);
//        require(status != 1, "BorrowerOps: Trove is active");
//    }

    function _requireNonZeroDebtChange(uint _EBTCChange) internal pure {
        require(_EBTCChange > 0, "BorrowerOps: Debt increase requires non-zero debtChange");
    }
   
    function _requireNotInRecoveryMode(uint _price) internal view {
        require(!_checkRecoveryMode(_price), "BorrowerOps: Operation not permitted during Recovery Mode");
    }

    function _requireNoCollWithdrawal(uint _collWithdrawal) internal pure {
        require(_collWithdrawal == 0, "BorrowerOps: Collateral withdrawal not permitted Recovery Mode");
    }

    function _requireValidAdjustmentInCurrentMode 
    (
        bool _isRecoveryMode,
        uint _collWithdrawal,
        bool _isDebtIncrease, 
        LocalVariables_adjustTrove memory _vars
    ) 
        internal 
        view 
    {
        /* 
        *In Recovery Mode, only allow:
        *
        * - Pure collateral top-up
        * - Pure debt repayment
        * - Collateral top-up with debt repayment
        * - A debt increase combined with a collateral top-up which makes the ICR >= 150% and improves the ICR (and by extension improves the TCR).
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
        } else { // if Normal Mode
            _requireICRisAboveMCR(_vars.newICR);
            _vars.newTCR = _getNewTCRFromTroveChange(_vars.collChange, _vars.isCollIncrease, _vars.netDebtChange, _isDebtIncrease, _vars.price);
            _requireNewTCRisAboveCCR(_vars.newTCR);  
        }
    }

    function _requireICRisAboveMCR(uint _newICR) internal pure {
        require(_newICR >= MCR, "BorrowerOps: An operation that would result in ICR < MCR is not permitted");
    }

    function _requireICRisAboveCCR(uint _newICR) internal pure {
        require(_newICR >= CCR, "BorrowerOps: Operation must leave trove with ICR >= CCR");
    }

    function _requireNewICRisAboveOldICR(uint _newICR, uint _oldICR) internal pure {
        require(_newICR >= _oldICR, "BorrowerOps: Cannot decrease your Trove's ICR in Recovery Mode");
    }

    function _requireNewTCRisAboveCCR(uint _newTCR) internal pure {
        require(_newTCR >= CCR, "BorrowerOps: An operation that would result in TCR < CCR is not permitted");
    }

    function _requireAtLeastMinNetDebt(uint _netDebt) internal pure {
        require (_netDebt >= MIN_NET_DEBT, "BorrowerOps: Trove's net debt must be greater than minimum");
    }

    function _requireValidEBTCRepayment(uint _currentDebt, uint _debtRepayment) internal pure {
        require(_debtRepayment <= _currentDebt.sub(EBTC_GAS_COMPENSATION), "BorrowerOps: Amount repaid must not be larger than the Trove's debt");
    }

    function _requireCallerIsStabilityPool() internal view {
        require(msg.sender == stabilityPoolAddress, "BorrowerOps: Caller is not Stability Pool");
    }

     function _requireSufficientEBTCBalance(IEBTCToken _ebtcToken, address _borrower, uint _debtRepayment) internal view {
        require(_ebtcToken.balanceOf(_borrower) >= _debtRepayment, "BorrowerOps: Caller doesnt have enough EBTC to make repayment");
    }

    function _requireValidMaxFeePercentage(uint _maxFeePercentage, bool _isRecoveryMode) internal pure {
        if (_isRecoveryMode) {
            require(_maxFeePercentage <= DECIMAL_PRECISION,
                "Max fee percentage must less than or equal to 100%");
        } else {
            require(_maxFeePercentage >= BORROWING_FEE_FLOOR && _maxFeePercentage <= DECIMAL_PRECISION,
                "Max fee percentage must be between 0.5% and 100%");
        }
    }

    // --- ICR and TCR getters ---

    // Compute the new collateral ratio, considering the change in coll and debt. Assumes 0 pending rewards.
    function _getNewNominalICRFromTroveChange
    (
        uint _coll,
        uint _debt,
        uint _collChange,
        bool _isCollIncrease,
        uint _debtChange,
        bool _isDebtIncrease
    )
        pure
        internal
        returns (uint)
    {
        (uint newColl, uint newDebt) = _getNewTroveAmounts(_coll, _debt, _collChange, _isCollIncrease, _debtChange, _isDebtIncrease);

        uint newNICR = LiquityMath._computeNominalCR(newColl, newDebt);
        return newNICR;
    }

    // Compute the new collateral ratio, considering the change in coll and debt. Assumes 0 pending rewards.
    function _getNewICRFromTroveChange
    (
        uint _coll,
        uint _debt,
        uint _collChange,
        bool _isCollIncrease,
        uint _debtChange,
        bool _isDebtIncrease,
        uint _price
    )
        pure
        internal
        returns (uint)
    {
        (uint newColl, uint newDebt) = _getNewTroveAmounts(_coll, _debt, _collChange, _isCollIncrease, _debtChange, _isDebtIncrease);

        uint newICR = LiquityMath._computeCR(newColl, newDebt, _price);
        return newICR;
    }

    function _getNewTroveAmounts(
        uint _coll,
        uint _debt,
        uint _collChange,
        bool _isCollIncrease,
        uint _debtChange,
        bool _isDebtIncrease
    )
        internal
        pure
        returns (uint, uint)
    {
        uint newColl = _coll;
        uint newDebt = _debt;

        newColl = _isCollIncrease ? _coll.add(_collChange) :  _coll.sub(_collChange);
        newDebt = _isDebtIncrease ? _debt.add(_debtChange) : _debt.sub(_debtChange);

        return (newColl, newDebt);
    }

    function _getNewTCRFromTroveChange
    (
        uint _collChange,
        bool _isCollIncrease,
        uint _debtChange,
        bool _isDebtIncrease,
        uint _price
    )
        internal
        view
        returns (uint)
    {
        uint totalColl = getEntireSystemColl();
        uint totalDebt = getEntireSystemDebt();

        totalColl = _isCollIncrease ? totalColl.add(_collChange) : totalColl.sub(_collChange);
        totalDebt = _isDebtIncrease ? totalDebt.add(_debtChange) : totalDebt.sub(_debtChange);

        uint newTCR = LiquityMath._computeCR(totalColl, totalDebt, _price);
        return newTCR;
    }

    function getCompositeDebt(uint _debt) external pure override returns (uint) {
        return _getCompositeDebt(_debt);
    }
}
