// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./interfaces/IStablePoolFactory.sol";
import "./interfaces/IBalancerPool.sol";
import "./interfaces/IAsset.sol";
import "./interfaces/IBalancerVault.sol";
import "./interfaces/ICurvePool.sol";

abstract contract MainnetConstants {
    // ebtc cdp pos.
    uint256 LEV_BPS = 4_000;

    // misc.
    uint256 SLIPPAGE_CONTROL = 9_700;
    uint256 SLIPPAGE_CONTROL_SWAP = 9_850;
    uint256 MAX_DELTA = 7e17;
    bytes32 public constant NULL_CDP_ID = bytes32(0);

    // balancer
    IStablePoolFactory STABLE_POOL_FACTORY =
        IStablePoolFactory(0x8df6EfEc5547e31B0eb7d1291B511FF8a2bf987c);
    IBalancerVault BALANCER_VAULT =
        IBalancerVault(payable(0xBA12222222228d8Ba445958a75a0704d566BF2C8));
    bytes32 constant WBTC_WETH_POOL_ID =
        0xa6f548df93de924d73be7d25dc02554c6bd66db500020000000000000000000e;
    uint256 AMPLIFICATION_FACTOR = 25;

    // curve (https://curve.fi/#/ethereum/pools/factory-v2-117/deposit)
    ICurvePool STETH_ETH_CURVE_POOL = ICurvePool(0x828b154032950C8ff7CF8085D841723Db2696056);

    // tokens
    address WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
}
