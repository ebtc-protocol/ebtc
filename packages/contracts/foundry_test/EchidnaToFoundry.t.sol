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

    function testTCRMustIncreaseAfterLiquidation() public {
        // setEthPerShare 982343204100130190
        // openCdp 2200000000000000016 1
        // withdrawColl 1640157506641381371 0
        // openCdp 2232664843905093514 132673875684216277
        // setEthPerShare 893039276454663809
        // setEthPerShare 820056407903603577
        // setEthPerShare 745505825366912342
        // liquidateCdps 1

        vm.stopPrank();
        vm.startPrank(user);
        vm.deal(user, type(uint96).max);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 100 ether}();

        collateral.setEthPerShare(982343204100130190);
        bytes32 _cdpId = borrowerOperations.openCdp(1, HINT, HINT, 2200000000000000016);
        console2.log("cdpId");
        console2.logBytes32(_cdpId);
        borrowerOperations.withdrawColl(_cdpId, 1640157506641381371, _cdpId, _cdpId); // NOTE: THIS IS AN ILLEGAL MOVE // NOTE: Changing order is irrelevant, it's not a ordering issue
        bytes32 secondCdpId = borrowerOperations.openCdp(132673875684216277, HINT, HINT, 2232664843905093514);

        console2.log("Cdp Ordering afrer open - first - last");
        console2.logBytes32(sortedCdps.getFirst());
        console2.log("NICR FIRST", cdpManager.getNominalICR(sortedCdps.getFirst()));
        console2.logBytes32(sortedCdps.getFirst());
        console2.log("NICR LAST", cdpManager.getNominalICR(sortedCdps.getLast()));

        console2.log("secondCdpId");
        console2.logBytes32(secondCdpId);
        collateral.setEthPerShare(893039276454663809);
        collateral.setEthPerShare(820056407903603577);
        collateral.setEthPerShare(745505825366912342);

        cdpManager.applyPendingGlobalState();
        uint256 _price = priceFeedMock.getPrice();

        uint256 tcrBeforeAnyLocal = cdpManager.getTCR(_price);
        console2.log("tcrBeforeAnyLocal", tcrBeforeAnyLocal);

        // Log the details of both CDPs
        console2.log("First CDP CR", cdpManager.getCurrentICR(_cdpId, _price));
        console2.log("Second CDP CR", cdpManager.getCurrentICR(secondCdpId, _price));

        // Prank BO for local
        vm.stopPrank();
        vm.startPrank(address(borrowerOperations));
        cdpManager.applyPendingState(_cdpId);
        cdpManager.applyPendingState(secondCdpId);
        console2.log("AFTER First CDP CR", cdpManager.getCurrentICR(_cdpId, _price));
        console2.log("AFTER Second CDP CR", cdpManager.getCurrentICR(secondCdpId, _price));
        // Resume prank
        vm.stopPrank();
        vm.startPrank(user);

        uint256 tcrBefore = cdpManager.getTCR(_price);
        console2.log("before", tcrBefore);

        console2.log("Cdp Ordering before liquidation - First - Last");
        console2.logBytes32(sortedCdps.getFirst());
        console2.log("NICR FIRST", cdpManager.getNominalICR(sortedCdps.getFirst()));
        console2.logBytes32(sortedCdps.getFirst());
        console2.log("NICR LAST", cdpManager.getNominalICR(sortedCdps.getLast()));

        cdpManager.liquidateCdps(1);

        uint256 tcrAfter = cdpManager.getTCR(_price);
        console2.log("after", tcrAfter);

        assertGt(tcrAfter, tcrBefore, L_12);
        vm.stopPrank();

        console2.log("Cdp Ordering at end");
        console2.logBytes32(sortedCdps.getFirst());
        console2.log("NICR FIRST", cdpManager.getNominalICR(sortedCdps.getFirst()));
        console2.logBytes32(sortedCdps.getFirst());
        console2.log("NICR LAST", cdpManager.getNominalICR(sortedCdps.getLast()));
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
            (currentEthPerShare * 1 ether) / 1.1 ether,
            (currentEthPerShare * 1.1 ether) / 1 ether
        );

        console2.log("setEthPerShare", _newEthPerShare);
        collateral.setEthPerShare(_newEthPerShare);
    }

    function setPrice(uint256 _newPrice) external {
        uint256 currentPrice = priceFeedMock.getPrice();
        _newPrice = clampBetween(
            _newPrice,
            (currentPrice * 1 ether) / 1.1 ether,
            (currentPrice * 1.1 ether) / 1 ether
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
        bytes32 id = borrowerOperations.openCdp(_EBTCAmount, bytes32(0), bytes32(0), _col);
        return id;
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
}
