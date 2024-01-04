pragma solidity 0.8.17;

import "@crytic/properties/contracts/util/PropertiesConstants.sol";
import "@crytic/properties/contracts/util/Hevm.sol";

import "../../Interfaces/ICdpManagerData.sol";
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
        defaultGovernance = address(0xA967Ba66Fb284EC18bbe59f65bcf42dD11BA8128);
        ebtcDeployer = EBTCDeployer(0xe90f99c08F286c48db4D1AfdAE6C122de69B7219);
        collateral = CollateralTokenTester(payable(0xf8017430A0efE03577f6aF88069a21900448A373));
        {
            authority = Governor(0x4945Fc25282b1bC103d2C62C251Cd022138c1de9);
            liqudationLibrary = LiquidationLibrary(0xE8943a17363DE9A6e0d4A5d48d5Ab45283199F77);
            cdpManager = CdpManager(0x0c5C2B93b96C9B3aD7fb9915952BD7BA256C4f04);
            borrowerOperations = BorrowerOperations(0xA178BFBc42E3D886d540CDDcf4562c53a8Fc02c1);
            priceFeedMock = PriceFeedTestnet(0x5C819E5D61EFCfBd7e4635f1112f3bF94663999b);
            sortedCdps = SortedCdps(0xDeFF25eC3cd3041BC8B9A464F9BEc12EB8247Be6);
            activePool = ActivePool(0x55abdfb760dd032627D531f7cF3DAa72549CEbA2);
            collSurplusPool = CollSurplusPool(0x7b4D951D7b8090f62bD009b371abd7Fe04aB7e1A);
            hintHelpers = HintHelpers(0xCaBdBc4218dd4b9E3fB9842232aD0aFc7c431693);
            eBTCToken = EBTCTokenTester(0x9Aa69Db8c53E504EF22615390EE9Eb72cb8bE498);
            feeRecipient = FeeRecipient(0x40FF68eaE525233950B63C2BCEa39770efDE52A4);

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
                abi.encodeWithSelector(CollateralTokenTester.deposit.selector, ""),
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
