// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../FeeRecipient.sol";

contract LQTYStakingTester is FeeRecipient {
    constructor(
        address _ownerAddress,
        address _authorityAddress
    ) FeeRecipient(_ownerAddress, _authorityAddress) {}
}
