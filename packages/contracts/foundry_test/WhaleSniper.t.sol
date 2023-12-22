pragma solidity 0.8.17;

import {console2 as console} from "forge-std/console2.sol";

import {eBTCBaseFixture} from "./BaseFixture.sol";

contract WhaleSniperPOCTest is eBTCBaseFixture {
    address payable[] users;

    address private splitFeeRecipient;
    mapping(bytes32 => uint256) private _targetCdpPrevCollUnderlyings;
    mapping(bytes32 => uint256) private _targetCdpPrevColls;
    mapping(bytes32 => uint256) private _targetCdpPrevFeeApplied;

    struct LocalFeeSplitVar {
        uint256 _prevSystemStEthFeePerUnitIndex;
        uint256 _prevTotalCollUnderlying;
    }

    ////////////////////////////////////////////////////////////////////////////
    // Tests
    ////////////////////////////////////////////////////////////////////////////

    function setUp() public override {
        super.setUp();

        connectCoreContracts();
        connectLQTYContractsToCore();

        users = _utils.createUsers(3);

        splitFeeRecipient = address(feeRecipient);
    }

    /**
        Proof that Split goes down after claiming
     */
    function test_TcrDecreasesAfterClaiming() public {
        uint256 debtAmt = 1e20; // TODO: Consider fuzz

        uint256 _curPrice = priceFeedMock.getPrice();
        uint256 coll1 = _utils.calculateCollAmount(debtAmt, _curPrice, 126e16);

        bytes32 cdpId1 = _openTestCDP(users[0], coll1, debtAmt);

        // Once a CDP is open
        // Just take some yield
        uint256 _curIndex = collateral.getPooledEthByShares(1e18);
        uint256 _newIndex = _curIndex + 5e16;
        collateral.setEthPerShare(_newIndex);

        // Get TCR
        uint256 tcr = cdpManager.getCachedTCR(_curPrice);

        console.log("tcr b4", tcr);

        // And show that the TCR goes down once you claim
        cdpManager.syncGlobalAccountingAndGracePeriod();

        uint256 tcrAfter = cdpManager.getCachedTCR(_curPrice);
        console.log("tcrAfter", tcrAfter);

        assertLt(tcrAfter, tcr, "TCR didn't decrease");
    }

    function _tryOpenCdp(address _user, uint256 _coll, uint256 _debt) internal returns (bytes32) {
        dealCollateral(_user, _coll);
        vm.startPrank(_user);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        bytes32 _cdpId;
        try borrowerOperations.openCdp(_debt, bytes32(0), bytes32(0), _coll) returns (bytes32 id) {
            _cdpId = id;
        } catch {}
        vm.stopPrank();
        return _cdpId;
    }

    // NOTE: This test requires a ton of runs, ideally 100k+
    function test_canNeverTriggerRMViaDepositFuzzed(
        uint64 cdpCR,
        uint88 attackerDebtAmount,
        uint88 systemDebtAmount
    ) public {
        // A) Given any attacker and system debt, both of which are above 100 BTC in denomination
        attackerDebtAmount = uint88(bound(attackerDebtAmount, 1e20, type(uint88).max));
        systemDebtAmount = uint88(bound(systemDebtAmount, 1e20, type(uint88).max));

        console.log("systemDebtAmount", systemDebtAmount);
        console.log("attackerDebtAmount", attackerDebtAmount);
        // u88 max is 3e26, max bitcoins are 2e25 (adjuges for 18 decimals)
        // And a ICR for the attacker that will drive the TCR below 150
        cdpCR = cdpCR % 126e16; // Anything above is not meaningful since it drives the TCR above
        console.log("cdpCR", cdpCR);

        uint256 _curPrice = priceFeedMock.getPrice();

        // 2) Given an initial deposit that matches the attacker capital, that is very close to CCR
        uint256 coll1 = _utils.calculateCollAmount(systemDebtAmount, _curPrice, 126e16); // Literally at the edge

        bytes32 cdpId1 = _openTestCDP(users[0], coll1, systemDebtAmount);
        console.log("tcrAfterOpen Base", cdpManager.getCachedTCR(_curPrice));

        // Get TCR
        uint256 tcr = cdpManager.getCachedTCR(_curPrice);

        // Deposit and bring TCR to RM

        // 3) Given a Victim that is heavily levered, with ICR below CCR
        // 5% of amt
        {
            uint256 victimAmount = systemDebtAmount / 50;
            console.log("victimAmount", victimAmount);

            // Levered to the tits
            uint256 collVictim = _utils.calculateCollAmount(victimAmount, _curPrice, 111e16);
            console.log("collVictim", collVictim);
            bytes32 cdpIdVictm = _openTestCDP(users[0], collVictim, victimAmount);
            console.log("tcrAfterOpen Victim", cdpManager.getCachedTCR(_curPrice));
        }

        // Once a CDP is open
        // Just take some yield
        // NOTE: We must do this here due to `updateCdpDebtRedistributionIndex` resynching the index after each open
        {
            uint256 _curIndex = collateral.getPooledEthByShares(1e18);
            uint256 _newIndex = _curIndex + 5e16;
            collateral.setEthPerShare(_newIndex);
            uint256 _tcr = cdpManager.getCachedTCR(_curPrice);

            // reference https://github.com/Badger-Finance/ebtc/pull/456#issuecomment-1566821518
            uint256 _requiredDeltaIdxTriggeRM = (((_newIndex * (_tcr - cdpManager.CCR())) / _tcr) *
                cdpManager.MAX_REWARD_SPLIT()) / cdpManager.stakingRewardSplit();

            // hack manipulation to sync global index in attacker's benefit
            uint256 _oldIdx = _newIndex - _requiredDeltaIdxTriggeRM;
            collateral.setEthPerShare(_oldIdx);
            _oldIdx = collateral.getEthPerShare();
            console.log("_oldIdx:", _oldIdx);
            cdpManager.syncGlobalAccountingAndGracePeriod();
            console.log("_oldIndex:", cdpManager.stEthIndex());
            assertEq(_oldIdx, cdpManager.stEthIndex());
            assertLt(_oldIdx, _curIndex);
            collateral.setEthPerShare(_newIndex);
            console.log("_newIndex:", _newIndex);
        }

        // Attacker opens CDP to push to barely to RM
        // 4) The attacker tries the TCR from the fuzzer
        {
            uint256 collAttacker = _utils.calculateCollAmount(
                (systemDebtAmount / 100000),
                _curPrice,
                125005e13
            );
            bytes32 cdpIdAttacker = _tryOpenCdp(users[0], collAttacker, (systemDebtAmount / 100000));
            console.log("tcrAfterOpen Attacker", cdpManager.getCachedTCR(_curPrice));
        }

        // Now we take the split
        cdpManager.syncGlobalAccountingAndGracePeriod();

        uint256 tcrAfter = cdpManager.getCachedTCR(_curPrice);
        console.log("tcrAfter claim", tcrAfter);

        // Now we're in recovery mode so there exist a value such that a liquidation can be triggered willingly by the attacker
        assertGt(tcrAfter, 1250000000000000000); /// @audit ??? No longer triggering RM?
    }

    // Padding Deposits -> W/e, prob 300% CR
    // Victim Deposits -> Leverage to 110
    // Attacker Brings TCR close to Recovery Mode -> Basically 110 as well
    // Attacker liquidates victim
    // Change the TCR to see different results
    function test_canNeverTriggerRMManual() public {
        uint256 debtAmt = 1e20; // TODO: Consider fuzz

        uint256 _curPrice = priceFeedMock.getPrice();

        uint256 coll1 = _utils.calculateCollAmount(debtAmt, _curPrice, 126e16); // Literally at the edge

        bytes32 cdpId1 = _openTestCDP(users[0], coll1, debtAmt);
        console.log("tcrAfterOpen Base", cdpManager.getCachedTCR(_curPrice));

        // Get TCR
        uint256 tcr = cdpManager.getCachedTCR(_curPrice);

        // Deposit and bring TCR to RM

        // 2% of amt
        uint256 victimAmount = debtAmt / 20;
        console.log("victimAmount", victimAmount);

        // Levered to the tits
        uint256 collVictim = _utils.calculateCollAmount(victimAmount, _curPrice, 111e16);
        console.log("collVictim", collVictim);
        bytes32 cdpIdVictm = _openTestCDP(users[0], collVictim, victimAmount);
        console.log("tcrAfterOpen Victim", cdpManager.getCachedTCR(_curPrice));

        // Once a CDP is open
        // Just take some yield
        // NOTE: We must do this here due to `updateCdpDebtRedistributionIndex` resynching the index after each open
        uint256 _curIndex = collateral.getPooledEthByShares(1e18);
        uint256 _newIndex = _curIndex + 5e16;
        collateral.setEthPerShare(_newIndex);

        // Attacker opens CDP to push to barely to RM
        uint256 attackerDebtAmount = debtAmt;
        // 1214e15 makes the tx revert due to change in TCR
        // 1215e15 is safe but the liquidation reverts
        uint256 collAttacker = _utils.calculateCollAmount(attackerDebtAmount, _curPrice, 1215e15); // NOTE: This fails
        bytes32 cdpIdAttacker = _openTestCDP(users[0], collAttacker, attackerDebtAmount);
        console.log("tcrAfterOpen Attacker", cdpManager.getCachedTCR(_curPrice));

        // Now we take the split
        cdpManager.syncGlobalAccountingAndGracePeriod();

        uint256 tcrAfter = cdpManager.getCachedTCR(_curPrice);
        console.log("tcrAfter claim", tcrAfter);

        // We're not in recovery mode
        assertGt(tcrAfter, 1250000000000000000);

        vm.startPrank(users[0]);
        vm.expectRevert(); // NOTE: We expect revert here, meaning the operation is safe
        cdpManager.liquidate(cdpIdVictm);
        uint256 tcrEnd = cdpManager.getCachedTCR(_curPrice);
        console.log("tcrEnd liquidation", tcrEnd);
        assertGt(tcrEnd, 1250000000000000000);
    }
}
