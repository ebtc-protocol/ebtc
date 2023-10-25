// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;
pragma abicoder v2;

import "../Dependencies/ICollateralToken.sol";
import "../Interfaces/IEBTCToken.sol";
import "../Dependencies/IBalancerV2Vault.sol";

contract MockBalancer {
    // swap output slippage
    uint256 public slippage = 50;
    uint256 public constant MAX_SLIPPAGE = 10000;
    // collateral(stETH) to eBTC
    uint256 public price = 7428 * 1e13;

    ICollateralToken public stETH;
    IEBTCToken public eBTCToken;

    constructor(address _ebtc, address _coll) {
        stETH = ICollateralToken(_coll);
        eBTCToken = IEBTCToken(_ebtc);
    }

    function setPrice(uint256 _newPrice) external {
        price = _newPrice;
    }

    function setSlippage(uint256 _slippage) external {
        slippage = _slippage;
    }

    function swap(
        SingleSwap calldata singleSwap,
        FundManagement calldata funds,
        uint256 limit,
        uint256 deadline
    ) external returns (uint256) {
        require(singleSwap.kind == SwapKind.GIVEN_IN, "MockBalancer: invalid swap kind!");
        address tokenIn = singleSwap.assetIn;
        address tokenOut = singleSwap.assetOut;
        uint256 amountIn = singleSwap.amount;

        if (tokenIn == address(stETH) && tokenOut == address(eBTCToken)) {
            stETH.transferFrom(msg.sender, address(this), amountIn);
            uint256 amt = _getOutputAmountWithSlippage((amountIn * price) / 1e18);
            require(amt >= limit, "MockBalancer: below expected limit!");
            eBTCToken.transfer(msg.sender, amt);
            return amt;
        } else if (tokenIn == address(eBTCToken) && tokenOut == address(stETH)) {
            eBTCToken.transferFrom(msg.sender, address(this), amountIn);
            uint256 amt = _getOutputAmountWithSlippage((amountIn * 1e18) / price);
            require(amt >= limit, "MockBalancer: below expected limit!");
            stETH.transfer(msg.sender, amt);
            return amt;
        }

        revert("MockBalancer: Invalid swap parameters!");
    }

    function _getOutputAmountWithSlippage(uint256 _input) internal returns (uint256) {
        return (_input * (MAX_SLIPPAGE - slippage)) / MAX_SLIPPAGE;
    }
}
