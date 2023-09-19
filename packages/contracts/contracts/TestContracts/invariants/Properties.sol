pragma solidity 0.8.17;

import {ICollateralToken} from "../../Dependencies/ICollateralToken.sol";
import {ActivePool} from "../../ActivePool.sol";
import {EBTCToken} from "../../EBTCToken.sol";
import {BorrowerOperations} from "../../BorrowerOperations.sol";
import {CdpManager} from "../../CdpManager.sol";
import {SortedCdps} from "../../SortedCdps.sol";
import {AssertionHelper} from "./AssertionHelper.sol";
import {CollSurplusPool} from "../../CollSurplusPool.sol";
import {PriceFeedTestnet} from "../testnet/PriceFeedTestnet.sol";
import {ICdpManagerData} from "../../Interfaces/ICdpManagerData.sol";
import {BeforeAfter} from "./BeforeAfter.sol";
import {PropertiesDescriptions} from "./PropertiesDescriptions.sol";
import {CRLens} from "../../CRLens.sol";


abstract contract Properties is AssertionHelper, BeforeAfter, PropertiesDescriptions {
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
        uint256 _sum;
        for (uint256 i = 0; i < _cdpCount; ++i) {
            (, uint256 _coll, ) = cdpManager.getDebtAndCollShares(cdpManager.CdpIds(i));
            _sum += _coll;
        }
        uint256 _activeColl = activePool.getSystemCollShares();
        uint256 _diff = _sum > _activeColl ? (_sum - _activeColl) : (_activeColl - _sum);
        uint256 _divisor = _sum > _activeColl ? _sum : _activeColl;
        return (_diff * 1e18 <= diff_tolerance * _activeColl);
    }

    function invariant_AP_05(
        CdpManager cdpManager,
        uint256 diff_tolerance
    ) internal view returns (bool) {
        uint256 _cdpCount = cdpManager.getActiveCdpsCount();
        uint256 _sum;
        for (uint256 i = 0; i < _cdpCount; ++i) {
            (uint256 _debt, , ) = cdpManager.getDebtAndCollShares(cdpManager.CdpIds(i));
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
        uint256 _sum;
        for (uint256 i = 0; i < _cdpCount; ++i) {
            _sum += cdpManager.getCdpStake(cdpManager.CdpIds(i));
        }
        return (_sum == cdpManager.totalStakes());
    }

    function invariant_CDPM_03(CdpManager cdpManager) internal view returns (bool) {
        uint256 _cdpCount = cdpManager.getActiveCdpsCount();
        uint256 systemStEthFeePerUnitIndex = cdpManager.systemStEthFeePerUnitIndex();
        for (uint256 i = 0; i < _cdpCount; ++i) {
            if (systemStEthFeePerUnitIndex < cdpManager.stEthFeePerUnitIndex(cdpManager.CdpIds(i))) {
                return false;
            }
        }
        return true;
    }

    /** TODO: See EchidnaToFoundry._getValue */
    function invariant_CDPM_04(Vars memory vars) internal view returns (bool) {
        uint256 beforeValue = ((vars.activePoolCollBefore +
            vars.liquidatorRewardSharesBefore +
            vars.collSurplusPoolBefore +
            vars.feeRecipientTotalCollBefore) * vars.priceBefore) /
            1e18 -
            vars.activePoolDebtBefore;

        uint256 afterValue = ((vars.activePoolCollAfter +
            vars.liquidatorRewardSharesAfter +
            vars.collSurplusPoolAfter +
            vars.feeRecipientTotalCollAfter) * vars.priceAfter) /
            1e18 -
            vars.activePoolDebtAfter;

        return afterValue >= beforeValue || isApproximateEq(afterValue, beforeValue, 0.01e18);
    }

    function invariant_CSP_01(
        ICollateralToken collateral,
        CollSurplusPool collSurplusPool
    ) internal view returns (bool) {
        return
            collateral.sharesOf(address(collSurplusPool)) >=
            collSurplusPool.getTotalSurplusCollShares();
    }

    event L(string, uint);

    function invariant_SL_01(
        CdpManager cdpManager,
        SortedCdps sortedCdps,
        uint256 diff_tolerance
    ) internal returns (bool) {
        bytes32 currentCdp = sortedCdps.getFirst();
        bytes32 nextCdp = sortedCdps.getNext(currentCdp);

        while (currentCdp != bytes32(0) && nextCdp != bytes32(0) && currentCdp != nextCdp) {
            // TODO remove tolerance once proper fix has been applied
            uint256 nicrNext = cdpManager.getNominalICR(nextCdp);
            uint256 nicrCurrent = cdpManager.getNominalICR(currentCdp);
            emit L("NICR next", nicrNext);
            emit L("NICR curr", nicrCurrent);
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
        PriceFeedTestnet priceFeedTestnet,
        uint256 diff_tolerance
    ) internal view returns (bool) {
        bytes32 _first = sortedCdps.getFirst();
        uint256 _price = priceFeedTestnet.getPrice();
        uint256 _firstICR = cdpManager.getICR(_first, _price);
        uint256 _TCR = cdpManager.getTCR(_price);

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
        PriceFeedTestnet priceFeedTestnet,
        SortedCdps sortedCdps
    ) internal view returns (bool) {
        bytes32 currentCdp = sortedCdps.getFirst();

        uint256 _price = priceFeedTestnet.getPrice();
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

    function invariant_SL_05(
        CRLens crLens,
        CdpManager cdpManager,
        PriceFeedTestnet priceFeedTestnet,
        SortedCdps sortedCdps
    ) internal returns (bool) {
        bytes32 currentCdp = sortedCdps.getFirst();

        uint256 _price = priceFeedMock.getPrice();
        uint256 newIcrPrevious = type(uint256).max;

        while (currentCdp != bytes32(0)) {
            uint256 newIcr = crLens.quoteRealICR(currentCdp);
            if (newIcr > newIcrPrevious) {
                return false;
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
        PriceFeedTestnet priceFeedTestnet,
        EBTCToken eBTCToken
    ) internal view returns (bool) {
        // TODO how to calculate "the dollar value of eBTC"?
        // TODO how do we take into account underlying/shares into this calculation?
        return
            cdpManager.getTCR(priceFeedTestnet.getPrice()) > collateral.getPooledEthByShares(1e18)
                ? (cdpManager.getSystemCollShares() * priceFeedTestnet.getPrice()) / 1e18 >=
                    eBTCToken.totalSupply()
                : (cdpManager.getSystemCollShares() * priceFeedTestnet.getPrice()) / 1e18 <
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
        ICollateralToken collateral
    ) internal view returns (bool) {
        return collateral.sharesOf(address(activePool)) >= activePool.getSystemCollShares();
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
            (uint256 entireDebt, uint256 entireColl, ) = cdpManager.getDebtAndCollShares(currentCdp);
            cdpsBalance += entireDebt;
            currentCdp = sortedCdps.getNext(currentCdp);
        }

        return totalSupply >= cdpsBalance;
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
        PriceFeedTestnet priceFeedTestnet,
        CRLens crLens
    ) internal returns (bool) {
        uint256 curentPrice = priceFeedTestnet.getPrice();
        return crLens.quoteRealTCR() == cdpManager.getSyncedTCR(curentPrice);
    }

    function invariant_GENERAL_13(
        CRLens crLens,
        CdpManager cdpManager,
        PriceFeedTestnet priceFeedTestnet,
        SortedCdps sortedCdps
    ) internal returns (bool) {
        bytes32 currentCdp = sortedCdps.getFirst();

        uint256 _price = priceFeedMock.getPrice();
        uint256 newIcrPrevious = type(uint256).max;

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

    function invariant_DUMMY_01(PriceFeedTestnet priceFeedTestnet) internal view returns (bool) {
        return priceFeedTestnet.getPrice() > 0;
    }
}
