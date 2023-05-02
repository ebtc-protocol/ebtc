pragma solidity 0.8.17;

import "./Interfaces/IBorrowerOperations.sol";
import "./Interfaces/IERC3156FlashLender.sol";
import "./Interfaces/IEBTCToken.sol";
import "./Interfaces/ISortedCdps.sol";
import "./Interfaces/IPriceFeed.sol";
import "./Dependencies/ICollateralToken.sol";
import "./Dependencies/IBalancerV2Vault.sol";

contract LeverageMacro is IERC3156FlashBorrower {
    IBorrowerOperations public immutable borrowerOperations;
    IBorrowerOperations public immutable activePool; // TODO: TYPE
    IEBTCToken public immutable ebtcToken;
    ISortedCdps public immutable sortedCdps;
    ICollateralToken public immutable stETH;

    // event LeveragedCdpOpened(address indexed _initiator, uint256 _debt, uint256 _coll, bytes32 indexed _cdpId);
    // TODO: Events if you want, imo not needed
    

    bytes32 constant FLASH_LOAN_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    // Leverage Macro should receive a request and set that data
    // Then perform the request

    constructor(
        address _borrowerOperationsAddress,
        address _activePool,
        address _ebtc,
        address _coll,
        address _sortedCdps
    ) {
        borrowerOperations = IBorrowerOperations(_borrowerOperationsAddress);
        activePool = IBorrowerOperations(_activePool);
        ebtcToken = IEBTCToken(_ebtc);
        stETH = ICollateralToken(_coll);
        sortedCdps = ISortedCdps(_sortedCdps);

        // set allowance for flashloan lender/CDP open
        ebtcToken.approve(_borrowerOperationsAddress, type(uint256).max);
        stETH.approve(_borrowerOperationsAddress, type(uint256).max);
    }

    enum FlashLoanType {
        stETH,
        eBTC
    }

    function doOperation(FlashLoanType flType, uint256 borrowAmount, LeverageMacroOperation calldata operation)
        external
    {
        require(operation.forwardedCaller == msg.sender); // Enforce encoded properly

        // Call FL Here, then the stuff below needs to happen inside the FL
        if (operation.amountToTransferIn > 0) {
            // Not safe because OZ for our cases, if you use USDT it's your prob friend
            IERC20(operation.tokenToTransferIn).transferFrom(msg.sender, address(this), operation.amountToTransferIn);
        }

        // Take eBTC or stETH FlashLoan
        if (flType == FlashLoanType.eBTC) {
            IERC3156FlashLender(address(borrowerOperations)).flashLoan(
                IERC3156FlashBorrower(address(this)), address(ebtcToken), borrowAmount, abi.encode(operation)
            );
        } else if (flType == FlashLoanType.stETH) {
            IERC3156FlashLender(address(activePool)).flashLoan(
                IERC3156FlashBorrower(address(this)), address(stETH), borrowAmount, abi.encode(operation)
            );
        } else {
            // TODO: If enum OOB reverts, can remove this, can also leave as explicity
            revert("Must be valid due to forwarding of users");
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
         *         - Sweep
         */
        // TODO: Post Operations Checks

        // Sweep here
        _sweepToCaller();
    }

    /// @dev Must be memory since we had to decode it
    function _handleOperation(LeverageMacroOperation memory operation, address forwardedCaller) internal {
        uint256 beforeSwapsLength = operation.swapsBefore.length;
        if (beforeSwapsLength > 0) {
            _doSwaps(operation.swapsBefore);
        }

        // Based on the type we do stuff
        if (operation.operationType == OperationType.OpenCdpOperation) {
            _openCdpCallback(operation.OperationData, forwardedCaller);
        } else if (operation.operationType == OperationType.CloseCdpOperation) {
            _closeCdpCallback(operation.OperationData, forwardedCaller);
        } else if (operation.operationType == OperationType.AdjustCdpOperation) {
            _adjustCdpCallback(operation.OperationData, forwardedCaller);
        }

        uint256 afterSwapsLength = operation.swapsAfter.length;
        if (afterSwapsLength > 0) {
            _doSwaps(operation.swapsAfter);
        }
    }

    struct LeverageMacroOperation {
        address tokenToTransferIn;
        uint256 amountToTransferIn;
        SwapOperation[] swapsBefore; // Empty to skip
        SwapOperation[] swapsAfter; // Empty to skip
        OperationType operationType; // Open, Close, etc..
        bytes OperationData; // Generic Operation Data, which we'll decode to use
        address forwardedCaller; // We add this, we'll enforce that it's added by us
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

    // TODO: Encoding of different types as helpers for View
    // TODO: Perhaps, to side-step audit LOC we can do it in a view contract which will not be audited since it's just a way to populate calldata

    // // TODO: Consider adding more post-op checks
    // function _hardcodedPostOpenChecks(address originalCaller) internal {
    //     uint256 newCdpCount = sortedCdps.cdpCountOf(originalCaller);
    //     require(newCdpCount > initialCdpCount, "LeverageMacro: no CDP created!");
    //     bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(originalCaller, newCdpCount - 1);
    // }

    function onFlashLoan(address initiator, address token, uint256 amount, uint256 fee, bytes calldata data)
        external
        override
        returns (bytes32)
    {
        // Verify we started the FL
        require(initiator == address(this), "LeverageMacro: wrong initiator for flashloan");

        // Ensure the caller is the intended contract
        if (token == address(ebtcToken)) {
            require(msg.sender == address(borrowerOperations), "LeverageMacro: wrong lender for eBTC flashloan");
        } else {
            // Enforce that this is either eBTC or stETH
            // If we allow anything then the forwardedCaller invariant will break
            require(msg.sender == address(activePool), "LeverageMacro: wrong lender for stETH flashloan");
        }

        // NOTE: Because of the fact that the forward the caller, we must only allow fallback from known contracts
        // Else a malicious contract, that changes the data would be able to inject a forwarded caller


        // Get the data
        // We will get the first byte of data for enum an type
        // The rest of the data we can decode based on the operation type from calldata
        // Then we can do multiple hooks and stuff
        (LeverageMacroOperation memory operation) = decodeFLData(data);

        _handleOperation(operation, operation.forwardedCaller);

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
    function _openCdpCallback(bytes memory data, address forwardedCaller) internal {
        OpenCdpOperation memory flData = abi.decode(data, (OpenCdpOperation));
        /**
         * Open CDP and Emit event
         */
        bytes32 _cdpId = borrowerOperations.openCdpFor(
            flData.eBTCToMint, flData._upperHint, flData._lowerHint, flData.stETHToDeposit, forwardedCaller
        );

        // Tokens will be swept to msg.sender
        // NOTE: that you need to repay the FL here, which will happen automatically
    }

    /// @dev Must be memory since we had to decode it
    function _closeCdpCallback(bytes memory data, address forwardedCaller) internal {
        CloseCdpOperation memory flData = abi.decode(data, (CloseCdpOperation));

        // Initiator must be added by this contract, else it's not trusted
        borrowerOperations.closeCdpFor(flData._cdpId, forwardedCaller);
    }

    /// @dev Must be memory since we had to decode it
    function _adjustCdpCallback(bytes memory data, address forwardedCaller) internal {
        AdjustCdpOperation memory flData = abi.decode(data, (AdjustCdpOperation));

        borrowerOperations.adjustCdpFor(
            flData._cdpId,
            flData._collWithdrawal,
            flData._EBTCChange,
            flData._isDebtIncrease,
            flData._upperHint,
            flData._lowerHint,
            flData._collAddAmount,
            forwardedCaller
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
