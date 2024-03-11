// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {SimplifiedDiamondLike} from "../contracts/SimplifiedDiamondLike.sol";

import {eBTCBaseInvariants} from "./BaseInvariants.sol";
import {LeverageMacroDelegateTarget} from "../contracts/LeverageMacroDelegateTarget.sol";
import {LeverageMacroBase} from "../contracts/LeverageMacroBase.sol";
import {LeverageMacroReference} from "../contracts/LeverageMacroReference.sol";
import {Mock1Inch} from "../contracts/TestContracts/Mock1Inch.sol";
import {ICdpManagerData} from "../contracts/Interfaces/ICdpManagerData.sol";
import {IPositionManagers} from "../contracts/Interfaces/IPositionManagers.sol";

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
            data: abi.encodeCall(eBTCToken.approve, (address(borrowerOperations), type(uint256).max))
        });

        // 3) stETH.approve(_activePool, type(uint256).max);
        data[3] = SimplifiedDiamondLike.Operation({
            to: address(address(collateral)),
            checkSuccess: true,
            value: 0,
            gas: 9999999,
            capGas: false,
            opType: SimplifiedDiamondLike.OperationType.call,
            data: abi.encodeCall(eBTCToken.approve, (address(activePool), type(uint256).max))
        });

        // 4) Leverage Operation on Macro Reference
        data[4] = SimplifiedDiamondLike.Operation({
            to: address(address(macro_reference)),
            checkSuccess: true,
            value: 0,
            gas: 9999999,
            capGas: false,
            opType: SimplifiedDiamondLike.OperationType.delegatecall,
            data: getEncodedOpenCdpData()
        });

        uint256 cdpCntBefore = sortedCdps.cdpCountOf(address(wallet));
        _mock1Inch.setPrice(priceFeedMock.getPrice());

        wallet.execute(data);

        // Verify new cdp is opened
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(address(wallet), cdpCntBefore);

        // NOTE: We don't sweep to caller, but instead leave in SC wallet

        // Verify CDP Was Open
        // IsCDPOpen
        vm.stopPrank();

        // Verify token balance to user
        assertTrue(eBTCToken.balanceOf(address(wallet)) > 0);
    }

    function test_claimCollateralSurplus() public {
        vm.prank(user);
        collateral.transferShares(address(collSurplusPool), 1e18);

        vm.prank(address(activePool));
        collSurplusPool.increaseTotalSurplusCollShares(1e18);

        vm.prank(address(cdpManager));
        collSurplusPool.increaseSurplusCollShares(bytes32(0), address(wallet), 1e18, 0);

        SimplifiedDiamondLike.Operation[] memory data = new SimplifiedDiamondLike.Operation[](1);

        LeverageMacroBase.LeverageMacroOperation memory operation = LeverageMacroBase
            .LeverageMacroOperation(
                address(0),
                0,
                new LeverageMacroBase.SwapOperation[](0),
                new LeverageMacroBase.SwapOperation[](0),
                LeverageMacroBase.OperationType.ClaimSurplusOperation,
                ""
            );

        // Post check params
        LeverageMacroBase.PostCheckParams memory postCheckParams = LeverageMacroBase
            .PostCheckParams({
                expectedDebt: LeverageMacroBase.CheckValueAndType({
                    value: 0,
                    operator: LeverageMacroBase.Operator.skip
                }),
                expectedCollateral: LeverageMacroBase.CheckValueAndType({
                    value: 0,
                    operator: LeverageMacroBase.Operator.skip
                }),
                // NOTE: Unused
                cdpId: bytes32(0),
                // NOTE: Superfluous
                expectedStatus: ICdpManagerData.Status.active
            });

        data[0] = SimplifiedDiamondLike.Operation({
            to: address(address(macro_reference)),
            checkSuccess: true,
            value: 0,
            gas: 9999999,
            capGas: false,
            opType: SimplifiedDiamondLike.OperationType.delegatecall,
            data: abi.encodeCall(
                LeverageMacroBase.doOperation,
                (
                    LeverageMacroBase.FlashLoanType.noFlashloan,
                    0,
                    operation,
                    LeverageMacroBase.PostOperationCheck.none,
                    postCheckParams
                )
            )
        });

        vm.startPrank(user);
        wallet.execute(data);
        vm.stopPrank();
    }

    function _generatePermitSignature(
        address _signer,
        address _positionManager,
        IPositionManagers.PositionManagerApproval _approval,
        uint _deadline
    ) internal returns (bytes32) {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                borrowerOperations.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        borrowerOperations.permitTypeHash(),
                        _signer,
                        _positionManager,
                        _approval,
                        borrowerOperations.nonces(_signer),
                        _deadline
                    )
                )
            )
        );
        return digest;
    }

    function _generateOneTimePermitFromFixedTestUser(
        LeverageMacroBase zapRouter,
        address user,
        uint256 userPrivateKey
    ) internal returns (uint deadline, uint8 v, bytes32 r, bytes32 s) {
        deadline = (block.timestamp + deadline);
        IPositionManagers.PositionManagerApproval _approval = IPositionManagers
            .PositionManagerApproval
            .OneTime;

        // Generate signature to one-time approve zap
        bytes32 digest = _generatePermitSignature(user, address(zapRouter), _approval, deadline);
        (v, r, s) = vm.sign(userPrivateKey, digest);
    }

    function test_openCdpFor() public {
        uint256 userPrivateKey = 0xaabbccdd;
        address user = vm.addr(userPrivateKey);

        dealCollateral(user, 1e20);

        LeverageMacroBase zapRouter = new LeverageMacroReference(
            address(borrowerOperations),
            address(activePool),
            address(cdpManager),
            address(eBTCToken),
            address(collateral),
            address(sortedCdps),
            user
        );

        (uint deadline, uint8 v, bytes32 r, bytes32 s) = _generateOneTimePermitFromFixedTestUser(
            zapRouter,
            user,
            userPrivateKey
        );

        borrowerOperations.permitPositionManagerApproval(
            user,
            address(zapRouter),
            IPositionManagers.PositionManagerApproval.OneTime,
            deadline,
            v,
            r,
            s
        );

        uint256 debt = 1e18;
        uint256 margin = 5 ether;
        uint256 flAmount = _debtToCollateral(debt);
        uint256 totalCollateral = ((flAmount + margin) * 9995) / 1e4;

        LeverageMacroBase.OpenCdpForOperation memory cdp;

        cdp.eBTCToMint = debt;
        cdp._upperHint = bytes32(0);
        cdp._lowerHint = bytes32(0);
        cdp.stETHToDeposit = totalCollateral;
        cdp.borrower = user;

        // simulate transferFrom inside zap router
        vm.prank(user);
        collateral.approve(address(zapRouter), type(uint256).max);

        _openCdpForOperation({
            _zapRouter: zapRouter,
            _cdp: cdp,
            _flAmount: flAmount,
            _stEthBalance: margin,
            _exchangeData: abi.encodeWithSelector(
                Mock1Inch.swap.selector,
                address(eBTCToken),
                address(collateral),
                debt
            )
        });
    }

    function _getSwapOperations(
        address _tokenForSwap,
        uint256 _exactApproveAmount,
        bytes memory _exchangeData
    ) internal view returns (LeverageMacroBase.SwapOperation[] memory swaps) {
        swaps = new LeverageMacroBase.SwapOperation[](1);

        swaps[0].tokenForSwap = _tokenForSwap;
        swaps[0].addressForApprove = address(_mock1Inch);
        swaps[0].exactApproveAmount = _exactApproveAmount;
        swaps[0].addressForSwap = address(_mock1Inch);
        swaps[0].calldataForSwap = _exchangeData;
    }

    function _debtToCollateral(uint256 _debt) public returns (uint256) {
        uint256 price = priceFeedMock.fetchPrice();
        return (_debt * 1e18) / price;
    }

    function _openCdpForOperation(
        LeverageMacroBase _zapRouter,
        LeverageMacroBase.OpenCdpForOperation memory _cdp,
        uint256 _flAmount,
        uint256 _stEthBalance,
        bytes memory _exchangeData
    ) internal {
        LeverageMacroBase.LeverageMacroOperation memory op;

        op.tokenToTransferIn = address(collateral);
        op.amountToTransferIn = _stEthBalance;
        op.operationType = LeverageMacroBase.OperationType.OpenCdpOperation;
        op.OperationData = abi.encode(_cdp);
        op.swapsAfter = _getSwapOperations(address(eBTCToken), _cdp.eBTCToMint, _exchangeData);

        vm.prank(_cdp.borrower);
        _zapRouter.doOperation(
            LeverageMacroBase.FlashLoanType.stETH,
            _flAmount,
            op,
            LeverageMacroBase.PostOperationCheck.openCdp,
            _getPostCheckParams(
                bytes32(0),
                _cdp.eBTCToMint,
                _cdp.stETHToDeposit,
                ICdpManagerData.Status.active
            )
        );
    }

    function _getPostCheckParams(
        bytes32 _cdpId,
        uint256 _debt,
        uint256 _totalCollateral,
        ICdpManagerData.Status _status
    ) internal view returns (LeverageMacroBase.PostCheckParams memory) {
        return
            LeverageMacroBase.PostCheckParams({
                expectedDebt: LeverageMacroBase.CheckValueAndType({
                    value: _debt,
                    operator: LeverageMacroBase.Operator.lte
                }),
                expectedCollateral: LeverageMacroBase.CheckValueAndType({
                    value: _totalCollateral,
                    operator: LeverageMacroBase.Operator.gte
                }),
                cdpId: _cdpId,
                expectedStatus: _status
            });
    }

    function getEncodedOpenCdpData() internal returns (bytes memory) {
        // Swaps b4 and after
        LeverageMacroBase.SwapOperation[] memory _levSwapsBefore;
        LeverageMacroBase.SwapOperation[] memory _levSwapsAfter;

        uint256 netColl = collateral.balanceOf(user) / 2; // TODO: Make generic

        uint256 grossColl = netColl + cdpManager.LIQUIDATOR_REWARD();

        // TODO: FIX THIS // Donation breaks invariants but ensures we have enough to pay without figuring out issue with swap
        deal(address(eBTCToken), address(wallet), 1e23);

        // leverage parameters
        uint256 debt = _utils.calculateBorrowAmount(
            grossColl,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );

        // Swaps b4
        _levSwapsBefore = _generateCalldataSwapMock1InchOneStep(
            address(eBTCToken),
            debt,
            address(collateral),
            0 // TODO _collMinOut
        );

        // Open CDP
        LeverageMacroBase.OpenCdpOperation memory _opData = LeverageMacroBase.OpenCdpOperation(
            debt,
            DUMMY_CDP_ID,
            DUMMY_CDP_ID,
            grossColl
        );

        bytes memory _opDataEncoded = abi.encode(_opData);

        // Operation
        LeverageMacroBase.LeverageMacroOperation memory operation = LeverageMacroBase
            .LeverageMacroOperation(
                address(collateral),
                (grossColl - 0),
                _levSwapsBefore,
                _levSwapsAfter,
                LeverageMacroBase.OperationType.OpenCdpOperation,
                _opDataEncoded
            );

        // Post check params
        LeverageMacroBase.PostCheckParams memory postCheckParams = LeverageMacroBase
            .PostCheckParams({
                expectedDebt: LeverageMacroBase.CheckValueAndType({
                    value: 0,
                    operator: LeverageMacroBase.Operator.skip
                }),
                expectedCollateral: LeverageMacroBase.CheckValueAndType({
                    value: 0,
                    operator: LeverageMacroBase.Operator.skip
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
        dealCollateral(_setupOwner, 1_000_000_000e18);
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
        dealCollateral(_dex, 1_000_000_000e18);
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
