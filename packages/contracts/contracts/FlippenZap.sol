// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./Interfaces/IERC3156FlashBorrower.sol";
import "./Interfaces/IERC3156FlashLender.sol";
import "./Interfaces/IBorrowerOperations.sol";
import "./Interfaces/IPriceFeed.sol";
import "./Interfaces/ICdpManager.sol";
import "./Dependencies/ICollateralToken.sol";
import "./Dependencies/IBalancerV2Vault.sol";
import "./Dependencies/Ownable.sol";

/// @title This contracts aims to facilitate convenient one-click Zap around eBTC system
/// @notice Any donated or mis-transferred token sitting in this contract will be stuck forever
contract FlippenZap is IERC3156FlashBorrower, Ownable {
    /// @notice This parameter limit the highest leverage a CDP could be created with
    /// @notice This max leverage would result a CDP with ICR around 125%
    uint8 public constant MAX_REASONABLE_LEVERAGE = 5;
    uint256 private constant ICR_SMALL_BUFFER = 12345678901234567; // 1.23%
    bytes32 private constant FL_BORROWER_RETURN = keccak256("ERC3156FlashBorrower.onFlashLoan");
    uint256 public constant MCR = 1100000000000000000; // 110%
    uint256 public constant CCR = 1250000000000000000; // 125%
    uint256 public constant MIN_NET_STETH_BALANCE = 2e18;
    uint256 public slippage = 500; // default 5% allowed slippage for eBTC<->stETH
    uint256 public constant MAX_SLIPPAGE = 10000;

    /// @notice This is the interface of BorrowerOperations contract within eBTC system
    IBorrowerOperations public ebtcBorrowerOperations;

    /// @notice This the interface of PriceFeed contract within eBTC system
    IPriceFeed public ebtcPriceFeed;

    /// @notice This the interface of CdpManager contract within eBTC system
    ICdpManager public ebtcCdpManager;

    /// @notice This the interface of collateral token contract used in eBTC system
    ICollateralToken public ebtcCollToken;

    /// @notice This the interface of eBTC token contract
    IEBTCToken public ebtcToken;

    /// @notice This the interface of balancer for eBTC<->stETH pair liquidity
    IBalancerV2Vault public balancerVault;

    /// @notice This the pool ID for eBTC<->stETH pair in Balancer Vault
    bytes32 public balancerPoolId;

    mapping(address => uint256) private _zapLeveragedCdpCount;
    mapping(address => mapping(uint256 => bytes32)) private _zapLeveragedCdps;

    /// @param _borrowerOperations The address of BorrowerOperations contract within eBTC system
    /// @param _priceFeed The address of PriceFeed contract within eBTC system
    /// @param _cdpManager The address of CdpManager contract within eBTC system
    /// @param _collToken The address of collateral token used in eBTC system
    /// @param _ebtcToken The address of eBTC token
    /// @param _balancerVault The address of Balancer Vault
    /// @param _balancerPoolId The pool ID of eBTC-stETH pair in Balancer Vault
    constructor(
        address _borrowerOperations,
        address _priceFeed,
        address _cdpManager,
        address _collToken,
        address _ebtcToken,
        address _balancerVault,
        bytes32 _balancerPoolId
    ) public {
        require(_borrowerOperations != address(0), "FlippenZap: empty BorrowerOperations address");
        require(_priceFeed != address(0), "FlippenZap: empty PriceFeed address");
        require(_cdpManager != address(0), "FlippenZap: empty CdpManager address");
        require(_collToken != address(0), "FlippenZap: empty collateral token address");
        require(_ebtcToken != address(0), "FlippenZap: empty eBTC token address");
        require(_balancerVault != address(0), "FlippenZap: empty Balancer vault address");
        require(_balancerPoolId != bytes32(0), "FlippenZap: empty Balancer pool ID");

        ebtcBorrowerOperations = IBorrowerOperations(_borrowerOperations);
        ebtcPriceFeed = IPriceFeed(_priceFeed);
        ebtcCdpManager = ICdpManager(_cdpManager);
        ebtcCollToken = ICollateralToken(_collToken);
        ebtcToken = IEBTCToken(_ebtcToken);
        balancerVault = IBalancerV2Vault(_balancerVault);
        balancerPoolId = _balancerPoolId;

        ebtcCollToken.approve(_borrowerOperations, type(uint256).max);
        ebtcToken.approve(_borrowerOperations, type(uint256).max);

        ebtcCollToken.approve(_balancerVault, type(uint256).max);
        ebtcToken.approve(_balancerVault, type(uint256).max);
    }

    /// @notice This function allows caller to create a leveraged CDP with an initial collateral.
    /// @notice The caller has to approve this contract as a valid PositionManager via BorrowerOperations
    /// @notice and approve this contract to spend _initialStETH amount of collateral
    /// @param _initialStETH The initial amount of stETH used as collateral
    /// @param _leverage The expected leverage for this long position, should be no more than MAX_REASONABLE_LEVERAGE
    /// @return The CdpId created with owner as the caller
    function enterLongEth(uint256 _initialStETH, uint256 _leverage) external returns (bytes32) {
        require(_initialStETH > MIN_NET_STETH_BALANCE, "FlippenZap: initial principal too small");
        require(_leverage <= MAX_REASONABLE_LEVERAGE, "FlippenZap: _leverage is too big");
        require(_leverage > 0, "FlippenZap: _leverage is too small");

        // under the covers:
        // mints eBTC against stETH collateral and
        // sells the eBTC back for stETH.

        bytes32 _newCdp;
        uint256 _collToLoan = _leverage > 1 ? (_leverage - 1) * _initialStETH : 0;
        uint256 _expectedColl = _collToLoan + _initialStETH;
        uint256 _expectedDebt;

        // transfer initial collateral
        ebtcCollToken.transferFrom(msg.sender, address(this), _initialStETH);

        if (_collToLoan > 0) {
            _expectedDebt = _calculateCdpDebtForZap(_collToLoan, _leverage);
            // Initialize the flashloan to do the leverage
            uint256 _cdpCountBefore = _zapLeveragedCdpCount[msg.sender];
            IERC3156FlashLender(address(ebtcBorrowerOperations)).flashLoan(
                IERC3156FlashBorrower(address(this)),
                address(ebtcToken),
                _expectedDebt,
                abi.encode(address(msg.sender), _initialStETH, _collToLoan)
            );
            _newCdp = _zapLeveragedCdps[msg.sender][_cdpCountBefore + 1];

            // No eBTC left since all is used repay the flashloan
            // resulting only a leveraged CDP
        } else {
            _expectedDebt = _calculateCdpDebtForZap(_expectedColl, _leverage);
            require(
                ebtcCollToken.balanceOf(address(this)) >= _expectedColl,
                "FlippenZap: not enough collateral to openCdpFor()"
            );
            _newCdp = ebtcBorrowerOperations.openCdpFor(
                _expectedDebt,
                bytes32(0),
                bytes32(0),
                _expectedColl,
                msg.sender
            );

            // transfer minted eBTC
            // TODO do we really need to swap minted eBTC here on caller's behalf?
            require(
                ebtcToken.balanceOf(address(this)) >= _expectedDebt,
                "FlippenZap: no expected debt after openCdpFor()"
            );
            ebtcToken.transfer(msg.sender, _expectedDebt);
        }
        return _newCdp;
    }

    function _calculateCdpDebtForZap(uint256 _coll, uint256 _leverage) internal returns (uint256) {
        uint256 denominator = _leverage > 1 ? 1e18 : (CCR + ICR_SMALL_BUFFER);
        uint256 _price = ebtcPriceFeed.fetchPrice();
        return (_coll * _price) / denominator;
    }

    function _singleSwapViaBalancer(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 expectedOut
    ) internal returns (uint256) {
        SingleSwap memory singleSwap = SingleSwap(
            balancerPoolId,
            SwapKind.GIVEN_IN,
            tokenIn,
            tokenOut,
            amountIn,
            ""
        );
        FundManagement memory funds = FundManagement(address(this), false, address(this), false);
        return balancerVault.swap(singleSwap, funds, expectedOut, block.timestamp);
    }

    /// @inheritdoc IERC3156FlashBorrower
    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external override returns (bytes32) {
        require(initiator == address(this), "FlippenZap: flashloan has to be initiated from this");
        require(
            msg.sender == address(ebtcBorrowerOperations),
            "FlippenZap: flashloan call has to be from BorrowerOperations"
        );
        require(token == address(ebtcToken), "FlippenZap: flashloan token has to be eBTC");
        require(amount > 0, "FlippenZap: flashloan amount has to be above zero");

        // decode from flashloan parameter for new leveraged CDP
        (address _borrower, uint256 _initialColl, uint256 _collToLoan) = abi.decode(
            data,
            (address, uint256, uint256)
        );
        uint256 _expectedDebt = amount + fee;

        // swap eBTC to collateral
        uint256 _outAmount = _singleSwapViaBalancer(
            address(ebtcToken),
            address(ebtcCollToken),
            amount,
            ((_collToLoan * (MAX_SLIPPAGE - slippage)) / MAX_SLIPPAGE)
        );
        uint256 _expectedColl = _initialColl + _outAmount;
        require(
            ebtcCollToken.balanceOf(address(this)) >= _expectedColl,
            "FlippenZap: not enough collateral for leveraged CDP"
        );

        // open leveraged CDP
        uint256 _cdpCountBefore = _zapLeveragedCdpCount[_borrower];
        bytes32 _newCdp = ebtcBorrowerOperations.openCdpFor(
            _expectedDebt,
            bytes32(0),
            bytes32(0),
            _expectedColl,
            _borrower
        );
        _zapLeveragedCdps[_borrower][_cdpCountBefore + 1] = _newCdp;

        // prepare the repayment
        require(
            ebtcToken.balanceOf(address(this)) >= _expectedDebt,
            "FlippenZap: not enough debt minted from leveraged CDP"
        );

        return FL_BORROWER_RETURN;
    }

    /// @notice Set new eBTC<->stETH pool ID in Balance Vault
    /// @param _newPoolID The new eBTC<->stETH pool ID in Balance Vault
    function setBalancerPoolID(bytes32 _newPoolID) external onlyOwner {
        require(_newPoolID != bytes32(0), "FlippenZap: empty Balancer pool ID");
        require(_newPoolID != balancerPoolId, "FlippenZap: same Balancer pool ID");
        balancerPoolId = _newPoolID;
    }

    /// @notice Set new slippage expected in Zap swap
    /// @param _slippage The new slippage expected in Zap swap
    function setSlippage(uint256 _slippage) external onlyOwner {
        require(_slippage < MAX_SLIPPAGE, "FlippenZap: slippage too large");
        require(_slippage > 0, "FlippenZap: slippage should be above zero");
        slippage = _slippage;
    }
}
