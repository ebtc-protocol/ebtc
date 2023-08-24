// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.9.0;

/**
 * @dev String operations.
 */
library Strings {
    /**
     * @dev Converts a `uint256` to its ASCII `string` representation.
     */
    function toString(uint256 value) internal pure returns (string memory) {
        // Inspired by OraclizeAPI's implementation - MIT licence
        // https://github.com/oraclize/ethereum-api/blob/b42146b063c7d6ee1358846c198246239e9360e8/oraclizeAPI_0.4.25.sol

        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        uint256 index = digits - 1;
        temp = value;
        while (temp != 0) {
            buffer[index--] = bytes1(uint8(48 + (temp % 10)));
            temp /= 10;
        }
        return string(buffer);
    }

    function bytes32ToString(bytes32 _bytes) public pure returns (string memory) {
        bytes memory charset = "0123456789abcdef";
        bytes memory result = new bytes(64); // as each byte will be represented by 2 chars in hex

        for (uint256 i = 0; i < 32; i++) {
            result[i * 2] = charset[uint8(_bytes[i] >> 4)];
            result[i * 2 + 1] = charset[uint8(_bytes[i] & 0x0F)];
        }

        return string(result);
    }
}
