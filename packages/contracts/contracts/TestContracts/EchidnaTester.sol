// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "../CdpManager.sol";
import "../BorrowerOperations.sol";
import "../ActivePool.sol";
import "../DefaultPool.sol";
import "../GasPool.sol";
import "../CollSurplusPool.sol";
import "../SortedCdps.sol";
import "../HintHelpers.sol";
import "../LQTY/FeeRecipient.sol";
import "./PriceFeedTestnet.sol";
import "./CollateralTokenTester.sol";
import "./EchidnaProxy.sol";
import "./EBTCTokenTester.sol";
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
// ~/.local/bin/echidna-test contracts/TestContracts/EchidnaTester.sol --test-mode property --contract EchidnaTester --config fuzzTests/echidna_config.yaml --crytic-args "--solc <your-path-to-solc0611>"
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
    EBTCTokenTester private eBTCToken;
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
    uint private constant diff_tolerance = 2000000; //compared to 1e18

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
                collateral,
                activePool,
                priceFeedTestnet
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
        eBTCToken = new EBTCTokenTester(
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

    ///////////////////////////////////////////////////////
    // Helper functions
    ///////////////////////////////////////////////////////

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

    function _getRandomCdp(uint _i) internal view returns (bytes32) {
        uint _cdpIdx = _i % cdpManager.getCdpIdsCount();
        return cdpManager.CdpIds(_cdpIdx);
    }

    function _getNewPriceForLiquidation(
        uint _i
    ) internal view returns (uint _oldPrice, uint _newPrice) {
        uint _priceDiv = _i % 10;
        _oldPrice = priceFeedTestnet.getPrice();
        _newPrice = _oldPrice / _priceDiv;
    }

    function _assertApproximateEq(
        uint _num1,
        uint _num2,
        uint _tolerance
    ) internal pure returns (bool) {
        if (_num1 > _num2) {
            return _tolerance >= _num1.sub(_num2);
        } else {
            return _tolerance >= _num2.sub(_num1);
        }
    }

    ///////////////////////////////////////////////////////
    // CdpManager
    ///////////////////////////////////////////////////////

    function liquidateExt(uint _i) external {
        uint actor = _getRandomActor(_i);
        EchidnaProxy echidnaProxy = echidnaProxies[actor];
        bytes32 _cdpId = _getRandomCdp(_i);

        (uint _oldPrice, uint _newPrice) = _getNewPriceForLiquidation(_i);
        priceFeedTestnet.setPrice(_newPrice);

        uint _icr = cdpManager.getCurrentICR(_cdpId, _newPrice);
        bool _recovery = cdpManager.checkRecoveryMode(_newPrice);

        if (_icr < cdpManager.MCR() || (_recovery && _icr < cdpManager.getTCR(_newPrice))) {
            (uint256 entireDebt, , , ) = cdpManager.getEntireDebtAndColl(_cdpId);
            eBTCToken.unprotectedMint(address(echidnaProxy), entireDebt);
            uint _totalSupplyBefore = eBTCToken.totalSupply();
            echidnaProxy.liquidatePrx(_cdpId);
            require(!sortedCdps.contains(_cdpId), "!ClosedByLiquidation");
            uint _totalSupplyDiff = _totalSupplyBefore - eBTCToken.totalSupply();
			if (_totalSupplyDiff < entireDebt){
			    eBTCToken.unprotectedBurn(address(echidnaProxy), entireDebt - _totalSupplyDiff);
			}
        }

        priceFeedTestnet.setPrice(_oldPrice);
    }

    function partialLiquidateExt(uint _i, uint _partialAmount) external {
        uint actor = _getRandomActor(_i);
        EchidnaProxy echidnaProxy = echidnaProxies[actor];
        bytes32 _cdpId = _getRandomCdp(_i);

        (uint _oldPrice, uint _newPrice) = _getNewPriceForLiquidation(_i);
        priceFeedTestnet.setPrice(_newPrice);

        uint _icr = cdpManager.getCurrentICR(_cdpId, _newPrice);
        bool _recovery = cdpManager.checkRecoveryMode(_newPrice);

        if (_icr < cdpManager.MCR() || (_recovery && _icr < cdpManager.getTCR(_newPrice))) {
            (uint256 entireDebt, , , ) = cdpManager.getEntireDebtAndColl(_cdpId);
            eBTCToken.unprotectedMint(address(echidnaProxy), _partialAmount);
            require(_partialAmount < entireDebt, "!_partialAmount");
            uint _totalSupplyBefore = eBTCToken.totalSupply();
            echidnaProxy.partialLiquidatePrx(_cdpId, _partialAmount);
            (uint256 _newEntireDebt, , , ) = cdpManager.getEntireDebtAndColl(_cdpId);
            require(_newEntireDebt < entireDebt, "!reducedByPartialLiquidation");
            uint _totalSupplyDiff = _totalSupplyBefore - eBTCToken.totalSupply();
			if (_totalSupplyDiff < _partialAmount){
			    eBTCToken.unprotectedBurn(address(echidnaProxy), _partialAmount - _totalSupplyDiff);
			}
        }

        priceFeedTestnet.setPrice(_oldPrice);
    }

    function liquidateCdpsExt(uint _i, uint _n) external {
        uint actor = _getRandomActor(_i);
        EchidnaProxy echidnaProxy = echidnaProxies[actor];

        (uint _oldPrice, uint _newPrice) = _getNewPriceForLiquidation(_i);
        priceFeedTestnet.setPrice(_newPrice);

        if (_n > cdpManager.getCdpIdsCount()) {
            _n = cdpManager.getCdpIdsCount();
        }
		
        uint _sugar = cdpManager.getEntireSystemDebt();
        eBTCToken.unprotectedMint(address(echidnaProxy), _sugar);
        uint _totalSupplyBefore = eBTCToken.totalSupply();
        echidnaProxy.liquidateCdpsPrx(_n);
        uint _totalSupplyDiff = _totalSupplyBefore - eBTCToken.totalSupply();
        if (_totalSupplyDiff < _sugar){
            eBTCToken.unprotectedBurn(address(echidnaProxy), _sugar - _totalSupplyDiff);
        }

        priceFeedTestnet.setPrice(_oldPrice);
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
        EchidnaProxy echidnaProxy = echidnaProxies[actor];
        eBTCToken.unprotectedMint(address(echidnaProxy), _EBTCAmount);
        uint _totalSupplyBefore = eBTCToken.totalSupply();
        echidnaProxy.redeemCollateralPrx(
            _EBTCAmount,
            _firstRedemptionHint,
            _upperPartialRedemptionHint,
            _lowerPartialRedemptionHint,
            _partialRedemptionHintNICR,
            0,
            0
        );
        uint _totalSupplyDiff = _totalSupplyBefore - eBTCToken.totalSupply();
        if (_totalSupplyDiff < _EBTCAmount){
            eBTCToken.unprotectedBurn(address(echidnaProxy), _EBTCAmount - _totalSupplyDiff);
        }
    }

    function claimSplitFee() external {
        cdpManager.claimStakingSplitFee();
    }

    ///////////////////////////////////////////////////////
    // ActivePool
    ///////////////////////////////////////////////////////

    function flashloanCollExt(uint _i, uint _collAmount) public {
        uint actor = _getRandomActor(_i);
        EchidnaProxy echidnaProxy = echidnaProxies[actor];
        echidnaProxy.flashloanColl(_collAmount);
    }

    ///////////////////////////////////////////////////////
    // BorrowerOperations
    ///////////////////////////////////////////////////////

    function flashloanEBTCExt(uint _i, uint _EBTCAmount) public {
        uint actor = _getRandomActor(_i);
        EchidnaProxy echidnaProxy = echidnaProxies[actor];
        echidnaProxy.flashloanEBTC(_EBTCAmount);
    }

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
    }

    function openCdpWithCollExt(uint _i, uint _coll, uint _EBTCAmount) public {
        uint actor = _getRandomActor(_i);
        EchidnaProxy echidnaProxy = echidnaProxies[actor];

        uint price = priceFeedTestnet.getPrice();
        require(price > 0);
        require(_EBTCAmount.mul(MCR).div(price) < _coll, "!openCdpRawExt_EBTCAmount");

        uint actorBalance = collateral.balanceOf(address(echidnaProxy));
        if (actorBalance < _coll) {
            echidnaProxy.dealCollateral(_coll.sub(actorBalance));
        }
        echidnaProxies[actor].openCdpPrx(_coll, _EBTCAmount, bytes32(0), bytes32(0));

        numberOfCdps = cdpManager.getCdpIdsCount();
        assert(numberOfCdps > 0);
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

    function withdrawCollExt(uint _i, uint _amount) external {
        uint actor = _getRandomActor(_i);
        EchidnaProxy echidnaProxy = echidnaProxies[actor];
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(echidnaProxy), 0);
        require(_cdpId != bytes32(0), "!cdpId");

        CDPChange memory _change = CDPChange(0, _amount, 0, 0);
        _ensureMCR(_cdpId, _change);

        echidnaProxy.withdrawCollPrx(_cdpId, _amount, _cdpId, _cdpId);
    }

    function withdrawEBTCExt(uint _i, uint _amount) external {
        uint actor = _getRandomActor(_i);
        EchidnaProxy echidnaProxy = echidnaProxies[actor];
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(echidnaProxy), 0);
        require(_cdpId != bytes32(0), "!cdpId");

        CDPChange memory _change = CDPChange(0, 0, _amount, 0);
        _ensureMCR(_cdpId, _change);

        echidnaProxy.withdrawEBTCPrx(_cdpId, _amount, _cdpId, _cdpId);
    }

    function repayEBTCExt(uint _i, uint _amount) external {
        uint actor = _getRandomActor(_i);
        EchidnaProxy echidnaProxy = echidnaProxies[actor];
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(echidnaProxy), 0);
        require(_cdpId != bytes32(0), "!cdpId");
        (uint256 entireDebt, , , ) = cdpManager.getEntireDebtAndColl(_cdpId);
        require(_amount <= entireDebt, "!repayEBTC_amount");
        eBTCToken.unprotectedMint(address(echidnaProxy), _amount);
        uint _totalSupplyBefore = eBTCToken.totalSupply();
        echidnaProxy.repayEBTCPrx(_cdpId, _amount, _cdpId, _cdpId);
        uint _totalSupplyDiff = _totalSupplyBefore - eBTCToken.totalSupply();
        if (_totalSupplyDiff < _amount){
            eBTCToken.unprotectedBurn(address(echidnaProxy), _amount - _totalSupplyDiff);
        }
    }

    function closeCdpExt(uint _i) external {
        uint actor = _getRandomActor(_i);
        EchidnaProxy echidnaProxy = echidnaProxies[actor];
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(echidnaProxy), 0);
        require(_cdpId != bytes32(0), "!cdpId");
        require(1 == cdpManager.getCdpStatus(_cdpId), "!closeCdpExtActive");
        (uint256 entireDebt, , , ) = cdpManager.getEntireDebtAndColl(_cdpId);
        eBTCToken.unprotectedMint(address(echidnaProxy), entireDebt);
        uint _totalSupplyBefore = eBTCToken.totalSupply();
        echidnaProxies[actor].closeCdpPrx(_cdpId);
        uint _totalSupplyDiff = _totalSupplyBefore - eBTCToken.totalSupply();
        if (_totalSupplyDiff < entireDebt){
            eBTCToken.unprotectedBurn(address(echidnaProxy), entireDebt - _totalSupplyDiff);
        }
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
        uint _totalSupplyBefore;
        if (_isDebtIncrease) {
            _change = CDPChange(0, _collWithdrawal, _debtChange, 0);
        } else {
            require(_debtChange < entireDebt, "!adjustCdpExt_debtChange");
            eBTCToken.unprotectedMint(address(echidnaProxy), _debtChange);
            _totalSupplyBefore = eBTCToken.totalSupply();
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
		if (_totalSupplyBefore > 0){
            uint _totalSupplyDiff = _totalSupplyBefore - eBTCToken.totalSupply();
            if (_totalSupplyDiff < _debtChange){
                eBTCToken.unprotectedBurn(address(echidnaProxy), _debtChange - _totalSupplyDiff);
            }		
		}
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

    ///////////////////////////////////////////////////////
    // Collateral Token (Test)
    ///////////////////////////////////////////////////////

    function increaseCollateralRate(uint _newBiggerIndex) external {
        require(_newBiggerIndex > collateral.getPooledEthByShares(1e18), "!biggerNewRate");
        require(_newBiggerIndex < 10000e18, "!nonsenseNewBiggerRate");
        collateral.setEthPerShare(_newBiggerIndex);
    }
    
    // Example for real world slashing: https://twitter.com/LidoFinance/status/1646505631678107649
    // > There are 11 slashing ongoing with the RockLogic GmbH node operator in Lido. 
    // > the total projected impact is around 20 ETH, 
    // > or about 3% of average daily protocol rewards/0.0004% of TVL.
    function decreaseCollateralRate(uint _newSmallerIndex) external {
        require(_newSmallerIndex < collateral.getPooledEthByShares(1e18), "!smallerNewRate");
        require(_newSmallerIndex > 0, "!nonsenseNewSmallerRate");
        collateral.setEthPerShare(_newSmallerIndex);
    }

    // --------------------------
    // Invariants and properties
    // --------------------------

    function echidna_canary_active_pool_balance() public view returns (bool) {
        if (cdpManager.getCdpIdsCount() > 0 && collateral.balanceOf(address(activePool)) <= 0) {
            return false;
        }
        return true;
    }

    function _echidna_cdps_order() internal view returns (bool) {
        bytes32 currentCdp = sortedCdps.getFirst();
        bytes32 nextCdp = sortedCdps.getNext(currentCdp);

        while (currentCdp != bytes32(0) && nextCdp != bytes32(0) && currentCdp != nextCdp) {
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

            // Stake > 0
            if (cdpManager.getCdpStake(currentCdp) == 0) {
                return false;
            }

            currentCdp = sortedCdps.getNext(currentCdp);
        }
        return true;
    }

    function echidna_accounting_balances() public view returns (bool) {
        if (collateral.sharesOf(address(activePool)) < activePool.getETH()) {
            return false;
        }

        if (collateral.sharesOf(address(defaultPool)) < defaultPool.getETH()) {
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

        bytes32 currentCdp = sortedCdps.getFirst();
        uint cdpsBalance;
        while (currentCdp != bytes32(0)) {
            (uint256 entireDebt, uint256 entireColl, , ) = cdpManager.getEntireDebtAndColl(
                currentCdp
            );
            cdpsBalance = cdpsBalance.add(entireDebt);
            currentCdp = sortedCdps.getNext(currentCdp);
        }

        if (totalSupply < cdpsBalance) {
            return false;
        }

        return true;
    }

    ////////////////////////////////////////////////////////////////////////////
    // Basic Invariants for ebtc system
    // - active_pool_1： collateral balance in active pool is greater than or equal to its accounting number
    // - active_pool_2： EBTC debt accounting number in active pool is less than or equal to EBTC total supply
    // - active_pool_3： sum of EBTC debt accounting numbers in active pool & default pool is equal to EBTC total supply
    // - active_pool_4： total collateral in active pool should be equal to the sum of all individual CDP collateral
    // - cdp_manager_1： count of active CDPs is equal to SortedCdp list length
    // - cdp_manager_2： sum of active CDPs stake is equal to totalStakes
    // - cdp_manager_3： stFeePerUnit tracker for individual CDP is equal to or less than the global variable
    // - default_pool_1： collateral balance in default pool is greater than or equal to its accounting number
    // - default_pool_2： sum of debt accounting in default pool and active pool should be equal to sum of debt accounting of individual CDPs
    // - coll_surplus_pool_1： collateral balance in collSurplus pool is greater than or equal to its accounting number
    // - sorted_list_1： NICR ranking in the sorted list should follow descending order
    // - sorted_list_2： the first(highest) ICR in the sorted list should be bigger or equal to TCR
    ////////////////////////////////////////////////////////////////////////////

    function echidna_active_pool_invariant_1() public view returns (bool) {
        if (collateral.sharesOf(address(activePool)) < activePool.getETH()) {
            return false;
        }
        return true;
    }

    function echidna_active_pool_invariant_2() public view returns (bool) {
        if (eBTCToken.totalSupply() < activePool.getEBTCDebt()) {
            return false;
        }
        return true;
    }

    function echidna_active_pool_invariant_3() public view returns (bool) {
        if (eBTCToken.totalSupply() != activePool.getEBTCDebt().add(defaultPool.getEBTCDebt())) {
            return false;
        }
        return true;
    }

    function echidna_active_pool_invariant_4() public view returns (bool) {
        uint _cdpCount = cdpManager.getCdpIdsCount();
        uint _sum;
        for (uint i = 0; i < _cdpCount; ++i) {
            (, uint _coll, , ) = cdpManager.getEntireDebtAndColl(cdpManager.CdpIds(i));
            _sum = _sum.add(_coll);
        }
        uint _activeColl = activePool.getETH();
		uint _diff = _sum > _activeColl? (_sum - _activeColl) : (_activeColl - _sum);
		uint _divisor = _sum > _activeColl? _sum : _activeColl;
        if (_diff * 1e18 > diff_tolerance * _activeColl) {
            return false;
        }
        return true;
    }

    function echidna_cdp_manager_invariant_1() public view returns (bool) {
        if (cdpManager.getCdpIdsCount() != sortedCdps.getSize()) {
            return false;
        }
        return true;
    }

    function echidna_cdp_manager_invariant_2() public view returns (bool) {
        uint _cdpCount = cdpManager.getCdpIdsCount();
        uint _sum;
        for (uint i = 0; i < _cdpCount; ++i) {
            _sum = _sum.add(cdpManager.getCdpStake(cdpManager.CdpIds(i)));
        }
        if (_sum != cdpManager.totalStakes()) {
            return false;
        }
        return true;
    }

    function echidna_cdp_manager_invariant_3() public view returns (bool) {
        uint _cdpCount = cdpManager.getCdpIdsCount();
        uint _stFeePerUnitg = cdpManager.stFeePerUnitg();
        for (uint i = 0; i < _cdpCount; ++i) {
            if (_stFeePerUnitg < cdpManager.stFeePerUnitcdp(cdpManager.CdpIds(i))) {
                return false;
            }
        }
        return true;
    }

    function echidna_default_pool_invariant_1() public view returns (bool) {
        if (collateral.sharesOf(address(defaultPool)) < defaultPool.getETH()) {
            return false;
        }
        return true;
    }

    function echidna_default_pool_invariant_2() public view returns (bool) {
        uint _cdpCount = cdpManager.getCdpIdsCount();
        uint _sum;
        for (uint i = 0; i < _cdpCount; ++i) {
            (uint _debt, , , ) = cdpManager.getEntireDebtAndColl(cdpManager.CdpIds(i));
            _sum = _sum.add(_debt);
        }
        if (!_assertApproximateEq(_sum, cdpManager.getEntireSystemDebt(), diff_tolerance)) {
            return false;
        }
        return true;
    }

    function echidna_coll_surplus_pool_invariant_1() public view returns (bool) {
        if (collateral.sharesOf(address(collSurplusPool)) < collSurplusPool.getETH()) {
            return false;
        }
        return true;
    }

    function echidna_sorted_list_invariant_1() public view returns (bool) {
        return _echidna_cdps_order();
    }

    function echidna_sorted_list_invariant_2() public view returns (bool) {
        bytes32 _first = sortedCdps.getFirst();
        uint _price = priceFeedTestnet.getPrice();
        if (
            _first != sortedCdps.dummyId() &&
            _price > 0 &&
            cdpManager.getCurrentICR(_first, _price) < cdpManager.getTCR(_price)
        ) {
            return false;
        }
        return true;
    }
}
