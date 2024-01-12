// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;
import "./Strings.sol";

contract LogUtils {
    using Strings for uint256;
    using Strings for bytes32;

    enum GlueType {
        None,
        Comma,
        Bar,
        Dot
    }

    // credit: https://ethereum.stackexchange.com/questions/118995/how-to-add-separative-commas-every-3-digits-in-solidity-to-an-input-integer
    function concat(
        string memory base,
        uint256 part,
        GlueType glueType
    ) internal pure returns (string memory) {
        string memory stringified = part.toString();
        string memory glue = ",";

        if (glueType == GlueType.None) glue = "";
        else if (glueType == GlueType.Bar) glue = "_";
        else if (glueType == GlueType.Dot) glue = ".";
        return string(abi.encodePacked(stringified, glue, base));
    }

    function format(uint256 source) public pure returns (string memory) {
        string memory result = "";
        uint128 index;

        while (source > 0) {
            uint256 part = source % 10; // get each digit

            GlueType glueType = GlueType.None;

            if (index != 0 && index % 3 == 0 && index % 18 != 0)
                glueType = GlueType.Comma; // if we're passed another set of 3 digits, request set glue
            else if (index != 0 && index % 18 == 0) glueType = GlueType.Bar;

            result = concat(result, part, glueType);
            source = source / 10;
            index += 1;
        }

        return result;
    }

    function parseNode(bytes32 node) public pure returns (address, uint256) {
        bytes20 addressPart;
        uint256 numberPart;

        // Extract the first 20 bytes for the address
        assembly {
            addressPart := and(
                node,
                0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF000000000000000000000000
            )
        }

        // Extract the remaining 12 bytes for the uint256
        assembly {
            numberPart := and(
                node,
                0x000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
            )
        }

        return (address(addressPart), numberPart);
    }

    function bytes32ToString(bytes32 data) public pure returns (string memory result) {
        bytes memory temp = new bytes(65);
        uint256 count;

        for (uint256 i = 0; i < 32; i++) {
            bytes1 currentByte = bytes1(data << (i * 8));

            uint8 c1 = uint8(bytes1((currentByte << 4) >> 4));

            uint8 c2 = uint8(bytes1((currentByte >> 4)));

            if (c2 >= 0 && c2 <= 9) temp[++count] = bytes1(c2 + 48);
            else temp[++count] = bytes1(c2 + 87);

            if (c1 >= 0 && c1 <= 9) temp[++count] = bytes1(c1 + 48);
            else temp[++count] = bytes1(c1 + 87);
        }

        result = string(temp);
    }
}
