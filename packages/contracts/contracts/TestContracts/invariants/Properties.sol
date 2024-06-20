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
import {CRLens} from "../CRLens.sol";
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

        return sumStakes == cdpManager.totalStakes();
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
    ) internal returns (bool) {
        bytes32 _first = sortedCdps.getFirst();
        uint256 _price = priceFeedMock.fetchPrice();
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
    ) internal returns (bool) {
        bytes32 currentCdp = sortedCdps.getFirst();

        uint256 _price = priceFeedMock.fetchPrice();
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
    ) internal returns (bool) {
        // TODO how to calculate "the dollar value of eBTC"?
        // TODO how do we take into account underlying/shares into this calculation?
        return
            cdpManager.getCachedTCR(priceFeedMock.fetchPrice()) > 1e18
                ? (collateral.getPooledEthByShares(cdpManager.getSystemCollShares()) *
                    priceFeedMock.fetchPrice()) /
                    1e18 >=
                    eBTCToken.totalSupply()
                : (collateral.getPooledEthByShares(cdpManager.getSystemCollShares()) *
                    priceFeedMock.fetchPrice()) /
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
    ) internal returns (bool) {
        uint256 curentPrice = priceFeedTestnet.fetchPrice();

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
        uint256 curentPrice = priceFeedMock.fetchPrice();
        return crLens.quoteRealTCR() == cdpManager.getSyncedTCR(curentPrice);
    }

    function invariant_GENERAL_13(
        CRLens crLens,
        CdpManager cdpManager,
        PriceFeedTestnet priceFeedMock,
        SortedCdps sortedCdps
    ) internal returns (bool) {
        bytes32 currentCdp = sortedCdps.getFirst();

        uint256 _price = priceFeedMock.fetchPrice();

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
        uint256 price = priceFeedTestnet.fetchPrice();

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

    function invariant_DUMMY_01(PriceFeedTestnet priceFeedTestnet) internal returns (bool) {
        return priceFeedTestnet.fetchPrice() > 0;
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

    // PYS_01: As a user I should earn the same yield on my collateral when held in the protocol, as outside, given PYS of 0
    function invariant_PYS_01(
        CdpManager cdpManager,
        bytes32 yieldTargetCdp,
        address controlActor,
        address yieldTarget
    ) internal view returns (bool) {
        // If not set we aren't testing PYS
        if (yieldControlAddress == address(0) || cdpManager.stakingRewardSplit() != 0) return true;
        if (!vars.inRebase) return true;

        // Get the current shares of this cdp in the protocol
        uint256 _coll = cdpManager.getSyncedCdpCollShares(yieldTargetCdp);

        // If the CDP has 0 shares then it has been liquidated
        if (_coll == 0) return true;
        if (vars.feeRecipientCollSharesAfter < vars.feeRecipientCollSharesBefore) return true;
        // In this case we aren't in a rebase
        if (vars.stakingRewardSplitAfter != vars.stakingRewardSplitBefore) return true;

    
        // In case the Yield Actor closes or redeems, we check their address as well
        // Note: we must also remember the gas stipend gets subtracted from the shares at the start
        uint256 yieldTargetCollateral = collateral.balanceOf(address(actors[yieldTarget])) + collateral.getPooledEthByShares(_coll);

        // Simpler to check that `yield on collateral == yield on control, for each rebase event, @ PYS == 0`
        uint256 yieldGrowthControl = (vars.yieldControlValueAfter - vars.yieldControlValueBefore * 1e18) / vars.yieldControlValueBefore;
        uint256 yieldGrowthActor = (vars.yieldActorValueAfter - vars.yieldActorValueBefore * 1e18) / vars.yieldActorValueBefore;

        // Is approximate eq good here? 1e8 would be dust
        return  _assertApproximateEq(yieldGrowthControl / 1e18, yieldGrowthActor / 1e18, 1e8); 

        // Is approximate eq good here? 1e8 would be dust
        //return  _assertApproximateEq(collateral.balanceOf(controlActor), yieldTargetCollateral, 1e8); 
    }

    // At all times the fees taken from systemCollShares should be added to feeRecipientCollShares
    function invariant_PYS_02(
        CdpManager cdpManager,
        Vars memory vars
    ) internal view returns (bool) {
        // If yieldControlAddress is not set this invariant cannot be tested
        if (yieldControlAddress == address(0)) return true;
        // If our target CDP has no collateral then we cannot test this invariant
        if (cdpManager.getCdpCollShares(yieldTargetCdpId) == 0) return true;

        // In total the yield growth percentage of the control must be equal to protocol growth percentage
        // Has there been yield?
        if (vars.prevStEthFeeIndex < vars.afterStEthFeeIndex) {
            return _assertApproximateEq(vars.yieldProtocolCollSharesBefore - vars.yieldProtocolCollSharesAfter, vars.feeRecipientCollSharesAfter - vars.feeRecipientCollSharesBefore, 1e4);
        }

        // Implies there was no yield
        return true;

    }

    // As a user, the value of my CDP after rebase should be equal to it's value prior to rebase + yield - fee, according to the PYS at the moment of rebase
    function invariant_PYS_03(
        CdpManager cdpManager,
        Vars memory vars
    ) internal view returns (bool) {
        // If yieldControlAddress is not set this invariant cannot be tested
        if (yieldControlAddress == address(0)) return true;
        // If our target CDP has no collateral then we cannot test this invariant
        if (cdpManager.getCdpCollShares(yieldTargetCdpId) == 0) return true;
        // If stakingRewardSplit is 0 then there is no fee split
        if (cdpManager.stakingRewardSplit() == 0) return true;
        // In this case we are not testing the setEthPerShare
        if (vars.prevStEthFeeIndex == vars.afterStEthFeeIndex) return true;

        // In this case we aren't in a rebase
        if (vars.stakingRewardSplitAfter != vars.stakingRewardSplitBefore) return true;
        if (!vars.inRebase) return true;

        // If the shares are the same then no fee split was done
        // @audit Why do we run into this case though? Maybe if the split fee is too low + low rebase then maybe no fee can be taken?
        if (vars.yieldActorSharesAfter == vars.yieldActorSharesBefore) return true;

        if (vars.feeRecipientCollSharesAfter < vars.feeRecipientCollSharesBefore) return true;

        // Has there been yield?
        if (vars.yieldStEthIndexAfter > vars.yieldStEthIndexBefore) {
            // Determine the growth, adjusted to 1e18 precision
            uint256 yieldGrowthPercent = (vars.yieldStEthIndexAfter - vars.yieldStEthIndexBefore) * 1e18 / vars.yieldStEthIndexBefore;

            // Expected fee is (growth % * startingVal) * feeSplit %
            uint256 expectedFee = (vars.yieldActorValueBefore * yieldGrowthPercent / 1e18) * cdpManager.stakingRewardSplit() / cdpManager.MAX_REWARD_SPLIT();
            uint256 feeInShares = collateral.getSharesByPooledEth(expectedFee);

            return _assertApproximateEq(
                collateral.getPooledEthByShares(vars.yieldActorSharesBefore - feeInShares),
                collateral.getPooledEthByShares(vars.yieldActorSharesAfter),
                1e6 //canary value, if we break this by this much we need to investigate
            );
        }

        // Implies there was no yield
        return true;
    }

    // As a protocol, we expect the yield growth from moment to moment to be equal to the PYS, given a positive yield 
    function invariant_PYS_04(CdpManager cdpManager, Vars memory vars) internal view returns (bool) {
        // If yieldControlAddress is not set this invariant cannot be tested
        if (yieldControlAddress == address(0)) return true;
        // In this case we are not testing the setEthPerShare
        if (vars.prevStEthFeeIndex == vars.afterStEthFeeIndex) return true;

        // If there is no PYS there is no yield
        if (cdpManager.stakingRewardSplit() == 0) return true;

        // In this case we aren't in a rebase
        if (vars.stakingRewardSplitAfter != vars.stakingRewardSplitBefore) return true;

        if (vars.feeRecipientCollSharesAfter < vars.feeRecipientCollSharesBefore) return true;

        if (vars.yieldStEthIndexAfter > vars.yieldStEthIndexBefore) {
            uint256 yieldGrowthPercent = (vars.yieldStEthIndexAfter - vars.yieldStEthIndexBefore) * 1e18 / vars.yieldStEthIndexBefore;
            // The protocol's claimable fees should increase by the PYS % on the expected increase of the system collateral shares value
            uint256 feesTakenExpected = (vars.yieldProtocolValueBefore * yieldGrowthPercent / 1e18)
                * cdpManager.stakingRewardSplit() / cdpManager.MAX_REWARD_SPLIT();

            uint256 feesTakenActual = vars.feeRecipientCollSharesAfter - vars.feeRecipientCollSharesBefore;

            require((vars.yieldProtocolCollSharesBefore - vars.yieldProtocolCollSharesAfter) == feesTakenActual, "!fees taken should be synced");

            feesTakenExpected = collateral.getSharesByPooledEth(feesTakenExpected);
            collateral.getSharesByPooledEth(feesTakenActual);

            return _assertApproximateEq(feesTakenExpected, feesTakenActual, 1e6);
        }

        // Implies there was no rebase
        return true;
    }

}
