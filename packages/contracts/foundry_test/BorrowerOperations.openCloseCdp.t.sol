// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.11;

import "forge-std/Test.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";
import {Utilities} from "./utils/Utilities.sol";

/*
 * Test suite that tests opening and closing CDPs
 * It tests different cases and also does random testing against random coll amounts and amount of users
 */
contract CDPOpenCloseTest is eBTCBaseFixture {
    mapping(bytes32 => bool) private _cdpIdsExist;

    Utilities internal _utils;

    function setUp() public override {
        eBTCBaseFixture.setUp();
        eBTCBaseFixture.connectLQTYContracts();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();
        _utils = new Utilities();
    }

    // Generic test for happy case when 1 user open CDP
    function testOpenCDPsHappy() public {
        address payable[] memory users;
        users = _utils.createUsers(1);
        address user = users[0];
        uint borrowedAmount = _utils.calculateBorrowAmount(30 ether, priceFeedMock.fetchPrice(), COLLATERAL_RATIO);
        // Make sure there is no CDPs in the system yet
        assert(sortedCdps.getLast() == "");
        vm.prank(user);
        borrowerOperations.openCdp{value : 30 ether}(FEE, borrowedAmount, HINT, HINT);
        assertEq(cdpManager.getCdpIdsCount(), 1);
        // Make sure valid cdpId returned and user is it's owner
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        assert(cdpId != "");
        assertEq(sortedCdps.getOwnerAddress(cdpId), user);
        // Check user's balance
        assertEq(eBTCToken.balanceOf(user), borrowedAmount);
    }

    // Generic test for happy case when 1 user open CDP and then closes it
    function testOpenCDPsAndClose() public {
        address payable[] memory users;
        users = _utils.createUsers(1);
        address user = users[0];
        uint borrowedAmount = _utils.calculateBorrowAmount(30 ether, priceFeedMock.fetchPrice(), COLLATERAL_RATIO);
        // Make sure there is no CDPs in the system yet
        vm.startPrank(user);
        borrowerOperations.openCdp{value : 30 ether}(FEE, borrowedAmount, HINT, HINT);
        assertEq(cdpManager.getCdpIdsCount(), 1);

        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        // Borrow for the second time so user has enough eBTC to close their first CDP
        borrowerOperations.openCdp{value : 30 ether}(FEE, borrowedAmount, HINT, HINT);
        assertEq(cdpManager.getCdpIdsCount(), 2);

        // Check that user has 2x eBTC balance as they opened 2 CDPs
        assertEq(eBTCToken.balanceOf(user), borrowedAmount.mul(2));

        // Close first CDP
        borrowerOperations.closeCdp(cdpId);
        // Make sure CDP is now not active anymore. Enum Status.2 == closedByOwner
        assertEq(cdpManager.getCdpStatus(cdpId), 2);
        vm.stopPrank();
    }

    // Fail if borrowed eBTC amount is too high
    function testICRTooLow() public {
        address payable[] memory users;
        users = _utils.createUsers(1);
        address user = users[0];
        assert(sortedCdps.getLast() == "");
        vm.prank(user);
        // Borrowed eBTC amount is too high compared to Collateral
        vm.expectRevert(bytes("BorrowerOps: An operation that would result in ICR < MCR is not permitted"));
        borrowerOperations.openCdp{value : 10 ether}(FEE, 20000e20, HINT, HINT);
    }

    // Fail if fee is invalid. Should be between 0.5% and 100%
    function testOpenCdpInvalidFeeFuzzFirst(uint256 fee) public {
        // Fee cannot be > 100%
        fee = uint256(bound(fee, 100e18, 100e25));
        uint borrowedAmount = _utils.calculateBorrowAmount(30 ether, priceFeedMock.fetchPrice(), COLLATERAL_RATIO);
        address payable[] memory users;
        users = _utils.createUsers(1);
        address user = users[0];
        vm.prank(user);
        // Make sure to revert on invalid fee %
        vm.expectRevert(bytes("Max fee percentage must be between 0.5% and 100%"));
        borrowerOperations.openCdp{value : 30 ether}(fee, borrowedAmount, HINT, HINT);
    }

    // Fail if fee is invalid. Should be between 0.5% and 100%
    function testOpenCdpInvalidFeeFuzzSecond(uint256 fee) public {
        // Fee cannot be < 0.5%
        fee = uint256(bound(fee, 1e7, 5e15));
        uint borrowedAmount = _utils.calculateBorrowAmount(30 ether, priceFeedMock.fetchPrice(), COLLATERAL_RATIO);
        address payable[] memory users;
        users = _utils.createUsers(1);
        address user = users[0];
        vm.prank(user);
        // Make sure to revert on invalid fee %
        vm.expectRevert(bytes("Max fee percentage must be between 0.5% and 100%"));
        borrowerOperations.openCdp{value : 30 ether}(fee, borrowedAmount, HINT, HINT);
    }

    // Fail if Net Debt is too low. Check MIN_NET_DEBT constant
    function testMinNetDebtTooLow() public {
        address payable[] memory users;
        users = _utils.createUsers(1);
        address user = users[0];
        assert(sortedCdps.getLast() == "");
        vm.prank(user);
        // Borrowed eBTC amount is lower than MIN_NET_DEBT
        vm.expectRevert(bytes("BorrowerOps: Cdp's net debt must be greater than minimum"));
        borrowerOperations.openCdp{value : address(user).balance}(FEE, 180e18, HINT, HINT);
    }

    /* Open CDPs for random amount of users
    * Checks that each CDP id is unique and the amount of opened CDPs == amount of users
    */
    function testCdpsForManyUsers() public {
        uint collateral = 30 ether;
        uint borrowedAmount = _utils.calculateBorrowAmount(collateral, priceFeedMock.fetchPrice(), COLLATERAL_RATIO);
        // Iterate thru all users and open CDP for each of them
        for (uint userIx = 0; userIx < AMOUNT_OF_USERS; userIx++) {
            address user = _utils.getNextUserAddress();
            vm.deal(user, 10000000 ether);
            vm.prank(user);
            borrowerOperations.openCdp{value : collateral}(FEE, borrowedAmount, HINT, HINT);
            // Get User's CDP and check it for uniqueness
            bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
            // Make sure that each new CDP id is unique
            assertEq(_cdpIdsExist[cdpId], false);
            // Set cdp id to exist == true
            _cdpIdsExist[cdpId] = true;
            // Make sure that each user has now CDP opened
            assertEq(sortedCdps.cdpCountOf(user), 1);
            // Check borrowed amount
            assertEq(eBTCToken.balanceOf(user), borrowedAmount);
            // Warp after each user to increase randomness of next collateralAmount
            vm.warp(block.number + 1);
        }
        // Make sure amount of SortedCDPs equals to `amountUsers`
        assertEq(sortedCdps.getSize(), AMOUNT_OF_USERS);
    }

    /* Open CDPs for random amount of users. Randomize collateral as well for each user separately
     * By randomizing collateral we make sure that each user open CDP with different collAmnt
    */
    function testCdpsForManyUsersManyColl() public {
        // Iterate thru all users and open CDP for each of them with randomized collateral
        for (uint userIx = 0; userIx < AMOUNT_OF_USERS; userIx++) {
            address user = _utils.getNextUserAddress();
            uint collAmount = _utils.generateRandomNumber(
                28 ether, 10000000 ether, user
            );
            uint borrowedAmount = _utils.calculateBorrowAmount(
                collAmount, priceFeedMock.fetchPrice(), COLLATERAL_RATIO
            );
            vm.deal(user, 10000000 ether);
            vm.prank(user);
            borrowerOperations.openCdp{value : collAmount}(FEE,  borrowedAmount,  "hint",  "hint");
            // Get User's CDP and check it for uniqueness
            bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
            // Make sure that each new CDP id is unique
            assertEq(_cdpIdsExist[cdpId], false);
            // Set cdp id to exist == true
            _cdpIdsExist[cdpId] = true;
            // Make sure that each user has now CDP opened
            assertEq(sortedCdps.cdpCountOf(user), 1);
            // Check borrowed amount
            assertEq(eBTCToken.balanceOf(user), borrowedAmount);
            // Warp after each user to increase randomness of next collateralAmount
            vm.warp(block.number + 1);
        }
        assertEq(sortedCdps.getSize(), AMOUNT_OF_USERS);
    }

    /* Open CDPs for fuzzed amount of users with random collateral. Don't restrict coll amount by bottom.
    * In case debt is below MIN_NET_DEBT, expect CDP opening to fail, otherwise it should be ok
    */
    function testCdpsForManyUsersManyMinDebtTooLowFuzz(uint96 collAmount) public {
        collAmount = uint96(bound(collAmount, 1 ether, 10000000 ether));

        uint borrowedAmount = _utils.calculateBorrowAmount(
            collAmount, priceFeedMock.fetchPrice(), COLLATERAL_RATIO_DEFENSIVE
        );
        // Net Debt == initial Debt + Fee taken
        uint feeTaken = borrowedAmount.mul(FEE);
        uint borrowedAmountWithFee = borrowedAmount.add(feeTaken);
        // Iterate thru all users and open CDP for each of them
        for (uint userIx = 0; userIx < AMOUNT_OF_USERS; userIx++) {
            address user = _utils.getNextUserAddress();
            vm.deal(user, 10000000 ether);
            // If collAmount was too small, debt will not reach threshold, hence system should revert
            if (borrowedAmountWithFee < MIN_NET_DEBT) {
                vm.expectRevert(bytes("BorrowerOps: Cdp's net debt must be greater than minimum"));
                vm.prank(user);
                borrowerOperations.openCdp{value : collAmount}(FEE,  borrowedAmount,  "hint",  "hint");
            }
        }
    }

    /* Open CDPs for random amount of users, random collateral amounts and random CDPs per user
    * Testing against large eth numbers because amount of CDPs can be large
    */
    function testCdpsForManyUsersManyCollManyCdps() public {
        // Randomize number of CDPs
        uint amountCdps = _utils.generateRandomNumber(1, 20, msg.sender);
        // Iterate thru all users and open CDP for each of them
        for (uint userIx = 0; userIx < AMOUNT_OF_USERS; userIx++) {
            // Create multiple CDPs per user
            address user = _utils.getNextUserAddress();
            vm.deal(user, 10000000 ether);
            // Randomize collateral amount
            uint collAmount = _utils.generateRandomNumber(100000 ether, 10000000 ether, user);
            uint collAmountChunk = collAmount.div(amountCdps);
            uint borrowedAmount = _utils.calculateBorrowAmount(
                collAmountChunk, priceFeedMock.fetchPrice(), COLLATERAL_RATIO
            );
            for (uint cdpIx = 0; cdpIx < amountCdps; cdpIx++) {
                vm.prank(user);
                borrowerOperations.openCdp{value : collAmountChunk}(FEE,  borrowedAmount,  "hint",  "hint");
                // Get User's CDP and check it for uniqueness
                bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, cdpIx);
                assertEq(_cdpIdsExist[cdpId], false);
                _cdpIdsExist[cdpId] = true;
            }
            // Check user balances. Should be Σ of all user's CDPs borrowed eBTC
            assertEq(eBTCToken.balanceOf(user), borrowedAmount.mul(amountCdps));
            // Warp after each user to increase randomness of next collateralAmount
            vm.warp(block.number + 1);
        }
        // Make sure amount of SortedCDPs equals to `amountUsers` multiplied by `amountCDPs`
        assertEq(sortedCdps.getSize(), AMOUNT_OF_USERS.mul(amountCdps));
    }
}
