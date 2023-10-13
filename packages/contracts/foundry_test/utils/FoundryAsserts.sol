pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "../../contracts/TestContracts/invariants/Asserts.sol";

abstract contract FoundryAsserts is Test, Asserts {
    function gt(uint256 a, uint256 b, string memory message) internal override {
        assertGt(a, b, message);
    }

    function lt(uint256 a, uint256 b, string memory message) internal override {
        assertLt(a, b, message);
    }

    function gte(uint256 a, uint256 b, string memory message) internal override {
        assertGe(a, b, message);
    }

    function lte(uint256 a, uint256 b, string memory message) internal override {
        assertLe(a, b, message);
    }

    function eq(uint256 a, uint256 b, string memory message) internal override {
        assertEq(a, b, message);
    }

    function t(bool a, string memory message) internal override {
        assertTrue(a, message);
    }

    function between(
        uint256 value,
        uint256 low,
        uint256 high
    ) internal view override returns (uint256) {
        if (value < low || value > high) {
            uint ans = low + (value % (high - low + 1));
            return ans;
        }
        return value;
    }
}
