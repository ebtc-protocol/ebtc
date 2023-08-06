// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {console2 as console} from "forge-std/console2.sol";

import {eBTCBaseInvariants} from "../BaseInvariants.sol";

contract RedemptionAdjustCdpGriefTest is eBTCBaseInvariants {
    address payable[] users;

    function setUp() public override {
        super.setUp();

        connectCoreContracts();
        connectLQTYContractsToCore();
    }

    function testRetryFullLiquidation() public {
        address whale = _utils.getNextUserAddress();
        address degen1 = _utils.getNextUserAddress();
        address degen2 = _utils.getNextUserAddress();
        address degen3 = _utils.getNextUserAddress();
        address redeemer = _utils.getNextUserAddress();

        // Make price and stETH ratio 1:1 for simplicity
        priceFeedMock.setPrice(1 ether);
        collateral.setEthPerShare(1e18);

        // 1) we have TCR far above CCR because whales have created big CDP with coll >> debt
        bytes32 whaleCdp = _openTestCDP(whale, 100000 ether, 25000 ether);

        uint price = priceFeedMock.fetchPrice();
        console.log("TCR with only whale: ", cdpManager.getTCR(price));

        // 2) users (griefiers or just small investors) creates CDPs with ICR = ~MCR
        bytes32 degen1Cdp = _openTestCDP(degen1, 100 ether, 89 ether);
        bytes32 degen2Cdp = _openTestCDP(degen2, 100 ether, 89 ether);
        bytes32 degen3Cdp = _openTestCDP(degen3, 100 ether, 89 ether);

        console.log("TCR after degens only: ", cdpManager.getTCR(price));

        // 3) stETH share value drops to 1 ether - 1 wei
        collateral.setEthPerShare(1e18-1);

        // 4) users can adjust their CDP to have coll < 2 stETH as much as they want and create "dust CDPs"
        vm.prank(degen1);
        borrowerOperations.withdrawColl(degen1Cdp, 99 ether, bytes32(0), bytes32(0));

        
    }
}
