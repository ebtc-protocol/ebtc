// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.11;

import "forge-std/Test.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";
import {Utilities} from "./utils/Utilities.sol";

/*
 * Test suite that tests exactly one thing: opening CDPs
 * It tests different cases and also does fuzz testing against fuzzed coll amounts and amount of users
 */
contract CDPTest is eBTCBaseFixture {
    uint private constant FEE = 5e17;
    uint256 internal constant COLLATERAL_RATIO = 160e16;  // 160%: take higher CR as CCR is 150%

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
        borrowerOperations.openCdp{value : 30 ether}(FEE, borrowedAmount, "hint", "hint");
        assertEq(cdpManager.getCdpIdsCount(), 1);
        // Make sure valid cdpId returned and user is it's owner
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        assert(cdpId != "");
        assertEq(sortedCdps.getOwnerAddress(cdpId), user);
        // Check user's balance
        assertEq(eBTCToken.balanceOf(user), borrowedAmount);
    }

    // Fail if borrowed eBTC amount is too high
    function testFailICRTooLow() public {
        address payable[] memory users;
        users = _utils.createUsers(1);
        address user = users[0];
        assert(sortedCdps.getLast() == "");
        vm.prank(user);
        // Borrowed eBTC amount is too high compared to Collateral
        borrowerOperations.openCdp{value : 10 ether}(FEE, 20000e20, "hint", "hint");
    }

    // Fail if Net Debt is too low. Check MIN_NET_DEBT constant
    function testFailMinNetDebtTooLow() public {
        address payable[] memory users;
        users = _utils.createUsers(1);
        address user = users[0];
        assert(sortedCdps.getLast() == "");
        vm.prank(user);
        // Borrowed eBTC amount is lower than MIN_NET_DEBT
        borrowerOperations.openCdp{value : address(user).balance}(FEE, 180e18, "hint", "hint");
    }

    /* Open CDPs for fuzzed amount of users ONLY
    * Checks that each CDP id is unique and the amount of opened CDPs == amount of fuzzed users
    */
    function testCdpsForManyUsers(uint8 amountUsers) public {
        // Skip case when amount of Users is 0
        vm.assume(amountUsers > 1);

        // Populate users
        address payable[] memory users;
        users = _utils.createUsers(amountUsers);

        uint collateral = 30 ether;
        uint borrowedAmount = _utils.calculateBorrowAmount(collateral, priceFeedMock.fetchPrice(), COLLATERAL_RATIO);
        // Iterate thru all users and open CDP for each of them
        for (uint userIx = 0; userIx < users.length; userIx++) {
            vm.prank(users[userIx]);
            borrowerOperations.openCdp{value : collateral}(FEE, borrowedAmount, "hint", "hint");
            // Get User's CDP and check it for uniqueness
            bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(users[userIx], 0);
            // Make sure that each new CDP id is unique
            assertEq(_cdpIdsExist[cdpId], false);
            // Set cdp id to exist == true
            _cdpIdsExist[cdpId] = true;
            // Make sure that each user has now CDP opened
            assertEq(sortedCdps.cdpCountOf(users[userIx]), 1);
            // Check borrowed amount
            assertEq(eBTCToken.balanceOf(users[userIx]), borrowedAmount);
        }
        // Make sure amount of SortedCDPs equals to `amountUsers`
        assertEq(sortedCdps.getSize(), amountUsers);
    }

    /* Open CDPs for fuzzed amount of users. Also fuzz collateral amounts
    * 28 ether and 90 ether boundaries are made so larger borrowers won't drag TCR down too much resulting in errors
    */
    function testCdpsForManyUsersManyColl(uint8 amountUsers, uint96 collAmount) public {
        vm.assume(collAmount > 28 ether && collAmount < 99 ether);
        vm.assume(amountUsers > 1);
        address payable[] memory users;
        users = _utils.createUsers(amountUsers);

        uint borrowedAmount = _utils.calculateBorrowAmount(collAmount, priceFeedMock.fetchPrice(), COLLATERAL_RATIO);
        // Iterate thru all users and open CDP for each of them
        for (uint userIx = 0; userIx < users.length; userIx++) {
            vm.prank(users[userIx]);
            borrowerOperations.openCdp{value : collAmount}(FEE,  borrowedAmount,  "hint",  "hint");
            // Get User's CDP and check it for uniqueness
            bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(users[userIx], 0);
            // Make sure that each new CDP id is unique
            assertEq(_cdpIdsExist[cdpId], false);
            // Set cdp id to exist == true
            _cdpIdsExist[cdpId] = true;
            assertEq(eBTCToken.balanceOf(users[userIx]), borrowedAmount);
        }
        // Make sure amount of SortedCDPs equals to `amountUsers`
        assertEq(sortedCdps.getSize(), amountUsers);
    }

    /* Open CDPs for fuzzed amount of users, fuzzed collateral amounts and fuzzed amount of CDPs per user
    * Testing against large eth numbers because amount of CDPs can be large
    */
    function testCdpsForManyUsersManyCollManyCdps(uint8 amountUsers, uint8 amountCdps, uint96 collAmount) public {
        // amountCdps cannot be 0 to avoid zero div error
        vm.assume(amountCdps > 1 && amountCdps < 10);
        vm.assume(amountUsers > 1);
        vm.assume(collAmount > 1000 ether && collAmount < 10000 ether);

        address payable[] memory users;
        users = _utils.createUsers(amountUsers);
        uint collAmountChunk = collAmount.div(amountCdps);
        uint borrowedAmount = _utils.calculateBorrowAmount(
            collAmountChunk, priceFeedMock.fetchPrice(), COLLATERAL_RATIO
        );
        // Iterate thru all users and open CDP for each of them
        for (uint userIx = 0; userIx < users.length; userIx++) {
            // Create multiple CDPs per user
            for (uint cdpIx = 0; cdpIx < amountCdps; cdpIx++) {
                vm.prank(users[userIx]);
                borrowerOperations.openCdp{value : collAmountChunk}(FEE,  borrowedAmount,  "hint",  "hint");
                // Get User's CDP and check it for uniqueness
                bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(users[userIx], cdpIx);
                assertEq(_cdpIdsExist[cdpId], false);
                _cdpIdsExist[cdpId] = true;
            }
            // Check user balancec. Should be Σ of all user's CDPs borrowed eBTC
            assertEq(eBTCToken.balanceOf(users[userIx]), borrowedAmount.mul(amountCdps));
        }
        // Make sure amount of SortedCDPs equals to `amountUsers` multiplied by `amountCDPs`
        assertEq(sortedCdps.getSize(), amountUsers.mul(amountCdps));
    }

}
