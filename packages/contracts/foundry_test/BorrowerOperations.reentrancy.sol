// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;
import "forge-std/Test.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";

/*
 * Test suite that tests exactly one thing: opening CDPs
 * It tests different cases and also does random testing against random coll amounts and amount of users
 */
contract BorrowerOperationsReentrancyTest is eBTCBaseFixture {
    mapping(bytes32 => bool) private _cdpIdsExist;

    function setUp() public override {
        eBTCBaseFixture.setUp();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();
    }

    /// @dev ensure re-entrnacy state is reset in cross-contract sequential call
    /// @dev confirms fix of a bug involving modifiers + proxy delegation functionality
    function test_BorrowerOperationsCallPossibleAfterCdpManagerCall() public {
        address payable[] memory users;
        users = _utils.createUsers(1);
        address user = users[0];

        _dealCollateralAndPrepForUse(user);

        priceFeedMock.setPrice(1e18);

        vm.startPrank(user);
        uint256 borrowedAmount = 5 ether;

        borrowerOperations.openCdp(borrowedAmount, "hint", "hint", 10 ether);
        borrowerOperations.openCdp(borrowedAmount, "hint", "hint", 10 ether);

        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);

        // price drop
        priceFeedMock.setPrice(5e17);

        cdpManager.liquidate(cdpId);

        // price bounces back
        priceFeedMock.setPrice(1e18);
        borrowerOperations.openCdp(borrowedAmount, "hint", "hint", 10 ether);

        vm.stopPrank();
    }
}
