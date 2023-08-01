pragma solidity 0.8.17;

import {ICollateralToken} from "../../Dependencies/ICollateralToken.sol";
import {ActivePool} from "../../ActivePool.sol";

abstract contract Properties {
  function invariant_AP_01(ICollateralToken collateral, ActivePool activePool) internal view returns(bool) {
    return (collateral.sharesOf(address(activePool)) >= activePool.getStEthColl());
  }
}