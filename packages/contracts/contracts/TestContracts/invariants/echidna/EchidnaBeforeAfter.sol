pragma solidity 0.8.17;

import {EchidnaBaseTester} from "./EchidnaBaseTester.sol";

abstract contract EchidnaBeforeAfter is EchidnaBaseTester {
    struct Vars {
        uint256 nicrBefore;
        uint256 nicrAfter;
    }

    Vars vars;

    function _before(bytes32 _cdpId) internal {
        vars.nicrBefore = cdpManager.getNominalICR(_cdpId);
    }

    function _after(bytes32 _cdpId) internal {
        vars.nicrAfter = cdpManager.getNominalICR(_cdpId);
    }
}
