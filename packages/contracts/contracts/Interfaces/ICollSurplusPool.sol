// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface ICollSurplusPool {
    // --- Events ---

    event SurplusCollSharesAdded(
        bytes32 indexed _cdpId,
        address indexed _account,
        uint256 _claimableSurplusCollShares,
        uint256 _surplusCollSharesAddedFromCollateral,
        uint256 _surplusCollSharesAddedFromLiquidatorReward
    );
    event CollSharesTransferred(address indexed _to, uint256 _amount);

    event SweepTokenSuccess(address indexed _token, uint256 _amount, address indexed _recipient);

    // --- Contract setters ---

    function getTotalSurplusCollShares() external view returns (uint256);

    function getSurplusCollShares(address _account) external view returns (uint256);

    function increaseSurplusCollShares(
        bytes32 _cdpId,
        address _account,
        uint256 _collateralShares,
        uint256 _liquidatorRewardShares
    ) external;

    function claimSurplusCollShares(address _account) external;

    function increaseTotalSurplusCollShares(uint256 _value) external;
}
