pragma solidity 0.8.17;

import {ICollateralToken} from "../../Dependencies/ICollateralToken.sol";
import {ActivePool} from "../../ActivePool.sol";
import {EBTCToken} from "../../EBTCToken.sol";
import {CdpManager} from "../../CdpManager.sol";
import {AssertionHelper} from "./AssertionHelper.sol";

// See PROPERTIES.md for the full list of invariants
abstract contract Properties is AssertionHelper {
  function invariant_AP_01(ICollateralToken collateral, ActivePool activePool) internal view returns(bool) {
    return (collateral.sharesOf(address(activePool)) >= activePool.getStEthColl());
  }

  function invariant_AP_03(EBTCToken eBTCToken, ActivePool activePool) internal view returns(bool) {
    return (eBTCToken.totalSupply() == activePool.getEBTCDebt());
  }

  function invariant_AP_04(CdpManager cdpManager, ActivePool activePool, uint256 diff_tolerance) internal view returns(bool) {
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

    function invariant_AP_05(CdpManager cdpManager, uint256 diff_tolerance) internal view returns (bool) {
      uint256 _cdpCount = cdpManager.getCdpIdsCount();
      uint256 _sum;
      for (uint256 i = 0; i < _cdpCount; ++i) {
          (uint256 _debt, , ) = cdpManager.getEntireDebtAndColl(cdpManager.CdpIds(i));
          _sum += _debt;
      }
      return isApproximateEq(_sum, cdpManager.getEntireSystemDebt(), diff_tolerance);
    }
}