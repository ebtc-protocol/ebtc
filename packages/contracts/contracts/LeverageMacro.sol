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

    struct FLOperation {
        // Open CDP For Data
        uint256 eBTCToMint;
        bytes32 _upperHint;
        bytes32 _lowerHint;
        uint256 stETHToDeposit;
        address borrower;
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

    /// @notice Given the inputs returns the Bytes for the contract to pass via FL
    /// @dev Must be memory because it's encoded locally
    /// @dev Maybe we can encode from caller and save the cost, but that makes it less practical to perform onChain
    function encodeOperation(FLOperation calldata flData) external view returns (bytes memory encoded) {
        encoded = abi.encode(flData);
    }

    /// @notice Given the data returns the data for the FL to decode
    function decodeOperation(bytes calldata encoded) public view returns (FLOperation memory flData) {
        (
            flData
        ) = abi.decode(encoded, (FLOperation));
    }

    function openCdpLeveraged(
        // FL Settings
        uint256 initialEBTCAmount,
        uint256 eBTCToBorrow,
        // NOTE: We pass the encoded data directly because it's already complex enough
        bytes calldata encodedFlData
    ) external returns (bytes32) {
        // NOTE: data validation is on FL so we avoid any gotcha

        // Get the initial amount, we'll verify the cdpCount has increased
        uint256 initialCdpCount = sortedCdps.cdpCountOf(msg.sender);

        // Take the initial eBTC Amount
        ebtcToken.transferFrom(msg.sender, address(this), initialEBTCAmount);

        // NOTE: You need to make sure there's enough for swap and fee to work

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

        // Send eBTC to caller + Cdp (NEED TO ALLOW TRANSFERING ON CREATION)
        return cdpId;
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
        (FLOperation memory flData) = decodeOperation(data);

        // NOTE: This is the check that will be enforced, so we do it here
        require(flData.tokenForSwap == address(ebtcToken)); // TODO: For now just eBTC so we have a easier time
        require(flData.tokenToCheck == address(stETH)); // TODO: For now just stETH so we have a easier time

        // Check this to avoid griefing, if we change to local approvals on each operation we can get rid of this check
        require(flData.addressForApprove != address(borrowerOperations));

        if (token == address(ebtcToken)) {
            /**
             * SWAP from eBTC to stETH *
             */

            // Exact approve
            IERC20(flData.tokenForSwap).approve(flData.addressForApprove, flData.exactApproveAmount);

            // Call and perform swap // TODO Technically approval may be different from target, something to keep in mind
            (bool success, ) = excessivelySafeCall(flData.addressForSwap, gasleft(), 0, 32, flData.calldataForSwap);
            require(success, "Call has failed"); 
            // Approve back to 0
            // Enforce exact approval
            // Can use max because the tokens are OZ
            // val -> 0 -> 0 -> val means this is safe to repeat since even if full approve is unused, we always go back to 0 after
            IERC20(flData.tokenForSwap).approve(flData.addressForApprove, 0);

            // Perform the slippage check
            // TODO: Perhaps make it options
            // TODO TODO Perhaps allow to skim vs use all of the out
            require(IERC20(flData.tokenToCheck).balanceOf(address(this)) > flData.expectedMinOut);

            /**
             * Open CDP AND REPAY *
             */
            bytes32 _cdpId = borrowerOperations.openCdpFor(flData.eBTCToMint, flData._upperHint, flData._lowerHint, flData.stETHToDeposit, flData.borrower);
            emit LeveragedCdpOpened(flData.borrower, flData.eBTCToMint, flData.stETHToDeposit, _cdpId);

        }
        return FLASH_LOAN_SUCCESS;
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
