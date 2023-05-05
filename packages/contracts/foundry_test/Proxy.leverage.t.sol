// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;
import "forge-std/Test.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";

/*
 * Test suite that tests exactly one thing: opening CDPs
 * It tests different cases and also does random testing against random coll amounts and amount of users
 */
contract ProxyLeverageTest is eBTCBaseFixture {
    mapping(bytes32 => bool) private _cdpIdsExist;

    SwapOperation[] internal EMPTY_SWAPS;

    function setUp() public override {
        eBTCBaseFixture.setUp();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();

        EMPTY_SWAPS = new SwapOperation[](0);
    }

    function test_OpenLeveragedCDPHappy() public {
        address payable[] memory users;
        users = _utils.createUsers(1);
        address user = users[0];

        vm.startPrank(user);

        vm.deal(user, type(uint96).max);
        collateral.deposit{value: 10000 ether}();

        // deploy proxy for user
        address proxy;

        // approve collateral for proxy
        collateral.approve(address(proxy), type(uint256).max);

        uint netColl = 30 ether;
        uint grossColl = 30 ether + 2e17;

        // leverage open 
        uint debt = _utils.calculateBorrowAmount(
            grossColl,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );

        // Make sure there is no CDPs in the system yet
        assert(sortedCdps.getLast() == "");

        LeverageMacro.LeverageMacroOperation memory operation = LeverageMacroOperation(
            address(collateral),
            grossColl,
            EMPTY_SWAPS,
            EMPTY_SWAPS,
            LeverageMacro.OperationType.open,
            
        );
        
        // confirm debt is equal to expected
        LeverageMacro.CheckValueAndType expectedDebt = CheckValueAndType(
            debt,
            LeverageMacro.Operator.equal
        );

        // confirm coll is equal to expected
        LeverageMacro.CheckValueAndType expectedCollateral = CheckValueAndType(
            netColl,
            LeverageMacro.Operator.equal
        );

        // confirm status is active
        ICdpManagerData.Status expectedStatus = ICdpManagerData.Status.active;

        LeverageMacro.PostCheckParams postCheckParams = LeverageMacro.PostCheckParams(
            expectedDebt,
            expectedCollateral,
            bytes32(0),
            expectedStatus
        );        

        proxy.doOperation(
            LeverageMacro.FlashLoanType.stETH,
            debt,

            LeverageMacro.PostOperationCheck.openCdp,
            postCheckParams
            
        );

        vm.stopPrank();
    }

    function test_AdjustLeveragedCDPHappy() {
        
    }

    function test_OpenAndCloseLeveragedCDPHappy() {
        
    }

    function _generateCalldataSwapMock1Inch() internal {}

}
