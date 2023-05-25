// SPDX-License-Identifier: MIT
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

/**
 * @title Implementation of the LeverageMacro, meant to be called via a delegatecall by a SC Like Wallet
 * @notice The Caller MUST implement the `function owner() external view returns (address)`
 * @notice to use this contract:
 *      Add this logic address to `callbackHandler` for the function `onFlashLoan`
 *      Add the inteded allowances (see above)
 *      Toggle the `callbackEnabledForCall` for the current call, by adding a call to `enableCallbackForCall`
 *      Perform the operation
 * @notice NOTE: that tokens will remain in the SC Wallet
 *  You can perform a delegatecall to `sweepToCaller` after the operation to have the SC Wallet send you back the funds
 * @notice If you didn't get it, this is an advanced contract, please simulate the TX with Tenderly before using this
 * @dev Only one deployment of this reference contract must be performed as users will delegatecall to it
 *  This makes upgrades opt-in
 */
contract LeverageMacroDelegateTarget is LeverageMacroBase {
    constructor(
        address _borrowerOperationsAddress,
        address _activePool,
        address _cdpManager,
        address _ebtc,
        address _coll,
        address _sortedCdps
    )
        LeverageMacroBase(
            _borrowerOperationsAddress,
            _activePool,
            _cdpManager,
            _ebtc,
            _coll,
            _sortedCdps,
            false // Do not sweep to caller
        )
    {
        // Approves are done via `execute` since this is a contract you delegatecall into
    }

    /// @dev Call self, since this is called via delegate call, and get owner
    function owner() public override returns (address) {
        address _owner = IOwnerLike(address(this)).owner();
        return _owner;
    }
}
