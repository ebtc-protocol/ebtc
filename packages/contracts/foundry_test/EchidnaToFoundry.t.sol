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
    uint internal constant INITIAL_COLL_BALANCE = 1e21;
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

    function testBrokenImprovementofNICR() public {
        setEthPerShare(112);
        bytes32 cdpId = openCdp(
            115792089237316195423570985008687907853269984665640564039456534007913129639919,
            6401
        );
        console2.log("Fee index", cdpManager.stEthFeePerUnitIndex(cdpId));
        uint256 startNICR = cdpManager.getNominalICR(cdpId);
        setEthPerShare(1000000000000000000);

        // B0-03 FIX
        // 1) Accrue global
        cdpManager.syncGlobalAccountingAndGracePeriod(); // This fixes it
        // 2) Read NICR with latest global stETH Index
        uint256 afterStETHPerSharesNICR = cdpManager.getNominalICR(cdpId);

        // In handler, solved by using crLens

        console2.log("Fee index", cdpManager.stEthFeePerUnitIndex(cdpId));
        addColl(20, 36);
        uint256 afterRepayNICR = cdpManager.getNominalICR(cdpId);
        console2.log("Fee index", cdpManager.stEthFeePerUnitIndex(cdpId));

        console2.log("startNICR", startNICR);
        console2.log("afterStETHPerSharesNICR", afterStETHPerSharesNICR);
        console2.log("afterRepayNICR", afterRepayNICR);
        assertGt(afterRepayNICR, afterStETHPerSharesNICR, "BO-03: Must increase NICR");
    }

    /**
        1) EchidnaTester.setEthPerShare(31656099540918703381915350012813182642308405422272958668865762453755205317560) (block=3966, time=264453, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000010000)
        2) EchidnaTester.openCdp(60831556551619617237480607135123444879160274018218144781759469227986909022036, 48) (block=8500, time=427094, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000030000)
        3) EchidnaTester.setEthPerShare(1000000000000000000) (block=28684, time=979712, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000010000)
        4) EchidnaTester.addColl(16, 115792089237316195423570985008687907853269984665640564039457584007913129508864) (block=54621, ti
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
        1) EchidnaTester.openCdp(5, 9) (block=21034, time=230044, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000030000)
        2) EchidnaTester.openCdp(84262773986715970128580444052678471626722414870282791794979066159115554213330, 1030000000000000000) (block=24528, time=400319, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000010000)
        3) EchidnaTester.setPrice(62851218183508081866601323998844678683340852927274212763025381189284030175116) (block=36605, time=452175, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000030000)
        4) EchidnaTester.setEthPerShare(106776231264650488527396238935264109957201160064867503889176542731952275025143) (block=36605, time=452175, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000030000)
        5) EchidnaTester.openCdp(76780224446527678697820911257670310585293087149232760248922738678857400527227, 7428) (block=50619, time=633086, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000020000)
        6) EchidnaTester.setEthPerShare(115792089237316195423570985008687907853269984665640564039457584007913129639917) (block=50619, time=633086, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000020000)
        7) EchidnaTester.liquidateCdps(2) (block=74280, time=1191523, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000010000)
        8) EchidnaTester.redeemCollateral(46569391515833093424627317458962525217707765577058029473090855375431272918988, 0, 14229479364104465894069837803513832929478804353344870192956752971009762732884, 84531756315918705342020165315694316831239657177696340854927806097286510294339) (block=130886, time=1730710, gas=12500000, gasprice=1, value=0, sender=0x0000000000000000000000000000000000010000)
    
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

    function testMinCdpSize() public {
        openCdp(0, 1);
        openCdp(
            72288567839925548448879814980609186672926104313635808777211548693631,
            132140405255026398
        );
        setEthPerShare(0);

        bytes32 _cdpId = _getRandomCdp(7);
        _before(_cdpId);
        partialLiquidate(7, 0);
        _after(_cdpId);
        console2.log(_diff());
    }

    function clampBetween(uint256 value, uint256 low, uint256 high) internal returns (uint256) {
        if (value < low || value > high) {
            uint ans = low + (value % (high - low + 1));
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
        uint price = priceFeedMock.getPrice();

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

    function closeCdp(uint _i) internal {
        uint256 numberOfCdps = sortedCdps.cdpCountOf(address(user));
        require(numberOfCdps > 0, "Actor must have at least one CDP open");

        _i = clampBetween(_i, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(user), _i);

        console2.log("closeCdp", _i);
        borrowerOperations.closeCdp(_cdpId);
    }

    function addColl(uint _coll, uint256 _i) internal {
        uint256 numberOfCdps = sortedCdps.cdpCountOf(user);

        _i = clampBetween(_i, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(user, _i);

        _coll = clampBetween(_coll, 0, 1e20);
        collateral.approve(address(borrowerOperations), _coll);

        console2.log("addColl", _coll, _i);
        borrowerOperations.addColl(_cdpId, _cdpId, _cdpId, _coll);
    }

    function withdrawEBTC(uint _amount, uint256 _i) internal {
        uint256 numberOfCdps = sortedCdps.cdpCountOf(user);

        _i = clampBetween(_i, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(user, _i);

        _amount = clampBetween(_amount, 0, type(uint128).max);

        console2.log("withdrawEBTC", _amount, _i);
        borrowerOperations.withdrawEBTC(_cdpId, _amount, _cdpId, _cdpId);
    }

    function withdrawColl(uint _amount, uint256 _i) internal {
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

    function repayEBTC(uint _amount, uint256 _i) internal {
        uint256 numberOfCdps = sortedCdps.cdpCountOf(user);

        _i = clampBetween(_i, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(user, _i);

        (uint256 entireDebt, , ) = cdpManager.getDebtAndCollShares(_cdpId);
        _amount = clampBetween(_amount, 0, entireDebt);

        console2.log("repayEBTC", _amount, _i);
        borrowerOperations.repayEBTC(_cdpId, _amount, _cdpId, _cdpId);
    }

    function redeemCollateral(
        uint _EBTCAmount,
        uint _partialRedemptionHintNICR,
        uint _maxFeePercentage,
        uint _maxIterations
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

    function liquidateCdps(uint _n) internal {
        _n = clampBetween(_n, 1, cdpManager.getActiveCdpsCount());

        console2.log("liquidateCdps", _n);
        _liquidateCdps(_n);
    }

    function partialLiquidate(uint _i, uint _partialAmount) internal returns (bytes32 _cdpId) {
        require(cdpManager.getActiveCdpsCount() > 1, "Cannot liquidate last CDP");

        _cdpId = _getRandomCdp(_i);

        (uint256 entireDebt, , ) = cdpManager.getDebtAndCollShares(_cdpId);
        require(entireDebt > 0, "CDP must have debt");

        _partialAmount = clampBetween(_partialAmount, 0, entireDebt - 1);

        console2.log("partiallyLiquidate", _i % cdpManager.getActiveCdpsCount(), _partialAmount);
        cdpManager.partiallyLiquidate(_cdpId, _partialAmount, _cdpId, _cdpId);
    }

    function flashLoanColl(uint _amount) internal {
        _amount = clampBetween(_amount, 0, activePool.maxFlashLoan(address(collateral)));

        console2.log("flashLoanColl", _amount);

        uint _balBefore = collateral.balanceOf(activePool.feeRecipientAddress());
        uint _fee = activePool.flashFee(address(collateral), _amount);
        activePool.flashLoan(
            IERC3156FlashBorrower(address(this)),
            address(collateral),
            _amount,
            _getFlashLoanActions(_amount)
        );
        uint _balAfter = collateral.balanceOf(activePool.feeRecipientAddress());
        console.log("\tbalances", _balBefore, _balAfter);
        console.log("\tfee", _fee);
    }

    function flashLoanEBTC(uint _amount) internal {
        _amount = clampBetween(_amount, 0, borrowerOperations.maxFlashLoan(address(eBTCToken)));

        console2.log("flashLoanEBTC", _amount);

        uint _balBefore = eBTCToken.balanceOf(borrowerOperations.feeRecipientAddress());
        uint _fee = borrowerOperations.flashFee(address(eBTCToken), _amount);
        borrowerOperations.flashLoan(
            IERC3156FlashBorrower(address(this)),
            address(eBTCToken),
            _amount,
            _getFlashLoanActions(_amount)
        );
        uint _balAfter = eBTCToken.balanceOf(borrowerOperations.feeRecipientAddress());
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

    function _getRandomCdp(uint _i) internal view returns (bytes32) {
        uint _cdpIdx = _i % cdpManager.getActiveCdpsCount();
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
}
