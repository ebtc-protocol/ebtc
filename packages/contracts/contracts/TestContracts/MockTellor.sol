// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "../PriceFeed.sol";

contract MockTellor {
    // --- Mock price data ---

    bool didRetrieve = true; // default to a positive retrieval
    uint private ethPrice;
    uint private btcPrice;
    uint private updateTime;

    bool private revertRequest;
    uint private invalidRequest; // 1 - price, 2 - timestamp

    // --- Setters for mock price data ---

    function setEthPrice(uint _price) external {
        ethPrice = _price;
    }

    function setBtcPrice(uint _price) external {
        btcPrice = _price;
    }

    function setDidRetrieve(bool _didRetrieve) external {
        didRetrieve = _didRetrieve;
    }

    function setUpdateTime(uint _updateTime) external {
        updateTime = _updateTime;
    }

    function setRevertRequest() external {
        revertRequest = !revertRequest;
    }

    function setInvalidRequest(uint _invalidType) external {
        invalidRequest = _invalidType;
    }

    // --- Mock data reporting functions ---

    function getUpdateTime() external view returns (uint) {
        return updateTime;
    }

    function retrieveData(uint256, uint256) external view returns (uint256) {
        return ethPrice;
    }

    function getDataBefore(
        bytes32 _queryId,
        uint256 _timestamp
    ) external returns (bool _ifRetrieve, bytes memory _value, uint256 _timestampRetrieved) {
        if (revertRequest) {
            require(1 == 0, "Tellor request reverted");
        }
        uint statefulPrice;
        // Return price based on queryId:
        if (_queryId == 0x83a7f3d48786ac2667503a61e8c415438ed2922eb86a2906e4ee66d9a2ce4992) {
            statefulPrice = ethPrice;
        } else if (_queryId == 0xa6f013ee236804827b77696d350e9f0ac3e879328f2a3021d473a0b778ad78ac) {
            statefulPrice = btcPrice;
        }
        return
            invalidRequest > 0
                ? (
                    false,
                    invalidRequest == 1 ? abi.encode(0) : abi.encode(statefulPrice),
                    invalidRequest == 2 ? 0 : updateTime
                )
                : (true, abi.encode(statefulPrice), updateTime);
    }
}
