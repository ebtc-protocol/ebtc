// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "forge-std/Test.sol";

import {PriceFeed} from "../contracts/PriceFeed.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";
import {TellorCaller} from "../contracts/Dependencies/TellorCaller.sol";

contract PriceFeedTester is PriceFeed {
    function getCurrentTellorResponse() public view returns (TellorResponse memory tellorResponse) {
        return _getCurrentTellorResponse();
    }

    function getCurrentChainlinkResponse()
        public
        view
        returns (ChainlinkResponse memory chainlinkResponse)
    {
        return _getCurrentChainlinkResponse();
    }

    function scaleChainlinkPriceByDigits(uint _price, uint _decimals) public view returns (uint256) {
        return _scaleChainlinkPriceByDigits(_price, _decimals);
    }

    function bothOraclesSimilarPrice(
        ChainlinkResponse memory _chainlinkResponse,
        TellorResponse memory _tellorResponse
    ) public view returns (bool) {
        return _bothOraclesSimilarPrice(_chainlinkResponse, _tellorResponse);
    }
}

contract PriceFeedTest is eBTCBaseFixture {
    PriceFeedTester internal _priceFeed;
    TellorCaller internal _tellorCaller;
    bytes32[] cdpIds;

    // To run this forktest, make tests public instead of private
    function testPriceFeedFork() private {
        _priceFeed = new PriceFeedTester();
        _tellorCaller = new TellorCaller(0xB3B662644F8d3138df63D2F43068ea621e2981f9);
        _priceFeed.setAddresses(0xAc559F25B1619171CbC396a50854A3240b6A4e99, address(_tellorCaller));
        PriceFeed.TellorResponse memory tellorResponse = _priceFeed.getCurrentTellorResponse();

        console.log("Tellor Response:");

        console.log(tellorResponse.value);
        console.log("Chainlink Response:");
        PriceFeed.ChainlinkResponse memory chainlinkResponse = _priceFeed
            .getCurrentChainlinkResponse();
        console.log(uint256(chainlinkResponse.answer));
        console.log(
            _priceFeed.scaleChainlinkPriceByDigits(
                uint256(chainlinkResponse.answer),
                chainlinkResponse.decimals
            )
        );

        console.log("PriceFeed Response:");
        console.log(_priceFeed.fetchPrice());

        bool similar = _priceFeed.bothOraclesSimilarPrice(chainlinkResponse, tellorResponse);
        console.log(similar);
    }
}
