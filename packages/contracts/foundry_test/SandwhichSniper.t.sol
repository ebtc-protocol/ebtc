pragma solidity 0.8.17;

import {console2 as console} from "forge-std/console2.sol";

import {eBTCBaseFixture} from "./BaseFixture.sol";

contract SandWhichSniperTest is eBTCBaseFixture {
    address payable[] users;

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

    // Padding Deposits -> W/e, prob 300% CR
    // Victim Deposits -> Leverage to 110
    // Attacker Brings TCR close to Recovery Mode -> Basically 110 as well
    // Attacker liquidates victim
    function test_snipeViaPriceDradwown() public {
        uint256 debtAmt = 1e20; // TODO: Consider fuzz

        vm.assume(debtAmt > 1e18);

        /** SETUP */
        // Rebase collateral so it's never 1/1
        uint _curIndex = collateral.getPooledEthByShares(1e18);
        uint _newIndex = _curIndex + 5e16;
        collateral.setEthPerShare(_newIndex);

        // Base Deposits
        uint _curPrice = priceFeedMock.getPrice();
        uint256 coll1 = _utils.calculateCollAmount(debtAmt, _curPrice, 126e16); // Literally at the edge, for similicity

        bytes32 cdpId1 = _openTestCDP(users[0], coll1, debtAmt);
        console.log("tcrAfterOpen Base", cdpManager.getTCR(_curPrice));

        // Get TCR
        uint256 tcr = cdpManager.getTCR(_curPrice);

        // Deposit and bring TCR to RM

        /** VICTIM */
        uint256 victimAmount = debtAmt / 2;
        console.log("victimAmount", victimAmount);

        // Levered to the tits
        uint256 collVictim = _utils.calculateCollAmount(victimAmount, _curPrice, 124e16); // Liquidatable only in RM
        console.log("collVictim", collVictim);
        bytes32 cdpIdVictim = _openTestCDP(users[0], collVictim, victimAmount);
        console.log("tcrAfterOpen Victim", cdpManager.getTCR(_curPrice));

        /** SANDWHICH 1 */
        // Attacker opens CDP to push to barely to RM
        uint256 attackerDebtAmount = debtAmt;
        console.log("attackerDebtAmount", attackerDebtAmount);
        uint256 collAttacker = _utils.calculateCollAmount(attackerDebtAmount, _curPrice, 125e16); // Safe CR, since it's price that moves to liquidations
        console.log("_curPrice", _curPrice);
        console.log("collAttacker", collAttacker);
        console.log(
            "CR Attacker",
            ((collAttacker - _utils.LIQUIDATOR_REWARD()) * _curPrice) / attackerDebtAmount
        );
        bytes32 cdpIdAttacker = _openTestCDP(users[0], collAttacker, attackerDebtAmount);
        console.log("tcrAfterOpen Attacker", cdpManager.getTCR(_curPrice));

        /** SANDWHICH 2 */
        // 1% drawdown for simiplicity
        priceFeedMock.setPrice((_curPrice * 99) / 100);
        uint256 _newPrice = priceFeedMock.getPrice();

        uint256 tcrAfter = cdpManager.getTCR(_newPrice);
        console.log("tcrAfter claim", tcrAfter);

        // We're in recovery mode
        assertLt(tcrAfter, 1250000000000000000);

        // We can now liquidate victim
        /** SANDWHICH 3 */
        vm.startPrank(users[0]);
        vm.expectRevert("Grace period not started, call `notifyStartGracePeriod`");
        cdpManager.liquidate(cdpIdVictim);
        uint256 tcrEnd = cdpManager.getTCR(_newPrice);
        console.log("tcrEnd liquidation", tcrEnd);
        assertEq(cdpManager.getCdpStatus(cdpIdVictim), 1); //Still Open (And safe until end of Grace Period)
    }
}
