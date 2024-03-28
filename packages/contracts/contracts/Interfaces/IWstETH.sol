// SPDX-FileCopyrightText: 2020 Lido <info@lido.fi>

// SPDX-License-Identifier: GPL-3.0

/* See contracts/COMPILERS.md */
pragma solidity 0.8.17;

import {IERC20} from "../Dependencies/IERC20.sol";

/// @notice Check https://etherscan.io/token/0x7f39c581f595b53c5cb19bd0b3f8da6c935e2ca0#code
interface IWstETH is IERC20 {
    /// @notice Exchanges wstETH to stETH
    function unwrap(uint256 _wstETHAmount) external returns (uint256);

    /// @notice Exchanges stETH to wstETH
    function wrap(uint256 _stETHAmount) external returns (uint256);

    /// @notice Get amount of wstETH for a given amount of stETH
    function getWstETHByStETH(uint256 _stETHAmount) external view returns (uint256);

    /// @notice Get amount of stETH for a given amount of wstETH
    function getStETHByWstETH(uint256 _stETHAmount) external view returns (uint256);
}
