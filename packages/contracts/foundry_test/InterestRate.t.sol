// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.11;

import {console2 as console} from "forge-std/console2.sol";

import {eBTCBaseFixture} from "./BaseFixture.sol";
import {Utilities} from "./utils/Utilities.sol";

contract InterestRateTest is eBTCBaseFixture {
    uint256 private testNumber;
    address payable[] users;

    // TODO: Move to base fixture
    Utilities internal _utils;
    // TODO: Inherit base fixture from LiquityBase
    uint256 EBTC_GAS_COMPENSATION;
    uint public constant DECIMAL_PRECISION = 1e18;
    uint256 internal constant MAX_UINT256 = 2 ** 256 - 1;

    struct CdpState {
        uint256 debt;
        uint256 coll;
        uint256 pendingEBTCDebtReward;
        uint256 pendingEBTCInterest;
        uint256 pendingETHReward;
    }

    function setUp() public override {
        eBTCBaseFixture.setUp();

        eBTCBaseFixture.connectLQTYContracts();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();

        _utils = new Utilities();
        users = _utils.createUsers(3);

        EBTC_GAS_COMPENSATION = cdpManager.EBTC_GAS_COMPENSATION();
    }

    function testCalculateBorrowAmountFromDebt() public {
        uint256 debtWithoutGasComp = 2000e18;
        bytes32 cdpId = borrowerOperations.openCdp{value: users[0].balance}(
            5e17,
            _calculateBorrowAmountFromDebt(debtWithoutGasComp),
            bytes32(0),
            bytes32(0)
        );
        (uint256 debt, , , , ) = cdpManager.getEntireDebtAndColl(cdpId);
        // Borrow amount + gas compensation
        assertEq(debt, debtWithoutGasComp.add(EBTC_GAS_COMPENSATION));
    }

    function testInterestIsApplied() public {
        uint256 debtWithoutGasComp = 2000e18;
        vm.prank(users[0]);
        bytes32 cdpId0 = borrowerOperations.openCdp{value: users[0].balance}(
            5e17,
            _calculateBorrowAmountFromDebt(debtWithoutGasComp), // Excluding borrow fee and gas compensation
            bytes32(0),
            bytes32(0)
        );
        assertTrue(cdpId0 != "");
        assertEq(cdpManager.getCdpIdsCount(), 1);

        // Make sure valid cdpId returned
        bytes32 cdpId1 = sortedCdps.getLast();
        assertEq(cdpId0, cdpId1);

        uint256 debt;
        (debt, , , , ) = cdpManager.getEntireDebtAndColl(cdpId0);
        assertEq(debt, debtWithoutGasComp.add(EBTC_GAS_COMPENSATION));

        skip(365 days);

        (debt, , , , ) = cdpManager.getEntireDebtAndColl(cdpId0);
        // Expected interest over a year is 2%
        uint256 expectedInterest = debtWithoutGasComp.mul(2).div(100);
        assertApproxEqRel(
            debt,
            debtWithoutGasComp.add(expectedInterest).add(EBTC_GAS_COMPENSATION),
            0.0001e18
        ); // Error is <0.01% of the expected value
    }

    function testInterestIsSameForInteractingAndNonInteractingUsers() public {
        vm.prank(users[0]);
        bytes32 cdpId0 = borrowerOperations.openCdp{value: 100 ether}(
            5e17,
            2000e18,
            bytes32(0),
            bytes32(0)
        );
        vm.prank(users[1]);
        bytes32 cdpId1 = borrowerOperations.openCdp{value: 100 ether}(
            5e17,
            2000e18,
            bytes32(0),
            bytes32(0)
        );
        assertEq(cdpManager.getCdpIdsCount(), 2);

        uint256 debt0;
        uint256 debt1;
        uint256 pendingReward0;
        uint256 pendingInterest0;
        uint256 pendingReward1;
        uint256 pendingInterest1;

        (debt0, , , , ) = cdpManager.getEntireDebtAndColl(cdpId0);
        (debt1, , , , ) = cdpManager.getEntireDebtAndColl(cdpId1);

        assertEq(debt0, debt1);

        skip(100 days);

        (debt0, , pendingReward0, pendingInterest0, ) = cdpManager.getEntireDebtAndColl(cdpId0);
        (debt1, , pendingReward1, pendingInterest1, ) = cdpManager.getEntireDebtAndColl(cdpId1);

        assertEq(pendingReward0, 0);
        assertEq(pendingReward1, 0);

        assertGt(pendingInterest0, 0);
        assertEq(pendingInterest0, pendingInterest1);

        assertEq(debt0, debt1);

        // Realize pending debt
        vm.prank(users[0]);
        borrowerOperations.addColl{value: 1}(cdpId0, bytes32(0), bytes32(0));

        (debt0, , , pendingInterest0, ) = cdpManager.getEntireDebtAndColl(cdpId0);
        assertEq(pendingInterest0, 0);
        assertEq(debt0, debt1);

        skip(100 days);

        (debt0, , pendingReward0, pendingInterest0, ) = cdpManager.getEntireDebtAndColl(cdpId0);
        (debt1, , pendingReward1, pendingInterest1, ) = cdpManager.getEntireDebtAndColl(cdpId1);

        assertGt(pendingInterest0, 0);
        // TODO: Check why loss of precision
        assertApproxEqAbs(debt0, debt1, 1);

        // Realize pending debt
        vm.prank(users[0]);
        borrowerOperations.addColl{value: 1}(cdpId0, bytes32(0), bytes32(0));

        (debt0, , , pendingInterest0, ) = cdpManager.getEntireDebtAndColl(cdpId0);
        assertEq(pendingInterest0, 0);
        // TODO: Check why loss of precision
        assertApproxEqAbs(debt0, debt1, 1);
    }

    function testInterestIsAppliedOnRedistributedDebt() public {
        uint256 debt0WithoutGasComp = 2000e18;
        uint256 coll0 = _calculateCollAmount(debt0WithoutGasComp.add(EBTC_GAS_COMPENSATION), 300e16);

        uint256 debt1 = 2000e18;
        uint256 coll1 = _calculateCollAmount(debt1, 200e16);

        vm.prank(users[0]);
        bytes32 cdpId0 = borrowerOperations.openCdp{value: coll0}(
            5e17,
            _calculateBorrowAmountFromDebt(debt0WithoutGasComp),
            bytes32(0),
            bytes32(0)
        );
        vm.prank(users[1]);
        bytes32 cdpId1 = borrowerOperations.openCdp{value: coll1}(
            5e17,
            _calculateBorrowAmountFromDebt(debt1.sub(EBTC_GAS_COMPENSATION)),
            bytes32(0),
            bytes32(0)
        );

        // Price falls from 200e18 to 100e18
        priceFeedMock.setPrice(100e18);

        // Liquidate cdp1 and redistribute debt to cdp0
        vm.prank(users[2]);
        cdpManager.liquidate(cdpId1);

        // Now ~half of cdp0's debt is pending and in the default pool
        CdpState memory cdpState = _getEntireDebtAndColl(cdpId0);

        // Check if pending debt/coll is correct
        // Some loss of precision due to rounding
        assertApproxEqRel(cdpState.pendingEBTCDebtReward, debt1, 0.01e18);
        assertApproxEqRel(cdpState.pendingETHReward, coll1, 0.01e18);

        assertApproxEqRel(cdpState.coll, coll0.add(coll1), 0.01e18);
        assertApproxEqRel(
            cdpState.debt,
            debt0WithoutGasComp.add(debt1).add(EBTC_GAS_COMPENSATION),
            0.01e18
        );

        // No interest since no time has passed
        assertEq(cdpState.pendingEBTCInterest, 0);

        skip(365 days);

        // Expected interest over a year is 2%
        uint256 expectedInterest = (debt0WithoutGasComp.add(debt1)).mul(2).div(100);

        cdpState = _getEntireDebtAndColl(cdpId0);
        assertApproxEqRel(
            cdpState.debt,
            debt0WithoutGasComp.add(debt1).add(expectedInterest).add(EBTC_GAS_COMPENSATION),
            0.01e18
        );
    }

    ////////////////////////////////////////////////////////////////////////////
    // Utilities
    ////////////////////////////////////////////////////////////////////////////

    // TODO: Move somewhere else
    function mulDivUp(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256 z) {
        /// @solidity memory-safe-assembly
        assembly {
            // Equivalent to require(denominator != 0 && (y == 0 || x <= type(uint256).max / y))
            if iszero(mul(denominator, iszero(mul(y, gt(x, div(MAX_UINT256, y)))))) {
                revert(0, 0)
            }

            // If x * y modulo the denominator is strictly greater than 0,
            // 1 is added to round up the division of x * y by the denominator.
            z := add(gt(mod(mul(x, y), denominator), 0), div(mul(x, y), denominator))
        }
    }

    function _calculateBorrowAmountFromDebt(uint256 amount) internal view returns (uint256) {
        // Borrow amount = Debt / (1 + Borrow Rate)
        return
            mulDivUp(
                amount,
                DECIMAL_PRECISION,
                DECIMAL_PRECISION.add(cdpManager.getBorrowingRateWithDecay())
            );
    }

    function _calculateCollAmount(
        uint256 debt,
        uint256 collateralRatio
    ) internal view returns (uint256) {
        return _utils.calculateCollAmount(debt, priceFeedMock.getPrice(), collateralRatio);
    }

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
}
