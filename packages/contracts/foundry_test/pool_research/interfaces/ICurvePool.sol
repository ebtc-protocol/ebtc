// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ICurvePool {
    function exchange(
        int128 i,
        int128 j,
        uint256 dx,
        uint256 min_dy
    ) external payable returns (uint256);

    function get_dy(int128 i, int128 j, uint256 dx) external view returns (uint256);

    function get_dy(uint256 i, uint256 j, uint256 dx) external view returns (uint256);
}
