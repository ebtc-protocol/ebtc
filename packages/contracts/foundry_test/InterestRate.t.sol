// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.11;

import {console2 as console} from "forge-std/console2.sol";

import {eBTCBaseFixture} from "./BaseFixture.sol";
import {Utilities} from "./utils/Utilities.sol";

// TODO: Do an invariant test that total interest minted is equal to sum of all borrowers' interest
contract InterestRateTest is eBTCBaseFixture {
    struct CdpState {
        uint256 debt;
        uint256 coll;
        uint256 pendingEBTCDebtReward;
        uint256 pendingEBTCInterest;
        uint256 pendingETHReward;
    }

    uint256 private testNumber;
    address payable[] users;

    Utilities internal _utils;

    uint public constant DECIMAL_PRECISION = 1e18;

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

    ////////////////////////////////////////////////////////////////////////////
    // Tests
    ////////////////////////////////////////////////////////////////////////////

    function setUp() public override {
        eBTCBaseFixture.setUp();

        eBTCBaseFixture.connectLQTYContracts();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();

        _utils = new Utilities();
        users = _utils.createUsers(3);
    }

    /**
        - Confirm some basic CDP properites hold (count, ID, sorting with 1 CDP)
        - Confirm CDP is generated with the intended debt value, and that the entire system debt and active pool are as expected
        - Ensure no pending rewards before time has passed
        - Ensure pending interest is present for CDP after one year, and that it has the correct value given assumed interest rate. pendingEBTCInterest and debt values for the CDP should reflect this
        - Ensure the interest is reflected in ICR - ICR has gone down for CDP (more debt, same collateral)
        - Ensure the debt is reflected in entire system debt (note this only covers the _one CDP_ state and should handle _N CDPs_)
        - Ensure active pool does _not_ reflect the new debt (it's implicit and not realized as tokens yet)
        - Ensure LQTY staking balance hasn't changed during this process

        Next, apply pending interest via an addColl() operation
    */
    function testInterestIsAppliedAddCollOps() public {
        vm.startPrank(users[0]);
        uint256 coll = _utils.calculateCollAmount(2000e18, priceFeedMock.getPrice(), 200e16);

        bytes32 cdpId0 = borrowerOperations.openCdp{value: coll}(
            5e17,
            _utils.calculateBorrowAmountFromDebt(
                2000e18,
                cdpManager.EBTC_GAS_COMPENSATION(),
                cdpManager.getBorrowingRateWithDecay()
            ), // Excluding borrow fee and gas compensation
            bytes32(0),
            bytes32(0)
        );

        uint256 lqtyStakingBalanceOld = eBTCToken.balanceOf(address(lqtyStaking));
        assertGt(lqtyStakingBalanceOld, 0);

        CdpState memory cdpState;
        cdpState = _getEntireDebtAndColl(cdpId0);
        assertEq(cdpState.debt, 2000e18);

        assertEq(cdpManager.getEntireSystemDebt(), 2000e18);
        assertEq(activePool.getEBTCDebt(), 2000e18);

        // Confirm no pending rewards before time has passed
        assertFalse(cdpManager.hasPendingRewards(cdpId0));

        // Fast-forward 1 year
        skip(365 days);

        // Has pending interest
        assertTrue(cdpManager.hasPendingRewards(cdpId0));

        cdpState = _getEntireDebtAndColl(cdpId0);
        // Expected interest over a year is 2%
        assertApproxEqRel(cdpState.pendingEBTCInterest, 40e18, 0.001e18); // Error is <0.1% of the expected value
        assertApproxEqRel(cdpState.debt, 2040e18, 0.0001e18); // Error is <0.01% of the expected value
        uint256 debtOld = cdpState.debt;

        assertLt(cdpManager.getCurrentICR(cdpId0, priceFeedMock.getPrice()), 200e16);

        assertEq(cdpState.debt, cdpManager.getEntireSystemDebt());

        // Active pool only contains realized interest (no pending interest)
        assertEq(activePool.getEBTCDebt(), 2000e18);

        assertEq(eBTCToken.balanceOf(address(lqtyStaking)), lqtyStakingBalanceOld);

        // Apply pending interest
        borrowerOperations.addColl{value: 1}(cdpId0, bytes32(0), bytes32(0));

        assertFalse(cdpManager.hasPendingRewards(cdpId0));

        cdpState = _getEntireDebtAndColl(cdpId0);
        assertEq(cdpState.pendingEBTCInterest, 0);
        assertEq(cdpState.debt, debtOld);

        assertEq(cdpManager.getEntireSystemDebt(), debtOld);
        assertEq(activePool.getEBTCDebt(), debtOld);

        // Check interest is minted to LQTY staking contract
        assertApproxEqRel(
            eBTCToken.balanceOf(address(lqtyStaking)).sub(lqtyStakingBalanceOld),
            40e18,
            0.001e18
        ); // Error is <0.1% of the expected value
    }

    /**
        Confirm that interest is applied to a CDP when collateral is removed by user
    */
    function testInterestIsAppliedWithdrawCollOps() public {
        vm.startPrank(users[0]);
        uint256 coll = _utils.calculateCollAmount(2000e18, priceFeedMock.getPrice(), 200e16);
        bytes32 cdpId0 = borrowerOperations.openCdp{value: coll}(
            5e17,
            _utils.calculateBorrowAmountFromDebt(
                2000e18,
                cdpManager.EBTC_GAS_COMPENSATION(),
                cdpManager.getBorrowingRateWithDecay()
            ), // Excluding borrow fee and gas compensation
            bytes32(0),
            bytes32(0)
        );
        uint256 lqtyStakingBalanceOld = eBTCToken.balanceOf(address(lqtyStaking));
        assertGt(lqtyStakingBalanceOld, 0);

        CdpState memory cdpState;
        cdpState = _getEntireDebtAndColl(cdpId0);
        assertEq(cdpState.debt, 2000e18);

        assertEq(cdpManager.getEntireSystemDebt(), 2000e18);
        assertEq(activePool.getEBTCDebt(), 2000e18);

        // Confirm no pending rewards before time has passed
        assertFalse(cdpManager.hasPendingRewards(cdpId0));

        // Fast-forward 1 year
        skip(365 days);

        // Has pending interest
        assertTrue(cdpManager.hasPendingRewards(cdpId0));

        cdpState = _getEntireDebtAndColl(cdpId0);
        // Expected interest over a year is 2%
        assertApproxEqRel(cdpState.pendingEBTCInterest, 40e18, 0.001e18); // Error is <0.1% of the expected value
        assertApproxEqRel(cdpState.debt, 2040e18, 0.0001e18); // Error is <0.01% of the expected value
        uint256 debtOld = cdpState.debt;

        assertLt(cdpManager.getCurrentICR(cdpId0, priceFeedMock.getPrice()), 200e16);

        assertEq(cdpState.debt, cdpManager.getEntireSystemDebt());

        // Active pool only contains realized interest (no pending interest)
        assertEq(activePool.getEBTCDebt(), 2000e18);

        assertEq(eBTCToken.balanceOf(address(lqtyStaking)), lqtyStakingBalanceOld);

        // Apply pending interest
        borrowerOperations.withdrawColl(cdpId0, 1e17, bytes32(0), bytes32(0));
        assertFalse(cdpManager.hasPendingRewards(cdpId0));

        cdpState = _getEntireDebtAndColl(cdpId0);
        assertEq(cdpState.pendingEBTCInterest, 0);
        assertEq(cdpState.debt, debtOld);

        assertEq(cdpManager.getEntireSystemDebt(), debtOld);
        assertEq(activePool.getEBTCDebt(), debtOld);

        // Check interest is minted to LQTY staking contract
        assertApproxEqRel(
            eBTCToken.balanceOf(address(lqtyStaking)).sub(lqtyStakingBalanceOld),
            40e18,
            0.001e18
        ); // Error is <0.1% of the expected value
    }

    /**
        - Open two identical CDPS
        - Advance time and ensure the debt and interest accrued are identical
        - Now, add collateral to one of the CDPS (a single wei). This interaction realizes the pending debt.
        - Advance time and ensure the pending interest is the same across both CDPS
     */
    function testInterestIsSameForInteractingAndNonInteractingUsers() public {
        bytes32 cdpId0 = borrowerOperations.openCdp{value: 100 ether}(
            FEE,
            2e18,
            bytes32(0),
            bytes32(0)
        );
        bytes32 cdpId1 = borrowerOperations.openCdp{value: 100 ether}(
            FEE,
            2e18,
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
        borrowerOperations.addColl{value: 1}(cdpId0, bytes32(0), bytes32(0));

        (debt0, , , pendingInterest0, ) = cdpManager.getEntireDebtAndColl(cdpId0);
        assertEq(pendingInterest0, 0);
        // TODO: Check why loss of precision
        assertApproxEqAbs(debt0, debt1, 1);
    }

    function testInterestIsAppliedOnRedistributedDebt() public {
        uint256 coll0 = _utils.calculateCollAmount(4000e18, priceFeedMock.getPrice(), 300e16);
        uint256 coll1 = _utils.calculateCollAmount(2000e18, priceFeedMock.getPrice(), 200e16);

        bytes32 cdpId0 = borrowerOperations.openCdp{value: coll0}(
            FEE,
            _utils.calculateBorrowAmountFromDebt(
                4000e18,
                cdpManager.EBTC_GAS_COMPENSATION(),
                cdpManager.getBorrowingRateWithDecay()
            ),
            bytes32(0),
            bytes32(0)
        );
        bytes32 cdpId1 = borrowerOperations.openCdp{value: coll1}(
            FEE,
            _utils.calculateBorrowAmountFromDebt(
                2000e18,
                cdpManager.EBTC_GAS_COMPENSATION(),
                cdpManager.getBorrowingRateWithDecay()
            ),
            bytes32(0),
            bytes32(0)
        );

        assertFalse(cdpManager.hasPendingRewards(cdpId0));

        // Price falls from 7428e13 to 3000e13
        priceFeedMock.setPrice(3000 * 1e13);

        // Liquidate cdp1 and redistribute debt to cdp0
        vm.prank(users[0]);
        cdpManager.liquidate(cdpId1);

        // Has pending redistribution
        assertTrue(cdpManager.hasPendingRewards(cdpId0));

        // Now ~half of cdp0's debt is pending and in the default pool
        CdpState memory cdpState;
        cdpState = _getEntireDebtAndColl(cdpId0);

        // Check if pending debt/coll is correct
        // Some loss of precision due to rounding
        assertApproxEqRel(cdpState.pendingEBTCDebtReward, 2000e18, 0.02e18);
        assertApproxEqRel(cdpState.pendingETHReward, coll1, 0.02e18);

        assertApproxEqRel(cdpState.coll, coll0.add(coll1), 0.02e18);
        assertApproxEqRel(
            cdpState.debt,
            6000e18, // debt0 + debt1
            0.02e18
        );

        // No interest since no time has passed
        assertEq(cdpState.pendingEBTCInterest, 0);

        assertEq(cdpManager.getEntireSystemDebt(), 6000e18);
        assertEq(defaultPool.getEBTCDebt(), 2000e18);

        uint256 lqtyStakingBalanceOld = eBTCToken.balanceOf(address(lqtyStaking));

        skip(365 days);

        // Expected interest over a year is 2%
        cdpState = _getEntireDebtAndColl(cdpId0);
        assertApproxEqRel(
            cdpState.pendingEBTCDebtReward,
            2040e18, // ~2% over a year 2000e18
            0.02e18
        );
        assertApproxEqRel(
            cdpState.pendingEBTCInterest,
            80e18, // ~2% over a year on 4000e18
            0.02e18
        );
        assertApproxEqRel(
            cdpState.debt,
            6120e18, // ~2% over a year
            0.02e18
        );

        // TODO: Check if precision loss can lead to issues. Can it be avoided?
        assertApproxEqRel(cdpState.debt, cdpManager.getEntireSystemDebt(), 2);

        // Default pool only contains realized interest (no pending interest)
        assertEq(defaultPool.getEBTCDebt(), 2000e18);

        uint256 debtOld = cdpState.debt;

        // Apply pending interest
        borrowerOperations.addColl{value: 100e18}(cdpId0, bytes32(0), bytes32(0));

        assertFalse(cdpManager.hasPendingRewards(cdpId0));

        cdpState = _getEntireDebtAndColl(cdpId0);
        assertEq(cdpState.pendingEBTCDebtReward, 0);
        assertEq(cdpState.pendingEBTCInterest, 0);
        assertEq(cdpState.debt, debtOld);

        assertApproxEqRel(cdpManager.getEntireSystemDebt(), debtOld, 2);
        // TODO: Check if precision loss can lead to issues. Can it be avoided?
        //        assertApproxEqAbs(defaultPool.getEBTCDebt(), 0, 100);
        //        assertEq(activePool.getEBTCDebt(), debtOld);

        // Check interest is minted to LQTY staking contract
        assertApproxEqRel(
            eBTCToken.balanceOf(address(lqtyStaking)).sub(lqtyStakingBalanceOld),
            120e18,
            0.002e18
        ); // Error is <0.2% of the expected value
    }

    function testCalculateBorrowAmountFromDebt() public {
        bytes32 cdpId = borrowerOperations.openCdp{value: users[0].balance}(
            5e17,
            _utils.calculateBorrowAmountFromDebt(
                2000e18,
                cdpManager.EBTC_GAS_COMPENSATION(),
                cdpManager.getBorrowingRateWithDecay()
            ),
            bytes32(0),
            bytes32(0)
        );
        (uint256 debt, , , , ) = cdpManager.getEntireDebtAndColl(cdpId);
        // Borrow amount + gas compensation
        assertEq(debt, 2000e18);
    }
}
