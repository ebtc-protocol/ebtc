// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

/**
 * Based on the stETH:
 *  -   https://docs.lido.fi/contracts/lido#
 */
interface ICollateralTokenOracle {
    // Return beacon specification data.
    function getBeaconSpec()
        external
        view
        returns (
            uint64 epochsPerFrame,
            uint64 slotsPerEpoch,
            uint64 secondsPerSlot,
            uint64 genesisTime
        );
}
