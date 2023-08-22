// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// Interface for State Updates that can trigger RM Liquidations
interface IRmLiquidationsChecker {
    function checkLiquidateCoolDownAndReset() external;
}
