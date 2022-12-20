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

    function basicLoanEBTC(uint256 loanAmount) public {
      // TODO: Separate test for 0 amount
      vm.assume(loanAmount > 0);

      // Perform flashloan
      borrowerOperations.flashLoan(
        ebtcReceiver,
        address(eBTCToken),
        loanAmount,
        abi.encodePacked(uint256(0))
      );

      // Check fees were sent
    }

    function zeroCaseEBTC() public {
      // Zero test case
      uint256 loanAmount = 0;

      // Perform flashloan
      borrowerOperations.flashLoan(
        ebtcReceiver,
        address(eBTCToken),
        loanAmount,
        abi.encodePacked(uint256(0))
      );
    }

    function eBTCRevertsIfUnpaid() public {
      // Send the eBTC somewhere else, see it revert
    }

    // TODO: Read flashLoan Spec
    /**
      I think we need to:
        - Revert if too much
        - Revert if unpaid
        - Revert if target is not contract (Or just revert anyway so no prob)
     */
    function eBTCSpec() public {
      // Send the eBTC somewhere else, see it revert
    }

    // TODO: Add Weth (perhaps separate file or w/e)
}