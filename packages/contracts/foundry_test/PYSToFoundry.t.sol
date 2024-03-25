// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import {Properties} from "../contracts/TestContracts/invariants/Properties.sol";
import {IERC20} from "../contracts/Dependencies/IERC20.sol";
import {IERC3156FlashBorrower} from "../contracts/Interfaces/IERC3156FlashBorrower.sol";
import "../contracts/TestContracts/invariants/echidna/EchidnaProperties.sol";
import "../contracts/TestContracts/invariants/TargetFunctions.sol";
import {FoundryAsserts} from "./utils/FoundryAsserts.sol";
import {BeforeAfterWithLogging} from "./utils/BeforeAfterWithLogging.sol";

/*
 * Test suite that converts from echidna "fuzz tests" to foundry "unit tests"
 * The objective is to go from random values to hardcoded values that can be analyzed more easily
 */
contract EToFoundry is
    Test,
    FoundryAsserts,
    TargetFunctions,
    EchidnaProperties
{
    modifier setup() override {
        _;
        address sender = uint160(msg.sender) % 3 == 0 ? address(USER1) : uint160(msg.sender) % 3 == 1
            ? address(USER2)
            : address(USER3);
        actor = actors[sender];
    }
    /** TEMP BAD */

    // NOTE: Customized setup for a Yield Control actor and a Yield Target actor
    function _setupYieldActors() internal {
        bool success;
        address[] memory tokens = new address[](2);
        tokens[0] = address(eBTCToken);
        tokens[1] = address(collateral);
        address[] memory callers = new address[](2);
        callers[0] = address(borrowerOperations);
        callers[1] = address(activePool);
        address[] memory addresses = new address[](2);

        addresses[0] = yieldTargetAddress;
        Actor[] memory actorsArray = new Actor[](2);
        // Just add Yield target, leaving as loop because we may want to make this more complex later
        for (uint i = 0; i < 1; i++) {
            actors[addresses[i]] = new Actor(tokens, callers);
            (success, ) = address(actors[addresses[i]]).call{value: INITIAL_ETH_BALANCE}("");
            assert(success);
            (success, ) = actors[addresses[i]].proxy(
                address(collateral),
                abi.encodeWithSelector(CollateralTokenTester.deposit.selector, ""),
                INITIAL_COLL_BALANCE
            );
            assert(success);
        }

        // We set up our Control Address with an initial amount of collateral
        // NOT as an actor (exposes control to outside tx)
        (success, ) = yieldControlAddress.call{value: INITIAL_ETH_BALANCE}("");
        hevm.prank(yieldControlAddress);
        collateral.deposit{value: INITIAL_COLL_BALANCE - 0.2 ether}();

        // Set the PYS at 0
        TargetFunctions.setGovernanceParameters(2, 0);

        priceFeedMock.setPrice(1e8); /// TODO: Does this price make any sense?

        // The Yield Target opens a CDP. We want to follow their Yield Story
        // At the moment we aren't letting them do anything else
        actor = actors[yieldTargetAddress];
        // Small eBTC amount to prevent liquidations for now
        (success, yieldTargetCdpId) = _openCdp(INITIAL_COLL_BALANCE, 1e4);
        assert(success);
    }

    // From EchidnaDoomsDayTester
    function _openCdp(uint256 _col, uint256 _EBTCAmount) internal returns (bool, bytes32) {
        bool success;
        bytes memory returnData;

        // we pass in CCR instead of MCR in case it's the first one
        {
            uint price = priceFeedMock.getPrice();

            uint256 requiredCollAmount = (_EBTCAmount * cdpManager.CCR()) / (price);
            uint256 minCollAmount = max(
                cdpManager.MIN_NET_STETH_BALANCE() + borrowerOperations.LIQUIDATOR_REWARD(),
                requiredCollAmount
            );
            uint256 maxCollAmount = min(2 * minCollAmount, INITIAL_COLL_BALANCE / 10);
            _col = between(requiredCollAmount, minCollAmount, maxCollAmount);
        }

        (success, ) = actor.proxy(
            address(collateral),
            abi.encodeWithSelector(
                CollateralTokenTester.approve.selector,
                address(borrowerOperations),
                _col
            )
        );
        t(success, "Approve never fails");

        {
            (success, returnData) = actor.proxy(
                address(borrowerOperations),
                abi.encodeWithSelector(
                    BorrowerOperations.openCdp.selector,
                    _EBTCAmount,
                    bytes32(0),
                    bytes32(0),
                    _col
                )
            );
        }

        bytes32 newCdpId;
        if (success) {
            newCdpId = abi.decode(returnData, (bytes32));
        }

        // We don't want the actor to do other things in this case (yet)
        actors[yieldTargetAddress].setRestrictedMode(true);

        return (success, newCdpId);
    }

    // We override just the part of set Governance parameters that might set the stakingRewardSplit
    // This allows testing against 0 if we wish it
    function setGovernanceParameters(uint256 parameter, uint256 value) public override {
        /*if (parameter == 2) {
            parameter++;
        }*/

        // Allows us flexibility that other params can still change.
        // For now we just want the PYS to be 0
        TargetFunctions.setGovernanceParameters(parameter, value);
    }

    // WIP: Ideas with regards to tracking PYS as it changes
    // Assuming only upwards rebases for now
    function setEthPerShare(uint256 _newEthPerShare) public override {
        _before(yieldTargetCdpId);

        TargetFunctions.setEthPerShare(_newEthPerShare);
        // Sync the accounting for our tracked cdp after rebase
        hevm.prank(address(borrowerOperations));
        cdpManager.syncGlobalAccounting();

        _after(yieldTargetCdpId);
    }
    /** TEMP BAD */


    function setUp() public {
        yieldControlAddress = address(0x5000000000000005);
        yieldTargetAddress =  address(0x6000000000000006);

        _setUp();
        _setUpActors();
        _setupYieldActors();
        actor = actors[address(USER1)];

        setGovernanceParameters(2, 50);
    }

    function test_pys03() public {
        setGovernanceParameters(2, 1);
        setEthPerShare(92486899360406498);

        assertTrue(invariant_PYS_03_A(
            cdpManager,
            vars
        ), "PYS");

        console2.log("yieldControlAddress", yieldControlAddress);
        console2.log("yieldTargetCdpId", uint256(yieldTargetCdpId));
        console2.log("vars.prevStEthFeeIndex", vars.prevStEthFeeIndex);
        console2.log("vars.afterStEthFeeIndex", vars.afterStEthFeeIndex);

    }

    function test_pys04() public {
        setEthPerShare(99930128941342140000266291552701334095267781396938829755845405936407078624212);
        setGovernanceParameters(703936011954574190096648107132477385862451789338, 921840306035071876313799756458405179838510662337);

        assertTrue(invariant_PYS_04(
            cdpManager,
            vars
        ), "PYS");

        console2.log("Index Before", vars.yieldStEthIndexBefore);
        console2.log("Index After", vars.yieldStEthIndexAfter);
        console2.log("vars.prevStEthFeeIndex", vars.prevStEthFeeIndex);
        console2.log("vars.afterStEthFeeIndex", vars.afterStEthFeeIndex);
        console2.log("vars.stakingRewardSplitBefore", vars.stakingRewardSplitBefore);
        console2.log("vars.stakingRewardSplitAfter", vars.stakingRewardSplitAfter);
        console2.log("vars.yieldProtocolCollSharesBefore", vars.yieldProtocolCollSharesBefore);
        console2.log("vars.yieldProtocolCollSharesAfter", vars.yieldProtocolCollSharesAfter);
        console2.log("vars.yieldProtocolValueBefore", vars.yieldProtocolValueBefore);
        console2.log("vars.yieldProtocolValueAfter", vars.yieldProtocolValueAfter);

    }

    function test_observe_pys() public {
        redeemCollateral(uint256(90458316914717687018285766791880846721660733942214271788798389244204902476436), bytes32(0x9984ecefafb4976872527b3d689e455b678d5fbcb6f2a774aaa77868bf7787ee), 525600000, false, true, false, 80444820362816977085570302672334763444553857845933241468982361145635920126096, 115792089237316195423570985008687907853269984665640564039457584007913129639933);
        observe();
        }
                

    function test_echidna_GENERAL_19() public {
        openCdp(2010411661375431176097740776866814458891947993313687254558535, 66816);
        addColl(115792089237316195423570985008687907853269984665640564039457584007913129639935, 131072);
        redeemCollateral(79535811480921385075613638753076253022779147871111159552744519620652667383301, bytes32(0x2337fbe6b0de0d43dbbc3cea2dd4e93de3df62424d0cac43801da0984d40f4e9), 967132654952507783299167304032791279490280620328, false, true, true, 35318840368464762976683892081176931813236465855817304324070807662237527033729, 7);
        adjustCdp(528117742564021316393271938429391066789996829083, 89640239480504075107596920309519069394391085781043110840553585090728759853056, 65836381767953292916116827710951075734401640722998164525497771436128998279695, false);
        }
                

    function test_echidna_PYS_01() public {
        setEthPerShare(1000000000000000000000000);
        setEthPerShare(115792089237316195423570985008687907853269984665640564039457584007913129639851);
        setGovernanceParameters(16, 0);
        setEthPerShare(107255381416776339463566659553951964104195326848432414062452240917269290912885);
        setEthPerShare(115792089237316195423570985007720775198317476882341396735424792728422849019608);
        }
                

    function test_echidna_PYS_03_B() public {
        setEthPerShare(100520583068771558804887038843340722944597399665684362727926778979678355358689);
        setEthPerShare(1683309);
        setEthPerShare(0);
        setEthPerShare(882900241912855636407163849928715490687649047704);
        setEthPerShare(115792089237316195423570985008687907853269984665640564039457584007913129635136);
        }
                

    function test_echidna_coll_surplus_pool_invariant_2() public {
        openCdp(2010411661375431176097740776866814458891947993313687254558535, 66816);
        addColl(115792089237316195423570985008687907853269984665640564039457584007913129639935, 131072);
        redeemCollateral(189528868517225480592232, bytes32(0x5eeed1af03563e995b9ab2720adbe1cb1ee15a976f6686520414cca85302b37f), 115792089237316195423570985008687907853269984665640564039457534007913129639918, false, false, true, 115792089237316195423570985007272045719787830250843198431889343271055891324045, 65518);
    }

}