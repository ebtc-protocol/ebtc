// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../Interfaces/IFeeRecipient.sol";

contract LQTYStakingScript {
    IFeeRecipient FeeRecipient;

    constructor(address _feeRecipientAddress) public {
        FeeRecipient = IFeeRecipient(_feeRecipientAddress);
    }
}
