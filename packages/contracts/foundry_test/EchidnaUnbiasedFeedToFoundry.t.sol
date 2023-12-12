// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import {InternalEchidnaFeedUnbiasedTester} from "../contracts/TestContracts/invariants/echidna/EchidnaFeedUnbiasedTester.sol";
import {FoundryAsserts} from "./utils/FoundryAsserts.sol";

/*
 * Test suite that converts from echidna "fuzz tests" to foundry "unit tests"
 * The objective is to go from random values to hardcoded values that can be analyzed more easily
 */
contract EtoFTwo is
    Test,
    InternalEchidnaFeedUnbiasedTester,
    FoundryAsserts
{
    function setUp() public {
        
    }

    function testAgainTheFeed() public {
        setPreviousEth(245780001970263909205726, 18171729198400830759034417139200982561872633605400531195186222708445767418645, 115792089237316195423570985008687907853269984665640564039457584007913129639935, true);
        setDecimals(16, false);
        setFallbackCaller(false);

        uint256 price = priceFeed.fetchPrice();
        uint256 price2 = priceFeed.fetchPrice();
        uint256 price3 = priceFeed.fetchPrice();

        assertEq(price, price2, "price 1-2 change");
        assertEq(price, price3, "price 1-3 change");
        assertEq(price2, price3, "price 2-3 change");
    }
}
