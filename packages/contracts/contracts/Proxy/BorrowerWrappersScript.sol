// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "../Dependencies/SafeMath.sol";
import "../Dependencies/LiquityMath.sol";
import "../Dependencies/IERC20.sol";
import "../Interfaces/IBorrowerOperations.sol";
import "../Interfaces/ICdpManager.sol";
import "../Interfaces/IPriceFeed.sol";
import "../Interfaces/ILQTYStaking.sol";
import "./BorrowerOperationsScript.sol";
import "./ETHTransferScript.sol";
import "./LQTYStakingScript.sol";
import "../Dependencies/console.sol";
import "../Dependencies/ICollateralToken.sol";

contract BorrowerWrappersScript is BorrowerOperationsScript, ETHTransferScript, LQTYStakingScript {
    using SafeMath for uint;

    string public constant NAME = "BorrowerWrappersScript";

    ICdpManager immutable cdpManager;
    IPriceFeed immutable priceFeed;
    IERC20 immutable ebtcToken;
    IERC20 immutable lqtyToken;
    ILQTYStaking immutable lqtyStaking;
    ICollateralToken immutable collToken;

    constructor(
        address _borrowerOperationsAddress,
        address _cdpManagerAddress,
        address _lqtyStakingAddress,
        address _collTokenAddress
    )
        public
        BorrowerOperationsScript(IBorrowerOperations(_borrowerOperationsAddress))
        LQTYStakingScript(_lqtyStakingAddress)
    {
        checkContract(_cdpManagerAddress);
        ICdpManager cdpManagerCached = ICdpManager(_cdpManagerAddress);
        cdpManager = cdpManagerCached;

        IPriceFeed priceFeedCached = cdpManagerCached.priceFeed();
        checkContract(address(priceFeedCached));
        priceFeed = priceFeedCached;

        address ebtcTokenCached = address(cdpManagerCached.ebtcToken());
        checkContract(ebtcTokenCached);
        ebtcToken = IERC20(ebtcTokenCached);

        address lqtyTokenCached = address(cdpManagerCached.lqtyToken());
        checkContract(lqtyTokenCached);
        lqtyToken = IERC20(lqtyTokenCached);

        ILQTYStaking lqtyStakingCached = cdpManagerCached.lqtyStaking();
        require(
            _lqtyStakingAddress == address(lqtyStakingCached),
            "BorrowerWrappersScript: Wrong LQTYStaking address"
        );
        lqtyStaking = lqtyStakingCached;

        checkContract(_collTokenAddress);
        collToken = ICollateralToken(_collTokenAddress);
    }

    function claimCollateralAndOpenCdp(
        uint _EBTCAmount,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint _collAmount
    ) external {
        uint balanceBefore = collToken.balanceOf(address(this));

        // Claim collateral
        borrowerOperations.claimCollateral();

        uint balanceAfter = collToken.balanceOf(address(this));

        // already checked in CollSurplusPool
        assert(balanceAfter > balanceBefore);

        uint totalCollateral = balanceAfter.sub(balanceBefore).add(_collAmount);

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
        uint collBalanceBefore = collToken.balanceOf(address(this));
        uint ebtcBalanceBefore = ebtcToken.balanceOf(address(this));
        uint lqtyBalanceBefore = lqtyToken.balanceOf(address(this));

        // Claim gains
        lqtyStaking.unstake(0);

        uint gainedCollateral = collToken.balanceOf(address(this)).sub(collBalanceBefore); // stack too deep issues :'(
        uint gainedEBTC = ebtcToken.balanceOf(address(this)).sub(ebtcBalanceBefore);

        uint netEBTCAmount;
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

        uint totalEBTC = gainedEBTC.add(netEBTCAmount);
        if (totalEBTC > 0) {
            ebtcToken.transfer(address(0x000000000000000000000000000000000000dEaD), totalEBTC);
            //  stake LQTY if any
            uint lqtyBalanceAfter = lqtyToken.balanceOf(address(this));
            uint claimedLQTY = lqtyBalanceAfter.sub(lqtyBalanceBefore);
            if (claimedLQTY > 0) {
                lqtyStaking.stake(claimedLQTY);
            }
        }
    }

    function _getNetEBTCAmount(bytes32 _cdpId, uint _collateral) internal returns (uint) {
        uint price = priceFeed.fetchPrice();
        uint ICR = cdpManager.getCurrentICR(_cdpId, price);

        uint EBTCAmount = _collateral.mul(price).div(ICR);
        uint borrowingRate = cdpManager.getBorrowingRateWithDecay();
        uint netDebt = EBTCAmount.mul(LiquityMath.DECIMAL_PRECISION).div(
            LiquityMath.DECIMAL_PRECISION.add(borrowingRate)
        );

        return netDebt;
    }

    function _requireUserHasCdp(bytes32 _cdpId) internal view {
        require(
            cdpManager.getCdpStatus(_cdpId) == 1,
            "BorrowerWrappersScript: caller must have an active cdp"
        );
    }
}
