// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

interface ILQTYStaking {

    // --- Events --
    
    event LQTYTokenAddressSet(address _lqtyTokenAddress);
    event EBTCTokenAddressSet(address _ebtcTokenAddress);
    event TroveManagerAddressSet(address _cdpManager);
    event BorrowerOperationsAddressSet(address _borrowerOperationsAddress);
    event ActivePoolAddressSet(address _activePoolAddress);

    event StakeChanged(address indexed staker, uint newStake);
    event StakingGainsWithdrawn(address indexed staker, uint EBTCGain, uint ETHGain);
    event F_ETHUpdated(uint _F_ETH);
    event F_EBTCUpdated(uint _F_EBTC);
    event TotalLQTYStakedUpdated(uint _totalLQTYStaked);
    event EtherSent(address _account, uint _amount);
    event StakerSnapshotsUpdated(address _staker, uint _F_ETH, uint _F_EBTC);

    // --- Functions ---

    function setAddresses
    (
        address _lqtyTokenAddress,
        address _ebtcTokenAddress,
        address _cdpManagerAddress, 
        address _borrowerOperationsAddress,
        address _activePoolAddress
    )  external;

    function stake(uint _LQTYamount) external;

    function unstake(uint _LQTYamount) external;

    function increaseF_ETH(uint _ETHFee) external; 

    function increaseF_EBTC(uint _LQTYFee) external;  

    function getPendingETHGain(address _user) external view returns (uint);

    function getPendingEBTCGain(address _user) external view returns (uint);
}
