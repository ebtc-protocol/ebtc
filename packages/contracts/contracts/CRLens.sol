// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./Interfaces/IPriceFeed.sol";
import "./Interfaces/ICdpManager.sol";

/// @notice The contract allows to check real CR of CDPs
///   Acknowledgement: https://github.com/Uniswap/v3-periphery/blob/main/contracts/lens/Quoter.sol
contract CRLens {
    ICdpManager public immutable cdpManager;
    IPriceFeed public immutable priceFeed;

    constructor(address _cdpManager, address _priceFeed) {
        cdpManager = ICdpManager(_cdpManager);
        priceFeed = IPriceFeed(_priceFeed);
    }

    // == CORE FUNCTIONS == //

    /// @notice Returns the TCR of the system after the fee split
    /// @dev Call this from offChain with `eth_call` to avoid paying for gas
    function getRealTCR(bool revertValue) external returns (uint256) {
        // Synch State
        cdpManager.syncGlobalAccountingAndGracePeriod();

        // Return latest
        uint price = priceFeed.fetchPrice();
        uint256 tcr = cdpManager.getTCR(price);

        if (revertValue) {
            assembly {
                let ptr := mload(0x40)
                mstore(ptr, tcr)
                revert(ptr, 32)
            }
        }

        return tcr;
    }

    /// @notice Return the ICR of a CDP after the fee split
    /// @dev Call this from offChain with `eth_call` to avoid paying for gas
    function getRealICR(bytes32 cdpId, bool revertValue) external returns (uint256) {
        cdpManager.syncAccounting(cdpId);
        uint price = priceFeed.fetchPrice();
        uint256 icr = cdpManager.getICR(cdpId, price);

        if (revertValue) {
            assembly {
                let ptr := mload(0x40)
                mstore(ptr, icr)
                revert(ptr, 32)
            }
        }

        return icr;
    }

    /// @notice Return the ICR of a CDP after the fee split
    /// @dev Call this from offChain with `eth_call` to avoid paying for gas
    function getRealNICR(bytes32 cdpId, bool revertValue) external returns (uint256) {
        cdpManager.syncAccounting(cdpId);
        uint price = priceFeed.fetchPrice();
        uint256 icr = cdpManager.getNominalICR(cdpId);

        if (revertValue) {
            assembly {
                let ptr := mload(0x40)
                mstore(ptr, icr)
                revert(ptr, 32)
            }
        }

        return icr;
    }

    // == REVERT LOGIC == //
    // Thanks to: https://github.com/Uniswap/v3-periphery/blob/main/contracts/lens/Quoter.sol
    // NOTE: You should never use these in prod, these are just for testing //

    function parseRevertReason(bytes memory reason) private pure returns (uint256) {
        if (reason.length != 32) {
            if (reason.length < 68) revert("Unexpected error");
            assembly {
                reason := add(reason, 0x04)
            }
            revert(abi.decode(reason, (string)));
        }
        return abi.decode(reason, (uint256));
    }

    /// @notice Returns the TCR of the system after the fee split
    /// @dev Call this from offChain with `eth_call` to avoid paying for gas
    ///     These cost more gas, there should never be a reason for you to use them beside integration with Echidna
    function quoteRealTCR() external returns (uint256) {
        try this.getRealTCR(true) {} catch (bytes memory reason) {
            return parseRevertReason(reason);
        }
    }

    /// @notice Returns the ICR of the system after the fee split
    /// @dev Call this from offChain with `eth_call` to avoid paying for gas
    ///     These cost more gas, there should never be a reason for you to use them beside integration with Echidna
    function quoteRealICR(bytes32 cdpId) external returns (uint256) {
        try this.getRealICR(cdpId, true) {} catch (bytes memory reason) {
            return parseRevertReason(reason);
        }
    }
    /// @notice Returns the NICR of the system after the fee split
    /// @dev Call this from offChain with `eth_call` to avoid paying for gas
    ///     These cost more gas, there should never be a reason for you to use them beside integration with Echidna
    function quoteRealNICR(bytes32 cdpId) external returns (uint256) {
        try this.getRealNICR(cdpId, true) {} catch (bytes memory reason) {
            return parseRevertReason(reason);
        }
    }
}
