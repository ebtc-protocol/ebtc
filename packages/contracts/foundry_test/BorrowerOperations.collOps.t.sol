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
        uint borrowedAmount = _utils.calculateBorrowAmount(collAmount, priceFeedMock.fetchPrice(), COLLATERAL_RATIO);
        borrowerOperations.openCdp{value : collAmount}(FEE, borrowedAmount, HINT, HINT);
        // Get new CDP id
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        uint coll = cdpManager.getCdpColl(cdpId);
        // Make sure collateral is as expected
        assertEq(collAmount, coll);
        // Get ICR for CDP:
        uint initialIcr = cdpManager.getCurrentICR(cdpId, priceFeedMock.fetchPrice());
        assertGt(initialIcr, MINIMAL_COLLATERAL_RATIO);
        // Add more collateral and make sure ICR changes
        borrowerOperations.addColl{value : collAmount}(cdpId, "hint", "hint");
        uint newIcr = cdpManager.getCurrentICR(cdpId, priceFeedMock.fetchPrice());
        assert(newIcr != initialIcr);
        // Make sure collateral increased by 2x
        assertEq(collAmount.mul(2), cdpManager.getCdpColl(cdpId));
        vm.stopPrank();
    }

    // Fuzzing for collAdd happy case scenario
    function testIncreaseCRHappyFuzz(uint96 collAmount) public {
        // Set min collAmount to avoid zero div error
        collAmount = uint96(bound(collAmount, 1e15, type(uint96).max));
        address user = _utils.getNextUserAddress();
        vm.startPrank(user);
        vm.deal(user, type(uint256).max);
        uint borrowedAmount = _utils.calculateBorrowAmount(
            collAmount, priceFeedMock.fetchPrice(), COLLATERAL_RATIO_DEFENSIVE
        );
        // In case borrowedAmount is less than MIN_NET_DEBT - expect revert
        if (borrowedAmount < MIN_NET_DEBT) {
            vm.expectRevert(bytes("BorrowerOps: Cdp's net debt must be greater than minimum"));
            borrowerOperations.openCdp{value : collAmount}(FEE,  borrowedAmount,  "hint",  "hint");
            return;
        }
        borrowerOperations.openCdp{value : collAmount}(FEE, borrowedAmount, HINT, HINT);
        // Make TCR snapshot before increasing collateral
        uint initialTcr = LiquityMath._computeCR(
            borrowerOperations.getEntireSystemColl(),
            borrowerOperations.getEntireSystemDebt(),
            priceFeedMock.fetchPrice()
        );
        // Get new CDP id
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        uint coll = cdpManager.getCdpColl(cdpId);
        // Make sure collateral is as expected
        assertEq(collAmount, coll);
        // Get ICR for CDP:
        uint initialIcr = cdpManager.getCurrentICR(cdpId, priceFeedMock.fetchPrice());
        assertGt(initialIcr, MINIMAL_COLLATERAL_RATIO);
        // Add more collateral and make sure ICR changes
        borrowerOperations.addColl{value : collAmount}(cdpId, "hint", "hint");
        uint newIcr = cdpManager.getCurrentICR(cdpId, priceFeedMock.fetchPrice());
        assert(newIcr != initialIcr);
        // Make sure collateral increased by 2x
        assertEq(collAmount.mul(2), cdpManager.getCdpColl(cdpId));

        // Make sure TCR increased after collateral was added
        uint newTcr = LiquityMath._computeCR(
            borrowerOperations.getEntireSystemColl(),
            borrowerOperations.getEntireSystemDebt(),
            priceFeedMock.fetchPrice()
        );
        assertGt(newTcr, initialTcr);
        vm.stopPrank();
    }

    // Test case for random-multiple users adding more collateral to their CDPs
    function testIncreaseCRManyUsers() public {
        bytes32[] memory cdpIds = new bytes32[](AMOUNT_OF_USERS);
        for (uint userIx = 0; userIx < AMOUNT_OF_USERS; userIx++) {
            address user = _utils.getNextUserAddress();
            // Random collateral for each user
            uint collAmount = _utils.generateRandomNumber(
                28 ether, 10000000 ether, user
            );
            uint borrowedAmount = _utils.calculateBorrowAmount(
                collAmount, priceFeedMock.fetchPrice(), COLLATERAL_RATIO
            );
            // First, open new CDP
            vm.deal(user, 10100000 ether);
            vm.prank(user);
            borrowerOperations.openCdp{value : collAmount}(FEE, borrowedAmount, HINT, HINT);
            bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
            cdpIds[userIx] = cdpId;
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
            uint randCollIncrease = _utils.generateRandomNumber(
                10 ether, 100000 ether, user
            );
            uint initialIcr = cdpManager.getCurrentICR(cdpIds[cdpIx], priceFeedMock.fetchPrice());
            vm.prank(user);
            // Increase coll by random value
            borrowerOperations.addColl{value : randCollIncrease}(cdpIds[cdpIx], "hint", "hint");
            uint newIcr = cdpManager.getCurrentICR(cdpIds[cdpIx], priceFeedMock.fetchPrice());
            // Make sure ICR for CDP increased
            assertGt(newIcr, initialIcr);
        }
        // Make sure TCR increased after collateral was added
        uint newTcr = LiquityMath._computeCR(
            borrowerOperations.getEntireSystemColl(),
            borrowerOperations.getEntireSystemDebt(),
            priceFeedMock.fetchPrice()
        );
        assertGt(newTcr, initialTcr);
    }

    // Test case for multiple users with random amount of CDPs, adding more collateral
    function testIncreaseCRManyUsersManyCdps() public {
        uint amountCdps = _utils.generateRandomNumber(1, 20, msg.sender);
        bytes32[] memory cdpIds = new bytes32[](AMOUNT_OF_USERS);
        for (uint userIx = 0; userIx < AMOUNT_OF_USERS; userIx++) {
            address user = _utils.getNextUserAddress();
            vm.deal(user, 10100000 ether);
            // Random collateral for each user
            uint collAmount = _utils.generateRandomNumber(
                28 ether, 10000000 ether, user
            );
            uint collAmountChunk = collAmount.div(amountCdps);
            uint borrowedAmount = _utils.calculateBorrowAmount(
                collAmountChunk, priceFeedMock.fetchPrice(), COLLATERAL_RATIO
            );
            // Create multiple CDPs per user
            for (uint cdpIx = 0; cdpIx < amountCdps; cdpIx++) {
                vm.prank(user);
                borrowerOperations.openCdp{value : collAmountChunk}(FEE, borrowedAmount, HINT, HINT);
                bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
                cdpIds[userIx] = cdpId;
            }
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
            uint randCollIncrease = _utils.generateRandomNumber(
                10 ether, 100000 ether, user
            );
            vm.prank(user);
            uint initialIcr = cdpManager.getCurrentICR(cdpIds[cdpIx], priceFeedMock.fetchPrice());
            // Increase coll by random value
            vm.prank(user);
            borrowerOperations.addColl{value : randCollIncrease}(cdpIds[cdpIx], "hint", "hint");
            uint newIcr = cdpManager.getCurrentICR(cdpIds[cdpIx], priceFeedMock.fetchPrice());
            // Make sure ICR for CDP increased
            assertGt(newIcr, initialIcr);
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

    // Happy case for borrowing and withdrawing collateral within CDP
    function testWithdrawCRHappy() public {
        uint collAmount = 30 ether;
        uint withdrawnColl = 5 ether;
        address user = _utils.getNextUserAddress();
        vm.deal(user, type(uint96).max);
        vm.startPrank(user);
        // Calculate borrowed amount. Borrow less because of COLLATERAL_RATIO_DEFENSIVE is used which forces
        // to open more collateralized position
        uint borrowedAmount = _utils.calculateBorrowAmount(
            collAmount, priceFeedMock.fetchPrice(), COLLATERAL_RATIO_DEFENSIVE
        );
        borrowerOperations.openCdp{value : collAmount}(FEE, borrowedAmount, HINT, HINT);
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

    // Happy case for borrowing and withdrawing collateral within CDP for many users
    function testWithdrawCRManyUsers() public {
        bytes32[] memory cdpIds = new bytes32[](AMOUNT_OF_USERS);
        uint[] memory collateralsUsed = new uint[](AMOUNT_OF_USERS);
        for (uint userIx = 0; userIx < AMOUNT_OF_USERS; userIx++) {
            address user = _utils.getNextUserAddress();
            // Random collateral for each user
            uint collAmount = _utils.generateRandomNumber(
                50 ether, 10000000 ether, user
            );
            vm.deal(user, type(uint96).max);
            vm.startPrank(user);
            uint borrowedAmount = _utils.calculateBorrowAmount(
                collAmount, priceFeedMock.fetchPrice(), COLLATERAL_RATIO_DEFENSIVE
            );
            borrowerOperations.openCdp{value : collAmount}(FEE, borrowedAmount, HINT, HINT);
            // Collect all cdpIds into array
            cdpIds[userIx] = sortedCdps.cdpOfOwnerByIndex(user, 0);
            collateralsUsed[userIx] = collAmount;
            vm.stopPrank();
        }
        // Make TCR snapshot before decreasing collateral
        uint initialTcr = LiquityMath._computeCR(
            borrowerOperations.getEntireSystemColl(),
            borrowerOperations.getEntireSystemDebt(),
            priceFeedMock.fetchPrice()
        );
        // Now, withdraw collateral from each CDP and make sure TCR declined
        for (uint cdpIx = 0; cdpIx < cdpIds.length; cdpIx++) {
            address user = sortedCdps.getOwnerAddress(cdpIds[cdpIx]);
            uint collToWithdrawLimit = _utils.findMin(collateralsUsed);
            // Use minimal coll amount borrowed to withdraw to not end up with ICR < MCR error
            uint randCollWithdraw = _utils.generateRandomNumber(
                0.1 ether, collToWithdrawLimit.sub(10 ether), user
            );
            uint initialIcr = cdpManager.getCurrentICR(cdpIds[cdpIx], priceFeedMock.fetchPrice());
            vm.prank(user);
            borrowerOperations.withdrawColl(cdpIds[cdpIx], randCollWithdraw, "hint", "hint");
            uint newIcr = cdpManager.getCurrentICR(cdpIds[cdpIx], priceFeedMock.fetchPrice());
            // Make sure ICR for CDP decreased after coll withdrawal
            assertGt(initialIcr, newIcr);
        }
        // Make sure TCR decreased after collateral was added
        uint newTcr = LiquityMath._computeCR(
            borrowerOperations.getEntireSystemColl(),
            borrowerOperations.getEntireSystemDebt(),
            priceFeedMock.fetchPrice()
        );
        assertGt(initialTcr, newTcr);
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
            collAmount, priceFeedMock.fetchPrice(), COLLATERAL_RATIO
        );
        borrowerOperations.openCdp{value : collAmount}(FEE, borrowedAmount, HINT, HINT);
        // Get new CDP id
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        // Withdraw collateral and make sure operation reverts with ICR < MCR
        vm.expectRevert(bytes("BorrowerOps: An operation that would result in ICR < MCR is not permitted"));
        borrowerOperations.withdrawColl(cdpId, withdrawnColl, "hint", "hint");
        vm.stopPrank();
    }
}
