// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../CdpManager.sol";

/* Tester contract inherits from CdpManager, and provides external functions 
for testing the parent's internal functions. */

contract CdpManagerTester is CdpManager {
    bytes4 public constant FUNC_SIG1 = bytes4(keccak256(bytes("someFunc1()")));
    bytes4 public constant FUNC_SIG_REDEMP_FLOOR =
        bytes4(keccak256(bytes("setRedemptionFeeFloor(uint256)")));
    bytes4 public constant FUNC_SIG_DECAY_FACTOR =
        bytes4(keccak256(bytes("setMinuteDecayFactor(uint256)")));
    event SomeFunc1Called(address _caller);

    constructor(
        address _liquidationLibraryAddress,
        address _authorityAddress,
        address _borrowerOperationsAddress,
        address _collSurplusPoolAddress,
        address _ebtcTokenAddress,
        address _sortedCdpsAddress,
        address _activePoolAddress,
        address _priceFeedAddress,
        address _collTokenAddress
    )
        CdpManager(
            _liquidationLibraryAddress,
            _authorityAddress,
            _borrowerOperationsAddress,
            _collSurplusPoolAddress,
            _ebtcTokenAddress,
            _sortedCdpsAddress,
            _activePoolAddress,
            _priceFeedAddress,
            _collTokenAddress
        )
    {}

    function computeICR(
        uint256 _coll,
        uint256 _debt,
        uint256 _price
    ) external pure returns (uint256) {
        return EbtcMath._computeCR(_coll, _debt, _price);
    }

    function getDeltaIndexToTriggerRM(
        uint256 _currentIndex,
        uint256 _price,
        uint256 _stakingRewardSplit
    ) external view returns (uint256) {
        uint256 _tcr = _getCachedTCR(_price);
        if (_tcr <= CCR) {
            return 0;
        } else if (_tcr == EbtcMath.MAX_TCR) {
            return type(uint256).max;
        } else {
            uint256 _splitIndex = (_currentIndex * MAX_REWARD_SPLIT) / _stakingRewardSplit;
            return (_splitIndex * (_tcr - CCR)) / _tcr;
        }
    }

    function unprotectedDecayBaseRateFromBorrowing() external returns (uint256) {
        baseRate = _calcDecayedBaseRate();
        assert(baseRate >= 0 && baseRate <= DECIMAL_PRECISION);

        _updateLastRedemptionTimestamp();
        return baseRate;
    }

    function minutesPassedSinceLastRedemption() external view returns (uint256) {
        return _minutesPassedSinceLastRedemption();
    }

    function unprotectedUpdateLastFeeOpTime() external {
        _updateLastRedemptionTimestamp();
    }

    function setLastFeeOpTimeToNow() external {
        lastRedemptionTimestamp = block.timestamp;
    }

    function getDecayedBaseRate() external view returns (uint256) {
        uint256 minutesPassed = _minutesPassedSinceLastRedemption();
        uint256 _mulFactor = EbtcMath._decPow(minuteDecayFactor, minutesPassed);
        return (baseRate * _mulFactor) / DECIMAL_PRECISION;
    }

    function setBaseRate(uint256 _baseRate) external {
        baseRate = _baseRate;
    }

    /// @dev No more concept of composite debt. Just return debt. Maintaining for test compatiblity
    function getActualDebtFromComposite(uint256 _debtVal) external pure returns (uint256) {
        return _debtVal;
    }

    function someFunc1() external requiresAuth {
        emit SomeFunc1Called(msg.sender);
    }

    function getUpdatedBaseRateFromRedemption(
        uint256 _ETHDrawn,
        uint256 _price
    ) external view returns (uint256) {
        return getUpdatedBaseRateFromRedemptionWithSystemDebt(_ETHDrawn, _price, _getSystemDebt());
    }

    function getUpdatedBaseRateFromRedemptionWithSystemDebt(
        uint256 _ETHDrawn,
        uint256 _price,
        uint256 _systemDebt
    ) public view returns (uint256) {
        uint256 _totalEBTCSupply = EbtcMath._min(_getSystemDebt(), _systemDebt);
        uint256 decayedBaseRate = _calcDecayedBaseRate();
        uint256 redeemedEBTCFraction = (collateral.getPooledEthByShares(_ETHDrawn) * _price) /
            _totalEBTCSupply;
        uint256 newBaseRate = decayedBaseRate + (redeemedEBTCFraction / beta);
        return EbtcMath._min(newBaseRate, DECIMAL_PRECISION); // cap baseRate at a maximum of 100%
    }

    function activePoolIncreaseSystemDebt(uint256 _amount) external {
        activePool.increaseSystemDebt(_amount);
    }

    function activePoolDecreaseSystemDebt(uint256 _amount) external {
        activePool.decreaseSystemDebt(_amount);
    }

    function activePoolTransferSystemCollShares(address _addr, uint256 _amt) external {
        activePool.transferSystemCollShares(_addr, _amt);
    }

    function sortedCdpsBatchRemove(bytes32[] memory _cdpIds) external {
        sortedCdps.batchRemove(_cdpIds);
    }

    function syncGracePeriod() external {
        _syncGracePeriod();
    }

    function forward(address _dest, bytes calldata _data) external payable {
        (bool success, bytes memory returnData) = _dest.call{value: msg.value}(_data);
        require(success, string(returnData));
    }

    //    function callInternalRemoveCdpOwner(address _cdpOwner) external {
    //        uint256 cdpOwnersArrayLength = CdpOwners.length;
    //        _removeCdpOwner(_cdpOwner, cdpOwnersArrayLength);
    //    }
}
