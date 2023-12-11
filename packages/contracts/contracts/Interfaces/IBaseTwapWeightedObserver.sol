// SPDX-License Identifier: MIT
pragma solidity 0.8.17;

interface IBaseTwapWeightedObserver {
    // NOTE: Packing manually is cheaper, but this is simpler to understand and follow
    struct PackedData {
        // Slot 0
        // Seconds in a year: 3.154e+7
        uint128 priceCumulative0; // 3.154e+7 * 80 * 100e27 = 2.5232e+38 | log_2(100e27 * 3.154e+7 * 80) = 127.568522171
        uint128 accumulator; // 3.154e+7 * 80 * 100e27 = 2.5232e+38 | log_2(100e27 * 3.154e+7 * 80) = 127.568522171
        // NOTE: We can further compress this slot but we will not be able to use only one (see u72 impl)
        /// So what's the point of making the code more complex?

        // Slot 1
        uint64 t0; // Thousands of Years, if we use relative time we can use u32 | Relative to deploy time (as immutable)
        uint64 lastUpdate; // Thousands of years
        // Expect eBTC debt to never surpass 100e27, which is 100 BILLION eBTC
        // log_2(100e27) = 96.3359147517 | log_2(100e27 / 1e18) = 36.5412090438
        // We could use a u64
        uint128 avgValue;
    }
}
