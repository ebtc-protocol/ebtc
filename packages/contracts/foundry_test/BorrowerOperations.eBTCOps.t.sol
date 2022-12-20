// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.11;

import "forge-std/Test.sol";
import "../contracts/Dependencies/LiquityMath.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";
import {Utilities} from "./utils/Utilities.sol";

/*
 * Test suite that tests opened CDPs with two different operations: addColl and withdrawColl
 */
contract CDPOpsTest is eBTCBaseFixture {
    Utilities internal _utils;

    function setUp() public override {
        eBTCBaseFixture.setUp();
        eBTCBaseFixture.connectLQTYContracts();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();
        _utils = new Utilities();
    }

    // -------- Repay eBTC Test cases --------
    // Happy case for borrowing and repaying back eBTC which should result in increasing ICR
    function testRepayHappy() public {
        uint collAmount = 30 ether;
        address user = _utils.getNextUserAddress();
        vm.startPrank(user);
        vm.deal(user, type(uint96).max);
        uint borrowedAmount = _utils.calculateBorrowAmount(collAmount, priceFeedMock.fetchPrice(), COLLATERAL_RATIO);
        borrowerOperations.openCdp{value : collAmount}(FEE, borrowedAmount, HINT, HINT);
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        uint initialIcr = cdpManager.getCurrentICR(cdpId, priceFeedMock.fetchPrice());
        uint balanceSnapshot = eBTCToken.balanceOf(user);
        // Repay eBTC
        borrowerOperations.repayEBTC(
            cdpId,
            // Repay 10% of eBTC
            borrowedAmount.div(10),
            HINT, HINT
        );
        // Make sure eBTC balance decreased
        assertLt(eBTCToken.balanceOf(user), balanceSnapshot);
        // Make sure ICR for CDP improved after eBTC was repaid
        uint newIcr = cdpManager.getCurrentICR(cdpId, priceFeedMock.fetchPrice());
        assertGt(newIcr, initialIcr);
        vm.stopPrank();
    }

    // Fuzzing different amounts of eBTC repaid
    function testRepayFuzz(uint96 repayAmnt) public {
        repayAmnt = uint96(bound(repayAmnt, 1e18, type(uint96).max));
        // Coll amount will always be max of uint96
        uint collAmount = type(uint96).max;
        address user = _utils.getNextUserAddress();
        vm.startPrank(user);
        vm.deal(user, type(uint96).max);
        uint borrowedAmount = _utils.calculateBorrowAmount(collAmount, priceFeedMock.fetchPrice(), COLLATERAL_RATIO);
        borrowerOperations.openCdp{value : collAmount}(FEE, borrowedAmount, HINT, HINT);
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, 0);
        uint initialIcr = cdpManager.getCurrentICR(cdpId, priceFeedMock.fetchPrice());
        uint balanceSnapshot = eBTCToken.balanceOf(user);
        // Repay eBTC
        borrowerOperations.repayEBTC(
            cdpId,
            repayAmnt,
            HINT, HINT
        );
        // Make sure eBTC balance decreased
        assertLt(eBTCToken.balanceOf(user), balanceSnapshot);
        // Make sure ICR for CDP improved after eBTC was repaid
        uint newIcr = cdpManager.getCurrentICR(cdpId, priceFeedMock.fetchPrice());
        assertGt(newIcr, initialIcr);
        vm.stopPrank();
    }
}
