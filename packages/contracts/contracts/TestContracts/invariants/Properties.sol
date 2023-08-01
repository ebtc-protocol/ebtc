pragma solidity 0.8.17;

import {ICollateralToken} from "../../Dependencies/ICollateralToken.sol";
import {ActivePool} from "../../ActivePool.sol";
import {EBTCToken} from "../../EBTCToken.sol";

// See PROPERTIES.md for the full list of invariants
abstract contract Properties {
  function invariant_AP_01(ICollateralToken collateral, ActivePool activePool) internal view returns(bool) {
    return (collateral.sharesOf(address(activePool)) >= activePool.getStEthColl());
  }

  function invariant_AP_03(EBTCToken eBTCToken, ActivePool activePool) internal view returns(bool) {
    return (eBTCToken.totalSupply() == activePool.getEBTCDebt());
  }
}