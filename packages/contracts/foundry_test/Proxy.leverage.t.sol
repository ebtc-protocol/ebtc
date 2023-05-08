// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;
import "forge-std/Test.sol";
import {eBTCBaseInvariants} from "./BaseInvariants.sol";
import {LeverageMacro} from "../contracts/LeverageMacro.sol";
import {Mock1Inch} from "../contracts/TestContracts/Mock1Inch.sol";
import {ICdpManagerData} from "../contracts/Interfaces/ICdpManagerData.sol";

/*
 * Test suite that tests exactly one thing: opening CDPs
 * It tests different cases and also does random testing against random coll amounts and amount of users
 */
contract ProxyLeverageTest is eBTCBaseInvariants {
    mapping(bytes32 => bool) private _cdpIdsExist;

    Mock1Inch public _mock1Inch;
    uint public _acceptedSlippage = 50;
    uint public constant MAX_SLIPPAGE = 10000;
    bytes32 public constant DUMMY_CDP_ID = bytes32(0);
    uint public constant INITITAL_COLL = 10000 ether;

    function setUp() public override {
        super.setUp();

        connectCoreContracts();
        connectLQTYContractsToCore();

        _mock1Inch = new Mock1Inch(address(eBTCToken), address(collateral));
        _setupSwapDex(address(_mock1Inch));

        _acceptedSlippage = _mock1Inch.slippage() * 2;
        require(_acceptedSlippage < MAX_SLIPPAGE, "!_acceptedSlippage");

        _ensureSystemInvariants();
    }

    function test_OpenLeveragedCDPHappy(uint netColl) public {
        address user = _utils.createUsers(1)[0];

        vm.deal(user, type(uint96).max);

        // check input
        vm.assume(netColl < INITITAL_COLL * 5);
        vm.assume(netColl > cdpManager.MIN_NET_COLL());

        // deploy proxy for user
        address proxyAddr = _createLeverageMacro(user);

        // open CDP
        dealCollateral(user, netColl);
        _openCDPViaProxy(user, netColl, proxyAddr);
    }

    function test_AdjustLeveragedCDPHappy() public {}

    function test_OpenAndCloseLeveragedCDPHappy(uint netColl) public {
        address user = _utils.createUsers(1)[0];

        vm.deal(user, type(uint96).max);

        // check input
        vm.assume(netColl < INITITAL_COLL * 5);
        vm.assume(netColl > cdpManager.MIN_NET_COLL());

        // deploy proxy for user
        address proxyAddr = _createLeverageMacro(user);

        // open CDP
        dealCollateral(user, netColl);
        bytes32 cdpId = _openCDPViaProxy(user, netColl, proxyAddr);

        // close CDP
        _closeCDPViaProxy(user, cdpId, proxyAddr);
    }

    function _openCDPViaProxy(
        address user,
        uint256 netColl,
        address proxyAddr
    ) internal returns (bytes32) {
        uint grossColl = netColl + cdpManager.LIQUIDATOR_REWARD();

        vm.startPrank(user);

        // leverage parameters
        uint debt = _utils.calculateBorrowAmount(
            grossColl,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );
        LeverageMacro.SwapOperation[] memory _levSwapsBefore;
        LeverageMacro.SwapOperation[] memory _levSwapsAfter;

        // prepare operation data
        uint _cdpDebt = _getTotalAmountForFlashLoan(debt, true);
        LeverageMacro.OpenCdpOperation memory _opData = LeverageMacro.OpenCdpOperation(
            _cdpDebt,
            DUMMY_CDP_ID,
            DUMMY_CDP_ID,
            grossColl
        );
        bytes memory _opDataEncoded = abi.encode(_opData);
        uint _collMinOut = _convertDebtAndCollForSwap(
            debt,
            true,
            _acceptedSlippage,
            priceFeedMock.getPrice(),
            false
        );
        _levSwapsBefore = _generateCalldataSwapMock1InchOneStep(
            address(eBTCToken),
            debt,
            address(collateral),
            _collMinOut
        );
        require(
            (grossColl - _collMinOut) > 0,
            "!leverage Open CDP transferIn collateral amount can't be zero"
        );
        LeverageMacro.LeverageMacroOperation memory operation = LeverageMacro.LeverageMacroOperation(
            address(collateral),
            (grossColl - _collMinOut),
            _levSwapsBefore,
            _levSwapsAfter,
            LeverageMacro.OperationType.OpenCdpOperation,
            _opDataEncoded
        );

        LeverageMacro.PostCheckParams memory postCheckParams = _preparePostCheckParams(
            _cdpDebt,
            LeverageMacro.Operator.equal,
            netColl,
            LeverageMacro.Operator.equal,
            ICdpManagerData.Status.active,
            DUMMY_CDP_ID
        );

        // execute the leverage through proxy
        uint cdpCntBefore = sortedCdps.cdpCountOf(proxyAddr);
        _mock1Inch.setPrice(priceFeedMock.getPrice());
        LeverageMacro(proxyAddr).doOperation(
            LeverageMacro.FlashLoanType.eBTC,
            debt,
            operation,
            LeverageMacro.PostOperationCheck.openCdp,
            postCheckParams
        );

        vm.stopPrank();
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(proxyAddr, cdpCntBefore);

        // check system invariants
        _ensureSystemInvariants();
        return cdpId;
    }

    function _closeCDPViaProxy(address user, bytes32 cdpId, address proxyAddr) internal {
        vm.startPrank(user);

        // leverage parameters
        LeverageMacro.SwapOperation[] memory _levSwapsBefore;
        LeverageMacro.SwapOperation[] memory _levSwapsAfter;
        bytes memory _opDataEncoded;
        uint _totalDebt;

        // prepare operation data
        {
            (uint _debt, uint _totalColl, , ) = cdpManager.getEntireDebtAndColl(cdpId);
            _totalDebt = _debt;
            uint _flDebt = _getTotalAmountForFlashLoan(_totalDebt, true);
            LeverageMacro.CloseCdpOperation memory _opData = LeverageMacro.CloseCdpOperation(cdpId);
            _opDataEncoded = abi.encode(_opData);
            uint _collRequired = _convertDebtAndCollForSwap(
                _flDebt,
                true,
                _acceptedSlippage,
                priceFeedMock.getPrice(),
                true
            );
            require(_totalColl >= _collRequired, "!not enough collateral in CDP for flashloan debt");

            _levSwapsAfter = _generateCalldataSwapMock1InchOneStep(
                address(collateral),
                _collRequired,
                address(eBTCToken),
                _flDebt
            );
        }
        LeverageMacro.LeverageMacroOperation memory operation = LeverageMacro.LeverageMacroOperation(
            address(collateral),
            0,
            _levSwapsBefore,
            _levSwapsAfter,
            LeverageMacro.OperationType.CloseCdpOperation,
            _opDataEncoded
        );

        LeverageMacro.PostCheckParams memory postCheckParams = _preparePostCheckParams(
            0,
            LeverageMacro.Operator.equal,
            0,
            LeverageMacro.Operator.equal,
            ICdpManagerData.Status.closedByOwner,
            cdpId
        );

        // execute the leverage through proxy
        _mock1Inch.setPrice(priceFeedMock.getPrice());
        LeverageMacro(proxyAddr).doOperation(
            LeverageMacro.FlashLoanType.eBTC,
            _totalDebt,
            operation,
            LeverageMacro.PostOperationCheck.isClosed,
            postCheckParams
        );

        vm.stopPrank();

        // check system invariants
        _ensureSystemInvariants();
    }

    function _generateCalldataSwapMock1Inch(
        address _inToken,
        uint256 _inAmt,
        address _outToken,
        uint _minOut
    ) internal view returns (LeverageMacro.SwapOperation memory) {
        LeverageMacro.SwapCheck[] memory _swapChecks = new LeverageMacro.SwapCheck[](1);
        _swapChecks[0] = LeverageMacro.SwapCheck(_outToken, _minOut);

        bytes memory _swapData = abi.encodeWithSelector(
            Mock1Inch.swap.selector,
            _inToken,
            _outToken,
            _inAmt
        );
        return
            LeverageMacro.SwapOperation(
                _inToken,
                address(_mock1Inch),
                _inAmt,
                address(_mock1Inch),
                _swapData,
                _swapChecks
            );
    }

    function _generateCalldataSwapMock1InchOneStep(
        address _inToken,
        uint256 _inAmt,
        address _outToken,
        uint _minOut
    ) internal view returns (LeverageMacro.SwapOperation[] memory) {
        LeverageMacro.SwapOperation[] memory _oneStep = new LeverageMacro.SwapOperation[](1);
        _oneStep[0] = _generateCalldataSwapMock1Inch(_inToken, _inAmt, _outToken, _minOut);
        return _oneStep;
    }

    function _convertDebtAndCollForSwap(
        uint _amt,
        bool _fromDebtToColl,
        uint _acceptedSlippage,
        uint _price,
        bool _addSlippage
    ) internal view returns (uint) {
        uint _raw;
        if (_fromDebtToColl) {
            _raw = (_amt * 1e18) / _price;
        } else {
            _raw = (_amt * _price) / 1e18;
        }
        uint _multiplier = _addSlippage
            ? (MAX_SLIPPAGE + _acceptedSlippage)
            : (MAX_SLIPPAGE - _acceptedSlippage);
        return (_raw * _multiplier) / MAX_SLIPPAGE;
    }

    function _preparePostCheckParams(
        uint _expectedDebt,
        LeverageMacro.Operator _debtOperator,
        uint _expectedColl,
        LeverageMacro.Operator _collOperator,
        ICdpManagerData.Status _expectedStatus,
        bytes32 _cdpId
    ) internal view returns (LeverageMacro.PostCheckParams memory) {
        // confirm debt is expected
        LeverageMacro.CheckValueAndType memory expectedDebt = LeverageMacro.CheckValueAndType(
            _expectedDebt,
            _debtOperator
        );

        // confirm coll is expected
        LeverageMacro.CheckValueAndType memory expectedCollateral = LeverageMacro.CheckValueAndType(
            _expectedColl,
            _collOperator
        );

        return
            LeverageMacro.PostCheckParams(expectedDebt, expectedCollateral, _cdpId, _expectedStatus);
    }

    function _getTotalAmountForFlashLoan(
        uint _borrowAmt,
        bool _borrowDebt
    ) internal view returns (uint) {
        uint _fee;
        if (_borrowDebt) {
            _fee = borrowerOperations.flashFee(address(eBTCToken), _borrowAmt);
        } else {
            _fee = activePool.flashFee(address(collateral), _borrowAmt);
        }
        return _borrowAmt + _fee;
    }

    function _createLeverageMacro(address _user) internal returns (address) {
        vm.startPrank(_user);

        LeverageMacro proxy = new LeverageMacro(
            address(borrowerOperations),
            address(activePool),
            address(cdpManager),
            address(eBTCToken),
            address(collateral),
            address(sortedCdps),
            _user
        );

        // approve tokens for proxy
        collateral.approve(address(proxy), type(uint256).max);
        eBTCToken.approve(address(proxy), type(uint256).max);

        vm.stopPrank();

        return address(proxy);
    }

    function _setupSwapDex(address _dex) internal {
        // sugardaddy eBTCToken
        address _setupOwner = _utils.createUsers(1)[0];
        vm.deal(_setupOwner, INITITAL_COLL);
        dealCollateral(_setupOwner, type(uint128).max);
        uint _coll = collateral.balanceOf(_setupOwner);
        uint _debt = _utils.calculateBorrowAmount(
            _coll,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO * 2
        );
        _openTestCDP(_setupOwner, _coll, _debt);
        uint _sugarDebt = eBTCToken.balanceOf(_setupOwner);
        vm.prank(_setupOwner);
        eBTCToken.transfer(_dex, _sugarDebt);

        // sugardaddy collateral
        vm.deal(_dex, INITITAL_COLL);
        dealCollateral(_dex, type(uint128).max);
    }
}
