pragma solidity 0.8.17;

abstract contract Asserts {
    event L1(uint256);
    event L2(uint256, uint256);
    event L3(uint256, uint256, uint256);
    event L4(uint256, uint256, uint256, uint256);

    function gt(uint256 a, uint256 b, string memory reason) internal virtual;

    function gte(uint256 a, uint256 b, string memory reason) internal virtual;

    function lt(uint256 a, uint256 b, string memory reason) internal virtual;

    function lte(uint256 a, uint256 b, string memory reason) internal virtual;

    function eq(uint256 a, uint256 b, string memory reason) internal virtual;

    function t(bool b, string memory reason) internal virtual;

    function between(uint256 value, uint256 low, uint256 high) internal virtual returns (uint256);

    function isApproximateEq(
        uint256 _num1,
        uint256 _num2,
        uint256 _tolerance
    ) internal pure returns (bool) {
        return diffPercent(_num1, _num2) <= _tolerance;
    }

    function diffPercent(uint256 _num1, uint256 _num2) internal pure returns (uint256) {
        if (_num1 == _num2) return 0;
        else if (_num1 > _num2) {
            return ((_num1 - _num2) * 1e18) / ((_num1 + _num2) / 2);
        } else {
            return ((_num2 - _num1) * 1e18) / ((_num1 + _num2) / 2);
        }
    }

    /// @dev compare absoulte value
    function _assertApproximateEq(
        uint256 _num1,
        uint256 _num2,
        uint256 _tolerance
    ) internal pure returns (bool) {
        if (_num1 > _num2) {
            return _tolerance >= (_num1 - _num2);
        } else {
            return _tolerance >= (_num2 - _num1);
        }
    }

    // https://ethereum.stackexchange.com/a/83577
    function _getRevertMsg(bytes memory returnData) internal pure returns (string memory) {
        // Check that the data has the right size: 4 bytes for signature + 32 bytes for panic code
        if (returnData.length == 4 + 32) {
            // Check that the data starts with the Panic signature
            bytes4 panicSignature = bytes4(keccak256(bytes("Panic(uint256)")));
            for (uint i = 0; i < 4; i++) {
                if (returnData[i] != panicSignature[i]) return "Undefined signature";
            }

            uint256 panicCode;
            for (uint i = 4; i < 36; i++) {
                panicCode = panicCode << 8;
                panicCode |= uint8(returnData[i]);
            }

            // Now convert the panic code into its string representation
            if (panicCode == 17) {
                return "Panic(17)";
            }

            // Add other panic codes as needed or return a generic "Unknown panic"
            return "Undefined panic code";
        }

        // If the returnData length is less than 68, then the transaction failed silently (without a revert message)
        if (returnData.length < 68) return "Transaction reverted silently";

        assembly {
            // Slice the sighash.
            returnData := add(returnData, 0x04)
        }
        return abi.decode(returnData, (string)); // All that remains is the revert string
    }

    function _isRevertReasonEqual(
        bytes memory returnData,
        string memory reason
    ) internal pure returns (bool) {
        return (keccak256(abi.encodePacked(_getRevertMsg(returnData))) ==
            keccak256(abi.encodePacked(reason)));
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function assertRevertReasonNotEqual(bytes memory returnData, string memory reason) internal {
        bool isEqual = _isRevertReasonEqual(returnData, reason);
        t(!isEqual, reason);
    }

    function assertRevertReasonEqual(bytes memory returnData, string memory reason) internal {
        bool isEqual = _isRevertReasonEqual(returnData, reason);
        t(isEqual, reason);
    }

    function assertRevertReasonEqual(
        bytes memory returnData,
        string memory reason1,
        string memory reason2
    ) internal {
        bool isEqual = _isRevertReasonEqual(returnData, reason1) ||
            _isRevertReasonEqual(returnData, reason2);
        t(isEqual, string.concat(reason1, " OR ", reason2));
    }

    function assertRevertReasonEqual(
        bytes memory returnData,
        string memory reason1,
        string memory reason2,
        string memory reason3
    ) internal {
        bool isEqual = _isRevertReasonEqual(returnData, reason1) ||
            _isRevertReasonEqual(returnData, reason2) ||
            _isRevertReasonEqual(returnData, reason3);
        t(isEqual, string.concat(reason1, " OR ", reason2, " OR ", reason3));
    }

    function assertRevertReasonEqual(
        bytes memory returnData,
        string memory reason1,
        string memory reason2,
        string memory reason3,
        string memory reason4
    ) internal {
        bool isEqual = _isRevertReasonEqual(returnData, reason1) ||
            _isRevertReasonEqual(returnData, reason2) ||
            _isRevertReasonEqual(returnData, reason3) ||
            _isRevertReasonEqual(returnData, reason4);
        t(isEqual, string.concat(reason1, " OR ", reason2, " OR ", reason3, " OR ", reason4));
    }
}
