pragma solidity 0.8.17;

import {BaseStorageVariables} from "../BaseStorageVariables.sol";

abstract contract BeforeAfter is BaseStorageVariables {
    struct Vars {
        uint256 nicrBefore;
        uint256 nicrAfter;
        uint256 icrBefore;
        uint256 icrAfter;
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
        uint256 debtBefore;
        uint256 debtAfter;
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
        vars.icrBefore = _cdpId != bytes32(0)
            ? cdpManager.getICR(_cdpId, vars.priceBefore)
            : 0;
        vars.cdpCollBefore = _cdpId != bytes32(0) ? cdpManager.getCdpCollShares(_cdpId) : 0;
        vars.cdpDebtBefore = _cdpId != bytes32(0) ? cdpManager.getCdpDebt(_cdpId) : 0;
        vars.liquidatorRewardSharesBefore = _cdpId != bytes32(0)
            ? cdpManager.getCdpLiquidatorRewardShares(_cdpId)
            : 0;
        vars.cdpStatusBefore = _cdpId != bytes32(0) ? cdpManager.getCdpStatus(_cdpId) : 0;
        vars.debtBefore = _cdpId != bytes32(0) ? cdpManager.getCdpDebt(_cdpId) : 0;

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
        _calldatas[0] = abi.encodeWithSelector(cdpManager.syncGlobalAccountingAndGracePeriod.selector);

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
        vars.debtAfter = _cdpId != bytes32(0) ? cdpManager.getCdpDebt(_cdpId) : 0;

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
        _calldatas[0] = abi.encodeWithSelector(cdpManager.syncGlobalAccountingAndGracePeriod.selector);

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
    }
}
