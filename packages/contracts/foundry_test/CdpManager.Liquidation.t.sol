// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.11;

import {console2 as console} from "forge-std/console2.sol";

import {eBTCBaseFixture} from "./BaseFixture.sol";
import {Utilities} from "./utils/Utilities.sol";

contract CdpManagerLiquidationTest is eBTCBaseFixture {
    struct CdpState {
        uint256 debt;
        uint256 coll;
        uint256 pendingEBTCDebtReward;
        uint256 pendingEBTCInterest;
        uint256 pendingETHReward;
    }

    address payable[] users;

    Utilities internal _utils;

    uint public constant DECIMAL_PRECISION = 1e18;

    ////////////////////////////////////////////////////////////////////////////
    // Helper functions
    ////////////////////////////////////////////////////////////////////////////

    function _getEntireDebtAndColl(bytes32 cdpId) internal view returns (CdpState memory) {
        (
            uint256 debt,
            uint256 coll,
            uint256 pendingEBTCDebtReward,
            uint256 pendingEBTCDebtInterest,
            uint256 pendingETHReward
        ) = cdpManager.getEntireDebtAndColl(cdpId);
        return
            CdpState(debt, coll, pendingEBTCDebtReward, pendingEBTCDebtInterest, pendingETHReward);
    }

    ////////////////////////////////////////////////////////////////////////////
    // Tests
    ////////////////////////////////////////////////////////////////////////////

    function setUp() public override {
        eBTCBaseFixture.setUp();

        eBTCBaseFixture.connectLQTYContracts();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();

        _utils = new Utilities();
        users = _utils.createUsers(1);
    }

    // Test single CDP liquidation with price fluctuation
    function testLiquidateSingleCDP(uint256 price, uint256 debtAmt) public {
        vm.assume(debtAmt > 2000e18);
        vm.assume(debtAmt < 200000000e18);

        uint _curPrice = priceFeedMock.getPrice();
        vm.assume(_curPrice > price * 2);

        uint256 coll1 = _utils.calculateCollAmount(debtAmt, _curPrice, 297e16);

        vm.startPrank(users[0]);
        borrowerOperations.openCdp{value: 100 ether}(
            DECIMAL_PRECISION,
            _utils.calculateBorrowAmountFromDebt(
                2001e18,
                cdpManager.EBTC_GAS_COMPENSATION(),
                cdpManager.getBorrowingRateWithDecay()
            ),
            bytes32(0),
            bytes32(0)
        );
        bytes32 cdpId1 = borrowerOperations.openCdp{value: coll1}(
            DECIMAL_PRECISION,
            _utils.calculateBorrowAmountFromDebt(
                debtAmt,
                cdpManager.EBTC_GAS_COMPENSATION(),
                cdpManager.getBorrowingRateWithDecay()
            ),
            bytes32(0),
            bytes32(0)
        );
        vm.stopPrank();

        // accrue some interest before liquidation
        skip(365 days);

        // Price falls
        priceFeedMock.setPrice(price);

        // Liquidate cdp1
        uint _TCR = cdpManager.getTCR(price);
        uint _ICR = cdpManager.getCurrentICR(cdpId1, price);
        bool _recoveryMode = _TCR < cdpManager.CCR();
        if (_ICR < cdpManager.MCR() || (_recoveryMode && _ICR < _TCR)) {
            CdpState memory _cdpState = _getEntireDebtAndColl(cdpId1);
            deal(address(eBTCToken), users[0], _cdpState.debt); // sugardaddy liquidator
            vm.prank(users[0]);
            cdpManager.liquidate(cdpId1);

            // target CDP got liquidated
            assertFalse(sortedCdps.contains(cdpId1));

            // check state is closedByLiquidation
            assertTrue(cdpManager.getCdpStatus(cdpId1) == 3);
        }
    }
}
