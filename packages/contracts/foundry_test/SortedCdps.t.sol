// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";
import {Properties} from "../contracts/TestContracts/invariants/Properties.sol";

contract CDPOpsTest is eBTCBaseFixture, Properties {
    function setUp() public override {
        eBTCBaseFixture.setUp();

        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();
    }

    function test_Fuzz_cdpCountOf(uint256 _cdpCount, uint256 _maxNodes) public {
        _cdpCount = bound(_cdpCount, AMOUNT_OF_CDPS, 20);
        _maxNodes = bound(_maxNodes, 1, type(uint256).max);
        address user = _openSomeCDPs(_cdpCount);
        uint _cdpCountOfReturned = sortedCdps.cdpCountOf(user, sortedCdps.dummyId(), _maxNodes);
        // result should be capped by given maxNodes
        assertTrue(_cdpCountOfReturned <= _maxNodes);
        if (_maxNodes >= _cdpCount) {
            assertTrue(_cdpCountOfReturned == _cdpCount);
        } else {
            assertTrue(_cdpCountOfReturned == _maxNodes);
        }
    }

    function testGetCdpsOfUser() public {
        address user = _openSomeCDPs(AMOUNT_OF_CDPS);
        bytes32[] memory cdps = sortedCdps.getCdpsOf(user);
        bytes32[] memory cdpsByMaxNode = sortedCdps.getCdpsOf(
            user,
            sortedCdps.dummyId(),
            AMOUNT_OF_CDPS
        );
        bytes32[] memory cdpsByStartNode = sortedCdps.getCdpsOf(
            user,
            sortedCdps.getLast(),
            AMOUNT_OF_CDPS
        );
        for (uint256 cdpIx = 0; cdpIx < AMOUNT_OF_CDPS; cdpIx++) {
            bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, cdpIx);
            bytes32 _cdpId = sortedCdps.cdpOfOwnerByIdx(user, 0, cdpId, 1);
            assertEq(_cdpId, cdpId);
            assertEq(cdps[cdpIx], cdpId);
            assertEq(cdpsByMaxNode[cdpIx], cdpId);
            assertEq(cdpsByStartNode[cdpIx], cdpId);
        }
        // check count of CDP owned by the user
        uint _cdpCountOf = sortedCdps.cdpCountOf(user);
        uint _cdpCountOfByMaxNode = sortedCdps.cdpCountOf(
            user,
            sortedCdps.dummyId(),
            AMOUNT_OF_CDPS
        );
        uint _cdpCountOfByStartNode = sortedCdps.cdpCountOf(
            user,
            sortedCdps.getLast(),
            AMOUNT_OF_CDPS
        );
        assertEq(_cdpCountOf, AMOUNT_OF_CDPS);
        assertEq(_cdpCountOfByMaxNode, AMOUNT_OF_CDPS);
        assertEq(_cdpCountOfByStartNode, AMOUNT_OF_CDPS);
    }

    // Make sure if user didn't open CDP, cdps array is empty
    function testGetCdpsOfUserDoesNotExist() public {
        address user = _utils.getNextUserAddress();
        bytes32[] memory cdps = sortedCdps.getCdpsOf(user);
        assertEq(0, cdps.length);
    }

    // Keep amntOfCdps reasonable, as it will eat all the memory
    // Change to fuzzed uint16 with caution, as it can consume > 10Gb of Memory
    function testGetCdpsOfUserFuzz(uint8 amntOfCdps) public {
        address user = _openSomeCDPs(amntOfCdps);
        bytes32[] memory cdps = sortedCdps.getCdpsOf(user);
        // And check that amount of CDPs as expected
        assertEq(amntOfCdps, cdps.length);
        for (uint256 cdpIx = 0; cdpIx < amntOfCdps; cdpIx++) {
            bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, cdpIx);
            bytes32 cdp = cdps[cdpIx];
            assertEq(cdp, cdpId);
        }
    }

    function testNICRDescendingOrder() public {
        bytes32 cdpId;
        address user = _utils.getNextUserAddress();
        vm.startPrank(user);
        vm.deal(user, type(uint96).max);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 10 ether}();

        uint256 coll1 = 2000000000000000016 + borrowerOperations.LIQUIDATOR_REWARD();
        cdpId = borrowerOperations.openCdp(1, HINT, HINT, coll1);
        emit log_string("col1");
        emit log_uint(cdpManager.getCdpCollShares(cdpId));

        collateral.setEthPerShare(0.957599492232792566e18);

        uint256 coll2 = 1999995586570936579 +
            collateral.getSharesByPooledEth(borrowerOperations.LIQUIDATOR_REWARD());
        cdpId = borrowerOperations.openCdp(1, HINT, HINT, coll2);

        emit log_string("col2");
        emit log_uint(cdpManager.getCdpCollShares(cdpId));

        collateral.setEthPerShare(1.000002206719401318e18);

        uint256 coll3 = 2096314780549457901 +
            collateral.getSharesByPooledEth(borrowerOperations.LIQUIDATOR_REWARD());
        cdpId = borrowerOperations.openCdp(1, HINT, HINT, coll3);

        emit log_string("col3");
        emit log_uint(cdpManager.getCdpCollShares(cdpId));

        emit log_uint(cdpManager.getTCR(priceFeedMock.getPrice()));
        emit log_uint(cdpManager.getICR(sortedCdps.getFirst(), priceFeedMock.getPrice()));

        assertTrue(invariant_SL_01(cdpManager, sortedCdps, 0.01e18), "SL-01");
    }

    function testSortedCdpsICRgteTCRInvariant() public {
        uint256 coll = borrowerOperations.MIN_NET_COLL() +
            borrowerOperations.LIQUIDATOR_REWARD() +
            16;

        address user = _utils.getNextUserAddress();
        vm.startPrank(user);
        vm.deal(user, type(uint96).max);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: coll * 2}();

        borrowerOperations.openCdp(1, HINT, HINT, coll);
        borrowerOperations.openCdp(1, HINT, HINT, coll);
        collateral.setEthPerShare((collateral.getEthPerShare() * 1 ether) / 1.1 ether);

        emit log_uint(cdpManager.getTCR(priceFeedMock.getPrice()));
        emit log_uint(cdpManager.getICR(sortedCdps.getFirst(), priceFeedMock.getPrice()));

        assertTrue(invariant_SL_02(cdpManager, sortedCdps, priceFeedMock, 0.01e18), "SL-02");
    }

    function _openSomeCDPs(uint256 _cdpCount) internal returns (address user) {
        uint256 collAmount = 30 ether;
        user = _utils.getNextUserAddress();
        vm.startPrank(user);
        vm.deal(user, type(uint96).max);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 10000 ether}();
        uint256 borrowedAmount = _utils.calculateBorrowAmount(
            collAmount,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );
        // Open X amount of CDPs
        for (uint256 cdpIx = 0; cdpIx < _cdpCount; cdpIx++) {
            borrowerOperations.openCdp(borrowedAmount, HINT, HINT, collAmount);
        }
        vm.stopPrank();
    }
}
