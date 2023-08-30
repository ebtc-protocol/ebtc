// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {LeverageMacroBase} from "./LeverageMacroBase.sol";

/**
 * @title Reference implementation of LeverageMacro
 * @notice Deploy a copy of this via `LeverageMacroFactory` to use it for yourself
 * @dev You can deploy a copy of this via a clone or similar to save users gas
 */
contract LeverageMacroReference is LeverageMacroBase {
    address internal immutable theOwner;

    // Leverage Macro should receive a request and set that data
    // Then perform the request

    constructor(
        address _borrowerOperationsAddress,
        address _activePool,
        address _cdpManager,
        address _ebtc,
        address _coll,
        address _sortedCdps,
        address _owner
    )
        LeverageMacroBase(
            _borrowerOperationsAddress,
            _activePool,
            _cdpManager,
            _ebtc,
            _coll,
            _sortedCdps,
            true // Sweep to caller since this is not supposed to hold funds
        )
    {
        theOwner = _owner;

        // set allowance for flashloan lender/CDP open
        ebtcToken.approve(_borrowerOperationsAddress, type(uint256).max);
        stETH.approve(_borrowerOperationsAddress, type(uint256).max);
        stETH.approve(_activePool, type(uint256).max);
    }

    function owner() public override returns (address) {
        return theOwner;
    }

    /// @notice use this if you broke the approvals
    /// @dev diamond wallets can re-approve separately
    function resetApprovals() external {
        _assertOwner();

        ebtcToken.approve(address(borrowerOperations), type(uint256).max);
        stETH.approve(address(borrowerOperations), type(uint256).max);
        stETH.approve(address(activePool), type(uint256).max);
    }
}
