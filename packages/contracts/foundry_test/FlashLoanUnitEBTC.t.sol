// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;
pragma experimental ABIEncoderV2;

import "forge-std/Test.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";
import {UselessFlashReceiver, eBTCFlashReceiver, FlashLoanSpecReceiver, FlashLoanWrongReturn} from "./utils/Flashloans.sol";

/*
 * Unit Tests for Flashloans
 * Basic Considerations:
 * Flash Fee can go to zero due to rounding, that's marginal
 * Minting is capped at u112 for UniV2 Compatibility, but mostly arbitrary
 */
contract FlashLoanUnitEBTC is eBTCBaseFixture {
    // Flashloans
    UselessFlashReceiver internal uselessReceiver;
    eBTCFlashReceiver internal ebtcReceiver;
    FlashLoanSpecReceiver internal specReceiver;
    FlashLoanWrongReturn internal wrongReturnReceiver;

    function setUp() public override {
        // Base setup
        eBTCBaseFixture.setUp();

        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();

        // Create a CDP
        address payable[] memory users;
        users = _utils.createUsers(1);
        address user = users[0];
        uint borrowedAmount = _utils.calculateBorrowAmount(
            30 ether,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );
        // Make sure there is no CDPs in the system yet
        assert(sortedCdps.getLast() == "");
        vm.startPrank(user);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 30 ether}();
        borrowerOperations.openCdp(borrowedAmount, "hint", "hint", 30 ether);
        vm.stopPrank();

        uselessReceiver = new UselessFlashReceiver();
        ebtcReceiver = new eBTCFlashReceiver();
        specReceiver = new FlashLoanSpecReceiver();
        wrongReturnReceiver = new FlashLoanWrongReturn();
    }

    /// @dev Basic happy path test
    /// @notice We cap to uint128 avoid multiplication overflow
    function testBasicLoanEBTC(uint128 loanAmount) public {
        require(address(ebtcReceiver) != address(0));

        uint256 fee = borrowerOperations.flashFee(address(eBTCToken), loanAmount);

        // Funny enough 0 reverts because of deal not
        vm.assume(loanAmount > 0);

        // No cheecky overflow
        vm.assume(loanAmount + fee <= type(uint256).max);

        // Cannot deal if not enough
        vm.assume(fee > 1800e18);

        deal(address(eBTCToken), address(ebtcReceiver), fee);

        uint256 prevFeeBalance = eBTCToken.balanceOf(borrowerOperations.FEE_RECIPIENT());

        // Perform flashloan
        borrowerOperations.flashLoan(
            ebtcReceiver,
            address(eBTCToken),
            loanAmount,
            abi.encodePacked(uint256(0))
        );

        // Check fees were sent and balance increased exactly by the expected fee amount
        assertEq(eBTCToken.balanceOf(borrowerOperations.FEE_RECIPIENT()), prevFeeBalance + fee);
    }

    /// @dev Can take a 0 flashloan, nothing happens
    function testZeroCaseEBTC() public {
        // Zero test case
        uint256 loanAmount = 0;

        vm.expectRevert("BorrowerOperations: 0 Amount");
        // Perform flashloan
        borrowerOperations.flashLoan(
            ebtcReceiver,
            address(eBTCToken),
            loanAmount,
            abi.encodePacked(uint256(0))
        );
    }

    /// @dev Amount too high, we overflow when computing fees
    function testOverflowCaseEBTC() public {
        // Zero Overflow Case
        uint256 loanAmount = type(uint256).max;

        try
            borrowerOperations.flashLoan(
                ebtcReceiver,
                address(eBTCToken),
                loanAmount,
                abi.encodePacked(uint256(0))
            )
        {} catch Panic(uint _errorCode) {
            assertEq(_errorCode, 17); //0x11: If an arithmetic operation results in underflow or overflow outside of an unchecked block.
        }
    }

    /// @dev Do nothing (no fee), check that it reverts
    function testEBTCRevertsIfUnpaid(uint128 loanAmount) public {
        uint256 fee = borrowerOperations.flashFee(address(eBTCToken), loanAmount);
        // Ensure fee is not rounded down
        vm.assume(fee > 1);

        deal(address(eBTCToken), address(uselessReceiver), fee);

        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        // Perform flashloan
        borrowerOperations.flashLoan(
            uselessReceiver,
            address(eBTCToken),
            loanAmount,
            abi.encodePacked(uint256(0))
        );
    }

    /// @dev This test converts the MUST into assets from the spec
    ///   Using a custom receiver to ensure state and balances follow the spec
    /// @notice Based on the spec: https://eips.ethereum.org/EIPS/eip-3156
    function testEBTCSpec(uint128 amount, address randomToken) public {
        vm.assume(randomToken != address(eBTCToken));
        vm.assume(amount > 0);

        // The maxFlashLoan function MUST return the maximum loan possible for token.
        assertEq(borrowerOperations.maxFlashLoan(address(eBTCToken)), type(uint112).max);

        // If a token is not currently supported maxFlashLoan MUST return 0, instead of reverting.
        assertEq(borrowerOperations.maxFlashLoan(randomToken), 0);

        uint256 fee = borrowerOperations.flashFee(address(eBTCToken), amount);

        // The flashFee function MUST return the fee charged for a loan of amount token.
        assertTrue(fee >= 0);
        assertEq(fee, (amount * borrowerOperations.FEE_AMT()) / borrowerOperations.MAX_BPS());

        // If the token is not supported flashFee MUST revert.
        vm.expectRevert("BorrowerOperations: EBTC Only");
        borrowerOperations.flashFee(randomToken, amount);

        // If the token is not supported flashLoan MUST revert.
        vm.expectRevert("BorrowerOperations: EBTC Only");
        borrowerOperations.flashLoan(
            specReceiver,
            randomToken,
            amount,
            abi.encodePacked(uint256(0))
        );

        if (fee > 0) {
            deal(address(eBTCToken), address(specReceiver), fee);
        }

        // Set amount already there to ensure delta is amount received
        specReceiver.setBalanceAlready(address(eBTCToken));

        // Perform flashloan
        bool returnValue = borrowerOperations.flashLoan(
            specReceiver,
            address(eBTCToken),
            amount,
            abi.encodePacked(uint256(0))
        );

        // Was called
        assertTrue(specReceiver.called());

        // Amount received was exactly amount
        assertEq(specReceiver.balanceReceived(), amount);

        // We are the initator
        assertEq(specReceiver.caller(), address(this));

        // Data was not manipulated
        assertEq(specReceiver.receivedToken(), address(eBTCToken));
        assertEq(specReceiver.receivedAmount(), amount);
        assertEq(specReceiver.receivedData(), abi.encodePacked(uint256(0)));

        // Fee was not manipulated
        assertEq(specReceiver.receivedFee(), fee);

        // The lender MUST verify that the onFlashLoan callback returns the keccak256 hash of “ERC3156FlashBorrower.onFlashLoan”.
        // See `testEBTCSpecReturnValue`

        // After the callback, the flashLoan function MUST take the amount + fee token from the receiver, or revert if this is not successful.
        // Already tested by not granting allowance or not paying fee (See `test_eBTCRevertsIfUnpaid`)

        // If successful, flashLoan MUST return true.
        assertTrue(returnValue);
    }

    function testEBTCSpecReturnValue() public {
        vm.expectRevert("BorrowerOperations: IERC3156: Callback failed");
        borrowerOperations.flashLoan(
            wrongReturnReceiver,
            address(eBTCToken),
            123,
            abi.encodePacked(uint256(0))
        );
    }
}
