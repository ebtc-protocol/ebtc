// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "../contracts/BraindeadFeed.sol";
import "../contracts/Interfaces/IOracleCaller.sol";

contract MockCLCaller is  IOracleCaller {
  uint256 public getLatestPrice;
  
  function setPrice(uint256 newPrice) external {
    getLatestPrice = newPrice;
  }
}

contract BraindeadFeedUnit is Test {
  MockCLCaller mockCl;
  BraindeadFeed feed;

  function setUp() public {
    mockCl = new MockCLCaller();
    mockCl.setPrice(123);
    feed = new BraindeadFeed(address(mockCl), address(0));
  }

  function testTinfoilCalls(uint256 price) public {
    if(price == 0) {
      price = 1;
    }
    mockCl.setPrice(price);
    assertEq(mockCl.getLatestPrice(), price, "Mock CL has bug");

    assertEq(feed.fetchPrice(), price, "Feed and CL Match");
  }

}