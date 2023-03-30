// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "forge-std/Test.sol";
import "../contracts/Dependencies/SafeMath.sol";
import {WETH9} from "../contracts/TestContracts/WETH9.sol";
import {BorrowerOperations} from "../contracts/BorrowerOperations.sol";
import {PriceFeedTestnet} from "../contracts/TestContracts/PriceFeedTestnet.sol";
import {SortedCdps} from "../contracts/SortedCdps.sol";
import {CdpManager} from "../contracts/CdpManager.sol";
import {ActivePool} from "../contracts/ActivePool.sol";
import {GasPool} from "../contracts/GasPool.sol";
import {DefaultPool} from "../contracts/DefaultPool.sol";
import {HintHelpers} from "../contracts/HintHelpers.sol";
import {LQTYStaking} from "../contracts/LQTY/LQTYStaking.sol";
import {LQTYToken} from "../contracts/LQTY/LQTYToken.sol";
import {LockupContractFactory} from "../contracts/LQTY/LockupContractFactory.sol";
import {CommunityIssuance} from "../contracts/LQTY/CommunityIssuance.sol";
import {EBTCToken} from "../contracts/EBTCToken.sol";
import {CollSurplusPool} from "../contracts/CollSurplusPool.sol";
import {FunctionCaller} from "../contracts/TestContracts/FunctionCaller.sol";
import {CollateralTokenTester} from "../contracts/TestContracts/CollateralTokenTester.sol";
import {Governor} from "../contracts/Governor.sol";
import {Utilities} from "./utils/Utilities.sol";

contract eBTCBaseFixture is Test {
    uint internal constant FEE = 5e15; // 0.5%
    uint256 internal constant MINIMAL_COLLATERAL_RATIO = 110e16; // MCR: 110%
    uint public constant CCR = 150e16; // 150%
    uint256 internal constant COLLATERAL_RATIO = 160e16; // 160%: take higher CR as CCR is 150%
    uint256 internal constant COLLATERAL_RATIO_DEFENSIVE = 200e16; // 200% - defensive CR
    uint internal constant MIN_NET_DEBT = 1e17; // Subject to changes once CL is changed
    // TODO: Modify these constants to increase/decrease amount of users
    uint internal constant AMOUNT_OF_USERS = 100;
    uint internal constant AMOUNT_OF_CDPS = 3;

    // -- Permissioned Function Signatures for Authority --
    // CDPManager
    bytes4 private constant SET_STAKING_REWARD_SPLIT_SIG = bytes4(keccak256(bytes("setStakingRewardSplit(uint256)")));

    // EBTCToken
    bytes4 private constant MINT_SIG = bytes4(keccak256(bytes("mint(address,uint256)")));
    bytes4 private constant BURN_SIG = bytes4(keccak256(bytes("burn(address,uint256)")));

    using SafeMath for uint256;
    using SafeMath for uint96;
    using SafeMath for uint64;
    using SafeMath for uint32;
    using SafeMath for uint16;
    using SafeMath for uint8;
    uint256 constant maxBytes32 = type(uint256).max;
    bytes32 constant HINT = "hint";
    PriceFeedTestnet priceFeedMock;
    SortedCdps sortedCdps;
    CdpManager cdpManager;
    WETH9 weth;
    ActivePool activePool;
    GasPool gasPool;
    DefaultPool defaultPool;
    CollSurplusPool collSurplusPool;
    FunctionCaller functionCaller;
    BorrowerOperations borrowerOperations;
    HintHelpers hintHelpers;
    EBTCToken eBTCToken;
    CollateralTokenTester collateral;
    Governor authority;
    address defaultGovernance;

    Utilities internal _utils;

    // LQTY Stuff
    LQTYToken lqtyToken;
    LQTYStaking lqtyStaking;
    LockupContractFactory lockupContractFactory;
    CommunityIssuance communityIssuance;

    ////////////////////////////////////////////////////////////////////////////
    // Structs
    ////////////////////////////////////////////////////////////////////////////
    struct CdpState {
        uint256 debt;
        uint256 coll;
        uint256 pendingEBTCDebtReward;
        uint256 pendingEBTCInterest;
        uint256 pendingETHReward;
    }

    /* setUp() - basic function to call when setting up new Foundry test suite
    Use in pair with connectCoreContracts to wire up infrastructure

    Consider overriding this function if in need of custom setup
    */
    function setUp() public virtual {
        _utils = new Utilities();
        defaultGovernance = _utils.getNextSpecialAddress();

        authority = new Governor(defaultGovernance);
        
        borrowerOperations = new BorrowerOperations();
        priceFeedMock = new PriceFeedTestnet();
        sortedCdps = new SortedCdps();
        cdpManager = new CdpManager();
        weth = new WETH9();
        activePool = new ActivePool();
        gasPool = new GasPool();
        defaultPool = new DefaultPool();
        collSurplusPool = new CollSurplusPool();
        functionCaller = new FunctionCaller();
        hintHelpers = new HintHelpers();
        eBTCToken = new EBTCToken(address(cdpManager), address(borrowerOperations), address(authority));
        collateral = new CollateralTokenTester();

        // Liquity Stuff
        lqtyStaking = new LQTYStaking();
        lockupContractFactory = new LockupContractFactory();
        communityIssuance = new CommunityIssuance();
        lqtyToken = new LQTYToken(
            address(communityIssuance),
            address(lqtyStaking),
            address(lockupContractFactory),
            // Set misc addresses to self
            address(this),
            address(this),
            address(this)
        );

        // Set up initial permissions and then renounce global owner role
        vm.startPrank(defaultGovernance);
        
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

        vm.stopPrank();
    }

    /* connectCoreContracts() - wiring up deployed contracts and setting up infrastructure
     */
    function connectCoreContracts() public virtual {
        // set CdpManager addr in SortedCdps
        sortedCdps.setParams(maxBytes32, address(cdpManager), address(borrowerOperations));

        // set contracts in the Cdp Manager
        cdpManager.setAddresses(
            address(borrowerOperations),
            address(activePool),
            address(defaultPool),
            address(gasPool),
            address(collSurplusPool),
            address(priceFeedMock),
            address(eBTCToken),
            address(sortedCdps),
            address(lqtyToken),
            address(lqtyStaking),
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
            address(priceFeedMock),
            address(sortedCdps),
            address(eBTCToken),
            address(lqtyStaking),
            address(collateral)
        );

        // set contracts in activePool
        activePool.setAddresses(
            address(borrowerOperations),
            address(cdpManager),
            address(defaultPool),
            address(collateral),
            address(collSurplusPool)
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

    /* connectLQTYContracts() - wire up necessary liquity contracts
     */
    function connectLQTYContracts() public virtual {
        lockupContractFactory.setLQTYTokenAddress(address(lqtyToken));
    }

    /* connectLQTYContractsToCore() - connect LQTY contracts to core contracts
     */
    function connectLQTYContractsToCore() public virtual {
        lqtyStaking.setAddresses(
            address(lqtyToken),
            address(eBTCToken),
            address(cdpManager),
            address(borrowerOperations),
            address(activePool),
            address(collateral)
        );
    }

    ////////////////////////////////////////////////////////////////////////////
    // Helper functions
    ////////////////////////////////////////////////////////////////////////////

    function _getEntireDebtAndColl(bytes32 cdpId) internal view returns (CdpState memory) {
        (
            uint256 debt,
            uint256 coll,
            uint256 pendingEBTCDebtReward,
            uint256 pendingEBTCDebtInterest,
            uint256 pendingETHReward
        ) = cdpManager.getEntireDebtAndColl(cdpId);
        return
            CdpState(debt, coll, pendingEBTCDebtReward, pendingEBTCDebtInterest, pendingETHReward);
    }

    function dealCollateral(address _recipient, uint _amount) public virtual returns (uint) {
        vm.deal(_recipient, _amount);
        uint _balBefore = collateral.balanceOf(_recipient);

        vm.prank(_recipient);
        collateral.deposit{value: _amount}();

        uint _balAfter = collateral.balanceOf(_recipient);
        return _balAfter - _balBefore;
    }
}
