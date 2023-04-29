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
    function test_OpenCDPForSelfHappy() public {
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

    function test_OpenCdpForArbitraryUser(address borrower) public {
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
    function test_OpenCDPsAndClose() public {
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
    function test_ICRTooLow() public {
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

    // Fail if Net Debt is too low. Check MIN_NET_DEBT constant
    function xtest_MinNetDebtTooLow() public {
        address payable[] memory users;
        users = _utils.createUsers(2);
        address user = users[0];
        address borrower = users[1];

        vm.startPrank(user);
        vm.deal(user, type(uint96).max);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 10000 ether}();
        assert(sortedCdps.getLast() == "");
        // Borrowed eBTC amount is lower than MIN_NET_DEBT
        vm.expectRevert(bytes("BorrowerOps: Cdp's net debt must be greater than minimum"));
        borrowerOperations.openCdpFor(1e15, "hint", "hint", 30 ether, borrower);
        vm.stopPrank();
    }

    // @dev Attempt to open a CDP with net coll below the minimum allowed and ensure it fails
    // @dev The collateral value passed into the openCdp function is interpretted as netColl + liqudiatorReward. The fixed liqudiator reward is taken out before netColl is checked
    function testMinCollTooLow(uint netColl) public {
        vm.assume(netColl < borrowerOperations.MIN_NET_COLL());

        uint collPlusLiquidatorReward = netColl + borrowerOperations.LIQUIDATOR_REWARD();

        address payable[] memory users;
        users = _utils.createUsers(2);
        address user = users[0];
        address borrower = users[1];

        _dealCollateralAndPrepForUse(user);

        assert(sortedCdps.getLast() == "");

        vm.startPrank(user);
        vm.expectRevert(bytes("BorrowerOps: Cdp's net coll must be greater than minimum"));
        borrowerOperations.openCdpFor(1, "hint", "hint", collPlusLiquidatorReward, borrower);
        vm.stopPrank();
    }

    /// @dev Should not be able to open a CDP for an eBTC system address
    function test_OpenCdpForSystemAddressFails() public {
        // Attempt to open CDP for each system address
    }

    /* Open CDPs for random amount of users
     * Checks that each CDP id is unique and the amount of opened CDPs == amount of users
     */
    function test_CdpsForManyUsers() public {
        uint collAmnt = 30 ether;
        uint borrowedAmount = _utils.calculateBorrowAmount(
            collAmnt,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );
        // Iterate thru all users and open CDP for a new borrower from each of them
        for (uint userIx = 0; userIx < AMOUNT_OF_USERS; userIx++) {
            address user = _utils.getNextUserAddress();
            address borrower = _utils.getNextUserAddress();

            vm.startPrank(user);
            vm.deal(user, type(uint96).max);
            collateral.approve(address(borrowerOperations), type(uint256).max);
            collateral.deposit{value: 10000 ether}();
            borrowerOperations.openCdpFor(borrowedAmount, "hint", "hint", collAmnt, borrower);
            // Get User's CDP and check it for uniqueness
            bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(borrower, 0);
            // Make sure that each new CDP id is unique
            assertEq(_cdpIdsExist[cdpId], false);
            // Set cdp id to exist == true
            _cdpIdsExist[cdpId] = true;
            // Make sure that each user has now CDP opened
            assertEq(sortedCdps.cdpCountOf(borrower), 1);
            // Check borrowed amount
            assertEq(eBTCToken.balanceOf(borrower), borrowedAmount);
            vm.stopPrank();
        }
        // Make sure amount of SortedCDPs equals to `amountUsers`
        assertEq(sortedCdps.getSize(), AMOUNT_OF_USERS);
    }

    /* Open CDPs for random amount of users. Randomize collateral as well for each user separately
     * By randomizing collateral we make sure that each user open CDP with different collAmnt
     */
    function test_CdpsForManyUsersManyColl() public {
        // Iterate thru all users and open CDP for each of them with randomized collateral
        for (uint userIx = 0; userIx < AMOUNT_OF_USERS; userIx++) {
            address user = _utils.getNextUserAddress();
            address borrower = _utils.getNextUserAddress();

            uint collAmount = _utils.generateRandomNumber(28 ether, 10000000 ether, user);
            uint borrowedAmount = _utils.calculateBorrowAmount(
                collAmount,
                priceFeedMock.fetchPrice(),
                COLLATERAL_RATIO
            );

            vm.startPrank(user);
            vm.deal(user, type(uint256).max);

            collateral.approve(address(borrowerOperations), type(uint256).max);
            collateral.deposit{value: 100000000000 ether}();
            borrowerOperations.openCdpFor(borrowedAmount, "hint", "hint", collAmount, borrower);
            // Get User's CDP and check it for uniqueness
            bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(borrower, 0);
            // Make sure that each new CDP id is unique
            assertEq(_cdpIdsExist[cdpId], false);
            // Set cdp id to exist == true
            _cdpIdsExist[cdpId] = true;
            // Make sure that each user has now CDP opened
            assertEq(sortedCdps.cdpCountOf(borrower), 1);
            // Check borrowed amount
            assertEq(eBTCToken.balanceOf(borrower), borrowedAmount);
            // Warp after each user to increase randomness of next collateralAmount
            vm.warp(block.number + 1);
            vm.stopPrank();
        }
        assertEq(sortedCdps.getSize(), AMOUNT_OF_USERS);
    }

    /* Open CDPs for fuzzed amount of users with random collateral. Don't restrict coll amount by bottom.
     * In case debt is below MIN_NET_DEBT, expect CDP opening to fail, otherwise it should be ok
     */
    function test_CdpsForManyUsersManyMinDebtTooLow(uint96 collAmount) public {
        vm.assume(collAmount > 1 ether);
        vm.assume(collAmount < 10000000 ether);

        uint borrowedAmount = _utils.calculateBorrowAmount(
            collAmount,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO_DEFENSIVE
        );
        // Net Debt == initial Debt + Fee taken
        uint feeTaken = borrowedAmount * FEE;
        uint borrowedAmountWithFee = borrowedAmount + feeTaken;

        // Iterate thru all users and open CDP for each of them
        for (uint userIx = 0; userIx < AMOUNT_OF_USERS; userIx++) {
            address user = _utils.getNextUserAddress();
            address borrower = _utils.getNextUserAddress();

            vm.deal(user, 10000000 ether);
            // If collAmount was too small, debt will not reach threshold, hence system should revert
            if (borrowedAmountWithFee < MIN_NET_DEBT) {
                vm.expectRevert(bytes("BorrowerOps: Cdp's net debt must be greater than minimum"));
                vm.prank(user);
                borrowerOperations.openCdpFor(borrowedAmount, "hint", "hint", collAmount, borrower);
            }
        }
    }

    /* Open CDPs for random amount of users, random collateral amounts and random CDPs per user
     * Testing against large eth numbers because amount of CDPs can be large
     */
    function test_CdpsForManyUsersManyCollManyCdps() public {
        // Randomize number of CDPs
        // Iterate thru all users and open CDP for each of them
        for (uint userIx = 0; userIx < AMOUNT_OF_USERS; userIx++) {
            // Create multiple CDPs per user
            address user = _utils.getNextUserAddress();
            address borrower = _utils.getNextUserAddress();

            vm.startPrank(user);
            vm.deal(user, type(uint256).max);

            collateral.approve(address(borrowerOperations), type(uint256).max);
            collateral.deposit{value: 100000000000 ether}();

            // Randomize collateral amount
            uint collAmount = _utils.generateRandomNumber(100000 ether, 10000000 ether, borrower);
            uint collAmountChunk = collAmount / AMOUNT_OF_CDPS;
            uint borrowedAmount = _utils.calculateBorrowAmount(
                collAmountChunk,
                priceFeedMock.fetchPrice(),
                COLLATERAL_RATIO
            );

            for (uint cdpIx = 0; cdpIx < AMOUNT_OF_CDPS; cdpIx++) {
                borrowerOperations.openCdpFor(
                    borrowedAmount,
                    "hint",
                    "hint",
                    collAmountChunk,
                    borrower
                );
                // Get User's CDP and check it for uniqueness
                bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(borrower, cdpIx);
                assertEq(_cdpIdsExist[cdpId], false);
                _cdpIdsExist[cdpId] = true;
            }
            vm.stopPrank();
            // Check user balances. Should be Σ of all user's CDPs borrowed eBTC
            assertEq(eBTCToken.balanceOf(borrower), borrowedAmount * AMOUNT_OF_CDPS);
        }
        // Make sure amount of SortedCDPs equals to `amountUsers` multiplied by `AMOUNT_OF_CDPS`
        assertEq(sortedCdps.getSize(), AMOUNT_OF_USERS * AMOUNT_OF_CDPS);
    }
}
