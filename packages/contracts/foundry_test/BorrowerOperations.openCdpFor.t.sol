// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;
import "forge-std/Test.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";

/*
 * Test suite that tests exactly one thing: opening CDPs
 * It tests different cases and also does random testing against random coll amounts and amount of users
 */
contract BorrowerOperationsOpenCdpForTest is eBTCBaseFixture {
    mapping(bytes32 => bool) private _cdpIdsExist;

    function setUp() public override {
        eBTCBaseFixture.setUp();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();
    }

    // Generic test for happy case when 1 user open CDP
    function testOpenCDPForSelfHappy() public {
        address payable[] memory users;
        users = _utils.createUsers(1);
        address user = users[0];
        vm.startPrank(user);
        vm.deal(user, type(uint96).max);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 10000 ether}();
        uint borrowedAmount = _utils.calculateBorrowAmount(
            30 ether,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );
        // Make sure there is no CDPs in the system yet
        assert(sortedCdps.getLast() == "");

        borrowerOperations.openCdpFor(borrowedAmount, "hint", "hint", 30 ether, user);
        assertEq(cdpManager.getCdpIdsCount(), 1);
        // Make sure valid cdpId returned and user is it's owner
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        assert(cdpId != "");
        assertEq(sortedCdps.getOwnerAddress(cdpId), user);
        // Check user's balance
        assertEq(eBTCToken.balanceOf(user), borrowedAmount);
        vm.stopPrank();
    }

    function test_openCdpForArbitraryUser(address borrower) public {
        address payable[] memory users;
        users = _utils.createUsers(1);
        address user = users[0];
        vm.assume(borrower != user);

        vm.startPrank(user);
        vm.deal(user, type(uint96).max);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 10000 ether}();
        uint borrowedAmount = _utils.calculateBorrowAmount(
            30 ether,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );
        // Make sure there is no CDPs in the system yet
        assert(sortedCdps.getLast() == "");

        borrowerOperations.openCdpFor(borrowedAmount, "hint", "hint", 30 ether, borrower);
        assertEq(cdpManager.getCdpIdsCount(), 1);
        // Make sure valid cdpId returned and borrower is it's owner
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(borrower, 0);
        assert(cdpId != "");
        assertEq(sortedCdps.getOwnerAddress(cdpId), borrower);
        assertTrue(sortedCdps.getOwnerAddress(cdpId) != user);
        // Check user's balance
        assertEq(eBTCToken.balanceOf(borrower), borrowedAmount);
        assertEq(eBTCToken.balanceOf(user), 0);

        vm.stopPrank();
    }

    // Generic test for happy case when 1 user open CDP and then closes it
    function testOpenCDPsAndClose() public {
        address payable[] memory users;
        users = _utils.createUsers(2);
        address user = users[0];
        address borrower = users[1];
        vm.startPrank(user);
        vm.deal(user, type(uint96).max);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 10000 ether}();
        uint borrowedAmount = _utils.calculateBorrowAmount(
            30 ether,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );
        // Make sure there is no CDPs in the system yet
        borrowerOperations.openCdpFor(borrowedAmount, "hint", "hint", 30 ether, borrower);
        assertEq(cdpManager.getCdpIdsCount(), 1);

        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(borrower, 0);
        // Borrow for the second time so user has enough eBTC to close their first CDP
        borrowerOperations.openCdpFor(borrowedAmount, "hint", "hint", 30 ether, borrower);
        assertEq(cdpManager.getCdpIdsCount(), 2);
        vm.stopPrank();

        // Check that user has 2x eBTC balance as they opened 2 CDPs
        assertEq(eBTCToken.balanceOf(borrower), borrowedAmount * 2);

        // Close first CDP
        vm.prank(borrower);
        borrowerOperations.closeCdp(cdpId);

        // Make sure CDP is now not active anymore. Enum Status.2 == closedByOwner
        assertEq(cdpManager.getCdpStatus(cdpId), 2);
    }

    // Fail if borrowed eBTC amount is too high
    function testICRTooLow() public {
        address payable[] memory users;
        users = _utils.createUsers(2);
        address user = users[0];
        address borrower = users[1];
        vm.startPrank(user);
        vm.deal(user, type(uint96).max);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 10000 ether}();
        assert(sortedCdps.getLast() == "");
        // Borrowed eBTC amount is too high compared to Collateral
        vm.expectRevert(
            bytes("BorrowerOps: An operation that would result in ICR < MCR is not permitted")
        );
        borrowerOperations.openCdpFor(20000e20, "hint", "hint", 10 ether, borrower);
        vm.stopPrank();
    }

    function testLeverageHappy() public {}
}
