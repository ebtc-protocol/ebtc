// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "../Dependencies/CheckContract.sol";
import "../Interfaces/ICdpManager.sol";

contract CdpManagerScript is CheckContract {
    string public constant NAME = "CdpManagerScript";

    ICdpManager immutable cdpManager;

    constructor(ICdpManager _cdpManager) public {
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
