// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "./Interfaces/ITroveManager.sol";
import "./Interfaces/ISortedTroves.sol";
import "./Dependencies/LiquityBase.sol";
import "./Dependencies/Ownable.sol";
import "./Dependencies/CheckContract.sol";

contract HintHelpers is LiquityBase, Ownable, CheckContract {
    string constant public NAME = "HintHelpers";

    ISortedTroves public sortedTroves;
    ITroveManager public cdpManager;

    // --- Events ---

    event SortedTrovesAddressChanged(address _sortedTrovesAddress);
    event TroveManagerAddressChanged(address _cdpManagerAddress);

    // --- Dependency setters ---

    function setAddresses(
        address _sortedTrovesAddress,
        address _cdpManagerAddress
    )
        external
        onlyOwner
    {
        checkContract(_sortedTrovesAddress);
        checkContract(_cdpManagerAddress);

        sortedTroves = ISortedTroves(_sortedTrovesAddress);
        cdpManager = ITroveManager(_cdpManagerAddress);

        emit SortedTrovesAddressChanged(_sortedTrovesAddress);
        emit TroveManagerAddressChanged(_cdpManagerAddress);

        _renounceOwnership();
    }

    // --- Functions ---

    /* getRedemptionHints() - Helper function for finding the right hints to pass to redeemCollateral().
     *
     * It simulates a redemption of `_EBTCamount` to figure out where the redemption sequence will start and what state the final Trove
     * of the sequence will end up in.
     *
     * Returns three hints:
     *  - `firstRedemptionHint` is the address of the first Trove with ICR >= MCR (i.e. the first Trove that will be redeemed).
     *  - `partialRedemptionHintNICR` is the final nominal ICR of the last Trove of the sequence after being hit by partial redemption,
     *     or zero in case of no partial redemption.
     *  - `truncatedEBTCamount` is the maximum amount that can be redeemed out of the the provided `_EBTCamount`. This can be lower than
     *    `_EBTCamount` when redeeming the full amount would leave the last Trove of the redemption sequence with less net debt than the
     *    minimum allowed value (i.e. MIN_NET_DEBT).
     *
     * The number of Troves to consider for redemption can be capped by passing a non-zero value as `_maxIterations`, while passing zero
     * will leave it uncapped.
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
            uint truncatedEBTCamount
        )
    {
        ISortedTroves sortedTrovesCached = sortedTroves;

        uint remainingEBTC = _EBTCamount;
        bytes32 currentTroveId = sortedTrovesCached.getLast();
        address currentTroveuser = sortedTroves.existTroveOwners(currentTroveId);

        while (currentTroveuser != address(0) && cdpManager.getCurrentICR(currentTroveId, _price) < MCR) {
            currentTroveId = sortedTrovesCached.getPrev(currentTroveId);
            currentTroveuser = sortedTrovesCached.existTroveOwners(currentTroveId);
        }

        firstRedemptionHint = currentTroveId;

        if (_maxIterations == 0) {
            _maxIterations = uint(-1);
        }

        while (currentTroveuser != address(0) && remainingEBTC > 0 && _maxIterations-- > 0) {
            uint netEBTCDebt = _getNetDebt(cdpManager.getTroveDebt(currentTroveId)).add(cdpManager.getPendingEBTCDebtReward(currentTroveId));

            if (netEBTCDebt > remainingEBTC) {
                if (netEBTCDebt > MIN_NET_DEBT) {
                    uint maxRedeemableEBTC = LiquityMath._min(remainingEBTC, netEBTCDebt.sub(MIN_NET_DEBT));

                    uint ETH = cdpManager.getTroveColl(currentTroveId).add(cdpManager.getPendingETHReward(currentTroveId));

                    uint newColl = ETH.sub(maxRedeemableEBTC.mul(DECIMAL_PRECISION).div(_price));
                    uint newDebt = netEBTCDebt.sub(maxRedeemableEBTC);

                    uint compositeDebt = _getCompositeDebt(newDebt);
                    partialRedemptionHintNICR = LiquityMath._computeNominalCR(newColl, compositeDebt);

                    remainingEBTC = remainingEBTC.sub(maxRedeemableEBTC);
                }
                break;
            } else {
                remainingEBTC = remainingEBTC.sub(netEBTCDebt);
            }

            currentTroveId = sortedTrovesCached.getPrev(currentTroveId);
            currentTroveuser = sortedTrovesCached.existTroveOwners(currentTroveId);
        }

        truncatedEBTCamount = _EBTCamount.sub(remainingEBTC);
    }

    /* getApproxHint() - return address of a Trove that is, on average, (length / numTrials) positions away in the 
    sortedTroves list from the correct insert position of the Trove to be inserted. 
    
    Note: The output address is worst-case O(n) positions away from the correct insert position, however, the function 
    is probabilistic. Input can be tuned to guarantee results to a high degree of confidence, e.g:

    Submitting numTrials = k * sqrt(length), with k = 15 makes it very, very likely that the ouput address will 
    be <= sqrt(length) positions away from the correct insert position.
    */
    function getApproxHint(uint _CR, uint _numTrials, uint _inputRandomSeed)
        external
        view
        returns (bytes32 hint, uint diff, uint latestRandomSeed)
    {
        uint arrayLength = cdpManager.getTroveIdsCount();

        if (arrayLength == 0) {
            return (sortedTroves.nonExistId(), 0, _inputRandomSeed);
        }

        hint = sortedTroves.getLast();
        diff = LiquityMath._getAbsoluteDifference(_CR, cdpManager.getNominalICR(hint));
        latestRandomSeed = _inputRandomSeed;

        uint i = 1;

        while (i < _numTrials) {
            latestRandomSeed = uint(keccak256(abi.encodePacked(latestRandomSeed)));

            uint arrayIndex = latestRandomSeed % arrayLength;
            bytes32 _cId = cdpManager.getIdFromTroveIdsArray(arrayIndex);
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

    function computeNominalCR(uint _coll, uint _debt) external pure returns (uint) {
        return LiquityMath._computeNominalCR(_coll, _debt);
    }

    function computeCR(uint _coll, uint _debt, uint _price) external pure returns (uint) {
        return LiquityMath._computeCR(_coll, _debt, _price);
    }
}
