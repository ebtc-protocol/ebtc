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
     * 1) EchidnaTester.openCdp(5, 9) (block=21034, time=230044, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000030000)
     *     2) EchidnaTester.openCdp(84262773986715970128580444052678471626722414870282791794979066159115554213330, 1030000000000000000) (block=24528, time=400319, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000010000)
     *     3) EchidnaTester.setPrice(62851218183508081866601323998844678683340852927274212763025381189284030175116) (block=36605, time=452175, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000030000)
     *     4) EchidnaTester.setEthPerShare(106776231264650488527396238935264109957201160064867503889176542731952275025143) (block=36605, time=452175, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000030000)
     *     5) EchidnaTester.openCdp(76780224446527678697820911257670310585293087149232760248922738678857400527227, 7428) (block=50619, time=633086, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000020000)
     *     6) EchidnaTester.setEthPerShare(115792089237316195423570985008687907853269984665640564039457584007913129639917) (block=50619, time=633086, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000020000)
     *     7) EchidnaTester.liquidateCdps(2) (block=74280, time=1191523, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000010000)
     *     8) EchidnaTester.redeemCollateral(46569391515833093424627317458962525217707765577058029473090855375431272918988, 0, 14229479364104465894069837803513832929478804353344870192956752971009762732884, 84531756315918705342020165315694316831239657177696340854927806097286510294339) (block=130886, time=1730710, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000010000)
     */

    function testCdpm04() public {
        bytes32 firstCdp = openCdp(1999999999998000000, 900);
        setEthPerShare(1250000000000000000);
        openCdp(8000000000000000000, 2000000000000000000);
        openCdp(9, 24);
        setEthPerShare(
            115792089237316195423570985008687907853269984665640564039457494007913129639936
        );
        setEthPerShare(
            49955707469362902507454157297736832118868343942642399513960811609542965143241
        );
        setEthPerShare(196608);
        uint256 valueBeforeLiq = _getValue();
        liquidateCdps(23427001867620538865025159276465004083966829863592832258101893764170212492148);
        uint256 valueBeforeRedeem = _getValue();

        // AP + Etc...
        uint256 count = sortedCdps.cdpCountOf(address(this));
        _before(firstCdp);
        redeemCollateral(
            115792089237316195423570985008687907853269984665640564039457584007913129639934,
            135941972438511685695082801964033710960734498785361969386688073429943393822,
            115792089237316195423570985008687907853269984665640564039457584007913129638361,
            23850712709987925641283238546894891155169667596125834416480726033458037299273
        );
        _after(firstCdp);
        uint256 countAfter = sortedCdps.cdpCountOf(address(this));
        uint256 endValue = _getValue();

        console2.log("count", count);
        console2.log("countAfter", countAfter);

        // Log values
        console2.log("valueBeforeLiq", valueBeforeLiq);
        console2.log("valueBeforeRedeem", valueBeforeRedeem);
        console2.log("endValue", endValue);

        assertGe(endValue, valueBeforeRedeem, "Value");
        assertTrue(invariant_CDPM_04(vars), "Cdp-04");
    }

    function testCdpm04AnotheAdditional() public {
        // https://fuzzy-fyi-output.s3.us-east-1.amazonaws.com/job/fe1496f7-cfb8-4376-b7e5-05ffa4ee7d6f/logs.txt?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Content-Sha256=UNSIGNED-PAYLOAD&X-Amz-Credential=AKIA46FZI5L426LZ5IFS%2F20231002%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=20231002T163253Z&X-Amz-Expires=3600&X-Amz-Signature=050d7e5fd68eb61a99b521314d454bbdf2732eee66c14ba09fe639db1fc29c17&X-Amz-SignedHeaders=host&x-id=GetObject

        setEthPerShare(
            23616972738430218693583668677955189858970801833460037124433618006874437290965
        );
        setEthPerShare(2989419041988439887121753128827724139087959435872810892689978202619186667695);
        openCdp(0, 1);
        // withdrawColl(0,12822405550995444841658104866515);
        setEthPerShare(0);
        setEthPerShare(0);
        addColl(
            50968176814569943267438244148340830381999672120914652414769163921298475367,
            10200800384557968531078276525531536582718865772597718390226839025308055544254
        );
        withdrawDebt(273760318116041220, 1);
        openCdp(
            7239597706248181732406841427528500623622848712137431728409551405830913454985,
            131091200944273154
        );
        redeemCollateral(
            532196406196528562753434746700243676344227539938048054616104670496,
            4890020780892971426953827393838177353120388721150155457442057090730,
            79351417069918029012441131522214482912497779320630528396640923848,
            721365069108257478864098679538511406284762242833640043187158267755
        );

        assertTrue(invariant_CDPM_04(vars), "Cdp-04");
    }

    function testCdpm04AnotherFalsePositive() public {
        // https://fuzzy-fyi-output.s3.us-east-1.amazonaws.com/job/4be81955-d57f-4cab-a2c1-17a1f4cb8905/logs.txt?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Content-Sha256=UNSIGNED-PAYLOAD&X-Amz-Credential=AKIA46FZI5L426LZ5IFS%2F20231002%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=20231002T163253Z&X-Amz-Expires=3600&X-Amz-Signature=234ab66b56a96bdc934c02f1cfe311502e0cc1dbb28ea9d43f8648b19963a0ea&X-Amz-SignedHeaders=host&x-id=GetObject

        setEthPerShare(
            23616972738430218693583668677955189858970801833460037124433618006874437290965
        );
        setEthPerShare(2989419041988439887121753128827724139087959435872810892689978202619186667695);
        openCdp(0, 1);
        setEthPerShare(0);
        setEthPerShare(0);
        addColl(
            48372588722475458336871280420998083314865307176782653091349042960126337674,
            6905847517024232365818322099823885743692319936861589798779382113699392850729
        );
        withdrawDebt(260972099767576353, 1);
        openCdp(
            8515157922397009703417557607681739958843134455800791473869353135908031450320,
            131251319846597049
        );
        redeemCollateral(
            289058276040013882279825268963168994859580940307359182338590061533,
            721412354899084084812938159596061041337963802121256850421410071451651,
            746364832991185847452451142827121750634362670833976451629299654241,
            1279293321452559466690908804649893886462942558282969306040083134065919
        );

        assertTrue(invariant_CDPM_04(vars), "Cdp-04");
    }

    function testCdpm04AFalsePositiveNew() public {
        // https://fuzzy-fyi-output.s3.us-east-1.amazonaws.com/job/4be81955-d57f-4cab-a2c1-17a1f4cb8905/logs.txt?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Content-Sha256=UNSIGNED-PAYLOAD&X-Amz-Credential=AKIA46FZI5L426LZ5IFS%2F20231002%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=20231002T163253Z&X-Amz-Expires=3600&X-Amz-Signature=234ab66b56a96bdc934c02f1cfe311502e0cc1dbb28ea9d43f8648b19963a0ea&X-Amz-SignedHeaders=host&x-id=GetObject
        setEthPerShare(
            23616972738430218693583668677955189858970801833460037124433618006874437290965
        );
        setEthPerShare(2989419041988439887121753128827724139087959435872810892689978202619186667695);
        openCdp(0, 1);
        setEthPerShare(0);
        setEthPerShare(0);
        addColl(
            48372588722475458336871280420998083314865307176782653091349042960126337674,
            6905847517024232365818322099823885743692319936861589798779382113699392850729
        );
        withdrawDebt(260972099767576353, 1);
        openCdp(
            8515157922397009703417557607681739958843134455800791473869353135908031450320,
            131251319846597049
        );

        console2.log("");
        console2.log("");
        console2.log("Before");
        bytes32 currentCdp = sortedCdps.getFirst();

        while (currentCdp != bytes32(0)) {
            (uint256 debtBefore, uint256 collBefore) = cdpManager.getSyncedDebtAndCollShares(
                currentCdp
            );
            console2.log("debtBefore", debtBefore);
            console2.log("collBefore", collBefore);

            currentCdp = sortedCdps.getNext(currentCdp);
        }

        /**
        PYTHON
        >>> activePoolCollBefore = 11166023933140299463
        >>> collSurplusPoolBefore = 0
        >>> feeRecipientTotalCollBefore = 0
        >>> activePoolDebtBefore = 392223419614173403
        >>> activePoolCollAfter = 8251456769332992047
        >>> collSurplusPoolAfter = 640951562503257069
        >>> feeRecipientTotalCollAfter = 441787493250854661
        >>> activePoolDebtAfter = 260972099767576354
         */

        redeemCollateral(
            289058276040013882279825268963168994859580940307359182338590061533,
            721412354899084084812938159596061041337963802121256850421410071451651,
            746364832991185847452451142827121750634362670833976451629299654241,
            1279293321452559466690908804649893886462942558282969306040083134065919
        );

        // Debug all CDPs
        console2.log("");
        console2.log("");
        console2.log("After");
        currentCdp = sortedCdps.getFirst();

        while (currentCdp != bytes32(0)) {
            (uint256 debtBefore, uint256 collBefore) = cdpManager.getSyncedDebtAndCollShares(
                currentCdp
            );
            console2.log("debtBefore", debtBefore);
            console2.log("collBefore", collBefore);

            currentCdp = sortedCdps.getNext(currentCdp);
        }

        assertTrue(invariant_CDPM_04(vars), "Cdp-04");

        uint256 beforeValue = ((vars.activePoolCollBefore +
            vars.collSurplusPoolBefore +
            vars.feeRecipientTotalCollBefore) * vars.priceBefore) /
            1e18 -
            vars.activePoolDebtBefore;

        uint256 afterValue = ((vars.activePoolCollAfter +
            vars.collSurplusPoolAfter +
            vars.feeRecipientTotalCollAfter) * vars.priceAfter) /
            1e18 -
            vars.activePoolDebtAfter;

        console2.log("vars.priceBefore", vars.priceBefore);
        console2.log("vars.priceAfter", vars.priceAfter);

        console2.log("vars.activePoolCollBefore", vars.activePoolCollBefore);
        console2.log("vars.collSurplusPoolBefore", vars.collSurplusPoolBefore);
        console2.log("vars.feeRecipientTotalCollBefore", vars.feeRecipientTotalCollBefore);
        console2.log("vars.activePoolDebtBefore", vars.activePoolDebtBefore);
        console2.log("beforeValue", beforeValue);

        console2.log("vars.activePoolCollAfter", vars.activePoolCollAfter);
        console2.log("vars.collSurplusPoolAfter", vars.collSurplusPoolAfter);
        console2.log("vars.feeRecipientTotalCollAfter", vars.feeRecipientTotalCollAfter);
        console2.log("vars.activePoolDebtAfter", vars.activePoolDebtAfter);
        console2.log("afterValue", afterValue);
    }

    function testEchidnaCdpm04() public {
        setEthPerShare(1000);
        openCdp(4524377229654262, 1);
        setEthPerShare(590);
        setPrice(62585740236349503659258829433448686991336332142246890573120200334913125020112);
        openCdp(2657952782541674, 1);
        openCdp(172506625533584, 9);
        openCdp(
            70904944448444413766718256551751006946686858338215426210784442951345040628276,
            233679843592838171
        );
        setEthPerShare(
            30760764109311844204706504954759457409868061391948563936927790118012690823836
        );
        setPrice(4);
        setEthPerShare(0);
        openCdp(4828486340510796, 2);
        closeCdp(1345287747116898108965462631934150381390299335717054913487485891514232193537);
        closeCdp(26877208931871548936656503713107409645415224744284780026010032151217117725615);
        setEthPerShare(60);
        liquidate(4);
        // TODO: ID
        _before(bytes32(0));
        redeemCollateral(
            2494964906324939450636487309639740620040425748472758226468879113711198275036,
            43,
            704006032010148001431895171996,
            1
        );
        _after(bytes32(0));
        // uint256 valueBeforeLiq = _getValue();

        assertTrue(invariant_CDPM_04(vars), "Cdp-04");
    }

    /**
        TODO: ECHIDNA
        setEthPerShare(1000) Time delay: 127761 seconds Block delay: 9880
    openCdp(4524377229654262,1)
    setEthPerShare(590)
    setPrice(62585740236349503659258829433448686991336332142246890573120200334913125020112) Time delay: 444463 seconds Block delay: 30040
    openCdp(2657952782541674,1)
    openCdp(172506625533584,9)
    openCdp(70904944448444413766718256551751006946686858338215426210784442951345040628276,233679843592838171)
    setEthPerShare(30760764109311844204706504954759457409868061391948563936927790118012690823836) Time delay: 504709 seconds Block delay: 43002
    setPrice(4)
    setEthPerShare(0)
    openCdp(4828486340510796,2)
    closeCdp(1345287747116898108965462631934150381390299335717054913487485891514232193537)
    closeCdp(26877208931871548936656503713107409645415224744284780026010032151217117725615)
    setEthPerShare(60)
    liquidate(4) Time delay: 19105 seconds Block delay: 183
    redeemCollateral(2494964906324939450636487309639740620040425748472758226468879113711198275036,43,704006032010148001431895171996,22212171859233866095593919364911988290126468271901060749390510031300370298087) Time delay: 119384 seconds Block delay: 23684

     */

    /**
     * 1) EchidnaTester.openCdp(61352334913724331844673735825348778692790231616991642409891756431271008690910, 3) (block=58171, time=241669, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000030000)
     *     2) EchidnaTester.setPrice(53242692202139136259844779411728414198979339870792811349285416325947018641415) (block=94549, time=628711, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000030000)
     *     3) EchidnaTester.setEthPerShare(19) (block=133367, time=1152871, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000020000)
     *     4) EchidnaTester.setEthPerShare(1) (block=175121, time=1582898, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000010000)
     *     5) EchidnaTester.setEthPerShare(3) (block=194749, time=1969716, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000010000)
     *     6) EchidnaTester.openCdp(63481775631040330868488838440380883887548553786606511443800351945466791372972, 12) (block=206558, time=2073883, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000030000)
     *     7) EchidnaTester.openCdp(115275689634636763471407553554696230511651534645337120528720836289775559173670, 3400000000000000000) (block=224043, time=2279568, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000030000)
     *     8) EchidnaTester.setPrice(49955707469362902507454157297736832118868343942642399513960811609542965143241) (block=224080, time=2279608, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000020000)
     *     9) EchidnaTester.setPrice(300) (block=245965, time=2827818, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000020000)
     *     10) EchidnaTester.setPrice(115792089237316195423570985008687907853269984665640564039455484007913129639937) (block=245965, time=2827818, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000020000)
     *     11) EchidnaTester.openCdp(115221720474780537866491969647886078644641607235938297017113192275671201037351, 13) (block=246061, time=3119917, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000010000)
     *     12) EchidnaTester.setEthPerShare(10) (block=279881, time=3480526, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000030000)
     *     13) EchidnaTester.liquidateCdps(81474231948216353665336502151292255308693665505215124358133307261506484044001) (block=318699, time=3552356, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000030000)
     * 14) EchidnaTester.redeemCollateral(100000000000000000000, 44528197469369619828452631535878582533537470583240950950026051403192050331017, 102238259035789227257399501220130095402144821045197998782718521293354458806802, 109921003103601632895059323246440408018934276513278813998597458827588043910345
     */
    function testCdpm04NewBroken() public {
        bytes32 firstCdp = openCdp(
            61352334913724331844673735825348778692790231616991642409891756431271008690910,
            3
        );
        setPrice(53242692202139136259844779411728414198979339870792811349285416325947018641415);
        setEthPerShare(19);
        setEthPerShare(1);
        setEthPerShare(3);
        openCdp(63481775631040330868488838440380883887548553786606511443800351945466791372972, 12);
        openCdp(
            115275689634636763471407553554696230511651534645337120528720836289775559173670,
            3400000000000000000
        );
        setPrice(49955707469362902507454157297736832118868343942642399513960811609542965143241);
        setPrice(300);
        setPrice(115792089237316195423570985008687907853269984665640564039455484007913129639937);
        openCdp(115221720474780537866491969647886078644641607235938297017113192275671201037351, 13);
        setEthPerShare(10);
        vm.warp(block.timestamp + cdpManager.recoveryModeGracePeriodDuration() + 1);
        liquidateCdps(81474231948216353665336502151292255308693665505215124358133307261506484044001);
        vm.warp(block.timestamp + cdpManager.recoveryModeGracePeriodDuration() + 1);
        uint256 valueBeforeRedeem = _getValue();
        _before(firstCdp);
        redeemCollateral(
            100000000000000000000,
            44528197469369619828452631535878582533537470583240950950026051403192050331017,
            102238259035789227257399501220130095402144821045197998782718521293354458806802,
            109921003103601632895059323246440408018934276513278813998597458827588043910345
        );
        _after(firstCdp);
        uint256 endValue = _getValue();

        // Log values
        console2.log("valueBeforeRedeem", valueBeforeRedeem);
        console2.log("endValue", endValue);

        assertGe(endValue, valueBeforeRedeem, "Value");
        assertTrue(invariant_CDPM_04(vars), "Cdp-04");
    }

    // https://fuzzy-fyi-output.s3.us-east-1.amazonaws.com/job/5414c08a-742e-49c1-8ca4-40e53b0a339c/logs.txt?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Content-Sha256=UNSIGNED-PAYLOAD&X-Amz-Credential=AKIA46FZI5L426LZ5IFS%2F20230922%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=20230922T151344Z&X-Amz-Expires=3600&X-Amz-Signature=ec081f6d369188a914e2fad9bf9d5c505b7a7596b16fe18690fe711bed9da22d&X-Amz-SignedHeaders=host&x-id=GetObject
    function testCdpAgain() public {
        setEthPerShare(1000);
        openCdp(4524377229654262, 1);
        setEthPerShare(590);
        setPrice(62585740236349503659258829433448686991336332142246890573120200334913125020112);
        openCdp(2657952782541674, 1);
        openCdp(172506625533584, 9);
        openCdp(
            70904944448444413766718256551751006946686858338215426210784442951345040628276,
            233679843592838171
        );
        setEthPerShare(
            30760764109311844204706504954759457409868061391948563936927790118012690823836
        );
        setPrice(4);
        setEthPerShare(0);
        openCdp(4828486340510796, 2);
        closeCdp(1345287747116898108965462631934150381390299335717054913487485891514232193537);
        closeCdp(26877208931871548936656503713107409645415224744284780026010032151217117725615);
        setEthPerShare(60);
        liquidate(4);
        _before(_getRandomCdp(4));
        uint256 startValue = _getValue();
        redeemCollateral(
            2494964906324939450636487309639740620040425748472758226468879113711198275036,
            43,
            704006032010148001431895171996,
            22212171859233866095593919364911988290126468271901060749390510031300370298087
        );
        uint256 endValue = _getValue();
        _after(_getRandomCdp(4));

        console2.log("");
        console2.log("");
        console2.log("");
        console2.log("startValue", startValue);
        console2.log("endValue", endValue);
        assertTrue(invariant_CDPM_04(vars), "Cdp-04");
    }

    // https://app.fuzzy.fyi/dashboard/jobs/0d22a32b-5612-4b73-bad2-824dffb6549d
    function testCdpM04ThirdTimesTheCharm() public {
        openCdp(0, 1);
        setPrice(167381130243608416929425501779011646220066545286939311441885146324);
        openCdp(
            4980718136141618313160385753170286089323593151999767814947781318659447486,
            234907954466222134
        );
        setEthPerShare(0);
        openCdp(
            1473100926471622789265820750888494507940889343982425262601996032509121429131,
            25122460264649447
        );
        _before(_getRandomCdp(4));
        uint256 startValue = _getValue();
        redeemCollateral(
            2836130018220487240424649660515350581035271781043904753321251,
            1303662118734886403439420394944695180633540216476340,
            718387314243405812531259987954424393104777196278117421089,
            1
        );
        uint256 endValue = _getValue();
        _after(_getRandomCdp(4));

        console2.log("");
        console2.log("");
        console2.log("");
        console2.log("startValue", startValue);
        console2.log("endValue", endValue);
        assertTrue(invariant_CDPM_04(vars), "Cdp-04");
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

    function testCdpm05() public {
        // Solved
        /**
         * 1) EchidnaTester.setPrice(34051283353441948537783721195918380744632616820013704574804095343781505350319) (block=3085, time=3584, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000030000)
         *     2) EchidnaTester.setPrice(34051283353441948537783721195918380744632616820013704574804095343781505350319) (block=6169, time=7167, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000030000)
         *     3) EchidnaTester.openCdp(35249873508603838970923917239059411282999141349869438512391489011181002963691, 131092) (block=33052, time=174742, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000020000)
         *     4) EchidnaTester.openCdp(35249873508603838970923917239059411282999141349869438512391489011181002963691, 131092) (block=59935, time=342317, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000020000)
         *     5) EchidnaTester.openCdp(59995130856179578012753964916304385582098201770011658156865798823036230046284, 1030000000000000000) (block=71744, time=934712, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000010000)
         *     6) EchidnaTester.openCdp(59995130856179578012753964916304385582098201770011658156865798823036230046284, 1030000000000000000) (block=83553, time=1527107, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000010000)
         *     7) EchidnaTester.setEthPerShare(102306107605456699406774569057307260912721427228498938043330144895537147074023) (block=138760, time=1887730, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000020000)
         *     8) EchidnaTester.setEthPerShare(102306107605456699406774569057307260912721427228498938043330144895537147074023) (block=193967, time=2248353, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000020000)
         *     9) EchidnaTester.setEthPerShare(12) (block=195307, time=2410416, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000020000)
         *     10) EchidnaTester.setEthPerShare(12) (block=196647, time=2572479, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000020000)
         *     11) EchidnaTester.liquidate(115792089237316195423570985008687907853269984665640564039457334248473421194186) (block=253087, time=2862985, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000010000)
         *     12) EchidnaTester.setEthPerShare(114585921641094151721242120581514075479798422325373474830713234174497367872855) (block=254911, time=3182269, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000030000)
         *     13) EchidnaTester.setEthPerShare(115792089237316195423570985008687907853269984665640564039457584007913129639917) (block=285219, time=3710528, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000010000)
         *     14) EchidnaTester.redeemCollateral(115792089237316195423570985008687907853269984665640564039457584007913129639804, 0, 80249580005923426999017426291550598604072605825515246012521238124436083823501, 3257859594493584007631716565564259005791797157466827520714009080874875672245)
         */

        // CDPM-05:
        setPrice(34051283353441948537783721195918380744632616820013704574804095343781505350319);
        setPrice(34051283353441948537783721195918380744632616820013704574804095343781505350319);
        openCdp(
            35249873508603838970923917239059411282999141349869438512391489011181002963691,
            131092
        );
        openCdp(
            35249873508603838970923917239059411282999141349869438512391489011181002963691,
            131092
        );
        openCdp(
            59995130856179578012753964916304385582098201770011658156865798823036230046284,
            1030000000000000000
        );
        bytes32 lastCdp = openCdp(
            59995130856179578012753964916304385582098201770011658156865798823036230046284,
            1030000000000000000
        );
        setEthPerShare(
            102306107605456699406774569057307260912721427228498938043330144895537147074023
        );
        setEthPerShare(
            102306107605456699406774569057307260912721427228498938043330144895537147074023
        );
        setEthPerShare(12);
        setEthPerShare(12);
        liquidate(115792089237316195423570985008687907853269984665640564039457334248473421194186);
        setEthPerShare(
            114585921641094151721242120581514075479798422325373474830713234174497367872855
        );
        setEthPerShare(
            115792089237316195423570985008687907853269984665640564039457584007913129639917
        );
        _before(lastCdp);
        redeemCollateral(
            115792089237316195423570985008687907853269984665640564039457584007913129639804,
            0,
            80249580005923426999017426291550598604072605825515246012521238124436083823501,
            3257859594493584007631716565564259005791797157466827520714009080874875672245
        );
        _after(lastCdp);

        // Global debt is fixed
        assertGe(vars.activePoolDebtBefore, vars.activePoolDebtAfter, "CDPM_05_GLOBAL");
    }

    function testGeneral14() public {
        setEthPerShare(12);
        openCdp(
            115792089237316195423570985008687907853269984665640564039457584007913129639935,
            6383
        );

        assertTrue(invariant_GENERAL_14(crLens, cdpManager, sortedCdps), "G-14");
    }

    /// @dev Debunk false positives for L-15
    ///     These will happen because of the desynch if nobody calls, it is what it is
    // function testL15Debunk() public {
    //     openCdp(67534042799335353648407647554112468697195277953615236438520200454730440793371, 8);
    //     openCdp(
    //         115792089237316195423570985008687907853269984665640564039457584007913129639931,
    //         1000000000000000900
    //     );
    //     setPrice(1324275793822189518402623021008446576244702559577);
    //     setEthPerShare(
    //         48542174391735010270995007834653745032392815149632706327135797120960854131722
    //     );
    //     setEthPerShare(40);
    //     partialLiquidate(
    //         48286268184227095156290128211489441036242155783962558196294945633758974303757,
    //         115792089237316195423570985008687907853269984665640564039457574007913129639736
    //     );
    //     _before(bytes32(0));
    //     setPrice(115792089237316195423570985007766067547234912789326764283000208828074618977599);
    //     _after(bytes32(0));
    //     _before(bytes32(0));
    //     redeemCollateral(
    //         999999999999999999,
    //         55466683072102056944478843133004903753885086444364839670214645639376128222361,
    //         68,
    //         26404592988528753382516565589028978384076848812021257892050088220355054183615
    //     );
    //     _after(bytes32(0));

    //     if (!vars.isRecoveryModeBefore && vars.isRecoveryModeAfter) {
    //         t(
    //             !vars.lastGracePeriodStartTimestampIsSetBefore &&
    //                 vars.lastGracePeriodStartTimestampIsSetAfter,
    //             L_15
    //         );
    //     }
    // }

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

    function testCDPM04Again() public {
        skip(255508);
        openCdp(0, 1);
        skip(448552);
        setPrice(167381130243608416929425501779011646220066545286939311441885146324);
        openCdp(
            4980718136141618313160385753170286089323593151999767814947781318659447486,
            234907954466222134
        );
        setEthPerShare(0);
        skip(315973);
        openCdp(
            1473100926471622789265820750888494507940889343982425262601996032509121429131,
            25122460264649447
        );
        setEthPerShare(0);
        skip(195123);
        bytes32 _cdpId = _getFirstCdpWithIcrGteMcr();
        _before(_cdpId);
        uint256 valueBeforeLiq = _getValue();
        redeemCollateral(
            2836130018220487240424649660515350581035271781043904753321251,
            1303662118734886403439420394944695180633540216476340,
            718387314243405812531259987954424393104777196278117421089,
            1
        );
        uint256 valueAfterLiq = _getValue();
        _after(_cdpId);
        uint256 beforeValue = ((vars.activePoolCollBefore +
            // vars.liquidatorRewardSharesBefore +
            vars.collSurplusPoolBefore +
            vars.feeRecipientTotalCollBefore) * vars.priceBefore) /
            1e18 -
            vars.activePoolDebtBefore;

        uint256 afterValue = ((vars.activePoolCollAfter +
            // vars.liquidatorRewardSharesAfter +
            vars.collSurplusPoolAfter +
            vars.feeRecipientTotalCollAfter) * vars.priceAfter) /
            1e18 -
            vars.activePoolDebtAfter;
        console2.log(_diff());
        console2.log(beforeValue, afterValue);
        console2.log("valueBeforeLiq", valueBeforeLiq);
        console2.log("valueAfterLiq", valueAfterLiq);
        assertGt(valueAfterLiq, valueBeforeLiq, "Value rises");
        assertTrue(invariant_CDPM_04(vars), CDPM_04);
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

    function testPropertyCSP01() public {
        openCdp(4875031885513970860143576544506802817390763544834983767953988765, 2);
        setEthPerShare(165751067651587426758928329439401399262641793);
        openCdp(0, 1);
        repayDebt(365894549068404535662610420582951074074566619457568347292095201808, 22293884342);
        _before(bytes32(0));
        console2.log(
            "CSP",
            collateral.sharesOf(address(collSurplusPool)),
            collSurplusPool.getTotalSurplusCollShares()
        );
        redeemCollateral(
            457124696465624691469821009088209599710133263214077681392799765737718,
            109056029728595120081267952673704432671053472351341847857754147758,
            40494814561017944903952057713046004326662485653288253330497571770,
            0
        );
        console2.log(
            "CSP",
            collateral.sharesOf(address(collSurplusPool)),
            collSurplusPool.getTotalSurplusCollShares()
        );
        _after(bytes32(0));
        console2.log(_diff());
        assertTrue(invariant_CSP_01(collateral, collSurplusPool), CSP_01);
    }

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
