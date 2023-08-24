// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
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
    function _openCdps(uint256 numberOfCdpsAtRisk) internal returns (bytes32[] memory) {
        address payable[] memory users;
        users = _utils.createUsers(2);

        bytes32[] memory cdps = new bytes32[](numberOfCdpsAtRisk + 1);

        // Deposit a big CDP, not at risk
        uint256 _curPrice = priceFeedMock.getPrice();
        uint256 debt1 = 1000e18;
        uint256 coll1 = _utils.calculateCollAmount(debt1, _curPrice, 1.30e18); // Comfy unliquidatable

        cdps[0] = _openTestCDP(users[0], coll1, debt1);
        liquidator = users[0];

        // At risk CDPs (small CDPs)
        for (uint256 i; i < numberOfCdpsAtRisk; i++) {
            uint256 debt2 = 2e18;
            uint256 coll2 = _utils.calculateCollAmount(debt2, _curPrice, 1.15e18); // Fairly risky
            cdps[1 + i] = _openTestCDP(users[1], coll2, debt2);
        }
        
        // Move past bootstrap phase to allow redemptions
        vm.warp(cdpManager.getDeploymentStartTime() + cdpManager.BOOTSTRAP_PERIOD());

        return cdps;
    }

    function _openDegen() internal returns (bytes32) {
        address payable[] memory users;
        users = _utils.createUsers(1);

        uint256 _curPrice = priceFeedMock.getPrice();
        uint256 debt2 = 2e18;
        uint256 coll2 = _utils.calculateCollAmount(debt2, _curPrice, 1.105e18); // Extremely Risky
        bytes32 cdp = _openTestCDP(users[0], coll2, debt2);
        
        // Move past bootstrap phase to allow redemptions
        vm.warp(cdpManager.getDeploymentStartTime() + cdpManager.BOOTSTRAP_PERIOD());

        return cdp;
    }

    /// @dev Verifies that the Grace Period Works when triggered by a Price Dump
    function testTheBasicGracePeriodViaPrice() public {
        bytes32[] memory cdps = _openCdps(5);
        assertTrue(cdps.length == 5 + 1, "length"); // 5 created, 1 safe (first)

        _triggerRMViaPrice();

        _checkLiquidationsFSMForRmCdps(cdps);
    }

    function testTheBasicGracePeriodViaPriceWithDegenGettingLiquidated() public {
        // Open Safe and RM Risky
        bytes32[] memory rmLiquidatableCdps = _openCdps(5);

        // Open Degen
        bytes32 degen = _openDegen();

        // Trigger RM
        _triggerRMViaPrice();

        uint256 degenSnapshot = vm.snapshot();
        // Do extra checks for Degen getting liquidated Etc..
        _checkLiquidationsForDegen(degen);
        vm.revertTo(degenSnapshot);

        vm.startPrank(liquidator);
        // Liquidate Degen
        cdpManager.liquidate(degen); // Liquidate them "for real"
        vm.stopPrank();

        // Then do the same checks for Grace Period
        _checkLiquidationsFSMForRmCdps(rmLiquidatableCdps); // Verify rest of behaviour is consistent with Grace Period
    }

    function _triggerRMViaPrice() internal {
        // 4% Downward Price will trigger RM but not Liquidations
        priceFeedMock.setPrice((priceFeedMock.getPrice() * 96) / 100); // 4% downturn, 5% should be enough to liquidate in-spite of RM
        uint256 reducedPrice = priceFeedMock.getPrice();

        // Check if we are in RM
        uint256 TCR = cdpManager.getTCR(reducedPrice);
        assertLt(TCR, 1.25e18, "!RM");
    }

    /// @dev Verifies that the Grace Period Works when triggered by a Slashing
    function testTheBasicGracePeriodViaSplit() public {
        bytes32[] memory cdps = _setupAndTriggerRMViaSplit();

        _checkLiquidationsFSMForRmCdps(cdps);
    }

    function _triggerRMViaSplit() internal {
        // 4% Downward Price will trigger RM but not Liquidations
        collateral.setEthPerShare((collateral.getSharesByPooledEth(1e18) * 96) / 100); // 4% downturn, 5% should be enough to liquidate in-spite of RM
        uint256 price = priceFeedMock.getPrice();

        // Check if we are in RM
        uint256 TCR = cdpManager.getTCR(price);
        assertLt(TCR, 1.25e18, "!RM");
    }

    function _setupAndTriggerRMViaSplit() internal returns (bytes32[] memory) {
        bytes32[] memory cdps = _openCdps(5);
        assertTrue(cdps.length == 5 + 1, "length"); // 5 created, 1 safe (first)

        _triggerRMViaSplit();

        return cdps;
    }

    function testTheBasicGracePeriodViaSplitWithDegenGettingLiquidated() public {
        // Open Safe and RM Risky
        bytes32[] memory rmLiquidatableCdps = _openCdps(5);

        // Open Degen
        bytes32 degen = _openDegen();

        // Trigger RM
        _triggerRMViaSplit();

        uint256 degenSnapshot = vm.snapshot();
        // Do extra checks for Degen getting liquidated Etc..
        _checkLiquidationsForDegen(degen);
        vm.revertTo(degenSnapshot);

        vm.startPrank(liquidator);
        // Liquidate Degen
        cdpManager.liquidate(degen); // Liquidate them "for real"
        vm.stopPrank();

        // Then do the same checks for Grace Period
        _checkLiquidationsFSMForRmCdps(rmLiquidatableCdps); // Verify rest of behaviour is consistent with Grace Period
    }


    /// Verify that if the Grace Period is not started, true liquidations still happen
    /// Verify that if the Grace Period is started, true liquidations still happen
    /// Verify that if the Grace Period is finished, true liquidations still happen



    /// Verify Grace Period Synching applies to all external functions
    
    
    /// Claim Fee Split prob doesn't


    /// @dev Verifies liquidations wrt Grace Period and Cdps that can be always be liquidated
    function _checkLiquidationsForDegen(bytes32 cdp) internal {
        // Grace Period not started, expect reverts on liquidations
        _assertSuccessOnAllLiquidationsDegen(cdp);

        cdpManager.beginRMLiquidationCooldown();
        // 15 mins not elapsed, prove these cdps still revert
        _assertSuccessOnAllLiquidationsDegen(cdp);

        // Grace Period Ended, liquidations work
        vm.warp(block.timestamp + cdpManager.waitTimeFromRMTriggerToLiquidations() + 1);
        _assertSuccessOnAllLiquidationsDegen(cdp);
    }

    /// @dev Verifies liquidations wrt Grace Period and Cdps that can be liquidated only during RM
    function _checkLiquidationsFSMForRmCdps(bytes32[] memory cdps) internal {
        // Grace Period not started, expect reverts on liquidations
        _assertRevertOnAllLiquidations(cdps);

        cdpManager.beginRMLiquidationCooldown();
        // 15 mins not elapsed, prove these cdps still revert
        _assertRevertOnAllLiquidations(cdps);

        // Grace Period Ended, liquidations work
        vm.warp(block.timestamp + cdpManager.waitTimeFromRMTriggerToLiquidations() + 1);
        _assertAllLiquidationSuccess(cdps);
    }

    /** 
        @dev Test ways the grace period could be set in RM by expected exteral calls
        @dev "Valid" actions are actions that can trigger grace period and also keep the system in recovery mode

        PriceDecreaseAction:
        - setPrice
        - setEthPerShare

        Action:
        - openCdp
        - adjustCdp
        - redemptions
    */
    function test_GracePeriodViaValidAction(uint8 priceDecreaseAction, uint8 action) public {
        vm.assume(priceDecreaseAction <= 1);
        vm.assume(action <= 2);

        // setup: create Cdps, enter RM via price change or rebase
        bytes32[] memory cdps = _openCdps(5);
        assertTrue(cdps.length == 5 + 1, "length"); // 5 created, 1 safe (first)

        _execPriceDecreaseAction(priceDecreaseAction);
        uint256 price = priceFeedMock.getPrice();

        // Check if we are in RM
        uint256 TCR = cdpManager.getTCR(price);
        assertLt(TCR, 1.25e18, "!RM");

        // Pre valid
        _assertRevertOnAllLiquidations(cdps);

        _execValidRMAction(cdps, action);

        _postValidActionLiquidationChecks(cdps);
    }

    /// @dev Enumerate variants of ways the grace period could be reset
    /// @dev "Valid" actions are actions that can trigger grace period and also keep the system in recovery mode
    function test_GracePeriodResetWhenRecoveryModeExitedViaAction(uint8 priceDecreaseAction, uint8 validA) public {
        // setup: create Cdps, enter RM via price change or rebase
    }

    function _execValidRMAction(bytes32[] memory cdps, uint256 action) internal {
        address borrower = sortedCdps.getOwnerAddress(cdps[0]);
        uint256 price = priceFeedMock.fetchPrice();
        if (action == 0) { // openCdp
            uint256 debt = 2e18;
            uint256 coll = _utils.calculateCollAmount(debt, price, 1.3 ether);

            dealCollateral(borrower, coll);

            vm.prank(borrower);
            borrowerOperations.openCdp(coll, bytes32(0), bytes32(0), debt);

            uint256 TCR = cdpManager.getTCR(price);
            assertLt(TCR, 1.25e18, "!RM");
        } else if (action == 1) { // adjustCdp: addColl
            dealCollateral(borrower, 1);

            vm.prank(borrower);
            borrowerOperations.addColl(cdps[0], bytes32(0), bytes32(0), 1);

            uint256 TCR = cdpManager.getTCR(price);
            assertLt(TCR, 1.25e18, "!RM");
        } else if (action == 2) { //adjustCdp: repayEBTC
            vm.prank(borrower);
            borrowerOperations.repayEBTC(cdps[0], 1, bytes32(0), bytes32(0));

            uint256 TCR = cdpManager.getTCR(price);
            assertLt(TCR, 1.25e18, "!RM");
        }
    }

    function _execPriceDecreaseAction(uint8 priceDecreaseAction) internal {
        // 4% Downward Price will trigger
        if (priceDecreaseAction == 0) {
            priceFeedMock.setPrice((priceFeedMock.getPrice() * 96) / 100); // 4% downturn, 5% should be enough to liquidate in-spite of RM
        } else {
            collateral.setEthPerShare((collateral.getSharesByPooledEth(1e18) * 96) / 100); // 4% downturn, 5% should be enough to liquidate in-spite of RM
        }
    }

    function _postValidActionLiquidationChecks(bytes32[] memory cdps) internal {
        // Liquidations still revert
        _assertRevertOnAllLiquidations(cdps);

        // Grace Period Ended, liquidations work
        vm.warp(block.timestamp + cdpManager.waitTimeFromRMTriggerToLiquidations() + 1);
        _assertAllLiquidationSuccess(cdps);
    }

    function _assertRevertOnAllLiquidations(bytes32[] memory cdps) internal {
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

    function _assertSuccessOnAllLiquidationsDegen(bytes32 cdp) internal {
        vm.startPrank(liquidator);
        uint256 snapshotId = vm.snapshot();

        // Try liquidating a cdp
        cdpManager.liquidate(cdp);
        vm.revertTo(snapshotId);

        // Try liquidating a cdp partially
        cdpManager.partiallyLiquidate(cdp, 1e18, cdp, cdp);
        vm.revertTo(snapshotId);

        // Try liquidating a cdp via the list (2)
        bytes32[] memory cdpsToLiquidateBatch = new bytes32[](1);
        cdpsToLiquidateBatch[0] = cdp;
        cdpManager.batchLiquidateCdps(cdpsToLiquidateBatch);
        vm.revertTo(snapshotId);


        // Try liquidating a cdp via the list (1)
        cdpManager.liquidateCdps(1);
        vm.revertTo(snapshotId);

        console2.log("About to batchLiquidateCdps", uint256(cdp));


        console2.log("This log if batchLiquidateCdps didn't revert");


        vm.stopPrank();
    }

    function _assertAllLiquidationSuccess(bytes32[] memory cdps) internal {
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
        
        vm.stopPrank();
    }
}
