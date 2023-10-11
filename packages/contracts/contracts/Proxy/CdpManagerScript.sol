// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../Interfaces/ICdpManager.sol";

contract CdpManagerScript {
    string public constant NAME = "CdpManagerScript";

    ICdpManager immutable cdpManager;

    constructor(ICdpManager _cdpManager) public {
        cdpManager = _cdpManager;
    }

    function redeemCollateral(
        uint256 _EBTCAmount,
        bytes32 _firstRedemptionHint,
        bytes32 _upperPartialRedemptionHint,
        bytes32 _lowerPartialRedemptionHint,
        uint256 _partialRedemptionHintNICR,
        uint256 _maxIterations,
        uint256 _maxFee
    ) external returns (uint256) {
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
