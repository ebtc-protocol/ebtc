// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.11;

import "forge-std/Test.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";
import {Utilities} from "./utils/Utilities.sol";
import {UselessFlashReceiver, eBTCFlashReceiver, WETHFlashReceiver} from "./utils/Flashloans.sol";

// TODO: Basic

/*
 * Unit Tests for Flashloans
 */
contract FlashLoanUnit is eBTCBaseFixture {
    uint private constant FEE = 5e17;
    uint256 internal constant COLLATERAL_RATIO = 160e16;  // 160%: take higher CR as CCR is 150%
    // TODO: Modify these constants to increase/decrease amount of users
    uint internal constant AMOUNT_OF_USERS = 100;

    mapping(bytes32 => bool) private _cdpIdsExist;

    Utilities internal _utils;

    // Flashloans
    UselessFlashReceiver internal uselessReceiver;
    eBTCFlashReceiver internal ebtcReceiver;
    WETHFlashReceiver internal wethReceiver;

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
      wethReceiver = new WETHFlashReceiver(); 
    }

    function dealEBTC(address recipient, uint256 amount) public {
      address payable[] memory users;
      users = _utils.createUsers(1);
      address user = users[0];
      // Deal max - 1 - current bal so they have max - 1
      vm.deal(user, type(uint256).max - 1 - user.balance);
      uint toDepositAmount = _utils.calculateCollateralAmount(amount, priceFeedMock.fetchPrice(), COLLATERAL_RATIO);
      vm.prank(user);
      borrowerOperations.openCdp{value : toDepositAmount + 1}(FEE, amount, "hint", "hint"); 
      vm.prank(user);
      eBTCToken.transfer(recipient, amount);
    }

    // Basic happy path test
    // We cap to uint128 avoid multiplication overflow
    // TODO: Add a max / max - 1 test to show what happens
    function test_basicLoanEBTC(uint128 loanAmount) public {
      require(address(ebtcReceiver) != address(0));

      uint256 fee = borrowerOperations.flashFee(address(eBTCToken), loanAmount);

      // Funny enough 0 reverts because of deal not
      vm.assume(loanAmount > 0);


      // No cheecky overflow
      vm.assume(loanAmount + fee <= type(uint256).max);

      // Cannot deal if not enough
      vm.assume(fee > 1800e18);

      if(fee > 0){
        deal(address(eBTCToken), address(ebtcReceiver), fee);
      }


      // Perform flashloan
      borrowerOperations.flashLoan(
        ebtcReceiver,
        address(eBTCToken),
        loanAmount,
        abi.encodePacked(uint256(0))
      );

      // Check fees were sent
    }

    // Explicit Zero amount test
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

    // TODO:
    function test_overflowCaseEBTC() public {
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
      // TODO: Check spec
    }


    // Do nothing (no fee), check that it reverts
    function test_eBTCRevertsIfUnpaid(uint256 loanAmount) public {
      vm.assume(loanAmount > 0);
      uint256 fee = borrowerOperations.flashFee(address(eBTCToken), loanAmount);
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

    // TODO: Read flashLoan Spec
    /**
      I think we need to:
        - Revert if too much
        - Revert if unpaid
        - Revert if target is not contract (Or just revert anyway so no prob)
     */
    function test_eBTCSpec() public {
      // Send the eBTC somewhere else, see it revert
    }

    // TODO: Add Weth (perhaps separate file or w/e)
}