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
    uint256 internal constant MAX_UINT256 = 2 ** 256 - 1;

    bool constant DEBUG = false; // Print debug logging

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
    function testCdpOrderingSanityCheck() public {
        uint256 cdp0Debt = 2000e18;
        uint256 cdp1Debt = 2001e18;

        bytes32 cdp0Id = borrowerOperations.openCdp{value: _calculateCollAmount(cdp0Debt, 200e16)}(
            5e17,
            cdp0Debt,
            bytes32(0),
            bytes32(0)
        );

        // Insert a second CDP with a lower CR immediately. We expect it to be later in the LL.
        bytes32 cdp1Id = borrowerOperations.openCdp{value: _calculateCollAmount(cdp0Debt, 200e16)}(
            5e17,
            cdp1Debt,
            bytes32(0),
            bytes32(0)
        );

        bytes32 first = sortedCdps.getFirst();
        assertEq(first, cdp0Id);
        bytes32 second = sortedCdps.getNext(first);
        assertEq(second, cdp1Id);
    }

    /**
        Pending interest should be considered when inserting a new CDP. CDPs with a lower CR should be closer to the end of the LL
        - Create a CDP.
        - Create a second CDP with a lower CR than the first one after some time has passed for interest to accumulate
        - If pending interest was not considered, this CDP should go after the first one (it has a lower CR so goes later in the list)
        - If pending interest is considered, this new CDP should go before the first one (it has a higher CR now, due to the increased debt)
     */
    function testPendingInterestShouldBeConsideredWhenInsertingNewCdp() public {
        uint256 cdp0Debt = 2000e18;
        uint256 cdp1Debt = 2001e18;

        bytes32 cdp0Id = borrowerOperations.openCdp{value: _calculateCollAmount(cdp0Debt, 200e16)}(
            5e17,
            cdp0Debt,
            bytes32(0),
            bytes32(0)
        );

        if (DEBUG) {
            console.log("Initial Cdp0 State");
            _getAndPrintCdpState(cdp0Id);
        }

        skip(365 days);

        // Insert a second CDP with a lower CR than the first one originally, but with a higher CR due to the interest. It should be earlier in the list given the higher CR
        bytes32 cdp1Id = borrowerOperations.openCdp{value: _calculateCollAmount(cdp0Debt, 200e16)}(
            5e17,
            cdp1Debt,
            bytes32(0),
            bytes32(0)
        );

        bytes32 first = sortedCdps.getFirst();
        assertEq(first, cdp1Id);
        bytes32 second = sortedCdps.getNext(first);
        assertEq(second, cdp0Id);

        if (DEBUG) {
            console.log("Cdp0 State After Timewarp");
            _getAndPrintCdpState(cdp0Id);
            _printCdpList();
            console.log("Cdp1 State After Creation");
            _getAndPrintCdpState(cdp1Id);
        }
    }

    /**
        - Open two CDPs at the same time. 
        - Advance time such that pending interest can accumulate 
        - Modify 
    */
    function testPendingInterestShouldBeConsideredWhenReinsertingExistingCdp() public {
        uint256 cdp0Debt = 2000e18;
        uint256 cdp1Debt = 2001e18;

        bytes32 cdp0Id = borrowerOperations.openCdp{value: _calculateCollAmount(cdp0Debt, 200e16)}(
            5e17,
            cdp0Debt,
            bytes32(0),
            bytes32(0)
        );

        bytes32 cdp1Id = borrowerOperations.openCdp{value: _calculateCollAmount(cdp0Debt, 200e16)}(
            5e17,
            cdp1Debt,
            bytes32(0),
            bytes32(0)
        );

        skip(365 days);

        // CDP 1 has more debt and same coll, therefore a lower CR - it should be further towards the end of the LL (0 -> 1)
        bytes32 first = sortedCdps.getFirst();
        assertEq(first, cdp0Id);
        bytes32 second = sortedCdps.getNext(first);
        assertEq(second, cdp1Id);

        // TODO: Verify pending interest, total values

        /**
            - the expected total debt owed (principal + interest) by cdp0 is around 2000*1.02
            - the expected debt (pendingEBTCDebtInterest) over one year for cdp0 is around X
            - the expected NICR for cdp0 is around 20/2254.2=0.0088724452 (which will be scaled by 1e20 in code)
         */

        // Update Operation on one that should cause a reorder
        // We will make CDP 1 have more collateral, raising it's CR above that of CDP 0
        borrowerOperations.addColl{value: 1e18}(cdp1Id, bytes32(0), bytes32(0));

        // They should have switched (1 -> 0)
        first = sortedCdps.getFirst();
        assertEq(first, cdp1Id);
        second = sortedCdps.getNext(first);
        assertEq(second, cdp0Id);
    }

    /**
        Open two CDPs of set sizes at the same time.
        - Ensure compound interest does not cause two CDPs to flip positions
    */
    function testCdpReorderingFromCompoundingInterest() public {
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

        uint256 timeElapsed = 0;
        uint256 maxTimeElapsed = 300 * 365 days;

        if (DEBUG) {
            _getAndPrintCdpState(cdpIds[0]);
            _getAndPrintCdpState(cdpIds[1]);
        }

        while (timeElapsed < maxTimeElapsed) {
            // Track ICR and NICR
            cdpNICRBefore[0] = cdpManager.getNominalICR(cdpIds[0]);
            cdpNICRBefore[1] = cdpManager.getNominalICR(cdpIds[1]);

            if (DEBUG) {
                console.log("====== Time Passed ", timeElapsed / 365 days, " ======");
                console.log("NICR Before [0] ", format(cdpNICRBefore[0]));
                console.log("NICR Before [1] ", format(cdpNICRBefore[1]));
                console.log(
                    "NICR Before Diff",
                    format(stdMath.delta(cdpNICRBefore[0], cdpNICRBefore[1]))
                );
            }

            // Advance Time
            skip(365 days);

            // Track ICR and NICR - has the relative value changed?
            cdpNICRAfter[0] = cdpManager.getNominalICR(cdpIds[0]);
            cdpNICRAfter[1] = cdpManager.getNominalICR(cdpIds[1]);

            if (DEBUG) {
                console.log("NCIR After [0] ", format(cdpNICRAfter[0]));
                console.log("NCIR After [1] ", format(cdpNICRAfter[1]));
                console.log(
                    "NICR After Diff",
                    format(stdMath.delta(cdpNICRAfter[0], cdpNICRAfter[1]))
                );
                console.log("");
            }

            // If it ordering (NICR) has reversed since last check, report
            if (
                (cdpNICRBefore[0] > cdpNICRBefore[1] && cdpNICRAfter[1] > cdpNICRAfter[0]) ||
                (cdpNICRBefore[1] > cdpNICRBefore[0] && cdpNICRAfter[0] > cdpNICRAfter[1])
            ) {
                console.log(
                    "Reorder Discovered after ",
                    vm.toString(timeElapsed / 86400 / 365),
                    " years"
                );
                assert(false);
            }
            timeElapsed = timeElapsed + 365 days;
        }
    }

    // Duplicated helper functions, should be consolidated
    function _calculateCollAmount(
        uint256 debt,
        uint256 collateralRatio
    ) internal view returns (uint256) {
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

    function _bulkOpenCdps(
        uint256[] memory debts,
        uint256[] memory colls,
        address owner
    ) internal returns (bytes32[] memory cdpIds) {
        require(debts.length == colls.length, "Input array length mismatch");

        vm.startPrank(owner);
        for (uint256 i = 0; i < debts.length; i++) {
            bytes32 cdpId = borrowerOperations.openCdp{value: colls[i]}(
                5e17,
                debts[i],
                bytes32(0),
                bytes32(0)
            );

            cdpIds[i] = cdpId;
        }
        vm.stopPrank();

        return cdpIds;
    }

    function _printCdpList() internal {
        // TODO: Add print functions to sorted CDPs? Paginated optionally?
        uint numCdps = sortedCdps.getSize();
        uint i = 0;
        bytes32 cdpId;

        while (i < numCdps) {
            if (i == 0) {
                cdpId = sortedCdps.getFirst();
            } else {
                cdpId = sortedCdps.getNext(cdpId);
            }
            console.log(vm.toString(cdpId));
            ++i;
        }
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
        console.log("NICR", format(cdpManager.getNominalICR(cdpId)));
        console.log("");
    }
}
