// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.11;

import "forge-std/Test.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";
import {Utilities} from "./utils/Utilities.sol";
import {UselessFlashReceiver, eBTCFlashReceiver, FlashLoanSpecReceiver, FlashLoanWrongReturn} from "./utils/Flashloans.sol";
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

    constructor(IERC20 _want, IERC3156FlashLender _lender) public {
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

contract FlashLoanAttack is eBTCBaseFixture {
    uint private constant FEE = 5e17;
    uint256 internal constant COLLATERAL_RATIO = 160e16; // 160%: take higher CR as CCR is 150%

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
        uint borrowedAmount = _utils.calculateBorrowAmount(
            30 ether,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );
        // Make sure there is no CDPs in the system yet
        assert(sortedCdps.getLast() == "");
        vm.prank(user);
        borrowerOperations.openCdp{value: 30 ether}(FEE, borrowedAmount, "hint", "hint");
    }

    function testEBTCAttack(uint128 amount) public {
        uint256 fee = borrowerOperations.flashFee(address(eBTCToken), amount);

        vm.assume(fee > 0);

        FlashAttack attacker = new FlashAttack(
            IERC20(eBTCToken),
            IERC3156FlashLender(address(borrowerOperations))
        );

        // Deal only fee for one, will revert
        deal(address(eBTCToken), address(attacker), fee);

        vm.expectRevert(bytes("ERC20: burn amount exceeds balance"));
        borrowerOperations.flashLoan(
            IERC3156FlashBorrower(address(attacker)),
            address(eBTCToken),
            amount,
            abi.encodePacked(uint256(0))
        );

        // Deal more
        deal(address(eBTCToken), address(attacker), fee * 2);

        uint256 feeRecipientPreviousBalance = eBTCToken.balanceOf(
            borrowerOperations.FEE_RECIPIENT()
        );
        uint256 attackerPreviousBalance = eBTCToken.balanceOf(address(attacker));
        uint256 ebtcSupplyBefore = eBTCToken.totalSupply();

        // It will go through, no issues
        borrowerOperations.flashLoan(
            IERC3156FlashBorrower(address(attacker)),
            address(eBTCToken),
            amount,
            abi.encodePacked(uint256(0))
        );

        assertEq(
            eBTCToken.balanceOf(borrowerOperations.FEE_RECIPIENT()),
            feeRecipientPreviousBalance + fee * 2
        );
        assertEq(eBTCToken.balanceOf(address(attacker)), attackerPreviousBalance - fee * 2);
        assertEq(eBTCToken.totalSupply(), ebtcSupplyBefore);
    }

    function testWethAttack(uint128 amount) public {
        uint256 fee = activePool.flashFee(address(WETH), amount);

        vm.assume(fee > 0);

        FlashAttack attacker = new FlashAttack(
            IERC20(address(WETH)),
            IERC3156FlashLender(address(activePool))
        );

        // Deal only fee for one, will revert
        vm.deal(address(activePool), amount);
        deal(address(WETH), address(attacker), fee);

        vm.expectRevert("ActivePool: Too much");
        activePool.flashLoan(
            IERC3156FlashBorrower(address(attacker)),
            address(WETH),
            amount,
            abi.encodePacked(uint256(0))
        );

        vm.deal(address(activePool), amount * 2);
        deal(address(WETH), address(attacker), fee * 2);

        // Check is to ensure that we didn't donate too much
        vm.assume(address(activePool).balance - amount < activePool.getETH());
        vm.expectRevert("ActivePool: Must repay Balance");
        activePool.flashLoan(
            IERC3156FlashBorrower(address(attacker)),
            address(WETH),
            amount,
            abi.encodePacked(uint256(0))
        );
    }
}
