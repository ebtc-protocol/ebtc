// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;
import "forge-std/Test.sol";
import {eBTCBaseInvariants} from "./BaseInvariants.sol";
import {CdpManager} from "../contracts/CdpManager.sol";

/*
 * Test suite that tests exactly one thing: opening CDPs
 * It tests different cases and also does random testing against random coll amounts and amount of users
 */
contract OpenCloseCdpTest is eBTCBaseInvariants {
    mapping(bytes32 => bool) private _cdpIdsExist;

    function setUp() public override {
        super.setUp();

        connectCoreContracts();
        connectLQTYContractsToCore();
    }

    // Generic test for happy case when 1 user open CDP
    function testOpenCDPsHappy() public {
        address payable[] memory users;
        users = _utils.createUsers(1);
        address user = users[0];

        _dealCollateralAndPrepForUse(user);

        vm.startPrank(user);
        uint256 borrowedAmount = _utils.calculateBorrowAmount(
            30 ether,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );
        // Make sure there is no CDPs in the system yet
        assert(sortedCdps.getLast() == "");

        borrowerOperations.openCdp(borrowedAmount, "hint", "hint", 30 ether);
        assertEq(cdpManager.getActiveCdpsCount(), 1);
        // Make sure valid cdpId returned and user is it's owner
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        assert(cdpId != "");
        assertEq(sortedCdps.getOwnerAddress(cdpId), user);
        // Check user's balance
        assertEq(eBTCToken.balanceOf(user), borrowedAmount);
        vm.stopPrank();
    }

    // Generic test for happy case when 1 user open CDP and then closes it
    function testOpenCDPsAndClose() public {
        address payable[] memory users;
        users = _utils.createUsers(1);
        address user = users[0];

        _dealCollateralAndPrepForUse(user);

        vm.startPrank(user);
        uint256 borrowedAmount = _utils.calculateBorrowAmount(
            30 ether,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );
        // Make sure there is no CDPs in the system yet
        borrowerOperations.openCdp(borrowedAmount, "hint", "hint", 30 ether);
        assertEq(cdpManager.getActiveCdpsCount(), 1);

        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        // Borrow for the second time so user has enough eBTC to close their first CDP
        borrowerOperations.openCdp(borrowedAmount, "hint", "hint", 30 ether);
        assertEq(cdpManager.getActiveCdpsCount(), 2);

        // Check that user has 2x eBTC balance as they opened 2 CDPs
        assertEq(eBTCToken.balanceOf(user), borrowedAmount * 2);

        // Close first CDP
        borrowerOperations.closeCdp(cdpId);
        // Make sure CDP is now not active anymore. Enum Status.2 == closedByOwner
        assertEq(cdpManager.getCdpStatus(cdpId), 2);
        _assertCdpClosed(cdpId, 2);
        _assertCdpNotInSortedCdps(cdpId);
        vm.stopPrank();
    }

    // Fail if borrowed eBTC amount is too high
    function testICRTooLow() public {
        address payable[] memory users;
        users = _utils.createUsers(1);
        address user = users[0];

        _dealCollateralAndPrepForUse(user);
        assert(sortedCdps.getLast() == "");

        vm.startPrank(user);
        // Borrowed eBTC amount is too high compared to Collateral
        vm.expectRevert(
            bytes("BorrowerOperations: An operation that would result in ICR < MCR is not permitted")
        );
        borrowerOperations.openCdp(20000e20, "hint", "hint", 10 ether);
        vm.stopPrank();
    }

    // Fail if Net Debt is too low. Check MIN_NET_DEBT constant
    function xtestMinNetDebtTooLow() public {
        address payable[] memory users;
        users = _utils.createUsers(1);
        address user = users[0];

        vm.startPrank(user);
        _dealCollateralAndPrepForUse(user);

        assert(sortedCdps.getLast() == "");
        // Borrowed eBTC amount is lower than MIN_NET_DEBT
        vm.expectRevert(bytes("BorrowerOperations: Cdp's net debt must be greater than minimum"));
        borrowerOperations.openCdp(1e15, "hint", "hint", 30 ether);
        vm.stopPrank();
    }

    // @dev Attempt to open a CDP with net coll below the minimum allowed and ensure it fails
    // @dev The collateral value passed into the openCdp function is interpretted as netColl + liqudiatorReward. The fixed liqudiator reward is taken out before netColl is checked
    function testMinCollTooLow(uint256 netColl) public {
        netColl = bound(netColl, 0, borrowerOperations.MIN_NET_STETH_BALANCE() - 1);

        uint256 collPlusLiquidatorReward = netColl + borrowerOperations.LIQUIDATOR_REWARD();

        address payable[] memory users;
        users = _utils.createUsers(1);
        address user = users[0];

        _dealCollateralAndPrepForUse(user);

        assert(sortedCdps.getLast() == "");

        vm.startPrank(user);
        vm.expectRevert(
            bytes("BorrowerOperations: Cdp's net stEth balance must not fall below minimum")
        );
        borrowerOperations.openCdp(minChange, "hint", "hint", collPlusLiquidatorReward);
        vm.stopPrank();
    }

    /* Open CDPs for random amount of users
     * Checks that each CDP id is unique and the amount of opened CDPs == amount of users
     */
    function testCdpsForManyUsers() public {
        uint256 collAmnt = 30 ether;
        uint256 borrowedAmount = _utils.calculateBorrowAmount(
            collAmnt,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );
        // Iterate thru all users and open CDP for each of them
        for (uint256 userIx = 0; userIx < AMOUNT_OF_USERS; userIx++) {
            address user = _utils.getNextUserAddress();

            _dealCollateralAndPrepForUse(user);
            vm.startPrank(user);

            borrowerOperations.openCdp(borrowedAmount, "hint", "hint", collAmnt);
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
            vm.stopPrank();
        }
        // Make sure amount of SortedCDPs equals to `amountUsers`
        assertEq(sortedCdps.getSize(), AMOUNT_OF_USERS);
    }

    /* Open CDPs for random amount of users. Randomize collateral as well for each user separately
     * By randomizing collateral we make sure that each user open CDP with different collAmnt
     */
    function testCdpsForManyUsersManyColl() public {
        // Iterate thru all users and open CDP for each of them with randomized collateral
        for (uint256 userIx = 0; userIx < AMOUNT_OF_USERS; userIx++) {
            address user = _utils.getNextUserAddress();
            uint256 collAmount = _utils.generateRandomNumber(28 ether, 10000000 ether, user);
            uint256 borrowedAmount = _utils.calculateBorrowAmount(
                collAmount,
                priceFeedMock.fetchPrice(),
                COLLATERAL_RATIO
            );
            vm.startPrank(user);
            vm.deal(user, type(uint256).max);
            collateral.approve(address(borrowerOperations), type(uint256).max);
            collateral.deposit{value: 100000000000 ether}();
            borrowerOperations.openCdp(borrowedAmount, "hint", "hint", collAmount);
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
            vm.warp(block.timestamp + 1);
            vm.stopPrank();
        }
        assertEq(sortedCdps.getSize(), AMOUNT_OF_USERS);
        _ensureSystemInvariants();
    }

    /* Open CDPs for fuzzed amount of users with random collateral. Don't restrict coll amount by bottom.
     * In case debt is below MIN_NET_DEBT, expect CDP opening to fail, otherwise it should be ok
     */
    function testCdpsForManyUsersManyMinDebtTooLow(uint96 collAmount) public {
        collAmount = uint96(bound(collAmount, 1 ether, 10000000 ether));

        uint256 borrowedAmount = _utils.calculateBorrowAmount(
            collAmount,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO_DEFENSIVE
        );
        // Net Debt == initial Debt + Fee taken
        uint256 feeTaken = borrowedAmount * FEE;
        uint256 borrowedAmountWithFee = borrowedAmount + feeTaken;
        // Iterate thru all users and open CDP for each of them
        for (uint256 userIx = 0; userIx < AMOUNT_OF_USERS; userIx++) {
            address user = _utils.getNextUserAddress();
            vm.deal(user, 10000000 ether);
            // If collAmount was too small, debt will not reach threshold, hence system should revert
            if (borrowedAmountWithFee < MIN_NET_DEBT) {
                vm.expectRevert(
                    bytes("BorrowerOperations: Cdp's net debt must be greater than minimum")
                );
                vm.prank(user);
                borrowerOperations.openCdp(borrowedAmount, "hint", "hint", collAmount);
            }
        }
    }

    /* Open CDPs for random amount of users, random collateral amounts and random CDPs per user
     * Testing against large eth numbers because amount of CDPs can be large
     */
    function testCdpsForManyUsersManyCollManyCdps() public {
        // Randomize number of CDPs
        // Iterate thru all users and open CDP for each of them
        for (uint256 userIx = 0; userIx < AMOUNT_OF_USERS; userIx++) {
            // Create multiple CDPs per user
            address user = _utils.getNextUserAddress();
            vm.startPrank(user);
            vm.deal(user, type(uint256).max);
            collateral.approve(address(borrowerOperations), type(uint256).max);
            collateral.deposit{value: 100000000000 ether}();
            // Randomize collateral amount
            uint256 collAmount = _utils.generateRandomNumber(100000 ether, 10000000 ether, user);
            uint256 collAmountChunk = collAmount / AMOUNT_OF_CDPS;
            uint256 borrowedAmount = _utils.calculateBorrowAmount(
                collAmountChunk,
                priceFeedMock.fetchPrice(),
                COLLATERAL_RATIO
            );
            for (uint256 cdpIx = 0; cdpIx < AMOUNT_OF_CDPS; cdpIx++) {
                borrowerOperations.openCdp(borrowedAmount, "hint", "hint", collAmountChunk);
                // Get User's CDP and check it for uniqueness
                bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, cdpIx);
                assertEq(_cdpIdsExist[cdpId], false);
                _cdpIdsExist[cdpId] = true;
            }
            vm.stopPrank();
            // Check user balances. Should be Σ of all user's CDPs borrowed eBTC
            assertEq(eBTCToken.balanceOf(user), borrowedAmount * AMOUNT_OF_CDPS);
        }
        // Make sure amount of SortedCDPs equals to `amountUsers` multiplied by `AMOUNT_OF_CDPS`
        assertEq(sortedCdps.getSize(), AMOUNT_OF_USERS * AMOUNT_OF_CDPS);
        _ensureSystemInvariants();
    }

    // test for overflow Liquidator Reward Share
    function testOverflowLiquidatorRewardShare() public {
        address payable[] memory users = _utils.createUsers(1);
        address user = users[0];

        CdpManager _dummyCdpMgr = new CdpManager(
            user,
            user,
            user,
            user,
            user,
            user,
            user,
            user,
            address(collateral)
        );

        vm.startPrank(user);

        uint256 _overflowedLRS = type(uint128).max;
        vm.expectRevert("EbtcMath: downcast to uint128 will overflow");
        _dummyCdpMgr.initializeCdp(bytes32(0), 1000, 2e18, (_overflowedLRS + 1), user);

        vm.stopPrank();
    }
}
