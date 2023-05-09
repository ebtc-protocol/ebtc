pragma solidity 0.8.17;
import {console2 as console} from "forge-std/console2.sol";

import {eBTCBaseFixture} from "./BaseFixture.sol";

contract ActivePoolFeeRecipientTest is eBTCBaseFixture {
    function setUp() public override {
        eBTCBaseFixture.setUp();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();

        // Send coll to activePool by opening a CDP
        // Force a fee split
    }

    function test_AuthorizedUserCanSweepTokens() public {
        // Send a mock token for sweeping
        // grant random user role
        // user can sweep
        // confirm balances
    }

    function test_UnauthorizedUserCannotSweepTokens() public {
        // Send a mock token for sweeping
        // random user cannot sweep
        // confirm balances
    }

    function test_AuthorizedUserCannotSweepCollateral() public {
        // grant random user role
        // user cannot sweep collateral
        // confirm balances
    }

    function test_UnauthorizedUserCannotSweepCollateral() public {
        // random user cannot sweep collateral
        // confirm balances
    }

    function test_AuthorizedUserCanClaimOutstandingFeesToFeeRecipient() public {
        // grant random user role
        // user can call
        // confirm balances and internal accounting after operation
    }

    function test_UnauthorizedUserCannotClaimOutstandingFeesToFeeRecipient() public {
        // random user cannot call
        // confirm balances and internal accounting after operation
    }
}
