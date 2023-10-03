// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "../contracts/Dependencies/EbtcMath.sol";
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

    /// @dev Should maintain despite switch in ordering due to applying fee split to just one of the Cdps after a large rebase
    /// @dev Note the current example does not swtich ordering if outdated NICR data was used.
    function test_NICROrderingShouldStaySameAfterFeeSplit() public {
        // Deposit 100 shares (A)
        (, bytes32 cdp0) = _openTestCdpAtICR(users[0], 100e18, 150e16);

        // stEth increase by 20%
        collateral.setEthPerShare(1.2e18);

        // Deposit 100 shares (B)
        uint newCdpStEthBalance = (100e18 * collateral.getPooledEthByShares(100e18)) / 100e18;
        (, bytes32 cdp1) = _openTestCdpAtICR(users[1], newCdpStEthBalance, 150e16);

        console.log(cdpManager.getCdpCollShares(cdp0));
        console.log(cdpManager.getCdpCollShares(cdp1));

        console.log("Before syncAccounting");
        _printAllCdps();
        _printSystemState();
        _printSortedCdpsList();

        assertEq(cdpManager.getCdpCollShares(cdp0), cdpManager.getCdpCollShares(cdp1));

        // Accure + fee split (A) -> A is 90 shares
        vm.prank(address(borrowerOperations));
        cdpManager.syncAccounting(cdp0);

        console.log("After syncAccounting");
        _printAllCdps();
        _printSystemState();
        _printSortedCdpsList();

        _ensureSystemInvariants();
    }
}
