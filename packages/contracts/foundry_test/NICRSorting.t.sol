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
        // stEth increase by 100%
        uint256 _newIndex = 2e18;
        uint256 _sameShare = 200e18;

        // Deposit for (A)
        (, bytes32 cdp0) = _openTestCdpAtICR(users[0], _sameShare, 150e16);

        collateral.setEthPerShare(_newIndex);

        // Deposit same share for (B)
        uint newCdpStEthBalance = collateral.getPooledEthByShares(_sameShare);
        (, bytes32 cdp1) = _openTestCdpAtICR(users[1], newCdpStEthBalance, 150e16);

        console.log("cdp0 coll share=", cdpManager.getCdpCollShares(cdp0));
        console.log("cdp1 coll share=", cdpManager.getCdpCollShares(cdp1));

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
