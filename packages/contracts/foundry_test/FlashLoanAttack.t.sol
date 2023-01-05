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
import "../../contracts/Dependencies/IERC20.sol";
import "../../contracts/Interfaces/IERC3156FlashLender.sol";
import "../../contracts/Interfaces/IWETH.sol";


/*
 * FlashLoan ReEntrancy Attack
 */

contract FlashAttack {
  IERC20 public immutable want;
  IERC3156FlashLender public immutable lender;
  uint256 public counter;
  constructor (IERC20 _want, IERC3156FlashLender _lender) public {
    want = _want;
    lender = _lender;

    // Approve to repay
    IERC20(_want).approve(address(_lender), type(uint256).max);
  }

  function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
  ) external returns (bytes32) {
    require(token == address(want));
   

    if (counter == 0) {
      ++counter;

      // Perform a second loan
      lender.flashLoan(IERC3156FlashBorrower(address(this)), address(want), amount, data);
    }


    return keccak256("ERC3156FlashBorrower.onFlashLoan");
  }

}

contract FlashLoanUnitEBTC is eBTCBaseFixture {

    uint private constant FEE = 5e17;
    uint256 internal constant COLLATERAL_RATIO = 160e16;  // 160%: take higher CR as CCR is 150%
    uint internal constant AMOUNT_OF_USERS = 100;

    mapping(bytes32 => bool) private _cdpIdsExist;

    Utilities internal _utils;

    IWETH public constant WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);


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
    }

    function test_eBTCAttack(uint128 amount) public {
      uint256 fee = borrowerOperations.flashFee(address(eBTCToken), amount);

      vm.assume(fee > 0);

      FlashAttack attacker = new FlashAttack(IERC20(eBTCToken), IERC3156FlashLender(address(borrowerOperations)));
      
      
      // Deal only fee for one, will revert
      deal(address(eBTCToken), address(attacker), fee);

      vm.expectRevert();
      borrowerOperations.flashLoan(
        IERC3156FlashBorrower(address(attacker)),
        address(eBTCToken),
        amount,
        abi.encodePacked(uint256(0))
      );

      // Deal more
      deal(address(eBTCToken), address(attacker), fee * 2);

      // It will go through, no issues
      borrowerOperations.flashLoan(
        IERC3156FlashBorrower(address(attacker)),
        address(eBTCToken),
        amount,
        abi.encodePacked(uint256(0))
      );
    }

    function test_WethAttack(uint128 amount) public {
      uint256 fee = activePool.flashFee(address(WETH), amount);

      vm.assume(fee > 0);

      FlashAttack attacker = new FlashAttack(IERC20(address(WETH)), IERC3156FlashLender(address(activePool)));
      
      
      // Deal only fee for one, will revert
      vm.deal(address(activePool), amount);
      vm.deal(address(attacker), fee);

      vm.expectRevert();
      activePool.flashLoan(
        IERC3156FlashBorrower(address(attacker)),
        address(WETH),
        amount,
        abi.encodePacked(uint256(0))
      );

      // Deal only fee for one, will revert
      vm.deal(address(activePool), amount * 2);
      vm.deal(address(attacker), fee * 2);

      vm.expectRevert();
      activePool.flashLoan(
        IERC3156FlashBorrower(address(attacker)),
        address(WETH),
        amount,
        abi.encodePacked(uint256(0))
      );
    }

}