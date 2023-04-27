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
    IPriceFeed public immutable priceFeed;
    ICollateralToken public immutable collateral;

    // DEX to swap between debt and collateral
    IBalancerV2Vault public immutable balancerV2Vault;
    bytes32 public balancerV2PoolId;

    // swap slippage bps
    uint public slippageBps = 50;
    uint public constant MAX_BPS = 10000;

    // max leverage (scaled by 10000) capped by MCR: (maxLeverage + 1) > MCR * maxLeverage
    uint256 public maxLeverageBPS = 10 * MAX_BPS;

    event LeveragedCdpOpened(address _initiator, uint256 _debt, uint256 _coll, bytes32 _cdpId);

    bytes32 constant FLASH_LOAN_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    constructor(
        address _borrowerOperationsAddress,
        address _ebtc,
        address _coll,
        address _priceFeed,
        address _sortedCdps,
        address _balancerDEX,
        bytes32 _balancerPoolId
    ) {
        borrowerOperations = IBorrowerOperations(_borrowerOperationsAddress);
        ebtcToken = IEBTCToken(_ebtc);
        collateral = ICollateralToken(_coll);
        balancerV2Vault = IBalancerV2Vault(_balancerDEX);
        balancerV2PoolId = _balancerPoolId;
        priceFeed = IPriceFeed(_priceFeed);
        sortedCdps = ISortedCdps(_sortedCdps);

        // set allowance for DEX
        collateral.approve(_balancerDEX, type(uint256).max);
        ebtcToken.approve(_balancerDEX, type(uint256).max);

        // set allowance for flashloan lender/CDP open
        ebtcToken.approve(_borrowerOperationsAddress, type(uint256).max);
        collateral.approve(_borrowerOperationsAddress, type(uint256).max);
    }

    function openCdpLeveraged(
        uint _EBTCAmount,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint _collAmount
    ) external returns (bytes32, uint256) {
        // Flashloan final eBTC Balance (add buffer for fee)
        uint _collInSender = collateral.balanceOf(msg.sender);
        uint _collWorthInDebt = _getExpectedOutputAmount(true, _collInSender, 0);

        // Note this is a rather loose requirement to provide an early check
        // to ensure leverage in safe range, i.e, created CDP ICR > MCR or > TCR
        require(
            _EBTCAmount < ((maxLeverageBPS * _collWorthInDebt) / MAX_BPS),
            "LeverageMacro: too much leverage for eBTC!"
        );

        // take eBTC flashloan
        uint256 flashloanFee = IERC3156FlashLender(address(borrowerOperations)).flashFee(
            address(ebtcToken),
            _EBTCAmount
        );
        bytes memory _data = abi.encode(_upperHint, msg.sender, _lowerHint, _collAmount);
        IERC3156FlashLender(address(borrowerOperations)).flashLoan(
            IERC3156FlashBorrower(address(this)),
            address(ebtcToken),
            _EBTCAmount,
            _data
        );
        uint256 _newCdpCount = sortedCdps.cdpCountOf(msg.sender);
        require(_newCdpCount >= 1, "LeverageMacro: no CDP created!");
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(msg.sender, _newCdpCount - 1);

        // Send eBTC to caller + Cdp (NEED TO ALLOW TRANSFERING ON CREATION)
        return (_cdpId, flashloanFee);
    }

    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external override returns (bytes32) {
        require(initiator == address(this), "LeverageMacro: wrong initiator for flashloan");
        if (token == address(ebtcToken)) {
            require(
                msg.sender == address(borrowerOperations),
                "LeverageMacro: wrong lender for eBTC flashloan"
            );

            // Use eBTC Balance to Buy stETH
            uint256 _debt = amount;
            (bytes32 _upperHint, address _borrower, bytes32 _lowerHint, uint256 _coll) = abi.decode(
                data,
                (bytes32, address, bytes32, uint256)
            );
            require(
                ebtcToken.balanceOf(address(this)) >= _debt,
                "LeverageMacro: not enough borrowed eBTC!"
            );
            uint256 _swappedColl = _swapInBalancerV2(address(ebtcToken), address(collateral), _debt);

            // transfer remaining collateral from borrower
            uint _collFromSender = _coll - _swappedColl;
            collateral.transferFrom(_borrower, address(this), _collFromSender);
            require(
                collateral.balanceOf(address(this)) >= _coll,
                "LeverageMacro: not enough leveraged collateral!"
            );

            // Deposit stETH to mint eBTC
            uint256 _totalDebt = (_debt + fee);
            bytes32 _cdpId = borrowerOperations.openCdpFor(
                _totalDebt,
                _upperHint,
                _lowerHint,
                _coll,
                _borrower
            );
            emit LeveragedCdpOpened(_borrower, _totalDebt, _coll, _cdpId);

            // Repay FlashLoan + fee
            ebtcToken.transferFrom(_borrower, address(this), _totalDebt);
            require(
                ebtcToken.balanceOf(address(this)) >= _totalDebt,
                "LeverageMacro: not enough to repay eBTC!"
            );
        }
        return FLASH_LOAN_SUCCESS;
    }

    // swap in single balancer v2 pool, suppose it should be stETH/eBTC
    function _swapInBalancerV2(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal returns (uint256) {
        uint256 _expectedOut = _getExpectedOutputAmount(
            tokenIn == address(ebtcToken),
            amountIn,
            slippageBps
        );
        SingleSwap memory singleSwap = SingleSwap(
            balancerV2PoolId,
            SwapKind.GIVEN_IN,
            tokenIn,
            tokenOut,
            amountIn,
            ""
        );
        FundManagement memory funds = FundManagement(address(this), false, address(this), false);
        return balancerV2Vault.swap(singleSwap, funds, _expectedOut, block.timestamp);
    }

    function _getExpectedOutputAmount(
        bool _tradeCollForEBTC,
        uint256 _inputAmount,
        uint256 _slippage
    ) internal returns (uint256) {
        if (_inputAmount == 0) {
            return 0;
        }
        uint _price = priceFeed.fetchPrice();
        // assume eBTC token and collateral have same decimals
        return
            _tradeCollForEBTC
                ? (((_inputAmount * _price) / 1e18) * (MAX_BPS - _slippage)) / MAX_BPS
                : (((_inputAmount * 1e18) / _price) * (MAX_BPS - _slippage)) / MAX_BPS;
    }
}
