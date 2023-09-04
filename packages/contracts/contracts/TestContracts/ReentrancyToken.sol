pragma solidity 0.8.17;

import "./WETH9.sol";

interface ISweepPool {
    function sweepToken(address token, uint256 amount) external;
}

// for reentrancy test
contract ReentrancyToken is WETH9 {
    address public pool;

    function setSweepPool(address _pool) external {
        pool = _pool;
    }

    function transfer(address dst, uint256 wad) public override returns (bool) {
        if (pool == address(0)) {
            return false;
        }
        // try to reenter
        ISweepPool(pool).sweepToken(address(this), wad);
    }
}
