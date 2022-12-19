// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "../Dependencies/CheckContract.sol";
import "../Interfaces/IStabilityPool.sol";

contract StabilityPoolScript is CheckContract {
    string public constant NAME = "StabilityPoolScript";

    IStabilityPool immutable stabilityPool;

    constructor(IStabilityPool _stabilityPool) public {
        checkContract(address(_stabilityPool));
        stabilityPool = _stabilityPool;
    }

    function provideToSP(uint _amount, address _frontEndTag) external {
        stabilityPool.provideToSP(_amount, _frontEndTag);
    }

    function withdrawFromSP(uint _amount) external {
        stabilityPool.withdrawFromSP(_amount);
    }

    function withdrawETHGainToCdp(bytes32 _cdpId, bytes32 _upperHint, bytes32 _lowerHint) external {
        stabilityPool.withdrawETHGainToCdp(_cdpId, _upperHint, _lowerHint);
    }
}
