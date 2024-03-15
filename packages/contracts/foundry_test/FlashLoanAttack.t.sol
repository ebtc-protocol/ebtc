// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";
import {UselessFlashReceiver, eBTCFlashReceiver, FlashLoanSpecReceiver, FlashLoanWrongReturn} from "./utils/Flashloans.sol";
import "../contracts/Dependencies/IERC20.sol";
import "../contracts/Interfaces/IERC3156FlashLender.sol";

/*
 * FlashLoan ReEntrancy Attack
 */

interface IActivePool {
    function feeRecipientAddress() external view returns (address);

    function feeBps() external view returns (uint256);
}

contract FlashAttack {
    IERC20 public immutable want;
    IERC3156FlashLender public immutable lender;
    uint256 public counter;

    constructor(IERC20 _want, IERC3156FlashLender _lender) {
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
            uint256 _amt = (amount + abi.decode(data, (uint256)));
            lender.flashLoan(IERC3156FlashBorrower(address(this)), address(want), _amt, data);
        }

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}

contract FlashFeeEscapeBorrower {
    IERC20 public immutable want;
    IERC3156FlashLender public immutable lender;
    uint256 public counter;

    constructor(IERC20 _want, IERC3156FlashLender _lender, uint256 _amt) {
        want = _want;
        lender = _lender;

        // Approve to repay
        IERC20(_want).approve(address(_lender), type(uint256).max);
        counter = _amt;
    }

    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external returns (bytes32) {
        require(token == address(want));

        if (IERC20(want).balanceOf(address(this)) < counter) {
            lender.flashLoan(IERC3156FlashBorrower(address(this)), address(want), amount, data);
        }

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}

contract FlashLoanAttack is eBTCBaseFixture {
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

    function testEBTCAttack(uint128 amount) public {
        amount = uint128(bound(amount, 0, borrowerOperations.maxFlashLoan(address(eBTCToken))));

        uint256 fee = borrowerOperations.flashFee(address(eBTCToken), amount);

        vm.assume(fee > 0);

        FlashAttack attacker = new FlashAttack(
            IERC20(eBTCToken),
            IERC3156FlashLender(address(borrowerOperations))
        );

        // Deal only fee for one, will revert
        deal(address(eBTCToken), address(attacker), fee);

        vm.expectRevert(bytes("ERC20: transfer amount exceeds balance"));
        borrowerOperations.flashLoan(
            IERC3156FlashBorrower(address(attacker)),
            address(eBTCToken),
            amount,
            abi.encodePacked(uint256(0))
        );

        // Deal more
        deal(address(eBTCToken), address(attacker), fee * 2);

        uint256 feeRecipientPreviousBalance = eBTCToken.balanceOf(
            borrowerOperations.feeRecipientAddress()
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
            eBTCToken.balanceOf(borrowerOperations.feeRecipientAddress()),
            feeRecipientPreviousBalance + fee * 2
        );
        assertEq(eBTCToken.balanceOf(address(attacker)), attackerPreviousBalance - fee * 2);
        assertEq(eBTCToken.totalSupply(), ebtcSupplyBefore);
    }

    function testWethAttack(uint112 amount) public {
        uint256 _maxAvailable = activePool.getSystemCollShares();

        amount = uint112(bound(amount, cdpManager.LIQUIDATOR_REWARD() + 1, _maxAvailable / 2 - 1));

        uint256 fee = activePool.flashFee(address(collateral), amount);

        vm.assume(fee > 0);

        FlashAttack attacker = new FlashAttack(
            IERC20(address(collateral)),
            IERC3156FlashLender(address(activePool))
        );

        // Deal only fee for one, will revert
        vm.deal(address(activePool), amount);
        dealCollateral(address(attacker), fee);

        vm.expectRevert("ActivePool: Too much");
        activePool.flashLoan(
            IERC3156FlashBorrower(address(attacker)),
            address(collateral),
            amount,
            abi.encodePacked(_maxAvailable)
        );

        vm.deal(address(activePool), amount * 2);
        dealCollateral(address(attacker), fee * 2);

        // Check is to ensure that we didn't donate too much
        vm.assume(
            collateral.balanceOf(address(activePool)) - amount < activePool.getSystemCollShares()
        );
        vm.expectRevert("ActivePool: Must repay Balance");
        activePool.flashLoan(
            IERC3156FlashBorrower(address(attacker)),
            address(collateral),
            amount,
            abi.encodePacked(uint256(0))
        );
    }

    function testFeeEscapeAttack() public {
        uint256 _feeBps = IActivePool(address(activePool)).feeBps();
        uint256 amount = 10000 / IActivePool(address(activePool)).feeBps();
        uint256 totalAmount = amount * _feeBps;

        uint256 fee = activePool.flashFee(address(collateral), amount);

        vm.assume(fee == 0);

        FlashFeeEscapeBorrower attacker = new FlashFeeEscapeBorrower(
            IERC20(address(collateral)),
            IERC3156FlashLender(address(activePool)),
            amount
        );

        dealCollateral(address(activePool), totalAmount * 2);

        address _feeRecipient = IActivePool(address(activePool)).feeRecipientAddress();
        uint256 _feeBefore = IERC20(address(collateral)).balanceOf(_feeRecipient);
        activePool.flashLoan(
            IERC3156FlashBorrower(address(attacker)),
            address(collateral),
            amount,
            abi.encodePacked(amount)
        );
        uint256 _feeAfter = IERC20(address(collateral)).balanceOf(_feeRecipient);
        require(_feeAfter == _feeBefore, "!flash fee should be zero due to division loss");
    }
}
