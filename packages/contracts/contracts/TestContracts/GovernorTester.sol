// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;
pragma experimental ABIEncoderV2;

import "../Governor.sol";

contract GovernorTester is Governor {
    bytes4 public constant FUNC_SIG1 = bytes4(keccak256(bytes("someFunc1()")));

    event OwnerSet(address _owner);

    constructor(address _owner) public Governor(_owner) {
        emit OwnerSet(_owner);
    }

    function someFunc1() external {
        require(
            isAuthorized(msg.sender, FUNC_SIG1),
            "GovernorTester: sender not authorized for this function"
        );
    }
}
