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

    // RM untriggered via Price - DONE
    // RM untriggered via Split - DONE

    // RM untriggered via User Operations
    // All operations where the system goes off of RM should cancel the countdown

    /**
        @dev Setup function to ensure we liquidate the correct amount of CDPs

        Current use:
        - 1 healthy Cdps at 130% (1000 scale)
        - 5 unhealthy Cdps at 115% (2 scale each)

        TCR somewhat above RM thresold ~130%

        - price drop via market price or rebase

        TCR just below RM threshold ~124.5%

     */
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

        uint TCR = cdpManager.getTCR(_curPrice);
        assertGt(TCR, CCR);

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
        vm.assume(action <= 3);

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
    function test_GracePeriodResetWhenRecoveryModeExitedViaAction_WithoutGracePeriodSet(
        uint8 priceDecreaseAction,
        uint8 action
    ) public {
        // setup: create Cdps, enter RM via price change or rebase
        vm.assume(priceDecreaseAction <= 1);
        vm.assume(action <= 3);

        // setup: create Cdps, enter RM via price change or rebase
        bytes32[] memory cdps = _openCdps(5);
        assertTrue(cdps.length == 5 + 1, "length"); // 5 created, 1 safe (first)

        _execPriceDecreaseAction(priceDecreaseAction);
        uint256 price = priceFeedMock.getPrice();

        // Check if we are in RM
        uint256 TCR = cdpManager.getTCR(price);
        assertLt(TCR, 1.25e18, "!RM");

        _assertRevertOnAllLiquidations(cdps);

        _execExitRMAction(cdps, action);

        _postExitRMLiquidationChecks(cdps);
    }

    /// @dev Recovery mode is "virtually" entered and subsequently exited via price movement
    /// @dev When no action is taken during RM, actions after RM naturally exited via price should behave as expected from NM
    function test_GracePeriodResetWhenRecoveryModeExited_WithoutAction_WithoutGracePeriodSet(
        uint8 priceDecreaseAction,
        uint8 priceIncreaseAction
    ) public {
        // setup: create Cdps, enter RM via price change or rebase
        vm.assume(priceDecreaseAction <= 1);
        vm.assume(priceIncreaseAction <= 1);

        // setup: create Cdps, enter RM via price change or rebase
        bytes32[] memory cdps = _openCdps(5);
        assertTrue(cdps.length == 5 + 1, "length"); // 5 created, 1 safe (first)

        _execPriceDecreaseAction(priceDecreaseAction);
        uint256 price = priceFeedMock.getPrice();

        // Check if we are in RM
        uint256 TCR = cdpManager.getTCR(price);
        assertLt(TCR, 1.25e18, "!RM");

        _assertRevertOnAllLiquidations(cdps);

        _execPriceIncreaseAction(priceIncreaseAction);

        // Confirm no longer in RM
        TCR = cdpManager.getTCR(priceFeedMock.getPrice());
        assertGt(TCR, 1.25e18, "still in RM");

        _assertRevertOnAllLiquidations(cdps);
    }

    function test_GracePeriodResetWhenRecoveryModeExitedViaAction_WithGracePeriodSet(
        uint8 priceDecreaseAction,
        uint8 action
    ) public {
        // setup: create Cdps, enter RM via price change or rebase
        vm.assume(priceDecreaseAction <= 1);
        vm.assume(action <= 3);

        // setup: create Cdps, enter RM via price change or rebase
        bytes32[] memory cdps = _openCdps(5);
        assertTrue(cdps.length == 5 + 1, "length"); // 5 created, 1 safe (first)

        _execPriceDecreaseAction(priceDecreaseAction);
        uint256 price = priceFeedMock.getPrice();

        // Check if we are in RM
        uint256 TCR = cdpManager.getTCR(price);
        assertLt(TCR, 1.25e18, "!RM");

        // Set grace period before action which exits RM
        cdpManager.beginRMLiquidationCooldown();

        _assertRevertOnAllLiquidations(cdps);

        _execExitRMAction(cdps, action);

        _postExitRMLiquidationChecks(cdps);
    }

    function _execValidRMAction(bytes32[] memory cdps, uint256 action) internal {
        address borrower = sortedCdps.getOwnerAddress(cdps[0]);
        uint256 price = priceFeedMock.fetchPrice();
        if (action == 0) {
            // openCdp
            uint256 debt = 2e18;
            uint256 coll = _utils.calculateCollAmount(debt, price, 1.3 ether);

            dealCollateral(borrower, coll);

            vm.prank(borrower);
            borrowerOperations.openCdp(debt, ZERO_ID, ZERO_ID, coll);
        } else if (action == 1) {
            // adjustCdp: addColl
            dealCollateral(borrower, 1);

            vm.prank(borrower);
            borrowerOperations.addColl(cdps[0], ZERO_ID, ZERO_ID, 1);
        } else if (action == 2) {
            //adjustCdp: repayEBTC
            vm.prank(borrower);
            borrowerOperations.repayEBTC(cdps[0], 1, ZERO_ID, ZERO_ID);
        } else if (action == 3) {
            uint toRedeem = 5e17;
            //redemption
            (
                bytes32 firstRedemptionHint,
                uint partialRedemptionHintNICR,
                uint truncatedEBTCamount,
                uint partialRedemptionNewColl
            ) = hintHelpers.getRedemptionHints(toRedeem, price, 0);

            vm.prank(borrower);
            cdpManager.redeemCollateral(
                toRedeem,
                firstRedemptionHint,
                ZERO_ID,
                ZERO_ID,
                partialRedemptionHintNICR,
                0,
                1e18
            );
        }

        uint256 TCR = cdpManager.getTCR(price);
        assertLt(TCR, 1.25e18, "!RM");
    }

    function _execExitRMAction(bytes32[] memory cdps, uint256 action) internal {
        address borrower = sortedCdps.getOwnerAddress(cdps[0]);
        uint256 price = priceFeedMock.fetchPrice();

        // Debt and coll values to push us out of RM
        uint256 debt = 1e18;
        uint256 coll = _utils.calculateCollAmount(debt, price, 1.3 ether) * 100000;
        if (action == 0) {
            // openCdp
            dealCollateral(borrower, coll);

            vm.prank(borrower);
            borrowerOperations.openCdp(debt, ZERO_ID, ZERO_ID, coll);
        } else if (action == 1) {
            // adjustCdp: addColl (increase coll)
            dealCollateral(borrower, coll);

            vm.prank(borrower);
            borrowerOperations.addColl(cdps[0], ZERO_ID, ZERO_ID, coll);
        } else if (action == 2) {
            //adjustCdp: withdrawEBTC (reduce debt)
            debt = cdpManager.getCdpDebt(cdps[0]);
            console.log(debt);

            vm.prank(borrower);
            borrowerOperations.repayEBTC(cdps[0], debt - 1, ZERO_ID, ZERO_ID);
        } else if (action == 3) {
            //adjustCdp: adjustCdpWithColl (reduce debt + increase coll)
            debt = cdpManager.getCdpDebt(cdps[0]);
            dealCollateral(borrower, coll);

            vm.prank(borrower);
            borrowerOperations.adjustCdpWithColl(
                cdps[0],
                0,
                debt - 1,
                false,
                ZERO_ID,
                ZERO_ID,
                coll
            );
        }

        uint256 TCR = cdpManager.getTCR(price);
        console.log(TCR);
        console.log(1.25e18);
        assertGt(TCR, 1.25e18, "!RM");
    }

    /// @dev Trigger recovery mode via a dependency action that decreases price
    function _execPriceDecreaseAction(uint8 action) internal {
        // 4% Downward Price will trigger RM
        if (action == 0) {
            priceFeedMock.setPrice((priceFeedMock.getPrice() * 96) / 100); // 4% downturn, 5% should be enough to liquidate in-spite of RM
        } else {
            collateral.setEthPerShare((collateral.getSharesByPooledEth(1e18) * 96) / 100); // 4% downturn, 5% should be enough to liquidate in-spite of RM
        }
    }

    /// @dev Trigger exit of recovery mode via a dependency action that decreases price
    function _execPriceIncreaseAction(uint8 action) internal {
        // Upward Price will leave RM
        if (action == 0) {
            priceFeedMock.setPrice((priceFeedMock.getPrice() * 105) / 100); // 4% downturn, 5% should be enough to liquidate in-spite of RM
        } else {
            collateral.setEthPerShare((collateral.getSharesByPooledEth(1e18) * 105) / 100); // 4% downturn, 5% should be enough to liquidate in-spite of RM
        }
    }

    /// @dev Run these checks immediately after action that sets grace period
    function _postValidActionLiquidationChecks(bytes32[] memory cdps) internal {
        // Grace period timestamp is now
        uint recoveryModeSetTimestamp = block.timestamp;
        assertEq(
            cdpManager.lastRecoveryModeTimestamp(),
            block.timestamp,
            "lastRecoveryModeTimestamp set time"
        );

        // Liquidations still revert
        _assertRevertOnAllLiquidations(cdps);

        // Grace Period Ended
        vm.warp(block.timestamp + cdpManager.waitTimeFromRMTriggerToLiquidations() + 1);

        // Grace period timestamp hasn't changed
        assertEq(
            cdpManager.lastRecoveryModeTimestamp(),
            recoveryModeSetTimestamp,
            "lastRecoveryModeTimestamp set time"
        );

        // Liquidations work
        _assertAllLiquidationSuccess(cdps);
    }

    function _postExitRMLiquidationChecks(bytes32[] memory cdps) internal {
        // Grace period timestamp is now
        assertEq(
            cdpManager.lastRecoveryModeTimestamp(),
            cdpManager.UNSET_TIMESTAMP_FLAG(),
            "lastRecoveryModeTimestamp unset"
        );

        // Liquidations still revert
        _assertRevertOnAllLiquidations(cdps);

        // Grace Period Ended
        vm.warp(block.timestamp + cdpManager.waitTimeFromRMTriggerToLiquidations() + 1);

        // Grace period timestamp hasn't changed
        assertEq(
            cdpManager.lastRecoveryModeTimestamp(),
            cdpManager.UNSET_TIMESTAMP_FLAG(),
            "lastRecoveryModeTimestamp unset"
        );

        // Only liquidations valid under normal work
        _assertRevertOnAllLiquidations(cdps);
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
