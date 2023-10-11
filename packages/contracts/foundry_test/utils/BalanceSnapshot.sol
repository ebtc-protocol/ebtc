// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.17;

import "../../contracts/Dependencies/IERC20.sol";

//common utilities for forge tests
contract BalanceSnapshot {
    mapping(address => mapping(address => uint)) public balances; // token -> account -> amount

    // Fetch and store all balances
    constructor(address[] memory tokens, address[] memory accounts) {
        for (uint i = 0; i < tokens.length; i++) {
            for (uint j = 0; j < accounts.length; j++) {
                address token = tokens[i];
                address account = accounts[j];
                balances[token][account] = IERC20(token).balanceOf(account);
            }
        }
    }

    function get(address token, address account) external view returns (uint) {
        return balances[token][account];
    }
}
