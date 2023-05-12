// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;
import "forge-std/Test.sol";
import {eBTCBaseInvariants} from "./BaseInvariants.sol";
import {LeverageMacroReference} from "../contracts/LeverageMacroReference.sol";
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
        _checkInputFuzzParameters(netColl, 1000);

        // deploy proxy for user
        address proxyAddr = _createLeverageMacro(user);

        // open CDP
        dealCollateral(user, netColl);
        _openCDPViaProxy(user, netColl, proxyAddr);
    }

    function test_AdjustLeveragedCDPHappy(uint netColl, uint adjustBps) public {
        address user = _utils.createUsers(1)[0];

        vm.deal(user, type(uint96).max);

        // check input
        _checkInputFuzzParameters(netColl, adjustBps);

        // deploy proxy for user
        address proxyAddr = _createLeverageMacro(user);

        // open CDP
        dealCollateral(user, netColl);
        bytes32 cdpId = _openCDPViaProxy(user, netColl, proxyAddr);

        // adjust CDP : increase its collateral and debt
        uint _additionalColl = (netColl * adjustBps) / MAX_SLIPPAGE;
        dealCollateral(user, _additionalColl);
        _increaseCDPSizeViaProxy(user, cdpId, _additionalColl, proxyAddr);

        // adjust CDP : decrease its collateral and debt
        uint _removedColl = (netColl * (MAX_SLIPPAGE / 2 - adjustBps)) / MAX_SLIPPAGE;
        _descreaseCDPSizeViaProxy(user, cdpId, _removedColl, proxyAddr);
    }

    function test_OpenAndCloseLeveragedCDPHappy(uint netColl) public {
        address user = _utils.createUsers(1)[0];

        vm.deal(user, type(uint96).max);

        // check input
        _checkInputFuzzParameters(netColl, 1000);

        // deploy proxy for user
        address proxyAddr = _createLeverageMacro(user);

        // open CDP
        dealCollateral(user, netColl);
        bytes32 cdpId = _openCDPViaProxy(user, netColl, proxyAddr);

        // close CDP
        _closeCDPViaProxy(user, cdpId, proxyAddr);
    }

    function test_MultipleUserLeveragedCDPHappy(uint userCnt, uint netColl, uint adjustBps) public {
        // check input
        _checkInputFuzzParameters(netColl, adjustBps);
        vm.assume(userCnt > 1);
        vm.assume(userCnt < 5);

        address payable[] memory users = _utils.createUsers(userCnt);

        // deploy proxy for user and open CDP
        address[] memory userProxies = new address[](userCnt);
        bytes32[] memory userCdpIds = new bytes32[](userCnt);
        for (uint i = 0; i < users.length; ++i) {
            address _user = users[i];
            vm.deal(_user, type(uint96).max);

            userProxies[i] = _createLeverageMacro(_user);
            dealCollateral(_user, netColl);
            userCdpIds[i] = _openCDPViaProxy(_user, netColl, userProxies[i]);
        }

        // adjust CDP randomly
        for (uint i = 0; i < users.length; ++i) {
            address _user = users[i];
            uint _r = _utils.generateRandomNumber(i, MAX_SLIPPAGE, _user);
            if (_r % 3 == 0) {
                // adjust CDP : increase its collateral and debt
                uint _additionalColl = (netColl * adjustBps) / MAX_SLIPPAGE;
                dealCollateral(_user, _additionalColl);
                _increaseCDPSizeViaProxy(_user, userCdpIds[i], _additionalColl, userProxies[i]);
                // adjust CDP : decrease its collateral and debt
                uint _removedColl = (netColl * (MAX_SLIPPAGE / 2 - adjustBps)) / MAX_SLIPPAGE;
                _descreaseCDPSizeViaProxy(_user, userCdpIds[i], _removedColl, userProxies[i]);
            } else if (_r % 3 == 1) {
                // adjust CDP : increase its collateral and debt
                uint _additionalColl = (netColl * adjustBps) / MAX_SLIPPAGE;
                dealCollateral(_user, _additionalColl);
                _increaseCDPSizeViaProxy(_user, userCdpIds[i], _additionalColl, userProxies[i]);
            } else if (_r % 3 == 2) {
                // adjust CDP : decrease its collateral and debt
                uint _removedColl = (netColl * (MAX_SLIPPAGE / 2 - adjustBps)) / MAX_SLIPPAGE;
                _descreaseCDPSizeViaProxy(_user, userCdpIds[i], _removedColl, userProxies[i]);
            }
        }

        // close CDP randomly
        for (uint i = 0; i < users.length; ++i) {
            address _user = users[i];
            uint _r = _utils.generateRandomNumber(i, MAX_SLIPPAGE, _user);
            if (_r % 2 == 0) {
                _closeCDPViaProxy(_user, userCdpIds[i], userProxies[i]);
            }
        }
    }

    function _checkInputFuzzParameters(uint netColl, uint adjustBps) internal {
        vm.assume(netColl < INITITAL_COLL * 5);
        vm.assume(netColl > cdpManager.MIN_NET_COLL() * 2);
        vm.assume(adjustBps < (MAX_SLIPPAGE / 2));
        vm.assume(adjustBps > 100);
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
        LeverageMacroReference.SwapOperation[] memory _levSwapsBefore;
        LeverageMacroReference.SwapOperation[] memory _levSwapsAfter;

        // prepare operation data
        uint _cdpDebt = _getTotalAmountForFlashLoan(debt, true);
        LeverageMacroReference.OpenCdpOperation memory _opData = LeverageMacroReference.OpenCdpOperation(
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
        LeverageMacroReference.LeverageMacroOperation memory operation = LeverageMacroReference.LeverageMacroOperation(
            address(collateral),
            (grossColl - _collMinOut),
            _levSwapsBefore,
            _levSwapsAfter,
            LeverageMacroReference.OperationType.OpenCdpOperation,
            _opDataEncoded
        );

        LeverageMacroReference.PostCheckParams memory postCheckParams = _preparePostCheckParams(
            _cdpDebt,
            LeverageMacroReference.Operator.equal,
            netColl,
            LeverageMacroReference.Operator.equal,
            ICdpManagerData.Status.active,
            DUMMY_CDP_ID
        );

        // execute the leverage through proxy
        uint cdpCntBefore = sortedCdps.cdpCountOf(proxyAddr);
        _mock1Inch.setPrice(priceFeedMock.getPrice());
        LeverageMacroReference(proxyAddr).doOperation(
            LeverageMacroReference.FlashLoanType.eBTC,
            debt,
            operation,
            LeverageMacroReference.PostOperationCheck.openCdp,
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
        LeverageMacroReference.SwapOperation[] memory _levSwapsBefore;
        LeverageMacroReference.SwapOperation[] memory _levSwapsAfter;
        bytes memory _opDataEncoded;
        uint _totalDebt;

        // prepare operation data
        {
            (uint _debt, uint _totalColl, , ) = cdpManager.getEntireDebtAndColl(cdpId);
            _totalDebt = _debt;
            uint _flDebt = _getTotalAmountForFlashLoan(_totalDebt, true);
            LeverageMacroReference.CloseCdpOperation memory _opData = LeverageMacroReference.CloseCdpOperation(cdpId);
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
        LeverageMacroReference.LeverageMacroOperation memory operation = LeverageMacroReference.LeverageMacroOperation(
            address(collateral),
            0,
            _levSwapsBefore,
            _levSwapsAfter,
            LeverageMacroReference.OperationType.CloseCdpOperation,
            _opDataEncoded
        );

        LeverageMacroReference.PostCheckParams memory postCheckParams = _preparePostCheckParams(
            0,
            LeverageMacroReference.Operator.equal,
            0,
            LeverageMacroReference.Operator.equal,
            ICdpManagerData.Status.closedByOwner,
            cdpId
        );

        // execute the leverage through proxy
        _mock1Inch.setPrice(priceFeedMock.getPrice());
        LeverageMacroReference(proxyAddr).doOperation(
            LeverageMacroReference.FlashLoanType.eBTC,
            _totalDebt,
            operation,
            LeverageMacroReference.PostOperationCheck.isClosed,
            postCheckParams
        );

        vm.stopPrank();

        // check system invariants
        _ensureSystemInvariants();
    }

    function _increaseCDPSizeViaProxy(
        address user,
        bytes32 cdpId,
        uint _collAdded,
        address proxyAddr
    ) internal {
        vm.startPrank(user);

        // leverage parameters
        LeverageMacroReference.SwapOperation[] memory _levSwapsBefore;
        LeverageMacroReference.SwapOperation[] memory _levSwapsAfter;
        LocalVar_AdjustCdp memory _adjustVars;
        (uint _debt, uint _totalColl, , ) = cdpManager.getEntireDebtAndColl(cdpId);
        // prepare operation data
        {
            _adjustVars = _increaseCdpSize(cdpId, _totalColl, _collAdded, _debt);
            _levSwapsBefore = _adjustVars._swapSteps;

            LeverageMacroReference.LeverageMacroOperation memory operation = LeverageMacroReference
                .LeverageMacroOperation(
                    address(collateral),
                    _adjustVars._deltaCollAmt,
                    _levSwapsBefore,
                    _levSwapsAfter,
                    LeverageMacroReference.OperationType.AdjustCdpOperation,
                    _adjustVars._opEncoded
                );

            LeverageMacroReference.PostCheckParams memory postCheckParams = _preparePostCheckParams(
                (_debt + _adjustVars._borrowAmt + _adjustVars._borrowFee),
                LeverageMacroReference.Operator.equal,
                (_totalColl + _collAdded),
                LeverageMacroReference.Operator.equal,
                ICdpManagerData.Status.active,
                cdpId
            );

            // execute the leverage through proxy
            _mock1Inch.setPrice(priceFeedMock.getPrice());
            uint _collBal = collateral.balanceOf(user);
            LeverageMacroReference(proxyAddr).doOperation(
                LeverageMacroReference.FlashLoanType.eBTC,
                _adjustVars._borrowAmt,
                operation,
                LeverageMacroReference.PostOperationCheck.cdpStats,
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
        uint _collRemoved,
        address proxyAddr
    ) internal {
        vm.startPrank(user);

        // leverage parameters
        LeverageMacroReference.SwapOperation[] memory _levSwapsBefore;
        LeverageMacroReference.SwapOperation[] memory _levSwapsAfter;
        LocalVar_AdjustCdp memory _adjustVars;
        (uint _debt, uint _totalColl, , ) = cdpManager.getEntireDebtAndColl(cdpId);
        // prepare operation data
        {
            if (
                collateral.getPooledEthByShares(_totalColl - _collRemoved) <=
                cdpManager.MIN_NET_COLL()
            ) {
                uint _minShare = collateral.getSharesByPooledEth(
                    cdpManager.MIN_NET_COLL() + 123456789
                );
                require(_totalColl > _minShare, "!CDP is too small to decrease size");
                _collRemoved = _totalColl - _minShare;
            }
            _adjustVars = _decreaseCdpSize(cdpId, _totalColl, _collRemoved, _debt);
            _levSwapsAfter = _adjustVars._swapSteps;

            LeverageMacroReference.LeverageMacroOperation memory operation = LeverageMacroReference
                .LeverageMacroOperation(
                    address(collateral),
                    0,
                    _levSwapsBefore,
                    _levSwapsAfter,
                    LeverageMacroReference.OperationType.AdjustCdpOperation,
                    _adjustVars._opEncoded
                );

            LeverageMacroReference.PostCheckParams memory postCheckParams = _preparePostCheckParams(
                (_debt - _adjustVars._borrowAmt),
                LeverageMacroReference.Operator.equal,
                (_totalColl - _adjustVars._deltaCollAmt),
                LeverageMacroReference.Operator.equal,
                ICdpManagerData.Status.active,
                cdpId
            );

            // execute the leverage through proxy
            _mock1Inch.setPrice(priceFeedMock.getPrice());
            uint _collBal = collateral.balanceOf(user);
            LeverageMacroReference(proxyAddr).doOperation(
                LeverageMacroReference.FlashLoanType.eBTC,
                _adjustVars._borrowAmt,
                operation,
                LeverageMacroReference.PostOperationCheck.cdpStats,
                postCheckParams
            );
        }

        vm.stopPrank();

        // check system invariants
        _ensureSystemInvariants();
    }

    struct LocalVar_AdjustCdp {
        bytes _opEncoded;
        LeverageMacroReference.SwapOperation[] _swapSteps;
        uint _borrowAmt;
        uint _borrowFee;
        uint _deltaCollAmt;
    }

    function _increaseCdpSize(
        bytes32 cdpId,
        uint _totalColl,
        uint _collAdded,
        uint _debt
    ) internal view returns (LocalVar_AdjustCdp memory) {
        uint _price = priceFeedMock.getPrice();
        uint _grossColl = _totalColl + _collAdded;
        uint _targetDebt = _utils.calculateBorrowAmount(
            _grossColl,
            _price,
            cdpManager.getCurrentICR(cdpId, _price)
        );
        require(_targetDebt > _debt, "!CDP debt already maximized thus can't increase any more");
        uint _totalDebt = _targetDebt - _debt;

        uint _flDebt = _getTotalAmountForFlashLoan(_totalDebt, true);
        LeverageMacroReference.AdjustCdpOperation memory _opData = LeverageMacroReference.AdjustCdpOperation(
            cdpId,
            0,
            _flDebt,
            true,
            cdpId,
            cdpId,
            _collAdded
        );
        bytes memory _opDataEncoded = abi.encode(_opData);
        uint _collMinOut = _convertDebtAndCollForSwap(
            _totalDebt,
            true,
            _acceptedSlippage,
            _price,
            false
        );
        LeverageMacroReference.SwapOperation[] memory _swapSteps = _generateCalldataSwapMock1InchOneStep(
            address(eBTCToken),
            _totalDebt,
            address(collateral),
            _collMinOut
        );
        uint _transferInColl = _grossColl - _collMinOut - _totalColl;
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
        uint _totalColl,
        uint _collRemoved,
        uint _debt
    ) internal view returns (LocalVar_AdjustCdp memory) {
        uint _price = priceFeedMock.getPrice();
        uint _grossColl = _totalColl - _collRemoved;
        uint _targetDebt = _utils.calculateBorrowAmount(
            _grossColl,
            _price,
            cdpManager.getCurrentICR(cdpId, _price)
        );
        require(_targetDebt < _debt, "!CDP debt already minimized thus can't decrease any more");
        uint _totalDebt = _debt - _targetDebt;

        uint _flDebt = _getTotalAmountForFlashLoan(_totalDebt, true);
        uint _collWithdrawn = _convertDebtAndCollForSwap(
            _flDebt,
            true,
            _acceptedSlippage,
            _price,
            true
        );
        LeverageMacroReference.AdjustCdpOperation memory _opData = LeverageMacroReference.AdjustCdpOperation(
            cdpId,
            _collWithdrawn,
            _totalDebt,
            false,
            cdpId,
            cdpId,
            0
        );
        bytes memory _opDataEncoded = abi.encode(_opData);
        LeverageMacroReference.SwapOperation[] memory _swapSteps = _generateCalldataSwapMock1InchOneStep(
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
        uint _minOut
    ) internal view returns (LeverageMacroReference.SwapOperation memory) {
        LeverageMacroReference.SwapCheck[] memory _swapChecks = new LeverageMacroReference.SwapCheck[](1);
        _swapChecks[0] = LeverageMacroReference.SwapCheck(_outToken, _minOut);

        bytes memory _swapData = abi.encodeWithSelector(
            Mock1Inch.swap.selector,
            _inToken,
            _outToken,
            _inAmt
        );
        return
            LeverageMacroReference.SwapOperation(
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
    ) internal view returns (LeverageMacroReference.SwapOperation[] memory) {
        LeverageMacroReference.SwapOperation[] memory _oneStep = new LeverageMacroReference.SwapOperation[](1);
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
        LeverageMacroReference.Operator _debtOperator,
        uint _expectedColl,
        LeverageMacroReference.Operator _collOperator,
        ICdpManagerData.Status _expectedStatus,
        bytes32 _cdpId
    ) internal view returns (LeverageMacroReference.PostCheckParams memory) {
        // confirm debt is expected
        LeverageMacroReference.CheckValueAndType memory expectedDebt = LeverageMacroReference.CheckValueAndType(
            _expectedDebt,
            _debtOperator
        );

        // confirm coll is expected
        LeverageMacroReference.CheckValueAndType memory expectedCollateral = LeverageMacroReference.CheckValueAndType(
            _expectedColl,
            _collOperator
        );

        return
            LeverageMacroReference.PostCheckParams(expectedDebt, expectedCollateral, _cdpId, _expectedStatus);
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

        LeverageMacroReference proxy = new LeverageMacroReference(
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
