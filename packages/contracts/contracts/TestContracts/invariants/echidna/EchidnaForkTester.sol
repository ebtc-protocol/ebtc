// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./EchidnaAsserts.sol";
import "./EchidnaProperties.sol";
import "../TargetFunctions.sol";

contract EchidnaForkTester is EchidnaAsserts, EchidnaProperties, TargetFunctions {
    constructor() payable {
        _setUpFork();
        _setUpActors();
        
        // https://etherscan.io/tx/0xca4f2e9a7e8cc82969e435091576dbd8c8bfcc008e89906857056481e0542f23
        hevm.roll(19437242); // Block
        hevm.warp(1710460800);
    }

    function setPrice(uint256) public pure override {
        require(false, "Skip. TODO: call hevm.store to update the price");
    }

    function setGovernanceParameters(uint256, uint256) public pure override {
        require(false, "Skip. TODO: call hevm.store to bypass timelock");
    }

    function setEthPerShare(uint256) public pure override {
        require(false, "Skip. TODO: call hevm.store to seth ETH per share");
    }
}
