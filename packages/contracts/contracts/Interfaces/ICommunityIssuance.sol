// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

interface ICommunityIssuance {
    // --- Events ---

    event LQTYTokenAddressSet(address _lqtyTokenAddress);
    event TotalLQTYIssuedUpdated(uint _totalLQTYIssued);

    // --- Functions ---

    function setAddresses(address _lqtyTokenAddress) external;
}
