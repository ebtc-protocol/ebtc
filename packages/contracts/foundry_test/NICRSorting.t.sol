// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "../contracts/Dependencies/LiquityMath.sol";
import {eBTCBaseInvariants} from "./BaseInvariants.sol";

contract NICRSortingTest is eBTCBaseInvariants {
    address[] public users;

    function setUp() public override {
        super.setUp();
        connectCoreContracts();
        connectLQTYContractsToCore();
        vm.warp(3 weeks);

        users = _utils.createUsers(4);
    }

    function test_NICROrderingShouldStaySameAfterFeeSplit() public {
        // Deposit 100 shares (A)
        (, bytes32 cdp0) = _openTestCdpAtICR(users[0], 100e18, 150e16);

        // stEth increase by 20%
        collateral.setEthPerShare(1.2e18);

        // Deposit 100 shares (B)
        (, bytes32 cdp1) = _openTestCdpAtICR(users[1], 100e18, 150e16);

        // Accure + fee split (A) -> A is 90 shares
        vm.prank(address(borrowerOperations));
        cdpManager.syncAccounting(cdp0);
        _ensureSystemInvariants();
    }
}
