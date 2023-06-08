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

    function computeICR(uint _coll, uint _debt, uint _price) external pure returns (uint) {
        return LiquityMath._computeCR(_coll, _debt, _price);
    }

    function getCollGasCompensation(uint _coll) external pure returns (uint) {
        return _getCollGasCompensation(_coll);
    }

    function unprotectedDecayBaseRateFromBorrowing() external returns (uint) {
        baseRate = _calcDecayedBaseRate();
        assert(baseRate >= 0 && baseRate <= DECIMAL_PRECISION);

        _updateLastFeeOpTime();
        return baseRate;
    }

    function minutesPassedSinceLastFeeOp() external view returns (uint) {
        return _minutesPassedSinceLastFeeOp();
    }

    function setLastFeeOpTimeToNow() external {
        lastFeeOperationTime = block.timestamp;
    }

    function getDecayedBaseRate() external view returns (uint) {
        uint minutesPassed = _minutesPassedSinceLastFeeOp();
        uint _mulFactor = LiquityMath._decPow(minuteDecayFactor, minutesPassed);
        return (baseRate * _mulFactor) / DECIMAL_PRECISION;
    }

    function setBaseRate(uint _baseRate) external {
        baseRate = _baseRate;
    }

    /// @dev No more concept of composite debt. Just return debt. Maintaining for test compatiblity
    function getActualDebtFromComposite(uint _debtVal) external pure returns (uint) {
        return _debtVal;
    }

    function someFunc1() external requiresAuth {
        emit SomeFunc1Called(msg.sender);
    }

    function getUpdatedBaseRateFromRedemption(
        uint _ETHDrawn,
        uint _price
    ) external view returns (uint) {
        uint _totalEBTCSupply = _getEntireSystemDebt();
        uint decayedBaseRate = _calcDecayedBaseRate();
        uint redeemedEBTCFraction = (collateral.getPooledEthByShares(_ETHDrawn) * _price) /
            _totalEBTCSupply;
        uint newBaseRate = decayedBaseRate + (redeemedEBTCFraction / beta);
        return LiquityMath._min(newBaseRate, DECIMAL_PRECISION); // cap baseRate at a maximum of 100%
    }

    function activePoolIncreaseEBTCDebt(uint _amount) external {
        activePool.increaseEBTCDebt(_amount);
    }

    function activePoolDecreaseEBTCDebt(uint _amount) external {
        activePool.decreaseEBTCDebt(_amount);
    }

    function activePoolSendStEthColl(address _addr, uint _amt) external {
        activePool.sendStEthColl(_addr, _amt);
    }

    function sortedCdpsBatchRemove(bytes32[] memory _cdpIds) external {
        sortedCdps.batchRemove(_cdpIds);
    }

    function forward(address _dest, bytes calldata _data) external payable {
        (bool success, bytes memory returnData) = _dest.call{value: msg.value}(_data);
        require(success, string(returnData));
    }

    //    function callInternalRemoveCdpOwner(address _cdpOwner) external {
    //        uint cdpOwnersArrayLength = CdpOwners.length;
    //        _removeCdpOwner(_cdpOwner, cdpOwnersArrayLength);
    //    }
}
