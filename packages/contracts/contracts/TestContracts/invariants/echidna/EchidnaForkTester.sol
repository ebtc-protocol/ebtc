// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./EchidnaAsserts.sol";
import "./EchidnaProperties.sol";
import "../TargetFunctions.sol";

contract EchidnaForkTester is EchidnaAsserts, EchidnaProperties, TargetFunctions {
    constructor() payable {
        // https://etherscan.io/tx/0xca4f2e9a7e8cc82969e435091576dbd8c8bfcc008e89906857056481e0542f23

        _setUpFork();
        _setUpActors();
    }

    function setPrice(uint256) public pure override {
        require(false, "Skip. TODO: call hevm.store to update the price");
    }

    // Can delete this and will still be called via `TargetFunctions`
    // Don't need to etch storage, mocking it as a call from default governance should be enough
    // as the timelock logic happens in the TimelockController, and governance params only care about who is the caller
    function setGovernanceParameters(uint256 parameter, uint256 value) public override {
        TargetFunctions.setGovernanceParameters(parameter, value);
    }

    function setEthPerShare(uint256 newValue) public override {
        _before(bytes32(0));
        // Our approach is to to increase the amount of ether without increasing the number of shares
        // We load the bulk share of staked ether, then modify it, then change the value in the slot directly.
        uint256 oldValue = uint256(hevm.load(address(collateral), 0xa66d35f054e68143c18f32c990ed5cb972bb68a68f500cd2dd3a16bbf3686483));

        newValue = between(
            newValue,
            (oldValue * 1e18) / MAX_REBASE_PERCENT,
            (oldValue * MAX_REBASE_PERCENT) / 1e18
        );

        hevm.store(address(collateral), 0xa66d35f054e68143c18f32c990ed5cb972bb68a68f500cd2dd3a16bbf3686483, bytes32(newValue));
        cdpManager.syncGlobalAccountingAndGracePeriod();

        _after(bytes32(0));
    }
}
