// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// Interface for State Updates that can trigger RM Liquidations
interface IRecoveryModeGracePeriod {
    event TCRNotified(uint TCR); /// NOTE: Mostly for debugging to ensure synch

    // NOTE: Ts is implicit in events (it's added by GETH)
    event GracePeriodStart();
    event GracePeriodEnd();
    event GracePeriodSet(uint256 _recoveryModeGracePeriod);

    function syncGracePeriod() external;

    function notifyStartGracePeriod(uint256 tcr) external;

    function notifyEndGracePeriod(uint256 tcr) external;
}
