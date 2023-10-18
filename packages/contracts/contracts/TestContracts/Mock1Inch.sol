// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;
pragma abicoder v2;

import "./EbtcTokenTester.sol";
import "./CollateralTokenTester.sol";

contract Mock1Inch {
    // swap output slippage
    uint256 public slippage = 50;
    uint256 public constant MAX_SLIPPAGE = 10000;
    // collateral(stETH) to eBTC
    uint256 public price = 7428 * 1e13;

    CollateralTokenTester public stETH;
    EbtcTokenTester public eBTCToken;

    constructor(address _ebtcTester, address _collTester) {
        stETH = CollateralTokenTester(payable(_collTester));
        eBTCToken = EbtcTokenTester(_ebtcTester);
    }

    function setPrice(uint256 _newPrice) external {
        price = _newPrice;
    }

    function swap(address tokenIn, address tokenOut, uint256 amountIn) external returns (uint256) {
        if (tokenIn == address(stETH) && tokenOut == address(eBTCToken)) {
            stETH.transferFrom(msg.sender, address(this), amountIn);
            uint256 amt = (amountIn * price) / 1e18;
            eBTCToken.transfer(msg.sender, amt);
            return amt;
        } else if (tokenIn == address(eBTCToken) && tokenOut == address(stETH)) {
            eBTCToken.transferFrom(msg.sender, address(this), amountIn);
            uint256 amt = (amountIn * 1e18) / price;
            stETH.transfer(msg.sender, amt);
            return amt;
        }

        revert("No match");
    }
}
