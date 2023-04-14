// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../CdpManager.sol";
import "../BorrowerOperations.sol";
import "../ActivePool.sol";
import "../DefaultPool.sol";
import "../GasPool.sol";
import "../CollSurplusPool.sol";
import "../EBTCToken.sol";
import "../SortedCdps.sol";
import "../HintHelpers.sol";
import "../LQTY/FeeRecipient.sol";
import "./PriceFeedTestnet.sol";
import "./CollateralTokenTester.sol";
import "./EchidnaProxy.sol";
import "../Governor.sol";

// https://hevm.dev/controlling-the-unit-testing-environment.html#cheat-codes
interface IHevm {
    // Sets the block timestamp to x.
    function warp(uint x) external;

    // Sets the block number to x.
    function roll(uint x) external;

    // Sets msg.sender to the specified sender for the next call.
    function prank(address sender) external;

    // Sets the slot loc of contract c to val.
    function store(address c, bytes32 loc, bytes32 val) external;

    // Reads the slot loc of contract c.
    function load(address c, bytes32 loc) external returns (bytes32 val);
}

// Run with:
// rm -f fuzzTests/corpus/* # (optional)
// ~/.local/bin/echidna-test contracts/TestContracts/EchidnaTester.sol --test-mode assertion --contract EchidnaTester --config fuzzTests/echidna_config.yaml --crytic-args "--solc <your-path-to-solc0611>"
contract EchidnaTester {
    using SafeMath for uint;

    uint private constant NUMBER_OF_ACTORS = 100;
    uint private constant INITIAL_BALANCE = 1e24;
    uint private constant INITIAL_COLL_BALANCE = 1e21;
    uint private MCR;
    uint private CCR;
    uint private LICR;
    uint private MIN_NET_DEBT;

    CdpManager private cdpManager;
    BorrowerOperations private borrowerOperations;
    ActivePool private activePool;
    DefaultPool private defaultPool;
    GasPool private gasPool;
    CollSurplusPool private collSurplusPool;
    EBTCToken private eBTCToken;
    SortedCdps private sortedCdps;
    HintHelpers private hintHelpers;
    PriceFeedTestnet private priceFeedTestnet;
    CollateralTokenTester private collateral;
    FeeRecipient private feeRecipient;
    Governor private authority;
    address defaultGovernance;

    EchidnaProxy[NUMBER_OF_ACTORS] private echidnaProxies;

    uint private numberOfCdps;

    address private constant hevm = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;

    // -- Permissioned Function Signatures for Authority --
    // CDPManager
    bytes4 private constant SET_STAKING_REWARD_SPLIT_SIG =
        bytes4(keccak256(bytes("setStakingRewardSplit(uint256)")));

    // EBTCToken
    bytes4 private constant MINT_SIG = bytes4(keccak256(bytes("mint(address,uint256)")));
    bytes4 private constant BURN_SIG = bytes4(keccak256(bytes("burn(address,uint256)")));

    struct CDPChange {
        uint collAddition;
        uint collReduction;
        uint debtAddition;
        uint debtReduction;
    }

    constructor() public payable {
        _setUp();
        _connectCoreContracts();
        _connectLQTYContractsToCore();

        for (uint i = 0; i < NUMBER_OF_ACTORS; i++) {
            echidnaProxies[i] = new EchidnaProxy(
                cdpManager,
                borrowerOperations,
                eBTCToken,
                collateral
            );
            (bool success, ) = address(echidnaProxies[i]).call{value: INITIAL_BALANCE}("");
            require(success);
            echidnaProxies[i].dealCollateral(INITIAL_COLL_BALANCE);
        }

        MCR = cdpManager.MCR();
        CCR = cdpManager.CCR();
        LICR = cdpManager.LICR();
        MIN_NET_DEBT = cdpManager.MIN_NET_DEBT();
        require(MCR > 0);
        require(CCR > 0);
        require(LICR > 0);
        require(MIN_NET_DEBT > 0);
    }

    /* basic function to call when setting up new echidna test
    Use in pair with connectCoreContracts to wire up infrastructure
    */
    function _setUp() internal {
        defaultGovernance = msg.sender;
        authority = new Governor(address(this));

        borrowerOperations = new BorrowerOperations();
        priceFeedTestnet = new PriceFeedTestnet();
        sortedCdps = new SortedCdps();
        cdpManager = new CdpManager();
        activePool = new ActivePool();
        gasPool = new GasPool();
        defaultPool = new DefaultPool();
        collSurplusPool = new CollSurplusPool();
        hintHelpers = new HintHelpers();
        eBTCToken = new EBTCToken(
            address(cdpManager),
            address(borrowerOperations),
            address(authority)
        );
        collateral = new CollateralTokenTester();

        // External Contracts
        feeRecipient = new FeeRecipient();

        // Configure authority
        authority.setRoleName(0, "Admin");
        authority.setRoleName(1, "eBTCToken: mint");
        authority.setRoleName(2, "eBTCToken: burn");
        authority.setRoleName(3, "CDPManager: setStakingRewardSplit");

        authority.setRoleCapability(1, address(eBTCToken), MINT_SIG, true);
        authority.setRoleCapability(2, address(eBTCToken), BURN_SIG, true);
        authority.setRoleCapability(3, address(cdpManager), SET_STAKING_REWARD_SPLIT_SIG, true);

        authority.setUserRole(defaultGovernance, 0, true);
        authority.setUserRole(defaultGovernance, 1, true);
        authority.setUserRole(defaultGovernance, 2, true);
        authority.setUserRole(defaultGovernance, 3, true);

        authority.transferOwnership(defaultGovernance);
    }

    /* connectCoreContracts() - wiring up deployed contracts and setting up infrastructure
     */
    function _connectCoreContracts() internal {
        // set CdpManager addr in SortedCdps
        sortedCdps.setParams(type(uint256).max, address(cdpManager), address(borrowerOperations));

        IHevm(hevm).warp(block.timestamp + 86400);

        // set contracts in the Cdp Manager
        cdpManager.setAddresses(
            address(borrowerOperations),
            address(activePool),
            address(defaultPool),
            address(gasPool),
            address(collSurplusPool),
            address(priceFeedTestnet),
            address(eBTCToken),
            address(sortedCdps),
            address(feeRecipient),
            address(collateral),
            address(authority)
        );

        // set contracts in BorrowerOperations
        borrowerOperations.setAddresses(
            address(cdpManager),
            address(activePool),
            address(defaultPool),
            address(gasPool),
            address(collSurplusPool),
            address(priceFeedTestnet),
            address(sortedCdps),
            address(eBTCToken),
            address(feeRecipient),
            address(collateral)
        );

        // set contracts in activePool
        activePool.setAddresses(
            address(borrowerOperations),
            address(cdpManager),
            address(defaultPool),
            address(collateral),
            address(collSurplusPool),
            address(feeRecipient)
        );

        // set contracts in defaultPool
        defaultPool.setAddresses(address(cdpManager), address(activePool), address(collateral));

        // set contracts in collSurplusPool
        collSurplusPool.setAddresses(
            address(borrowerOperations),
            address(cdpManager),
            address(activePool),
            address(collateral)
        );

        // set contracts in HintHelpers
        hintHelpers.setAddresses(address(sortedCdps), address(cdpManager), address(collateral));
    }

    /* connectLQTYContractsToCore() - connect LQTY contracts to core contracts
     */
    function _connectLQTYContractsToCore() internal {
        feeRecipient.setAddresses(
            address(eBTCToken),
            address(cdpManager),
            address(borrowerOperations),
            address(activePool),
            address(collateral)
        );
    }

    function _ensureMCR(bytes32 _cdpId, CDPChange memory _change) internal {
        uint price = priceFeedTestnet.getPrice();
        require(price > 0);
        (uint256 entireDebt, uint256 entireColl, , ) = cdpManager.getEntireDebtAndColl(_cdpId);
        uint _debt = entireDebt.add(_change.debtAddition).sub(_change.debtReduction);
        uint _coll = entireColl.add(_change.collAddition).sub(_change.collReduction);
        require(_debt.mul(MCR).div(price) < _coll, "!CDP_MCR");
    }

    function _getRandomActor(uint _i) internal view returns (uint) {
        return _i % NUMBER_OF_ACTORS;
    }

    ///////////////////////////////////////////////////////
    // CdpManager
    ///////////////////////////////////////////////////////

    function liquidateExt(uint _i, bytes32 _cdpId) external {
        uint actor = _getRandomActor(_i);
        echidnaProxies[actor].liquidatePrx(_cdpId);
    }

    function liquidateCdpsExt(uint _i, uint _n) external {
        uint actor = _getRandomActor(_i);
        echidnaProxies[actor].liquidateCdpsPrx(_n);
    }

    function batchLiquidateCdpsExt(uint _i, bytes32[] calldata _cdpIdArray) external {
        uint actor = _getRandomActor(_i);
        echidnaProxies[actor].batchLiquidateCdpsPrx(_cdpIdArray);
    }

    function redeemCollateralExt(
        uint _i,
        uint _EBTCAmount,
        bytes32 _firstRedemptionHint,
        bytes32 _upperPartialRedemptionHint,
        bytes32 _lowerPartialRedemptionHint,
        uint _partialRedemptionHintNICR
    ) external {
        uint actor = _getRandomActor(_i);
        echidnaProxies[actor].redeemCollateralPrx(
            _EBTCAmount,
            _firstRedemptionHint,
            _upperPartialRedemptionHint,
            _lowerPartialRedemptionHint,
            _partialRedemptionHintNICR,
            0,
            0
        );
    }

    ///////////////////////////////////////////////////////
    // BorrowerOperations
    ///////////////////////////////////////////////////////

    function openCdpExt(uint _i, uint _EBTCAmount) public {
        uint actor = _getRandomActor(_i);
        EchidnaProxy echidnaProxy = echidnaProxies[actor];

        // we pass in CCR instead of MCR in case it’s the first one
        uint price = priceFeedTestnet.getPrice();
        require(price > 0);

        uint requiredCollAmount = _EBTCAmount.mul(CCR).div(price);
        uint actorBalance = collateral.balanceOf(address(echidnaProxy));
        if (actorBalance < requiredCollAmount) {
            echidnaProxy.dealCollateral(requiredCollAmount.sub(actorBalance));
        }
        echidnaProxy.openCdpPrx(requiredCollAmount, _EBTCAmount, bytes32(0), bytes32(0));

        numberOfCdps = cdpManager.getCdpIdsCount();
        assert(numberOfCdps > 0);
        // canary
        //assert(numberOfCdps == 0);
    }

    function openCdpRawExt(
        uint _i,
        uint _coll,
        uint _EBTCAmount,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint _maxFee
    ) public {
        uint actor = _getRandomActor(_i);
        EchidnaProxy echidnaProxy = echidnaProxies[actor];

        uint price = priceFeedTestnet.getPrice();
        require(price > 0);
        require(_EBTCAmount.mul(MCR).div(price) < _coll, "!openCdpRawExt_EBTCAmount");

        uint actorBalance = collateral.balanceOf(address(echidnaProxy));
        if (actorBalance < _coll) {
            echidnaProxy.dealCollateral(_coll.sub(actorBalance));
        }
        echidnaProxies[actor].openCdpPrx(_coll, _EBTCAmount, _upperHint, _lowerHint);
    }

    function addCollExt(uint _i, uint _coll) external {
        uint actor = _getRandomActor(_i);
        EchidnaProxy echidnaProxy = echidnaProxies[actor];
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(echidnaProxy), 0);
        require(_cdpId != bytes32(0), "!cdpId");
        uint actorBalance = collateral.balanceOf(address(echidnaProxy));
        if (actorBalance < _coll) {
            echidnaProxy.dealCollateral(_coll.sub(actorBalance));
        }

        echidnaProxy.addCollPrx(_cdpId, _coll, _cdpId, _cdpId);
    }

    function withdrawCollExt(
        uint _i,
        uint _amount,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external {
        uint actor = _getRandomActor(_i);
        EchidnaProxy echidnaProxy = echidnaProxies[actor];
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(echidnaProxy), 0);
        require(_cdpId != bytes32(0), "!cdpId");

        CDPChange memory _change = CDPChange(0, _amount, 0, 0);
        _ensureMCR(_cdpId, _change);

        echidnaProxy.withdrawCollPrx(_cdpId, _amount, _upperHint, _lowerHint);
    }

    function withdrawEBTCExt(
        uint _i,
        uint _amount,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external {
        uint actor = _getRandomActor(_i);
        EchidnaProxy echidnaProxy = echidnaProxies[actor];
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(echidnaProxy), 0);
        require(_cdpId != bytes32(0), "!cdpId");

        CDPChange memory _change = CDPChange(0, 0, _amount, 0);
        _ensureMCR(_cdpId, _change);

        echidnaProxy.withdrawEBTCPrx(_cdpId, _amount, _upperHint, _lowerHint);
    }

    function repayEBTCExt(uint _i, uint _amount, bytes32 _upperHint, bytes32 _lowerHint) external {
        uint actor = _getRandomActor(_i);
        EchidnaProxy echidnaProxy = echidnaProxies[actor];
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(echidnaProxy), 0);
        require(_cdpId != bytes32(0), "!cdpId");
        require(_amount <= cdpManager.getCdpDebt(_cdpId), "!repayEBTC_amount");
        echidnaProxy.repayEBTCPrx(_cdpId, _amount, _upperHint, _lowerHint);
    }

    function closeCdpExt(uint _i) external {
        uint actor = _getRandomActor(_i);
        EchidnaProxy echidnaProxy = echidnaProxies[actor];
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(echidnaProxy), 0);
        require(_cdpId != bytes32(0), "!cdpId");
        require(1 == cdpManager.getCdpStatus(_cdpId), "!closeCdpExtActive");
        echidnaProxies[actor].closeCdpPrx(_cdpId);
    }

    function adjustCdpExt(
        uint _i,
        uint _collWithdrawal,
        uint _debtChange,
        bool _isDebtIncrease
    ) external {
        uint actor = _getRandomActor(_i);
        EchidnaProxy echidnaProxy = echidnaProxies[actor];
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(echidnaProxy), 0);
        require(_cdpId != bytes32(0), "!cdpId");

        (uint256 entireDebt, uint256 entireColl, , ) = cdpManager.getEntireDebtAndColl(_cdpId);
        require(_collWithdrawal < entireColl, "!adjustCdpExt_collWithdrawal");

        uint price = priceFeedTestnet.getPrice();
        require(price > 0);

        uint debtChange = _debtChange;
        CDPChange memory _change;
        if (_isDebtIncrease) {
            _change = CDPChange(0, _collWithdrawal, _debtChange, 0);
        } else {
            require(_debtChange < entireDebt, "!adjustCdpExt_debtChange");
            _change = CDPChange(0, _collWithdrawal, 0, _debtChange);
        }
        _ensureMCR(_cdpId, _change);
        echidnaProxy.adjustCdpPrx(
            _cdpId,
            _collWithdrawal,
            debtChange,
            _isDebtIncrease,
            _cdpId,
            _cdpId
        );
    }

    ///////////////////////////////////////////////////////
    // EBTC Token
    ///////////////////////////////////////////////////////

    function transferExt(uint _i, address recipient, uint256 amount) external returns (bool) {
        uint actor = _getRandomActor(_i);
        echidnaProxies[actor].transferPrx(recipient, amount);
    }

    function approveExt(uint _i, address spender, uint256 amount) external returns (bool) {
        uint actor = _getRandomActor(_i);
        echidnaProxies[actor].approvePrx(spender, amount);
    }

    function transferFromExt(
        uint _i,
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool) {
        uint actor = _getRandomActor(_i);
        echidnaProxies[actor].transferFromPrx(sender, recipient, amount);
    }

    function increaseAllowanceExt(
        uint _i,
        address spender,
        uint256 addedValue
    ) external returns (bool) {
        uint actor = _getRandomActor(_i);
        echidnaProxies[actor].increaseAllowancePrx(spender, addedValue);
    }

    function decreaseAllowanceExt(
        uint _i,
        address spender,
        uint256 subtractedValue
    ) external returns (bool) {
        uint actor = _getRandomActor(_i);
        echidnaProxies[actor].decreaseAllowancePrx(spender, subtractedValue);
    }

    // --------------------------
    // Invariants and properties
    // --------------------------

    function echidna_canary_active_pool_balance() public view returns (bool) {
        if (collateral.balanceOf(address(activePool)) > 0) {
            return false;
        }
        return true;
    }

    function echidna_cdps_order() external view returns (bool) {
        bytes32 currentCdp = sortedCdps.getFirst();
        bytes32 nextCdp = sortedCdps.getNext(currentCdp);

        while (currentCdp != bytes32(0) && nextCdp != bytes32(0)) {
            if (cdpManager.getNominalICR(nextCdp) > cdpManager.getNominalICR(currentCdp)) {
                return false;
            }

            currentCdp = nextCdp;
            nextCdp = sortedCdps.getNext(currentCdp);
        }

        return true;
    }

    /**
     * - Status
     * - Minimum debt
     * - Stake
     */
    function echidna_cdp_properties() public view returns (bool) {
        bytes32 currentCdp = sortedCdps.getFirst();

        uint _price = priceFeedTestnet.getPrice();
        require(_price > 0, "!price");

        while (currentCdp != bytes32(0)) {
            // Status
            if (CdpManager.Status(cdpManager.getCdpStatus(currentCdp)) != CdpManager.Status.active) {
                return false;
            }

            // Minimum debt
            uint _icr = cdpManager.getCurrentICR(currentCdp, _price);
            if (cdpManager.getCdpDebt(currentCdp).mul(_icr).div(_price) < MIN_NET_DEBT) {
                return false;
            }

            // Stake > 0
            if (cdpManager.getCdpStake(currentCdp) == 0) {
                return false;
            }

            currentCdp = sortedCdps.getNext(currentCdp);
        }
        return true;
    }

    function echidna_ETH_balances() public view returns (bool) {
        if (collateral.balanceOf(address(cdpManager)) > 0) {
            return false;
        }

        if (collateral.balanceOf(address(borrowerOperations)) > 0) {
            return false;
        }

        if (collateral.sharesOf(address(activePool)) != activePool.getStEthColl()) {
            return false;
        }

        if (collateral.sharesOf(address(defaultPool)) != defaultPool.getStEthColl()) {
            return false;
        }

        if (collateral.balanceOf(address(eBTCToken)) > 0) {
            return false;
        }

        if (collateral.balanceOf(address(priceFeedTestnet)) > 0) {
            return false;
        }

        if (collateral.balanceOf(address(sortedCdps)) > 0) {
            return false;
        }

        return true;
    }

    function echidna_price() public view returns (bool) {
        uint price = priceFeedTestnet.getPrice();

        if (price == 0) {
            return false;
        }

        return true;
    }

    function echidna_EBTC_global_balances() public view returns (bool) {
        uint totalSupply = eBTCToken.totalSupply();

        uint activePoolBalance = activePool.getEBTCDebt();
        uint defaultPoolBalance = defaultPool.getEBTCDebt();
        if (totalSupply != activePoolBalance.add(defaultPoolBalance)) {
            return false;
        }

        bytes32 currentCdp = sortedCdps.getFirst();
        uint cdpsBalance;
        while (currentCdp != bytes32(0)) {
            (uint256 entireDebt, uint256 entireColl, , ) = cdpManager.getEntireDebtAndColl(
                currentCdp
            );
            cdpsBalance = cdpsBalance.add(entireDebt);
            currentCdp = sortedCdps.getNext(currentCdp);
        }

        if (totalSupply != cdpsBalance) {
            return false;
        }

        return true;
    }
}
