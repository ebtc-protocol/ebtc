// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./Interfaces/ICdpManager.sol";
import "./Interfaces/ISortedCdps.sol";
import "./Dependencies/LiquityBase.sol";

contract HintHelpers is LiquityBase {
    string public constant NAME = "HintHelpers";

    ISortedCdps public immutable sortedCdps;
    ICdpManager public immutable cdpManager;

    // --- Events ---

    struct LocalVariables_getRedemptionHints {
        uint remainingEBTCToRedeemToRedeem;
        uint minNetDebtInBTC;
        bytes32 currentCdpId;
        address currentCdpUser;
    }

    // --- Dependency setters ---
    constructor(
        address _sortedCdpsAddress,
        address _cdpManagerAddress,
        address _collateralAddress,
        address _activePoolAddress,
        address _priceFeedAddress
    ) LiquityBase(_activePoolAddress, _priceFeedAddress, _collateralAddress) {
        sortedCdps = ISortedCdps(_sortedCdpsAddress);
        cdpManager = ICdpManager(_cdpManagerAddress);
    }

    // --- Functions ---

    /**
     * @notice Get the redemption hints for the specified amount of eBTC, price and maximum number of iterations.
     * @param _EBTCamount The amount of eBTC to be redeemed.
     * @param _price The current price of the asset.
     * @param _maxIterations The maximum number of iterations to be performed.
     * @return firstRedemptionHint The identifier of the first CDP to be considered for redemption.
     * @return partialRedemptionHintNICR The new Nominal Collateral Ratio (NICR) of the CDP after partial redemption.
     * @return truncatedEBTCamount The actual amount of eBTC that can be redeemed.
     * @return partialRedemptionNewColl The new collateral amount after partial redemption.
     */
    function getRedemptionHints(
        uint _EBTCamount,
        uint _price,
        uint _maxIterations
    )
        external
        view
        returns (
            bytes32 firstRedemptionHint,
            uint partialRedemptionHintNICR,
            uint truncatedEBTCamount,
            uint partialRedemptionNewColl
        )
    {
        LocalVariables_getRedemptionHints memory vars;
        {
            vars.remainingEBTCToRedeemToRedeem = _EBTCamount;
            vars.currentCdpId = sortedCdps.getLast();
            vars.currentCdpUser = sortedCdps.getOwnerAddress(vars.currentCdpId);

            while (
                vars.currentCdpUser != address(0) &&
                cdpManager.getICR(vars.currentCdpId, _price) < MCR
            ) {
                vars.currentCdpId = sortedCdps.getPrev(vars.currentCdpId);
                vars.currentCdpUser = sortedCdps.getOwnerAddress(vars.currentCdpId);
            }
            firstRedemptionHint = vars.currentCdpId;
        }

        if (_maxIterations == 0) {
            _maxIterations = type(uint256).max;
        }

        // Underflow is intentionally used in _maxIterations-- > 0
        unchecked {
            while (
                vars.currentCdpUser != address(0) &&
                vars.remainingEBTCToRedeemToRedeem > 0 &&
                _maxIterations-- > 0
            ) {
                // Apply pending debt
                uint currentCdpDebt = cdpManager.getCdpDebt(vars.currentCdpId) +
                    cdpManager.getPendingDebtRedistribution(vars.currentCdpId);

                // If this CDP has more debt than the remaining to redeem, attempt a partial redemption
                if (currentCdpDebt > vars.remainingEBTCToRedeemToRedeem) {
                    uint _cachedEbtcToRedeem = vars.remainingEBTCToRedeemToRedeem;
                    (
                        partialRedemptionNewColl,
                        partialRedemptionHintNICR
                    ) = _calculateCdpStateAfterPartialRedemption(vars, currentCdpDebt, _price);

                    // If the partial redemption would leave the CDP with less than the minimum allowed coll, bail out of partial redemption and return only the fully redeemable
                    // TODO: This seems to return the original coll? why?
                    if (
                        collateral.getPooledEthByShares(partialRedemptionNewColl) <
                        MIN_CDP_STETH_BALANCE
                    ) {
                        partialRedemptionHintNICR = 0; //reset to 0 as there is no partial redemption in this case
                        partialRedemptionNewColl = 0;
                        vars.remainingEBTCToRedeemToRedeem = _cachedEbtcToRedeem;
                    } else {
                        vars.remainingEBTCToRedeemToRedeem = 0;
                    }
                    break;
                } else {
                    vars.remainingEBTCToRedeemToRedeem =
                        vars.remainingEBTCToRedeemToRedeem -
                        currentCdpDebt;
                }

                vars.currentCdpId = sortedCdps.getPrev(vars.currentCdpId);
                vars.currentCdpUser = sortedCdps.getOwnerAddress(vars.currentCdpId);
            }
        }

        truncatedEBTCamount = _EBTCamount - vars.remainingEBTCToRedeemToRedeem;
    }

    /**
     * @notice Calculate the partial redemption information.
     * @dev This is an internal function used by getRedemptionHints.
     * @param vars The local variables of the getRedemptionHints function.
     * @param currentCdpDebt The net eBTC debt of the CDP.
     * @param _price The current price of the asset.
     * @return newColl The new collateral amount after partial redemption.
     * @return newNICR The new Nominal Collateral Ratio (NICR) of the CDP after partial redemption.
     */
    function _calculateCdpStateAfterPartialRedemption(
        LocalVariables_getRedemptionHints memory vars,
        uint currentCdpDebt,
        uint _price
    ) internal view returns (uint, uint) {
        // maxReemable = min(remainingToRedeem, currentDebt)
        uint maxRedeemableEBTC = LiquityMath._min(
            vars.remainingEBTCToRedeemToRedeem,
            currentCdpDebt
        );

        uint newColl;
        uint _oldIndex = cdpManager.stEthIndex();
        uint _newIndex = collateral.getPooledEthByShares(DECIMAL_PRECISION);

        if (_oldIndex < _newIndex) {
            newColl = _getCollateralWithSplitFeeApplied(vars.currentCdpId, _newIndex, _oldIndex);
        } else {
            (, newColl, ) = cdpManager.getVirtualDebtAndColl(vars.currentCdpId);
        }

        vars.remainingEBTCToRedeemToRedeem = vars.remainingEBTCToRedeemToRedeem - maxRedeemableEBTC;
        uint collToReceive = collateral.getSharesByPooledEth(
            (maxRedeemableEBTC * DECIMAL_PRECISION) / _price
        );

        uint _newCollAfter = newColl - collToReceive;
        return (
            _newCollAfter,
            LiquityMath._computeNominalCR(_newCollAfter, currentCdpDebt - maxRedeemableEBTC)
        );
    }

    /**
     * @notice Get the collateral amount of a CDP after applying split fee.
     * @dev This is an internal function used by _calculateCdpStateAfterPartialRedemption.
     * @param _cdpId The identifier of the CDP.
     * @param _newIndex The new index after the split fee is applied.
     * @param _oldIndex The old index before the split fee is applied.
     * @return newColl The new collateral amount after applying split fee.
     */
    function _getCollateralWithSplitFeeApplied(
        bytes32 _cdpId,
        uint _newIndex,
        uint _oldIndex
    ) internal view returns (uint) {
        uint _deltaFeePerUnit;
        uint _newStFeePerUnit;
        uint _perUnitError;
        uint _feeTaken;

        (_feeTaken, _deltaFeePerUnit, _perUnitError) = cdpManager.calcFeeUponStakingReward(
            _newIndex,
            _oldIndex
        );
        _newStFeePerUnit = _deltaFeePerUnit + cdpManager.stFeePerUnitg();
        (, uint newColl) = cdpManager.getAccumulatedFeeSplitApplied(_cdpId, _newStFeePerUnit);
        return newColl;
    }

    /* getApproxHint() - return address of a Cdp that is, on average, (length / numTrials) positions away in the 
    sortedCdps list from the correct insert position of the Cdp to be inserted. 
    
    Note: The output address is worst-case O(n) positions away from the correct insert position, however, the function 
    is probabilistic. Input can be tuned to guarantee results to a high degree of confidence, e.g:

    Submitting numTrials = k * sqrt(length), with k = 15 makes it very, very likely that the ouput address will 
    be <= sqrt(length) positions away from the correct insert position.
    */
    function getApproxHint(
        uint _CR,
        uint _numTrials,
        uint _inputRandomSeed
    ) external view returns (bytes32 hint, uint diff, uint latestRandomSeed) {
        uint arrayLength = cdpManager.getCdpIdsCount();

        if (arrayLength == 0) {
            return (sortedCdps.nonExistId(), 0, _inputRandomSeed);
        }

        hint = sortedCdps.getLast();
        diff = LiquityMath._getAbsoluteDifference(_CR, cdpManager.getNominalICR(hint));
        latestRandomSeed = _inputRandomSeed;

        uint i = 1;

        while (i < _numTrials) {
            latestRandomSeed = uint(keccak256(abi.encodePacked(latestRandomSeed)));

            uint arrayIndex = latestRandomSeed % arrayLength;
            bytes32 _cId = cdpManager.getIdFromCdpIdsArray(arrayIndex);
            uint currentNICR = cdpManager.getNominalICR(_cId);

            // check if abs(current - CR) > abs(closest - CR), and update closest if current is closer
            uint currentDiff = LiquityMath._getAbsoluteDifference(currentNICR, _CR);

            if (currentDiff < diff) {
                diff = currentDiff;
                hint = _cId;
            }
            i++;
        }
    }

    /// @notice Compute nominal CR for a specified collateral and debt amount
    function computeNominalCR(uint _coll, uint _debt) external pure returns (uint) {
        return LiquityMath._computeNominalCR(_coll, _debt);
    }

    /// @notice Compute CR for a specified collateral and debt amount
    function computeCR(uint _coll, uint _debt, uint _price) external pure returns (uint) {
        return LiquityMath._computeCR(_coll, _debt, _price);
    }
}
