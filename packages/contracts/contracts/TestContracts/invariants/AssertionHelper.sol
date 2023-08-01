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
}
