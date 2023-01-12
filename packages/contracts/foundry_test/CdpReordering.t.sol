// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.11;

import "forge-std/Test.sol";

import {eBTCBaseFixture} from "./BaseFixture.sol";
import {Utilities} from "./utils/Utilities.sol";
import {LogUtils} from "./utils/LogUtils.sol";

// TODO: Do an invariant test that total interest minted is equal to sum of all borrowers' interest
contract CdpReorderingTest is eBTCBaseFixture, LogUtils {
    struct CdpState {
        uint256 debt;
        uint256 coll;
        uint256 pendingEBTCDebtReward;
        uint256 pendingEBTCInterest;
        uint256 pendingETHReward;
    }

    struct RunParams {
        uint256 duration;
        uint256 maxColl;
        uint256 maxDebt;
        uint256 price;
    }

    uint256 private testNumber;
    address payable[] users;

    // TODO: Move to base fixture
    Utilities internal _utils;
    // TODO: Inherit base fixture from LiquityBase
    uint256 EBTC_GAS_COMPENSATION;
    uint256 public constant DECIMAL_PRECISION = 1e18;
    uint256 internal constant MAX_UINT256 = 2**256 - 1;

    ////////////////////////////////////////////////////////////////////////////
    // Tests
    ////////////////////////////////////////////////////////////////////////////

    function setUp() public override {
        eBTCBaseFixture.setUp();

        eBTCBaseFixture.connectLQTYContracts();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();

        _utils = new Utilities();
        users = _utils.createUsers(3);

        EBTC_GAS_COMPENSATION = cdpManager.EBTC_GAS_COMPENSATION();
    }

    /**
        Open a number of CDPs at the same time. 
        We want to confirm they are _not reordered_ due to pending interest payments
        - Ensure the order is the same at the start as at the end
    */
    function testTroveReorderingSim() public {
    }

    /**
        Pending interest should be considered when inserting a new CDP
        Create a CDP.
        Later create a second trove that without interest, would be inserted _after_ the original CDP. However, considering the interest the first has accumulated, it should be inserted before. Ensure this happens.
     */
    function testPendingInterestShouldBeConsideredWhenInsertingNewCdp() public {
        uint cdp0Debt = 2000e18;
        uint cdp1Debt = 2001e18;

        bytes32 cdp0Id = borrowerOperations.openCdp{value: _calculateCollAmount(cdp0Debt, 200e16)}(
                5e17,
                cdp0Debt,
                bytes32(0),
                bytes32(0)
            );

        console.log("Initial Cdp0 State");
        _getAndPrintCdpState(cdp0Id);

        skip(365 days);

        console.log("Cdp0 State After Timewarp");
        _getAndPrintCdpState(cdp0Id);

        bytes32 cdp1Id = borrowerOperations.openCdp{value: _calculateCollAmount(cdp0Debt, 200e16)}(
                5e17,
                cdp1Debt,
                bytes32(0),
                bytes32(0)
            );
        
        console.log("Initial Cdp1 State");
        _getAndPrintCdpState(cdp1Id);

        bytes32 first = sortedCdps.getFirst();
        assertEq(first, cdp1Id);
        bytes32 second = sortedCdps.getNext(first);
        assertEq(second, cdp0Id);
    }

    /**
        Open two CDPs of random sizes at the same time.
        - How long does it take for compounding interest to cause them to flip?
        - What is the relative different in ICR/NICR of them at the maximum time?
        - Do they flip within the maximum time alloted? (100 years)
    */
    function testCdpReorderingTwoSameTimeSim() public {
        uint256 numCdps = 2;

        uint256[] memory cdpColl = new uint256[](numCdps);
        uint256[] memory cdpDebt = new uint256[](numCdps);
        bytes32[] memory cdpIds = new bytes32[](numCdps);

        cdpDebt[0] = 2000e18;
        cdpDebt[1] = 2000001e15;

        cdpColl[0] = _calculateCollAmount(cdpDebt[0], 200e16);
        cdpColl[1] = cdpColl[0];

        // Open all CDPs
        for (uint256 i = 0; i < numCdps; i++) {
            bytes32 cdpId = borrowerOperations.openCdp{value: cdpColl[i]}(
                5e17,
                cdpDebt[i],
                bytes32(0),
                bytes32(0)
            );

            cdpIds[i] = cdpId;
        }

        uint256[] memory cdpNICRBefore = new uint256[](numCdps);
        uint256[] memory cdpNICRAfter = new uint256[](numCdps);

        uint timeElapsed = 0;
        uint maxTimeElapsed = 300 * 365 days;

        _getAndPrintCdpState(cdpIds[0]);
        _getAndPrintCdpState(cdpIds[1]);

        while (timeElapsed < maxTimeElapsed) {
            // Track ICR and NICR
            cdpNICRBefore[0] = cdpManager.getNominalICR(cdpIds[0]);
            cdpNICRBefore[1] = cdpManager.getNominalICR(cdpIds[1]);

            console.log("====== Time Passed ", timeElapsed / 365 days ," ======");
            console.log("NICR Before [0] ", format(cdpNICRBefore[0]));
            console.log("NICR Before [1] ", format(cdpNICRBefore[1]));
            console.log("NICR Before Diff", format(stdMath.delta(cdpNICRBefore[0], cdpNICRBefore[1])));

            // Advance Time
            skip(365 days);

            // Track ICR and NICR - has the relative value changed?
            cdpNICRAfter[0] = cdpManager.getNominalICR(cdpIds[0]);
            cdpNICRAfter[1] = cdpManager.getNominalICR(cdpIds[1]);

            console.log("NCIR After [0] ", format(cdpNICRAfter[0]));
            console.log("NCIR After [1] ", format(cdpNICRAfter[1]));
            console.log("NICR After Diff", format(stdMath.delta(cdpNICRAfter[0], cdpNICRAfter[1])));
            console.log("");

            // If it ordering (NICR) has reversed since last check, report
            if (
                (cdpNICRBefore[0] > cdpNICRBefore[1] && cdpNICRAfter[1] > cdpNICRAfter[0]) ||
                (cdpNICRBefore[1] > cdpNICRBefore[0] && cdpNICRAfter[0] > cdpNICRAfter[1])
            ) {
                console.log("Reorder!");
                return;
            }
                timeElapsed = timeElapsed + 365 days;
        }
    }

    // Duplicated helper functions, should be consolidated
    function _calculateCollAmount(uint256 debt, uint256 collateralRatio)
        internal
        view
        returns (uint256)
    {
        return _utils.calculateCollAmount(debt, priceFeedMock.getPrice(), collateralRatio);
    }

    function _getEntireDebtAndColl(bytes32 cdpId) internal view returns (CdpState memory) {
        (
            uint256 debt,
            uint256 coll,
            uint256 pendingEBTCDebtReward,
            uint256 pendingEBTCDebtInterest,
            uint256 pendingETHReward
        ) = cdpManager.getEntireDebtAndColl(cdpId);
        return
            CdpState(debt, coll, pendingEBTCDebtReward, pendingEBTCDebtInterest, pendingETHReward);
    }

    function _getAndPrintCdpState(bytes32 cdpId) internal {
        CdpState memory cdpState = _getEntireDebtAndColl(cdpId);
        _printCdpState(cdpId, cdpState);
    }

    function _printCdpState(bytes32 cdpId, CdpState memory cdpState) internal {
        // Issue console.log bytes32
        console.log("=== CDP State for ===");
        console.log("debt", format(cdpState.debt)); 
        console.log("coll", format(cdpState.coll));
        console.log("pendingEBTCDebtReward", format(cdpState.pendingEBTCDebtReward)); 
        console.log("pendingEBTCDebtInterest", format(cdpState.pendingEBTCInterest)); 
        console.log("pendingETHReward", format(cdpState.pendingETHReward));
        console.log("ICR", format(cdpManager.getCurrentICR(cdpId, priceFeedMock.getPrice())));
        console.log("");
    }
}
