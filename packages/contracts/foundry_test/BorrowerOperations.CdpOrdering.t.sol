// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;
import "forge-std/Test.sol";
import {eBTCBaseInvariants} from "./BaseInvariants.sol";
import {Pretty, Strings} from "../contracts/TestContracts/Pretty.sol";

/*
 * Test suite that tests exactly one thing: opening CDPs
 * It tests different cases and also does random testing against random coll amounts and amount of users
 */
contract CdpOrderingTest is eBTCBaseInvariants {
    using Strings for string;
    using Pretty for uint256;
    using Pretty for int256;
    using Pretty for bool;

    function setUp() public override {
        super.setUp();

        connectCoreContracts();
        connectLQTYContractsToCore();
    }

    function test_OpenCdpOrdering() public {
        // start with index 1
        collateral.setEthPerShare(1e18);

        address user = _utils.getNextUserAddress();
        uint256 coll = 100 ether;
        uint256 debt = 1 ether;

        bytes32 cdp1 = _openTestCDP(user, coll, debt);

        uint256 price = priceFeedMock.fetchPrice();
        console.log("cdp1 before: ", cdpManager.getCachedICR(cdp1, price));

        /**
            move to index 1.2
            CDP#1 should now implicitly have coll 102, debt 1
            CDP#2 will have coll 101, debt 1

            with the correct index, the ordering will be (CDP#2 -> CDP#1)
            if not updated correctly, the ordering will be (CDP#1 -> CDP#2)
         */

        collateral.setEthPerShare(1e18 + 2e17);

        user = _utils.getNextUserAddress();
        coll = 101 ether;

        bytes32 cdp2 = _openTestCDP(user, coll, debt);

        price = priceFeedMock.fetchPrice();
        console.log("cdp1 after: ", cdpManager.getCachedICR(cdp1, price));
        console.log("cdp2 after: ", cdpManager.getCachedICR(cdp2, price));

        _ensureSystemInvariants();
    }

    /**
        Ensure CDP ordering on operations in the face of rebasing stETH index
     */
    function test_CdpOrdering() public {
        uint256 rebaseCount = 100;
        uint256 maxIndexChangeUp = 1e16;
        uint256 maxIndexChangeDown = 1e15;

        uint256 indexChangeUpProbabilityBps = 9500;

        int indexChange = _getIndexChangeWithinRange(
            maxIndexChangeUp,
            maxIndexChangeDown,
            indexChangeUpProbabilityBps
        );

        for (uint256 i = 0; i < rebaseCount; i++) {
            (uint256 oldIndex, uint256 newIndex) = _applyIndexChange(indexChange);
            if (newIndex >= oldIndex) {
                console.log(newIndex);
            } else {
                console.log(newIndex, "(slash)");
            }
            // get a random user
            address user = _utils.getNextUserAddress();
            vm.startPrank(user);

            // Randomize collateral amount used
            uint256 collAmount = _utils.generateRandomNumber(2 ether, 10000 ether, user);
            // deal ETH and deposit for collateral
            vm.deal(user, collAmount * 1000);
            collateral.approve(address(borrowerOperations), collAmount);
            collateral.deposit{value: collAmount * 1000}();

            uint256 borrowedAmount = _utils.calculateBorrowAmount(
                collAmount,
                priceFeedMock.fetchPrice(),
                COLLATERAL_RATIO
            );

            borrowerOperations.openCdp(borrowedAmount, "hint", "hint", collAmount);

            console.log("openCdp:", collAmount, ": ", borrowedAmount);

            vm.stopPrank();
            _ensureSystemInvariants();
        }
    }

    function test_H1() public {
        vm.pauseGasMetering();

        address firstUser;
        address lastUser;
        bytes32 firstCdpId;
        bytes32 lastCdpId;

        uint loop = 100;

        /// let's open 100 cdps and save the 1st and last index
        for (uint256 i = 0; i < loop; i++) {
            (uint256 oldIndex, uint256 newIndex) = _applyIndexChange(2000000000000000); // 0,2% stETH increase
            // get a random user
            address user = _utils.getNextUserAddress();
            vm.startPrank(user);

            // Randomize collateral amount used
            vm.deal(user, 10 ether * 1000);
            collateral.approve(address(borrowerOperations), 10 ether * 1000);
            collateral.deposit{value: 10 ether * 1000}();

            uint shareAmount = 10 ether;
            uint256 collAmount = collateral.getPooledEthByShares(shareAmount);

            uint256 borrowedAmount;
            if (i == loop - 1)
                // here we compute borrowedAmount to make lastCdpId NCIR very close to firstCdpId NICR
                borrowedAmount =
                    (1e20 * (shareAmount - collateral.getSharesByPooledEth(2e17))) /
                    cdpManager.getSyncedNominalICR(firstCdpId); // borrowedAmount = 0.65764 ether;
            else borrowedAmount = 0.5 ether;

            bytes32 id = borrowerOperations.openCdp(borrowedAmount, "hint", "hint", collAmount);

            if (i == 0) {
                firstUser = user;
                firstCdpId = id;
            }
            if (i == loop - 1) {
                lastUser = user;
                lastCdpId = id;
            }

            vm.stopPrank();
        }

        _printAllCdps();

        console.log("=== Before opening final cdp ===");
        logNICR(firstCdpId, lastCdpId);
        // NICR 1st trove should be < NICR last trove
        assertLe(
            cdpManager.getSyncedNominalICR(firstCdpId),
            cdpManager.getSyncedNominalICR(lastCdpId)
        );

        /// Let's increase the stETH by 40% and open a last cdp
        (uint256 oldIndex, uint256 newIndex) = _applyIndexChange(400000000000000000); // 40% stETH increase
        // get a random user
        address user = _utils.getNextUserAddress();
        vm.startPrank(user);

        uint256 collAmount = 10 ether;
        // deal ETH and deposit for collateral
        vm.deal(user, collAmount * 1000);
        collateral.approve(address(borrowerOperations), collAmount);
        collateral.deposit{value: collAmount * 1000}();

        uint borrowedAmount = 0.5 ether;
        borrowerOperations.openCdp(borrowedAmount, "hint", "hint", collAmount);
        vm.stopPrank();

        _printAllCdps();

        console.log("=== After opening final cdp ===");
        logNICR(firstCdpId, lastCdpId);
        // NICR 1st trove should be < NICR last cdp but it's not the case
        assertLe(
            cdpManager.getSyncedNominalICR(firstCdpId),
            cdpManager.getSyncedNominalICR(lastCdpId)
        );
    }

    function logNICR(bytes32 firstCdpId, bytes32 lastCdpId) public {
        console.log("---------------------------------- 1st cdp", bytes32ToString(firstCdpId));
        console.log("getCdpStake         : ", cdpManager.getCdpStake(firstCdpId).pretty());
        console.log("getCdpCollShares    : ", cdpManager.getCdpCollShares(firstCdpId).pretty());
        console.log("getSyncedNominalICR : ", cdpManager.getSyncedNominalICR(firstCdpId).pretty());
        console.log("---------------------------------- last cdp", bytes32ToString(lastCdpId));
        console.log("getCdpStake         : ", cdpManager.getCdpStake(lastCdpId).pretty());
        console.log("getCdpCollShares    : ", cdpManager.getCdpCollShares(lastCdpId).pretty());
        console.log("getSyncedNominalICR : ", cdpManager.getSyncedNominalICR(lastCdpId).pretty());
        console.log("---");
        console.logInt(
            int(
                int(cdpManager.getSyncedNominalICR(firstCdpId)) -
                    int(cdpManager.getSyncedNominalICR(lastCdpId))
            )
        );
        console.log("----------------------------------");
    }

    function _getIndexChangeWithinRange(
        uint256 maxIndexChangeUp,
        uint256 maxIndexChangeDown,
        uint256 indexChangeUpProbabilityBps
    ) internal view returns (int) {
        uint256 random = _utils.generateRandomNumber(0, 10000, address(1));
        if (random < indexChangeUpProbabilityBps) {
            return int(_utils.generateRandomNumber(0, maxIndexChangeUp, address(0)));
        } else {
            return -int(_utils.generateRandomNumber(0, maxIndexChangeDown, address(0)));
        }
    }

    function _applyIndexChange(int indexChange) internal returns (uint256, uint256) {
        uint256 currentIndex = collateral.getPooledEthByShares(1e18);
        uint256 proposedIndex;

        if (indexChange >= 0) {
            proposedIndex = currentIndex + uint256(indexChange);
        } else if (indexChange < 0) {
            // if we will be above zero
            if (currentIndex >= uint256(indexChange)) {
                proposedIndex = currentIndex - uint256(indexChange);
            }
            // handle zero / underflow
            else {
                proposedIndex = 0;
            }
        }

        collateral.setEthPerShare(proposedIndex);
        return (currentIndex, collateral.getPooledEthByShares(1e18));
    }
}
