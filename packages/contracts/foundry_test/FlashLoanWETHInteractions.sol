// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {eBTCBaseFixture, BorrowerOperations} from "./BaseFixture.sol";
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

    uint256 internal constant MIN_NET_DEBT = 2e18; // Subject to changes once CL is changed
    uint256 private constant FEE = 5e17;

    constructor(
        IERC20 _want,
        IERC3156FlashLender _lender,
        BorrowerOperations _borrowerOperations,
        address collTokenAddress
    ) {
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
        borrowerOperations.openCdp(MIN_NET_DEBT, "hint", "hint", amount);

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    receive() external payable {}
}

contract FlashLoanWETHInteractions is eBTCBaseFixture {
    function setUp() public override {
        // Base setup
        eBTCBaseFixture.setUp();

        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();

        // Create a CDP
        address payable[] memory users;
        users = _utils.createUsers(1);
        address user = users[0];
        uint256 borrowedAmount = _utils.calculateBorrowAmount(
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
    }

    function testCanUseCDPWithFL(uint128 amount, uint128 amountToDepositInCDP) public {
        uint256 fee = activePool.flashFee(address(collateral), amount);

        vm.assume(fee > 0);

        // TODO: Could change to w/e but this should be fine
        // Peer review and change accordingly
        amountToDepositInCDP = uint128(bound(amountToDepositInCDP, 100 ether + 1, 100_000_000e18));
        // Avoid over borrowing
        amount = uint128(bound(amount, 1, amountToDepositInCDP - 1));

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
        uint256 borrowedAmount = _utils.calculateBorrowAmount(
            amountToDepositInCDP,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO_DEFENSIVE
        );
        vm.deal(address(user), amountToDepositInCDP);
        vm.startPrank(user);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: amountToDepositInCDP}();
        borrowerOperations.openCdp(borrowedAmount, "hint", "hint", amountToDepositInCDP);
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
