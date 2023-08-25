pragma solidity 0.8.17;

abstract contract BeforeAfter {
    struct Vars {
        uint256 nicrBefore;
        uint256 nicrAfter;
        uint256 icrBefore;
        uint256 icrAfter;
        uint256 feeRecipientTotalCollBefore;
        uint256 feeRecipientTotalCollAfter;
        uint256 actorCollBefore;
        uint256 actorCollAfter;
        uint256 actorEbtcBefore;
        uint256 actorEbtcAfter;
        uint256 actorCdpCountBefore;
        uint256 actorCdpCountAfter;
        uint256 cdpCollBefore;
        uint256 cdpCollAfter;
        uint256 cdpDebtBefore;
        uint256 cdpDebtAfter;
        uint256 liquidatorRewardSharesBefore;
        uint256 liquidatorRewardSharesAfter;
        uint256 sortedCdpsSizeBefore;
        uint256 sortedCdpsSizeAfter;
        uint256 cdpStatusBefore;
        uint256 cdpStatusAfter;
        uint256 tcrBefore;
        uint256 tcrAfter;
        uint256 debtBefore;
        uint256 debtAfter;
        uint256 ebtcTotalSupplyBefore;
        uint256 ebtcTotalSupplyAfter;
        uint256 ethPerShareBefore;
        uint256 ethPerShareAfter;
        uint256 activePoolCollBefore;
        uint256 activePoolCollAfter;
        uint256 collSurplusPoolBefore;
        uint256 collSurplusPoolAfter;
        uint256 priceBefore;
        uint256 priceAfter;
        bool isRecoveryModeBefore;
        bool isRecoveryModeAfter;
    }

    Vars vars;
}
