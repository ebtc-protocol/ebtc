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

contract BorrowerWrappersScript is BorrowerOperationsScript, ETHTransferScript, LQTYStakingScript {
    using SafeMath for uint;

    string public constant NAME = "BorrowerWrappersScript";

    ICdpManager immutable cdpManager;
    IPriceFeed immutable priceFeed;
    IERC20 immutable ebtcToken;
    IERC20 immutable lqtyToken;
    ILQTYStaking immutable lqtyStaking;

    constructor(
        address _borrowerOperationsAddress,
        address _cdpManagerAddress,
        address _lqtyStakingAddress
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
    }

    function claimCollateralAndOpenCdp(
        uint _maxFee,
        uint _EBTCAmount,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external payable {
        uint balanceBefore = address(this).balance;

        // Claim collateral
        borrowerOperations.claimCollateral();

        uint balanceAfter = address(this).balance;

        // already checked in CollSurplusPool
        assert(balanceAfter > balanceBefore);

        uint totalCollateral = balanceAfter.sub(balanceBefore).add(msg.value);

        // Open cdp with obtained collateral, plus collateral sent by user
        borrowerOperations.openCdp{value: totalCollateral}(
            _maxFee,
            _EBTCAmount,
            _upperHint,
            _lowerHint
        );
    }

    function claimStakingGainsAndRecycle(
        bytes32 _cdpId,
        uint _maxFee,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external {
        uint collBalanceBefore = address(this).balance;
        uint ebtcBalanceBefore = ebtcToken.balanceOf(address(this));
        uint lqtyBalanceBefore = lqtyToken.balanceOf(address(this));

        // Claim gains
        lqtyStaking.unstake(0);

        uint gainedCollateral = address(this).balance.sub(collBalanceBefore); // stack too deep issues :'(
        uint gainedEBTC = ebtcToken.balanceOf(address(this)).sub(ebtcBalanceBefore);

        uint netEBTCAmount;
        // Top up cdp and get more EBTC, keeping ICR constant
        if (gainedCollateral > 0) {
            _requireUserHasCdp(_cdpId);
            netEBTCAmount = _getNetEBTCAmount(_cdpId, gainedCollateral);
            borrowerOperations.adjustCdp{value: gainedCollateral}(
                _cdpId,
                _maxFee,
                0,
                netEBTCAmount,
                true,
                _upperHint,
                _lowerHint
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
