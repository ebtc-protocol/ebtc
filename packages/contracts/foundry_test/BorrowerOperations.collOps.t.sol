// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";

/*
 * Test suite that tests opened CDPs with two different operations: addColl and withdrawColl
 * Test include testing different metrics such as each CDP ICR, also TCR changes after operations are executed
 */
contract CDPOpsTest is eBTCBaseFixture {
    // Storage array of cdpIDs when impossible to calculate array size
    bytes32[] cdpIds;

    function setUp() public override {
        eBTCBaseFixture.setUp();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();
    }

    // -------- Increase Collateral Test cases --------

    /**
        @notice Happy case for borrowing and adding collateral within CDP
        @dev Assumes collateral pooledEth and Shares are 1:1
     */
    function testIncreaseCRHappy() public {
        uint256 collAmount = 30 ether;
        uint256 netColl = collAmount - borrowerOperations.LIQUIDATOR_REWARD();
        address user = _utils.getNextUserAddress();
        vm.startPrank(user);
        vm.deal(user, type(uint96).max);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 10000 ether}();

        // Calculate borrowed amount
        uint256 borrowedAmount = _utils.calculateBorrowAmount(
            collAmount,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );
        borrowerOperations.openCdp(borrowedAmount, HINT, HINT, collAmount);

        // Get new CDP id
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        uint256 coll = cdpManager.getCdpCollShares(cdpId);

        // Make sure collateral is as expected
        assertEq(netColl, collateral.getPooledEthByShares(coll));

        // Get ICR for CDP:
        uint256 initialIcr = cdpManager.getCachedICR(cdpId, priceFeedMock.fetchPrice());
        assertGt(initialIcr, MINIMAL_COLLATERAL_RATIO);

        // Add more collateral and make sure ICR changes
        borrowerOperations.addColl(cdpId, "hint", "hint", collAmount);
        uint256 newIcr = cdpManager.getCachedICR(cdpId, priceFeedMock.fetchPrice());

        assertGt(newIcr, initialIcr);

        // Make sure collateral increased by 2x
        uint256 expected = (collAmount * 2) - borrowerOperations.LIQUIDATOR_REWARD();
        assertEq(expected, cdpManager.getCdpCollShares(cdpId));
        vm.stopPrank();
    }

    // Expect revert if trying to pass a value less than MIN_CHANGE as coll increase value
    function testIncreaseCRWithLessThanMinAmount() public {
        uint256 collAmount = 30 ether;
        address user = _utils.getNextUserAddress();
        vm.deal(user, type(uint96).max);
        dealCollateral(user, 100000000 ether);
        vm.startPrank(user);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        uint256 borrowedAmount = _utils.calculateBorrowAmount(
            collAmount,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );
        borrowerOperations.openCdp(borrowedAmount, HINT, HINT, collAmount);
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        // Test with 0
        vm.expectRevert(ERR_BORROWER_OPERATIONS_NON_ZERO_CHANGE);
        borrowerOperations.addColl(cdpId, "hint", "hint", 0);
        // Test with MIN_CHANGE - 1
        vm.expectRevert(ERR_BORROWER_OPERATIONS_MIN_CHANGE);
        borrowerOperations.addColl(cdpId, "hint", "hint", minChange - 1);
        vm.stopPrank();
    }

    /**
     * @notice Fuzz testing for happy case scenario of increasing collateral in a CDP.
     * @param increaseAmnt The amount of collateral to increase in the CDP.
     */
    function testIncreaseCRHappyFuzz(uint96 increaseAmnt) public {
        increaseAmnt = uint96(bound(increaseAmnt, 1e1, type(uint96).max));
        uint256 collAmount = 28 ether;
        uint256 netColl = collAmount - borrowerOperations.LIQUIDATOR_REWARD();
        address user = _utils.getNextUserAddress();
        vm.startPrank(user);
        vm.deal(user, type(uint256).max);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 10000000000000000000000 ether}();
        uint256 borrowedAmount = _utils.calculateBorrowAmount(
            collAmount,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO_DEFENSIVE
        );

        // In case borrowedAmount is less than MIN_NET_DEBT - expect revert
        if (collAmount < borrowerOperations.MIN_NET_STETH_BALANCE()) {
            vm.expectRevert(
                bytes("BorrowerOperations: Cdp's net stEth balance must not fall below minimum")
            );
            borrowerOperations.openCdp(borrowedAmount, "hint", "hint", collAmount);
            return;
        }

        if (borrowedAmount == 0) {
            vm.expectRevert(bytes("BorrowerOperations: Debt must be non-zero"));
            borrowerOperations.openCdp(borrowedAmount, "hint", "hint", collAmount);
            return;
        }

        if (borrowedAmount < borrowerOperations.MIN_CHANGE()) {
            vm.expectRevert(ERR_BORROWER_OPERATIONS_MIN_DEBT);
            borrowerOperations.openCdp(borrowedAmount, "hint", "hint", collAmount);
            return;
        }

        borrowerOperations.openCdp(borrowedAmount, HINT, HINT, collAmount);
        // Make TCR snapshot before increasing collateral
        uint256 initialTcr = cdpManager.getCachedTCR(priceFeedMock.fetchPrice());
        // Get new CDP id
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        // Make sure collateral is as expected
        assertEq(netColl, cdpManager.getCdpCollShares(cdpId));
        // Get ICR for CDP:
        uint256 initialIcr = cdpManager.getCachedICR(cdpId, priceFeedMock.fetchPrice());
        assertGt(initialIcr, MINIMAL_COLLATERAL_RATIO);
        // Add more collateral and make sure ICR changes

        if (increaseAmnt == 0) {
            vm.expectRevert(ERR_BORROWER_OPERATIONS_NON_ZERO_CHANGE);
            borrowerOperations.addColl(cdpId, "hint", "hint", increaseAmnt);
            return;
        }

        if (increaseAmnt < borrowerOperations.MIN_CHANGE()) {
            vm.expectRevert(ERR_BORROWER_OPERATIONS_MIN_CHANGE);
            borrowerOperations.addColl(cdpId, "hint", "hint", increaseAmnt);
            return;
        }

        borrowerOperations.addColl(cdpId, "hint", "hint", increaseAmnt);
        uint256 newIcr = cdpManager.getCachedICR(cdpId, priceFeedMock.fetchPrice());
        assertGt(newIcr, initialIcr);
        // Make sure collateral increased by increaseAmnt
        assertEq((netColl + increaseAmnt), cdpManager.getCdpCollShares(cdpId));

        // Make sure TCR increased after collateral was added
        uint256 newTcr = cdpManager.getCachedTCR(priceFeedMock.fetchPrice());
        assertGt(newTcr, initialTcr);
        vm.stopPrank();
    }

    /**
        @notice Test case for multiple users with random amounts of CDPs, each adding more collateral.
        @dev Each user opens a CDP of a random size within range, and then adds a collateral value from a random size within range
        @dev Ensure ICR and TCR increase after adding additional collateral
        @dev Ensure the expected collateral amount is added to the CDP's coll value
        @dev Ensure that no new security deposit shares are added to the CDP
    */
    function testIncreaseCRManyUsersManyCdps() public {
        for (uint256 userIx = 0; userIx < AMOUNT_OF_USERS; userIx++) {
            address user = _utils.getNextUserAddress();
            vm.startPrank(user);
            vm.deal(user, type(uint256).max);
            collateral.approve(address(borrowerOperations), type(uint256).max);
            collateral.deposit{value: 100000000000000 ether}();
            // Random collateral for each user
            uint256 collAmount = _utils.generateRandomNumber(28 ether, 10000000 ether, user);
            uint256 netColl = collAmount - borrowerOperations.LIQUIDATOR_REWARD();
            uint256 collAmountChunk = (collAmount / AMOUNT_OF_CDPS);
            uint256 borrowedAmount = _utils.calculateBorrowAmount(
                collAmountChunk,
                priceFeedMock.fetchPrice(),
                COLLATERAL_RATIO
            );
            // Create multiple CDPs per user
            for (uint256 cdpIx = 0; cdpIx < AMOUNT_OF_CDPS; cdpIx++) {
                // In case borrowedAmount < MIN_NET_DEBT should expect revert
                if (borrowedAmount < MIN_NET_DEBT) {
                    vm.expectRevert(
                        bytes("BorrowerOperations: Cdp's net debt must be greater than minimum")
                    );
                    borrowerOperations.openCdp(borrowedAmount, HINT, HINT, collAmountChunk);
                    break;
                }
                borrowerOperations.openCdp(borrowedAmount, HINT, HINT, collAmountChunk);
                cdpIds.push(sortedCdps.cdpOfOwnerByIndex(user, cdpIx));
            }
            vm.stopPrank();
            _utils.mineBlocks(100);
        }
        // Make TCR snapshot before increasing collateral
        uint256 initialTcr = cdpManager.getCachedTCR(priceFeedMock.fetchPrice());
        // Now, add collateral for each CDP and make sure TCR improved
        for (uint256 cdpIx = 0; cdpIx < cdpIds.length; cdpIx++) {
            // Randomize collateral increase amount for each user
            address user = sortedCdps.getOwnerAddress(cdpIds[cdpIx]);
            uint256 randCollIncrease = _utils.generateRandomNumber(10 ether, 1000 ether, user);
            uint256 netColl = cdpManager.getCdpCollShares(cdpIds[cdpIx]);
            uint256 initialIcr = cdpManager.getCachedICR(cdpIds[cdpIx], priceFeedMock.fetchPrice());
            vm.prank(user);
            borrowerOperations.addColl(cdpIds[cdpIx], "hint", "hint", randCollIncrease);
            assertEq(netColl + randCollIncrease, cdpManager.getCdpCollShares(cdpIds[cdpIx]));
            uint256 newIcr = cdpManager.getCachedICR(cdpIds[cdpIx], priceFeedMock.fetchPrice());
            // Make sure ICR for CDP increased
            assertGt(newIcr, initialIcr);
            _utils.mineBlocks(100);
        }
        // Make sure TCR increased after collateral was added
        uint256 newTcr = cdpManager.getCachedTCR(priceFeedMock.fetchPrice());
        assertGt(newTcr, initialTcr);
    }

    // -------- Withdraw Collateral Test cases --------

    // Happy case for borrowing and withdrawing collateral from CDP
    function testWithdrawCRHappy() public {
        uint256 collAmount = 30 ether;
        uint256 withdrawnColl = 5 ether;
        address user = _utils.getNextUserAddress();
        vm.startPrank(user);
        vm.deal(user, type(uint256).max);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 100000000000000 ether}();
        // Calculate borrowed amount. Borrow less because of COLLATERAL_RATIO_DEFENSIVE is used which forces
        // to open more collateralized position
        uint256 borrowedAmount = _utils.calculateBorrowAmount(
            collAmount,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO_DEFENSIVE
        );
        borrowerOperations.openCdp(borrowedAmount, HINT, HINT, collAmount);
        // Get new CDP id
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        // Get ICR for CDP:
        uint256 initialIcr = cdpManager.getCachedICR(cdpId, priceFeedMock.fetchPrice());
        // Withdraw collateral and make sure ICR changes
        borrowerOperations.withdrawColl(cdpId, withdrawnColl, "hint", "hint");
        uint256 newIcr = cdpManager.getCachedICR(cdpId, priceFeedMock.fetchPrice());
        assertLt(newIcr, initialIcr);
        // Make sure collateral was reduced by `withdrawnColl` amount
        assertEq(
            (collAmount - borrowerOperations.LIQUIDATOR_REWARD() - withdrawnColl),
            cdpManager.getCdpCollShares(cdpId)
        );
        vm.stopPrank();
    }

    // Test case for multiple users with random amount of CDPs, withdrawing collateral
    function testWithdrawCRManyUsersManyCdps() public {
        for (uint256 userIx = 0; userIx < AMOUNT_OF_USERS; userIx++) {
            address user = _utils.getNextUserAddress();
            vm.startPrank(user);
            vm.deal(user, type(uint256).max);
            collateral.approve(address(borrowerOperations), type(uint256).max);
            collateral.deposit{value: 100000000000000 ether}();
            // Random collateral for each user
            uint256 collAmount = _utils.generateRandomNumber(28 ether, 100000 ether, user);
            uint256 collAmountChunk = (collAmount / AMOUNT_OF_CDPS);
            uint256 borrowedAmount = _utils.calculateBorrowAmount(
                collAmountChunk,
                priceFeedMock.fetchPrice(),
                COLLATERAL_RATIO_DEFENSIVE
            );
            // Create multiple CDPs per user
            for (uint256 cdpIx = 0; cdpIx < AMOUNT_OF_CDPS; cdpIx++) {
                // In case borrowedAmount < MIN_NET_DEBT should expect revert
                if (borrowedAmount < MIN_NET_DEBT) {
                    vm.expectRevert(
                        bytes("BorrowerOperations: Cdp's net debt must be greater than minimum")
                    );
                    borrowerOperations.openCdp(borrowedAmount, HINT, HINT, collAmountChunk);
                    break;
                }
                borrowerOperations.openCdp(borrowedAmount, HINT, HINT, collAmountChunk);
                cdpIds.push(sortedCdps.cdpOfOwnerByIndex(user, cdpIx));
            }
            vm.stopPrank();
            _utils.mineBlocks(100);
        }
        // Make TCR snapshot before decreasing collateral
        uint256 initialTcr = cdpManager.getCachedTCR(priceFeedMock.fetchPrice());
        // Now, withdraw collateral for each CDP and make sure TCR decreased
        for (uint256 cdpIx = 0; cdpIx < cdpIds.length; cdpIx++) {
            // Randomize collateral increase amount for each user
            address user = sortedCdps.getOwnerAddress(cdpIds[cdpIx]);
            uint256 randCollWithdraw = _utils.generateRandomNumber(
                // Max value to withdraw is 20% of collateral
                0.1 ether,
                (cdpManager.getCdpCollShares(cdpIds[cdpIx]) / 5),
                user
            );
            uint256 initialIcr = cdpManager.getCachedICR(cdpIds[cdpIx], priceFeedMock.fetchPrice());
            // Withdraw
            vm.prank(user);
            borrowerOperations.withdrawColl(cdpIds[cdpIx], randCollWithdraw, "hint", "hint");
            uint256 newIcr = cdpManager.getCachedICR(cdpIds[cdpIx], priceFeedMock.fetchPrice());
            // Make sure ICR for CDP decreased
            assertGt(initialIcr, newIcr);
            _utils.mineBlocks(100);
        }
        // Make sure TCR increased after collateral was added
        uint256 newTcr = cdpManager.getCachedTCR(priceFeedMock.fetchPrice());
        assertGt(initialTcr, newTcr);
    }

    // Expect revert if trying to withdraw less than min
    function testWithdrawLessThanMinAmnt() public {
        uint256 collAmount = 30 ether;
        address user = _utils.getNextUserAddress();
        vm.startPrank(user);
        vm.deal(user, type(uint256).max);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 100000000000000 ether}();
        uint256 borrowedAmount = _utils.calculateBorrowAmount(
            collAmount,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );
        borrowerOperations.openCdp(borrowedAmount, HINT, HINT, collAmount);
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        // Test with 0
        vm.expectRevert(ERR_BORROWER_OPERATIONS_NON_ZERO_CHANGE);
        borrowerOperations.withdrawColl(cdpId, 0, HINT, HINT);
        // Test with MIN_CHANGE() - 1
        vm.expectRevert(ERR_BORROWER_OPERATIONS_MIN_CHANGE);
        borrowerOperations.withdrawColl(cdpId, minChange - 1, HINT, HINT);
        vm.stopPrank();
    }

    /* Test case when user is trying to withraw too much collateral which results in
     * ICR being too low, hence operation is reverted
     */
    function testWithdrawIcrTooLow() public {
        uint256 collAmount = 30 ether;
        uint256 withdrawnColl = 10 ether;
        address user = _utils.getNextUserAddress();
        vm.deal(user, type(uint256).max);
        vm.startPrank(user);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 100000000000000 ether}();
        // Calculate borrowed amount
        uint256 borrowedAmount = _utils.calculateBorrowAmount(
            collAmount,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );
        borrowerOperations.openCdp(borrowedAmount, HINT, HINT, collAmount);
        // Get new CDP id
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        // Withdraw collateral and make sure operation reverts with ICR < MCR
        vm.expectRevert(
            bytes("BorrowerOperations: An operation that would result in ICR < MCR is not permitted")
        );
        borrowerOperations.withdrawColl(cdpId, withdrawnColl, HINT, HINT);
        vm.stopPrank();
    }
}
