pragma solidity 0.8.17;
import {console2 as console} from "forge-std/console2.sol";

import {eBTCBaseFixture} from "./BaseFixture.sol";
import {ActivePoolTester} from "../contracts/TestContracts/ActivePoolTester.sol";

contract ActivePoolTwapAccTest is eBTCBaseFixture {
    event TwapDisabled();

    ActivePoolTester internal apTester;

    function setUp() public override {
        eBTCBaseFixture.setUp();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();

        apTester = new ActivePoolTester(
            address(borrowerOperations),
            address(cdpManager),
            address(collateral),
            address(collSurplusPool)
        );
    }

    function testBasicTwap() public {
        uint256 entropy = 67842918170911949682054359726922204181906323355453850;
        vm.warp((apTester.getData()).lastAccrued + apTester.PERIOD());
        apTester.unprotectedSetTwapTrackVal(100);

        while (entropy > 0) {
            uint256 randomSeed = entropy % 10;
            entropy /= 10; // Cut the value

            if (apTester.valueToTrack() == 0) {
                apTester.unprotectedSetTwapTrackVal(randomSeed);
                continue;
            }

            uint256 _val;
            if (randomSeed > 5) {
                _val = apTester.valueToTrack() * (randomSeed - 5);
            } else {
                _val = (apTester.valueToTrack() * (5 - randomSeed)) / 10;
            }
            apTester.unprotectedSetTwapTrackVal(_val);
            assertEq(_val, apTester.valueToTrack());

            uint256 _accBefore = apTester.getLatestAccumulator();
            vm.warp((apTester.getData()).lastAccrued + apTester.PERIOD());
            uint256 _duration = block.timestamp - (apTester.getData()).lastAccrued;
            uint256 _accAfter = apTester.getLatestAccumulator();
            assertEq(_duration * _val, _accAfter - _accBefore);
        }
    }

    function testIsOverflowAValidConcern() public {
        // 10 Billion USD
        // many years
        uint256 MANY_YEARS = 800 * 365.25 days;
        uint256 TEN_BILLION_USD = 10e27; // 10 billion in 18 decimals

        apTester.unprotectedSetTwapTrackVal(TEN_BILLION_USD);
        assertEq(TEN_BILLION_USD, apTester.valueToTrack());

        uint256 _accBefore = apTester.getLatestAccumulator();
        vm.warp(MANY_YEARS);
        uint256 _duration = block.timestamp - (apTester.getData()).lastAccrued;
        uint256 _accAfter = apTester.getLatestAccumulator();
        assertEq(TEN_BILLION_USD * _duration, _accAfter - _accBefore);
    }

    function testIsManipulationAValidConcern() public {
        uint256 NORMAL_VALUE = 1000e18;
        apTester.unprotectedSetTwapTrackVal(NORMAL_VALUE);
        assertEq(NORMAL_VALUE, apTester.valueToTrack());

        // update the accumulator normally after period
        vm.warp((apTester.getData()).lastObserved + apTester.PERIOD() + 123);
        apTester.update();
        assertEq(NORMAL_VALUE, apTester.valueToTrack());
        uint256 _obsv = apTester.observe();
        assertEq(_obsv, NORMAL_VALUE);

        // make a huge pike
        uint256 HUNDRED_BILLION_USD = 100e27; // 100 billion in 18 decimals
        apTester.unprotectedSetTwapTrackVal(HUNDRED_BILLION_USD);
        assertEq(HUNDRED_BILLION_USD, apTester.valueToTrack());

        // then check the new observe
        vm.warp(block.timestamp + 12);
        _obsv = apTester.observe();
        uint256 _diffObsvNormal = _obsv > NORMAL_VALUE
            ? (_obsv - NORMAL_VALUE)
            : (NORMAL_VALUE - _obsv);
        uint256 _diffObsvPike = _obsv > HUNDRED_BILLION_USD
            ? (_obsv - HUNDRED_BILLION_USD)
            : (HUNDRED_BILLION_USD - _obsv);

        // ensure observe is not obviously manipulated by pike
        console.log("new observe=", _obsv);
        assertGt(_diffObsvPike, _diffObsvNormal);
    }

    function testTwapOverflow() public {
        assertEq(activePool.twapDisabled(), false);

        address payable[] memory users;
        users = _utils.createUsers(2);

        vm.warp(1000);

        _openTestCDP(users[0], 5e18, 0.1e18);

        // force TWAP to overflow
        vm.warp(uint256(type(uint64).max) + 1);

        dealCollateral(users[1], 5e18);
        vm.startPrank(users[1]);
        collateral.approve(address(borrowerOperations), type(uint256).max);

        vm.expectEmit(false, false, false, false);
        emit TwapDisabled();
        borrowerOperations.openCdp(0.1e18, bytes32(0), bytes32(0), 5e18);
        vm.stopPrank();

        assertEq(activePool.twapDisabled(), true);
    }
}
