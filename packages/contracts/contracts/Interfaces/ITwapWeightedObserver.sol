// SPDX-License Identifier: MIT
pragma solidity 0.8.17;
import {IBaseTwapWeightedObserver} from "./IBaseTwapWeightedObserver.sol";

interface ITwapWeightedObserver is IBaseTwapWeightedObserver {
    function PERIOD() external view returns (uint256);

    function valueToTrack() external view returns (uint128);

    function timeToAccrue() external view returns (uint64);

    function getLatestAccumulator() external view returns (uint128);

    function observe() external returns (uint256);

    function update() external;
}
