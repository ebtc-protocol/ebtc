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
        @dev Set the max fee to MAX_FEE_BPS
        @dev Test flash fee setter within the full valid range
     */
    function test_FlashFeeInValidFullRange(uint newFee) public {
        vm.assume(newFee < borrowerOperations.MAX_FEE_BPS());

        uint oldFee = borrowerOperations.feeBps();

        vm.startPrank(defaultGovernance);

        vm.expectEmit(true, true, false, true);
        emit FlashFeeSet(defaultGovernance, oldFee, newFee);

        borrowerOperations.setFeeBps(newFee);

        assertEq(borrowerOperations.feeBps(), newFee);

        vm.stopPrank();
    }

    function test_FlashFeeInValidReducedRange(uint randomMaxFlashFee, uint newFee) public {
        vm.assume(randomMaxFlashFee < borrowerOperations.MAX_FEE_BPS());
        vm.assume(newFee < randomMaxFlashFee);

        uint oldFee = borrowerOperations.feeBps();

        vm.startPrank(defaultGovernance);

        vm.expectEmit(true, true, false, true);
        emit FlashFeeSet(defaultGovernance, oldFee, newFee);

        borrowerOperations.setFeeBps(newFee);

        assertEq(borrowerOperations.feeBps(), newFee);

        vm.stopPrank();
    }
}
