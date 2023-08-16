// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "../contracts/Dependencies/LiquityMath.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";
import {Properties} from "../contracts/TestContracts/invariants/Properties.sol";

/*
 * Test suite that tests opened CDPs with two different operations: repayEBTC and withdrawEBTC
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
    function testRepayEBTCHappy() public {
        uint collAmount = 30 ether;
        address user = _utils.getNextUserAddress();
        vm.startPrank(user);
        vm.deal(user, type(uint96).max);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 10000 ether}();
        uint borrowedAmount = _utils.calculateBorrowAmount(
            collAmount,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );
        borrowerOperations.openCdp(borrowedAmount, HINT, HINT, collAmount);
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        uint initialIcr = cdpManager.getCurrentICR(cdpId, priceFeedMock.fetchPrice());
        uint balanceSnapshot = eBTCToken.balanceOf(user);
        // Repay eBTC
        borrowerOperations.repayEBTC(
            cdpId,
            // Repay 10% of eBTC
            borrowedAmount / 10,
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
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 10000 ether}();
        uint borrowedAmount = _utils.calculateBorrowAmount(
            collAmount,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );
        borrowerOperations.openCdp(borrowedAmount, HINT, HINT, collAmount);
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        // Repay eBTC and make sure it reverts for 0 amount
        vm.expectRevert(
            bytes("BorrowerOperations: There must be either a collateral change or a debt change")
        );
        borrowerOperations.repayEBTC(cdpId, 0, HINT, HINT);
        vm.stopPrank();
    }

    // Fuzzing different amounts of eBTC repaid
    function testRepayEBTCFuzz(uint88 repayAmnt) public {
        vm.assume(repayAmnt > 1e10);
        vm.assume(repayAmnt < type(uint88).max);
        // Coll amount will always be max of uint96
        uint collAmount = type(uint96).max;
        address user = _utils.getNextUserAddress();
        vm.startPrank(user);
        vm.deal(user, type(uint256).max);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 10000000000000000 ether}();
        uint borrowedAmount = _utils.calculateBorrowAmount(
            collAmount,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );
        borrowerOperations.openCdp(borrowedAmount, HINT, HINT, collAmount);
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        uint initialIcr = cdpManager.getCurrentICR(cdpId, priceFeedMock.fetchPrice());
        uint balanceSnapshot = eBTCToken.balanceOf(user);
        // Repay eBTC
        borrowerOperations.repayEBTC(cdpId, repayAmnt, HINT, HINT);
        // Make sure eBTC balance decreased
        assertLt(eBTCToken.balanceOf(user), balanceSnapshot);
        // Make sure eBTC balance decreased by repayAmnt precisely
        assertEq(balanceSnapshot - eBTCToken.balanceOf(user), repayAmnt);
        // Make sure ICR for CDP improved after eBTC was repaid
        uint newIcr = cdpManager.getCurrentICR(cdpId, priceFeedMock.fetchPrice());
        assertGt(newIcr, initialIcr);
        vm.stopPrank();
    }

    // Repaying eBTC by multiple users for many CDPs with randomized collateral
    function testRepayEbtcManyUsersManyCdps() public {
        for (uint userIx = 0; userIx < AMOUNT_OF_USERS; userIx++) {
            address user = _utils.getNextUserAddress();
            vm.startPrank(user);
            vm.deal(user, type(uint256).max);
            collateral.approve(address(borrowerOperations), type(uint256).max);
            collateral.deposit{value: 10000000000000000 ether}();
            // Random collateral for each user
            uint collAmount = _utils.generateRandomNumber(28 ether, 10000000 ether, user);
            uint collAmountChunk = collAmount / AMOUNT_OF_CDPS;
            uint borrowedAmount = _utils.calculateBorrowAmount(
                collAmountChunk,
                priceFeedMock.fetchPrice(),
                COLLATERAL_RATIO
            );
            // Create multiple CDPs per user
            for (uint cdpIx = 0; cdpIx < AMOUNT_OF_CDPS; cdpIx++) {
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
        uint initialTcr = cdpManager.getTCR(priceFeedMock.fetchPrice());
        // Now, repay eBTC and make sure ICR improved
        for (uint cdpIx = 0; cdpIx < cdpIds.length; cdpIx++) {
            address user = sortedCdps.getOwnerAddress(cdpIds[cdpIx]);
            // Randomize ebtc repaid amnt from 10 eBTC to max ebtc.balanceOf(user) / amount of CDPs for user
            uint randRepayAmnt = _utils.generateRandomNumber(
                10e18,
                eBTCToken.balanceOf(user) / AMOUNT_OF_CDPS,
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
        vm.startPrank(user);
        vm.deal(user, type(uint96).max);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 10000 ether}();
        uint borrowedAmount = _utils.calculateBorrowAmount(
            collAmount,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO_DEFENSIVE
        );
        borrowerOperations.openCdp(borrowedAmount, HINT, HINT, collAmount);
        // Take eBTC balance snapshot
        uint balanceSnapshot = eBTCToken.balanceOf(user);
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        // Get ICR for CDP:
        uint initialIcr = cdpManager.getCurrentICR(cdpId, priceFeedMock.fetchPrice());
        // Get initial Debt after opened CDP
        uint initialDebt = cdpManager.getCdpDebt(cdpId);
        // Withdraw 1 eBTC
        borrowerOperations.withdrawEBTC(cdpId, 1e17, "hint", "hint");
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
        vm.startPrank(user);
        vm.deal(user, type(uint96).max);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 10000 ether}();
        uint borrowedAmount = _utils.calculateBorrowAmount(
            collAmount,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO_DEFENSIVE
        );
        borrowerOperations.openCdp(borrowedAmount, HINT, HINT, collAmount);
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        vm.expectRevert(bytes("BorrowerOperations: Debt increase requires non-zero debtChange"));
        borrowerOperations.withdrawEBTC(cdpId, 0, "hint", "hint");
        vm.stopPrank();
    }

    // Fuzz for borrowing and withdrawing eBTC from CDP
    // Handle scenarios when users try to withdraw too much eBTC resulting in either ICR < MCR or TCR < CCR
    function testWithdrawEBTCFuzz(uint96 withdrawAmnt, uint96 collAmount) public {
        vm.assume(withdrawAmnt > 1e13);
        vm.assume(collAmount > 30e18);
        vm.assume(withdrawAmnt < type(uint96).max);
        vm.assume(collAmount < type(uint96).max);

        address user = _utils.getNextUserAddress();
        vm.startPrank(user);
        vm.deal(user, type(uint256).max);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 1000000000000000000000000 ether}();
        uint borrowedAmount = _utils.calculateBorrowAmount(
            collAmount,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );
        borrowerOperations.openCdp(borrowedAmount, HINT, HINT, collAmount);
        uint balanceSnapshot = eBTCToken.balanceOf(user);
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        // Get ICR for CDP:
        uint initialIcr = cdpManager.getCurrentICR(cdpId, priceFeedMock.fetchPrice());
        // Get initial Debt after opened CDP
        uint initialDebt = cdpManager.getCdpDebt(cdpId);

        // Calculate projected ICR change
        uint projectedIcr = LiquityMath._computeCR(
            collAmount,
            initialDebt + withdrawAmnt,
            priceFeedMock.fetchPrice()
        );
        // Calculate projected TCR change with new debt added on top
        uint projectedSystemDebt = cdpManager.getEntireSystemDebt() + withdrawAmnt;
        uint projectedTcr = LiquityMath._computeCR(
            borrowerOperations.getEntireSystemColl(),
            projectedSystemDebt,
            priceFeedMock.fetchPrice()
        );
        // Make sure tx is reverted if user tries to make withdraw resulting in either TCR < CCR or ICR < MCR
        if (projectedTcr <= CCR || projectedIcr <= MINIMAL_COLLATERAL_RATIO) {
            vm.expectRevert();
            borrowerOperations.withdrawEBTC(cdpId, withdrawAmnt, "hint", "hint");
            return;
        }
        // Withdraw
        borrowerOperations.withdrawEBTC(cdpId, withdrawAmnt, "hint", "hint");
        // Make sure ICR decreased
        uint newIcr = cdpManager.getCurrentICR(cdpId, priceFeedMock.fetchPrice());
        assertLt(newIcr, initialIcr);
        // Make sure eBTC balance increased by withdrawAmnt
        assertEq(eBTCToken.balanceOf(user) - balanceSnapshot, withdrawAmnt);
        // Make sure debt increased
        assertGt(cdpManager.getCdpDebt(cdpId), initialDebt);
        vm.stopPrank();
    }

    // Test case for multiple users with random amount of CDPs, withdrawing eBTC
    function testWithdrawEBTCManyUsersManyCdps() public {
        for (uint userIx = 0; userIx < AMOUNT_OF_USERS; userIx++) {
            address user = _utils.getNextUserAddress();
            vm.startPrank(user);
            vm.deal(user, type(uint256).max);
            collateral.approve(address(borrowerOperations), type(uint256).max);
            collateral.deposit{value: 1000000000000000000000000 ether}();
            // Random collateral for each user
            uint collAmount = _utils.generateRandomNumber(30 ether, 100000 ether, user);
            uint collAmountChunk = collAmount / AMOUNT_OF_CDPS;
            uint borrowedAmount = _utils.calculateBorrowAmount(
                collAmountChunk,
                priceFeedMock.fetchPrice(),
                COLLATERAL_RATIO_DEFENSIVE
            );
            // Create multiple CDPs per user
            for (uint cdpIx = 0; cdpIx < AMOUNT_OF_CDPS; cdpIx++) {
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
        uint initialTcr = cdpManager.getTCR(priceFeedMock.fetchPrice());
        // Now, withdraw eBTC for each CDP and make sure TCR decreased
        for (uint cdpIx = 0; cdpIx < cdpIds.length; cdpIx++) {
            // Randomize collateral increase amount for each user
            address user = sortedCdps.getOwnerAddress(cdpIds[cdpIx]);
            uint randCollWithdraw = _utils.generateRandomNumber(
                // Max value to withdraw is 33% of eBTCs belong to CDP
                0.1 ether,
                cdpManager.getCdpDebt(cdpIds[cdpIx]) / 3,
                user
            );
            uint initialIcr = cdpManager.getCurrentICR(cdpIds[cdpIx], priceFeedMock.fetchPrice());
            vm.prank(user);
            // Withdraw
            borrowerOperations.withdrawEBTC(cdpIds[cdpIx], randCollWithdraw, "hint", "hint");
            uint newIcr = cdpManager.getCurrentICR(cdpIds[cdpIx], priceFeedMock.fetchPrice());
            // Make sure ICR for CDP decreased
            assertGt(initialIcr, newIcr);
            _utils.mineBlocks(100);
        }
        // Make sure TCR increased after collateral was added
        uint newTcr = cdpManager.getTCR(priceFeedMock.fetchPrice());
        assertGt(initialTcr, newTcr);
    }

    function testRepayEBTCMustImproveTCR() public {
        uint collAmount = 2000000000000000016 + borrowerOperations.LIQUIDATOR_REWARD();
        uint borrowedAmount = 1;
        uint debtAmount = 28;
        uint repayAmount = 1;
        address user = _utils.getNextUserAddress();
        vm.startPrank(user);
        vm.deal(user, type(uint96).max);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 10 ether}();

        bytes32 _cdpId = borrowerOperations.openCdp(borrowedAmount, HINT, HINT, collAmount);
        borrowerOperations.withdrawEBTC(_cdpId, debtAmount, _cdpId, _cdpId);
        collateral.setEthPerShare(1.099408949270679030e18);

        uint256 _price = priceFeedMock.getPrice();
        uint256 tcrBefore = cdpManager.getTCR(_price);

        uint entireSystemColl = cdpManager.getEntireSystemColl();
        uint entireSystemDebt = activePool.getEBTCDebt();
        uint underlyingCollateral = collateral.getPooledEthByShares(entireSystemColl);

        emit log_named_uint("C", entireSystemColl);
        emit log_named_uint("D", entireSystemDebt);
        emit log_named_uint("U", underlyingCollateral);

        borrowerOperations.repayEBTC(_cdpId, repayAmount, HINT, HINT);

        entireSystemColl = cdpManager.getEntireSystemColl();
        entireSystemDebt = activePool.getEBTCDebt();
        underlyingCollateral = collateral.getPooledEthByShares(entireSystemColl);

        emit log_named_uint("C", entireSystemColl);
        emit log_named_uint("D", entireSystemDebt);
        emit log_named_uint("U", underlyingCollateral);

        uint256 tcrAfter = cdpManager.getTCR(_price);

        // TODO uncomment after https://github.com/Badger-Finance/ebtc-fuzz-review/issues/3 is fixed
        // assertGt(tcrAfter, tcrBefore, "TCR must increase after a repayment");
    }

    function testRepayEBTCMustBurn() public {
        uint collAmount = 2000000000000000033 + borrowerOperations.LIQUIDATOR_REWARD();
        uint borrowedAmount = 2;
        uint repayAmount = 1;
        address user = _utils.getNextUserAddress();
        vm.startPrank(user);
        vm.deal(user, type(uint96).max);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 10 ether}();

        bytes32 _cdpId = borrowerOperations.openCdp(borrowedAmount, HINT, HINT, collAmount);

        uint256 userEbtcBefore = eBTCToken.balanceOf((address(user)));
        emit log_named_uint("eBTC balance before", userEbtcBefore);
        emit log_named_uint("Repay amount", repayAmount);

        borrowerOperations.repayEBTC(_cdpId, repayAmount, _cdpId, _cdpId);

        uint256 userEbtcAfter = eBTCToken.balanceOf((address(user)));
        emit log_named_uint("eBTC balance after", userEbtcAfter);

        assertEq(userEbtcBefore - repayAmount, userEbtcAfter, BO_07);
    }

    function testAllCdpsShouldMaintainAMinimumCollateralSize() public {
        uint collAmount = 2000000000000000016 + borrowerOperations.LIQUIDATOR_REWARD();
        uint _EBTCAmount = 1;
        uint withdrawAmount = 186970840931894992;
        uint ethPerShare = 0.909090909090909092e18;
        address user = _utils.getNextUserAddress();

        vm.startPrank(user);
        vm.deal(user, type(uint96).max);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 10 ether}();

        console2.log("openCdp", _EBTCAmount, collAmount);
        bytes32 _cdpId = borrowerOperations.openCdp(_EBTCAmount, HINT, HINT, collAmount);

        console2.log("setETHPerShare", ethPerShare);
        collateral.setEthPerShare(ethPerShare);

        console2.log(">> CDP coll before", cdpManager.getCdpColl(_cdpId));
        console2.log(
            ">> CDP shares before",
            collateral.getPooledEthByShares(cdpManager.getCdpColl(_cdpId))
        );

        console2.log("withdrawColl", withdrawAmount);
        borrowerOperations.withdrawColl(_cdpId, withdrawAmount, _cdpId, _cdpId);

        console2.log(">> CDP coll after", cdpManager.getCdpColl(_cdpId));
        console2.log(
            ">> CDP shares after",
            collateral.getPooledEthByShares(cdpManager.getCdpColl(_cdpId))
        );

        // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/4
        assertGe(
            collateral.getPooledEthByShares(cdpManager.getCdpColl(_cdpId)),
            borrowerOperations.MIN_NET_COLL(),
            GENERAL_10
        );
    }

    function testRedemptionMustSatisfyAccountingEquation() public {
        vm.warp(block.timestamp + cdpManager.BOOTSTRAP_PERIOD());

        address user = _utils.getNextUserAddress();

        vm.startPrank(user);
        vm.deal(user, type(uint96).max);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 10 ether}();

        borrowerOperations.openCdp(1, HINT, HINT, 2200000000000000016);
        borrowerOperations.openCdp(130881814726979393, HINT, HINT, 2202507652244537442);
        collateral.setEthPerShare(909090909090909090);

        uint256 activePoolCollBefore = activePool.getStEthColl();
        uint256 collSurplusPoolBefore = collSurplusPool.getStEthColl();
        uint256 debtBefore = activePool.getEBTCDebt();
        uint256 priceBefore = priceFeedMock.getPrice();

        cdpManager.redeemCollateral(
            1,
            bytes32(0),
            bytes32(0),
            bytes32(0),
            0,
            0,
            5000000000000000 
        );
        
        uint256 activePoolCollAfter = activePool.getStEthColl();
        uint256 collSurplusPoolAfter = collSurplusPool.getStEthColl();
        uint256 debtAfter = activePool.getEBTCDebt();
        uint256 priceAfter = priceFeedMock.getPrice();

        uint256 beforeEquity = (activePoolCollBefore + collSurplusPoolBefore) *
            priceBefore -
            debtBefore;
        uint256 afterEquity = (activePoolCollAfter + collSurplusPoolAfter) * priceAfter - debtAfter;

        assertEq(beforeEquity, afterEquity, GENERAL_11);
    }
}
