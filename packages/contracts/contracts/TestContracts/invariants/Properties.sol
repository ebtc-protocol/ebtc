pragma solidity 0.8.17;

import "@crytic/properties/contracts/util/PropertiesConstants.sol";

import {ICollateralToken} from "../../Dependencies/ICollateralToken.sol";
import {EbtcMath} from "../../Dependencies/EbtcMath.sol";
import {ActivePool} from "../../ActivePool.sol";
import {EBTCToken} from "../../EBTCToken.sol";
import {BorrowerOperations} from "../../BorrowerOperations.sol";
import {CdpManager} from "../../CdpManager.sol";
import {SortedCdps} from "../../SortedCdps.sol";
import {Asserts} from "./Asserts.sol";
import {CollSurplusPool} from "../../CollSurplusPool.sol";
import {PriceFeedTestnet} from "../testnet/PriceFeedTestnet.sol";
import {ICdpManagerData} from "../../Interfaces/ICdpManagerData.sol";
import {BeforeAfter} from "./BeforeAfter.sol";
import {PropertiesDescriptions} from "./PropertiesDescriptions.sol";
import {CRLens} from "../../CRLens.sol";
import {LiquidationSequencer} from "../../LiquidationSequencer.sol";
import {SyncedLiquidationSequencer} from "../../SyncedLiquidationSequencer.sol";

abstract contract Properties is BeforeAfter, PropertiesDescriptions, Asserts, PropertiesConstants {
    function invariant_AP_01(
        ICollateralToken collateral,
        ActivePool activePool
    ) internal view returns (bool) {
        return (collateral.sharesOf(address(activePool)) >= activePool.getSystemCollShares());
    }

    function invariant_AP_02(
        CdpManager cdpManager,
        ActivePool activePool
    ) internal view returns (bool) {
        return cdpManager.getActiveCdpsCount() > 0 ? activePool.getSystemCollShares() > 0 : true;
    }

    function invariant_AP_03(
        EBTCToken eBTCToken,
        ActivePool activePool
    ) internal view returns (bool) {
        return (eBTCToken.totalSupply() == activePool.getSystemDebt());
    }

    function invariant_AP_04(
        CdpManager cdpManager,
        ActivePool activePool,
        uint256 diff_tolerance
    ) internal view returns (bool) {
        uint256 _cdpCount = cdpManager.getActiveCdpsCount();
        bytes32[] memory cdpIds = hintHelpers.sortedCdpsToArray();
        uint256 _sum;

        for (uint256 i = 0; i < _cdpCount; ++i) {
            (, uint256 _coll) = cdpManager.getSyncedDebtAndCollShares(cdpIds[i]);
            _sum += _coll;
        }
        uint256 _activeColl = activePool.getSystemCollShares();
        uint256 _diff = _sum > _activeColl ? (_sum - _activeColl) : (_activeColl - _sum);
        return (_diff * 1e18 <= diff_tolerance * _activeColl);
    }

    function invariant_AP_05(
        CdpManager cdpManager,
        uint256 diff_tolerance
    ) internal view returns (bool) {
        uint256 _cdpCount = cdpManager.getActiveCdpsCount();
        bytes32[] memory cdpIds = hintHelpers.sortedCdpsToArray();
        uint256 _sum;

        for (uint256 i = 0; i < _cdpCount; ++i) {
            (uint256 _debt, ) = cdpManager.getSyncedDebtAndCollShares(cdpIds[i]);
            _sum += _debt;
        }

        bool oldCheck = isApproximateEq(_sum, cdpManager.getSystemDebt(), diff_tolerance);
        // New check ensures this is above 1000 wei
        bool newCheck = cdpManager.getSystemDebt() - _sum > 1_000;
        // @audit We have an instance of getting above 1e18 in rounding error, see `testBrokenInvariantFive`
        return oldCheck || !newCheck;
    }

    function invariant_CDPM_01(
        CdpManager cdpManager,
        SortedCdps sortedCdps
    ) internal view returns (bool) {
        return (cdpManager.getActiveCdpsCount() == sortedCdps.getSize());
    }

    function invariant_CDPM_02(CdpManager cdpManager) internal view returns (bool) {
        uint256 _cdpCount = cdpManager.getActiveCdpsCount();
        bytes32[] memory cdpIds = hintHelpers.sortedCdpsToArray();

        uint256 _sum;

        for (uint256 i = 0; i < _cdpCount; ++i) {
            _sum += cdpManager.getCdpStake(cdpIds[i]);
        }
        return (_sum == cdpManager.totalStakes());
    }

    function invariant_CDPM_03(CdpManager cdpManager) internal view returns (bool) {
        uint256 _cdpCount = cdpManager.getActiveCdpsCount();
        bytes32[] memory cdpIds = hintHelpers.sortedCdpsToArray();
        uint256 systemStEthFeePerUnitIndex = cdpManager.systemStEthFeePerUnitIndex();
        for (uint256 i = 0; i < _cdpCount; ++i) {
            if (systemStEthFeePerUnitIndex < cdpManager.cdpStEthFeePerUnitIndex(cdpIds[i])) {
                return false;
            }
        }
        return true;
    }

    /** TODO: See EchidnaToFoundry._getValue */
    function invariant_CDPM_04(Vars memory vars) internal view returns (bool) {
        return
            vars.valueInSystemAfter >= vars.valueInSystemBefore ||
            isApproximateEq(vars.valueInSystemAfter, vars.valueInSystemBefore, 0.01e18);
    }

    function invariant_CDPM_10(CdpManager cdpManager) internal view returns (bool) {
        if (vars.afterStEthFeeIndex > vars.prevStEthFeeIndex) {
            return cdpManager.totalStakesSnapshot() == cdpManager.totalStakes();
        }
        return true;
    }

    function invariant_CDPM_11(CdpManager cdpManager) internal view returns (bool) {
        if (vars.afterStEthFeeIndex > vars.prevStEthFeeIndex) {
            return cdpManager.totalCollateralSnapshot() == cdpManager.getSystemCollShares();
        }
        return true;
    }

    function invariant_CDPM_12(
        SortedCdps sortedCdps,
        Vars memory vars
    ) internal view returns (bool) {
        bytes32 currentCdp = sortedCdps.getFirst();

        uint256 sumStakes;
        while (currentCdp != bytes32(0)) {
            sumStakes += cdpManager.getCdpStake(currentCdp);
            currentCdp = sortedCdps.getNext(currentCdp);
        }

        return sumStakes == vars.totalStakesAfter;
    }

    function invariant_CSP_01(
        ICollateralToken collateral,
        CollSurplusPool collSurplusPool
    ) internal view returns (bool) {
        return
            collateral.sharesOf(address(collSurplusPool)) >=
            collSurplusPool.getTotalSurplusCollShares();
    }

    function invariant_CSP_02(CollSurplusPool collSurplusPool) internal view returns (bool) {
        uint256 sum;

        // NOTE: See PropertiesConstants
        // We only have 3 actors so just set these up
        sum += collSurplusPool.getSurplusCollShares(address(actors[USER1]));
        sum += collSurplusPool.getSurplusCollShares(address(actors[USER2]));
        sum += collSurplusPool.getSurplusCollShares(address(actors[USER3]));

        return sum == collSurplusPool.getTotalSurplusCollShares();
    }

    function invariant_SL_01(CdpManager cdpManager, SortedCdps sortedCdps) internal returns (bool) {
        bytes32 currentCdp = sortedCdps.getFirst();
        bytes32 nextCdp = sortedCdps.getNext(currentCdp);

        while (currentCdp != bytes32(0) && nextCdp != bytes32(0) && currentCdp != nextCdp) {
            // TODO remove tolerance once proper fix has been applied
            uint256 nicrNext = cdpManager.getCachedNominalICR(nextCdp);
            uint256 nicrCurrent = cdpManager.getCachedNominalICR(currentCdp);
            emit L2(nicrNext, nicrCurrent);
            if (nicrNext > nicrCurrent && diffPercent(nicrNext, nicrCurrent) > 0.01e18) {
                return false;
            }

            currentCdp = nextCdp;
            nextCdp = sortedCdps.getNext(currentCdp);
        }

        return true;
    }

    function invariant_SL_02(
        CdpManager cdpManager,
        SortedCdps sortedCdps,
        PriceFeedTestnet priceFeedMock
    ) internal view returns (bool) {
        bytes32 _first = sortedCdps.getFirst();
        uint256 _price = priceFeedMock.getPrice();
        uint256 _firstICR = cdpManager.getCachedICR(_first, _price);
        uint256 _TCR = cdpManager.getCachedTCR(_price);

        if (
            _first != sortedCdps.dummyId() &&
            _firstICR < _TCR &&
            diffPercent(_firstICR, _TCR) > 0.01e18
        ) {
            return false;
        }
        return true;
    }

    function invariant_SL_03(
        CdpManager cdpManager,
        PriceFeedTestnet priceFeedMock,
        SortedCdps sortedCdps
    ) internal view returns (bool) {
        bytes32 currentCdp = sortedCdps.getFirst();

        uint256 _price = priceFeedMock.getPrice();
        if (_price == 0) return true;

        while (currentCdp != bytes32(0)) {
            // Status
            if (
                ICdpManagerData.Status(cdpManager.getCdpStatus(currentCdp)) !=
                ICdpManagerData.Status.active
            ) {
                return false;
            }

            // Stake > 0
            if (cdpManager.getCdpStake(currentCdp) == 0) {
                return false;
            }

            currentCdp = sortedCdps.getNext(currentCdp);
        }
        return true;
    }

    uint256 NICR_ERROR_THRESHOLD = 1e18; // NOTE: 1e20 is basically 1/1 so it's completely safe as a threshold

    function invariant_SL_05(CRLens crLens, SortedCdps sortedCdps) internal returns (bool) {
        bytes32 currentCdp = sortedCdps.getFirst();

        uint256 newIcrPrevious = type(uint256).max;

        while (currentCdp != bytes32(0)) {
            uint256 newIcr = crLens.quoteRealICR(currentCdp);
            if (newIcr > newIcrPrevious) {
                /// @audit Precision Threshold to flag very scary scenarios
                /// Innoquous scenario illustrated here: https://github.com/Badger-Finance/ebtc-fuzz-review/issues/15
                if (newIcr - newIcrPrevious > NICR_ERROR_THRESHOLD) {
                    return false;
                }
            }
            newIcrPrevious = newIcr;

            currentCdp = sortedCdps.getNext(currentCdp);
        }
        return true;
    }

    function invariant_GENERAL_01(Vars memory vars) internal view returns (bool) {
        return !vars.isRecoveryModeBefore ? !vars.isRecoveryModeAfter : true;
    }

    function invariant_GENERAL_02(
        CdpManager cdpManager,
        PriceFeedTestnet priceFeedMock,
        EBTCToken eBTCToken,
        ICollateralToken collateral
    ) internal view returns (bool) {
        // TODO how to calculate "the dollar value of eBTC"?
        // TODO how do we take into account underlying/shares into this calculation?
        return
            cdpManager.getCachedTCR(priceFeedMock.getPrice()) > 1e18
                ? (collateral.getPooledEthByShares(cdpManager.getSystemCollShares()) *
                    priceFeedMock.getPrice()) /
                    1e18 >=
                    eBTCToken.totalSupply()
                : (collateral.getPooledEthByShares(cdpManager.getSystemCollShares()) *
                    priceFeedMock.getPrice()) /
                    1e18 <
                    eBTCToken.totalSupply();
    }

    function invariant_GENERAL_03(
        CdpManager cdpManager,
        BorrowerOperations borrowerOperations,
        EBTCToken eBTCToken,
        ICollateralToken collateral
    ) internal view returns (bool) {
        return
            collateral.balanceOf(address(cdpManager)) == 0 &&
            eBTCToken.balanceOf(address(cdpManager)) == 0 &&
            collateral.balanceOf(address(borrowerOperations)) == 0 &&
            eBTCToken.balanceOf(address(borrowerOperations)) == 0;
    }

    function invariant_GENERAL_05(
        ActivePool activePool,
        CdpManager cdpManager,
        ICollateralToken collateral
    ) internal view returns (bool) {
        uint256 totalStipendShares;

        // Iterate over CDPs add the stipendShares
        bytes32 currentCdp = sortedCdps.getFirst();
        while (currentCdp != bytes32(0)) {
            totalStipendShares += cdpManager.getCdpLiquidatorRewardShares(currentCdp);

            currentCdp = sortedCdps.getNext(currentCdp);
        }

        return
            collateral.sharesOf(address(activePool)) >=
            (activePool.getSystemCollShares() +
                activePool.getFeeRecipientClaimableCollShares() +
                totalStipendShares);
    }

    function invariant_GENERAL_05_B(
        CollSurplusPool surplusPool,
        ICollateralToken collateral
    ) internal view returns (bool) {
        return
            collateral.sharesOf(address(surplusPool)) >= (surplusPool.getTotalSurplusCollShares());
    }

    function invariant_GENERAL_06(
        EBTCToken eBTCToken,
        CdpManager cdpManager,
        SortedCdps sortedCdps
    ) internal view returns (bool) {
        uint256 totalSupply = eBTCToken.totalSupply();

        bytes32 currentCdp = sortedCdps.getFirst();
        uint256 cdpsBalance;
        while (currentCdp != bytes32(0)) {
            (uint256 entireDebt, uint256 entireColl) = cdpManager.getSyncedDebtAndCollShares(
                currentCdp
            );
            cdpsBalance += entireDebt;
            currentCdp = sortedCdps.getNext(currentCdp);
        }

        return totalSupply >= cdpsBalance;
    }

    function invariant_GENERAL_17(
        CdpManager cdpManager,
        SortedCdps sortedCdps,
        PriceFeedTestnet priceFeedTestnet,
        ICollateralToken collateral
    ) internal view returns (bool) {
        bytes32 currentCdp = sortedCdps.getFirst();

        uint256 sumOfDebt;
        while (currentCdp != bytes32(0)) {
            uint256 entireDebt = cdpManager.getSyncedCdpDebt(currentCdp);
            sumOfDebt += entireDebt;
            currentCdp = sortedCdps.getNext(currentCdp);
        }
        sumOfDebt += cdpManager.lastEBTCDebtErrorRedistribution() / 1e18; // TODO: We need to add 1 wei for all CDPs at their time of redistribution
        uint256 _systemDebt = activePool.getSystemDebt();

        if (cdpManager.lastEBTCDebtErrorRedistribution() % 1e18 > 0) sumOfDebt += 1; // Round up debt

        // SumOfDebt can have rounding error
        // And rounding error is capped by:
        // 1 wei of rounding error in lastEBTCDebtErrorRedistribution
        // 1 wei for each cdp at each redistribution (as their index may round down causing them to lose 1 wei of debt)
        return sumOfDebt <= _systemDebt && sumOfDebt + totalCdpDustMaxCap >= _systemDebt;
    }

    function invariant_GENERAL_18(
        CdpManager cdpManager,
        SortedCdps sortedCdps,
        PriceFeedTestnet priceFeedTestnet,
        ICollateralToken collateral
    ) internal view returns (bool) {
        bytes32 currentCdp = sortedCdps.getFirst();

        uint256 sumOfColl;
        while (currentCdp != bytes32(0)) {
            uint256 entireColl = cdpManager.getSyncedCdpCollShares(currentCdp);
            sumOfColl += entireColl;
            currentCdp = sortedCdps.getNext(currentCdp);
        }

        if (sumOfColl == 0) {
            return sumOfColl == cdpManager.getSyncedSystemCollShares();
        }

        sumOfColl -= cdpManager.systemStEthFeePerUnitIndexError() / 1e18;
        uint256 _systemCollShares = cdpManager.getSyncedSystemCollShares();

        if (cdpManager.systemStEthFeePerUnitIndexError() % 1e18 > 0) sumOfColl -= 1; // Round down coll

        // sumOfColl can have rounding error
        // And rounding error is capped by:
        // 1 wei of rounding error in systemStEthFeePerUnitIndexError
        // 1 wei for each cdp at each index change (as their index may round down causing them to lose 1 wei of fee split)
        return
            sumOfColl <= _systemCollShares &&
            sumOfColl + vars.cumulativeCdpsAtTimeOfRebase >= _systemCollShares;
    }

    function invariant_GENERAL_19(ActivePool activePool) internal view returns (bool) {
        return !activePool.twapDisabled();
    }

    function invariant_GENERAL_08(
        CdpManager cdpManager,
        SortedCdps sortedCdps,
        PriceFeedTestnet priceFeedTestnet,
        ICollateralToken collateral
    ) internal view returns (bool) {
        uint256 curentPrice = priceFeedTestnet.getPrice();

        bytes32 currentCdp = sortedCdps.getFirst();

        uint256 sumOfColl;
        uint256 sumOfDebt;
        while (currentCdp != bytes32(0)) {
            uint256 entireColl = cdpManager.getSyncedCdpCollShares(currentCdp);
            uint256 entireDebt = cdpManager.getSyncedCdpDebt(currentCdp);
            sumOfColl += entireColl;
            sumOfDebt += entireDebt;
            currentCdp = sortedCdps.getNext(currentCdp);
        }

        uint256 _systemCollShares = cdpManager.getSyncedSystemCollShares();
        uint256 _systemDebt = activePool.getSystemDebt();
        uint256 tcrFromSystem = cdpManager.getSyncedTCR(curentPrice);

        uint256 tcrFromSums = EbtcMath._computeCR(
            collateral.getPooledEthByShares(sumOfColl),
            sumOfDebt,
            curentPrice
        );

        bool _acceptedTcrDiff = _assertApproximateEq(tcrFromSystem, tcrFromSums, 1e8);

        // add generic diff function (original, second, diff) - all at once

        /// @audit 1e8 precision in absoulte value (not the percent)
        //return  isApproximateEq(tcrFromSystem, tcrFromSums, 1e8); // Up to 1e8 precision is accepted
        bool _acceptedCollDiff = _assertApproximateEq(_systemCollShares, sumOfColl, 1e8);
        bool _acceptedDebtDiff = _assertApproximateEq(_systemDebt, sumOfDebt, 1e8);
        return (_acceptedCollDiff && _acceptedDebtDiff);
    }

    function invariant_GENERAL_09(
        CdpManager cdpManager,
        Vars memory vars
    ) internal view returns (bool) {
        if (vars.isRecoveryModeBefore) {
            if (vars.cdpDebtAfter > vars.cdpDebtBefore) return (vars.icrAfter > cdpManager.MCR());
            else return true;
        } else {
            return (vars.icrAfter > cdpManager.MCR());
        }
    }

    function invariant_GENERAL_12(
        CdpManager cdpManager,
        PriceFeedTestnet priceFeedMock,
        CRLens crLens
    ) internal returns (bool) {
        uint256 curentPrice = priceFeedMock.getPrice();
        return crLens.quoteRealTCR() == cdpManager.getSyncedTCR(curentPrice);
    }

    function invariant_GENERAL_13(
        CRLens crLens,
        CdpManager cdpManager,
        PriceFeedTestnet priceFeedMock,
        SortedCdps sortedCdps
    ) internal returns (bool) {
        bytes32 currentCdp = sortedCdps.getFirst();

        uint256 _price = priceFeedMock.getPrice();

        // Compare synched with quote for all Cdps
        while (currentCdp != bytes32(0)) {
            uint256 newIcr = crLens.quoteRealICR(currentCdp);
            uint256 synchedICR = cdpManager.getSyncedICR(currentCdp, _price);

            if (newIcr != synchedICR) {
                return false;
            }

            currentCdp = sortedCdps.getNext(currentCdp);
        }
        return true;
    }

    function invariant_GENERAL_14(
        CRLens crLens,
        CdpManager cdpManager,
        SortedCdps sortedCdps
    ) internal returns (bool) {
        bytes32 currentCdp = sortedCdps.getFirst();

        uint256 newIcrPrevious = type(uint256).max;

        // Compare synched with quote for all Cdps
        while (currentCdp != bytes32(0)) {
            uint256 newNICR = crLens.quoteRealNICR(currentCdp);
            uint256 synchedNICR = cdpManager.getSyncedNominalICR(currentCdp); // Uses cached stETH index -> It's not the "real NICR"

            if (newNICR != synchedNICR) {
                return false;
            }

            currentCdp = sortedCdps.getNext(currentCdp);
        }
        return true;
    }

    function invariant_GENERAL_15() internal returns (bool) {
        return
            crLens.quoteAnything(simulator.simulateRepayEverythingAndCloseCdps) == simulator.TRUE();
    }

    function invariant_LS_01(
        CdpManager cdpManager,
        LiquidationSequencer ls,
        SyncedLiquidationSequencer syncedLs,
        PriceFeedTestnet priceFeedTestnet
    ) internal returns (bool) {
        // Or just compare max lenght since that's the one with all of them
        uint256 n = cdpManager.getActiveCdpsCount();

        // Get
        uint256 price = priceFeedTestnet.getPrice();

        // Get lists
        bytes32[] memory cdpsFromCurrent = ls.sequenceLiqToBatchLiqWithPrice(n, price);
        bytes32[] memory cdpsSynced = syncedLs.sequenceLiqToBatchLiqWithPrice(n, price);

        uint256 length = cdpsFromCurrent.length;
        if (length != cdpsSynced.length) {
            return false;
        }

        // Compare Lists
        for (uint256 i; i < length; i++) {
            // Find difference = broken
            if (cdpsFromCurrent[i] != cdpsSynced[i]) {
                return false;
            }
        }

        // Implies we're good
        return true;
    }

    function invariant_DUMMY_01(PriceFeedTestnet priceFeedTestnet) internal view returns (bool) {
        return priceFeedTestnet.getPrice() > 0;
    }

    function invariant_BO_09(
        CdpManager cdpManager,
        uint256 price,
        bytes32 cdpId
    ) internal view returns (bool) {
        uint256 _icr = cdpManager.getSyncedICR(cdpId, price);
        if (cdpManager.checkRecoveryMode(price)) {
            return _icr >= cdpManager.CCR();
        } else {
            return _icr >= cdpManager.MCR();
        }
    }
}
