// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IStablePoolFactory {
    event PoolCreated(address indexed pool);

    function create(
        string memory name,
        string memory symbol,
        address[] memory tokens,
        uint256 amplificationParameter,
        uint256 swapFeePercentage,
        address owner
    ) external returns (address);
}
