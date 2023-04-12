// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "./Interfaces/ICdpManager.sol";
import "./Interfaces/ISortedCdps.sol";
import "./Dependencies/LiquityBase.sol";
import "./Dependencies/Ownable.sol";
import "./Dependencies/CheckContract.sol";

contract HintHelpers is LiquityBase, Ownable, CheckContract {
    string public constant NAME = "HintHelpers";

    ISortedCdps public sortedCdps;
    ICdpManager public cdpManager;

    // --- Events ---

    event SortedCdpsAddressChanged(address _sortedCdpsAddress);
    event CdpManagerAddressChanged(address _cdpManagerAddress);
    event CollateralAddressChanged(address _collTokenAddress);

    struct LocalVariables_getRedemptionHints {
        uint remainingEBTC;
        uint minNetDebtInBTC;
        bytes32 currentCdpId;
        address currentCdpuser;
    }

    // --- Dependency setters ---
    function setAddresses(
        address _sortedCdpsAddress,
        address _cdpManagerAddress,
        address _collateralAddress
    ) external onlyOwner {
        checkContract(_sortedCdpsAddress);
        checkContract(_cdpManagerAddress);
        checkContract(_collateralAddress);

        sortedCdps = ISortedCdps(_sortedCdpsAddress);
        cdpManager = ICdpManager(_cdpManagerAddress);
        collateral = ICollateralToken(_collateralAddress);

        emit SortedCdpsAddressChanged(_sortedCdpsAddress);
        emit CdpManagerAddressChanged(_cdpManagerAddress);
        emit CollateralAddressChanged(_collateralAddress);

        renounceOwnership();
    }

    // --- Functions ---


     /*
        @notice Helper function for finding the right hints to pass to redeemCollateral().
        @dev It simulates a redemption of `_EBTCamount` to figure out where the redemption sequence will start and what state the final Cdp of the sequence will end up in.
        @param _EBTCamount The amount of EBTC to redeem.
        @param _price The assumed price value for eBTC/stETH.
        @param _maxIterations The number of Cdps to consider for redemption can be capped by passing a non-zero value as `_maxIterations`, while passing zero will leave it uncapped.
        @return firstRedemptionHint The address of the first Cdp with ICR >= MCR (i.e. the first Cdp that will be redeemed).
        @return partialRedemptionHintNICR The final nominal ICR of the last Cdp of the sequence after being hit by partial redemption, or zero in case of no partial redemption.
        @return truncatedEBTCamount The maximum amount that can be redeemed out of the the provided `_EBTCamount`. This can be lower than `_EBTCamount` when redeeming the full amount would leave the last Cdp of the redemption sequence with less net debt than the minimum allowed value (i.e. MIN_NET_DEBT).
        @return partialRedemptionNewColl The amount of collateral that will be left in the last Cdp of the sequence after being hit by partial redemption, or zero in case of no partial redemption.
     **/
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
        ISortedCdps sortedCdpsCached = sortedCdps;
        LocalVariables_getRedemptionHints memory vars;
        {
            vars.remainingEBTC = _EBTCamount;
            // Find out minimal debt value denominated in ETH
            vars.minNetDebtInBTC = _convertDebtDenominationToBtc(MIN_NET_DEBT, _price);
            vars.currentCdpId = sortedCdpsCached.getLast();
            vars.currentCdpuser = sortedCdpsCached.getOwnerAddress(vars.currentCdpId);

            while (
                vars.currentCdpuser != address(0) &&
                cdpManager.getCurrentICR(vars.currentCdpId, _price) < MCR
            ) {
                vars.currentCdpId = sortedCdpsCached.getPrev(vars.currentCdpId);
                vars.currentCdpuser = sortedCdpsCached.getOwnerAddress(vars.currentCdpId);
            }
            firstRedemptionHint = vars.currentCdpId;
        }

        if (_maxIterations == 0) {
            _maxIterations = type(uint256).max;
        }

        // Underflow is intentionally used in _maxIterations-- > 0
        unchecked {
        while (vars.currentCdpuser != address(0) && vars.remainingEBTC > 0 && _maxIterations-- > 0) {
            uint pendingEBTC;
            {
                uint pendingEBTCDebtReward = cdpManager.getPendingEBTCDebtReward(vars.currentCdpId);
                pendingEBTC = pendingEBTCDebtReward;
            }

            uint netEBTCDebt = pendingEBTC + _getNetDebt(cdpManager.getCdpDebt(vars.currentCdpId));

            if (netEBTCDebt > vars.remainingEBTC) {
                if (netEBTCDebt > vars.minNetDebtInBTC) {
                    (partialRedemptionNewColl, partialRedemptionHintNICR) = _calculatePartialRedeem(
                        vars,
                        netEBTCDebt,
                        _price
                    );
                }
                break;
            } else {
                vars.remainingEBTC = vars.remainingEBTC - netEBTCDebt;
            }

            vars.currentCdpId = sortedCdpsCached.getPrev(vars.currentCdpId);
            vars.currentCdpuser = sortedCdpsCached.getOwnerAddress(vars.currentCdpId);
        }
        }

        truncatedEBTCamount = _EBTCamount - vars.remainingEBTC;
    }

    function _calculatePartialRedeem(
        LocalVariables_getRedemptionHints memory vars,
        uint netEBTCDebt,
        uint _price
    ) internal view returns (uint, uint) {
        uint maxRedeemableEBTC = LiquityMath._min(
            vars.remainingEBTC,
            (netEBTCDebt - vars.minNetDebtInBTC)
        );

        uint ETH;
        uint _oldIndex = cdpManager.stFPPSg();
        uint _newIndex = collateral.getPooledEthByShares(1e18);

        if (_oldIndex < _newIndex) {
            ETH = _getCollateralWithSplitFeeApplied(vars.currentCdpId, _newIndex, _oldIndex);
        } else {
            (, ETH, , ) = cdpManager.getEntireDebtAndColl(vars.currentCdpId);
        }

        vars.remainingEBTC = vars.remainingEBTC - maxRedeemableEBTC;
        return (
            ETH,
            LiquityMath._computeNominalCR(
                (ETH -
                    collateral.getSharesByPooledEth(
                        (maxRedeemableEBTC * DECIMAL_PRECISION) / _price
                    )),
                _getCompositeDebt(netEBTCDebt - maxRedeemableEBTC)
            )
        );
    }

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
        (, uint ETH) = cdpManager.getAccumulatedFeeSplitApplied(
            _cdpId,
            _newStFeePerUnit,
            _perUnitError,
            cdpManager.totalStakes()
        );
        return ETH;
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

    function computeNominalCR(uint _coll, uint _debt) external pure returns (uint) {
        return LiquityMath._computeNominalCR(_coll, _debt);
    }

    function computeCR(uint _coll, uint _debt, uint _price) external pure returns (uint) {
        return LiquityMath._computeCR(_coll, _debt, _price);
    }
}
