pragma solidity 0.8.17;

import "./Interfaces/IBorrowerOperations.sol";
import "./Interfaces/IERC3156FlashLender.sol";
import "./Interfaces/IEBTCToken.sol";
import "./Interfaces/ISortedCdps.sol";
import "./Interfaces/IPriceFeed.sol";
import "./Dependencies/ICollateralToken.sol";
import "./Dependencies/IBalancerV2Vault.sol";

/**
    Allows specifying arbitrary operations to lever up
    NOTE: Due to security concenrs
    LeverageMacro accepts allowances and transfers token to FlashLoanMacroReceiver
    // FlashLoanMacroReceiver can perform ARBITRARY CALLS YOU WILL LOSE ALL ASSETS IF YOU APPROVE IT
    LeverageMacro on the other hand is safe to approve as it cannot move your funds without your consent
 */
contract LeverageMacro {
    address public immutable borrowerOperations;
    address public immutable activePool;
    IEBTCToken public immutable ebtcToken;
    ISortedCdps public immutable sortedCdps;
    ICollateralToken public immutable stETH;

    address flashLoanMacroReceiver; // TODO: Prob deploy via constructor and make immutable

    bytes32 constant FLASH_LOAN_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    // Leverage Macro should receive a request and set that data
    // Then perform the request

    constructor(
        address _borrowerOperationsAddress,
        address _activePool,
        address _ebtc,
        address _coll,
        address _sortedCdps,
        address _flashLoanMacroReceiver
    ) {
        borrowerOperations = _borrowerOperationsAddress;
        activePool = _activePool;
        ebtcToken = IEBTCToken(_ebtc);
        stETH = ICollateralToken(_coll);
        sortedCdps = ISortedCdps(_sortedCdps);

        flashLoanMacroReceiver = _flashLoanMacroReceiver;

        // NO allowances here, this contract just has allowance from users and only sends to FLMacroReceiver
    }

    enum FlashLoanType {
        stETH,
        eBTC
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
    function doOperation(FlashLoanType flType, uint256 borrowAmount, LeverageMacroOperation calldata operation)
        external
    {
        require(operation.forwardedCaller == msg.sender); // Enforce encoded properly

        // Call FL Here, then the stuff below needs to happen inside the FL
        if (operation.amountToTransferIn > 0) {
            // Not safe because OZ for our cases, if you use USDT it's your prob friend
            // NOTE: Send directly to flashLoanMacroReceiver
            IERC20(operation.tokenToTransferIn).transferFrom(msg.sender, address(flashLoanMacroReceiver), operation.amountToTransferIn);
        }

        // Take eBTC or stETH FlashLoan
        if (flType == FlashLoanType.eBTC) {
            IERC3156FlashLender(address(borrowerOperations)).flashLoan(
                IERC3156FlashBorrower(address(flashLoanMacroReceiver)), address(ebtcToken), borrowAmount, abi.encode(operation)
            );
        } else if (flType == FlashLoanType.stETH) {
            IERC3156FlashLender(address(activePool)).flashLoan(
                IERC3156FlashBorrower(address(flashLoanMacroReceiver)), address(stETH), borrowAmount, abi.encode(operation)
            );
        } else {
            // TODO: If enum OOB reverts, can remove this, can also leave as explicity
            revert("Must be valid due to forwarding of users");
        }

        // TODO: Post Operations Checks
        // CDP ID.isClosed for Close
        // CDP ID.debt, collateral

        // Sweep here
        _sweepToCaller();
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


    // TODO: Encoding of different types as helpers for View
    // TODO: Perhaps, to side-step audit LOC we can do it in a view contract which will not be audited since it's just a way to populate calldata

    // // TODO: Consider adding more post-op checks
    // function _hardcodedPostOpenChecks(address originalCaller) internal {
    //     uint256 newCdpCount = sortedCdps.cdpCountOf(originalCaller);
    //     require(newCdpCount > initialCdpCount, "LeverageMacro: no CDP created!");
    //     bytes32 cdpId = sortedCdps.cdpOfOwnerByIndex(originalCaller, newCdpCount - 1);
    // }


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
}
