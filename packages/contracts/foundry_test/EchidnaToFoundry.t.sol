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
        assertTrue(invariant_CSP_01(collateral, collSurplusPool), "CSP-01");
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
