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

    function bytes32ToString(bytes32 _bytes32) public pure returns (string memory) {
        return _bytes32.bytes32ToString();
    }
}
