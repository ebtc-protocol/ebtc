// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// Interface for State Updates that can trigger RM Liquidations
interface IRmLiquidationsChecker {
    event TCRNotified(uint TCR); /// NOTE: Mostly for debugging to ensure synch

    // NOTE: Ts is implicit in events (it's added by GETH)
    event GracePeriodStart();
    event GracePeriodEnd();

    function checkLiquidateCoolDownAndReset() external;

    function notifyBeginRM(uint256 tcr) external;

    function notifyEndRM(uint256 tcr) external;
}
