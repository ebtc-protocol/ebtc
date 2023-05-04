pragma solidity 0.8.17;

import "./Interfaces/IBorrowerOperations.sol";
import "./Interfaces/IERC3156FlashLender.sol";
import "./Interfaces/IEBTCToken.sol";
import "./Interfaces/ICdpManager.sol";
import "./Interfaces/ISortedCdps.sol";
import "./Interfaces/IPriceFeed.sol";
import "./Dependencies/ICollateralToken.sol";

import {ICdpManagerData} from "./Interfaces/ICdpManagerData.sol";

interface ICdpCdps {
    function Cdps(bytes32) external view returns (ICdpManagerData.Cdp memory);
}

/**
 * Allows specifying arbitrary operations to lever up
 *     NOTE: Due to security concenrs
 *     LeverageMacro accepts allowances and transfers token to FlashLoanMacroReceiver
 *     // FlashLoanMacroReceiver can perform ARBITRARY CALLS YOU WILL LOSE ALL ASSETS IF YOU APPROVE IT
 *     LeverageMacro on the other hand is safe to approve as it cannot move your funds without your consent
 */
contract LeverageMacro {
    IBorrowerOperations public immutable borrowerOperations;
    IActivePool public immutable activePool;
    ICdpCdps public immutable cdpManager;
    IEBTCToken public immutable ebtcToken;
    ISortedCdps public immutable sortedCdps;
    ICollateralToken public immutable stETH;

    address public immutable owner;

    bytes32 constant FLASH_LOAN_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    // Leverage Macro should receive a request and set that data
    // Then perform the request

    constructor(
        address _borrowerOperationsAddress,
        address _activePool,
        address _cdpManager,
        address _ebtc,
        address _coll,
        address _sortedCdps,
        address _owner
    ) {
        borrowerOperations = IBorrowerOperations(_borrowerOperationsAddress);
        activePool = IActivePool(_activePool);
        cdpManager = ICdpCdps(_cdpManager);
        ebtcToken = IEBTCToken(_ebtc);
        stETH = ICollateralToken(_coll);
        sortedCdps = ISortedCdps(_sortedCdps);

        owner = _owner;

        // set allowance for flashloan lender/CDP open
        ebtcToken.approve(_borrowerOperationsAddress, type(uint256).max);
        stETH.approve(_borrowerOperationsAddress, type(uint256).max);
        stETH.approve(_activePool, type(uint256).max);
    }

    enum FlashLoanType {
        stETH,
        eBTC
    }

    enum PostOperationCheck {
        openCdp,
        cdpStats,
        isClosed
    }

    enum Operator {
        skip,
        equal,
        gte,
        lte
    }

    struct CheckValueAndType {
        uint256 value;
        Operator operator;
    }

    struct PostCheckParams {
        CheckValueAndType expectedDebt;
        CheckValueAndType expectedCollateral;
        // Used only if cdpStats || isClosed
        bytes32 cdpId;
        // Used only if isClosed
        ICdpManagerData.Status expectedStatus;
    }

    /**
     * FL Setup
     *         - Validate Caller
     *
     *         FL
     *         - SwapsBefore
     *         - Operation
     *         - SwapsAfter
     *         - Repay
     *
     *         - Post Operation Checks
     *
     *         - Sweep
     */
    function doOperation(
        FlashLoanType flType,
        uint256 borrowAmount,
        LeverageMacroOperation calldata operation,
        PostOperationCheck postCheckType,
        PostCheckParams calldata checkParams
    ) external {
        require(msg.sender == owner);

        // Call FL Here, then the stuff below needs to happen inside the FL
        if (operation.amountToTransferIn > 0) {
            // Not safe because OZ for our cases, if you use USDT it's your prob friend
            // NOTE: Send directly to flashLoanMacroReceiver
            IERC20(operation.tokenToTransferIn).transferFrom(
                msg.sender, address(this), operation.amountToTransferIn
            );
        }

        /**
         * SETUP FOR POST CALL CHECK
         */
        uint256 initialCdpIndex;
        if (postCheckType == PostOperationCheck.openCdp) {
            // How to get owner
            // sortedCdps.existCdpOwners(_cdpId);
            initialCdpIndex = sortedCdps.cdpCountOf(msg.sender);
        }

        // Take eBTC or stETH FlashLoan
        if (flType == FlashLoanType.eBTC) {
            IERC3156FlashLender(address(borrowerOperations)).flashLoan(
                IERC3156FlashBorrower(address(this)),
                address(ebtcToken),
                borrowAmount,
                abi.encode(operation)
            );
        } else if (flType == FlashLoanType.stETH) {
            IERC3156FlashLender(address(activePool)).flashLoan(
                IERC3156FlashBorrower(address(this)),
                address(stETH),
                borrowAmount,
                abi.encode(operation)
            );
        } else {
            // TODO: If enum OOB reverts, can remove this, can also leave as explicity
            revert("Must be valid due to forwarding of users");
        }

        /**
         * POST CALL CHECK FOR CREATION
         */
        if (postCheckType == PostOperationCheck.openCdp) {
            // How to get owner
            // sortedCdps.existCdpOwners(_cdpId);
            // initialCdpIndex is initialCdpIndex + 1
            bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(msg.sender, initialCdpIndex);

            // Check for param details
            ICdpManagerData.Cdp memory cdpInfo = cdpManager.Cdps(cdpId);
            _doCheckValueType(cdpInfo.debt, checkParams.expectedDebt);
            _doCheckValueType(cdpInfo.coll, checkParams.expectedCollateral);
            require(cdpInfo.status == checkParams.expectedStatus);
        }

        // Update CDP, Ensure the stats are as intended
        if (postCheckType == PostOperationCheck.cdpStats) {
            ICdpManagerData.Cdp memory cdpInfo = cdpManager.Cdps(checkParams.cdpId);

            _doCheckValueType(cdpInfo.debt, checkParams.expectedDebt);
            _doCheckValueType(cdpInfo.coll, checkParams.expectedCollateral);
            require(cdpInfo.status == checkParams.expectedStatus);
        }

        // Post check type: Close, ensure it has the status we want
        if (postCheckType == PostOperationCheck.isClosed) {
            ICdpManagerData.Cdp memory cdpInfo = cdpManager.Cdps(checkParams.cdpId);

            require(cdpInfo.status == checkParams.expectedStatus);
        }

        // Sweep here
        _sweepToCaller();
    }

    /// @dev Assumes that 
    ///     >= you prob use this one
    ///     <= if you don't need >= you go for lte
    ///     And if you really need eq, it's third
    function _doCheckValueType(uint256 valueToCheck, CheckValueAndType memory check) internal {
        if(check.operator == Operator.skip) {
            // Early return
            return;
        } else if(check.operator == Operator.gte) {
            require(check.value >= valueToCheck);
        } else if(check.operator == Operator.lte) {
            require(check.value <= valueToCheck);
        } else if (check.operator == Operator.equal) {
            require(check.value == valueToCheck);
        } else {
            // TODO: If proof OOB enum, then we can remove this
            revert("Operator not found");
        }
    } 

    struct LeverageMacroOperation {
        address tokenToTransferIn;
        uint256 amountToTransferIn;
        SwapOperation[] swapsBefore; // Empty to skip
        SwapOperation[] swapsAfter; // Empty to skip
        OperationType operationType; // Open, Close, etc..
        bytes OperationData; // Generic Operation Data, which we'll decode to use
    }

    struct SwapOperation {
        // Swap Data
        address tokenForSwap;
        address addressForApprove;
        uint256 exactApproveAmount;
        address addressForSwap;
        bytes calldataForSwap;
        SwapCheck[] swapChecks; // Empty to skip
    }

    struct SwapCheck {
        // Swap Slippage Check
        address tokenToCheck;
        uint256 expectedMinOut;
    }

    enum OperationType {
        OpenCdpOperation,
        AdjustCdpOperation,
        CloseCdpOperation
    }

    function _sweepToCaller() internal {
        /**
         * SWEEP TO CALLER *
         */
        // Safe unchecked because known tokens
        uint256 ebtcBal = ebtcToken.balanceOf(address(this));
        uint256 collateralBal = stETH.balanceOf(address(this));

        if (ebtcBal > 0) {
            ebtcToken.transfer(msg.sender, ebtcBal);
        }

        if (collateralBal > 0) {
            stETH.transfer(msg.sender, collateralBal);
        }
    }

    /// @dev Must be memory since we had to decode it
    function _handleOperation(LeverageMacroOperation memory operation) internal {
        uint256 beforeSwapsLength = operation.swapsBefore.length;
        if (beforeSwapsLength > 0) {
            _doSwaps(operation.swapsBefore);
        }

        // Based on the type we do stuff
        if (operation.operationType == OperationType.OpenCdpOperation) {
            _openCdpCallback(operation.OperationData);
        } else if (operation.operationType == OperationType.CloseCdpOperation) {
            _closeCdpCallback(operation.OperationData);
        } else if (operation.operationType == OperationType.AdjustCdpOperation) {
            _adjustCdpCallback(operation.OperationData);
        }

        uint256 afterSwapsLength = operation.swapsAfter.length;
        if (afterSwapsLength > 0) {
            _doSwaps(operation.swapsAfter);
        }
    }


    // Open
    struct OpenCdpOperation {
        // Open CDP For Data
        uint256 eBTCToMint;
        bytes32 _upperHint;
        bytes32 _lowerHint;
        uint256 stETHToDeposit;
    }

    // Change leverage or something
    struct AdjustCdpOperation {
        bytes32 _cdpId;
        uint256 _collWithdrawal;
        uint256 _EBTCChange;
        bool _isDebtIncrease;
        bytes32 _upperHint;
        bytes32 _lowerHint;
        uint256 _collAddAmount;
    }

    // Repay and Close
    struct CloseCdpOperation {
        bytes32 _cdpId;
    }

    function decodeFLData(bytes calldata data) public view returns (LeverageMacroOperation memory) {
        (LeverageMacroOperation memory leverageMacroData) = abi.decode(data, (LeverageMacroOperation));
        return leverageMacroData;
    }

    function onFlashLoan(address initiator, address token, uint256 amount, uint256 fee, bytes calldata data)
        external
        returns (bytes32)
    {
        // Verify we started the FL
        require(initiator == address(this), "LeverageMacro: wrong initiator for flashloan");

        // Ensure the caller is the intended contract
        if (token == address(ebtcToken)) {
            require(msg.sender == address(borrowerOperations), "LeverageMacro: wrong lender for eBTC flashloan");
        } else {
            // Enforce that this is either eBTC or stETH
            require(msg.sender == address(activePool), "LeverageMacro: wrong lender for stETH flashloan");
        }

        // Else a malicious contract, that changes the data would be able to inject a forwarded caller

        // Get the data
        // We will get the first byte of data for enum an type
        // The rest of the data we can decode based on the operation type from calldata
        // Then we can do multiple hooks and stuff
        (LeverageMacroOperation memory operation) = decodeFLData(data);

        _handleOperation(operation);

        return FLASH_LOAN_SUCCESS;
    }

    /// @dev Must be memory since we had to decode it
    function _doSwaps(SwapOperation[] memory swapData) internal {
        uint256 swapLength = swapData.length;

        for (uint256 i; i < swapLength;) {
            _doSwap(swapData[i]);
            unchecked {
                ++i;
            }
        }
    }

    function _doSwap(SwapOperation memory swapData) internal {
        // Ensure call is safe
        // Block all system contracts
        _ensureNotSystem(swapData.addressForSwap);

        // Exact approve
        // Approve can be given anywhere because this is a router, and after call we will delete all approvals
        IERC20(swapData.tokenForSwap).approve(swapData.addressForApprove, swapData.exactApproveAmount);

        // Call and perform swap
        // NOTE: Technically approval may be different from target, something to keep in mind
        // Call target are limited
        // But technically you could approve w/e you want here, this is fine because the contract is a router and will not hold user funds
        (bool success,) = excessivelySafeCall(swapData.addressForSwap, gasleft(), 0, 32, swapData.calldataForSwap);
        require(success, "Call has failed");

        // Approve back to 0
        // Enforce exact approval
        // Can use max because the tokens are OZ
        // val -> 0 -> 0 -> val means this is safe to repeat since even if full approve is unused, we always go back to 0 after
        IERC20(swapData.tokenForSwap).approve(swapData.addressForApprove, 0);

        // Do the balance checks after the call to the aggregator
        _doSwapChecks(swapData.swapChecks);
    }

    function _doSwapChecks(SwapCheck[] memory swapChecks) internal {
        uint256 length = swapChecks.length;
        unchecked {
            for (uint256 i; i < length; ++i) {
                // > because if you don't want to check for 0, just don't have the check
                require(IERC20(swapChecks[i].tokenToCheck).balanceOf(address(this)) > swapChecks[i].expectedMinOut);
            }
        }
    }

    // TODO: Check and add more if you think it's better
    function _ensureNotSystem(address addy) internal {
        require(addy != address(borrowerOperations));
        require(addy != address(sortedCdps));
        require(addy != address(activePool));
        require(addy != address(this)); // If it could call this it could fake the forwarded caller
    }

    /// @dev Must be memory since we had to decode it
    function _openCdpCallback(bytes memory data) internal {
        OpenCdpOperation memory flData = abi.decode(data, (OpenCdpOperation));
        /**
         * Open CDP and Emit event
         */
        bytes32 _cdpId = borrowerOperations.openCdp(
            flData.eBTCToMint, flData._upperHint, flData._lowerHint, flData.stETHToDeposit
        );
    }

    /// @dev Must be memory since we had to decode it
    function _closeCdpCallback(bytes memory data) internal {
        CloseCdpOperation memory flData = abi.decode(data, (CloseCdpOperation));

        // Initiator must be added by this contract, else it's not trusted
        borrowerOperations.closeCdp(flData._cdpId);
    }

    /// @dev Must be memory since we had to decode it
    function _adjustCdpCallback(bytes memory data) internal {
        AdjustCdpOperation memory flData = abi.decode(data, (AdjustCdpOperation));

        borrowerOperations.adjustCdpWithColl(
            flData._cdpId,
            flData._collWithdrawal,
            flData._EBTCChange,
            flData._isDebtIncrease,
            flData._upperHint,
            flData._lowerHint,
            flData._collAddAmount
        );
    }

    /**
     * excessivelySafeCall to perform generic calls without getting gas bombed | useful if you don't care about return value
     */
    // Credits to: https://github.com/nomad-xyz/ExcessivelySafeCall/blob/main/src/ExcessivelySafeCall.sol
    function excessivelySafeCall(address _target, uint256 _gas, uint256 _value, uint16 _maxCopy, bytes memory _calldata)
        internal
        returns (bool, bytes memory)
    {
        // set up for assembly call
        uint256 _toCopy;
        bool _success;
        bytes memory _returnData = new bytes(_maxCopy);
        // dispatch message to recipient
        // by assembly calling "handle" function
        // we call via assembly to avoid memcopying a very large returndata
        // returned by a malicious contract
        assembly {
            _success :=
                call(
                    _gas, // gas
                    _target, // recipient
                    _value, // ether value
                    add(_calldata, 0x20), // inloc
                    mload(_calldata), // inlen
                    0, // outloc
                    0 // outlen
                )
            // limit our copy to 256 bytes
            _toCopy := returndatasize()
            if gt(_toCopy, _maxCopy) { _toCopy := _maxCopy }
            // Store the length of the copied bytes
            mstore(_returnData, _toCopy)
            // copy the bytes from returndata[0:_toCopy]
            returndatacopy(add(_returnData, 0x20), 0, _toCopy)
        }
        return (_success, _returnData);
    }
}