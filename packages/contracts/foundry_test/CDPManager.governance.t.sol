// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;
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

    // -------- eBTC Minting governance cases --------

    function testCDPManagerSetStakingRewardSplitNoPermission() public {
        address user = _utils.getNextUserAddress();

        vm.startPrank(user);
        vm.expectRevert("CDPManager: sender not authorized for setStakingRewardSplit(uint256)");
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
}
