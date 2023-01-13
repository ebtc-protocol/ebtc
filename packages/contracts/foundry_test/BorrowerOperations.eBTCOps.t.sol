// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.11;

import "forge-std/Test.sol";
import "../contracts/Dependencies/LiquityMath.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";
import {Utilities} from "./utils/Utilities.sol";

/*
 * Test suite that tests opened CDPs with two different operations: repayEBTC and withdrawEBTC
 * Test include testing different metrics such as each CDP ICR, also TCR changes after operations are executed
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
        uint borrowedAmount = _utils.calculateBorrowAmount(
            collAmount,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );
        borrowerOperations.openCdp{value: collAmount}(FEE, borrowedAmount, HINT, HINT);
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        uint initialIcr = cdpManager.getCurrentICR(cdpId, priceFeedMock.fetchPrice());
        uint balanceSnapshot = eBTCToken.balanceOf(user);
        // Repay eBTC
        borrowerOperations.repayEBTC(
            cdpId,
            // Repay 10% of eBTC
            borrowedAmount.div(10),
            HINT,
            HINT
        );
        // Make sure eBTC balance decreased
        assertLt(eBTCToken.balanceOf(user), balanceSnapshot);
        // Make sure ICR for CDP improved after eBTC was repaid
        uint newIcr = cdpManager.getCurrentICR(cdpId, priceFeedMock.fetchPrice());
        assertGt(newIcr, initialIcr);
        vm.stopPrank();
    }

    // Case when trying to repay 0 eBTC
    function testRepayWithZeroAmnt() public {
        uint collAmount = 30 ether;
        address user = _utils.getNextUserAddress();
        vm.startPrank(user);
        vm.deal(user, type(uint96).max);
        uint borrowedAmount = _utils.calculateBorrowAmount(
            collAmount,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );
        borrowerOperations.openCdp{value: collAmount}(FEE, borrowedAmount, HINT, HINT);
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        // Repay eBTC and make sure it reverts for 0 amount
        vm.expectRevert(
            bytes("BorrowerOps: There must be either a collateral change or a debt change")
        );
        borrowerOperations.repayEBTC(cdpId, 0, HINT, HINT);
        vm.stopPrank();
    }

    // Fuzzing different amounts of eBTC repaid
    function testRepayEBTCFuzz(uint96 repayAmnt) public {
        repayAmnt = uint96(bound(repayAmnt, 1e13, type(uint96).max));
        // Coll amount will always be max of uint96
        uint collAmount = type(uint96).max;
        address user = _utils.getNextUserAddress();
        vm.startPrank(user);
        vm.deal(user, type(uint96).max);
        uint borrowedAmount = _utils.calculateBorrowAmount(
            collAmount,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );
        borrowerOperations.openCdp{value: collAmount}(FEE, borrowedAmount, HINT, HINT);
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        uint initialIcr = cdpManager.getCurrentICR(cdpId, priceFeedMock.fetchPrice());
        uint balanceSnapshot = eBTCToken.balanceOf(user);
        // Repay eBTC
        borrowerOperations.repayEBTC(cdpId, repayAmnt, HINT, HINT);
        // Make sure eBTC balance decreased
        assertLt(eBTCToken.balanceOf(user), balanceSnapshot);
        // Make sure eBTC balance decreased by repayAmnt precisely
        assertEq(balanceSnapshot.sub(eBTCToken.balanceOf(user)), repayAmnt);
        // Make sure ICR for CDP improved after eBTC was repaid
        uint newIcr = cdpManager.getCurrentICR(cdpId, priceFeedMock.fetchPrice());
        assertGt(newIcr, initialIcr);
        vm.stopPrank();
    }

    // Repaying eBTC by multiple users for many CDPs with randomized collateral
    function testRepayEbtcManyUsersManyCdps() public {
        for (uint userIx = 0; userIx < AMOUNT_OF_USERS; userIx++) {
            address user = _utils.getNextUserAddress();
            vm.deal(user, 1000000000 ether);
            // Random collateral for each user
            uint collAmount = _utils.generateRandomNumber(28 ether, 10000000 ether, user);
            uint collAmountChunk = collAmount.div(AMOUNT_OF_CDPS);
            uint borrowedAmount = _utils.calculateBorrowAmount(
                collAmountChunk,
                priceFeedMock.fetchPrice(),
                COLLATERAL_RATIO
            );
            // Create multiple CDPs per user
            for (uint cdpIx = 0; cdpIx < AMOUNT_OF_CDPS; cdpIx++) {
                vm.prank(user);
                // In case borrowedAmount < MIN_NET_DEBT should expect revert
                if (borrowedAmount < MIN_NET_DEBT) {
                    vm.expectRevert(
                        bytes("BorrowerOps: Cdp's net debt must be greater than minimum")
                    );
                    borrowerOperations.openCdp{value: collAmountChunk}(
                        FEE,
                        borrowedAmount,
                        HINT,
                        HINT
                    );
                    break;
                }
                borrowerOperations.openCdp{value: collAmountChunk}(FEE, borrowedAmount, HINT, HINT);
                cdpIds.push(sortedCdps.cdpOfOwnerByIndex(user, cdpIx));
            }
            _utils.mineBlocks(100);
        }
        // Make TCR snapshot before increasing collateral
        uint initialTcr = cdpManager.getTCR(priceFeedMock.fetchPrice());
        // Now, repay eBTC and make sure ICR improved
        for (uint cdpIx = 0; cdpIx < cdpIds.length; cdpIx++) {
            address user = sortedCdps.getOwnerAddress(cdpIds[cdpIx]);
            // Randomize ebtc repaid amnt from 10 eBTC to max ebtc.balanceOf(user) / amount of CDPs for user
            uint randRepayAmnt = _utils.generateRandomNumber(
                10e18,
                eBTCToken.balanceOf(user).div(AMOUNT_OF_CDPS),
                user
            );
            uint initialIcr = cdpManager.getCurrentICR(cdpIds[cdpIx], priceFeedMock.fetchPrice());
            vm.prank(user);
            // Repay eBTC for each CDP
            borrowerOperations.repayEBTC(cdpIds[cdpIx], randRepayAmnt, HINT, HINT);
            uint newIcr = cdpManager.getCurrentICR(cdpIds[cdpIx], priceFeedMock.fetchPrice());
            // Make sure ICR for CDP increased
            assertGt(newIcr, initialIcr);
            _utils.mineBlocks(100);
        }
        // Make sure TCR increased after eBTC was repaid
        uint newTcr = cdpManager.getTCR(priceFeedMock.fetchPrice());
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
            collAmount,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO_DEFENSIVE
        );
        borrowerOperations.openCdp{value: collAmount}(FEE, borrowedAmount, HINT, HINT);
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

    // Fail when trying to withdraw 0 ebtc
    function testWithdrawWithZeroAmnt() public {
        uint collAmount = 30 ether;
        address user = _utils.getNextUserAddress();
        vm.deal(user, type(uint96).max);
        vm.startPrank(user);
        uint borrowedAmount = _utils.calculateBorrowAmount(
            collAmount,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO_DEFENSIVE
        );
        borrowerOperations.openCdp{value: collAmount}(FEE, borrowedAmount, HINT, HINT);
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        vm.expectRevert(bytes("BorrowerOps: Debt increase requires non-zero debtChange"));
        borrowerOperations.withdrawEBTC(cdpId, FEE, 0, "hint", "hint");
        vm.stopPrank();
    }

    // Fuzz for borrowing and withdrawing eBTC from CDP
    // Handle scenarios when users try to withdraw too much eBTC resulting in either ICR < MCR or TCR < CCR
    function testWithdrawEBTCFuzz(uint96 withdrawAmnt, uint96 collAmount) public {
        withdrawAmnt = uint96(bound(withdrawAmnt, 1e13, type(uint96).max));
        collAmount = uint96(bound(collAmount, 30e18, type(uint96).max));

        address user = _utils.getNextUserAddress();
        vm.deal(user, type(uint96).max);
        vm.startPrank(user);
        uint borrowedAmount = _utils.calculateBorrowAmount(
            collAmount,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );
        borrowerOperations.openCdp{value: collAmount}(FEE, borrowedAmount, HINT, HINT);
        uint balanceSnapshot = eBTCToken.balanceOf(user);
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        // Get ICR for CDP:
        uint initialIcr = cdpManager.getCurrentICR(cdpId, priceFeedMock.fetchPrice());
        // Get initial Debt after opened CDP
        uint initialDebt = cdpManager.getCdpDebt(cdpId);

        // Calculate projected ICR change
        uint projectedIcr = LiquityMath._computeCR(
            collAmount,
            initialDebt.add(withdrawAmnt),
            priceFeedMock.fetchPrice()
        );
        // Calculate projected TCR change with new debt added on top
        uint projectedSystemDebt = borrowerOperations.getEntireSystemDebt().add(withdrawAmnt);
        uint projectedTcr = LiquityMath._computeCR(
            borrowerOperations.getEntireSystemColl(),
            projectedSystemDebt,
            priceFeedMock.fetchPrice()
        );
        // Make sure tx is reverted if user tries to make withdraw resulting in either TCR < CCR or ICR < MCR
        if (projectedTcr < CCR || projectedIcr < MINIMAL_COLLATERAL_RATIO) {
            vm.expectRevert();
            borrowerOperations.withdrawEBTC(cdpId, FEE, withdrawAmnt, "hint", "hint");
            return;
        }
        // Withdraw
        borrowerOperations.withdrawEBTC(cdpId, FEE, withdrawAmnt, "hint", "hint");
        // Make sure ICR decreased
        uint newIcr = cdpManager.getCurrentICR(cdpId, priceFeedMock.fetchPrice());
        assertLt(newIcr, initialIcr);
        // Make sure eBTC balance increased by withdrawAmnt
        assertEq(eBTCToken.balanceOf(user).sub(balanceSnapshot), withdrawAmnt);
        // Make sure debt increased
        assertGt(cdpManager.getCdpDebt(cdpId), initialDebt);
        vm.stopPrank();
    }

    // Test case for multiple users with random amount of CDPs, withdrawing eBTC
    function testWithdrawEBTCManyUsersManyCdps() public {
        for (uint userIx = 0; userIx < AMOUNT_OF_USERS; userIx++) {
            address user = _utils.getNextUserAddress();
            vm.deal(user, 10100000 ether);
            // Random collateral for each user
            uint collAmount = _utils.generateRandomNumber(28 ether, 100000 ether, user);
            uint collAmountChunk = collAmount.div(AMOUNT_OF_CDPS);
            uint borrowedAmount = _utils.calculateBorrowAmount(
                collAmountChunk,
                priceFeedMock.fetchPrice(),
                COLLATERAL_RATIO_DEFENSIVE
            );
            uint minBorrowedAmount = borrowedAmount.mul(btcPriceFeedMock.fetchPrice()).div(1e18);
            // Create multiple CDPs per user
            for (uint cdpIx = 0; cdpIx < AMOUNT_OF_CDPS; cdpIx++) {
                vm.prank(user);
                // In case borrowedAmount < MIN_NET_DEBT should expect revert
                if (minBorrowedAmount < MIN_NET_DEBT) {
                    vm.expectRevert(
                        bytes("BorrowerOps: Cdp's net debt must be greater than minimum")
                    );
                    borrowerOperations.openCdp{value: collAmountChunk}(
                        FEE,
                        borrowedAmount,
                        HINT,
                        HINT
                    );
                    break;
                }
                borrowerOperations.openCdp{value: collAmountChunk}(FEE, borrowedAmount, HINT, HINT);
                cdpIds.push(sortedCdps.cdpOfOwnerByIndex(user, cdpIx));
            }
            _utils.mineBlocks(100);
        }
        // Make TCR snapshot before withdrawing eBTC
        uint initialTcr = cdpManager.getTCR(priceFeedMock.fetchPrice());
        // Now, withdraw eBTC for each CDP and make sure TCR decreased
        for (uint cdpIx = 0; cdpIx < cdpIds.length; cdpIx++) {
            // Randomize collateral increase amount for each user
            address user = sortedCdps.getOwnerAddress(cdpIds[cdpIx]);
            uint randCollWithdraw = _utils.generateRandomNumber(
                // Max value to withdraw is 20% of eBTCs belong to CDP
                0.1 ether,
                cdpManager.getCdpDebt(cdpIds[cdpIx]).div(5),
                user
            );
            uint initialIcr = cdpManager.getCurrentICR(cdpIds[cdpIx], priceFeedMock.fetchPrice());
            vm.prank(user);
            // Withdraw
            borrowerOperations.withdrawEBTC(cdpIds[cdpIx], FEE, randCollWithdraw, "hint", "hint");
            uint newIcr = cdpManager.getCurrentICR(cdpIds[cdpIx], priceFeedMock.fetchPrice());
            // Make sure ICR for CDP decreased
            assertGt(initialIcr, newIcr);
            _utils.mineBlocks(100);
        }
        // Make sure TCR increased after collateral was added
        uint newTcr = cdpManager.getTCR(priceFeedMock.fetchPrice());
        assertGt(initialTcr, newTcr);
    }
}
