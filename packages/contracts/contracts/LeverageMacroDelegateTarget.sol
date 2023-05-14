pragma solidity 0.8.17;

import {LeverageMacroBase} from "./LeverageMacroBase.sol";

interface IOwnerLike {
    function owner() external view returns (address);
}

/**
 * LeverageMacroDelegateTarget - Meant to be DelegateCalled from the SC Wallet
 * Delegate call to doOperation to start
 * Set the DelegateCallBack for onFlashLoan in your SC Wallet to handle the FL Callback
 * NOTE: `_sweepToCaller` is set to false
 * You can `delegatecall` to it as part of `execute` as a way to use it in SC Wallet
 */

 /**
 SETUP
    // YOUR SC WALLET MUST HAVE DONE THE FOLLOWING
    ebtcToken.approve(_borrowerOperationsAddress, type(uint256).max);
    stETH.approve(_borrowerOperationsAddress, type(uint256).max);
    stETH.approve(_activePool, type(uint256).max);
  */
contract LeverageMacroDelegateTarget is LeverageMacroBase {
    constructor(
        address _borrowerOperationsAddress,
        address _activePool,
        address _cdpManager,
        address _ebtc,
        address _coll,
        address _sortedCdps
    ) LeverageMacroBase(
        _borrowerOperationsAddress,
        _activePool,
        _cdpManager,
        _ebtc,
        _coll,
        _sortedCdps,
        false // Do not sweep to caller
    ) {
        // Approves are done via `execute` since this is a contract you delegatecall into
    }

    /// @dev Call self, since this is called via delegate call, and get owner
    function owner() public override returns (address) {
      address _owner = IOwnerLike(address(this)).owner();
      return _owner;
    }
}
