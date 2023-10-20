// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {SimplifiedDiamondLike} from "../contracts/SimplifiedDiamondLike.sol";

import {eBTCBaseInvariants} from "./BaseInvariants.sol";
import {LeverageMacroDelegateTarget} from "../contracts/LeverageMacroDelegateTarget.sol";
import {LeverageMacroBase} from "../contracts/LeverageMacroBase.sol";
import {Mock1Inch} from "../contracts/TestContracts/Mock1Inch.sol";
import {ICdpManagerData} from "../contracts/Interfaces/ICdpManagerData.sol";

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

    LeverageMacroBase macro_reference;
    LeverageMacroOwnerCheck owner_check;

    SimplifiedDiamondLike wallet;

    Mock1Inch public _mock1Inch;

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

        // SWAP
        _mock1Inch = new Mock1Inch(address(eBTCToken), address(collateral));
        _setupSwapDex(address(_mock1Inch));
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
            data: abi.encodeCall(
                collateral.approve,
                (address(borrowerOperations), type(uint256).max)
            ) // TODO: Max reverts??
        });

        // Open CDP
        /**
         * uint256 _EBTCAmount,
         *         bytes32 _upperHint,
         *         bytes32 _lowerHint,
         *         uint256 _collAmount
         */
        data[2] = SimplifiedDiamondLike.Operation({
            to: address(address(borrowerOperations)),
            checkSuccess: true,
            value: 0,
            gas: 9999999,
            capGas: false,
            opType: SimplifiedDiamondLike.OperationType.call,
            data: abi.encodeCall(
                borrowerOperations.openCdp,
                (2e18, bytes32(0), bytes32(0), collBall)
            )
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

        // TODO check token balances?
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

    function test_openWithLeverage(uint256 _leverage) public {
        // Same as above, but:
        // Swap data
        // Flashloan
        // Etc..

        // PROB Change the macro to not sweep

        // Set the macro for callback
        vm.startPrank(user);
        wallet.setFallbackHandler(LeverageMacroBase.onFlashLoan.selector, address(macro_reference));

        // Approve col for SC Wallet usage
        collateral.approve(address(wallet), type(uint256).max);
        uint256 collBall = collateral.balanceOf(user);

        // Step 0
        // Enable Callback for the FL

        // CDP MACRO APPROVALS 3
        // 1) ebtcToken.approve(_borrowerOperationsAddress, type(uint256).max);
        // 2) stETH.approve(_borrowerOperationsAddress, type(uint256).max);
        // 3) stETH.approve(_activePool, type(uint256).max);

        // In macro
        // 4) Delegate to LeverageMacroBase
        SimplifiedDiamondLike.Operation[] memory data = new SimplifiedDiamondLike.Operation[](5);

        data[0] = SimplifiedDiamondLike.Operation({
            to: address(address(wallet)),
            checkSuccess: true,
            value: 0,
            gas: 9999999,
            capGas: false,
            opType: SimplifiedDiamondLike.OperationType.call,
            data: abi.encodeCall(SimplifiedDiamondLike.enableCallbackForCall, ()) // Empty tuple for no params
        });

        // 1) ebtcToken.approve(_borrowerOperationsAddress, type(uint256).max);
        data[1] = SimplifiedDiamondLike.Operation({
            to: address(address(eBTCToken)),
            checkSuccess: true,
            value: 0,
            gas: 9999999,
            capGas: false,
            opType: SimplifiedDiamondLike.OperationType.call,
            data: abi.encodeCall(eBTCToken.approve, (address(borrowerOperations), type(uint256).max))
        });

        // 2) stETH.approve(_borrowerOperationsAddress, type(uint256).max);
        data[2] = SimplifiedDiamondLike.Operation({
            to: address(address(collateral)),
            checkSuccess: true,
            value: 0,
            gas: 9999999,
            capGas: false,
            opType: SimplifiedDiamondLike.OperationType.call,
            // NOTE: same sig
            data: abi.encodeCall(
                collateral.approve,
                (address(borrowerOperations), type(uint256).max)
            )
        });

        // 3) stETH.approve(_activePool, type(uint256).max);
        data[3] = SimplifiedDiamondLike.Operation({
            to: address(address(collateral)),
            checkSuccess: true,
            value: 0,
            gas: 9999999,
            capGas: false,
            opType: SimplifiedDiamondLike.OperationType.call,
            data: abi.encodeCall(collateral.approve, (address(activePool), type(uint256).max))
        });

        // 4) Leverage Operation on Macro Reference
        uint256 _expectedICR = MINIMAL_COLLATERAL_RATIO + 12345678901234567;
        data[4] = SimplifiedDiamondLike.Operation({
            to: address(address(macro_reference)),
            checkSuccess: true,
            value: 0,
            gas: 9999999,
            capGas: false,
            opType: SimplifiedDiamondLike.OperationType.delegatecall,
            data: getEncodedOpenCdpData(_leverage, _expectedICR)
        });

        uint256 cdpCntBefore = sortedCdps.cdpCountOf(address(wallet));
        _mock1Inch.setPrice(priceFeedMock.getPrice());

        wallet.execute(data);

        // Verify new cdp is opened
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(address(wallet), cdpCntBefore);
        assertTrue(cdpId != bytes32(0));
        uint256 cdpCntAfter = sortedCdps.cdpCountOf(address(wallet));
        assertTrue(cdpCntAfter == cdpCntBefore + 1);

        // NOTE: We don't sweep to caller, but instead leave in SC wallet

        // Verify CDP Was Open
        // IsCDPOpen
        vm.stopPrank();

        // Verify leveraged CDP ICR
        uint256 _icr = cdpManager.getSyncedICR(cdpId, priceFeedMock.fetchPrice());
        _utils.assertApproximateEq(_expectedICR, _icr, 1e8);
    }

    function getEncodedOpenCdpData(
        uint256 _leverage,
        uint256 _expectedICR
    ) internal returns (bytes memory) {
        // do some clamp on leverage parameter
        _leverage = bound(_leverage, 2, 8);

        // Swaps b4 and after
        LeverageMacroBase.SwapOperation[] memory _levSwapsBefore;
        LeverageMacroBase.SwapOperation[] memory _levSwapsAfter;

        uint256 initialPrincipal = collateral.balanceOf(user) / (2 * _leverage);

        uint256 grossColl = (initialPrincipal * _leverage) + cdpManager.LIQUIDATOR_REWARD();

        // leverage parameters
        uint256 debt = _utils.calculateBorrowAmount(
            grossColl,
            priceFeedMock.fetchPrice(),
            _expectedICR
        );
        uint256 _debtPlusFee = debt + borrowerOperations.flashFee(address(eBTCToken), debt);

        // Swaps b4: from flashloaned eBTC to collateral for leverage
        _levSwapsBefore = _generateCalldataSwapMock1InchOneStep(
            address(eBTCToken),
            debt,
            address(collateral),
            (grossColl - initialPrincipal)
        );

        // Open CDP with expected collateral & debt
        LeverageMacroBase.OpenCdpOperation memory _opData = LeverageMacroBase.OpenCdpOperation(
            _debtPlusFee,
            DUMMY_CDP_ID,
            DUMMY_CDP_ID,
            grossColl
        );

        bytes memory _opDataEncoded = abi.encode(_opData);

        // Operation
        LeverageMacroBase.LeverageMacroOperation memory operation = LeverageMacroBase
            .LeverageMacroOperation(
                address(collateral),
                (initialPrincipal), // transfer initial principal to wallet from user
                _levSwapsBefore,
                _levSwapsAfter,
                LeverageMacroBase.OperationType.OpenCdpOperation,
                _opDataEncoded
            );

        // Post check params
        uint256 _expectedCdpColl = grossColl - cdpManager.LIQUIDATOR_REWARD();
        LeverageMacroBase.PostCheckParams memory postCheckParams = LeverageMacroBase
            .PostCheckParams({
                expectedDebt: LeverageMacroBase.CheckValueAndType({
                    value: _debtPlusFee,
                    operator: LeverageMacroBase.Operator.equal
                }),
                expectedCollateral: LeverageMacroBase.CheckValueAndType({
                    value: _expectedCdpColl,
                    operator: LeverageMacroBase.Operator.equal
                }),
                // NOTE: Unused
                cdpId: bytes32(0),
                // NOTE: Superfluous
                expectedStatus: ICdpManagerData.Status.active
            });

        // return this as encoded call since we're one level of abstraction deeper
        return
            abi.encodeCall(
                LeverageMacroBase.doOperation,
                (
                    LeverageMacroBase.FlashLoanType.eBTC,
                    debt,
                    operation,
                    LeverageMacroBase.PostOperationCheck.openCdp,
                    postCheckParams
                )
            );
    }

    // TODO: Refactor to separate file to reuse code
    function _setupSwapDex(address _dex) internal {
        // sugardaddy eBTCToken
        address _setupOwner = _utils.createUsers(1)[0];
        vm.deal(_setupOwner, INITITAL_COLL);
        dealCollateral(_setupOwner, type(uint128).max);
        uint256 _coll = collateral.balanceOf(_setupOwner);
        uint256 _debt = _utils.calculateBorrowAmount(
            _coll,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO * 2
        );
        _openTestCDP(_setupOwner, _coll, _debt);
        uint256 _sugarDebt = eBTCToken.balanceOf(_setupOwner);
        vm.prank(_setupOwner);
        eBTCToken.transfer(_dex, _sugarDebt);

        // sugardaddy collateral
        vm.deal(_dex, INITITAL_COLL);
        dealCollateral(_dex, type(uint128).max);
    }

    function _generateCalldataSwapMock1InchOneStep(
        address _inToken,
        uint256 _inAmt,
        address _outToken,
        uint256 _minOut
    ) internal view returns (LeverageMacroBase.SwapOperation[] memory) {
        LeverageMacroBase.SwapOperation[] memory _oneStep = new LeverageMacroBase.SwapOperation[](1);
        _oneStep[0] = _generateCalldataSwapMock1Inch(_inToken, _inAmt, _outToken, _minOut);
        return _oneStep;
    }

    function _generateCalldataSwapMock1Inch(
        address _inToken,
        uint256 _inAmt,
        address _outToken,
        uint256 _minOut
    ) internal view returns (LeverageMacroBase.SwapOperation memory) {
        LeverageMacroBase.SwapCheck[] memory _swapChecks = new LeverageMacroBase.SwapCheck[](1);
        _swapChecks[0] = LeverageMacroBase.SwapCheck(_outToken, _minOut);

        bytes memory _swapData = abi.encodeWithSelector(
            Mock1Inch.swap.selector,
            _inToken,
            _outToken,
            _inAmt
        );
        return
            LeverageMacroBase.SwapOperation(
                _inToken,
                address(_mock1Inch),
                _inAmt,
                address(_mock1Inch),
                _swapData,
                _swapChecks
            );
    }
}
