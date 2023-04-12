// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

/**
 * The purpose of this contract is to hold EBTC tokens for gas compensation:
 * https://github.com/liquity/dev#gas-compensation
 * When a borrower opens a cdp, an additional 50 EBTC debt is issued,
 * and 50 EBTC is minted and sent to this contract.
 * When a borrower closes their active cdp, this gas compensation is refunded:
 * 50 EBTC is burned from the this contract's balance, and the corresponding
 * 50 EBTC debt on the cdp is cancelled.
 * See this issue for more context: https://github.com/liquity/dev/issues/186
 */
contract GasPool {
    // do nothing, as the core contracts have permission to send to and burn from this address
}
