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
        uint collAmount = 30 ether;
        uint netColl = collAmount - borrowerOperations.LIQUIDATOR_REWARD();
        address user = _utils.getNextUserAddress();
        vm.startPrank(user);
        vm.deal(user, type(uint96).max);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 10000 ether}();

        // Calculate borrowed amount
        uint borrowedAmount = _utils.calculateBorrowAmount(
            collAmount,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );
        borrowerOperations.openCdp(borrowedAmount, HINT, HINT, collAmount);

        // Get new CDP id
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        uint coll = cdpManager.getCdpColl(cdpId);

        // Make sure collateral is as expected
        assertEq(netColl, collateral.getPooledEthByShares(coll));

        // Get ICR for CDP:
        uint initialIcr = cdpManager.getICR(cdpId, priceFeedMock.fetchPrice());
        assertGt(initialIcr, MINIMAL_COLLATERAL_RATIO);

        // Add more collateral and make sure ICR changes
        borrowerOperations.addColl(cdpId, "hint", "hint", collAmount);
        uint newIcr = cdpManager.getICR(cdpId, priceFeedMock.fetchPrice());

        assertGt(newIcr, initialIcr);

        // Make sure collateral increased by 2x
        uint expected = (collAmount * 2) - borrowerOperations.LIQUIDATOR_REWARD();
        assertEq(expected, cdpManager.getCdpColl(cdpId));
        vm.stopPrank();
    }

    // Expect revert if trying to pass 0 as coll increase value
    function testIncreaseCRWithZeroAmount() public {
        uint collAmount = 30 ether;
        address user = _utils.getNextUserAddress();
        vm.deal(user, type(uint96).max);
        dealCollateral(user, 100000000 ether);
        vm.startPrank(user);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        uint borrowedAmount = _utils.calculateBorrowAmount(
            collAmount,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );
        borrowerOperations.openCdp(borrowedAmount, HINT, HINT, collAmount);
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        vm.expectRevert(
            bytes("BorrowerOperations: There must be either a collateral change or a debt change")
        );
        borrowerOperations.addColl(cdpId, "hint", "hint", 0);
        vm.stopPrank();
    }

    /**
     * @notice Fuzz testing for happy case scenario of increasing collateral in a CDP.
     * @param increaseAmnt The amount of collateral to increase in the CDP.
     */
    function testIncreaseCRHappyFuzz(uint96 increaseAmnt) public {
        vm.assume(increaseAmnt > 1e1);
        vm.assume(increaseAmnt < type(uint96).max);
        uint collAmount = 28 ether;
        uint netColl = collAmount - borrowerOperations.LIQUIDATOR_REWARD();
        address user = _utils.getNextUserAddress();
        vm.startPrank(user);
        vm.deal(user, type(uint256).max);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 10000000000000000000000 ether}();
        uint borrowedAmount = _utils.calculateBorrowAmount(
            collAmount,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO_DEFENSIVE
        );

        // In case borrowedAmount is less than MIN_NET_DEBT - expect revert
        if (collAmount < borrowerOperations.MIN_NET_COLL()) {
            vm.expectRevert(
                bytes("BorrowerOperations: Cdp's net coll must be greater than minimum")
            );
            borrowerOperations.openCdp(borrowedAmount, "hint", "hint", collAmount);
            return;
        }

        if (borrowedAmount == 0) {
            vm.expectRevert(bytes("BorrowerOperations: Debt must be non-zero"));
            borrowerOperations.openCdp(borrowedAmount, "hint", "hint", collAmount);
            return;
        }

        borrowerOperations.openCdp(borrowedAmount, HINT, HINT, collAmount);
        // Make TCR snapshot before increasing collateral
        uint initialTcr = cdpManager.getTCR(priceFeedMock.fetchPrice());
        // Get new CDP id
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        // Make sure collateral is as expected
        assertEq(netColl, cdpManager.getCdpColl(cdpId));
        // Get ICR for CDP:
        uint initialIcr = cdpManager.getICR(cdpId, priceFeedMock.fetchPrice());
        assertGt(initialIcr, MINIMAL_COLLATERAL_RATIO);
        // Add more collateral and make sure ICR changes
        borrowerOperations.addColl(cdpId, "hint", "hint", increaseAmnt);
        uint newIcr = cdpManager.getICR(cdpId, priceFeedMock.fetchPrice());
        assertGt(newIcr, initialIcr);
        // Make sure collateral increased by increaseAmnt
        assertEq((netColl + increaseAmnt), cdpManager.getCdpColl(cdpId));

        // Make sure TCR increased after collateral was added
        uint newTcr = cdpManager.getTCR(priceFeedMock.fetchPrice());
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
        for (uint userIx = 0; userIx < AMOUNT_OF_USERS; userIx++) {
            address user = _utils.getNextUserAddress();
            vm.startPrank(user);
            vm.deal(user, type(uint256).max);
            collateral.approve(address(borrowerOperations), type(uint256).max);
            collateral.deposit{value: 100000000000000 ether}();
            // Random collateral for each user
            uint collAmount = _utils.generateRandomNumber(28 ether, 10000000 ether, user);
            uint netColl = collAmount - borrowerOperations.LIQUIDATOR_REWARD();
            uint collAmountChunk = (collAmount / AMOUNT_OF_CDPS);
            uint borrowedAmount = _utils.calculateBorrowAmount(
                collAmountChunk,
                priceFeedMock.fetchPrice(),
                COLLATERAL_RATIO
            );
            // Create multiple CDPs per user
            for (uint cdpIx = 0; cdpIx < AMOUNT_OF_CDPS; cdpIx++) {
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
        uint initialTcr = cdpManager.getTCR(priceFeedMock.fetchPrice());
        // Now, add collateral for each CDP and make sure TCR improved
        for (uint cdpIx = 0; cdpIx < cdpIds.length; cdpIx++) {
            // Randomize collateral increase amount for each user
            address user = sortedCdps.getOwnerAddress(cdpIds[cdpIx]);
            uint randCollIncrease = _utils.generateRandomNumber(10 ether, 1000 ether, user);
            uint netColl = cdpManager.getCdpColl(cdpIds[cdpIx]);
            uint initialIcr = cdpManager.getICR(cdpIds[cdpIx], priceFeedMock.fetchPrice());
            vm.prank(user);
            borrowerOperations.addColl(cdpIds[cdpIx], "hint", "hint", randCollIncrease);
            assertEq(netColl + randCollIncrease, cdpManager.getCdpColl(cdpIds[cdpIx]));
            uint newIcr = cdpManager.getICR(cdpIds[cdpIx], priceFeedMock.fetchPrice());
            // Make sure ICR for CDP increased
            assertGt(newIcr, initialIcr);
            _utils.mineBlocks(100);
        }
        // Make sure TCR increased after collateral was added
        uint newTcr = cdpManager.getTCR(priceFeedMock.fetchPrice());
        assertGt(newTcr, initialTcr);
    }

    // -------- Withdraw Collateral Test cases --------

    // Happy case for borrowing and withdrawing collateral from CDP
    function testWithdrawCRHappy() public {
        uint collAmount = 30 ether;
        uint withdrawnColl = 5 ether;
        address user = _utils.getNextUserAddress();
        vm.startPrank(user);
        vm.deal(user, type(uint256).max);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 100000000000000 ether}();
        // Calculate borrowed amount. Borrow less because of COLLATERAL_RATIO_DEFENSIVE is used which forces
        // to open more collateralized position
        uint borrowedAmount = _utils.calculateBorrowAmount(
            collAmount,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO_DEFENSIVE
        );
        borrowerOperations.openCdp(borrowedAmount, HINT, HINT, collAmount);
        // Get new CDP id
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        // Get ICR for CDP:
        uint initialIcr = cdpManager.getICR(cdpId, priceFeedMock.fetchPrice());
        // Withdraw collateral and make sure ICR changes
        borrowerOperations.withdrawColl(cdpId, withdrawnColl, "hint", "hint");
        uint newIcr = cdpManager.getICR(cdpId, priceFeedMock.fetchPrice());
        assertLt(newIcr, initialIcr);
        // Make sure collateral was reduced by `withdrawnColl` amount
        assertEq(
            (collAmount - borrowerOperations.LIQUIDATOR_REWARD() - withdrawnColl),
            cdpManager.getCdpColl(cdpId)
        );
        vm.stopPrank();
    }

    // Test case for multiple users with random amount of CDPs, withdrawing collateral
    function testWithdrawCRManyUsersManyCdps() public {
        for (uint userIx = 0; userIx < AMOUNT_OF_USERS; userIx++) {
            address user = _utils.getNextUserAddress();
            vm.startPrank(user);
            vm.deal(user, type(uint256).max);
            collateral.approve(address(borrowerOperations), type(uint256).max);
            collateral.deposit{value: 100000000000000 ether}();
            // Random collateral for each user
            uint collAmount = _utils.generateRandomNumber(28 ether, 100000 ether, user);
            uint collAmountChunk = (collAmount / AMOUNT_OF_CDPS);
            uint borrowedAmount = _utils.calculateBorrowAmount(
                collAmountChunk,
                priceFeedMock.fetchPrice(),
                COLLATERAL_RATIO_DEFENSIVE
            );
            // Create multiple CDPs per user
            for (uint cdpIx = 0; cdpIx < AMOUNT_OF_CDPS; cdpIx++) {
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
        uint initialTcr = cdpManager.getTCR(priceFeedMock.fetchPrice());
        // Now, withdraw collateral for each CDP and make sure TCR decreased
        for (uint cdpIx = 0; cdpIx < cdpIds.length; cdpIx++) {
            // Randomize collateral increase amount for each user
            address user = sortedCdps.getOwnerAddress(cdpIds[cdpIx]);
            uint randCollWithdraw = _utils.generateRandomNumber(
                // Max value to withdraw is 20% of collateral
                0.1 ether,
                (cdpManager.getCdpColl(cdpIds[cdpIx]) / 5),
                user
            );
            uint initialIcr = cdpManager.getICR(cdpIds[cdpIx], priceFeedMock.fetchPrice());
            // Withdraw
            vm.prank(user);
            borrowerOperations.withdrawColl(cdpIds[cdpIx], randCollWithdraw, "hint", "hint");
            uint newIcr = cdpManager.getICR(cdpIds[cdpIx], priceFeedMock.fetchPrice());
            // Make sure ICR for CDP decreased
            assertGt(initialIcr, newIcr);
            _utils.mineBlocks(100);
        }
        // Make sure TCR increased after collateral was added
        uint newTcr = cdpManager.getTCR(priceFeedMock.fetchPrice());
        assertGt(initialTcr, newTcr);
    }

    // Expect revert if trying to withdraw 0
    function testWithdrawZeroAmnt() public {
        uint collAmount = 30 ether;
        address user = _utils.getNextUserAddress();
        vm.startPrank(user);
        vm.deal(user, type(uint256).max);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 100000000000000 ether}();
        uint borrowedAmount = _utils.calculateBorrowAmount(
            collAmount,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );
        borrowerOperations.openCdp(borrowedAmount, HINT, HINT, collAmount);
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        vm.expectRevert(
            bytes("BorrowerOperations: There must be either a collateral change or a debt change")
        );
        borrowerOperations.withdrawColl(cdpId, 0, HINT, HINT);
        vm.stopPrank();
    }

    /* Test case when user is trying to withraw too much collateral which results in
     * ICR being too low, hence operation is reverted
     */
    function testWithdrawIcrTooLow() public {
        uint collAmount = 30 ether;
        uint withdrawnColl = 10 ether;
        address user = _utils.getNextUserAddress();
        vm.deal(user, type(uint256).max);
        vm.startPrank(user);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 100000000000000 ether}();
        // Calculate borrowed amount
        uint borrowedAmount = _utils.calculateBorrowAmount(
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
