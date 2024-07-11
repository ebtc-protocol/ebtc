// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface ISyncedLiquidationSequencer {
    function sequenceLiqToBatchLiq(uint256 _n) external returns (bytes32[] memory _array);
}
