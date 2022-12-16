// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.11;

import "forge-std/Test.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";
import {Utilities} from "./utils/Utilities.sol";

/*
 * Test suite that tests opened CDPs with operations
 * TODO: implement
 */
contract CDPTestOperations is eBTCBaseFixture {
    uint private constant FEE = 5e17;
    uint256 internal constant COLLATERAL_RATIO = 160e16;  // 160%: take higher CR as CCR is 150%
    uint256 internal constant COLLATERAL_RATIO_DEFENSIVE = 200e16;  // 200% - defencive CR

    Utilities internal _utils;

    function setUp() public override {
        eBTCBaseFixture.setUp();
        eBTCBaseFixture.connectLQTYContracts();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();
        _utils = new Utilities();
    }

    // Happy case for borrowing and adding collateral within CDP
    function testIncreaseCRHappy() public {
        uint collAmount = 30 ether;
        address payable[] memory users;
        users = _utils.createUsers(1);
        address user = users[0];
        vm.startPrank(user);
        // Calculate borrowed amount
        uint borrowedAmount = _utils.calculateBorrowAmount(collAmount, priceFeedMock.fetchPrice(), COLLATERAL_RATIO);
        borrowerOperations.openCdp{value : collAmount}(FEE, borrowedAmount, "hint", "hint");
        // Get new CDP id
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        uint coll = cdpManager.getCdpColl(cdpId);
        // Make sure collateral is as expected
        assertEq(collAmount, coll);
        // Get ICR for CDP:
        uint initialIcr = cdpManager.getCurrentICR(cdpId, priceFeedMock.fetchPrice());
        // Add more collateral and make sure ICR changes
        borrowerOperations.addColl{value : collAmount}(cdpId, "hint", "hint");
        uint newIcr = cdpManager.getCurrentICR(cdpId, priceFeedMock.fetchPrice());
        assert(newIcr != initialIcr);
        // Make sure collateral increased by 2x
        assertEq(collAmount.mul(2), cdpManager.getCdpColl(cdpId));
        vm.stopPrank();
    }

    // Happy case for borrowing and withdrawing collateral within CDP
    function testWithdrawCRHappy() public {
        uint collAmount = 30 ether;
        uint withdrawnColl = 5 ether;
        address payable[] memory users;
        users = _utils.createUsers(1);
        address user = users[0];
        vm.startPrank(user);
        // Calculate borrowed amount. Borrow less because of COLLATERAL_RATIO_DEFENSIVE is used which forces
        // to open more collateralized position
        uint borrowedAmount = _utils.calculateBorrowAmount(
            collAmount, priceFeedMock.fetchPrice(), COLLATERAL_RATIO_DEFENSIVE
        );
        borrowerOperations.openCdp{value : collAmount}(FEE, borrowedAmount, "hint", "hint");
        // Get new CDP id
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        // Get ICR for CDP:
        uint initialIcr = cdpManager.getCurrentICR(cdpId, priceFeedMock.fetchPrice());
        // Withdraw collateral and make sure ICR changes
        borrowerOperations.withdrawColl(cdpId, withdrawnColl, "hint", "hint");
        uint newIcr = cdpManager.getCurrentICR(cdpId, priceFeedMock.fetchPrice());
        assert(newIcr != initialIcr);
        // Make sure collateral was reduced by `withdrawnColl` amount
        assertEq(collAmount.sub(withdrawnColl), cdpManager.getCdpColl(cdpId));
        vm.stopPrank();
    }
}
