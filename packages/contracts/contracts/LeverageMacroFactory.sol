pragma solidity 0.8.17;

import {LeverageMacro} from "./LeverageMacro.sol";
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

        // set allowance for flashloan lender/CDP open
        IEBTCToken(ebtcToken).approve(_borrowerOperationsAddress, type(uint256).max);
        ICollateralToken(stETH).approve(_borrowerOperationsAddress, type(uint256).max);
        ICollateralToken(stETH).approve(_activePool, type(uint256).max);
    }

    function deployNewMacro() external returns (address) {
        return deployNewMacro(msg.sender);
    }

    function deployNewMacro(address _owner) public returns (address) {
        address addy = address(
            new LeverageMacro(
            borrowerOperations,
            activePool,
            cdpManager,
            ebtcToken,
            sortedCdps,
            stETH,
            _owner)
        );

        emit DeployNewMacro(_owner, addy);

        return addy;
    }
}
