// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import {Properties} from "../contracts/TestContracts/invariants/Properties.sol";
import {IERC20} from "../contracts/Dependencies/IERC20.sol";
import {IERC3156FlashBorrower} from "../contracts/Interfaces/IERC3156FlashBorrower.sol";
import {TargetFunctions} from "../contracts/TestContracts/invariants/TargetFunctions.sol";
import {TargetContractSetup} from "../contracts/TestContracts/invariants/TargetContractSetup.sol";
import {FoundryAsserts} from "./utils/FoundryAsserts.sol";

/*
 * Test suite that converts from echidna "fuzz tests" to foundry "unit tests"
 * The objective is to go from random values to hardcoded values that can be analyzed more easily
 */
contract EToFoundry is
    Test,
    TargetContractSetup,
    FoundryAsserts,
    TargetFunctions,
    IERC3156FlashBorrower
{
    modifier setup() override {
        _;
    }

    function setUp() public {
        _setUp();
        _setUpActors();
        actor = actors[USER1];
        vm.startPrank(address(actor));
    }

    /// @dev Example of test for invariant
    function testBO05() public {
        openCdp(0, 1);
        setEthPerShare(0);
        addColl(89746347972992101541, 29594050145240);
        openCdp(0, 1);
        uint256 balanceBefore = collateral.balanceOf(address(actor));
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(actor), 0);
        uint256 cdpCollBefore = cdpManager.getCdpCollShares(_cdpId);
        uint256 liquidatorRewardSharesBefore = cdpManager.getCdpLiquidatorRewardShares(_cdpId);
        console2.log("before %s", balanceBefore);
        closeCdp(0);
        uint256 balanceAfter = collateral.balanceOf(address(actor));
        console2.log("after %s %s %s %s", balanceAfter, cdpCollBefore, liquidatorRewardSharesBefore);
        console2.log(
            "isApproximateEq? %s",
            isApproximateEq(
                balanceBefore +
                    collateral.getPooledEthByShares(cdpCollBefore + liquidatorRewardSharesBefore),
                balanceAfter,
                0.0e18
            )
        );
    }

    function _getValue() internal returns (uint256) {
        uint256 currentPrice = priceFeedMock.getPrice();

        uint256 totalColl = cdpManager.getSystemCollShares();
        uint256 totalDebt = cdpManager.getSystemDebt();
        uint256 totalCollFeeRecipient = activePool.getFeeRecipientClaimableCollShares();

        uint256 surplusColl = collSurplusPool.getTotalSurplusCollShares();

        uint256 totalValue = ((totalCollFeeRecipient * currentPrice) / 1e18) +
            ((totalColl * currentPrice) / 1e18) +
            ((surplusColl * currentPrice) / 1e18) -
            totalDebt;
        return totalValue;
    }

    event DebugBytes32(string name, bytes32 v);

    function testLS01() public {
        openCdp(36, 1);
        openCdp(
            44123017348912576180317745456189857733780478953582148509153709115247120891823,
            200000000000000000
        );
        setPrice(76198417712734018461546705290463707597643164940764698001817170623344387673136);
        setPrice(87405135521336340527122586343533021380622128208084101094060450788350832849209);
        setEthPerShare(
            103391299437296880034081343669838720993649506068708991825092080752669230555147
        );
        setEthPerShare(
            115792089237316195423570985008687907853269984665640564039447584007913129639936
        );
        adjustCdp(
            17557140364109963148061446080805750691763165277705558547368821385485334844592,
            65536,
            52150574133267500752110179891739993549417328753147422856083931774206217442908,
            false
        );
        setEthPerShare(131032);
        openCdp(1273085944690585089466618884538704481757146938342, 7428);
        setEthPerShare(
            115792089237316195423570985008687907853269984665640564039457584007913129639918
        );

        // SEE invariant_LS_01
        uint256 n = cdpManager.getActiveCdpsCount();

        // Get
        uint256 price = priceFeedMock.getPrice();

        // Get lists
        bytes32[] memory cdpsFromCurrent = liquidationSequencer.sequenceLiqToBatchLiqWithPrice(
            n,
            price
        );
        bytes32[] memory cdpsSynced = syncedLiquidationSequencer.sequenceLiqToBatchLiqWithPrice(
            n,
            price
        );

        for (uint256 i; i < cdpsFromCurrent.length; i++) {
            emit DebugBytes32("cdpsFromCurrent[i]", cdpsFromCurrent[i]);
        }
        for (uint256 i; i < cdpsSynced.length; i++) {
            emit DebugBytes32("cdpsSynced[i]", cdpsSynced[i]);
        }

        uint256 length = cdpsFromCurrent.length;
        assertEq(length, cdpsSynced.length, "Same Length");

        // Compare Lists
        for (uint256 i; i < length; i++) {
            // Find difference = broken
            console2.log("i", i);
            assertEq(cdpsFromCurrent[i], cdpsSynced[i], "Same Cdp");
        }
    }

    /**
     * 1) EchidnaTester.setEthPerShare(645326474426547203313410069153905908525362434357) (block=10, time=17, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000030000)
     *     2) EchidnaTester.setPrice(200) (block=43, time=58, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000010000)
     *     3) EchidnaTester.openCdp(15271506168544636618683946165347184908672584999956201311530805028234774281247, 525600000) (block=53316, time=581135, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000020000)
     *     4) EchidnaTester.setEthPerShare(34490286643335581993866445125615501807464041659106654042251963443032165120461) (block=53319, time=581142, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000030000)
     *     5) EchidnaTester.setPrice(72100039377333553285200231852034304471788766724978643708968246258805481443120) (block=53351, time=1118043, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000020000)
     *     6) EchidnaTester.openCdp(2, 999999999999999999) (block=77228, time=1142454, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000030000)
     *     7) EchidnaTester.setPrice(53613208255846312190970113690532613198662175001504036140235273976036627984403) (block=108595, time=1214284, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000030000)
     *     8) EchidnaTester.setEthPerShare(53885036727293763953039497818137962919540408473654007727202467955943039934842) (block=135098, time=1414579, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000020000)
     *     9) EchidnaTester.withdrawColl(64613413140793438003392705322981884782961011222878036826703269533463170986176, 9999999999744) (block=194809, time=1611187, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000030000)
     *     10) EchidnaTester.setEthPerShare(38654105012746982034204530442925091332196750429568734891400199507115192250853) (block=196570, time=1788109, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000030000)
     *     11) EchidnaTester.partialLiquidate(51745835282927565687010251523416875790034155913406312339604760725754223914917, 19) (block=228509, time=1844314, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000030000)
     *     12) EchidnaTester.setEthPerShare(79832022615203712424393490440177025697015516400034287083326403000335384151815) (block=232929, time=2127507, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000030000)
     *     13) EchidnaTester.partialLiquidate(257, 71149553722330727595372666179561318863321173766102370975927893395343749396843) (block=276132, time=2338894, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000030000)
     */
    function testBrokenLiquidationLoc() public {
        setEthPerShare(645326474426547203313410069153905908525362434357);
        vm.warp(block.timestamp + cdpManager.recoveryModeGracePeriodDuration() + 1);
        setPrice(200);
        vm.warp(block.timestamp + cdpManager.recoveryModeGracePeriodDuration() + 1);
        bytes32 randomCdp = openCdp(
            15271506168544636618683946165347184908672584999956201311530805028234774281247,
            525600000
        );
        vm.warp(block.timestamp + cdpManager.recoveryModeGracePeriodDuration() + 1);
        setEthPerShare(
            34490286643335581993866445125615501807464041659106654042251963443032165120461
        );
        vm.warp(block.timestamp + cdpManager.recoveryModeGracePeriodDuration() + 1);
        setPrice(72100039377333553285200231852034304471788766724978643708968246258805481443120);
        vm.warp(block.timestamp + cdpManager.recoveryModeGracePeriodDuration() + 1);
        openCdp(2, 999999999999999999);
        vm.warp(block.timestamp + cdpManager.recoveryModeGracePeriodDuration() + 1);
        setPrice(53613208255846312190970113690532613198662175001504036140235273976036627984403);
        vm.warp(block.timestamp + cdpManager.recoveryModeGracePeriodDuration() + 1);
        setEthPerShare(
            53885036727293763953039497818137962919540408473654007727202467955943039934842
        );
        vm.warp(block.timestamp + cdpManager.recoveryModeGracePeriodDuration() + 1);
        withdrawColl(
            64613413140793438003392705322981884782961011222878036826703269533463170986176,
            9999999999744
        );
        vm.warp(block.timestamp + cdpManager.recoveryModeGracePeriodDuration() + 1);
        setEthPerShare(
            38654105012746982034204530442925091332196750429568734891400199507115192250853
        );
        vm.warp(block.timestamp + cdpManager.recoveryModeGracePeriodDuration() + 1);
        partialLiquidate(
            51745835282927565687010251523416875790034155913406312339604760725754223914917,
            19
        );
        vm.warp(block.timestamp + cdpManager.recoveryModeGracePeriodDuration() + 1);
        setEthPerShare(
            79832022615203712424393490440177025697015516400034287083326403000335384151815
        );
        vm.warp(block.timestamp + cdpManager.recoveryModeGracePeriodDuration() + 1);
        bytes32 cdpToTrack = _getRandomCdp(257);
        // Accrue here (will trigger recovery mode due to index change)
        // cdpManager.syncGlobalAccountingAndGracePeriod(); /// @audit: Issue with invariants is we need this to change
        _before(cdpToTrack);
        partialLiquidate(
            257,
            71149553722330727595372666179561318863321173766102370975927893395343749396843
        );
        _after(cdpToTrack);

        console2.log("vars.newIcrBefore", vars.newIcrBefore);
        console2.log("cdpManager.MCR()", cdpManager.MCR());

        console2.log("vars.newIcrBefore", vars.newIcrBefore);
        console2.log("cdpManager.CCR()", cdpManager.CCR());
        console2.log("vars.isRecoveryModeBefore", vars.isRecoveryModeBefore);

        assertTrue(
            vars.newIcrBefore < cdpManager.MCR() ||
                (vars.newIcrBefore < cdpManager.CCR() && vars.isRecoveryModeBefore),
            "Mcr, ccr"
        );
    }

    function testPartialLiquidationCanCloseCDPS() public {
        openCdp(67534042799335353648407647554112468697195277953615236438520200454730440793371, 8);
        openCdp(
            115792089237316195423570985008687907853269984665640564039457584007913129639931,
            1000000000000000900
        );
        setEthPerShare(
            48542174391735010270995007834653745032392815149632706327135797120960854131722
        );
        setEthPerShare(40);
        console2.log("cdpManager.getActiveCdpsCount()", cdpManager.getActiveCdpsCount());
        partialLiquidate(
            10055443073786697780288631944863873711310414440862685961782620523444705292193,
            0
        );
        console2.log("cdpManager.getActiveCdpsCount()", cdpManager.getActiveCdpsCount());
    }

    function testBrokenImprovementofNICR() public {
        bytes32 cdpId = openCdp(36, 1);
        setEthPerShare(
            115792089237316195423570985008687907853269984665640564039456334007913129639936
        );
        uint256 beforeNICR = crLens.quoteRealNICR(cdpId);
        addColl(1, 10);
        uint256 afterNICR = crLens.quoteRealNICR(cdpId);

        assertGe(afterNICR, beforeNICR, "BO-03: Must increase NICR");
    }

    /**
     * 1) EchidnaTester.setEthPerShare(31656099540918703381915350012813182642308405422272958668865762453755205317560) (block=3966, time=264453, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000010000)
     *     2) EchidnaTester.openCdp(60831556551619617237480607135123444879160274018218144781759469227986909022036, 48) (block=8500, time=427094, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000030000)
     *     3) EchidnaTester.setEthPerShare(1000000000000000000) (block=28684, time=979712, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000010000)
     *     4) EchidnaTester.addColl(16, 115792089237316195423570985008687907853269984665640564039457584007913129508864) (block=54621, ti
     */

    function testBo03() public {
        setEthPerShare(
            31656099540918703381915350012813182642308405422272958668865762453755205317560
        );
        bytes32 firstCdp = openCdp(
            60831556551619617237480607135123444879160274018218144781759469227986909022036,
            48
        );
        setEthPerShare(1000000000000000000);
        // NO longer needs accrual here cause we check internal value
        // cdpManager.syncGlobalAccountingAndGracePeriod();
        _before(firstCdp);
        addColl(16, 115792089237316195423570985008687907853269984665640564039457584007913129508864);
        _after(firstCdp);
        assertGt(vars.nicrAfter, vars.nicrBefore, "GT");
    }

    

    /**
     * 1) EchidnaTester.setEthPerShare(86688896451552136001225523381455512999487671226724657278887281953146484774479) (block=32358, time=34290, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000030000)
     *     2) EchidnaTester.setEthPerShare(2) (block=33152, time=35290, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000020000)
     *     3) EchidnaTester.setPrice(53242692202139136259844779411728414198979339870792811349285416325947018641415) (block=69530, time=422332, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000030000)
     *     4) EchidnaTester.setEthPerShare(19) (block=108348, time=946492, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000020000)
     *     5) EchidnaTester.setEthPerShare(3) (block=127976, time=1333310, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000010000)
     *     6) EchidnaTester.openCdp(63481775631040330868488838440380883887548553786606511443800351945466791372972, 12) (block=139785, time=1437477, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000030000)
     *     7) EchidnaTester.openCdp(115275689634636763471407553554696230511651534645337120528720836289775559173670, 3400000000000000000) (block=157270, time=1643162, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000030000)
     *     8) EchidnaTester.setPrice(49955707469362902507454157297736832118868343942642399513960811609542965143241) (block=157307, time=1643202, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000020000)
     *     9) EchidnaTester.setEthPerShare(115792089237316195423570985008687907853269984665640564039457584007913129639935) (block=181185, time=1975696, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000010000)
     *     10) EchidnaTester.setPrice(115792089237316195423570985008687907853269984665640564039456584970154295856934) (block=181410, time=2328893, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000010000)
     *     11) EchidnaTester.setEthPerShare(2) (block=205279, time=2387142, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000010000)
     *     12) EchidnaTester.liquidateCdps(15271506168544636618683946165347184908672584999956201311530805028234774281247) (block=205385, time=2672544, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000030000)
     *     13) EchidnaTester.openCdp(110953018886617049369109243176193885383860427032951825314358709007138889273943, 4) (block=205390, time=2672554, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000010000)
     *     14) EchidnaTester.closeCdp(57413278564244504453191656087298467315431246439675010725238485654181166168124) (block=228276, time=3033171, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000030000)
     */

    function testBrokenInvariantFive() external {
        setEthPerShare(
            86688896451552136001225523381455512999487671226724657278887281953146484774479
        );
        setEthPerShare(2);
        setPrice(53242692202139136259844779411728414198979339870792811349285416325947018641415);
        setEthPerShare(19);
        setEthPerShare(3);
        openCdp(63481775631040330868488838440380883887548553786606511443800351945466791372972, 12);
        openCdp(
            115275689634636763471407553554696230511651534645337120528720836289775559173670,
            3400000000000000000
        );
        setPrice(49955707469362902507454157297736832118868343942642399513960811609542965143241);
        setEthPerShare(
            115792089237316195423570985008687907853269984665640564039457584007913129639935
        );
        setPrice(115792089237316195423570985008687907853269984665640564039456584970154295856934);
        setEthPerShare(2);
        vm.warp(block.timestamp + cdpManager.recoveryModeGracePeriodDuration() + 1);
        console.log("B4 Liquidation");
        console.log("B4 Liquidation");
        console.log("B4 Liquidation");
        console.log("B4 Liquidation");
        console.log("B4 Liquidation");
        console.log("B4 Liquidation");
        liquidateCdps(15271506168544636618683946165347184908672584999956201311530805028234774281247); // Redistribution here
        console.log("After Liquidation");
        console.log("After Liquidation");
        console.log("After Liquidation");
        console.log("After Liquidation");
        console.log("After Liquidation");
        console.log("After Liquidation");
        openCdp(110953018886617049369109243176193885383860427032951825314358709007138889273943, 4); // After this open you have 2 CDPs
        console.log("Before Close");
        console.log("Before Close");
        console.log("Before Close");
        console.log("Before Close");
        console.log("Before Close");
        closeCdp(57413278564244504453191656087298467315431246439675010725238485654181166168124); // After this you only have 1 CDP left
        console.log("After Close");

        // Accrue all cdps
        for (uint256 i; i < sortedCdps.cdpCountOf(address(actor)); i++) {
            cdpManager.syncAccounting(_getRandomCdp(i));
        }

        console.log("lastEBTCDebtErrorRedistribution", cdpManager.lastEBTCDebtErrorRedistribution());
        // 0.000000000002e18 = diff_tollerance
        assertTrue(invariant_AP_05(cdpManager, 1e10), "5");
    }

    function test_12_third() public {
        openCdp(115792089237316195423570985008687907853269984665640564039457584007913129443328, 96);
        setEthPerShare(4);
        openCdp(
            33368919118782005608721287363227282769956823662243832624194025284013169799183,
            1000000000000000000
        );
        setEthPerShare(4);
        setEthPerShare(5);
        setEthPerShare(5);
        bytes32 cdpId = _getRandomCdp(1);
        _before(cdpId);
        liquidateCdps(1209600);
        _after(cdpId);

        // Fails if done with 0
        // Passes if done with 1
        // if (
        //     vars.newIcrBefore >= cdpManager.LICR() // 103% else liquidating locks in bad debt | // This fixes the check
        // ) {
        //     assertGe(vars.newTcrAfter, vars.newTcrBefore, "l_12_expected"); // This invariant should break (because it's underwater)
        // }
    }

    function test_12_echidna() public {
        openCdp(377643985018801171895083631724856447701596730093, 1);
        openCdp(91089814, 691043319023089930);
        setPrice(0);
        setPrice(1879);
        setPrice(0);
        setPrice(26763297809616538244014300302511745532211487653003070172849205502011);
        setEthPerShare(0);
        setPrice(0);

        uint256 preCastTcr = crLens.quoteRealTCR();
        console2.log("preCastTcr", preCastTcr);

        bytes32 targetCdpId = _getRandomCdp(1);
        uint256 precastIcr = crLens.quoteRealICR(targetCdpId);
        console2.log("precastIcr", precastIcr);

        _before(targetCdpId);
        // // Trigger RM
        // cdpManager.syncGlobalAccountingAndGracePeriod();
        // vm.warp(block.timestamp + cdpManager.recoveryModeGracePeriodDuration() + 1);
        partialLiquidate(1, 73813787571110962545934699418512877744225252688696);
        _after(targetCdpId);

        console2.log("vars.newTcrAfter", vars.newTcrAfter);
        console2.log("vars.newTcrBefore", vars.newTcrBefore);

        console2.log("vars.newIcrBefore", vars.newIcrBefore);

        if (
            vars.newIcrBefore >= cdpManager.LICR() // 103% else liquidating locks in bad debt | // This fixes the check
        ) {
            assertGe(vars.newTcrAfter, vars.newTcrBefore, "l_12_expected"); // This invariant should break (because it's underwater)
        }
    }

    function test_12_another() public {
        setEthPerShare(
            88579253913579105526224682439871956245251055820069560960533630083319393319956
        );
        openCdp(0, 1);
        setEthPerShare(0);
        setEthPerShare(284895597005704535247502731285036474904903416448491451905968026529048971064);
        openCdp(0, 1222182215362783394);
        setEthPerShare(8638659756498750496833243577353157099794911949450027267768114415513163468546);
        setEthPerShare(145549758451909858);
        setEthPerShare(1817115128564573399596756316693876822239412011203157237758517879834095793);
        bytes32 targetCdpId = _getRandomCdp(1);

        _before(targetCdpId);
        // // Trigger RM
        // cdpManager.syncGlobalAccountingAndGracePeriod();
        // vm.warp(block.timestamp + cdpManager.recoveryModeGracePeriodDuration() + 1);
        partialLiquidate(1, 77);
        _after(targetCdpId);

        if (
            vars.newIcrBefore >= cdpManager.LICR() // 103% else liquidating locks in bad debt | // This fixes the check
        ) {
            assertGe(vars.newTcrAfter, vars.newTcrBefore, "l_12_expected"); // This invariant should break (because it's underwater)
        }
    }

    

    function testGeneral14() public {
        setEthPerShare(12);
        openCdp(
            115792089237316195423570985008687907853269984665640564039457584007913129639935,
            6383
        );

        assertTrue(invariant_GENERAL_14(crLens, cdpManager, sortedCdps), "G-14");
    }


    /// @dev Debunk false positives for L-12
    ///     These will happen exclusively if all CDPs are Underwater, and instead of liquidating the riskiest, the one above is liquidated
    // function testL12Debunk() public {
    //     openCdp(92917081472816941941184964779154375129173708512214393931667457813751914161634, 20);
    //     openCdp(
    //         14357740897988057106500935390524526462940912496206879728999588820331360643957,
    //         1000000000000000256
    //     );
    //     openCdp(
    //         14357740897988057106500935390524526462940912496206879728999588820331360643957,
    //         1000000000000000256
    //     );
    //     setPrice(74629061016018350331730450585755319739830762911693635404016285330120218663634);
    //     setEthPerShare(
    //         69007891472983439489040112860682059911742470146824120203672378698503585549508
    //     );
    //     withdrawColl(
    //         2000000,
    //         49955707469362902507454157299064623548400035506668976771172421598874183583296
    //     );
    //     setPrice(0);
    //     closeCdp(79284842807605095858149520102903844594789751342105937047923718189601373042235);
    //     setEthPerShare(0);
    //     setPrice(3);
    //     bytes32 cdpId = _getRandomCdp(
    //         115792089237316195423570985008193886025822902127156998188347748450894401986382
    //     );

    //     console2.log("vars.newTcrBefore", vars.newTcrBefore);
    //     console2.log("vars.newTcrAfter", vars.newTcrAfter);

    //     uint256 newIcr;
    //     bytes32 currentCdp = sortedCdps.getFirst();

    //     while (currentCdp != bytes32(0)) {
    //         console2.log("ICR ICR", crLens.quoteRealICR(currentCdp));
    //         currentCdp = sortedCdps.getNext(currentCdp);
    //     }

    //     _before(cdpId);
    //     liquidate(115792089237316195423570985008193886025822902127156998188347748450894401986382);
    //     _after(cdpId);

    //     // If every CDP is liquidatable
    //     // Then you liquidate the 2nd
    //     // And break the invariant

    //     if (
    //         vars.newIcrBefore >= cdpManager.LICR() // 103% else liquidating locks in bad debt
    //     ) {
    //         // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/5
    //         gte(vars.newTcrAfter, vars.newTcrBefore, L_12);
    //     }
    // }

    function testGeneral08() public {
        openCdp(72782931752105455104411619997485041164599478189648810093633428138496255693523, 544);
        addColl(
            1100000000000000000000000000000000000000,
            115792089237316195423570985008687907853269984665640564039457584007913129639935
        );
        setEthPerShare(
            56373508540503437814647566068284858699061461229979853420083514714791232396417
        );
        repayDebt(8929450416115957309093038580112496615268409790537290379189142570379833892626, 256);

        assertTrue(invariant_GENERAL_08(cdpManager, sortedCdps, priceFeedMock, collateral), "G-08");
    }

    function testLiquidate() public {
        bytes32 _cdpId1 = openCdp(0, 1);
        bytes32 _cdpId2 = openCdp(0, 138503371414274893);
        setEthPerShare(25767972494220010983395751604996338730092976238166499268284213460476321971);
        setEthPerShare(6227937557915401158291460378146315744099125361417328696236621337846631);
        setPrice(0);
        uint256 _price = priceFeedMock.getPrice();
        console2.log(
            "\tCR before",
            cdpManager.getCachedTCR(_price),
            cdpManager.getCachedICR(_cdpId1, _price),
            cdpManager.getCachedICR(_cdpId2, _price)
        );
        console2.log(
            "CDP1",
            uint256(sortedCdps.getFirst()),
            cdpManager.getCachedICR(sortedCdps.getFirst(), _price)
        );
        liquidateCdps(18144554526834239235);
        console2.log(
            "CDP1",
            uint256(sortedCdps.getFirst()),
            cdpManager.getCachedICR(sortedCdps.getFirst(), _price)
        );
    }

    function testTcrMustIncreaseAfterRepayment() public {
        openCdp(13981380896748761892053706028661380888937876551972584966356379645, 23);
        setEthPerShare(55516200804822679866310029419499170992281118179349982013988952907);
        repayDebt(1, 509846657665200610349434642309205663062);
    }

    

    // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/15
    // function testPropertySL05() public {
    //     setEthPerShare(
    //         12137138735364853393659783413495902950573335538668689540776328203983925215811
    //     );
    //     setEthPerShare(30631887070343426798280082917191654654292863364863423646265020494943238699);
    //     setEthPerShare(776978999485790388950919620588735464671614128565904936170116473650448744381);
    //     openCdp(168266871339698218615133335629239858353993370046701339713750467499, 1);
    //     setEthPerShare(
    //         18259119993128374494182960141815059756667443030056035825036320914502997177865
    //     );
    //     addColl(
    //         7128974394460579557571027269632372427504086125697185719639350284139296986,
    //         53241717733798681974905139247559310444497207854177943207741265181147256271
    //     );
    //     openCdp(
    //         37635557627948612150381079279416828011988176534495127519810996522075020800647,
    //         136472217300866767
    //     );
    //     setEthPerShare(445556188509986934837462424);
    //     openCdp(12181230440821352134148880356120823470441483581757, 1);
    //     setEthPerShare(612268882000635712391494911936034158156169162782123690926313314401353750575);
    //     vm.warp(block.timestamp + cdpManager.recoveryModeGracePeriodDuration() + 1);
    //     bytes32 currentCdp = sortedCdps.getFirst();
    //     uint256 i = 0;
    //     uint256 _price = priceFeedMock.getPrice();
    //     console2.log("\tbefore");

    //     uint256 newIcr;

    //     while (currentCdp != bytes32(0)) {
    //         newIcr = crLens.quoteRealICR(currentCdp);

    //         console2.log("\t", i++, cdpManager.getCachedICR(currentCdp, _price), newIcr);
    //         currentCdp = sortedCdps.getNext(currentCdp);
    //     }
    //     _before(bytes32(0));
    //     liquidateCdps(0);
    //     _after(bytes32(0));
    //     console2.log(_diff());
    //     console2.log("\tafter");
    //     i = 0;
    //     currentCdp = sortedCdps.getFirst();
    //     while (currentCdp != bytes32(0)) {
    //         newIcr = crLens.quoteRealICR(currentCdp);

    //         console2.log("\t", i++, cdpManager.getCachedICR(currentCdp, _price), newIcr);
    //         currentCdp = sortedCdps.getNext(currentCdp);
    //     }
    //     assertTrue(invariant_SL_05(crLens, cdpManager, priceFeedMock, sortedCdps), SL_05);
    // }

    function testF01() public {
        openCdp(98395894838500698392817722927941537132848065121834445032333865318330537647396, 8);
        setEthPerShare(
            115792089237316195423570985008687907853269984665640564039417584007913129639936
        );

        vm.stopPrank(); // NOTE: NEcessary to avoid prank error
        setGovernanceParameters(
            26867618863262410052765999477726257874446598077054247881181555941856098176126,
            80691838055579444843664038389770275836658310912423649719692389195983842013783
        );

        // TODO: stop prank again?
        setGovernanceParameters(
            1273085944690585089466618884538704481757146938342,
            73117119168387963680367060438159427411497267004306122806373332532305103240544
        );

        gte(vars.feeRecipientTotalCollAfter, vars.feeRecipientTotalCollBefore, "F-12 as");
    }

    function get_cdp(uint256 _i) internal returns (bytes32) {
        uint256 numberOfCdps = sortedCdps.cdpCountOf(address(actor));

        _i = between(_i, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(actor), _i);

        return _cdpId;
    }

    // callback for flashloan
    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external override returns (bytes32) {
        if (data.length != 0) {
            (address[] memory _targets, bytes[] memory _calldatas) = abi.decode(
                data,
                (address[], bytes[])
            );
            for (uint256 i = 0; i < _targets.length; ++i) {
                (bool success, bytes memory returnData) = address(_targets[i]).call(_calldatas[i]);
                require(success, _getRevertMsg(returnData));
            }
        }

        IERC20(token).approve(msg.sender, amount + fee);

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}
