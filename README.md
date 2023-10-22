# eBTC
eBTC is a collateralized crypto asset soft pegged to the price of Bitcoin and built on the Ethereum network. It is backed exclusively by Staked Ether (stETH) and powered by immutable smart contracts with minimized counterparty reliance. It’s designed to be the most decentralized synthetic BTC in DeFi and offers the ability for anyone in the world to borrow BTC at no cost.

After locking up stETH as collateral in a smart contract and creating an individual position called a "CDP", the user can get instant liquidity by minting eBTC. Each CDP is required to be collateralized at a fixed minimum ratio determined by the protocol.

The redemption and liquidation mechanisms help ensure that stability is maintained through economically-driven user interactions and arbitrage, rather than through active governance or monetary interventions.

## eBTC Audit - What's in scope


|File|[SLOC](#nowhere "(nSLOC, SLOC, Lines)")|Description|
:-|:-:|:-|
|_Core Protocol Contracts (10)_|
|[/packages/contracts/contracts/ActivePool.sol]()|[221]|Manages system-level internal accounting and stETH tokens.|
|[/packages/contracts/contracts/BorrowerOperations.sol]()|[751]|Entry point to Open, Adjust, and Close Cdps as well as delegate positionManagers.|
|[/packages/contracts/contracts/CdpManager.sol]()|[578]|Cdp operations and entry point for non-borrower operations on Cdps (Liquidations, Redemptions).|
|[/packages/contracts/contracts/LiquidationLibrary.sol]()|[700]|Contains liquidation-related functions. Split off due to maximum contract size, delegateCalled by CdpManager.|
|[/packages/contracts/contracts/CdpManagerStorage.sol]()|[550]|Shared storage variables between CdpManager and Liquidation Library, and common functions.|
|[/packages/contracts/contracts/CollSurplusPool.sol]()|[83]|Isolated storage of excess collateral owed to users from liquidations or redemptions. Not considered part of system for accounting.|
|[/packages/contracts/contracts/EBTCToken.sol]()|[223]|ERC20 EbtcToken, with permit approvals and extensible minting.|
|[/packages/contracts/contracts/Governor.sol]()|[107]|Roles-based authorization contract, adapted and expanded from solmate Authority. Expanded with more convenience view functions and ability to permanently burn capabilities.|
|[/packages/contracts/contracts/PriceFeed.sol]()|[491]|PriceFeed with primary and secondary oracles and state machine to switch between them and handle failure cases.|
|[/packages/contracts/contracts/SortedCdps.sol]()|[399]|Data storage for the doubly-linked list of Cdps. Sorting of Cdps is used to enforce redemptions from lowest ICR to highest ICR.|
|_Lens / Helper Contracts (4)_|
|[/packages/contracts/contracts/HintHelpers.sol]()|[142]|Generate approximate locations for proper linked list insertion locations for Cdps.|
|[/packages/contracts/contracts/CRLens.sol]()|[98]|Simulate state changes and view results, to compare to expected results in testing env.|
|[/packages/contracts/contracts/MultiCdpGetter.sol]()|[92]|Get data from multiple Cdps in one call.|
|[/packages/contracts/contracts/SyncedLiquidationSequencer.sol]()|[76]|Generate sequences of Cdps available for liquidation, for use with batchLiquidate|
|_Leverage Macros & Smart Wallets (5)_|
|[/packages/contracts/contracts/LeverageMacroBase.sol]()|[353]|Common base implementation of the LeverageMacro.|
|[/packages/contracts/contracts/LeverageMacroDelegateTarget.sol]()|[30]|LeverageMacro variant for use with delegateCall with compatible smart wallets.|
|[/packages/contracts/contracts/LeverageMacroFactory.sol]()|[46]|Factory for deploying LeverageMacroReference|
|[/packages/contracts/contracts/LeverageMacroReference.sol]()|[38]|LeverageMacro variant for use as a zap with an individual owner.|
|[/packages/contracts/contracts/SimplifiedDiamondLike.sol]()|[109]|Smart wallet with custom callback handler support.|
|_Modified Dependencies (7)_|
|[/packages/contracts/contracts/Dependencies/Auth.sol]()|[33]|Inherited by contracts consuming authorization rules of Governor.|
|[/packages/contracts/contracts/Dependencies/AuthNoOwner.sol]()|[36]|Inherited by contracts consuming authorization rules of Governor. Removes owner address that has global 'admin' permission from Auth.|
|[/packages/contracts/contracts/Dependencies/ERC3156FlashLender.sol]()|[10]|Base for standardized flash loans|
|[/packages/contracts/contracts/Dependencies/EbtcBase.sol]()|[78]|Common definition and base functions for system contracts.|
|[/packages/contracts/contracts/Dependencies/EbtcMath.sol]()|[62]|More common math functions for system contracts.|
|[/packages/contracts/contracts/Dependencies/ReentrancyGuard.sol]()|[12]|Simple, optimized reentrancy guard.|
|[/packages/contracts/contracts/Dependencies/RolesAuthority.sol]()|[102]|Role-based authorization from solmate. Expanded functionality for use with Governor.|


## Known issues from Previous Audits

All findings contained in theses reports:
- RiskDAO: https://github.com/Risk-DAO/Reports/blob/main/eBTC.pdf
- Trust: https://badger.com/images/uploads/trust-ebtc-audit-report.pdf
- Spearbit: https://badger.com/images/uploads/ebtc-security-review-spearbit.pdf
- Cantina: https://badger.com/images/uploads/ebtc-security-review-cantina.pdf

Acknowledged findings should be considered known and ignored

Fixes to the above findings may have introduced bugs and should be well accepted

## More information

- [Introducing eBTC - A Decentralized Bitcoin Powered by Ethereum Staking](https://forum.badger.finance/t/introducing-ebtc-a-decentralized-bitcoin-powered-by-ethereum-staking/5952)
- See the [eBTC Cheatsheet](https://gist.github.com/GalloDaSballo/7b060bb97de09c539ec64c533dd352c6) for an up to date list of additional resources.

## Known issues

### There is no fallback oracle as of now
We should gracefully handle the case of no fallback oracle, as well as switching to a fallback oracle from having none.

### If Chainlink dependencies burn all gas, or the contract is destructed, then the Price Feed will revert

### If Chainlink performs an upgrade, due to how PhaseId and RoundId are calculated the price will be stale

This is because there will not be a valid price at roundId - 1

The Oracle will resume working as intended once the CL Feed reports 2 prices from the same aggregator (see Spearibit / Cantina Reports for more details)

### We understand some rounding errors can happen
Badger will:
- Donate up to 2 stETH of collateral to the system contracts as a way to prevent any shortfall due to rounding (avoids off by one errors)
- Keep open, at all times, a CDP with at least 2 stETH of Collateral with a CR between 150 and 200% (ensures its the last DP)

For this reason, rounding errors related to stETH should not be accepted as valid unless they can provably break the 2stETH threshold under reasonable circumnstances (e.g. 100 billion people using the protocol would be considered above reasonable)


### stETH contract can be arbitrarily upgraded
We acknowledge that and understand that’s a dependency risk.

### eBTC Governance has the ability to cause substantial damage
These impacts but are not limited to:

  - Mint new eBTC (until extensible minting capability is burned)
  - Pause Flashloans and Redemptions
  - Raise fees for Flashloans and Redemtpions
  - Raise the Fee Split of stETH to up to 100%
  - Delay Recovery Mode via the Grace Period to an indefinite amount

eBTC governance should however not be able to block depositing, minting, adjusting and closing of positions under any circumstance.

### Permit Signatures are malleable
Because they use nonces, the malleability cannot be exploited.

### Malicious Position Managers can steal all tokens from borrowers that grant them approvals
Position Managers can receive Permanent or One Time abilities to perform any operation on behalf of an address.

Ths means that signing delegation to a malicious address can cause a total loss of funds for all CDPs

We recommend:
- Opening a single CDP per address
- Verifying the code of the recipient of the delegation
- Ensure that the recipient of the delegation is a safe zap that rescinds it's ownership after the transaction
- Simulate all your transactions before performing them

### The tokens of the system are fixed: StETH and eBTC

They do not require safeTransfer nor SafeApprove, eBTC is deployed exclusively on mainnet

### Flashloan Limits can be bypassed

The limitations are capping the value that one call can access, but looping to borrow more stETH and more eBTC can occur.

### Prevening Bad Debt Redistribution
Closing a CDP or reducing Stake are ways to prevent or minimize redistribution of bad debt during Normal Mode.

Sandwiching the redistribution:
* close or reduce position
* bad debt redistribution event occurs
* re-open or increase position

### Incorrect Sorting due to Pending Debt and Yield
We have been able to create scenarios during fuzz testing in which the sorting of CDPs invariant is violated. Anticipate example cases shown here. The impact is believed to be minimal in practice.

### Liquidators can behave in ways that are not ideal to the protocol security
Liquidators can maximize their expected profits by liquidating from the lowest risk CDP -> highest risk CDP.

Lower risk CDPs (e.g. 109%) offer more due to the dynamic premium than higher risk CDPs (e.g. 103%)

From our benchmarks, assuming liquidations happen at 3% premium requires a 2/1 eBTC ratio in a stableswap pool vs like-kind BTC asset before it becomes a concern (see riskDAO report).

### Liquidations Premium
Was determined via modelling by RiskDAO

3% bad debt is extremely smaller compared to worst case scenarios

And 3% for a stableswap is a crazy high depeg

### Leverage Macro
Because swaps may not use all tokens, some dust could be left in the contract.

It can be swept after, but may cause operations to be slightly inefficient if slippage occurs between the time the calldata is generated and the call is executed.

### Grace Period Desynchs

#### Grace Period Cannot start if no interaction happens

Liquidations for Recovery Mode will be delayed by at least the `recoveryModeGracePeriodDuration`

This period can take longer as the countdown must be started, either via any single person performing an operation, or by calling `syncGlobalAccountingAndGracePeriod`

### Grace Period will not re-start if the system exists recovery mode but no interaction re-sets it

Grace Period may also be triggered, then the price could raise to "undo recovery mode" and if no action is performed during this period, the next time Recovery Mode is triggered, the Grace Period will be already expired - See the test `testL15Debunk` which shows how this can happen

To Reiterate:
If nobody calls the Start or the End of the Grace Period, then:
- Nobody ends it -> RM Liquidations will have no delay
- Nobody starts it -> RM Liquidations cannot happen until the Grace Period is started and the time has passed

### Grace Period can be denied by repaying
Can be denied by repaying or by depositing more collateral.

Repaying or adding more collateral are intended behaviours, they helps the system and reduce the maximum debt that has to be liquidated at a time.

Adding collateral raises your CR as well, and it's always cheaper to repay than to deposit collateral.

Proper risky Liquidations are not delayed in any way.


## Other Notes
We anticipate liquidators and redemption arbitrageurs to use Curve and Balancer pools to access on-chain liquidity. Potential economic attacks should be considered taking this into account.

Specifically, the main pairs for eBTC are going to be:

- StableSwap eBTC - wBTC (Low Fee)
Which will allow buying stETH via the highly liquid wBTC - WETH pair

- 50/50 Pool eBTC - stETH - High Fee (50 BPS / 1%)

Which allows delta neutral LPing as well as gas efficient liquidations and leverage for smaller sizes (the pool price imbalances more rapidly)

## eBTC System Summary
- [eBTC Overview](#ebtc-overview)
- [Liquidations](#liquidations)
- [eBTC Token Redemption](#ebtc-token-redemption)
  - [Partial redemption](#partial-redemption)
  - [Full redemption](#full-redemption)
  - [Redemptions create a price floor](#redemptions-create-a-price-floor)
- [Recovery Mode](#recovery-mode)
- [Project Structure](#project-structure)
  - [Directories](#directories)
- [Core System Architecture](#core-system-architecture)
  - [Contract Interfaces](#contract-interfaces)
  - [PriceFeed and Oracle](#pricefeed-and-oracle)
  - [PriceFeed Logic](#pricefeed-logic)
  - [Testnet PriceFeed and PriceFeed tests](#testnet-pricefeed-and-pricefeed-tests)
  - [PriceFeed limitations and known issues](#pricefeed-limitations-and-known-issues)
  - [Keeping a sorted list of CDPs ordered by ICR](#keeping-a-sorted-list-of-cdps-ordered-by-icr)
- [Expected User Behaviors](#expected-user-behaviors)
- [Contract Ownership and Function Permissions](#contract-ownership-and-function-permissions)
- [Deployment to a Development Blockchain](#deployment-to-a-development-blockchain)
- [System Quantities - Units and Representation](#system-quantities---units-and-representation)
  - [Integer representations of decimals](#integer-representations-of-decimals)
- [Public Data](#public-data)
- [Core Public User-Facing Functions](#core-public-user-facing-functions)
  - [Borrower (CDP) Operations - `BorrowerOperations.sol`](#borrower-cdp-operations---borroweroperationssol)
  - [CdpManager Functions - `CdpManager.sol`](#cdpmanager-functions---cdpmanagersol)
  - [Hint Helper Functions - `HintHelpers.sol`](#hint-helper-functions---hinthelperssol)
  - [Stability Pool Functions - `StabilityPool.sol`](#stability-pool-functions---stabilitypoolsol)
  - [eBTC token `EBTCToken.sol`](#ebtc-token-ebtctokensol)
- [Supplying Hints to CDP operations](#supplying-hints-to-cdp-operations)
  - [Hints for `redeemCollateral`](#hints-for-redeemcollateral)
    - [First redemption hint](#first-redemption-hint)
    - [Partial redemption hints](#partial-redemption-hints)
- [Gas compensation](#gas-compensation)
  - [Gas compensation schedule](#gas-compensation-schedule)
  - [Liquidation](#liquidation)
  - [Gas compensation and redemptions](#gas-compensation-and-redemptions)
  - [Gas compensation helper functions](#gas-compensation-helper-functions)
- [eBTC Redemption Fees](#ebtc-redemption-fees)
  - [Redemption Fee](#redemption-fee)
  - [Fee Schedule](#fee-schedule)
  - [Intuition behind fees](#intuition-behind-fees)
  - [Fee decay Implementation](#fee-decay-implementation)
  - [Staking LQTY and earning fees](#staking-lqty-and-earning-fees)
- [Redistributions and Corrected Stakes](#redistributions-and-corrected-stakes)
  - [Corrected Stake Solution](#corrected-stake-solution)
- [Math Proofs](#math-proofs)
- [Definitions](#definitions)
- [Development](#development)
  - [Prerequisites](#prerequisites)
    - [Making node-gyp work](#making-node-gyp-work)
  - [Clone & Install](#clone--install)
  - [Top-level scripts](#top-level-scripts)
    - [Run all tests](#run-all-tests)
    - [Deploy contracts to a testnet](#deploy-contracts-to-a-testnet)
    - [Start a local fork blockchain and deploy the contracts](#start-a-local-fork-blockchain-and-deploy-the-contracts)
    - [Start dev-frontend in development mode](#start-dev-frontend-in-development-mode)
    - [Start dev-frontend in demo mode](#start-dev-frontend-in-demo-mode)
    - [Start dev-frontend against a mainnet fork RPC node](#start-dev-frontend-against-a-mainnet-fork-rpc-node)
    - [Build dev-frontend for production](#build-dev-frontend-for-production)
  - [Configuring your custom frontend](#configuring-your-custom-dev-ui)
- [Running a frontend with Docker](#running-dev-ui-with-docker)
  - [Prerequisites](#prerequisites-1)
  - [Running with `docker`](#running-with-docker)
  - [Configuring a public frontend](#configuring-a-public-dev-ui)
    - [FRONTEND_TAG](#frontend_tag)
    - [INFURA_API_KEY](#infura_api_key)
  - [Setting a kickback rate](#setting-a-kickback-rate)
  - [Setting a kickback rate with Gnosis Safe](#setting-a-kickback-rate-with-gnosis-safe)
  - [Next steps for hosting a frontend](#next-steps-for-hosting-dev-ui)
    - [Example 1: using static website hosting](#example-1-using-static-website-hosting)
    - [Example 2: wrapping the frontend container in HTTPS](#example-2-wrapping-the-dev-ui-container-in-https)
- [Known Issues](#known-issues)
  - [Front-running issues](#front-running-issues)
- [Periphery](#periphery)

## eBTC Overview
eBTC is a collateralized crypto asset soft pegged to the price of Bitcoin and built on the Ethereum network. It is backed exclusively by Lido's stETH and powered by immutable smart contracts with minimized counterparty reliance. It’s designed to be the most decentralized synthetic BTC in DeFi and offers the ability for anyone in the world to borrow BTC at no cost.

A CDP is the unit of accounting used to track a specific borrowed debt amount, the respective collateral that backs it as well as the ratio between the value of these two assets, known as the Individual Collateral Ratio (ICR). Each CDP is tied and owned by a single Ethereum account.

CDP owners have the freedom to make adjustments to their CDPs at any time by increasing their collateral, withdrawing some collateral, borrowing more debt, or repaying a part or the full outstanding debt. Any modification to the CDP triggers a corresponding adjustment to the ICR.

The eBTC Token is designed with economic properties that aim to maintain price parity with BTC. These properties include:

1. The system is designed to always be over-collateralized - the dollar value of the locked stETH exceeds the dollar value of the issued eBTC.

2. eBTC token are fully redeemable - users can always swap $x worth of eBTC for $x worth of stETH (minus fees), directly with the system.

After opening a CDP with some stETH, users may issue ("borrow") tokens such that the collateralization ratio of their CDP remains above 110%. A user with $1000 worth of stETH in a CDP can issue up to $909.09 worth of eBTC.

The tokens are freely exchangeable - anyone with an Ethereum address can send or receive eBTC tokens, whether they have an open CDP or not. The tokens are burned upon repayment of a CDP's debt.

The eBTC system regularly updates the stETH:BTC price via a decentralized data feed. When a CDP falls below a minimum collateralization ratio (MCR) of 110%, it is considered under-collateralized, and is vulnerable to liquidation.

## Liquidations
eBTC implements an open and incentivized liquidation mechanism, where any user can liquidate a CDP that does not have enough collateral. As a reward for their service, the liquidator receives a percentage of the CDP's collateral, ranging from 3% to 10%. Additionally, the liquidator also receives a "Gas Stipend" of 0.2 stETH, which is previously deposited by the borrower as insurance against liquidation costs. See [this](https://hackmd.io/@re73/r19oq9LM2) for details.

Anyone may call the public `liquidate()` function, which will allow the liquidation of under-collateralized CDPs. Alternatively they can call `batchLiquidateCdps()` with a custom list of CDP addresses to attempt to liquidate.

## eBTC Token Redemption

Any eBTC holder (whether or not they have an active CDP) may redeem their eBTC directly with the system. Their eBTC is exchanged for stETH, at face value: redeeming x eBTC tokens returns \$x worth of stETH (minus a [redemption fee](#redemption-fee)).

When eBTC is redeemed for stETH, the system cancels the eBTC with debt from CDPs, and the stETH is drawn from their collateral.

In order to fulfill the redemption request, CDPs are redeemed from in ascending order of their collateralization ratio.

A redemption sequence of `n` steps will **fully** redeem from up to `n-1` CDPs, and, and **partially** redeems from up to 1 CDP, which is always the last CDP in the redemption sequence.

Redemptions are blocked when TCR < 110% (there is no need to restrict ICR < TCR). At that TCR redemptions would likely be unprofitable, as eBTC is probably trading below the price of 1 BTC if the system has crashed that badly, but it could be a way for an attacker with a lot of eBTC to lower the TCR even further.

Note that redemptions are disabled during the first 14 days of operation since deployment of the eBTC protocol to protect the monetary system in its infancy.

### Partial redemption

Most redemption transactions will include a partial redemption, since the amount redeemed is unlikely to perfectly match the total debt of a series of CDPs.

The partially redeemed CDP is re-inserted into the sorted list of CDPs, and remains active, with reduced collateral and debt.

### Full redemption

If we assume the fixed liquidation incentive is 200 units, A CDP is defined as “fully redeemed from” when the redemption has caused its debt to absorb (debt-200) eBTC. Then, its 200 eBTC Liquidation Reserve is cancelled with its remaining 200 debt: the Liquidation Reserve is burned from the gas address, and the 200 debt is zero’d.

Before closing, we must handle the CDP’s **collateral surplus**: that is, the excess stETH collateral remaining after redemption, due to its initial over-collateralization.

This collateral surplus is sent to the `CollSurplusPool`, and the borrower can reclaim it later. The CDP is then fully closed.

### Redemptions create a price floor

Economically, the redemption mechanism creates a hard price floor for eBTC, ensuring that the market price stays at or near to 1 Bitcoin. 

## Recovery Mode

Recovery Mode kicks in when the total collateralization ratio (TCR) of the system falls below 125%.

During Recovery Mode, liquidation conditions are relaxed, and the system blocks borrower transactions that would further decrease the TCR. New eBTC may only be issued by adjusting existing CDPs in a way that improves their ICR, or by opening a new CDP with an ICR of >=125%. In general, if an existing CDP's adjustment reduces its ICR, the transaction is only executed if the resulting TCR is above 125%

Recovery Mode is structured to incentivize borrowers to behave in ways that promptly raise the TCR back above 125%.

Economically, Recovery Mode is designed to encourage collateral top-ups and debt repayments, and also itself acts as a self-negating deterrent: the possibility of it occurring actually guides the system away from ever reaching it.

## Project Structure

### Directories
- `packages/contracts/` - The backend development folder, contains the Hardhat and Foundry projects, contracts, and tests
- `packages/contracts/contracts/` - The core back end smart contracts written in Solidity
- `packages/contracts/test/` - JS test suite for the system. Tests run in Mocha/Chai
- `packages/contracts/foundry_test/` - Foundry test suite for the system
- `packages/contracts/tests/` - Python test suite for the system. Tests run in Brownie
- `packages/contracts/utils/` - external Hardhat and node scripts - deployment helpers, gas calculators, etc

Backend development is done in the Hardhat framework, and allows eBTC to be deployed on the Hardhat EVM network for fast compilation and test execution.

## External Contract Architecture
Fees generated through the core protocol are managed at an external FeeRecipient contract. This contract is fully managed by BadgerDAO but with the option to switch it out for a new mechanic.

`FeeRecipient.sol` - All fees generated by the core system are recieved at this address, with events emitted when a fee is processed for acounting purposes. These fees include redemptions and the staking yield split.

## Core System Architecture

The core eBTC system consists of several smart contracts.

All application logic and data is contained in these contracts - there is no need for a separate database or back end logic running on a web server. In effect, the Ethereum network is itself the eBTC back end. As such, all balances and contract data are public.


The two main contracts - `BorrowerOperations.sol` and `CdpManager.sol` - hold the user-facing public functions, and contain most of the internal system logic. Together they control CDP state updates and movements of stETH and eBTC tokens around the system.

### PriceFeed and Oracle

eBTC functions that require the most current stETH:BTC price data fetch the price dynamically, as needed, via the core `PriceFeed.sol` contract using the Chainlink stETH:BTC reference contract as its primary and can use another oracle source as a secondary. PriceFeed is stateful, i.e. it records the last good price that may come from either of the two sources based on the contract's current state.

The fallback logic distinguishes 3 different failure modes for Chainlink and 2 failure modes for the backup:

- `Frozen` (for both oracles): last price update more than 4 hours ago
- `Broken` (for both oracles): response call reverted, invalid timeStamp that is either 0 or in the future, or reported price is non-positive (Chainlink) or zero (Backup). Chainlink is considered broken if either the response for the latest round _or_ the response for the round before the latest fails one of these conditions.
- `PriceChangeAboveMax` (Chainlink only): higher than 50% deviation between two consecutive price updates

There is also a return condition `bothOraclesLiveAndUnbrokenAndSimilarPrice` which is a function returning true if both oracles are live and not broken, and the percentual difference between the two reported prices is below 5%.

The current `PriceFeed.sol` contract has an external `fetchPrice()` function that is called by core eBTC functions which require a current stETH:BTC price.  `fetchPrice()` calls each oracle's proxy, asserts on the responses, and converts returned prices to 18 digits.

### PriceFeed Logic

The PriceFeed contract fetches the current price and previous price from Chainlink and changes its state (called `Status`) based on certain conditions.

**Initial PriceFeed state:** `chainlinkWorking`. The initial system state that is maintained as long as Chainlink is working properly, i.e. neither broken nor frozen nor exceeding the maximum price change threshold between two consecutive rounds. PriceFeed then obeys the logic found in this table:

  https://docs.google.com/spreadsheets/d/18fdtTUoqgmsK3Mb6LBO-6na0oK-Y9LWBqnPCJRp5Hsg/edit?usp=sharing


### Testnet PriceFeed and PriceFeed tests

The `PriceFeedTestnet.sol` is a mock PriceFeed for testnet and general back end testing purposes, with no oracle connection. It contains a manual price setter, `setPrice()`, and a getter, `getPrice()`, which returns the latest stored price.

### PriceFeed limitations and known issues

The purpose of the PriceFeed is to be at least as good as an immutable PriceFeed that relies purely on Chainlink, while also having some resilience in case of Chainlink failure / timeout, and chance of recovery.

The PriceFeed logic consists of automatic on-chain decision-making for obtaining fallback price data from the backup, and if possible, for returning to Chainlink if/when it recovers.

The PriceFeed logic is complex, and although we would prefer simplicity, it does allow the system a chance of switching to an accurate price source in case of a Chainlink failure or timeout, and also the possibility of returning to an honest Chainlink price after it has failed and recovered.

We believe the benefit of the fallback logic is worth the complexity. If we had no fallback logic and Chainlink were to be hacked or permanently fail, eBTC would become unusable without a backup.

Governance is also capable of setting a new backup oracle feed, as long as it conforms to the interface.

**Chainlink Decimals**: the `PriceFeed` checks for and uses the latest `decimals` value reported by the Chainlink aggregator in order to calculate the Chainlink price at 18-digit precision, as needed by eBTC.  `PriceFeed` does not assume a value for decimals and can handle the case where Chainlink change their decimal value. 

However, the check `chainlinkIsBroken` uses both the current response from the latest round and the response previous round. Since `decimals` is not attached to round data, eBTC has no way of knowing whether decimals has changed between the current round and the previous round, so we assume it is the same. eBTC assumes the current return value of decimals() applies to both current round `i` and previous round `i-1`. 

This means that a decimal change that coincides with a eBTC price fetch could cause eBTC to assert that the Chainlink price has deviated too much, and fall back to the backup. There is nothing we can do about this. We hope/expect Chainlink to never change their `decimals()` return value (currently 8), and if a hack/technical error causes Chainlink's decimals to change, eBTC may fall back to the backup.

To summarize the Chainlink decimals issue: 
- eBTC can handle the case where Chainlink decimals changes across _two consecutive rounds `i` and `i-1` which are not used in the same eBTC price fetch_
- If eBTC fetches the price at round `i`, it will not know if Chainlink decimals changed across round `i-1` to round `i`, and the consequent price scaling distortion may cause eBTC to fall back to the backup.
- eBTC will always calculate the correct current price at 18-digit precision assuming the current return value of `decimals()` is correct (i.e. is the value used by the nodes).

### Keeping a sorted list of CDPs ordered by ICR

eBTC relies on a particular data structure: a sorted doubly-linked list of CDPs that remains ordered by individual collateralization ratio (ICR), i.e. the amount of collateral value divided by the amount of debt value.

This ordered list is critical for gas-efficient redemption sequences and for the `liquidateCdps` sequence, both of which target CDPs in ascending order of ICR.

The sorted doubly-linked list is found in `SortedCdps.sol`. 

Nodes map to active CDPs in the system - the ID property is the address of a CDP owner. The list accepts positional hints for efficient O(1) insertion - please see the [hints](#supplying-hints-to-cdp-operations) section for more details.

ICRs are computed dynamically at runtime, and not stored on the node. This is because ICRs of active CDPs change dynamically, when:

- The stETH:BTC price varies, altering the value of the collateral of every CDP
- A liquidation that redistributes collateral and debt to active CDPs occurs

The list relies on the fact that a collateral and debt redistribution due to a liquidation preserves the ordering of all active CDPs (though it does decrease the ICR of each active CDP above the MCR).

The fact that ordering is maintained as redistributions occur, is not immediately obvious: please see the [mathematical proof](https://github.com/liquity/dev/blob/main/papers) which shows that this holds in eBTC.

A node inserted based on current ICR will maintain the correct position, relative to its peers, as liquidation gains accumulate, as long as its raw collateral and debt have not changed.

Nodes also remain sorted as the stETH:BTC price varies, since price fluctuations change the collateral value of each CDP by the same proportion.

Thus, nodes need only be re-inserted to the sorted list upon a CDP operation - when the owner adds or removes collateral or debt to their position.

## Expected User Behaviors

Generally, borrowers call functions that trigger CDP operations on their own CDP.

Anyone may call the public liquidation functions, and attempt to liquidate one or several CDPs.

eBTC token holders may also redeem their tokens, and swap an amount of tokens 1-for-1 in value (minus fees) with stETH.

## Contract Ownership and Function Permissions

Several public and external functions have modifiers such as `requireCallerIsCdpManager`, `requireCallerIsActivePool`, etc - ensuring they can only be called by the respective permitted contract.

Functions subject to minimal governance use the `isAuthorized()` modifier inherited from `AuthNoOwner.sol`. The authority contract is the Governor. See [solmate auth paradigm](https://github.com/transmissions11/solmate/tree/main/src/auth) which this functionality is lightly modified from.

## Deployment to a Development Blockchain

The script in `mainnetDeployment/eBTCDeployScript.js` deploy all contracts, and connects all contracts to their dependency contracts, by setting the necessary deployed addresses.

The project is deployed on the Sepolia testnet.

## System Quantities - Units and Representation

### Integer representations of decimals

Several ratios and the stETH:BTC price are integer representations of decimals, to 18 digits of precision. For example:

| **uint representation of decimal** | **Number**    |
| ---------------------------------- | ------------- |
| 1100000000000000000                | 1.1           |
| 200000000000000000000              | 200           |
| 1000000000000000000                | 1             |
| 5432100000000000000                | 5.4321        |
| 34560000000                        | 0.00000003456 |
| 370000000000000000000              | 370           |
| 1                                  | 1e-18         |

etc.

## Public Data

## Core Public User-Facing Functions

### Borrower (CDP) Operations - `BorrowerOperations.sol`

- `openCdp`
- `openCdpFor`
- `addColl`
- `withdrawColl`
- `withdrawDebt`
- `repayDebt`
- `adjustCdp`
- `adjustCdpWithColl`
- `closeCdp`
- `claimCollateral`
- `setPositionManagerApproval`
- `revokePositionManagerApproval`
- `renouncePositionManagerApproval`
- `permitPositionManagerApproval`

### CdpManager Functions - `CdpManager.sol`

- `liquidate`
- `partiallyLiquidate`
- `batchLiquidateCdps`
- `redeemCollateral`

### Hint Helper Functions - `HintHelpers.sol`

`function getApproxHint(uint _CR, uint _numTrials, uint _inputRandomSeed)`: helper function, returns a positional hint for the sorted list. Used for transactions that must efficiently re-insert a CDP to the sorted list.

`getRedemptionHints(uint _EBTCamount, uint _price, uint _maxIterations)`: helper function specifically for redemptions. Returns three hints:

- `firstRedemptionHint` is a positional hint for the first redeemable CDP (i.e. CDP with the lowest ICR >= MCR).
- `partialRedemptionHintNICR` is the final nominal ICR of the last CDP after being hit by partial redemption, or zero in case of no partial redemption (see [Hints for `redeemCollateral`](#hints-for-redeemcollateral)).
- `truncatedEBTCamount` is the maximum amount that can be redeemed out of the the provided `_EBTCamount`. This can be lower than `_EBTCamount` when redeeming the full amount would leave the last CDP of the redemption sequence with less debt than the minimum allowed value.

The number of CDPs to consider for redemption can be capped by passing a non-zero value as `_maxIterations`, while passing zero will leave it uncapped.

### eBTC token `EBTCToken.sol`

Standard ERC20 and EIP2612 (`permit()` ) functionality.

**Note**: `permit()` can be front-run, as it does not require that the permitted spender be the `msg.sender`.

This allows flexibility, as it means that _anyone_ can submit a Permit signed by A that allows B to spend a portion of A's tokens.

The end result is the same for the signer A and spender B, but does mean that a `permit` transaction
could be front-run and revert - which may hamper the execution flow of a contract that is intended to handle the submission of a Permit on-chain.

For more details please see the original proposal EIP-2612:
https://eips.ethereum.org/EIPS/eip-2612

## Supplying Hints to CDP operations

CDPs in eBTC are recorded in a sorted doubly linked list, sorted by their NICR, from high to low. NICR stands for the nominal collateral ratio that is simply the amount of collateral (in stETH) multiplied by 100e18 and divided by the amount of debt (in eBTC), without taking the stETH:BTC price into account. Given that all CDPs are equally affected by stETH price changes, they do not need to be sorted by their real ICR.

All CDP operations that change the collateralization ratio need to either insert or reinsert the CDP to the `SortedCdps` list. To reduce the computational complexity (and gas cost) of the insertion to the linked list, two ‘hints’ may be provided.

A hint is the address of a CDP with a position in the sorted list close to the correct insert position.

All CDP operations take two ‘hint’ arguments: a `_lowerHint` referring to the `nextId` and an `_upperHint` referring to the `prevId` of the two adjacent nodes in the linked list that are (or would become) the neighbors of the given CDP. Taking both direct neighbors as hints has the advantage of being much more resilient to situations where a neighbor gets moved or removed before the caller's transaction is processed: the transaction would only fail if both neighboring CDPs are affected during the pendency of the transaction.

The better the ‘hint’ is, the shorter the list traversal, and the cheaper the gas cost of the function call. `SortedList::findInsertPosition(uint256 _NICR, address _prevId, address _nextId)` that is called by the CDP operation firsts check if `prevId` is still existant and valid (larger NICR than the provided `_NICR`) and then descends the list starting from `prevId`. If the check fails, the function further checks if `nextId` is still existant and valid (smaller NICR than the provided `_NICR`) and then ascends list starting from `nextId`. 

The `HintHelpers::getApproxHint(...)` function can be used to generate a useful hint pointing to a CDP relatively close to the target position, which can then be passed as an argument to the desired CDP operation or to `SortedCdps::findInsertPosition(...)` to get its two direct neighbors as ‘exact‘ hints (based on the current state of the system).

`getApproxHint(uint _CR, uint _numTrials, uint _inputRandomSeed)` randomly selects `numTrials` amount of CDPs, and returns the one with the closest position in the list to where a CDP with a nominal collateralization ratio of `_CR` should be inserted. It can be shown mathematically that for `numTrials = k * sqrt(n)`, the function's gas cost is with very high probability worst case `O(sqrt(n)) if k >= 10`. For scalability reasons (Infura is able to serve up to ~4900 trials), the function also takes a random seed `_inputRandomSeed` to make sure that calls with different seeds may lead to a different results, allowing for better approximations through multiple consecutive runs.

**CDP operation without a hint**

1. User performs CDP operation in their browser
2. Call the CDP operation with `_lowerHint = _upperHint = userAddress`

Gas cost will be worst case `O(n)`, where n is the size of the `SortedCdps` list.

**CDP operation with hints**

1. User performs CDP operation in their browser
2. The front end computes a new collateralization ratio locally, based on the change in collateral and/or debt.
3. Call `HintHelpers::getApproxHint(...)`, passing it the computed nominal collateralization ratio. Returns an address close to the correct insert position
4. Call `SortedCdps::findInsertPosition(uint256 _NICR, address _prevId, address _nextId)`, passing it the same approximate hint via both `_prevId` and `_nextId` and the new nominal collateralization ratio via `_NICR`. 
5. Pass the ‘exact‘ hint in the form of the two direct neighbors, i.e. `_nextId` as `_lowerHint` and `_prevId` as `_upperHint`, to the CDP operation function call. (Note that the hint may become slightly inexact due to pending transactions that are processed first, though this is gracefully handled by the system that can ascend or descend the list as needed to find the right position.)

Gas cost of steps 2-4 will be free, and step 5 will be `O(1)`.

Hints allow cheaper CDP operations for the user, at the expense of a slightly longer time to completion, due to the need to await the result of the two read calls in steps 1 and 2 - which may be sent as JSON-RPC requests to Infura, unless the Frontend Operator is running a full Ethereum node.

### Example Borrower Operations with Hints

#### Opening a CDP
```
  const toWei = web3.utils.toWei
  const toBN = web3.utils.toBN

  const EBTCAmount = toBN(toWei('2500')) // borrower wants to withdraw 2500 eBTC
  const ETHColl = toBN(toWei('5')) // borrower wants to lock 5 stETH collateral

  // Call deployed CdpManager contract to read the liquidation reserve and latest borrowing fee
  const liquidationReserve = await cdpManager.EBTC_GAS_COMPENSATION()
  const expectedFee = await cdpManager.getBorrowingFeeWithDecay(EBTCAmount)
  
  // Total debt of the new CDP = eBTC amount drawn, plus fee, plus the liquidation reserve
  const expectedDebt = EBTCAmount.add(expectedFee).add(liquidationReserve)

  // Get the nominal NICR of the new CDP
  const _1e20 = toBN(toWei('100'))
  let NICR = ETHColl.mul(_1e20).div(expectedDebt)

  // Get an approximate address hint from the deployed HintHelper contract. Use (15 * number of CDPs) trials 
  // to get an approx. hint that is close to the right position.
  let numCdps = await sortedCdps.getSize()
  let numTrials = numCdps.mul(toBN('15'))
  let { 0: approxHint } = await hintHelpers.getApproxHint(NICR, numTrials, 42)  // random seed of 42

  // Use the approximate hint to get the exact upper and lower hints from the deployed SortedCdps contract
  let { 0: upperHint, 1: lowerHint } = await sortedCdps.findInsertPosition(NICR, approxHint, approxHint)

  // Finally, call openCdp with the exact upperHint and lowerHint
  const maxFee = '5'.concat('0'.repeat(16)) // Slippage protection: 5%
  await borrowerOperations.openCdp(maxFee, EBTCAmount, upperHint, lowerHint, { value: ETHColl })
```

#### Adjusting a CDP
```
  const collIncrease = toBN(toWei('1'))  // borrower wants to add 1 stETH
  const EBTCRepayment = toBN(toWei('230')) // borrower wants to repay 230 eBTC

  // Get CDP's current debt and coll
  const {0: debt, 1: coll} = await cdpManager.getSyncedDebtAndCollShares(borrower)
  
  const newDebt = debt.sub(EBTCRepayment)
  const newColl = coll.add(collIncrease)

  NICR = newColl.mul(_1e20).div(newDebt)

  // Get an approximate address hint from the deployed HintHelper contract. Use (15 * number of CDPs) trials 
  // to get an approx. hint that is close to the right position.
  numCdps = await sortedCdps.getSize()
  numTrials = numCdps.mul(toBN('15'))
  ({0: approxHint} = await hintHelpers.getApproxHint(NICR, numTrials, 42))

  // Use the approximate hint to get the exact upper and lower hints from the deployed SortedCdps contract
  ({ 0: upperHint, 1: lowerHint } = await sortedCdps.findInsertPosition(NICR, approxHint, approxHint))

  // Call adjustCdp with the exact upperHint and lowerHint
  await borrowerOperations.adjustCdp(maxFee, 0, EBTCRepayment, false, upperHint, lowerHint, {value: collIncrease})
```

### Hints for `redeemCollateral`

`CdpManager::redeemCollateral` as a special case requires additional hints:
- `_firstRedemptionHint` hints at the position of the first CDP that will be redeemed from,
- `_lowerPartialRedemptionHint` hints at the `nextId` neighbor of the last redeemed CDP upon reinsertion, if it's partially redeemed,
- `_upperPartialRedemptionHint` hints at the `prevId` neighbor of the last redeemed CDP upon reinsertion, if it's partially redeemed,
- `_partialRedemptionHintNICR` ensures that the transaction won't run out of gas if neither `_lowerPartialRedemptionHint` nor `_upperPartialRedemptionHint` are  valid anymore.

`redeemCollateral` will only redeem from CDPs that have an ICR >= MCR. In other words, if there are CDPs at the bottom of the SortedCdps list that are below the minimum collateralization ratio (which can happen after an stETH:BTC price drop), they will be skipped. To make this more gas-efficient, the position of the first redeemable CDP should be passed as `_firstRedemptionHint`.

#### First redemption hint

The first redemption hint is the address of the CDP from which to start the redemption sequence - i.e the address of the first CDP in the system with ICR >= 110%.

If when the transaction is confirmed the address is in fact not valid - the system will start from the lowest ICR CDP in the system, and step upwards until it finds the first CDP with ICR >= 110% to redeem from. In this case, since the number of CDPs below 110% will be limited due to ongoing liquidations, there's a good chance that the redemption transaction still succeed. 

#### Partial redemption hints

All CDPs that are fully redeemed from in a redemption sequence are left with zero debt, and are closed. The remaining collateral (the difference between the orginal collateral and the amount used for the redemption) will be claimable by the owner.

It’s likely that the last CDP in the redemption sequence would be partially redeemed from - i.e. only some of its debt cancelled with eBTC. In this case, it should be reinserted somewhere between top and bottom of the list. The `_lowerPartialRedemptionHint` and `_upperPartialRedemptionHint` hints passed to `redeemCollateral` describe the future neighbors the expected reinsert position.

However, if between the off-chain hint computation and on-chain execution a different transaction changes the state of a CDP that would otherwise be hit by the redemption sequence, then the off-chain hint computation could end up totally inaccurate. This could lead to the whole redemption sequence reverting due to out-of-gas error.

To mitigate this, another hint needs to be provided: `_partialRedemptionHintNICR`, the expected nominal ICR of the final partially-redeemed-from CDP. The on-chain redemption function checks whether, after redemption, the nominal ICR of this CDP would equal the nominal ICR hint.

If not, the redemption sequence doesn’t perform the final partial redemption, and terminates early. This ensures that the transaction doesn’t revert, and most of the requested eBTC redemption can be fulfilled.

#### Example Redemption with hints
```
 // Get the redemptions hints from the deployed HintHelpers contract
  const redemptionhint = await hintHelpers.getRedemptionHints(EBTCAmount, price, 50)

  const { 0: firstRedemptionHint, 1: partialRedemptionNewICR, 2: truncatedEBTCAmount } = redemptionhint

  // Get the approximate partial redemption hint
  const { hintAddress: approxPartialRedemptionHint } = await contracts.hintHelpers.getApproxHint(partialRedemptionNewICR, numTrials, 42)
  
  /* Use the approximate partial redemption hint to get the exact partial redemption hint from the 
  * deployed SortedCdps contract
  */
  const exactPartialRedemptionHint = (await sortedCdps.findInsertPosition(partialRedemptionNewICR,
    approxPartialRedemptionHint,
    approxPartialRedemptionHint))

  /* Finally, perform the on-chain redemption, passing the truncated eBTC amount, the correct hints, and the expected
  * ICR of the final partially redeemed CDP in the sequence. 
  */
  await cdpManager.redeemCollateral(truncatedEBTCAmount,
    firstRedemptionHint,
    exactPartialRedemptionHint[0],
    exactPartialRedemptionHint[1],
    partialRedemptionNewICR,
    0, maxFee,
    { from: redeemer },
  )
```

## Gas compensation

In eBTC, we want to maximize liquidation throughput, and ensure that undercollateralized CDPs are liquidated promptly by “liquidators” at all times, regardless of the degree of collateralization of the CDP.

However, gas costs in Ethereum are substantial. If the gas costs of our public liquidation functions are too high, this may discourage liquidators from calling them, and leave the system holding too many undercollateralized CDPs for too long.

The protocol thus directly compensates liquidators for their gas costs, to incentivize prompt liquidations in both normal and extreme periods of high gas prices. Liquidators should be confident that they will at least break even by making liquidation transactions.

Liquidation incentives are paid in stETH. When a borrower first issues debt, they must provide an additional 0.2 stETH (Gas Stipend) that is reserved as a Liquidation Reserve. A liquidation transaction thus draws stETH from the CDP(s) it liquidates, and sends both the reserved Gas Stipend and the compensation in stETH to the caller, and liquidates the remainder.

When a liquidation transaction liquidates multiple CDPs, each CDP contributes its Gas Stipend and stETH towards the total compensation for the transaction.

Gas compensation per liquidated CDP is given by the formula:

- Full liquidation Gas compensation = `max(1.03, min(ICR, 1.1)) + Gas Stipend`
- Partial liquidation Gas compensation = `max(1.03, min(ICR, 1.1))`

This means that liquidations are always incentivized within the eBTC ecosystem with a percentage of the collateral that can go from 3% to 10%, plus tha gas stipend when the liquidation results in the closing of the CDP. This also applies to CDPs being liquidated during Recovery Mode, the max incentive is capped at 10%. In the same way, CDPs that are liquidated at or below the 103% ICR mark are also subject to a fixed 3% incentive. In these cases, CDPs will remain with a portion of bad dept remaining and no collateral. Then, and only then, this outstanding debt will be subject to [redistribution](#redistributions-and-corrected-stakes).

### Gas compensation schedule

When a borrower opens a CDP, an additional 0.2 stETH are required and the equivalent amount of shares are sent to the `ActivePool` for gas compensation. Their accounting is kept separate from the core system collateral.

When a borrower closes their active CDP, this gas compensation is refunded: the amount of shares sent by the user are transferred back from the ActivePool to the user. Note that these shares may represent a larger amount of stETH than before due to the accrued yield or a smaller amount due to negative rebases.

The purpose of the 0.2 stETH Liquidation Reserve is to provide a minimum level of gas compensation, regardless of the CDP's collateral size or the current stETH market price.

### Liquidation

When a CDP is liquidated, all of the collateral is transferred to the liquidator. Therefore, the compensation incentive percentage will depend on the ICR at which the ICR is liquidated according to the equations [above](#gas-compensation). For example, a liquidation at 110% ICR will mean a 10% profit for the liquidator plus the Gas Stipend. 

As mentioned as well, if liquidated below 103%, the liquidator is guaranteed a 3% incentive. For intance, if the liquidation occurs at 97% ICR, the system will estimate the debt to be repaid based equivalent to that required to yield a 103% ICR. Therefore, the liquidator will be required to pay a debt amount 3% lower in value than the total available collateral and profit from that difference. Undercollateralized liquidations are also incentivized with the Gas Stipend.

### Gas compensation and redemptions

If the redemption causes a CDP's full debt to be cancelled, the CDP is then closed: Gas Stipend from the Liquidation Reserve becomes avaiable for the borrower to reclaim along of the CDP's Collateral Surplus.

## eBTC Redemption Fees

eBTC generates fee revenue from redemptions. Fees are captured by the feeRecipient contract. Redemptions fees are paid in stETH.

### Redemption Fee

The redemption fee is taken as a cut of the total stETH drawn from the system in a redemption. It is based on the current redemption rate.

In the `CdpManager`, `redeemCollateral` calculates the stETH fee and it is allocated to the `FeeRecipient` address in the `ActivePool`.

### Fee Schedule

Redemption fees are based on the `baseRate` state variable in CdpManager, which is dynamically updated. The `baseRate` increases with each redemption, and decays according to time passed since the last fee event - i.e. the last redemption of eBTC.

The current fee schedule:

Upon each redemption:
- `baseRate` is decayed based on time passed since the last fee event
- `baseRate` is incremented by an amount proportional to the fraction of the total eBTC supply that was redeemed
- The redemption rate is given by `min{REDEMPTION_FEE_FLOOR + baseRate * ETHdrawn, DECIMAL_PRECISION}`

`REDEMPTION_FEE_FLOOR` is set to 1%, while `DECIMAL_PRECISION` is 100%.

### Intuition behind fees

The larger the redemption volume, the greater the fee percentage.

The longer the time delay since the last operation, the more the `baseRate` decreases.

The intent is to throttle large redemptions with higher fees. The `baseRate` decay over time ensures that the fee for redeemers will “cool down”, while redemptions volumes are low.

Furthermore, the fees cannot become smaller than 1% (Oracle's maximum deviation threshold), which in the case of redemptions protects the redemption facility from being front-run by arbitrageurs that are faster than the price feed.

### Fee decay Implementation

Time is measured in units of minutes. The `baseRate` decay is based on `block.timestamp - lastFeeOpTime`. If less than a minute has passed since the last fee event, then `lastFeeOpTime` is not updated. This prevents “base rate griefing”: i.e. it prevents an attacker stopping the `baseRate` from decaying by making a series of redemptions or issuing eBTC with time intervals of < 1 minute.

The decay parameter is tuned such that the fee changes by a factor of 0.99 per hour, i.e. it loses 1% of its current value per hour. At that rate, after one week, the baseRate decays to 18% of its prior value. The exact decay parameter is subject to change, and will be fine-tuned via economic modelling.

## Redistributions and Corrected Stakes
When a liquidation occurs on an undercollateralized Cdp and bad debt remains after paying out the premium, the redistribution mechanism should distribute the remaining collateral and debt of the liquidated CDP, to all active CDPs in the system, in proportion to their collateral.

For two CDPs A and B with collateral `A.coll > B.coll`, CDP A should earn a bigger share of the liquidated collateral and debt.

However, when it comes to implementation, Ethereum gas costs make it too expensive to loop over all CDPs and write new data to storage for each one. When a CDP receives redistributed debt, the system does not update the CDP's debt value - instead, the debt remains "pending" until the borrower's next operation (or more accurately, next operation directly modifying that CDP).

These “pending debt redistributions" can not be accounted for in future calculations in a scalable way.

However: the ICR of a CDP is always calculated as the ratio of its total collateral to its total debt. So, a Cdp’s ICR calculation **does** include all its previous accumulated rewards.

**This causes a problem: redistributions proportional to initial collateral can break CDP ordering.**

Consider the case where new CDP is created after all active CDPs have received a redistribution from a liquidation. This “fresh” CDP has then experienced fewer rewards than the older CDPs, and thus, it receives a disproportionate share of subsequent rewards, relative to its total collateral.

The fresh CDP would earns rewards based on its **entire** collateral, whereas old CDPs would earn rewards based only on **some portion** of their collateral - since a part of their collateral is pending, and not included in the Cdp’s `coll` property.

This can break the ordering of CDPs by ICR - see the [proofs section](https://github.com/liquity/dev/tree/main/papers).

### Corrected Stake Solution

We use a corrected stake to account for this discrepancy, and ensure that newer CDPs earn the same liquidation rewards per unit of total collateral, as do older CDPs with pending changes. Thus the corrected stake ensures the sorted list remains ordered by ICR, as liquidation events occur over time.

When a CDP is opened, its stake is calculated based on its collateral, and snapshots of the entire system collateral and debt which were taken immediately after the last liquidation.

A Cdp’s stake is given by:

```
stake = _coll.mul(totalStakesSnapshot).div(totalCollateralSnapshot)
```

It then earns redistribution rewards based on this corrected stake. A newly opened Cdp’s stake will be less than its raw collateral, if the system contains active CDPs with pending redistribution rewards when it was made.

Whenever a borrower adjusts their Cdp’s collateral, their pending rewards are applied, and a fresh corrected stake is computed.

To convince yourself this corrected stake preserves ordering of active CDPs by ICR, please see the [proofs section](https://github.com/liquity/dev/blob/main/papers).

## Math Proofs

The eBTC implementation relies on some important system properties and mathematical derivations from Liquity's initial design.

In particular, we have:

- Proofs that CDP ordering is maintained throughout a series of liquidations and new CDP openings
- A derivation of a formula and implementation for a highly scalable (O(1) complexity) reward distribution in the Stability Pool, involving compounding and decreasing stakes.

PDFs of these can be found in https://github.com/liquity/dev/blob/main/papers

## Definitions

_**CDP:**_ a collateralized debt position, bound to a single Ethereum address. Also referred to as a “CDP” in similar protocols.

_**eBTC**_:  The soft-pegged asset that may be issued from a user's collateralized debt position and freely transferred/traded to any Ethereum address. Intended to maintain parity with BTC, and can always be redeemed directly with the system: 1 eBTC is always exchangeable for 1 BTC worth of stETH, minus fees.

_**Active CDP:**_ an Ethereum address owns an “active Cdp” if there is a node in the `SortedCdps` list with ID equal to the address, and non-zero collateral is recorded on the CDP struct for that address.

_**Closed CDP:**_ a CDP that was once active, but now has zero debt and zero collateral recorded on its struct, and there is no node in the `SortedCdps` list with ID equal to the owning address.

_**Cached collateral:**_ the amount of stETH collateral recorded on a Cdp’s struct

_**Cached debt:**_ the amount of eBTC debt recorded on a Cdp’s struct

_**Synced collateral:**_ the sum of a Cdp’s active collateral plus its pending collateral rewards accumulated from postive stETH rebases

_**Sycned debt:**_ the sum of a Cdp’s active debt plus its pending debt accumulated from distributions

_**Individual collateralization ratio (ICR):**_ a CDP's ICR is the ratio of the dollar value of its entire collateral at the current stETH:BTC price, to its entire debt

_**Nominal collateralization ratio (nominal ICR, NICR):**_ a CDP's nominal ICR is its entire collateral (in stETH) multiplied by 100e18 and divided by its entire debt.

_**System collateral:**_ the sum of active collateral over all CDPs. Equal to the stETH in the ActivePool allocated to the system from internal accounting values.

_**System debt:**_ the sum of active debt over all CDPs. Equal to the eBTC in the ActivePool.

_**Total collateralization ratio (TCR):**_ the ratio of the dollar value of the entire system collateral at the current stETH:BTC price, to the entire system debt

_**Critical collateralization ratio (CCR):**_ 125%. When the TCR is below the CCR, the system enters Recovery Mode.

_**Borrower:**_ an externally owned account or contract that locks collateral in a CDP and issues eBTC tokens to their own address. They “borrow” eBTC tokens against their stETH collateral.

_**Redemption:**_ the act of swapping eBTC tokens with the system, in return for an equivalent value of stETH. Any account with a eBTC token balance may redeem them, whether or not they are a borrower.

When eBTC is redeemed for stETH, the stETH is always withdrawn from the lowest collateral CDPs, in ascending order of their collateralization ratio. A redeemer can not selectively target CDPs with which to swap eBTC for stETH.

_**Liquidation:**_ the act of force-closing a CDP that is considered undercollateralized in the current system mode, and distributing its collateral and debt.

Liquidation functionality is permissionless and publically available - anyone may liquidate an undercollateralized CDP, or batch liquidate CDPs in ascending order of collateralization ratio.

_**Gas stipend:**_ A fixed value, in stETH, automatically paid to the caller of a liquidation function that fully liquidates a CDP. Intended to at least cover the gas cost of the transaction. Designed to ensure that liquidators are not dissuaded by potentially high gas costs.

### Clone & Install

```
git clone https://github.com/Badger-Finance/ebtc.git ebtc
cd ebtc
yarn
```

### Top-level scripts

There are a number of scripts in the top-level package.json file to ease development, which you can run with yarn.

#### Run tests

Hardhat test suite
```
yarn test
```

Foundry test suite
```
forge test
```

## Known Issues (Liquity)
> 🦉 These issues are lightly modified from the text of the Liquity readme, and may no longer be relevant or may behave differently within the context of eBTC.

### Temporary and slightly inaccurate TCR calculation within `batchLiquidateCdps` in Recovery Mode. 

When liquidating a CDP with `ICR > 110%`, a collateral surplus remains claimable by the borrower. This collateral surplus should be excluded from subsequent TCR calculations, but within the liquidation sequence in `batchLiquidateCdps` in Recovery Mode, it is not. This results in a slight distortion to the TCR value used at each step of the liquidation sequence going forward. This distortion only persists for the duration the `batchLiquidateCdps` function call, and the TCR is again calculated correctly after the liquidation sequence ends. In most cases there is no impact at all, and when there is, the effect tends to be minor. The issue is not present at all in Normal Mode. 

There is a theoretical and extremely rare case where it incorrectly causes a loss for Stability Depositors instead of a gain. It relies on the stars aligning: the system must be in Recovery Mode, the TCR must be very close to the 125% boundary, a large CDP must be liquidated, and the stETH price must drop by >10% at exactly the right moment. No profitable exploit is possible. For more details, please see [this security advisory](https://github.com/liquity/dev/security/advisories/GHSA-xh2p-7p87-fhgh).

### SortedCdps edge cases - top and bottom of the sorted list

When the CDP is at one end of the `SortedCdps` list and adjusted such that its ICR moves further away from its neighbor, `findInsertPosition` returns unhelpful positional hints, which if used can cause the `adjustCdp` transaction to run out of gas. This is due to the fact that one of the returned addresses is in fact the address of the CDP to move - however, at re-insertion, it has already been removed from the list. As such the insertion logic defaults to `0x0` for that hint address, causing the system to search for the CDP starting at the opposite end of the list. A workaround is possible, and this has been corrected in the SDK used by front ends.

### Front-running issues

#### Loss evasion by front-running Stability Pool depositors

*Example sequence 1): evade liquidation tx*
- Depositor sees incoming liquidation tx that would cause them a net loss
- Depositor front-runs with `withdrawFromSP()` to evade the loss

*Example sequence 2): evade price drop*
- Depositor sees incoming price drop tx (or just anticipates one, by reading exchange price data), that would shortly be followed by unprofitable liquidation txs
- Depositor front-runs with `withdrawFromSP()` to evade the loss

Stability Pool depositors expect to make profits from liquidations which are likely to happen at a collateral ratio slightly below 110%, but well above 100%. In rare cases (flash crashes, oracle failures), CDPs may be liquidated below 100% though, resulting in a net loss for stability depositors. Depositors thus have an incentive to withdraw their deposits if they anticipate liquidations below 100% (note that the exact threshold of such “unprofitable” liquidations will depend on the current Dollar price of eBTC).

As long the difference between two price feed updates is <10% and price stability is maintained, loss evasion situations should be rare. The percentage changes between two consecutive prices reported by Chainlink’s stETH:BTC oracle has only ever come close to 10% a handful of times in the past few years.

In the current implementation, deposit withdrawals are prohibited if and while there are CDPs with a collateral ratio (ICR) < 110% in the system. This prevents loss evasion by front-running the liquidate transaction as long as there are CDPs that are liquidatable in normal mode.

This solution is only partially effective since it does not prevent stability depositors from monitoring the stETH price feed and front-running oracle price update transactions that would make CDPs liquidatable. Given that we expect loss-evasion opportunities to be very rare, we do not expect that a significant fraction of stability depositors would actually apply front-running strategies, which require sophistication and automation. In the unlikely event that large fraction of the depositors withdraw shortly before the liquidation of CDPs at <100% CR, the redistribution mechanism will still be able to absorb defaults.


#### Reaping liquidation gains on the fly

*Example sequence:*
- User sees incoming profitable liquidation tx
- User front-runs it and immediately makes a deposit with `provideToSP()`
- User earns a profit

Front-runners could deposit funds to the Stability Pool on the fly (instead of keeping their funds in the pool) and make liquidation gains when they see a pending price update or liquidate transaction. They could even borrow the eBTC using a CDP as a flash loan.

Such flash deposit-liquidations would actually be beneficial (in terms of TCR) to system health and prevent redistributions, since the pool can be filled on the spot to liquidate CDPs anytime, if only for the length of 1 transaction.


#### Front-running and changing the order of CDPs as a DoS attack

*Example sequence:**
-Attacker sees incoming operation(`openLoan()`, `redeemCollateral()`, etc) that would insert a CDP to the sorted list
-Attacker front-runs with mass openLoan txs
-Incoming operation becomes more costly - more traversals needed for insertion

It’s theoretically possible to increase the number of the CDPs that need to be traversed on-chain. That is, an attacker that sees a pending borrower transaction (or redemption or liquidation transaction) could try to increase the number of traversed CDPs by introducing additional CDPs on the way. However, the number of CDPs that an attacker can inject before the pending transaction gets mined is limited by the amount of spendable gas. Also, the total costs of making the path longer by 1 are significantly higher (gas costs of opening a CDP, plus the 0.5% borrowing fee) than the costs of one extra traversal step (simply reading from storage). The attacker also needs significant capital on-hand, since the minimum debt for a CDP is 2000 eBTC.

In case of a redemption, the “last” CDP affected by the transaction may end up being only partially redeemed from, which means that its ICR will change so that it needs to be reinserted at a different place in the sorted CDP list (note that this is not the case for partial liquidations in recovery mode, which preserve the ICR). A special ICR hint therefore needs to be provided by the transaction sender for that matter, which may become incorrect if another transaction changes the order before the redemption is processed. The protocol gracefully handles this by terminating the redemption sequence at the last fully redeemed CDP (see [here](https://github.com/liquity/dev#hints-for-redeemcollateral)).

An attacker trying to DoS redemptions could be bypassed by redeeming an amount that exactly corresponds to the debt of the affected CDP(s).

Finally, this DoS could be avoided if the initial transaction avoids the public gas auction entirely and is sent direct-to-miner, via (for example) Flashbots.

## Periphery

### Leverage Macro

Leverage Macro is divided into multiple contracts:
- LeverageMacroBase
  The base reference contract, that allows to perform an Open, Close or Adjust of a CDP as a callback of a flashloan

- LeverageMacroDelegatTarget
  The variant of the Leverage Macro that is meant to be used as a delegatecall target

- LeverageMacroReference
  The smart contract version that can be deployed as a contract / proxy which will open a CDP via FLashloan on behalf of it's owner

### SimplifiedDiamondLike
A reference implementation of a smart contract wallet that uses configurable callbacks to use leverage macro natively, rather than as a separate support contract.
Demonstrates how this can also be achieved by other SC wallets with configurable callbacks such as Gnosis Safe.

A mix of a DSProxy and a Diamond
-> `execute` is heavily inspired by Gnosis Safe
-> `_fallback` is basically a diamon proxy with the extra check for callback being enabled

Allows arbitrary call execution by it's owner, both via call and delegate call
-> Arbitrary calls can be performed via `execute`
-> This can be further extended by setting up `callbackHandler`s

Adds a check to allow callbacks or allow any call to be handled by it's fallback
-> Non callback must be explicitly allowed via `setAllowAnyCall` which ensures that the owner of the proxy is explicitly taking on the extra risks

Allows to specify a different implementation for each function selector
-> Thanks to `callbackHandler` any function sig (beside ones clashing with the basic ones), can be added to the proxy, instead of having a proxy by proxy upgrade pattern


