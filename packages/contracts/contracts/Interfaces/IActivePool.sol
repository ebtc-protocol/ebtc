// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./IPool.sol";

interface IActivePool is IPool {
    // --- Events ---
    event BorrowerOperationsAddressChanged(address _newBorrowerOperationsAddress);
    event CdpManagerAddressChanged(address _newCdpManagerAddress);
    event ActivePoolEBTCDebtUpdated(uint _EBTCDebt);
    event ActivePoolCollBalanceUpdated(uint _coll);
    event CollateralAddressChanged(address _collTokenAddress);
    event FeeRecipientAddressChanged(address _feeRecipientAddress);
    event CollSurplusPoolAddressChanged(address _collSurplusAddress);
    event ActivePoolFeeRecipientClaimableCollIncreased(uint _coll, uint _fee);
    event ActivePoolFeeRecipientClaimableCollDecreased(uint _coll, uint _fee);
    event FlashLoanSuccess(address _receiver, address _token, uint _amount, uint _fee);
    event SweepTokenSuccess(address indexed _token, uint _amount, address indexed _recipient);

    // --- Functions ---
    function transferSystemCollShares(address _account, uint _amount) external;

    function receiveColl(uint _value) external;

    function transferSystemCollSharesAndLiquidatorReward(
        address _account,
        uint _shares,
        uint _liquidatorRewardShares
    ) external;

    function allocateSystemCollSharesToFeeRecipient(uint _shares) external;

    function claimFeeRecipientCollShares(uint _shares) external;

    function feeRecipientAddress() external view returns (address);

    function getFeeRecipientClaimableCollShares() external view returns (uint);

    function setFeeRecipientAddress(address _feeRecipientAddress) external;
}
