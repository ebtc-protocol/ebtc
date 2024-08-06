// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../contracts/Interfaces/IERC3156FlashLender.sol";
import "../contracts/Interfaces/ISyncedLiquidationSequencer.sol";
import "../contracts/Interfaces/IBorrowerOperations.sol";
import "../contracts/Interfaces/ICdpManager.sol";
import "../contracts/Interfaces/IEBTCToken.sol";
import "../contracts/Interfaces/IWstETH.sol";
import "../contracts/Dependencies/ICollateralToken.sol";
import "../contracts/Dependencies/SafeERC20.sol";

interface IAddressGetter {
    function cdpManager() external view returns (address);

    function ebtcToken() external view returns (address);

    function priceFeed() external view returns (address);

    function collateral() external view returns (address);
}

contract BatchLiquidator {
    using SafeERC20 for IERC20;

    bytes32 constant FLASH_LOAN_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    ISyncedLiquidationSequencer public immutable syncedLiquidationSequencer;
    ICdpManager public immutable cdpManager;
    IBorrowerOperations public immutable borrowerOperations;
    IEBTCToken public immutable ebtcToken;
    ICollateralToken public immutable stETH;
    address public immutable dex;
    address public immutable owner;

    error GetCollateralOnly(uint256 amount);

    constructor(address _sequencer, address _borrowerOperations, address _dex, address _owner) {
        syncedLiquidationSequencer = ISyncedLiquidationSequencer(_sequencer);
        borrowerOperations = IBorrowerOperations(_borrowerOperations);
        cdpManager = ICdpManager(IAddressGetter(_borrowerOperations).cdpManager());
        ebtcToken = IEBTCToken(IAddressGetter(_borrowerOperations).ebtcToken());
        stETH = ICollateralToken(IAddressGetter(_borrowerOperations).collateral());
        dex = _dex;
        owner = _owner;

        // For flash loan repayment
        IERC20(address(ebtcToken)).safeApprove(address(borrowerOperations), type(uint256).max);

        // For trading
        IERC20(address(stETH)).safeApprove(address(dex), type(uint256).max);
    }

    function _getCdpsToLiquidate(
        uint256 _n
    ) private returns (bytes32[] memory cdps, uint256 flashLoanAmount) {
        cdps = syncedLiquidationSequencer.sequenceLiqToBatchLiq(_n);

        for (uint256 i; i < cdps.length; i++) {
            flashLoanAmount += cdpManager.getSyncedCdpDebt(cdps[i]);
        }
    }

    function sweep(address token) external {
        IERC20(token).safeTransfer(owner, IERC20(token).balanceOf(address(this)));
    }

    function batchLiquidate(uint256 _n, bytes calldata exchangeData, bool getCollOnly) external {
        (bytes32[] memory cdps, uint256 flashLoanAmount) = _getCdpsToLiquidate(_n);

        IERC3156FlashLender(address(borrowerOperations)).flashLoan(
            IERC3156FlashBorrower(address(this)),
            address(ebtcToken),
            flashLoanAmount,
            abi.encode(getCollOnly, false, cdps, exchangeData, bytes32(0), bytes32(0))
        );

        ebtcToken.transfer(owner, ebtcToken.balanceOf(address(this)));
        stETH.transferShares(owner, stETH.sharesOf(address(this)));
    }

    function partiallyLiquidate(
        bytes32 _cdpId,
        uint256 _partialAmount,
        bytes32 _upperPartialHint,
        bytes32 _lowerPartialHint,
        bytes calldata exchangeData,
        bool getCollOnly
    ) external {
        bytes32[] memory cdps = new bytes32[](1);

        cdps[0] = _cdpId;

        IERC3156FlashLender(address(borrowerOperations)).flashLoan(
            IERC3156FlashBorrower(address(this)),
            address(ebtcToken),
            _partialAmount,
            abi.encode(getCollOnly, true, cdps, exchangeData, _upperPartialHint, _lowerPartialHint)
        );

        ebtcToken.transfer(owner, ebtcToken.balanceOf(address(this)));
        stETH.transferShares(owner, stETH.sharesOf(address(this)));
    }

    /// @notice Proper Flashloan Callback handler
    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external returns (bytes32) {
        // Verify we started the FL
        require(initiator == address(this), "BatchLiquidator: wrong initiator for flashloan");
        require(
            msg.sender == address(borrowerOperations),
            "BatchLiquidator: wrong lender for eBTC flashloan"
        );
        require(token == address(ebtcToken));

        (
            bool getCollOnly,
            bool partialLiq,
            bytes32[] memory cdps,
            bytes memory exchangeData,
            bytes32 upperPartialHint,
            bytes32 lowerPartialHint
        ) = abi.decode(data, (bool, bool, bytes32[], bytes, bytes32, bytes32));

        if (partialLiq) {
            cdpManager.partiallyLiquidate(cdps[0], amount, upperPartialHint, lowerPartialHint);
        } else {
            cdpManager.batchLiquidateCdps(cdps);
        }

        if (getCollOnly) {
            revert GetCollateralOnly(stETH.balanceOf(address(this)));
        }

        (bool success, ) = dex.call(exchangeData);
        require(success, "BatchLiquidator: trade failed");

        return FLASH_LOAN_SUCCESS;
    }
}
