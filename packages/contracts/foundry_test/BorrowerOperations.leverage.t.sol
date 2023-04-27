// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;
pragma experimental ABIEncoderV2;

import "forge-std/Test.sol";
import {eBTCBaseInvariants} from "./BaseInvariants.sol";

/*
 * Test suite that tests exactly one thing: opening CDPs
 * It tests different cases and also does random testing against random coll amounts and amount of users
 */
contract LeverageOpenCdpTest is eBTCBaseInvariants {
    mapping(bytes32 => bool) private _cdpIdsExist;

    function setUp() public override {
        super.setUp();
        connectCoreContracts();
        connectLQTYContractsToCore();
    }

    // Generic test for happy case when 1 user open CDP
    function test_OpenCDPForSelfHappy() public {
        address payable[] memory users;
        users = _utils.createUsers(1);
        address user = users[0];
        vm.startPrank(user);
        vm.deal(user, type(uint96).max);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 10000 ether}();
        uint borrowedAmount = _utils.calculateBorrowAmount(
            30 ether,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );
        // Make sure there is no CDPs in the system yet
        assert(sortedCdps.getLast() == "");

        borrowerOperations.openCdpFor(borrowedAmount, "hint", "hint", 30 ether, user);

        vm.stopPrank();
    }

    // Test using LeverageMacro to open leveraged CDP
    function test_OpenLeverageCDP(uint256 _initColl) public {
        address payable[] memory users;
        users = _utils.createUsers(1);
        address user = users[0];
        uint _price = priceFeedMock.fetchPrice();

        uint _expectedSlippage = mockDex.slippage() * 2;
        uint _slippageMax = mockDex.MAX_SLIPPAGE();
        uint _leverageScale = leverageMacro.MAX_BPS();
        uint _icr = COLLATERAL_RATIO;
        uint _gasDebtComp = borrowerOperations.EBTC_GAS_COMPENSATION(); // to be removed?
        uint _maxLeverageBPS = leverageMacro.maxLeverageBPS();
        uint _leverageBuffer = _maxLeverageBPS / 2;
        vm.assume(_initColl > 1e18);
        vm.assume(_initColl < (type(uint128).max / _maxLeverageBPS));

        // adjust expected collateral to deposit according to expected debt
        uint _totalColl = ((_maxLeverageBPS - _leverageBuffer) * _initColl) / _leverageScale;
        uint _totalDebt = _utils.calculateBorrowAmount(_totalColl, _price, _icr) - _gasDebtComp;
        _totalColl =
            ((((_totalDebt * 1e18) / _price) * (_slippageMax - _expectedSlippage)) / _slippageMax) +
            _initColl;

        // open leverage CDP
        dealCollateral(user, _initColl);
        vm.startPrank(user);
        collateral.approve(address(leverageMacro), type(uint256).max);
        eBTCToken.approve(address(leverageMacro), type(uint256).max);
        (bytes32 _leveragedCdpId, uint256 _fee) = leverageMacro.openCdpLeveraged(
            _totalDebt,
            "hint",
            "hint",
            _totalColl
        );
        vm.stopPrank();

        // Make sure everything works as expected
        assert(sortedCdps.getOwnerAddress(_leveragedCdpId) == user);
        assertEq(cdpManager.getCdpColl(_leveragedCdpId), _totalColl, "!leveraged Cdp coll");
        assertEq(
            cdpManager.getCdpDebt(_leveragedCdpId),
            (_totalDebt + _fee + _gasDebtComp),
            "!leveraged Cdp debt"
        );

        // ensure leveraged CDP keep system invariants
        _ensureSystemInvariants();
    }
}
