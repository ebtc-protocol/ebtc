pragma solidity 0.8.17;

contract BytecodeReader {
    function getBytecodeAtAddress(address _address) public view returns (bytes memory) {
        bytes memory bytecode;
        assembly {
            // Get the size of the code at the specified address
            let codeSize := extcodesize(_address)

            // Allocate memory to store the bytecode
            bytecode := mload(0x40)

            // Update the free memory pointer
            mstore(0x40, add(bytecode, add(codeSize, 0x20)))

            // Store the size of the bytecode at the beginning of the memory
            mstore(bytecode, codeSize)

            // Retrieve the code and store it in memory
            extcodecopy(_address, add(bytecode, 0x20), 0, codeSize)
        }
        return bytecode;
    }
}
