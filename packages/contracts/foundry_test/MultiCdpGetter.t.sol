// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "../contracts/Dependencies/LiquityMath.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";
import {MultiCdpGetter} from "../contracts/MultiCdpGetter.sol";

/*
  Tests around MultiCdpGetter
 */
contract MultiCdpGetterTest is eBTCBaseFixture {
    function setUp() public override {
        eBTCBaseFixture.setUp();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();
    }

    function testBasicAccounting(uint256 usersCount) public {
        vm.assume(usersCount > 0);
        vm.assume(usersCount < 400);

        address payable[] memory users;
        users = _utils.createUsers(usersCount);

        for (uint256 i = 0; i < usersCount; i++) {
            _dealCollateralAndPrepForUse(users[i]);
            vm.startPrank(users[i]);
            uint256 collAmount = (2 ether) * (i + 1);
            uint256 borrowedAmount = _utils.calculateBorrowAmount(
                collAmount + (0.2 ether),
                priceFeedMock.fetchPrice(),
                COLLATERAL_RATIO
            );
            borrowerOperations.openCdp(borrowedAmount, "hint", "hint", collAmount + (0.2 ether));
            assertEq(cdpManager.getActiveCdpsCount(), i + 1);
            assertEq(eBTCToken.balanceOf(users[i]), borrowedAmount);
            vm.stopPrank();
        }

        MultiCdpGetter.CombinedCdpData[] memory cdps = cdpGetter.getMultipleSortedCdps(
            0,
            usersCount
        );

        uint256 totalColl = activePool.getSystemCollShares();
        uint256 totalDebt = activePool.getSystemDebt();

        uint256 collSum;
        uint256 debtSum;
        for (uint256 i = 0; i < usersCount; i++) {
            collSum += cdps[i].coll;
            debtSum += cdps[i].debt;
        }
        assertEq(collSum, totalColl);
        assertEq(debtSum, totalDebt);
    }
}
