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
    uint256 internal constant COLLATERAL_RATIO_DEFENSIVE = 180e16;  // 200% - defencive CR
    uint internal constant MIN_NET_DEBT = 1800e18;  // Subject to changes once CL is changed

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

    // Generic test for happy case when 1 user open CDP and then closes it
    function testOpenCDPsAndClose() public {
        address payable[] memory users;
        users = _utils.createUsers(1);
        address user = users[0];
        uint borrowedAmount = _utils.calculateBorrowAmount(30 ether, priceFeedMock.fetchPrice(), COLLATERAL_RATIO);
        // Make sure there is no CDPs in the system yet
        vm.startPrank(user);
        borrowerOperations.openCdp{value : 30 ether}(FEE, borrowedAmount, "hint", "hint");
        assertEq(cdpManager.getCdpIdsCount(), 1);

        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        // Borrow for the second time so user has enough eBTC to close their first CDP
        borrowerOperations.openCdp{value : 30 ether}(FEE, borrowedAmount, "hint", "hint");
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
        borrowerOperations.openCdp{value : 10 ether}(FEE, 20000e20, "hint", "hint");
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
        borrowerOperations.openCdp{value : address(user).balance}(FEE, 180e18, "hint", "hint");
    }

    /* Open CDPs for fuzzed amount of users ONLY
    * Checks that each CDP id is unique and the amount of opened CDPs == amount of fuzzed users
    */
    function testCdpsForManyUsers(uint64 amountUsers) public {
        // Skip case when amount of Users is 0
        amountUsers = uint64(bound(amountUsers, 1, 5000));  // up to 5k users

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

    // Open CDPs for fuzzed amount of users. Also fuzz collateral amounts up to high numbers
    function testCdpsForManyUsersManyColl(uint64 amountUsers, uint96 collAmount) public {
        amountUsers = uint64(bound(amountUsers, 1, 5000));  // up to 5k users
        collAmount = uint96(bound(collAmount, 28 ether, 10000000 ether));
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
            // Make sure that each user has now CDP opened
            assertEq(sortedCdps.cdpCountOf(users[userIx]), 1);
            // Check borrowed amount
            assertEq(eBTCToken.balanceOf(users[userIx]), borrowedAmount);
        }
        // Make sure amount of SortedCDPs equals to `amountUsers`
        assertEq(sortedCdps.getSize(), amountUsers);
    }

    /* Open CDPs for fuzzed amount of users with random collateral. Don't restrict coll amount.
    * In case debt is below MIN_NET_DEBT, expect CDP opening to fail, otherwise it should be ok
    */
    function testCdpsForManyUsersManyMinDebtTooLow(uint64 amountUsers, uint96 collAmount) public {
        amountUsers = uint64(bound(amountUsers, 1, 5000));  // up to 50k users
        collAmount = uint96(bound(collAmount, 1 ether, 10000000 ether));
        address payable[] memory users;
        users = _utils.createUsers(amountUsers);

        uint borrowedAmount = _utils.calculateBorrowAmount(
            collAmount, priceFeedMock.fetchPrice(), COLLATERAL_RATIO_DEFENSIVE
        );
        // Net Debt == initial Debt + Fee taken
        uint feeTaken = borrowedAmount.mul(FEE);
        uint borrowedAmountWithFee = borrowedAmount.add(feeTaken);
        // Iterate thru all users and open CDP for each of them
        for (uint userIx = 0; userIx < users.length; userIx++) {
            vm.prank(users[userIx]);
            // If collAmount was too small, debt will not reach threshold, hence system should revert
            if (borrowedAmountWithFee < MIN_NET_DEBT) {
                vm.expectRevert(bytes("BorrowerOps: Cdp's net debt must be greater than minimum"));
                borrowerOperations.openCdp{value : collAmount}(FEE,  borrowedAmount,  "hint",  "hint");
            }
        }
    }

    /* Open CDPs for fuzzed amount of users, fuzzed collateral amounts and fuzzed amount of CDPs per user
    * Testing against large eth numbers because amount of CDPs can be large
    */
    function testCdpsForManyUsersManyCollManyCdps(uint64 amountUsers, uint16 amountCdps, uint96 collAmount) public {
        // amountCdps cannot be 0 to avoid zero div error
        amountCdps = uint16(bound(amountCdps, 1, 200));
        amountUsers = uint64(bound(amountUsers, 1, 5000));
        collAmount = uint96(bound(collAmount, 100000 ether, 10000000 ether));

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
            // Check user balances. Should be Σ of all user's CDPs borrowed eBTC
            assertEq(eBTCToken.balanceOf(users[userIx]), borrowedAmount.mul(amountCdps));
        }
        // Make sure amount of SortedCDPs equals to `amountUsers` multiplied by `amountCDPs`
        assertEq(sortedCdps.getSize(), amountUsers.mul(amountCdps));
    }

}
