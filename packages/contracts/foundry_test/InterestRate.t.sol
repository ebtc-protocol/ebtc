// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;
import {console2 as console} from "forge-std/console2.sol";

import {eBTCBaseFixture} from "./BaseFixture.sol";
import {LiquityBase} from "../contracts/Dependencies/LiquityBase.sol";

contract LiquityTester is LiquityBase {
    function calcUnitAmountAfterInterest(uint _time) public pure virtual returns (uint) {
        return _calcUnitAmountAfterInterest(_time);
    }
}

// TODO: Do an invariant test that total interest minted is equal to sum of all borrowers' interest
contract InterestRateTest is eBTCBaseFixture {
    event LTermsUpdated(uint _L_ETH, uint _L_EBTCDebt, uint _L_EBTCInterest);

    bytes32[] cdpIds;

    uint256 private testNumber;
    address payable[] users;

    LiquityTester internal _liquityTester;

    uint public constant DECIMAL_PRECISION = 1e18;

    ////////////////////////////////////////////////////////////////////////////
    // Tests
    ////////////////////////////////////////////////////////////////////////////

    function setUp() public override {
        eBTCBaseFixture.setUp();

        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();

        users = _utils.createUsers(3);
        _liquityTester = new LiquityTester();
        vm.deal(users[0], type(uint256).max);
        vm.startPrank(users[0]);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 10000000000000000000000000000 ether}();
        vm.stopPrank();
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

        bytes32 cdpId0 = borrowerOperations.openCdp(
            _utils.calculateBorrowAmountFromDebt(
                2000e18,
                cdpManager.EBTC_GAS_COMPENSATION(),
                cdpManager.getBorrowingRateWithDecay()
            ),
            bytes32(0),
            bytes32(0),
            coll
        );

        uint256 lqtyStakingBalanceOld = eBTCToken.balanceOf(address(feeRecipient));
        assertEq(lqtyStakingBalanceOld, 0);

        CdpState memory cdpState;
        cdpState = _getEntireDebtAndColl(cdpId0);
        assertEq(cdpState.debt, 2000e18);

        assertEq(cdpManager.getEntireSystemDebt(), 2000e18);
        assertEq(activePool.getEBTCDebt(), 2000e18);

        // Confirm no pending rewards before time has passed
        assertFalse(cdpManager.hasPendingRewards(cdpId0));
        uint nicrBefore = cdpManager.getNominalICR(cdpId0);
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

        assertEq(eBTCToken.balanceOf(address(feeRecipient)), lqtyStakingBalanceOld);
        vm.expectEmit(false, false, false, true);
        // Third parameter is the applied interest rate ~102%, first two params are 0 since no liquidations happened
        emit LTermsUpdated(0, 0, 1019986589312086194);
        // Apply pending interest
        borrowerOperations.addColl(cdpId0, bytes32(0), bytes32(0), 2000e18);
        // Make sure that NICR increased after user added more collateral
        assertLt(nicrBefore, cdpManager.getNominalICR(cdpId0));

        assertFalse(cdpManager.hasPendingRewards(cdpId0));

        cdpState = _getEntireDebtAndColl(cdpId0);
        assertEq(cdpState.pendingEBTCInterest, 0);
        assertEq(cdpState.debt, debtOld);

        assertEq(cdpManager.getEntireSystemDebt(), debtOld);
        assertEq(activePool.getEBTCDebt(), debtOld);

        // Check interest is minted to LQTY staking contract
        assertApproxEqRel(
            eBTCToken.balanceOf(address(feeRecipient)).sub(lqtyStakingBalanceOld),
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
        bytes32 cdpId0 = borrowerOperations.openCdp(
            _utils.calculateBorrowAmountFromDebt(
                2000e18,
                cdpManager.EBTC_GAS_COMPENSATION(),
                cdpManager.getBorrowingRateWithDecay()
            ),
            bytes32(0),
            bytes32(0),
            coll
        );
        uint256 lqtyStakingBalanceOld = eBTCToken.balanceOf(address(feeRecipient));
        assertEq(lqtyStakingBalanceOld, 0);

        CdpState memory cdpState;
        cdpState = _getEntireDebtAndColl(cdpId0);
        assertEq(cdpState.debt, 2000e18);

        assertEq(cdpManager.getEntireSystemDebt(), 2000e18);
        assertEq(activePool.getEBTCDebt(), 2000e18);

        // Confirm no pending rewards before time has passed
        assertFalse(cdpManager.hasPendingRewards(cdpId0));
        uint nicrBefore = cdpManager.getNominalICR(cdpId0);
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

        assertEq(eBTCToken.balanceOf(address(feeRecipient)), lqtyStakingBalanceOld);

        vm.expectEmit(false, false, false, true);
        // Third parameter is the applied interest rate ~102%, first two params are 0 since no liquidations happened
        emit LTermsUpdated(0, 0, 1019986589312086194);
        // Apply pending interest
        borrowerOperations.withdrawColl(cdpId0, 1e17, bytes32(0), bytes32(0));
        // Make sure that NICR decreased after user withdrew collateral
        assertGt(nicrBefore, cdpManager.getNominalICR(cdpId0));
        assertFalse(cdpManager.hasPendingRewards(cdpId0));

        cdpState = _getEntireDebtAndColl(cdpId0);
        assertEq(cdpState.pendingEBTCInterest, 0);
        assertEq(cdpState.debt, debtOld);

        assertEq(cdpManager.getEntireSystemDebt(), debtOld);
        assertEq(activePool.getEBTCDebt(), debtOld);

        // Check interest is minted to LQTY staking contract
        assertApproxEqRel(
            eBTCToken.balanceOf(address(feeRecipient)).sub(lqtyStakingBalanceOld),
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
        bytes32 cdpId = borrowerOperations.openCdp(
            _utils.calculateBorrowAmountFromDebt(
                debt,
                cdpManager.EBTC_GAS_COMPENSATION(),
                cdpManager.getBorrowingRateWithDecay()
            ),
            bytes32(0),
            bytes32(0),
            coll
        );
        uint256 lqtyStakingBalanceOld = eBTCToken.balanceOf(address(feeRecipient));
        assertEq(lqtyStakingBalanceOld, 0);
        uint balanceSnapshot = eBTCToken.balanceOf(users[0]);

        // Fast-forward 1 year
        skip(365 days);
        cdpState = _getEntireDebtAndColl(cdpId);
        uint256 debtOld = cdpState.debt;
        vm.expectEmit(false, false, false, true);
        // Third parameter is the applied interest rate ~102%, first two params are 0 since no liquidations happened
        emit LTermsUpdated(0, 0, 1019986589312086194);
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
            eBTCToken.balanceOf(address(feeRecipient)).sub(lqtyStakingBalanceOld),
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
        bytes32 cdpId = borrowerOperations.openCdp(
            _utils.calculateBorrowAmountFromDebt(
                debt,
                cdpManager.EBTC_GAS_COMPENSATION(),
                cdpManager.getBorrowingRateWithDecay()
            ),
            bytes32(0),
            bytes32(0),
            coll
        );
        // Borrow for the second time so user has enough eBTC to close their first CDP
        bytes32 cdpId2 = borrowerOperations.openCdp(
            _utils.calculateBorrowAmountFromDebt(
                debt,
                cdpManager.EBTC_GAS_COMPENSATION(),
                cdpManager.getBorrowingRateWithDecay()
            ),
            bytes32(0),
            bytes32(0),
            coll
        );
        // Make balance snapshot to make sure that user's balance increased after closing CDP
        uint ethSnapshot = collateral.balanceOf((users[0]));

        uint256 lqtyStakingBalanceOld = eBTCToken.balanceOf(address(feeRecipient));
        assertEq(lqtyStakingBalanceOld, 0);
        uint balanceSnapshot = eBTCToken.balanceOf(users[0]);
        uint icrSnapshot = cdpManager.getCurrentICR(cdpId2, priceFeedMock.getPrice());
        // Fast-forward 1 year
        skip(365 days);
        uint256 debtOld = cdpManager.getEntireSystemDebt();
        vm.expectEmit(false, false, false, true);
        // Third parameter is the applied interest rate ~102%, first two params are 0 since no liquidations happened
        emit LTermsUpdated(0, 0, 1019986589312086194);
        // User decided to close first CDP after 1 year. This should apply pending interest
        borrowerOperations.closeCdp(cdpId);
        // Make sure that ICR for second CDP decreased after interest ticked and interest was realized against second CDP
        assertLt(cdpManager.getCurrentICR(cdpId2, priceFeedMock.getPrice()), icrSnapshot);
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
            eBTCToken.balanceOf(address(feeRecipient)).sub(lqtyStakingBalanceOld),
            80e18,
            0.001e18
        ); // Error is <0.1% of the expected value
        // Check that user ETH balance increased specifically by CDP.eth withdrawn value
        assertEq(ethSnapshot.add(coll), collateral.balanceOf((users[0])));
    }

    /**
    Confirm that after interest compounds, it won't be possible to withdraw coll as ICR decreases over time
    Opens N identical CDPs to make sure TCR is too high if one CDP decides to withdraw a lot
    */
    function testInterestIsAppliedImpactsICRAndDoesntAllowWithdraw() public {
        CdpState memory cdpState1;
        CdpState memory cdpState2;
        uint debt = 2000e18;

        // eBTC amount that does not revert before interest is applied but reverts after interest is applied
        uint sweetSpotDebt = 890e18;

        uint256 coll = _utils.calculateCollAmount(debt, priceFeedMock.getPrice(), COLLATERAL_RATIO);
        // Open N identical CDPs
        for (uint userIx = 0; userIx < AMOUNT_OF_USERS; userIx++) {
            address user = _utils.getNextUserAddress();
            vm.deal(user, type(uint256).max);
            vm.startPrank(user);
            collateral.approve(address(borrowerOperations), type(uint256).max);
            collateral.deposit{value: 10000000000000000000000000000 ether}();
            bytes32 cdpId = borrowerOperations.openCdp(debt, bytes32(0), bytes32(0), coll);
            cdpIds.push(cdpId);
            vm.stopPrank();
        }
        bytes32 benchmarkCdpId = cdpIds[0];
        bytes32 triggerCdpId = cdpIds[1];
        bytes32 testedCdpId = cdpIds[2];
        // Withdraw some eBTC to make sure it won't revert:
        address user0 = sortedCdps.getOwnerAddress(cdpIds[0]);
        vm.prank(user0);
        borrowerOperations.withdrawEBTC(benchmarkCdpId, sweetSpotDebt, "hint", "hint");
        uint icrSnapshot = cdpManager.getCurrentICR(testedCdpId, priceFeedMock.getPrice());
        // Fast-forward 1 year
        skip(365 days);
        // Repay some eBTC to trigger tick interest
        address user1 = sortedCdps.getOwnerAddress(triggerCdpId);
        vm.prank(user1);
        borrowerOperations.repayEBTC(
            triggerCdpId,
            // Repay 25% of eBTC of cdp3
            debt.div(4),
            HINT,
            HINT
        );

        // Make sure that ICR for second CDP decreased after interest ticked and interest was realized against second CDP
        assertLt(cdpManager.getCurrentICR(testedCdpId, priceFeedMock.getPrice()), icrSnapshot);

        // Try to withdrwaw eBTC: that will result in ICR decrease below ICR floor
        address user2 = sortedCdps.getOwnerAddress(testedCdpId);
        vm.prank(user2);
        vm.expectRevert(
            bytes("BorrowerOps: An operation that would result in ICR < MCR is not permitted")
        );
        borrowerOperations.withdrawEBTC(testedCdpId, sweetSpotDebt, "hint", "hint");
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
        bytes32 cdpId = borrowerOperations.openCdp(
            _utils.calculateBorrowAmountFromDebt(
                debt,
                cdpManager.EBTC_GAS_COMPENSATION(),
                cdpManager.getBorrowingRateWithDecay()
            ),
            bytes32(0),
            bytes32(0),
            coll
        );
        uint256 lqtyStakingBalanceOld = eBTCToken.balanceOf(address(feeRecipient));
        assertEq(lqtyStakingBalanceOld, 0);
        uint balanceSnapshot = eBTCToken.balanceOf(users[0]);
        cdpState = _getEntireDebtAndColl(cdpId);
        uint256 debtOld = cdpState.debt;
        uint nicrBefore = cdpManager.getNominalICR(cdpId);

        // Fast-forward 1 year
        skip(365 days);
        vm.expectEmit(false, false, false, true);
        // Third parameter is the applied interest rate ~102%, first two params are 0 since no liquidations happened
        emit LTermsUpdated(0, 0, 1019986589312086194);
        // Withdraw 1 eBTC after 1 year. This should apply pending interest
        borrowerOperations.withdrawEBTC(cdpId, 1e18, "hint", "hint");
        // Make sure eBTC balance increased by 1eBTC
        assertEq(balanceSnapshot.add(1e18), eBTCToken.balanceOf(users[0]));
        // Make sure that NICR decreased after user withdrew eBTC
        assertGt(nicrBefore, cdpManager.getNominalICR(cdpId));

        assertFalse(cdpManager.hasPendingRewards(cdpId));

        cdpState = _getEntireDebtAndColl(cdpId);
        assertEq(cdpState.pendingEBTCInterest, 0);
        // Make sure user's debt increased by 1eBTC plus realized interest
        assertApproxEqRel(debtOld.add(40e18).add(1e18), cdpState.debt, 0.001e18);
        // Make sure total debt increased
        assertApproxEqRel(debtOld.add(40e18).add(1e18), cdpManager.getEntireSystemDebt(), 0.001e18);
        // Check interest is minted to LQTY staking contract
        assertApproxEqRel(
            eBTCToken.balanceOf(address(feeRecipient)).sub(lqtyStakingBalanceOld),
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
        vm.deal(address(this), type(uint256).max);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 1000000000000 ether}();
        bytes32 cdpId0 = borrowerOperations.openCdp(2e18, bytes32(0), bytes32(0), 100 ether);
        bytes32 cdpId1 = borrowerOperations.openCdp(2e18, bytes32(0), bytes32(0), 100 ether);
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
        borrowerOperations.addColl(cdpId0, bytes32(0), bytes32(0), 1);

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
        borrowerOperations.addColl(cdpId0, bytes32(0), bytes32(0), 1);

        (debt0, , , pendingInterest0, ) = cdpManager.getEntireDebtAndColl(cdpId0);
        assertEq(pendingInterest0, 0);
        // TODO: Check why loss of precision
        assertApproxEqAbs(debt0, debt1, 1);
    }

    // TODO since liquidation is changed to external liquidator, this test might need some adaptation
    function testInterestIsAppliedOnRedistributedDebt() public {
        vm.deal(address(this), type(uint256).max);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 1000000000000 ether}();
        uint256 coll0 = _utils.calculateCollAmount(4000e18, priceFeedMock.getPrice(), 300e16);
        uint256 coll1 = _utils.calculateCollAmount(
            2000e18,
            priceFeedMock.getPrice(),
            COLLATERAL_RATIO_DEFENSIVE
        );

        bytes32 cdpId0 = borrowerOperations.openCdp(
            _utils.calculateBorrowAmountFromDebt(
                4000e18,
                cdpManager.EBTC_GAS_COMPENSATION(),
                cdpManager.getBorrowingRateWithDecay()
            ),
            bytes32(0),
            bytes32(0),
            coll0
        );
        bytes32 cdpId1 = borrowerOperations.openCdp(
            _utils.calculateBorrowAmountFromDebt(
                2000e18,
                cdpManager.EBTC_GAS_COMPENSATION(),
                cdpManager.getBorrowingRateWithDecay()
            ),
            bytes32(0),
            bytes32(0),
            coll1
        );

        assertFalse(cdpManager.hasPendingRewards(cdpId0));

        // Price falls from 7428e13 to 3000e13
        priceFeedMock.setPrice(3000 * 1e13);

        // Liquidate cdp1
        deal(address(eBTCToken), users[0], cdpManager.getCdpDebt(cdpId1));
        vm.prank(users[0]);
        cdpManager.liquidate(cdpId1);

        // no pending redistribution since no time has passed
        assertFalse(cdpManager.hasPendingRewards(cdpId0));

        // Now ~half of cdp0's debt is pending and in the default pool
        CdpState memory cdpState;
        cdpState = _getEntireDebtAndColl(cdpId0);

        // Check if pending debt/coll is correct
        // Some loss of precision due to rounding
        assertApproxEqRel(cdpState.pendingEBTCDebtReward, 0, 0.01e18); //2000e18, 0.01e18);
        assertApproxEqRel(cdpState.pendingETHReward, 0, 0.01e18); //coll1, 0.01e18);

        assertApproxEqRel(cdpState.coll, coll0, 0.01e18); //coll0.add(coll1), 0.01e18);
        assertApproxEqRel(
            cdpState.debt,
            4000e18, //6000e18, // debt0 + debt1
            0.01e18
        );

        // No interest since no time has passed
        assertEq(cdpState.pendingEBTCInterest, 0);

        assertEq(cdpManager.getEntireSystemDebt(), 4000e18); //6000e18);
        assertEq(defaultPool.getEBTCDebt(), 0); //2000e18);

        uint256 lqtyStakingBalanceOld = eBTCToken.balanceOf(address(feeRecipient));

        skip(365 days);

        // Expected interest over a year is 2%
        cdpState = _getEntireDebtAndColl(cdpId0);
        assertApproxEqRel(
            cdpState.pendingEBTCDebtReward,
            0, //2040e18, // ~2% over a year 2000e18
            0.01e18
        );
        assertApproxEqRel(
            cdpState.pendingEBTCInterest,
            80e18, // ~2% over a year on 4000e18
            0.02e18
        );
        assertApproxEqRel(
            cdpState.debt,
            4080e18, //6120e18, // ~2% over a year
            0.01e18
        );

        // TODO: Check if precision loss can lead to issues. Can it be avoided?
        assertApproxEqRel(cdpState.debt, cdpManager.getEntireSystemDebt(), 2);

        // Default pool only contains realized interest (no pending interest)
        assertEq(defaultPool.getEBTCDebt(), 0); //2000e18);

        uint256 debtOld = cdpState.debt;

        // Apply pending interest
        borrowerOperations.addColl(cdpId0, bytes32(0), bytes32(0), 100e18);

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
            eBTCToken.balanceOf(address(feeRecipient)).sub(lqtyStakingBalanceOld),
            80e18, //120e18,
            0.001e18
        ); // Error is <0.1% of the expected value
    }

    ////////////////////////////////////////////////////////////////////////////
    // FUZZ
    ////////////////////////////////////////////////////////////////////////////
    /**
    Confirm that interest is applied to a CDP when user withdraws eBTC when passed FUZZ amount of time
    */
    function testFuzzInterestIsAppliedWithdrawEbtc(uint16 amntOfDays, uint96 debt) public {
        vm.assume(amntOfDays > 1);
        vm.assume(amntOfDays < type(uint16).max);

        vm.assume(debt > 100e18);
        vm.assume(debt < 20000e18);
        CdpState memory cdpState;
        vm.startPrank(users[0]);
        uint256 coll = _utils.calculateCollAmount(
            debt,
            priceFeedMock.getPrice(),
            COLLATERAL_RATIO_DEFENSIVE
        );
        bytes32 cdpId = borrowerOperations.openCdp(
            _utils.calculateBorrowAmountFromDebt(
                debt,
                cdpManager.EBTC_GAS_COMPENSATION(),
                cdpManager.getBorrowingRateWithDecay()
            ),
            bytes32(0),
            bytes32(0),
            coll
        );
        uint256 lqtyStakingBalanceOld = eBTCToken.balanceOf(address(feeRecipient));
        assertEq(lqtyStakingBalanceOld, 0);
        uint balanceSnapshot = eBTCToken.balanceOf(users[0]);
        // Make sure ICR is exactly COLLATERAL_RATIO_DEFENSIVE
        assertApproxEqRel(
            cdpManager.getCurrentICR(cdpId, priceFeedMock.getPrice()),
            COLLATERAL_RATIO_DEFENSIVE,
            1
        );
        uint nicrBefore = cdpManager.getNominalICR(cdpId);
        cdpState = _getEntireDebtAndColl(cdpId);
        uint256 debtOld = cdpState.debt;
        // Fast-forward X amount of days
        skip(amntOfDays);

        // Withdraw 1 eBTC after N amnt of time. This should apply pending interest
        borrowerOperations.withdrawEBTC(cdpId, 1e16, "hint", "hint");
        // Make sure ICR decreased as withdrew more eBTC
        assertLt(
            cdpManager.getCurrentICR(cdpId, priceFeedMock.getPrice()),
            COLLATERAL_RATIO_DEFENSIVE.sub(1)
        );
        // Make sure NICR decreased
        assertGt(nicrBefore, cdpManager.getNominalICR(cdpId));

        // Make sure eBTC balance increased
        assertApproxEqRel(eBTCToken.balanceOf(users[0]), balanceSnapshot.add(1e16), 1);

        assertFalse(cdpManager.hasPendingRewards(cdpId));

        cdpState = _getEntireDebtAndColl(cdpId);
        assertEq(cdpState.pendingEBTCInterest, 0);
        // Make sure user's debt increased
        assertApproxEqRel(debtOld.add(1e16), cdpState.debt, 0.001e18);
        // Make sure total debt increased
        assertApproxEqRel(debtOld.add(1e16), cdpManager.getEntireSystemDebt(), 0.001e18);
        // Make sure that interest was applied
        assertGt(eBTCToken.balanceOf(address(feeRecipient)), lqtyStakingBalanceOld);
    }

    /**
    Confirm that interest is applied to a CDP when user closes their position when passed FUZZ amount of time
    */
    function testFuzzInterestIsAppliedCloseCdp(uint16 amntOfDays, uint96 debt) public {
        vm.assume(amntOfDays > 1);
        vm.assume(amntOfDays < type(uint16).max);

        vm.assume(debt > 100e18);
        vm.assume(debt < 20000e18);
        CdpState memory cdpState;
        vm.startPrank(users[0]);

        uint256 coll = _utils.calculateCollAmount(
            debt,
            priceFeedMock.getPrice(),
            COLLATERAL_RATIO_DEFENSIVE
        );
        bytes32 cdpId = borrowerOperations.openCdp(
            _utils.calculateBorrowAmountFromDebt(
                debt,
                cdpManager.EBTC_GAS_COMPENSATION(),
                cdpManager.getBorrowingRateWithDecay()
            ),
            bytes32(0),
            bytes32(0),
            coll
        );
        // Borrow for the second time so user has enough eBTC to close their first CDP
        borrowerOperations.openCdp(
            _utils.calculateBorrowAmountFromDebt(
                debt,
                cdpManager.EBTC_GAS_COMPENSATION(),
                cdpManager.getBorrowingRateWithDecay()
            ),
            bytes32(0),
            bytes32(0),
            coll
        );
        uint256 lqtyStakingBalanceOld = eBTCToken.balanceOf(address(feeRecipient));
        assertEq(lqtyStakingBalanceOld, 0);
        uint balanceSnapshot = eBTCToken.balanceOf(users[0]);
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
        cdpState = _getEntireDebtAndColl(cdpId);

        assertApproxEqRel(
            eBTCToken.balanceOf(users[0]),
            balanceSnapshot.sub(debt).sub(cdpState.pendingEBTCInterest),
            0.01e18
        );
        assertEq(cdpState.pendingEBTCInterest, 0);
        // Make sure user's debt is now 0
        assertEq(cdpState.debt, 0);
        // Make sure that interest was applied
        assertGt(eBTCToken.balanceOf(address(feeRecipient)).sub(lqtyStakingBalanceOld), 0);
    }

    /**
    Confirm that interest is applied to a CDP when user repays eBTC after FUZZED amount of time
    */
    function testFuzzInterestIsAppliedRepayEbtc(uint16 amntOfDays, uint96 debt) public {
        vm.assume(amntOfDays > 1);
        vm.assume(amntOfDays < type(uint16).max);

        vm.assume(debt > 100e18);
        vm.assume(debt < 20000e18);
        CdpState memory cdpState;
        vm.startPrank(users[0]);

        uint256 coll = _utils.calculateCollAmount(
            debt,
            priceFeedMock.getPrice(),
            COLLATERAL_RATIO_DEFENSIVE
        );
        bytes32 cdpId = borrowerOperations.openCdp(
            _utils.calculateBorrowAmountFromDebt(
                debt,
                cdpManager.EBTC_GAS_COMPENSATION(),
                cdpManager.getBorrowingRateWithDecay()
            ),
            bytes32(0),
            bytes32(0),
            coll
        );
        uint256 lqtyStakingBalanceOld = eBTCToken.balanceOf(address(feeRecipient));
        assertEq(lqtyStakingBalanceOld, 0);
        uint balanceSnapshot = eBTCToken.balanceOf(users[0]);
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
        assertEq(eBTCToken.balanceOf(users[0]), balanceSnapshot.sub(debt.div(10)));
        // Make sure ICR increased as user repaid eBTC back
        assertGt(
            cdpManager.getCurrentICR(cdpId, priceFeedMock.getPrice()),
            COLLATERAL_RATIO_DEFENSIVE
        );
        assertFalse(cdpManager.hasPendingRewards(cdpId));

        cdpState = _getEntireDebtAndColl(cdpId);
        assertEq(cdpState.pendingEBTCInterest, 0);
        // Make sure user's debt decreased
        assertEq(cdpState.debt, debtOld.sub(debt.div(10)));
        // Make sure total debt decreased
        assertEq(cdpManager.getEntireSystemDebt(), debtOld.sub(debt.div(10)));
        // Make sure debt in active pool decreased by 10%
        assertEq(activePool.getEBTCDebt(), debtOld.sub(debt.div(10)));

        // Check interest is minted to LQTY staking contract
        assertGt(eBTCToken.balanceOf(address(feeRecipient)), lqtyStakingBalanceOld);
    }

    /**
        Confirm that interest is applied to a CDP when collateral is added by user after FUZZ amnt of time
    */
    function testFuzzInterestIsAppliedAddCollOps(uint16 amntOfDays, uint96 debt) public {
        vm.assume(amntOfDays > 1);
        vm.assume(amntOfDays < type(uint16).max);

        vm.assume(debt > 100e18);
        vm.assume(debt < 20000e18);
        vm.startPrank(users[0]);

        uint256 coll = _utils.calculateCollAmount(
            debt,
            priceFeedMock.getPrice(),
            COLLATERAL_RATIO_DEFENSIVE
        );

        bytes32 cdpId0 = borrowerOperations.openCdp(
            _utils.calculateBorrowAmountFromDebt(
                debt,
                cdpManager.EBTC_GAS_COMPENSATION(),
                cdpManager.getBorrowingRateWithDecay()
            ),
            bytes32(0),
            bytes32(0),
            coll
        );

        uint256 lqtyStakingBalanceOld = eBTCToken.balanceOf(address(feeRecipient));
        assertEq(lqtyStakingBalanceOld, 0);

        CdpState memory cdpState;
        cdpState = _getEntireDebtAndColl(cdpId0);
        assertApproxEqRel(cdpState.debt, debt, 1);
        assertApproxEqRel(cdpManager.getEntireSystemDebt(), debt, 1);
        assertApproxEqRel(activePool.getEBTCDebt(), debt, 1);

        // Confirm no pending rewards before time has passed
        assertFalse(cdpManager.hasPendingRewards(cdpId0));
        // Make sure ICR is exactly COLLATERAL_RATIO_DEFENSIVE
        assertApproxEqRel(
            cdpManager.getCurrentICR(cdpId0, priceFeedMock.getPrice()),
            COLLATERAL_RATIO_DEFENSIVE,
            1
        );
        uint nicrBefore = cdpManager.getNominalICR(cdpId0);
        skip(amntOfDays);

        // Has pending interest
        assertTrue(cdpManager.hasPendingRewards(cdpId0));

        cdpState = _getEntireDebtAndColl(cdpId0);
        uint256 debtOld = cdpState.debt;

        assertEq(cdpState.debt, cdpManager.getEntireSystemDebt());

        // Active pool only contains realized interest (no pending interest)
        assertApproxEqRel(activePool.getEBTCDebt(), debt, 1);

        // Apply pending interest
        borrowerOperations.addColl(cdpId0, bytes32(0), bytes32(0), 1000e18);
        // Make sure ICR increased as user added collateral
        assertGt(
            cdpManager.getCurrentICR(cdpId0, priceFeedMock.getPrice()),
            COLLATERAL_RATIO_DEFENSIVE
        );
        // Make sure NICR increased
        assertLt(nicrBefore, cdpManager.getNominalICR(cdpId0));

        assertFalse(cdpManager.hasPendingRewards(cdpId0));

        cdpState = _getEntireDebtAndColl(cdpId0);
        assertEq(cdpState.pendingEBTCInterest, 0);
        assertEq(cdpState.debt, debtOld);

        assertEq(cdpManager.getEntireSystemDebt(), debtOld);
        assertEq(activePool.getEBTCDebt(), debtOld);

        // Check interest is minted to LQTY staking contract
        assertGt(eBTCToken.balanceOf(address(feeRecipient)), lqtyStakingBalanceOld);
    }

    /**
        Confirm that interest is applied to a CDP when collateral is removed by user after FUZZ amnt of time
    */
    function testFuzzInterestIsAppliedWithdrawCollOps(uint16 amntOfDays, uint96 debt) public {
        vm.assume(amntOfDays > 1);
        vm.assume(amntOfDays < type(uint16).max);

        vm.assume(debt > 100e18);
        vm.assume(debt < 20000e18);
        vm.startPrank(users[0]);
        uint256 coll = _utils.calculateCollAmount(
            debt,
            priceFeedMock.getPrice(),
            COLLATERAL_RATIO_DEFENSIVE
        );
        bytes32 cdpId0 = borrowerOperations.openCdp(
            _utils.calculateBorrowAmountFromDebt(
                debt,
                cdpManager.EBTC_GAS_COMPENSATION(),
                cdpManager.getBorrowingRateWithDecay()
            ),
            bytes32(0),
            bytes32(0),
            coll
        );
        uint256 lqtyStakingBalanceOld = eBTCToken.balanceOf(address(feeRecipient));
        assertEq(lqtyStakingBalanceOld, 0);

        CdpState memory cdpState;
        cdpState = _getEntireDebtAndColl(cdpId0);
        assertApproxEqRel(cdpState.debt, debt, 1);
        assertApproxEqRel(cdpManager.getEntireSystemDebt(), debt, 1);
        assertApproxEqRel(activePool.getEBTCDebt(), debt, 1);

        // Confirm no pending rewards before time has passed
        assertFalse(cdpManager.hasPendingRewards(cdpId0));
        // Make sure ICR is exactly COLLATERAL_RATIO_DEFENSIVE
        assertApproxEqRel(
            cdpManager.getCurrentICR(cdpId0, priceFeedMock.getPrice()),
            COLLATERAL_RATIO_DEFENSIVE,
            1
        );
        uint nicrBefore = cdpManager.getNominalICR(cdpId0);
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

        // Make sure NICR decreased
        assertGt(nicrBefore, cdpManager.getNominalICR(cdpId0));

        assertEq(cdpState.debt, cdpManager.getEntireSystemDebt());

        // Active pool only contains realized interest (no pending interest)
        assertApproxEqRel(activePool.getEBTCDebt(), debt, 1);

        assertEq(eBTCToken.balanceOf(address(feeRecipient)), lqtyStakingBalanceOld);

        // Apply pending interest
        borrowerOperations.withdrawColl(cdpId0, 1e18, bytes32(0), bytes32(0));
        assertFalse(cdpManager.hasPendingRewards(cdpId0));

        cdpState = _getEntireDebtAndColl(cdpId0);
        assertEq(cdpState.pendingEBTCInterest, 0);
        assertEq(cdpState.debt, debtOld);

        assertEq(cdpManager.getEntireSystemDebt(), debtOld);
        assertEq(activePool.getEBTCDebt(), debtOld);

        // Check interest is minted to LQTY staking contract
        assertGt(eBTCToken.balanceOf(address(feeRecipient)), lqtyStakingBalanceOld);
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
