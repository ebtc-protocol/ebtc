// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "forge-std/Test.sol";
import {eBTCBaseFixture, BorrowerOperations} from "./BaseFixture.sol";
import {Utilities} from "./utils/Utilities.sol";
import {UselessFlashReceiver, eBTCFlashReceiver, FlashLoanSpecReceiver, FlashLoanWrongReturn} from "./utils/Flashloans.sol";
import "../../contracts/Dependencies/IERC20.sol";
import "../../contracts/Interfaces/IERC3156FlashLender.sol";
import "../../contracts/Interfaces/IWETH.sol";

/*
 * Runs Flashloans and deposits ETH into CDPManager
 */
contract FlashWithDeposit {
    IERC20 public immutable want;
    IERC3156FlashLender public immutable lender;
    BorrowerOperations public borrowerOperations;

    uint internal constant MIN_NET_DEBT = 1800e18; // Subject to changes once CL is changed
    uint private constant FEE = 5e17;

    constructor(
        IERC20 _want,
        IERC3156FlashLender _lender,
        BorrowerOperations _borrowerOperations
    ) public {
        want = _want;
        lender = _lender;
        borrowerOperations = _borrowerOperations;

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

        uint256 amount = abi.decode(data, (uint256));

        // Run an operation with BorrowerOperations
        // W/e we got send as value
        borrowerOperations.openCdp{value: amount}(FEE, MIN_NET_DEBT, "hint", "hint");

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    receive() external payable {}
}

contract FlashLoanWETHInteractions is eBTCBaseFixture {
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

    // TODO: More after Auditors consultation
    function testCanUseCDPWithFL(uint128 amount, uint128 amountToDepositInCDP) public {
        uint256 fee = activePool.flashFee(address(WETH), amount);

        vm.assume(fee > 0);

        // TODO: Could change to w/e but this should be fine
        // Peer review and change accordingly
        vm.assume(amountToDepositInCDP > 30 ether);

        // Avoid over borrowing
        vm.assume(amount < amountToDepositInCDP);

        FlashWithDeposit macroContract = new FlashWithDeposit(
            IERC20(address(WETH)),
            IERC3156FlashLender(address(activePool)),
            borrowerOperations
        );

        // SETUP Contract
        // Create a CDP by sending enough
        address payable[] memory users;
        users = _utils.createUsers(1);
        address user = users[0];
        uint borrowedAmount = _utils.calculateBorrowAmount(
            30 ether,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );
        vm.prank(user);
        vm.deal(address(user), amountToDepositInCDP);
        borrowerOperations.openCdp{value: amountToDepositInCDP}(FEE, borrowedAmount, "hint", "hint");

        deal(address(WETH), address(macroContract), fee);
        vm.deal(address(macroContract), amountToDepositInCDP);

        // Ensure Delta between ETH and balance is marginal
        activePool.flashLoan(
            IERC3156FlashBorrower(address(macroContract)),
            address(WETH),
            amount,
            abi.encodePacked(uint256(amountToDepositInCDP))
        );

        assertTrue(eBTCToken.balanceOf(address(macroContract)) > 0);
    }
}
