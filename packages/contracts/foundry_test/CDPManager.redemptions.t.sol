// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;
pragma experimental ABIEncoderV2;
import "forge-std/Test.sol";
import "../contracts/Dependencies/LiquityMath.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";

contract CDPManagerRedemptionsTest is eBTCBaseFixture {
    // Storage array of cdpIDs when impossible to calculate array size
    bytes32[] cdpIds;
    uint public mintAmount = 1e18;

    function setUp() public override {
        eBTCBaseFixture.setUp();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();
        vm.warp(3 weeks);
    }

    function atestCDPManagerSetMinuteDecayFactorDecaysBaseRate() public {
        uint newMinuteDecayFactor = 500;
        uint timePassed = 60; // 60 seconds (1 minute)

        address user = _utils.getNextUserAddress();

        // Grant permission
        vm.prank(defaultGovernance);
        authority.setUserRole(user, 3, true);

        collateral.approve(address(borrowerOperations), type(uint256).max);

        assertEq(cdpManager.getBorrowingRateWithDecay(), 0);

        uint debt = _utils.calculateBorrowAmountFromDebt(
            2e17,
            cdpManager.EBTC_GAS_COMPENSATION(),
            cdpManager.getBorrowingRateWithDecay()
        );

        console.log("debt %s", debt);

        bytes32 cdpId1 = _openTestCDP(user, 10000 ether, debt);

        vm.startPrank(user);
        assertEq(cdpManager.getBorrowingRateWithDecay(), 0);

        // Set minute decay factor
        cdpManager.setMinuteDecayFactor(newMinuteDecayFactor);

        // Confirm variable set
        assertEq(cdpManager.minuteDecayFactor(), newMinuteDecayFactor);

        // Set the initial baseRate to a non-zero value via rdemption
        console.log("balance: %s", eBTCToken.balanceOf(user));
        eBTCToken.approve(address(cdpManager), type(uint256).max);
        cdpManager.redeemCollateral(1, bytes32(0), bytes32(0), bytes32(0), 0, 0, 1e18);

        uint initialRate = cdpManager.baseRate();

        console.log("baseRate: %s", cdpManager.baseRate());

        // Calculate the expected decayed base rate
        uint decayFactor = cdpManager.minuteDecayFactor();
        uint expectedDecayedBaseRate = (initialRate * (decayFactor ** timePassed)) /
            (cdpManager.DECIMAL_PRECISION() ** timePassed);

        // Fast forward time by 1 minute
        vm.warp(block.timestamp + timePassed);

        // Test that baseRate is decayed according to the previous factor
        console.log("baseRate after: %s", cdpManager.baseRate());
        console.log("expected baseRate: %s", expectedDecayedBaseRate);
        assertEq(cdpManager.baseRate(), expectedDecayedBaseRate);
        vm.stopPrank();
    }
}
