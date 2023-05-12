pragma solidity 0.8.17;

import {LeverageMacroReference} from "./LeverageMacroReference.sol";
import "./Dependencies/ICollateralToken.sol";
import "./Interfaces/IEBTCToken.sol";

contract LeverageMacroFactory {
    address public immutable borrowerOperations;
    address public immutable activePool;
    address public immutable cdpManager;
    address public immutable ebtcToken;
    address public immutable sortedCdps;
    address public immutable stETH;

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

    function deployNewMacro() external returns (address) {
        return deployNewMacro(msg.sender);
    }

    function deployNewMacro(address _owner) public returns (address) {
        address addy = address(
            new LeverageMacroReference(
                borrowerOperations,
                activePool,
                cdpManager,
                ebtcToken,
                sortedCdps,
                stETH,
                _owner
            )
        );

        emit DeployNewMacro(_owner, addy);

        return addy;
    }
}
