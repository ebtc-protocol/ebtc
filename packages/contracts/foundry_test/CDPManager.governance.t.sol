// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "../contracts/Dependencies/EbtcMath.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";

/*
 * Test suite that tests opened CDPs with two different operations: repayDebt and withdrawDebt
 * Test include testing different metrics such as each CDP ICR, also TCR changes after operations are executed
 */
contract CDPManagerGovernanceTest is eBTCBaseFixture {
    // Storage array of cdpIDs when impossible to calculate array size
    bytes32[] cdpIds;
    uint256 public mintAmount = 1e18;

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

    function testCDPManagerSetStakingRewardSplitWithPermission(
        uint256 newStakingRewardSplit
    ) public {
        // TODO: Test the actual math from this works out
        newStakingRewardSplit = bound(newStakingRewardSplit, 0, cdpManager.MAX_REWARD_SPLIT());

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
        uint256 newInvalidStakingRewardSplit
    ) public {
        newInvalidStakingRewardSplit = bound(
            newInvalidStakingRewardSplit,
            cdpManager.MAX_REWARD_SPLIT() + 1,
            type(uint256).max
        );

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

    function testCDPManagerSetRedemptionFeeFloorWithPermission(
        uint256 newRedemptionFeeFloor
    ) public {
        // TODO: Test the actual math from this works out
        newRedemptionFeeFloor = bound(
            newRedemptionFeeFloor,
            cdpManager.MIN_REDEMPTION_FEE_FLOOR(),
            cdpManager.DECIMAL_PRECISION()
        );

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
        uint256 newInvalidRedemptionFeeFloor
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
        uint256 newInvalidRedemptionFeeFloor = cdpManager.DECIMAL_PRECISION() + 1;

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

    function testCDPManagerSetMinuteDecayFactorWithPermission(uint256 newMinuteDecayFactor) public {
        newMinuteDecayFactor = bound(
            newMinuteDecayFactor,
            cdpManager.MIN_MINUTE_DECAY_FACTOR(),
            cdpManager.MAX_MINUTE_DECAY_FACTOR()
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

    function testCDPManagerSetMinuteDecayFactorLimits(uint256 newInvalidMinuteDecayFactor) public {
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

    function testCDPManagerSetBetaWithPermission(uint256 newBeta) public {
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

    function test_CdpManagerSetGracePeriod_Auth(uint128 newGracePeriod) public {
        newGracePeriod = uint128(
            bound(newGracePeriod, cdpManager.MINIMUM_GRACE_PERIOD(), type(uint128).max)
        );
        (bytes32 whaleCdpId, bytes32 toLiquidateCdpId, address whale) = _initSystemInRecoveryMode();

        uint256 oldGracePeriod = cdpManager.recoveryModeGracePeriodDuration();

        address noPermissionsUser = _utils.getNextUserAddress();
        vm.prank(noPermissionsUser);
        vm.expectRevert("Auth: UNAUTHORIZED");
        cdpManager.setGracePeriod(newGracePeriod);
    }

    function test_CdpManagerSetGracePeriodValid_Succeeds(uint128 newGracePeriod) public {
        newGracePeriod = uint128(
            bound(newGracePeriod, cdpManager.MINIMUM_GRACE_PERIOD(), type(uint128).max)
        );
        (bytes32 whaleCdpId, bytes32 toLiquidateCdpId, address whale) = _initSystemInRecoveryMode();

        uint256 oldGracePeriod = cdpManager.recoveryModeGracePeriodDuration();

        vm.prank(defaultGovernance);
        cdpManager.setGracePeriod(newGracePeriod);

        assertEq(cdpManager.recoveryModeGracePeriodDuration(), newGracePeriod);
    }

    /// @dev Confirm extending the grace period works
    function test_CdpManagerSetGracePeriodValid_IsEnforcedForUnsetGracePeriod(
        uint128 newGracePeriod
    ) public {
        newGracePeriod = uint128(
            bound(
                newGracePeriod,
                cdpManager.MINIMUM_GRACE_PERIOD() + 2,
                cdpManager.MINIMUM_GRACE_PERIOD() * 1000000
            )
        ); // prevent unrealistic overflow

        (bytes32 whaleCdpId, bytes32 toLiquidateCdpId, address whale) = _initSystemInRecoveryMode();

        uint256 oldGracePeriod = cdpManager.recoveryModeGracePeriodDuration();

        vm.prank(defaultGovernance);
        cdpManager.setGracePeriod(newGracePeriod);

        assertEq(cdpManager.recoveryModeGracePeriodDuration(), newGracePeriod);

        _confirmGracePeriodNewDurationEnforced(
            oldGracePeriod,
            newGracePeriod,
            whale,
            toLiquidateCdpId
        );
    }

    function test_CdpManagerSetGracePeriodInvalid_Reverts(uint128 newGracePeriod) public {
        newGracePeriod = uint128(bound(newGracePeriod, 0, cdpManager.MINIMUM_GRACE_PERIOD() - 1));
        (bytes32 whaleCdpId, bytes32 toLiquidateCdpId, address whale) = _initSystemInRecoveryMode();

        uint256 oldGracePeriod = cdpManager.recoveryModeGracePeriodDuration();

        vm.prank(defaultGovernance);
        vm.expectRevert("CdpManager: Grace period below minimum duration");
        cdpManager.setGracePeriod(newGracePeriod);

        assertEq(cdpManager.recoveryModeGracePeriodDuration(), oldGracePeriod);
    }

    function test_CdpManagerSetGracePeriodInvalid_RevertsAndIsNotEnforcedForUnsetGracePeriod(
        uint128 newGracePeriod
    ) public {
        newGracePeriod = uint128(bound(newGracePeriod, 0, cdpManager.MINIMUM_GRACE_PERIOD() - 1));
        (bytes32 whaleCdpId, bytes32 toLiquidateCdpId, address whale) = _initSystemInRecoveryMode();

        uint256 oldGracePeriod = cdpManager.recoveryModeGracePeriodDuration();

        vm.prank(defaultGovernance);
        vm.expectRevert("CdpManager: Grace period below minimum duration");
        cdpManager.setGracePeriod(newGracePeriod);

        assertEq(cdpManager.recoveryModeGracePeriodDuration(), oldGracePeriod);
    }

    /// @dev Assumes newGracePeriod > oldGracePeriod
    function _confirmGracePeriodNewDurationEnforced(
        uint256 oldGracePeriod,
        uint256 newGracePeriod,
        address actor,
        bytes32 toLiquidateCdpId
    ) public {
        vm.startPrank(actor);
        cdpManager.syncGlobalAccountingAndGracePeriod();
        uint256 startTimestamp = block.timestamp;
        uint256 expectedGracePeriodExpiration = cdpManager.recoveryModeGracePeriodDuration() +
            cdpManager.lastGracePeriodStartTimestamp();

        assertEq(startTimestamp, cdpManager.lastGracePeriodStartTimestamp());

        // Attempt before previous duration, should fail
        vm.warp(startTimestamp + oldGracePeriod + 1);
        assertLt(block.timestamp, expectedGracePeriodExpiration, "after grace period complete");

        console.log(1);

        vm.expectRevert("LiquidationLibrary: Recovery mode grace period still in effect");
        cdpManager.liquidate(toLiquidateCdpId);

        // Attempt between previous duration and new duration, should fail
        vm.warp(startTimestamp + newGracePeriod - 1);
        assertLt(block.timestamp, expectedGracePeriodExpiration, "after grace period complete");

        console.log(2);

        vm.expectRevert("LiquidationLibrary: Recovery mode grace period still in effect");
        cdpManager.liquidate(toLiquidateCdpId);

        // Attempt after new duration, should succeed
        vm.warp(startTimestamp + newGracePeriod + 1);
        assertGe(block.timestamp, expectedGracePeriodExpiration, "before grace period complete");

        console.log(3);
        _syncSystemDebtTwapToSpotValue();
        cdpManager.liquidate(toLiquidateCdpId);

        vm.stopPrank();
    }

    function _initSystemInRecoveryMode()
        internal
        returns (bytes32 whaleCdpId, bytes32 toLiquidateCdpId, address whale)
    {
        // Create a whale
        whale = _utils.getNextUserAddress();

        // 2x test price
        priceFeedMock.setPrice(2 ether);
        uint256 price = priceFeedMock.fetchPrice();

        // Open whale CDPs at 220%
        whaleCdpId = _openTestCDP(whale, 1100.2e18, 1000e18);

        /// @audit this liquidation fails, because the check is _ICR < _TCR
        /// @audit this is an edge case where _ICR == _TCR and liquidation is in RM
        toLiquidateCdpId = _openTestCDP(whale, 11.2e18, 10e18);

        assertEq(cdpManager.getCachedICR(whaleCdpId, price), 220e16, "unexpected ICR");
        assertEq(cdpManager.getCachedTCR(price), 220e16, "unexpected TCR");

        // original price
        priceFeedMock.setPrice(1 ether);
        price = priceFeedMock.fetchPrice();

        assertEq(cdpManager.getCachedICR(whaleCdpId, price), 110e16, "unexpected ICR");
        assertEq(cdpManager.getCachedTCR(price), 110e16, "unexpected TCR");
    }
}
