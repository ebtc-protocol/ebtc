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

abstract contract Properties is AssertionHelper, BeforeAfter, PropertiesDescriptions {
    /// @notice AP-01 The collateral balance in the active pool is greater than or equal to its accounting number
    function invariant_AP_01(
        ICollateralToken collateral,
        ActivePool activePool
    ) internal view returns (bool) {
        return (collateral.sharesOf(address(activePool)) >= activePool.getStEthColl());
    }

    /// @notice AP-03 The eBTC debt accounting number in active pool equal to the EBTC total supply
    function invariant_AP_03(
        EBTCToken eBTCToken,
        ActivePool activePool
    ) internal view returns (bool) {
        return (eBTCToken.totalSupply() == activePool.getEBTCDebt());
    }

    /// @notice AP-04 The total collateral in active pool should be equal to the sum of all individual CDP collateral
    function invariant_AP_04(
        CdpManager cdpManager,
        ActivePool activePool,
        uint256 diff_tolerance
    ) internal view returns (bool) {
        uint256 _cdpCount = cdpManager.getCdpIdsCount();
        uint256 _sum;
        for (uint256 i = 0; i < _cdpCount; ++i) {
            (, uint256 _coll, ) = cdpManager.getEntireDebtAndColl(cdpManager.CdpIds(i));
            _sum += _coll;
        }
        uint256 _activeColl = activePool.getStEthColl();
        uint256 _diff = _sum > _activeColl ? (_sum - _activeColl) : (_activeColl - _sum);
        uint256 _divisor = _sum > _activeColl ? _sum : _activeColl;
        return (_diff * 1e18 <= diff_tolerance * _activeColl);
    }

    /// @notice AP-05 The sum of debt accounting in active pool should be equal to sum of debt accounting of individual CDPs
    function invariant_AP_05(
        CdpManager cdpManager,
        uint256 diff_tolerance
    ) internal view returns (bool) {
        uint256 _cdpCount = cdpManager.getCdpIdsCount();
        uint256 _sum;
        for (uint256 i = 0; i < _cdpCount; ++i) {
            (uint256 _debt, , ) = cdpManager.getEntireDebtAndColl(cdpManager.CdpIds(i));
            _sum += _debt;
        }
        return isApproximateEq(_sum, cdpManager.getEntireSystemDebt(), diff_tolerance);
    }

    /// @notice CDPM-01 The count of active CDPs is equal to the SortedCdp list length
    function invariant_CDPM_01(
        CdpManager cdpManager,
        SortedCdps sortedCdps
    ) internal view returns (bool) {
        return (cdpManager.getCdpIdsCount() == sortedCdps.getSize());
    }

    /// @notice CDPM-02 The sum of active CDPs stake is equal to totalStakes
    function invariant_CDPM_02(CdpManager cdpManager) internal view returns (bool) {
        uint256 _cdpCount = cdpManager.getCdpIdsCount();
        uint256 _sum;
        for (uint256 i = 0; i < _cdpCount; ++i) {
            _sum += cdpManager.getCdpStake(cdpManager.CdpIds(i));
        }
        return (_sum == cdpManager.totalStakes());
    }

    /// @notice CDPM-03 The stFeePerUnit tracker for individual CDP is equal to or less than the global variable
    function invariant_CDPM_03(CdpManager cdpManager) internal view returns (bool) {
        uint256 _cdpCount = cdpManager.getCdpIdsCount();
        uint256 _stFeePerUnitg = cdpManager.stFeePerUnitg();
        for (uint256 i = 0; i < _cdpCount; ++i) {
            if (_stFeePerUnitg < cdpManager.stFeePerUnitcdp(cdpManager.CdpIds(i))) {
                return false;
            }
        }
        return true;
    }

    /// @notice CSP-01 The collateral balance in the collSurplus pool is greater than or equal to its accounting number
    function invariant_CSP_01(
        ICollateralToken collateral,
        CollSurplusPool collSurplusPool
    ) internal view returns (bool) {
        return collateral.sharesOf(address(collSurplusPool)) >= collSurplusPool.getStEthColl();
    }

    event L(string, uint);

    /// @notice SL-01 The NICR ranking in the sorted list should follow descending order
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

    /// @notice SL-02 The the first(highest) ICR in the sorted list should be greater or equal to TCR (with tolerance due to rounding errors)
    function invariant_SL_02(
        CdpManager cdpManager,
        SortedCdps sortedCdps,
        PriceFeedTestnet priceFeedTestnet,
        uint256 diff_tolerance
    ) internal view returns (bool) {
        bytes32 _first = sortedCdps.getFirst();
        uint256 _price = priceFeedTestnet.getPrice();
        uint256 _firstICR = cdpManager.getCurrentICR(_first, _price);
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

    /// @notice SL-03 All CDPs have status active and stake greater than zero
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

    /// @notice P-01 The dollar value of the locked stETH exceeds the dollar value of the issued eBTC if TCR is greater than 100%
    function invariant_P_01(
        CdpManager cdpManager,
        PriceFeedTestnet priceFeedTestnet,
        EBTCToken eBTCToken
    ) internal view returns (bool) {
        // TODO how to calculate "the dollar value of eBTC"?
        return
            cdpManager.getTCR(priceFeedTestnet.getPrice()) > 1 ether
                ? cdpManager.getEntireSystemColl() * priceFeedTestnet.getPrice() >=
                    eBTCToken.totalSupply()
                : cdpManager.getEntireSystemColl() * priceFeedTestnet.getPrice() <
                    eBTCToken.totalSupply();
    }

    /// @notice P-03 After any operation, the TCR must be above the CCR
    function invariant_P_03(Vars memory vars) internal view returns (bool) {
        return !vars.isRecoveryModeBefore && !vars.isRecoveryModeAfter;
    }

    /// @notice P-22 `CdpManager`, `BorrowerOperations`, `eBTCToken`, `SortedCDPs` and `PriceFeed`s do not hold value terms of stETH and eBTC unless there are donations. @todo Missing CdpManager balance check, Missing stETH/eBTC checks
    function invariant_P_22(
        ICollateralToken collateral,
        BorrowerOperations borrowerOperations,
        EBTCToken eBTCToken,
        SortedCdps sortedCdps,
        PriceFeedTestnet priceFeedTestnet
    ) internal view returns (bool) {
        if (collateral.balanceOf(address(borrowerOperations)) > 0) {
            return false;
        }

        if (collateral.balanceOf(address(eBTCToken)) > 0) {
            return false;
        }

        if (collateral.balanceOf(address(priceFeedTestnet)) > 0) {
            return false;
        }

        if (collateral.balanceOf(address(sortedCdps)) > 0) {
            return false;
        }

        return true;
    }

    /// @notice P-36 At all times, the total debt is equal to the sum of all debts from all CDP + toRedistribute
    function invariant_P_36(
        EBTCToken eBTCToken,
        CdpManager cdpManager,
        SortedCdps sortedCdps
    ) internal view returns (bool) {
        uint256 totalSupply = eBTCToken.totalSupply();

        bytes32 currentCdp = sortedCdps.getFirst();
        uint256 cdpsBalance;
        while (currentCdp != bytes32(0)) {
            (uint256 entireDebt, uint256 entireColl, ) = cdpManager.getEntireDebtAndColl(currentCdp);
            cdpsBalance += entireDebt;
            currentCdp = sortedCdps.getNext(currentCdp);
        }

        return totalSupply >= cdpsBalance;
    }

    /// @notice P-47 The collateral balance of the ActivePool is positive if there is at least one CDP open
    function invariant_P_47(
        CdpManager cdpManager,
        ICollateralToken collateral,
        ActivePool activePool
    ) internal view returns (bool) {
        if (cdpManager.getCdpIdsCount() > 0) {
            return collateral.balanceOf(address(activePool)) > 0;
        } else {
            // @todo verify if should return 0 in this case, assuming no donations
            return true;
        }
    }

    /// @notice P-48 Adding collateral improves Nominal ICR
    function invariant_P_48(uint256 nicrBefore, uint256 nicrAfter) internal view returns (bool) {
        return nicrAfter > nicrBefore;
    }

    /// @notice P-50 After any operation, the ICR of a CDP must be above the MCR in Normal mode or TCR in Recovery mode
    function invariant_P_50(
        CdpManager cdpManager,
        PriceFeedTestnet priceFeedTestnet,
        bytes32 _cdpId
    ) internal view returns (bool) {
        uint _price = priceFeedTestnet.getPrice();
        bool _recovery = cdpManager.checkRecoveryMode(_price);
        uint _icr = cdpManager.getCurrentICR(_cdpId, _price);
        if (_recovery) {
            return (_icr > cdpManager.getTCR(_price));
        } else {
            return (_icr > cdpManager.MCR());
        }
    }

    /// @notice DUMMY-01 PriceFeed is configured
    function invariant_DUMMY_01(PriceFeedTestnet priceFeedTestnet) internal view returns (bool) {
        return priceFeedTestnet.getPrice() > 0;
    }
}
