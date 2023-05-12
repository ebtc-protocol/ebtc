pragma solidity 0.8.17;
import {console2 as console} from "forge-std/console2.sol";

import {eBTCBaseFixture} from "./BaseFixture.sol";

contract ActivePoolGovernanceTest is eBTCBaseFixture {
    WethMock public mockToken;

    function setUp() public override {
        eBTCBaseFixture.setUp();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();

        // Create mock token for sweeping
        mockToken = new WethMock();
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
        address feeRecipient = collateral.feeRecipientAddress();
        // grant random user role
        // user can call

        collateral.balanceOf(feeRecipient);

        // confirm balances and internal accounting after operation
        uint availableFees = activePool.getFeeRecipientClaimableColl();
        activePool.claimFeeRecipientColl(availableFees);

        assertEq(activePool.getFeeRecipientClaimableColl(), 0);

        collateral.balanceOf(feeRecipient);
    }

    function test_UnauthorizedUserCannotClaimOutstandingFeesToFeeRecipient() public {
        // random user cannot call
        // confirm balances and internal accounting after operation
    }

    function test_UserWithPermissionCanSetRecipientAddressToValidAddress(
        address _newRecipient
    ) public {
        vm.assume(_newRecipient != address(0));
        address user = _utils.getNextUserAddress();

        // grant permission to set the recipient address
        vm.prank(defaultGovernance);
        authority.setUserRole(user, 5, true);

        // user sets recipient address
        vm.prank(user);
        activePool.setFeeRecipientAddress(_newRecipient);
        assertEq(_newRecipient, activePool.feeRecipientAddress());
    }

    function test_UserWithoutPermissionCannotSetRecipientAddressToValidAddress(
        address _newRecipient
    ) public {
        vm.assume(_newRecipient != address(0));

        address oldFeeRecipient = activePool.feeRecipientAddress();
        address user = _utils.getNextUserAddress();

        // user sets recipient address
        vm.expectRevert("Auth: UNAUTHORIZED");
        activePool.setFeeRecipientAddress(_newRecipient);
        assertEq(oldFeeRecipient, activePool.feeRecipientAddress());
    }

    function test_UserWithPermissionCannotSetRecipientAddressToZeroAddress() public {
        address oldFeeRecipient = activePool.feeRecipientAddress();
        address user = _utils.getNextUserAddress();

        // grant permission to set the recipient address
        vm.prank(defaultGovernance);
        authority.setUserRole(user, 5, true);

        // user sets recipient address
        vm.prank(user);
        vm.expectRevert("ActivePool: cannot set fee recipient to zero address");
        activePool.setFeeRecipientAddress(address(0));
        assertEq(oldFeeRecipient, activePool.feeRecipientAddress());
    }

    function test_UserWithoutPermissionCannotSetRecipientAddressToZerAddress() public {
        address oldFeeRecipient = activePool.feeRecipientAddress();
        address user = _utils.getNextUserAddress();

        // user sets recipient address
        vm.expectRevert("Auth: UNAUTHORIZED");
        activePool.setFeeRecipientAddress(address(0));
        assertEq(oldFeeRecipient, activePool.feeRecipientAddress());
    }
}
