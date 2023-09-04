// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";
import {UselessFlashReceiver, STETHFlashReceiver, FlashLoanSpecReceiver, FlashLoanWrongReturn} from "./utils/Flashloans.sol";

/*
 * Unit Tests for Flashloans
 * Basic Considerations:
 * Flash Fee can go to zero due to rounding, that's marginal
 */
contract FlashLoanUnitSTETH is eBTCBaseFixture {
    // Flashloans
    UselessFlashReceiver internal uselessReceiver;
    STETHFlashReceiver internal stethReceiver;
    FlashLoanSpecReceiver internal specReceiver;
    FlashLoanWrongReturn internal wrongReturnReceiver;

    function setUp() public override {
        // Base setup
        eBTCBaseFixture.setUp();

        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();

        uselessReceiver = new UselessFlashReceiver();
        stethReceiver = new STETHFlashReceiver();
        specReceiver = new FlashLoanSpecReceiver();
        wrongReturnReceiver = new FlashLoanWrongReturn();
    }

    /// @dev Basic happy path test
    /// @notice We cap to uint128 avoid multiplication overflow
    ///   TODO: Add a max / max - 1 test to show what happens
    function testBasicLoanSTETH(uint128 loanAmount, uint128 giftAmount) public {
        require(address(stethReceiver) != address(0));

        uint256 fee = activePool.flashFee(address(collateral), loanAmount);

        // Funny enough 0 reverts because of deal not
        vm.assume(loanAmount > 0);

        // No cheecky overflow
        vm.assume(loanAmount + fee <= type(uint256).max);

        // Cannot deal if not enough
        vm.assume(fee > 1800e18);

        dealCollateral(address(stethReceiver), fee);

        // Give a bunch of ETH to the pool so we can loan it and randomly gift some to activePool
        uint256 _suggar = giftAmount > loanAmount ? giftAmount : loanAmount;
        dealCollateral(address(activePool), _suggar);
        vm.assume(giftAmount > 0);

        uint256 prevFeeBalance = collateral.balanceOf(activePool.feeRecipientAddress());
        // Perform flashloan
        activePool.flashLoan(
            stethReceiver,
            address(collateral),
            loanAmount,
            abi.encodePacked(uint256(0))
        );

        assertEq(collateral.balanceOf(address(activePool)), _suggar);

        // Check fees were sent and balance increased exactly by the expected fee amount
        assertEq(collateral.balanceOf(activePool.feeRecipientAddress()), prevFeeBalance + fee);
    }

    /// @dev Can take a 0 flashloan, nothing happens
    function testZeroCaseSTETH() public {
        // Zero test case
        uint256 loanAmount = 0;

        vm.expectRevert("ActivePool: 0 Amount");
        // Perform flashloan
        activePool.flashLoan(
            stethReceiver,
            address(collateral),
            loanAmount,
            abi.encodePacked(uint256(0))
        );
    }

    /// @dev Cannot send ETH to ActivePool
    function testCannottransferSystemCollShares(uint256 amount) public {
        vm.deal(address(this), amount);
        vm.assume(amount > 0);

        vm.expectRevert("ActivePool: Caller is not BorrowerOperations");
        payable(address(activePool)).call{value: amount}("");
    }

    /// @dev Amount too high, we overflow when computing fees
    function testOverflowCaseSTETH() public {
        // Zero Overflow Case
        uint256 loanAmount = type(uint256).max / 1e18;

        dealCollateral(address(activePool), loanAmount);

        try
            activePool.flashLoan(
                stethReceiver,
                address(collateral),
                loanAmount,
                abi.encodePacked(uint256(0))
            )
        {} catch Panic(uint256 _errorCode) {
            assertEq(_errorCode, 17); //0x11: If an arithmetic operation results in underflow or overflow outside of an unchecked block.
        }
    }

    // Do nothing (no fee), check that it reverts
    function testSTETHRevertsIfUnpaid(uint128 loanAmount) public {
        uint256 fee = activePool.flashFee(address(collateral), loanAmount);
        // Ensure fee is not rounded down
        vm.assume(fee > 1);

        vm.deal(address(activePool), loanAmount);

        // NOTE: STETH has no error message
        // Source: https://etherscan.io/token/0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2#code#L68
        vm.expectRevert();
        // Perform flashloan
        activePool.flashLoan(
            uselessReceiver,
            address(collateral),
            loanAmount,
            abi.encodePacked(uint256(0))
        );
    }

    /**
      Based on the spec: https://eips.ethereum.org/EIPS/eip-3156
        If successful, flashLoan MUST return true.
     */
    function testWETHSpec(uint128 amount, address randomToken, uint256 flashFee) public {
        vm.assume(randomToken != address(collateral));
        vm.assume(amount > 0);
        vm.assume(flashFee <= activePool.MAX_FEE_BPS());

        vm.prank(defaultGovernance);
        activePool.setFeeBps(flashFee);

        // NOTE: Send funds for flashloan to be doable
        dealCollateral(address(activePool), amount);

        // The maxFlashLoan function MUST return the maximum loan possible for token.
        // In this case the balance of the pool
        assertEq(
            activePool.maxFlashLoan(address(collateral)),
            collateral.balanceOf(address(activePool))
        );

        // If a token is not currently supported maxFlashLoan MUST return 0, instead of reverting.
        assertEq(activePool.maxFlashLoan(randomToken), 0);

        uint256 fee = activePool.flashFee(address(collateral), amount);

        // The feeBps function MUST return the fee charged for a loan of amount token.
        assertTrue(fee >= 0);
        assertEq(
            uint256(fee),
            (uint256(amount) * uint256(activePool.feeBps())) / uint256(activePool.MAX_BPS())
        );

        // If the token is not supported feeBps MUST revert.
        vm.expectRevert("ActivePool: collateral Only");
        activePool.flashFee(randomToken, amount);

        // If the token is not supported flashLoan MUST revert.
        vm.expectRevert("ActivePool: collateral Only");
        activePool.flashLoan(specReceiver, randomToken, amount, abi.encodePacked(uint256(0)));

        // Pause FL
        vm.startPrank(defaultGovernance);
        activePool.setFlashLoansPaused(true);
        vm.stopPrank();

        // If the FL is paused, flashFee Reverts
        vm.expectRevert("ActivePool: Flash Loans Paused");
        activePool.flashFee(address(collateral), amount);

        // If the FL is paused, maxFlashLoan returns 0
        assertEq(activePool.maxFlashLoan(address(collateral)), 0);

        // if the FL is paused, flashLoan Reverts
        vm.expectRevert("ActivePool: Flash Loans Paused");
        activePool.flashLoan(
            specReceiver,
            address(collateral),
            amount,
            abi.encodePacked(uint256(0))
        );

        // Unpause
        vm.startPrank(defaultGovernance);
        activePool.setFlashLoansPaused(false);
        vm.stopPrank();

        if (fee > 0) {
            dealCollateral(address(specReceiver), fee);
        }

        // Set amount already there to ensure delta is amount received
        specReceiver.setBalanceAlready(address(collateral));

        // Perform flashloan
        bool returnValue = activePool.flashLoan(
            specReceiver,
            address(collateral),
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
        assertEq(specReceiver.receivedToken(), address(collateral));
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

    function testSTETHReturnValue() public {
        // NOTE: Send funds for spec
        dealCollateral(address(activePool), 123);

        vm.expectRevert("ActivePool: IERC3156: Callback failed");
        activePool.flashLoan(
            wrongReturnReceiver,
            address(collateral),
            123,
            abi.encodePacked(uint256(0))
        );
    }
}
