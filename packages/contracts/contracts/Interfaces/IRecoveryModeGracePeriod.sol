// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// Interface for State Updates that can trigger RM Liquidations
interface IRecoveryModeGracePeriod {
    event TCRNotified(uint256 TCR); /// NOTE: Mostly for debugging to ensure synch

    // NOTE: Ts is implicit in events (it's added by GETH)
    event GracePeriodStart();
    event GracePeriodEnd();
    event GracePeriodDurationSet(uint256 _recoveryModeGracePeriodDuration);

    function notifyStartGracePeriod(uint256 tcr) external;

    function notifyEndGracePeriod(uint256 tcr) external;
}
