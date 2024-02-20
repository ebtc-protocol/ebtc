pragma solidity 0.8.17;

import "@crytic/properties/contracts/util/PropertiesConstants.sol";
import "@crytic/properties/contracts/util/Hevm.sol";

import "../../Dependencies/SafeMath.sol";
import "../../CdpManager.sol";
import "../AccruableCdpManager.sol";
import "../../LiquidationLibrary.sol";
import "../../BorrowerOperations.sol";
import "../../ActivePool.sol";
import "../../CollSurplusPool.sol";
import "../../SortedCdps.sol";
import "../../HintHelpers.sol";
import "../../FeeRecipient.sol";
import "../../EbtcFeed.sol";
import "../testnet/PriceFeedTestnet.sol";
import "../CollateralTokenTester.sol";
import "../EBTCTokenTester.sol";
import "../../Governor.sol";
import "../../EBTCDeployer.sol";

import "./Properties.sol";
import "./Actor.sol";
import "../BaseStorageVariables.sol";

abstract contract TargetContractSetup is BaseStorageVariables, PropertiesConstants {
    using SafeMath for uint;

    bytes4 internal constant BURN_SIG = bytes4(keccak256(bytes("burn(address,uint256)")));

    uint internal numberOfCdps;

    struct CDPChange {
        uint collAddition;
        uint collReduction;
        uint debtAddition;
        uint debtReduction;
    }

    function _setUp() internal {
        defaultGovernance = address(this);
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
            /// @audit NOTE: This is the TEST contract!!!
            creationCode = type(AccruableCdpManager).creationCode;
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

            priceFeedMock = new PriceFeedTestnet(addr.authorityAddress);

            // Price Feed Mock
            creationCode = type(EbtcFeed).creationCode;
            args = abi.encode(addr.authorityAddress, address(priceFeedMock), address(0));

            ebtcFeed = EbtcFeed(
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
            authority.setRoleName(5, "BorrowerOperations: all");

            authority.setRoleCapability(1, address(eBTCToken), eBTCToken.mint.selector, true);

            authority.setRoleCapability(2, address(eBTCToken), BURN_SIG, true);

            authority.setRoleCapability(
                3,
                address(cdpManager),
                cdpManager.setStakingRewardSplit.selector,
                true
            );
            authority.setRoleCapability(
                3,
                address(cdpManager),
                cdpManager.setRedemptionFeeFloor.selector,
                true
            );
            authority.setRoleCapability(
                3,
                address(cdpManager),
                cdpManager.setMinuteDecayFactor.selector,
                true
            );
            authority.setRoleCapability(3, address(cdpManager), cdpManager.setBeta.selector, true);
            authority.setRoleCapability(
                3,
                address(cdpManager),
                cdpManager.setGracePeriod.selector,
                true
            );
            authority.setRoleCapability(
                3,
                address(cdpManager),
                cdpManager.setRedemptionsPaused.selector,
                true
            );

            authority.setRoleCapability(
                4,
                address(priceFeedMock),
                priceFeedMock.setFallbackCaller.selector,
                true
            );
            authority.setRoleCapability(
                4,
                address(ebtcFeed),
                ebtcFeed.setPrimaryOracle.selector,
                true
            );
            authority.setRoleCapability(
                4,
                address(ebtcFeed),
                ebtcFeed.setSecondaryOracle.selector,
                true
            );

            authority.setRoleCapability(
                5,
                address(borrowerOperations),
                borrowerOperations.setFeeBps.selector,
                true
            );
            authority.setRoleCapability(
                5,
                address(borrowerOperations),
                borrowerOperations.setFlashLoansPaused.selector,
                true
            );

            authority.setRoleCapability(5, address(activePool), activePool.setFeeBps.selector, true);
            authority.setRoleCapability(
                5,
                address(activePool),
                activePool.setFlashLoansPaused.selector,
                true
            );
            authority.setRoleCapability(
                5,
                address(activePool),
                activePool.claimFeeRecipientCollShares.selector,
                true
            );

            authority.setUserRole(defaultGovernance, 0, true);
            authority.setUserRole(defaultGovernance, 1, true);
            authority.setUserRole(defaultGovernance, 2, true);
            authority.setUserRole(defaultGovernance, 3, true);
            authority.setUserRole(defaultGovernance, 4, true);
            authority.setUserRole(defaultGovernance, 5, true);

            crLens = new CRLens(address(cdpManager), address(priceFeedMock));

            liquidationSequencer = new LiquidationSequencer(
                address(cdpManager),
                address(cdpManager.sortedCdps()),
                address(priceFeedMock),
                address(activePool),
                address(collateral)
            );
            syncedLiquidationSequencer = new SyncedLiquidationSequencer(
                address(cdpManager),
                address(cdpManager.sortedCdps()),
                address(priceFeedMock),
                address(activePool),
                address(collateral)
            );
        }
    }

    event Log(string);

    function _setUpFork() internal {
        defaultGovernance = address(0x0);
        ebtcDeployer = EBTCDeployer(0xA93A9CBBD47AA7B57853D460f442E2de2FB1dA4D);
        collateral = CollateralTokenTester(payable(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84)); // stETH
        {
            authority = Governor(0x93d4f82903B87E94796Ec3665efa5f67F2072c6e);
            liqudationLibrary = LiquidationLibrary(0x55262e1128FafD9Bb0B0fD59A8998c13299c4AD4);
            cdpManager = CdpManager(0x3c672ee8e13Cde7617923658138B111e157C8997);
            borrowerOperations = BorrowerOperations(0x99c4ea5d7aDF5d115c85AEEDD98Bd26DdBa714Cb);
            priceFeedMock = PriceFeedTestnet(address(0x4039ca03Ce49021655c9B7C52Ab817d42DB7325e)); // PriceFeed
            sortedCdps = SortedCdps(0x6cb99cF839c5AD3C24431c85da5Fdb7c7ab66d97);
            activePool = ActivePool(0x1e3Bf0965dca89Cd057d63c0cD65A37Acf920590);
            collSurplusPool = CollSurplusPool(0x596EfaF17dFb3fd2CAE7543Ffa399F6e31658E4D);
            hintHelpers = HintHelpers(0xE5A25E39A95750326322175249699eC5Cd66919F);
            eBTCToken = EBTCTokenTester(0xead18fD27CAa1CFf909B5f2BD26ac9a46a6Ab1b5);
            feeRecipient = FeeRecipient(0x522ef088d94BD2125eC47F0967bf5B4E79Af4ed8);

            crLens = new CRLens(address(cdpManager), address(priceFeedMock));

            liquidationSequencer = new LiquidationSequencer(
                address(cdpManager),
                address(cdpManager.sortedCdps()),
                address(priceFeedMock),
                address(activePool),
                address(collateral)
            );
        }
    }

    function _setUpActors() internal {
        bool success;
        address[] memory tokens = new address[](2);
        tokens[0] = address(eBTCToken);
        tokens[1] = address(collateral);
        address[] memory callers = new address[](2);
        callers[0] = address(borrowerOperations);
        callers[1] = address(activePool);
        address[] memory addresses = new address[](3);
        addresses[0] = USER1;
        addresses[1] = USER2;
        addresses[2] = USER3;
        Actor[] memory actorsArray = new Actor[](NUMBER_OF_ACTORS);
        for (uint i = 0; i < NUMBER_OF_ACTORS; i++) {
            actors[addresses[i]] = new Actor(tokens, callers);
            (success, ) = address(actors[addresses[i]]).call{value: INITIAL_ETH_BALANCE}("");
            assert(success);
            (success, ) = actors[addresses[i]].proxy(
                address(collateral),
                "",
                INITIAL_COLL_BALANCE
            );
            assert(success);
            actorsArray[i] = actors[addresses[i]];
        }
        simulator = new Simulator(actorsArray, cdpManager, sortedCdps, borrowerOperations);
    }

    function _syncSystemDebtTwapToSpotValue() internal {
        hevm.warp(block.timestamp + activePool.PERIOD());
        activePool.update();
    }

    function _openWhaleCdpAndTransferEBTC() internal {
        bool success;
        Actor actor = actors[USER3]; // USER3 is the whale CDP holder
        uint256 _col = INITIAL_COLL_BALANCE / 2; // 50% of their initial collateral balance

        uint256 price = priceFeedMock.getPrice();
        uint256 _EBTCAmount = (_col * price) / cdpManager.CCR();

        (success, ) = actor.proxy(
            address(collateral),
            abi.encodeWithSelector(
                CollateralTokenTester.approve.selector,
                address(borrowerOperations),
                _col
            )
        );
        assert(success);
        (success, ) = actor.proxy(
            address(borrowerOperations),
            abi.encodeWithSelector(
                BorrowerOperations.openCdp.selector,
                _EBTCAmount,
                bytes32(0),
                bytes32(0),
                _col
            )
        );
        assert(success);
        address[] memory addresses = new address[](2);
        addresses[0] = USER1;
        addresses[1] = USER2;
        for (uint i = 0; i < addresses.length; i++) {
            (success, ) = actor.proxy(
                address(eBTCToken),
                abi.encodeWithSelector(
                    eBTCToken.transfer.selector,
                    actors[addresses[i]],
                    _EBTCAmount / 3
                )
            );
            assert(success);
        }
    }
}
