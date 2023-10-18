// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../Dependencies/SafeMath.sol";
import "../Dependencies/EbtcMath.sol";
import "../Dependencies/IERC20.sol";
import "../Interfaces/IBorrowerOperations.sol";
import "../Interfaces/ICdpManager.sol";
import "../Interfaces/IPriceFeed.sol";
import "../Interfaces/IFeeRecipient.sol";
import "./BorrowerOperationsScript.sol";
import "./ETHTransferScript.sol";
import "./LQTYStakingScript.sol";
import "../Dependencies/ICollateralToken.sol";

contract BorrowerWrappersScript is BorrowerOperationsScript, ETHTransferScript, LQTYStakingScript {
    using SafeMath for uint256;

    string public constant NAME = "BorrowerWrappersScript";

    ICdpManager immutable cdpManager;
    IPriceFeed immutable priceFeed;
    IERC20 immutable ebtcToken;
    IFeeRecipient feeRecipient;
    ICollateralToken immutable collToken;

    constructor(
        address _borrowerOperationsAddress,
        address _cdpManagerAddress,
        address _feeRecipientAddress,
        address _collTokenAddress
    )
        public
        BorrowerOperationsScript(IBorrowerOperations(_borrowerOperationsAddress))
        LQTYStakingScript(_feeRecipientAddress)
    {
        ICdpManager cdpManagerCached = ICdpManager(_cdpManagerAddress);
        cdpManager = cdpManagerCached;

        IPriceFeed priceFeedCached = cdpManagerCached.priceFeed();
        priceFeed = priceFeedCached;

        address ebtcTokenCached = address(cdpManagerCached.ebtcToken());
        ebtcToken = IERC20(ebtcTokenCached);

        IFeeRecipient lqtyStakingCached = IFeeRecipient(borrowerOperations.feeRecipientAddress());
        require(
            _feeRecipientAddress == address(lqtyStakingCached),
            "BorrowerWrappersScript: Wrong FeeRecipient address"
        );
        feeRecipient = lqtyStakingCached;

        collToken = ICollateralToken(_collTokenAddress);
    }

    function claimCollateralAndOpenCdp(
        uint256 _EBTCAmount,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _collAmount
    ) external {
        uint256 balanceBefore = collToken.balanceOf(address(this));

        // Claim collateral
        borrowerOperations.claimSurplusCollShares();

        uint256 balanceAfter = collToken.balanceOf(address(this));

        // already checked in CollSurplusPool
        assert(balanceAfter > balanceBefore);

        uint256 totalCollateral = balanceAfter.sub(balanceBefore).add(_collAmount);

        // Open cdp with obtained collateral, plus collateral sent by user
        collToken.approve(address(borrowerOperations), type(uint256).max);
        borrowerOperations.openCdp(_EBTCAmount, _upperHint, _lowerHint, totalCollateral);
    }

    function claimStakingGainsAndRecycle(
        bytes32 _cdpId,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external {
        require(address(collToken) != address(0), "!collToken");
        uint256 collBalanceBefore = collToken.balanceOf(address(this));
        uint256 ebtcBalanceBefore = ebtcToken.balanceOf(address(this));

        uint256 gainedCollateral = collToken.balanceOf(address(this)).sub(collBalanceBefore); // stack too deep issues :'(
        uint256 gainedEBTC = ebtcToken.balanceOf(address(this)).sub(ebtcBalanceBefore);

        uint256 netEBTCAmount;
        // Top up cdp and get more EBTC, keeping ICR constant
        if (gainedCollateral > 0) {
            _requireUserHasCdp(_cdpId);
            netEBTCAmount = _getNetEBTCAmount(_cdpId, gainedCollateral);
            borrowerOperations.adjustCdpWithColl(
                _cdpId,
                0,
                netEBTCAmount,
                true,
                _upperHint,
                _lowerHint,
                gainedCollateral
            );
        }

        uint256 totalEBTC = gainedEBTC.add(netEBTCAmount);
        if (totalEBTC > 0) {
            ebtcToken.transfer(address(0x000000000000000000000000000000000000dEaD), totalEBTC);
        }
    }

    function _getNetEBTCAmount(bytes32 _cdpId, uint256 _collateral) internal returns (uint256) {
        uint256 price = priceFeed.fetchPrice();
        uint256 ICR = cdpManager.getCachedICR(_cdpId, price);

        uint256 EBTCAmount = _collateral.mul(price).div(ICR);
        uint256 netDebt = EBTCAmount.mul(EbtcMath.DECIMAL_PRECISION).div(EbtcMath.DECIMAL_PRECISION);

        return netDebt;
    }

    function _requireUserHasCdp(bytes32 _cdpId) internal view {
        require(
            cdpManager.getCdpStatus(_cdpId) == 1,
            "BorrowerWrappersScript: caller must have an active cdp"
        );
    }
}
