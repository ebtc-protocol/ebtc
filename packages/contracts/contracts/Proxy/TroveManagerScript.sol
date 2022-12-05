// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "../Dependencies/CheckContract.sol";
import "../Interfaces/ITroveManager.sol";


contract TroveManagerScript is CheckContract {
    string constant public NAME = "TroveManagerScript";

    ITroveManager immutable cdpManager;

    constructor(ITroveManager _cdpManager) public {
        checkContract(address(_cdpManager));
        cdpManager = _cdpManager;
    }

    function redeemCollateral(
        uint _EBTCAmount,
        bytes32 _firstRedemptionHint,
        bytes32 _upperPartialRedemptionHint,
        bytes32 _lowerPartialRedemptionHint,
        uint _partialRedemptionHintNICR,
        uint _maxIterations,
        uint _maxFee
    ) external returns (uint) {
        cdpManager.redeemCollateral(
            _EBTCAmount,
            _firstRedemptionHint,
            _upperPartialRedemptionHint,
            _lowerPartialRedemptionHint,
            _partialRedemptionHintNICR,
            _maxIterations,
            _maxFee
        );
    }
}
