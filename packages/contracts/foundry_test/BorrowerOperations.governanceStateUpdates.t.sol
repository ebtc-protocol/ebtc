// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;
import "forge-std/Test.sol";
import {eBTCBaseInvariants} from "./BaseInvariants.sol";

/*
    Ensure any governance function correctly updates global pending state if needed 
 */
contract BorrowerOperationsGovernanceStateUpdatesTest is eBTCBaseInvariants {
    function setUp() public override {
        super.setUp();

        connectCoreContracts();
        connectLQTYContractsToCore();
    }

    /**
        Set fee fl bps paused to a valid value
        Confirm flash fee bps is updated afterwards
     */
    function test_FlashFeeBpsGlobalStateUpdated() public {
        (uint oldIndex, uint newIndex, uint storedIndex) = _increaseCollateralIndex();
        uint oldFee = borrowerOperations.feeBps();

        vm.startPrank(defaultGovernance);
        borrowerOperations.setFeeBps(oldFee);
        vm.stopPrank();

        _ensureSystemInvariants();
    }

    /**
        Set fee fl paused bool to a valid value
        Confirm global state is updated afterwards
     */
    function test_FlashLoansPausedGlobalStateUpdated() public {
        (uint oldIndex, uint newIndex, uint storedIndex) = _increaseCollateralIndex();

        vm.startPrank(defaultGovernance);
        borrowerOperations.setFlashLoansPaused(false);
        vm.stopPrank();

        _ensureSystemInvariants();
    }

    /**
        Set fee recipient address to a valid address
        Confirm global state is updated afterwards
     */
    function test_FeeRecipientAddressGlobalStateUpdated() public {
        (uint oldIndex, uint newIndex, uint storedIndex) = _increaseCollateralIndex();

        vm.startPrank(defaultGovernance);
        borrowerOperations.setFeeRecipientAddress(address(1));
        vm.stopPrank();

        _ensureSystemInvariants();
    }
}
