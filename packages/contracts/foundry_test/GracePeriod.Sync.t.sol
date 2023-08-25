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

    event TCRNotified(uint TCR); /// NOTE: Mostly for debugging to ensure synch

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
        // SKIPPED CAUSE BORING AF
        // Open
        _openSafeCdp();
        // Adjust
        // Close

        _openRiskyCdps(1);


        // Adjust and close one cdp
        // TODO

        // Redeem
        // Get TCR after Redeem
        // Snapshot back
        // Then expect it to work
        
        uint256 biggerSnap = vm.snapshot();
        uint256 price = priceFeedMock.fetchPrice();
        vm.startPrank(safeUser);
        _partialRedemption(1e17, price);
        // Get TCR here
        uint256 EXPECTED_TCR = cdpManager.getTCR(price);
        vm.revertTo(biggerSnap);

        vm.expectEmit(false, false, false, true);
        emit TCRNotified(EXPECTED_TCR);
        _partialRedemption(1e17, price);


        // Liquidate 4x
    }

    function _partialRedemption(uint256 toRedeem, uint256 price) internal {
        //redemption
        (
            bytes32 firstRedemptionHint,
            uint partialRedemptionHintNICR,
            uint truncatedEBTCamount,
            uint partialRedemptionNewColl
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


        // TODO: Add a check here for TCR being computed correctly and sent properly

        return _openTestCDP(safeUser, coll1, debt1);
    }


    function _openRiskyCdps(uint256 numberOfCdpsAtRisk) internal returns (bytes32[] memory) {
        address payable[] memory users;
        users = _utils.createUsers(1);

        uint256 _curPrice = priceFeedMock.getPrice();

        bytes32[] memory cdps = new bytes32[](numberOfCdpsAtRisk + 1);

        // At risk CDPs (small CDPs)
        for (uint256 i; i < numberOfCdpsAtRisk; i++) {
            uint256 debt2 = 2e18;
            uint256 coll2 = _utils.calculateCollAmount(debt2, _curPrice, 1.15e18); // Fairly risky
            cdps[1 + i] = _openTestCDP(users[0], coll2, debt2);
        }

        uint TCR = cdpManager.getTCR(_curPrice);
        assertGt(TCR, CCR);

        // Move past bootstrap phase to allow redemptions
        vm.warp(cdpManager.getDeploymentStartTime() + cdpManager.BOOTSTRAP_PERIOD());

        return cdps;
    }
}
