// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;
pragma experimental ABIEncoderV2;

import "forge-std/Test.sol";
import {WETH9} from "../contracts/TestContracts/WETH9.sol";
import {BorrowerOperations} from "../contracts/BorrowerOperations.sol";
import {PriceFeedTestnet} from "../contracts/TestContracts/PriceFeedTestnet.sol";
import {SortedCdps} from "../contracts/SortedCdps.sol";
import {CdpManager} from "../contracts/CdpManager.sol";
import {LiquidationLibrary} from "../contracts/LiquidationLibrary.sol";
import {ActivePool} from "../contracts/ActivePool.sol";
import {DefaultPool} from "../contracts/DefaultPool.sol";
import {HintHelpers} from "../contracts/HintHelpers.sol";
import {FeeRecipient} from "../contracts/LQTY/FeeRecipient.sol";
import {EBTCToken} from "../contracts/EBTCToken.sol";
import {CollSurplusPool} from "../contracts/CollSurplusPool.sol";
import {FunctionCaller} from "../contracts/TestContracts/FunctionCaller.sol";
import {CollateralTokenTester} from "../contracts/TestContracts/CollateralTokenTester.sol";
import {Governor} from "../contracts/Governor.sol";
import {EBTCDeployer} from "../contracts/EBTCDeployer.sol";
import {Utilities} from "./utils/Utilities.sol";
import {BytecodeReader} from "./utils/BytecodeReader.sol";

contract eBTCBaseFixture is Test, BytecodeReader {
    uint internal constant FEE = 5e15; // 0.5%
    uint256 internal constant MINIMAL_COLLATERAL_RATIO = 110e16; // MCR: 110%
    uint public constant CCR = 125e16; // 125%
    uint256 internal constant COLLATERAL_RATIO = 160e16; // 160%: take higher CR as CCR is 150%
    uint256 internal constant COLLATERAL_RATIO_DEFENSIVE = 200e16; // 200% - defensive CR
    uint internal constant MIN_NET_DEBT = 1e17; // Subject to changes once CL is changed
    // TODO: Modify these constants to increase/decrease amount of users
    uint internal constant AMOUNT_OF_USERS = 100;
    uint internal constant AMOUNT_OF_CDPS = 3;

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

    uint256 constant maxBytes32 = type(uint256).max;
    bytes32 constant HINT = "hint";
    PriceFeedTestnet priceFeedMock;
    SortedCdps sortedCdps;
    CdpManager cdpManager;
    WETH9 weth;
    ActivePool activePool;
    DefaultPool defaultPool;
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
        uint256 coll;
        uint256 pendingEBTCDebtReward;
        uint256 pendingETHReward;
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
            7: defaultPool
            8: collSurplusPool
            9: hintHelpers
            10: eBTCToken
            11: feeRecipient
            12: multiCdpGetter
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
                addr.feeRecipientAddress,
                addr.sortedCdpsAddress,
                addr.activePoolAddress,
                addr.defaultPoolAddress,
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
                addr.feeRecipientAddress,
                addr.sortedCdpsAddress,
                addr.activePoolAddress,
                addr.defaultPoolAddress,
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
                addr.defaultPoolAddress,
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
                addr.defaultPoolAddress,
                address(collateral),
                addr.collSurplusPoolAddress,
                addr.feeRecipientAddress
            );

            activePool = ActivePool(
                ebtcDeployer.deploy(ebtcDeployer.ACTIVE_POOL(), abi.encodePacked(creationCode, args))
            );

            // Default Pool
            creationCode = type(DefaultPool).creationCode;
            args = abi.encode(addr.cdpManagerAddress, addr.activePoolAddress, address(collateral));

            defaultPool = DefaultPool(
                ebtcDeployer.deploy(
                    ebtcDeployer.DEFAULT_POOL(),
                    abi.encodePacked(creationCode, args)
                )
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
                addr.defaultPoolAddress,
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
        }

        // Set up initial permissions and then renounce global owner role
        vm.startPrank(defaultGovernance);
        authority.setRoleName(0, "Admin");
        authority.setRoleName(1, "eBTCToken: mint");
        authority.setRoleName(2, "eBTCToken: burn");
        authority.setRoleName(3, "CDPManager: all");
        authority.setRoleName(3, "PriceFeed: setTellorCaller");

        authority.setRoleCapability(1, address(eBTCToken), MINT_SIG, true);

        authority.setRoleCapability(2, address(eBTCToken), BURN_SIG, true);

        authority.setRoleCapability(3, address(cdpManager), SET_STAKING_REWARD_SPLIT_SIG, true);
        authority.setRoleCapability(3, address(cdpManager), SET_REDEMPTION_FEE_FLOOR_SIG, true);
        authority.setRoleCapability(3, address(cdpManager), SET_MINUTE_DECAY_FACTOR_SIG, true);
        authority.setRoleCapability(3, address(cdpManager), SET_BASE_SIG, true);

        authority.setRoleCapability(4, address(priceFeedMock), SET_TELLOR_CALLER_SIG, true);

        authority.setUserRole(defaultGovernance, 0, true);
        authority.setUserRole(defaultGovernance, 1, true);
        authority.setUserRole(defaultGovernance, 2, true);
        authority.setUserRole(defaultGovernance, 3, true);
        authority.setUserRole(defaultGovernance, 4, true);

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
        (
            uint256 debt,
            uint256 coll,
            uint256 pendingEBTCDebtReward,
            uint256 pendingETHReward
        ) = cdpManager.getEntireDebtAndColl(cdpId);
        return CdpState(debt, coll, pendingEBTCDebtReward, pendingETHReward);
    }

    function dealCollateral(address _recipient, uint _amount) public virtual returns (uint) {
        vm.deal(_recipient, _amount);
        uint _balBefore = collateral.balanceOf(_recipient);

        vm.prank(_recipient);
        collateral.deposit{value: _amount}();

        uint _balAfter = collateral.balanceOf(_recipient);
        return _balAfter - _balBefore;
    }

    function _openTestCDP(address _user, uint _coll, uint _debt) internal returns (bytes32) {
        dealCollateral(_user, _coll);
        vm.startPrank(_user);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        bytes32 _cdpId = borrowerOperations.openCdp(_debt, bytes32(0), bytes32(0), _coll);
        vm.stopPrank();
        return _cdpId;
    }
}
