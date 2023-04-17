pragma solidity 0.8.17;

import "./WETH9.sol";

interface IActivePool {
    function sweepToken(address token, uint amount) external;
}

// for reentrancy test
contract ReentrancyToken is WETH9 {
    address public activePool;

    function setActivePool(address _activePool) external {
        activePool = _activePool;
    }

    function transfer(address dst, uint wad) public override returns (bool) {
        // try to reenter
        IActivePool(activePool).sweepToken(address(this), wad);
    }
}
