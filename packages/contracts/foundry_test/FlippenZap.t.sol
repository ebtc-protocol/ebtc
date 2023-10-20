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

    function test_ZapEnterLongEth(uint256 _collAmt, uint256 _leverage) public {
        // do some clamp on leverage parameter
        _leverage = bound(_leverage, 1, flippenZap.MAX_REASONABLE_LEVERAGE());
        _collAmt = bound(_collAmt, 2.2e18, INITITAL_COLL);

        address payable[] memory _testUsrs = _utils.createUsers(1);
        address payable _testUsr = _testUsrs[0];

        dealCollateral(_testUsr, _collAmt);

        uint256 _debtBefore = eBTCToken.balanceOf(_testUsr);
        vm.startPrank(_testUsr);
        collateral.approve(address(flippenZap), type(uint256).max);
        borrowerOperations.setPositionManagerApproval(
            address(flippenZap),
            IPositionManagers.PositionManagerApproval.Persistent
        ); // Permanent
        bytes32 _cdpId = flippenZap.enterLongEth(_collAmt, _leverage);
        vm.stopPrank();

        // ensure the leveraged Cdp is created
        assertTrue(_cdpId != DUMMY_CDP_ID);
        assertTrue(sortedCdps.getOwnerAddress(_cdpId) == _testUsr);

        // ensure status is good
        uint256 _debtAfter = eBTCToken.balanceOf(_testUsr);
        if (_leverage > 1) {
            // only one leveraged CDP left to user
            assertTrue(_debtBefore == _debtAfter);
            uint256 _cdpColl = collateral.getPooledEthByShares(
                cdpManager.getSyncedCdpCollShares(_cdpId)
            );
            uint256 _leveraged = _collAmt * _leverage;
            console.log("_leveraged:", _leveraged);
            console.log("_cdpColl:", _cdpColl);
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
