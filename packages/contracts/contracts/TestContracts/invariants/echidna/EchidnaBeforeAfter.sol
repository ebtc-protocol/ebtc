pragma solidity 0.8.17;

import {BeforeAfter} from "../BeforeAfter.sol";
import {EchidnaBaseTester} from "./EchidnaBaseTester.sol";

abstract contract EchidnaBeforeAfter is EchidnaBaseTester, BeforeAfter {
    struct Cdp {
        bytes32 id;
        uint256 icr;
    }

    function _before(bytes32 _cdpId) internal {
        vars.priceBefore = priceFeedTestnet.fetchPrice();

        vars.nicrBefore = _cdpId != bytes32(0) ? cdpManager.getNominalICR(_cdpId) : 0;
        vars.icrBefore = _cdpId != bytes32(0)
            ? cdpManager.getCurrentICR(_cdpId, vars.priceBefore)
            : 0;
        vars.cdpCollBefore = _cdpId != bytes32(0) ? cdpManager.getCdpColl(_cdpId) : 0;
        vars.cdpDebtBefore = _cdpId != bytes32(0) ? cdpManager.getCdpDebt(_cdpId) : 0;
        vars.liquidatorRewardSharesBefore = _cdpId != bytes32(0)
            ? cdpManager.getCdpLiquidatorRewardShares(_cdpId)
            : 0;
        vars.cdpStatusBefore = _cdpId != bytes32(0) ? cdpManager.getCdpStatus(_cdpId) : 0;
        vars.debtBefore = _cdpId != bytes32(0) ? cdpManager.getCdpDebt(_cdpId) : 0;

        vars.isRecoveryModeBefore = cdpManager.checkRecoveryMode(vars.priceBefore);
        (vars.feeSplitBefore, , ) = collateral.getPooledEthByShares(cdpManager.DECIMAL_PRECISION()) >
            cdpManager.stFPPSg()
            ? cdpManager.calcFeeUponStakingReward(
                collateral.getPooledEthByShares(cdpManager.DECIMAL_PRECISION()),
                cdpManager.stFPPSg()
            )
            : (0, 0, 0);
        vars.feeRecipientTotalCollBefore =
            activePool.getFeeRecipientClaimableColl() +
            collateral.balanceOf(activePool.feeRecipientAddress());
        vars.actorCollBefore = collateral.balanceOf(address(actor));
        vars.actorEbtcBefore = eBTCToken.balanceOf(address(actor));
        vars.actorCdpCountBefore = sortedCdps.cdpCountOf(address(actor));
        vars.sortedCdpsSizeBefore = sortedCdps.getSize();
        vars.tcrBefore = cdpManager.getTCR(vars.priceBefore);
        vars.ebtcTotalSupplyBefore = eBTCToken.totalSupply();
        vars.ethPerShareBefore = collateral.getEthPerShare();
        vars.activePoolCollBefore = activePool.getStEthColl();
        vars.collSurplusPoolBefore = collSurplusPool.getStEthColl();
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
        _calldatas[0] = abi.encodeWithSelector(cdpManager.syncPendingGlobalState.selector);

        _targets[1] = address(cdpManager);
        _calldatas[1] = abi.encodeWithSelector(cdpManager.getTCR.selector, vars.priceBefore);

        // Compute new TCR after syncPendingGlobalState and revert to previous snapshot in oder to not affect the current state
        try actor.simulate(_targets, _calldatas) {} catch (bytes memory reason) {
            assembly {
                // Slice the sighash.
                reason := add(reason, 0x04)
            }
            bytes memory returnData = abi.decode(reason, (bytes));
            vars.newTcrSyncPendingGlobalStateBefore = abi.decode(returnData, (uint256));
        }
    }

    function _after(bytes32 _cdpId) internal {
        vars.priceAfter = priceFeedTestnet.fetchPrice();

        vars.nicrAfter = _cdpId != bytes32(0) ? cdpManager.getNominalICR(_cdpId) : 0;
        vars.icrAfter = _cdpId != bytes32(0) ? cdpManager.getCurrentICR(_cdpId, vars.priceAfter) : 0;
        vars.cdpCollAfter = _cdpId != bytes32(0) ? cdpManager.getCdpColl(_cdpId) : 0;
        vars.cdpDebtAfter = _cdpId != bytes32(0) ? cdpManager.getCdpDebt(_cdpId) : 0;
        vars.liquidatorRewardSharesAfter = _cdpId != bytes32(0)
            ? cdpManager.getCdpLiquidatorRewardShares(_cdpId)
            : 0;
        vars.cdpStatusAfter = _cdpId != bytes32(0) ? cdpManager.getCdpStatus(_cdpId) : 0;
        vars.debtAfter = _cdpId != bytes32(0) ? cdpManager.getCdpDebt(_cdpId) : 0;

        vars.isRecoveryModeAfter = cdpManager.checkRecoveryMode(vars.priceAfter);
        (vars.feeSplitAfter, , ) = collateral.getPooledEthByShares(cdpManager.DECIMAL_PRECISION()) >
            cdpManager.stFPPSg()
            ? cdpManager.calcFeeUponStakingReward(
                collateral.getPooledEthByShares(cdpManager.DECIMAL_PRECISION()),
                cdpManager.stFPPSg()
            )
            : (0, 0, 0);
        vars.feeRecipientTotalCollAfter =
            activePool.getFeeRecipientClaimableColl() +
            collateral.balanceOf(activePool.feeRecipientAddress());
        vars.actorCollAfter = collateral.balanceOf(address(actor));
        vars.actorEbtcAfter = eBTCToken.balanceOf(address(actor));
        vars.actorCdpCountAfter = sortedCdps.cdpCountOf(address(actor));
        vars.sortedCdpsSizeAfter = sortedCdps.getSize();
        vars.tcrAfter = cdpManager.getTCR(vars.priceAfter);
        vars.ebtcTotalSupplyAfter = eBTCToken.totalSupply();
        vars.ethPerShareAfter = collateral.getEthPerShare();
        vars.activePoolCollAfter = activePool.getStEthColl();
        vars.collSurplusPoolAfter = collSurplusPool.getStEthColl();
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
        _calldatas[0] = abi.encodeWithSelector(cdpManager.syncPendingGlobalState.selector);

        _targets[1] = address(cdpManager);
        _calldatas[1] = abi.encodeWithSelector(cdpManager.getTCR.selector, vars.priceAfter);

        // Compute new TCR after syncPendingGlobalState and revert to previous snapshot in oder to not affect the current state
        try actor.simulate(_targets, _calldatas) {} catch (bytes memory reason) {
            assembly {
                // Slice the sighash.
                reason := add(reason, 0x04)
            }
            bytes memory returnData = abi.decode(reason, (bytes));
            vars.newTcrSyncPendingGlobalStateAfter = abi.decode(returnData, (uint256));
        }
    }
}
