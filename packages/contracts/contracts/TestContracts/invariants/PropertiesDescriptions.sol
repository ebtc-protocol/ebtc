pragma solidity 0.8.17;

abstract contract PropertiesDescriptions {
    string constant AP_01 =
        "AP-01 The collateral balance in the active pool is greater than or equal to its accounting number";
    string constant AP_03 =
        "AP-03 The eBTC debt accounting number in active pool is greater than or equal to its accounting number";
    string constant AP_04 =
        "AP-04 The total collateral in active pool should be equal to the sum of all individual CDP collateral";
    string constant AP_05 =
        "AP-05 The sum of debt accounting in active pool should be equal to sum of debt accounting of individual CDPs";
    string constant CDPM_01 =
        "CDPM-01 The count of active CDPs is equal to the SortedCdp list length";
    string constant CDPM_02 = "CDPM-02 The sum of active CDPs stake is equal to totalStakes";
    string constant CDPM_03 =
        "CDPM-03 The stFeePerUnit tracker for individual CDP is equal to or less than the global variable";
    string constant CSP_01 =
        "CSP-01 The collateral balance in the collSurplus pool is greater than or equal to its accounting number";
    string constant SL_01 =
        "SL-01 The NICR ranking in the sorted list should follow descending order";
    string constant SL_02 =
        "SL-02 The the first(highest) ICR in the sorted list should be greater or equal to TCR (with tolerance due to rounding errors)";
    string constant SL_03 = "SL-03 All CDPs have status active and stake greater than zero";
    string constant P_01 =
        "P-01 The dollar value of the locked stETH exceeds the dollar value of the issued eBTC if TCR is greater than 100%";
    string constant P_02 =
        "Any eBTC holder (whether or not they have an active CDP) may redeem their eBTC unless the system is in Recovery Mode";
    string constant P_03 = "P-03 After any operation, the TCR must be above the CCR";
    string constant P_05 = "P-05 eBTC tokens are burned upon repayment of a CDP's debt";
    string constant P_22 =
        "P-22 `CdpManager`, `BorrowerOperations`, `eBTCToken`, `SortedCDPs` and `PriceFeed`s do not hold value terms of stETH and eBTC unless there are donations";
    string constant P_36 =
        "P-36 At all times, the total debt is equal to the sum of all debts from all CDP + toRedistribute";
    string constant P_47 =
        "P-47 The collateral balance of the ActivePool is positive if there is at least one CDP open";
    string constant P_48 = "P-48 Adding collateral improves Nominal ICR";
    string constant P_50 =
        "P-50 After any operation, the ICR of a CDP must be above the MCR in Normal mode or TCR in Recovery mode";
    string constant DUMMY_01 = "DUMMY-01 PriceFeed is configured";
}
