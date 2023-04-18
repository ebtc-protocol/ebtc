// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../Dependencies/CheckContract.sol";
import "../Interfaces/IFeeRecipient.sol";

contract LQTYStakingScript is CheckContract {
    IFeeRecipient immutable FeeRecipient;

    constructor(address _feeRecipientAddress) public {
        checkContract(_feeRecipientAddress);
        FeeRecipient = IFeeRecipient(_feeRecipientAddress);
    }
}
