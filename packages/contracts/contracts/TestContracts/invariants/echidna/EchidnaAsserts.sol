pragma solidity 0.8.17;

import "@crytic/properties/contracts/util/PropertiesHelper.sol";
import "../Asserts.sol";

abstract contract EchidnaAsserts is PropertiesAsserts, Asserts {
    function gt(uint256 a, uint256 b, string memory message) internal override {
        assertGt(a, b, message);
    }

    function lt(uint256 a, uint256 b, string memory message) internal override {
        assertLt(a, b, message);
    }

    function gte(uint256 a, uint256 b, string memory message) internal override {
        assertGte(a, b, message);
    }

    function lte(uint256 a, uint256 b, string memory message) internal override {
        assertLte(a, b, message);
    }

    function eq(uint256 a, uint256 b, string memory message) internal override {
        assertEq(a, b, message);
    }

    function t(bool a, string memory message) internal override {
        assertWithMsg(a, message);
    }

    function between(uint256 value, uint256 low, uint256 high) internal override returns (uint256) {
        return clampBetween(value, low, high);
    }
}
