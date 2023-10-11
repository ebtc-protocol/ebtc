# Properties

List of properties of the eBTC protocol, following the categorization by [Certora](https://github.com/Certora/Tutorials/blob/master/06.Lesson_ThinkingProperties/Categorizing_Properties.pdf):

- Valid States
- State Transitions
- Variable Transitions
- High-Level Properties
- Unit Tests

## Active Pool

| Property | Description | Category | Tested |
| --- | --- | --- | --- |
| AP-01 | The collateral balance in the active pool is greater than or equal to its accounting number | High Level | ✅ |
| AP-02 | The collateral balance of the ActivePool is positive if there is at least one CDP open | High Level | ✅ |
| AP-03 | The eBTC debt accounting number in active pool equal to the EBTC total supply | High Level | ✅ |
| AP-04 | The total collateral in active pool should be equal to the sum of all individual CDP collateral | High Level | ✅ |
| AP-05 | The sum of debt accounting in active pool should be equal to sum of debt accounting of individual CDPs | High Level | ✅ |

## CDP Manager

| Property | Description | Category | Tested |
| --- | --- | --- | --- |
| CDPM-01 | The count of active CDPs is equal to the SortedCdp list length | High Level | ✅ |
| CDPM-02 | The sum of active CDPs stake is equal to totalStakes | High Level | ✅ |
| CDPM-03 | The `systemStEthFeePerUnitIndex` tracker for individual CDP is equal to or less than the global variable | High Level | ✅ |
| CDPM-04 | The total system value does not decrease constant during redemptions | Unit Tests | ✅ |
| CDPM-05 | Redemptions do not increase the total system debt | Unit Tests | ✅ |
| CDPM-06 | Redemptions do not increase a CDPs debt | Unit Tests | ✅ |

## Borrower Operations

| Property | Description | Category | Tested |
| --- | --- | --- | --- |
| BO-01 | Users can only open CDPs with healthy ICR | Unit Tests | ✅ |
| BO-02 | Users must repay all debt to close a CDP | State Transitions | ✅ |
| BO-03 | Adding collateral improves the Nominal ICR of a CDP if there is no rebase | Unit Tests | ✅ |
| BO-04 | Removing collateral does not increase the Nominal ICR | Unit Tests | ✅ |
| BO-05 | When a borrower closes their active CDP, the gas compensation is refunded to the user: the amount of shares sent by the user is transferred back from the GasPool to the user | Unit Tests | ✅ |
| BO-06 | Each time I change my ICR, the TCR changes by an impact that is equal to the relative weight of collateral and debt from my position | State Transitions | | - IMO SCRAP
| BO-07 | eBTC tokens are burned upon repayment of a CDP's debt | State Transitions | ✅ |
| BO-08 | TCR must increase after a repayment | Variable Transitions | ✅ |

## Collateral Surplus Pool

| Property | Description | Category | Tested |
| --- | --- | --- | --- |
| CSP-01 | The collateral balance in the collSurplus pool is greater than or equal to its accounting number | High Level | ✅ |
| CSP-02 | The sum of all surpluses is equal to the value of getTotalSurplusCollShares | High Level | ✅ |


TODO: Recon
For each caller, calling either reverts due to 0
Or
They can always retrieve the funds

// If above 0, must succeed

## Sorted List

| Property | Description | Category | Tested |
| --- | --- | --- | --- |
| SL-01 | The NICR ranking in the sorted list should follow descending order | High Level | ✅️ |
| SL-02 | The the first(highest) ICR in the sorted list should be greater or equal to TCR | High Level | ✅️ |
| SL-03 | All CDPs have status active and stake greater than zero | High Level | ✅ |
| SL-05 | The CDPs should be sorted in descending order of new ICR (accrued) | Variable Transitions | ❌ | Breaks in certain cases

## General

| Property | Description | Category | Tested |
| --- | --- | --- | --- |
| GENERAL-01 | After any user operation, the system should not enter in Recovery Mode | High Level | ✅ |
| GENERAL-02 | The dollar value of the locked stETH exceeds the dollar value of the issued eBTC if TCR is greater than 100% | High-Level | ✅ |
| GENERAL-03 | CdpManager and BorrowerOperations do not hold value terms of stETH and eBTC unless there are donations | Valid States | ✅ |
| GENERAL-05 | At all times, the total stETH shares of the system exceeds the deposits if there is no negative rebasing events | High Level |  |
| GENERAL-06 | At all times, the total debt is greater than the sum of all debts from all CDPs | High Level | ✅ |

| GENERAL-07 | Without a price change, a rebasing event, or a redistribution, my position can never reduce in absolute value | State Transitions | | - TODO: 
Recon Attack IMO

| GENERAL-08 | At all times TCR = SUM(ICR) for all CDPs | High Level | ✅ |
| GENERAL-09 | After any operation, the ICR of a CDP must be above the MCR in Normal Mode, and after debt increase in Recovery Mode the ICR must be above the CCR | High Level | ✅ |
| GENERAL-10 | All CDPs should maintain a minimum collateral size | High Level | ✅ |
| GENERAL-11 | The TCR pre-computed (TCRNotified) is the same as the one after all calls | High Level | ✅ |
| GENERAL-12 | The synchedTCR matches the TCR after accrual (as returned by CrLens) | High Level | ✅ |
| GENERAL-13 | The SynchedICR of every CDP in the Linked List Matches the ICR the CDPs will have the call (as returned by CrLens)  | High Level | ✅ |
| GENERAL-14 | The NominalICR from getNominalICR matches quoteRealNICR (as returned by CrLens)  | High Level | ✅ |
| GENERAL-15 | Users can always withdraw their whole collateral by repaying all their debt | High Level | ✅ |


## Liquidation Sequencer vs Syncing Liquidation Sequencer
| --- | --- | --- | --- |
| LS-01 | The Liquidation Sequencer produces the same output as the SyncedLiquidationSequencer | Unit Tests | ✅ |

## Redemptions - Pls Antonio Review

| Property | Description | Category | Tested |
| --- | --- | --- | --- |
| R-01 | When a user redeems eBTC, it is exchanged for stETH, at face value (minus a redemption fee) | Unit Tests | |
-> TODO: Code

| R-02 | When eBTC is redeemed for stETH, the system cancels the eBTC with debt from CDPs, and the stETH is drawn from their collateral in exact amounts (totalDebt Decrease is equal to TS decrease). The debt reduction is pro-rata to all CDPs open based on their size | Unit Tests | |
-> TODO: Code

| R-03 | A redemption sequence of n steps will fully redeem from up to n-1 CDPs, and, and partially redeems from up to 1 CDP, which is always the last CDP in the redemption sequence. | Unit Tests | |
-> TODO: Code with supporting contract prob

| R-04 | Redemptions are disabled during the first 14 days of operation since deployment of the eBTC protocol | Valid States | ✅ |
-> TODO: Remove

| R-05 | Partially redeemed CDP is re-inserted into the sorted list of CDPs, and remains active, with reduced collateral and debt. Linked List invariant is maintained. And new values correspond with tokens burned and transferred. | Unit Tests | |
-> TODO: SCRAP -> Invariant of List integrity covers this

| R-06 | If the redemption causes a CDP's full debt to be cancelled, the CDP is then closed: Gas Stipend from the Liquidation Reserve becomes avaiable for the borrower to reclaim along of the CDP's Collateral Surplus. The original CDP owner gets the stipend when a CDP is fully closed by redemption | Unit Tests | |
-> TODO: Code

| R-07 | TCR should not decrease after redemptions | Unit Tests | ✅ |

| R-08 | The user eBTC balance should be used to pay the system debt | Unit Tests | ✅ |

## Liquidations - Pls Antonio Review

| Property | Description | Category | Tested |
| --- | --- | --- | --- |
| L-01 | Liquidation only succeeds if ICR < 110% in normal mode, or if ICR < 125% in Recovery Mode. | State Transitions | ✅ |

| L-04 | A "Gas Stipend" of 0.2 stETH is previously deposited by the borrower as insurance against liquidation costs | Unit Tests | ✅ |
| L-05 | Anyone may call the public `liquidateCdps` and `batchLiquidateCdps` functions | Unit Tests | ✅ |

| L-07 | Gas compensation per liquidated CDP is given by the formula: Full liquidation Gas compensation = max(1.03, min(ICR, 1.1)) + Gas Stipend, Partial liquidation Gas compensation = max(1.03, min(ICR, 1.1)) | Unit Tests | |
-> TODO

| L-08 | When a CDP is liquidated, all of the collateral is transferred to the liquidator. When it's fully liquidated, the SHARES are transferred (balance may cause rounding errors). | State Transitions | ✅ |

| L-09 | Undercollateralized liquidations are also incentivized with the Gas Stipend. Full liquidations of any type, always pay the stipend | Unit Tests | |
-> TODO

| L-10 | As a Individual Leveraged to the maximum (110 CR), I can only be liquidated if: The oracle price changes in such a way that my CR goes below 110 or Other depositors bring the system CR to 125 (edge of Recovery Mode), then the Oracle Price updates to a lower value, causing every CDP below RM to be liquidatable | State Transitions |  |

| L-12 | TCR must increase after liquidation with no redistributions | High Level | ❌ | Breaks if all CDPs are underwater
| L-14 | If the RM grace period is set and we're in recovery mode, new actions that keep the system in recovery mode should not change the cooldown timestamp | High Level | ✅ |
| L-15 | The RM grace period should set if a BO/liquidation/redistribution makes the TCR above CCR | High Level | ❌ | Breaks if nobody calls to sync (known)
| L-16 | The RM grace period should reset if a BO/liquidation/redistribution makes the TCR below CCR | High Level | ✅ |
| L-17 |Partial Liquidations Cannot Close CDPs | High Level | ✅ |

TODO: Also do one that shows that it can NEVER revert

| Property | Description | Category | Tested |
| --- | --- | --- | --- |
| F-01 | `claimFeeRecipientCollShares` claiming increases the balance of the fee recipient | Unit Tests | ✅ |
| F-02 | Fees From Redemptions are added to `claimFeeRecipientCollShares` | Unit Tests | ✅ |
| F-03 | Fees From FlashLoans are sent to the fee Recipient | Unit Tests | ✅ |




### `claimFeeRecipientCollShares` allows to claim at any time (SEE BELOW)

```solidity
    function claimFeeRecipientCollShares(uint256 _shares) external override requiresAuth {
```

If success -> Check that goes to 0
-> Check that balance of the recipient increased by XYZ

If fail -> check balance is unchanged

### FeeeRebase
-> Claiming Pending stETH Index
-> Increases the Value
_before stETHINDEX
_after stETHINDEX

-> FeeRecipient changed

Should we write a explicit check that in any other situation it didn't change?



## Col Surplus

claimSurplusCollShares

Revert -> Because it's 0
OR
Always Succeeds

-> We want to indentify scenarios in which we get a revert due to undercollateralization

## Col in General
RECON

-> Have everyone repay everything

-> Verify everyone get's their Coll back

-> Last CDP
-> Can still reduce to min size

-> Custom "Withdraw All Handler"
-> Each Actor
-> All withdraw
-> Revert if one of them doesn't
-> Revert with index?




## eBTC

| Property | Description | Category | Tested |
| --- | --- | --- | --- |
| EBTC-01 | Anyone with an Ethereum address can send or receive eBTC tokens, whether they have an open CDP or not | Unit Tests |  |
| EBTC-02 | Any eBTC holder (whether or not they have an active CDP) may redeem their eBTC unless TCR is below MCR | High Level | |
| EBTC-03 | The eBTC token contract implements the ERC20 fungible token standard in conjunction with EIP-2612 and a mechanism that blocks (accidental) transfers to contracts and addresses like address(0) that are not supposed to receive funds through direct transfers | Unit Tests | |



## Governance

| Property | Description | Category | Tested |
| --- | --- | --- | --- |
| GOV-01 | Only authorized accounts can call functions which require authorization (`requiresAuth` modifier) | Unit Tests | |

## Price Feed

| Property | Description | Category | Tested |
| --- | --- | --- | --- |
| PF-01 | The price feed must never revert | High Level | ✅ |
| PF-02 | The price feed must follow valid status transitions | State Transitions | ✅ |
| PF-03 | The price feed must never deadlock | State Transitions | TODO: this is hard to test, as we may have false positives due to the random nature of the tests |
| PF-04 | The price feed should never report an outdated price if chainlink is Working | High Level | ✅ |
| PF-05 | The price feed should never use the fallback if chainlink is Working | High Level | ✅ |
| PF-06 | The system never tries to use the fallback if it is not set | High Level | ✅ |
