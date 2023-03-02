// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "forge-std/Test.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";
import {Utilities} from "./utils/Utilities.sol";
import {UselessFlashReceiver, WETHFlashReceiver, FlashLoanSpecReceiver, FlashLoanWrongReturn} from "./utils/Flashloans.sol";

/*
 * Unit Tests for Flashloans
 * Basic Considerations:
 * Flash Fee can go to zero due to rounding, that's marginal
 * Minting is capped at u112 for UniV2 Compatibility, but mostly arbitrary
 */
contract FlashLoanUnitWETH is eBTCBaseFixture {
    Utilities internal _utils;

    // Flashloans
    UselessFlashReceiver internal uselessReceiver;
    WETHFlashReceiver internal wethReceiver;
    FlashLoanSpecReceiver internal specReceiver;
    FlashLoanWrongReturn internal wrongReturnReceiver;

    function setUp() public override {
        // Base setup
        eBTCBaseFixture.setUp();
        eBTCBaseFixture.connectLQTYContracts();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();

        uselessReceiver = new UselessFlashReceiver();
        wethReceiver = new WETHFlashReceiver();
        specReceiver = new FlashLoanSpecReceiver();
        wrongReturnReceiver = new FlashLoanWrongReturn();
    }

    /// @dev Basic happy path test
    /// @notice We cap to uint128 avoid multiplication overflow
    ///   TODO: Add a max / max - 1 test to show what happens
    function testBasicLoanWETH(uint128 loanAmount, uint128 giftAmount) public {
        require(address(wethReceiver) != address(0));

        uint256 fee = activePool.flashFee(address(weth), loanAmount);

        // Funny enough 0 reverts because of deal not
        vm.assume(loanAmount > 0);

        // No cheecky overflow
        vm.assume(loanAmount + fee <= type(uint256).max);

        // Cannot deal if not enough
        vm.assume(fee > 1800e18);

        deal(address(weth), address(wethReceiver), fee);

        // Give a bunch of ETH to the pool so we can loan it
        deal(address(activePool), loanAmount);

        // Amount we randomly send to activePool
        deal(address(weth), address(activePool), giftAmount);
        vm.assume(giftAmount > 0);

        uint256 prevFeeBalance = weth.balanceOf(activePool.FEE_RECIPIENT());
        // Perform flashloan
        activePool.flashLoan(wethReceiver, address(weth), loanAmount, abi.encodePacked(uint256(0)));

        assertEq(weth.balanceOf(address(activePool)), giftAmount);

        // Check fees were sent and balance increased exactly by the expected fee amount
        assertEq(weth.balanceOf(activePool.FEE_RECIPIENT()), prevFeeBalance + fee);
    }

    /// @dev Can take a 0 flashloan, nothing happens
    function testZeroCaseWETH() public {
        // Zero test case
        uint256 loanAmount = 0;

        vm.expectRevert("ActivePool: 0 Amount");
        // Perform flashloan
        activePool.flashLoan(wethReceiver, address(weth), loanAmount, abi.encodePacked(uint256(0)));
    }

    /// @dev Cannot send ETH to ActivePool
    function testCannotSendEth(uint256 amount) public {
        vm.deal(address(this), amount);
        vm.assume(amount > 0);

        vm.expectRevert("ActivePool: Caller is neither BO nor Default Pool");
        payable(address(activePool)).call{value: amount}("");
    }

    /// @dev Amount too high, we overflow when computing fees
    function testOverflowCaseWETH() public {
        // Zero Overflow Case
        uint256 loanAmount = type(uint256).max;

        vm.deal(address(activePool), loanAmount);

        vm.expectRevert("SafeMath: multiplication overflow");
        activePool.flashLoan(wethReceiver, address(weth), loanAmount, abi.encodePacked(uint256(0)));
    }

    // Do nothing (no fee), check that it reverts
    function testWETHRevertsIfUnpaid(uint128 loanAmount) public {
        uint256 fee = activePool.flashFee(address(weth), loanAmount);
        // Ensure fee is not rounded down
        vm.assume(fee > 1);

        vm.deal(address(activePool), loanAmount);

        // NOTE: WETH has no error message
        // Source: https://etherscan.io/token/0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2#code#L68
        vm.expectRevert();
        // Perform flashloan
        activePool.flashLoan(
            uselessReceiver,
            address(weth),
            loanAmount,
            abi.encodePacked(uint256(0))
        );
    }

    /**
      Based on the spec: https://eips.ethereum.org/EIPS/eip-3156
        If successful, flashLoan MUST return true.
     */
    function testWETHSpec(uint128 amount, address randomToken) public {
        vm.assume(randomToken != address(weth));
        vm.assume(amount > 0);

        // NOTE: Send funds for flashloan to be doable
        vm.deal(address(activePool), amount);

        // The maxFlashLoan function MUST return the maximum loan possible for token.
        // In this case the balance of the pool
        assertEq(activePool.maxFlashLoan(address(weth)), address(activePool).balance);

        // If a token is not currently supported maxFlashLoan MUST return 0, instead of reverting.
        assertEq(activePool.maxFlashLoan(randomToken), 0);

        uint256 fee = activePool.flashFee(address(weth), amount);

        // The flashFee function MUST return the fee charged for a loan of amount token.
        assertTrue(fee >= 0);
        assertEq(fee, (amount * activePool.FEE_AMT()) / activePool.MAX_BPS());

        // If the token is not supported flashFee MUST revert.
        vm.expectRevert("ActivePool: WETH Only");
        activePool.flashFee(randomToken, amount);

        // If the token is not supported flashLoan MUST revert.
        vm.expectRevert("ActivePool: WETH Only");
        activePool.flashLoan(specReceiver, randomToken, amount, abi.encodePacked(uint256(0)));

        if (fee > 0) {
            deal(address(weth), address(specReceiver), fee);
        }

        // Set amount already there to ensure delta is amount received
        specReceiver.setBalanceAlready(address(weth));

        // Perform flashloan
        bool returnValue = activePool.flashLoan(
            specReceiver,
            address(weth),
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
        assertEq(specReceiver.receivedToken(), address(weth));
        assertEq(specReceiver.receivedAmount(), amount);
        assertEq(specReceiver.receivedData(), abi.encodePacked(uint256(0)));

        // Fee was not manipulated
        assertEq(specReceiver.receivedFee(), fee);

        // The lender MUST verify that the onFlashLoan callback returns the keccak256 hash of “ERC3156FlashBorrower.onFlashLoan”.
        // See `testWethSpecReturnValue`

        // After the callback, the flashLoan function MUST take the amount + fee token from the receiver, or revert if this is not successful.
        // Already tested by not granting allowance or not paying fee (See `test_eBTCRevertsIfUnpaid`)

        // If successful, flashLoan MUST return true.
        assertTrue(returnValue);
    }

    function testWETHReturnValue() public {
        // NOTE: Send funds for spec
        vm.deal(address(activePool), 123);

        vm.expectRevert("ActivePool: IERC3156: Callback failed");
        activePool.flashLoan(wrongReturnReceiver, address(weth), 123, abi.encodePacked(uint256(0)));
    }
}
