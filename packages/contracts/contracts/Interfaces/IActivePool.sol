// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./IPool.sol";

interface IActivePool is IPool {
    // --- Events ---
    event BorrowerOperationsAddressChanged(address _newBorrowerOperationsAddress);
    event CdpManagerAddressChanged(address _newCdpManagerAddress);
    event ActivePoolEBTCDebtUpdated(uint256 _EBTCDebt);
    event SystemCollSharesUpdated(uint256 _coll);
    event CollateralAddressChanged(address _collTokenAddress);
    event FeeRecipientAddressChanged(address _feeRecipientAddress);
    event CollSurplusPoolAddressChanged(address _collSurplusAddress);
    event FeeRecipientClaimableCollSharesIncreased(uint256 _coll, uint256 _fee);
    event FeeRecipientClaimableCollSharesDecreased(uint256 _coll, uint256 _fee);
    event FlashLoanSuccess(address _receiver, address _token, uint256 _amount, uint256 _fee);
    event SweepTokenSuccess(address indexed _token, uint256 _amount, address indexed _recipient);

    // --- Functions ---
    function transferSystemCollShares(address _account, uint256 _amount) external;

    function increaseSystemCollShares(uint256 _value) external;

    function transferSystemCollSharesAndLiquidatorReward(
        address _account,
        uint256 _shares,
        uint256 _liquidatorRewardShares
    ) external;

    function allocateSystemCollSharesToFeeRecipient(uint256 _shares) external;

    function claimFeeRecipientCollShares(uint256 _shares) external;

    function feeRecipientAddress() external view returns (address);

    function getFeeRecipientClaimableCollShares() external view returns (uint256);

    function setFeeRecipientAddress(address _feeRecipientAddress) external;
}
