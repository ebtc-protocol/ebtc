// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;
import "forge-std/Test.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";

/*
 * Test suite that tests exactly one thing: opening CDPs
 * It tests different cases and also does random testing against random coll amounts and amount of users
 */
contract BorrowerOperationsFlashFeeGovernanceTest is eBTCBaseFixture {
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
    function test_FlashFeeInValidFullRange(uint newFee) public {
        vm.assume(newFee < MAX_BPS);

        uint oldFee = borrowerOperations.flashFee();

        vm.startPrank(defaultGovernance);

        vm.expectEmit(true, true, false, true);
        emit FlashFeeSet(defaultGovernance, oldFee, newFee);

        borrowerOperations.setFlashFee(newFee);

        assertEq(borrowerOperations.flashFee(), newFee);

        vm.stopPrank();
    }

    function test_FlashFeeInValidReducedRange(uint randomMaxFlashFee, uint newFee) public {
        vm.assume(randomMaxFlashFee < MAX_BPS);
        vm.assume(newFee < randomMaxFlashFee);

        uint oldFee = borrowerOperations.flashFee();

        vm.startPrank(defaultGovernance);

        vm.expectEmit(true, true, false, true);
        emit FlashFeeSet(defaultGovernance, oldFee, newFee);

        borrowerOperations.setFlashFee(newFee);

        assertEq(borrowerOperations.flashFee(), newFee);

        vm.stopPrank();
    }

    /**
        @dev Set the max fee randaomly within its valid range

     */
    function test_FlashFeeOutsideValidRange(uint randomMaxFlashFee, uint newFee) public {
        vm.assume(randomMaxFlashFee <= MAX_BPS);
        vm.assume(newFee > randomMaxFlashFee);

        vm.startPrank(defaultGovernance);

        borrowerOperations.setMaxFlashFee(randomMaxFlashFee);

        vm.expectRevert("ERC3156FlashLender: _newFee should <= maxFlashFee");
        borrowerOperations.setFlashFee(newFee);

        vm.stopPrank();
    }

    /**
        @dev Confirm flash loans work with zero valid fee
    */
    function test_ZeroFlashfee() public {}
}
