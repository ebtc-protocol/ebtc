pragma solidity 0.8.17;

import {console2 as console} from "forge-std/console2.sol";

import {eBTCBaseFixture} from "./BaseFixture.sol";

contract WhaleSniperPOCTest is eBTCBaseFixture {
    address payable[] users;

    uint public constant DECIMAL_PRECISION = 1e18;

    address private splitFeeRecipient;
    mapping(bytes32 => uint) private _targetCdpPrevCollUnderlyings;
    mapping(bytes32 => uint) private _targetCdpPrevColls;
    mapping(bytes32 => uint) private _targetCdpPrevFeeApplied;

    struct LocalFeeSplitVar {
        uint _prevStFeePerUnitg;
        uint _prevTotalCollUnderlying;
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
        vm.assume(debtAmt > 1e18);

        uint _curPrice = priceFeedMock.getPrice();
        uint256 coll1 = _utils.calculateCollAmount(debtAmt, _curPrice, 136e16);

        bytes32 cdpId1 = _openTestCDP(users[0], coll1, debtAmt);

        // Once a CDP is open
        // Just take some yield
        uint _curIndex = collateral.getPooledEthByShares(1e18);
        uint _newIndex = _curIndex + 5e16;
        collateral.setEthPerShare(_newIndex);

        // Get TCR
        uint256 tcr = cdpManager.getTCR(_curPrice);

        console.log("tcr b4", tcr);

        // And show that the TCR goes down once you claim
        cdpManager.applyPendingGlobalState();

        uint256 tcrAfter = cdpManager.getTCR(_curPrice);
        console.log("tcrAfter", tcrAfter);

        assertLt(tcrAfter, tcr, "TCR didn't decrease");
    }

    function _tryOpenCdp(address _user, uint _coll, uint _debt) internal returns (bytes32) {
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
        cdpCR = cdpCR % 135e16; // Anything above is not meaningful since it drives the TCR above
        console.log("cdpCR", cdpCR);

        uint _curPrice = priceFeedMock.getPrice();

        // 2) Given an initial deposit that matches the attacker capital, that is very close to CCR
        uint256 coll1 = _utils.calculateCollAmount(systemDebtAmount, _curPrice, 136e16); // Literally at the edge

        bytes32 cdpId1 = _openTestCDP(users[0], coll1, systemDebtAmount);
        console.log("tcrAfterOpen Base", cdpManager.getTCR(_curPrice));

        // Get TCR
        uint256 tcr = cdpManager.getTCR(_curPrice);

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
            console.log("tcrAfterOpen Victim", cdpManager.getTCR(_curPrice));
        }

        // Once a CDP is open
        // Just take some yield
        // NOTE: We must do this here due to `updateCdpRewardSnapshots` resynching the index after each open
        {
            uint _curIndex = collateral.getPooledEthByShares(1e18);
            uint _newIndex = _curIndex + 5e16;
            collateral.setEthPerShare(_newIndex);
            uint _tcr = cdpManager.getTCR(_curPrice);

            // reference https://github.com/Badger-Finance/ebtc/pull/456#issuecomment-1566821518
            uint _requiredDeltaIdxTriggeRM = (((_newIndex * (_tcr - cdpManager.CCR())) / _tcr) *
                cdpManager.MAX_REWARD_SPLIT()) / cdpManager.stakingRewardSplit();

            // hack manipulation to sync global index in attacker's benefit
            uint _oldIdx = _newIndex - _requiredDeltaIdxTriggeRM - 1234567890;
            collateral.setEthPerShare(_oldIdx);
            cdpManager.applyPendingGlobalState();
            console.log("_oldIndex:", cdpManager.stFPPSg());
            assertEq(_oldIdx, cdpManager.stFPPSg());
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
            console.log("tcrAfterOpen Attacker", cdpManager.getTCR(_curPrice));
        }

        // Now we take the split
        cdpManager.applyPendingGlobalState();

        uint256 tcrAfter = cdpManager.getTCR(_curPrice);
        console.log("tcrAfter claim", tcrAfter);

        // Now we're in recovery mode so there exist a value such that a liquidation can be triggered willingly by the attacker
        assertLt(tcrAfter, 1250000000000000000);
    }

    // Padding Deposits -> W/e, prob 300% CR
    // Victim Deposits -> Leverage to 110
    // Attacker Brings TCR close to Recovery Mode -> Basically 110 as well
    // Attacker liquidates victim
    // Change the TCR to see different results
    function test_canNeverTriggerRMManual() public {
        uint256 debtAmt = 1e20; // TODO: Consider fuzz

        vm.assume(debtAmt > 1e18);

        uint _curPrice = priceFeedMock.getPrice();

        uint256 coll1 = _utils.calculateCollAmount(debtAmt, _curPrice, 136e16); // Literally at the edge

        bytes32 cdpId1 = _openTestCDP(users[0], coll1, debtAmt);
        console.log("tcrAfterOpen Base", cdpManager.getTCR(_curPrice));

        // Get TCR
        uint256 tcr = cdpManager.getTCR(_curPrice);

        // Deposit and bring TCR to RM

        // 1% of amt
        uint256 victimAmount = debtAmt / 100;
        console.log("victimAmount", victimAmount);

        // Levered to the tits
        uint256 collVictim = _utils.calculateCollAmount(victimAmount, _curPrice, 111e16);
        console.log("collVictim", collVictim);
        bytes32 cdpIdVictm = _openTestCDP(users[0], collVictim, victimAmount);
        console.log("tcrAfterOpen Victim", cdpManager.getTCR(_curPrice));

        // Once a CDP is open
        // Just take some yield
        // NOTE: We must do this here due to `updateCdpRewardSnapshots` resynching the index after each open
        uint _curIndex = collateral.getPooledEthByShares(1e18);
        uint _newIndex = _curIndex + 5e16;
        collateral.setEthPerShare(_newIndex);

        // Attacker opens CDP to push to barely to RM
        uint256 attackerDebtAmount = debtAmt; // AMT matches increase in value so we decrease TCR
        // 1214e15 makes the tx revert due to change in TCR
        // 125e16 is safe but the liquidation reverts

        // NOTE: We cannot trigger RM, but this still reverts since it's too strong of a negative push
        uint256 collAttacker = _utils.calculateCollAmount(attackerDebtAmount, _curPrice, 130e16);

        bytes32 cdpIdAttacker = _expectCdpRevert(users[0], collAttacker, attackerDebtAmount);
        console.log("tcrAfterOpen Attacker", cdpManager.getTCR(_curPrice));

        // Now we take the split
        cdpManager.applyPendingGlobalState();

        uint256 tcrAfter = cdpManager.getTCR(_curPrice);
        console.log("tcrAfter claim", tcrAfter);

        // We're not in recovery mode
        assertGt(tcrAfter, 1250000000000000000);

        vm.startPrank(users[0]);
        vm.expectRevert(); // NOTE: We expect revert here, meaning the operation is safe
        cdpManager.liquidate(cdpIdVictm);
        uint256 tcrEnd = cdpManager.getTCR(_curPrice);
        console.log("tcrEnd liquidation", tcrEnd);
        assertGt(tcrEnd, 1250000000000000000);
    }

    function _expectCdpRevert(address _user, uint _coll, uint _debt) internal returns (bytes32) {
        dealCollateral(_user, _coll);
        vm.startPrank(_user);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        vm.expectRevert();
        bytes32 _cdpId = borrowerOperations.openCdp(_debt, bytes32(0), bytes32(0), _coll);
        vm.stopPrank();
        return _cdpId;
    }
}
