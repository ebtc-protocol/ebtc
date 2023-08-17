// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;
import "forge-std/Test.sol";
import "forge-std/console2.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";
import {Properties} from "../contracts/TestContracts/invariants/Properties.sol";

/*
 * Test suite that converts from echidna "fuzz tests" to foundry "unit tests"
 * The objective is to go from random values to hardcoded values that can be analyzed more easily
 */
contract EchidnaToFoundry is eBTCBaseFixture, Properties {
    address user;

    function setUp() public override {
        eBTCBaseFixture.setUp();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();
        user = _utils.getNextUserAddress();
        vm.startPrank(user);
        uint256 funds = type(uint96).max;
        vm.deal(user, funds);
        collateral.approve(address(borrowerOperations), funds);
        collateral.deposit{value: funds}();
    }

    function testGetValuesRedemptions() public {
        vm.warp(block.timestamp + 60 * 60 * 24 * 365); // Warp a year to go over min time
        openCdp(4975011538218946772755711718445854401649461238704126722046796672, 1);
        setEthPerShare(0);
        openCdp(3605950849545190917236707431640872421373248423478238946946259069, 2);
        redeemCollateral(
            547127325038,
            947890426751454568089952789385716404489268405604644114758048974194620,
            57939920126045711308615423797531076503306665406531885559654882737632016156
        );
        openCdp(4975011538218946772755711718445854401649461238704126722046796672, 1);
        setEthPerShare(0);
        openCdp(3605950849545190917236707431640872421373248423478238946946259069, 2);
        redeemCollateral(
            547127325038,
            947890426751454568089952789385716404489268405604644114758048974194620,
            57939920126045711308615423797531076503306665406531885559654882737632016156
        );

        console2.log(
            "collateral.sharesOf(address(collSurplusPool)",
            collateral.sharesOf(address(collSurplusPool))
        );
        console2.log("collSurplusPool.getStEthColl()", collSurplusPool.getStEthColl());
        // assertTrue(invariant_CSP_01(collateral, collSurplusPool), "CSP-01");
    }

    function testGetValues() public {
        openCdp(298, 1);
        addColl(
            1643239628397191314697579057448420627080273462830700079102449130509,
            365742980907456965584449763965903736633480494004802033305060593621986
        );
        withdrawEBTC(
            1184219647878146906,
            2441064729135930468687515109208933352881429821330765071021434864906412112313
        );
        setEthPerShare(534740885114938036571112017074595968544303330274215367894);
        setEthPerShare(0);
        openCdp(0, 1);
    }

    function testGetAllCdpsShouldMaintainAMinimumCollateralSize() public {
        setEthPerShare(0);
        openCdp(306448163413226964497420707241366511691019849585554, 1);
        withdrawColl(186970840931894992, 1379465742659455);
    }

    function testGetRedemptionMustSatisfyAccountingEquation() public {
        // TODO verify this shares/coll
        vm.warp(block.timestamp + cdpManager.BOOTSTRAP_PERIOD());
        openCdp(313025303777237127496675, 1);
        openCdp(
            3352225288317311202032007496640886572550824479399475529334293962347630660369,
            130881814726979393
        );
        setEthPerShare(0);

        uint256 activePoolCollBefore = activePool.getStEthColl();
        uint256 collSurplusPoolBefore = collSurplusPool.getStEthColl();
        uint256 debtBefore = activePool.getEBTCDebt();
        uint256 priceBefore = priceFeedMock.getPrice();

        redeemCollateral(1, 0, 0);

        uint256 activePoolCollAfter = activePool.getStEthColl();
        uint256 collSurplusPoolAfter = collSurplusPool.getStEthColl();
        uint256 debtAfter = activePool.getEBTCDebt();
        uint256 priceAfter = priceFeedMock.getPrice();

        uint256 beforeEquity = (activePoolCollBefore + collSurplusPoolBefore) *
            priceBefore -
            debtBefore;
        uint256 afterEquity = (activePoolCollAfter + collSurplusPoolAfter) * priceAfter - debtAfter;
    }

    function testGetLiquidateCdpsRequirement() public {
        setPrice(3264556868619879573026084322651197177268672182083607397683096094371498037850);
        openCdp(69652862183452624822016556040736808781, 1);
        setPrice(35214457645965492516898328250219169724615509157237329333267235674754740177);
        setEthPerShare(0);
        setPrice(0);
        openCdp(
            25680956500934176239642042885176745386278813810605282339941673502986668712,
            703271415273598548
        );
        setPrice(697741474626659514621642131614254585334739556886403282679043574150546445);
        setEthPerShare(0);
        liquidateCdps(2252467458);
    }

    function testGetLiquidationPrecondition() public {
        setEthPerShare(4676074530337448333154874636284405909660288077692074436378651732565385820);
        setEthPerShare(121723041127249310969693481616406928693460288241266723901306125760671698189);
        setEthPerShare(5009376261553868904870699697388021000813000619345695951626510062434371576);
        openCdp(331122237537735863278688276997565185798016290397008375268300287328688032, 1);
        openCdp(
            5431275612983197753898029233276238246222276901738759866963494316953057560184,
            939336331742640342
        );
        setEthPerShare(126708291550348242045596698306381078560921466586869136435238349973189731358);
        setEthPerShare(0);
        liquidateCdps(32196079);
    }

    function testGetICRMustBeAboveMCRorCCR() public {
        openCdp(75300317850386881515037613066457986, 1);
        openCdp(
            3247335123189069439632999755254158605220646892775811768642425889390169656571,
            621779537595273744
        );
        setEthPerShare(569167568057158159980723842815614925281518516805731465637553840);
        setEthPerShare(0);
        repayEBTC(
            9134837060512050891165910624894753554151602525392217144768174063888028620303,
            22962890867158867814049967727650951797802352273713784497290262518250038227473
        );
    }

    function testGetGasRefund() public {
        // TODO convert to foundry test
        setEthPerShare(320990760767759855665581119236317863482547217297538940976328986384347);
        openCdp(26813322668106373355851675928577557790421707851094448227301944, 1);
        setEthPerShare(5344609922436460377681113694659206750079290288127281100932756);
        addColl(8998373131940891300701418953323269805182346149013003655641488006448, 0);
        openCdp(0, 1);
        closeCdp(0);
    }

    function testGetTCRMustIncreaseAfterLiquidation() public {
        setEthPerShare(12400542648256292754961779260076532665041890555330100137126831902070556);
        openCdp(412840791364640467162300642920, 1);
        withdrawColl(
            44587864534782987197058919504145324787930113096565080678163339697467,
            3035020603323
        );
        openCdp(
            2285243171284733437318174962905631735518539885491274999644636718241370058,
            132673875684216277
        );
        setEthPerShare(0);
        setEthPerShare(455164160439835708458810255348816459178554101974349799990005);
        setEthPerShare(0);
        liquidateCdps(0);
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
            (currentPrice * 1e18) / 1.1e18,
            (currentPrice * 1.1e18) / 1e18
        );

        console2.log("setPrice", _newPrice);
        priceFeedMock.setPrice(_newPrice);
    }

    function openCdp(uint256 _col, uint256 _EBTCAmount) internal {
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
        borrowerOperations.openCdp(_EBTCAmount, bytes32(0), bytes32(0), _col);
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
            collateral.getPooledEthByShares(cdpManager.getCdpColl(_cdpId))
        );

        console2.log("withdrawColl", _amount, _i);
        borrowerOperations.withdrawColl(_cdpId, _amount, _cdpId, _cdpId);
    }

    function repayEBTC(uint _amount, uint256 _i) internal {
        uint256 numberOfCdps = sortedCdps.cdpCountOf(user);

        _i = clampBetween(_i, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(user, _i);

        (uint256 entireDebt, , ) = cdpManager.getEntireDebtAndColl(_cdpId);
        _amount = clampBetween(_amount, 0, entireDebt);

        console2.log("repayEBTC", _amount, _i);
        borrowerOperations.repayEBTC(_cdpId, _amount, _cdpId, _cdpId);
    }

    function redeemCollateral(
        uint _EBTCAmount,
        uint _partialRedemptionHintNICR,
        uint _maxFeePercentage
    ) internal {
        require(
            block.timestamp > cdpManager.getDeploymentStartTime() + cdpManager.BOOTSTRAP_PERIOD(),
            "CdpManager: Redemptions are not allowed during bootstrap phase"
        );

        _EBTCAmount = clampBetween(_EBTCAmount, 0, eBTCToken.balanceOf(address(user)));

        _maxFeePercentage = clampBetween(
            _maxFeePercentage,
            cdpManager.redemptionFeeFloor(),
            cdpManager.DECIMAL_PRECISION()
        );

        console2.log("redeemCollateral", _EBTCAmount, _partialRedemptionHintNICR, _maxFeePercentage);
        cdpManager.redeemCollateral(
            _EBTCAmount,
            bytes32(0),
            bytes32(0),
            bytes32(0),
            _partialRedemptionHintNICR,
            0,
            _maxFeePercentage
        );
    }

    function liquidateCdps(uint _n) internal {
        _n = clampBetween(_n, 1, cdpManager.getCdpIdsCount());

        console2.log("liquidateCdps", _n);
        cdpManager.liquidateCdps(_n);
    }
}
