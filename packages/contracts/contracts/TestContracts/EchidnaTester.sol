// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../Interfaces/ICdpManagerData.sol";
import "../Dependencies/SafeMath.sol";
import "../CdpManager.sol";
import "../LiquidationLibrary.sol";
import "../BorrowerOperations.sol";
import "../ActivePool.sol";
import "../CollSurplusPool.sol";
import "../SortedCdps.sol";
import "../HintHelpers.sol";
import "../FeeRecipient.sol";
import "./testnet/PriceFeedTestnet.sol";
import "./CollateralTokenTester.sol";
import "./EchidnaProxy.sol";
import "./EBTCTokenTester.sol";
import "../Governor.sol";
import "../EBTCDeployer.sol";

import "./invariants/IHevm.sol";
import "./invariants/Properties.sol";

// Run with:
// cd <your-path-to-ebtc-repo-root>/packages/contracts
// rm -f ./fuzzTests/corpus/* # (optional)
// <your-path-to->/echidna-test contracts/TestContracts/EchidnaTester.sol --test-mode property --contract EchidnaTester --config fuzzTests/echidna_config.yaml --crytic-args "--solc <your-path-to-solc0817>" --solc-args "--base-path <your-path-to-ebtc-repo-root>/packages/contracts --include-path <your-path-to-ebtc-repo-root>/packages/contracts/contracts --include-path <your-path-to-ebtc-repo-root>/packages/contracts/contracts/Dependencies -include-path <your-path-to-ebtc-repo-root>/packages/contracts/contracts/Interfaces"
contract EchidnaTester is Properties {
    using SafeMath for uint;

    uint private constant NUMBER_OF_ACTORS = 100;
    uint private constant INITIAL_BALANCE = 1e24;
    uint private constant INITIAL_COLL_BALANCE = 1e21;
    uint private MCR;
    uint private CCR;
    uint private LICR;
    uint private MIN_NET_COLL;

    CdpManager private cdpManager;
    BorrowerOperations private borrowerOperations;
    ActivePool private activePool;
    CollSurplusPool private collSurplusPool;
    EBTCTokenTester private eBTCToken;
    SortedCdps private sortedCdps;
    HintHelpers private hintHelpers;
    PriceFeedTestnet private priceFeedTestnet;
    CollateralTokenTester private collateral;
    FeeRecipient private feeRecipient;
    LiquidationLibrary private liqudationLibrary;
    Governor private authority;
    address defaultGovernance;
    EBTCDeployer ebtcDeployer;

    EchidnaProxy[NUMBER_OF_ACTORS] private echidnaProxies;

    uint private numberOfCdps;

    address private constant hevm = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
    uint private constant diff_tolerance = 2000000; //compared to 1e18

    // -- Permissioned Function Signatures for Authority --
    // CDPManager
    bytes4 public constant SET_STAKING_REWARD_SPLIT_SIG =
        bytes4(keccak256(bytes("setStakingRewardSplit(uint256)")));
    bytes4 private constant SET_REDEMPTION_FEE_FLOOR_SIG =
        bytes4(keccak256(bytes("setRedemptionFeeFloor(uint256)")));
    bytes4 private constant SET_MINUTE_DECAY_FACTOR_SIG =
        bytes4(keccak256(bytes("setMinuteDecayFactor(uint256)")));
    bytes4 private constant SET_BASE_SIG = bytes4(keccak256(bytes("setBase(uint256)")));

    // EBTCToken
    bytes4 public constant MINT_SIG = bytes4(keccak256(bytes("mint(address,uint256)")));
    bytes4 public constant BURN_SIG = bytes4(keccak256(bytes("burn(address,uint256)")));

    // PriceFeed
    bytes4 public constant SET_TELLOR_CALLER_SIG =
        bytes4(keccak256(bytes("setTellorCaller(address)")));

    // Flash Lender
    bytes4 internal constant SET_FLASH_FEE_SIG = bytes4(keccak256(bytes("setFlashFee(uint256)")));
    bytes4 internal constant SET_MAX_FLASH_FEE_SIG =
        bytes4(keccak256(bytes("setMaxFlashFee(uint256)")));

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
        MIN_NET_COLL = cdpManager.MIN_NET_COLL();
        require(MCR > 0);
        require(CCR > 0);
        require(LICR > 0);
        require(MIN_NET_COLL > 0);
    }

    /* basic function to call when setting up new echidna test
    Use in pair with connectCoreContracts to wire up infrastructure
    */
    function _setUp() internal {
        defaultGovernance = msg.sender;
        ebtcDeployer = new EBTCDeployer();

        // Default governance is deployer
        // vm.prank(defaultGovernance);
        collateral = new CollateralTokenTester();

        EBTCDeployer.EbtcAddresses memory addr = ebtcDeployer.getFutureEbtcAddresses();

        {
            bytes memory creationCode;
            bytes memory args;

            // Use EBTCDeployer to deploy all contracts at determistic addresses

            // Authority
            creationCode = type(Governor).creationCode;
            args = abi.encode(address(this));

            authority = Governor(
                ebtcDeployer.deploy(ebtcDeployer.AUTHORITY(), abi.encodePacked(creationCode, args))
            );

            // Liquidation Library
            creationCode = type(LiquidationLibrary).creationCode;
            args = abi.encode(
                addr.borrowerOperationsAddress,
                addr.collSurplusPoolAddress,
                addr.ebtcTokenAddress,
                addr.sortedCdpsAddress,
                addr.activePoolAddress,
                addr.priceFeedAddress,
                address(collateral)
            );

            liqudationLibrary = LiquidationLibrary(
                ebtcDeployer.deploy(
                    ebtcDeployer.LIQUIDATION_LIBRARY(),
                    abi.encodePacked(creationCode, args)
                )
            );

            // CDP Manager
            creationCode = type(CdpManager).creationCode;
            args = abi.encode(
                addr.liquidationLibraryAddress,
                addr.authorityAddress,
                addr.borrowerOperationsAddress,
                addr.collSurplusPoolAddress,
                addr.ebtcTokenAddress,
                addr.sortedCdpsAddress,
                addr.activePoolAddress,
                addr.priceFeedAddress,
                address(collateral)
            );

            cdpManager = CdpManager(
                ebtcDeployer.deploy(ebtcDeployer.CDP_MANAGER(), abi.encodePacked(creationCode, args))
            );

            // Borrower Operations
            creationCode = type(BorrowerOperations).creationCode;
            args = abi.encode(
                addr.cdpManagerAddress,
                addr.activePoolAddress,
                addr.collSurplusPoolAddress,
                addr.priceFeedAddress,
                addr.sortedCdpsAddress,
                addr.ebtcTokenAddress,
                addr.feeRecipientAddress,
                address(collateral)
            );

            borrowerOperations = BorrowerOperations(
                ebtcDeployer.deploy(
                    ebtcDeployer.BORROWER_OPERATIONS(),
                    abi.encodePacked(creationCode, args)
                )
            );

            // Price Feed Mock
            creationCode = type(PriceFeedTestnet).creationCode;
            args = abi.encode(addr.authorityAddress);

            priceFeedTestnet = PriceFeedTestnet(
                ebtcDeployer.deploy(ebtcDeployer.PRICE_FEED(), abi.encodePacked(creationCode, args))
            );

            // Sorted CDPS
            creationCode = type(SortedCdps).creationCode;
            args = abi.encode(
                type(uint256).max,
                addr.cdpManagerAddress,
                addr.borrowerOperationsAddress
            );

            sortedCdps = SortedCdps(
                ebtcDeployer.deploy(ebtcDeployer.SORTED_CDPS(), abi.encodePacked(creationCode, args))
            );

            // Active Pool
            creationCode = type(ActivePool).creationCode;
            args = abi.encode(
                addr.borrowerOperationsAddress,
                addr.cdpManagerAddress,
                address(collateral),
                addr.collSurplusPoolAddress,
                addr.feeRecipientAddress
            );

            activePool = ActivePool(
                ebtcDeployer.deploy(ebtcDeployer.ACTIVE_POOL(), abi.encodePacked(creationCode, args))
            );

            // Coll Surplus Pool
            creationCode = type(CollSurplusPool).creationCode;
            args = abi.encode(
                addr.borrowerOperationsAddress,
                addr.cdpManagerAddress,
                addr.activePoolAddress,
                address(collateral)
            );

            collSurplusPool = CollSurplusPool(
                ebtcDeployer.deploy(
                    ebtcDeployer.COLL_SURPLUS_POOL(),
                    abi.encodePacked(creationCode, args)
                )
            );

            // Hint Helpers
            creationCode = type(HintHelpers).creationCode;
            args = abi.encode(
                addr.sortedCdpsAddress,
                addr.cdpManagerAddress,
                address(collateral),
                addr.activePoolAddress,
                addr.priceFeedAddress
            );

            hintHelpers = HintHelpers(
                ebtcDeployer.deploy(
                    ebtcDeployer.HINT_HELPERS(),
                    abi.encodePacked(creationCode, args)
                )
            );

            // eBTC Token
            creationCode = type(EBTCTokenTester).creationCode;
            args = abi.encode(
                addr.cdpManagerAddress,
                addr.borrowerOperationsAddress,
                addr.authorityAddress
            );

            eBTCToken = EBTCTokenTester(
                ebtcDeployer.deploy(ebtcDeployer.EBTC_TOKEN(), abi.encodePacked(creationCode, args))
            );

            // Fee Recipieint
            creationCode = type(FeeRecipient).creationCode;
            args = abi.encode(
                addr.ebtcTokenAddress,
                addr.cdpManagerAddress,
                addr.borrowerOperationsAddress,
                addr.activePoolAddress,
                address(collateral)
            );

            feeRecipient = FeeRecipient(
                ebtcDeployer.deploy(
                    ebtcDeployer.FEE_RECIPIENT(),
                    abi.encodePacked(creationCode, args)
                )
            );

            // Configure authority
            authority.setRoleName(0, "Admin");
            authority.setRoleName(1, "eBTCToken: mint");
            authority.setRoleName(2, "eBTCToken: burn");
            authority.setRoleName(3, "CDPManager: all");
            authority.setRoleName(4, "PriceFeed: setTellorCaller");
            authority.setRoleName(5, "BorrowerOperations: setFlashFee & setMaxFlashFee");

            authority.setRoleCapability(1, address(eBTCToken), MINT_SIG, true);

            authority.setRoleCapability(2, address(eBTCToken), BURN_SIG, true);

            authority.setRoleCapability(3, address(cdpManager), SET_STAKING_REWARD_SPLIT_SIG, true);
            authority.setRoleCapability(3, address(cdpManager), SET_REDEMPTION_FEE_FLOOR_SIG, true);
            authority.setRoleCapability(3, address(cdpManager), SET_MINUTE_DECAY_FACTOR_SIG, true);
            authority.setRoleCapability(3, address(cdpManager), SET_BASE_SIG, true);

            authority.setRoleCapability(4, address(priceFeedTestnet), SET_TELLOR_CALLER_SIG, true);

            authority.setRoleCapability(5, address(borrowerOperations), SET_FLASH_FEE_SIG, true);
            authority.setRoleCapability(5, address(borrowerOperations), SET_MAX_FLASH_FEE_SIG, true);

            authority.setRoleCapability(5, address(activePool), SET_FLASH_FEE_SIG, true);
            authority.setRoleCapability(5, address(activePool), SET_MAX_FLASH_FEE_SIG, true);

            authority.setUserRole(defaultGovernance, 0, true);
            authority.setUserRole(defaultGovernance, 1, true);
            authority.setUserRole(defaultGovernance, 2, true);
            authority.setUserRole(defaultGovernance, 3, true);
            authority.setUserRole(defaultGovernance, 4, true);
            authority.setUserRole(defaultGovernance, 5, true);

            authority.transferOwnership(defaultGovernance);
        }
    }

    /* connectCoreContracts() - wiring up deployed contracts and setting up infrastructure
     */
    function _connectCoreContracts() internal {
        IHevm(hevm).warp(block.timestamp + 86400);
    }

    /* connectLQTYContractsToCore() - connect LQTY contracts to core contracts
     */
    function _connectLQTYContractsToCore() internal {}

    ///////////////////////////////////////////////////////
    // Helper functions
    ///////////////////////////////////////////////////////

    function _ensureMCR(bytes32 _cdpId, CDPChange memory _change) internal view {
        uint price = priceFeedTestnet.getPrice();
        require(price > 0);
        (uint256 entireDebt, uint256 entireColl, ) = cdpManager.getEntireDebtAndColl(_cdpId);
        uint _debt = entireDebt.add(_change.debtAddition).sub(_change.debtReduction);
        uint _coll = entireColl.add(_change.collAddition).sub(_change.collReduction);
        require(_debt.mul(MCR).div(price) < _coll, "!CDP_MCR");
    }

    function _getRandomActor(uint _i) internal pure returns (uint) {
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
        _newPrice = _oldPrice / (_priceDiv + 1);
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
            (uint256 entireDebt, , ) = cdpManager.getEntireDebtAndColl(_cdpId);
            echidnaProxy.liquidatePrx(_cdpId);
            require(!sortedCdps.contains(_cdpId), "!ClosedByLiquidation");
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
            (uint256 entireDebt, , ) = cdpManager.getEntireDebtAndColl(_cdpId);
            require(_partialAmount < entireDebt, "!_partialAmount");
            echidnaProxy.partialLiquidatePrx(_cdpId, _partialAmount);
            (uint256 _newEntireDebt, , ) = cdpManager.getEntireDebtAndColl(_cdpId);
            require(_newEntireDebt < entireDebt, "!reducedByPartialLiquidation");
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

        echidnaProxy.liquidateCdpsPrx(_n);

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
        echidnaProxy.redeemCollateralPrx(
            _EBTCAmount,
            _firstRedemptionHint,
            _upperPartialRedemptionHint,
            _lowerPartialRedemptionHint,
            _partialRedemptionHintNICR,
            0,
            0
        );
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
        (uint256 entireDebt, , ) = cdpManager.getEntireDebtAndColl(_cdpId);
        require(_amount <= entireDebt, "!repayEBTC_amount");
        echidnaProxy.repayEBTCPrx(_cdpId, _amount, _cdpId, _cdpId);
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

        (uint256 entireDebt, uint256 entireColl, ) = cdpManager.getEntireDebtAndColl(_cdpId);
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

    ///////////////////////////////////////////////////////
    // Collateral Token (Test)
    ///////////////////////////////////////////////////////

    function increaseCollateralRate(uint _newBiggerIndex) external {
        require(_newBiggerIndex > collateral.getPooledEthByShares(1e18), "!biggerNewRate");
        require(_newBiggerIndex < collateral.getPooledEthByShares(1e18) * 10000, "!tooBigNewRate");
        require(_newBiggerIndex < 10000e18, "!nonsenseNewBiggerRate");
        collateral.setEthPerShare(_newBiggerIndex);
    }

    // Example for real world slashing: https://twitter.com/LidoFinance/status/1646505631678107649
    // > There are 11 slashing ongoing with the RockLogic GmbH node operator in Lido.
    // > the total projected impact is around 20 ETH,
    // > or about 3% of average daily protocol rewards/0.0004% of TVL.
    function decreaseCollateralRate(uint _newSmallerIndex) external {
        require(_newSmallerIndex < collateral.getPooledEthByShares(1e18), "!smallerNewRate");
        require(
            _newSmallerIndex > collateral.getPooledEthByShares(1e18) / 10000,
            "!tooSmallNewRate"
        );
        require(_newSmallerIndex > 0, "!nonsenseNewSmallerRate");
        collateral.setEthPerShare(_newSmallerIndex);
    }

    // --------------------------
    // Invariants and properties
    // --------------------------

    function echidna_canary_active_pool_balance() public view returns (bool) {
        return invariant_P_47(cdpManager, collateral, activePool);
    }

    function echidna_cdp_properties() public view returns (bool) {
        return invariant_SL_03(cdpManager, priceFeedTestnet, sortedCdps);
    }

    function echidna_accounting_balances() public view returns (bool) {
        return invariant_P_22(collateral, borrowerOperations, eBTCToken, sortedCdps, priceFeedTestnet);
    }

    function echidna_price() public view returns (bool) {
        return invariant_DUMMY_01(priceFeedTestnet);
    }

    function echidna_EBTC_global_balances() public view returns (bool) {
        return invariant_P_36(eBTCToken, cdpManager, sortedCdps);
    }

    function echidna_active_pool_invariant_1() public view returns (bool) {
        return invariant_AP_01(collateral, activePool);
    }

    function echidna_active_pool_invariant_3() public view returns (bool) {
        return invariant_AP_03(eBTCToken, activePool);
    }

    function echidna_active_pool_invariant_4() public view returns (bool) {
        return invariant_AP_04(cdpManager, activePool, diff_tolerance);
    }

    function echidna_active_pool_invariant_5() public view returns (bool) {
        return invariant_AP_05(cdpManager, diff_tolerance);
    }

    function echidna_cdp_manager_invariant_1() public view returns (bool) {
        return invariant_CDPM_01(cdpManager, sortedCdps);
    }

    function echidna_cdp_manager_invariant_2() public view returns (bool) {
        return invariant_CDPM_02(cdpManager);
    }

    function echidna_cdp_manager_invariant_3() public view returns (bool) {
        return invariant_CDPM_03(cdpManager);
    }

    function echidna_coll_surplus_pool_invariant_1() public view returns (bool) {
        return invariant_CSP_01(collateral, collSurplusPool);
    }

    function echidna_sorted_list_invariant_1() public view returns (bool) {
        return invariant_SL_01(cdpManager, sortedCdps);
    }

    function echidna_sorted_list_invariant_2() public view returns (bool) {
        return invariant_SL_02(cdpManager, sortedCdps, priceFeedTestnet, 1e13);
    }
}
