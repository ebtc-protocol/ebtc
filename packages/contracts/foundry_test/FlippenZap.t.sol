// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {console2 as console} from "forge-std/console2.sol";

import {FlippenZap} from "../contracts/FlippenZap.sol";

import {eBTCBaseInvariants} from "./BaseInvariants.sol";
import {MockBalancer} from "../contracts/TestContracts/MockBalancer.sol";
import {IPositionManagers} from "../contracts/Interfaces/IPositionManagers.sol";

contract FlippenZapTest is eBTCBaseInvariants {
    uint256 public _acceptedSlippage = 50;
    uint256 public constant MAX_SLIPPAGE = 10000;
    bytes32 public constant DUMMY_CDP_ID = bytes32(0);
    uint256 public constant INITITAL_COLL = 10000 ether;

    FlippenZap flippenZap;
    MockBalancer mockBalancer;

    function setUp() public override {
        super.setUp();

        connectCoreContracts();
        connectLQTYContractsToCore();

        mockBalancer = new MockBalancer(address(eBTCToken), address(collateral));
        _setupSwapDex(address(mockBalancer));
        bytes32 _whateverPoolId = sortedCdps.getFirst();

        flippenZap = new FlippenZap(
            address(borrowerOperations),
            address(priceFeedMock),
            address(cdpManager),
            address(collateral),
            address(eBTCToken),
            address(mockBalancer),
            _whateverPoolId
        );
    }

    function test_ZapEnterLongBtc_Single(uint256 _collAmt) public {
        // do some clamp on leverage parameter
        _collAmt = bound(_collAmt, 2.2e18, INITITAL_COLL);

        address payable[] memory _testUsrs = _utils.createUsers(1);
        address payable _testUsr = _testUsrs[0];

        dealCollateral(_testUsr, _collAmt * 2);

        vm.startPrank(_testUsr);
        collateral.approve(address(flippenZap), type(uint256).max);
        uint256 _balBefore = eBTCToken.balanceOf(_testUsr);
        uint256 _swapped = flippenZap.enterLongBtc(_collAmt);
        uint256 _balAfter = eBTCToken.balanceOf(_testUsr);
        assertTrue(_balAfter == _balBefore + _swapped);
        vm.stopPrank();

        // decrease slippage of FlippenZap
        address _zapOwner = flippenZap.owner();
        uint256 _newSlippage = mockBalancer.slippage() / 2;
        vm.prank(_zapOwner);
        flippenZap.setSlippage(_newSlippage);
        assertTrue(flippenZap.slippage() == _newSlippage);

        // expect a swap revert
        vm.prank(_testUsr);
        vm.expectRevert("MockBalancer: below expected limit!");
        flippenZap.enterLongBtc(_collAmt);
    }

    function test_ZapEnterLongEth_Single(uint256 _collAmt, uint256 _leverage) public {
        // do some clamp on leverage parameter
        _leverage = bound(_leverage, 1, flippenZap.MAX_REASONABLE_LEVERAGE());
        _collAmt = bound(_collAmt, 2.2e18, INITITAL_COLL);

        address payable[] memory _testUsrs = _utils.createUsers(1);
        address payable _testUsr = _testUsrs[0];

        _zapOneLongEth(_testUsr, _collAmt, _leverage);
    }

    function test_ZapEnterLongEth_TripleZaps(uint256 _collAmt, uint256 _leverage) public {
        // do some clamp on leverage parameter
        _leverage = bound(_leverage, 1, flippenZap.MAX_REASONABLE_LEVERAGE());
        _collAmt = bound(_collAmt, 2.2e18, INITITAL_COLL);
        _leverage = 2;
        _collAmt = 2.2e18;

        address payable[] memory _testUsrs = _utils.createUsers(1);
        address payable _testUsr = _testUsrs[0];

        // First Zap
        _zapOneLongEth(_testUsr, _collAmt, _leverage);

        // open another CDP withour normally without FlippenZap
        _openTestCdpAtICR(_testUsr, flippenZap.MIN_NET_STETH_BALANCE(), COLLATERAL_RATIO_DEFENSIVE);
        // Second Zap
        _zapOneLongEth(_testUsr, _collAmt + flippenZap.MIN_NET_STETH_BALANCE(), _leverage);

        // open another CDP withour normally without FlippenZap
        _openTestCdpAtICR(_testUsr, flippenZap.MIN_NET_STETH_BALANCE(), COLLATERAL_RATIO_DEFENSIVE);
        // Third Zap
        _zapOneLongEth(_testUsr, _collAmt + flippenZap.MIN_NET_STETH_BALANCE() * 2, _leverage);
    }

    function test_ZapEnterLongEth_MultipleUsers(uint256 _collAmt, uint256 _leverage) public {
        // do some clamp on leverage parameter
        _leverage = bound(_leverage, 1, flippenZap.MAX_REASONABLE_LEVERAGE());
        _collAmt = bound(_collAmt, 2.2e18, INITITAL_COLL);
        _leverage = 5;
        _collAmt = INITITAL_COLL;

        address payable[] memory _testUsrs = _utils.createUsers(2);
        address payable _testUsr = _testUsrs[0];
        address payable _testUsr2 = _testUsrs[1];

        // First Zap
        _zapOneLongEth(_testUsr, _collAmt, _leverage);
        _zapOneLongEth(_testUsr2, _collAmt, _leverage);

        // open another CDP withour normally without FlippenZap
        _openTestCdpAtICR(_testUsr, flippenZap.MIN_NET_STETH_BALANCE(), COLLATERAL_RATIO_DEFENSIVE);
        _openTestCdpAtICR(_testUsr2, flippenZap.MIN_NET_STETH_BALANCE(), COLLATERAL_RATIO_DEFENSIVE);
        // Second Zap
        _zapOneLongEth(_testUsr, _collAmt + flippenZap.MIN_NET_STETH_BALANCE(), _leverage);
        _zapOneLongEth(_testUsr2, _collAmt + flippenZap.MIN_NET_STETH_BALANCE(), _leverage);

        // open another CDP withour normally without FlippenZap
        _openTestCdpAtICR(_testUsr, flippenZap.MIN_NET_STETH_BALANCE(), COLLATERAL_RATIO_DEFENSIVE);
        _openTestCdpAtICR(_testUsr2, flippenZap.MIN_NET_STETH_BALANCE(), COLLATERAL_RATIO_DEFENSIVE);
        // Third Zap
        _zapOneLongEth(_testUsr, _collAmt + flippenZap.MIN_NET_STETH_BALANCE() * 2, _leverage);
        _zapOneLongEth(_testUsr2, _collAmt + flippenZap.MIN_NET_STETH_BALANCE() * 2, _leverage);
    }

    function _zapOneLongEth(address _testUsr, uint256 _collAmt, uint256 _leverage) public {
        dealCollateral(_testUsr, _collAmt);

        uint256 _debtBefore = eBTCToken.balanceOf(_testUsr);
        vm.startPrank(_testUsr);
        collateral.approve(address(flippenZap), type(uint256).max);
        borrowerOperations.setPositionManagerApproval(
            address(flippenZap),
            IPositionManagers.PositionManagerApproval.Persistent
        ); // Permanent
        uint256 _cdpCountBefore = sortedCdps.cdpCountOf(_testUsr);
        bytes32 _cdpId = flippenZap.enterLongEth(_collAmt, _leverage);
        uint256 _cdpCountAfter = sortedCdps.cdpCountOf(_testUsr);
        vm.stopPrank();

        // ensure the leveraged Cdp is created successfully
        assertTrue(_cdpCountAfter == _cdpCountBefore + 1);
        assertTrue(_cdpId != DUMMY_CDP_ID);
        assertTrue(sortedCdps.getOwnerAddress(_cdpId) == _testUsr);

        // ensure status is good
        uint256 _debtAfter = eBTCToken.balanceOf(_testUsr);
        if (_leverage > 1) {
            // there is a new leveraged CDP created for user
            assertTrue(_debtBefore == _debtAfter);
            (, , , uint256 _liquidatorRewardShares, , ) = cdpManager.Cdps(_cdpId);
            uint256 _cdpColl = collateral.getPooledEthByShares(
                cdpManager.getSyncedCdpCollShares(_cdpId)
            );
            uint256 _leveraged = (_collAmt - _liquidatorRewardShares) * _leverage;
            console.log("_leveraged:", _leveraged);
            console.log("_cdpColl:", _cdpColl);
            uint256 _diffRatioScaled = ((_leveraged - _cdpColl) * 1e18) / _leveraged;
            console.log("_diffRatioScaled:", _diffRatioScaled);
            uint256 _slippageScaled = (mockBalancer.slippage() * 1e18) / mockBalancer.MAX_SLIPPAGE();
            assertTrue(_diffRatioScaled <= _slippageScaled);
        } else {
            // TODO minted eBTC sent directly to user?
            uint256 _cdpDebt = cdpManager.getSyncedCdpDebt(_cdpId);
            assertTrue(_cdpDebt + _debtBefore == _debtAfter);
        }
    }

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
}
