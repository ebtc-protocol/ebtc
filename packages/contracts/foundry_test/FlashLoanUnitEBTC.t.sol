// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.11;

import "forge-std/Test.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";
import {Utilities} from "./utils/Utilities.sol";
import {
  UselessFlashReceiver, 
  eBTCFlashReceiver,
  FlashLoanSpecReceiver, 
  FlashLoanWrongReturn
} from "./utils/Flashloans.sol";


/*
 * Unit Tests for Flashloans
 * Basic Considerations:
 * Flash Fee can go to zero due to rounding, that's marginal
 * Minting is capped at u112 for UniV2 Compatibility, but mostly arbitrary
 */
contract FlashLoanUnitEBTC is eBTCBaseFixture {
    uint private constant FEE = 5e17;
    uint256 internal constant COLLATERAL_RATIO = 160e16;  // 160%: take higher CR as CCR is 150%
    uint internal constant AMOUNT_OF_USERS = 100;

    mapping(bytes32 => bool) private _cdpIdsExist;

    Utilities internal _utils;

    // Flashloans
    UselessFlashReceiver internal uselessReceiver;
    eBTCFlashReceiver internal ebtcReceiver;
    FlashLoanSpecReceiver internal specReceiver;
    FlashLoanWrongReturn internal wrongReturnReceiver;

    function setUp() public override {

      // Base setup
      eBTCBaseFixture.setUp();
      eBTCBaseFixture.connectLQTYContracts();
      eBTCBaseFixture.connectCoreContracts();
      eBTCBaseFixture.connectLQTYContractsToCore();
      _utils = new Utilities();

      // Create a CDP
      address payable[] memory users;
      users = _utils.createUsers(1);
      address user = users[0];
      uint borrowedAmount = _utils.calculateBorrowAmount(30 ether, priceFeedMock.fetchPrice(), COLLATERAL_RATIO);
      // Make sure there is no CDPs in the system yet
      assert(sortedCdps.getLast() == "");
      vm.prank(user);
      borrowerOperations.openCdp{value : 30 ether}(FEE, borrowedAmount, "hint", "hint");

      uselessReceiver = new UselessFlashReceiver();
      ebtcReceiver = new eBTCFlashReceiver();
      specReceiver = new FlashLoanSpecReceiver(); 
      wrongReturnReceiver = new FlashLoanWrongReturn(); 
    }

    /// @dev Basic happy path test
    /// @notice We cap to uint128 avoid multiplication overflow
    function test_basicLoanEBTC(uint128 loanAmount) public {
      require(address(ebtcReceiver) != address(0));

      uint256 fee = borrowerOperations.flashFee(address(eBTCToken), loanAmount);

      // Funny enough 0 reverts because of deal not
      vm.assume(loanAmount > 0);


      // No cheecky overflow
      vm.assume(loanAmount + fee <= type(uint256).max);

      // Cannot deal if not enough
      vm.assume(fee > 1800e18);

      deal(address(eBTCToken), address(ebtcReceiver), fee);


      // Perform flashloan
      borrowerOperations.flashLoan(
        ebtcReceiver,
        address(eBTCToken),
        loanAmount,
        abi.encodePacked(uint256(0))
      );

      // Check fees were sent
    }

    /// @dev Can take a 0 flashloan, nothing happens
    function test_zeroCaseEBTC() public {
      // Zero test case
      uint256 loanAmount = 0;

      // Perform flashloan
      borrowerOperations.flashLoan(
        ebtcReceiver,
        address(eBTCToken),
        loanAmount,
        abi.encodePacked(uint256(0))
      );

      // Doesn't revert as we have to pay nothing back
    }

    /// @dev Amount too high, we overflow when computing fees
    function test_overflowCaseEBTC() public {
      // Zero Overflow Case
      uint256 loanAmount = type(uint256).max;

      vm.expectRevert();
      borrowerOperations.flashLoan(
        ebtcReceiver,
        address(eBTCToken),
        loanAmount,
        abi.encodePacked(uint256(0))
      );
    }


    /// @dev Do nothing (no fee), check that it reverts
    function test_eBTCRevertsIfUnpaid(uint256 loanAmount) public {
      uint256 fee = borrowerOperations.flashFee(address(eBTCToken), loanAmount);
      // Ensure fee is not rounded down
      vm.assume(fee > 1);

      vm.expectRevert();
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
    function test_eBTCSpec(uint128 amount, address randomToken) public {
        vm.assume(randomToken != address(eBTCToken));

        // The maxFlashLoan function MUST return the maximum loan possible for token.
        assertEq(borrowerOperations.maxFlashLoan(address(eBTCToken)), type(uint112).max);

        // If a token is not currently supported maxFlashLoan MUST return 0, instead of reverting.
        assertEq(borrowerOperations.maxFlashLoan(randomToken), 0);

        uint256 fee = borrowerOperations.flashFee(address(eBTCToken), amount);

        // The flashFee function MUST return the fee charged for a loan of amount token.
        assertTrue(fee >= 0);

        // If the token is not supported flashFee MUST revert.
        vm.expectRevert();
        borrowerOperations.flashFee(randomToken, amount);

        // If the token is not supported flashLoan MUST revert.
        vm.expectRevert();
        borrowerOperations.flashLoan(
          specReceiver,
          randomToken,
          amount,
          abi.encodePacked(uint256(0))
        );


        if (fee > 0){
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
        // See `test_eBTCSpec_returnValue`


        // After the callback, the flashLoan function MUST take the amount + fee token from the receiver, or revert if this is not successful.
        // Already tested by not granting allowance or not paying fee (See `test_eBTCRevertsIfUnpaid`)

        // If successful, flashLoan MUST return true.
        assertTrue(returnValue);
    }

    function test_eBTCSpec_returnValue() public {
      vm.expectRevert("IERC3156: Callback failed");
      borrowerOperations.flashLoan(
          wrongReturnReceiver,
          address(eBTCToken),
          123,
          abi.encodePacked(uint256(0))
        );
      }
  }
