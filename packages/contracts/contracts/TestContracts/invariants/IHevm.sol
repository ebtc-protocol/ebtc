pragma solidity 0.8.17;

// https://hevm.dev/controlling-the-unit-testing-environment.html#cheat-codes
interface IHevm {
    // Sets the block timestamp to x.
    function warp(uint x) external;

    // Sets the block number to x.
    function roll(uint x) external;

    // Sets msg.sender to the specified sender for the next call.
    function prank(address sender) external;

    // Sets the slot loc of contract c to val.
    function store(address c, bytes32 loc, bytes32 val) external;

    // Reads the slot loc of contract c.
    function load(address c, bytes32 loc) external returns (bytes32 val);
}