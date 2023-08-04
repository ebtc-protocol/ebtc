pragma solidity 0.8.17;

import {EchidnaBaseTester} from "./EchidnaBaseTester.sol";

abstract contract EchidnaBeforeAfter is EchidnaBaseTester {
    struct Vars {
        uint256 nicrBefore;
        uint256 nicrAfter;
        uint256 actorCollBefore;
        uint256 actorCollAfter;
        uint256 cdpCollBefore;
        uint256 cdpCollAfter;
        uint256 liquidatorRewardSharesBefore;
        uint256 liquidatorRewardSharesAfter;
        uint256 sortedCdpsSizeBefore;
        uint256 sortedCdpsSizeAfter;
    }

    Vars vars;

    function _before(bytes32 _cdpId) internal {
        vars.nicrBefore = cdpManager.getNominalICR(_cdpId);
        vars.actorCollBefore = collateral.balanceOf(address(actor));
        vars.cdpCollBefore = cdpManager.getCdpColl(_cdpId);
        vars.liquidatorRewardSharesBefore = cdpManager.getCdpLiquidatorRewardShares(_cdpId);
        vars.sortedCdpsSizeBefore = sortedCdps.getSize();
    }

    function _after(bytes32 _cdpId) internal {
        vars.nicrAfter = cdpManager.getNominalICR(_cdpId);
        vars.actorCollAfter = collateral.balanceOf(address(actor));
        vars.cdpCollAfter = cdpManager.getCdpColl(_cdpId);
        vars.liquidatorRewardSharesAfter = cdpManager.getCdpLiquidatorRewardShares(_cdpId);
        vars.sortedCdpsSizeAfter = sortedCdps.getSize();
    }
}
