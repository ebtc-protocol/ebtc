// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./Interfaces/IERC3156FlashBorrower.sol";
import "./Interfaces/IBorrowerOperations.sol";
import "./Interfaces/IPriceFeed.sol";
import "./Interfaces/ICdpManager.sol";
import "./Dependencies/ICollateralToken.sol";

/// @title This contracts aims to facilitate convenient one-click Zap around eBTC system
/// @notice Any donated or mis-transferred token sitting in this contract will be stuck forever
contract FlippenZap is IERC3156FlashBorrower {
    /// @notice This parameter limit the highest leverage a CDP could be created with
    uint8 public constant MAX_REASONABLE_LEVERAGE = 8;
    uint256 private constant ICR_SMALL_BUFFER = 12345678901234567; // 1.23%
    bytes32 private constant FL_BORROWER_RETURN = keccak256("ERC3156FlashBorrower.onFlashLoan");
    uint256 public constant MCR = 1100000000000000000; // 110%
    uint256 public constant CCR = 1250000000000000000; // 125%
    uint256 public constant MIN_NET_STETH_BALANCE = 2e18;

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

    /// @param _borrowerOperations The address of BorrowerOperations contract within eBTC system
    /// @param _priceFeed The address of PriceFeed contract within eBTC system
    /// @param _cdpManager The address of CdpManager contract within eBTC system
    /// @param _collToken The address of collateral token used in eBTC system
    /// @param _ebtcToken The address of eBTC token
    constructor(
        address _borrowerOperations,
        address _priceFeed,
        address _cdpManager,
        address _collToken,
        address _ebtcToken
    ) public {
        require(_borrowerOperations != address(0), "FlippenZap: empty BorrowerOperations address");
        require(_priceFeed != address(0), "FlippenZap: empty PriceFeed address");
        require(_cdpManager != address(0), "FlippenZap: empty CdpManager address");
        require(_collToken != address(0), "FlippenZap: empty collateral token address");
        require(_ebtcToken != address(0), "FlippenZap: empty eBTC token address");

        ebtcBorrowerOperations = IBorrowerOperations(_borrowerOperations);
        ebtcPriceFeed = IPriceFeed(_priceFeed);
        ebtcCdpManager = ICdpManager(_cdpManager);
        ebtcCollToken = ICollateralToken(_collToken);
        ebtcToken = IEBTCToken(_ebtcToken);

        ebtcCollToken.approve(_borrowerOperations, type(uint256).max);
        ebtcToken.approve(_borrowerOperations, type(uint256).max);
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
        uint256 _expectedDebt;
        uint256 _collToLoan = _leverage > 1 ? (_leverage - 1) * _initialStETH : 0;
        uint256 _expectedColl = _collToLoan + _initialStETH;

        // transfer initial collateral
        ebtcCollToken.transferFrom(msg.sender, address(this), _initialStETH);

        if (_collToLoan > 0) {
            // TODO with LeverageMacro initialize the flashloan to do the leverage
        } else {
            _expectedDebt = _calculateCdpDebtForZap(_expectedColl);
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

    function _calculateCdpDebtForZap(uint256 _coll) internal returns (uint256) {
        uint256 _price = ebtcPriceFeed.fetchPrice();
        uint256 _tcr = ebtcCdpManager.getSyncedTCR(_price);
        uint256 _icrDesirable;

        // check if eBTC system in Normal Mode or Recovery Mode
        if (_tcr <= CCR) {
            _icrDesirable = CCR + ICR_SMALL_BUFFER;
        } else {
            _icrDesirable = MCR + ICR_SMALL_BUFFER;
        }
        return (_coll * _price) / _icrDesirable;
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
        require(token == address(_ebtcToken), "FlippenZap: flashloan token has to be eBTC");
        require(amount > 0, "FlippenZap: flashloan amount has to be above zero");

        return FL_BORROWER_RETURN;
    }
}
