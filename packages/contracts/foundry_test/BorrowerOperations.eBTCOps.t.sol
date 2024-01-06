// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "../contracts/Dependencies/EbtcMath.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";
import {Properties} from "../contracts/TestContracts/invariants/Properties.sol";

/*
 * Test suite that tests opened CDPs with two different operations: repayDebt and withdrawDebt
 * Test include testing different metrics such as each CDP ICR, also TCR changes after operations are executed
 */
contract CDPOpsTest is eBTCBaseFixture, Properties {
    // Storage array of cdpIDs when impossible to calculate array size
    bytes32[] cdpIds;

    function setUp() public override {
        eBTCBaseFixture.setUp();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();
    }

    // -------- Repay eBTC Test cases --------

    // Happy case for borrowing and repaying back eBTC which should result in increasing ICR
    function testrepayDebtHappy() public {
        uint256 collAmount = 30 ether;
        address user = _utils.getNextUserAddress();
        vm.startPrank(user);
        vm.deal(user, type(uint96).max);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 10000 ether}();
        uint256 borrowedAmount = _utils.calculateBorrowAmount(
            collAmount,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );
        borrowerOperations.openCdp(borrowedAmount, HINT, HINT, collAmount);
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        uint256 initialIcr = cdpManager.getCachedICR(cdpId, priceFeedMock.fetchPrice());
        uint256 balanceSnapshot = eBTCToken.balanceOf(user);
        // Repay eBTC
        borrowerOperations.repayDebt(
            cdpId,
            // Repay 10% of eBTC
            borrowedAmount / 10,
            HINT,
            HINT
        );
        // Make sure eBTC balance decreased
        assertLt(eBTCToken.balanceOf(user), balanceSnapshot);
        // Make sure ICR for CDP improved after eBTC was repaid
        uint256 newIcr = cdpManager.getCachedICR(cdpId, priceFeedMock.fetchPrice());
        assertGt(newIcr, initialIcr);
        vm.stopPrank();
    }

    // Case when trying to repay less than min eBTC
    function testRepayWithLessThanMinAmnt() public {
        uint256 collAmount = 30 ether;
        address user = _utils.getNextUserAddress();
        vm.startPrank(user);
        vm.deal(user, type(uint96).max);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 10000 ether}();
        uint256 borrowedAmount = _utils.calculateBorrowAmount(
            collAmount,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );
        borrowerOperations.openCdp(borrowedAmount, HINT, HINT, collAmount);
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        // Repay eBTC and make sure it reverts for 0 amount
        vm.expectRevert(ERR_BORROWER_OPERATIONS_NON_ZERO_CHANGE);
        borrowerOperations.repayDebt(cdpId, 0, HINT, HINT);
        // Repay eBTC and make sure it reverts for MIN_CHANGE - 1 amount
        vm.expectRevert(ERR_BORROWER_OPERATIONS_MIN_CHANGE);
        borrowerOperations.repayDebt(cdpId, minChange - 1, HINT, HINT);
        vm.stopPrank();
    }

    // Fuzzing different amounts of eBTC repaid
    function testrepayDebtFuzz(uint88 repayAmnt) public {
        repayAmnt = uint88(bound(repayAmnt, 1e10, type(uint88).max));
        // Coll amount will always be max of uint96
        uint256 collAmount = type(uint96).max;
        address user = _utils.getNextUserAddress();
        vm.startPrank(user);
        vm.deal(user, type(uint256).max);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 10000000000000000 ether}();
        uint256 borrowedAmount = _utils.calculateBorrowAmount(
            collAmount,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );
        borrowerOperations.openCdp(borrowedAmount, HINT, HINT, collAmount);
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        uint256 initialIcr = cdpManager.getCachedICR(cdpId, priceFeedMock.fetchPrice());
        uint256 balanceSnapshot = eBTCToken.balanceOf(user);
        // Repay eBTC
        borrowerOperations.repayDebt(cdpId, repayAmnt, HINT, HINT);
        // Make sure eBTC balance decreased
        assertLt(eBTCToken.balanceOf(user), balanceSnapshot);
        // Make sure eBTC balance decreased by repayAmnt precisely
        assertEq(balanceSnapshot - eBTCToken.balanceOf(user), repayAmnt);
        // Make sure ICR for CDP improved after eBTC was repaid
        uint256 newIcr = cdpManager.getCachedICR(cdpId, priceFeedMock.fetchPrice());
        assertGt(newIcr, initialIcr);
        vm.stopPrank();
    }

    // Repaying eBTC by multiple users for many CDPs with randomized collateral
    function testrepayDebtManyUsersManyCdps() public {
        for (uint256 userIx = 0; userIx < AMOUNT_OF_USERS; userIx++) {
            address user = _utils.getNextUserAddress();
            vm.startPrank(user);
            vm.deal(user, type(uint256).max);
            collateral.approve(address(borrowerOperations), type(uint256).max);
            collateral.deposit{value: 10000000000000000 ether}();
            // Random collateral for each user
            uint256 collAmount = _utils.generateRandomNumber(28 ether, 10000000 ether, user);
            uint256 collAmountChunk = collAmount / AMOUNT_OF_CDPS;
            uint256 borrowedAmount = _utils.calculateBorrowAmount(
                collAmountChunk,
                priceFeedMock.fetchPrice(),
                COLLATERAL_RATIO
            );
            // Create multiple CDPs per user
            for (uint256 cdpIx = 0; cdpIx < AMOUNT_OF_CDPS; cdpIx++) {
                // In case borrowedAmount < MIN_NET_DEBT should expect revert
                if (borrowedAmount < MIN_NET_DEBT) {
                    vm.expectRevert(
                        bytes("BorrowerOperations: Cdp's net debt must be greater than minimum")
                    );
                    borrowerOperations.openCdp(borrowedAmount, HINT, HINT, collAmountChunk);
                    break;
                }
                borrowerOperations.openCdp(borrowedAmount, HINT, HINT, collAmountChunk);
                cdpIds.push(sortedCdps.cdpOfOwnerByIndex(user, cdpIx));
            }
            vm.stopPrank();
            _utils.mineBlocks(100);
        }
        // Make TCR snapshot before increasing collateral
        uint256 initialTcr = cdpManager.getCachedTCR(priceFeedMock.fetchPrice());
        // Now, repay eBTC and make sure ICR improved
        for (uint256 cdpIx = 0; cdpIx < cdpIds.length; cdpIx++) {
            address user = sortedCdps.getOwnerAddress(cdpIds[cdpIx]);
            // Randomize ebtc repaid amnt from 10 eBTC to max ebtc.balanceOf(user) / amount of CDPs for user
            uint256 randRepayAmnt = _utils.generateRandomNumber(
                10e18,
                eBTCToken.balanceOf(user) / AMOUNT_OF_CDPS,
                user
            );
            uint256 initialIcr = cdpManager.getCachedICR(cdpIds[cdpIx], priceFeedMock.fetchPrice());
            vm.prank(user);
            // Repay eBTC for each CDP
            borrowerOperations.repayDebt(cdpIds[cdpIx], randRepayAmnt, HINT, HINT);
            uint256 newIcr = cdpManager.getCachedICR(cdpIds[cdpIx], priceFeedMock.fetchPrice());
            // Make sure ICR for CDP increased
            assertGt(newIcr, initialIcr);
            _utils.mineBlocks(100);
        }
        // Make sure TCR increased after eBTC was repaid
        uint256 newTcr = cdpManager.getCachedTCR(priceFeedMock.fetchPrice());
        assertGt(newTcr, initialTcr);
    }

    // -------- Withdraw eBTC Test cases --------

    // Simple Happy case for borrowing and withdrawing eBTC from CDP
    function testwithdrawDebtHappy() public {
        uint256 collAmount = 30 ether;
        address user = _utils.getNextUserAddress();
        vm.startPrank(user);
        vm.deal(user, type(uint96).max);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 10000 ether}();
        uint256 borrowedAmount = _utils.calculateBorrowAmount(
            collAmount,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO_DEFENSIVE
        );
        borrowerOperations.openCdp(borrowedAmount, HINT, HINT, collAmount);
        // Take eBTC balance snapshot
        uint256 balanceSnapshot = eBTCToken.balanceOf(user);
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        // Get ICR for CDP:
        uint256 initialIcr = cdpManager.getCachedICR(cdpId, priceFeedMock.fetchPrice());
        // Get initial Debt after opened CDP
        uint256 initialDebt = cdpManager.getCdpDebt(cdpId);
        // Withdraw 1 eBTC
        borrowerOperations.withdrawDebt(cdpId, 1e17, "hint", "hint");
        // Make sure ICR decreased
        assertLt(cdpManager.getCachedICR(cdpId, priceFeedMock.fetchPrice()), initialIcr);
        // Make sure debt increased
        assertGt(cdpManager.getCdpDebt(cdpId), initialDebt);
        // Make sure eBTC balance of user increased
        assertGt(eBTCToken.balanceOf(user), balanceSnapshot);
        vm.stopPrank();
    }

    // Fail when trying to withdraw less than min ebtc
    function testWithdrawWithLessThanMinAmnt() public {
        uint256 collAmount = 30 ether;
        address user = _utils.getNextUserAddress();
        vm.startPrank(user);
        vm.deal(user, type(uint96).max);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 10000 ether}();
        uint256 borrowedAmount = _utils.calculateBorrowAmount(
            collAmount,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO_DEFENSIVE
        );
        borrowerOperations.openCdp(borrowedAmount, HINT, HINT, collAmount);
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);

        // Test with 0 debt
        vm.expectRevert(ERR_BORROWER_OPERATIONS_MIN_DEBT_CHANGE);
        borrowerOperations.withdrawDebt(cdpId, 0, "hint", "hint");

        // Test with <1000 debt
        vm.expectRevert(ERR_BORROWER_OPERATIONS_MIN_DEBT_CHANGE);
        borrowerOperations.withdrawDebt(cdpId, 999, "hint", "hint");
        vm.stopPrank();
    }

    // Fuzz for borrowing and withdrawing eBTC from CDP
    // Handle scenarios when users try to withdraw too much eBTC resulting in either ICR < MCR or TCR < CCR
    function testwithdrawDebtFuzz(uint96 withdrawAmnt, uint96 collAmount) public {
        withdrawAmnt = uint96(bound(withdrawAmnt, 1e13, type(uint96).max));
        collAmount = uint96(bound(collAmount, 30e18, type(uint96).max));

        address user = _utils.getNextUserAddress();
        vm.startPrank(user);
        vm.deal(user, type(uint256).max);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 1000000000000000000000000 ether}();
        uint256 borrowedAmount = _utils.calculateBorrowAmount(
            collAmount,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );
        borrowerOperations.openCdp(borrowedAmount, HINT, HINT, collAmount);
        uint256 balanceSnapshot = eBTCToken.balanceOf(user);
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        // Get ICR for CDP:
        uint256 initialIcr = cdpManager.getCachedICR(cdpId, priceFeedMock.fetchPrice());
        // Get initial Debt after opened CDP
        uint256 initialDebt = cdpManager.getCdpDebt(cdpId);

        // Calculate projected ICR change
        uint256 projectedIcr = EbtcMath._computeCR(
            collAmount,
            initialDebt + withdrawAmnt,
            priceFeedMock.fetchPrice()
        );
        // Calculate projected TCR change with new debt added on top
        uint256 projectedSystemDebt = cdpManager.getSystemDebt() + withdrawAmnt;
        uint256 projectedTcr = EbtcMath._computeCR(
            borrowerOperations.getSystemCollShares(),
            projectedSystemDebt,
            priceFeedMock.fetchPrice()
        );
        // Make sure tx is reverted if user tries to make withdraw resulting in either TCR < CCR or ICR < MCR
        if (projectedTcr <= CCR || projectedIcr <= MINIMAL_COLLATERAL_RATIO) {
            vm.expectRevert();
            borrowerOperations.withdrawDebt(cdpId, withdrawAmnt, "hint", "hint");
            return;
        }
        // Withdraw
        borrowerOperations.withdrawDebt(cdpId, withdrawAmnt, "hint", "hint");
        // Make sure ICR decreased
        uint256 newIcr = cdpManager.getCachedICR(cdpId, priceFeedMock.fetchPrice());
        assertLt(newIcr, initialIcr);
        // Make sure eBTC balance increased by withdrawAmnt
        assertEq(eBTCToken.balanceOf(user) - balanceSnapshot, withdrawAmnt);
        // Make sure debt increased
        assertGt(cdpManager.getCdpDebt(cdpId), initialDebt);
        vm.stopPrank();
    }

    // Test case for multiple users with random amount of CDPs, withdrawing eBTC
    function testwithdrawDebtManyUsersManyCdps() public {
        for (uint256 userIx = 0; userIx < AMOUNT_OF_USERS; userIx++) {
            address user = _utils.getNextUserAddress();
            vm.startPrank(user);
            vm.deal(user, type(uint256).max);
            collateral.approve(address(borrowerOperations), type(uint256).max);
            collateral.deposit{value: 1_000_000_000e18}();
            // Random collateral for each user
            uint256 collAmount = _utils.generateRandomNumber(30 ether, 100000 ether, user);
            uint256 collAmountChunk = collAmount / AMOUNT_OF_CDPS;
            uint256 borrowedAmount = _utils.calculateBorrowAmount(
                collAmountChunk,
                priceFeedMock.fetchPrice(),
                COLLATERAL_RATIO_DEFENSIVE
            );
            // Create multiple CDPs per user
            for (uint256 cdpIx = 0; cdpIx < AMOUNT_OF_CDPS; cdpIx++) {
                // In case borrowedAmount < MIN_NET_DEBT should expect revert
                if (borrowedAmount < MIN_NET_DEBT) {
                    vm.expectRevert(
                        bytes("BorrowerOperations: Cdp's net debt must be greater than minimum")
                    );
                    borrowerOperations.openCdp(borrowedAmount, HINT, HINT, collAmountChunk);
                    break;
                }
                borrowerOperations.openCdp(borrowedAmount, HINT, HINT, collAmountChunk);
                cdpIds.push(sortedCdps.cdpOfOwnerByIndex(user, cdpIx));
            }
            vm.stopPrank();
            _utils.mineBlocks(100);
        }
        // Make TCR snapshot before withdrawing eBTC
        uint256 initialTcr = cdpManager.getCachedTCR(priceFeedMock.fetchPrice());
        // Now, withdraw eBTC for each CDP and make sure TCR decreased
        for (uint256 cdpIx = 0; cdpIx < cdpIds.length; cdpIx++) {
            // Randomize collateral increase amount for each user
            address user = sortedCdps.getOwnerAddress(cdpIds[cdpIx]);
            uint256 randCollWithdraw = _utils.generateRandomNumber(
                // Max value to withdraw is 33% of eBTCs belong to CDP
                0.1 ether,
                cdpManager.getCdpDebt(cdpIds[cdpIx]) / 3,
                user
            );
            uint256 initialIcr = cdpManager.getCachedICR(cdpIds[cdpIx], priceFeedMock.fetchPrice());
            vm.prank(user);
            // Withdraw
            borrowerOperations.withdrawDebt(cdpIds[cdpIx], randCollWithdraw, "hint", "hint");
            uint256 newIcr = cdpManager.getCachedICR(cdpIds[cdpIx], priceFeedMock.fetchPrice());
            // Make sure ICR for CDP decreased
            assertGt(initialIcr, newIcr);
            _utils.mineBlocks(100);
        }
        // Make sure TCR increased after collateral was added
        uint256 newTcr = cdpManager.getCachedTCR(priceFeedMock.fetchPrice());
        assertGt(initialTcr, newTcr);
    }

    function testrepayDebtMustImproveTCR() public {
        uint collAmount = 2000000000000000016 + borrowerOperations.LIQUIDATOR_REWARD();
        uint borrowedAmount = borrowerOperations.MIN_CHANGE();
        uint debtAmount = 28 * borrowerOperations.MIN_CHANGE();
        uint repayAmount = borrowerOperations.MIN_CHANGE();
        address user = _utils.getNextUserAddress();
        vm.startPrank(user);
        vm.deal(user, type(uint96).max);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 10 ether}();

        bytes32 _cdpId = borrowerOperations.openCdp(borrowedAmount, HINT, HINT, collAmount);
        borrowerOperations.withdrawDebt(_cdpId, debtAmount, _cdpId, _cdpId);
        collateral.setEthPerShare(1.099408949270679030e18);

        uint256 _price = priceFeedMock.getPrice();
        uint256 tcrBefore = cdpManager.getCachedTCR(_price);

        uint entireSystemColl = cdpManager.getSystemCollShares();
        uint entireSystemDebt = activePool.getSystemDebt();
        uint underlyingCollateral = collateral.getPooledEthByShares(entireSystemColl);

        emit log_named_uint("C", entireSystemColl);
        emit log_named_uint("D", entireSystemDebt);
        emit log_named_uint("U", underlyingCollateral);

        borrowerOperations.repayDebt(_cdpId, repayAmount, HINT, HINT);

        entireSystemColl = cdpManager.getSystemCollShares();
        entireSystemDebt = activePool.getSystemDebt();
        underlyingCollateral = collateral.getPooledEthByShares(entireSystemColl);

        emit log_named_uint("C", entireSystemColl);
        emit log_named_uint("D", entireSystemDebt);
        emit log_named_uint("U", underlyingCollateral);

        uint256 tcrAfter = cdpManager.getCachedTCR(_price);

        // TODO uncomment after https://github.com/Badger-Finance/ebtc-fuzz-review/issues/3 is fixed
        // assertGt(tcrAfter, tcrBefore, "TCR must increase after a repayment");
    }

    function testrepayDebtMustBurn() public {
        uint collAmount = 2000000000000000033 + borrowerOperations.LIQUIDATOR_REWARD();
        uint borrowedAmount = 2 * borrowerOperations.MIN_CHANGE();
        uint repayAmount = borrowerOperations.MIN_CHANGE();
        address user = _utils.getNextUserAddress();
        vm.startPrank(user);
        vm.deal(user, type(uint96).max);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 10 ether}();

        bytes32 _cdpId = borrowerOperations.openCdp(borrowedAmount, HINT, HINT, collAmount);

        uint256 userEbtcBefore = eBTCToken.balanceOf((address(user)));
        emit log_named_uint("eBTC balance before", userEbtcBefore);
        emit log_named_uint("Repay amount", repayAmount);

        borrowerOperations.repayDebt(_cdpId, repayAmount, _cdpId, _cdpId);

        uint256 userEbtcAfter = eBTCToken.balanceOf((address(user)));
        emit log_named_uint("eBTC balance after", userEbtcAfter);

        assertEq(userEbtcBefore - repayAmount, userEbtcAfter, BO_07);
    }
}
