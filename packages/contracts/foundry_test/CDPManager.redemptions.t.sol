// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "../contracts/Dependencies/LiquityMath.sol";
import {eBTCBaseInvariants} from "./BaseInvariants.sol";

contract CDPManagerRedemptionsTest is eBTCBaseInvariants {
    // Storage array of cdpIDs when impossible to calculate array size
    bytes32[] cdpIds;
    uint public mintAmount = 1e18;

    function setUp() public override {
        super.setUp();
        connectCoreContracts();
        connectLQTYContractsToCore();
        vm.warp(3 weeks);
    }

    function testCDPManagerSetMinuteDecayFactorDecaysBaseRate() public {
        uint newMinuteDecayFactor = (500 + 999037758833783000);
        uint timePassed = 600; // seconds/60 => minute

        address user = _utils.getNextUserAddress();

        // Grant permission
        vm.prank(defaultGovernance);
        authority.setUserRole(user, 3, true);

        collateral.approve(address(borrowerOperations), type(uint256).max);

        assertEq(cdpManager.getBorrowingRateWithDecay(), 0);

        uint debt = 2e17;

        console.log("debt %s", debt);

        bytes32 cdpId1 = _openTestCDP(user, 10000 ether, debt);

        vm.startPrank(user);
        assertEq(cdpManager.getBorrowingRateWithDecay(), 0);

        // Set minute decay factor
        cdpManager.setMinuteDecayFactor(newMinuteDecayFactor);

        // Confirm variable set
        assertEq(cdpManager.minuteDecayFactor(), newMinuteDecayFactor);

        // Set the initial baseRate to a non-zero value via rdemption
        console.log("balance: %s", eBTCToken.balanceOf(user));
        eBTCToken.approve(address(cdpManager), type(uint256).max);
        uint _redeemDebt = 1;
        (bytes32 firstRedemptionHint, uint partialRedemptionHintNICR, , ) = hintHelpers
            .getRedemptionHints(_redeemDebt, (priceFeedMock.fetchPrice()), 0);
        cdpManager.redeemCollateral(
            _redeemDebt,
            firstRedemptionHint,
            bytes32(0),
            bytes32(0),
            partialRedemptionHintNICR,
            0,
            1e18
        );

        uint initialRate = cdpManager.baseRate();

        console.log("baseRate: %s", cdpManager.baseRate());

        // Calculate the expected decayed base rate
        uint decayFactor = cdpManager.minuteDecayFactor();
        console.log("decayFactor: %s", decayFactor);
        uint _decayMultiplier = _decPow(decayFactor, (timePassed / 60));
        console.log("_decayMultiplier: %s", _decayMultiplier);
        uint expectedDecayedBaseRate = (initialRate * _decayMultiplier) /
            cdpManager.DECIMAL_PRECISION();

        // Fast forward time by 1 minute
        vm.warp(block.timestamp + timePassed);
        // set factor to decay base rate
        cdpManager.setMinuteDecayFactor(newMinuteDecayFactor);
        // Test that baseRate is decayed according to the previous factor
        console.log("baseRate after: %s", cdpManager.baseRate());
        console.log("expected baseRate: %s", expectedDecayedBaseRate);
        assertEq(cdpManager.baseRate(), expectedDecayedBaseRate);
        vm.stopPrank();
    }

    function testMultipleRedemption(uint _cdpNumber, uint _collAmt) public {
        vm.assume(_cdpNumber > 1);
        vm.assume(_cdpNumber <= 1000);
        vm.assume(_collAmt > 22e17);
        vm.assume(_collAmt <= 10000e18);
        uint _price = priceFeedMock.getPrice();

        // open random cdps with increasing ICR
        address payable[] memory _borrowers = _utils.createUsers(_cdpNumber + 1);
        bytes32[] memory _cdpIds = new bytes32[](_cdpNumber);
        for (uint i = 1; i <= _cdpNumber; ++i) {
            uint _debt = _utils.calculateBorrowAmount(
                _collAmt,
                _price,
                (COLLATERAL_RATIO + (i * 5e15))
            );
            require(_debt > 0, "!no debt for cdp");
            bytes32 _cdpId = _openTestCDP(_borrowers[i], _collAmt, _debt);
            _cdpIds[i - 1] = _cdpId;
            if (i > 1) {
                uint _icr = cdpManager.getCurrentICR(_cdpId, _price);
                uint _prevICR = cdpManager.getCurrentICR(_cdpIds[i - 2], _price);
                require(_icr > _prevICR, "!icr");
                require(_icr > CCR, "!icr>ccr");
            }
        }

        _ensureSystemInvariants();

        // prepare redemption by picking a random number of CDPs to redeem
        address _redeemer = _borrowers[0];
        uint _debt = _utils.calculateBorrowAmount(_collAmt, _price, COLLATERAL_RATIO * 1000);
        _openTestCDP(_redeemer, _collAmt, _debt);
        uint _redeemNumber = _utils.generateRandomNumber(1, _cdpNumber - 1, _redeemer);
        vm.assume(_redeemNumber > 0);
        uint _redeemDebt;
        for (uint i = 0; i < _redeemNumber; ++i) {
            CdpState memory _state = _getEntireDebtAndColl(_cdpIds[i]);
            _redeemDebt += _state.debt;
            address _owner = sortedCdps.getOwnerAddress(_cdpIds[i]);
            uint _sugar = eBTCToken.balanceOf(_owner);
            vm.prank(_owner);
            eBTCToken.transfer(_redeemer, _sugar);
        }

        // execute redemption
        (bytes32 firstRedempHint, uint partialRedempNICR, , ) = hintHelpers.getRedemptionHints(
            _redeemDebt,
            _price,
            0
        );
        require(firstRedempHint == _cdpIds[0], "!firstRedempHint");
        uint _debtBalBefore = eBTCToken.balanceOf(_redeemer);
        vm.prank(_redeemer);
        cdpManager.redeemCollateral(
            _redeemDebt,
            firstRedempHint,
            bytes32(0),
            bytes32(0),
            partialRedempNICR,
            0,
            1e18
        );
        uint _debtBalAfter = eBTCToken.balanceOf(_redeemer);

        // post checks
        require(_debtBalAfter + _redeemDebt == _debtBalBefore, "!redemption debt reduction");
        for (uint i = 0; i < _redeemNumber; ++i) {
            require(cdpManager.getCdpStatus(_cdpIds[i]) == 4, "redemption leave CDP not closed!");
            address _owner = sortedCdps.getOwnerAddress(_cdpIds[i]);
            require(
                collSurplusPool.getCollateral(_owner) > cdpManager.LIQUIDATOR_REWARD(),
                "redemption leave wrong surplus to claim!"
            );
        }

        _ensureSystemInvariants();
    }

    function _decMul(uint x, uint y) internal pure returns (uint decProd) {
        uint prod_xy = x * y;

        decProd = (prod_xy + (1e18 / 2)) / 1e18;
    }

    function _decPow(uint _base, uint _minutes) internal pure returns (uint) {
        if (_minutes > 525600000) {
            _minutes = 525600000;
        } // cap to avoid overflow

        if (_minutes == 0) {
            return 1e18;
        }

        uint y = 1e18;
        uint x = _base;
        uint n = _minutes;

        // Exponentiation-by-squaring
        while (n > 1) {
            if (n % 2 == 0) {
                x = _decMul(x, x);
                n = n / 2;
            } else {
                // if (n % 2 != 0)
                y = _decMul(x, y);
                x = _decMul(x, x);
                n = (n - 1) / 2;
            }
        }

        return _decMul(x, y);
    }
}
