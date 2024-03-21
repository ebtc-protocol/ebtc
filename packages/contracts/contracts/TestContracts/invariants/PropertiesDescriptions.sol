pragma solidity 0.8.17;

abstract contract PropertiesDescriptions {
    ///////////////////////////////////////////////////////
    // Active Pool
    ///////////////////////////////////////////////////////

    string constant AP_01 =
        "AP-01: The collateral balance in the active pool is greater than or equal to its accounting number";
    string constant AP_02 =
        "AP-02: The collateral balance of the ActivePool is positive if there is at least one CDP open";
    string constant AP_03 =
        "AP-03: The eBTC debt accounting number in active pool is greater than or equal to its accounting number";
    string constant AP_04 =
        "AP-04: The total collateral in active pool should be equal to the sum of all individual CDP collateral";
    string constant AP_05 =
        "AP-05: The sum of debt accounting in active pool should be equal to sum of debt accounting of individual CDPs";

    ///////////////////////////////////////////////////////
    // Cdp Manager
    ///////////////////////////////////////////////////////

    string constant CDPM_01 =
        "CDPM-01: The count of active CDPs is equal to the SortedCdp list length";
    string constant CDPM_02 = "CDPM-02: The sum of active CDPs stake is equal to totalStakes";
    string constant CDPM_03 =
        "CDPM-03: The stFeePerUnit tracker for individual CDP is equal to or less than the global variable";
    string constant CDPM_04 = "CDPM-04: The total system value does not decrease during redemptions";
    string constant CDPM_05 = "CDPM-05: Redemptions do not increase the total system debt";
    string constant CDPM_06 = "CDPM-06: Redemptions do not increase the total system debt";
    string constant CDPM_07 = "CDPM-07: Stake decreases when collShares decreases for a CDP";
    string constant CDPM_08 = "CDPM-08: Stake increases when collShares increases for a CDP";
    string constant CDPM_09 =
        "CDPM-09: expectedStake = coll * totalStakesSnapshot / totalCollateralSnapshot after every operation involving a CDP";
    string constant CDPM_10 =
        "CDPM-10: totalStakesSnapshot matches totalStakes after an operation, if rebase index changed during the OP";
    string constant CDPM_11 =
        "CDPM-11: totalCollateralSnapshot matches activePool.systemCollShares after an operation, if rebase index changed during the OP";
    string constant CDPM_12 =
        "CDPM-12: Sum of all individual CDP stakes should equal to totalStakes";

    ///////////////////////////////////////////////////////
    // Collateral Surplus Pool
    ///////////////////////////////////////////////////////

    string constant CSP_01 =
        "CSP-01: The collateral balance in the collSurplus pool is greater than or equal to its accounting number";
    string constant CSP_02 =
        "CSP-02: The sum of all surpluses is equal to the value of getTotalSurplusCollShares";

    ///////////////////////////////////////////////////////
    // Sorted List
    ///////////////////////////////////////////////////////

    string constant SL_01 =
        "SL-01: The NICR ranking in the sorted list should follow descending order";
    string constant SL_02 =
        "SL-02: The the first(highest) ICR in the sorted list should be greater or equal to TCR (with tolerance due to rounding errors)";
    string constant SL_03 = "SL-03: All CDPs have status active and stake greater than zero";
    string constant SL_05 =
        "SL-05: The CDPs should be sorted in descending order of new ICR (accrued)";

    ///////////////////////////////////////////////////////
    // Borrower Operations
    ///////////////////////////////////////////////////////

    string constant BO_01 = "BO-01: Users can only open CDPs with healthy ICR";
    string constant BO_02 = "BO-02: Users must repay all debt to close a CDP";
    string constant BO_03 = "BO-03: Adding collateral doesn't reduce Nominal ICR";
    string constant BO_04 = "BO-04: Removing collateral does not increase the Nominal ICR";
    string constant BO_05 =
        "BO-05: When a borrower closes their active CDP, the gas compensation is refunded to the user";
    string constant BO_07 = "BO-07: eBTC tokens are burned upon repayment of a CDP's debt";
    string constant BO_08 = "BO-08: TCR must increase after a repayment";
    string constant BO_09 = "BO-09: Borrower can not open a CDP that is immediately liquidatable";

    ///////////////////////////////////////////////////////
    // General
    ///////////////////////////////////////////////////////
    string constant GENERAL_01 =
        "GENERAL-01: After any operation, the system should not enter in Recovery Mode";
    string constant GENERAL_02 =
        "GENERAL-02: The dollar value of the locked stETH exceeds the dollar value of the issued eBTC if TCR is greater than 100%";
    string constant GENERAL_03 =
        "GENERAL-03: CdpManager and BorrowerOperations do not hold value terms of stETH and eBTC unless there are donations";
    string constant GENERAL_05 =
        "GENERAL-05: At all times, the total stETH shares of the system exceeds the deposits if there is no negative rebasing events"; /// NOTE this holds even with rebases
    string constant GENERAL_06 =
        "GENERAL-06: At all times, the total debt is greater than the sum of all debts from all CDPs";
    string constant GENERAL_08 =
        "GENERAL-08: At all times TCR = SUM(COLL)  * price / SUM(DEBT) of all CDPs";
    string constant GENERAL_09 =
        "GENERAL-09: After any operation, the ICR of a CDP must be above the MCR in Normal Mode, and after debt increase in Recovery Mode the ICR must be above the CCR";
    string constant GENERAL_10 = "GENERAL-10: All CDPs should maintain a minimum collateral size";
    string constant GENERAL_11 =
        "GENERAL-11: The TCR pre-computed (TCRNotified) is the same as the one after all calls";
    string constant GENERAL_12 =
        "GENERAL-12: The synchedTCR matches the TCR after accrual (as returned by CrLens)";
    string constant GENERAL_13 =
        "GENERAL-13: The SynchedICR of every CDP in the Linked List Matches the ICR the CDPs will have the call (as returned by CrLens)";
    string constant GENERAL_14 =
        "GENERAL-14: The NominalICR from `getNominalICR` matches `quoteRealNICR` (as returned by CrLens)";
    string constant GENERAL_15 =
        "GENERAL-15: CDP debt should always be greater than MIN_CHANGE (1000 Wei)";
    string constant GENERAL_16 =
        "GENERAL-16: Collateral and debt change amounts should always be greater than MIN_CHANGE (1000 Wei)";
    string constant GENERAL_17 =
        "GENERAL-17: Sum of synced debt values of all Cdps + the stored debt redistribution error accumulator should never be more than the total system debt + 1";
    string constant GENERAL_18 =
        "GENERAL-18: Sum of synced coll shares of all Cdps - cumulative errors should never be more than _systemCollShares";
    string constant GENERAL_19 = "GENERAL-19: TWAP should never be disabled";

    ///////////////////////////////////////////////////////
    // Redemptions
    ///////////////////////////////////////////////////////

    string constant R_07 = "R-07: TCR should not decrease after redemptions";
    string constant R_08 = "R-08: The user eBTC balance should be used to pay the system debt";

    ///////////////////////////////////////////////////////
    // Liquidations
    ///////////////////////////////////////////////////////

    string constant L_01 =
        "L-01: Liquidation only succeeds if ICR < 110% in Normal Mode, or if ICR < 125% in Recovery Mode";
    string constant L_09 =
        "L-09: Undercollateralized liquidations are also incentivized with the Gas Stipend";
    string constant L_12 =
        "L-12: TCR must increase after liquidation with no redistributions if the liquidated CDP's ICR is less than TCR before liquidation";
    string constant L_14 =
        "If the RM grace period is set and we're in recovery mode, new actions that keep the system in recovery mode should not change the cooldown timestamp";
    string constant L_15 =
        "L-15: The RM grace period should set if a BO/liquidation/redistribution makes the TCR below CCR";
    string constant L_16 =
        "L-16: The RM grace period should reset if a BO/liquidation/redistribution makes the TCR above CCR";
    string constant L_17 =
        "L-17: Debt Redistribution Error Accumulator should be less than Total Stakes immediately after a bad debt redistribution";

    ///////////////////////////////////////////////////////
    // eBTC
    ///////////////////////////////////////////////////////

    string constant EBTC_02 =
        "EBTC-02: Any eBTC holder (whether or not they have an active CDP) may redeem their eBTC unless TCR is below MCR";

    ///////////////////////////////////////////////////////
    // Fee Recipient
    ///////////////////////////////////////////////////////

    string constant F_01 = "F-01: `claimFeeRecipientCollShares` allows to claim at any time";
    string constant F_02 = "F-02: Fees From Redemptions are added to `claimFeeRecipientCollShares`";
    string constant F_03 = "F-03: Fees From FlashLoans are sent to the fee Recipient";
    string constant F_04 =
        "F-04: `claimFeeRecipientCollShares` claiming increases the balance of the fee recipient";

    ///////////////////////////////////////////////////////
    // Price Feed
    ///////////////////////////////////////////////////////

    string constant PF_01 = "PF-01: The price feed must never revert";
    string constant PF_02 = "PF-02: The price feed must follow valid status transitions";
    string constant PF_03 = "PF-03: The price feed must never deadlock";
    string constant PF_04 =
        "PF-04: The price feed should never report an outdated price if chainlink is Working";
    string constant PF_05 =
        "PF-05: The price feed should never use the fallback if chainlink is Working";
    string constant PF_06 = "PF-06: The system never tries to use the fallback if it is not set";
    string constant PF_07 =
        "PF-07: The price feed should return the primary oracle price if it is working";
    string constant PF_08 =
        "PF-08: The price feed should return the secondary oracle price if the primary oracle is not working";
    string constant PF_09 =
        "PF-09: The price feed should return the last good price if both oracles are not working";
    string constant PF_10 =
        "PF-10: The price feed should never return different prices when called multiple times in a single tx";
}
