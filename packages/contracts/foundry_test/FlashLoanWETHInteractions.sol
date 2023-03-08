// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "forge-std/Test.sol";
import {eBTCBaseFixture, BorrowerOperations} from "./BaseFixture.sol";
import {Utilities} from "./utils/Utilities.sol";
import {UselessFlashReceiver, eBTCFlashReceiver, FlashLoanSpecReceiver, FlashLoanWrongReturn} from "./utils/Flashloans.sol";
import "../contracts/Dependencies/IERC20.sol";
import "../contracts/Interfaces/IERC3156FlashLender.sol";
import "../contracts/Interfaces/IWETH.sol";

/*
 * Runs Flashloans and deposits ETH into CDPManager
 */
contract FlashWithDeposit {
    IERC20 public immutable want;
    IERC3156FlashLender public immutable lender;
    BorrowerOperations public borrowerOperations;
    address public collToken;

    uint internal constant MIN_NET_DEBT = 2e18; // Subject to changes once CL is changed
    uint private constant FEE = 5e17;

    constructor(
        IERC20 _want,
        IERC3156FlashLender _lender,
        BorrowerOperations _borrowerOperations,
        address collTokenAddress
    ) public {
        want = _want;
        lender = _lender;
        borrowerOperations = _borrowerOperations;
        collToken = collTokenAddress;

        // Approve to repay
        IERC20(_want).approve(address(_lender), type(uint256).max);
        IERC20(collToken).approve(address(borrowerOperations), type(uint256).max);
    }

    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external returns (bytes32) {
        require(token == address(want));

        uint256 amount = abi.decode(data, (uint256));

        // Run an operation with BorrowerOperations
        // W/e we got send as value
        IWETH(collToken).deposit{value: amount}();
        borrowerOperations.openCdp(FEE, MIN_NET_DEBT, "hint", "hint", amount);

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    receive() external payable {}
}

contract FlashLoanWETHInteractions is eBTCBaseFixture {
    Utilities internal _utils;

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
        vm.startPrank(user);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 30 ether}();
        borrowerOperations.openCdp(FEE, borrowedAmount, "hint", "hint", 30 ether);
        vm.stopPrank();
    }

    function testCanUseCDPWithFL(uint128 amount, uint128 amountToDepositInCDP) public {
        uint256 fee = activePool.flashFee(address(collateral), amount);

        vm.assume(fee > 0);

        // TODO: Could change to w/e but this should be fine
        // Peer review and change accordingly
        vm.assume(amountToDepositInCDP > 100 ether);

        // Avoid over borrowing
        vm.assume(amount < amountToDepositInCDP);

        FlashWithDeposit macroContract = new FlashWithDeposit(
            IERC20(address(collateral)),
            IERC3156FlashLender(address(activePool)),
            borrowerOperations,
            address(collateral)
        );

        // SETUP Contract
        // Create a CDP by sending enough
        address payable[] memory users;
        users = _utils.createUsers(1);
        address user = users[0];
        uint borrowedAmount = _utils.calculateBorrowAmount(
            amountToDepositInCDP,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO_DEFENSIVE
        );
        vm.deal(address(user), amountToDepositInCDP);
        vm.startPrank(user);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: amountToDepositInCDP}();
        borrowerOperations.openCdp(FEE, borrowedAmount, "hint", "hint", amountToDepositInCDP);
        vm.stopPrank();

        dealCollateral(address(macroContract), fee);
        vm.deal(address(macroContract), amountToDepositInCDP);

        // Ensure Delta between ETH and balance is marginal
        activePool.flashLoan(
            IERC3156FlashBorrower(address(macroContract)),
            address(collateral),
            amount,
            abi.encodePacked(uint256(amountToDepositInCDP))
        );

        assertTrue(eBTCToken.balanceOf(address(macroContract)) > 0);
    }
}
