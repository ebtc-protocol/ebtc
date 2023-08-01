pragma solidity 0.8.17;

import "../../../Interfaces/ICdpManagerData.sol";
import "../../../Dependencies/SafeMath.sol";
import "../../../CdpManager.sol";
import "../../../LiquidationLibrary.sol";
import "../../../BorrowerOperations.sol";
import "../../../ActivePool.sol";
import "../../../CollSurplusPool.sol";
import "../../../SortedCdps.sol";
import "../../../HintHelpers.sol";
import "../../../FeeRecipient.sol";
import "../../testnet/PriceFeedTestnet.sol";
import "../../CollateralTokenTester.sol";
import "./EchidnaProxy.sol";
import "../../EBTCTokenTester.sol";
import "../../../Governor.sol";
import "../../../EBTCDeployer.sol";

import "../../invariants/IHevm.sol";
import "../../invariants/Properties.sol";

abstract contract EchidnaBaseTester {
    using SafeMath for uint;

    uint internal constant NUMBER_OF_ACTORS = 100;
    uint internal constant INITIAL_BALANCE = 1e24;
    uint internal constant INITIAL_COLL_BALANCE = 1e21;
    uint internal MCR;
    uint internal CCR;
    uint internal LICR;
    uint internal MIN_NET_COLL;

    CdpManager internal cdpManager;
    BorrowerOperations internal borrowerOperations;
    ActivePool internal activePool;
    CollSurplusPool internal collSurplusPool;
    EBTCTokenTester internal eBTCToken;
    SortedCdps internal sortedCdps;
    HintHelpers internal hintHelpers;
    PriceFeedTestnet internal priceFeedTestnet;
    CollateralTokenTester internal collateral;
    FeeRecipient internal feeRecipient;
    LiquidationLibrary internal liqudationLibrary;
    Governor internal authority;
    address defaultGovernance;
    EBTCDeployer ebtcDeployer;

    EchidnaProxy[NUMBER_OF_ACTORS] internal echidnaProxies;

    uint internal numberOfCdps;

    address internal constant hevm = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
    uint internal constant diff_tolerance = 2000000; //compared to 1e18

    // -- Permissioned Function Signatures for Authority --
    // CDPManager
    bytes4 internal constant SET_STAKING_REWARD_SPLIT_SIG =
        bytes4(keccak256(bytes("setStakingRewardSplit(uint256)")));
    bytes4 internal constant SET_REDEMPTION_FEE_FLOOR_SIG =
        bytes4(keccak256(bytes("setRedemptionFeeFloor(uint256)")));
    bytes4 internal constant SET_MINUTE_DECAY_FACTOR_SIG =
        bytes4(keccak256(bytes("setMinuteDecayFactor(uint256)")));
    bytes4 internal constant SET_BASE_SIG = bytes4(keccak256(bytes("setBase(uint256)")));

    // EBTCToken
    bytes4 internal constant MINT_SIG = bytes4(keccak256(bytes("mint(address,uint256)")));
    bytes4 internal constant BURN_SIG = bytes4(keccak256(bytes("burn(address,uint256)")));

    // PriceFeed
    bytes4 internal constant SET_TELLOR_CALLER_SIG =
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
}
