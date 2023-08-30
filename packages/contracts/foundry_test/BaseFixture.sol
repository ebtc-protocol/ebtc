// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {WETH9} from "../contracts/TestContracts/WETH9.sol";
import {BorrowerOperations} from "../contracts/BorrowerOperations.sol";
import {PriceFeedTestnet} from "../contracts/TestContracts/testnet/PriceFeedTestnet.sol";
import {SortedCdps} from "../contracts/SortedCdps.sol";
import {CdpManager} from "../contracts/CdpManager.sol";
import {LiquidationLibrary} from "../contracts/LiquidationLibrary.sol";
import {ActivePool} from "../contracts/ActivePool.sol";
import {HintHelpers} from "../contracts/HintHelpers.sol";
import {FeeRecipient} from "../contracts/FeeRecipient.sol";
import {EBTCToken} from "../contracts/EBTCToken.sol";
import {CollSurplusPool} from "../contracts/CollSurplusPool.sol";
import {FunctionCaller} from "../contracts/TestContracts/FunctionCaller.sol";
import {CollateralTokenTester} from "../contracts/TestContracts/CollateralTokenTester.sol";
import {Governor} from "../contracts/Governor.sol";
import {EBTCDeployer} from "../contracts/EBTCDeployer.sol";
import {Utilities} from "./utils/Utilities.sol";
import {LogUtils} from "./utils/LogUtils.sol";
import {BytecodeReader} from "./utils/BytecodeReader.sol";
import {IERC3156FlashLender} from "../contracts/Interfaces/IERC3156FlashLender.sol";

contract eBTCBaseFixture is Test, BytecodeReader, LogUtils {
    uint internal constant FEE = 5e15; // 0.5%
    uint256 internal constant MINIMAL_COLLATERAL_RATIO = 110e16; // MCR: 110%
    uint public constant CCR = 125e16; // 125%
    uint256 internal constant COLLATERAL_RATIO = 160e16; // 160%: take higher CR as CCR is 150%
    uint256 internal constant COLLATERAL_RATIO_DEFENSIVE = 200e16; // 200% - defensive CR
    uint internal constant MIN_NET_DEBT = 1e17; // Subject to changes once CL is changed
    // TODO: Modify these constants to increase/decrease amount of users
    uint internal constant AMOUNT_OF_USERS = 100;
    uint internal constant AMOUNT_OF_CDPS = 3;
    uint internal DECIMAL_PRECISION = 1e18;
    bytes32 public constant ZERO_ID = bytes32(0);

    uint internal constant MAX_BPS = 10000;

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

    event FlashFeeSet(address _setter, uint _oldFee, uint _newFee);
    event MaxFlashFeeSet(address _setter, uint _oldMaxFee, uint _newMaxFee);

    uint256 constant maxBytes32 = type(uint256).max;
    bytes32 constant HINT = "hint";
    PriceFeedTestnet priceFeedMock;
    SortedCdps sortedCdps;
    CdpManager cdpManager;
    WETH9 weth;
    ActivePool activePool;
    CollSurplusPool collSurplusPool;
    FunctionCaller functionCaller;
    BorrowerOperations borrowerOperations;
    HintHelpers hintHelpers;
    EBTCToken eBTCToken;
    CollateralTokenTester collateral;
    Governor authority;
    LiquidationLibrary liqudationLibrary;
    EBTCDeployer ebtcDeployer;
    address defaultGovernance;

    Utilities internal _utils;

    // LQTY Stuff
    FeeRecipient feeRecipient;

    ////////////////////////////////////////////////////////////////////////////
    // Structs
    ////////////////////////////////////////////////////////////////////////////
    struct CdpState {
        uint256 debt;
        uint256 collShares;
        uint256 pendingEBTCDebtReward;
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

            // Fee Recipieint
            creationCode = type(FeeRecipient).creationCode;
            args = abi.encode(defaultGovernance, addr.authorityAddress);

            feeRecipient = FeeRecipient(
                ebtcDeployer.deploy(
                    ebtcDeployer.FEE_RECIPIENT(),
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

    function _getEntireDebtAndColl(bytes32 cdpId) internal view returns (CdpState memory) {
        (uint256 debt, uint256 coll, uint256 pendingEBTCDebtReward) = cdpManager
            .getEntireDebtAndColl(cdpId);
        return CdpState(debt, coll, pendingEBTCDebtReward);
    }

    function dealCollateral(address _recipient, uint _amount) public virtual returns (uint) {
        vm.deal(_recipient, _amount);
        uint _balBefore = collateral.balanceOf(_recipient);

        vm.prank(_recipient);
        collateral.deposit{value: _amount}();

        uint _balAfter = collateral.balanceOf(_recipient);
        return _balAfter - _balBefore;
    }

    function _dealCollateralAndPrepForUse(address user) internal virtual {
        vm.deal(user, type(uint96).max);
        vm.prank(user);
        collateral.approve(address(borrowerOperations), type(uint256).max);

        vm.prank(user);
        collateral.deposit{value: 10000 ether}();
    }

    function _openTestCDP(address _user, uint _coll, uint _debt) internal returns (bytes32) {
        dealCollateral(_user, _coll);
        vm.startPrank(_user);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        bytes32 _cdpId = borrowerOperations.openCdp(_debt, bytes32(0), bytes32(0), _coll);
        vm.stopPrank();
        return _cdpId;
    }

    /// @dev Increase index on collateral, storing real before, after, and what is stored in the CdpManager global index
    function _increaseCollateralIndex()
        internal
        returns (uint oldIndex, uint newIndex, uint storedIndex)
    {
        oldIndex = collateral.getPooledEthByShares(1e18);
        collateral.setEthPerShare(oldIndex + 1e17);
        newIndex = collateral.getPooledEthByShares(1e18);

        storedIndex = cdpManager.stFPPSg();
    }

    /// @dev Ensure data fields for Cdp are in expected post-close state
    function _assertCdpClosed(bytes32 cdpId, uint expectedStatus) internal {
        (uint _debt, uint _coll, uint _stake, uint _liquidatorRewardShares, , ) = cdpManager.Cdps(
            cdpId
        );
        uint _status = cdpManager.getCdpStatus(cdpId);

        assertTrue(_debt == 0);
        assertTrue(_coll == 0);
        assertTrue(_stake == 0);
        assertTrue(_liquidatorRewardShares == 0);
        assertTrue(_status == expectedStatus);

        assertTrue(cdpManager.rewardSnapshots(cdpId) == 0);
        assertTrue(cdpManager.stFeePerUnitcdp(cdpId) == 0);
    }

    function _printSystemState() internal {
        uint price = priceFeedMock.fetchPrice();
        console.log("== Core State ==");
        console.log("systemCollShares   :", activePool.getSystemCollShares());
        console.log(
            "systemStEthBalance :",
            collateral.getPooledEthByShares(activePool.getSystemCollShares())
        );
        console.log("systemDebt         :", activePool.getSystemDebt());
        console.log("TCR                :", cdpManager.getTCR(price));
        console.log("stEthLiveIndex     :", collateral.getPooledEthByShares(DECIMAL_PRECISION));
        console.log("stEthGlobalIndex   :", cdpManager.stFPPSg());
        console.log("price              :", price);
    }

    function _getICR(bytes32 cdpId) internal returns (uint) {
        uint price = priceFeedMock.fetchPrice();
        return cdpManager.getCurrentICR(cdpId, price);
    }

    function _printAllCdps() internal {
        uint price = priceFeedMock.fetchPrice();
        uint numCdps = sortedCdps.getSize();
        bytes32 node = sortedCdps.getLast();
        address borrower = sortedCdps.getOwnerAddress(node);

        while (borrower != address(0)) {
            console.log("=== ", bytes32ToString(node));
            console.log("debt       (realized) :", cdpManager.getCdpDebt(node));
            console.log("collShares (realized) :", cdpManager.getCdpCollShares(node));
            console.log("ICR                   :", cdpManager.getCurrentICR(node, price));
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
        cdpManager.syncGracePeriod();
        vm.warp(block.timestamp + cdpManager.recoveryModeGracePeriod() + 1);
    }
}
