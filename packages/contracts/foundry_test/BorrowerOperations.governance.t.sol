// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;
import "forge-std/Test.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";

/*
 * Test suite that tests exactly one thing: opening CDPs
 * It tests different cases and also does random testing against random coll amounts and amount of users
 */
contract BorrowerOperationsGovernanceTest is eBTCBaseFixture {
    mapping(bytes32 => bool) private _cdpIdsExist;

    function setUp() public override {
        eBTCBaseFixture.setUp();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();
    }

    /**
        @dev Set the max fee to 100%
        @dev Test flash fee setter within the full valid range
     */
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
        borrowerOperations.setFeeRecipientAddress(_newRecipient);
        assertEq(_newRecipient, borrowerOperations.feeRecipientAddress());
    }

    function test_UserWithoutPermissionCannotSetRecipientAddressToValidAddress(
        address _newRecipient
    ) public {
        vm.assume(_newRecipient != address(0));

        address oldFeeRecipient = borrowerOperations.feeRecipientAddress();
        address user = _utils.getNextUserAddress();

        // user sets recipient address
        vm.expectRevert("Auth: UNAUTHORIZED");
        vm.prank(user);
        borrowerOperations.setFeeRecipientAddress(_newRecipient);
        assertEq(oldFeeRecipient, borrowerOperations.feeRecipientAddress());
    }

    function test_UserWithPermissionCannotSetRecipientAddressToZeroAddress() public {
        address oldFeeRecipient = borrowerOperations.feeRecipientAddress();
        address user = _utils.getNextUserAddress();

        // grant permission to set the recipient address
        vm.prank(defaultGovernance);
        authority.setUserRole(user, 5, true);

        // user sets recipient address
        vm.prank(user);
        vm.expectRevert("BorrowerOperations: Cannot set feeRecipient to zero address");
        borrowerOperations.setFeeRecipientAddress(address(0));
        assertEq(oldFeeRecipient, borrowerOperations.feeRecipientAddress());
    }

    function test_UserWithoutPermissionCannotSetRecipientAddressToZerAddress() public {
        address oldFeeRecipient = borrowerOperations.feeRecipientAddress();
        address user = _utils.getNextUserAddress();

        // user sets recipient address
        vm.expectRevert("Auth: UNAUTHORIZED");
        borrowerOperations.setFeeRecipientAddress(address(0));
        assertEq(oldFeeRecipient, borrowerOperations.feeRecipientAddress());
    }
}
