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

    event SortedCdpsAddressChanged(address _sortedCdpsAddress);
    event CdpManagerAddressChanged(address _cdpManagerAddress);
    event CollateralAddressChanged(address _collTokenAddress);

    struct LocalVariables_getRedemptionHints {
        uint256 remainingEbtcToRedeem;
        uint256 minNetDebtInBTC;
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

        emit SortedCdpsAddressChanged(_sortedCdpsAddress);
        emit CdpManagerAddressChanged(_cdpManagerAddress);
        emit CollateralAddressChanged(_collateralAddress);
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
        uint256 _EBTCamount,
        uint256 _price,
        uint256 _maxIterations
    )
        external
        view
        returns (
            bytes32 firstRedemptionHint,
            uint256 partialRedemptionHintNICR,
            uint256 truncatedEBTCamount,
            uint256 partialRedemptionNewColl
        )
    {
        LocalVariables_getRedemptionHints memory vars;
        {
            vars.remainingEbtcToRedeem = _EBTCamount;
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
                vars.remainingEbtcToRedeem > 0 &&
                _maxIterations-- > 0
            ) {
                // Apply pending debt
                uint256 currentCdpDebt = cdpManager.getCdpDebt(vars.currentCdpId) +
                    cdpManager.getPendingRedistributedDebt(vars.currentCdpId);

                // If this CDP has more debt than the remaining to redeem, attempt a partial redemption
                if (currentCdpDebt > vars.remainingEbtcToRedeem) {
                    uint256 _cachedEbtcToRedeem = vars.remainingEbtcToRedeem;
                    (partialRedemptionNewColl, partialRedemptionHintNICR) = _calculatePartialRedeem(
                        vars,
                        currentCdpDebt,
                        _price
                    );

                    // If the partial redemption would leave the CDP with less than the minimum allowed coll, bail out of partial redemption and return only the fully redeemable
                    // TODO: This seems to return the original coll? why?
                    if (collateral.getPooledEthByShares(partialRedemptionNewColl) < MIN_NET_COLL) {
                        partialRedemptionHintNICR = 0; //reset to 0 as there is no partial redemption in this case
                        partialRedemptionNewColl = 0;
                        vars.remainingEbtcToRedeem = _cachedEbtcToRedeem;
                    } else {
                        vars.remainingEbtcToRedeem = 0;
                    }
                    break;
                } else {
                    vars.remainingEbtcToRedeem = vars.remainingEbtcToRedeem - currentCdpDebt;
                }

                vars.currentCdpId = sortedCdps.getPrev(vars.currentCdpId);
                vars.currentCdpUser = sortedCdps.getOwnerAddress(vars.currentCdpId);
            }
        }

        truncatedEBTCamount = _EBTCamount - vars.remainingEbtcToRedeem;
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
    function _calculatePartialRedeem(
        LocalVariables_getRedemptionHints memory vars,
        uint256 currentCdpDebt,
        uint256 _price
    ) internal view returns (uint256, uint256) {
        // maxReemable = min(remainingToRedeem, currentDebt)
        uint256 maxRedeemableEBTC = LiquityMath._min(vars.remainingEbtcToRedeem, currentCdpDebt);

        uint256 newColl;
        uint256 _oldIndex = cdpManager.stEthIndex();
        uint256 _newIndex = collateral.getPooledEthByShares(DECIMAL_PRECISION);

        if (_oldIndex < _newIndex) {
            newColl = _getCollateralWithSplitFeeApplied(vars.currentCdpId, _newIndex, _oldIndex);
        } else {
            (, newColl, ) = cdpManager.getDebtAndCollShares(vars.currentCdpId);
        }

        vars.remainingEbtcToRedeem = vars.remainingEbtcToRedeem - maxRedeemableEBTC;
        uint256 collToReceive = collateral.getSharesByPooledEth(
            (maxRedeemableEBTC * DECIMAL_PRECISION) / _price
        );

        uint256 _newCollAfter = newColl - collToReceive;
        return (
            _newCollAfter,
            LiquityMath._computeNominalCR(_newCollAfter, currentCdpDebt - maxRedeemableEBTC)
        );
    }

    /**
     * @notice Get the collateral amount of a CDP after applying split fee.
     * @dev This is an internal function used by _calculatePartialRedeem.
     * @param _cdpId The identifier of the CDP.
     * @param _newIndex The new index after the split fee is applied.
     * @param _oldIndex The old index before the split fee is applied.
     * @return newColl The new collateral amount after applying split fee.
     */
    function _getCollateralWithSplitFeeApplied(
        bytes32 _cdpId,
        uint256 _newIndex,
        uint256 _oldIndex
    ) internal view returns (uint256) {
        uint256 _deltaFeePerUnit;
        uint256 _newStFeePerUnit;
        uint256 _perUnitError;
        uint256 _feeTaken;

        (_feeTaken, _deltaFeePerUnit, _perUnitError) = cdpManager.calcFeeUponStakingReward(
            _newIndex,
            _oldIndex
        );
        _newStFeePerUnit = _deltaFeePerUnit + cdpManager.systemStEthFeePerUnitIndex();
        (, uint256 newColl) = cdpManager.getAccumulatedFeeSplitApplied(_cdpId, _newStFeePerUnit);
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
        uint256 _CR,
        uint256 _numTrials,
        uint256 _inputRandomSeed
    ) external view returns (bytes32 hint, uint256 diff, uint256 latestRandomSeed) {
        uint256 arrayLength = cdpManager.getActiveCdpsCount();

        if (arrayLength == 0) {
            return (sortedCdps.nonExistId(), 0, _inputRandomSeed);
        }

        hint = sortedCdps.getLast();
        diff = LiquityMath._getAbsoluteDifference(_CR, cdpManager.getNominalICR(hint));
        latestRandomSeed = _inputRandomSeed;

        uint256 i = 1;

        while (i < _numTrials) {
            latestRandomSeed = uint256(keccak256(abi.encodePacked(latestRandomSeed)));

            uint256 arrayIndex = latestRandomSeed % arrayLength;
            bytes32 _cId = cdpManager.getIdFromCdpIdsArray(arrayIndex);
            uint256 currentNICR = cdpManager.getNominalICR(_cId);

            // check if abs(current - CR) > abs(closest - CR), and update closest if current is closer
            uint256 currentDiff = LiquityMath._getAbsoluteDifference(currentNICR, _CR);

            if (currentDiff < diff) {
                diff = currentDiff;
                hint = _cId;
            }
            i++;
        }
    }

    /// @notice Compute nominal CR for a specified collateral and debt amount
    function computeNominalCR(uint256 _coll, uint256 _debt) external pure returns (uint256) {
        return LiquityMath._computeNominalCR(_coll, _debt);
    }

    /// @notice Compute CR for a specified collateral and debt amount
    function computeCR(uint256 _coll, uint256 _debt, uint256 _price) external pure returns (uint256) {
        return LiquityMath._computeCR(_coll, _debt, _price);
    }
}
