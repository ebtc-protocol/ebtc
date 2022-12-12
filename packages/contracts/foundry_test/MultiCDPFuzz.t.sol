// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.11;

import "forge-std/Test.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";
import {Utilities} from "./utils/Utilities.sol";

contract CDPTest is eBTCBaseFixture {
    uint256 internal _collateralRatio = 160e16;  // 160% take higher CR as CCR is 150%
    Utilities internal _utils;
    mapping(bytes32 => bool) private _cdpIdsExist;

    function setUp() public override {
        eBTCBaseFixture.setUp();
        eBTCBaseFixture.connectLQTYContracts();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();
        _utils = new Utilities();
    }

    /* Open CDPs for fuzzed amount of users
    Checks that each CDP id is unique and the amount of opened CDPs == amount of fuzzed users
    */
    function testCdpsForManyUsersFixedCR(uint8 amountUsers) public {
        // Skip case when amount of Users is 0
        vm.assume(amountUsers > 1);

        // Populate users
        address payable[] memory users;
        users = _utils.createUsers(amountUsers);

        uint collateral = 30 ether;
        uint borrowedAmount = _utils.calculateBorrowAmount(collateral, priceFeedMock.fetchPrice(), _collateralRatio);
        // Iterate thru all users and open CDP for each of them
        for (uint userIx = 0; userIx < users.length; userIx++) {
            vm.deal(users[userIx], 300 ether);
            vm.prank(users[userIx]);
            borrowerOperations.openCdp{value : collateral}(
                5e17,
                borrowedAmount,
                "some hint",
                "some hint"
            );
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
        uint cdpAmount = sortedCdps.getSize();
        assertEq(cdpAmount, amountUsers);
    }
}
