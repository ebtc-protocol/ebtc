// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "./ILiquityBase.sol";
import "./IStabilityPool.sol";
import "./IEBTCToken.sol";
import "./ILQTYToken.sol";
import "./ILQTYStaking.sol";


// Common interface for the Trove Manager.
interface ITroveManager is ILiquityBase {
    
    // --- Events ---

    event BorrowerOperationsAddressChanged(address _newBorrowerOperationsAddress);
    event PriceFeedAddressChanged(address _newPriceFeedAddress);
    event EBTCTokenAddressChanged(address _newEBTCTokenAddress);
    event ActivePoolAddressChanged(address _activePoolAddress);
    event DefaultPoolAddressChanged(address _defaultPoolAddress);
    event StabilityPoolAddressChanged(address _stabilityPoolAddress);
    event GasPoolAddressChanged(address _gasPoolAddress);
    event CollSurplusPoolAddressChanged(address _collSurplusPoolAddress);
    event SortedTrovesAddressChanged(address _sortedTrovesAddress);
    event LQTYTokenAddressChanged(address _lqtyTokenAddress);
    event LQTYStakingAddressChanged(address _lqtyStakingAddress);

    event Liquidation(uint _liquidatedDebt, uint _liquidatedColl, uint _collGasCompensation, uint _EBTCGasCompensation);
    event Redemption(uint _attemptedEBTCAmount, uint _actualEBTCAmount, uint _ETHSent, uint _ETHFee);
    event TroveUpdated(bytes32 indexed _cdpId, address indexed _borrower, uint _debt, uint _coll, uint _stake, uint8 _operation);
    event TroveLiquidated(bytes32 indexed _cdpId, address indexed _borrower, uint _debt, uint _coll, uint8 operation);
    event BaseRateUpdated(uint _baseRate);
    event LastFeeOpTimeUpdated(uint _lastFeeOpTime);
    event TotalStakesUpdated(uint _newTotalStakes);
    event SystemSnapshotsUpdated(uint _totalStakesSnapshot, uint _totalCollateralSnapshot);
    event LTermsUpdated(uint _L_ETH, uint _L_EBTCDebt);
    event TroveSnapshotsUpdated(uint _L_ETH, uint _L_EBTCDebt);
    event TroveIndexUpdated(bytes32 _borrower, uint _newIndex);

    // --- Functions ---

    function setAddresses(
        address _borrowerOperationsAddress,
        address _activePoolAddress,
        address _defaultPoolAddress,
        address _stabilityPoolAddress,
        address _gasPoolAddress,
        address _collSurplusPoolAddress,
        address _priceFeedAddress,
        address _ebtcTokenAddress,
        address _sortedTrovesAddress,
        address _lqtyTokenAddress,
        address _lqtyStakingAddress
    ) external;

    function stabilityPool() external view returns (IStabilityPool);
    function ebtcToken() external view returns (IEBTCToken);
    function lqtyToken() external view returns (ILQTYToken);
    function lqtyStaking() external view returns (ILQTYStaking);

    function getTroveIdsCount() external view returns (uint);

    function getIdFromTroveIdsArray(uint _index) external view returns (bytes32);

    function getNominalICR(bytes32 _cdpId) external view returns (uint);
    function getCurrentICR(bytes32 _cdpId, uint _price) external view returns (uint);

    function liquidate(bytes32 _cdpId) external;

    function liquidateTroves(uint _n) external;

    function batchLiquidateTroves(bytes32[] calldata _cdpArray) external;

    function redeemCollateral(
        uint _EBTCAmount,
        bytes32 _firstRedemptionHint,
        bytes32 _upperPartialRedemptionHint,
        bytes32 _lowerPartialRedemptionHint,
        uint _partialRedemptionHintNICR,
        uint _maxIterations,
        uint _maxFee
    ) external; 

    function updateStakeAndTotalStakes(bytes32 _cdpId) external returns (uint);

    function updateTroveRewardSnapshots(bytes32 _cdpId) external;

    function addTroveIdToArray(bytes32 _cdpId) external returns (uint index);

    function applyPendingRewards(bytes32 _cdpId) external;

    function getPendingETHReward(bytes32 _cdpId) external view returns (uint);

    function getPendingEBTCDebtReward(bytes32 _cdpId) external view returns (uint);

    function hasPendingRewards(bytes32 _cdpId) external view returns (bool);

    function getEntireDebtAndColl(bytes32 _cdpId) external view returns (
        uint debt, 
        uint coll, 
        uint pendingEBTCDebtReward, 
        uint pendingETHReward
    );

    function closeTrove(bytes32 _cdpId) external;

    function removeStake(bytes32 _cdpId) external;

    function getRedemptionRate() external view returns (uint);
    function getRedemptionRateWithDecay() external view returns (uint);

    function getRedemptionFeeWithDecay(uint _ETHDrawn) external view returns (uint);

    function getBorrowingRate() external view returns (uint);
    function getBorrowingRateWithDecay() external view returns (uint);

    function getBorrowingFee(uint EBTCDebt) external view returns (uint);
    function getBorrowingFeeWithDecay(uint _EBTCDebt) external view returns (uint);

    function decayBaseRateFromBorrowing() external;

    function getTroveStatus(bytes32 _cdpId) external view returns (uint);
    
    function getTroveStake(bytes32 _cdpId) external view returns (uint);

    function getTroveDebt(bytes32 _cdpId) external view returns (uint);

    function getTroveColl(bytes32 _cdpId) external view returns (uint);

    function setTroveStatus(bytes32 _cdpId, uint num) external;

    function increaseTroveColl(bytes32 _cdpId, uint _collIncrease) external returns (uint);

    function decreaseTroveColl(bytes32 _cdpId, uint _collDecrease) external returns (uint); 

    function increaseTroveDebt(bytes32 _cdpId, uint _debtIncrease) external returns (uint); 

    function decreaseTroveDebt(bytes32 _cdpId, uint _collDecrease) external returns (uint); 

    function getTCR(uint _price) external view returns (uint);

    function checkRecoveryMode(uint _price) external view returns (bool);
}
