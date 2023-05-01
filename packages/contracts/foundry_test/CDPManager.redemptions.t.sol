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

    function testCDPManagerSetMinuteDecayFactorDecaysBaseRate() public {
        uint newMinuteDecayFactor = (500 + 999037758833783000);
        uint timePassed = 600; // seconds/60 => minute

        address user = _utils.getNextUserAddress();

        // Grant permission
        vm.prank(defaultGovernance);
        authority.setUserRole(user, 3, true);

        collateral.approve(address(borrowerOperations), type(uint256).max);

        assertEq(cdpManager.getBorrowingRateWithDecay(), 0);

        uint debt = 2e17;

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
        uint _redeemDebt = 1;
        (bytes32 firstRedemptionHint, uint partialRedemptionHintNICR, , ) = hintHelpers
            .getRedemptionHints(_redeemDebt, (priceFeedMock.fetchPrice()), 0);
        cdpManager.redeemCollateral(
            _redeemDebt,
            firstRedemptionHint,
            bytes32(0),
            bytes32(0),
            partialRedemptionHintNICR,
            0,
            1e18
        );

        uint initialRate = cdpManager.baseRate();

        console.log("baseRate: %s", cdpManager.baseRate());

        // Calculate the expected decayed base rate
        uint decayFactor = cdpManager.minuteDecayFactor();
        console.log("decayFactor: %s", decayFactor);
        uint _decayMultiplier = _decPow(decayFactor, (timePassed / 60));
        console.log("_decayMultiplier: %s", _decayMultiplier);
        uint expectedDecayedBaseRate = (initialRate * _decayMultiplier) /
            cdpManager.DECIMAL_PRECISION();

        // Fast forward time by 1 minute
        vm.warp(block.timestamp + timePassed);
        // set factor to decay base rate
        cdpManager.setMinuteDecayFactor(newMinuteDecayFactor);
        // Test that baseRate is decayed according to the previous factor
        console.log("baseRate after: %s", cdpManager.baseRate());
        console.log("expected baseRate: %s", expectedDecayedBaseRate);
        assertEq(cdpManager.baseRate(), expectedDecayedBaseRate);
        vm.stopPrank();
    }

    function _decMul(uint x, uint y) internal pure returns (uint decProd) {
        uint prod_xy = x * y;

        decProd = (prod_xy + (1e18 / 2)) / 1e18;
    }

    function _decPow(uint _base, uint _minutes) internal pure returns (uint) {
        if (_minutes > 525600000) {
            _minutes = 525600000;
        } // cap to avoid overflow

        if (_minutes == 0) {
            return 1e18;
        }

        uint y = 1e18;
        uint x = _base;
        uint n = _minutes;

        // Exponentiation-by-squaring
        while (n > 1) {
            if (n % 2 == 0) {
                x = _decMul(x, x);
                n = n / 2;
            } else {
                // if (n % 2 != 0)
                y = _decMul(x, y);
                x = _decMul(x, x);
                n = (n - 1) / 2;
            }
        }

        return _decMul(x, y);
    }
}
