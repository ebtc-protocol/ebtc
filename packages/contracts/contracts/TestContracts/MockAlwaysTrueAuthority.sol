// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

contract MockAlwaysTrueAuthority {
    function canCall(address user, address target, bytes4 functionSig) external view returns (bool) {
        return true;
    }
}
