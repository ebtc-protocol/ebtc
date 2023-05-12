// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {SimplifiedDiamondLike} from "../contracts/SimplifiedDiamondLike.sol";

import {eBTCBaseInvariants} from "./BaseInvariants.sol";
import {LeverageMacro} from "../contracts/LeverageMacro.sol";

contract SimplifiedDiamondLikeLeverageTests is eBTCBaseInvariants {
    mapping(bytes32 => bool) private _cdpIdsExist;

    uint public _acceptedSlippage = 50;
    uint public constant MAX_SLIPPAGE = 10000;
    bytes32 public constant DUMMY_CDP_ID = bytes32(0);
    uint public constant INITITAL_COLL = 10000 ether;

    address user_1 = address(0xbad455);

    function _createNewWalletForUser(address user) internal returns (address payable) {
        SimplifiedDiamondLike contractWallet = new SimplifiedDiamondLike(user);
        return payable(contractWallet);
    }

    function setUp() public override {
        super.setUp();

        connectCoreContracts();
        connectLQTYContractsToCore();
    }

    function test_happyOpen() public {
        address user = _utils.createUsers(1)[0];
        vm.deal(user, type(uint96).max);

        // check input
        uint256 netColl = 1e20;
        // deploy proxy for user
        SimplifiedDiamondLike wallet = SimplifiedDiamondLike(_createNewWalletForUser(user));

        /// == OPEN CDP FLOW == ///
        // User:
        // Approve the Wallet

        // SC Wallet
        // Approve Coll for borrowersOperations
        // TransferFrom
        // OpenCdp
        // Transfer To user
        uint256 collBall = dealCollateral(user, netColl);

        // User.Approve col
        vm.startPrank(user);
        collateral.approve(address(wallet), type(uint256).max);

        assertEq(collBall, collateral.balanceOf(user), "User bal");

        // In macro
        // TransferFrom
        // OpenCdp
        // Transfer To
    
        SimplifiedDiamondLike.Operation[] memory data = new SimplifiedDiamondLike.Operation[](4);

        // TransferFrom
        data[0] = SimplifiedDiamondLike.Operation({
                to: address(address(collateral)),
                checkSuccess: true,
                value: 0,
                gas: 9999999,
                capGas: false,
                opType: SimplifiedDiamondLike.OperationType.call,
                data: abi.encodeCall(collateral.transferFrom, (user, address(wallet), collBall))
        });

        // BO
        // Approve as one off for BO
        data[1] = SimplifiedDiamondLike.Operation({
                to: address(address(collateral)),
                checkSuccess: true,
                value: 0,
                gas: 9999999,
                capGas: false,
                opType: SimplifiedDiamondLike.OperationType.call,
                data: abi.encodeCall(collateral.approve, (address(borrowerOperations), type(uint256).max)) // TODO: Max reverts??
        });

        // Open CDP
        /**
            uint _EBTCAmount,
            bytes32 _upperHint,
            bytes32 _lowerHint,
            uint _collAmount
         */
        data[2] = SimplifiedDiamondLike.Operation({
                to: address(address(borrowerOperations)),
                checkSuccess: true,
                value: 0,
                gas: 9999999,
                capGas: false,
                opType: SimplifiedDiamondLike.OperationType.call,
                data: abi.encodeCall(borrowerOperations.openCdp, (2e18, bytes32(0), bytes32(0), collBall))
        });


        // Transfer to Caller
        data[3] = SimplifiedDiamondLike.Operation({
                to: address(address(eBTCToken)),
                checkSuccess: true,
                value: 0,
                gas: 9999999,
                capGas: false,
                opType: SimplifiedDiamondLike.OperationType.call,
                data: abi.encodeCall(eBTCToken.transfer, (address(user), 2e18)) // NOTE: This is hardcoded before the call
                // To make this dynamic you'd need to delegate call to a sweep contract
        });

        wallet.execute(data);


        // Verify CDP Was Open
        // IsCDPOpen
        vm.stopPrank();

        // Verify token balance to user
        assertTrue(eBTCToken.balanceOf(user) > 0);

    }

    function test_openWithLeverage() public {
        // TODO: 

        // Same as above, but:
        // Swap data
        // Flashloan
        // Etc..

        // PROB Change the macro to not sweep

        // Create the Sweep Module
        
    }
}
