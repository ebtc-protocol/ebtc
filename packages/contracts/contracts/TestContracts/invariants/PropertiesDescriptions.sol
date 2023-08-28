pragma solidity 0.8.17;

abstract contract PropertiesDescriptions {
    ///////////////////////////////////////////////////////
    // Active Pool
    ///////////////////////////////////////////////////////

    string constant AP_01 =
        "AP-01: The collateral balance in the active pool is greater than or equal to its accounting number";
    string constant AP_02 =
        "AP-06: The collateral balance of the ActivePool is positive if there is at least one CDP open";
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
    string constant CDPM_04 =
        "CDPM-04: The total system Assets - Liabilities remain constant during redemptions";
    string constant CDPM_05 = "CDPM-05: Redemptions do not increase the total system debt";

    ///////////////////////////////////////////////////////
    // Collateral Surplus Pool
    ///////////////////////////////////////////////////////

    string constant CSP_01 =
        "CSP-01: The collateral balance in the collSurplus pool is greater than or equal to its accounting number";

    ///////////////////////////////////////////////////////
    // Sorted List
    ///////////////////////////////////////////////////////

    string constant SL_01 =
        "SL-01: The NICR ranking in the sorted list should follow descending order";
    string constant SL_02 =
        "SL-02: The the first(highest) ICR in the sorted list should be greater or equal to TCR (with tolerance due to rounding errors)";
    string constant SL_03 = "SL-03: All CDPs have status active and stake greater than zero";

    ///////////////////////////////////////////////////////
    // Borrower Operations
    ///////////////////////////////////////////////////////

    string constant BO_03 = "BO-03: Adding collateral improves Nominal ICR";
    string constant BO_04 = "BO-04: Removing collateral decreases the Nominal ICR";
    string constant BO_05 =
        "BO-05: When a borrower closes their active CDP, the gas compensation is refunded to the user";
    string constant BO_07 = "BO-07: eBTC tokens are burned upon repayment of a CDP's debt";
    string constant BO_08 = "BO-08: TCR must increase after a repayment";

    ///////////////////////////////////////////////////////
    // General
    ///////////////////////////////////////////////////////
    string constant GENERAL_01 =
        "GENERAL-01: After any operation, the system should not enter in Recovery Mode";
    string constant GENERAL_02 =
        "GENERAL-02: The dollar value of the locked stETH exceeds the dollar value of the issued eBTC if TCR is greater than 100%";
    string constant GENERAL_03 =
        "GENERAL-03: CdpManager and BorrowerOperations do not hold value terms of stETH and eBTC unless there are donations";
    string constant GENERAL_09 =
        "GENERAL-09: After any operation, the ICR of a CDP must be above the MCR in Normal mode or TCR in Recovery mode";
    string constant GENERAL_10 = "GENERAL-10: All CDPs should maintain a minimum collateral size";

    ///////////////////////////////////////////////////////
    // Redemptions
    ///////////////////////////////////////////////////////

    string constant R_07 = "TCR should be slightly improved after every redemption";
    string constant R_08 = "The user eBTC balance should be used to pay the system debt";

    ///////////////////////////////////////////////////////
    // Liquidations
    ///////////////////////////////////////////////////////

    string constant L_01 =
        "L-01: Liquidation only succeeds if ICR < 110% in Normal Mode, or if ICR < 125% in Recovery Mode";
    string constant L_12 = "L-12: TCR must increase after liquidation with no redistributions";

    ///////////////////////////////////////////////////////
    // eBTC
    ///////////////////////////////////////////////////////

    string constant EBTC_02 =
        "EBTC-02: Any eBTC holder (whether or not they have an active CDP) may redeem their eBTC unless the system is in Recovery Mode";

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
}
