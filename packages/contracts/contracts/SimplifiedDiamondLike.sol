// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

/**
 * @title A multi-purpose Smart Contract Wallet
 * @notice `execute`s just like DSProxy
 * @notice handles callbacks via a DiamondLike Pattern
 * @notice CallbackOnly, only when toggled on, unless explicitly changed
 * @notice Due to the additional complexity, it's best used with a TX Simulator
 *
 * @dev Diamond Like Storage
 *  Because of risk of clash, we must place storage at a pseudo-random location (see DIAMOND EIP)
 *  Add to `OurSettings` to extend the eternal storage with custom fields
 *
 * @dev Hardcoded Functions
 *  Per solidity, hardcoded functions are switched into, meaning they cannot be overriden (although you could set a callbackHandler that cannot be reached)
 *  All other functions will reach the `fallback`
 *  This is basically a diamond, with an extra check for safety / extra control from the owner
 *
 * @dev Explicit Callback Handling
 *  All SimplifiedDiamondLike are deployed with `allowNonCallback` set to `false`
 *  This ensures that nobody can call this contract unless the owner sets this to `true` via the scary `setAllowAnyCall`
 *
 */
contract SimplifiedDiamondLike {
    // SIMPLIFIED STRUCT
    // We add our settings to the diamond logic to extend it
    struct OurSettings {
        bool allowNonCallback;
        bool callbackEnabledForCall;
    }

    struct DiamondLikeStorage {
        mapping(bytes4 => address) callbackHandler;
        OurSettings settings; // add to these to allow more fields
    }

    // SIMPLFIIED STORAGE POS
    bytes32 constant DIAMOND_STORAGE_POSITION = keccak256("diamond.standard.diamond.storage");

    // make owner immutable cause reasons
    address public immutable owner;

    constructor(address _owner) {
        owner = _owner;
    }

    /// === HARDCODED SETTERS === ///
    /// @notice Given a funsig and a implementation address
    ///     Set the handler to the logic we will delegatecall to
    function setFallbackHandler(bytes4 sig, address handler) external {
        require(msg.sender == owner);

        // NOTE: We prob don't need this due to how solidity works
        // "execute((address,bool,uint128,uint128,bool,uint8,bytes)[])": "94b24d09"
        require(sig != 0x94b24d09);

        DiamondLikeStorage storage s = _getStorage();

        s.callbackHandler[sig] = handler;
    }

    /// @notice Do you want to allow any caller to call this contract?
    ///     This is a VERY DANGEROUS setting
    ///     Do not call this unless you know what you are doing
    function setAllowAnyCall(bool allowNonCallbacks) external {
        require(msg.sender == owner);

        DiamondLikeStorage storage s = _getStorage();
        s.settings.allowNonCallback = allowNonCallbacks;
    }

    /// @notice Allows one callback for this call
    ///     This is a VERY DANGEROUS setting
    ///     Ensure you use the callback in the same call as you set it, or this may be used to attack this wallet
    function enableCallbackForCall() external {
        require(msg.sender == address(this)); // Must call this via `execute` to explicitly set the flag
        _setCallbackEnabledForCall(_getStorage(), true);
    }

    /// === DIAMOND LIKE STORAGE === ///
    /// @dev Get pointer to storage
    function _getStorage() internal pure returns (DiamondLikeStorage storage ds) {
        bytes32 position = DIAMOND_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    /// === DS LIKE === ////

    // Hardcoded Generic Function
    // NOTE: If you don't know what these are, DO NOT USE THIS!
    enum OperationType {
        call,
        delegatecall
    }

    struct Operation {
        address to; // Target to call
        bool checkSuccess; // If false we will ignore a revert
        uint128 value; // How much ETH to send
        uint128 gas; // How much gas to send
        bool capGas; // true to use above "gas" setting or we send gasleft()
        OperationType opType; // See `OperationType`
        bytes data; // Calldata to send (funsig + data)
    }

    /// @notice Execute a list of operations in sequence
    function execute(Operation[] calldata ops) external payable {
        require(msg.sender == owner, "Must be owner");

        uint256 length = ops.length;
        for (uint256 i; i < length; ) {
            _executeOne(ops[i]);

            unchecked {
                ++i;
            }
        }

        // Toggle `callbackEnabledForCall` to false
        // NOTE: We could check calldata to see if this has to be done, but this is fine for a reference impl
        // Even if no-op, this ensures we never allow a callback if in that mode
        _setCallbackEnabledForCall(_getStorage(), false);
    }

    /// @dev toggle callbackEnabledForCall in OurSetting
    function _setCallbackEnabledForCall(DiamondLikeStorage storage ds, bool _enabled) internal {
        ds.settings.callbackEnabledForCall = _enabled;
    }

    /// @dev Execute one tx
    function _executeOne(Operation calldata op) internal {
        bool success;
        bytes memory data = op.data;
        uint256 txGas = op.capGas ? op.gas : gasleft();
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
            require(success);
        }
    }

    /// === DIAMOND LIKE Functions === ///

    receive() external payable {
        // PHP is my favourite language
    }

    fallback() external payable {
        _fallback();
    }

    /// @dev DiamondLike Fallback
    /// - Checks if it allows fallback either permanently or as one-off
    /// - If it does, load the handler for that signatures
    /// - If it exists, delegatecall to it, forwarding the data
    /// @notice The pattern allows to add custom callbacks to this contract
    ///     Effectively making this a Smart Contract Wallet which enables Callbacks
    function _fallback() internal {
        DiamondLikeStorage storage ds = _getStorage();

        // If we don't allow callback
        if (!ds.settings.allowNonCallback) {
            require(ds.settings.callbackEnabledForCall, "Only Enabled Callbacks");
            // NOTE: May also act as reEntrancy guard
            // But wouldn't just count on it
            _setCallbackEnabledForCall(ds, false);
        }

        // Diamond like fallback if programmed
        address facet = ds.callbackHandler[msg.sig];
        require(facet != address(0), "Diamond: Function does not exist");

        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }
}
