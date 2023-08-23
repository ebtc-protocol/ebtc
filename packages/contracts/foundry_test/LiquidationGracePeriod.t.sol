// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {console2 as console} from "forge-std/console2.sol";

import {eBTCBaseInvariants} from "./BaseInvariants.sol";

/**
    Tests to ensure delay on all external liquidations (exclusively for CDPs that can be liquidated in RM)

    Setup:
    - 2 deposits: 1 Safe, 2nd Unsafe
    - Trigger RM via a price change 
    - Ensure you must wait the 15 minutes before liquidations can occur

    # Triggers to begin RM grace period (system starting in RM):
    Price Change: PRICE UP 
        * If system remains in RM, any valid operation should set countdown
            - public manual setter
            - open, adjust, close Cdp
            - redemption
        * If system returns to NM, any valid operation should reset countdown
            - public manual setter
            - open, adjust, close Cdp
            - redemption

    StEth Rebase + Fee Split: STETH PPFS UP 
        * If system remains in RM, any valid operation should set countdown
            - public manual setter
            - open, adjust, close Cdp
            - redemption
        * If system returns to NM, any valid operation should reset countdown
            - public manual setter
            - open, adjust, close Cdp
            - redemption

    # Triggers to end RM grace period (starting in RM):
    Open Cdp Positively - TCR UP - After such an operation, TCR is up and glass is applied automatically
    Repay / Adjust - TCR UP - After such an operation, TCR is up and glass is applied automatically
    Close - After such an operation, TCR is up and glass is applied automatically
    Liquidate - After such an operation, TCR is up and glass is applied automatically
    Redeem - After such an operation, TCR is up and glass is applied automatically
 */
contract LiquidationGracePeriod is eBTCBaseInvariants {
    // enum ActionCode {
    //     MANUAL_SET
    //     OPEN_INCREASE_TCR
    //     OPEN_DECREASE_TCR
    //     ADJUST_INCREASE_TCR
    //     ADJUST_DECREASE_TCR
    //     CLOSE_INCREASE_TCR
    // }

    address payable[] users;

    function setUp() public override {
        super.setUp();

        connectCoreContracts();
        connectLQTYContractsToCore();

        users = _utils.createUsers(4);
    }

    function _priceChangeIntoRecoveryModeSetup internal {
        beta = users[0];
        degen = users[1];
        marketActor = users[2];

        priceFeedMock.setPrice(1e18);

        // beta opens healthy Cdp
        bytes32 betaCdpId = _openTestCDP();

        // degen opens risky Cdp
        bytes32 degenCdpId = _openTestCDP();

        // TCR is close to RM Threshold (CCR)
        uint price = priceFeedMock.fetchPrice();
        uint TCR = cdpManager.getTCR();

        uint newPrice = _calculateMaximumPriceToBeInRecoveryMode(TCR, );

        // Price changes pushes system into RM
    }

    // Enter RM Liquidation Grace Period: Triggers 
    function test_PriceChangeIntoRecoveryMode_GracePeriodSetByManualSetter_SystemRemainsInRecoveryMode() public {
        _priceChangeIntoRecoveryModeSetup();
    }

    function test_PriceChangeIntoRecoveryMode_GracePeriodSetByOpenCdp_SystemRemainsInRecoveryMode() public {

    }

    function test_PriceChangeIntoRecoveryMode_GracePeriodSetByAdjustCdp_SystemRemainsInRecoveryMode() public {

    }

    function test_PriceChangeIntoRecoveryMode_GracePeriodSetByRedemption_SystemRemainsInRecoveryMode() public {

    }

//     function test_PriceUpWhenRMIsAvertedManualReapplyGlass() public {}
//     function test_FeeSplitStEthUpWhileRMIsOngoingCountdownIsAdded() public {}
//     function test_FeeSplitStEthUpWhenRMIsAvertedManualReapplyGlass() public {}
//     function test_FeeSplitStEthUpWhenRMIsAvertedReapplyGlassViaOperation() public {}

//     // RM untriggers
//     function test_RMUntriggerPriceUpWhileRMIsOngoingCountdownUnchanged() public {}
//     function test_RMUntriggerPriceUpWhenRMIsAvertedManualReapplyGlass() public {}
//     function testR_MUntriggerFeeSplitSTETHUpWhileRMIsOngoingCountdownUnchanged() public {}
//     function test_RMUntriggerFeeSplitSTETHUpWhenRMIsAvertedManualReapplyGlass() public {}
//     function test_RMUntriggerFeeSplitSTETHUpWhenRMIsAvertedReapplyGlassViaOperation() public {}
//     function test_RMUntriggerOpenCDPPositiveTCRUpGlassAppliedAutomatically() public {}
//     function test_RMUntriggerRepayAdjustTCRUpGlassAppliedAutomatically() public {}
//     function test_RMUntriggerCloseOperationTCRUpGlassAppliedAutomatically() public {}
//     function test_RMUntriggerLiquidateOperationTCRUpGlassAppliedAutomatically() public {}
//     function test_RMUntriggerRedeemOperationTCRUpGlassAppliedAutomatically() public {}
}
