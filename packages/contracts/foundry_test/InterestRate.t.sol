// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.11;

import {console2 as console} from "forge-std/console2.sol";

import {eBTCBaseFixture} from "./BaseFixture.sol";
import {Utilities} from "./utils/Utilities.sol";
import {LiquityBase} from "../contracts/Dependencies/LiquityBase.sol";

contract LiquityTester is LiquityBase {
    function calcUnitAmountAfterInterest(uint _time) public pure virtual returns (uint) {
        return _calcUnitAmountAfterInterest(_time);
    }
}

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
    LiquityTester internal _liquityTester;

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
        _liquityTester = new LiquityTester();
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
        uint256 coll = _utils.calculateCollAmount(
            2000e18,
            priceFeedMock.getPrice(),
            COLLATERAL_RATIO_DEFENSIVE
        );

        bytes32 cdpId0 = borrowerOperations.openCdp{value: coll}(
            5e17,
            _utils.calculateBorrowAmountFromDebt(
                2000e18,
                cdpManager.EBTC_GAS_COMPENSATION(),
                cdpManager.getBorrowingRateWithDecay()
            ),
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

        assertLt(
            cdpManager.getCurrentICR(cdpId0, priceFeedMock.getPrice()),
            COLLATERAL_RATIO_DEFENSIVE
        );

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
        uint256 coll = _utils.calculateCollAmount(
            2000e18,
            priceFeedMock.getPrice(),
            COLLATERAL_RATIO_DEFENSIVE
        );
        bytes32 cdpId0 = borrowerOperations.openCdp{value: coll}(
            5e17,
            _utils.calculateBorrowAmountFromDebt(
                2000e18,
                cdpManager.EBTC_GAS_COMPENSATION(),
                cdpManager.getBorrowingRateWithDecay()
            ),
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

        assertLt(
            cdpManager.getCurrentICR(cdpId0, priceFeedMock.getPrice()),
            COLLATERAL_RATIO_DEFENSIVE
        );

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
    Confirm that interest is applied to a CDP when user repays eBTC
    */
    function testInterestIsAppliedRepayEbtc() public {
        CdpState memory cdpState;
        vm.startPrank(users[0]);

        uint debt = 2000e18;
        uint256 coll = _utils.calculateCollAmount(
            debt,
            priceFeedMock.getPrice(),
            COLLATERAL_RATIO_DEFENSIVE
        );
        bytes32 cdpId = borrowerOperations.openCdp{value: coll}(
            FEE,
            _utils.calculateBorrowAmountFromDebt(
                debt,
                cdpManager.EBTC_GAS_COMPENSATION(),
                cdpManager.getBorrowingRateWithDecay()
            ),
            bytes32(0),
            bytes32(0)
        );
        uint256 lqtyStakingBalanceOld = eBTCToken.balanceOf(address(lqtyStaking));
        assertGt(lqtyStakingBalanceOld, 0);
        uint balanceSnapshot = eBTCToken.balanceOf(users[0]);
        assertGt(balanceSnapshot, 0);

        // Fast-forward 1 year
        skip(365 days);
        cdpState = _getEntireDebtAndColl(cdpId);
        uint256 debtOld = cdpState.debt;
        // User decided to repay 10% of eBTC after 1 year. This should apply pending interest
        borrowerOperations.repayEBTC(
            cdpId,
            // Repay 10% of eBTC
            debt.div(10),
            HINT,
            HINT
        );
        // Make sure eBTC balance decreased
        assertEq(eBTCToken.balanceOf(users[0]), balanceSnapshot.sub(debt.div(10)));

        assertFalse(cdpManager.hasPendingRewards(cdpId));

        cdpState = _getEntireDebtAndColl(cdpId);
        assertEq(cdpState.pendingEBTCInterest, 0);
        // Make sure total debt decreased
        assertEq(cdpManager.getEntireSystemDebt(), debtOld.sub(debt.div(10)));
        // Make sure debt in active pool decreased by 10%
        assertEq(activePool.getEBTCDebt(), debtOld.sub(debt.div(10)));

        // Check interest is minted to LQTY staking contract
        assertApproxEqRel(
            eBTCToken.balanceOf(address(lqtyStaking)).sub(lqtyStakingBalanceOld),
            40e18,
            0.001e18
        ); // Error is <0.1% of the expected value

        // Make sure user's debt decreased and calculated as follows:
        // debt = debtOld - 10% of debtOld + 40e18 (interest)
        assertApproxEqRel(cdpState.debt, debt.sub(debt.div(10)).add(40e18), 0.01e18);
    }

    /**
    Confirm that interest is applied to a CDP when user closes their position
    */
    function testInterestIsAppliedCloseCdp() public {
        CdpState memory cdpState;
        vm.startPrank(users[0]);

        uint debt = 2000e18;
        uint256 coll = _utils.calculateCollAmount(
            debt,
            priceFeedMock.getPrice(),
            COLLATERAL_RATIO_DEFENSIVE
        );
        bytes32 cdpId = borrowerOperations.openCdp{value: coll}(
            FEE,
            _utils.calculateBorrowAmountFromDebt(
                debt,
                cdpManager.EBTC_GAS_COMPENSATION(),
                cdpManager.getBorrowingRateWithDecay()
            ),
            bytes32(0),
            bytes32(0)
        );
        // Borrow for the second time so user has enough eBTC to close their first CDP
        bytes32 cdpId2 = borrowerOperations.openCdp{value: coll}(
            FEE,
            _utils.calculateBorrowAmountFromDebt(
                debt,
                cdpManager.EBTC_GAS_COMPENSATION(),
                cdpManager.getBorrowingRateWithDecay()
            ),
            bytes32(0),
            bytes32(0)
        );
        uint256 lqtyStakingBalanceOld = eBTCToken.balanceOf(address(lqtyStaking));
        assertGt(lqtyStakingBalanceOld, 0);
        uint balanceSnapshot = eBTCToken.balanceOf(users[0]);

        // Fast-forward 1 year
        skip(365 days);
        uint256 debtOld = cdpManager.getEntireSystemDebt();
        // User decided to close first CDP after 1 year. This should apply pending interest
        borrowerOperations.closeCdp(cdpId);
        // Make sure eBTC balance decreased by debt of first CDP plus realized interest
        assertApproxEqRel(
            balanceSnapshot.sub(debt).sub(40e18),
            eBTCToken.balanceOf(users[0]),
            0.01e18
        );

        assertFalse(cdpManager.hasPendingRewards(cdpId));
        assertTrue(cdpManager.hasPendingRewards(cdpId2));

        cdpState = _getEntireDebtAndColl(cdpId);
        assertEq(cdpState.pendingEBTCInterest, 0);
        // Make sure user's debt is now 0
        assertEq(cdpState.debt, 0);

        // Check interest is minted to LQTY staking contract twice from both CDPs
        assertApproxEqRel(
            eBTCToken.balanceOf(address(lqtyStaking)).sub(lqtyStakingBalanceOld),
            80e18,
            0.001e18
        ); // Error is <0.1% of the expected value
    }

    /**
    Confirm that interest is applied to a CDP when user withdraws eBTC
    */
    function testInterestIsAppliedWithdrawEbtc() public {
        CdpState memory cdpState;
        vm.startPrank(users[0]);

        uint debt = 2000e18;
        uint256 coll = _utils.calculateCollAmount(
            debt,
            priceFeedMock.getPrice(),
            COLLATERAL_RATIO_DEFENSIVE
        );
        bytes32 cdpId = borrowerOperations.openCdp{value: coll}(
            FEE,
            _utils.calculateBorrowAmountFromDebt(
                debt,
                cdpManager.EBTC_GAS_COMPENSATION(),
                cdpManager.getBorrowingRateWithDecay()
            ),
            bytes32(0),
            bytes32(0)
        );
        uint256 lqtyStakingBalanceOld = eBTCToken.balanceOf(address(lqtyStaking));
        assertGt(lqtyStakingBalanceOld, 0);
        uint balanceSnapshot = eBTCToken.balanceOf(users[0]);
        assertGt(balanceSnapshot, 0);
        cdpState = _getEntireDebtAndColl(cdpId);
        uint256 debtOld = cdpState.debt;
        // Fast-forward 1 year
        skip(365 days);
        // Withdraw 1 eBTC after 1 year. This should apply pending interest
        borrowerOperations.withdrawEBTC(cdpId, FEE, 1e18, "hint", "hint");
        // Make sure eBTC balance increased by 1eBTC plus realized interest
        assertEq(balanceSnapshot.add(1e18), eBTCToken.balanceOf(users[0]));

        assertFalse(cdpManager.hasPendingRewards(cdpId));

        cdpState = _getEntireDebtAndColl(cdpId);
        assertEq(cdpState.pendingEBTCInterest, 0);
        // Make sure user's debt increased by 1eBTC plus realized interest
        assertApproxEqRel(
            debtOld.add(40e18).add(1e18),
            cdpState.debt,
            0.001e18
        );
        // Make sure total debt increased
        assertGt(cdpManager.getEntireSystemDebt(), debtOld);
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
        uint256 coll1 = _utils.calculateCollAmount(
            2000e18,
            priceFeedMock.getPrice(),
            COLLATERAL_RATIO_DEFENSIVE
        );

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
        assertApproxEqAbs(defaultPool.getEBTCDebt(), 0, 13202);
        assertEq(activePool.getEBTCDebt(), debtOld);

        // Check interest is minted to LQTY staking contract
        assertApproxEqRel(
            eBTCToken.balanceOf(address(lqtyStaking)).sub(lqtyStakingBalanceOld),
            120e18,
            0.002e18
        ); // Error is <0.2% of the expected value
    }

    ////////////////////////////////////////////////////////////////////////////
    // FUZZ
    ////////////////////////////////////////////////////////////////////////////
    /**
    Confirm that interest is applied to a CDP when user withdraws eBTC when passed FUZZ amount of time
    */
    function testFuzzInterestIsAppliedWithdrawEbtc(uint16 amntOfDays) public {
        CdpState memory cdpState;
        vm.startPrank(users[0]);
        uint debt = 2000e18;
        uint256 coll = _utils.calculateCollAmount(
            debt,
            priceFeedMock.getPrice(),
            COLLATERAL_RATIO_DEFENSIVE
        );
        bytes32 cdpId = borrowerOperations.openCdp{value: coll}(
            FEE,
            _utils.calculateBorrowAmountFromDebt(
                debt,
                cdpManager.EBTC_GAS_COMPENSATION(),
                cdpManager.getBorrowingRateWithDecay()
            ),
            bytes32(0),
            bytes32(0)
        );
        uint256 lqtyStakingBalanceOld = eBTCToken.balanceOf(address(lqtyStaking));
        assertGt(lqtyStakingBalanceOld, 0);
        uint balanceSnapshot = eBTCToken.balanceOf(users[0]);
        assertGt(balanceSnapshot, 0);
        // Make sure ICR is exactly COLLATERAL_RATIO_DEFENSIVE
        assertApproxEqRel(
            cdpManager.getCurrentICR(cdpId, priceFeedMock.getPrice()),
            COLLATERAL_RATIO_DEFENSIVE,
            1
        );
        // Fast-forward X amount of days
        skip(amntOfDays);
        uint256 debtOld = cdpState.debt;
        // Withdraw 1 eBTC after 1 year. This should apply pending interest
        borrowerOperations.withdrawEBTC(cdpId, FEE, 1e18, "hint", "hint");
        // Make sure ICR decreased as withdrew more eBTC
        assertLt(
            cdpManager.getCurrentICR(cdpId, priceFeedMock.getPrice()),
            COLLATERAL_RATIO_DEFENSIVE.sub(1)
        );
        // Make sure eBTC balance increased
        assertGt(eBTCToken.balanceOf(users[0]), balanceSnapshot);

        assertFalse(cdpManager.hasPendingRewards(cdpId));

        cdpState = _getEntireDebtAndColl(cdpId);
        assertEq(cdpState.pendingEBTCInterest, 0);
        // Make sure user's debt increased
        assertGt(cdpState.debt, debtOld);
        // Make sure total debt increased
        assertGt(cdpManager.getEntireSystemDebt(), debtOld);
        // Make sure that interest was applied
        assertGt(eBTCToken.balanceOf(address(lqtyStaking)), lqtyStakingBalanceOld);
    }

    /**
    Confirm that interest is applied to a CDP when user closes their position when passed FUZZ amount of time
    */
    function testFuzzInterestIsAppliedCloseCdp(uint16 amntOfDays) public {
        amntOfDays = uint16(bound(amntOfDays, 1, type(uint16).max));
        CdpState memory cdpState;
        vm.startPrank(users[0]);

        uint debt = 2000e18;
        uint256 coll = _utils.calculateCollAmount(
            debt,
            priceFeedMock.getPrice(),
            COLLATERAL_RATIO_DEFENSIVE
        );
        bytes32 cdpId = borrowerOperations.openCdp{value: coll}(
            FEE,
            _utils.calculateBorrowAmountFromDebt(
                debt,
                cdpManager.EBTC_GAS_COMPENSATION(),
                cdpManager.getBorrowingRateWithDecay()
            ),
            bytes32(0),
            bytes32(0)
        );
        // Borrow for the second time so user has enough eBTC to close their first CDP
        borrowerOperations.openCdp{value: coll}(
            FEE,
            _utils.calculateBorrowAmountFromDebt(
                debt,
                cdpManager.EBTC_GAS_COMPENSATION(),
                cdpManager.getBorrowingRateWithDecay()
            ),
            bytes32(0),
            bytes32(0)
        );
        uint256 lqtyStakingBalanceOld = eBTCToken.balanceOf(address(lqtyStaking));
        assertGt(lqtyStakingBalanceOld, 0);
        uint balanceSnapshot = eBTCToken.balanceOf(users[0]);
        assertGt(balanceSnapshot, 0);
        // Make sure ICR is exactly COLLATERAL_RATIO_DEFENSIVE
        assertApproxEqRel(
            cdpManager.getCurrentICR(cdpId, priceFeedMock.getPrice()),
            COLLATERAL_RATIO_DEFENSIVE,
            1
        );
        skip(amntOfDays);
        uint256 debtOld = cdpManager.getEntireSystemDebt();
        // User decided to close first CDP after 1 year. This should apply pending interest
        borrowerOperations.closeCdp(cdpId);
        // Make sure eBTC balance decreased
        assertLt(eBTCToken.balanceOf(users[0]), balanceSnapshot);

        cdpState = _getEntireDebtAndColl(cdpId);
        assertEq(cdpState.pendingEBTCInterest, 0);
        // Make sure user's debt is now 0
        assertEq(cdpState.debt, 0);
        // Make sure that interest was applied
        assertGt(eBTCToken.balanceOf(address(lqtyStaking)).sub(lqtyStakingBalanceOld), 0);
    }

    /**
    Confirm that interest is applied to a CDP when user repays eBTC after FUZZED amount of time
    */
    function testFuzzInterestIsAppliedRepayEbtc(uint16 amntOfDays) public {
        amntOfDays = uint16(bound(amntOfDays, 1, type(uint16).max));
        CdpState memory cdpState;
        vm.startPrank(users[0]);

        uint debt = 2000e18;
        uint256 coll = _utils.calculateCollAmount(
            debt,
            priceFeedMock.getPrice(),
            COLLATERAL_RATIO_DEFENSIVE
        );
        bytes32 cdpId = borrowerOperations.openCdp{value: coll}(
            FEE,
            _utils.calculateBorrowAmountFromDebt(
                debt,
                cdpManager.EBTC_GAS_COMPENSATION(),
                cdpManager.getBorrowingRateWithDecay()
            ),
            bytes32(0),
            bytes32(0)
        );
        uint256 lqtyStakingBalanceOld = eBTCToken.balanceOf(address(lqtyStaking));
        assertGt(lqtyStakingBalanceOld, 0);
        uint balanceSnapshot = eBTCToken.balanceOf(users[0]);
        assertGt(balanceSnapshot, 0);
        // Make sure ICR is exactly COLLATERAL_RATIO_DEFENSIVE
        assertApproxEqRel(
            cdpManager.getCurrentICR(cdpId, priceFeedMock.getPrice()),
            COLLATERAL_RATIO_DEFENSIVE,
            1
        );
        skip(amntOfDays);
        cdpState = _getEntireDebtAndColl(cdpId);
        uint256 debtOld = cdpState.debt;
        // User decided to repay 10%. This should apply pending interest
        borrowerOperations.repayEBTC(
            cdpId,
            // Repay 10% of eBTC
            debt.div(10),
            HINT,
            HINT
        );
        // Make sure eBTC balance decreased
        assertLt(eBTCToken.balanceOf(users[0]), balanceSnapshot);
        // Make sure ICR increased as user repaid eBTC back
        assertGt(
            cdpManager.getCurrentICR(cdpId, priceFeedMock.getPrice()),
            COLLATERAL_RATIO_DEFENSIVE
        );
        assertFalse(cdpManager.hasPendingRewards(cdpId));

        cdpState = _getEntireDebtAndColl(cdpId);
        assertEq(cdpState.pendingEBTCInterest, 0);
        // Make sure user's debt decreased
        assertLt(cdpState.debt, debtOld);
        // Make sure total debt decreased
        assertLt(cdpManager.getEntireSystemDebt(), debtOld);
        // Make sure debt in active pool decreased by 10%
        assertEq(activePool.getEBTCDebt(), debtOld.sub(debt.div(10)));

        // Check interest is minted to LQTY staking contract
        assertGt(eBTCToken.balanceOf(address(lqtyStaking)), lqtyStakingBalanceOld);
    }

    /**
        Confirm that interest is applied to a CDP when collateral is added by user after FUZZ amnt of time
    */
    function testFuzzInterestIsAppliedAddCollOps(uint16 amntOfDays) public {
        amntOfDays = uint16(bound(amntOfDays, 1, type(uint16).max));
        vm.startPrank(users[0]);
        uint256 coll = _utils.calculateCollAmount(
            2000e18,
            priceFeedMock.getPrice(),
            COLLATERAL_RATIO_DEFENSIVE
        );

        bytes32 cdpId0 = borrowerOperations.openCdp{value: coll}(
            5e17,
            _utils.calculateBorrowAmountFromDebt(
                2000e18,
                cdpManager.EBTC_GAS_COMPENSATION(),
                cdpManager.getBorrowingRateWithDecay()
            ),
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
        // Make sure ICR is exactly COLLATERAL_RATIO_DEFENSIVE
        assertApproxEqRel(
            cdpManager.getCurrentICR(cdpId0, priceFeedMock.getPrice()),
            COLLATERAL_RATIO_DEFENSIVE,
            1
        );
        skip(amntOfDays);

        // Has pending interest
        assertTrue(cdpManager.hasPendingRewards(cdpId0));

        cdpState = _getEntireDebtAndColl(cdpId0);
        uint256 debtOld = cdpState.debt;

        assertEq(cdpState.debt, cdpManager.getEntireSystemDebt());

        // Active pool only contains realized interest (no pending interest)
        assertEq(activePool.getEBTCDebt(), 2000e18);

        assertEq(eBTCToken.balanceOf(address(lqtyStaking)), lqtyStakingBalanceOld);

        // Apply pending interest
        borrowerOperations.addColl{value: 1000e18}(cdpId0, bytes32(0), bytes32(0));
        // Make sure ICR increased as user added collateral
        assertGt(
            cdpManager.getCurrentICR(cdpId0, priceFeedMock.getPrice()),
            COLLATERAL_RATIO_DEFENSIVE
        );
        assertFalse(cdpManager.hasPendingRewards(cdpId0));

        cdpState = _getEntireDebtAndColl(cdpId0);
        assertEq(cdpState.pendingEBTCInterest, 0);
        assertEq(cdpState.debt, debtOld);

        assertEq(cdpManager.getEntireSystemDebt(), debtOld);
        assertEq(activePool.getEBTCDebt(), debtOld);

        // Check interest is minted to LQTY staking contract
        assertGt(eBTCToken.balanceOf(address(lqtyStaking)), lqtyStakingBalanceOld);
    }

    /**
        Confirm that interest is applied to a CDP when collateral is removed by user after FUZZ amnt of time
    */
    function testFuzzInterestIsAppliedWithdrawCollOps(uint16 amntOfDays) public {
        amntOfDays = uint16(bound(amntOfDays, 1, type(uint16).max));
        vm.startPrank(users[0]);
        uint256 coll = _utils.calculateCollAmount(
            2000e18,
            priceFeedMock.getPrice(),
            COLLATERAL_RATIO_DEFENSIVE
        );
        bytes32 cdpId0 = borrowerOperations.openCdp{value: coll}(
            5e17,
            _utils.calculateBorrowAmountFromDebt(
                2000e18,
                cdpManager.EBTC_GAS_COMPENSATION(),
                cdpManager.getBorrowingRateWithDecay()
            ),
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
        // Make sure ICR is exactly COLLATERAL_RATIO_DEFENSIVE
        assertApproxEqRel(
            cdpManager.getCurrentICR(cdpId0, priceFeedMock.getPrice()),
            COLLATERAL_RATIO_DEFENSIVE,
            1
        );
        skip(amntOfDays);

        // Has pending interest
        assertTrue(cdpManager.hasPendingRewards(cdpId0));

        cdpState = _getEntireDebtAndColl(cdpId0);
        uint256 debtOld = cdpState.debt;
        // Make sure ICR decreased
        assertLt(
            cdpManager.getCurrentICR(cdpId0, priceFeedMock.getPrice()),
            COLLATERAL_RATIO_DEFENSIVE
        );

        assertEq(cdpState.debt, cdpManager.getEntireSystemDebt());

        // Active pool only contains realized interest (no pending interest)
        assertEq(activePool.getEBTCDebt(), 2000e18);

        assertEq(eBTCToken.balanceOf(address(lqtyStaking)), lqtyStakingBalanceOld);

        // Apply pending interest
        borrowerOperations.withdrawColl(cdpId0, 100e18, bytes32(0), bytes32(0));
        assertFalse(cdpManager.hasPendingRewards(cdpId0));

        cdpState = _getEntireDebtAndColl(cdpId0);
        assertEq(cdpState.pendingEBTCInterest, 0);
        assertEq(cdpState.debt, debtOld);

        assertEq(cdpManager.getEntireSystemDebt(), debtOld);
        assertEq(activePool.getEBTCDebt(), debtOld);

        // Check interest is minted to LQTY staking contract
        assertGt(eBTCToken.balanceOf(address(lqtyStaking)), lqtyStakingBalanceOld);
    }

    function testFuzzCalcUnitAmountAfterInterest(uint256 time) public {
        // After 150676588855, fpow will start failing with overflow
        // This means that if `_lastInterestRateUpdateTime` wasn't updated for ~47.85 years, `calcUnitAmountAfterInterest`
        // will fail with overflow
        if (time >= 150676588855) {
            vm.expectRevert();
            _liquityTester.calcUnitAmountAfterInterest(time);
        } else {
            uint256 result = _liquityTester.calcUnitAmountAfterInterest(time);
            assertGt(result, 0);
        }
    }
}
