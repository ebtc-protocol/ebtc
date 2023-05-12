// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

contract SimplifiedDiamondLike {
    // SIMPLIFIED STRUCT
    // We add our settings to the diamond logic to extend it
    struct OurSettings {
        bool allowNonCallback;
        bool callbackEnabledForCall;
    }

    struct DiamondLikeStorage {
        mapping(bytes4 => address) callbackHandler;
        OurSettings settings; // add to these to allow more fiels
    }

    // SIMPLFIIED STORAGE POS
    bytes32 constant DIAMOND_STORAGE_POSITION = keccak256("diamond.standard.diamond.storage");

    // make owner immutable cause reasons
    address public immutable owner;

    constructor(address _owner) {
        owner = _owner;
    }

    // SIMPLIFIED ACCESS
    function getStorage() internal pure returns (DiamondLikeStorage storage ds) {
        bytes32 position = DIAMOND_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    // Hardcoded setters
    function setFallbackHandler(bytes4 sig, address handler) external {
        require(msg.sender == owner);

        // "execute((address,bool,uint128,uint128,bool,uint8,bytes)[])": "94b24d09"
        require(sig != 0x94b24d09);

        DiamondLikeStorage storage s = getStorage();

        s.callbackHandler[sig] = handler;
    }

    function setAllowAnyCall(bool allowNonCallbacks) external {
        require(msg.sender == owner);

        DiamondLikeStorage storage s = getStorage();
        s.settings.allowNonCallback = allowNonCallbacks;
    }

    // Hardcoded Generic Function
    enum OperationType {
        call,
        delegatecall
    }

    struct Operation {
        address to;
        bool checkSuccess;
        uint128 value;
        uint128 gas; // Prob can be smallers
        bool capGas; //  TODO: add
        OperationType opType;
        bytes data;
    }

    function enableCallbackForCall() external {
        require(msg.sender == address(this)); // Must call this via `execute` to explicitly set the flag

        DiamondLikeStorage storage ds = getStorage();

        ds.settings.callbackEnabledForCall = true;
    }

    /// @notice Execute a list of operations in sequence
    function execute(Operation[] calldata ops) external payable {
        require(msg.sender == owner, "Must be owner");

        uint256 length = ops.length;
        for (uint256 i; i < length;) {
            _executeOne(ops[i], i);

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Execute one tx
    function _executeOne(Operation calldata op, uint256 counter) internal {
        bool success;
        bytes memory data = op.data;
        uint256 txGas = op.gas;
        address to = op.to;
        uint256 value = op.value;

        if (op.opType == OperationType.delegatecall) {
            // solhint-disable-next-line no-inline-assembly
            assembly {
                success := delegatecall(txGas, to, add(data, 0x20), mload(data), 0, 0)
            }
        } else {
            // solhint-disable-next-line no-inline-assembly
            assembly {
                success := call(txGas, to, value, add(data, 0x20), mload(data), 0, 0)
            }
        }

        if (op.checkSuccess) {
            require(success); // TODO: How do we easily debug this?
        }
    }

    receive() external payable {
        // PHP is my favourite language
    }

    fallback() external payable {
        _fallback();
    }

    // DiamondLike Fallback
    function _fallback() internal {
        DiamondLikeStorage storage ds = getStorage();

        // If we don't allow callback
        if (!ds.settings.allowNonCallback) {
            require(ds.settings.callbackEnabledForCall, "Only Enabled Callbacks");
            // NOTE: May also act as reEntrancy guard
            ds.settings.callbackEnabledForCall = false;
        }

        // Diamond like fallback if programmed
        address facet = ds.callbackHandler[msg.sig];
        require(facet != address(0), "Diamond: Function does not exist");
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
}
