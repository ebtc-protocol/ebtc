// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./Interfaces/IBorrowerOperations.sol";
import "./Interfaces/ICdpManager.sol";
import "./Interfaces/ICdpManagerData.sol";
import "./Interfaces/IEBTCToken.sol";
import "./Interfaces/ICollSurplusPool.sol";
import "./Interfaces/ISortedCdps.sol";
import "./Dependencies/EbtcBase.sol";
import "./Dependencies/ReentrancyGuard.sol";
import "./Dependencies/Ownable.sol";
import "./Dependencies/AuthNoOwner.sol";
import "./Dependencies/ERC3156FlashLender.sol";
import "./Dependencies/PermitNonce.sol";

/// @title BorrowerOperations is mainly in charge of all end user interactions like Cdp open, adjust, close etc
/// @notice End users could approve delegate via IPositionManagers for authorized actions on their behalf
/// @dev BorrowerOperations also allows ERC3156 compatible flashmint of eBTC token
contract BorrowerOperations is
    EbtcBase,
    ReentrancyGuard,
    IBorrowerOperations,
    ERC3156FlashLender,
    AuthNoOwner,
    PermitNonce
{
    string public constant NAME = "BorrowerOperations";

    // keccak256("permitPositionManagerApproval(address borrower,address positionManager,uint8 status,uint256 nonce,uint256 deadline)");
    bytes32 private constant _PERMIT_POSITION_MANAGER_TYPEHASH =
        keccak256(
            "PermitPositionManagerApproval(address borrower,address positionManager,uint8 status,uint256 nonce,uint256 deadline)"
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

    address public immutable feeRecipientAddress;

    IEBTCToken public immutable ebtcToken;

    // A doubly linked list of Cdps, sorted by their collateral ratios
    ISortedCdps public immutable sortedCdps;

    // Mapping of borrowers to approved position managers, by approval status: cdpOwner(borrower) -> positionManager -> PositionManagerApproval (None, OneTime, Persistent)
    mapping(address => mapping(address => PositionManagerApproval)) public positionManagers;

    /* --- Variable container structs  ---

    Used to hold, return and assign variables inside a function, in order to avoid the error:
    "CompilerError: Stack too deep". */

    struct AdjustCdpLocals {
        uint256 price;
        uint256 collSharesChange;
        uint256 netDebtChange;
        bool isCollIncrease;
        uint256 debt;
        uint256 collShares;
        uint256 oldICR;
        uint256 newICR;
        uint256 newTCR;
        uint256 newDebt;
        uint256 newCollShares;
        uint256 stake;
    }

    struct OpenCdpLocals {
        uint256 price;
        uint256 debt;
        uint256 netStEthBalance;
        uint256 ICR;
        uint256 NICR;
        uint256 stake;
    }

    struct MoveTokensParams {
        address user;
        uint256 collSharesChange;
        uint256 collAddUnderlying; // ONLY for isCollIncrease=true
        bool isCollIncrease;
        uint256 netDebtChange;
        bool isDebtIncrease;
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
    ) EbtcBase(_activePoolAddress, _priceFeedAddress, _collTokenAddress) {
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

    /// @notice Function that creates a Cdp for the caller with the requested debt, and the stETH received as collateral.
    /// @notice Successful execution is conditional mainly on the resulting collateralization ratio which must exceed minimum requirement, e.g., MCR.
    /// @notice Upon Cdp open, a separate gas stipend (denominated in stETH) will be allocated for possible liquidation.
    /// @param _debt The expected debt for this new Cdp
    /// @param _upperHint The expected CdpId of neighboring higher ICR within SortedCdps, could be simply bytes32(0)
    /// @param _lowerHint The expected CdpId of neighboring lower ICR within SortedCdps, could be simply bytes32(0)
    /// @param _stEthBalance The total stETH collateral amount deposited for the specified Cdp
    /// @return The CdpId for this newly created Cdp
    function openCdp(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthBalance
    ) external override nonReentrantSelfAndCdpM returns (bytes32) {
        return _openCdp(_debt, _upperHint, _lowerHint, _stEthBalance, msg.sender);
    }

    /// @notice Function that creates a Cdp for the specified _borrower by caller with the requested debt, and the stETH received as collateral.
    /// @dev Caller will need approval from _borrower via IPositionManagers if they are different address
    /// @notice Successful execution is conditional mainly on the resulting collateralization ratio which must exceed minimum requirement, e.g., MCR.
    /// @notice Upon Cdp open, a separate gas stipend (denominated in stETH) will be allocated for possible liquidation.
    /// @param _debt The expected debt for this new Cdp
    /// @param _upperHint The expected CdpId of neighboring higher ICR within SortedCdps, could be simply bytes32(0)
    /// @param _lowerHint The expected CdpId of neighboring lower ICR within SortedCdps, could be simply bytes32(0)
    /// @param _stEthBalance The total stETH collateral amount deposited for the specified Cdp
    /// @param _borrower The Cdp owner for this new Cdp.
    /// @return The CdpId for this newly created Cdp
    function openCdpFor(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthBalance,
        address _borrower
    ) external override nonReentrantSelfAndCdpM returns (bytes32) {
        return _openCdp(_debt, _upperHint, _lowerHint, _stEthBalance, _borrower);
    }

    /// @notice Function that adds the received stETH to the specified Cdp.
    /// @dev If caller is different from Cdp owner, it will need approval from Cdp owner for this call
    /// @param _cdpId The CdpId on which this operation is operated
    /// @param _upperHint The expected CdpId of neighboring higher ICR within SortedCdps, could be simply bytes32(0)
    /// @param _lowerHint The expected CdpId of neighboring lower ICR within SortedCdps, could be simply bytes32(0)
    /// @param _stEthBalanceIncrease The total stETH collateral amount deposited (added) for the specified Cdp
    function addColl(
        bytes32 _cdpId,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthBalanceIncrease
    ) external override nonReentrantSelfAndCdpM {
        _adjustCdpInternal(_cdpId, 0, 0, false, _upperHint, _lowerHint, _stEthBalanceIncrease);
    }

    /// @notice Function that withdraws `_stEthBalanceDecrease` amount of collateral from the specified Cdp
    /// @dev If caller is different from Cdp owner, it will need approval from Cdp owner for this call
    /// @notice Successful execution is conditional on whether the withdrawal would bring down the ICR or TCR to the minimum requirement, e.g., MCR or CCR
    /// @param _cdpId The CdpId on which this operation is operated
    /// @param _stEthBalanceDecrease The total stETH collateral amount withdrawn (reduced) for the specified Cdp
    /// @param _upperHint The expected CdpId of neighboring higher ICR within SortedCdps, could be simply bytes32(0)
    /// @param _lowerHint The expected CdpId of neighboring lower ICR within SortedCdps, could be simply bytes32(0)
    function withdrawColl(
        bytes32 _cdpId,
        uint256 _stEthBalanceDecrease,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external override nonReentrantSelfAndCdpM {
        _adjustCdpInternal(_cdpId, _stEthBalanceDecrease, 0, false, _upperHint, _lowerHint, 0);
    }

    /// @notice Function that withdraws `_debt` amount of eBTC token from the specified Cdp, thus increasing its debt accounting
    /// @dev If caller is different from Cdp owner, it will need approval from Cdp owner for this call
    /// @notice Successful execution is conditional on whether the withdrawal would bring down the ICR or TCR to the minimum requirement, e.g., MCR or CCR
    /// @param _cdpId The CdpId on which this operation is operated
    /// @param _debt The total debt collateral amount increased for the specified Cdp
    /// @param _upperHint The expected CdpId of neighboring higher ICR within SortedCdps, could be simply bytes32(0)
    /// @param _lowerHint The expected CdpId of neighboring lower ICR within SortedCdps, could be simply bytes32(0)
    function withdrawDebt(
        bytes32 _cdpId,
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external override nonReentrantSelfAndCdpM {
        _adjustCdpInternal(_cdpId, 0, _debt, true, _upperHint, _lowerHint, 0);
    }

    /// @notice Function that repays the received eBTC token to the specified Cdp, thus reducing its debt accounting.
    /// @dev If caller is different from Cdp owner, it will need approval from Cdp owner for this call
    /// @param _cdpId The CdpId on which this operation is operated
    /// @param _upperHint The expected CdpId of neighboring higher ICR within SortedCdps, could be simply bytes32(0)
    /// @param _lowerHint The expected CdpId of neighboring lower ICR within SortedCdps, could be simply bytes32(0)
    /// @param _debt The total eBTC debt amount repaid for the specified Cdp
    function repayDebt(
        bytes32 _cdpId,
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external override nonReentrantSelfAndCdpM {
        _adjustCdpInternal(_cdpId, 0, _debt, false, _upperHint, _lowerHint, 0);
    }

    /// @notice Function that allows various operations which might change both collateral and debt
    /// @notice like taking more risky position (withdraws eBTC token and reduces stETH collateral)
    /// @notice or holding more safer position (repays eBTC token) with the specified Cdp.
    /// @notice If end user want to add collateral and change debt at the same time, use adjustCdpWithColl() instead
    /// @dev If caller is different from Cdp owner, it will need approval from Cdp owner for this call
    /// @param _cdpId The CdpId on which this operation is operated
    /// @param _stEthBalanceDecrease The total stETH collateral amount withdrawn from the specified Cdp
    /// @param _debtChange The total eBTC debt amount withdrawn or repaid for the specified Cdp
    /// @param _isDebtIncrease The flag (true or false) to indicate whether this is a eBTC token withdrawal (debt increase) or a repayment (debt reduce)
    /// @param _upperHint The expected CdpId of neighboring higher ICR within SortedCdps, could be simply bytes32(0)
    /// @param _lowerHint The expected CdpId of neighboring lower ICR within SortedCdps, could be simply bytes32(0)
    function adjustCdp(
        bytes32 _cdpId,
        uint256 _stEthBalanceDecrease,
        uint256 _debtChange,
        bool _isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external override nonReentrantSelfAndCdpM {
        _adjustCdpInternal(
            _cdpId,
            _stEthBalanceDecrease,
            _debtChange,
            _isDebtIncrease,
            _upperHint,
            _lowerHint,
            0
        );
    }

    /// @notice Function that allows various operations which might change both collateral and debt
    /// @notice like taking more risky position (withdraws eBTC token and reduces stETH collateral)
    /// @notice or holding more safer position (repays eBTC token and adds stETH collateral) with the specified Cdp.
    /// @dev If caller is different from Cdp owner, it will need approval from Cdp owner for this call
    /// @param _cdpId The CdpId on which this operation is operated
    /// @param _stEthBalanceDecrease The total stETH collateral amount withdrawn from the specified Cdp
    /// @param _debtChange The total eBTC debt amount withdrawn or repaid for the specified Cdp
    /// @param _isDebtIncrease The flag (true or false) to indicate whether this is a eBTC token withdrawal (debt increase) or a repayment (debt reduce)
    /// @param _upperHint The expected CdpId of neighboring higher ICR within SortedCdps, could be simply bytes32(0)
    /// @param _lowerHint The expected CdpId of neighboring lower ICR within SortedCdps, could be simply bytes32(0)
    /// @param _stEthBalanceIncrease The total stETH collateral amount deposited (added) for the specified Cdp
    function adjustCdpWithColl(
        bytes32 _cdpId,
        uint256 _stEthBalanceDecrease,
        uint256 _debtChange,
        bool _isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthBalanceIncrease
    ) external override nonReentrantSelfAndCdpM {
        _adjustCdpInternal(
            _cdpId,
            _stEthBalanceDecrease,
            _debtChange,
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
        uint256 _debtChange,
        bool _isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthBalanceIncrease
    ) internal {
        // Confirm the operation is the borrower or approved position manager adjusting its own cdp
        address _borrower = sortedCdps.getOwnerAddress(_cdpId);
        _requireBorrowerOrPositionManagerAndUpdateManagerApproval(_borrower);

        _requireCdpisActive(cdpManager, _cdpId);

        cdpManager.syncAccounting(_cdpId);

        AdjustCdpLocals memory vars;

        vars.price = priceFeed.fetchPrice();

        if (_isDebtIncrease) {
            _requireMinDebtChange(_debtChange);
        } else {
            _requireZeroOrMinAdjustment(_debtChange);
        }

        _requireSingularCollChange(_stEthBalanceIncrease, _stEthBalanceDecrease);
        _requireNonZeroAdjustment(_stEthBalanceIncrease, _stEthBalanceDecrease, _debtChange);
        _requireZeroOrMinAdjustment(_stEthBalanceIncrease);
        _requireZeroOrMinAdjustment(_stEthBalanceDecrease);
        // min debt adjustment checked above

        // Get the collSharesChange based on the collateral value transferred in the transaction
        (vars.collSharesChange, vars.isCollIncrease) = _getCollSharesChangeFromStEthChange(
            _stEthBalanceIncrease,
            _stEthBalanceDecrease
        );

        vars.netDebtChange = _debtChange;

        vars.debt = cdpManager.getCdpDebt(_cdpId);
        vars.collShares = cdpManager.getCdpCollShares(_cdpId);

        // Get the cdp's old ICR before the adjustment, and what its new ICR will be after the adjustment
        uint256 _cdpStEthBalance = collateral.getPooledEthByShares(vars.collShares);
        require(
            _stEthBalanceDecrease <= _cdpStEthBalance,
            "BorrowerOperations: Cannot withdraw greater stEthBalance than the value in Cdp"
        );
        vars.oldICR = EbtcMath._computeCR(_cdpStEthBalance, vars.debt, vars.price);
        vars.newICR = _getNewICRFromCdpChange(
            vars.collShares,
            vars.debt,
            vars.collSharesChange,
            vars.isCollIncrease,
            vars.netDebtChange,
            _isDebtIncrease,
            vars.price
        );

        // Check the adjustment satisfies all conditions for the current system mode
        bool isRecoveryMode = _checkRecoveryModeForTCR(_getCachedTCR(vars.price));
        _requireValidAdjustmentInCurrentMode(
            isRecoveryMode,
            _stEthBalanceDecrease,
            _isDebtIncrease,
            vars
        );

        // When the adjustment is a debt repayment, check it's a valid amount, that the caller has enough EBTC, and that the resulting debt is >0
        if (!_isDebtIncrease && _debtChange > 0) {
            _requireValidDebtRepayment(vars.debt, vars.netDebtChange);
            _requireSufficientEbtcTokenBalance(msg.sender, vars.netDebtChange);
            _requireMinDebt(vars.debt - vars.netDebtChange);
        }

        (vars.newCollShares, vars.newDebt) = _getNewCdpAmounts(
            vars.collShares,
            vars.debt,
            vars.collSharesChange,
            vars.isCollIncrease,
            vars.netDebtChange,
            _isDebtIncrease
        );

        _requireMinDebt(vars.newDebt);
        _requireAtLeastMinNetStEthBalance(collateral.getPooledEthByShares(vars.newCollShares));

        cdpManager.updateCdp(
            _cdpId,
            _borrower,
            vars.collShares,
            vars.debt,
            vars.newCollShares,
            vars.newDebt
        );

        // Re-insert cdp in to the sorted list
        {
            uint256 newNICR = _getNewNominalICRFromCdpChange(vars, _isDebtIncrease);
            sortedCdps.reInsert(_cdpId, newNICR, _upperHint, _lowerHint);
        }

        // CEI: Process token movements
        {
            MoveTokensParams memory _varMvTokens = MoveTokensParams(
                msg.sender,
                vars.collSharesChange,
                (vars.isCollIncrease ? _stEthBalanceIncrease : 0),
                vars.isCollIncrease,
                _debtChange,
                _isDebtIncrease
            );
            _processTokenMovesFromAdjustment(_varMvTokens);
        }
    }

    function _openCdp(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthBalance,
        address _borrower
    ) internal returns (bytes32) {
        _requireMinDebt(_debt);
        _requireBorrowerOrPositionManagerAndUpdateManagerApproval(_borrower);

        OpenCdpLocals memory vars;

        // ICR is based on the net stEth balance, i.e. the specified stEth balance amount - fixed liquidator incentive gas comp.
        vars.netStEthBalance = _calcNetStEthBalance(_stEthBalance);

        _requireAtLeastMinNetStEthBalance(vars.netStEthBalance);

        // Update global pending index before any operations
        cdpManager.syncGlobalAccounting();

        vars.price = priceFeed.fetchPrice();
        vars.debt = _debt;

        // Sanity check
        require(vars.netStEthBalance > 0, "BorrowerOperations: zero collateral for openCdp()!");

        uint256 _netCollAsShares = collateral.getSharesByPooledEth(vars.netStEthBalance);
        uint256 _liquidatorRewardShares = collateral.getSharesByPooledEth(LIQUIDATOR_REWARD);

        // ICR is based on the net coll, i.e. the requested coll amount - fixed liquidator incentive gas comp.
        vars.ICR = EbtcMath._computeCR(vars.netStEthBalance, vars.debt, vars.price);

        // NICR uses shares to normalize NICR across Cdps opened at different pooled ETH / shares ratios
        vars.NICR = EbtcMath._computeNominalCR(_netCollAsShares, vars.debt);

        /**
            In recovery move, ICR must be greater than CCR
            CCR > MCR (125% vs 110%)

            In normal mode, ICR must be greater thatn MCR
            Additionally, the new system TCR after the Cdps addition must be >CCR
        */
        bool isRecoveryMode = _checkRecoveryModeForTCR(_getCachedTCR(vars.price));
        uint256 newTCR = _getNewTCRFromCdpChange(
            vars.netStEthBalance,
            true,
            vars.debt,
            true,
            vars.price
        );
        if (isRecoveryMode) {
            _requireICRisNotBelowCCR(vars.ICR);

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
            _requireICRisNotBelowMCR(vars.ICR);
            _requireNewTCRisNotBelowCCR(newTCR);

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

        // CEI: Mint the full debt amount, in eBTC tokens, to the caller
        _withdrawDebt(msg.sender, _debt);

        /**
            Note that only NET stEth balance (as shares) is considered part of the Cdp.
            The static liqudiation incentive is stored in the gas pool and can be considered a deposit / voucher to be returned upon Cdp close, to the closer.
            The close can happen from the borrower closing their own Cdp, a full liquidation, or a redemption.
        */

        // CEI: Move the collateral and liquidator gas compensation to the Active Pool. Track only net collateral for TCR purposes.
        _activePoolAddColl(_stEthBalance, _netCollAsShares);

        // Invariant check
        require(
            vars.netStEthBalance + LIQUIDATOR_REWARD == _stEthBalance,
            "BorrowerOperations: deposited collateral mismatch!"
        );

        return _cdpId;
    }

    /// @notice Function that allows the caller to repay all debt, withdraw collateral, and close the specified Cdp
    /// @notice Caller should have enough eBTC token to repay off the debt fully for specified Cdp
    /// @dev If caller is different from Cdp owner, it will need approval from Cdp owner for this call
    /// @param _cdpId The CdpId on which this operation is operated
    function closeCdp(bytes32 _cdpId) external override {
        address _borrower = sortedCdps.getOwnerAddress(_cdpId);
        _requireBorrowerOrPositionManagerAndUpdateManagerApproval(_borrower);

        _requireCdpisActive(cdpManager, _cdpId);

        cdpManager.syncAccounting(_cdpId);

        uint256 price = priceFeed.fetchPrice();
        _requireNotInRecoveryMode(_getCachedTCR(price));

        uint256 collShares = cdpManager.getCdpCollShares(_cdpId);
        uint256 debt = cdpManager.getCdpDebt(_cdpId);
        uint256 liquidatorRewardShares = cdpManager.getCdpLiquidatorRewardShares(_cdpId);

        _requireSufficientEbtcTokenBalance(msg.sender, debt);

        uint256 newTCR = _getNewTCRFromCdpChange(
            collateral.getPooledEthByShares(collShares),
            false,
            debt,
            false,
            price
        );
        _requireNewTCRisNotBelowCCR(newTCR);

        // == Grace Period == //
        // By definition we are not in RM, notify CDPManager to ensure "Glass is on"
        cdpManager.notifyEndGracePeriod(newTCR);

        cdpManager.closeCdp(_cdpId, _borrower, debt, collShares);

        // Burn the repaid EBTC from the user's balance
        _repayDebt(msg.sender, debt);

        // CEI: Send the collateral and liquidator reward shares back to the user
        activePool.transferSystemCollSharesAndLiquidatorReward(
            msg.sender,
            collShares,
            liquidatorRewardShares
        );
    }

    /// @notice Claim remaining collateral from a redemption or from a liquidation with ICR > MCR in Recovery Mode
    /// @notice when a Cdp has been fully redeemed from and closed, or liquidated in Recovery Mode with a collateralization ratio higher enough (like over MCR)
    /// @notice the borrower is allowed to claim their stETH collateral surplus that remains in the system if any
    function claimSurplusCollShares() external override {
        // send ETH from CollSurplus Pool to owner
        collSurplusPool.claimSurplusCollShares(msg.sender);
    }

    /// @notice Returns true if the borrower is allowing position manager to act on their behalf
    /// @return PositionManagerApproval (None/OneTime/Persistent) status for given _borrower and _positionManager
    /// @param _borrower The Cdp owner who use eBTC
    /// @param _positionManager The position manager address in question whether it gets valid approval from _borrower
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

    /// @notice Approve an account (_positionManager) to take arbitrary actions on your Cdps.
    /// @notice Position managers with 'Persistent' status will be able to take actions indefinitely
    /// @notice Position managers with 'OneTIme' status will be able to take a single action on one Cdp. Approval will be automatically revoked after one Cdp-related action.
    /// @notice Similar to approving tokens, approving a position manager allows _stealing of all positions_ if given to a malicious account.
    /// @param _positionManager The position manager address which will get the specified approval from caller
    /// @param _approval PositionManagerApproval (None/OneTime/Persistent) status set to the specified _positionManager for caller's Cdp
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
    /// @param _positionManager The position manager address which will get all approval revoked by caller (a Cdp owner)
    function revokePositionManagerApproval(address _positionManager) external override {
        _setPositionManagerApproval(msg.sender, _positionManager, PositionManagerApproval.None);
    }

    /// @notice Allows recipient of delegation to renounce it
    /// @param _borrower The Cdp owner address which will have all approval to the caller (a PositionManager) revoked.
    function renouncePositionManagerApproval(address _borrower) external override {
        _setPositionManagerApproval(_borrower, msg.sender, PositionManagerApproval.None);
    }

    /// @notice This function returns the domain separator for current chain
    /// @return EIP712 compatible Domain definition
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return domainSeparator();
    }

    /// @notice This function returns the domain separator for current chain
    /// @return EIP712 compatible Domain definition
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

    /// @notice This function returns the version parameter for the EIP712 domain
    /// @return EIP712 compatible version parameter
    function version() external pure override returns (string memory) {
        return _VERSION;
    }

    /// @notice This function returns hash of the fully encoded EIP712 message for the permitPositionManagerApproval.
    /// @return EIP712 compatible hash of Positon Manager permit
    function permitTypeHash() external pure override returns (bytes32) {
        return _PERMIT_POSITION_MANAGER_TYPEHASH;
    }

    /// @notice This function set given _approval for specified _borrower and _positionManager
    /// @notice by verifying the validity of given deadline and signature parameters (v, r, s).
    /// @param _borrower The Cdp owner
    /// @param _positionManager The delegate to which _borrower want to grant approval
    /// @param _approval The PositionManagerApproval (None/OneTime/Persistent) status to be set
    /// @param _deadline The permit valid deadline
    /// @param v The v part of signature from _borrower
    /// @param r The r part of signature from _borrower
    /// @param s The s part of signature from _borrower
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
    ) internal view returns (uint256 collSharesChange, bool isCollIncrease) {
        if (_collReceived != 0) {
            collSharesChange = collateral.getSharesByPooledEth(_collReceived);
            isCollIncrease = true;
        } else {
            collSharesChange = collateral.getSharesByPooledEth(_requestedCollWithdrawal);
        }
    }

    /**
        @notice Process the token movements required by a Cdp adjustment.
        @notice Handles the cases of a debt increase / decrease, and/or a collateral increase / decrease.
     */
    function _processTokenMovesFromAdjustment(MoveTokensParams memory _varMvTokens) internal {
        // Debt increase: mint change value of new eBTC to user, increment ActivePool eBTC internal accounting
        if (_varMvTokens.isDebtIncrease) {
            _withdrawDebt(_varMvTokens.user, _varMvTokens.netDebtChange);
        } else {
            // Debt decrease: burn change value of eBTC from user, decrement ActivePool eBTC internal accounting
            _repayDebt(_varMvTokens.user, _varMvTokens.netDebtChange);
        }

        if (_varMvTokens.isCollIncrease) {
            // Coll increase: send change value of stETH to Active Pool, increment ActivePool stETH internal accounting
            _activePoolAddColl(_varMvTokens.collAddUnderlying, _varMvTokens.collSharesChange);
        } else {
            // Coll decrease: send change value of stETH to user, decrement ActivePool stETH internal accounting
            activePool.transferSystemCollShares(_varMvTokens.user, _varMvTokens.collSharesChange);
        }
    }

    /// @notice Send stETH to Active Pool and increase its recorded ETH balance
    /// @param _stEthBalance total balance of stETH to send, inclusive of coll and liquidatorRewardShares
    /// @param _sharesToTrack coll as shares (exclsuive of liquidator reward shares)
    /// @dev Liquidator reward shares are not considered as part of the system for CR purposes.
    /// @dev These number of liquidator shares associated with each Cdp are stored in the Cdp, while the actual tokens float in the active pool
    function _activePoolAddColl(uint256 _stEthBalance, uint256 _sharesToTrack) internal {
        // NOTE: No need for safe transfer if the collateral asset is standard. Make sure this is the case!
        collateral.transferFrom(msg.sender, address(activePool), _stEthBalance);
        activePool.increaseSystemCollShares(_sharesToTrack);
    }

    /// @dev Mint specified debt tokens to account and change global debt accounting accordingly
    function _withdrawDebt(address _account, uint256 _debt) internal {
        activePool.increaseSystemDebt(_debt);
        ebtcToken.mint(_account, _debt);
    }

    // Burn the specified amount of EBTC from _account and decreases the total active debt
    function _repayDebt(address _account, uint256 _debt) internal {
        activePool.decreaseSystemDebt(_debt);
        ebtcToken.burn(_account, _debt);
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
        uint256 _debtChange,
        uint256 _stEthBalanceDecrease
    ) internal pure {
        require(
            _stEthBalanceIncrease > 0 || _stEthBalanceDecrease > 0 || _debtChange > 0,
            "BorrowerOperations: There must be either a collateral or debt change"
        );
    }

    function _requireZeroOrMinAdjustment(uint256 _change) internal pure {
        require(
            _change == 0 || _change >= MIN_CHANGE,
            "BorrowerOperations: Collateral or debt change must be zero or above min"
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

    function _requireMinDebtChange(uint _debtChange) internal pure {
        require(
            _debtChange >= MIN_CHANGE,
            "BorrowerOperations: Debt increase requires min debtChange"
        );
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
            "BorrowerOperations: Collateral withdrawal not permitted during Recovery Mode"
        );
    }

    function _requireValidAdjustmentInCurrentMode(
        bool _isRecoveryMode,
        uint256 _stEthBalanceDecrease,
        bool _isDebtIncrease,
        AdjustCdpLocals memory _vars
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
            collateral.getPooledEthByShares(_vars.collSharesChange),
            _vars.isCollIncrease,
            _vars.netDebtChange,
            _isDebtIncrease,
            _vars.price
        );

        if (_isRecoveryMode) {
            _requireNoStEthBalanceDecrease(_stEthBalanceDecrease);
            if (_isDebtIncrease) {
                _requireICRisNotBelowCCR(_vars.newICR);
                _requireNoDecreaseOfICR(_vars.newICR, _vars.oldICR);
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
            _requireICRisNotBelowMCR(_vars.newICR);
            _requireNewTCRisNotBelowCCR(_vars.newTCR);

            // == Grace Period == //
            // We are not in RM, no edge case, we always stay above RM
            // Always Notify Back to Normal Mode
            cdpManager.notifyEndGracePeriod(_vars.newTCR);
        }
    }

    function _requireICRisNotBelowMCR(uint256 _newICR) internal pure {
        require(
            _newICR >= MCR,
            "BorrowerOperations: An operation that would result in ICR < MCR is not permitted"
        );
    }

    function _requireICRisNotBelowCCR(uint256 _newICR) internal pure {
        require(_newICR >= CCR, "BorrowerOperations: Operation must leave cdp with ICR >= CCR");
    }

    function _requireNoDecreaseOfICR(uint256 _newICR, uint256 _oldICR) internal pure {
        require(
            _newICR >= _oldICR,
            "BorrowerOperations: Cannot decrease your Cdp's ICR in Recovery Mode"
        );
    }

    function _requireNewTCRisNotBelowCCR(uint256 _newTCR) internal pure {
        require(
            _newTCR >= CCR,
            "BorrowerOperations: An operation that would result in TCR < CCR is not permitted"
        );
    }

    function _requireMinDebt(uint256 _debt) internal pure {
        require(_debt >= MIN_CHANGE, "BorrowerOperations: Debt must be above min");
    }

    function _requireAtLeastMinNetStEthBalance(uint256 _stEthBalance) internal pure {
        require(
            _stEthBalance >= MIN_NET_STETH_BALANCE,
            "BorrowerOperations: Cdp's net stEth balance must not fall below minimum"
        );
    }

    function _requireValidDebtRepayment(uint256 _currentDebt, uint256 _debtRepayment) internal pure {
        require(
            _debtRepayment <= _currentDebt,
            "BorrowerOperations: Amount repaid must not be larger than the Cdp's debt"
        );
    }

    function _requireSufficientEbtcTokenBalance(
        address _account,
        uint256 _debtRepayment
    ) internal view {
        require(
            ebtcToken.balanceOf(_account) >= _debtRepayment,
            "BorrowerOperations: Caller doesnt have enough eBTC to make repayment"
        );
    }

    function _requireBorrowerOrPositionManagerAndUpdateManagerApproval(address _borrower) internal {
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
        /// @dev If the PositionManagerApproval was none, we should have failed with the check in _requireBorrowerOrPositionManagerAndUpdateManagerApproval
        if (_approval == PositionManagerApproval.OneTime) {
            _setPositionManagerApproval(_borrower, msg.sender, PositionManagerApproval.None);
        }
    }

    // --- ICR and TCR getters ---

    // Compute the new collateral ratio, considering the change in coll and debt. Assumes 0 pending rewards.
    function _getNewNominalICRFromCdpChange(
        AdjustCdpLocals memory vars,
        bool _isDebtIncrease
    ) internal pure returns (uint256) {
        (uint256 newCollShares, uint256 newDebt) = _getNewCdpAmounts(
            vars.collShares,
            vars.debt,
            vars.collSharesChange,
            vars.isCollIncrease,
            vars.netDebtChange,
            _isDebtIncrease
        );

        uint256 newNICR = EbtcMath._computeNominalCR(newCollShares, newDebt);
        return newNICR;
    }

    // Compute the new collateral ratio, considering the change in coll and debt. Assumes 0 pending rewards.
    function _getNewICRFromCdpChange(
        uint256 _collShares,
        uint256 _debt,
        uint256 _collSharesChange,
        bool _isCollIncrease,
        uint256 _debtChange,
        bool _isDebtIncrease,
        uint256 _price
    ) internal view returns (uint256) {
        (uint256 newCollShares, uint256 newDebt) = _getNewCdpAmounts(
            _collShares,
            _debt,
            _collSharesChange,
            _isCollIncrease,
            _debtChange,
            _isDebtIncrease
        );

        uint256 newICR = EbtcMath._computeCR(
            collateral.getPooledEthByShares(newCollShares),
            newDebt,
            _price
        );
        return newICR;
    }

    function _getNewCdpAmounts(
        uint256 _collShares,
        uint256 _debt,
        uint256 _collSharesChange,
        bool _isCollIncrease,
        uint256 _debtChange,
        bool _isDebtIncrease
    ) internal pure returns (uint256, uint256) {
        uint256 newCollShares = _collShares;
        uint256 newDebt = _debt;

        newCollShares = _isCollIncrease
            ? _collShares + _collSharesChange
            : _collShares - _collSharesChange;
        newDebt = _isDebtIncrease ? _debt + _debtChange : _debt - _debtChange;

        return (newCollShares, newDebt);
    }

    function _getNewTCRFromCdpChange(
        uint256 _stEthBalanceChange,
        bool _isCollIncrease,
        uint256 _debtChange,
        bool _isDebtIncrease,
        uint256 _price
    ) internal view returns (uint256) {
        uint256 _systemCollShares = getSystemCollShares();
        uint256 systemStEthBalance = collateral.getPooledEthByShares(_systemCollShares);
        uint256 systemDebt = _getSystemDebt();

        systemStEthBalance = _isCollIncrease
            ? systemStEthBalance + _stEthBalanceChange
            : systemStEthBalance - _stEthBalanceChange;
        systemDebt = _isDebtIncrease ? systemDebt + _debtChange : systemDebt - _debtChange;

        uint256 newTCR = EbtcMath._computeCR(systemStEthBalance, systemDebt, _price);
        return newTCR;
    }

    // === Flash Loans === //

    /// @notice Borrow assets with a flash loan
    /// @param receiver The address to receive the flash loan
    /// @param token The address of the token to loan
    /// @param amount The amount of tokens to loan
    /// @param data Additional data
    /// @return A boolean value indicating whether the operation was successful
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

    /// @notice Calculate the flash loan fee for a given token and amount loaned
    /// @param token The address of the token to calculate the fee for
    /// @param amount The amount of tokens to calculate the fee for
    /// @return The flashloan fee calcualted for given token and loan amount
    function flashFee(address token, uint256 amount) public view override returns (uint256) {
        require(token == address(ebtcToken), "BorrowerOperations: EBTC Only");
        require(!flashLoansPaused, "BorrowerOperations: Flash Loans Paused");

        return (amount * feeBps) / MAX_BPS;
    }

    /// @notice Get the maximum flash loan amount for a specific token
    /// @param token The address of the token to get the maximum flash loan amount for, exclusively used here for eBTC token
    /// @return The maximum available flashloan amount for the token, equals to `type(uint112).max`
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

    /// @notice Sets new Fee for FlashLoans
    /// @param _newFee The new flashloan fee to be set
    function setFeeBps(uint256 _newFee) external requiresAuth {
        require(_newFee <= MAX_FEE_BPS, "ERC3156FlashLender: _newFee should <= MAX_FEE_BPS");

        cdpManager.syncGlobalAccounting();

        // set new flash fee
        uint256 _oldFee = feeBps;
        feeBps = uint16(_newFee);
        emit FlashFeeSet(msg.sender, _oldFee, _newFee);
    }

    /// @notice Should Flashloans be paused?
    /// @param _paused The flag (true or false) whether flashloan will be paused
    function setFlashLoansPaused(bool _paused) external requiresAuth {
        cdpManager.syncGlobalAccounting();

        flashLoansPaused = _paused;
        emit FlashLoansPaused(msg.sender, _paused);
    }
}
