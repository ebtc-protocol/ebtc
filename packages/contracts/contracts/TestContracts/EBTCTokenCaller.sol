// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "../Interfaces/IEBTCToken.sol";

contract EBTCTokenCaller {
    IEBTCToken EBTC;

    function setEBTC(IEBTCToken _EBTC) external {
        EBTC = _EBTC;
    }

    function ebtcMint(address _account, uint _amount) external {
        EBTC.mint(_account, _amount);
    }

    function ebtcBurn(address _account, uint _amount) external {
        EBTC.burn(_account, _amount);
    }

    function ebtcReturnFromPool(address _poolAddress, address _receiver, uint256 _amount) external {
        EBTC.returnFromPool(_poolAddress, _receiver, _amount);
    }
}
