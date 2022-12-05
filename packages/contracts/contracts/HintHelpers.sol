// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "./Interfaces/ICdpManager.sol";
import "./Interfaces/ISortedCdps.sol";
import "./Dependencies/LiquityBase.sol";
import "./Dependencies/Ownable.sol";
import "./Dependencies/CheckContract.sol";

contract HintHelpers is LiquityBase, Ownable, CheckContract {
    string constant public NAME = "HintHelpers";

    ISortedCdps public sortedCdps;
    ICdpManager public cdpManager;

    // --- Events ---

    event SortedCdpsAddressChanged(address _sortedCdpsAddress);
    event CdpManagerAddressChanged(address _cdpManagerAddress);

    // --- Dependency setters ---

    function setAddresses(
        address _sortedCdpsAddress,
        address _cdpManagerAddress
    )
        external
        onlyOwner
    {
        checkContract(_sortedCdpsAddress);
        checkContract(_cdpManagerAddress);

        sortedCdps = ISortedCdps(_sortedCdpsAddress);
        cdpManager = ICdpManager(_cdpManagerAddress);

        emit SortedCdpsAddressChanged(_sortedCdpsAddress);
        emit CdpManagerAddressChanged(_cdpManagerAddress);

        _renounceOwnership();
    }

    // --- Functions ---

    /* getRedemptionHints() - Helper function for finding the right hints to pass to redeemCollateral().
     *
     * It simulates a redemption of `_EBTCamount` to figure out where the redemption sequence will start and what state the final Cdp
     * of the sequence will end up in.
     *
     * Returns three hints:
     *  - `firstRedemptionHint` is the address of the first Cdp with ICR >= MCR (i.e. the first Cdp that will be redeemed).
     *  - `partialRedemptionHintNICR` is the final nominal ICR of the last Cdp of the sequence after being hit by partial redemption,
     *     or zero in case of no partial redemption.
     *  - `truncatedEBTCamount` is the maximum amount that can be redeemed out of the the provided `_EBTCamount`. This can be lower than
     *    `_EBTCamount` when redeeming the full amount would leave the last Cdp of the redemption sequence with less net debt than the
     *    minimum allowed value (i.e. MIN_NET_DEBT).
     *
     * The number of Cdps to consider for redemption can be capped by passing a non-zero value as `_maxIterations`, while passing zero
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
        ISortedCdps sortedCdpsCached = sortedCdps;

        uint remainingEBTC = _EBTCamount;
        bytes32 currentCdpId = sortedCdpsCached.getLast();
        address currentCdpuser = sortedCdps.existCdpOwners(currentCdpId);

        while (currentCdpuser != address(0) && cdpManager.getCurrentICR(currentCdpId, _price) < MCR) {
            currentCdpId = sortedCdpsCached.getPrev(currentCdpId);
            currentCdpuser = sortedCdpsCached.existCdpOwners(currentCdpId);
        }

        firstRedemptionHint = currentCdpId;

        if (_maxIterations == 0) {
            _maxIterations = uint(-1);
        }

        while (currentCdpuser != address(0) && remainingEBTC > 0 && _maxIterations-- > 0) {
            uint netEBTCDebt = _getNetDebt(cdpManager.getCdpDebt(currentCdpId)).add(cdpManager.getPendingEBTCDebtReward(currentCdpId));

            if (netEBTCDebt > remainingEBTC) {
                if (netEBTCDebt > MIN_NET_DEBT) {
                    uint maxRedeemableEBTC = LiquityMath._min(remainingEBTC, netEBTCDebt.sub(MIN_NET_DEBT));

                    uint ETH = cdpManager.getCdpColl(currentCdpId).add(cdpManager.getPendingETHReward(currentCdpId));

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

            currentCdpId = sortedCdpsCached.getPrev(currentCdpId);
            currentCdpuser = sortedCdpsCached.existCdpOwners(currentCdpId);
        }

        truncatedEBTCamount = _EBTCamount.sub(remainingEBTC);
    }

    /* getApproxHint() - return address of a Cdp that is, on average, (length / numTrials) positions away in the 
    sortedCdps list from the correct insert position of the Cdp to be inserted. 
    
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

    function computeNominalCR(uint _coll, uint _debt) external pure returns (uint) {
        return LiquityMath._computeNominalCR(_coll, _debt);
    }

    function computeCR(uint _coll, uint _debt, uint _price) external pure returns (uint) {
        return LiquityMath._computeCR(_coll, _debt, _price);
    }
}
