// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// Interface for State Updates that can trigger RM Liquidations
interface IRmLiquidationsChecker {
    function syncRMLiquidationGracePeriod() external;

    function notifyRMLiquidationGracePeriod(bool isRecoveryMode) external;

    function notifyBeginRM() external;

    function notifyEndRM() external;
}
