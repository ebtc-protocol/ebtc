pragma solidity 0.8.17;

import "./Interfaces/IBorrowerOperations.sol";
import "./Interfaces/IERC3156FlashLender.sol";
import "./Interfaces/IEBTCToken.sol";
import "./Interfaces/ICdpManager.sol";
import "./Interfaces/ISortedCdps.sol";
import "./Interfaces/IPriceFeed.sol";
import "./Dependencies/ICollateralToken.sol";
import "./Dependencies/IBalancerV2Vault.sol";

import "./FlashLoanMacroReceiver.sol";

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
    address public immutable borrowerOperations;
    address public immutable activePool;
    ICdpCdps public immutable cdpManager;
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
        address _cdpManager,
        address _ebtc,
        address _coll,
        address _sortedCdps,
        address _flashLoanMacroReceiver
    ) {
        borrowerOperations = _borrowerOperationsAddress;
        activePool = _activePool;
        cdpManager = ICdpCdps(_cdpManager);
        ebtcToken = IEBTCToken(_ebtc);
        stETH = ICollateralToken(_coll);
        sortedCdps = ISortedCdps(_sortedCdps);

        flashLoanMacroReceiver = address(
            new FlashLoanMacroReceiver(
                    _borrowerOperationsAddress,
            _activePool,
            _ebtc,
            _coll,
            _sortedCdps,
            address(this)
            )
        );

        // NO allowances here, this contract just has allowance from users and only sends to FLMacroReceiver
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
        require(operation.forwardedCaller == msg.sender); // Enforce encoded properly

        // Call FL Here, then the stuff below needs to happen inside the FL
        if (operation.amountToTransferIn > 0) {
            // Not safe because OZ for our cases, if you use USDT it's your prob friend
            // NOTE: Send directly to flashLoanMacroReceiver
            IERC20(operation.tokenToTransferIn).transferFrom(
                msg.sender, address(flashLoanMacroReceiver), operation.amountToTransferIn
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
                IERC3156FlashBorrower(address(flashLoanMacroReceiver)),
                address(ebtcToken),
                borrowAmount,
                abi.encode(operation)
            );
        } else if (flType == FlashLoanType.stETH) {
            IERC3156FlashLender(address(activePool)).flashLoan(
                IERC3156FlashBorrower(address(flashLoanMacroReceiver)),
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

            // TODO: These checks maybe should be made more lenient else some dust will always accrue
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
