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

    // keccak256("permitPositionManagerApproval(address borrower,address positionManager,uint256 status,uint256 nonce,uint256 deadline)");
    bytes32 private constant _PERMIT_POSITION_MANAGER_TYPEHASH =
        keccak256(
            "PermitPositionManagerApproval(address borrower,address positionManager,uint256 status,uint256 nonce,uint256 deadline)"
        );

    // keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant _TYPE_HASH =
        0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;

    string internal constant _VERSION = "1";

    // Cache the domain separator as an immutable value, but also store the chain id that it corresponds to, in order to
    // invalidate the cached domain separator if the chain id changes.
    bytes32 private immutable _CACHED_DOMAIN_SEPARATOR;
    uint256 private immutable _CACHED_CHAIN_ID;

    bytes32 private immutable _HASHED_NAME;
    bytes32 private immutable _HASHED_VERSION;

    // --- Connected contract declarations ---

    ICdpManager public immutable cdpManager;

    ICollSurplusPool public immutable collSurplusPool;

    address public feeRecipientAddress;

    IEBTCToken public immutable ebtcToken;

    // A doubly linked list of Cdps, sorted by their collateral ratios
    ISortedCdps public immutable sortedCdps;

    // Mapping of borrowers to approved position managers, by approval status: cdpOwner(borrower) -> positionManager -> PositionManagerApproval (None, OneTime, Persistent)
    mapping(address => mapping(address => PositionManagerApproval)) public positionManagers;
    mapping(address => uint256) private _nonces;

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
        uint256 debt;
        uint256 totalColl;
        uint256 netColl;
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

        bytes32 hashedName = keccak256(bytes(NAME));
        bytes32 hashedVersion = keccak256(bytes(_VERSION));

        _HASHED_NAME = hashedName;
        _HASHED_VERSION = hashedVersion;
        _CACHED_CHAIN_ID = _chainID();
        _CACHED_DOMAIN_SEPARATOR = _buildDomainSeparator(_TYPE_HASH, hashedName, hashedVersion);

        emit FeeRecipientAddressChanged(_feeRecipientAddress);
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
        uint256 _EBTCAmount,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthBalance
    ) external override nonReentrantSelfAndCdpM returns (bytes32) {
        return _openCdp(_EBTCAmount, _upperHint, _lowerHint, _stEthBalance, msg.sender);
    }

    function openCdpFor(
        uint256 _EBTCAmount,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _collAmount,
        address _borrower
    ) external override nonReentrantSelfAndCdpM returns (bytes32) {
        return _openCdp(_EBTCAmount, _upperHint, _lowerHint, _collAmount, _borrower);
    }

    // Function that adds the received stETH to the caller's specified Cdp.
    function addColl(
        bytes32 _cdpId,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthBalanceIncrease
    ) external override nonReentrantSelfAndCdpM {
        _adjustCdpInternal(_cdpId, 0, 0, false, _upperHint, _lowerHint, _stEthBalanceIncrease);
    }

    /**
    Withdraws `_stEthBalanceDecrease` amount of collateral from the caller’s Cdp. Executes only if the user has an active Cdp, the withdrawal would not pull the user’s Cdp below the minimum collateralization ratio, and the resulting total collateralization ratio of the system is above 150%.
    */
    function withdrawColl(
        bytes32 _cdpId,
        uint256 _stEthBalanceDecrease,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external override nonReentrantSelfAndCdpM {
        _adjustCdpInternal(_cdpId, _stEthBalanceDecrease, 0, false, _upperHint, _lowerHint, 0);
    }

    // Withdraw EBTC tokens from a cdp: mint new EBTC tokens to the owner, and increase the cdp's debt accordingly
    /**
    Issues `_amount` of eBTC from the caller’s Cdp to the caller. Executes only if the Cdp's collateralization ratio would remain above the minimum, and the resulting total collateralization ratio is above 150%.
     */
    function withdrawEBTC(
        bytes32 _cdpId,
        uint256 _EBTCAmount,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external override nonReentrantSelfAndCdpM {
        _adjustCdpInternal(_cdpId, 0, _EBTCAmount, true, _upperHint, _lowerHint, 0);
    }

    // Repay EBTC tokens to a Cdp: Burn the repaid EBTC tokens, and reduce the cdp's debt accordingly
    /**
    repay `_amount` of eBTC to the caller’s Cdp, subject to leaving 50 debt in the Cdp (which corresponds to the 50 eBTC gas compensation).
    */
    function repayEBTC(
        bytes32 _cdpId,
        uint256 _EBTCAmount,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external override nonReentrantSelfAndCdpM {
        _adjustCdpInternal(_cdpId, 0, _EBTCAmount, false, _upperHint, _lowerHint, 0);
    }

    function adjustCdp(
        bytes32 _cdpId,
        uint256 _stEthBalanceDecrease,
        uint256 _EBTCChange,
        bool _isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external override nonReentrantSelfAndCdpM {
        _adjustCdpInternal(
            _cdpId,
            _stEthBalanceDecrease,
            _EBTCChange,
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
        uint256 _stEthBalanceDecrease,
        uint256 _EBTCChange,
        bool _isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthBalanceIncrease
    ) external override nonReentrantSelfAndCdpM {
        _adjustCdpInternal(
            _cdpId,
            _stEthBalanceDecrease,
            _EBTCChange,
            _isDebtIncrease,
            _upperHint,
            _lowerHint,
            _stEthBalanceIncrease
        );
    }

    /*
     * _adjustCdpInternal(): Alongside a debt change, this function can perform either
     * a collateral top-up or a collateral withdrawal.
     *
     * It therefore expects either a positive _stEthBalanceIncrease, or a positive _stEthBalanceDecrease argument.
     *
     * If both are positive, it will revert.
     */
    function _adjustCdpInternal(
        bytes32 _cdpId,
        uint256 _stEthBalanceDecrease,
        uint256 _EBTCChange,
        bool _isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthBalanceIncrease
    ) internal {
        // Confirm the operation is the borrower or approved position manager adjusting its own cdp
        address _borrower = sortedCdps.getOwnerAddress(_cdpId);
        _requireBorrowerOrPositionManagerAndUpdate(_borrower);

        _requireCdpisActive(cdpManager, _cdpId);

        cdpManager.syncAccounting(_cdpId);

        LocalVariables_adjustCdp memory vars;

        vars.price = priceFeed.fetchPrice();
        bool isRecoveryMode = _checkRecoveryModeForTCR(_getTCR(vars.price));

        if (_isDebtIncrease) {
            _requireNonZeroDebtChange(_EBTCChange);
        }
        _requireSingularCollChange(_stEthBalanceIncrease, _stEthBalanceDecrease);
        _requireNonZeroAdjustment(_stEthBalanceIncrease, _stEthBalanceDecrease, _EBTCChange);

        // Get the collChange based on the collateral value transferred in the transaction
        (vars.collChange, vars.isCollIncrease) = _getCollSharesChangeFromStEthChange(
            _stEthBalanceIncrease,
            _stEthBalanceDecrease
        );

        vars.netDebtChange = _EBTCChange;

        vars.debt = cdpManager.getCdpDebt(_cdpId);
        vars.coll = cdpManager.getCdpCollShares(_cdpId);

        // Get the cdp's old ICR before the adjustment, and what its new ICR will be after the adjustment
        uint256 _cdpStEthBalance = collateral.getPooledEthByShares(vars.coll);
        require(
            _stEthBalanceDecrease <= _cdpStEthBalance,
            "BorrowerOperations: withdraw more collateral than CDP has!"
        );
        vars.oldICR = LiquityMath._computeCR(_cdpStEthBalance, vars.debt, vars.price);
        vars.newICR = _getNewICRFromCdpChange(
            vars.coll,
            vars.debt,
            vars.collChange,
            vars.isCollIncrease,
            vars.netDebtChange,
            _isDebtIncrease,
            vars.price
        );

        // Check the adjustment satisfies all conditions for the current system mode
        _requireValidAdjustmentInCurrentMode(
            isRecoveryMode,
            _stEthBalanceDecrease,
            _isDebtIncrease,
            vars
        );

        // When the adjustment is a debt repayment, check it's a valid amount, that the caller has enough EBTC, and that the resulting debt is >0
        if (!_isDebtIncrease && _EBTCChange > 0) {
            _requireValidEBTCRepayment(vars.debt, vars.netDebtChange);
            _requireSufficientEBTCBalance(ebtcToken, msg.sender, vars.netDebtChange);
            _requireNonZeroDebt(vars.debt - vars.netDebtChange);
        }

        (vars.newColl, vars.newDebt) = _getNewCdpAmounts(
            vars.coll,
            vars.debt,
            vars.collChange,
            vars.isCollIncrease,
            vars.netDebtChange,
            _isDebtIncrease
        );

        _requireAtLeastMinNetStEthBalance(collateral.getPooledEthByShares(vars.newColl));

        cdpManager.updateCdp(_cdpId, _borrower, vars.coll, vars.debt, vars.newColl, vars.newDebt);

        // Re-insert cdp in to the sorted list
        {
            uint256 newNICR = _getNewNominalICRFromCdpChange(vars, _isDebtIncrease);
            sortedCdps.reInsert(_cdpId, newNICR, _upperHint, _lowerHint);
        }

        // Use the unmodified _EBTCChange here, as we don't send the fee to the user
        {
            LocalVariables_moveTokens memory _varMvTokens = LocalVariables_moveTokens(
                msg.sender,
                vars.collChange,
                (vars.isCollIncrease ? _stEthBalanceIncrease : 0),
                vars.isCollIncrease,
                _EBTCChange,
                _isDebtIncrease,
                vars.netDebtChange
            );
            _processTokenMovesFromAdjustment(_varMvTokens);
        }
    }

    function _openCdp(
        uint256 _EBTCAmount,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthBalance,
        address _borrower
    ) internal returns (bytes32) {
        _requireNonZeroDebt(_EBTCAmount);
        _requireBorrowerOrPositionManagerAndUpdate(_borrower);

        LocalVariables_openCdp memory vars;

        // ICR is based on the net coll, i.e. the requested coll amount - fixed liquidator incentive gas comp.
        vars.netColl = _getNetColl(_stEthBalance);

        // will revert if _stEthBalance is less than MIN_NET_COLL + LIQUIDATOR_REWARD
        _requireAtLeastMinNetStEthBalance(vars.netColl);

        // Update global pending index before any operations
        cdpManager.syncGlobalAccounting();

        vars.price = priceFeed.fetchPrice();
        bool isRecoveryMode = _checkRecoveryModeForTCR(_getTCR(vars.price));

        vars.debt = _EBTCAmount;

        // Sanity check
        require(vars.netColl > 0, "BorrowerOperations: zero collateral for openCdp()!");

        uint256 _netCollAsShares = collateral.getSharesByPooledEth(vars.netColl);
        uint256 _liquidatorRewardShares = collateral.getSharesByPooledEth(LIQUIDATOR_REWARD);

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
        uint256 newTCR = _getNewTCRFromCdpChange(vars.netColl, true, vars.debt, true, vars.price);
        if (isRecoveryMode) {
            _requireICRisAboveCCR(vars.ICR);

            // == Grace Period == //
            // We are in RM, Edge case is Depositing Coll could exit RM
            // We check with newTCR
            if (newTCR < CCR) {
                // Notify RM
                cdpManager.notifyStartGracePeriod(newTCR);
            } else {
                // Notify Back to Normal Mode
                cdpManager.notifyEndGracePeriod(newTCR);
            }
        } else {
            _requireICRisAboveMCR(vars.ICR);
            _requireNewTCRisAboveCCR(newTCR);

            // == Grace Period == //
            // We are not in RM, no edge case, we always stay above RM
            // Always Notify Back to Normal Mode
            cdpManager.notifyEndGracePeriod(newTCR);
        }

        // Set the cdp struct's properties
        bytes32 _cdpId = sortedCdps.insert(_borrower, vars.NICR, _upperHint, _lowerHint);

        // Collision check: collisions should never occur
        // Explicitly prevent it by checking for `nonExistent`
        _requireCdpIsNonExistent(_cdpId);

        // Collateral is stored in shares form for normalization
        cdpManager.initializeCdp(
            _cdpId,
            vars.debt,
            _netCollAsShares,
            _liquidatorRewardShares,
            _borrower
        );

        // Mint the full EBTCAmount to the caller
        _withdrawEBTC(msg.sender, _EBTCAmount, _EBTCAmount);

        /**
            Note that only NET coll (as shares) is considered part of the CDP.
            The static liqudiation incentive is stored in the gas pool and can be considered a deposit / voucher to be returned upon CDP close, to the closer.
            The close can happen from the borrower closing their own CDP, a full liquidation, or a redemption.
        */

        // CEI: Move the net collateral and liquidator gas compensation to the Active Pool. Track only net collateral shares for TCR purposes.
        _activePoolAddColl(_stEthBalance, _netCollAsShares);

        // Invariant check
        require(
            vars.netColl + LIQUIDATOR_REWARD == _stEthBalance,
            "BorrowerOperations: deposited collateral mismatch!"
        );

        return _cdpId;
    }

    /**
    allows a borrower to repay all debt, withdraw all their collateral, and close their Cdp. Requires the borrower have a eBTC balance sufficient to repay their cdp's debt, excluding gas compensation - i.e. `(debt - 50)` eBTC.
    */
    function closeCdp(bytes32 _cdpId) external override {
        address _borrower = sortedCdps.getOwnerAddress(_cdpId);
        _requireBorrowerOrPositionManagerAndUpdate(_borrower);

        _requireCdpisActive(cdpManager, _cdpId);

        cdpManager.syncAccounting(_cdpId);

        uint256 price = priceFeed.fetchPrice();
        _requireNotInRecoveryMode(_getTCR(price));

        uint256 coll = cdpManager.getCdpCollShares(_cdpId);
        uint256 debt = cdpManager.getCdpDebt(_cdpId);
        uint256 liquidatorRewardShares = cdpManager.getCdpLiquidatorRewardShares(_cdpId);

        _requireSufficientEBTCBalance(ebtcToken, msg.sender, debt);

        uint256 newTCR = _getNewTCRFromCdpChange(
            collateral.getPooledEthByShares(coll),
            false,
            debt,
            false,
            price
        );
        _requireNewTCRisAboveCCR(newTCR);

        // == Grace Period == //
        // By definition we are not in RM, notify CDPManager to ensure "Glass is on"
        cdpManager.notifyEndGracePeriod(newTCR);

        cdpManager.removeStake(_cdpId);

        // We already verified msg.sender is the borrower
        cdpManager.closeCdp(_cdpId, msg.sender, debt, coll);

        // Burn the repaid EBTC from the user's balance
        _repayEBTC(msg.sender, debt);

        // CEI: Send the collateral and liquidator reward shares back to the user
        activePool.transferSystemCollSharesAndLiquidatorReward(
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
        collSurplusPool.claimSurplusCollShares(msg.sender);
    }

    /// @notice Returns true if the borrower is allowing position manager to act on their behalf
    function getPositionManagerApproval(
        address _borrower,
        address _positionManager
    ) external view override returns (PositionManagerApproval) {
        return _getPositionManagerApproval(_borrower, _positionManager);
    }

    function _getPositionManagerApproval(
        address _borrower,
        address _positionManager
    ) internal view returns (PositionManagerApproval) {
        return positionManagers[_borrower][_positionManager];
    }

    /// @notice Approve an account to take arbitrary actions on your Cdps.
    /// @notice Account managers with 'Persistent' status will be able to take actions indefinitely
    /// @notice Account managers with 'OneTIme' status will be able to take a single action on one Cdp. Approval will be automatically revoked after one Cdp-related action.
    /// @notice Similar to approving tokens, approving a position manager allows _stealing of all positions_ if given to a malicious account.
    function setPositionManagerApproval(
        address _positionManager,
        PositionManagerApproval _approval
    ) external override {
        _setPositionManagerApproval(msg.sender, _positionManager, _approval);
    }

    function _setPositionManagerApproval(
        address _borrower,
        address _positionManager,
        PositionManagerApproval _approval
    ) internal {
        positionManagers[_borrower][_positionManager] = _approval;
        emit PositionManagerApprovalSet(_borrower, _positionManager, _approval);
    }

    /// @notice Revoke a position manager from taking further actions on your Cdps
    /// @notice Similar to approving tokens, approving a position manager allows _stealing of all positions_ if given to a malicious account.
    function revokePositionManagerApproval(address _positionManager) external override {
        _setPositionManagerApproval(msg.sender, _positionManager, PositionManagerApproval.None);
    }

    /// @notice Allows recipient of delegation to renounce it
    function renouncePositionManagerApproval(address _borrower) external override {
        _setPositionManagerApproval(_borrower, msg.sender, PositionManagerApproval.None);
    }

    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return domainSeparator();
    }

    function domainSeparator() public view override returns (bytes32) {
        if (_chainID() == _CACHED_CHAIN_ID) {
            return _CACHED_DOMAIN_SEPARATOR;
        } else {
            return _buildDomainSeparator(_TYPE_HASH, _HASHED_NAME, _HASHED_VERSION);
        }
    }

    function _chainID() private view returns (uint256) {
        return block.chainid;
    }

    function _buildDomainSeparator(
        bytes32 typeHash,
        bytes32 name,
        bytes32 version
    ) private view returns (bytes32) {
        return keccak256(abi.encode(typeHash, name, version, _chainID(), address(this)));
    }

    function nonces(address _borrower) external view override returns (uint256) {
        // FOR EIP 2612
        return _nonces[_borrower];
    }

    function version() external pure override returns (string memory) {
        return _VERSION;
    }

    function permitTypeHash() external pure override returns (bytes32) {
        return _PERMIT_POSITION_MANAGER_TYPEHASH;
    }

    function permitPositionManagerApproval(
        address _borrower,
        address _positionManager,
        PositionManagerApproval _approval,
        uint256 _deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override {
        require(_deadline >= block.timestamp, "BorrowerOperations: Position manager permit expired");

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator(),
                keccak256(
                    abi.encode(
                        _PERMIT_POSITION_MANAGER_TYPEHASH,
                        _borrower,
                        _positionManager,
                        _approval,
                        _nonces[_borrower]++,
                        _deadline
                    )
                )
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(
            recoveredAddress != address(0) && recoveredAddress == _borrower,
            "BorrowerOperations: Invalid signature"
        );

        _setPositionManagerApproval(_borrower, _positionManager, _approval);
    }

    // --- Helper functions ---

    function _getCollSharesChangeFromStEthChange(
        uint256 _collReceived,
        uint256 _requestedCollWithdrawal
    ) internal view returns (uint256 collChange, bool isCollIncrease) {
        if (_collReceived != 0) {
            collChange = collateral.getSharesByPooledEth(_collReceived);
            isCollIncrease = true;
        } else {
            collChange = collateral.getSharesByPooledEth(_requestedCollWithdrawal);
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
            _withdrawEBTC(_varMvTokens.user, _varMvTokens.EBTCChange, _varMvTokens.netDebtChange);
        } else {
            // Debt decrease: burn change value of eBTC from user, decrement ActivePool eBTC internal accounting
            _repayEBTC(_varMvTokens.user, _varMvTokens.EBTCChange);
        }

        if (_varMvTokens.isCollIncrease) {
            // Coll increase: send change value of stETH to Active Pool, increment ActivePool stETH internal accounting
            _activePoolAddColl(_varMvTokens.collAddUnderlying, _varMvTokens.collChange);
        } else {
            // Coll decrease: send change value of stETH to user, decrement ActivePool stETH internal accounting
            activePool.transferSystemCollShares(_varMvTokens.user, _varMvTokens.collChange);
        }
    }

    /// @notice Send stETH to Active Pool and increase its recorded ETH balance
    /// @param _stEthBalance total balance of stETH to send, inclusive of coll and liquidatorRewardShares
    /// @param _sharesToTrack coll as shares (exclsuive of liquidator reward shares)
    /// @dev Liquidator reward shares are not considered as part of the system for CR purposes.
    /// @dev These number of liquidator shares associated with each CDP are stored in the CDP, while the actual tokens float in the active pool
    function _activePoolAddColl(uint256 _stEthBalance, uint256 _sharesToTrack) internal {
        // NOTE: No need for safe transfer if the collateral asset is standard. Make sure this is the case!
        collateral.transferFrom(msg.sender, address(activePool), _stEthBalance);
        activePool.increaseSystemCollShares(_sharesToTrack);
    }

    // Issue the specified amount of EBTC to _account and increases
    // the total active debt
    function _withdrawEBTC(
        address _account,
        uint256 _EBTCAmount,
        uint256 _netDebtIncrease
    ) internal {
        activePool.increaseSystemDebt(_netDebtIncrease);
        ebtcToken.mint(_account, _EBTCAmount);
    }

    // Burn the specified amount of EBTC from _account and decreases the total active debt
    function _repayEBTC(address _account, uint256 _EBTC) internal {
        activePool.decreaseSystemDebt(_EBTC);
        ebtcToken.burn(_account, _EBTC);
    }

    // --- 'Require' wrapper functions ---

    function _requireSingularCollChange(
        uint256 _stEthBalanceIncrease,
        uint256 _stEthBalanceDecrease
    ) internal pure {
        require(
            _stEthBalanceIncrease == 0 || _stEthBalanceDecrease == 0,
            "BorrowerOperations: Cannot add and withdraw collateral in same operation"
        );
    }

    function _requireNonZeroAdjustment(
        uint256 _stEthBalanceIncrease,
        uint256 _EBTCChange,
        uint256 _stEthBalanceDecrease
    ) internal pure {
        require(
            _stEthBalanceIncrease != 0 || _stEthBalanceDecrease != 0 || _EBTCChange != 0,
            "BorrowerOperations: There must be either a collateral change or a debt change"
        );
    }

    function _requireCdpisActive(ICdpManager _cdpManager, bytes32 _cdpId) internal view {
        uint256 status = _cdpManager.getCdpStatus(_cdpId);
        require(status == 1, "BorrowerOperations: Cdp does not exist or is closed");
    }

    function _requireCdpIsNonExistent(bytes32 _cdpId) internal view {
        uint status = cdpManager.getCdpStatus(_cdpId);
        require(status == 0, "BorrowerOperations: Cdp is active or has been previously closed");
    }

    function _requireNonZeroDebtChange(uint _EBTCChange) internal pure {
        require(_EBTCChange > 0, "BorrowerOperations: Debt increase requires non-zero debtChange");
    }

    function _requireNotInRecoveryMode(uint256 _tcr) internal view {
        require(
            !_checkRecoveryModeForTCR(_tcr),
            "BorrowerOperations: Operation not permitted during Recovery Mode"
        );
    }

    function _requireNoStEthBalanceDecrease(uint256 _stEthBalanceDecrease) internal pure {
        require(
            _stEthBalanceDecrease == 0,
            "BorrowerOperations: Collateral withdrawal not permitted Recovery Mode"
        );
    }

    function _requireValidAdjustmentInCurrentMode(
        bool _isRecoveryMode,
        uint256 _stEthBalanceDecrease,
        bool _isDebtIncrease,
        LocalVariables_adjustCdp memory _vars
    ) internal {
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

        _vars.newTCR = _getNewTCRFromCdpChange(
            collateral.getPooledEthByShares(_vars.collChange),
            _vars.isCollIncrease,
            _vars.netDebtChange,
            _isDebtIncrease,
            _vars.price
        );

        if (_isRecoveryMode) {
            _requireNoStEthBalanceDecrease(_stEthBalanceDecrease);
            if (_isDebtIncrease) {
                _requireICRisAboveCCR(_vars.newICR);
                _requireNewICRisAboveOldICR(_vars.newICR, _vars.oldICR);
            }

            // == Grace Period == //
            // We are in RM, Edge case is Depositing Coll could exit RM
            // We check with newTCR
            if (_vars.newTCR < CCR) {
                // Notify RM
                cdpManager.notifyStartGracePeriod(_vars.newTCR);
            } else {
                // Notify Back to Normal Mode
                cdpManager.notifyEndGracePeriod(_vars.newTCR);
            }
        } else {
            // if Normal Mode
            _requireICRisAboveMCR(_vars.newICR);
            _requireNewTCRisAboveCCR(_vars.newTCR);

            // == Grace Period == //
            // We are not in RM, no edge case, we always stay above RM
            // Always Notify Back to Normal Mode
            cdpManager.notifyEndGracePeriod(_vars.newTCR);
        }
    }

    function _requireICRisAboveMCR(uint256 _newICR) internal pure {
        require(
            _newICR >= MCR,
            "BorrowerOperations: An operation that would result in ICR < MCR is not permitted"
        );
    }

    function _requireICRisAboveCCR(uint256 _newICR) internal pure {
        require(_newICR >= CCR, "BorrowerOperations: Operation must leave cdp with ICR >= CCR");
    }

    function _requireNewICRisAboveOldICR(uint256 _newICR, uint256 _oldICR) internal pure {
        require(
            _newICR >= _oldICR,
            "BorrowerOperations: Cannot decrease your Cdp's ICR in Recovery Mode"
        );
    }

    function _requireNewTCRisAboveCCR(uint256 _newTCR) internal pure {
        require(
            _newTCR >= CCR,
            "BorrowerOperations: An operation that would result in TCR < CCR is not permitted"
        );
    }

    function _requireNonZeroDebt(uint256 _debt) internal pure {
        require(_debt > 0, "BorrowerOperations: Debt must be non-zero");
    }

    function _requireAtLeastMinNetStEthBalance(uint256 _coll) internal pure {
        require(
            _coll >= MIN_NET_COLL,
            "BorrowerOperations: Cdp's net coll must be greater than minimum"
        );
    }

    function _requireValidEBTCRepayment(uint256 _currentDebt, uint256 _debtRepayment) internal pure {
        require(
            _debtRepayment <= _currentDebt,
            "BorrowerOperations: Amount repaid must not be larger than the Cdp's debt"
        );
    }

    function _requireSufficientEBTCBalance(
        IEBTCToken _ebtcToken,
        address _account,
        uint256 _debtRepayment
    ) internal view {
        require(
            _ebtcToken.balanceOf(_account) >= _debtRepayment,
            "BorrowerOperations: Caller doesnt have enough EBTC to make repayment"
        );
    }

    function _requireBorrowerOrPositionManagerAndUpdate(address _borrower) internal {
        if (_borrower == msg.sender) {
            return; // Early return, no delegation
        }

        PositionManagerApproval _approval = _getPositionManagerApproval(_borrower, msg.sender);
        // Must be an approved position manager at this point
        require(
            _approval != PositionManagerApproval.None,
            "BorrowerOperations: Only borrower account or approved position manager can OpenCdp on borrower's behalf"
        );

        // Conditional Adjustment
        /// @dev If this is a position manager operation with a one-time approval, clear that approval
        /// @dev If the PositionManagerApproval was none, we should have failed with the check in _requireBorrowerOrPositionManagerAndUpdate
        if (_approval == PositionManagerApproval.OneTime) {
            _setPositionManagerApproval(_borrower, msg.sender, PositionManagerApproval.None);
        }
    }

    // --- ICR and TCR getters ---

    // Compute the new collateral ratio, considering the change in coll and debt. Assumes 0 pending rewards.
    function _getNewNominalICRFromCdpChange(
        LocalVariables_adjustCdp memory vars,
        bool _isDebtIncrease
    ) internal pure returns (uint256) {
        (uint256 newColl, uint256 newDebt) = _getNewCdpAmounts(
            vars.coll,
            vars.debt,
            vars.collChange,
            vars.isCollIncrease,
            vars.netDebtChange,
            _isDebtIncrease
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
        (uint256 newColl, uint256 newDebt) = _getNewCdpAmounts(
            _coll,
            _debt,
            _collChange,
            _isCollIncrease,
            _debtChange,
            _isDebtIncrease
        );

        uint256 newICR = LiquityMath._computeCR(
            collateral.getPooledEthByShares(newColl),
            newDebt,
            _price
        );
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
        uint256 _shareColl = getSystemCollShares();
        uint256 totalColl = collateral.getPooledEthByShares(_shareColl);
        uint256 totalDebt = _getSystemDebt();

        totalColl = _isCollIncrease ? totalColl + _collChange : totalColl - _collChange;
        totalDebt = _isDebtIncrease ? totalDebt + _debtChange : totalDebt - _debtChange;

        uint256 newTCR = LiquityMath._computeCR(totalColl, totalDebt, _price);
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
        uint256 fee = flashFee(token, amount); // NOTE: Check for `eBTCToken` is implicit here // NOTE: Pause check is here
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
        require(!flashLoansPaused, "BorrowerOperations: Flash Loans Paused");

        return (amount * feeBps) / MAX_BPS;
    }

    /// @dev Max flashloan, exclusively in ETH equals to the current balance
    function maxFlashLoan(address token) public view override returns (uint256) {
        if (token != address(ebtcToken)) {
            return 0;
        }

        if (flashLoansPaused) {
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

        cdpManager.syncGlobalAccounting();

        feeRecipientAddress = _feeRecipientAddress;
        emit FeeRecipientAddressChanged(_feeRecipientAddress);
    }

    function setFeeBps(uint256 _newFee) external requiresAuth {
        require(_newFee <= MAX_FEE_BPS, "ERC3156FlashLender: _newFee should <= MAX_FEE_BPS");

        cdpManager.syncGlobalAccounting();

        // set new flash fee
        uint256 _oldFee = feeBps;
        feeBps = uint16(_newFee);
        emit FlashFeeSet(msg.sender, _oldFee, _newFee);
    }

    function setFlashLoansPaused(bool _paused) external requiresAuth {
        cdpManager.syncGlobalAccounting();

        flashLoansPaused = _paused;
        emit FlashLoansPaused(msg.sender, _paused);
    }
}
