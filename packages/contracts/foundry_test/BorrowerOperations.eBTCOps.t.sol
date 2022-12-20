// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.11;

import "forge-std/Test.sol";
import "../contracts/Dependencies/LiquityMath.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";
import {Utilities} from "./utils/Utilities.sol";

/*
 * Test suite that tests opened CDPs with two different operations: addColl and withdrawColl
 */
contract CDPOpsTest is eBTCBaseFixture {
    Utilities internal _utils;
    // Storage array of cdpIDs when impossible to calculate array size
    bytes32[] cdpIds;

    function setUp() public override {
        eBTCBaseFixture.setUp();
        eBTCBaseFixture.connectLQTYContracts();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();
        _utils = new Utilities();
    }

    // -------- Repay eBTC Test cases --------

    // Happy case for borrowing and repaying back eBTC which should result in increasing ICR
    function testRepayEBTCHappy() public {
        uint collAmount = 30 ether;
        address user = _utils.getNextUserAddress();
        vm.startPrank(user);
        vm.deal(user, type(uint96).max);
        uint borrowedAmount = _utils.calculateBorrowAmount(collAmount, priceFeedMock.fetchPrice(), COLLATERAL_RATIO);
        borrowerOperations.openCdp{value : collAmount}(FEE, borrowedAmount, HINT, HINT);
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        uint initialIcr = cdpManager.getCurrentICR(cdpId, priceFeedMock.fetchPrice());
        uint balanceSnapshot = eBTCToken.balanceOf(user);
        // Repay eBTC
        borrowerOperations.repayEBTC(
            cdpId,
            // Repay 10% of eBTC
            borrowedAmount.div(10),
            HINT, HINT
        );
        // Make sure eBTC balance decreased
        assertLt(eBTCToken.balanceOf(user), balanceSnapshot);
        // Make sure ICR for CDP improved after eBTC was repaid
        uint newIcr = cdpManager.getCurrentICR(cdpId, priceFeedMock.fetchPrice());
        assertGt(newIcr, initialIcr);
        vm.stopPrank();
    }

    // Fuzzing different amounts of eBTC repaid
    function testRepayEBTCFuzz(uint96 repayAmnt) public {
        repayAmnt = uint96(bound(repayAmnt, 1e18, type(uint96).max));
        // Coll amount will always be max of uint96
        uint collAmount = type(uint96).max;
        address user = _utils.getNextUserAddress();
        vm.startPrank(user);
        vm.deal(user, type(uint96).max);
        uint borrowedAmount = _utils.calculateBorrowAmount(collAmount, priceFeedMock.fetchPrice(), COLLATERAL_RATIO);
        borrowerOperations.openCdp{value : collAmount}(FEE, borrowedAmount, HINT, HINT);
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        uint initialIcr = cdpManager.getCurrentICR(cdpId, priceFeedMock.fetchPrice());
        uint balanceSnapshot = eBTCToken.balanceOf(user);
        // Repay eBTC
        borrowerOperations.repayEBTC(cdpId, repayAmnt, HINT, HINT);
        // Make sure eBTC balance decreased
        assertLt(eBTCToken.balanceOf(user), balanceSnapshot);
        // Make sure ICR for CDP improved after eBTC was repaid
        uint newIcr = cdpManager.getCurrentICR(cdpId, priceFeedMock.fetchPrice());
        assertGt(newIcr, initialIcr);
        vm.stopPrank();
    }

    // Repaying eBTC by multiple users for many CDPs with randomized collateral
    function testRepayEbtcManyUsersManyCdps() public {
        uint amountCdps = _utils.generateRandomNumber(1, 10, msg.sender);
        for (uint userIx = 0; userIx < AMOUNT_OF_USERS; userIx++) {
            address user = _utils.getNextUserAddress();
            vm.deal(user, 10100000 ether);
            // Random collateral for each user
            uint collAmount = _utils.generateRandomNumber(28 ether, 10000000 ether, user);
            uint collAmountChunk = collAmount.div(amountCdps);
            uint borrowedAmount = _utils.calculateBorrowAmount(
                collAmountChunk, priceFeedMock.fetchPrice(), COLLATERAL_RATIO
            );
            // Create multiple CDPs per user
            for (uint cdpIx = 0; cdpIx < amountCdps; cdpIx++) {
                vm.prank(user);
                borrowerOperations.openCdp{value : collAmountChunk}(FEE, borrowedAmount, HINT, HINT);
                cdpIds.push(sortedCdps.cdpOfOwnerByIndex(user, cdpIx));
            }
        }
        // Make TCR snapshot before increasing collateral
        uint initialTcr = LiquityMath._computeCR(
            borrowerOperations.getEntireSystemColl(),
            borrowerOperations.getEntireSystemDebt(),
            priceFeedMock.fetchPrice()
        );
        // Now, repay eBTC and make sure ICR improved
        for (uint cdpIx = 0; cdpIx < cdpIds.length; cdpIx++) {
            address user = sortedCdps.getOwnerAddress(cdpIds[cdpIx]);
            // Randomize ebtc repaid amnt from 10 eBTC to max ebtc.balanceOf(user) / amount of CDPs for user
            uint randRepayAmnt = _utils.generateRandomNumber(10e18, eBTCToken.balanceOf(user).div(amountCdps), user);
            uint initialIcr = cdpManager.getCurrentICR(cdpIds[cdpIx], priceFeedMock.fetchPrice());
            vm.prank(user);
            // Repay eBTC for each CDP
            borrowerOperations.repayEBTC(cdpIds[cdpIx], randRepayAmnt, HINT, HINT);
            uint newIcr = cdpManager.getCurrentICR(cdpIds[cdpIx], priceFeedMock.fetchPrice());
            // Make sure ICR for CDP increased
            assertGt(newIcr, initialIcr);
        }
        // Make sure TCR increased after eBTC was repaid
        uint newTcr = LiquityMath._computeCR(
            borrowerOperations.getEntireSystemColl(),
            borrowerOperations.getEntireSystemDebt(),
            priceFeedMock.fetchPrice()
        );
        assertGt(newTcr, initialTcr);
    }

    // -------- Withdraw eBTC Test cases --------

    // Simple Happy case for borrowing and withdrawing eBTC from CDP
    function testWithdrawEBTCHappy() public {
        uint collAmount = 30 ether;
        address user = _utils.getNextUserAddress();
        vm.deal(user, type(uint96).max);
        vm.startPrank(user);
        uint borrowedAmount = _utils.calculateBorrowAmount(
            collAmount, priceFeedMock.fetchPrice(), COLLATERAL_RATIO_DEFENSIVE
        );
        borrowerOperations.openCdp{value : collAmount}(FEE, borrowedAmount, HINT, HINT);
        // Take eBTC balance snapshot
        uint balanceSnapshot = eBTCToken.balanceOf(user);
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        // Get ICR for CDP:
        uint initialIcr = cdpManager.getCurrentICR(cdpId, priceFeedMock.fetchPrice());
        // Get initial Debt after opened CDP
        uint initialDebt = cdpManager.getCdpDebt(cdpId);
        // Withdraw 1 eBTC
        borrowerOperations.withdrawEBTC(cdpId, FEE, 1e18, "hint", "hint");
        // Make sure ICR decreased
        assertLt(cdpManager.getCurrentICR(cdpId, priceFeedMock.fetchPrice()), initialIcr);
        // Make sure debt increased
        assertGt(cdpManager.getCdpDebt(cdpId), initialDebt);
        // Make sure eBTC balance of user increased
        assertGt(eBTCToken.balanceOf(user), balanceSnapshot);
        vm.stopPrank();
    }

    // Fuzz for borrowing and withdrawing eBTC from CDP
    // Handle scenarios when users try to withdraw too much eBTC resulting in either ICR < MCR or TCR < CCR
    function testWithdrawEBTCFuzz(uint96 withdrawAmnt, uint96 collAmount) public {
        withdrawAmnt = uint96(bound(withdrawAmnt, 1e18, type(uint96).max));
        collAmount = uint96(bound(collAmount, 30e18, type(uint96).max));

        address user = _utils.getNextUserAddress();
        vm.deal(user, type(uint96).max);
        vm.startPrank(user);
        uint borrowedAmount = _utils.calculateBorrowAmount(
            collAmount, priceFeedMock.fetchPrice(), COLLATERAL_RATIO_DEFENSIVE
        );
        borrowerOperations.openCdp{value : collAmount}(FEE, borrowedAmount, HINT, HINT);
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        // Get ICR for CDP:
        uint initialIcr = cdpManager.getCurrentICR(cdpId, priceFeedMock.fetchPrice());
        // Get initial Debt after opened CDP
        uint initialDebt = cdpManager.getCdpDebt(cdpId);

        // Calculate projected ICR change
        uint projectedIcr = LiquityMath._computeCR(
            collAmount, initialDebt.add(withdrawAmnt), priceFeedMock.fetchPrice()
        );
        // Calculate projected TCR change with new debt added on top
        uint projectedSystemDebt = borrowerOperations.getEntireSystemDebt().add(withdrawAmnt);
        uint projectedTcr = LiquityMath._computeCR(
            borrowerOperations.getEntireSystemColl(),
            projectedSystemDebt,
            priceFeedMock.fetchPrice()
        );
        console.log(projectedTcr);
        // Make sure tx is reverted if user tries to make withdraw resulting in either TCR < CCR or ICR < MCR
        if (projectedTcr < CCR || projectedIcr < MINIMAL_COLLATERAL_RATIO) {
            vm.expectRevert();
            borrowerOperations.withdrawEBTC(cdpId, FEE, withdrawAmnt, "hint", "hint");
            return;
        }
        // Withdraw
        borrowerOperations.withdrawEBTC(cdpId, FEE, withdrawAmnt, "hint", "hint");
        // Make sure ICR decreased
        assertLt(cdpManager.getCurrentICR(cdpId, priceFeedMock.fetchPrice()), initialIcr);
        // Make sure debt increased
        assertGt(cdpManager.getCdpDebt(cdpId), initialDebt);
        vm.stopPrank();
    }
}

