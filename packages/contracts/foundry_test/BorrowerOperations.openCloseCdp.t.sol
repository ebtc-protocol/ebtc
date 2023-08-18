// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;
import "forge-std/Test.sol";

import {eBTCBaseFixture} from "./BaseFixture.sol";
import {Properties} from "../contracts/TestContracts/invariants/Properties.sol";

/*
 * Test suite that tests exactly one thing: opening CDPs
 * It tests different cases and also does random testing against random coll amounts and amount of users
 */
contract CDPTest is eBTCBaseFixture, Properties {
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
        uint borrowedAmount = _utils.calculateBorrowAmount(
            30 ether,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );
        // Make sure there is no CDPs in the system yet
        assert(sortedCdps.getLast() == "");

        borrowerOperations.openCdp(borrowedAmount, "hint", "hint", 30 ether);
        assertEq(cdpManager.getCdpIdsCount(), 1);
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
        uint borrowedAmount = _utils.calculateBorrowAmount(
            30 ether,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );
        // Make sure there is no CDPs in the system yet
        borrowerOperations.openCdp(borrowedAmount, "hint", "hint", 30 ether);
        assertEq(cdpManager.getCdpIdsCount(), 1);

        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        // Borrow for the second time so user has enough eBTC to close their first CDP
        borrowerOperations.openCdp(borrowedAmount, "hint", "hint", 30 ether);
        assertEq(cdpManager.getCdpIdsCount(), 2);

        // Check that user has 2x eBTC balance as they opened 2 CDPs
        assertEq(eBTCToken.balanceOf(user), borrowedAmount * 2);

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
    function testMinCollTooLow(uint netColl) public {
        vm.assume(netColl < borrowerOperations.MIN_NET_COLL());

        uint collPlusLiquidatorReward = netColl + borrowerOperations.LIQUIDATOR_REWARD();

        address payable[] memory users;
        users = _utils.createUsers(1);
        address user = users[0];

        _dealCollateralAndPrepForUse(user);

        assert(sortedCdps.getLast() == "");

        vm.startPrank(user);
        vm.expectRevert(bytes("BorrowerOperations: Cdp's net coll must be greater than minimum"));
        borrowerOperations.openCdp(1, "hint", "hint", collPlusLiquidatorReward);
        vm.stopPrank();
    }

    /* Open CDPs for random amount of users
     * Checks that each CDP id is unique and the amount of opened CDPs == amount of users
     */
    function testCdpsForManyUsers() public {
        uint collAmnt = 30 ether;
        uint borrowedAmount = _utils.calculateBorrowAmount(
            collAmnt,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );
        // Iterate thru all users and open CDP for each of them
        for (uint userIx = 0; userIx < AMOUNT_OF_USERS; userIx++) {
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
        for (uint userIx = 0; userIx < AMOUNT_OF_USERS; userIx++) {
            address user = _utils.getNextUserAddress();
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
            vm.warp(block.number + 1);
            vm.stopPrank();
        }
        assertEq(sortedCdps.getSize(), AMOUNT_OF_USERS);
    }

    /* Open CDPs for fuzzed amount of users with random collateral. Don't restrict coll amount by bottom.
     * In case debt is below MIN_NET_DEBT, expect CDP opening to fail, otherwise it should be ok
     */
    function testCdpsForManyUsersManyMinDebtTooLow(uint96 collAmount) public {
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
        for (uint userIx = 0; userIx < AMOUNT_OF_USERS; userIx++) {
            // Create multiple CDPs per user
            address user = _utils.getNextUserAddress();
            vm.startPrank(user);
            vm.deal(user, type(uint256).max);
            collateral.approve(address(borrowerOperations), type(uint256).max);
            collateral.deposit{value: 100000000000 ether}();
            // Randomize collateral amount
            uint collAmount = _utils.generateRandomNumber(100000 ether, 10000000 ether, user);
            uint collAmountChunk = collAmount / AMOUNT_OF_CDPS;
            uint borrowedAmount = _utils.calculateBorrowAmount(
                collAmountChunk,
                priceFeedMock.fetchPrice(),
                COLLATERAL_RATIO
            );
            for (uint cdpIx = 0; cdpIx < AMOUNT_OF_CDPS; cdpIx++) {
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
    }

    function testCdpsOpenRebaseClose() public {
        address user = _utils.getNextUserAddress();
        vm.startPrank(user);
        vm.deal(user, type(uint256).max);

        uint256 coll = borrowerOperations.MIN_NET_COLL() +
            borrowerOperations.LIQUIDATOR_REWARD() +
            16;

        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: coll}();

        bytes32 _cdpId = borrowerOperations.openCdp(1, HINT, HINT, coll);
        collateral.setEthPerShare(1.015149924993973008e18);

        // TODO uncomment these lines after this issue is fixed: https://github.com/Badger-Finance/ebtc-fuzz-review/issues/1
        // vm.expectRevert("CdpManager: Only one cdp in the system");
        // borrowerOperations.closeCdp(_cdpId);
    }

    function testOpenCdpMustNotTriggerRecoveryMode() public {
        address user = _utils.getNextUserAddress();
        vm.startPrank(user);
        uint256 funds = type(uint96).max;
        vm.deal(user, funds);
        collateral.approve(address(borrowerOperations), funds);
        collateral.deposit{value: funds}();

        uint price = priceFeedMock.getPrice();

        // openCdp
        collateral.approve(address(borrowerOperations), 2200000000000000016);
        bytes32 _cdpId = borrowerOperations.openCdp(1, bytes32(0), bytes32(0), 2200000000000000016);

        // addColl
        collateral.approve(address(borrowerOperations), 19055591963114510547);
        borrowerOperations.addColl(_cdpId, _cdpId, _cdpId, 19055591963114510547);

        // withdrawEBTC
        borrowerOperations.withdrawEBTC(_cdpId, 1184219647878146906, _cdpId, _cdpId);

        // setEthPerShare
        collateral.setEthPerShare(926216476604259366);

        // setEthPerShare
        collateral.setEthPerShare(842014978731144878);

        bool isRecoveryModeBefore = cdpManager.checkRecoveryMode(priceFeedMock.getPrice());
        // openCdp
        collateral.approve(address(borrowerOperations), 2200000000000000016);
        borrowerOperations.openCdp(1, bytes32(0), bytes32(0), 2200000000000000016);

        bool isRecoveryModeAfter = cdpManager.checkRecoveryMode(priceFeedMock.getPrice());

        assertTrue(!isRecoveryModeBefore ? !isRecoveryModeAfter : true, GENERAL_01);
    }

    function testCloseCdpGetGasRefund() public {
        address user = _utils.getNextUserAddress();
        vm.startPrank(user);
        uint256 funds = type(uint96).max;
        vm.deal(user, funds);
        collateral.approve(address(borrowerOperations), funds);
        collateral.deposit{value: funds}();

        uint _price = priceFeedMock.getPrice();

        //   setEthPerShare 910635822138744547
        //   openCdp 2200000000000000016 1
        //   addColl 94021985275614476877 0
        //   openCdp 2200000000000000016 1
        //   closeCdp 0

        collateral.setEthPerShare(910635822138744547);
        bytes32 _cdpId = borrowerOperations.openCdp(1, bytes32(0), bytes32(0), 2200000000000000016);
        borrowerOperations.addColl(_cdpId, _cdpId, _cdpId, 94021985275614476877);
        borrowerOperations.openCdp(1, bytes32(0), bytes32(0), 2200000000000000016);

        uint256 userCollBefore = collateral.balanceOf(user);
        uint256 cdpCollBefore = cdpManager.getCdpColl(_cdpId);
        uint256 liquidatorRewardSharesBefore = cdpManager.getCdpLiquidatorRewardShares(_cdpId);

        borrowerOperations.closeCdp(_cdpId);

        uint256 userCollAfter = collateral.balanceOf(user);

        console.log("before", userCollBefore, cdpCollBefore, liquidatorRewardSharesBefore);
        console.log("after", userCollAfter);

        assertTrue(
            // not exact due to rounding errors
            isApproximateEq(
                userCollBefore + cdpCollBefore + liquidatorRewardSharesBefore,
                userCollAfter,
                0.01e18
            ),
            BO_05
        );
    }
}
