// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "../contracts/Dependencies/LiquityMath.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";

/*
  Tests around GracePeriod
 */
contract GracePeriodBaseTests is eBTCBaseFixture {
    function setUp() public override {
        eBTCBaseFixture.setUp();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();
    }

    address liquidator;


    // == DELAY TEST == //
    // Delay of 15 minutes is enforced to liquidate CDPs in RM that are not below MCR - DONE
    // No Delay for the Portion of CDPs which is below MCR - TODO

    // RM Triggered via Price - DONE
    // RM Triggered via Split - DONE
    
    // RM Triggered via User Operation
    // All operations where the system is in RM should trigger the countdown

    // RM untriggered via Price
    // RM untriggered via Split

    // RM untriggered via User Operations
    // All operations where the system goes off of RM should cancel the countdown

    /// @dev Setup function to ensure we liquidate the correct amount of CDPs
    function triggerRmBasic(uint256 numberOfCdpsAtRisk) internal returns (bytes32[] memory) {
        address payable[] memory users;
        users = _utils.createUsers(2);

        bytes32[] memory cdps = new bytes32[](numberOfCdpsAtRisk + 1);

      // Deposit a big CDP, not at risk
        uint _curPrice = priceFeedMock.getPrice();
        uint256 debt1 = 1000e18;
        uint256 coll1 = _utils.calculateCollAmount(debt1, _curPrice, 1.30e18); // Comfy unliquidatable

        cdps[0] = _openTestCDP(users[0], coll1, debt1);
        liquidator = users[0];

        // At risk CDPs (small CDPs)
        for(uint256 i; i < numberOfCdpsAtRisk; i++) {
            uint256 debt2 = 2e18;
            uint256 coll2 = _utils.calculateCollAmount(debt2, _curPrice, 1.15e18); // Fairly risky
            cdps[1 + i] = _openTestCDP(users[1], coll2, debt2);
        }

      // Deposit a bunch at risk

      return cdps;
    }
    
    function testTheBasicGracePeriodViaPrice() public {
      bytes32[] memory cdps = triggerRmBasic(5);
      assertTrue(cdps.length == 5 + 1, "length"); // 5 created, 1 safe (first)
      

      // 2% Downward Price will trigger
      priceFeedMock.setPrice(priceFeedMock.getPrice() * 96 / 100); // 4% downturn, 5% should be enough to liquidate in-spite of RM
      uint256 reducedPrice = priceFeedMock.getPrice();

      // Check if we are in RM
      uint256 TCR = cdpManager.getTCR(reducedPrice);
      assertLt(TCR, 1.25e18, "!RM");

      // Check the stuff after RM
      // Do it as a function and reuse it
      // checkPropertiesOfTriggerinRM();
    }

    function testTheBasicGracePeriodViaSplit() public {
      bytes32[] memory cdps = triggerRmBasic(5);
      assertTrue(cdps.length == 5 + 1, "length"); // 5 created, 1 safe (first)
      

      // 2% Downward Price will trigger
      collateral.setEthPerShare(collateral.getSharesByPooledEth(1e18) * 96 / 100);// 4% downturn, 5% should be enough to liquidate in-spite of RM
      uint256 price = priceFeedMock.getPrice();

      // Check if we are in RM
      uint256 TCR = cdpManager.getTCR(price);
      assertLt(TCR, 1.25e18, "!RM");

      // Check the stuff after RM
      // Do it as a function and reuse it

      // Glass is not broken all liquidations revert (since those are not risky CDPs)
      assertRevertOnAllLiquidations(cdps);

      // Glass is broken
      cdpManager.beginRMLiquidationCooldown();
      // Liquidations still revert
      assertRevertOnAllLiquidations(cdps);

      // Grace Period Ended, liquidations work
      vm.warp(block.timestamp + cdpManager.waitTimeFromRMTriggerToLiquidations() + 1);
      assertAllLiquidationSuccess(cdps);
    }

    function assertRevertOnAllLiquidations(bytes32[] memory cdps) internal {
      // Try liquidating a cdp
      vm.expectRevert();
      cdpManager.liquidate(cdps[1]);

      // Try liquidating a cdp partially
      vm.expectRevert();
      cdpManager.partiallyLiquidate(cdps[1], 1e18, cdps[1], cdps[1]);

      // Try liquidating a cdp via the list (1)
      vm.expectRevert();
      cdpManager.liquidateCdps(1);

      // Try liquidating a cdp via the list (2)
      bytes32[] memory cdpsToLiquidateBatch = new bytes32[](1);
      cdpsToLiquidateBatch[0] = cdps[1];
      vm.expectRevert();
      cdpManager.batchLiquidateCdps(cdpsToLiquidateBatch);
    }

    function assertAllLiquidationSuccess(bytes32[] memory cdps) internal {
      vm.startPrank(liquidator);
      uint256 snapshotId = vm.snapshot();

      // Try liquidating a cdp
      cdpManager.liquidate(cdps[1]);

      vm.revertTo(snapshotId);

      // Try liquidating a cdp partially
      cdpManager.partiallyLiquidate(cdps[1], 1e18, cdps[1], cdps[1]);

      vm.revertTo(snapshotId);

      // Try liquidating a cdp via the list (1)
      cdpManager.liquidateCdps(1);

      vm.revertTo(snapshotId);

      // Try liquidating a cdp via the list (2)
      bytes32[] memory cdpsToLiquidateBatch = new bytes32[](1);
      cdpsToLiquidateBatch[0] = cdps[1];
      cdpManager.batchLiquidateCdps(cdpsToLiquidateBatch);

      vm.revertTo(snapshotId);
    }
}