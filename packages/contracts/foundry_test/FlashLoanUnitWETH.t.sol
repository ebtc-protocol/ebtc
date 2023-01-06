// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.11;

import "forge-std/Test.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";
import {Utilities} from "./utils/Utilities.sol";
import {
  UselessFlashReceiver, 
  WETHFlashReceiver, 
  FlashLoanSpecReceiver, 
  FlashLoanWrongReturn
} from "./utils/Flashloans.sol";


/*
 * Unit Tests for Flashloans
 * Basic Considerations:
 * Flash Fee can go to zero due to rounding, that's marginal
 * Minting is capped at u112 for UniV2 Compatibility, but mostly arbitrary
 */
contract FlashLoanUnit is eBTCBaseFixture {
    uint private constant FEE = 5e17;


    Utilities internal _utils;

    // Flashloans
    UselessFlashReceiver internal uselessReceiver;
    WETHFlashReceiver internal wethReceiver;
    FlashLoanSpecReceiver internal specReceiver;
    FlashLoanWrongReturn internal wrongReturnReceiver;

    // TODO: Finish
    // Aso: Fix rest of fixtures to be using WETH only
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

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
    function testBasicLoanWETH(uint128 loanAmount) public {
      require(address(wethReceiver) != address(0));

      uint256 fee = activePool.flashFee(address(WETH), loanAmount);

      // Funny enough 0 reverts because of deal not
      vm.assume(loanAmount > 0);


      // No cheecky overflow
      vm.assume(loanAmount + fee <= type(uint256).max);

      // Cannot deal if not enough
      vm.assume(fee > 1800e18);

      deal(address(WETH), address(wethReceiver), fee);

      // Give a bunch of ETH to the pool so we can loan it
      deal(address(activePool), loanAmount);


      // Perform flashloan
      activePool.flashLoan(
        wethReceiver,
        address(WETH),
        loanAmount,
        abi.encodePacked(uint256(0))
      );

      // Check fees were sent
    }

    /// @dev Can take a 0 flashloan, nothing happens
    function testZeroCaseWETH() public {
      // Zero test case
      uint256 loanAmount = 0;

      vm.expectRevert("0 Amount");
      // Perform flashloan
      activePool.flashLoan(
        wethReceiver,
        address(WETH),
        loanAmount,
        abi.encodePacked(uint256(0))
      );
    }

    /// @dev Amount too high, we overflow when computing fees
    function testOverflowCaseWETH() public {
      // Zero Overflow Case
      uint256 loanAmount = type(uint256).max;

      vm.expectRevert();
      activePool.flashLoan(
        wethReceiver,
        address(WETH),
        loanAmount,
        abi.encodePacked(uint256(0))
      );

      // Doesn't revert as we have to pay nothing back
    }


    // Do nothing (no fee), check that it reverts
    function testEBTCRevertsIfUnpaid(uint256 loanAmount) public {
      uint256 fee = activePool.flashFee(address(WETH), loanAmount);
      // Ensure fee is not rounded down
      vm.assume(fee > 1);

      vm.expectRevert();
      // Perform flashloan
      activePool.flashLoan(
        uselessReceiver,
        address(WETH),
        loanAmount,
        abi.encodePacked(uint256(0))
      );
    }

    /**
      Based on the spec: https://eips.ethereum.org/EIPS/eip-3156
        If successful, flashLoan MUST return true.
     */
    function testWETHSpec(uint128 amount, address randomToken) public {
        vm.assume(randomToken != address(WETH));
        vm.assume(amount > 0);

        // NOTE: Send funds for flashloan to be doable
        vm.deal(address(activePool), amount);

        // The maxFlashLoan function MUST return the maximum loan possible for token.
        // In this case the balance of the pool
        assertEq(activePool.maxFlashLoan(address(WETH)), address(activePool).balance);

        // If a token is not currently supported maxFlashLoan MUST return 0, instead of reverting.
        assertEq(activePool.maxFlashLoan(randomToken), 0);

        uint256 fee = activePool.flashFee(address(WETH), amount);

        // The flashFee function MUST return the fee charged for a loan of amount token.
        assertTrue(fee >= 0);

        // If the token is not supported flashFee MUST revert.
        vm.expectRevert();
        activePool.flashFee(randomToken, amount);

        // If the token is not supported flashLoan MUST revert.
        vm.expectRevert();
        activePool.flashLoan(
          specReceiver,
          randomToken,
          amount,
          abi.encodePacked(uint256(0))
        );


        if (fee > 0){
          deal(address(WETH), address(specReceiver), fee);
        }

        // Set amount already there to ensure delta is amount received
        specReceiver.setBalanceAlready(address(WETH));

        // Perform flashloan
        bool returnValue = activePool.flashLoan(
          specReceiver,
          address(WETH),
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
        assertEq(specReceiver.receivedToken(), address(WETH));
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

      vm.expectRevert("IERC3156: Callback failed");
      activePool.flashLoan(
          wrongReturnReceiver,
          WETH,
          123,
          abi.encodePacked(uint256(0))
        );
      }
  }
