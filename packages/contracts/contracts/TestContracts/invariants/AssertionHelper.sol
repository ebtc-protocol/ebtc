pragma solidity 0.8.17;

import "@crytic/properties/contracts/util/PropertiesHelper.sol";

abstract contract AssertionHelper is PropertiesAsserts {
    function isApproximateEq(
        uint256 _num1,
        uint256 _num2,
        uint256 _tolerance
    ) internal pure returns (bool) {
        if (_num1 > _num2) {
            return _tolerance >= _num1 - _num2;
        } else {
            return _tolerance >= _num2 - _num1;
        }
    }

    // https://ethereum.stackexchange.com/a/83577
    function _getRevertMsg(bytes memory returnData) internal pure returns (string memory) {
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

    function assertRevertReasonEqual(
        bytes memory returnData,
        string memory reason
    ) internal returns (bool) {
        bool isEqual = _isRevertReasonEqual(returnData, reason);
        assertWithMsg(isEqual, reason);
    }

    function assertRevertReasonEqual(
        bytes memory returnData,
        string memory reason1,
        string memory reason2
    ) internal returns (bool) {
        bool isEqual = _isRevertReasonEqual(returnData, reason1) ||
            _isRevertReasonEqual(returnData, reason2);
        assertWithMsg(isEqual, string.concat(reason1, " OR ", reason2));
    }

    function assertRevertReasonEqual(
        bytes memory returnData,
        string memory reason1,
        string memory reason2,
        string memory reason3
    ) internal returns (bool) {
        bool isEqual = _isRevertReasonEqual(returnData, reason1) ||
            _isRevertReasonEqual(returnData, reason2) ||
            _isRevertReasonEqual(returnData, reason3);
        assertWithMsg(isEqual, string.concat(reason1, " OR ", reason2, " OR ", reason3));
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
