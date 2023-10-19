// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;
import "forge-std/Test.sol";
import {eBTCBaseInvariants} from "./BaseInvariants.sol";

/*
 * Test suite that tests exactly one thing: opening CDPs
 * It tests different cases and also does random testing against random coll amounts and amount of users
 */
contract CdpOrderingTest is eBTCBaseInvariants {
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
