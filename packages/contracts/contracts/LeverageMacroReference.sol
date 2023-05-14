pragma solidity 0.8.17;

import {LeverageMacroBase} from "./LeverageMacroBase.sol";

/**
 * Allows specifying arbitrary operations to lever up
 *     NOTE: Due to security concenrs
 *     LeverageMacroReference accepts allowances and transfers token to FlashLoanMacroReceiver
 *     // FlashLoanMacroReceiver can perform ARBITRARY CALLS YOU WILL LOSE ALL ASSETS IF YOU APPROVE IT
 *     LeverageMacroReference on the other hand is safe to approve as it cannot move your funds without your consent
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
    ) LeverageMacroBase(
        _borrowerOperationsAddress,
        _activePool,
        _cdpManager,
        _ebtc,
        _coll,
        _sortedCdps,
        true // Sweep to caller since this is not supposed to hold funds
    ) {

        theOwner = _owner;

        // set allowance for flashloan lender/CDP open
        ebtcToken.approve(_borrowerOperationsAddress, type(uint256).max);
        stETH.approve(_borrowerOperationsAddress, type(uint256).max);
        stETH.approve(_activePool, type(uint256).max);
    }

    function owner() public override returns (address) {
        return theOwner;
    }
}
