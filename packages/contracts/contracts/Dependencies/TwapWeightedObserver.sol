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
            priceCumulative0: initialValue,
            accumulator: initialValue,
            t0: uint64(block.timestamp),
            lastUpdate: uint64(block.timestamp),
            avgValue: initialValue
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

        data.lastUpdate = uint64(block.timestamp);
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
        return uint64(block.timestamp) - data.lastUpdate;
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
        uint256 futureWeight = block.timestamp - data.t0;

        if (futureWeight == 0) {
            return data.avgValue;
        }

        // A reference period is 7 days
        // For each second passed after update
        // Let's virtally sync TWAP
        // With a weight, that is higher, the more time has passed
        uint128 priceCum0 = getLatestAccumulator();
        uint128 virtualAvgValue = (priceCum0 - data.priceCumulative0) /
            (uint64(block.timestamp) - data.t0);

        uint256 maxWeight = PERIOD;
        if (futureWeight > maxWeight) {
            _update(virtualAvgValue, priceCum0, uint64(block.timestamp)); // May as well update
            // Return virtual
            return virtualAvgValue;
        }

        uint256 weightedAvg = data.avgValue * (maxWeight - futureWeight);
        uint256 weightedVirtual = virtualAvgValue * (futureWeight);

        uint256 weightedMean = (weightedAvg + weightedVirtual) / PERIOD;

        return weightedMean;
    }

    function update() public {
        // On epoch flip, we update as intended
        if (block.timestamp >= data.t0 + PERIOD) {
            uint128 latestAcc = getLatestAccumulator();

            // Compute based on delta
            uint128 avgValue = (latestAcc - data.priceCumulative0) /
                (uint64(block.timestamp) - data.t0);
            uint128 priceCum0 = latestAcc;
            uint64 time0 = uint64(block.timestamp);

            _update(avgValue, priceCum0, time0);
        }
    }

    /// Internal update so we can call it both in _update and in observe
    function _update(uint128 avgValue, uint128 priceCum0, uint64 time0) internal {
        data.avgValue = avgValue;
        data.priceCumulative0 = priceCum0;
        data.t0 = time0;
    }

    function getData() external view returns (PackedData memory) {
        return data;
    }

    /// END TWAP WEIGHTED OBSERVER ///
}
