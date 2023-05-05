// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../Interfaces/IFallbackCaller.sol";
import "./ITellor.sol";

/*
 * This contract has a single external function that calls Tellor: getTellorCurrentValue().
 *
 * The function is called by the Liquity contract PriceFeed.sol. If any of its inner calls to Tellor revert,
 * this function will revert, and PriceFeed will catch the failure and handle it accordingly.
 *
 * The function comes from Tellor's own wrapper contract, 'UsingTellor.sol':
 * https://github.com/tellor-io/usingtellor/blob/master/contracts/UsingTellor.sol
 *
 */
contract TellorCaller is IFallbackCaller {
    ITellor public tellor;
    // TODO: Use new Tellor query ID for stETH/BTC when available
    bytes32 public constant STETH_BTC_TELLOR_QUERY_ID =
        0x4a5d321c06b63cd85798f884f7d5a1d79d27c6c65756feda15e06742bd161e69; // keccak256(abi.encode("SpotPrice", abi.encode("steth", "btc")))
    // default 15 minutes, soft governance might help to change this default configuration if required
    uint256 public tellorQueryBufferSeconds = 901;

    constructor(address _tellorMasterAddress) public {
        tellor = ITellor(_tellorMasterAddress);
    }

    /*
     * getFallbackResponse(): fixed according to https://www.liquity.org/blog/tellor-issue-and-fix
     *
     * @dev Allows the user to get the latest value for the queryId specified
     * @return answer - the oracle report retrieved (must be 18 decimals!)
     * @return timestamp - the value's timestamp
     * @return success - wheather or not the value was successfully retrived
     */
    function getFallbackResponse() external view override returns (uint256, uint256, bool) {
        (bool _ifRetrieve, bytes memory _value, uint256 _timestampRetrieved) = tellor.getDataBefore(
            STETH_BTC_TELLOR_QUERY_ID,
            block.timestamp - tellorQueryBufferSeconds
        );
        uint256 _val = abi.decode(_value, (uint256));
        if (_timestampRetrieved == 0 || _val == 0) {
            return (_val, _timestampRetrieved, false);
        } else {
            return (_val, _timestampRetrieved, true);
        }
    }
}
