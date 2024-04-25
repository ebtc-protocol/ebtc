// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./EchidnaAsserts.sol";
import "./EchidnaProperties.sol";
import "../TargetFunctions.sol";

contract EchidnaForkTester is EchidnaAsserts, EchidnaProperties, TargetFunctions {
    constructor() payable {
        // https://etherscan.io/tx/0xca4f2e9a7e8cc82969e435091576dbd8c8bfcc008e89906857056481e0542f23

        _setUpFork();
        _setUpActorsFork();

        // If the accounting hasn't been synced since the last rebase
        bytes32 currentCdp = sortedCdps.getFirst();

        while (currentCdp != bytes32(0)) {
            hevm.prank(address(borrowerOperations));
            cdpManager.syncAccounting(currentCdp);
            currentCdp = sortedCdps.getNext(currentCdp);
        }

        // Previous cumulative CDPs per each rebase
        // Will need to be adjusted
        vars.cumulativeCdpsAtTimeOfRebase = 200;
    }

    function setPrice(uint256 newPrice) public override {
        _before(bytes32(0));

        hevm.store(
            address(priceFeedMock),
            0x0000000000000000000000000000000000000000000000000000000000000002,
            bytes32(0)
        );

        // Load last good price
        uint256 oldPrice = uint256(
            hevm.load(
                address(priceFeedMock),
                0x0000000000000000000000000000000000000000000000000000000000000001
            )
        );
        // New Price
        newPrice = between(
            newPrice,
            (oldPrice * 1e18) / MAX_PRICE_CHANGE_PERCENT,
            (oldPrice * MAX_PRICE_CHANGE_PERCENT) / 1e18
        );

        // Set new price by etching last good price
        hevm.store(
            address(priceFeedMock),
            0x0000000000000000000000000000000000000000000000000000000000000001,
            bytes32(newPrice)
        );

        cdpManager.syncGlobalAccountingAndGracePeriod();

        _after(bytes32(0));
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
        uint256 oldValue = uint256(
            hevm.load(
                address(collateral),
                0xa66d35f054e68143c18f32c990ed5cb972bb68a68f500cd2dd3a16bbf3686483
            )
        );

        newValue = between(
            newValue,
            (oldValue * 1e18) / MAX_REBASE_PERCENT,
            (oldValue * MAX_REBASE_PERCENT) / 1e18
        );

        hevm.store(
            address(collateral),
            0xa66d35f054e68143c18f32c990ed5cb972bb68a68f500cd2dd3a16bbf3686483,
            bytes32(newValue)
        );
        cdpManager.syncGlobalAccountingAndGracePeriod();

        _after(bytes32(0));
    }
}
