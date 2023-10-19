// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {WETH9} from "../contracts/TestContracts/WETH9.sol";
import {BorrowerOperations} from "../contracts/BorrowerOperations.sol";
import {PriceFeedTestnet} from "../contracts/TestContracts/testnet/PriceFeedTestnet.sol";
import {SortedCdps} from "../contracts/SortedCdps.sol";
import {AccruableCdpManager} from "../contracts/TestContracts/AccruableCdpManager.sol";
import {CdpManager} from "../contracts/CdpManager.sol";
import {LiquidationLibrary} from "../contracts/LiquidationLibrary.sol";
import {LiquidationSequencer} from "../contracts/LiquidationSequencer.sol";
import {ActivePool} from "../contracts/ActivePool.sol";
import {HintHelpers} from "../contracts/HintHelpers.sol";
import {FeeRecipient} from "../contracts/FeeRecipient.sol";
import {EBTCToken} from "../contracts/EBTCToken.sol";
import {CollSurplusPool} from "../contracts/CollSurplusPool.sol";
import {MultiCdpGetter} from "../contracts/MultiCdpGetter.sol";
import {FunctionCaller} from "../contracts/TestContracts/FunctionCaller.sol";
import {CollateralTokenTester} from "../contracts/TestContracts/CollateralTokenTester.sol";
import {Governor} from "../contracts/Governor.sol";
import {EBTCDeployer} from "../contracts/EBTCDeployer.sol";
import {Utilities} from "./utils/Utilities.sol";
import {LogUtils} from "./utils/LogUtils.sol";
import {BytecodeReader} from "./utils/BytecodeReader.sol";
import {IERC3156FlashLender} from "../contracts/Interfaces/IERC3156FlashLender.sol";
import {BaseStorageVariables} from "../contracts/TestContracts/BaseStorageVariables.sol";
import {Actor} from "../contracts/TestContracts/invariants/Actor.sol";
import {CRLens} from "../contracts/CRLens.sol";
import {BeforeAfter} from "../contracts/TestContracts/invariants/BeforeAfter.sol";
import {FoundryAsserts} from "./utils/FoundryAsserts.sol";

contract eBTCBaseFixture is
    Test,
    BaseStorageVariables,
    BeforeAfter,
    FoundryAsserts,
    BytecodeReader,
    LogUtils
{
    uint256 internal constant FEE = 5e15; // 0.5%
    uint256 internal constant MINIMAL_COLLATERAL_RATIO = 110e16; // MCR: 110%
    uint256 public constant CCR = 125e16; // 125%
    uint256 internal constant COLLATERAL_RATIO = 160e16; // 160%: take higher CR as CCR is 150%
    uint256 internal constant COLLATERAL_RATIO_DEFENSIVE = 200e16; // 200% - defensive CR
    uint256 internal constant MIN_NET_DEBT = 1e17; // Subject to changes once CL is changed
    // TODO: Modify these constants to increase/decrease amount of users
    uint256 internal constant AMOUNT_OF_USERS = 100;
    uint256 internal constant AMOUNT_OF_CDPS = 3;
    uint256 internal DECIMAL_PRECISION = 1e18;
    bytes32 public constant ZERO_ID = bytes32(0);

    uint256 internal constant MAX_BPS = 10000;
    uint256 private ICR_COMPARE_TOLERANCE = 1000000; //in the scale of 1e18

    enum CapabilityFlag {
        None,
        Public,
        Burned
    }

    // -- Permissioned Function Signatures for Authority --
    // CDPManager
    bytes4 public constant SET_STAKING_REWARD_SPLIT_SIG =
        bytes4(keccak256(bytes("setStakingRewardSplit(uint256)")));
    bytes4 private constant SET_REDEMPTION_FEE_FLOOR_SIG =
        bytes4(keccak256(bytes("setRedemptionFeeFloor(uint256)")));
    bytes4 private constant SET_MINUTE_DECAY_FACTOR_SIG =
        bytes4(keccak256(bytes("setMinuteDecayFactor(uint256)")));
    bytes4 private constant SET_BETA_SIG = bytes4(keccak256(bytes("setBeta(uint256)")));
    bytes4 private constant SET_REDEMPETIONS_PAUSED_SIG =
        bytes4(keccak256(bytes("setRedemptionsPaused(bool)")));
    bytes4 private constant SET_GRACE_PERIOD_SIG =
        bytes4(keccak256(bytes("setGracePeriod(uint128)")));

    // EBTCToken
    bytes4 public constant MINT_SIG = bytes4(keccak256(bytes("mint(address,uint256)")));
    bytes4 public constant BURN_SIG = bytes4(keccak256(bytes("burn(address,uint256)")));
    bytes4 public constant BURN2_SIG = bytes4(keccak256(bytes("burn(uint256)")));

    // PriceFeed
    bytes4 public constant SET_FALLBACK_CALLER_SIG =
        bytes4(keccak256(bytes("setFallbackCaller(address)")));

    // Flash Lender
    bytes4 internal constant SET_FEE_BPS_SIG = bytes4(keccak256(bytes("setFeeBps(uint256)")));
    bytes4 internal constant SET_FLASH_LOANS_PAUSED_SIG =
        bytes4(keccak256(bytes("setFlashLoansPaused(bool)")));
    bytes4 internal constant SET_MAX_FEE_BPS_SIG = bytes4(keccak256(bytes("setMaxFeeBps(uint256)")));

    // ActivePool
    bytes4 private constant SWEEP_TOKEN_SIG =
        bytes4(keccak256(bytes("sweepToken(address,uint256)")));
    bytes4 private constant CLAIM_FEE_RECIPIENT_COLL_SIG =
        bytes4(keccak256(bytes("claimFeeRecipientCollShares(uint256)")));

    // Fee Recipient
    bytes4 internal constant SET_FEE_RECIPIENT_ADDRESS_SIG =
        bytes4(keccak256(bytes("setFeeRecipientAddress(address)")));

    event FlashFeeSet(address indexed _setter, uint256 _oldFee, uint256 _newFee);
    event MaxFlashFeeSet(address indexed _setter, uint256 _oldMaxFee, uint256 _newMaxFee);

    uint256 constant maxBytes32 = type(uint256).max;
    bytes32 constant HINT = "hint";

    MultiCdpGetter internal cdpGetter;
    Utilities internal _utils;

    address[] internal emptyAddresses;

    ////////////////////////////////////////////////////////////////////////////
    // Structs
    ////////////////////////////////////////////////////////////////////////////
    struct CdpState {
        uint256 debt;
        uint256 coll;
    }

    /* setUp() - basic function to call when setting up new Foundry test suite
    Use in pair with connectCoreContracts to wire up infrastructure

    Consider overriding this function if in need of custom setup
    */
    function setUp() public virtual {
        _utils = new Utilities();

        defaultGovernance = _utils.getNextSpecialAddress();

        vm.prank(defaultGovernance);
        ebtcDeployer = new EBTCDeployer();

        // Default governance is deployer
        // vm.prank(defaultGovernance);

        collateral = new CollateralTokenTester();
        weth = new WETH9();
        functionCaller = new FunctionCaller();

        /** @dev The order is as follows:
            0: authority
            1: liquidationLibrary
            2: cdpManager
            3: borrowerOperations
            4: priceFeed
            5; sortedCdps
            6: activePool
            7: collSurplusPool
            8: hintHelpers
            9: eBTCToken
            10: feeRecipient
            11: multiCdpGetter
        */

        EBTCDeployer.EbtcAddresses memory addr = ebtcDeployer.getFutureEbtcAddresses();

        {
            bytes memory creationCode;
            bytes memory args;

            // Use EBTCDeployer to deploy all contracts at determistic addresses

            // Authority
            creationCode = type(Governor).creationCode;
            args = abi.encode(defaultGovernance);

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
            /// @audit NOTE: This is the DEV VERSION!!!!!
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

            // Price Feed Mock
            creationCode = type(PriceFeedTestnet).creationCode;
            args = abi.encode(addr.authorityAddress);

            priceFeedMock = PriceFeedTestnet(
                ebtcDeployer.deploy(ebtcDeployer.PRICE_FEED(), abi.encodePacked(creationCode, args))
            );

            // Sorted CDPS
            creationCode = type(SortedCdps).creationCode;
            args = abi.encode(maxBytes32, addr.cdpManagerAddress, addr.borrowerOperationsAddress);

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
            creationCode = type(EBTCToken).creationCode;
            args = abi.encode(
                addr.cdpManagerAddress,
                addr.borrowerOperationsAddress,
                addr.authorityAddress
            );

            eBTCToken = EBTCToken(
                ebtcDeployer.deploy(ebtcDeployer.EBTC_TOKEN(), abi.encodePacked(creationCode, args))
            );

            // Fee Recipient
            creationCode = type(FeeRecipient).creationCode;
            args = abi.encode(defaultGovernance, addr.authorityAddress);

            feeRecipient = FeeRecipient(
                ebtcDeployer.deploy(
                    ebtcDeployer.FEE_RECIPIENT(),
                    abi.encodePacked(creationCode, args)
                )
            );

            // Multi Cdp Getter
            creationCode = type(MultiCdpGetter).creationCode;
            args = abi.encode(addr.cdpManagerAddress, addr.sortedCdpsAddress);

            cdpGetter = MultiCdpGetter(
                ebtcDeployer.deploy(
                    ebtcDeployer.MULTI_CDP_GETTER(),
                    abi.encodePacked(creationCode, args)
                )
            );
        }

        // Set up initial permissions and then renounce global owner role
        vm.startPrank(defaultGovernance);
        authority.setRoleName(0, "Admin");
        authority.setRoleName(1, "eBTCToken: mint");
        authority.setRoleName(2, "eBTCToken: burn");
        authority.setRoleName(3, "CDPManager: all");
        authority.setRoleName(4, "PriceFeed: setFallbackCaller");
        authority.setRoleName(
            5,
            "BorrowerOperations+ActivePool: setFeeBps, setFlashLoansPaused, setFeeRecipientAddress"
        );
        authority.setRoleName(6, "ActivePool: sweep tokens & claim fee recipient coll");

        // TODO: Admin should be granted all permissions on the authority contract to manage it if / when owner is renounced.

        authority.setRoleCapability(1, address(eBTCToken), MINT_SIG, true);
        authority.setRoleCapability(2, address(eBTCToken), BURN_SIG, true);
        authority.setRoleCapability(2, address(eBTCToken), BURN2_SIG, true);

        authority.setRoleCapability(3, address(cdpManager), SET_STAKING_REWARD_SPLIT_SIG, true);
        authority.setRoleCapability(3, address(cdpManager), SET_REDEMPTION_FEE_FLOOR_SIG, true);
        authority.setRoleCapability(3, address(cdpManager), SET_MINUTE_DECAY_FACTOR_SIG, true);
        authority.setRoleCapability(3, address(cdpManager), SET_BETA_SIG, true);
        authority.setRoleCapability(3, address(cdpManager), SET_REDEMPETIONS_PAUSED_SIG, true);
        authority.setRoleCapability(3, address(cdpManager), SET_GRACE_PERIOD_SIG, true);

        authority.setRoleCapability(4, address(priceFeedMock), SET_FALLBACK_CALLER_SIG, true);

        authority.setRoleCapability(5, address(borrowerOperations), SET_FEE_BPS_SIG, true);
        authority.setRoleCapability(
            5,
            address(borrowerOperations),
            SET_FLASH_LOANS_PAUSED_SIG,
            true
        );
        authority.setRoleCapability(
            5,
            address(borrowerOperations),
            SET_FEE_RECIPIENT_ADDRESS_SIG,
            true
        );

        authority.setRoleCapability(5, address(activePool), SET_FEE_BPS_SIG, true);
        authority.setRoleCapability(5, address(activePool), SET_FLASH_LOANS_PAUSED_SIG, true);
        authority.setRoleCapability(5, address(activePool), SET_FEE_RECIPIENT_ADDRESS_SIG, true);

        authority.setRoleCapability(6, address(activePool), SWEEP_TOKEN_SIG, true);
        authority.setRoleCapability(6, address(activePool), CLAIM_FEE_RECIPIENT_COLL_SIG, true);

        authority.setUserRole(defaultGovernance, 0, true);
        authority.setUserRole(defaultGovernance, 1, true);
        authority.setUserRole(defaultGovernance, 2, true);
        authority.setUserRole(defaultGovernance, 3, true);
        authority.setUserRole(defaultGovernance, 4, true);
        authority.setUserRole(defaultGovernance, 5, true);
        authority.setUserRole(defaultGovernance, 6, true);

        crLens = new CRLens(address(cdpManager), address(priceFeedMock));
        liquidationSequencer = new LiquidationSequencer(
            address(cdpManager),
            address(sortedCdps),
            address(priceFeedMock),
            address(activePool),
            address(collateral)
        );

        vm.stopPrank();
    }

    /* connectCoreContracts() - wiring up deployed contracts and setting up infrastructure
     */
    function connectCoreContracts() public virtual {
        skip(86400);
    }

    /* connectLQTYContractsToCore() - connect LQTY contracts to core contracts
     */
    function connectLQTYContractsToCore() public virtual {}

    /////////////////////////////////////////////////////////////////
    // Helper functions
    ////////////////////////////////////////////////////////////////////////////

    function _getSyncedDebtAndCollShares(bytes32 cdpId) internal view returns (CdpState memory) {
        (uint256 debt, uint256 coll) = cdpManager.getSyncedDebtAndCollShares(cdpId);
        return CdpState(debt, coll);
    }

    function dealCollateral(address _recipient, uint256 _amount) public virtual returns (uint256) {
        vm.deal(_recipient, _amount);
        uint256 _balBefore = collateral.balanceOf(_recipient);

        vm.prank(_recipient);
        collateral.deposit{value: _amount}();

        uint256 _balAfter = collateral.balanceOf(_recipient);
        return _balAfter - _balBefore;
    }

    function _dealCollateralAndPrepForUse(address user) internal virtual {
        vm.deal(user, type(uint96).max);
        vm.prank(user);
        collateral.approve(address(borrowerOperations), type(uint256).max);

        vm.prank(user);
        collateral.deposit{value: 10000 ether}();
    }

    function _openTestCDP(address _user, uint256 _coll, uint256 _debt) internal returns (bytes32) {
        dealCollateral(_user, _coll);
        vm.startPrank(_user);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        bytes32 _cdpId = borrowerOperations.openCdp(_debt, bytes32(0), bytes32(0), _coll);
        vm.stopPrank();
        return _cdpId;
    }

    /// @dev Automatically adds liquidator gas stipend to the Cdp in addition to specified coll
    function _openTestCdpAtICR(
        address _usr,
        uint256 _coll,
        uint256 _icr
    ) internal returns (address, bytes32) {
        uint256 _price = priceFeedMock.fetchPrice();
        uint256 _debt = (_coll * _price) / _icr;
        bytes32 _cdpId = _openTestCDP(_usr, _coll + cdpManager.LIQUIDATOR_REWARD(), _debt);
        uint256 _cdpICR = cdpManager.getCachedICR(_cdpId, _price);
        _utils.assertApproximateEq(_icr, _cdpICR, ICR_COMPARE_TOLERANCE); // in the scale of 1e18
        return (_usr, _cdpId);
    }

    /// @dev Increase index on collateral, storing real before, after, and what is stored in the CdpManager global index
    function _increaseCollateralIndex()
        internal
        returns (uint256 oldIndex, uint256 newIndex, uint256 storedIndex)
    {
        oldIndex = collateral.getPooledEthByShares(1e18);
        collateral.setEthPerShare(oldIndex + 1e17);
        newIndex = collateral.getPooledEthByShares(1e18);

        storedIndex = cdpManager.stEthIndex();
    }

    /// @dev Ensure data fields for Cdp are in expected post-close state
    function _assertCdpClosed(bytes32 cdpId, uint256 expectedStatus) internal {
        (
            uint256 _debt,
            uint256 _coll,
            uint256 _stake,
            uint256 _liquidatorRewardShares,
            ,

        ) = cdpManager.Cdps(cdpId);
        uint256 _status = cdpManager.getCdpStatus(cdpId);

        assertTrue(_debt == 0);
        assertTrue(_coll == 0);
        assertTrue(_stake == 0);
        assertTrue(_liquidatorRewardShares == 0);
        assertTrue(_status == expectedStatus);

        assertTrue(cdpManager.cdpDebtRedistributionIndex(cdpId) == 0);
        assertTrue(cdpManager.cdpStEthFeePerUnitIndex(cdpId) == 0);
    }

    function _printSystemState() internal {
        uint256 price = priceFeedMock.fetchPrice();
        console.log("== Core State ==");
        console.log("systemCollShares   :", activePool.getSystemCollShares());
        console.log(
            "systemStEthBalance :",
            collateral.getPooledEthByShares(activePool.getSystemCollShares())
        );
        console.log("systemDebt         :", activePool.getSystemDebt());
        console.log("TCR                :", cdpManager.getCachedTCR(price));
        console.log("stEthLiveIndex     :", collateral.getPooledEthByShares(DECIMAL_PRECISION));
        console.log("stEthGlobalIndex   :", cdpManager.stEthIndex());
        console.log("price              :", price);
        console.log("");
    }

    function _getCachedICR(bytes32 cdpId) internal returns (uint256) {
        uint256 price = priceFeedMock.fetchPrice();
        return cdpManager.getCachedICR(cdpId, price);
    }

    function _printAllCdps() internal {
        uint256 price = priceFeedMock.fetchPrice();
        uint256 numCdps = sortedCdps.getSize();
        bytes32 node = sortedCdps.getLast();
        address borrower = sortedCdps.getOwnerAddress(node);

        while (borrower != address(0)) {
            console.log("=== ", bytes32ToString(node));
            console.log("debt       (realized) :", cdpManager.getCdpDebt(node));
            console.log("collShares (realized) :", cdpManager.getCdpCollShares(node));
            console.log("ICR                   :", cdpManager.getCachedICR(node, price));
            console.log(
                "Percent of System     :",
                (cdpManager.getCdpCollShares(node) * DECIMAL_PRECISION) /
                    activePool.getSystemCollShares()
            );
            console.log("");

            node = sortedCdps.getPrev(node);
            borrower = sortedCdps.getOwnerAddress(node);
        }
    }

    function _printSortedCdpsList() internal {
        bytes32 _currentCdpId = sortedCdps.getLast();
        uint counter = 0;

        while (_currentCdpId != sortedCdps.dummyId()) {
            uint NICR = cdpManager.getCachedNominalICR(_currentCdpId);
            console.log(counter, bytes32ToString(_currentCdpId));
            console.log(NICR);
            _currentCdpId = sortedCdps.getPrev(_currentCdpId);
            counter += 1;
        }
        console.log("");
    }

    /// @dev Ensure a given CdpId is not in the Sorted Cdps LL.
    /// @dev a Cdp should only be present in the LL when it is active.
    function _assertCdpNotInSortedCdps(bytes32 cdpId) internal {
        // use stated O(1) method to see if node with given Id is presnt
        assertTrue(sortedCdps.contains(cdpId) == false);

        // validate by walking list
        bytes32 _currentCdpId = sortedCdps.getLast();

        while (_currentCdpId != sortedCdps.nonExistId()) {
            assertTrue(_currentCdpId != cdpId);
            _currentCdpId = sortedCdps.getPrev(_currentCdpId);
        }
    }

    // Grace Period, check never reverts so it's safe to use
    function _waitUntilRMColldown() internal {
        cdpManager.syncGlobalAccountingAndGracePeriod();
        vm.warp(block.timestamp + cdpManager.recoveryModeGracePeriodDuration() + 1);
    }

    function _getCdpStEthBalance(bytes32 _cdpId) public view returns (uint) {
        uint collShares = cdpManager.getCdpCollShares(_cdpId);
        return collateral.getPooledEthByShares(collShares);
    }

    function _liquidateCdps(uint256 _n) internal {
        bytes32[] memory batch = _sequenceLiqToBatchLiqWithPrice(_n);
        console.log(batch.length);
        _printCdpArray(batch);

        if (batch.length > 0) {
            cdpManager.batchLiquidateCdps(batch);
        }
    }

    function _sequenceLiqToBatchLiqWithPrice(uint256 _n) internal returns (bytes32[] memory) {
        uint256 price = priceFeedMock.fetchPrice();
        bytes32[] memory batch = liquidationSequencer.sequenceLiqToBatchLiqWithPrice(_n, price);
        return batch;
    }

    function _printCdpArray(bytes32[] memory _cdpArray) internal {
        if (_cdpArray.length == 0) {
            console.log("-empty array-");
            return;
        }

        for (uint256 i = 0; i < _cdpArray.length; i++) {
            console.log(bytes32ToString(_cdpArray[i]));
        }
    }
}
