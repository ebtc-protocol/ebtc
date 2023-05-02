// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";
import {Mock1Inch} from "../contracts/TestContracts/Mock1Inch.sol";
import {LeverageMacro} from "../contracts/LeverageMacro.sol";

/*
 * Test suite that tests exactly one thing: opening CDPs
 * It tests different cases and also does random testing against random coll amounts and amount of users
 */
contract LeverageOpenCdpTest is eBTCBaseFixture {
    mapping(bytes32 => bool) private _cdpIdsExist;

    address private user;
    Mock1Inch private oneInch;
    LeverageMacro private leverageMacro;


    function setUp() public override {
        eBTCBaseFixture.setUp();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();


        oneInch = new Mock1Inch(address(eBTCToken), address(collateral));

        leverageMacro = new LeverageMacro(
            address(borrowerOperations),
            address(eBTCToken),
            address(collateral),
        address(sortedCdps)

        );
        // Mint some tokens to it

        address payable[] memory users;
        users = _utils.createUsers(2);
        user = users[0];
        address user2 = users[1];

        vm.deal(user, type(uint96).max);

        vm.startPrank(user);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 10000 ether}();
        vm.stopPrank();

        vm.deal(user2, type(uint96).max);
        vm.startPrank(user2);
        collateral.deposit{value: 10000 ether}();
        collateral.transfer(address(oneInch), collateral.balanceOf(user2));
        vm.stopPrank();

    }

    // Generic test for happy case when 1 user open CDP
    // TODO: Convert to generic fuzzed test
    function test_OpenCDPForSelfHappy() public {
        vm.startPrank(user);
        uint256 borrowedAmount = _utils.calculateBorrowAmount(30 ether, priceFeedMock.fetchPrice(), COLLATERAL_RATIO);
        // Make sure there is no CDPs in the system yet
        assert(sortedCdps.getLast() == "");

        borrowerOperations.openCdpFor(borrowedAmount, "hint", "hint", 30 ether, user);
        vm.stopPrank();
    }

    function test_basicSwapOneInch(uint32 amountIn) public {
        uint256 priceOut = oneInch.price();
        uint256 expectedOut = amountIn / priceOut;
        vm.startPrank(user);
        collateral.approve(address(oneInch), type(uint256).max);

        assertEq(address(oneInch.stETH()), address(collateral), "eth is same");
        assertEq(address(oneInch.eBTCToken()), address(eBTCToken), "ebtc is same");

        uint256 initialEbtcBal = eBTCToken.balanceOf(user);
        oneInch.swap(address(collateral), address(eBTCToken), amountIn);
        uint256 balAfter = eBTCToken.balanceOf(user);
        uint256 delta = balAfter - initialEbtcBal;

        assertEq(expectedOut, delta);
    }

    // function test_basicLeverageHashing() public {
    //     LeverageMacro.FLOperation memory flData = LeverageMacro.FLOperation({
    //         eBTCToMint: 0,
    //         _upperHint: bytes32(0),
    //         _lowerHint: bytes32(0),
    //         stETHToDeposit: 1,
    //         borrower: user,
    //         // Swap Data
    //         tokenForSwap: address(eBTCToken),
    //         addressForApprove: address(oneInch),
    //         exactApproveAmount: 1,
    //         addressForSwap: address(oneInch),
    //         calldataForSwap: "",
    //         // Swap Slippage Check
    //         tokenToCheck: address(eBTCToken),
    //         expectedMinOut: 0
    //     });

    //     bytes memory encoded = leverageMacro.encodeOpenCdpOperation(flData);
    //     assertTrue(encoded.length > 0, "Encoded exists");
    // }

    // function test_basicLeverUp() public {
    //     uint256 priceOut = oneInch.price();


    //     LeverageMacro.FLOperation memory flData = LeverageMacro.FLOperation({
    //         eBTCToMint: (MIN_NET_DEBT + 1) / priceOut,
    //         _upperHint: bytes32(0),
    //         _lowerHint: bytes32(0),
    //         stETHToDeposit: MIN_NET_DEBT * 3,
    //         borrower: user,
    //         // Swap Data
    //         tokenForSwap: address(eBTCToken),
    //         addressForApprove: address(oneInch),
    //         exactApproveAmount: MIN_NET_DEBT * 3 / priceOut,
    //         addressForSwap: address(oneInch),
    //         calldataForSwap: abi.encodeCall(oneInch.swap, (address(eBTCToken), address(collateral), (MIN_NET_DEBT + 1) / priceOut)),
    //         // Swap Slippage Check
    //         tokenToCheck: address(collateral),
    //         expectedMinOut: 1
    //     });

    //     bytes memory encoded = leverageMacro.encodeOpenCdpOperation(flData);
    //     vm.startPrank(user);
    //     eBTCToken.approve(address(leverageMacro), (MIN_NET_DEBT + 1) / priceOut);

    //     // TODO: They should buy some eBTC initially
    //     deal(address(eBTCToken), user, (MIN_NET_DEBT + 1) / priceOut);

    //     leverageMacro.openCdpLeveraged(
    //         (MIN_NET_DEBT + 1) / priceOut,
    //         MIN_NET_DEBT * 2,
    //         encoded
    //     );

    //     vm.stopPrank();
    // }
}
