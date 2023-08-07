pragma solidity 0.8.17;

import {AssertionHelper} from "../AssertionHelper.sol";
import {PropertiesAsserts} from "@crytic/properties/contracts/util/PropertiesHelper.sol";

abstract contract EchidnaAssertionHelper is AssertionHelper, PropertiesAsserts {
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
}
