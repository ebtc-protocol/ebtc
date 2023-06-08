// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "../contracts/Dependencies/LiquityMath.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";

/*
 * Test suite that tests opened CDPs with two different operations: repayEBTC and withdrawEBTC
 * Test include testing different metrics such as each CDP ICR, also TCR changes after operations are executed
 */
contract CDPManagerGovernanceTest is eBTCBaseFixture {
    // Storage array of cdpIDs when impossible to calculate array size
    bytes32[] cdpIds;
    uint public mintAmount = 1e18;

    function setUp() public override {
        eBTCBaseFixture.setUp();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();
    }

    // -------- Set Staking Split --------

    function testCDPManagerSetStakingRewardSplitNoPermission() public {
        address user = _utils.getNextUserAddress();

        vm.startPrank(user);
        vm.expectRevert("Auth: UNAUTHORIZED");
        cdpManager.setStakingRewardSplit(5000);
        vm.stopPrank();
    }

    function testCDPManagerSetStakingRewardSplitWithPermission(uint newStakingRewardSplit) public {
        // TODO: Test the actual math from this works out
        vm.assume(newStakingRewardSplit <= cdpManager.MAX_REWARD_SPLIT());

        address user = _utils.getNextUserAddress();

        // Grant permission
        vm.prank(defaultGovernance);
        authority.setUserRole(user, 3, true);

        // Set split
        vm.startPrank(user);
        // TODO: Confirm event

        cdpManager.setStakingRewardSplit(newStakingRewardSplit);
        vm.stopPrank();

        // Confirm variable set
        assertEq(cdpManager.stakingRewardSplit(), newStakingRewardSplit);
    }

    function testCDPManagerSetStakingRewardSplitValueLimits(
        uint newInvalidStakingRewardSplit
    ) public {
        vm.assume(newInvalidStakingRewardSplit > cdpManager.MAX_REWARD_SPLIT());

        address user = _utils.getNextUserAddress();

        // Grant permission
        vm.prank(defaultGovernance);
        authority.setUserRole(user, 3, true);

        vm.startPrank(user);
        vm.expectRevert("CDPManager: new staking reward split exceeds max");
        cdpManager.setStakingRewardSplit(newInvalidStakingRewardSplit);
        vm.stopPrank();
    }

    // -- Set Redemption Fee Floor --

    function testCDPManagerSetRedemptionFeeFloorNoPermission() public {
        address user = _utils.getNextUserAddress();

        vm.startPrank(user);
        vm.expectRevert("Auth: UNAUTHORIZED");
        cdpManager.setRedemptionFeeFloor(500);
        vm.stopPrank();
    }

    function testCDPManagerSetRedemptionFeeFloorWithPermission(uint newRedemptionFeeFloor) public {
        // TODO: Test the actual math from this works out
        vm.assume(newRedemptionFeeFloor >= cdpManager.MIN_REDEMPTION_FEE_FLOOR());
        vm.assume(newRedemptionFeeFloor <= cdpManager.DECIMAL_PRECISION());

        address user = _utils.getNextUserAddress();

        // Grant permission
        vm.prank(defaultGovernance);
        authority.setUserRole(user, 3, true);

        // Set redemption fee floor
        vm.startPrank(user);
        // TODO: Confirm event

        cdpManager.setRedemptionFeeFloor(newRedemptionFeeFloor);
        vm.stopPrank();

        // Confirm variable set
        assertEq(cdpManager.redemptionFeeFloor(), newRedemptionFeeFloor);
    }

    function testCDPManagerSetRedemptionFeeFloorValueLimits(
        uint newInvalidRedemptionFeeFloor
    ) public {
        vm.assume(
            newInvalidRedemptionFeeFloor < cdpManager.MIN_REDEMPTION_FEE_FLOOR() ||
                newInvalidRedemptionFeeFloor > cdpManager.DECIMAL_PRECISION()
        );

        address user = _utils.getNextUserAddress();

        // Grant permission
        vm.prank(defaultGovernance);
        authority.setUserRole(user, 3, true);

        vm.startPrank(user);
        if (newInvalidRedemptionFeeFloor < cdpManager.MIN_REDEMPTION_FEE_FLOOR()) {
            vm.expectRevert("CDPManager: new redemption fee floor is lower than minimum");
            cdpManager.setRedemptionFeeFloor(newInvalidRedemptionFeeFloor);
        } else if (newInvalidRedemptionFeeFloor > cdpManager.DECIMAL_PRECISION()) {
            vm.expectRevert("CDPManager: new redemption fee floor is higher than maximum");
            cdpManager.setRedemptionFeeFloor(newInvalidRedemptionFeeFloor);
        }
        vm.stopPrank();
    }

    function testCDPManagerSetRedemptionFeeFloorHigherThanMax() public {
        uint newInvalidRedemptionFeeFloor = cdpManager.DECIMAL_PRECISION() + 1;

        address user = _utils.getNextUserAddress();

        // Grant permission
        vm.prank(defaultGovernance);
        authority.setUserRole(user, 3, true);

        vm.startPrank(user);
        vm.expectRevert("CDPManager: new redemption fee floor is higher than maximum");
        cdpManager.setRedemptionFeeFloor(newInvalidRedemptionFeeFloor);
        vm.stopPrank();
    }

    // -- Set Decay Factor --
    function testCDPManagerSetMinuteDecayFactorNoPermission() public {
        address user = _utils.getNextUserAddress();

        vm.startPrank(user);
        vm.expectRevert("Auth: UNAUTHORIZED");
        cdpManager.setMinuteDecayFactor(1000);
        vm.stopPrank();
    }

    function testCDPManagerSetMinuteDecayFactorWithPermission(uint newMinuteDecayFactor) public {
        vm.assume(
            newMinuteDecayFactor >= cdpManager.MIN_MINUTE_DECAY_FACTOR() &&
                newMinuteDecayFactor <= cdpManager.MAX_MINUTE_DECAY_FACTOR()
        );

        address user = _utils.getNextUserAddress();

        // Grant permission
        vm.prank(defaultGovernance);
        authority.setUserRole(user, 3, true);

        // Set minute decay factor
        vm.startPrank(user);
        // TODO: Confirm event

        cdpManager.setMinuteDecayFactor(newMinuteDecayFactor);
        vm.stopPrank();

        // Confirm variable set
        assertEq(cdpManager.minuteDecayFactor(), newMinuteDecayFactor);
    }

    function testCDPManagerSetMinuteDecayFactorLimits(uint newInvalidMinuteDecayFactor) public {
        vm.assume(
            newInvalidMinuteDecayFactor < cdpManager.MIN_MINUTE_DECAY_FACTOR() ||
                newInvalidMinuteDecayFactor > cdpManager.MAX_MINUTE_DECAY_FACTOR()
        );

        address user = _utils.getNextUserAddress();

        // Grant permission
        vm.prank(defaultGovernance);
        authority.setUserRole(user, 3, true);

        vm.startPrank(user);
        vm.expectRevert("CDPManager: new minute decay factor out of range");
        cdpManager.setMinuteDecayFactor(newInvalidMinuteDecayFactor);
        vm.stopPrank();
    }

    // Set beta
    function testCDPManagerSetBetaNoPermission() public {
        address user = _utils.getNextUserAddress();

        vm.startPrank(user);
        vm.expectRevert("Auth: UNAUTHORIZED");
        cdpManager.setBeta(500);
        vm.stopPrank();
    }

    function testCDPManagerSetBetaWithPermission(uint newBeta) public {
        address user = _utils.getNextUserAddress();

        // Grant permission
        vm.prank(defaultGovernance);
        authority.setUserRole(user, 3, true);

        // Set redemption fee floor
        vm.startPrank(user);
        // TODO: Confirm event

        cdpManager.setBeta(newBeta);
        vm.stopPrank();

        // Confirm variable set
        assertEq(cdpManager.beta(), newBeta);
    }
}
