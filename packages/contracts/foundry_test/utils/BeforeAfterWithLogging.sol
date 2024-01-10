// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.17;

import {BeforeAfter} from "../../contracts/TestContracts/invariants/BeforeAfter.sol";
import {console2 as console} from "forge-std/console2.sol";
import {LogUtils} from "./LogUtils.sol";
import {Strings as StringsUtils} from "./Strings.sol";

contract BeforeAfterWithLogging is BeforeAfter, LogUtils {
    function _printCdpId(string memory label, bytes32 _cdpId) internal {
        (address addressPart, uint256 numberPart) = parseNode(_cdpId);
        console.log(label, addressPart, numberPart);
    }

    function _printCdpSystemState() internal {
        uint256 price = priceFeedMock.fetchPrice();
        console.log("== Core State ==");
        console.log("systemCollShares                :", activePool.getSystemCollShares());
        console.log(
            "systemStEthBalance              :",
            collateral.getPooledEthByShares(activePool.getSystemCollShares())
        );
        console.log("systemDebt                      :", activePool.getSystemDebt());
        console.log("TCR       (cached)              :", cdpManager.getCachedTCR(price));
        console.log("TCR       (synced)              :", cdpManager.getSyncedTCR(price));
        console.log("");
        console.log("stEthLiveIndex                  :", collateral.getPooledEthByShares(1e18));
        console.log("stEthGlobalIndex                :", cdpManager.stEthIndex());
        console.log("");
        console.log("totalStakes                     :", cdpManager.totalStakes());
        console.log("totalStakesSnapshot             :", cdpManager.totalStakesSnapshot());
        console.log("totalCollateralSnapshot         :", cdpManager.totalCollateralSnapshot());
        console.log("");
        console.log("systemStEthFeePerUnitIndex      :", cdpManager.systemStEthFeePerUnitIndex());
        console.log(
            "systemStEthFeePerUnitIndexError :",
            cdpManager.systemStEthFeePerUnitIndexError()
        );
        console.log("");
        console.log("systemDebtRedistributionIndex   :", cdpManager.systemDebtRedistributionIndex());
        console.log(
            "lastEBTCDebtErrorRedistribution :",
            cdpManager.lastEBTCDebtErrorRedistribution()
        );
        console.log("");
        console.log("price                           :", price);
        console.log("");
    }

    function _printAllCdps() internal {
        uint256 price = priceFeedMock.fetchPrice();
        uint256 numCdps = sortedCdps.getSize();
        bytes32 node = sortedCdps.getLast();
        bytes32 firstNode = sortedCdps.getFirst();

        while (node != bytes32(0)) {
            (uint256 debtSynced, uint256 collSharesSynced) = cdpManager.getSyncedDebtAndCollShares(
                node
            );

            _printCdpId("=== ", node);
            console.log("owner                       :", sortedCdps.getOwnerAddress(node));
            console.log("debt       (realized)       :", cdpManager.getCdpDebt(node));
            console.log("debt       (virtual)        :", debtSynced);
            console.log("collShares (realized)       :", cdpManager.getCdpCollShares(node));
            console.log("collShares (virtual)        :", collSharesSynced);
            console.log("");
            console.log("ICR        (realized)       :", cdpManager.getCachedICR(node, price));
            console.log("ICR        (virtual)        :", cdpManager.getSyncedICR(node, price));
            console.log("");
            console.log("stake                       :", cdpManager.getCdpStake(node));
            console.log(
                "cdpDebtRedistributionIndex  :",
                cdpManager.cdpDebtRedistributionIndex(node)
            );
            console.log("cdpStEthFeePerUnitIndex     :", cdpManager.cdpStEthFeePerUnitIndex(node));
            console.log(
                "hasPendingRedistributedDebt :",
                cdpManager.hasPendingRedistributedDebt(node)
            );
            console.log(
                "getPendingRedistributedDebt :",
                cdpManager.getPendingRedistributedDebt(node)
            );
            console.log("");
            node = sortedCdps.getPrev(node);
        }
    }
}
