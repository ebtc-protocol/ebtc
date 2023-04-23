# eBTC
| Tests                                                                                                                                                                                   | Coverage                                                                                                                                        |
|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------|
| [![Test contracts](https://github.com/Badger-Finance/ebtc/actions/workflows/test-contracts.yml/badge.svg)](https://github.com/Badger-Finance/ebtc/actions/workflows/test-contracts.yml) | [![codecov](https://codecov.io/gh/Badger-Finance/ebtc/branch/main/graph/badge.svg?token=JZ8V8KI5D6)](https://codecov.io/gh/Badger-Finance/ebtc) |

eBTC is a collateralized crypto asset soft pegged to the price of Bitcoin and built on the Ethereum network. It is backed exclusively by Staked Ether (stTEH) and powered by immutable smart contracts with no counterparty reliance. It’s designed to be the most decentralized synthetic BTC in DeFi and offers the ability for anyone in the world to borrow BTC at no cost.

After locking up stETH as collateral in a smart contract and creating an individual position called a "CDP", the user can get instant liquidity by minting eBTC. Each CDP is required to be collateralized at a fixed minimum ratio determined by the protocol.

The redemption and liquidation mechanisms help ensure stability is maintained via economically-driven user interactions and arbitrage, rather than by active governance or monetary interventions.

## eBTC Audit - What's in scope
`/packages/contracts/contracts` (all files in the base directory)

Most of the `/Dependency` files are copy-pastes, but some are custom:
`/packages/contracts/contracts/Dependencies/LiquityBase.sol`
`/packages/contracts/contracts/Dependencies/AuthNoOwner.sol`

`/packages/contracts/contracts/LQTY/feeRecipient`

## Other Notes
- We anticipate liquidators and redemption arbers to use Curve and Balancer pools for on-chain liquidty, and anticipate potential economic attacks.   

## More information

- [Introducing eBTC - A Decentralized Bitcoin Powered by Ethereum Staking](https://forum.badger.finance/t/introducing-ebtc-a-decentralized-bitcoin-powered-by-ethereum-staking/5952)
- [eBTC - Builder Update #1](https://forum.badger.finance/t/ebtc-builder-update-1/5975)

## eBTC System Summary
- [Disclaimer](#disclaimer)
- [eBTC Overview](#ebtc-overview)
- [Liquidations](#liquidations)
  - [Liquidation gas costs](#liquidation-gas-costs)
- [eBTC Token Redemption](#ebtc-token-redemption)
  - [Partial redemption](#partial-redemption)
  - [Full redemption](#full-redemption)
  - [Redemptions create a price floor](#redemptions-create-a-price-floor)
- [Recovery Mode](#recovery-mode)
- [Project Structure](#project-structure)
  - [Directories](#directories)
  - [Branches](#branches)
- [Core System Architecture](#core-system-architecture)
  - [Core Smart Contracts](#core-smart-contracts)
  - [Data and Value Silo Contracts](#data-and-value-silo-contracts)
  - [Contract Interfaces](#contract-interfaces)
  - [PriceFeed and Oracle](#pricefeed-and-oracle)
  - [PriceFeed Logic](#pricefeed-logic)
  - [Testnet PriceFeed and PriceFeed tests](#testnet-pricefeed-and-pricefeed-tests)
  - [PriceFeed limitations and known issues](#pricefeed-limitations-and-known-issues)
  - [Keeping a sorted list of Cdps ordered by ICR](#keeping-a-sorted-list-of-cdps-ordered-by-icr)
  - [Flow of Ether in eBTC](#flow-of-stETH-in-ebtc)
  - [Flow of eBTC tokens in eBTC](#flow-of-ebtc-tokens-in-ebtc)
  - [Flow of LQTY Tokens in eBTC](#flow-of-lqty-tokens-in-ebtc)
- [Expected User Behaviors](#expected-user-behaviors)
- [Contract Ownership and Function Permissions](#contract-ownership-and-function-permissions)
- [Deployment to a Development Blockchain](#deployment-to-a-development-blockchain)
- [Running Tests](#running-tests)
  - [Brownie Tests](#brownie-tests)
  - [OpenEthereum](#openethereum)
  - [Coverage](#coverage)
- [System Quantities - Units and Representation](#system-quantities---units-and-representation)
  - [Integer representations of decimals](#integer-representations-of-decimals)
- [Public Data](#public-data)
- [Public User-Facing Functions](#public-user-facing-functions)
  - [Borrower (Cdp) Operations - `BorrowerOperations.sol`](#borrower-cdp-operations---borroweroperationssol)
  - [CdpManager Functions - `CdpManager.sol`](#cdpmanager-functions---cdpmanagersol)
  - [Hint Helper Functions - `HintHelpers.sol`](#hint-helper-functions---hinthelperssol)
  - [Stability Pool Functions - `StabilityPool.sol`](#stability-pool-functions---stabilitypoolsol)
  - [LQTY Staking Functions  `FeeRecipient.sol`](#lqty-staking-functions--lqtystakingsol)
  - [Lockup Contract Factory `LockupContractFactory.sol`](#lockup-contract-factory-lockupcontractfactorysol)
  - [Lockup contract - `LockupContract.sol`](#lockup-contract---lockupcontractsol)
  - [eBTC token `EBTCToken.sol` and LQTY token `LQTYToken.sol`](#ebtc-token-ebtctokensol-and-lqty-token-lqtytokensol)
- [Supplying Hints to Cdp operations](#supplying-hints-to-cdp-operations)
  - [Hints for `redeemCollateral`](#hints-for-redeemcollateral)
    - [First redemption hint](#first-redemption-hint)
    - [Partial redemption hints](#partial-redemption-hints)
- [Gas compensation](#gas-compensation)
  - [Gas compensation schedule](#gas-compensation-schedule)
  - [Liquidation](#liquidation)
  - [Gas compensation and redemptions](#gas-compensation-and-redemptions)
  - [Gas compensation helper functions](#gas-compensation-helper-functions)
- [eBTC System Fees](#ebtc-system-fees)
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
- [Disclaimer](#disclaimer)

## eBTC Overview
eBTC is a collateralized debt platform. Users can lock up Staked Ether, and are issued soft-pegged BTC tokens (eBTC) to their own Ethereum address, and subsequently transfer those tokens to any other Ethereum address. The individual collateralized debt positions are called Cdps.

The BTC tokens are economically geared towards maintaining value of 1 eBTC = 1 BTC, due to the following properties:

1. The system is designed to always be over-collateralized - the dollar value of the locked Ether exceeds the dollar value of the issued BTC

2. eBTC token are fully redeemable - users can always swap $x worth of eBTC for $x worth of stETH (minus fees), directly with the system.

After opening a Cdp with some stETH, users may issue ("borrow") tokens such that the collateralization ratio of their Cdp remains above 110%. A user with $1000 worth of stETH in a Cdp can issue up to $909.09 worth of eBTC.

The tokens are freely exchangeable - anyone with an Ethereum address can send or receive eBTC tokens, whether they have an open Cdp or not. The tokens are burned upon repayment of a Cdp's debt.

The eBTC system regularly updates the stETH:BTC price via a decentralized data feed. When a Cdp falls below a minimum collateralization ratio (MCR) of 110%, it is considered under-collateralized, and is vulnerable to liquidation.

## Liquidations

eBTC utilizes an open and intentivized liqudiation system. Any user can liquidate an under-collateralized CDP. Then will recieve a fixed "gas compensation" fee as well as up to a 3% liquidation bonus on the collateral recieved. See [this](https://hackmd.io/@re73/r19oq9LM2) for details.

Anyone may call the public `liquidateCdps()` function, which will check for under-collateralized Cdps, and liquidate them. Alternatively they can call `batchLiquidateCdps()` with a custom list of cdp addresses to attempt to liquidate.

### Liquidation gas costs

Currently, mass liquidations performed via the above functions cost 60-65k gas per cdp. Thus the system can liquidate up to a maximum of 95-105 cdps in a single transaction.

## eBTC Token Redemption

Any eBTC holder (whether or not they have an active Cdp) may redeem their eBTC directly with the system. Their eBTC is exchanged for stETH, at face value: redeeming x eBTC tokens returns \$x worth of stETH (minus a [redemption fee](#redemption-fee)).

When eBTC is redeemed for stETH, the system cancels the eBTC with debt from Cdps, and the stETH is drawn from their collateral.

In order to fulfill the redemption request, Cdps are redeemed from in ascending order of their collateralization ratio.

A redemption sequence of `n` steps will **fully** redeem from up to `n-1` Cdps, and, and **partially** redeems from up to 1 Cdp, which is always the last Cdp in the redemption sequence.

Redemptions are blocked when TCR < 110% (there is no need to restrict ICR < TCR). At that TCR redemptions would likely be unprofitable, as eBTC is probably trading above $1 if the system has crashed that badly, but it could be a way for an attacker with a lot of eBTC to lower the TCR even further.

Note that redemptions are disabled during the first 14 days of operation since deployment of the eBTC protocol to protect the monetary system in its infancy.

### Partial redemption

Most redemption transactions will include a partial redemption, since the amount redeemed is unlikely to perfectly match the total debt of a series of Cdps.

The partially redeemed Cdp is re-inserted into the sorted list of Cdps, and remains active, with reduced collateral and debt.

### Full redemption

If we assume the fixed liquidation incentive is 200 units, A Cdp is defined as “fully redeemed from” when the redemption has caused its debt to absorb (debt-200) eBTC. Then, its 200 eBTC Liquidation Reserve is cancelled with its remaining 200 debt: the Liquidation Reserve is burned from the gas address, and the 200 debt is zero’d.

Before closing, we must handle the Cdp’s **collateral surplus**: that is, the excess stETH collateral remaining after redemption, due to its initial over-collateralization.

This collateral surplus is sent to the `CollSurplusPool`, and the borrower can reclaim it later. The Cdp is then fully closed.

### Redemptions create a price floor

Economically, the redemption mechanism creates a hard price floor for eBTC, ensuring that the market price stays at or near to 1 Bitcoin. 

## Recovery Mode

Recovery Mode kicks in when the total collateralization ratio (TCR) of the system falls below 150%.

During Recovery Mode, liquidation conditions are relaxed, and the system blocks borrower transactions that would further decrease the TCR. New eBTC may only be issued by adjusting existing Cdps in a way that improves their ICR, or by opening a new Cdp with an ICR of >=150%. In general, if an existing Cdp's adjustment reduces its ICR, the transaction is only executed if the resulting TCR is above 150%

Recovery Mode is structured to incentivize borrowers to behave in ways that promptly raise the TCR back above 150%.

Economically, Recovery Mode is designed to encourage collateral top-ups and debt repayments, and also itself acts as a self-negating deterrent: the possibility of it occurring actually guides the system away from ever reaching it.

## Project Structure

### Directories
- `papers` - Whitepaper and math papers inhereited from Liquity: a proof of eBTC's cdp order invariant, and a derivation of the scalable Stability Pool staking formula
- `packages/contracts/` - The backend development folder, contains the Hardhat and Foundry projects, contracts, and tests
- `packages/contracts/contracts/` - The core back end smart contracts written in Solidity
- `packages/contracts/test/` - JS test suite for the system. Tests run in Mocha/Chai
- `packages/contracts/foundry_test/` - Foundry test suite for the system
- `packages/contracts/tests/` - Python test suite for the system. Tests run in Brownie
- `packages/contracts/gasTest/` - Non-assertive tests that return gas costs for eBTC operations under various scenarios
- `packages/contracts/fuzzTests/` - Echidna tests, and naive "random operation" tests 
- `packages/contracts/migrations/` - contains Hardhat script for deploying the smart contracts to the blockchain
- `packages/contracts/utils/` - external Hardhat and node scripts - deployment helpers, gas calculators, etc

Backend development is done in the Hardhat framework, and allows eBTC to be deployed on the Hardhat EVM network for fast compilation and test execution.

## External Contract Architecture
Fees generated through the core protocol are managed at an external FeeRecipient contract. This contract is fully managed by BadgerDAO but with the option to switch it out for a new mechanic.

`FeeRecipient.sol` - All fees generated by the core system are recieved at this address, with events emitted when a fee is processed for acounting purposes. These fees include redemptions and the staking yield split.

## Core System Architecture

The core eBTC system consists of several smart contracts, which are deployable to the Ethereum blockchain.

All application logic and data is contained in these contracts - there is no need for a separate database or back end logic running on a web server. In effect, the Ethereum network is itself the eBTC back end. As such, all balances and contract data are public.

The system has no admin key or human governance. Once deployed, it is fully automated, decentralized and no user holds any special privileges in or control over the system.

The two main contracts - `BorrowerOperations.sol` and `CdpManager.sol` - hold the user-facing public functions, and contain most of the internal system logic. Together they control Cdp state updates and movements of stETH and eBTC tokens around the system.

### Core Smart Contracts

`BorrowerOperations.sol` - contains the basic operations by which borrowers interact with their Cdp: Cdp creation, stETH top-up / withdrawal, eBTC issuance and repayment. BorrowerOperations functions call in to CdpManager, telling it to update Cdp state, where necessary. BorrowerOperations functions also call in to the various Pools, telling them to move stETH/eBTC between Pools or between Pool <> user, where necessary.

`CdpManager.sol` - contains functionality for liquidations and redemptions. It sends redemption fees to the `FeeRecipient` contract. Also contains the state of each Cdp - i.e. a record of the Cdp’s collateral and debt. CdpManager does not hold value (i.e. Ether / other tokens). CdpManager functions call in to the various Pools to tell them to move Ether/tokens between Pools, where necessary.

`LiquityBase.sol` - Both CdpManager and BorrowerOperations inherit from the parent contract LiquityBase, which contains global constants and some common functions.

`EBTCToken.sol` - the eBTC token contract, which implements the ERC20 fungible token standard in conjunction with EIP-2612 and a mechanism that blocks (accidental) transfers to contracts and addresses like address(0) that are not supposed to receive funds through direct transfers. The contract mints, burns and transfers eBTC tokens.

`SortedCdps.sol` - a doubly linked list that stores addresses of Cdp owners, sorted by their individual collateralization ratio (ICR). It inserts and re-inserts Cdps at the correct position, based on their ICR.

`PriceFeed.sol` - Contains functionality for obtaining the current stETH:BTC price, which the system uses for calculating collateralization ratios.

`HintHelpers.sol` - Helper contract, containing the read-only functionality for calculation of accurate hints to be supplied to borrower operations and redemptions.

### Data and Value Silo Contracts
These contracts hold stETH and/or eBTC for their respective parts of the system, and contain minimal logic:

`ActivePool.sol` - holds the total stETH balance and records the total eBTC debt of the active Cdps.

`DefaultPool.sol` - holds the total stETH balance and records the total eBTC debt of the liquidated Cdps that are pending redistribution to active Cdps. If a Cdp has pending stETH/debt “rewards” in the DefaultPool, then they will be applied to the Cdp when it next undergoes a borrower operation, a redemption, or a liquidation.

`CollSurplusPool.sol` - holds the stETH surplus from Cdps that have been fully redeemed from as well as from Cdps with an ICR > MCR that were liquidated in Recovery Mode. Sends the surplus back to the owning borrower, when told to do so by `BorrowerOperations.sol`.

`GasPool.sol` - holds the total eBTC liquidation reserves. eBTC is moved into the `GasPool` when a Cdp is opened, and moved out when a Cdp is liquidated or closed.

### Contract Interfaces

`ICdpManager.sol`, `IPool.sol` etc. These provide specification for a contract’s functions, without implementation. They are similar to interfaces in Java or C#.

### PriceFeed and Oracle

eBTC functions that require the most current stETH:BTC price data fetch the price dynamically, as needed, via the core `PriceFeed.sol` contract using the Chainlink stETH:BTC reference contract as its primary and Tellor's stETH:BTC price feed as its secondary (fallback) data source. PriceFeed is stateful, i.e. it records the last good price that may come from either of the two sources based on the contract's current state.

The fallback logic distinguishes 3 different failure modes for Chainlink and 2 failure modes for Tellor:

- `Frozen` (for both oracles): last price update more than 4 hours ago
- `Broken` (for both oracles): response call reverted, invalid timeStamp that is either 0 or in the future, or reported price is non-positive (Chainlink) or zero (Tellor). Chainlink is considered broken if either the response for the latest round _or_ the response for the round before the latest fails one of these conditions.
- `PriceChangeAboveMax` (Chainlink only): higher than 50% deviation between two consecutive price updates

There is also a return condition `bothOraclesLiveAndUnbrokenAndSimilarPrice` which is a function returning true if both oracles are live and not broken, and the percentual difference between the two reported prices is below 5%.

The current `PriceFeed.sol` contract has an external `fetchPrice()` function that is called by core eBTC functions which require a current stETH:BTC price.  `fetchPrice()` calls each oracle's proxy, asserts on the responses, and converts returned prices to 18 digits.

### PriceFeed Logic

The PriceFeed contract fetches the current price and previous price from Chainlink and changes its state (called `Status`) based on certain conditions.

**Initial PriceFeed state:** `chainlinkWorking`. The initial system state that is maintained as long as Chainlink is working properly, i.e. neither broken nor frozen nor exceeding the maximum price change threshold between two consecutive rounds. PriceFeed then obeys the logic found in this table:

  https://docs.google.com/spreadsheets/d/18fdtTUoqgmsK3Mb6LBO-6na0oK-Y9LWBqnPCJRp5Hsg/edit?usp=sharing


### Testnet PriceFeed and PriceFeed tests

The `PriceFeedTestnet.sol` is a mock PriceFeed for testnet and general back end testing purposes, with no oracle connection. It contains a manual price setter, `setPrice()`, and a getter, `getPrice()`, which returns the latest stored price.

The mainnet PriceFeed is tested in `test/PriceFeedTest.js`, using a mock Chainlink aggregator and a mock TellorMaster contract.

### PriceFeed limitations and known issues

The purpose of the PriceFeed is to be at least as good as an immutable PriceFeed that relies purely on Chainlink, while also having some resilience in case of Chainlink failure / timeout, and chance of recovery.

The PriceFeed logic consists of automatic on-chain decision-making for obtaining fallback price data from Tellor, and if possible, for returning to Chainlink if/when it recovers.

The PriceFeed logic is complex, and although we would prefer simplicity, it does allow the system a chance of switching to an accurate price source in case of a Chainlink failure or timeout, and also the possibility of returning to an honest Chainlink price after it has failed and recovered.

We believe the benefit of the fallback logic is worth the complexity. Ff we had no fallback logic and Chainlink were to be hacked or permanently fail, eBTC would become unusable without a backup.

Governance is also capable of setting a new backup oracle feed, as long as it conforms to the tellor interface.

**Chainlink Decimals**: the `PriceFeed` checks for and uses the latest `decimals` value reported by the Chainlink aggregator in order to calculate the Chainlink price at 18-digit precision, as needed by eBTC.  `PriceFeed` does not assume a value for decimals and can handle the case where Chainlink change their decimal value. 

However, the check `chainlinkIsBroken` uses both the current response from the latest round and the response previous round. Since `decimals` is not attached to round data, eBTC has no way of knowing whether decimals has changed between the current round and the previous round, so we assume it is the same. eBTC assumes the current return value of decimals() applies to both current round `i` and previous round `i-1`. 

This means that a decimal change that coincides with a eBTC price fetch could cause eBTC to assert that the Chainlink price has deviated too much, and fall back to Tellor. There is nothing we can do about this. We hope/expect Chainlink to never change their `decimals()` return value (currently 8), and if a hack/technical error causes Chainlink's decimals to change, eBTC may fall back to Tellor.

To summarize the Chainlink decimals issue: 
- eBTC can handle the case where Chainlink decimals changes across _two consecutive rounds `i` and `i-1` which are not used in the same eBTC price fetch_
- If eBTC fetches the price at round `i`, it will not know if Chainlink decimals changed across round `i-1` to round `i`, and the consequent price scaling distortion may cause eBTC to fall back to Tellor
- eBTC will always calculate the correct current price at 18-digit precision assuming the current return value of `decimals()` is correct (i.e. is the value used by the nodes).

### Keeping a sorted list of Cdps ordered by ICR

eBTC relies on a particular data structure: a sorted doubly-linked list of Cdps that remains ordered by individual collateralization ratio (ICR), i.e. the amount of collateral (in USD) divided by the amount of debt (in eBTC).

This ordered list is critical for gas-efficient redemption sequences and for the `liquidateCdps` sequence, both of which target Cdps in ascending order of ICR.

The sorted doubly-linked list is found in `SortedCdps.sol`. 

Nodes map to active Cdps in the system - the ID property is the address of a cdp owner. The list accepts positional hints for efficient O(1) insertion - please see the [hints](#supplying-hints-to-cdp-operations) section for more details.

ICRs are computed dynamically at runtime, and not stored on the node. This is because ICRs of active Cdps change dynamically, when:

- The stETH:BTC price varies, altering the value of the collateral of every Cdp
- A liquidation that redistributes collateral and debt to active Cdps occurs

The list relies on the fact that a collateral and debt redistribution due to a liquidation preserves the ordering of all active Cdps (though it does decrease the ICR of each active Cdp above the MCR).

The fact that ordering is maintained as redistributions occur, is not immediately obvious: please see the [mathematical proof](https://github.com/liquity/dev/blob/main/papers) which shows that this holds in eBTC.

A node inserted based on current ICR will maintain the correct position, relative to its peers, as liquidation gains accumulate, as long as its raw collateral and debt have not changed.

Nodes also remain sorted as the stETH:BTC price varies, since price fluctuations change the collateral value of each Cdp by the same proportion.

Thus, nodes need only be re-inserted to the sorted list upon a Cdp operation - when the owner adds or removes collateral or debt to their position.

### Flow of stETH in eBTC

![Flow of stETH](images/ETH_flows.svg)

stETH in the system lives in three Pools: the ActivePool, the DefaultPool and the StabilityPool. When an operation is made, stETH is transferred in one of three ways:

- From a user to a Pool
- From a Pool to a user
- From one Pool to another Pool

stETH is recorded on an _individual_ level, but stored in _aggregate_ in a Pool. An active Cdp with collateral and debt has a struct in the CdpManager that stores its stETH collateral value in a uint, but its actual stETH is in the balance of the ActivePool contract.

Likewise, the StabilityPool holds the total accumulated stETH gains from liquidations for all depositors.

**Borrower Operations**

| Function                     | stETH quantity                        | Path                                       |
|------------------------------|-------------------------------------|--------------------------------------------|
| openCdp                    | msg.value                           | msg.sender->BorrowerOperations->ActivePool |
| addColl                      | msg.value                           | msg.sender->BorrowerOperations->ActivePool |
| withdrawColl                 | _collWithdrawal parameter           | ActivePool->msg.sender                     |
| adjustCdp: adding stETH      | msg.value                           | msg.sender->BorrowerOperations->ActivePool |
| adjustCdp: withdrawing stETH | _collWithdrawal parameter           | ActivePool->msg.sender                     |
| closeCdp                   | All remaining                       | ActivePool->msg.sender                     |
| claimCollateral              | CollSurplusPool.balance[msg.sender] | CollSurplusPool->msg.sender                |

**Cdp Manager**

| Function                                | stETH quantity                           | Path                          |
|-----------------------------------------|----------------------------------------|-------------------------------|
| liquidate (offset)                      | collateral to be offset                | ActivePool->StabilityPool     |
| liquidate (redistribution)              | collateral to be redistributed         | ActivePool->DefaultPool       |
| liquidateCdps (offset)                | collateral to be offset                | ActivePool->StabilityPool     |
| liquidateCdps (redistribution)        | collateral to be redistributed         | ActivePool->DefaultPool       |
| batchLiquidateCdps (offset)           | collateral to be offset                | ActivePool->StabilityPool     |
| batchLiquidateCdps (redistribution).  | collateral to be redistributed         | ActivePool->DefaultPool       |
| redeemCollateral                        | collateral to be swapped with redeemer | ActivePool->msg.sender        |
| redeemCollateral                        | redemption fee                         | ActivePool->FeeRecipient       |
| redeemCollateral                        | cdp's collateral surplus             | ActivePool->CollSurplusPool |

### Flow of eBTC tokens in eBTC

![Flow of eBTC](images/EBTC_flows.svg)

When a user issues debt from their Cdp, eBTC tokens are minted to their own address, and a debt is recorded on the Cdp. Conversely, when they repay their Cdp’s eBTC debt, eBTC is burned from their address, and the debt on their Cdp is reduced.

Redemptions burn eBTC from the redeemer’s balance, and reduce the debt of the Cdp redeemed against.

**Borrower Operations**

| Function                      | eBTC Quantity | ERC20 Operation                      |
|-------------------------------|---------------|--------------------------------------|
| openCdp                     | Drawn eBTC    | eBTC._mint(msg.sender, _EBTCAmount)  |
| withdrawEBTC                  | Drawn eBTC    | eBTC._mint(msg.sender, _EBTCAmount)  |
| repayEBTC                     | Repaid eBTC   | eBTC._burn(msg.sender, _EBTCAmount)  |
| adjustCdp: withdrawing eBTC | Drawn eBTC    | eBTC._mint(msg.sender, _EBTCAmount)  |
| adjustCdp: repaying eBTC    | Repaid eBTC   | eBTC._burn(msg.sender, _EBTCAmount)  |
| closeCdp                    | Repaid eBTC   | eBTC._burn(msg.sender, _EBTCAmount) |

**Cdp Manager**

| Function                 | eBTC Quantity            | ERC20 Operation                                  |
|--------------------------|--------------------------|--------------------------------------------------|
| liquidate (offset)       | eBTC to offset with debt | eBTC._burn(stabilityPoolAddress, _debtToOffset); |
| liquidateCdps (offset)   | eBTC to offset with debt | eBTC._burn(stabilityPoolAddress, _debtToOffset); |
| batchLiquidateCdps (offset) | eBTC to offset with debt | eBTC._burn(stabilityPoolAddress, _debtToOffset); |
| redeemCollateral         | eBTC to redeem           | eBTC._burn(msg.sender, _EBTC)                    |

## Expected User Behaviors

Generally, borrowers call functions that trigger Cdp operations on their own Cdp.

Anyone may call the public liquidation functions, and attempt to liquidate one or several Cdps.

eBTC token holders may also redeem their tokens, and swap an amount of tokens 1-for-1 in value (minus fees) with stETH.

## Contract Ownership and Function Permissions

All the core smart contracts inherit from the OpenZeppelin `Ownable.sol` contract template. As such all contracts have a single owning address, which is the deploying address. The contract's ownership is renounced either upon deployment, or immediately after its address setter has been called, connecting it to the rest of the core eBTC system. 

Several public and external functions have modifiers such as `requireCallerIsCdpManager`, `requireCallerIsActivePool`, etc - ensuring they can only be called by the respective permitted contract.

Functions subject to minimal governance use the `isAuthorized()` modifier inherited from `AuthNoOwner.sol`. The authority contract is the Governor. See [solmate auth paradigm](https://github.com/transmissions11/solmate/tree/main/src/auth) which this functionality is lightly modified from.

## Deployment to a Development Blockchain

The Hardhat migrations script and deployment helpers in `utils/deploymentHelpers.js` deploy all contracts, and connect all contracts to their dependency contracts, by setting the necessary deployed addresses.

The project is deployed on the Goerli testnet.

## Running Tests

Run all tests with `npx hardhat test`, or run a specific test with `npx hardhat test ./test/contractTest.js`

Tests are run against the Hardhat EVM.

### Brownie Tests
There are some special tests that are using Brownie framework.

To test, install brownie with:
```
python3 -m pip install --user pipx
python3 -m pipx ensurepath

pipx install eth-brownie
```

and add numpy with:
```
pipx inject eth-brownie numpy
```

Add OpenZeppelin package:
```
brownie pm install OpenZeppelin/openzeppelin-contracts@3.3.0
```

Run, from `packages/contracts/`:
```
brownie test -s
```

### Coverage

To check test coverage you can run:
```
yarn coverage
```

You can see the coverage status at mainnet deployment [here](https://codecov.io/gh/liquity/dev/tree/8f52f2906f99414c0b1c3a84c95c74c319b7a8c6).

![Impacted file tree graph](https://codecov.io/gh/liquity/dev/pull/707/graphs/tree.svg?width=650&height=150&src=pr&token=7AJPQ3TW0O&utm_medium=referral&utm_source=github&utm_content=comment&utm_campaign=pr+comments&utm_term=liquity)

There’s also a [pull request](https://github.com/liquity/dev/pull/515) to increase the coverage, but it hasn’t been merged yet because it modifies some smart contracts (mostly removing unnecessary checks).

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

All data structures with the ‘public’ visibility specifier are ‘gettable’, with getters automatically generated by the compiler. Simply call `CdpManager::MCR()` to get the MCR, etc.

## Public User-Facing Functions

### Borrower (Cdp) Operations - `BorrowerOperations.sol`

- `openCdp`
- `addColl`
- `withdrawColl`
- `withdrawEBTC`
- `repayEBTC`
- `_adjustCdp`
- `closeCdp()`
- `claimCollateral`

### CdpManager Functions - `CdpManager.sol`

- `liquidate`
- `partiallyLiquidate`
- `liquidateCdps`
- `batchLiquidateCdps`
- `redeemCollateral`

### Hint Helper Functions - `HintHelpers.sol`

`function getApproxHint(uint _CR, uint _numTrials, uint _inputRandomSeed)`: helper function, returns a positional hint for the sorted list. Used for transactions that must efficiently re-insert a Cdp to the sorted list.

`getRedemptionHints(uint _EBTCamount, uint _price, uint _maxIterations)`: helper function specifically for redemptions. Returns three hints:

- `firstRedemptionHint` is a positional hint for the first redeemable Cdp (i.e. Cdp with the lowest ICR >= MCR).
- `partialRedemptionHintNICR` is the final nominal ICR of the last Cdp after being hit by partial redemption, or zero in case of no partial redemption (see [Hints for `redeemCollateral`](#hints-for-redeemcollateral)).
- `truncatedEBTCamount` is the maximum amount that can be redeemed out of the the provided `_EBTCamount`. This can be lower than `_EBTCamount` when redeeming the full amount would leave the last Cdp of the redemption sequence with less debt than the minimum allowed value.

The number of Cdps to consider for redemption can be capped by passing a non-zero value as `_maxIterations`, while passing zero will leave it uncapped.

### eBTC token `EBTCToken.sol`

Standard ERC20 and EIP2612 (`permit()` ) functionality.

**Note**: `permit()` can be front-run, as it does not require that the permitted spender be the `msg.sender`.

This allows flexibility, as it means that _anyone_ can submit a Permit signed by A that allows B to spend a portion of A's tokens.

The end result is the same for the signer A and spender B, but does mean that a `permit` transaction
could be front-run and revert - which may hamper the execution flow of a contract that is intended to handle the submission of a Permit on-chain.

For more details please see the original proposal EIP-2612:
https://eips.ethereum.org/EIPS/eip-2612

## Supplying Hints to Cdp operations

Cdps in eBTC are recorded in a sorted doubly linked list, sorted by their NICR, from high to low. NICR stands for the nominal collateral ratio that is simply the amount of collateral (in stETH) multiplied by 100e18 and divided by the amount of debt (in eBTC), without taking the stETH:BTC price into account. Given that all Cdps are equally affected by stETH price changes, they do not need to be sorted by their real ICR.

All Cdp operations that change the collateralization ratio need to either insert or reinsert the Cdp to the `SortedCdps` list. To reduce the computational complexity (and gas cost) of the insertion to the linked list, two ‘hints’ may be provided.

A hint is the address of a Cdp with a position in the sorted list close to the correct insert position.

All Cdp operations take two ‘hint’ arguments: a `_lowerHint` referring to the `nextId` and an `_upperHint` referring to the `prevId` of the two adjacent nodes in the linked list that are (or would become) the neighbors of the given Cdp. Taking both direct neighbors as hints has the advantage of being much more resilient to situations where a neighbor gets moved or removed before the caller's transaction is processed: the transaction would only fail if both neighboring Cdps are affected during the pendency of the transaction.

The better the ‘hint’ is, the shorter the list traversal, and the cheaper the gas cost of the function call. `SortedList::findInsertPosition(uint256 _NICR, address _prevId, address _nextId)` that is called by the Cdp operation firsts check if `prevId` is still existant and valid (larger NICR than the provided `_NICR`) and then descends the list starting from `prevId`. If the check fails, the function further checks if `nextId` is still existant and valid (smaller NICR than the provided `_NICR`) and then ascends list starting from `nextId`. 

The `HintHelpers::getApproxHint(...)` function can be used to generate a useful hint pointing to a Cdp relatively close to the target position, which can then be passed as an argument to the desired Cdp operation or to `SortedCdps::findInsertPosition(...)` to get its two direct neighbors as ‘exact‘ hints (based on the current state of the system).

`getApproxHint(uint _CR, uint _numTrials, uint _inputRandomSeed)` randomly selects `numTrials` amount of Cdps, and returns the one with the closest position in the list to where a Cdp with a nominal collateralization ratio of `_CR` should be inserted. It can be shown mathematically that for `numTrials = k * sqrt(n)`, the function's gas cost is with very high probability worst case `O(sqrt(n)) if k >= 10`. For scalability reasons (Infura is able to serve up to ~4900 trials), the function also takes a random seed `_inputRandomSeed` to make sure that calls with different seeds may lead to a different results, allowing for better approximations through multiple consecutive runs.

**Cdp operation without a hint**

1. User performs Cdp operation in their browser
2. Call the Cdp operation with `_lowerHint = _upperHint = userAddress`

Gas cost will be worst case `O(n)`, where n is the size of the `SortedCdps` list.

**Cdp operation with hints**

1. User performs Cdp operation in their browser
2. The front end computes a new collateralization ratio locally, based on the change in collateral and/or debt.
3. Call `HintHelpers::getApproxHint(...)`, passing it the computed nominal collateralization ratio. Returns an address close to the correct insert position
4. Call `SortedCdps::findInsertPosition(uint256 _NICR, address _prevId, address _nextId)`, passing it the same approximate hint via both `_prevId` and `_nextId` and the new nominal collateralization ratio via `_NICR`. 
5. Pass the ‘exact‘ hint in the form of the two direct neighbors, i.e. `_nextId` as `_lowerHint` and `_prevId` as `_upperHint`, to the Cdp operation function call. (Note that the hint may become slightly inexact due to pending transactions that are processed first, though this is gracefully handled by the system that can ascend or descend the list as needed to find the right position.)

Gas cost of steps 2-4 will be free, and step 5 will be `O(1)`.

Hints allow cheaper Cdp operations for the user, at the expense of a slightly longer time to completion, due to the need to await the result of the two read calls in steps 1 and 2 - which may be sent as JSON-RPC requests to Infura, unless the Frontend Operator is running a full Ethereum node.

### Example Borrower Operations with Hints

#### Opening a cdp
```
  const toWei = web3.utils.toWei
  const toBN = web3.utils.toBN

  const EBTCAmount = toBN(toWei('2500')) // borrower wants to withdraw 2500 eBTC
  const ETHColl = toBN(toWei('5')) // borrower wants to lock 5 stETH collateral

  // Call deployed CdpManager contract to read the liquidation reserve and latest borrowing fee
  const liquidationReserve = await cdpManager.EBTC_GAS_COMPENSATION()
  const expectedFee = await cdpManager.getBorrowingFeeWithDecay(EBTCAmount)
  
  // Total debt of the new cdp = eBTC amount drawn, plus fee, plus the liquidation reserve
  const expectedDebt = EBTCAmount.add(expectedFee).add(liquidationReserve)

  // Get the nominal NICR of the new cdp
  const _1e20 = toBN(toWei('100'))
  let NICR = ETHColl.mul(_1e20).div(expectedDebt)

  // Get an approximate address hint from the deployed HintHelper contract. Use (15 * number of cdps) trials 
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

#### Adjusting a Cdp
```
  const collIncrease = toBN(toWei('1'))  // borrower wants to add 1 stETH
  const EBTCRepayment = toBN(toWei('230')) // borrower wants to repay 230 eBTC

  // Get cdp's current debt and coll
  const {0: debt, 1: coll} = await cdpManager.getEntireDebtAndColl(borrower)
  
  const newDebt = debt.sub(EBTCRepayment)
  const newColl = coll.add(collIncrease)

  NICR = newColl.mul(_1e20).div(newDebt)

  // Get an approximate address hint from the deployed HintHelper contract. Use (15 * number of cdps) trials 
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
- `_firstRedemptionHint` hints at the position of the first Cdp that will be redeemed from,
- `_lowerPartialRedemptionHint` hints at the `nextId` neighbor of the last redeemed Cdp upon reinsertion, if it's partially redeemed,
- `_upperPartialRedemptionHint` hints at the `prevId` neighbor of the last redeemed Cdp upon reinsertion, if it's partially redeemed,
- `_partialRedemptionHintNICR` ensures that the transaction won't run out of gas if neither `_lowerPartialRedemptionHint` nor `_upperPartialRedemptionHint` are  valid anymore.

`redeemCollateral` will only redeem from Cdps that have an ICR >= MCR. In other words, if there are Cdps at the bottom of the SortedCdps list that are below the minimum collateralization ratio (which can happen after an stETH:BTC price drop), they will be skipped. To make this more gas-efficient, the position of the first redeemable Cdp should be passed as `_firstRedemptionHint`.

#### First redemption hint

The first redemption hint is the address of the cdp from which to start the redemption sequence - i.e the address of the first cdp in the system with ICR >= 110%.

If when the transaction is confirmed the address is in fact not valid - the system will start from the lowest ICR cdp in the system, and step upwards until it finds the first cdp with ICR >= 110% to redeem from. In this case, since the number of cdps below 110% will be limited due to ongoing liquidations, there's a good chance that the redemption transaction still succeed. 

#### Partial redemption hints

All Cdps that are fully redeemed from in a redemption sequence are left with zero debt, and are closed. The remaining collateral (the difference between the orginal collateral and the amount used for the redemption) will be claimable by the owner.

It’s likely that the last Cdp in the redemption sequence would be partially redeemed from - i.e. only some of its debt cancelled with eBTC. In this case, it should be reinserted somewhere between top and bottom of the list. The `_lowerPartialRedemptionHint` and `_upperPartialRedemptionHint` hints passed to `redeemCollateral` describe the future neighbors the expected reinsert position.

However, if between the off-chain hint computation and on-chain execution a different transaction changes the state of a Cdp that would otherwise be hit by the redemption sequence, then the off-chain hint computation could end up totally inaccurate. This could lead to the whole redemption sequence reverting due to out-of-gas error.

To mitigate this, another hint needs to be provided: `_partialRedemptionHintNICR`, the expected nominal ICR of the final partially-redeemed-from Cdp. The on-chain redemption function checks whether, after redemption, the nominal ICR of this Cdp would equal the nominal ICR hint.

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
  * ICR of the final partially redeemed cdp in the sequence. 
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

In eBTC, we want to maximize liquidation throughput, and ensure that undercollateralized Cdps are liquidated promptly by “liquidators” - agents who may also hold Stability Pool deposits, and who expect to profit from liquidations.

However, gas costs in Ethereum are substantial. If the gas costs of our public liquidation functions are too high, this may discourage liquidators from calling them, and leave the system holding too many undercollateralized Cdps for too long.

The protocol thus directly compensates liquidators for their gas costs, to incentivize prompt liquidations in both normal and extreme periods of high gas prices. Liquidators should be confident that they will at least break even by making liquidation transactions.

Gas compensation is paid in a mix of eBTC and stETH. While the stETH is taken from the liquidated Cdp, the eBTC is provided by the borrower. When a borrower first issues debt, some eBTC is reserved as a Liquidation Reserve. A liquidation transaction thus draws stETH from the cdp(s) it liquidates, and sends the both the reserved eBTC and the compensation in stETH to the caller, and liquidates the remainder.

When a liquidation transaction liquidates multiple Cdps, each Cdp contributes eBTC and stETH towards the total compensation for the transaction.

Gas compensation per liquidated Cdp is given by the formula:

Gas compensation = `200 eBTC + 0.5% of cdp’s collateral (stETH)`

The intentions behind this formula are:
- To ensure that smaller Cdps are liquidated promptly in normal times, at least
- To ensure that larger Cdps are liquidated promptly even in extreme high gas price periods. The larger the Cdp, the stronger the incentive to liquidate it.

### Gas compensation schedule

When a borrower opens a Cdp, an additional 200 eBTC debt is issued, and 200 eBTC is minted and sent to a dedicated contract (`GasPool`) for gas compensation - the "gas pool".

When a borrower closes their active Cdp, this gas compensation is refunded: 200 eBTC is burned from the gas pool's balance, and the corresponding 200 eBTC debt on the Cdp is cancelled.

The purpose of the 200 eBTC Liquidation Reserve is to provide a minimum level of gas compensation, regardless of the Cdp's collateral size or the current stETH price.

### Liquidation

When a Cdp is liquidated, 0.5% of its collateral is sent to the liquidator, along with the 200 eBTC Liquidation Reserve. Thus, a liquidator always receives `{200 eBTC + 0.5% collateral}` per Cdp that they liquidate. The collateral remainder of the Cdp is then either offset, redistributed or a combination of both, depending on the amount of eBTC in the Stability Pool.

### Gas compensation and redemptions

When a Cdp is redeemed from, the redemption is made only against (debt - 200), not the entire debt.

But if the redemption causes an amount (debt - 200) to be cancelled, the Cdp is then closed: the 200 eBTC Liquidation Reserve is cancelled with its remaining 200 debt. That is, the gas compensation is burned from the gas pool, and the 200 debt is zero’d. The stETH collateral surplus from the Cdp remains in the system, to be later claimed by its owner.

### Gas compensation helper functions

Gas compensation functions are found in the parent _LiquityBase.sol_ contract:

`_getCollGasCompensation(uint _entireColl)` returns the amount of stETH to be drawn from a cdp's collateral and sent as gas compensation. 

`_getCompositeDebt(uint _debt)` returns the composite debt (drawn debt + gas compensation) of a cdp, for the purpose of ICR calculation.

## eBTC System Fees

eBTC generates fee revenue from redemptions. Fees are captured by the feeRecipient contract. Redemptions fees are paid in stETH.

### Redemption Fee

The redemption fee is taken as a cut of the total stETH drawn from the system in a redemption. It is based on the current redemption rate.

In the `CdpManager`, `redeemCollateral` calculates the stETH fee and transfers it to the staking contract, `FeeRecipient.sol`

### Fee Schedule

Redemption fees are based on the `baseRate` state variable in CdpManager, which is dynamically updated. The `baseRate` increases with each redemption, and decays according to time passed since the last fee event - i.e. the last redemption of eBTC.

The current fee schedule:

Upon each redemption:
- `baseRate` is decayed based on time passed since the last fee event
- `baseRate` is incremented by an amount proportional to the fraction of the total eBTC supply that was redeemed
- The redemption rate is given by `min{REDEMPTION_FEE_FLOOR + baseRate * ETHdrawn, DECIMAL_PRECISION}`

`REDEMPTION_FEE_FLOOR` is set to 0.5%, while `DECIMAL_PRECISION` is 100%.

### Intuition behind fees

The larger the redemption volume, the greater the fee percentage.

The longer the time delay since the last operation, the more the `baseRate` decreases.

The intent is to throttle large redemptions with higher fees, and to throttle borrowing directly after large redemption volumes. The `baseRate` decay over time ensures that the fee for both borrowers and redeemers will “cool down”, while redemptions volumes are low.

Furthermore, the fees cannot become smaller than 0.5%, which in the case of redemptions protects the redemption facility from being front-run by arbitrageurs that are faster than the price feed.

### Fee decay Implementation

Time is measured in units of minutes. The `baseRate` decay is based on `block.timestamp - lastFeeOpTime`. If less than a minute has passed since the last fee event, then `lastFeeOpTime` is not updated. This prevents “base rate griefing”: i.e. it prevents an attacker stopping the `baseRate` from decaying by making a series of redemptions or issuing eBTC with time intervals of < 1 minute.

The decay parameter is tuned such that the fee changes by a factor of 0.99 per hour, i.e. it loses 1% of its current value per hour. At that rate, after one week, the baseRate decays to 18% of its prior value. The exact decay parameter is subject to change, and will be fine-tuned via economic modelling.

## Redistributions and Corrected Stakes
> 🦉 This section is not updated for eBTC, as there is no stability pool. The mechanics of redistribution still apply though

When a liquidation occurs and the Stability Pool is empty or smaller than the liquidated debt, the redistribution mechanism should distribute the remaining collateral and debt of the liquidated Cdp, to all active Cdps in the system, in proportion to their collateral.

For two Cdps A and B with collateral `A.coll > B.coll`, Cdp A should earn a bigger share of the liquidated collateral and debt.

In eBTC it is important that all active Cdps remain ordered by their ICR. We have proven that redistribution of the liquidated debt and collateral proportional to active Cdps’ collateral, preserves the ordering of active Cdps by ICR, as liquidations occur over time.  Please see the [proofs section](https://github.com/liquity/dev/tree/main/papers).

However, when it comes to implementation, Ethereum gas costs make it too expensive to loop over all Cdps and write new data to storage for each one. When a Cdp receives redistribution rewards, the system does not update the Cdp's collateral and debt properties - instead, the Cdp’s rewards remain "pending" until the borrower's next operation.

These “pending rewards” can not be accounted for in future reward calculations in a scalable way.

However: the ICR of a Cdp is always calculated as the ratio of its total collateral to its total debt. So, a Cdp’s ICR calculation **does** include all its previous accumulated rewards.

**This causes a problem: redistributions proportional to initial collateral can break cdp ordering.**

Consider the case where new Cdp is created after all active Cdps have received a redistribution from a liquidation. This “fresh” Cdp has then experienced fewer rewards than the older Cdps, and thus, it receives a disproportionate share of subsequent rewards, relative to its total collateral.

The fresh cdp would earns rewards based on its **entire** collateral, whereas old Cdps would earn rewards based only on **some portion** of their collateral - since a part of their collateral is pending, and not included in the Cdp’s `coll` property.

This can break the ordering of Cdps by ICR - see the [proofs section](https://github.com/liquity/dev/tree/main/papers).

### Corrected Stake Solution

We use a corrected stake to account for this discrepancy, and ensure that newer Cdps earn the same liquidation rewards per unit of total collateral, as do older Cdps with pending rewards. Thus the corrected stake ensures the sorted list remains ordered by ICR, as liquidation events occur over time.

When a Cdp is opened, its stake is calculated based on its collateral, and snapshots of the entire system collateral and debt which were taken immediately after the last liquidation.

A Cdp’s stake is given by:

```
stake = _coll.mul(totalStakesSnapshot).div(totalCollateralSnapshot)
```

It then earns redistribution rewards based on this corrected stake. A newly opened Cdp’s stake will be less than its raw collateral, if the system contains active Cdps with pending redistribution rewards when it was made.

Whenever a borrower adjusts their Cdp’s collateral, their pending rewards are applied, and a fresh corrected stake is computed.

To convince yourself this corrected stake preserves ordering of active Cdps by ICR, please see the [proofs section](https://github.com/liquity/dev/blob/main/papers).

## Math Proofs

The eBTC implementation relies on some important system properties and mathematical derivations.

In particular, we have:

- Proofs that Cdp ordering is maintained throughout a series of liquidations and new Cdp openings
- A derivation of a formula and implementation for a highly scalable (O(1) complexity) reward distribution in the Stability Pool, involving compounding and decreasing stakes.

PDFs of these can be found in https://github.com/liquity/dev/blob/main/papers

## Definitions

_**Cdp:**_ a collateralized debt position, bound to a single Ethereum address. Also referred to as a “CDP” in similar protocols.

_**eBTC**_:  The soft-pegged asset that may be issued from a user's collateralized debt position and freely transferred/traded to any Ethereum address. Intended to maintain parity with the US dollar, and can always be redeemed directly with the system: 1 eBTC is always exchangeable for $1 USD worth of stETH.

_**Active Cdp:**_ an Ethereum address owns an “active Cdp” if there is a node in the `SortedCdps` list with ID equal to the address, and non-zero collateral is recorded on the Cdp struct for that address.

_**Closed Cdp:**_ a Cdp that was once active, but now has zero debt and zero collateral recorded on its struct, and there is no node in the `SortedCdps` list with ID equal to the owning address.

_**Active collateral:**_ the amount of stETH collateral recorded on a Cdp’s struct

_**Active debt:**_ the amount of eBTC debt recorded on a Cdp’s struct

_**Entire collateral:**_ the sum of a Cdp’s active collateral plus its pending collateral rewards accumulated from distributions

_**Entire debt:**_ the sum of a Cdp’s active debt plus its pending debt rewards accumulated from distributions

_**Individual collateralization ratio (ICR):**_ a Cdp's ICR is the ratio of the dollar value of its entire collateral at the current stETH:BTC price, to its entire debt

_**Nominal collateralization ratio (nominal ICR, NICR):**_ a Cdp's nominal ICR is its entire collateral (in stETH) multiplied by 100e18 and divided by its entire debt.

_**Total active collateral:**_ the sum of active collateral over all Cdps. Equal to the stETH in the ActivePool.

_**Total active debt:**_ the sum of active debt over all Cdps. Equal to the eBTC in the ActivePool.

_**Total defaulted collateral:**_ the total stETH collateral in the DefaultPool

_**Total defaulted debt:**_ the total eBTC debt in the DefaultPool

_**Entire system collateral:**_ the sum of the collateral in the ActivePool and DefaultPool

_**Entire system debt:**_ the sum of the debt in the ActivePool and DefaultPool

_**Total collateralization ratio (TCR):**_ the ratio of the dollar value of the entire system collateral at the current stETH:BTC price, to the entire system debt

_**Critical collateralization ratio (CCR):**_ 150%. When the TCR is below the CCR, the system enters Recovery Mode.

_**Borrower:**_ an externally owned account or contract that locks collateral in a Cdp and issues eBTC tokens to their own address. They “borrow” eBTC tokens against their stETH collateral.

_**Depositor:**_ an externally owned account or contract that has assigned eBTC tokens to the Stability Pool, in order to earn returns from liquidations, and receive LQTY token issuance.

_**Redemption:**_ the act of swapping eBTC tokens with the system, in return for an equivalent value of stETH. Any account with a eBTC token balance may redeem them, whether or not they are a borrower.

When eBTC is redeemed for stETH, the stETH is always withdrawn from the lowest collateral Cdps, in ascending order of their collateralization ratio. A redeemer can not selectively target Cdps with which to swap eBTC for stETH.

_**Repayment:**_ when a borrower sends eBTC tokens to their own Cdp, reducing their debt, and increasing their collateralization ratio.

_**Retrieval:**_ when a borrower with an active Cdp withdraws some or all of their stETH collateral from their own cdp, either reducing their collateralization ratio, or closing their Cdp (if they have zero debt and withdraw all their stETH)

_**Liquidation:**_ the act of force-closing an undercollateralized Cdp and redistributing its collateral and debt.

Liquidation functionality is permissionless and publically available - anyone may liquidate an undercollateralized Cdp, or batch liquidate Cdps in ascending order of collateralization ratio.

_**Collateral Surplus**_: The difference between the dollar value of a Cdp's stETH collateral, and the dollar value of its eBTC debt. In a full liquidation, this is the net gain earned by the recipients of the liquidation.

_**Redistribution:**_ assignment of liquidated debt and collateral directly to active Cdps, in proportion to their collateral.

_**Gas compensation:**_ A refund, in eBTC and stETH, automatically paid to the caller of a liquidation function, intended to at least cover the gas cost of the transaction. Designed to ensure that liquidators are not dissuaded by potentially high gas costs.

## Development

The eBTC monorepo is based on Yarn's [workspaces](https://classic.yarnpkg.com/en/docs/workspaces/) feature. You might be able to install some of the packages individually with npm, but to make all interdependent packages see each other, you'll need to use Yarn.

In addition, some package scripts require Docker to be installed (Docker Desktop on Windows and Mac, Docker Engine on Linux).

### Prerequisites

You'll need to install the following:

- [Git](https://help.github.com/en/github/getting-started-with-github/set-up-git) (of course)
- [Node v12.x](https://nodejs.org/dist/latest-v12.x/)
- [Yarn](https://classic.yarnpkg.com/en/docs/install)

#### Making node-gyp work

eBTC indirectly depends on some packages with native addons. To make sure these can be built, you'll have to take some additional steps. Refer to the subsection of [Installation](https://github.com/nodejs/node-gyp#installation) in node-gyp's README that corresponds to your operating system.

Note: you can skip the manual installation of node-gyp itself (`npm install -g node-gyp`), but you will need to install its prerequisites to make sure eBTC can be installed.

### Clone & Install

```
git clone https://github.com/Badger-Finance/ebtc.git ebtc
cd ebtc
yarn
```

### Top-level scripts

There are a number of scripts in the top-level package.json file to ease development, which you can run with yarn.

#### Run all tests

```
yarn test
```

#### Deploy contracts to a testnet

E.g.:

```
yarn deploy --network ropsten
```

Supported networks are currently: ropsten, kovan, rinkeby, goerli. The above command will deploy into the default channel (the one that's used by the public dev-frontend). To deploy into the internal channel instead:

```
yarn deploy --network ropsten --channel internal
```

You can optionally specify an explicit gas price too:

```
yarn deploy --network ropsten --gas-price 20
```

After a successful deployment, the addresses of the newly deployed contracts will be written to a version-controlled JSON file under `packages/lib-ethers/deployments/default`.

To publish a new deployment, you must execute the above command for all of the following combinations:

| Network | Channel  |
| ------- | -------- |
| ropsten | default  |
| kovan   | default  |
| rinkeby | default  |
| goerli  | default  |

At some point in the future, we will make this process automatic. Once you're done deploying to all the networks, execute the following command:

```
yarn save-live-version
```

This copies the contract artifacts to a version controlled area (`packages/lib/live`) then checks that you really did deploy to all the networks. Next you need to commit and push all changed files. The repo's GitHub workflow will then build a new Docker image of the frontend interfacing with the new addresses.


#### Start a local fork blockchain and deploy the contracts
1. Create a `secrets.js` file within the @ebtc/contracts workspace (You can use this [template](packages/contracts/secrets.js.template))
2. Add an `alchemyAPIKey` to the file
3. Open a separate command line window, navigate to the ebtc project's root and call the following to launch the local fork nework:
```
yarn start-fork
```
4. On the main command line window, navigate to the ebtc project's root and call the following to run the local deployment script:
```
yarn fork-deployment
```

The script will do the following:
- Deploy all contracts locally and connect and configure them
- Open a CDP position from the first local account
- Create a Uniswap trading pair for eBTC/wETH and seed it
- Open a CDP position from the second local account
- Output all local deployment addresses to a new file called `localForkDeploymentOutput.json` under `packages/contracts/mainnetDeployment/`

**NOTES:**
- Should the script be runned again under the same active local network, the deployed addresses will be reused
- Terminating the local fork network will flush the deployment state. Starting a new environment will require a new deployment, the script will automatically delete your latest deployment record and create a new one if it detects that the addresses doesn't match any instance of the contracts on the new network
- Bear in mind that redeploying sometimes lead to new addresses being generated

## Known Issues
These issues are not modified from the text of the Liquity readme, and may no longer be relevant or may behave differently within the context of eBTC.

### Temporary and slightly inaccurate TCR calculation within `batchLiquidateCdps` in Recovery Mode. 

When liquidating a cdp with `ICR > 110%`, a collateral surplus remains claimable by the borrower. This collateral surplus should be excluded from subsequent TCR calculations, but within the liquidation sequence in `batchLiquidateCdps` in Recovery Mode, it is not. This results in a slight distortion to the TCR value used at each step of the liquidation sequence going forward. This distortion only persists for the duration the `batchLiquidateCdps` function call, and the TCR is again calculated correctly after the liquidation sequence ends. In most cases there is no impact at all, and when there is, the effect tends to be minor. The issue is not present at all in Normal Mode. 

There is a theoretical and extremely rare case where it incorrectly causes a loss for Stability Depositors instead of a gain. It relies on the stars aligning: the system must be in Recovery Mode, the TCR must be very close to the 150% boundary, a large cdp must be liquidated, and the stETH price must drop by >10% at exactly the right moment. No profitable exploit is possible. For more details, please see [this security advisory](https://github.com/liquity/dev/security/advisories/GHSA-xh2p-7p87-fhgh).

### SortedCdps edge cases - top and bottom of the sorted list

When the cdp is at one end of the `SortedCdps` list and adjusted such that its ICR moves further away from its neighbor, `findInsertPosition` returns unhelpful positional hints, which if used can cause the `adjustCdp` transaction to run out of gas. This is due to the fact that one of the returned addresses is in fact the address of the cdp to move - however, at re-insertion, it has already been removed from the list. As such the insertion logic defaults to `0x0` for that hint address, causing the system to search for the cdp starting at the opposite end of the list. A workaround is possible, and this has been corrected in the SDK used by front ends.

### Front-running issues

#### Loss evasion by front-running Stability Pool depositors

*Example sequence 1): evade liquidation tx*
- Depositor sees incoming liquidation tx that would cause them a net loss
- Depositor front-runs with `withdrawFromSP()` to evade the loss

*Example sequence 2): evade price drop*
- Depositor sees incoming price drop tx (or just anticipates one, by reading exchange price data), that would shortly be followed by unprofitable liquidation txs
- Depositor front-runs with `withdrawFromSP()` to evade the loss

Stability Pool depositors expect to make profits from liquidations which are likely to happen at a collateral ratio slightly below 110%, but well above 100%. In rare cases (flash crashes, oracle failures), cdps may be liquidated below 100% though, resulting in a net loss for stability depositors. Depositors thus have an incentive to withdraw their deposits if they anticipate liquidations below 100% (note that the exact threshold of such “unprofitable” liquidations will depend on the current Dollar price of eBTC).

As long the difference between two price feed updates is <10% and price stability is maintained, loss evasion situations should be rare. The percentage changes between two consecutive prices reported by Chainlink’s stETH:BTC oracle has only ever come close to 10% a handful of times in the past few years.

In the current implementation, deposit withdrawals are prohibited if and while there are cdps with a collateral ratio (ICR) < 110% in the system. This prevents loss evasion by front-running the liquidate transaction as long as there are cdps that are liquidatable in normal mode.

This solution is only partially effective since it does not prevent stability depositors from monitoring the stETH price feed and front-running oracle price update transactions that would make cdps liquidatable. Given that we expect loss-evasion opportunities to be very rare, we do not expect that a significant fraction of stability depositors would actually apply front-running strategies, which require sophistication and automation. In the unlikely event that large fraction of the depositors withdraw shortly before the liquidation of cdps at <100% CR, the redistribution mechanism will still be able to absorb defaults.


#### Reaping liquidation gains on the fly

*Example sequence:*
- User sees incoming profitable liquidation tx
- User front-runs it and immediately makes a deposit with `provideToSP()`
- User earns a profit

Front-runners could deposit funds to the Stability Pool on the fly (instead of keeping their funds in the pool) and make liquidation gains when they see a pending price update or liquidate transaction. They could even borrow the eBTC using a cdp as a flash loan.

Such flash deposit-liquidations would actually be beneficial (in terms of TCR) to system health and prevent redistributions, since the pool can be filled on the spot to liquidate cdps anytime, if only for the length of 1 transaction.


#### Front-running and changing the order of cdps as a DoS attack

*Example sequence:**
-Attacker sees incoming operation(`openLoan()`, `redeemCollateral()`, etc) that would insert a cdp to the sorted list
-Attacker front-runs with mass openLoan txs
-Incoming operation becomes more costly - more traversals needed for insertion

It’s theoretically possible to increase the number of the cdps that need to be traversed on-chain. That is, an attacker that sees a pending borrower transaction (or redemption or liquidation transaction) could try to increase the number of traversed cdps by introducing additional cdps on the way. However, the number of cdps that an attacker can inject before the pending transaction gets mined is limited by the amount of spendable gas. Also, the total costs of making the path longer by 1 are significantly higher (gas costs of opening a cdp, plus the 0.5% borrowing fee) than the costs of one extra traversal step (simply reading from storage). The attacker also needs significant capital on-hand, since the minimum debt for a cdp is 2000 eBTC.

In case of a redemption, the “last” cdp affected by the transaction may end up being only partially redeemed from, which means that its ICR will change so that it needs to be reinserted at a different place in the sorted cdp list (note that this is not the case for partial liquidations in recovery mode, which preserve the ICR). A special ICR hint therefore needs to be provided by the transaction sender for that matter, which may become incorrect if another transaction changes the order before the redemption is processed. The protocol gracefully handles this by terminating the redemption sequence at the last fully redeemed cdp (see [here](https://github.com/liquity/dev#hints-for-redeemcollateral)).

An attacker trying to DoS redemptions could be bypassed by redeeming an amount that exactly corresponds to the debt of the affected cdp(s).

Finally, this DoS could be avoided if the initial transaction avoids the public gas auction entirely and is sent direct-to-miner, via (for example) Flashbots.