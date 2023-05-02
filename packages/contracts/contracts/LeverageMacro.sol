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
    IEBTCToken public immutable ebtcToken;
    ISortedCdps public immutable sortedCdps;
    ICollateralToken public immutable stETH;

    event LeveragedCdpOpened(address _initiator, uint256 _debt, uint256 _coll, bytes32 _cdpId);

    bytes32 constant FLASH_LOAN_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    // Leverage Macro should receive a request and set that data
    // Then perform the request

    constructor(
        address _borrowerOperationsAddress,
        address _ebtc,
        address _coll,
        address _sortedCdps
    ) {
        borrowerOperations = IBorrowerOperations(_borrowerOperationsAddress);
        ebtcToken = IEBTCToken(_ebtc);
        stETH = ICollateralToken(_coll);
        sortedCdps = ISortedCdps(_sortedCdps);

        // set allowance for flashloan lender/CDP open
        ebtcToken.approve(_borrowerOperationsAddress, type(uint256).max);
        stETH.approve(_borrowerOperationsAddress, type(uint256).max);
    }


    struct SwapOperation {
        // Swap Data
        address tokenForSwap;
        address addressForApprove;
        uint256 exactApproveAmount;
        address addressForSwap;
        bytes calldataForSwap;

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
        address borrower;
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
        // address _forwardedCaller
    }

    // Repay and Close
    struct CloseCdpOperation {
        bytes32 _cdpId;
        // address _forwardedCaller
    }

    function decodeFLData(bytes calldata data) public view returns (OperationType, SwapOperation memory, bytes memory) {
        (OperationType theType, SwapOperation memory swapData, bytes memory theBytes /* These bytes are of type OperationType */) = abi.decode(data, (OperationType, SwapOperation, bytes));
        return (theType, swapData, theBytes);
    }

    /// @notice Given the inputs returns the Bytes for the contract to pass via FL
    /// @dev Must be memory because it's encoded locally
    /// @dev Maybe we can encode from caller and save the cost, but that makes it less practical to perform onChain
    function encodeOpenCdpOperation(OpenCdpOperation calldata flData) external view returns (bytes memory encoded) {
        encoded = abi.encode(flData);
    }

    /// @notice Given the data returns the data for the FL to decode
    function decodeOpenCdpOperation(bytes calldata encoded) public view returns (OpenCdpOperation memory openCdpData) {
        (
            openCdpData
        ) = abi.decode(encoded, (OpenCdpOperation));
    }

    function openCdpLeveraged(
        // FL Settings
        uint256 initialEBTCAmount,
        uint256 eBTCToBorrow,
        // NOTE: We pass the encoded data directly because it's already complex enough
        bytes calldata encodedFlData // (type, data), where data is either OpenCdp, CloseCdp, AdjustCdp + Swap Data
    ) external returns (bytes32) {
        // NOTE: data validation is on FL so we avoid any gotcha

        // Get the initial amount, we'll verify the cdpCount has increased
        uint256 initialCdpCount = sortedCdps.cdpCountOf(msg.sender);

        // Take the initial eBTC Amount
        ebtcToken.transferFrom(msg.sender, address(this), initialEBTCAmount);

        // NOTE: You need to make sure there's enough for swap and fee to work
        // TODO: Encode the Type of the Operation and then the Bytes for what to do

        // take eBTC flashloan
        IERC3156FlashLender(address(borrowerOperations)).flashLoan(
            IERC3156FlashBorrower(address(this)), address(ebtcToken), eBTCToBorrow, encodedFlData
        );

        // Verify they got the new CDP
        // Verify the leverage is the intended one -> Not necessary, the leverage is implicit in the CDP status
        // Safety of operation is also implicit in the status

        /**
         * VERIFY OPENING *
         */
        // We do fetch because it's cheaper cause we always write in those slots anyway
        // 100 + 100
        uint256 newCdpCount = sortedCdps.cdpCountOf(msg.sender);
        require(newCdpCount > initialCdpCount, "LeverageMacro: no CDP created!");
        bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(msg.sender, newCdpCount - 1);


        _sweepToCaller();

        // Send eBTC to caller + Cdp (NEED TO ALLOW TRANSFERING ON CREATION)
        return cdpId;
    }




    function closeCdpLeveraged() public {
        // Do the FL

        // Do the Swap

        // Ultimately just pass the values

         // Do a swap after if specified
    }

    function adjustCdpLeveraged() public {
        // Do the FL

        // Do the Swap

        // Ultimately just pass the values

        // Do a swap after if specified
    }



    function onFlashLoan(address initiator, address token, uint256 amount, uint256 fee, bytes calldata data)
        external
        override
        returns (bytes32)
    {
        // Verify we started the FL
        require(initiator == address(this), "LeverageMacro: wrong initiator for flashloan");

        // Ensure the caller is the intended contract
        require(msg.sender == address(borrowerOperations), "LeverageMacro: wrong lender for eBTC flashloan");

        // Get the data
        // We will get the first byte of data for enum an type
        // The rest of the data we can decode based on the operation type from calldata
        // Then we can do multiple hooks and stuff
        (  OperationType theType, 
            SwapOperation memory swapData, 
            bytes memory theBytes
        ) = decodeFLData(data);

        _doSwap(swapData);

        // Based on the type we do stuff
        if(theType == OperationType.OpenCdpOperation) {
            _openCdpCallback(data);
        } else if(theType == OperationType.CloseCdpOperation) {
            _closeCdpCallback(data);
        } else if(theType == OperationType.AdjustCdpOperation) {
            _adjustCdpCallback(data);
        }

        return FLASH_LOAN_SUCCESS;
    }

    function _doSwap(SwapOperation memory swapData) internal {
        // TODO: Ensure all approves and calls are safe here

        // Exact approve
        IERC20(swapData.tokenForSwap).approve(swapData.addressForApprove, swapData.exactApproveAmount);

        // Call and perform swap // TODO Technically approval may be different from target, something to keep in mind
        // TODO: Block calling `BO` else it's an issue
        // Must block all systems contract I think
        // TODO: BLOCK ALL SYSTEM CALL PLS SER
        (bool success, ) = excessivelySafeCall(swapData.addressForSwap, gasleft(), 0, 32, swapData.calldataForSwap);
        require(success, "Call has failed"); 
        
        // Approve back to 0
        // Enforce exact approval
        // Can use max because the tokens are OZ
        // val -> 0 -> 0 -> val means this is safe to repeat since even if full approve is unused, we always go back to 0 after
        IERC20(swapData.tokenForSwap).approve(swapData.addressForApprove, 0);

        // Perform the slippage check
        // TODO: Perhaps make it options
        // TODO TODO Perhaps allow to skim vs use all of the out
        if(swapData.expectedMinOut > 0) {
            require(IERC20(swapData.tokenToCheck).balanceOf(address(this)) > swapData.expectedMinOut);
        }
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


    function _openCdpCallback(bytes memory data) internal {

    }

    function _closeCdpCallback(bytes memory data) internal {
        revert("TODO");
    }

    function _adjustCdpCallback(bytes memory data) internal {
        revert("TODO");
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
