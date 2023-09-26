// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";
import {Properties} from "../contracts/TestContracts/invariants/Properties.sol";
import {IERC20} from "../contracts/Dependencies/IERC20.sol";
import {IERC3156FlashBorrower} from "../contracts/Interfaces/IERC3156FlashBorrower.sol";

/*
 * Test suite that converts from echidna "fuzz tests" to foundry "unit tests"
 * The objective is to go from random values to hardcoded values that can be analyzed more easily
 */
contract EToFoundry is eBTCBaseFixture, Properties, IERC3156FlashBorrower {
    address user;
    uint256 internal constant INITIAL_COLL_BALANCE = 1e21;
    uint256 private constant MAX_FLASHLOAN_ACTIONS = 4;

    function setUp() public override {
        eBTCBaseFixture.setUp();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();
        user = address(this);
        vm.startPrank(address(this));
        vm.deal(user, INITIAL_COLL_BALANCE);
        collateral.deposit{value: INITIAL_COLL_BALANCE}();

        IERC20(collateral).approve(address(activePool), type(uint256).max);
        IERC20(eBTCToken).approve(address(borrowerOperations), type(uint256).max);
    }

    /// @dev Example of test for invariant
    function testBO05() public {
        openCdp(0, 1);
        setEthPerShare(0);
        addColl(89746347972992101541, 29594050145240);
        openCdp(0, 1);
        uint256 balanceBefore = collateral.balanceOf(address(this));
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(this), 0);
        uint256 cdpCollBefore = cdpManager.getCdpCollShares(_cdpId);
        uint256 liquidatorRewardSharesBefore = cdpManager.getCdpLiquidatorRewardShares(_cdpId);
        console2.log("before %s", balanceBefore);
        closeCdp(0);
        uint256 balanceAfter = collateral.balanceOf(address(this));
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
        vm.warp(block.timestamp + cdpManager.BOOTSTRAP_PERIOD());
        setEthPerShare(645326474426547203313410069153905908525362434357);
        vm.warp(block.timestamp + cdpManager.recoveryModeGracePeriod() + 1);
        setPrice(200);
        vm.warp(block.timestamp + cdpManager.recoveryModeGracePeriod() + 1);
        bytes32 randomCdp = openCdp(
            15271506168544636618683946165347184908672584999956201311530805028234774281247,
            525600000
        );
        vm.warp(block.timestamp + cdpManager.recoveryModeGracePeriod() + 1);
        setEthPerShare(
            34490286643335581993866445125615501807464041659106654042251963443032165120461
        );
        vm.warp(block.timestamp + cdpManager.recoveryModeGracePeriod() + 1);
        setPrice(72100039377333553285200231852034304471788766724978643708968246258805481443120);
        vm.warp(block.timestamp + cdpManager.recoveryModeGracePeriod() + 1);
        openCdp(2, 999999999999999999);
        vm.warp(block.timestamp + cdpManager.recoveryModeGracePeriod() + 1);
        setPrice(53613208255846312190970113690532613198662175001504036140235273976036627984403);
        vm.warp(block.timestamp + cdpManager.recoveryModeGracePeriod() + 1);
        setEthPerShare(
            53885036727293763953039497818137962919540408473654007727202467955943039934842
        );
        vm.warp(block.timestamp + cdpManager.recoveryModeGracePeriod() + 1);
        withdrawColl(
            64613413140793438003392705322981884782961011222878036826703269533463170986176,
            9999999999744
        );
        vm.warp(block.timestamp + cdpManager.recoveryModeGracePeriod() + 1);
        setEthPerShare(
            38654105012746982034204530442925091332196750429568734891400199507115192250853
        );
        vm.warp(block.timestamp + cdpManager.recoveryModeGracePeriod() + 1);
        partialLiquidate(
            51745835282927565687010251523416875790034155913406312339604760725754223914917,
            19
        );
        vm.warp(block.timestamp + cdpManager.recoveryModeGracePeriod() + 1);
        setEthPerShare(
            79832022615203712424393490440177025697015516400034287083326403000335384151815
        );
        vm.warp(block.timestamp + cdpManager.recoveryModeGracePeriod() + 1);
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
        vm.warp(block.timestamp + cdpManager.BOOTSTRAP_PERIOD());
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

    function testEchidnaCdpm04() public {
        setEthPerShare(1000);
        vm.warp(block.timestamp + cdpManager.BOOTSTRAP_PERIOD());
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
        vm.warp(block.timestamp + cdpManager.BOOTSTRAP_PERIOD());

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
        vm.warp(block.timestamp + cdpManager.recoveryModeGracePeriod() + 1);
        liquidateCdps(81474231948216353665336502151292255308693665505215124358133307261506484044001);
        vm.warp(block.timestamp + cdpManager.recoveryModeGracePeriod() + 1);
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
        vm.warp(block.timestamp + cdpManager.BOOTSTRAP_PERIOD());
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
        vm.warp(block.timestamp + cdpManager.BOOTSTRAP_PERIOD());
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
        vm.warp(block.timestamp + cdpManager.BOOTSTRAP_PERIOD());
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
        vm.warp(block.timestamp + cdpManager.recoveryModeGracePeriod() + 1);
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
        for (uint256 i; i < sortedCdps.cdpCountOf(address(user)); i++) {
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
        if (
            vars.newIcrBefore >= cdpManager.LICR() // 103% else liquidating locks in bad debt | // This fixes the check
        ) {
            assertGe(vars.newTcrAfter, vars.newTcrBefore, "l_12_expected"); // This invariant should break (because it's underwater)
        }
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
        // vm.warp(block.timestamp + cdpManager.recoveryModeGracePeriod() + 1);
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
        // vm.warp(block.timestamp + cdpManager.recoveryModeGracePeriod() + 1);
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
        vm.warp(block.timestamp + cdpManager.BOOTSTRAP_PERIOD());

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

    function testGeneral09() public {
        /**
         * 1) EchidnaTester.setEthPerShare(102306107605456699406774569057307260912721427228498938043330144895537147074023) (block=55208, time=360624, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000020000)
         *     2) EchidnaTester.setEthPerShare(102306107605456699406774569057307260912721427228498938043330144895537147074023) (block=110415, time=721247, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000020000)
         *     3) EchidnaTester.setEthPerShare(12) (block=111755, time=883310, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000020000)
         *     4) EchidnaTester.setEthPerShare(12) (block=113095, time=1045373, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000020000)
         *     5) EchidnaTester.openCdp(35249873508603838970923917239059411282999141349869438512391489011181002963691, 131092) (block=139978, time=1212948, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000020000)
         *     6) EchidnaTester.openCdp(59995130856179578012753964916304385582098201770011658156865798823036230046284, 1030000000000000000) (block=151787, time=1805343, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000010000)
         *     7) EchidnaTester.openCdp(59995130856179578012753964916304385582098201770011658156865798823036230046284, 1030000000000000000) (block=163596, time=2397738, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000010000)
         *     8) EchidnaTester.setEthPerShare(102306107605456699406774569057307260912721427228498938043330144895537147074023) (block=218803, time=2758361, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000020000)
         *     9) EchidnaTester.setEthPerShare(12) (block=220143, time=2920424, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000020000)
         *     10) EchidnaTester.setEthPerShare(12) (block=221483, time=3082487, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000020000)
         *     11) EchidnaTester.liquidate(115792089237316195423570985008687907853269984665640564039457334248473421194186) (block=277923, time=3372993, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000010000)
         *     12) EchidnaTester.repayEBTC(9999999999993599, 48)
         */

        // GENERAL-09:
        setEthPerShare(
            102306107605456699406774569057307260912721427228498938043330144895537147074023
        );
        setEthPerShare(
            102306107605456699406774569057307260912721427228498938043330144895537147074023
        );
        setEthPerShare(12);
        setEthPerShare(12);
        openCdp(
            35249873508603838970923917239059411282999141349869438512391489011181002963691,
            131092
        );
        openCdp(
            59995130856179578012753964916304385582098201770011658156865798823036230046284,
            1030000000000000000
        );
        openCdp(
            59995130856179578012753964916304385582098201770011658156865798823036230046284,
            1030000000000000000
        );
        setEthPerShare(
            102306107605456699406774569057307260912721427228498938043330144895537147074023
        );
        setEthPerShare(12);
        setEthPerShare(12);
        liquidate(115792089237316195423570985008687907853269984665640564039457334248473421194186);
        bytes32 cdpId = get_cdp(48);
        _before(cdpId);
        repayEBTC(9999999999993599, 48);
        _after(cdpId);

        console2.log("vars.isRecoveryModeBefore", vars.isRecoveryModeBefore);
        console2.log("vars.cdpDebtBefore", vars.cdpDebtBefore);
        console2.log("vars.cdpDebtAfter", vars.cdpDebtAfter);
        console2.log("vars.icrAfter", vars.icrAfter); // 0.88

        assertTrue(invariant_GENERAL_09(cdpManager, vars), "G-09");
    }

    function testGeneral09AnotherEchidna() public {
        vm.warp(block.timestamp + cdpManager.BOOTSTRAP_PERIOD());
        setEthPerShare(422969885005186853460329118216965939317476978914332751313210691257388459660);
        setPrice(32722689803297159564660);
        setEthPerShare(2295800715889050428049394301540389611305203770840759558107023063707478756137);
        setEthPerShare(9430658084342478621110343879440481693664256397237066590580775256327894933237);
        openCdp(0, 56974);
        setEthPerShare(3658003803251865466884416677564469755415415764957710330089017560191195285885);
        openCdp(
            47178713746231187329670492904587548046295133576157509226996599744760046768080,
            1025940393747833117
        );
        setEthPerShare(1826419048);
        setEthPerShare(463853255);
        setEthPerShare(61234613524967728149213013066788335278812480284234739607096758628686182151);
        setEthPerShare(7954433823584281635390873055824344390954190101728441881267963183032688165561);
        openCdp(0, 65411);
        redeemCollateral(
            1411218970824529683653579944659199592374110441414703777589990697024796931545,
            28682412223937313107683354748345742208210734296344230354578406624067099566210,
            8026017604617149994705335113890034223124268667295240133106044134145840327608,
            24510602
        );
        openCdp(
            421639041749029036961420610791321146216723974031398276432264313125580738407,
            1398999
        );
        liquidateCdps(10337462962424082567470147037678370917064894195736595735492531568803797071);

        bytes32 cdpId = get_cdp(1);

        _before(cdpId);
        repayEBTC(1, 3664654876686139248533669277245093923727466555308247984199766471982047307);
        _after(cdpId);

        console2.log("vars.isRecoveryModeBefore", vars.isRecoveryModeBefore);
        console2.log("vars.cdpDebtBefore", vars.cdpDebtBefore);
        console2.log("vars.cdpDebtAfter", vars.cdpDebtAfter);
        console2.log("vars.icrAfter", vars.icrAfter); // 0.88

        assertTrue(invariant_GENERAL_09(cdpManager, vars), "G-09");
    }

    function testNewTcr() public {
        bytes32 cdp = openCdp(
            57171402311851979203771794298570627232849516536367359032302056791630,
            22
        );
        setPrice(969908437377713906993269161715201666459885343214304447044925418238284);
        uint256 currentPrice = priceFeedMock.getPrice();

        console2.log("tcr before sync", cdpManager.getTCR(currentPrice));

        cdpManager.syncGlobalAccountingAndGracePeriod();
        uint256 prevTCR = cdpManager.getTCR(currentPrice);

        console2.log("tcr after sync", cdpManager.getTCR(currentPrice));

        repayEBTC(
            65721117470445406076343058077880221223501416620988368611416146266508,
            158540941122585656115423420542823120113261891967556325033385077539052280
        );
        uint256 tcrAfter = cdpManager.getTCR(currentPrice);

        console2.log("tcr after repay", cdpManager.getTCR(currentPrice));
        console2.log("tcr after simulated sync", _getTcrAfterSimulatedSync());

        cdpManager.syncGlobalAccountingAndGracePeriod();

        console2.log("tcr after sync", cdpManager.getTCR(currentPrice));

        // assertGt(_getICR(cdp), cdpManager.MCR(), "ICR, MCR"); // basic

        // Logs:
        //   openCdp 2200000000000000370 22
        //   setPrice 71041372806687933
        //   tcr before sync 6458306618789813285695815385206145
        //   tcr after sync 6458306618789813285695815385206145
        //   repayEBTC 1 0
        //   tcr after repay 6765845029208375823109901832120724
        //   tcr after sync 6765845029208375823109901832120724

        assertGt(tcrAfter, prevTCR, "TCR Improved");
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
            cdpManager.getTCR(_price),
            cdpManager.getICR(_cdpId1, _price),
            cdpManager.getICR(_cdpId2, _price)
        );
        console2.log(
            "CDP1",
            uint256(sortedCdps.getFirst()),
            cdpManager.getICR(sortedCdps.getFirst(), _price)
        );
        liquidateCdps(18144554526834239235);
        console2.log(
            "CDP1",
            uint256(sortedCdps.getFirst()),
            cdpManager.getICR(sortedCdps.getFirst(), _price)
        );
    }

    function testTcrMustIncreaseAfterRepayment() public {
        openCdp(13981380896748761892053706028661380888937876551972584966356379645, 23);
        setEthPerShare(55516200804822679866310029419499170992281118179349982013988952907);
        repayEBTC(1, 509846657665200610349434642309205663062);
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
    //     vm.warp(block.timestamp + cdpManager.recoveryModeGracePeriod() + 1);
    //     bytes32 currentCdp = sortedCdps.getFirst();
    //     uint256 i = 0;
    //     uint256 _price = priceFeedMock.getPrice();
    //     console2.log("\tbefore");

    //     uint256 newIcr;

    //     while (currentCdp != bytes32(0)) {
    //         newIcr = crLens.quoteRealICR(currentCdp);

    //         console2.log("\t", i++, cdpManager.getICR(currentCdp, _price), newIcr);
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

    //         console2.log("\t", i++, cdpManager.getICR(currentCdp, _price), newIcr);
    //         currentCdp = sortedCdps.getNext(currentCdp);
    //     }
    //     assertTrue(invariant_SL_05(crLens, cdpManager, priceFeedMock, sortedCdps), SL_05);
    // }

    function testPropertyCSP01() public {
        vm.warp(block.timestamp + cdpManager.BOOTSTRAP_PERIOD());
        openCdp(4875031885513970860143576544506802817390763544834983767953988765, 2);
        setEthPerShare(165751067651587426758928329439401399262641793);
        openCdp(0, 1);
        repayEBTC(365894549068404535662610420582951074074566619457568347292095201808, 22293884342);
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

    function clampBetween(uint256 value, uint256 low, uint256 high) internal returns (uint256) {
        if (value < low || value > high) {
            uint256 ans = low + (value % (high - low + 1));
            return ans;
        }
        return value;
    }

    function setEthPerShare(uint256 _newEthPerShare) internal {
        uint256 currentEthPerShare = collateral.getEthPerShare();
        _newEthPerShare = clampBetween(
            _newEthPerShare,
            (currentEthPerShare * 1e18) / 1.1e18,
            (currentEthPerShare * 1.1e18) / 1e18
        );

        console2.log("setEthPerShare", _newEthPerShare);
        collateral.setEthPerShare(_newEthPerShare);
    }

    function setPrice(uint256 _newPrice) internal {
        uint256 currentPrice = priceFeedMock.getPrice();
        _newPrice = clampBetween(
            _newPrice,
            (currentPrice * 1e18) / 1.05e18,
            (currentPrice * 1.05e18) / 1e18
        );

        console2.log("setPrice", _newPrice);
        priceFeedMock.setPrice(_newPrice);
    }

    function openCdp(uint256 _col, uint256 _EBTCAmount) internal returns (bytes32) {
        uint256 price = priceFeedMock.getPrice();

        uint256 requiredCollAmount = (_EBTCAmount * CCR) / (price);
        uint256 minCollAmount = max(
            borrowerOperations.MIN_NET_COLL() + borrowerOperations.LIQUIDATOR_REWARD(),
            requiredCollAmount
        );
        uint256 maxCollAmount = min(2 * minCollAmount, 1e20);
        _col = clampBetween(requiredCollAmount, minCollAmount, maxCollAmount);
        collateral.approve(address(borrowerOperations), _col);

        console2.log("openCdp", _col, _EBTCAmount);
        return borrowerOperations.openCdp(_EBTCAmount, bytes32(0), bytes32(0), _col);
    }

    function closeCdp(uint256 _i) internal {
        uint256 numberOfCdps = sortedCdps.cdpCountOf(address(user));
        require(numberOfCdps > 0, "Actor must have at least one CDP open");

        _i = clampBetween(_i, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(user), _i);

        console2.log("closeCdp", _i);
        borrowerOperations.closeCdp(_cdpId);
    }

    function addColl(uint256 _coll, uint256 _i) internal {
        uint256 numberOfCdps = sortedCdps.cdpCountOf(user);

        _i = clampBetween(_i, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(user, _i);

        _coll = clampBetween(_coll, 0, 1e20);
        collateral.approve(address(borrowerOperations), _coll);

        console2.log("addColl", _coll, _i);
        borrowerOperations.addColl(_cdpId, _cdpId, _cdpId, _coll);
    }

    function withdrawEBTC(uint256 _amount, uint256 _i) internal {
        uint256 numberOfCdps = sortedCdps.cdpCountOf(user);

        _i = clampBetween(_i, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(user, _i);

        _amount = clampBetween(_amount, 0, type(uint128).max);

        console2.log("withdrawEBTC", _amount, _i);
        borrowerOperations.withdrawEBTC(_cdpId, _amount, _cdpId, _cdpId);
    }

    function withdrawColl(uint256 _amount, uint256 _i) internal {
        uint256 numberOfCdps = sortedCdps.cdpCountOf(user);

        _i = clampBetween(_i, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(user, _i);

        _amount = clampBetween(
            _amount,
            0,
            collateral.getPooledEthByShares(cdpManager.getCdpCollShares(_cdpId))
        );

        console2.log("withdrawColl", _amount, _i);
        borrowerOperations.withdrawColl(_cdpId, _amount, _cdpId, _cdpId);
    }

    function get_cdp(uint256 _i) internal returns (bytes32) {
        uint256 numberOfCdps = sortedCdps.cdpCountOf(user);

        _i = clampBetween(_i, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(user, _i);

        return _cdpId;
    }

    function repayEBTC(uint256 _amount, uint256 _i) internal {
        uint256 numberOfCdps = sortedCdps.cdpCountOf(user);

        _i = clampBetween(_i, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(user, _i);

        (uint256 entireDebt, , ) = cdpManager.getDebtAndCollShares(_cdpId);
        _amount = clampBetween(_amount, 0, entireDebt);

        console2.log("repayEBTC", _amount, _i);
        borrowerOperations.repayEBTC(_cdpId, _amount, _cdpId, _cdpId);
    }

    function redeemCollateral(
        uint256 _EBTCAmount,
        uint256 _partialRedemptionHintNICR,
        uint256 _maxFeePercentage,
        uint256 _maxIterations
    ) internal {
        require(
            block.timestamp > cdpManager.getDeploymentStartTime() + cdpManager.BOOTSTRAP_PERIOD(),
            "CdpManager: Redemptions are not allowed during bootstrap phase"
        );

        _EBTCAmount = clampBetween(_EBTCAmount, 0, eBTCToken.balanceOf(address(user)));
        _maxIterations = clampBetween(_maxIterations, 0, 1);

        _maxFeePercentage = clampBetween(
            _maxFeePercentage,
            cdpManager.redemptionFeeFloor(),
            cdpManager.DECIMAL_PRECISION()
        );

        console2.log("redeemCollateral", _EBTCAmount, _partialRedemptionHintNICR, _maxFeePercentage);
        console2.log("\t\t\t", _maxIterations);
        cdpManager.redeemCollateral(
            _EBTCAmount,
            bytes32(0),
            bytes32(0),
            bytes32(0),
            _partialRedemptionHintNICR,
            _maxIterations,
            _maxFeePercentage
        );
    }

    function liquidateCdps(uint256 _n) internal {
        _n = clampBetween(_n, 1, cdpManager.getActiveCdpsCount());

        console2.log("liquidateCdps", _n);
        _liquidateCdps(_n);
    }

    function liquidate(uint256 _i) internal returns (bytes32 _cdpId) {
        require(cdpManager.getActiveCdpsCount() > 1, "Cannot liquidate last CDP");

        _cdpId = _getRandomCdp(_i);

        (uint256 entireDebt, , ) = cdpManager.getDebtAndCollShares(_cdpId);
        require(entireDebt > 0, "CDP must have debt");

        console2.log("liquidate", _i % cdpManager.getActiveCdpsCount());
        cdpManager.liquidate(_cdpId);
    }

    function partialLiquidate(uint256 _i, uint256 _partialAmount) internal returns (bytes32 _cdpId) {
        require(cdpManager.getActiveCdpsCount() > 1, "Cannot liquidate last CDP");

        _cdpId = _getRandomCdp(_i);

        (uint256 entireDebt, , ) = cdpManager.getDebtAndCollShares(_cdpId);
        require(entireDebt > 0, "CDP must have debt");

        _partialAmount = clampBetween(_partialAmount, 1, entireDebt - 1);

        console2.log("partiallyLiquidate", _i % cdpManager.getActiveCdpsCount(), _partialAmount);
        cdpManager.partiallyLiquidate(_cdpId, _partialAmount, _cdpId, _cdpId);
    }

    function flashLoanColl(uint256 _amount) internal {
        _amount = clampBetween(_amount, 0, activePool.maxFlashLoan(address(collateral)));

        console2.log("flashLoanColl", _amount);

        uint256 _balBefore = collateral.balanceOf(activePool.feeRecipientAddress());
        uint256 _fee = activePool.flashFee(address(collateral), _amount);
        activePool.flashLoan(
            IERC3156FlashBorrower(address(this)),
            address(collateral),
            _amount,
            _getFlashLoanActions(_amount)
        );
        uint256 _balAfter = collateral.balanceOf(activePool.feeRecipientAddress());
        console.log("\tbalances", _balBefore, _balAfter);
        console.log("\tfee", _fee);
    }

    function flashLoanEBTC(uint256 _amount) internal {
        _amount = clampBetween(_amount, 0, borrowerOperations.maxFlashLoan(address(eBTCToken)));

        console2.log("flashLoanEBTC", _amount);

        uint256 _balBefore = eBTCToken.balanceOf(borrowerOperations.feeRecipientAddress());
        uint256 _fee = borrowerOperations.flashFee(address(eBTCToken), _amount);
        borrowerOperations.flashLoan(
            IERC3156FlashBorrower(address(this)),
            address(eBTCToken),
            _amount,
            _getFlashLoanActions(_amount)
        );
        uint256 _balAfter = eBTCToken.balanceOf(borrowerOperations.feeRecipientAddress());
        console.log("\tbalances", _balBefore, _balAfter);
        console.log("\tfee", _fee);
    }

    function _getFlashLoanActions(uint256 value) internal returns (bytes memory) {
        uint256 _actions = clampBetween(value, 1, MAX_FLASHLOAN_ACTIONS);
        uint256 _EBTCAmount = clampBetween(value, 1, eBTCToken.totalSupply() / 2);
        uint256 _col = clampBetween(value, 1, cdpManager.getSystemCollShares() / 2);
        uint256 _n = clampBetween(value, 1, cdpManager.getActiveCdpsCount());

        uint256 numberOfCdps = sortedCdps.cdpCountOf(address(user));
        require(numberOfCdps > 0, "Actor must have at least one CDP open");
        uint256 _i = clampBetween(value, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(user), _i);
        assert(_cdpId != bytes32(0));

        address[] memory _targets = new address[](_actions);
        bytes[] memory _calldatas = new bytes[](_actions);

        address[] memory _allTargets = new address[](7);
        bytes[] memory _allCalldatas = new bytes[](7);

        _allTargets[0] = address(borrowerOperations);
        _allCalldatas[0] = abi.encodeWithSelector(
            borrowerOperations.openCdp.selector,
            _EBTCAmount,
            bytes32(0),
            bytes32(0),
            _col
        );

        _allTargets[1] = address(borrowerOperations);
        _allCalldatas[1] = abi.encodeWithSelector(borrowerOperations.closeCdp.selector, _cdpId);

        _allTargets[2] = address(borrowerOperations);
        _allCalldatas[2] = abi.encodeWithSelector(
            borrowerOperations.addColl.selector,
            _cdpId,
            _cdpId,
            _cdpId,
            _col
        );

        _allTargets[3] = address(borrowerOperations);
        _allCalldatas[3] = abi.encodeWithSelector(
            borrowerOperations.withdrawColl.selector,
            _cdpId,
            _col,
            _cdpId,
            _cdpId
        );

        _allTargets[4] = address(borrowerOperations);
        _allCalldatas[4] = abi.encodeWithSelector(
            borrowerOperations.withdrawEBTC.selector,
            _cdpId,
            _EBTCAmount,
            _cdpId,
            _cdpId
        );

        _allTargets[5] = address(borrowerOperations);
        _allCalldatas[5] = abi.encodeWithSelector(
            borrowerOperations.repayEBTC.selector,
            _cdpId,
            _EBTCAmount,
            _cdpId,
            _cdpId
        );

        _allTargets[6] = address(cdpManager);
        bytes32[] memory _batch = liquidationSequencer.sequenceLiqToBatchLiqWithPrice(
            _n,
            priceFeedMock.getPrice()
        );
        _allCalldatas[6] = abi.encodeWithSelector(cdpManager.batchLiquidateCdps.selector, _batch);

        for (uint256 _j = 0; _j < _actions; ++_j) {
            _i = uint256(keccak256(abi.encodePacked(value, _j, _i))) % _allTargets.length;
            console2.log("\taction", _i);

            _targets[_j] = _allTargets[_i];
            _calldatas[_j] = _allCalldatas[_i];
        }

        return abi.encode(_targets, _calldatas);
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

    function _getTcrAfterSimulatedSync() internal returns (uint256 newTcr) {
        address[] memory _targets = new address[](2);
        bytes[] memory _calldatas = new bytes[](2);

        _targets[0] = address(cdpManager);
        _calldatas[0] = abi.encodeWithSelector(
            cdpManager.syncGlobalAccountingAndGracePeriod.selector
        );

        _targets[1] = address(cdpManager);
        _calldatas[1] = abi.encodeWithSelector(cdpManager.getTCR.selector, priceFeedMock.getPrice());

        console2.log("simulate");

        // Compute new TCR after syncGlobalAccountingAndGracePeriod and revert to previous snapshot in oder to not affect the current state
        try this.simulate(_targets, _calldatas) {} catch (bytes memory reason) {
            console2.logBytes(reason);
            assembly {
                // Slice the sighash.
                reason := add(reason, 0x04)
            }
            bytes memory returnData = abi.decode(reason, (bytes));
            newTcr = abi.decode(returnData, (uint256));
            console2.log("newTcr", newTcr);
        }
    }

    function _getRandomCdp(uint256 _i) internal view returns (bytes32) {
        uint256 _cdpIdx = _i % cdpManager.getActiveCdpsCount();
        return cdpManager.CdpIds(_cdpIdx);
    }

    error Simulate(bytes);

    function simulate(address[] memory _targets, bytes[] memory _calldatas) public {
        uint256 length = _targets.length;

        bool success;
        bytes memory returnData;

        for (uint256 i = 0; i < length; i++) {
            (success, returnData) = address(_targets[i]).call(_calldatas[i]);
            require(success, _getRevertMsg(returnData));
        }

        revert Simulate(returnData);
    }

    function _getFirstCdpWithIcrGteMcr() internal returns (bytes32) {
        bytes32 _cId = sortedCdps.getLast();
        address currentBorrower = sortedCdps.getOwnerAddress(_cId);
        // Find the first cdp with ICR >= MCR
        while (
            currentBorrower != address(0) &&
            cdpManager.getICR(_cId, priceFeedMock.getPrice()) < cdpManager.MCR()
        ) {
            _cId = sortedCdps.getPrev(_cId);
            currentBorrower = sortedCdps.getOwnerAddress(_cId);
        }
        return _cId;
    }
}
