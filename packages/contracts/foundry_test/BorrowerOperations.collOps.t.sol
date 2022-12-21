// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.11;

import "forge-std/Test.sol";
import "../contracts/Dependencies/LiquityMath.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";
import {Utilities} from "./utils/Utilities.sol";

/*
 * Test suite that tests opened CDPs with two different operations: addColl and withdrawColl
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

    // -------- Increase Collateral Test cases --------

    // Happy case for borrowing and adding collateral within CDP
    function testIncreaseCRHappy() public {
        uint collAmount = 30 ether;
        address user = _utils.getNextUserAddress();
        vm.startPrank(user);
        vm.deal(user, type(uint96).max);
        // Calculate borrowed amount
        uint borrowedAmount = _utils.calculateBorrowAmount(
            collAmount,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );
        borrowerOperations.openCdp{value: collAmount}(FEE, borrowedAmount, HINT, HINT);
        // Get new CDP id
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        uint coll = cdpManager.getCdpColl(cdpId);
        // Make sure collateral is as expected
        assertEq(collAmount, coll);
        // Get ICR for CDP:
        uint initialIcr = cdpManager.getCurrentICR(cdpId, priceFeedMock.fetchPrice());
        assertGt(initialIcr, MINIMAL_COLLATERAL_RATIO);
        // Add more collateral and make sure ICR changes
        borrowerOperations.addColl{value: collAmount}(cdpId, "hint", "hint");
        uint newIcr = cdpManager.getCurrentICR(cdpId, priceFeedMock.fetchPrice());
        assert(newIcr != initialIcr);
        // Make sure collateral increased by 2x
        assertEq(collAmount.mul(2), cdpManager.getCdpColl(cdpId));
        vm.stopPrank();
    }

    // Expect revert if trying to pass 0 as coll increase value
    function testIncreaseCRWithZeroAmount() public {
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
        vm.expectRevert(
            bytes("BorrowerOps: There must be either a collateral change or a debt change")
        );
        borrowerOperations.addColl{value: 0}(cdpId, "hint", "hint");
        vm.stopPrank();
    }

    // Fuzzing for collAdd happy case scenario
    function testIncreaseCRHappyFuzz(uint96 increaseAmnt) public {
        increaseAmnt = uint96(bound(increaseAmnt, 1e1, type(uint96).max));
        uint collAmount = 28 ether;
        address user = _utils.getNextUserAddress();
        vm.startPrank(user);
        vm.deal(user, type(uint256).max);
        uint borrowedAmount = _utils.calculateBorrowAmount(
            collAmount,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );
        // In case borrowedAmount is less than MIN_NET_DEBT - expect revert
        if (borrowedAmount < MIN_NET_DEBT) {
            vm.expectRevert(bytes("BorrowerOps: Cdp's net debt must be greater than minimum"));
            borrowerOperations.openCdp{value: collAmount}(FEE, borrowedAmount, "hint", "hint");
            return;
        }
        borrowerOperations.openCdp{value: collAmount}(FEE, borrowedAmount, HINT, HINT);
        // Make TCR snapshot before increasing collateral
        uint initialTcr = LiquityMath._computeCR(
            borrowerOperations.getEntireSystemColl(),
            borrowerOperations.getEntireSystemDebt(),
            priceFeedMock.fetchPrice()
        );
        // Get new CDP id
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        // Make sure collateral is as expected
        assertEq(collAmount, cdpManager.getCdpColl(cdpId));
        // Get ICR for CDP:
        uint initialIcr = cdpManager.getCurrentICR(cdpId, priceFeedMock.fetchPrice());
        assertGt(initialIcr, MINIMAL_COLLATERAL_RATIO);
        // Add more collateral and make sure ICR changes
        borrowerOperations.addColl{value: increaseAmnt}(cdpId, "hint", "hint");
        uint newIcr = cdpManager.getCurrentICR(cdpId, priceFeedMock.fetchPrice());
        assertGt(newIcr, initialIcr);
        // Make sure collateral increased by increaseAmnt
        assertEq(collAmount.add(increaseAmnt), cdpManager.getCdpColl(cdpId));

        // Make sure TCR increased after collateral was added
        uint newTcr = LiquityMath._computeCR(
            borrowerOperations.getEntireSystemColl(),
            borrowerOperations.getEntireSystemDebt(),
            priceFeedMock.fetchPrice()
        );
        assertGt(newTcr, initialTcr);
        vm.stopPrank();
    }

    // Test case for multiple users with random amount of CDPs, adding more collateral
    function testIncreaseCRManyUsersManyCdps() public {
        for (uint userIx = 0; userIx < AMOUNT_OF_USERS; userIx++) {
            address user = _utils.getNextUserAddress();
            vm.deal(user, 10100000 ether);
            // Random collateral for each user
            uint collAmount = _utils.generateRandomNumber(28 ether, 1000000 ether, user);
            uint collAmountChunk = collAmount.div(AMOUNT_OF_CDPS);
            uint borrowedAmount = _utils.calculateBorrowAmount(
                collAmountChunk,
                priceFeedMock.fetchPrice(),
                COLLATERAL_RATIO
            );
            // Create multiple CDPs per user
            for (uint cdpIx = 0; cdpIx < AMOUNT_OF_CDPS; cdpIx++) {
                vm.prank(user);
                borrowerOperations.openCdp{value: collAmountChunk}(FEE, borrowedAmount, HINT, HINT);
                cdpIds.push(sortedCdps.cdpOfOwnerByIndex(user, cdpIx));
            }
            _utils.mineBlocks(100);
        }
        // Make TCR snapshot before increasing collateral
        uint initialTcr = LiquityMath._computeCR(
            borrowerOperations.getEntireSystemColl(),
            borrowerOperations.getEntireSystemDebt(),
            priceFeedMock.fetchPrice()
        );
        // Now, add collateral for each CDP and make sure TCR improved
        for (uint cdpIx = 0; cdpIx < cdpIds.length; cdpIx++) {
            // Randomize collateral increase amount for each user
            address user = sortedCdps.getOwnerAddress(cdpIds[cdpIx]);
            uint randCollIncrease = _utils.generateRandomNumber(10 ether, 1000 ether, user);
            vm.prank(user);
            uint initialIcr = cdpManager.getCurrentICR(cdpIds[cdpIx], priceFeedMock.fetchPrice());
            // Increase coll by random value
            vm.prank(user);
            borrowerOperations.addColl{value: randCollIncrease}(cdpIds[cdpIx], "hint", "hint");
            uint newIcr = cdpManager.getCurrentICR(cdpIds[cdpIx], priceFeedMock.fetchPrice());
            // Make sure ICR for CDP increased
            assertGt(newIcr, initialIcr);
            _utils.mineBlocks(100);
        }
        // Make sure TCR increased after collateral was added
        uint newTcr = LiquityMath._computeCR(
            borrowerOperations.getEntireSystemColl(),
            borrowerOperations.getEntireSystemDebt(),
            priceFeedMock.fetchPrice()
        );
        assertGt(newTcr, initialTcr);
    }

    // -------- Withdraw Collateral Test cases --------

    // Happy case for borrowing and withdrawing collateral from CDP
    function testWithdrawCRHappy() public {
        uint collAmount = 30 ether;
        uint withdrawnColl = 5 ether;
        address user = _utils.getNextUserAddress();
        vm.deal(user, type(uint96).max);
        vm.startPrank(user);
        // Calculate borrowed amount. Borrow less because of COLLATERAL_RATIO_DEFENSIVE is used which forces
        // to open more collateralized position
        uint borrowedAmount = _utils.calculateBorrowAmount(
            collAmount,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO_DEFENSIVE
        );
        borrowerOperations.openCdp{value: collAmount}(FEE, borrowedAmount, HINT, HINT);
        // Get new CDP id
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        // Get ICR for CDP:
        uint initialIcr = cdpManager.getCurrentICR(cdpId, priceFeedMock.fetchPrice());
        // Withdraw collateral and make sure ICR changes
        borrowerOperations.withdrawColl(cdpId, withdrawnColl, "hint", "hint");
        uint newIcr = cdpManager.getCurrentICR(cdpId, priceFeedMock.fetchPrice());
        assert(newIcr != initialIcr);
        // Make sure collateral was reduced by `withdrawnColl` amount
        assertEq(collAmount.sub(withdrawnColl), cdpManager.getCdpColl(cdpId));
        vm.stopPrank();
    }

    // Test case for multiple users with random amount of CDPs, withdrawing collateral
    function testWithdrawCRManyUsersManyCdps() public {
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
            // Create multiple CDPs per user
            for (uint cdpIx = 0; cdpIx < AMOUNT_OF_CDPS; cdpIx++) {
                vm.prank(user);
                borrowerOperations.openCdp{value: collAmountChunk}(FEE, borrowedAmount, HINT, HINT);
                cdpIds.push(sortedCdps.cdpOfOwnerByIndex(user, cdpIx));
            }
            _utils.mineBlocks(100);
        }
        // Make TCR snapshot before decreasing collateral
        uint initialTcr = LiquityMath._computeCR(
            borrowerOperations.getEntireSystemColl(),
            borrowerOperations.getEntireSystemDebt(),
            priceFeedMock.fetchPrice()
        );
        // Now, withdraw collateral for each CDP and make sure TCR decreased
        for (uint cdpIx = 0; cdpIx < cdpIds.length; cdpIx++) {
            // Randomize collateral increase amount for each user
            address user = sortedCdps.getOwnerAddress(cdpIds[cdpIx]);
            uint randCollWithdraw = _utils.generateRandomNumber(
                // Max value to withdraw is 20% of collateral
                0.1 ether,
                cdpManager.getCdpColl(cdpIds[cdpIx]).div(5),
                user
            );
            uint initialIcr = cdpManager.getCurrentICR(cdpIds[cdpIx], priceFeedMock.fetchPrice());
            // Withdraw
            vm.prank(user);
            borrowerOperations.withdrawColl(cdpIds[cdpIx], randCollWithdraw, "hint", "hint");
            uint newIcr = cdpManager.getCurrentICR(cdpIds[cdpIx], priceFeedMock.fetchPrice());
            // Make sure ICR for CDP decreased
            assertGt(initialIcr, newIcr);
            _utils.mineBlocks(100);
        }
        // Make sure TCR increased after collateral was added
        uint newTcr = LiquityMath._computeCR(
            borrowerOperations.getEntireSystemColl(),
            borrowerOperations.getEntireSystemDebt(),
            priceFeedMock.fetchPrice()
        );
        assertGt(initialTcr, newTcr);
    }

    // Expect revert if trying to withdraw 0
    function testWithdrawZeroAmnt() public {
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
        vm.expectRevert(
            bytes("BorrowerOps: There must be either a collateral change or a debt change")
        );
        borrowerOperations.withdrawColl(cdpId, 0, HINT, HINT);
        vm.stopPrank();
    }

    /* Test case when user is trying to withraw too much collateral which results in
     * ICR being too low, hence operation is reverted
     */
    function testWithdrawIcrTooLow() public {
        uint collAmount = 30 ether;
        uint withdrawnColl = 10 ether;
        address user = _utils.getNextUserAddress();
        vm.deal(user, type(uint96).max);
        vm.startPrank(user);
        // Calculate borrowed amount
        uint borrowedAmount = _utils.calculateBorrowAmount(
            collAmount,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );
        borrowerOperations.openCdp{value: collAmount}(FEE, borrowedAmount, HINT, HINT);
        // Get new CDP id
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        // Withdraw collateral and make sure operation reverts with ICR < MCR
        vm.expectRevert(
            bytes("BorrowerOps: An operation that would result in ICR < MCR is not permitted")
        );
        borrowerOperations.withdrawColl(cdpId, withdrawnColl, HINT, HINT);
        vm.stopPrank();
    }
}
