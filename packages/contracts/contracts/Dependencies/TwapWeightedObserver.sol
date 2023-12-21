// SPDX-License Identifier: MIT
pragma solidity 0.8.17;
import {ITwapWeightedObserver} from "../Interfaces/ITwapWeightedObserver.sol";

/// @title TwapWeightedObserver
/// @notice Given a value, applies a time-weighted TWAP that smooths out changes over a 7 days period
/// @dev Used to get the lowest value of total supply to prevent underpaying redemptions
contract TwapWeightedObserver is ITwapWeightedObserver {
    PackedData public data;
    uint128 public valueToTrack;

    constructor(uint128 initialValue) {
        PackedData memory cachedData = PackedData({
            observerCumuVal: initialValue,
            accumulator: initialValue,
            observerUpdTs: uint64(block.timestamp),
            lastTrackUpdTs: uint64(block.timestamp),
            avgSinceLastObs: initialValue
        });

        valueToTrack = initialValue;
        data = cachedData;
    }

    /// TWAP ///
    event NewTrackValue(uint256 _oldValue, uint256 _newValue, uint256 _ts, uint256 _newAcc);

    // Set to new value, sync accumulator to now with old value
    // Changes in same block have no impact, as no time has expired
    // Effectively we use the previous block value, and we magnify it by weight
    function _setValue(uint128 newValue) internal {
        uint128 _newAcc = _updateAcc(valueToTrack);

        data.lastTrackUpdTs = uint64(block.timestamp);
        emit NewTrackValue(valueToTrack, newValue, block.timestamp, _newAcc);
        valueToTrack = newValue;
    }

    // Update the accumulator based on time passed
    function _updateAcc(uint128 oldValue) internal returns (uint128) {
        uint128 _newAcc = data.accumulator + oldValue * (timeToAccrue());
        data.accumulator = _newAcc;
        return _newAcc;
    }

    /// @notice Returns the time since the last update
    /// @return Duration since last update
    /// @dev Safe from overflow for tens of thousands of years
    function timeToAccrue() public view returns (uint64) {
        return uint64(block.timestamp) - data.lastTrackUpdTs;
    }

    /// @notice Returns the accumulator value, adjusted according to the current value and block timestamp
    // Return the update value to now
    function _syncToNow() internal view returns (uint128) {
        return data.accumulator + (valueToTrack * (timeToAccrue()));
    }

    // == Getters == //

    /// @notice Returns the accumulator value, adjusted according to the current value and block timestamp
    function getLatestAccumulator() public view returns (uint128) {
        return _syncToNow();
    }

    /// END TWAP ///

    /// TWAP WEIGHTED OBSERVER ///

    // Hardcoded TWAP Period of 7 days
    uint256 public constant PERIOD = 7 days;

    // Look at last
    // Linear interpolate (or prob TWAP already does that for you)

    /// @notice Returns the current value, adjusted according to the current value and block timestamp
    function observe() external returns (uint256) {
        // Here, we need to apply the new accumulator to skew the price in some way
        // The weight of the skew should be proportional to the time passed
        uint256 futureWeight = block.timestamp - data.observerUpdTs;

        if (futureWeight == 0) {
            return data.avgSinceLastObs;
        }

        // A reference period is 7 days
        // For each second passed after update
        // Let's virtally sync TWAP
        // With a weight, that is higher, the more time has passed
        (uint128 virtualAvgValue, uint128 obsAcc) = _calcUpdatedAvg();

        if (_checkUpdatePeriod()) {
            _update(virtualAvgValue, obsAcc); // May as well update
            // Return virtual
            return virtualAvgValue;
        }

        uint256 weightedAvg = data.avgSinceLastObs * (PERIOD - futureWeight);
        uint256 weightedVirtual = virtualAvgValue * (futureWeight);

        uint256 weightedMean = (weightedAvg + weightedVirtual) / PERIOD;

        return weightedMean;
    }

    function _calcUpdatedAvg() internal view returns (uint128, uint128) {
        uint128 latestAcc = getLatestAccumulator();
        uint128 avgValue = (latestAcc - data.observerCumuVal) /
            (uint64(block.timestamp) - data.observerUpdTs);
        return (avgValue, latestAcc);
    }

    function _update(uint128 avgValue, uint128 obsAcc) internal {
        data.avgSinceLastObs = avgValue;
        data.observerCumuVal = obsAcc;
        data.observerUpdTs = uint64(block.timestamp);
    }

    function _checkUpdatePeriod() internal returns (bool) {
        return block.timestamp >= (data.observerUpdTs + PERIOD);
    }

    /// @dev update time-weighted Observer
    function update() public {
        if (_checkUpdatePeriod()) {
            (uint128 avgValue, uint128 latestAcc) = _calcUpdatedAvg();
            _update(avgValue, latestAcc);
        }
    }

    function getData() external view returns (PackedData memory) {
        return data;
    }

    /// END TWAP WEIGHTED OBSERVER ///
}
