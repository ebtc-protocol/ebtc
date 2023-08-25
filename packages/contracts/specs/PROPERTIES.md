# Properties

List of properties of the eBTC protocol, following the categorization by [Certora](https://github.com/Certora/Tutorials/blob/master/06.Lesson_ThinkingProperties/Categorizing_Properties.pdf):

- Valid States
- State Transitions
- Variable Transitions
- High-Level Properties
- Unit Tests

## Active Pool

| Property | Description | Tested |
| --- | --- | --- | --- |
| AP-01 | The collateral balance in the active pool is greater than or equal to its accounting number | High Level | ✅ |
| AP-02 | The collateral balance of the ActivePool is positive if there is at least one CDP open | High Level | ✅ |
| AP-03 | The eBTC debt accounting number in active pool equal to the EBTC total supply | High Level | ✅ |
| AP-04 | The total collateral in active pool should be equal to the sum of all individual CDP collateral | High Level | ✅ |
| AP-05 | The sum of debt accounting in active pool should be equal to sum of debt accounting of individual CDPs | High Level | ✅ |

## CDP Manager

| CDPM-01 | The count of active CDPs is equal to the SortedCdp list length | High Level | ✅ |
| CDPM-02 | The sum of active CDPs stake is equal to totalStakes | High Level | 🚧 Redistributions? |
| CDPM-03 | The stFeePerUnit tracker for individual CDP is equal to or less than the global variable | High Level | 🚧 Negative Rebase + Pending Rewards? |
| CDPM-04 | The total system Assets - Liabilities remain constant during redemptions | Unit Tests | ✅ |
| CDPM-05 | Redemptions do not increase the total system debt | Unit Tests | ✅ |

## Borrower Operations

| BO-01 | Users can only open CDPs with healthy ICR | Unit Tests | TODO: Opening CDP can never directly trigger RM, Can NEVER open below 110 |
| BO-02 | Users must repay all debt to close a CDP | State Transitions | TODO: Always, at all time, in all conditions |
| BO-03 | Adding collateral improves the Nominal ICR of a CDP if there is no rebase | Unit Tests | ✅ |
| BO-04 | Reoving collateral decreases the Nominal ICR of a CDP if there is no rebase | Unit Tests | ✅ |
| BO-05 | If an existing CDP's adjustment reduces its ICR in Recovery Mode, the transaction is only executed if the resulting TCR is above 125% | State Transitions | TODO: May change to TCR + Buffer. KEY invariant |
| BO-05 | When a borrower closes their active CDP, the gas compensation is refunded to the user: the amount of shares sent by the user is transferred back from the GasPool to the user | Unit Tests | ✅ |
| BO-06 | Each time I change my ICR, the TCR changes by an impact that is equal to the relative weight of collateral and debt from my position | State Transitions | |
| BO-07 | eBTC tokens are burned upon repayment of a CDP's debt | State Transitions | ✅ |
| BO-08 | TCR must increase after a repayment | Variable Transitions | ✅ |

## Collateral Surplus Pool

| CSP-01 | The collateral balance in the collSurplus pool is greater than or equal to its accounting number | High Level | 🚧 TODO: Verify if the balance is equal to the shares at all times ? |
| CSP-02 | When a CDP is open, the total collateral is the sum of the collaterals split into the `CollSurplusPool`, the gas addresses, and ?? | Valid States | TODO: ask team about [Full redemption](./README.md#full-redemption) |

## Sorted List

| SL-01 | The NICR ranking in the sorted list should follow descending order | High Level | ⚠️ |
| SL-02 | The the first(highest) ICR in the sorted list should be greater or equal to TCR | High Level | ⚠️ |
| SL-03 | All CDPs have status active and stake greater than zero | High Level | ✅ |
| SL-04 | Nodes need only be re-inserted to the sorted list upon a CDP operation - when the owner adds or removes collateral or debt to their position. Only if the Debt and Coll ratio changes as well, if the ratio remains the same, a call to re-insert may happen, but the resulting order should be the same (e.g. add more coll and debt at same CR) | Variable Transitions | |

## General

| GENERAL-01 | After any user operation, the system should not enter in Recovery Mode | High Level | ✅ |
| GENERAL-02 | The dollar value of the locked stETH exceeds the dollar value of the issued eBTC if TCR is greater than 100% | High-Level | ✅ |
| GENERAL-03 | CdpManager and BorrowerOperations do not hold value terms of stETH and eBTC unless there are donations | Valid States | TODO: verify if the implementation is correct |
| GENERAL-04 | stETH in the system lives in ththe ActivePool, the DefaultPool. When an operation is made, stETH is transferred in one of three ways: From a user to a Pool, From a Pool to a user, and From one Pool to another Pool. Except for Liquidations and Redemptions | Variable Transitions | |
| GENERAL-05 | At all times, the total stETH balance of the system exceeds the deposits if there is no negative rebasing events | High Level | TODO: important and easy to implement |
| GENERAL-06 | At all times, the total debt is equal to the sum of all debts from all CDP + toRedistribute | High Level | ✅ TODO: + toRedistribute is not being checked |
| GENERAL-07 | Without a price change, a rebasing event, or a redistribution, my position can never reduce in absolute value | State Transitions | |
| GENERAL-08 | At all times TCR = SUM(ICR) for all CDPs | High Level | TODO: redistribution and pending fee split (prob need to look into this more) |
| GENERAL-09 | After any operation, the ICR of a CDP must be above the MCR in Normal mode or TCR in Recovery mode | High Level | ✅ |
| GENERAL-10 | All CDPs should maintain a minimum collateral size | High Level | ✅ |

## Redemptions

| R-01 | When a user redeems eBTC, it is exchanged for stETH, at face value (minus a redemption fee) | Unit Tests | |
| R-02 | When eBTC is redeemed for stETH, the system cancels the eBTC with debt from CDPs, and the stETH is drawn from their collateral in exact amounts (totalDebt Decrease is equal to TS decrease). The debt reduction is pro-rata to all CDPs open based on their size | Unit Tests | |
| R-03 | A redemption sequence of n steps will fully redeem from up to n-1 CDPs, and, and partially redeems from up to 1 CDP, which is always the last CDP in the redemption sequence. | Unit Tests | TODO: check that if the system has at least 1 CDP, it may never go back to 0 CDPs. Interesting to check last partial redemption. |
| R-04 | Redemptions are disabled during the first 14 days of operation since deployment of the eBTC protocol | Valid States | ✅ |
| R-05 | Partially redeemed CDP is re-inserted into the sorted list of CDPs, and remains active, with reduced collateral and debt. Linked List invariant is maintained. And new values correspond with tokens burned and transferred. | Unit Tests | |
| R-06 | If the redemption causes a CDP's full debt to be cancelled, the CDP is then closed: Gas Stipend from the Liquidation Reserve becomes avaiable for the borrower to reclaim along of the CDP's Collateral Surplus. The original CDP owner gets the stipend when a CDP is fully closed by redemption | Unit Tests | |
| R-07 | TCR should be slightly improved after every redemption | High Level | |

## Liquidations

| L-01 | Liquidation only succeeds if ICR < 110% in normal mode, or if ICR < 125% in Recovery Mode. | State Transitions | ✅ |
| L-02 | Any user can liquidate a CDP that does not have enough collateral | High-Level | TODO: check that liquidation always succeeds if MCR < 110% and the user has sufficient eBTC to repay |
| L-03 | As a reward for their service, the liquidator receives a percentage of the CDP's collateral, ranging from 3% to 10%. Additionally, the liquidator also receives a "Gas Stipend" of 0.2 stETH. The liquidator will always recieve 3% minimum bonus of collateral versus debt returned. However, they only get the 0.2 stETH stipend in a full liquidation. For a partial liquidation, only the % bonus is recieved based on the debt value returned. I'll actually need to check what happens if the CDP is below 3% ICR. I'd also clarify that the stipend is not strictly 0.2 stETH. It is stored as shares within the system upon opening of the CDP and therefore will differ based on rebases, and this can be checked through `cdpManager.getCdpLiquidatorRewardShares(cdpId)`  | Unit Tests | TODO: This may break when doing a debt redistributions |
| L-04 | A "Gas Stipend" of 0.2 stETH is previously deposited by the borrower as insurance against liquidation costs | Unit Tests | ✅ |
| L-05 | Anyone may call the public `liquidateCdps` and `batchLiquidateCdps` functions | Unit Tests |  |
| L-06 | Mass liquidations functions cost 60-65k gas per CDP, thus the system can liquidate up to a maximum of 95-105 CDPs in a single transaction | Unit Tests | |
| L-07 | Gas compensation per liquidated CDP is given by the formula: Full liquidation Gas compensation = max(1.03, min(ICR, 1.1)) + Gas Stipend, Partial liquidation Gas compensation = max(1.03, min(ICR, 1.1)) | Unit Tests | |
| L-08 | When a CDP is liquidated, all of the collateral is transferred to the liquidator. When it's fully liquidated, the SHARES are transferred (balance may cause rounding errors). | State Transitions | TODO: check balance before/after of liquidator |
| L-09 | Undercollateralized liquidations are also incentivized with the Gas Stipend. Full liquidations of any type, always pay the stipend | Unit Tests | TODO: check that P-32 holds even if ICR < 100% |
| L-10 | As a Individual Leveraged to the maximum (110 CR), I can only be liquidated if: The oracle price changes in such a way that my CR goes below 110 or Other depositors bring the system CR to 125 (edge of Recovery Mode), then the Oracle Price updates to a lower value, causing every CDP below RM to be liquidatable | State Transitions | TODO: Yes, you can only ever be liquidated if: Below MCR, System is in RM and you are below CCR |
| L-11 | A user can only be liquidated if there is a negative rebasing event or a price change that make the position go below the LT, or RM is triggered | State Transitions | |
| L-12 | TCR must increase after liquidation with no redistributions | High Level | ✅ |

## Fees

| F-01 | All fees generated by the core system are recieved at the `FeeRecipient` address after being claimed. Before being claimed, they are tracked in a variable `FeeRecipientColl` | Unit Tests | |

## eBTC

| EBTC-01 | Anyone with an Ethereum address can send or receive eBTC tokens, whether they have an open CDP or not | Unit Tests | TODO: use [crytic/properties](https://github.com/crytic/properties) |
| EBTC-02 | Any eBTC holder (whether or not they have an active CDP) may redeem their eBTC unless the system is in Recovery Mode | High Level | TODO: verify if this is true for MCR or CCR |
| EBTC-03 | The eBTC token contract implements the ERC20 fungible token standard in conjunction with EIP-2612 and a mechanism that blocks (accidental) transfers to contracts and addresses like address(0) that are not supposed to receive funds through direct transfers | Unit Tests | TODO: this can be partially & easily implemented with [crytic/properties](https://github.com/crytic/properties) |

## Governance

| GOV-01 | Only authorized accounts can call functions which require authorization (`requiresAuth` modifier) | Unit Tests | |

## Price Feed

| PF-01 | The price feed must never revert | High Level | ✅ |
| PF-02 | The price feed must follow valid status transitions | State Transitions | ✅ |
| PF-03 | The price feed must never deadlock | State Transitions |  |
| PF-04 | The price feed should never report an outdated price if chainlink is Working | State Transitions |  |
| PF-05 | The price feed should never use the fallback if chainlink is Working | State Transitions |  |
