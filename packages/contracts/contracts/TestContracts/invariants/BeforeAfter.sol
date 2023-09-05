pragma solidity 0.8.17;

import {Pretty, Strings} from "../Pretty.sol";
import {BaseStorageVariables} from "../BaseStorageVariables.sol";

abstract contract BeforeAfter is BaseStorageVariables {
    using Strings for string;
    using Pretty for uint256;
    using Pretty for int256;
    using Pretty for bool;

    struct Vars {
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
    }

    Vars vars;
    struct Cdp {
        bytes32 id;
        uint256 icr;
    }

    function _before(bytes32 _cdpId) internal {
        vars.priceBefore = priceFeedMock.fetchPrice();

        vars.nicrBefore = _cdpId != bytes32(0) ? cdpManager.getNominalICR(_cdpId) : 0;
        vars.icrBefore = _cdpId != bytes32(0) ? cdpManager.getICR(_cdpId, vars.priceBefore) : 0;
        vars.cdpCollBefore = _cdpId != bytes32(0) ? cdpManager.getCdpCollShares(_cdpId) : 0;
        vars.cdpDebtBefore = _cdpId != bytes32(0) ? cdpManager.getCdpDebt(_cdpId) : 0;
        vars.liquidatorRewardSharesBefore = _cdpId != bytes32(0)
            ? cdpManager.getCdpLiquidatorRewardShares(_cdpId)
            : 0;
        vars.cdpStatusBefore = _cdpId != bytes32(0) ? cdpManager.getCdpStatus(_cdpId) : 0;

        vars.isRecoveryModeBefore = cdpManager.checkRecoveryMode(vars.priceBefore);
        (vars.feeSplitBefore, , ) = collateral.getPooledEthByShares(cdpManager.DECIMAL_PRECISION()) >
            cdpManager.stEthIndex()
            ? cdpManager.calcFeeUponStakingReward(
                collateral.getPooledEthByShares(cdpManager.DECIMAL_PRECISION()),
                cdpManager.stEthIndex()
            )
            : (0, 0, 0);
        vars.feeRecipientTotalCollBefore =
            activePool.getFeeRecipientClaimableCollShares() +
            collateral.balanceOf(activePool.feeRecipientAddress());
        vars.actorCollBefore = collateral.balanceOf(address(actor));
        vars.actorEbtcBefore = eBTCToken.balanceOf(address(actor));
        vars.actorCdpCountBefore = sortedCdps.cdpCountOf(address(actor));
        vars.sortedCdpsSizeBefore = sortedCdps.getSize();
        vars.tcrBefore = cdpManager.getTCR(vars.priceBefore);
        vars.ebtcTotalSupplyBefore = eBTCToken.totalSupply();
        vars.ethPerShareBefore = collateral.getEthPerShare();
        vars.activePoolCollBefore = activePool.getSystemCollShares();
        vars.collSurplusPoolBefore = collSurplusPool.getTotalSurplusCollShares();
        vars.lastGracePeriodStartTimestampBefore = cdpManager.lastGracePeriodStartTimestamp();
        vars.lastGracePeriodStartTimestampIsSetBefore =
            cdpManager.lastGracePeriodStartTimestamp() != cdpManager.UNSET_TIMESTAMP();
        vars.hasGracePeriodPassedBefore =
            cdpManager.lastGracePeriodStartTimestamp() != cdpManager.UNSET_TIMESTAMP() &&
            block.timestamp >
            cdpManager.lastGracePeriodStartTimestamp() + cdpManager.recoveryModeGracePeriod();

        address[] memory _targets = new address[](2);
        bytes[] memory _calldatas = new bytes[](2);

        _targets[0] = address(cdpManager);
        _calldatas[0] = abi.encodeWithSelector(
            cdpManager.syncGlobalAccountingAndGracePeriod.selector
        );

        _targets[1] = address(cdpManager);
        _calldatas[1] = abi.encodeWithSelector(cdpManager.getTCR.selector, vars.priceBefore);

        // Compute new TCR after syncGlobalAccountingAndGracePeriod and revert to previous snapshot in oder to not affect the current state
        try actor.simulate(_targets, _calldatas) {} catch (bytes memory reason) {
            assembly {
                // Slice the sighash.
                reason := add(reason, 0x04)
            }
            bytes memory returnData = abi.decode(reason, (bytes));
            vars.newTcrBefore = abi.decode(returnData, (uint256));
        }

        _targets[0] = address(cdpManager);
        _calldatas[0] = abi.encodeWithSelector(cdpManager.syncAccounting.selector, _cdpId);

        _targets[1] = address(cdpManager);
        _calldatas[1] = abi.encodeWithSelector(cdpManager.getICR.selector, _cdpId, vars.priceBefore);

        // Compute new ICR after syncAccounting and revert to previous snapshot in oder to not affect the current state
        try actor.simulate(_targets, _calldatas) {} catch (bytes memory reason) {
            assembly {
                // Slice the sighash.
                reason := add(reason, 0x04)
            }
            bytes memory returnData = abi.decode(reason, (bytes));
            vars.newIcrBefore = abi.decode(returnData, (uint256));
        }
    }

    function _after(bytes32 _cdpId) internal {
        vars.priceAfter = priceFeedMock.fetchPrice();

        vars.nicrAfter = _cdpId != bytes32(0) ? cdpManager.getNominalICR(_cdpId) : 0;
        vars.icrAfter = _cdpId != bytes32(0) ? cdpManager.getICR(_cdpId, vars.priceAfter) : 0;
        vars.cdpCollAfter = _cdpId != bytes32(0) ? cdpManager.getCdpCollShares(_cdpId) : 0;
        vars.cdpDebtAfter = _cdpId != bytes32(0) ? cdpManager.getCdpDebt(_cdpId) : 0;
        vars.liquidatorRewardSharesAfter = _cdpId != bytes32(0)
            ? cdpManager.getCdpLiquidatorRewardShares(_cdpId)
            : 0;
        vars.cdpStatusAfter = _cdpId != bytes32(0) ? cdpManager.getCdpStatus(_cdpId) : 0;

        vars.isRecoveryModeAfter = cdpManager.checkRecoveryMode(vars.priceAfter);
        (vars.feeSplitAfter, , ) = collateral.getPooledEthByShares(cdpManager.DECIMAL_PRECISION()) >
            cdpManager.stEthIndex()
            ? cdpManager.calcFeeUponStakingReward(
                collateral.getPooledEthByShares(cdpManager.DECIMAL_PRECISION()),
                cdpManager.stEthIndex()
            )
            : (0, 0, 0);
        vars.feeRecipientTotalCollAfter =
            activePool.getFeeRecipientClaimableCollShares() +
            collateral.balanceOf(activePool.feeRecipientAddress());
        vars.actorCollAfter = collateral.balanceOf(address(actor));
        vars.actorEbtcAfter = eBTCToken.balanceOf(address(actor));
        vars.actorCdpCountAfter = sortedCdps.cdpCountOf(address(actor));
        vars.sortedCdpsSizeAfter = sortedCdps.getSize();
        vars.tcrAfter = cdpManager.getTCR(vars.priceAfter);
        vars.ebtcTotalSupplyAfter = eBTCToken.totalSupply();
        vars.ethPerShareAfter = collateral.getEthPerShare();
        vars.activePoolCollAfter = activePool.getSystemCollShares();
        vars.collSurplusPoolAfter = collSurplusPool.getTotalSurplusCollShares();
        vars.lastGracePeriodStartTimestampAfter = cdpManager.lastGracePeriodStartTimestamp();
        vars.lastGracePeriodStartTimestampIsSetAfter =
            cdpManager.lastGracePeriodStartTimestamp() != cdpManager.UNSET_TIMESTAMP();
        vars.hasGracePeriodPassedAfter =
            cdpManager.lastGracePeriodStartTimestamp() != cdpManager.UNSET_TIMESTAMP() &&
            block.timestamp >
            cdpManager.lastGracePeriodStartTimestamp() + cdpManager.recoveryModeGracePeriod();

        address[] memory _targets = new address[](2);
        bytes[] memory _calldatas = new bytes[](2);

        _targets[0] = address(cdpManager);
        _calldatas[0] = abi.encodeWithSelector(
            cdpManager.syncGlobalAccountingAndGracePeriod.selector
        );

        _targets[1] = address(cdpManager);
        _calldatas[1] = abi.encodeWithSelector(cdpManager.getTCR.selector, vars.priceAfter);

        // Compute new TCR after syncGlobalAccountingAndGracePeriod and revert to previous snapshot in oder to not affect the current state
        try actor.simulate(_targets, _calldatas) {} catch (bytes memory reason) {
            assembly {
                // Slice the sighash.
                reason := add(reason, 0x04)
            }
            bytes memory returnData = abi.decode(reason, (bytes));
            vars.newTcrAfter = abi.decode(returnData, (uint256));
        }

        _targets[0] = address(cdpManager);
        _calldatas[0] = abi.encodeWithSelector(cdpManager.syncAccounting.selector, _cdpId);

        _targets[1] = address(cdpManager);
        _calldatas[1] = abi.encodeWithSelector(cdpManager.getICR.selector, _cdpId, vars.priceAfter);

        // Compute new ICR after syncAccounting and revert to previous snapshot in oder to not affect the current state
        try actor.simulate(_targets, _calldatas) {} catch (bytes memory reason) {
            assembly {
                // Slice the sighash.
                reason := add(reason, 0x04)
            }
            bytes memory returnData = abi.decode(reason, (bytes));
            vars.newIcrAfter = abi.decode(returnData, (uint256));
        }
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
                .concat(vars.sortedCdpsSizeBefore.pretty())
                .concat("\t")
                .concat(vars.sortedCdpsSizeAfter.pretty())
                .concat("\n");
        }
        if (vars.cdpStatusBefore != vars.cdpStatusAfter) {
            log = log
                .concat("cdpStatus\t\t\t")
                .concat(vars.cdpStatusBefore.pretty())
                .concat("\t")
                .concat(vars.cdpStatusAfter.pretty())
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
                .concat("\t")
                .concat(vars.hasGracePeriodPassedAfter.pretty())
                .concat("\n");
        }
    }
}
