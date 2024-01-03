// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "../contracts/Dependencies/EbtcMath.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";

/*
  Tests around GracePeriod
 */
contract GracePeriodBaseTests is eBTCBaseFixture {
    event TCRNotified(uint256 TCR); /// NOTE: Mostly for debugging to ensure synch

    function setUp() public override {
        eBTCBaseFixture.setUp();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();
    }

    address liquidator;
    address safeUser;
    address degen;
    address risky;

    function testBasicSynchOnEachOperation() public {
        uint256 price = priceFeedMock.fetchPrice();

        // SKIPPED CAUSE BORING AF
        // == Open CDP == //
        console2.log("Open");
        uint256 openSnap = vm.snapshot();

        {
            _openSafeCdp();
            uint256 EXPECTED_OPEN_TCR = cdpManager.getCachedTCR(price);
            vm.revertTo(openSnap);

            // NOTE: Ported the same code of open because foundry doesn't find the event
            address payable[] memory users;
            users = _utils.createUsers(1);
            safeUser = users[0];

            uint256 debt1 = 1000e18;
            uint256 coll1 = _utils.calculateCollAmount(debt1, price, 1.30e18); // Comfy unliquidatable
            dealCollateral(safeUser, coll1);
            vm.startPrank(safeUser);
            collateral.approve(address(borrowerOperations), type(uint256).max);
            vm.expectEmit(false, false, false, true);
            emit TCRNotified(EXPECTED_OPEN_TCR);
            bytes32 safeId = borrowerOperations.openCdp(debt1, bytes32(0), bytes32(0), coll1);
            vm.stopPrank();

            // == Adjust CDP == //
            console2.log("Adjust");

            dealCollateral(safeUser, 12345 * minChange);
            uint256 adjustSnap = vm.snapshot();

            vm.startPrank(safeUser);
            borrowerOperations.addColl(safeId, ZERO_ID, ZERO_ID, 123 * minChange);
            uint256 EXPECTED_ADJUST_TCR = cdpManager.getCachedTCR(price);
            vm.revertTo(adjustSnap);

            vm.expectEmit(false, false, false, true);
            emit TCRNotified(EXPECTED_ADJUST_TCR);
            borrowerOperations.addColl(safeId, ZERO_ID, ZERO_ID, 123 * minChange);
            vm.stopPrank();
            vm.revertTo(adjustSnap);
        }

        // == Close CDP == //
        {
            console2.log("Close");
            uint256 closeSnapshot = vm.snapshot();
            // Open another so we can close it
            bytes32 safeIdSecond = _openSafeCdp();

            vm.startPrank(safeUser);
            borrowerOperations.closeCdp(safeIdSecond);
            uint256 EXPECTED_CLOSE_TCR = cdpManager.getCachedTCR(price);
            vm.revertTo(closeSnapshot);
            vm.stopPrank();

            // Open another so we can close it
            safeIdSecond = _openSafeCdp();

            vm.startPrank(safeUser);
            vm.expectEmit(false, false, false, true);
            emit TCRNotified(EXPECTED_CLOSE_TCR);
            borrowerOperations.closeCdp(safeIdSecond);
            vm.stopPrank();
        }

        // Revert back to here
        vm.revertTo(openSnap);

        // Do the rest (Redemptions and liquidations)
        _openSafeCdp();

        bytes32[] memory cdps = _openRiskyCdps(1);

        // == Redemptions == //
        // Get TCR after Redeem
        // Snapshot back
        // Then expect it to work

        uint256 biggerSnap = vm.snapshot();
        vm.startPrank(safeUser);
        _syncSystemDebtTwapToSpotValue();
        _partialRedemption(1e17, price);
        // Get TCR here
        uint256 EXPECTED_REDEMPTION_TCR = cdpManager.getCachedTCR(price);
        vm.revertTo(biggerSnap);

        _syncSystemDebtTwapToSpotValue();
        vm.expectEmit(false, false, false, true);
        emit TCRNotified(EXPECTED_REDEMPTION_TCR);
        _partialRedemption(1e17, price);

        // Trigger Liquidations via Split (so price is constant)
        _triggerRMViaSplit();
        _waitUntilRMColldown();
        vm.stopPrank();

        // Liquidate 4x
        vm.startPrank(safeUser);
        uint256 liquidationSnapshotId = vm.snapshot(); // New snap for liquidations

        // == Liquidation 1 == //
        {
            console.log("Liq 1");

            // Try liquidating a cdp
            cdpManager.liquidate(cdps[0]);
            // Get TCR after Liquidation
            uint256 EXPECTED_TCR_FIRST_LIQ_TCR = cdpManager.getCachedTCR(price);
            // Revert so we can verify Event
            vm.revertTo(liquidationSnapshotId);
            // since revertTo() deletes the snapshot and all snapshots taken after the given snapshot id
            liquidationSnapshotId = vm.snapshot();

            // Verify it worked
            vm.expectEmit(false, false, false, true);
            emit TCRNotified(EXPECTED_TCR_FIRST_LIQ_TCR);
            cdpManager.liquidate(cdps[0]);
        }

        // == Liquidate 2 == //
        {
            console.log("Liq 2");

            // Re-revert for next Op
            vm.revertTo(liquidationSnapshotId);
            // since revertTo() deletes the snapshot and all snapshots taken after the given snapshot id
            liquidationSnapshotId = vm.snapshot();

            // Try liquidating a cdp partially
            cdpManager.partiallyLiquidate(cdps[0], 1e18, cdps[0], cdps[0]);
            uint256 EXPECTED_TCR_SECOND_LIQ_TCR = cdpManager.getCachedTCR(price);
            vm.revertTo(liquidationSnapshotId);
            // since revertTo() deletes the snapshot and all snapshots taken after the given snapshot id
            liquidationSnapshotId = vm.snapshot();

            // Verify it worked
            vm.expectEmit(false, false, false, true);
            emit TCRNotified(EXPECTED_TCR_SECOND_LIQ_TCR);
            cdpManager.partiallyLiquidate(cdps[0], 1e18, cdps[0], cdps[0]);
        }

        // == Liquidate 3 == //
        {
            console.log("Liq 3");

            // Re-revert for next Op
            vm.revertTo(liquidationSnapshotId);
            // since revertTo() deletes the snapshot and all snapshots taken after the given snapshot id
            liquidationSnapshotId = vm.snapshot();

            // Try liquidating a cdp via the list (1)
            _liquidateCdps(1);
            uint256 EXPECTED_TCR_THIRD_LIQ_TCR = cdpManager.getCachedTCR(price);
            vm.revertTo(liquidationSnapshotId);
            // since revertTo() deletes the snapshot and all snapshots taken after the given snapshot id
            liquidationSnapshotId = vm.snapshot();

            // Verify it worked
            bytes32[] memory batch = _sequenceLiqToBatchLiqWithPrice(1);
            vm.expectEmit(false, false, false, true);
            emit TCRNotified(EXPECTED_TCR_THIRD_LIQ_TCR);
            cdpManager.batchLiquidateCdps(batch);
        }

        // == Liquidate 4 == //
        {
            console.log("Liq 4");

            // Re-revert for next Op
            vm.revertTo(liquidationSnapshotId);
            // since revertTo() deletes the snapshot and all snapshots taken after the given snapshot id
            liquidationSnapshotId = vm.snapshot();

            // Try liquidating a cdp via the list (2)
            bytes32[] memory cdpsToLiquidateBatch = new bytes32[](1);
            cdpsToLiquidateBatch[0] = cdps[0];
            cdpManager.batchLiquidateCdps(cdpsToLiquidateBatch);
            uint256 EXPECTED_TCR_FOURTH_LIQ_TCR = cdpManager.getCachedTCR(price);
            vm.revertTo(liquidationSnapshotId);
            // since revertTo() deletes the snapshot and all snapshots taken after the given snapshot id
            liquidationSnapshotId = vm.snapshot();

            vm.expectEmit(false, false, false, true);
            emit TCRNotified(EXPECTED_TCR_FOURTH_LIQ_TCR);
            cdpManager.batchLiquidateCdps(cdpsToLiquidateBatch);
            vm.revertTo(liquidationSnapshotId);
        }

        vm.stopPrank();
    }

    function _partialRedemption(uint256 toRedeem, uint256 price) internal {
        //redemption
        (
            bytes32 firstRedemptionHint,
            uint256 partialRedemptionHintNICR,
            uint256 truncatedEBTCamount,
            uint256 partialRedemptionNewColl
        ) = hintHelpers.getRedemptionHints(toRedeem, price, 0);
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

    function _openSafeCdp() internal returns (bytes32) {
        address payable[] memory users;
        users = _utils.createUsers(1);
        safeUser = users[0];

        // Deposit a big CDP, not at risk
        uint256 _curPrice = priceFeedMock.getPrice();
        uint256 debt1 = 1000e18;
        uint256 coll1 = _utils.calculateCollAmount(debt1, _curPrice, 1.30e18); // Comfy unliquidatable

        return _openTestCDP(safeUser, coll1, debt1);
    }

    function _openRiskyCdps(uint256 numberOfCdpsAtRisk) internal returns (bytes32[] memory) {
        address payable[] memory users;
        users = _utils.createUsers(1);

        uint256 _curPrice = priceFeedMock.getPrice();

        bytes32[] memory cdps = new bytes32[](numberOfCdpsAtRisk);

        // At risk CDPs (small CDPs)
        for (uint256 i; i < numberOfCdpsAtRisk; i++) {
            uint256 debt2 = 2e18;
            uint256 coll2 = _utils.calculateCollAmount(debt2, _curPrice, 1.15e18); // Fairly risky
            cdps[i] = _openTestCDP(users[0], coll2, debt2);
        }

        uint256 TCR = cdpManager.getCachedTCR(_curPrice);
        assertGt(TCR, CCR);

        return cdps;
    }

    function _triggerRMViaSplit() internal {
        // 4% Downward Price will trigger RM but not Liquidations
        collateral.setEthPerShare((collateral.getSharesByPooledEth(1e18) * 96) / 100); // 4% downturn, 5% should be enough to liquidate in-spite of RM
        uint256 price = priceFeedMock.getPrice();

        // Check if we are in RM
        uint256 TCR = cdpManager.getCachedTCR(price);
        assertLt(TCR, 1.25e18, "!RM");
    }
}
