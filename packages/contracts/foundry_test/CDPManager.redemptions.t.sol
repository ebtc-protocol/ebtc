// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "../contracts/Dependencies/EbtcMath.sol";
import {eBTCBaseInvariants} from "./BaseInvariants.sol";

contract CDPManagerRedemptionsTest is eBTCBaseInvariants {
    // Storage array of cdpIDs when impossible to calculate array size
    bytes32[] cdpIds;
    uint256 public mintAmount = 1e18;
    uint256 private ICR_COMPARE_TOLERANCE = 1000000; //in the scale of 1e18
    address payable[] users;

    function setUp() public override {
        super.setUp();
        connectCoreContracts();
        connectLQTYContractsToCore();
        vm.warp(3 weeks);
    }

    function testCDPManagerSetMinuteDecayFactorDecaysBaseRate() public {
        uint256 newMinuteDecayFactor = (500 + 999037758833783000);
        uint256 timePassed = 600; // seconds/60 => minute

        address user = _utils.getNextUserAddress();

        // Grant permission
        vm.prank(defaultGovernance);
        authority.setUserRole(user, 3, true);

        collateral.approve(address(borrowerOperations), type(uint256).max);

        uint256 debt = 2e17;

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
        uint256 _redeemDebt = borrowerOperations.MIN_CHANGE();
        (bytes32 firstRedemptionHint, uint256 partialRedemptionHintNICR, , ) = hintHelpers
            .getRedemptionHints(_redeemDebt, (priceFeedMock.fetchPrice()), 0);

        _syncSystemDebtTwapToSpotValue();
        cdpManager.redeemCollateral(
            _redeemDebt,
            firstRedemptionHint,
            bytes32(0),
            bytes32(0),
            partialRedemptionHintNICR,
            0,
            1e18
        );

        uint256 initialRate = cdpManager.baseRate();

        console.log("baseRate: %s", cdpManager.baseRate());

        // Calculate the expected decayed base rate
        uint256 decayFactor = cdpManager.minuteDecayFactor();
        console.log("decayFactor: %s", decayFactor);
        uint256 _decayMultiplier = _decPow(decayFactor, (timePassed / 60));
        console.log("_decayMultiplier: %s", _decayMultiplier);
        uint256 expectedDecayedBaseRate = (initialRate * _decayMultiplier) /
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

    function testMultipleRedemption(uint256 _cdpNumber, uint256 _collAmt) public {
        _cdpNumber = bound(_cdpNumber, 2, 1000);
        _collAmt = bound(_collAmt, 22e17 + 1, 10000e18);
        uint256 _price = priceFeedMock.getPrice();

        // open random cdps with increasing ICR
        address payable[] memory _borrowers = _utils.createUsers(_cdpNumber + 1);
        bytes32[] memory _cdpIds = new bytes32[](_cdpNumber);
        for (uint256 i = 1; i <= _cdpNumber; ++i) {
            uint256 _debt = _utils.calculateBorrowAmount(
                _collAmt,
                _price,
                (COLLATERAL_RATIO + (i * 5e15))
            );
            require(_debt > 0, "!no debt for cdp");
            bytes32 _cdpId = _openTestCDP(_borrowers[i], _collAmt, _debt);
            _cdpIds[i - 1] = _cdpId;
            if (i > 1) {
                uint256 _icr = cdpManager.getCachedICR(_cdpId, _price);
                uint256 _prevICR = cdpManager.getCachedICR(_cdpIds[i - 2], _price);
                require(_icr > _prevICR, "!icr");
                require(_icr > CCR, "!icr>ccr");
            }
        }

        _ensureSystemInvariants();

        // prepare redemption by picking a random number of CDPs to redeem
        address _redeemer = _borrowers[0];
        uint256 _debt = _utils.calculateBorrowAmount(_collAmt, _price, COLLATERAL_RATIO * 1000);
        _openTestCDP(_redeemer, _collAmt, _debt);
        uint256 _redeemNumber = _utils.generateRandomNumber(1, _cdpNumber - 1, _redeemer);
        uint256 _redeemDebt;
        for (uint256 i = 0; i < _redeemNumber; ++i) {
            CdpState memory _state = _getSyncedDebtAndCollShares(_cdpIds[i]);
            _redeemDebt += _state.debt;
            address _owner = sortedCdps.getOwnerAddress(_cdpIds[i]);
            uint256 _sugar = eBTCToken.balanceOf(_owner);
            vm.prank(_owner);
            eBTCToken.transfer(_redeemer, _sugar);
        }

        // execute redemption
        (bytes32 firstRedempHint, uint256 partialRedempNICR, , ) = hintHelpers.getRedemptionHints(
            _redeemDebt,
            _price,
            0
        );
        require(firstRedempHint == _cdpIds[0], "!firstRedempHint");
        uint256 _debtBalBefore = eBTCToken.balanceOf(_redeemer);
        _syncSystemDebtTwapToSpotValue();
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
        uint256 _debtBalAfter = eBTCToken.balanceOf(_redeemer);

        // post checks
        require(_debtBalAfter + _redeemDebt == _debtBalBefore, "!redemption debt reduction");
        for (uint256 i = 0; i < _redeemNumber; ++i) {
            require(
                cdpManager.getCdpStatus(_cdpIds[i]) == 4,
                "redemption leaves CDP not closed with correct status"
            );
            _assertCdpClosed(_cdpIds[i], 4);
            _assertCdpNotInSortedCdps(_cdpIds[i]);
            address _owner = sortedCdps.getOwnerAddress(_cdpIds[i]);
            require(
                collSurplusPool.getSurplusCollShares(_owner) > cdpManager.LIQUIDATOR_REWARD(),
                "redemption leave wrong surplus to claim!"
            );
        }

        _ensureSystemInvariants();
    }

    function _decMul(uint256 x, uint256 y) internal pure returns (uint256 decProd) {
        uint256 prod_xy = x * y;

        decProd = (prod_xy + (1e18 / 2)) / 1e18;
    }

    function _decPow(uint256 _base, uint256 _minutes) internal pure returns (uint256) {
        if (_minutes > 525600000) {
            _minutes = 525600000;
        } // cap to avoid overflow

        if (_minutes == 0) {
            return 1e18;
        }

        uint256 y = 1e18;
        uint256 x = _base;
        uint256 n = _minutes;

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
        uint256 debt = 1;

        vm.prank(defaultGovernance);
        cdpManager.setRedemptionsPaused(true);
        assertEq(true, cdpManager.redemptionsPaused());

        vm.startPrank(user);

        (bytes32 firstRedemptionHint, uint256 partialRedemptionHintNICR, , ) = hintHelpers
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
        uint256 debt = minChange;

        vm.startPrank(defaultGovernance);
        cdpManager.setRedemptionsPaused(true);
        cdpManager.setRedemptionsPaused(false);
        assertEq(false, cdpManager.redemptionsPaused());
        vm.stopPrank();

        vm.startPrank(user);

        (bytes32 firstRedemptionHint, uint256 partialRedemptionHintNICR, , ) = hintHelpers
            .getRedemptionHints(debt, (priceFeedMock.fetchPrice()), 0);
        _syncSystemDebtTwapToSpotValue();
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

    function test_SingleRedemptionCollSurplus(uint256 _toRedeemICR) public {
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
        _toRedeemICR = bound(_toRedeemICR, cdpManager.MCR() + 1, cdpManager.CCR());

        uint256 _originalPrice = priceFeedMock.fetchPrice();

        // ensure there is more than one CDP
        _singleCdpSetupWithICR(user, 200e16);
        (, bytes32 userCdpid) = _singleCdpSetupWithICR(user, _toRedeemICR);
        uint256 _totalCollBefore = cdpManager.getSystemCollShares();
        uint256 _totalDebtBefore = cdpManager.getSystemDebt();
        uint256 _redeemedDebt = cdpManager.getCdpDebt(userCdpid);
        uint256 _cdpColl = cdpManager.getCdpCollShares(userCdpid);
        uint256 _cdpLiqReward = cdpManager.getCdpLiquidatorRewardShares(userCdpid);

        // perform redemption
        _performRedemption(user, _redeemedDebt, userCdpid, userCdpid);

        {
            _checkFullyRedeemedCdp(userCdpid, user, _cdpColl, _redeemedDebt);
            _utils.assertApproximateEq(
                _totalCollBefore - _cdpColl,
                cdpManager.getSystemCollShares(),
                ICR_COMPARE_TOLERANCE
            );
            assertEq(
                _totalDebtBefore - _redeemedDebt,
                cdpManager.getSystemDebt(),
                "total debt mismatch after redemption!!!"
            );
        }
    }

    function test_MultipleRedemptionCollSurplus(uint256 _toRedeemICR) public {
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
        _toRedeemICR = bound(_toRedeemICR, cdpManager.MCR() + 1, cdpManager.CCR());

        uint256 _originalPrice = priceFeedMock.fetchPrice();

        // ensure there is more than one CDP
        _singleCdpSetupWithICR(users[0], 200e16);
        (, bytes32 userCdpid1) = _singleCdpSetupWithICR(users[0], _toRedeemICR);
        (, bytes32 userCdpid2) = _singleCdpSetupWithICR(users[1], _toRedeemICR + 2e16);
        (, bytes32 userCdpid3) = _singleCdpSetupWithICR(users[2], _toRedeemICR + 4e16);
        uint256 _totalCollBefore = cdpManager.getSystemCollShares();
        uint256 _totalDebtBefore = cdpManager.getSystemDebt();
        uint256 _cdpDebt1 = cdpManager.getCdpDebt(userCdpid1);
        uint256 _cdpDebt2 = cdpManager.getCdpDebt(userCdpid2);
        uint256 _cdpDebt3 = cdpManager.getCdpDebt(userCdpid3);
        uint256 _cdpColl1 = cdpManager.getCdpCollShares(userCdpid1);
        uint256 _cdpColl2 = cdpManager.getCdpCollShares(userCdpid2);
        uint256 _redeemedDebt = _cdpDebt1 + _cdpDebt2 + (_cdpDebt3 / 2);
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
                cdpManager.getSystemCollShares(),
                ICR_COMPARE_TOLERANCE
            );
            assertEq(
                _totalDebtBefore - _redeemedDebt,
                cdpManager.getSystemDebt(),
                "total debt mismatch after redemption!!!"
            );
        }
    }

    function _singleCdpRedemptionSetup() internal returns (address user, bytes32 userCdpId) {
        uint256 debt = 2e17;
        user = _utils.getNextUserAddress();
        userCdpId = _openTestCDP(user, 10000 ether, debt);

        vm.startPrank(user);
        eBTCToken.approve(address(cdpManager), type(uint256).max);
        vm.stopPrank();
    }

    function _singleCdpSetupWithICR(address _usr, uint256 _icr) internal returns (address, bytes32) {
        uint256 _price = priceFeedMock.fetchPrice();
        uint256 _coll = cdpManager.MIN_NET_STETH_BALANCE() * 2;
        uint256 _debt = (_coll * _price) / _icr;
        bytes32 _cdpId = _openTestCDP(_usr, _coll + cdpManager.LIQUIDATOR_REWARD(), _debt);
        uint256 _cdpICR = cdpManager.getCachedICR(_cdpId, _price);
        _utils.assertApproximateEq(_icr, _cdpICR, ICR_COMPARE_TOLERANCE); // in the scale of 1e18
        return (_usr, _cdpId);
    }

    function _performRedemption(
        address _redeemer,
        uint256 _redeemedDebt,
        bytes32 _upperPartialRedemptionHint,
        bytes32 _lowerPartialRedemptionHint
    ) internal {
        (bytes32 firstRedemptionHint, uint256 partialRedemptionHintNICR, , ) = hintHelpers
            .getRedemptionHints(_redeemedDebt, priceFeedMock.fetchPrice(), 0);
        _syncSystemDebtTwapToSpotValue();
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
        uint256 _cdpColl,
        uint256 _cdpDebt
    ) internal {
        uint256 _expectedCollSurplus = _cdpColl +
            cdpManager.LIQUIDATOR_REWARD() -
            ((_cdpDebt * 1e18) / priceFeedMock.fetchPrice());
        assertTrue(sortedCdps.contains(_cdpId) == false);
        assertEq(
            _expectedCollSurplus,
            collSurplusPool.getSurplusCollShares(_cdpOwner),
            "coll surplus balance mismatch after full redemption!!!"
        );
    }

    function _checkPartiallyRedeemedCdp(bytes32 _cdpId, address _cdpOwner) internal {
        assertTrue(sortedCdps.contains(_cdpId) == true);
        assertEq(
            0,
            collSurplusPool.getSurplusCollShares(_cdpOwner),
            "coll surplus not zero after partial redemption!!!"
        );
    }

    function _getFirstCdpWithIcrGteMcr() internal returns (bytes32) {
        bytes32 _cId = sortedCdps.getLast();
        address currentBorrower = sortedCdps.getOwnerAddress(_cId);
        // Find the first cdp with ICR >= MCR
        while (
            currentBorrower != address(0) &&
            cdpManager.getCachedICR(_cId, priceFeedMock.getPrice()) < cdpManager.MCR()
        ) {
            _cId = sortedCdps.getPrev(_cId);
            currentBorrower = sortedCdps.getOwnerAddress(_cId);
        }
        return _cId;
    }

    function test_RedemptionMustSatisfyAccountingEquation() public {
        //   openCdp 2200000000000000067 4
        //   openCdp 2293234842987251430 136273187309674429
        //   setEthPerShare 909090909090909090
        //   redeemCollateral 77233452000714940 137 302083018134466905 1

        address user = _utils.getNextUserAddress();
        vm.startPrank(user);
        uint256 funds = type(uint96).max;
        vm.deal(user, funds);
        collateral.approve(address(borrowerOperations), funds);
        collateral.deposit{value: funds}();

        bytes32 _cdpId0 = borrowerOperations.openCdp(
            minChange,
            bytes32(0),
            bytes32(0),
            2293234842987251430
        );

        bytes32 _cdpId1 = borrowerOperations.openCdp(
            4 * minChange,
            bytes32(0),
            bytes32(0),
            2200000000000000067
        );

        bytes32 _cdpId2 = borrowerOperations.openCdp(
            136273187309674429,
            bytes32(0),
            bytes32(0),
            2293234842987251430
        );

        collateral.setEthPerShare(909090909090909090);

        bytes32 _cdpId = _getFirstCdpWithIcrGteMcr();

        _before(_cdpId);
        _syncSystemDebtTwapToSpotValue();
        cdpManager.redeemCollateral(
            77233452000714940,
            bytes32(0),
            bytes32(0),
            bytes32(0),
            137,
            1,
            302083018134466905
        );

        _after(_cdpId);
        console.log(_diff());

        uint256 redeemedColl = (vars.actorCollAfter - vars.actorCollBefore);
        uint256 paidEbtc = (vars.actorEbtcBefore - vars.actorEbtcAfter);
        uint256 fee = (vars.feeRecipientTotalCollAfter - vars.feeRecipientTotalCollBefore);

        uint256 beforeValue = ((vars.activePoolCollBefore +
            vars.liquidatorRewardSharesBefore +
            vars.collSurplusPoolBefore) * vars.priceBefore) /
            1e18 -
            vars.cdpDebtBefore;
        uint256 afterValue = ((vars.activePoolCollAfter +
            vars.liquidatorRewardSharesAfter +
            vars.collSurplusPoolAfter +
            fee) * vars.priceAfter) /
            1e18 -
            vars.cdpDebtAfter;

        console2.log("value", beforeValue, afterValue);

        assertTrue(invariant_CDPM_04(vars), CDPM_04);
    }

    function testSortingForPartialRedemption() public {
        uint256 grossColl = 11e18 + cdpManager.LIQUIDATOR_REWARD();

        uint256 price = priceFeedMock.fetchPrice();

        uint256 debtMCR = _utils.calculateBorrowAmount(11e18, price, MINIMAL_COLLATERAL_RATIO);

        uint256 debtColl = _utils.calculateBorrowAmount(11e18, price, COLLATERAL_RATIO);

        address wallet = _utils.getNextUserAddress();

        // 5 Cdps with the biggest NICR and the head of the sorted list
        bytes32 zero = _openTestCDP(wallet, grossColl, debtColl - 20000);
        bytes32 first = _openTestCDP(wallet, grossColl, debtColl - 10000);
        bytes32 second = _openTestCDP(wallet, grossColl, debtColl - 7500);
        bytes32 third = _openTestCDP(wallet, grossColl, debtColl - 5000);
        bytes32 fourth = _openTestCDP(wallet, grossColl, debtMCR);

        vm.startPrank(wallet);

        // Check the TCR is above CCR
        assert(cdpManager.getCachedTCR(price) > CCR);

        // Lower the price so last node can go underwater
        // and the third node is the first hint for redeeming
        priceFeedMock.setPrice(price - 1e1);

        // Extra check to ensure:
        // Fourth node is underwater ICR < MCR
        // Third node has ICR > MCR
        assert(_getCachedICR(fourth) < MINIMAL_COLLATERAL_RATIO);
        assert(_getCachedICR(third) > MINIMAL_COLLATERAL_RATIO);

        uint256 _redeemAmt = debtColl + 10000;
        (bytes32 hint, uint256 partialNICR, , ) = hintHelpers.getRedemptionHints(
            (_redeemAmt),
            priceFeedMock.fetchPrice(),
            0
        );

        // Check the hint is the third node in the sorted list
        // Which is the node above the underwater Cdp
        assert(hint == third);

        // Approve cdp manager to use ebtc tokens
        eBTCToken.approve(address(cdpManager), eBTCToken.balanceOf(wallet));

        // Fully redeem a CDP and partially redeem another with a wrong hint pair
        // correct pair should be (zero, first)
        bytes32 _upperHintForPartialReinsert = first;
        bytes32 _lowerHintForPartailReinsert = fourth;

        console.log("Before redemption");
        console.log("first NICR:  %s", cdpManager.getCachedNominalICR(first));
        console.log("second NICR: %s", cdpManager.getCachedNominalICR(second));

        _syncSystemDebtTwapToSpotValue();
        cdpManager.redeemCollateral(
            _redeemAmt,
            hint,
            _upperHintForPartialReinsert,
            _lowerHintForPartailReinsert,
            partialNICR,
            0,
            1e18
        );

        // Check the third node is fully redeemed and no longer exists in the list
        assert(!sortedCdps.contains(third));
        // Check the lowest NICR node is still the fourth node
        assert(fourth == sortedCdps.getLast());
        // Check the biggest NICR node is still the first node
        assert(zero == sortedCdps.getFirst());

        // Check the second node is correctly placed, should be a bit upper after redemption
        assert(second == sortedCdps.getPrev(first));
        assert(second == sortedCdps.getNext(zero));

        uint256 _zeroNICR = cdpManager.getCachedNominalICR(zero);
        uint256 _firstNICR = cdpManager.getCachedNominalICR(first);
        uint256 _secondNICR = cdpManager.getCachedNominalICR(second);
        uint256 _fourthNICR = cdpManager.getCachedNominalICR(fourth);

        console.log("After redemption");
        console.log("zero NICR:   %s", _zeroNICR);
        console.log("second NICR: %s", _secondNICR);
        console.log("first NICR:  %s", _firstNICR);
        console.log("fourth NICR: %s", _fourthNICR);

        assert(_secondNICR > _firstNICR);
        assert(_zeroNICR > _secondNICR);
        assert(_firstNICR > _fourthNICR);

        vm.stopPrank();
    }

    function test_RedemptionsRevertWhenTriggerRM() public {
        (address user, bytes32 userCdpId) = _singleCdpRedemptionSetup();
        uint256 debt = cdpManager.getCdpDebt(userCdpId);

        (address user2, bytes32 userCdpId2) = _singleCdpRedemptionSetup();
        uint256 _moreDebt = (cdpManager.getCdpCollShares(userCdpId2) * priceFeedMock.fetchPrice()) /
            cdpManager.CCR();

        vm.startPrank(user2);
        borrowerOperations.withdrawDebt(
            userCdpId2,
            _moreDebt - cdpManager.getCdpDebt(userCdpId2),
            bytes32(0),
            bytes32(0)
        );
        vm.stopPrank();

        uint256 _newPrice = (priceFeedMock.fetchPrice() * 8000) / 10000;
        priceFeedMock.setPrice(_newPrice);
        require(
            cdpManager.getSyncedICR(userCdpId, _newPrice) > cdpManager.MCR(),
            "!no CDP to redeem"
        );
        require(
            cdpManager.getSyncedICR(userCdpId2, _newPrice) < cdpManager.MCR(),
            "!RM not trigger"
        );

        _syncSystemDebtTwapToSpotValue();
        vm.startPrank(user);
        vm.expectRevert("CdpManager: redemption should not trigger RecoveryMode");
        cdpManager.redeemCollateral(debt, userCdpId, bytes32(0), bytes32(0), 0, 0, 1e18);
        vm.stopPrank();
    }

    function testStakeUpdateForPartialRedemption() public {
        address wallet = _utils.getNextUserAddress();
        uint256 _yearlyInc = 36000000000000000;
        uint256 _dailyInc = _yearlyInc / 365;

        // fetch the price
        uint256 price = priceFeedMock.fetchPrice();

        // calculate the net coll + liquidator reward
        uint256 grossColl = 10e18 + cdpManager.LIQUIDATOR_REWARD();

        // calculate the debt allowed with collateral ratio of 110%
        uint256 debtMCR = _utils.calculateBorrowAmount(10e18, price, MINIMAL_COLLATERAL_RATIO);

        // calculate the debt allowed with collateral ratio of 125%
        uint256 debtColl = _utils.calculateBorrowAmount(10e18, price, COLLATERAL_RATIO);

        // open 5 cdps in the system
        _openTestCDP(wallet, grossColl, debtColl - 20000);
        _openTestCDP(wallet, grossColl, debtColl - 10000);
        _openTestCDP(wallet, grossColl, debtColl - 7500);
        bytes32 partialCdp = _openTestCDP(wallet, grossColl, debtColl);
        _openTestCDP(wallet, grossColl, debtMCR);

        vm.startPrank(wallet);

        // approve ebtc token to cdp manager
        eBTCToken.approve(address(cdpManager), eBTCToken.balanceOf(wallet));

        // increase the eth per share with one day split fee
        collateral.setEthPerShare(1e18 + _dailyInc);

        // get the last Cdp in the system
        bytes32 last = sortedCdps.getLast();

        // record the old coll and stake of the partial redeemed cdp
        uint256 oldCollBefore = cdpManager.getCdpCollShares(partialCdp);
        uint256 oldStakeBefore = cdpManager.getCdpStake(partialCdp);

        // sync the debt twap spot value
        _syncSystemDebtTwapToSpotValue();

        uint256 _syncedCollAfter = cdpManager.getSyncedCdpCollShares(partialCdp);

        // fully redeem the last cdp and try to partial redeem but cancel with wrong NICR
        cdpManager.redeemCollateral(
            debtMCR + (debtColl / 2),
            last,
            bytes32(0),
            bytes32(0),
            0,
            0,
            1e18
        );

        vm.stopPrank();

        // record the new coll and stake after the canceled partial redeeming
        uint256 newCollAfter = cdpManager.getCdpCollShares(partialCdp);
        uint256 newStakeAfter = cdpManager.getCdpStake(partialCdp);
        require(
            _syncedCollAfter == newCollAfter,
            "!collateral share for cancelled partially-redeemed CDP should be synced"
        );

        // ensure that the last cdp was fully redeemed
        assert(!sortedCdps.contains(last));

        // console log the old and new stats of the canceled cdp
        console.log("================Before");
        console.log("CollBefore            :", oldCollBefore);
        console.log("StakeBefore           :", oldStakeBefore);
        console.log("================After");
        console.log("CollAfter             :", newCollAfter);
        console.log("StakeAfter            :", newStakeAfter);

        // fetch the stake and coll snapshots
        uint256 stakeSnapshot = cdpManager.totalStakesSnapshot();
        uint256 collSnapshot = cdpManager.totalCollateralSnapshot();

        // calculate the correct stake based on the cdp new coll and latest stake ratio
        uint256 correctStake = (newCollAfter * stakeSnapshot) / collSnapshot;

        // console log the correct stake
        console.log("=====================");
        console.log("CorrectStake          :", correctStake);

        // The diference is based on 5 cdps in the system and only one daily increase.
        require(
            correctStake == newStakeAfter,
            "!stake for cancelled partially-redeemed CDP should be updated"
        );
    }
}
