# Properties

List of properties of the eBTC protocol, following the categorization by [Certora](https://github.com/Certora/Tutorials/blob/master/06.Lesson_ThinkingProperties/Categorizing_Properties.pdf):

- Valid States
- State Transitions
- Variable Transitions
- High-Level Properties
- Unit Tests

| Property | Description | Type | Tested |
| --- | --- | --- | --- |
| AP-01 | The collateral balance in the active pool is greater than or equal to its accounting number | High Level | ✅ |
| AP-03 | The eBTC debt accounting number in active pool equal to the EBTC total supply | High Level | ✅ |
| AP-04 | The total collateral in active pool should be equal to the sum of all individual CDP collateral | High Level | ✅ |
| AP-05 | The sum of debt accounting in active pool should be equal to sum of debt accounting of individual CDPs | High Level | ✅ |
| CDPM-01 | The count of active CDPs is equal to the SortedCdp list length | High Level | ✅ |
| CDPM-02 | The sum of active CDPs stake is equal to totalStakes | High Level | TODO: verify this under redistributions |
| CDPM-03 | The stFeePerUnit tracker for individual CDP is equal to or less than the global variable | High Level | TODO: Verify if this doesn't lead to inconsistent math after a negative slash (Has pending rewards, slash happens, what happens to CDP totals?) |
| CSP-01 | The collateral balance in the collSurplus pool is greater than or equal to its accounting number | High Level | TODO: Verify if the balance is equal to the shares at all times  |
| SL-01 | The NICR ranking in the sorted list should follow descending order | High Level | ✅ |
| SL-02 | The the first(highest) ICR in the sorted list should bigger or equal to TCR | High Level | ✅ |
| P-01 | The dollar value of the locked stETH exceeds the dollar value of the issued eBTC | High-Level | TODO: check that this BREAKS in case of price change/rebase. This should always be the case unless TCR < 100 Said the opposite way, if TCR < 100, then the value of $ value of eBTC is higher than the value of stETH |
| P-02 | Any eBTC holder (whether or not they have an active CDP) may redeem their eBTC unless the system is in Recovery Mode | High Level | TODO: verify if this is true for MCR or CCR |
| P-03 | After opening a CDP with some stETH, users may issue ("borrow") tokens such that the collateralization ratio of their CDP remains above 110%. After any operation, the TCR must be above the threshold (we may change this to 110 + Buffer) | High Level | TODO: good test, reminds of FREI-PI |
| P-04 | Anyone with an Ethereum address can send or receive eBTC tokens, whether they have an open CDP or not | High-Level | TODO: use [crytic/properties](https://github.com/crytic/properties) |
| P-05 | eBTC tokens are burned upon repayment of a CDP's debt | State Transitions | TODO: check that eBTC.totalSupply() decreases exactly by the amount of debt offset after repayment |
| P-06 | The eBTC system regularly updates the stETH:BTC price via a decentralized data feed | Variable Transitions | |
| P-07 | When a CDP falls below a minimum collateralization ratio (MCR) of 110%, it is considered under-collateralized, and is vulnerable to liquidation. | State Transitions | TODO: check that liquidation only succeeds if ICR < 110% in normal mode, or if ICR < 125% in Recovery Mode |
| P-08 | Any user can liquidate a CDP that does not have enough collateral | High-Level | TODO: check that liquidation always succeeds if MCR < 110% and the user has sufficient eBTC to repay |
| P-09 | As a reward for their service, the liquidator receives a percentage of the CDP's collateral, ranging from 3% to 10%. Additionally, the liquidator also receives a "Gas Stipend" of 0.2 stETH. The liquidator will always recieve 3% minimum bonus of collateral versus debt returned. However, they only get the 0.2 stETH stipend in a full liquidation. For a partial liquidation, only the % bonus is recieved based on the debt value returned. I'll actually need to check what happens if the CDP is below 3% ICR. I'd also clarify that the stipend is not strictly 0.2 stETH. It is stored as shares within the system upon opening of the CDP and therefore will differ based on rebases, and this can be checked through `cdpManager.getCdpLiquidatorRewardShares(cdpId)`  | Unit Tests | TODO: This may break when doing a debt redistributions |
| P-10 | A "Gas Stipend" of 0.2 stETH is previously deposited by the borrower as insurance against liquidation costs | Unit Tests | |
| P-11 | Anyone may call the public `liquidateCdps` and `batchLiquidateCdps` functions | Unit Tests | |
| P-12 | Mass liquidations functions cost 60-65k gas per CDP, thus the system can liquidate up to a maximum of 95-105 CDPs in a single transaction | Unit Tests | |
| P-13 | When a user redeems eBTC, it is exchanged for stETH, at face value (minus a redemption fee) | Unit Tests | |
| P-14 | When eBTC is redeemed for stETH, the system cancels the eBTC with debt from CDPs, and the stETH is drawn from their collateral in exact amounts (totalDebt Decrease is equal to TS decrease). The debt reduction is pro-rata to all CDPs open based on their size | Unit Tests | |
| P-15 | A redemption sequence of n steps will fully redeem from up to n-1 CDPs, and, and partially redeems from up to 1 CDP, which is always the last CDP in the redemption sequence. | Unit Tests | TODO: check that if the system has at least 1 CDP, it may never go back to 0 CDPs. Interesting to check last partial redemption. |
| P-16 | Redemptions are disabled during the first 14 days of operation since deployment of the eBTC protocol | Valid States | |
| P-17 | Partially redeemed CDP is re-inserted into the sorted list of CDPs, and remains active, with reduced collateral and debt. Linked List invariant is maintained. And new values correspond with tokens burned and transferred. | Unit Tests | |
| P-18 | When a CDP is open, the total collateral is the sum of the collaterals split into the `CollSurplusPool`, the gas addresses, and ?? | Valid States | TODO: ask team about [Full redemption](./README.md#full-redemption) |
| P-19 | If an existing CDP's adjustment reduces its ICR, the transaction is only executed if the resulting TCR is above 125% | State Transitions | TODO: May change to TCR + Buffer. KEY invariant |
| P-20 | All fees generated by the core system are recieved at the `FeeRecipient` address after being claimed. Before being claimed, they are tracked in a variable `FeeRecipientColl`` | Unit Tests | |
| P-21 | Only authorized accounts can call functions which require authorization (`requiresAuth` modifier) | Unit Tests | |
| P-22 | The `CdpManager` does not hold value (i.e. Ether / other tokens). After every operation, the balance of the CDPManager is unchanged in terms of stETH and eBTC. | Valid States | TODO: this seems important and easy to implement, as an error can usually mean "leftovers" in position manager contracts (donations are still possible) |
| P-23 | The eBTC token contract implements the ERC20 fungible token standard in conjunction with EIP-2612 and a mechanism that blocks (accidental) transfers to contracts and addresses like address(0) that are not supposed to receive funds through direct transfers | Unit Tests | TODO: this can be partially & easily implemented with [crytic/properties](https://github.com/crytic/properties) |
| P-24 | eBTC tracks CDPs in ascending order of ICR | Variable Transitions | TODO: confirm if I it's descending, First is Highest CR Last is Lowest CR |
| P-25 | The ordering of CDPs is maintained as redistribution occur | Variable Transitions | TODO: Worth checking, as different claim order may move the list temporarily |
| P-26 | A node inserted based on current ICR will maintain the correct position, relative to its peers, as liquidation gains accumulate, as long as its raw collateral and debt have not changed. It will also maintain correct position as: Redemptions happen, stETH Rebases in all directions, Redistribution Happens, Price changes, Liquidations happen (the non-liquidated part of the list remains the same) | Variable Transitions | |
| P-27 | Nodes also remain sorted as the stETH:BTC price varies, since price fluctuations change the collateral value of each CDP by the same proportion | Variable Transitions | |
| P-28 | Nodes need only be re-inserted to the sorted list upon a CDP operation - when the owner adds or removes collateral or debt to their position. Only if the Debt and Coll ratio changes as well, if the ratio remains the same, a call to re-insert may happen, but the resulting order should be the same (e.g. add more coll and debt at same CR) | Variable Transitions | |
| P-29 | stETH in the system lives in three Pools: the ActivePool, the DefaultPool. When an operation is made, stETH is transferred in one of three ways: From a user to a Pool, From a Pool to a user, and From one Pool to another Pool. Except for Liquidations and Redemptions | Variable Transitions | |
| P-30 | Gas compensation per liquidated CDP is given by the formula: Full liquidation Gas compensation = max(1.03, min(ICR, 1.1)) + Gas Stipend, Partial liquidation Gas compensation = max(1.03, min(ICR, 1.1)) | Unit Tests | |
| P-31 | When a borrower closes their active CDP, the gas compensation is refunded: the amount of shares sent by the user are transferred back from the GasPool to the user. Note that these shares may represent a larger amount of stETH than before due to the accrued yield. Same SHARES, different amount. | Unit Tests | |
| P-32 | When a CDP is liquidated, all of the collateral is transferred to the liquidator. When it's fully liquidated, the SHARES are transferred (balance may cause rounding errors). | State Transitions | TODO: check balance before/after of liquidator |
| P-33 | Undercollateralized liquidations are also incentivized with the Gas Stipend. Full liquidations of any type, always pay the stipend | Unit Tests | TODO: check that P-32 holds even if ICR < 100% |
| P-34 | If the redemption causes a CDP's full debt to be cancelled, the CDP is then closed: Gas Stipend from the Liquidation Reserve becomes avaiable for the borrower to reclaim along of the CDP's Collateral Surplus. The original CDP owner gets the stipend when a CDP is fully closed by redemption | Unit Tests | |
| P-35 | At all times, the total stETH balance of the system exceeds the deposits if there is no negative rebasing events | High Level | TODO: important and easy to implement |
| P-36 | At all times, the total debt is equal to the sum of all debts from all CDP + toRedistribute | High Level | |
| P-37 | If the system is not in Recovery Mode (TCR is above Recovery Mode threshold), no user action alone can bring the system to recovery mode without an oracle price change. If RM is triggered by a claim, then the triggering would have happened even if the user didn't do anything except claim the fee. In other words, if an operation by a normal user would trigger RM, then the operation must revert | State Transitions | |
| P-38 | As a Individual Leveraged to the maximum (110 CR), I can only be liquidated if: The oracle price changes in such a way that my CR goes below 110 or Other depositors bring the system CR to 125 (edge of Recovery Mode), then the Oracle Price updates to a lower value, causing every CDP below RM to be liquidatable | State Transitions | TODO: Yes, you can only ever be liquidated if: Below MCR, System is in RM and you are below CCR |
| P-39 | Without a price change, a rebasing event, or a redistribution, my position can never reduce in absolute value | State Transitions | |
| P-40 | A user can only be liquidated if there is a negative rebasing event or a price change that make the position go below the LT, or RM is triggered | State Transitions | |
| P-41 | Users can only open CDPs with healthy ICR | Unit Tests | TODO: Opening CDP can never directly trigger RM, Can NEVER open below 110 |
| P-42 | Users must repay all debt to close a CDP | State Transitions | TODO: Always, at all time, in all conditions |
| P-43 | Each time I change my ICR, the TCR changes by an impact that is equal to the relative weight of collateral and debt from my position | State Transitions | |
| P-44 | At all times TCR = SUM(ICR) for all CDPs | High Level | TODO: redistribution and pending fee split (prob need to look into this more) |
| P-45 | Anyone can open more than 1 CDP, and can open even if one of the CDPs is undercollateralized | High Level | |
| P-46 | TCR should be slightly improved after every redemption | High Level | |