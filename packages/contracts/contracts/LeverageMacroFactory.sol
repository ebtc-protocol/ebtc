// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {LeverageMacroReference} from "./LeverageMacroReference.sol";
import "./Dependencies/ICollateralToken.sol";
import "./Interfaces/IEBTCToken.sol";

/**
 * @title Factory for deploying LeverageMacros
 */
contract LeverageMacroFactory {
    address public immutable borrowerOperations;
    address public immutable activePool;
    address public immutable cdpManager;
    address public immutable ebtcToken;
    address public immutable stETH;
    address public immutable sortedCdps;

    event DeployNewMacro(address indexed sender, address indexed newContractAddress);

    constructor(
        address _borrowerOperationsAddress,
        address _activePool,
        address _cdpManager,
        address _ebtc,
        address _coll,
        address _sortedCdps
    ) {
        borrowerOperations = _borrowerOperationsAddress;
        activePool = _activePool;
        cdpManager = _cdpManager;
        ebtcToken = _ebtc;
        stETH = _coll;
        sortedCdps = _sortedCdps;
    }

    /// @notice Deploys a new macro for you
    function deployNewMacro() external returns (address) {
        return deployNewMacro(msg.sender);
    }

    /// @notice Deploys a new macro for an owner, only they can operate the macro
    function deployNewMacro(address _owner) public returns (address) {
        address addy = address(
            new LeverageMacroReference(
                borrowerOperations,
                activePool,
                cdpManager,
                ebtcToken,
                stETH,
                sortedCdps,
                _owner
            )
        );

        emit DeployNewMacro(_owner, addy);

        return addy;
    }
}
