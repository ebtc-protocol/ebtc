// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./Interfaces/ICdpManager.sol";
import "./Interfaces/ISortedCdps.sol";
import "./Dependencies/EbtcBase.sol";

/// @title HintHelpers mainly serves to provide handy information to facilitate offchain integration like redemption bots.
/// @dev It is strongly recommended to use HintHelper for redemption purpose
contract HintHelpers is EbtcBase {
    string public constant NAME = "HintHelpers";

    ISortedCdps public immutable sortedCdps;
    ICdpManager public immutable cdpManager;

    // --- Events ---

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
    ) EbtcBase(_activePoolAddress, _priceFeedAddress, _collateralAddress) {
        sortedCdps = ISortedCdps(_sortedCdpsAddress);
        cdpManager = ICdpManager(_cdpManagerAddress);
    }

    // --- Functions ---

    /// @notice Get the redemption hints for the specified amount of eBTC, price and maximum number of iterations.
    /// @param _EBTCamount The amount of eBTC to be redeemed.
    /// @param _price The current price of the stETH:eBTC.
    /// @param _maxIterations The maximum number of iterations to be performed.
    /// @return firstRedemptionHint The identifier of the first CDP to be considered for redemption.
    /// @return partialRedemptionHintNICR The new Nominal Collateral Ratio (NICR) of the CDP after partial redemption.
    /// @return truncatedEBTCamount The actual amount of eBTC that can be redeemed.
    /// @return partialRedemptionNewColl The new collateral amount after partial redemption.
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
                cdpManager.getSyncedICR(vars.currentCdpId, _price) < MCR
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
                uint256 currentCdpDebt = cdpManager.getSyncedCdpDebt(vars.currentCdpId);

                // If this CDP has more debt than the remaining to redeem, attempt a partial redemption
                if (currentCdpDebt > vars.remainingEbtcToRedeem) {
                    uint256 _cachedEbtcToRedeem = vars.remainingEbtcToRedeem;
                    (
                        partialRedemptionNewColl,
                        partialRedemptionHintNICR
                    ) = _calculateCdpStateAfterPartialRedemption(vars, currentCdpDebt, _price);

                    // If the partial redemption would leave the CDP with less than the minimum allowed coll, bail out of partial redemption and return only the fully redeemable
                    if (
                        collateral.getPooledEthByShares(partialRedemptionNewColl) <
                        MIN_NET_STETH_BALANCE
                    ) {
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
     * @return newCollShare The new collateral share amount after partial redemption.
     * @return newNICR The new Nominal Collateral Ratio (NICR) of the CDP after partial redemption.
     */
    function _calculateCdpStateAfterPartialRedemption(
        LocalVariables_getRedemptionHints memory vars,
        uint256 currentCdpDebt,
        uint256 _price
    ) internal view returns (uint256, uint256) {
        // maxReemable = min(remainingToRedeem, currentDebt)
        uint256 maxRedeemableEBTC = EbtcMath._min(vars.remainingEbtcToRedeem, currentCdpDebt);

        uint256 newCollShare = cdpManager.getSyncedCdpCollShares(vars.currentCdpId);

        vars.remainingEbtcToRedeem = vars.remainingEbtcToRedeem - maxRedeemableEBTC;
        uint256 collShareToReceive = collateral.getSharesByPooledEth(
            (maxRedeemableEBTC * DECIMAL_PRECISION) / _price
        );

        uint256 _newCollShareAfter = newCollShare - collShareToReceive;
        return (
            _newCollShareAfter,
            EbtcMath._computeNominalCR(_newCollShareAfter, currentCdpDebt - maxRedeemableEBTC)
        );
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
        diff = EbtcMath._getAbsoluteDifference(_CR, cdpManager.getSyncedNominalICR(hint));
        latestRandomSeed = _inputRandomSeed;

        uint256 i = 1;
        bytes32[] memory cdpIds = sortedCdpsToArray();

        while (i < _numTrials) {
            latestRandomSeed = uint256(keccak256(abi.encodePacked(latestRandomSeed)));

            uint256 arrayIndex = latestRandomSeed % arrayLength;
            bytes32 _cId = cdpIds[arrayIndex];

            uint256 currentNICR = cdpManager.getSyncedNominalICR(_cId);

            // check if abs(current - CR) > abs(closest - CR), and update closest if current is closer
            uint256 currentDiff = EbtcMath._getAbsoluteDifference(currentNICR, _CR);

            if (currentDiff < diff) {
                diff = currentDiff;
                hint = _cId;
            }
            i++;
        }
    }

    function sortedCdpsToArray() public view returns (bytes32[] memory cdpIdArray) {
        uint256 size = sortedCdps.getSize();
        cdpIdArray = new bytes32[](size);

        if (size == 0) {
            // If the list is empty, return an empty array
            return cdpIdArray;
        }

        // Initialize the first CDP in the list
        bytes32 currentCdpId = sortedCdps.getFirst();

        for (uint256 i = 0; i < size; ++i) {
            // Add the current CDP to the array
            cdpIdArray[i] = currentCdpId;

            // Move to the next CDP in the list
            currentCdpId = sortedCdps.getNext(currentCdpId);
        }

        return cdpIdArray;
    }

    /// @notice Compute nominal CR for a specified collateral and debt amount
    /// @param _coll The collateral amount, in shares
    /// @param _debt The debt amount
    /// @return The computed nominal CR for the given collateral and debt
    function computeNominalCR(uint256 _coll, uint256 _debt) external pure returns (uint256) {
        return EbtcMath._computeNominalCR(_coll, _debt);
    }

    /// @notice Compute CR for a specified collateral, debt amount, and price
    /// @param _coll The collateral amount, in shares
    /// @param _debt The debt amount
    /// @param _price The current price
    /// @return The computed CR for the given parameters
    function computeCR(
        uint256 _coll,
        uint256 _debt,
        uint256 _price
    ) external pure returns (uint256) {
        return EbtcMath._computeCR(_coll, _debt, _price);
    }
}
