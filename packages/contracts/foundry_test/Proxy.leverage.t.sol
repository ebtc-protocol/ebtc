// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {eBTCBaseInvariants} from "./BaseInvariants.sol";
import {LeverageMacroFactory} from "../contracts/LeverageMacroFactory.sol";
import {LeverageMacroReference} from "../contracts/LeverageMacroReference.sol";
import {LeverageMacroBase} from "../contracts/LeverageMacroBase.sol";
import {Mock1Inch} from "../contracts/TestContracts/Mock1Inch.sol";
import {ICdpManagerData} from "../contracts/Interfaces/ICdpManagerData.sol";

/*
 * Test suite that tests exactly one thing: opening CDPs
 * It tests different cases and also does random testing against random coll amounts and amount of users
 */
contract ProxyLeverageTest is eBTCBaseInvariants {
    mapping(bytes32 => bool) private _cdpIdsExist;

    Mock1Inch public _mock1Inch;
    uint256 public _acceptedSlippage = 50;
    uint256 public constant MAX_SLIPPAGE = 10000;
    bytes32 public constant DUMMY_CDP_ID = bytes32(0);
    uint256 public constant INITITAL_COLL = 10000 ether;

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

    function test_OpenLeveragedCDPHappy(uint256 netColl) public {
        address user = _utils.createUsers(1)[0];

        vm.deal(user, type(uint96).max);

        // check input
        (netColl, ) = _checkInputFuzzParameters(netColl, 1000);

        // deploy proxy for user
        address proxyAddr = _createLeverageMacro(user);

        // open CDP
        dealCollateral(user, netColl);
        _openCDPViaProxy(user, netColl, proxyAddr);
    }

    // TODO
    function test_AdjustLeveragedCDPHappy(uint256 netColl, uint256 adjustBps) public {
        address user = _utils.createUsers(1)[0];

        vm.deal(user, type(uint96).max);

        // check input
        (netColl, adjustBps) = _checkInputFuzzParameters(netColl, adjustBps);

        // deploy proxy for user
        address proxyAddr = _createLeverageMacro(user);

        // open CDP
        dealCollateral(user, netColl);
        bytes32 cdpId = _openCDPViaProxy(user, netColl, proxyAddr);

        // adjust CDP : increase its collateral and debt
        uint256 _additionalColl = (netColl * adjustBps) / MAX_SLIPPAGE;
        dealCollateral(user, _additionalColl);
        _increaseCDPSizeViaProxy(user, cdpId, _additionalColl, proxyAddr);

        // adjust CDP : decrease its collateral and debt
        uint256 _removedColl = (netColl * (MAX_SLIPPAGE / 2 - adjustBps)) / MAX_SLIPPAGE;
        _descreaseCDPSizeViaProxy(user, cdpId, _removedColl, proxyAddr);
    }

    function test_macroAndFactoryEquivalence(address user) public {
        vm.assume(user != address(0)); // Else this reverts on fuzzing
        LeverageMacroBase fromFactory = LeverageMacroBase(_createLeverageMacroWithFactory(user));
        LeverageMacroBase fromReference = LeverageMacroBase(_createLeverageMacro(user));

        // Equivalence of settings
        assertEq(
            address(fromFactory.borrowerOperations()),
            address(fromReference.borrowerOperations()),
            "different BO"
        );
        assertEq(
            address(fromFactory.activePool()),
            address(fromReference.activePool()),
            "different AP"
        );
        assertEq(
            address(fromFactory.cdpManager()),
            address(fromReference.cdpManager()),
            "different CDP"
        );
        assertEq(
            address(fromFactory.ebtcToken()),
            address(fromReference.ebtcToken()),
            "different Token"
        );
        assertEq(
            address(fromFactory.sortedCdps()),
            address(fromReference.sortedCdps()),
            "different Sorted"
        );
        assertEq(address(fromFactory.stETH()), address(fromReference.stETH()), "different stETH");
        assertEq(address(fromFactory.owner()), address(fromReference.owner()), "different Owner");
    }

    function test_OpenAndCloseLeveragedCDPHappy(uint256 netColl) public {
        address user = _utils.createUsers(1)[0];

        vm.deal(user, type(uint96).max);

        // check input
        (netColl, ) = _checkInputFuzzParameters(netColl, 1000);

        // deploy proxy for user
        address proxyAddr = _createLeverageMacro(user);

        // open CDP
        dealCollateral(user, netColl);
        bytes32 cdpId = _openCDPViaProxy(user, netColl, proxyAddr);

        // close CDP
        _closeCDPViaProxy(user, cdpId, proxyAddr);
    }

    function test_MultipleUserLeveragedCDPHappy(
        uint256 userCnt,
        uint256 netColl,
        uint256 adjustBps
    ) public {
        // check input
        (netColl, adjustBps) = _checkInputFuzzParameters(netColl, adjustBps);
        userCnt = bound(userCnt, 2, 4);

        address payable[] memory users = _utils.createUsers(userCnt);

        // deploy proxy for user and open CDP
        address[] memory userProxies = new address[](userCnt);
        bytes32[] memory userCdpIds = new bytes32[](userCnt);
        for (uint256 i = 0; i < users.length; ++i) {
            address _user = users[i];
            vm.deal(_user, type(uint96).max);

            userProxies[i] = _createLeverageMacro(_user);
            dealCollateral(_user, netColl);
            userCdpIds[i] = _openCDPViaProxy(_user, netColl, userProxies[i]);
        }

        // adjust CDP randomly
        for (uint256 i = 0; i < users.length; ++i) {
            address _user = users[i];
            uint256 _r = _utils.generateRandomNumber(i, MAX_SLIPPAGE, _user);
            if (_r % 3 == 0) {
                // adjust CDP : increase its collateral and debt
                uint256 _additionalColl = (netColl * adjustBps) / MAX_SLIPPAGE;
                dealCollateral(_user, _additionalColl);
                _increaseCDPSizeViaProxy(_user, userCdpIds[i], _additionalColl, userProxies[i]);
                // adjust CDP : decrease its collateral and debt
                uint256 _removedColl = (netColl * (MAX_SLIPPAGE / 2 - adjustBps)) / MAX_SLIPPAGE;
                _descreaseCDPSizeViaProxy(_user, userCdpIds[i], _removedColl, userProxies[i]);
            } else if (_r % 3 == 1) {
                // adjust CDP : increase its collateral and debt
                uint256 _additionalColl = (netColl * adjustBps) / MAX_SLIPPAGE;
                dealCollateral(_user, _additionalColl);
                _increaseCDPSizeViaProxy(_user, userCdpIds[i], _additionalColl, userProxies[i]);
            } else if (_r % 3 == 2) {
                // adjust CDP : decrease its collateral and debt
                uint256 _removedColl = (netColl * (MAX_SLIPPAGE / 2 - adjustBps)) / MAX_SLIPPAGE;
                _descreaseCDPSizeViaProxy(_user, userCdpIds[i], _removedColl, userProxies[i]);
            }
        }

        // close CDP randomly
        for (uint256 i = 0; i < users.length; ++i) {
            address _user = users[i];
            uint256 _r = _utils.generateRandomNumber(i, MAX_SLIPPAGE, _user);
            if (_r % 2 == 0) {
                _closeCDPViaProxy(_user, userCdpIds[i], userProxies[i]);
            }
        }
    }

    function _checkInputFuzzParameters(
        uint256 netColl,
        uint256 adjustBps
    ) internal returns (uint256 _netColl, uint256 _adjustBps) {
        _netColl = bound(netColl, cdpManager.MIN_NET_STETH_BALANCE() * 2 + 1, INITITAL_COLL * 5 - 1);
        _adjustBps = bound(adjustBps, 100 + 1, (MAX_SLIPPAGE / 2) - 1);
    }

    function _openCDPViaProxy(
        address user,
        uint256 netColl,
        address proxyAddr
    ) internal returns (bytes32) {
        uint256 grossColl = netColl + cdpManager.LIQUIDATOR_REWARD();

        vm.startPrank(user);

        // leverage parameters
        uint256 debt = _utils.calculateBorrowAmount(
            grossColl,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );
        LeverageMacroBase.SwapOperation[] memory _levSwapsBefore;
        LeverageMacroBase.SwapOperation[] memory _levSwapsAfter;

        // prepare operation data
        uint256 _cdpDebt = _getTotalAmountForFlashLoan(debt, true);
        LeverageMacroBase.OpenCdpOperation memory _opData = LeverageMacroBase.OpenCdpOperation(
            _cdpDebt,
            DUMMY_CDP_ID,
            DUMMY_CDP_ID,
            grossColl
        );
        bytes memory _opDataEncoded = abi.encode(_opData);
        uint256 _collMinOut = _convertDebtAndCollForSwap(
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
        LeverageMacroBase.LeverageMacroOperation memory operation = LeverageMacroBase
            .LeverageMacroOperation(
                address(collateral),
                (grossColl - _collMinOut),
                _levSwapsBefore,
                _levSwapsAfter,
                LeverageMacroBase.OperationType.OpenCdpOperation,
                _opDataEncoded
            );

        LeverageMacroBase.PostCheckParams memory postCheckParams = _preparePostCheckParams(
            _cdpDebt,
            LeverageMacroBase.Operator.equal,
            netColl,
            LeverageMacroBase.Operator.equal,
            ICdpManagerData.Status.active,
            DUMMY_CDP_ID
        );

        // execute the leverage through proxy
        uint256 cdpCntBefore = sortedCdps.cdpCountOf(proxyAddr);
        _mock1Inch.setPrice(priceFeedMock.getPrice());
        LeverageMacroBase(proxyAddr).doOperation(
            LeverageMacroBase.FlashLoanType.eBTC,
            debt,
            operation,
            LeverageMacroBase.PostOperationCheck.openCdp,
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
        LeverageMacroBase.SwapOperation[] memory _levSwapsBefore;
        LeverageMacroBase.SwapOperation[] memory _levSwapsAfter;
        bytes memory _opDataEncoded;
        uint256 _totalDebt;

        // prepare operation data
        {
            (uint256 _debt, uint256 _totalColl) = cdpManager.getSyncedDebtAndCollShares(cdpId);
            _totalDebt = _debt;
            uint256 _flDebt = _getTotalAmountForFlashLoan(_totalDebt, true);
            LeverageMacroBase.CloseCdpOperation memory _opData = LeverageMacroBase.CloseCdpOperation(
                cdpId
            );
            _opDataEncoded = abi.encode(_opData);
            uint256 _collRequired = _convertDebtAndCollForSwap(
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
        LeverageMacroBase.LeverageMacroOperation memory operation = LeverageMacroBase
            .LeverageMacroOperation(
                address(collateral),
                0,
                _levSwapsBefore,
                _levSwapsAfter,
                LeverageMacroBase.OperationType.CloseCdpOperation,
                _opDataEncoded
            );

        LeverageMacroBase.PostCheckParams memory postCheckParams = _preparePostCheckParams(
            0,
            LeverageMacroBase.Operator.equal,
            0,
            LeverageMacroBase.Operator.equal,
            ICdpManagerData.Status.closedByOwner,
            cdpId
        );

        // execute the leverage through proxy
        _mock1Inch.setPrice(priceFeedMock.getPrice());
        LeverageMacroBase(proxyAddr).doOperation(
            LeverageMacroBase.FlashLoanType.eBTC,
            _totalDebt,
            operation,
            LeverageMacroBase.PostOperationCheck.isClosed,
            postCheckParams
        );

        vm.stopPrank();

        // check system invariants
        _ensureSystemInvariants();
    }

    function _increaseCDPSizeViaProxy(
        address user,
        bytes32 cdpId,
        uint256 _collAdded,
        address proxyAddr
    ) internal {
        vm.startPrank(user);

        // leverage parameters
        LeverageMacroBase.SwapOperation[] memory _levSwapsBefore;
        LeverageMacroBase.SwapOperation[] memory _levSwapsAfter;
        LocalVar_AdjustCdp memory _adjustVars;
        (uint256 _debt, uint256 _totalColl) = cdpManager.getSyncedDebtAndCollShares(cdpId);
        // prepare operation data
        {
            _adjustVars = _increaseCdpSize(cdpId, _totalColl, _collAdded, _debt);
            _levSwapsBefore = _adjustVars._swapSteps;

            LeverageMacroBase.LeverageMacroOperation memory operation = LeverageMacroBase
                .LeverageMacroOperation(
                    address(collateral),
                    _adjustVars._deltaCollAmt,
                    _levSwapsBefore,
                    _levSwapsAfter,
                    LeverageMacroBase.OperationType.AdjustCdpOperation,
                    _adjustVars._opEncoded
                );

            LeverageMacroBase.PostCheckParams memory postCheckParams = _preparePostCheckParams(
                (_debt + _adjustVars._borrowAmt + _adjustVars._borrowFee),
                LeverageMacroBase.Operator.equal,
                (_totalColl + _collAdded),
                LeverageMacroBase.Operator.equal,
                ICdpManagerData.Status.active,
                cdpId
            );

            // execute the leverage through proxy
            _mock1Inch.setPrice(priceFeedMock.getPrice());
            uint256 _collBal = collateral.balanceOf(user);
            LeverageMacroBase(proxyAddr).doOperation(
                LeverageMacroBase.FlashLoanType.eBTC,
                _adjustVars._borrowAmt,
                operation,
                LeverageMacroBase.PostOperationCheck.cdpStats,
                postCheckParams
            );
        }

        vm.stopPrank();

        // check system invariants
        _ensureSystemInvariants();
    }

    function _descreaseCDPSizeViaProxy(
        address user,
        bytes32 cdpId,
        uint256 _collRemoved,
        address proxyAddr
    ) internal {
        vm.startPrank(user);

        // leverage parameters
        LeverageMacroBase.SwapOperation[] memory _levSwapsBefore;
        LeverageMacroBase.SwapOperation[] memory _levSwapsAfter;
        LocalVar_AdjustCdp memory _adjustVars;
        (uint256 _debt, uint256 _totalColl) = cdpManager.getSyncedDebtAndCollShares(cdpId);
        // prepare operation data
        {
            if (
                collateral.getPooledEthByShares(_totalColl - _collRemoved) <=
                cdpManager.MIN_NET_STETH_BALANCE()
            ) {
                uint256 _minShare = collateral.getSharesByPooledEth(
                    cdpManager.MIN_NET_STETH_BALANCE() + 123456789
                );
                require(_totalColl > _minShare, "!CDP is too small to decrease size");
                _collRemoved = _totalColl - _minShare;
            }
            _adjustVars = _decreaseCdpSize(cdpId, _totalColl, _collRemoved, _debt);
            _levSwapsAfter = _adjustVars._swapSteps;

            LeverageMacroBase.LeverageMacroOperation memory operation = LeverageMacroBase
                .LeverageMacroOperation(
                    address(collateral),
                    0,
                    _levSwapsBefore,
                    _levSwapsAfter,
                    LeverageMacroBase.OperationType.AdjustCdpOperation,
                    _adjustVars._opEncoded
                );

            LeverageMacroBase.PostCheckParams memory postCheckParams = _preparePostCheckParams(
                (_debt - _adjustVars._borrowAmt),
                LeverageMacroBase.Operator.equal,
                (_totalColl - _adjustVars._deltaCollAmt),
                LeverageMacroBase.Operator.equal,
                ICdpManagerData.Status.active,
                cdpId
            );

            // execute the leverage through proxy
            _mock1Inch.setPrice(priceFeedMock.getPrice());
            uint256 _collBal = collateral.balanceOf(user);
            LeverageMacroBase(proxyAddr).doOperation(
                LeverageMacroBase.FlashLoanType.eBTC,
                _adjustVars._borrowAmt,
                operation,
                LeverageMacroBase.PostOperationCheck.cdpStats,
                postCheckParams
            );
        }

        vm.stopPrank();

        // check system invariants
        _ensureSystemInvariants();
    }

    struct LocalVar_AdjustCdp {
        bytes _opEncoded;
        LeverageMacroBase.SwapOperation[] _swapSteps;
        uint256 _borrowAmt;
        uint256 _borrowFee;
        uint256 _deltaCollAmt;
    }

    function _increaseCdpSize(
        bytes32 cdpId,
        uint256 _totalColl,
        uint256 _collAdded,
        uint256 _debt
    ) internal view returns (LocalVar_AdjustCdp memory) {
        uint256 _price = priceFeedMock.getPrice();
        uint256 _grossColl = _totalColl + _collAdded;
        uint256 _targetDebt = _utils.calculateBorrowAmount(
            _grossColl,
            _price,
            cdpManager.getCachedICR(cdpId, _price)
        );
        require(_targetDebt > _debt, "!CDP debt already maximized thus can't increase any more");
        uint256 _totalDebt = _targetDebt - _debt;

        uint256 _flDebt = _getTotalAmountForFlashLoan(_totalDebt, true);
        LeverageMacroBase.AdjustCdpOperation memory _opData = LeverageMacroBase.AdjustCdpOperation(
            cdpId,
            0,
            _flDebt,
            true,
            cdpId,
            cdpId,
            _collAdded
        );
        bytes memory _opDataEncoded = abi.encode(_opData);
        uint256 _collMinOut = _convertDebtAndCollForSwap(
            _totalDebt,
            true,
            _acceptedSlippage,
            _price,
            false
        );
        LeverageMacroBase.SwapOperation[] memory _swapSteps = _generateCalldataSwapMock1InchOneStep(
            address(eBTCToken),
            _totalDebt,
            address(collateral),
            _collMinOut
        );
        uint256 _transferInColl = _grossColl - _collMinOut - _totalColl;
        require(
            _transferInColl > 0,
            "!leverage increase CDP transferIn collateral amount can't be zero"
        );
        return
            LocalVar_AdjustCdp(
                _opDataEncoded,
                _swapSteps,
                _totalDebt,
                (_flDebt - _totalDebt),
                _transferInColl
            );
    }

    function _decreaseCdpSize(
        bytes32 cdpId,
        uint256 _totalColl,
        uint256 _collRemoved,
        uint256 _debt
    ) internal view returns (LocalVar_AdjustCdp memory) {
        uint256 _price = priceFeedMock.getPrice();
        uint256 _grossColl = _totalColl - _collRemoved;
        uint256 _targetDebt = _utils.calculateBorrowAmount(
            _grossColl,
            _price,
            cdpManager.getCachedICR(cdpId, _price)
        );
        require(_targetDebt < _debt, "!CDP debt already minimized thus can't decrease any more");
        uint256 _totalDebt = _debt - _targetDebt;

        uint256 _flDebt = _getTotalAmountForFlashLoan(_totalDebt, true);
        uint256 _collWithdrawn = _convertDebtAndCollForSwap(
            _flDebt,
            true,
            _acceptedSlippage,
            _price,
            true
        );
        LeverageMacroBase.AdjustCdpOperation memory _opData = LeverageMacroBase.AdjustCdpOperation(
            cdpId,
            _collWithdrawn,
            _totalDebt,
            false,
            cdpId,
            cdpId,
            0
        );
        bytes memory _opDataEncoded = abi.encode(_opData);
        LeverageMacroBase.SwapOperation[] memory _swapSteps = _generateCalldataSwapMock1InchOneStep(
            address(collateral),
            _collWithdrawn,
            address(eBTCToken),
            _flDebt
        );
        return
            LocalVar_AdjustCdp(
                _opDataEncoded,
                _swapSteps,
                _totalDebt,
                (_flDebt - _totalDebt),
                _collWithdrawn
            );
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

    function _convertDebtAndCollForSwap(
        uint256 _amt,
        bool _fromDebtToColl,
        uint256 _acceptedSlippage,
        uint256 _price,
        bool _addSlippage
    ) internal view returns (uint256) {
        uint256 _raw;
        if (_fromDebtToColl) {
            _raw = (_amt * 1e18) / _price;
        } else {
            _raw = (_amt * _price) / 1e18;
        }
        uint256 _multiplier = _addSlippage
            ? (MAX_SLIPPAGE + _acceptedSlippage)
            : (MAX_SLIPPAGE - _acceptedSlippage);
        return (_raw * _multiplier) / MAX_SLIPPAGE;
    }

    function _preparePostCheckParams(
        uint256 _expectedDebt,
        LeverageMacroBase.Operator _debtOperator,
        uint256 _expectedColl,
        LeverageMacroBase.Operator _collOperator,
        ICdpManagerData.Status _expectedStatus,
        bytes32 _cdpId
    ) internal view returns (LeverageMacroBase.PostCheckParams memory) {
        // confirm debt is expected
        LeverageMacroBase.CheckValueAndType memory expectedDebt = LeverageMacroBase
            .CheckValueAndType(_expectedDebt, _debtOperator);

        // confirm coll is expected
        LeverageMacroBase.CheckValueAndType memory expectedCollateral = LeverageMacroBase
            .CheckValueAndType(_expectedColl, _collOperator);

        return
            LeverageMacroBase.PostCheckParams(
                expectedDebt,
                expectedCollateral,
                _cdpId,
                _expectedStatus
            );
    }

    function _getTotalAmountForFlashLoan(
        uint256 _borrowAmt,
        bool _borrowDebt
    ) internal view returns (uint256) {
        uint256 _fee;
        if (_borrowDebt) {
            _fee = borrowerOperations.flashFee(address(eBTCToken), _borrowAmt);
        } else {
            _fee = activePool.flashFee(address(collateral), _borrowAmt);
        }
        return _borrowAmt + _fee;
    }

    function _createLeverageMacro(address _user) internal returns (address) {
        vm.startPrank(_user);

        LeverageMacroBase proxy = new LeverageMacroReference(
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

    function _createLeverageMacroWithFactory(address _user) internal returns (address) {
        vm.startPrank(_user);

        LeverageMacroFactory factory = new LeverageMacroFactory(
            address(borrowerOperations),
            address(activePool),
            address(cdpManager),
            address(eBTCToken),
            address(collateral),
            address(sortedCdps)
        );

        address proxy = factory.deployNewMacro();

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
}
