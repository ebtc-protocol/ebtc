// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.11;

import "forge-std/Test.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";
import {Utilities} from "./utils/Utilities.sol";

contract CDPTest is eBTCBaseFixture {
    uint private constant FEE = 5e17;
    uint256 internal constant COLLATERAL_RATIO = 160e16;  // 160% take higher CR as CCR is 150%

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
        borrowerOperations.openCdp{value : address(user).balance}(FEE, borrowedAmount, "hint", "hint");
        assertEq(cdpManager.getCdpIdsCount(), 1);
        // Make sure valid cdpId returned
        assert(sortedCdps.getLast() != "");
    }

    // Fail if borrowed eBTC amount is too high
    function testFailICRTooLow() public {
        address payable[] memory users;
        users = _utils.createUsers(1);
        address user = users[0];
        assert(sortedCdps.getLast() == "");
        vm.prank(user);
        // Borrowed eBTC amount is too high compared to Collateral
        borrowerOperations.openCdp{value : address(user).balance}(FEE, 20000e20, "hint", "hint");
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
    Checks that each CDP id is unique and the amount of opened CDPs == amount of fuzzed users
    */
    function testCdpsForManyUsersFixedCR(uint8 amountUsers) public {
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
            uint256 currentCdpNonce = sortedCdps.nextCdpNonce() - 1;  // Next nonce is always incremented
            bytes32 cdpId = sortedCdps.toCdpId(users[userIx], block.number,  currentCdpNonce);
            // Make sure that each new CDP id is unique
            assertEq(_cdpIdsExist[cdpId], false);
            // Set cdp id to exist == true
            _cdpIdsExist[cdpId] = true;
            // Make sure that each user has now CDP opened
            assertEq(sortedCdps.cdpCountOf(users[userIx]), 1);
        }
        // Make sure amount of SortedCDPs equals to `amountUsers`
        assertEq(sortedCdps.getSize(), amountUsers);
    }

    /* Open CDPs for fuzzed amount of users. Also fuzz collateral amounts
    28 ether and 90 ether boundaries are made so larger borrowers won't drag TTR down too much resulting in errors
    */
    function testCdpsForManyUsersFixedCR(uint8 amountUsers, uint96 collAmount) public {
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
            uint256 currentCdpNonce = sortedCdps.nextCdpNonce() - 1;  // Next nonce is always incremented
            bytes32 cdpId = sortedCdps.toCdpId(users[userIx], block.number,  currentCdpNonce);
            // Make sure that each new CDP id is unique
            assertEq(_cdpIdsExist[cdpId], false);
            // Set cdp id to exist == true
            _cdpIdsExist[cdpId] = true;
        }
        // Make sure amount of SortedCDPs equals to `amountUsers`
        assertEq(sortedCdps.getSize(), amountUsers);
    }
}
