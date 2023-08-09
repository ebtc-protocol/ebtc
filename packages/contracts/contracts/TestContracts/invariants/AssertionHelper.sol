pragma solidity 0.8.17;

abstract contract AssertionHelper {
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

    function diffPercent(uint256 _num1, uint256 _num2) internal pure returns (uint256) {
        if (_num1 == _num2) return 0;
        else if (_num1 > _num2) {
            return ((_num1 - _num2) * 1e18) / ((_num1 + _num2) / 2);
        } else {
            return ((_num2 - _num1) * 1e18) / ((_num1 + _num2) / 2);
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

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
