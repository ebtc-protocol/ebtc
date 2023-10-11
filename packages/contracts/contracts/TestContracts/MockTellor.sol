// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../PriceFeed.sol";

contract MockTellor {
    // --- Mock price data ---

    bool didRetrieve = true; // default to a positive retrieval
    uint256 private price;
    uint256 private updateTime;

    bool private revertRequest;
    uint256 private invalidRequest; // 1 - price, 2 - timestamp

    // --- Setters for mock price data ---

    function setPrice(uint256 _price) external {
        price = _price;
    }

    function setDidRetrieve(bool _didRetrieve) external {
        didRetrieve = _didRetrieve;
    }

    function setUpdateTime(uint256 _updateTime) external {
        updateTime = _updateTime;
    }

    function setRevertRequest() external {
        revertRequest = !revertRequest;
    }

    function setInvalidRequest(uint256 _invalidType) external {
        invalidRequest = _invalidType;
    }

    // --- Mock data reporting functions ---

    function getUpdateTime() external view returns (uint256) {
        return updateTime;
    }

    function retrieveData(uint256, uint256) external view returns (uint256) {
        return price;
    }

    function getDataBefore(
        bytes32 _queryId,
        uint256 //_timestamp // unused
    ) external view returns (bool _ifRetrieve, bytes memory _value, uint256 _timestampRetrieved) {
        if (revertRequest) {
            require(1 == 0, "Tellor request reverted");
        }
        return
            invalidRequest > 0
                ? (
                    false,
                    invalidRequest == 1 ? abi.encode(0) : abi.encode(price),
                    invalidRequest == 2 ? 0 : updateTime
                )
                : (true, abi.encode(price), updateTime);
    }
}
