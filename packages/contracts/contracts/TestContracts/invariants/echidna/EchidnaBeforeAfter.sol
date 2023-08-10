pragma solidity 0.8.17;

import {EchidnaBaseTester} from "./EchidnaBaseTester.sol";

abstract contract EchidnaBeforeAfter is EchidnaBaseTester {
    struct Vars {
        uint256 nicrBefore;
        uint256 nicrAfter;
        uint256 actorCollBefore;
        uint256 actorCollAfter;
        uint256 actorCdpCountBefore;
        uint256 actorCdpCountAfter;
        uint256 cdpCollBefore;
        uint256 cdpCollAfter;
        uint256 liquidatorRewardSharesBefore;
        uint256 liquidatorRewardSharesAfter;
        uint256 sortedCdpsSizeBefore;
        uint256 sortedCdpsSizeAfter;
        uint256 cdpStatusBefore;
        uint256 cdpStatusAfter;
        uint256 tcrBefore;
        uint256 tcrAfter;
        uint256 debtBefore;
        uint256 debtAfter;
        uint256 ebtcTotalSupplyBefore;
        uint256 ebtcTotalSupplyAfter;
        uint256 ethPerShareBefore;
        uint256 ethPerShareAfter;
    }

    struct Cdp {
        bytes32 id;
        uint256 icr;
    }

    Vars vars;

    function _before(bytes32 _cdpId) internal {
        vars.nicrBefore = _cdpId != bytes32(0) ? cdpManager.getNominalICR(_cdpId) : 0;
        vars.cdpCollBefore = _cdpId != bytes32(0) ? cdpManager.getCdpColl(_cdpId) : 0;
        vars.liquidatorRewardSharesBefore = _cdpId != bytes32(0)
            ? cdpManager.getCdpLiquidatorRewardShares(_cdpId)
            : 0;
        vars.cdpStatusBefore = _cdpId != bytes32(0) ? cdpManager.getCdpStatus(_cdpId) : 0;
        vars.debtBefore = _cdpId != bytes32(0) ? cdpManager.getCdpDebt(_cdpId) : 0;

        vars.actorCollBefore = collateral.balanceOf(address(actor));
        vars.actorCdpCountBefore = sortedCdps.cdpCountOf(address(actor));
        vars.sortedCdpsSizeBefore = sortedCdps.getSize();
        vars.tcrBefore = cdpManager.getTCR(priceFeedTestnet.fetchPrice());
        vars.ebtcTotalSupplyBefore = eBTCToken.totalSupply();
        vars.ethPerShareBefore = collateral.getEthPerShare();
    }

    function _after(bytes32 _cdpId) internal {
        vars.nicrAfter = _cdpId != bytes32(0) ? cdpManager.getNominalICR(_cdpId) : 0;
        vars.cdpCollAfter = _cdpId != bytes32(0) ? cdpManager.getCdpColl(_cdpId) : 0;
        vars.liquidatorRewardSharesAfter = _cdpId != bytes32(0)
            ? cdpManager.getCdpLiquidatorRewardShares(_cdpId)
            : 0;
        vars.cdpStatusAfter = _cdpId != bytes32(0) ? cdpManager.getCdpStatus(_cdpId) : 0;
        vars.debtAfter = _cdpId != bytes32(0) ? cdpManager.getCdpDebt(_cdpId) : 0;

        vars.actorCollAfter = collateral.balanceOf(address(actor));
        vars.actorCdpCountAfter = sortedCdps.cdpCountOf(address(actor));
        vars.sortedCdpsSizeAfter = sortedCdps.getSize();
        vars.tcrAfter = cdpManager.getTCR(priceFeedTestnet.fetchPrice());
        vars.ebtcTotalSupplyAfter = eBTCToken.totalSupply();
        vars.ethPerShareAfter = collateral.getEthPerShare();
    }
}
