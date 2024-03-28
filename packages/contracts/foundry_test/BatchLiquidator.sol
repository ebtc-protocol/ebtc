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

interface IV3SwapRouter {
    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    /// @notice Swaps `amountIn` of one token for as much as possible of another along the specified path
    /// @param params The parameters necessary for the multi-hop swap, encoded as `ExactInputParams` in calldata
    /// @return amountOut The amount of the received token
    function exactInput(
        ExactInputParams calldata params
    ) external payable returns (uint256 amountOut);
}

interface IAddressGetter {
    function cdpManager() external view returns (address);

    function ebtcToken() external view returns (address);

    function priceFeed() external view returns (address);

    function collateral() external view returns (address);
}

contract BatchLiquidator {
    using SafeERC20 for IERC20;

    bytes32 constant FLASH_LOAN_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");
    uint24 constant POOL_FEE_100 = 100;
    uint24 constant POOL_FEE_500 = 500;
    uint256 constant SLIPPAGE_LIMIT_PRECISION = 1e5;

    ISyncedLiquidationSequencer public immutable syncedLiquidationSequencer;
    ICdpManager public immutable cdpManager;
    IBorrowerOperations public immutable borrowerOperations;
    IEBTCToken public immutable ebtcToken;
    ICollateralToken public immutable stETH;
    IWstETH public immutable wstETH;
    address public immutable weth;
    address public immutable wbtc;
    IPriceFeed public immutable priceFeed;
    IV3SwapRouter public immutable swapRouter;
    address public immutable owner;

    constructor(
        address _sequencer, 
        address _borrowerOperations, 
        address _wstETH,
        address _weth,
        address _wbtc,
        address _swapRouter,
        address _owner
    ) {
        syncedLiquidationSequencer = ISyncedLiquidationSequencer(_sequencer);
        borrowerOperations = IBorrowerOperations(_borrowerOperations);
        cdpManager = ICdpManager(IAddressGetter(_borrowerOperations).cdpManager());
        ebtcToken = IEBTCToken(IAddressGetter(_borrowerOperations).ebtcToken());
        priceFeed = IPriceFeed(IAddressGetter(_borrowerOperations).priceFeed());
        stETH = ICollateralToken(IAddressGetter(_borrowerOperations).collateral());
        wstETH = IWstETH(_wstETH);
        weth = _weth;
        wbtc = _wbtc;
        swapRouter = IV3SwapRouter(_swapRouter);
        owner = _owner;

        // For flash loan repayment
        IERC20(address(ebtcToken)).safeApprove(address(borrowerOperations), type(uint256).max);

        // For wrapping
        IERC20(address(stETH)).safeApprove(address(wstETH), type(uint256).max);

        // For trading
        IERC20(address(wstETH)).safeApprove(address(swapRouter), type(uint256).max);
    }

    function _getCdpsToLiquidate(uint256 _n) private returns (bytes32[] memory cdps, uint256 flashLoanAmount) {
        cdps = syncedLiquidationSequencer.sequenceLiqToBatchLiq(_n);

        for (uint256 i; i < cdps.length; i++) {
            flashLoanAmount += cdpManager.getSyncedCdpDebt(cdps[i]);
        }
    }

    function sweep(address token) external {
        IERC20(token).safeTransfer(owner, IERC20(token).balanceOf(address(this)));
    }

    function batchLiquidate(uint256 _n, uint256 _slippageLimit) external {
        (bytes32[] memory cdps, uint256 flashLoanAmount) = _getCdpsToLiquidate(_n);

        IERC3156FlashLender(address(borrowerOperations)).flashLoan(
            IERC3156FlashBorrower(address(this)),
            address(ebtcToken),
            flashLoanAmount,
            abi.encode(cdps, _slippageLimit)
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

        (bytes32[] memory cdps, uint256 slippageLimit) = abi.decode(data, (bytes32[], uint256));

        cdpManager.batchLiquidateCdps(cdps);

        uint256 collBalance = stETH.balanceOf(address(this));

        _swapStethToEbtc(collBalance, _calcMinAmount(collBalance, slippageLimit));

        return FLASH_LOAN_SUCCESS;
    }

    function _calcMinAmount(uint256 _collBalance, uint256 _slippageLimit) private returns (uint256) {
        uint256 price = priceFeed.fetchPrice();
        return (_collBalance * price * _slippageLimit) / (SLIPPAGE_LIMIT_PRECISION *  1e18);
    }

    function _swapStethToEbtc(uint256 _collBalance, uint256 _minEbtcOut) internal returns (uint256) {
        // STETH -> WSTETH
        uint256 wstETHCol = _lidoDepositStethToWstETH(_collBalance);

        // WSTETH -> WETH -> WBTC -> eBTC
        return _uniSwapWstETHToEbtc(wstETHCol, _minEbtcOut);
    }

    function _lidoDepositStethToWstETH(uint256 _initialStETH) internal returns (uint256) {
        return IWstETH(address(wstETH)).wrap(_initialStETH);
    }

    function _uniSwapWstETHToEbtc(uint256 _wstETHAmount, uint256 _minEbtcOut) internal returns (uint256) {
        IV3SwapRouter.ExactInputParams memory params = IV3SwapRouter.ExactInputParams({
            path: abi.encodePacked(
                address(wstETH), POOL_FEE_100, address(weth), POOL_FEE_500, address(wbtc), POOL_FEE_500, address(ebtcToken)
            ),
            recipient: address(this),
            amountIn: _wstETHAmount,
            amountOutMinimum: _minEbtcOut
        });

        return swapRouter.exactInput(params);
    }
}