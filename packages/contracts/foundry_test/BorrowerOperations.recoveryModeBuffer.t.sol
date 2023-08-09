// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;
import "forge-std/Test.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";

/*
 * Test suite that tests exactly one thing: opening CDPs
 * It tests different cases and also does random testing against random coll amounts and amount of users
 */
contract BorrowerOperationsRecoveryModeBufferTest is eBTCBaseFixture {
    uint public RECOVERY_MODE_TEST_TCR;
    uint public BUFFER_MODE_TEST_TCR;
    uint public NORMAL_MODE_TEST_TCR;

    function setUp() public override {
        eBTCBaseFixture.setUp();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();

        RECOVERY_MODE_TEST_TCR = cdpManager.CCR() - 5e16;
        BUFFER_MODE_TEST_TCR = cdpManager.BUFFERED_CCR() - 5e16;
        NORMAL_MODE_TEST_TCR = cdpManager.BUFFERED_CCR() + 50e16;
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
        uint borrowedAmount = 5 ether;

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

    /**
        If the system is in buffer mode, users can only take actions that don't decrease system health (increasing debt or decreasing collShares).
     */

    /**
        - TCR is in Buffer Mode after Cdp Adjustment
        - If ICR >= BCCR, succeed
     */

    /// @notice User should not be able to adjust their position such that ICR < BCCR if the system is in Buffer Mode after the action
    /// @dev We want to try entering buffer mode from multiple states
    /// @dev 1. in RM before adjustment, in BM after
    /// @dev 2. in BM before and after adjustment
    /// @dev 3. in NM before, in BM after

    /// @notice The user should always be able to open a position in Buffer Mode with ICR > 135% if the system stays in BM before and after
    function test_UserCanAlwaysOpenPositionInBufferModeWithIcrGreaterThanBccrIfSystemStaysInBmBeforeAndAfter()
        public
    {
        (address whale, address user) = _initializeSystemInBufferModeWithoutUserCdp();

        uint debt = 0;
        uint stEthBalance = 20e18;

        vm.startPrank(user);

        debt = _getDebtForDesiredICR(stEthBalance, 136e16);
        bytes32 _cdpId = borrowerOperations.openCdp(
            debt,
            bytes32(0),
            bytes32(0),
            stEthBalance + GAS_STIPEND_BALANCE
        );

        vm.stopPrank();
        assertLt(_getTCR(), cdpManager.BUFFERED_CCR()); //Confirm we're still in BM
    }

    /// @notice The user should always be able to open a position in Buffer Mode with ICR > 135% if the system moves from BM to NM after the action
    function test_UserCanAlwaysOpenPositionInBufferModeWithIcrGreaterThan135IfSystemMovesFromBmToNmAfterAction()
        public
    {
        (address whale, address user) = _initializeSystemInBufferModeWithoutUserCdp();

        uint debt = 0;
        uint stEthBalance = 1000e18;

        vm.startPrank(user);
        debt = _getDebtForDesiredICR(stEthBalance, 200e16);
        bytes32 _cdpId = borrowerOperations.openCdp(
            debt,
            bytes32(0),
            bytes32(0),
            stEthBalance + GAS_STIPEND_BALANCE
        );

        vm.stopPrank();
        assertGt(_getTCR(), cdpManager.BUFFERED_CCR()); //Confirm we're still in BM
    }

    /// @notice The user should not be able to open a position in Buffer Mode with ICR < BCCR if the system stays in BM before and after
    function test_UserCannotOpenPositionInBufferModeWithIcrLessThanBccrIfSystemStaysInBmBeforeAndAfter()
        public
    {
        (address whale, address user) = _initializeSystemInBufferModeWithoutUserCdp();

        uint debt = 0;
        uint stEthBalance = 20e18;

        vm.startPrank(user);

        // should fail if ICR < CCR and ICR > MCR
        debt = _getDebtForDesiredICR(stEthBalance, 120e16);
        vm.expectRevert(
            "BorrowerOps: A TCR decreasing operation that would result in TCR < BUFFERED_CCR is not permitted"
        );
        bytes32 _cdpId = borrowerOperations.openCdp(
            debt,
            bytes32(0),
            bytes32(0),
            stEthBalance + GAS_STIPEND_BALANCE
        );

        // should fail if ICR < MCR
        debt = _getDebtForDesiredICR(stEthBalance, 1e18);
        vm.expectRevert(
            "BorrowerOperations: An operation that would result in ICR < MCR is not permitted"
        );
        _cdpId = borrowerOperations.openCdp(
            debt,
            bytes32(0),
            bytes32(0),
            stEthBalance + GAS_STIPEND_BALANCE
        );

        vm.stopPrank();
        assertLt(_getTCR(), 135e16); //Confirm we're still in BM
    }

    /// @notice The user should be able to increase the health of their position above BCCR in Buffer Mode via adjustment
    function test_UserCanIncreasePositionHealthAboveBccrInBufferModeViaAdjustment() public {
        (address whale, address user, bytes32 userCdpId) = _initializeSystemAtTCRWithUserCdp(
            BUFFER_MODE_TEST_TCR
        );

        uint targetICR = cdpManager.BUFFERED_CCR() + 1;
        uint currentICR = _getCurrentICR(userCdpId);
        assertGt(targetICR, currentICR); // ensure this target ICR is actually above current

        uint userStEthBalance = collateral.getPooledEthByShares(cdpManager.getCdpColl(userCdpId));
        uint newDebtTarget = _getDebtForDesiredICR(userStEthBalance, targetICR);
        uint debtDiff = cdpManager.getCdpDebt(userCdpId) - newDebtTarget;

        vm.prank(user);
        vm.expectRevert(
            "BorrowerOps: A TCR decreasing operation that would result in TCR < BUFFERED_CCR is not permitted"
        );
        borrowerOperations.adjustCdp(userCdpId, 0, debtDiff, true, bytes32(0), bytes32(0));
    }

    /// @notice The user should not be able to increase the health of their position below BCCR in Buffer Mode via adjustment
    /// @dev Attempt by increasing health of a position below BCCR to another value below BCCR in BM
    function test_UserCannotIncreasePositionHealthBelowBccrInBufferModeViaAdjustment() public {
        (address whale, address user, bytes32 userCdpId) = _initializeSystemAtTCRWithUserCdp(
            BUFFER_MODE_TEST_TCR
        );

        uint targetICR = cdpManager.BUFFERED_CCR() - 1e16;
        uint currentICR = _getCurrentICR(userCdpId);
        assertGt(targetICR, currentICR); // ensure this target ICR is actually above current

        uint userStEthBalance = collateral.getPooledEthByShares(cdpManager.getCdpColl(userCdpId));
        uint newDebtTarget = _getDebtForDesiredICR(userStEthBalance, targetICR);
        uint debtDiff = cdpManager.getCdpDebt(userCdpId) - newDebtTarget;

        vm.prank(user);
        vm.expectRevert(
            "BorrowerOps: A TCR decreasing operation that would result in TCR < BUFFERED_CCR is not permitted"
        );
        borrowerOperations.adjustCdp(userCdpId, 0, debtDiff, true, bytes32(0), bytes32(0));
    }

    /// @notice The user should not be be able to set the health of their position below BCCR in Buffer Mode via adjustment
    /// @dev Attempt by decreasing health of a position above BCCR to belowe BCCR in BM
    function test_UserCannotDecreasePositionHealthBelowBccrInBufferModeViaAdjustment() public {
        (address whale, address user, bytes32 userCdpId) = _initializeSystemAtTCRWithUserCdp(
            BUFFER_MODE_TEST_TCR
        );

        // set ICR well above threshold
        uint targetICR = cdpManager.BUFFERED_CCR() + 20e16;
        uint currentICR = _getCurrentICR(userCdpId);
        assertGt(targetICR, currentICR); // ensure this target ICR is actually above current

        uint userStEthBalance = collateral.getPooledEthByShares(cdpManager.getCdpColl(userCdpId));
        uint newDebtTarget = _getDebtForDesiredICR(userStEthBalance, targetICR);
        uint debtDiff = cdpManager.getCdpDebt(userCdpId) - newDebtTarget;

        console.log("targetICR: ", targetICR);
        console.log("currentICR: ", currentICR);

        console.log(cdpManager.getCdpDebt(userCdpId));
        console.log(newDebtTarget);
        console.log(debtDiff);

        vm.prank(user);
        borrowerOperations.adjustCdp(userCdpId, 0, debtDiff, false, bytes32(0), bytes32(0));

        // attempt to set ICR below threshold
        targetICR = cdpManager.BUFFERED_CCR() - 1e16;
        currentICR = _getCurrentICR(userCdpId);
        assertGt(currentICR, targetICR); // should be above target in this case

        userStEthBalance = collateral.getPooledEthByShares(cdpManager.getCdpColl(userCdpId));
        newDebtTarget = _getDebtForDesiredICR(userStEthBalance, targetICR);
        debtDiff = newDebtTarget - cdpManager.getCdpDebt(userCdpId);

        vm.prank(user);
        vm.expectRevert(
            "BorrowerOps: A TCR decreasing operation that would result in TCR < BUFFERED_CCR is not permitted"
        );
        borrowerOperations.adjustCdp(userCdpId, 0, debtDiff, true, bytes32(0), bytes32(0));
    }

    /// @notice Initialize the system with a whale and a user, both with ICR == TCR
    function _initializeSystemInBufferModeWithoutUserCdp()
        internal
        returns (address whale, address user)
    {
        address payable[] memory users;
        users = _utils.createUsers(2);
        whale = users[0];
        user = users[1];

        // 1:1 price for simplicity
        priceFeedMock.setPrice(1e18);

        // 200% CDP for whale
        bytes32 whaleCdpId = _openTestCDP(whale, 200e18 + GAS_STIPEND_BALANCE, 100 ether);

        CdpData memory whaleCdpData = _getCdpData(whaleCdpId);

        _getAndPrintCdpData(whaleCdpId);

        // adjust price such that ICR = 130%
        uint newPrice = _getRequiredPriceForICR(whaleCdpData.debt, whaleCdpData.collShares, 130e16);
        console.log("Required price for desired ICR: %s", newPrice);
        priceFeedMock.setPrice(newPrice);

        _getAndPrintCdpData(whaleCdpId);

        // prep user
        dealCollateral(user, 10000e18);
        vm.prank(user);
        collateral.approve(address(borrowerOperations), type(uint256).max);
    }

    function _initializeSystemAtTCRWithUserCdp(
        uint TCR
    ) internal returns (address whale, address user, bytes32 userCdpId) {
        address payable[] memory users;
        users = _utils.createUsers(2);
        whale = users[0];
        user = users[1];

        // prep user
        dealCollateral(user, 10000e18);
        collateral.approve(address(borrowerOperations), type(uint256).max);

        // 1:1 price for simplicity
        priceFeedMock.setPrice(1e18);

        // calculate values for user position at ICR
        uint userStEthBalance = 100e18;
        uint userDebt = _getDebtForDesiredICR(userStEthBalance, TCR);

        // calculate values for whale CDP to bring system TCR to desired value
        uint whaleStEthBalance = 1000e18;
        uint whaleDebt = _getDebtForDesiredICR(whaleStEthBalance, TCR);

        // massive price increase to ensure we don't enter RM or BM for "reasonable" values
        priceFeedMock.setPrice(100e18);

        bytes32 whaleCdpId = _openTestCDP(whale, whaleStEthBalance + GAS_STIPEND_BALANCE, whaleDebt);
        CdpData memory whaleCdpData = _getCdpData(whaleCdpId);

        userCdpId = _openTestCDP(user, userStEthBalance + GAS_STIPEND_BALANCE, userDebt);
        CdpData memory userCdpData = _getCdpData(userCdpId);

        // return price
        priceFeedMock.setPrice(1e18);

        _getAndPrintCdpData(whaleCdpId);
        _getAndPrintCdpData(userCdpId);
        _getAndPrintSystemState();
    }
}
