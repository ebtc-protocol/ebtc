// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {SimplifiedDiamondLike} from "../contracts/SimplifiedDiamondLike.sol";

import {eBTCBaseInvariants} from "./BaseInvariants.sol";
import {LeverageMacroDelegateTarget} from "../contracts/LeverageMacroDelegateTarget.sol";

interface IOwnerLike {
    function owner() external view returns (address);
}

// Basic test to ensure delegate call will maintain the owner as we'd expect
contract LeverageMacroOwnerCheck {
    event DebugOwner(address);

    function getOwner() external returns (address) {
        // Since we delegate call we should have access to this if we call ourselves back
        address owner = IOwnerLike(address(this)).owner();
        emit DebugOwner(owner);

        return owner;
    }
}

interface FakeCall {
    function fakeFunction() external view;
}

contract SimplifiedDiamondLikeLeverageTests is eBTCBaseInvariants {
    mapping(bytes32 => bool) private _cdpIdsExist;

    uint256 public _acceptedSlippage = 50;
    uint256 public constant MAX_SLIPPAGE = 10000;
    bytes32 public constant DUMMY_CDP_ID = bytes32(0);
    uint256 public constant INITITAL_COLL = 10000 ether;

    address user = address(0xbad455);

    LeverageMacroDelegateTarget macro_reference;
    LeverageMacroOwnerCheck owner_check;

    SimplifiedDiamondLike wallet;

    function _createNewWalletForUser(address _user) internal returns (address payable) {
        SimplifiedDiamondLike contractWallet = new SimplifiedDiamondLike(_user);
        return payable(contractWallet);
    }

    function setUp() public override {
        super.setUp();

        connectCoreContracts();
        connectLQTYContractsToCore();

        macro_reference = new LeverageMacroDelegateTarget(
        address(borrowerOperations),
        address(activePool),
        address(cdpManager),
        address(eBTCToken),
        address(collateral),
        address(sortedCdps)
        );
        owner_check = new LeverageMacroOwnerCheck();

        vm.deal(user, type(uint96).max);

        // check input
        uint256 netColl = 1e20;
        // deploy proxy for user
        wallet = SimplifiedDiamondLike(_createNewWalletForUser(user));

        uint256 collBall = dealCollateral(user, netColl);
    }

    function test_happyOpen() public {
        /// == OPEN CDP FLOW == ///
        // User:
        // Approve the Wallet

        // SC Wallet
        // Approve Coll for borrowersOperations
        // TransferFrom
        // OpenCdp
        // Transfer To user

        // User.Approve col
        vm.startPrank(user);
        collateral.approve(address(wallet), type(uint256).max);
        uint256 collBall = collateral.balanceOf(user);

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
         * uint _EBTCAmount,
         *         bytes32 _upperHint,
         *         bytes32 _lowerHint,
         *         uint _collAmount
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

    function test_ownerCheckWithDelegateCall() public {
        SimplifiedDiamondLike.Operation[] memory data = new SimplifiedDiamondLike.Operation[](1);

        // TransferFrom
        data[0] = SimplifiedDiamondLike.Operation({
            to: address(address(owner_check)),
            checkSuccess: true,
            value: 0,
            gas: 9999999,
            capGas: false,
            opType: SimplifiedDiamondLike.OperationType.delegatecall,
            data: abi.encodeCall(owner_check.getOwner, ())
        });

        vm.startPrank(user);
        wallet.execute(data);
        vm.stopPrank();

        // TODO: Add test here to check event matches
    }
    
    function test_protectedCallbackCannotWork() public {
        // Set a callback
        vm.startPrank(user);
        wallet.setFallbackHandler(FakeCall.fakeFunction.selector, address(123));

        // Protection is set by default
        
        // Expect revert
        vm.expectRevert("Only Enabled Callbacks");
        // Call it
        FakeCall(address(wallet)).fakeFunction();

        
        // Will not revert due to no contract size check
        wallet.setAllowAnyCall(true);
        FakeCall(address(wallet)).fakeFunction();
    }

    function test_openWithLeverage() public {
        // Same as above, but:
        // Swap data
        // Flashloan
        // Etc..


        // PROB Change the macro to not sweep

        // Set the macro for callback

        // Create the Sweep Module

        // User.Approve col
        vm.startPrank(user);
        collateral.approve(address(wallet), type(uint256).max);
        uint256 collBall = collateral.balanceOf(user);

        // 0) Set the callback to onFlashloan
        wallet.enableCallbackForCall();


        // TODO: CDP MACRO APPROVALS 3
        // 1) ebtcToken.approve(_borrowerOperationsAddress, type(uint256).max);
        // 2) stETH.approve(_borrowerOperationsAddress, type(uint256).max);
        // 3) stETH.approve(_activePool, type(uint256).max);

        // In macro
        // 4) Delegate to LeverageMacroDelegateTarget
        SimplifiedDiamondLike.Operation[] memory data = new SimplifiedDiamondLike.Operation[](4);

        // 1) ebtcToken.approve(_borrowerOperationsAddress, type(uint256).max);
        data[0] = SimplifiedDiamondLike.Operation({
            to: address(address(eBTCToken)),
            checkSuccess: true,
            value: 0,
            gas: 9999999,
            capGas: false,
            opType: SimplifiedDiamondLike.OperationType.call,
            data: abi.encodeCall(eBTCToken.approve, (address(borrowerOperations), type(uint256).max))
        });

        // 2) stETH.approve(_borrowerOperationsAddress, type(uint256).max);
        data[1] = SimplifiedDiamondLike.Operation({
            to: address(address(collateral)),
            checkSuccess: true,
            value: 0,
            gas: 9999999,
            capGas: false,
            opType: SimplifiedDiamondLike.OperationType.call,
            // NOTE: same sig
            data: abi.encodeCall(eBTCToken.approve, (address(borrowerOperations), type(uint256).max))
        });

        // 3) stETH.approve(_activePool, type(uint256).max);
        data[2] = SimplifiedDiamondLike.Operation({
            to: address(address(collateral)),
            checkSuccess: true,
            value: 0,
            gas: 9999999,
            capGas: false,
            opType: SimplifiedDiamondLike.OperationType.call,
            data: abi.encodeCall(eBTCToken.approve, (address(activePool), type(uint256).max))
        });


        data[3] = SimplifiedDiamondLike.Operation({
            to: address(address(macro_reference)),
            checkSuccess: true,
            value: 0,
            gas: 9999999,
            capGas: false,
            opType: SimplifiedDiamondLike.OperationType.delegatecall,
            data: abi.encodeCall(
                // TODO: 1 hr of work prob XD
            )
        });
        wallet.execute(data);

        // NOTE: We don't sweep to caller, but instead leave in SC wallet

        // Verify CDP Was Open
        // IsCDPOpen
        vm.stopPrank();

        // Verify token balance to user
        assertTrue(eBTCToken.balanceOf(address(wallet)) > 0);

        // TODO: Verify there's debt
    }
}
