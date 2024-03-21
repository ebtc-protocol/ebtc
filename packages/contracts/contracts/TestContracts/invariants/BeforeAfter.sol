pragma solidity 0.8.17;

import {Pretty, Strings} from "../Pretty.sol";
import {BaseStorageVariables} from "../BaseStorageVariables.sol";

abstract contract BeforeAfter is BaseStorageVariables {
    using Strings for string;
    using Pretty for uint256;
    using Pretty for int256;
    using Pretty for bool;

    struct Vars {
        uint256 userSurplusBefore;
        uint256 userSurplusAfter;
        uint256 valueInSystemBefore;
        uint256 valueInSystemAfter;
        uint256 nicrBefore;
        uint256 nicrAfter;
        uint256 icrBefore;
        uint256 icrAfter;
        uint256 newIcrBefore;
        uint256 newIcrAfter;
        uint256 feeSplitBefore;
        uint256 feeSplitAfter;
        uint256 feeRecipientTotalCollBefore;
        uint256 feeRecipientTotalCollAfter;
        uint256 feeRecipientCollSharesBefore;
        uint256 feeRecipientCollSharesAfter;
        uint256 actorCollBefore;
        uint256 actorCollAfter;
        uint256 actorEbtcBefore;
        uint256 actorEbtcAfter;
        uint256 actorCdpCountBefore;
        uint256 actorCdpCountAfter;
        uint256 cdpCollBefore;
        uint256 cdpCollAfter;
        uint256 cdpDebtBefore;
        uint256 cdpDebtAfter;
        uint256 cdpStakeBefore;
        uint256 cdpStakeAfter;
        uint256 liquidatorRewardSharesBefore;
        uint256 liquidatorRewardSharesAfter;
        uint256 sortedCdpsSizeBefore;
        uint256 sortedCdpsSizeAfter;
        uint256 cdpStatusBefore;
        uint256 cdpStatusAfter;
        uint256 tcrBefore;
        uint256 tcrAfter;
        uint256 newTcrBefore;
        uint256 newTcrAfter;
        uint256 ebtcTotalSupplyBefore;
        uint256 ebtcTotalSupplyAfter;
        uint256 ethPerShareBefore;
        uint256 ethPerShareAfter;
        uint256 activePoolCollBefore;
        uint256 activePoolCollAfter;
        uint256 activePoolDebtBefore;
        uint256 activePoolDebtAfter;
        uint256 collSurplusPoolBefore;
        uint256 collSurplusPoolAfter;
        uint256 priceBefore;
        uint256 priceAfter;
        bool isRecoveryModeBefore;
        bool isRecoveryModeAfter;
        uint256 lastGracePeriodStartTimestampBefore;
        uint256 lastGracePeriodStartTimestampAfter;
        bool lastGracePeriodStartTimestampIsSetBefore;
        bool lastGracePeriodStartTimestampIsSetAfter;
        bool hasGracePeriodPassedBefore;
        bool hasGracePeriodPassedAfter;
        uint256 systemDebtRedistributionIndexBefore;
        uint256 systemDebtRedistributionIndexAfter;
        uint256 feeRecipientCollSharesBalBefore;
        uint256 feeRecipientCollSharesBalAfter;
        uint256 cumulativeCdpsAtTimeOfRebase;
        uint256 prevStEthFeeIndex;
        uint256 afterStEthFeeIndex;
        uint256 totalStakesBefore;
        uint256 totalStakesAfter;
        uint256 totalStakesSnapshotBefore;
        uint256 totalStakesSnapshotAfter;
        uint256 totalCollateralSnapshotBefore;
        uint256 totalCollateralSnapshotAfter;
    }

    Vars vars;
    struct Cdp {
        bytes32 id;
        uint256 icr;
    }

    function _before(bytes32 _cdpId) internal {
        vars.priceBefore = priceFeedMock.fetchPrice();

        address ownerToCheck = sortedCdps.getOwnerAddress(_cdpId);
        vars.userSurplusBefore = collSurplusPool.getSurplusCollShares(ownerToCheck);

        (uint256 debtBefore, uint256 collBefore) = cdpManager.getSyncedDebtAndCollShares(_cdpId);

        vars.nicrBefore = _cdpId != bytes32(0) ? crLens.quoteRealNICR(_cdpId) : 0;
        vars.icrBefore = _cdpId != bytes32(0)
            ? cdpManager.getCachedICR(_cdpId, vars.priceBefore)
            : 0;
        vars.cdpCollBefore = _cdpId != bytes32(0) ? collBefore : 0;
        vars.cdpDebtBefore = _cdpId != bytes32(0) ? debtBefore : 0;
        vars.cdpStakeBefore = _cdpId != bytes32(0) ? crLens.getRealStake(_cdpId) : 0;
        vars.liquidatorRewardSharesBefore = _cdpId != bytes32(0)
            ? cdpManager.getCdpLiquidatorRewardShares(_cdpId)
            : 0;
        vars.cdpStatusBefore = _cdpId != bytes32(0) ? cdpManager.getCdpStatus(_cdpId) : 0;

        vars.isRecoveryModeBefore = crLens.quoteCheckRecoveryMode() == 1; /// @audit crLens
        (vars.feeSplitBefore, , ) = collateral.getPooledEthByShares(cdpManager.DECIMAL_PRECISION()) >
            cdpManager.stEthIndex()
            ? cdpManager.calcFeeUponStakingReward(
                collateral.getPooledEthByShares(cdpManager.DECIMAL_PRECISION()),
                cdpManager.stEthIndex()
            )
            : (0, 0, 0);
        vars.feeRecipientTotalCollBefore = collateral.balanceOf(activePool.feeRecipientAddress());
        vars.feeRecipientCollSharesBefore = activePool.getFeeRecipientClaimableCollShares();
        vars.feeRecipientCollSharesBalBefore = collateral.sharesOf(activePool.feeRecipientAddress());
        vars.actorCollBefore = collateral.balanceOf(address(actor));
        vars.actorEbtcBefore = eBTCToken.balanceOf(address(actor));
        vars.actorCdpCountBefore = sortedCdps.cdpCountOf(address(actor));
        vars.sortedCdpsSizeBefore = sortedCdps.getSize();
        vars.tcrBefore = cdpManager.getCachedTCR(vars.priceBefore);
        vars.ebtcTotalSupplyBefore = eBTCToken.totalSupply();
        vars.ethPerShareBefore = collateral.getEthPerShare();
        vars.activePoolDebtBefore = activePool.getSystemDebt();
        vars.activePoolCollBefore = activePool.getSystemCollShares();
        vars.collSurplusPoolBefore = collSurplusPool.getTotalSurplusCollShares();
        vars.lastGracePeriodStartTimestampBefore = cdpManager.lastGracePeriodStartTimestamp();
        vars.lastGracePeriodStartTimestampIsSetBefore =
            cdpManager.lastGracePeriodStartTimestamp() != cdpManager.UNSET_TIMESTAMP();
        vars.hasGracePeriodPassedBefore =
            cdpManager.lastGracePeriodStartTimestamp() != cdpManager.UNSET_TIMESTAMP() &&
            block.timestamp >
            cdpManager.lastGracePeriodStartTimestamp() +
                cdpManager.recoveryModeGracePeriodDuration();
        vars.systemDebtRedistributionIndexBefore = cdpManager.systemDebtRedistributionIndex();
        vars.newTcrBefore = crLens.quoteRealTCR();
        vars.newIcrBefore = crLens.quoteRealICR(_cdpId);

        vars.valueInSystemBefore ==
            (collateral.getPooledEthByShares(
                vars.activePoolCollBefore +
                    vars.collSurplusPoolBefore +
                    vars.feeRecipientTotalCollBefore
            ) * vars.priceBefore) /
                1e18 -
                vars.activePoolDebtBefore;
        vars.prevStEthFeeIndex = cdpManager.systemStEthFeePerUnitIndex();

        vars.totalStakesBefore = cdpManager.totalStakes();
        vars.totalStakesSnapshotBefore = cdpManager.totalStakesSnapshot();
        vars.totalCollateralSnapshotBefore = cdpManager.totalCollateralSnapshot();
    }

    function _after(bytes32 _cdpId) internal {
        address ownerToCheck = sortedCdps.getOwnerAddress(_cdpId);
        vars.userSurplusAfter = collSurplusPool.getSurplusCollShares(ownerToCheck);

        vars.priceAfter = priceFeedMock.fetchPrice();

        (, uint256 collAfter) = cdpManager.getSyncedDebtAndCollShares(_cdpId);

        vars.nicrAfter = _cdpId != bytes32(0) ? crLens.quoteRealNICR(_cdpId) : 0;
        vars.icrAfter = _cdpId != bytes32(0) ? cdpManager.getCachedICR(_cdpId, vars.priceAfter) : 0;
        vars.cdpCollAfter = _cdpId != bytes32(0) ? collAfter : 0;
        vars.cdpDebtAfter = _cdpId != bytes32(0) ? cdpManager.getCdpDebt(_cdpId) : 0;
        vars.cdpStakeAfter = _cdpId != bytes32(0) ? crLens.getRealStake(_cdpId) : 0;
        vars.liquidatorRewardSharesAfter = _cdpId != bytes32(0)
            ? cdpManager.getCdpLiquidatorRewardShares(_cdpId)
            : 0;
        vars.cdpStatusAfter = _cdpId != bytes32(0) ? cdpManager.getCdpStatus(_cdpId) : 0;

        vars.isRecoveryModeAfter = cdpManager.checkRecoveryMode(vars.priceAfter); /// @audit This is fine as is because after the system is synched
        (vars.feeSplitAfter, , ) = collateral.getPooledEthByShares(cdpManager.DECIMAL_PRECISION()) >
            cdpManager.stEthIndex()
            ? cdpManager.calcFeeUponStakingReward(
                collateral.getPooledEthByShares(cdpManager.DECIMAL_PRECISION()),
                cdpManager.stEthIndex()
            )
            : (0, 0, 0);

        vars.feeRecipientTotalCollAfter = collateral.balanceOf(activePool.feeRecipientAddress());
        vars.feeRecipientCollSharesAfter = activePool.getFeeRecipientClaimableCollShares();
        vars.feeRecipientCollSharesBalAfter = collateral.sharesOf(activePool.feeRecipientAddress());
        vars.actorCollAfter = collateral.balanceOf(address(actor));
        vars.actorEbtcAfter = eBTCToken.balanceOf(address(actor));
        vars.actorCdpCountAfter = sortedCdps.cdpCountOf(address(actor));
        vars.sortedCdpsSizeAfter = sortedCdps.getSize();
        vars.tcrAfter = cdpManager.getCachedTCR(vars.priceAfter);
        vars.ebtcTotalSupplyAfter = eBTCToken.totalSupply();
        vars.ethPerShareAfter = collateral.getEthPerShare();
        vars.activePoolDebtAfter = activePool.getSystemDebt();
        vars.activePoolCollAfter = activePool.getSystemCollShares();
        vars.collSurplusPoolAfter = collSurplusPool.getTotalSurplusCollShares();
        vars.lastGracePeriodStartTimestampAfter = cdpManager.lastGracePeriodStartTimestamp();
        vars.lastGracePeriodStartTimestampIsSetAfter =
            cdpManager.lastGracePeriodStartTimestamp() != cdpManager.UNSET_TIMESTAMP();
        vars.hasGracePeriodPassedAfter =
            cdpManager.lastGracePeriodStartTimestamp() != cdpManager.UNSET_TIMESTAMP() &&
            block.timestamp >
            cdpManager.lastGracePeriodStartTimestamp() +
                cdpManager.recoveryModeGracePeriodDuration();
        vars.systemDebtRedistributionIndexAfter = cdpManager.systemDebtRedistributionIndex();

        vars.newTcrAfter = crLens.quoteRealTCR();
        vars.newIcrAfter = crLens.quoteRealICR(_cdpId);

        // Value in system after
        vars.valueInSystemAfter =
            (collateral.getPooledEthByShares(
                vars.activePoolCollAfter +
                    vars.collSurplusPoolAfter +
                    vars.feeRecipientTotalCollAfter
            ) * vars.priceAfter) /
            1e18 -
            vars.activePoolDebtAfter;
        vars.afterStEthFeeIndex = cdpManager.systemStEthFeePerUnitIndex();

        if (vars.afterStEthFeeIndex > vars.prevStEthFeeIndex) {
            vars.cumulativeCdpsAtTimeOfRebase += cdpManager.getActiveCdpsCount();
        }

        vars.totalStakesAfter = cdpManager.totalStakes();
        vars.totalStakesSnapshotAfter = cdpManager.totalStakesSnapshot();
        vars.totalCollateralSnapshotAfter = cdpManager.totalCollateralSnapshot();
    }

    function _diff() internal view returns (string memory log) {
        log = string("\n\t\t\t\tBefore\t\t\tAfter\n");
        if (vars.activePoolCollBefore != vars.activePoolCollAfter) {
            log = log
                .concat("activePoolColl\t\t\t")
                .concat(vars.activePoolCollBefore.pretty())
                .concat("\t")
                .concat(vars.activePoolCollAfter.pretty())
                .concat("\n");
        }
        if (vars.collSurplusPoolBefore != vars.collSurplusPoolAfter) {
            log = log
                .concat("collSurplusPool\t\t\t")
                .concat(vars.collSurplusPoolBefore.pretty())
                .concat("\t")
                .concat(vars.collSurplusPoolAfter.pretty())
                .concat("\n");
        }
        if (vars.nicrBefore != vars.nicrAfter) {
            log = log
                .concat("nicr\t\t\t\t")
                .concat(vars.nicrBefore.pretty())
                .concat("\t")
                .concat(vars.nicrAfter.pretty())
                .concat("\n");
        }
        if (vars.icrBefore != vars.icrAfter) {
            log = log
                .concat("icr\t\t\t\t")
                .concat(vars.icrBefore.pretty())
                .concat("\t")
                .concat(vars.icrAfter.pretty())
                .concat("\n");
        }
        if (vars.newIcrBefore != vars.newIcrAfter) {
            log = log
                .concat("newIcr\t\t\t\t")
                .concat(vars.newIcrBefore.pretty())
                .concat("\t")
                .concat(vars.newIcrAfter.pretty())
                .concat("\n");
        }
        if (vars.feeSplitBefore != vars.feeSplitAfter) {
            log = log
                .concat("feeSplit\t\t\t\t")
                .concat(vars.feeSplitBefore.pretty())
                .concat("\t")
                .concat(vars.feeSplitAfter.pretty())
                .concat("\n");
        }
        if (vars.feeRecipientTotalCollBefore != vars.feeRecipientTotalCollAfter) {
            log = log
                .concat("feeRecipientTotalColl\t")
                .concat(vars.feeRecipientTotalCollBefore.pretty())
                .concat("\t")
                .concat(vars.feeRecipientTotalCollAfter.pretty())
                .concat("\n");
        }
        if (vars.actorCollBefore != vars.actorCollAfter) {
            log = log
                .concat("actorColl\t\t\t\t")
                .concat(vars.actorCollBefore.pretty())
                .concat("\t")
                .concat(vars.actorCollAfter.pretty())
                .concat("\n");
        }
        if (vars.actorEbtcBefore != vars.actorEbtcAfter) {
            log = log
                .concat("actorEbtc\t\t\t\t")
                .concat(vars.actorEbtcBefore.pretty())
                .concat("\t")
                .concat(vars.actorEbtcAfter.pretty())
                .concat("\n");
        }
        if (vars.actorCdpCountBefore != vars.actorCdpCountAfter) {
            log = log
                .concat("actorCdpCount\t\t\t")
                .concat(vars.actorCdpCountBefore.pretty())
                .concat("\t")
                .concat(vars.actorCdpCountAfter.pretty())
                .concat("\n");
        }
        if (vars.cdpCollBefore != vars.cdpCollAfter) {
            log = log
                .concat("cdpColl\t\t\t\t")
                .concat(vars.cdpCollBefore.pretty())
                .concat("\t")
                .concat(vars.cdpCollAfter.pretty())
                .concat("\n");
        }
        if (vars.cdpDebtBefore != vars.cdpDebtAfter) {
            log = log
                .concat("cdpDebt\t\t\t\t")
                .concat(vars.cdpDebtBefore.pretty())
                .concat("\t")
                .concat(vars.cdpDebtAfter.pretty())
                .concat("\n");
        }
        if (vars.liquidatorRewardSharesBefore != vars.liquidatorRewardSharesAfter) {
            log = log
                .concat("liquidatorRewardShares\t\t")
                .concat(vars.liquidatorRewardSharesBefore.pretty())
                .concat("\t")
                .concat(vars.liquidatorRewardSharesAfter.pretty())
                .concat("\n");
        }
        if (vars.sortedCdpsSizeBefore != vars.sortedCdpsSizeAfter) {
            log = log
                .concat("sortedCdpsSize\t\t\t")
                .concat(vars.sortedCdpsSizeBefore.pretty(0))
                .concat("\t\t\t")
                .concat(vars.sortedCdpsSizeAfter.pretty(0))
                .concat("\n");
        }
        if (vars.cdpStatusBefore != vars.cdpStatusAfter) {
            log = log
                .concat("cdpStatus\t\t\t")
                .concat(vars.cdpStatusBefore.pretty(0))
                .concat("\t\t\t")
                .concat(vars.cdpStatusAfter.pretty(0))
                .concat("\n");
        }
        if (vars.tcrBefore != vars.tcrAfter) {
            log = log
                .concat("tcr\t\t\t\t")
                .concat(vars.tcrBefore.pretty())
                .concat("\t")
                .concat(vars.tcrAfter.pretty())
                .concat("\n");
        }
        if (vars.newTcrBefore != vars.newTcrAfter) {
            log = log
                .concat("newTcr\t\t\t\t")
                .concat(vars.newTcrBefore.pretty())
                .concat("\t")
                .concat(vars.newTcrAfter.pretty())
                .concat("\n");
        }
        if (vars.ebtcTotalSupplyBefore != vars.ebtcTotalSupplyAfter) {
            log = log
                .concat("ebtcTotalSupply\t\t\t")
                .concat(vars.ebtcTotalSupplyBefore.pretty())
                .concat("\t")
                .concat(vars.ebtcTotalSupplyAfter.pretty())
                .concat("\n");
        }
        if (vars.ethPerShareBefore != vars.ethPerShareAfter) {
            log = log
                .concat("ethPerShare\t\t\t")
                .concat(vars.ethPerShareBefore.pretty())
                .concat("\t")
                .concat(vars.ethPerShareAfter.pretty())
                .concat("\n");
        }
        if (vars.isRecoveryModeBefore != vars.isRecoveryModeAfter) {
            log = log
                .concat("isRecoveryMode\t\t\t")
                .concat(vars.isRecoveryModeBefore.pretty())
                .concat("\t")
                .concat(vars.isRecoveryModeAfter.pretty())
                .concat("\n");
        }
        if (vars.lastGracePeriodStartTimestampBefore != vars.lastGracePeriodStartTimestampAfter) {
            log = log
                .concat("lastGracePeriodStartTimestamp\t")
                .concat(vars.lastGracePeriodStartTimestampBefore.pretty())
                .concat("\t")
                .concat(vars.lastGracePeriodStartTimestampAfter.pretty())
                .concat("\n");
        }
        if (
            vars.lastGracePeriodStartTimestampIsSetBefore !=
            vars.lastGracePeriodStartTimestampIsSetAfter
        ) {
            log = log
                .concat("lastGracePeriodStartTimestampIsSet\t")
                .concat(vars.lastGracePeriodStartTimestampIsSetBefore.pretty())
                .concat("\t")
                .concat(vars.lastGracePeriodStartTimestampIsSetAfter.pretty())
                .concat("\n");
        }
        if (vars.hasGracePeriodPassedBefore != vars.hasGracePeriodPassedAfter) {
            log = log
                .concat("hasGracePeriodPassed\t\t")
                .concat(vars.hasGracePeriodPassedBefore.pretty())
                .concat("\t\t\t")
                .concat(vars.hasGracePeriodPassedAfter.pretty())
                .concat("\n");
        }
        if (vars.systemDebtRedistributionIndexBefore != vars.systemDebtRedistributionIndexAfter) {
            log = log
                .concat("systemDebtRedistributionIndex\t\t")
                .concat(vars.systemDebtRedistributionIndexBefore.pretty())
                .concat("\t")
                .concat(vars.systemDebtRedistributionIndexAfter.pretty())
                .concat("\n");
        }
    }
}
