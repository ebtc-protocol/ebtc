// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "../contracts/Dependencies/LiquityMath.sol";
import {eBTCBaseInvariants} from "./BaseInvariants.sol";

contract CDPManagerRedemptionsTest is eBTCBaseInvariants {
    // Storage array of cdpIDs when impossible to calculate array size
    bytes32[] cdpIds;
    uint public mintAmount = 1e18;
    uint private ICR_COMPARE_TOLERANCE = 1000000; //in the scale of 1e18
    address payable[] users;

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

        uint debt = 2e17;

        console.log("debt %s", debt);

        _openTestCDP(user, 10000 ether, debt);

        vm.startPrank(user);

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
            require(
                cdpManager.getCdpStatus(_cdpIds[i]) == 4,
                "redemption leaves CDP not closed with correct status"
            );
            _assertCdpClosed(_cdpIds[i], 4);
            _assertCdpNotInSortedCdps(_cdpIds[i]);
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

    function test_ValidRedemptionsRevertWhenPaused() public {
        (address user, bytes32 userCdpId) = _singleCdpRedemptionSetup();
        uint debt = 1;

        vm.prank(defaultGovernance);
        cdpManager.setRedemptionsPaused(true);
        assertEq(true, cdpManager.redemptionsPaused());

        vm.startPrank(user);

        (bytes32 firstRedemptionHint, uint partialRedemptionHintNICR, , ) = hintHelpers
            .getRedemptionHints(debt, (priceFeedMock.fetchPrice()), 0);

        vm.expectRevert("CdpManager: Redemptions Paused");
        cdpManager.redeemCollateral(
            debt,
            firstRedemptionHint,
            bytes32(0),
            bytes32(0),
            partialRedemptionHintNICR,
            0,
            1e18
        );

        vm.stopPrank();
    }

    function test_ValidRedemptionNoLongerRevertsWhenUnpausedAfterBeingPaused() public {
        (address user, bytes32 userCdpId) = _singleCdpRedemptionSetup();
        uint debt = 1;

        vm.startPrank(defaultGovernance);
        cdpManager.setRedemptionsPaused(true);
        cdpManager.setRedemptionsPaused(false);
        assertEq(false, cdpManager.redemptionsPaused());
        vm.stopPrank();

        vm.startPrank(user);

        (bytes32 firstRedemptionHint, uint partialRedemptionHintNICR, , ) = hintHelpers
            .getRedemptionHints(debt, (priceFeedMock.fetchPrice()), 0);
        cdpManager.redeemCollateral(
            debt,
            firstRedemptionHint,
            bytes32(0),
            bytes32(0),
            partialRedemptionHintNICR,
            0,
            1e18
        );

        vm.stopPrank();
    }

    function test_SingleRedemptionCollSurplus(uint _toRedeemICR) public {
        // setup healthy whale Cdp
        // set 1 Cdp that is valid to redeem
        // calculate expected collSurplus from redemption of Cdp
        // calculate expected system debt after valid redemption
        // calculate expected system coll after valid redemption
        // fully redeem single Cdp
        // borrower of Redeemed Cdp should have expected collSurplus available
        // confirm expected system debt and coll
        address user = _utils.getNextUserAddress();

        // ensure redemption ICR falls in reasonable range
        vm.assume(_toRedeemICR > cdpManager.MCR());
        vm.assume(_toRedeemICR <= cdpManager.CCR());

        uint _originalPrice = priceFeedMock.fetchPrice();

        // ensure there is more than one CDP
        _singleCdpSetupWithICR(user, 200e16);
        (, bytes32 userCdpid) = _singleCdpSetupWithICR(user, _toRedeemICR);
        uint _totalCollBefore = cdpManager.getEntireSystemColl();
        uint _totalDebtBefore = cdpManager.getEntireSystemDebt();
        uint _redeemedDebt = cdpManager.getCdpDebt(userCdpid);
        uint _cdpColl = cdpManager.getCdpColl(userCdpid);
        uint _cdpLiqReward = cdpManager.getCdpLiquidatorRewardShares(userCdpid);

        // perform redemption
        _performRedemption(user, _redeemedDebt, userCdpid, userCdpid);

        {
            _checkFullyRedeemedCdp(userCdpid, user, _cdpColl, _redeemedDebt);
            _utils.assertApproximateEq(
                _totalCollBefore - _cdpColl,
                cdpManager.getEntireSystemColl(),
                ICR_COMPARE_TOLERANCE
            );
            assertEq(
                _totalDebtBefore - _redeemedDebt,
                cdpManager.getEntireSystemDebt(),
                "total debt mismatch after redemption!!!"
            );
        }
    }

    function test_MultipleRedemptionCollSurplus(uint _toRedeemICR) public {
        // setup healthy whale Cdp
        // set 3 Cdps that are valid to redeem at same ICR, different borrowers
        // calculate expected collSurplus from full redemption of Cdps
        // calculate expected system debt after all valid redemptions
        // calculate expected system coll after all valid redemptions
        // fully redeem 2 Cdps, partially redeem the third
        // borrowers of full Redeemed Cdps should have expected collSurplus available
        // borrowers of partially redeemed Cdp should have no collSurplus available
        // confirm expected system debt and coll
        users = _utils.createUsers(3);

        // ensure redemption ICR falls in reasonable range
        vm.assume(_toRedeemICR > cdpManager.MCR());
        vm.assume(_toRedeemICR <= cdpManager.CCR());

        uint _originalPrice = priceFeedMock.fetchPrice();

        // ensure there is more than one CDP
        _singleCdpSetupWithICR(users[0], 200e16);
        (, bytes32 userCdpid1) = _singleCdpSetupWithICR(users[0], _toRedeemICR);
        (, bytes32 userCdpid2) = _singleCdpSetupWithICR(users[1], _toRedeemICR + 2e16);
        (, bytes32 userCdpid3) = _singleCdpSetupWithICR(users[2], _toRedeemICR + 4e16);
        uint _totalCollBefore = cdpManager.getEntireSystemColl();
        uint _totalDebtBefore = cdpManager.getEntireSystemDebt();
        uint _cdpDebt1 = cdpManager.getCdpDebt(userCdpid1);
        uint _cdpDebt2 = cdpManager.getCdpDebt(userCdpid2);
        uint _cdpDebt3 = cdpManager.getCdpDebt(userCdpid3);
        uint _cdpColl1 = cdpManager.getCdpColl(userCdpid1);
        uint _cdpColl2 = cdpManager.getCdpColl(userCdpid2);
        uint _redeemedDebt = _cdpDebt1 + _cdpDebt2 + (_cdpDebt3 / 2);
        deal(address(eBTCToken), users[0], _redeemedDebt); // sugardaddy redeemer

        // perform redemption
        _performRedemption(users[0], _redeemedDebt, userCdpid1, userCdpid1);

        {
            _checkFullyRedeemedCdp(userCdpid1, users[0], _cdpColl1, _cdpDebt1);
            _checkFullyRedeemedCdp(userCdpid2, users[1], _cdpColl2, _cdpDebt2);
            _checkPartiallyRedeemedCdp(userCdpid3, users[2]);
            _utils.assertApproximateEq(
                _totalCollBefore -
                    _cdpColl1 -
                    _cdpColl2 -
                    (((_cdpDebt3 * 1e18) / 2) / _originalPrice),
                cdpManager.getEntireSystemColl(),
                ICR_COMPARE_TOLERANCE
            );
            assertEq(
                _totalDebtBefore - _redeemedDebt,
                cdpManager.getEntireSystemDebt(),
                "total debt mismatch after redemption!!!"
            );
        }
    }

    function _singleCdpRedemptionSetup() internal returns (address user, bytes32 userCdpId) {
        uint debt = 2e17;
        user = _utils.getNextUserAddress();
        userCdpId = _openTestCDP(user, 10000 ether, debt);

        vm.startPrank(user);
        eBTCToken.approve(address(cdpManager), type(uint256).max);
        vm.stopPrank();
    }

    function _singleCdpSetupWithICR(address _usr, uint _icr) internal returns (address, bytes32) {
        uint _price = priceFeedMock.fetchPrice();
        uint _coll = cdpManager.MIN_NET_COLL() * 2;
        uint _debt = (_coll * _price) / _icr;
        bytes32 _cdpId = _openTestCDP(_usr, _coll + cdpManager.LIQUIDATOR_REWARD(), _debt);
        uint _cdpICR = cdpManager.getCurrentICR(_cdpId, _price);
        _utils.assertApproximateEq(_icr, _cdpICR, ICR_COMPARE_TOLERANCE); // in the scale of 1e18
        return (_usr, _cdpId);
    }

    function _performRedemption(
        address _redeemer,
        uint _redeemedDebt,
        bytes32 _upperPartialRedemptionHint,
        bytes32 _lowerPartialRedemptionHint
    ) internal {
        (bytes32 firstRedemptionHint, uint partialRedemptionHintNICR, , ) = hintHelpers
            .getRedemptionHints(_redeemedDebt, priceFeedMock.fetchPrice(), 0);
        vm.prank(_redeemer);
        cdpManager.redeemCollateral(
            _redeemedDebt,
            firstRedemptionHint,
            _upperPartialRedemptionHint,
            _lowerPartialRedemptionHint,
            partialRedemptionHintNICR,
            0,
            1e18
        );
    }

    function _checkFullyRedeemedCdp(
        bytes32 _cdpId,
        address _cdpOwner,
        uint _cdpColl,
        uint _cdpDebt
    ) internal {
        uint _expectedCollSurplus = _cdpColl +
            cdpManager.LIQUIDATOR_REWARD() -
            ((_cdpDebt * 1e18) / priceFeedMock.fetchPrice());
        assertTrue(sortedCdps.contains(_cdpId) == false);
        assertEq(
            _expectedCollSurplus,
            collSurplusPool.getCollateral(_cdpOwner),
            "coll surplus balance mismatch after full redemption!!!"
        );
    }

    function _checkPartiallyRedeemedCdp(bytes32 _cdpId, address _cdpOwner) internal {
        assertTrue(sortedCdps.contains(_cdpId) == true);
        assertEq(
            0,
            collSurplusPool.getCollateral(_cdpOwner),
            "coll surplus not zero after partial redemption!!!"
        );
    }

    function _getFirstCdpWithIcrGteMcr() internal returns (bytes32) {
        bytes32 _cId = sortedCdps.getLast();
        address currentBorrower = sortedCdps.getOwnerAddress(_cId);
        // Find the first cdp with ICR >= MCR
        while (
            currentBorrower != address(0) &&
            cdpManager.getCurrentICR(_cId, priceFeedMock.getPrice()) < cdpManager.MCR()
        ) {
            _cId = sortedCdps.getPrev(_cId);
            currentBorrower = sortedCdps.getOwnerAddress(_cId);
        }
        return _cId;
    }

    function test_RedemptionMustSatisfyAccountingEquation() public {
        vm.warp(block.timestamp + cdpManager.BOOTSTRAP_PERIOD());

        //   setEthPerShare 918257478759017910
        //   setEthPerShare 834779526144561736
        //   openCdp 2200000000000000016 1
        //   setEthPerShare 758890478313237941
        //   openCdp 2200000000000000016 1
        //   setEthPerShare 775495175528592427
        //   redeemCollateral 1 16255093501771068715759097899081134636629229191974495785422 525583544679053958

        address user = _utils.getNextUserAddress();
        vm.startPrank(user);
        uint256 funds = type(uint96).max;
        vm.deal(user, funds);
        collateral.approve(address(borrowerOperations), funds);
        collateral.deposit{value: funds}();

        collateral.setEthPerShare(918257478759017910);
        collateral.setEthPerShare(834779526144561736);

        bytes32 _cdpId1 = borrowerOperations.openCdp(1, bytes32(0), bytes32(0), 2200000000000000016);

        collateral.setEthPerShare(758890478313237941);

        bytes32 _cdpId2 = borrowerOperations.openCdp(1, bytes32(0), bytes32(0), 2200000000000000016);

        collateral.setEthPerShare(775495175528592427);

        bytes32 _cdpId = _getFirstCdpWithIcrGteMcr();

        vars.activePoolCollBefore = activePool.getStEthColl();
        vars.liquidatorRewardSharesBefore = cdpManager.getCdpLiquidatorRewardShares(_cdpId);
        vars.collSurplusPoolBefore = collSurplusPool.getStEthColl();
        vars.debtBefore = activePool.getEBTCDebt();
        vars.priceBefore = priceFeedMock.getPrice();
        vars.actorEbtcBefore = eBTCToken.balanceOf(user);
        vars.actorCollBefore = collateral.balanceOf(user);

        (vars.feeSplitBefore, , ) = cdpManager.calcFeeUponStakingReward(
            collateral.getPooledEthByShares(cdpManager.DECIMAL_PRECISION()),
            cdpManager.stFPPSg()
        );

        vars.feeRecipientTotalCollBefore =
            activePool.getFeeRecipientClaimableColl() +
            collateral.balanceOf(activePool.feeRecipientAddress()) +
            vars.feeSplitBefore;

        cdpManager.redeemCollateral(
            1,
            bytes32(0),
            bytes32(0),
            bytes32(0),
            16255093501771068715759097899081134636629229191974495785422,
            1,
            525583544679053958
        );

        vars.activePoolCollAfter = activePool.getStEthColl();
        vars.liquidatorRewardSharesAfter = cdpManager.getCdpLiquidatorRewardShares(_cdpId);
        vars.collSurplusPoolAfter = collSurplusPool.getStEthColl();
        vars.debtAfter = activePool.getEBTCDebt();
        vars.priceAfter = priceFeedMock.getPrice();
        vars.actorEbtcAfter = eBTCToken.balanceOf(user);
        vars.actorCollAfter = collateral.balanceOf(user);
        vars.feeRecipientTotalCollAfter =
            activePool.getFeeRecipientClaimableColl() +
            collateral.balanceOf(activePool.feeRecipientAddress());

        uint256 redeemedColl = (vars.actorCollAfter - vars.actorCollBefore);
        uint256 paidEbtc = (vars.actorEbtcBefore - vars.actorEbtcAfter);
        uint256 fee = (vars.feeRecipientTotalCollAfter - vars.feeRecipientTotalCollBefore);

        console2.log("ActivePool", vars.activePoolCollBefore, vars.activePoolCollAfter);
        console2.log("CollSurplusPool", vars.collSurplusPoolBefore, vars.collSurplusPoolAfter);
        console2.log(
            "LiquidatorRewards",
            vars.liquidatorRewardSharesBefore,
            vars.liquidatorRewardSharesAfter
        );
        console2.log("Debt", vars.debtBefore, vars.debtAfter);
        console2.log("Paid", paidEbtc);
        console2.log("Redeemed", redeemedColl);
        console2.log("Fee", fee);

        uint256 beforeValue = ((vars.activePoolCollBefore +
            vars.liquidatorRewardSharesBefore +
            vars.collSurplusPoolBefore) * vars.priceBefore) /
            1e18 -
            vars.debtBefore;
        uint256 afterValue = ((vars.activePoolCollAfter +
            vars.liquidatorRewardSharesAfter +
            vars.collSurplusPoolAfter -
            redeemedColl -
            fee +
            vars.feeSplitBefore) * vars.priceAfter) /
            1e18 -
            vars.debtAfter +
            paidEbtc;

        console2.log("value", beforeValue, afterValue);

        assertTrue(invariant_CDPM_04(vars), CDPM_04);
    }
}
