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
        (uint _cdpCountOfReturned, ) = sortedCdps.getCdpCountOf(
            user,
            sortedCdps.dummyId(),
            _maxNodes
        );
        // result should be capped by given maxNodes
        assertTrue(_cdpCountOfReturned <= _maxNodes);
        if (_maxNodes >= _cdpCount) {
            assertTrue(_cdpCountOfReturned == _cdpCount);
        } else {
            assertTrue(_cdpCountOfReturned == _maxNodes);
        }

        // check zero CDP return
        bytes32[] memory cdpsNone = sortedCdps.getCdpsOf(_utils.getNextUserAddress());
        (bytes32[] memory cdpsNone2, , ) = sortedCdps.getAllCdpsOf(
            _utils.getNextUserAddress(),
            sortedCdps.dummyId(),
            _maxNodes
        );
        assertTrue(cdpsNone.length == 0, "getCdpsOf() should return zero if none is found");
        assertTrue(cdpsNone2.length == 0, "getAllCdpsOf() should return zero if none is found");
    }

    function testGetCdpsOfUser() public {
        address user = _openSomeCDPs(AMOUNT_OF_CDPS);
        bytes32[] memory cdps = sortedCdps.getCdpsOf(user);
        (bytes32[] memory cdpsByMaxNode, , ) = sortedCdps.getAllCdpsOf(
            user,
            sortedCdps.dummyId(),
            AMOUNT_OF_CDPS
        );
        (bytes32[] memory cdpsByStartNode, , ) = sortedCdps.getAllCdpsOf(
            user,
            sortedCdps.getLast(),
            AMOUNT_OF_CDPS
        );
        for (uint256 cdpIx = 0; cdpIx < AMOUNT_OF_CDPS; cdpIx++) {
            bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(user, cdpIx);
            (bytes32 _cdpId, ) = sortedCdps.cdpOfOwnerByIdx(user, 0, cdpId, 1);
            assertEq(_cdpId, cdpId);
            assertEq(cdps[cdpIx], cdpId);
            assertEq(cdpsByMaxNode[cdpIx], cdpId);
            assertEq(cdpsByStartNode[cdpIx], cdpId);
        }
        // check count of CDP owned by the user
        uint _cdpCountOf = sortedCdps.cdpCountOf(user);
        (uint _cdpCountOfByMaxNode, ) = sortedCdps.getCdpCountOf(
            user,
            sortedCdps.dummyId(),
            AMOUNT_OF_CDPS
        );
        (uint _cdpCountOfByStartNode, ) = sortedCdps.getCdpCountOf(
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

        cdpId = borrowerOperations.openCdp(borrowerOperations.MIN_CHANGE(), HINT, HINT, coll1);

        emit log_string("col1");
        emit log_uint(cdpManager.getCdpCollShares(cdpId));

        collateral.setEthPerShare(0.957599492232792566e18);

        uint256 coll2 = 1999995586570936579 +
            collateral.getSharesByPooledEth(borrowerOperations.LIQUIDATOR_REWARD());

        cdpId = borrowerOperations.openCdp(borrowerOperations.MIN_CHANGE(), HINT, HINT, coll2);

        emit log_string("col2");
        emit log_uint(cdpManager.getCdpCollShares(cdpId));

        collateral.setEthPerShare(1.000002206719401318e18);

        uint256 coll3 = 2096314780549457901 +
            collateral.getSharesByPooledEth(borrowerOperations.LIQUIDATOR_REWARD());

        cdpId = borrowerOperations.openCdp(borrowerOperations.MIN_CHANGE(), HINT, HINT, coll2);

        emit log_string("col3");
        emit log_uint(cdpManager.getCdpCollShares(cdpId));

        emit log_uint(cdpManager.getCachedTCR(priceFeedMock.getPrice()));
        emit log_uint(cdpManager.getCachedICR(sortedCdps.getFirst(), priceFeedMock.getPrice()));

        assertTrue(invariant_SL_01(cdpManager, sortedCdps), "SL-01");
    }

    function testSortedCdpsICRgteTCRInvariant() public {
        uint256 coll = borrowerOperations.MIN_NET_STETH_BALANCE() +
            borrowerOperations.LIQUIDATOR_REWARD() +
            16;

        address user = _utils.getNextUserAddress();
        vm.startPrank(user);
        vm.deal(user, type(uint96).max);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: coll * 2}();

        vm.expectRevert(ERR_BORROWER_OPERATIONS_MIN_DEBT);
        borrowerOperations.openCdp(1, HINT, HINT, coll);

        borrowerOperations.openCdp(1000, HINT, HINT, coll);
        borrowerOperations.openCdp(1000, HINT, HINT, coll);
        collateral.setEthPerShare((collateral.getEthPerShare() * 1 ether) / 1.1 ether);

        emit log_uint(cdpManager.getCachedTCR(priceFeedMock.getPrice()));
        emit log_uint(cdpManager.getCachedICR(sortedCdps.getFirst(), priceFeedMock.getPrice()));

        assertTrue(invariant_SL_02(cdpManager, sortedCdps, priceFeedMock), "SL-02");
    }

    function testSortedCdpsPaginationFuzz(uint256 _cdpOpened) public {
        _cdpOpened = bound(_cdpOpened, 3, 20);
        address _usr1 = _utils.getNextUserAddress();
        address _usr2 = _utils.getNextUserAddress();

        vm.deal(_usr1, type(uint96).max);
        vm.deal(_usr2, type(uint96).max);

        vm.startPrank(_usr1);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 10000 ether}();
        vm.stopPrank();

        vm.startPrank(_usr2);
        collateral.approve(address(borrowerOperations), type(uint256).max);
        collateral.deposit{value: 10000 ether}();
        vm.stopPrank();

        {
            uint256 _icr = COLLATERAL_RATIO;
            uint256 collAmount = 30 ether;

            // Open some CDPs one by one for both users
            for (uint256 cdpIx = 0; cdpIx < _cdpOpened; cdpIx++) {
                // open CDP for user1
                uint256 _firstICR = _icr + (cdpIx * 1e16);
                uint256 borrowedAmount1 = _utils.calculateBorrowAmount(
                    collAmount,
                    priceFeedMock.fetchPrice(),
                    _firstICR
                );
                vm.prank(_usr1);
                borrowerOperations.openCdp(borrowedAmount1, HINT, HINT, collAmount);

                // open another higher one for user2
                uint256 _secondICR = _firstICR + 1e16;
                uint256 borrowedAmount2 = _utils.calculateBorrowAmount(
                    collAmount,
                    priceFeedMock.fetchPrice(),
                    _secondICR
                );
                vm.prank(_usr2);
                borrowerOperations.openCdp(borrowedAmount2, HINT, HINT, collAmount);

                // iterate to next round
                _icr = _secondICR;
            }
        }

        // now we use pagination to get all CDPs for user1
        bytes32 _startNodeId = sortedCdps.dummyId();
        uint256 _maxNodes = 2;
        uint256 _cdpIndex = 0;

        // firstly determine the count of CDPs
        for (uint256 cdpIx = 0; cdpIx < _cdpOpened; cdpIx++) {
            (uint256 _cdpCnt, bytes32 _nextStartId) = sortedCdps.getCdpCountOf(
                _usr1,
                _startNodeId,
                _maxNodes
            );
            assertTrue(_cdpCnt == 1, "getCdpCountOf() should return correct count of (user1)!!!");
            if (cdpIx < _cdpOpened - 1) {
                assertTrue(
                    sortedCdps.getOwnerAddress(_nextStartId) == _usr1,
                    "getCdpCountOf() should return correct CDP id (user1) for next pagination!!!"
                );
            } else {
                assertTrue(
                    _nextStartId == sortedCdps.dummyId(),
                    "getCdpCountOf() should correctly mark the end of list for next pagination!!!"
                );
            }

            (bytes32[] memory _allCdps, uint256 _retrieved, bytes32 _nextStartId2) = sortedCdps
                .getAllCdpsOf(_usr1, _startNodeId, _maxNodes);
            assertTrue(
                _retrieved == 1 && _allCdps.length == 1,
                "getAllCdpsOf() should return correct slice of the all CDPs of (user1)!!!"
            );
            assertTrue(
                sortedCdps.getOwnerAddress(_allCdps[0]) == _usr1,
                "getAllCdpsOf() should return all CDPs of (user1) as specified!!!"
            );
            assertTrue(
                _nextStartId2 == _nextStartId,
                "getAllCdpsOf() should return correct CDP id (user2) for next pagination!!!"
            );
            {
                (bytes32 _cdpIdx, bool _indicator) = sortedCdps.cdpOfOwnerByIdx(
                    _usr1,
                    _cdpIndex,
                    _startNodeId,
                    _maxNodes
                );
                assertTrue(_indicator, "cdpOfOwnerByIdx() should return correct CDP of (user1)!!!");
                assertTrue(
                    sortedCdps.getOwnerAddress(_cdpIdx) == _usr1,
                    "cdpOfOwnerByIdx() should return correct CDP id of (user1)!!!"
                );
            }
            // paginate with next user1 CDP
            _startNodeId = _nextStartId;
        }
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
