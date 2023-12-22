// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {PriceFeed} from "../PriceFeed.sol";
import {IPriceFetcher} from "../Interfaces/IOracleCaller.sol";

contract PriceFeedOracleTester {
    enum ErrorState {
        NONE,
        REVERT_BOMB,
        RETURN_BOMB,
        RETURN_BYTES,
        REVERT_CUSTOM_ERROR,
        REVERT_CUSTOM_ERROR_PARAMS,
        BURN_ALL_GAS,
        SELF_DESTRUCT,
        COUNT // Number of elements
    }

    IPriceFetcher public priceFeed;
    ErrorState public errorState;

    error InvalidAddress();
    error InvalidNumber(uint224);

    constructor(address _priceFeed) {
        priceFeed = IPriceFetcher(_priceFeed);
        errorState = ErrorState.NONE;
    }

    function fetchPrice() external returns (uint256) {
        if (errorState == ErrorState.NONE) {
            return priceFeed.fetchPrice();
        } else if (errorState == ErrorState.REVERT_BOMB) {
            revBytes(2_000_000);
        } else if (errorState == ErrorState.RETURN_BOMB) {
            retBytes(2_000_000);
        } else if (errorState == ErrorState.RETURN_BYTES) {
            retByteArray();
        } else if (errorState == ErrorState.REVERT_CUSTOM_ERROR) {
            revert InvalidAddress();
        } else if (errorState == ErrorState.REVERT_CUSTOM_ERROR_PARAMS) {
            revert InvalidNumber(12346);
        } else if (errorState == ErrorState.BURN_ALL_GAS) {
            uint256 counter;
            while (true) {
                counter += 1;
            }
        } else if (errorState == ErrorState.SELF_DESTRUCT) {
            selfdestruct(payable(msg.sender));
        }
    }

    function revBytes(uint256 _bytes) internal pure {
        assembly {
            revert(0, _bytes)
        }
    }

    function retBytes(uint256 _bytes) public pure {
        assembly {
            return(0, _bytes)
        }
    }

    function retByteArray() public pure {
        uint256[] memory entries = new uint256[](250);
        bytes memory retData = abi.encode(entries);
        uint256 retLen = retData.length;
        assembly {
            return(add(retData, 0x20), retLen)
        }
    }

    function setErrorState(ErrorState _errorState) external {
        errorState = _errorState;
    }
}
