// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../Dependencies/IERC20.sol";
import "../Dependencies/IERC2612.sol";

interface IEBTCToken is IERC20, IERC2612 {
    // --- Events ---

    event CdpManagerAddressChanged(address _cdpManagerAddress);
    event BorrowerOperationsAddressChanged(address _newBorrowerOperationsAddress);

    event EBTCTokenBalanceUpdated(address _user, uint _amount);

    // --- Functions ---

    function mint(address _account, uint256 _amount) external;

    function burn(address _account, uint256 _amount) external;
}