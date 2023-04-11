/* Script that logs gas costs for Liquity operations under various conditions. 

  Note: uses Mocha testing structure, but the purpose of each test is simply to print gas costs.

  'asserts' are only used to confirm the setup conditions.
*/
const fs = require('fs')

const deploymentHelper = require("../utils/deploymentHelpers.js")
const testHelpers = require("../utils/testHelpers.js")

const th = testHelpers.TestHelper
const dec = th.dec
const timeValues = testHelpers.TimeValues
const _100pct = th._100pct

const ZERO_ADDRESS = th.ZERO_ADDRESS

contract('Gas cost tests', async accounts => {
  const [owner] = accounts;
  const bountyAddress = accounts[998]
  const lpRewardsAddress = accounts[999]
  const multisig = accounts[1000]

  let priceFeed
  let ebtcToken

  let sortedCdps
  let cdpManager
  let activePool
  let stabilityPool
  let defaultPool
  let borrowerOperations

  let contracts
  let data = []

  beforeEach(async () => {
    contracts = await deploymentHelper.deployLiquityCore()
    const LQTYContracts = await deploymentHelper.deployLQTYContracts(bountyAddress, lpRewardsAddress, multisig)

    priceFeed = contracts.priceFeedTestnet
    ebtcToken = contracts.ebtcToken
    sortedCdps = contracts.sortedCdps
    cdpManager = contracts.cdpManager
    activePool = contracts.activePool
    stabilityPool = contracts.stabilityPool
    defaultPool = contracts.defaultPool
    borrowerOperations = contracts.borrowerOperations
    hintHelpers = contracts.hintHelpers

    feeRecipient = LQTYContracts.feeRecipient
    communityIssuance = LQTYContracts.communityIssuance
    lockupContractFactory = LQTYContracts.lockupContractFactory

    await deploymentHelper.connectLQTYContracts(LQTYContracts)
    await deploymentHelper.connectCoreContracts(contracts, LQTYContracts)
    await deploymentHelper.connectLQTYContractsToCore(LQTYContracts, contracts)
  })

  // --- liquidateCdps RECOVERY MODE - pure redistribution ---

  // 1 cdp
  it("", async () => {
    const message = 'liquidateCdps(). n = 1. Pure redistribution, Recovery Mode'
    // 10 accts each open Cdp with 10 ether, withdraw 900 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(900, 18))
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }

    //1 accts open Cdp with 1 ether and withdraw 100 EBTC
    const _1_Defaulter = accounts.slice(1, 2)
    await th.openCdp_allAccounts(_1_Defaulter, contracts, dec(1, 'ether'), dec(60, 18))

    // Check all defaulters are active
    for (account of _1_Defaulter) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 opens with 1 ether and withdraws 100 EBTC
    await borrowerOperations.openCdp(dec(60, 18), accounts[500], ZERO_ADDRESS, { from: accounts[500], value: dec(1, 'ether') })
    assert.isTrue(await sortedCdps.contains(accounts[500]))

    // Price drops, defaulters' cdps fall below MCR
    await priceFeed.setPrice(dec(100, 18))
    const price = await priceFeed.getPrice()

    // Account 500 is liquidated, creates pending distribution rewards for all
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[500]))

    // Check Recovery Mode is true
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    const tx = await cdpManager.liquidateCdps(1, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    // Check defaulters' cdps have been closed
    for (account of _1_Defaulter) { assert.isFalse(await sortedCdps.contains(account)) }

    // Check initial cdps with starting 10E/90EBTC are still open
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 2 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 2. Pure redistribution. Recovery Mode'
    // 10 accts each open Cdp with 10 ether, withdraw 900 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(900, 18))
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }

    //2 accts open Cdp with 1 ether and withdraw 100 EBTC
    const _2_Defaulters = accounts.slice(1, 3)
    await th.openCdp_allAccounts(_2_Defaulters, contracts, dec(1, 'ether'), dec(60, 18))

    // Check all defaulters are active
    for (account of _2_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 opens with 1 ether and withdraws 100 EBTC
    await borrowerOperations.openCdp(dec(60, 18), accounts[500],ZERO_ADDRESS, { from: accounts[500], value: dec(1, 'ether') })
    assert.isTrue(await sortedCdps.contains(accounts[500]))

    // Price drops, defaulters' cdps fall below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Account 500 is liquidated, creates pending distribution rewards for all
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[500]))

    // Check Recovery Mode is true
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    const tx = await cdpManager.liquidateCdps(2, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    // Check defaulters' cdps have been closed
    for (account of _2_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    // Check initial cdps with starting 10E/90EBTC are still open
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 3 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 3. Pure redistribution. Recovery Mode'
    // 10 accts each open Cdp with 10 ether, withdraw 900 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(900, 18))
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }

    //3 accts open Cdp with 1 ether and withdraw 100 EBTC
    const _3_Defaulters = accounts.slice(1, 4)
    await th.openCdp_allAccounts(_3_Defaulters, contracts, dec(1, 'ether'), dec(60, 18))

    // Check all defaulters are active
    for (account of _3_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 opens with 1 ether and withdraws 100 EBTC
    await borrowerOperations.openCdp(dec(60, 18), accounts[500], ZERO_ADDRESS,{ from: accounts[500], value: dec(1, 'ether') })
    assert.isTrue(await sortedCdps.contains(accounts[500]))

    // Price drops, defaulters' cdps fall below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Account 500 is liquidated, creates pending distribution rewards for all
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[500]))

    // Check Recovery Mode is true
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    const tx = await cdpManager.liquidateCdps(3, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    // Check defaulters' cdps have been closed
    for (account of _3_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    // Check initial cdps with starting 10E/90EBTC are still open
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 5 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 5. Pure redistribution. Recovery Mode'
    // 10 accts each open Cdp with 10 ether, withdraw 900 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(900, 18))
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }

    //5 accts open Cdp with 1 ether and withdraw 100 EBTC
    const _5_Defaulters = accounts.slice(1, 6)
    await th.openCdp_allAccounts(_5_Defaulters, contracts, dec(1, 'ether'), dec(60, 18))

    // Check all defaulters are active
    for (account of _5_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 opens with 1 ether and withdraws 100 EBTC
    await borrowerOperations.openCdp(dec(60, 18), accounts[500],ZERO_ADDRESS, { from: accounts[500], value: dec(1, 'ether') })
    assert.isTrue(await sortedCdps.contains(accounts[500]))

    // Price drops, defaulters' cdps fall below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Account 500 is liquidated, creates pending distribution rewards for all
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[500]))

    // Check Recovery Mode is true
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    const tx = await cdpManager.liquidateCdps(5, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    // Check defaulters' cdps have been closed
    for (account of _5_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    // Check initial cdps with starting 10E/90EBTC are still open
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 10 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 10. Pure redistribution. Recovery Mode'
    // 10 accts each open Cdp with 10 ether, withdraw 900 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(900, 18))
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }

    //10 accts open Cdp with 1 ether and withdraw 100 EBTC
    const _10_Defaulters = accounts.slice(1, 11)
    await th.openCdp_allAccounts(_10_Defaulters, contracts, dec(1, 'ether'), dec(60, 18))

    // Check all defaulters are active
    for (account of _10_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 opens with 1 ether and withdraws 100 EBTC
    await borrowerOperations.openCdp(dec(60, 18), accounts[500],ZERO_ADDRESS, { from: accounts[500], value: dec(1, 'ether') })
    assert.isTrue(await sortedCdps.contains(accounts[500]))

    // Price drops, defaulters' cdps fall below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Account 500 is liquidated, creates pending distribution rewards for all
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[500]))

    // Check Recovery Mode is true
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    const tx = await cdpManager.liquidateCdps(10, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    // Check defaulters' cdps have been closed
    for (account of _10_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    // Check initial cdps with starting 10E/90EBTC are still open
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  //20 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 20. Pure redistribution. Recovery Mode'
    // 10 accts each open Cdp with 10 ether, withdraw 90 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(900, 18))
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }

    //20 accts open Cdp with 1 ether and withdraw 100 EBTC
    const _20_Defaulters = accounts.slice(1, 21)
    await th.openCdp_allAccounts(_20_Defaulters, contracts, dec(1, 'ether'), dec(60, 18))

    // Check all defaulters are active
    for (account of _20_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 opens with 1 ether and withdraws 100 EBTC
    await borrowerOperations.openCdp(dec(60, 18), accounts[500], ZERO_ADDRESS,{ from: accounts[500], value: dec(1, 'ether') })
    assert.isTrue(await sortedCdps.contains(accounts[500]))

    // Price drops, defaulters' cdps fall below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Account 500 is liquidated, creates pending distribution rewards for all
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[500]))

    // Check Recovery Mode is true
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    const tx = await cdpManager.liquidateCdps(20, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    // Check defaulters' cdps have been closed
    for (account of _20_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    // Check initial cdps with starting 10E/90EBTC are still open
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 30 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 30. Pure redistribution. Recovery Mode'
    // 10 accts each open Cdp with 10 ether, withdraw 90 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(900, 18))
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }

    //30 accts open Cdp with 1 ether and withdraw 100 EBTC
    const _30_Defaulters = accounts.slice(1, 31)
    await th.openCdp_allAccounts(_30_Defaulters, contracts, dec(1, 'ether'), dec(60, 18))

    // Check all defaulters are active
    for (account of _30_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 opens with 1 ether and withdraws 100 EBTC
    await borrowerOperations.openCdp(dec(60, 18), accounts[500], ZERO_ADDRESS,{ from: accounts[500], value: dec(1, 'ether') })
    assert.isTrue(await sortedCdps.contains(accounts[500]))

    // Price drops, defaulters' cdps fall below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Account 500 is liquidated, creates pending distribution rewards for all
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[500]))

    // Check Recovery Mode is true
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    const tx = await cdpManager.liquidateCdps(30, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    // Check defaulters' cdps have been closed
    for (account of _30_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    // Check initial cdps with starting 10E/90EBTC are still open
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 40 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 40. Pure redistribution. Recovery Mode'
    // 10 accts each open Cdp with 10 ether, withdraw 90 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(900, 18))
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }

    //40 accts open Cdp with 1 ether and withdraw 100 EBTC
    const _40_Defaulters = accounts.slice(1, 41)
    await th.openCdp_allAccounts(_40_Defaulters, contracts, dec(1, 'ether'), dec(60, 18))

    // Check all defaulters are active
    for (account of _40_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 opens with 1 ether and withdraws 100 EBTC
    await borrowerOperations.openCdp(dec(60, 18), accounts[500],ZERO_ADDRESS, { from: accounts[500], value: dec(1, 'ether') })
    assert.isTrue(await sortedCdps.contains(accounts[500]))

    // Price drops, defaulters' cdps fall below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Account 500 is liquidated, creates pending distribution rewards for all
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[500]))

    // Check Recovery Mode is true
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    const tx = await cdpManager.liquidateCdps(40, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    // Check defaulters' cdps have been closed
    for (account of _40_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    // Check initial cdps with starting 10E/90EBTC are still open
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 45 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 45. Pure redistribution. Recovery Mode'
    // 10 accts each open Cdp 
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(1000, 'ether'), dec(90000, 18))
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }

    //45 accts open Cdp
    const _45_Defaulters = accounts.slice(1, 46)
    await th.openCdp_allAccounts(_45_Defaulters, contracts, dec(100, 'ether'), dec(9500, 18))

    // Check all defaulters are active
    for (account of _45_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 opens Cdp
    await borrowerOperations.openCdp(dec(9500, 18), accounts[500], ZERO_ADDRESS,{ from: accounts[500], value: dec(100, 'ether') })
    assert.isTrue(await sortedCdps.contains(accounts[500]))

    // Price drops, defaulters' cdps fall below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Account 500 is liquidated, creates pending distribution rewards for all
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[500]))

    // Check Recovery Mode is true
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    const tx = await cdpManager.liquidateCdps(45, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check defaulters' cdps have been closed
    for (account of _45_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    // Check initial cdps with starting 10E/90EBTC are still open
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // --- liquidate Cdps --- RECOVERY MODE --- Full offset, NO pending distribution rewards ----

  // 1 cdp
  it("", async () => {
    const message = 'liquidateCdps(). n = 1. All fully offset with Stability Pool. No pending distribution rewards. In Recovery Mode'
    // 10 accts each open Cdp with 10 ether, withdraw 900 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(900, 18))
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }

    // Whale opens cdp and fills SP with 1 billion EBTC
    const whale = accounts[999]
    await borrowerOperations.openCdp(dec(9, 28), whale,ZERO_ADDRESS, { from: whale, value: dec(1, 27) })
    await stabilityPool.provideToSP(dec(9, 28), ZERO_ADDRESS, { from: whale })

    // Check SP has 9e28 EBTC
    const EBTCinSP = (await stabilityPool.getTotalEBTCDeposits()).toString()
    assert.equal(EBTCinSP, dec(9, 28))

    //1 acct opens Cdp with 1 ether and withdraw 100 EBTC
    const _1_Defaulter = accounts.slice(1, 2)
    await th.openCdp_allAccounts(_1_Defaulter, contracts, dec(1, 'ether'), dec(60, 18))

    // Check all defaulters are active
    for (account of _1_Defaulter) { assert.isTrue(await sortedCdps.contains(account)) }

    // Price drops, defaulters falls below MCR
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()

    // Check Recovery Mode is true
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    // Check defaulter ICRs are all between 100% and 110%
    for (account of _1_Defaulter) {
      console.log(`ICR: ${await cdpManager.getCurrentICR(account, price)}`)
      assert.isTrue(await th.ICRbetween100and110(account, cdpManager, price))
    }

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(1, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    // // Check Cdps are closed
    for (account of _1_Defaulter) { assert.isFalse(await sortedCdps.contains(account)) }

    // Check initial cdps with starting 10E/90EBTC, and whale's cdp, are still open
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }
    assert.isTrue(await sortedCdps.contains(whale))

    //Check EBTC in SP has decreased but is still > 0
    const EBTCinSP_After = await stabilityPool.getTotalEBTCDeposits()
    assert.isTrue(EBTCinSP_After.lt(web3.utils.toBN(dec(9, 28))))
    assert.isTrue(EBTCinSP_After.gt(web3.utils.toBN('0')))

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 2 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 2. All fully offset with Stability Pool. No pending distribution rewards. In Recovery Mode'
    // 10 accts each open Cdp with 10 ether, withdraw 900 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(900, 18))
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }

    // Whale opens cdp and fills SP with 1 billion EBTC
    const whale = accounts[999]
    await borrowerOperations.openCdp(dec(9, 28), whale,ZERO_ADDRESS, { from: whale, value: dec(1, 27) })
    await stabilityPool.provideToSP(dec(9, 28), ZERO_ADDRESS, { from: whale })

    // Check SP has 9e28 EBTC
    const EBTCinSP = (await stabilityPool.getTotalEBTCDeposits()).toString()
    assert.equal(EBTCinSP, dec(9, 28))

    //2 acct opens Cdp with 1 ether and withdraw 100 EBTC
    const _2_Defaulters = accounts.slice(1, 3)
    await th.openCdp_allAccounts(_2_Defaulters, contracts, dec(1, 'ether'), dec(60, 18))

    // Check all defaulters are active
    for (account of _2_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Price drops, defaulters falls below MCR
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()

    // Check Recovery Mode is true
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    // Check defaulter ICRs are all between 100% and 110%
    for (account of _2_Defaulters) { assert.isTrue(await th.ICRbetween100and110(account, cdpManager, price)) }

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(2, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    // // Check Cdps are closed
    for (account of _2_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    // Check initial cdps with starting 10E/90EBTC, and whale's cdp, are still open
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }
    assert.isTrue(await sortedCdps.contains(whale))

    //Check EBTC in SP has decreased but is still > 0
    const EBTCinSP_After = await stabilityPool.getTotalEBTCDeposits()
    assert.isTrue(EBTCinSP_After.lt(web3.utils.toBN(dec(9, 28))))
    assert.isTrue(EBTCinSP_After.gt(web3.utils.toBN('0')))

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })


  // 3 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 3. All fully offset with Stability Pool. No pending distribution rewards. In Recovery Mode'
    // 10 accts each open Cdp with 10 ether, withdraw 900 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(900, 18))
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }

    // Whale opens cdp and fills SP with 1 billion EBTC
    const whale = accounts[999]
    await borrowerOperations.openCdp(dec(9, 28), whale,ZERO_ADDRESS, { from: whale, value: dec(1, 27) })
    await stabilityPool.provideToSP(dec(9, 28), ZERO_ADDRESS, { from: whale })

    // Check SP has 9e28 EBTC
    const EBTCinSP = (await stabilityPool.getTotalEBTCDeposits()).toString()
    assert.equal(EBTCinSP, dec(9, 28))

    //3 accts open Cdp with 1 ether and withdraw 100 EBTC
    const _3_Defaulters = accounts.slice(1, 4)
    await th.openCdp_allAccounts(_3_Defaulters, contracts, dec(1, 'ether'), dec(60, 18))

    // Check all defaulters are active
    for (account of _3_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Price drops, defaulters falls below MCR
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()

    // Check Recovery Mode is true
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    // Check defaulter ICRs are all between 100% and 110%
    for (account of _3_Defaulters) { assert.isTrue(await th.ICRbetween100and110(account, cdpManager, price)) }

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(3, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    // // Check Cdps are closed
    for (account of _3_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    // Check initial cdps with starting 10E/90EBTC, and whale's cdp, are still open
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }
    assert.isTrue(await sortedCdps.contains(whale))

    //Check EBTC in SP has decreased but is still > 0
    const EBTCinSP_After = await stabilityPool.getTotalEBTCDeposits()
    assert.isTrue(EBTCinSP_After.lt(web3.utils.toBN(dec(9, 28))))
    assert.isTrue(EBTCinSP_After.gt(web3.utils.toBN('0')))

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 5 cdps 
  it("", async () => {
    const message = 'liquidateCdps(). n = 5. All fully offset with Stability Pool. No pending distribution rewards. In Recovery Mode'
    // 10 accts each open Cdp with 10 ether, withdraw 900 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(900, 18))
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }

    // Whale opens cdp and fills SP with 1 billion EBTC
    const whale = accounts[999]
    await borrowerOperations.openCdp(dec(9, 28), whale,ZERO_ADDRESS, { from: whale, value: dec(1, 27) })
    await stabilityPool.provideToSP(dec(9, 28), ZERO_ADDRESS, { from: whale })

    // Check SP has 9e28 EBTC
    const EBTCinSP = (await stabilityPool.getTotalEBTCDeposits()).toString()
    assert.equal(EBTCinSP, dec(9, 28))

    //5 accts open Cdp with 1 ether and withdraw 100 EBTC
    const _5_Defaulters = accounts.slice(1, 6)
    await th.openCdp_allAccounts(_5_Defaulters, contracts, dec(1, 'ether'), dec(60, 18))

    // Check all defaulters are active
    for (account of _5_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Price drops, defaulters falls below MCR
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()

    // Check Recovery Mode is true
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    // Check defaulter ICRs are all between 100% and 110%
    for (account of _5_Defaulters) { assert.isTrue(await th.ICRbetween100and110(account, cdpManager, price)) }

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(5, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    // // Check Cdps are closed
    for (account of _5_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    // Check initial cdps with starting 10E/90EBTC, and whale's cdp, are still open
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }
    assert.isTrue(await sortedCdps.contains(whale))

    //Check EBTC in SP has decreased but is still > 0
    const EBTCinSP_After = await stabilityPool.getTotalEBTCDeposits()
    assert.isTrue(EBTCinSP_After.lt(web3.utils.toBN(dec(9, 28))))
    assert.isTrue(EBTCinSP_After.gt(web3.utils.toBN('0')))

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })


  // 10 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 10. All fully offset with Stability Pool. No pending distribution rewards. In Recovery Mode'
    // 10 accts each open Cdp with 10 ether, withdraw 900 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(900, 18))
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }

    // Whale opens cdp and fills SP with 1 billion EBTC
    const whale = accounts[999]
    await borrowerOperations.openCdp(dec(9, 28), whale,ZERO_ADDRESS, { from: whale, value: dec(1, 27) })
    await stabilityPool.provideToSP(dec(9, 28), ZERO_ADDRESS, { from: whale })

    // Check SP has 9e28 EBTC
    const EBTCinSP = (await stabilityPool.getTotalEBTCDeposits()).toString()
    assert.equal(EBTCinSP, dec(9, 28))

    //10 accts open Cdp with 1 ether and withdraw 100 EBTC
    const _10_Defaulters = accounts.slice(1, 11)
    await th.openCdp_allAccounts(_10_Defaulters, contracts, dec(1, 'ether'), dec(60, 18))

    // Check all defaulters are active
    for (account of _10_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Price drops, defaulters falls below MCR
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()

    // Check Recovery Mode is true
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    // Check defaulter ICRs are all between 100% and 110%
    for (account of _10_Defaulters) { assert.isTrue(await th.ICRbetween100and110(account, cdpManager, price)) }

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(10, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    // // Check Cdps are closed
    for (account of _10_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    // Check initial cdps with starting 10E/90EBTC, and whale's cdp, are still open
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }
    assert.isTrue(await sortedCdps.contains(whale))

    //Check EBTC in SP has decreased but is still > 0
    const EBTCinSP_After = await stabilityPool.getTotalEBTCDeposits()
    assert.isTrue(EBTCinSP_After.lt(web3.utils.toBN(dec(9, 28))))
    assert.isTrue(EBTCinSP_After.gt(web3.utils.toBN('0')))

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 20 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 20. All fully offset with Stability Pool. No pending distribution rewards. In Recovery Mode'
    // 10 accts each open Cdp with 10 ether, withdraw 900 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(900, 18))
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }

    // Whale opens cdp and fills SP with 1 billion EBTC
    const whale = accounts[999]
    await borrowerOperations.openCdp(dec(9, 28), whale,ZERO_ADDRESS, { from: whale, value: dec(1, 27) })
    await stabilityPool.provideToSP(dec(9, 28), ZERO_ADDRESS, { from: whale })

    // Check SP has 9e28 EBTC
    const EBTCinSP = (await stabilityPool.getTotalEBTCDeposits()).toString()
    assert.equal(EBTCinSP, dec(9, 28))

    //30 accts open Cdp with 1 ether and withdraw 100 EBTC
    const _20_Defaulters = accounts.slice(1, 21)
    await th.openCdp_allAccounts(_20_Defaulters, contracts, dec(1, 'ether'), dec(60, 18))

    // Check all defaulters are active
    for (account of _20_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Price drops, defaulters falls below MCR
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()

    // Check Recovery Mode is true
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    // Check defaulter ICRs are all between 100% and 110%
    for (account of _20_Defaulters) { assert.isTrue(await th.ICRbetween100and110(account, cdpManager, price)) }

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(20, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    // // Check Cdps are closed
    for (account of _20_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    // Check initial cdps with starting 10E/90EBTC, and whale's cdp, are still open
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }
    assert.isTrue(await sortedCdps.contains(whale))

    //Check EBTC in SP has decreased but is still > 0
    const EBTCinSP_After = await stabilityPool.getTotalEBTCDeposits()
    assert.isTrue(EBTCinSP_After.lt(web3.utils.toBN(dec(9, 28))))
    assert.isTrue(EBTCinSP_After.gt(web3.utils.toBN('0')))

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })


  // 30 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 30. All fully offset with Stability Pool. No pending distribution rewards. In Recovery Mode'
    // 10 accts each open Cdp with 10 ether, withdraw 900 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(900, 18))
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }

    // Whale opens cdp and fills SP with 1 billion EBTC
    const whale = accounts[999]
    await borrowerOperations.openCdp(dec(9, 28), whale,ZERO_ADDRESS, { from: whale, value: dec(1, 27) })
    await stabilityPool.provideToSP(dec(9, 28), ZERO_ADDRESS, { from: whale })

    // Check SP has 9e28 EBTC
    const EBTCinSP = (await stabilityPool.getTotalEBTCDeposits()).toString()
    assert.equal(EBTCinSP, dec(9, 28))

    //30 accts open Cdp with 1 ether and withdraw 100 EBTC
    const _30_Defaulters = accounts.slice(1, 31)
    await th.openCdp_allAccounts(_30_Defaulters, contracts, dec(1, 'ether'), dec(60, 18))

    // Check all defaulters are active
    for (account of _30_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Price drops, defaulters falls below MCR
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()

    // Check Recovery Mode is true
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    // Check defaulter ICRs are all between 100% and 110%
    for (account of _30_Defaulters) { assert.isTrue(await th.ICRbetween100and110(account, cdpManager, price)) }

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(30, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    // // Check Cdps are closed
    for (account of _30_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    // Check initial cdps with starting 10E/90EBTC, and whale's cdp, are still open
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }
    assert.isTrue(await sortedCdps.contains(whale))

    //Check EBTC in SP has decreased but is still > 0
    const EBTCinSP_After = await stabilityPool.getTotalEBTCDeposits()
    assert.isTrue(EBTCinSP_After.lt(web3.utils.toBN(dec(9, 28))))
    assert.isTrue(EBTCinSP_After.gt(web3.utils.toBN('0')))

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 40 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 40. All fully offset with Stability Pool. No pending distribution rewards. In Recovery Mode'
    // 10 accts each open Cdp with 10 ether, withdraw 900 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(900, 18))
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }

    // Whale opens cdp and fills SP with 1 billion EBTC
    const whale = accounts[999]
    await borrowerOperations.openCdp(dec(9, 28), whale, ZERO_ADDRESS,{ from: whale, value: dec(1, 27) })
    await stabilityPool.provideToSP(dec(9, 28), ZERO_ADDRESS, { from: whale })

    // Check SP has 9e28 EBTC
    const EBTCinSP = (await stabilityPool.getTotalEBTCDeposits()).toString()
    assert.equal(EBTCinSP, dec(9, 28))

    //40 accts open Cdp with 1 ether and withdraw 100 EBTC
    const _40_Defaulters = accounts.slice(1, 41)
    await th.openCdp_allAccounts(_40_Defaulters, contracts, dec(1, 'ether'), dec(60, 18))

    // Check all defaulters are active
    for (account of _40_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Price drops, defaulters falls below MCR
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()

    // Check Recovery Mode is true
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    // Check defaulter ICRs are all between 100% and 110%
    for (account of _40_Defaulters) { assert.isTrue(await th.ICRbetween100and110(account, cdpManager, price)) }

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(40, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    // // Check Cdps are closed
    for (account of _40_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    // Check initial cdps with starting 10E/90EBTC, and whale's cdp, are still open
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }
    assert.isTrue(await sortedCdps.contains(whale))

    //Check EBTC in SP has decreased but is still > 0
    const EBTCinSP_After = await stabilityPool.getTotalEBTCDeposits()
    assert.isTrue(EBTCinSP_After.lt(web3.utils.toBN(dec(9, 28))))
    assert.isTrue(EBTCinSP_After.gt(web3.utils.toBN('0')))

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 45 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 45. All fully offset with Stability Pool. No pending distribution rewards. In Recovery Mode'
    // 10 accts each open Cdp with 10 ether, withdraw 900 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(1000, 'ether'), dec(90000, 18))
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }

    // Whale opens cdp and fills SP with 1 billion EBTC
    const whale = accounts[999]
    await borrowerOperations.openCdp(dec(9, 28), whale,ZERO_ADDRESS, { from: whale, value: dec(1, 27) })
    await stabilityPool.provideToSP(dec(9, 28), ZERO_ADDRESS, { from: whale })

    // Check SP has 9e28 EBTC
    const EBTCinSP = (await stabilityPool.getTotalEBTCDeposits()).toString()
    assert.equal(EBTCinSP, dec(9, 28))

    //45 accts open Cdp with 1 ether and withdraw 100 EBTC
    const _45_Defaulters = accounts.slice(1, 46)
    await th.openCdp_allAccounts(_45_Defaulters, contracts, dec(100, 'ether'), dec(9500, 18))

    // Check all defaulters are active
    for (account of _45_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Price drops, defaulters falls below MCR
    await priceFeed.setPrice(dec(100, 18))
    const price = await priceFeed.getPrice()

    // Check Recovery Mode is true
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    // Check defaulter ICRs are all between 100% and 110%
    for (account of _45_Defaulters) { assert.isTrue(await th.ICRbetween100and110(account, cdpManager, price)) }

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(45, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    // // Check Cdps are closed
    for (account of _45_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    // Check initial cdps with starting 10E/90EBTC, and whale's cdp, are still open
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }
    assert.isTrue(await sortedCdps.contains(whale))

    //Check EBTC in SP has decreased but is still > 0
    const EBTCinSP_After = await stabilityPool.getTotalEBTCDeposits()
    assert.isTrue(EBTCinSP_After.lt(web3.utils.toBN(dec(9, 28))))
    assert.isTrue(EBTCinSP_After.gt(web3.utils.toBN('0')))

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // --- liquidate Cdps --- RECOVERY MODE --- Full offset, HAS pending distribution rewards ----

  // 1 cdp
  it("", async () => {
    const message = 'liquidateCdps(). n = 1. All fully offset with Stability Pool. Has pending distribution rewards. In Recovery Mode'
    // 10 accts each open Cdp with 10 ether, withdraw 900 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(900, 18))
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }

    //1 acct opens Cdp with 1 ether and withdraw 100 EBTC
    const _1_Defaulter = accounts.slice(1, 2)
    await th.openCdp_allAccounts(_1_Defaulter, contracts, dec(1, 'ether'), dec(60, 18))

    // Check all defaulters are active
    for (account of _1_Defaulter) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 opens with 1 ether and withdraws 110 EBTC
    await borrowerOperations.openCdp(dec(110, 18), accounts[500],ZERO_ADDRESS, { from: accounts[500], value: dec(1, 'ether') })
    assert.isTrue(await sortedCdps.contains(accounts[500]))

    // Account 500 is liquidated, creates pending distribution rewards for all
    await priceFeed.setPrice(dec(100, 18))
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[500]))
    await priceFeed.setPrice(dec(200, 18))

    // Check all defaulters have pending rewards 
    for (account of _1_Defaulter) { assert.isTrue(await cdpManager.hasPendingRewards(account)) }

    // Whale opens cdp and fills SP with 1 billion EBTC
    const whale = accounts[999]
    await borrowerOperations.openCdp(dec(9, 28), whale, ZERO_ADDRESS, { from: whale, value: dec(1, 27) })
    await stabilityPool.provideToSP(dec(9, 28),ZERO_ADDRESS,  { from: whale })

    // Check SP has 9e28 EBTC
    const EBTCinSP = (await stabilityPool.getTotalEBTCDeposits()).toString()
    assert.equal(EBTCinSP, dec(9, 28))

    // Price drops, defaulters falls below MCR
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()

    // Check Recovery Mode is true
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    // Check defaulter ICRs are all between 100% and 110%
    for (account of _1_Defaulter) { assert.isTrue(await th.ICRbetween100and110(account, cdpManager, price)) }

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(1, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    // // Check Cdps are closed
    for (account of _1_Defaulter) { assert.isFalse(await sortedCdps.contains(account)) }

    // Check initial cdps with starting 10E/90EBTC, and whale's cdp, are still open
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }
    assert.isTrue(await sortedCdps.contains(whale))

    //Check EBTC in SP has decreased but is still > 0
    const EBTCinSP_After = await stabilityPool.getTotalEBTCDeposits()
    assert.isTrue(EBTCinSP_After.lt(web3.utils.toBN(dec(9, 28))))
    assert.isTrue(EBTCinSP_After.gt(web3.utils.toBN('0')))

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 2 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 2. All fully offset with Stability Pool. Has pending distribution rewards. In Recovery Mode'
    // 10 accts each open Cdp with 10 ether, withdraw 900 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(900, 18))
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }

    //2 accts open Cdp with 1 ether and withdraw 100 EBTC
    const _2_Defaulters = accounts.slice(1, 3)
    await th.openCdp_allAccounts(_2_Defaulters, contracts, dec(1, 'ether'), dec(60, 18))

    // Check all defaulters are active
    for (account of _2_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 opens with 1 ether and withdraws 110 EBTC
    await borrowerOperations.openCdp(dec(110, 18), accounts[500],ZERO_ADDRESS, { from: accounts[500], value: dec(1, 'ether') })
    assert.isTrue(await sortedCdps.contains(accounts[500]))

    // Account 500 is liquidated, creates pending distribution rewards for all
    await priceFeed.setPrice(dec(100, 18))
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[500]))
    await priceFeed.setPrice(dec(200, 18))

    // Check all defaulters have pending rewards 
    for (account of _2_Defaulters) { assert.isTrue(await cdpManager.hasPendingRewards(account)) }

    // Whale opens cdp and fills SP with 1 billion EBTC
    const whale = accounts[999]
    await borrowerOperations.openCdp(dec(9, 28), whale, ZERO_ADDRESS, { from: whale, value: dec(1, 27) })
    await stabilityPool.provideToSP(dec(9, 28), ZERO_ADDRESS,  { from: whale })

    // Check SP has 9e28 EBTC
    const EBTCinSP = (await stabilityPool.getTotalEBTCDeposits()).toString()
    assert.equal(EBTCinSP, dec(9, 28))

    // Price drops, defaulters falls below MCR
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()

    // Check Recovery Mode is true
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    // Check defaulter ICRs are all between 100% and 110%
    for (account of _2_Defaulters) { assert.isTrue(await th.ICRbetween100and110(account, cdpManager, price)) }

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(2, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    // Check Cdps are closed
    for (account of _2_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    // Check initial cdps with starting 10E/90EBTC, and whale's cdp, are still open
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }
    assert.isTrue(await sortedCdps.contains(whale))

    //Check EBTC in SP has decreased but is still > 0
    const EBTCinSP_After = await stabilityPool.getTotalEBTCDeposits()
    assert.isTrue(EBTCinSP_After.lt(web3.utils.toBN(dec(9, 28))))
    assert.isTrue(EBTCinSP_After.gt(web3.utils.toBN('0')))


    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 3 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 3. All fully offset with Stability Pool. Has pending distribution rewards. In Recovery Mode'
    // 10 accts each open Cdp with 10 ether, withdraw 900 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(900, 18))
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }

    //3 accts open Cdp with 1 ether and withdraw 100 EBTC
    const _3_Defaulters = accounts.slice(1, 4)
    await th.openCdp_allAccounts(_3_Defaulters, contracts, dec(1, 'ether'), dec(60, 18))

    // Check all defaulters are active
    for (account of _3_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 opens with 1 ether and withdraws 110 EBTC
    await borrowerOperations.openCdp(dec(110, 18), accounts[500],ZERO_ADDRESS, { from: accounts[500], value: dec(1, 'ether') })
    assert.isTrue(await sortedCdps.contains(accounts[500]))

    // Account 500 is liquidated, creates pending distribution rewards for all
    await priceFeed.setPrice(dec(100, 18))
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[500]))
    await priceFeed.setPrice(dec(200, 18))

    // Check all defaulters have pending rewards 
    for (account of _3_Defaulters) { assert.isTrue(await cdpManager.hasPendingRewards(account)) }

    // Whale opens cdp and fills SP with 1 billion EBTC
    const whale = accounts[999]
    await borrowerOperations.openCdp(dec(9, 28), whale,ZERO_ADDRESS, { from: whale, value: dec(1, 27) })
    await stabilityPool.provideToSP(dec(9, 28), ZERO_ADDRESS, { from: whale })

    // Check SP has 9e28 EBTC
    const EBTCinSP = (await stabilityPool.getTotalEBTCDeposits()).toString()
    assert.equal(EBTCinSP, dec(9, 28))

    // Price drops, defaulters falls below MCR
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()

    // Check Recovery Mode is true
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    // Check defaulter ICRs are all between 100% and 110%
    for (account of _3_Defaulters) { assert.isTrue(await th.ICRbetween100and110(account, cdpManager, price)) }

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(3, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    // Check Cdps are closed
    for (account of _3_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    // Check initial cdps with starting 10E/90EBTC, and whale's cdp, are still open
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }
    assert.isTrue(await sortedCdps.contains(whale))

    //Check EBTC in SP has decreased but is still > 0
    const EBTCinSP_After = await stabilityPool.getTotalEBTCDeposits()
    assert.isTrue(EBTCinSP_After.lt(web3.utils.toBN(dec(9, 28))))
    assert.isTrue(EBTCinSP_After.gt(web3.utils.toBN('0')))

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 5 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 5. All fully offset with Stability Pool. Has pending distribution rewards. In Recovery Mode'
    // 10 accts each open Cdp with 10 ether, withdraw 900 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(900, 18))
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }

    //5 accts open Cdp with 1 ether and withdraw 100 EBTC
    const _5_Defaulters = accounts.slice(1, 6)
    await th.openCdp_allAccounts(_5_Defaulters, contracts, dec(1, 'ether'), dec(60, 18))

    // Check all defaulters are active
    for (account of _5_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 opens with 1 ether and withdraws 110 EBTC
    await borrowerOperations.openCdp(dec(110, 18), accounts[500],ZERO_ADDRESS, { from: accounts[500], value: dec(1, 'ether') })
    assert.isTrue(await sortedCdps.contains(accounts[500]))

    // Account 500 is liquidated, creates pending distribution rewards for all
    await priceFeed.setPrice(dec(100, 18))
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[500]))
    await priceFeed.setPrice(dec(200, 18))

    // Check all defaulters have pending rewards 
    for (account of _5_Defaulters) { assert.isTrue(await cdpManager.hasPendingRewards(account)) }

    // Whale opens cdp and fills SP with 1 billion EBTC
    const whale = accounts[999]
    await borrowerOperations.openCdp(dec(9, 28), whale,ZERO_ADDRESS, { from: whale, value: dec(1, 27) })
    await stabilityPool.provideToSP(dec(9, 28), ZERO_ADDRESS, { from: whale })

    // Check SP has 9e28 EBTC
    const EBTCinSP = (await stabilityPool.getTotalEBTCDeposits()).toString()
    assert.equal(EBTCinSP, dec(9, 28))

    // Price drops, defaulters falls below MCR
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()

    // Check Recovery Mode is true
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    // Check defaulter ICRs are all between 100% and 110%
    for (account of _5_Defaulters) { assert.isTrue(await th.ICRbetween100and110(account, cdpManager, price)) }

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(5, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    // Check Cdps are closed
    for (account of _5_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    // Check initial cdps with starting 10E/90EBTC, and whale's cdp, are still open
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }
    assert.isTrue(await sortedCdps.contains(whale))

    //Check EBTC in SP has decreased but is still > 0
    const EBTCinSP_After = await stabilityPool.getTotalEBTCDeposits()
    assert.isTrue(EBTCinSP_After.lt(web3.utils.toBN(dec(9, 28))))
    assert.isTrue(EBTCinSP_After.gt(web3.utils.toBN('0')))

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 10 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 10. All fully offset with Stability Pool. Has pending distribution rewards. In Recovery Mode'
    // 10 accts each open Cdp with 10 ether, withdraw 900 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(900, 18))
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }

    //10 accts open Cdp with 1 ether and withdraw 100 EBTC
    const _10_Defaulters = accounts.slice(1, 11)
    await th.openCdp_allAccounts(_10_Defaulters, contracts, dec(1, 'ether'), dec(60, 18))

    // Check all defaulters are active
    for (account of _10_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 opens with 1 ether and withdraws 110 EBTC
    await borrowerOperations.openCdp(dec(110, 18), accounts[500],ZERO_ADDRESS, { from: accounts[500], value: dec(1, 'ether') })
    assert.isTrue(await sortedCdps.contains(accounts[500]))

    // Account 500 is liquidated, creates pending distribution rewards for all
    await priceFeed.setPrice(dec(100, 18))
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[500]))
    await priceFeed.setPrice(dec(200, 18))

    // Check all defaulters have pending rewards 
    for (account of _10_Defaulters) { assert.isTrue(await cdpManager.hasPendingRewards(account)) }

    // Whale opens cdp and fills SP with 1 billion EBTC
    const whale = accounts[999]
    await borrowerOperations.openCdp(dec(9, 28), whale,ZERO_ADDRESS, { from: whale, value: dec(1, 27) })
    await stabilityPool.provideToSP(dec(9, 28), ZERO_ADDRESS, { from: whale })

    // Check SP has 9e28 EBTC
    const EBTCinSP = (await stabilityPool.getTotalEBTCDeposits()).toString()
    assert.equal(EBTCinSP, dec(9, 28))

    // Price drops, defaulters falls below MCR
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()

    // Check Recovery Mode is true
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    // Check defaulter ICRs are all between 100% and 110%
    for (account of _10_Defaulters) { assert.isTrue(await th.ICRbetween100and110(account, cdpManager, price)) }

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(10, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    // Check Cdps are closed
    for (account of _10_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    // Check initial cdps with starting 10E/90EBTC, and whale's cdp, are still open
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }
    assert.isTrue(await sortedCdps.contains(whale))

    //Check EBTC in SP has decreased but is still > 0
    const EBTCinSP_After = await stabilityPool.getTotalEBTCDeposits()
    assert.isTrue(EBTCinSP_After.lt(web3.utils.toBN(dec(9, 28))))
    assert.isTrue(EBTCinSP_After.gt(web3.utils.toBN('0')))

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 20 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 20. All fully offset with Stability Pool. Has pending distribution rewards. In Recovery Mode'
    // 10 accts each open Cdp with 10 ether, withdraw 900 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(900, 18))
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }

    //20 accts open Cdp with 1 ether and withdraw 100 EBTC
    const _20_Defaulters = accounts.slice(1, 21)
    await th.openCdp_allAccounts(_20_Defaulters, contracts, dec(1, 'ether'), dec(60, 18))

    // Check all defaulters are active
    for (account of _20_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 opens with 1 ether and withdraws 110 EBTC
    await borrowerOperations.openCdp(dec(110, 18), accounts[500],ZERO_ADDRESS, { from: accounts[500], value: dec(1, 'ether') })
    assert.isTrue(await sortedCdps.contains(accounts[500]))

    // Account 500 is liquidated, creates pending distribution rewards for all
    await priceFeed.setPrice(dec(100, 18))
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[500]))
    await priceFeed.setPrice(dec(200, 18))

    // Check all defaulters have pending rewards 
    for (account of _20_Defaulters) { assert.isTrue(await cdpManager.hasPendingRewards(account)) }

    // Whale opens cdp and fills SP with 1 billion EBTC
    const whale = accounts[999]
    await borrowerOperations.openCdp(dec(9, 28), whale,ZERO_ADDRESS, { from: whale, value: dec(1, 27) })
    await stabilityPool.provideToSP(dec(9, 28), ZERO_ADDRESS, { from: whale })

    // Check SP has 9e28 EBTC
    const EBTCinSP = (await stabilityPool.getTotalEBTCDeposits()).toString()
    assert.equal(EBTCinSP, dec(9, 28))

    // Price drops, defaulters falls below MCR
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()

    // Check Recovery Mode is true
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    // Check defaulter ICRs are all between 100% and 110%
    for (account of _20_Defaulters) { assert.isTrue(await th.ICRbetween100and110(account, cdpManager, price)) }

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(20, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    // Check Cdps are closed
    for (account of _20_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    // Check initial cdps with starting 10E/90EBTC, and whale's cdp, are still open
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }
    assert.isTrue(await sortedCdps.contains(whale))

    //Check EBTC in SP has decreased but is still > 0
    const EBTCinSP_After = await stabilityPool.getTotalEBTCDeposits()
    assert.isTrue(EBTCinSP_After.lt(web3.utils.toBN(dec(9, 28))))
    assert.isTrue(EBTCinSP_After.gt(web3.utils.toBN('0')))

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 30 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 30. All fully offset with Stability Pool. Has pending distribution rewards. In Recovery Mode'
    // 10 accts each open Cdp with 10 ether, withdraw 900 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(900, 18))
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }

    //30 accts open Cdp with 1 ether and withdraw 100 EBTC
    const _30_Defaulters = accounts.slice(1, 31)
    await th.openCdp_allAccounts(_30_Defaulters, contracts, dec(1, 'ether'), dec(60, 18))

    // Check all defaulters are active
    for (account of _30_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 opens with 1 ether and withdraws 110 EBTC
    await borrowerOperations.openCdp(dec(110, 18), accounts[500],ZERO_ADDRESS, { from: accounts[500], value: dec(1, 'ether') })
    assert.isTrue(await sortedCdps.contains(accounts[500]))

    // Account 500 is liquidated, creates pending distribution rewards for all
    await priceFeed.setPrice(dec(100, 18))
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[500]))
    await priceFeed.setPrice(dec(200, 18))

    // Check all defaulters have pending rewards 
    for (account of _30_Defaulters) { assert.isTrue(await cdpManager.hasPendingRewards(account)) }

    // Whale opens cdp and fills SP with 1 billion EBTC
    const whale = accounts[999]
    await borrowerOperations.openCdp(dec(9, 28), whale,ZERO_ADDRESS, { from: whale, value: dec(1, 27) })
    await stabilityPool.provideToSP(dec(9, 28), ZERO_ADDRESS, { from: whale })

    // Check SP has 9e28 EBTC
    const EBTCinSP = (await stabilityPool.getTotalEBTCDeposits()).toString()
    assert.equal(EBTCinSP, dec(9, 28))

    // Price drops, defaulters falls below MCR
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()

    // Check Recovery Mode is true
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    // Check defaulter ICRs are all between 100% and 110%
    for (account of _30_Defaulters) { assert.isTrue(await th.ICRbetween100and110(account, cdpManager, price)) }

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(30, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    // Check Cdps are closed
    for (account of _30_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    // Check initial cdps with starting 10E/90EBTC, and whale's cdp, are still open
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }
    assert.isTrue(await sortedCdps.contains(whale))

    //Check EBTC in SP has decreased but is still > 0
    const EBTCinSP_After = await stabilityPool.getTotalEBTCDeposits()
    assert.isTrue(EBTCinSP_After.lt(web3.utils.toBN(dec(9, 28))))
    assert.isTrue(EBTCinSP_After.gt(web3.utils.toBN('0')))

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 40 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 40. All fully offset with Stability Pool. Has pending distribution rewards. In Recovery Mode'
    // 10 accts each open Cdp with 10 ether, withdraw 900 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(900, 18))
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }

    //40 accts open Cdp with 1 ether and withdraw 100 EBTC
    const _40_Defaulters = accounts.slice(1, 41)
    await th.openCdp_allAccounts(_40_Defaulters, contracts, dec(1, 'ether'), dec(60, 18))

    // Check all defaulters are active
    for (account of _40_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 opens with 1 ether and withdraws 110 EBTC
    await borrowerOperations.openCdp(dec(110, 18), accounts[500],ZERO_ADDRESS, { from: accounts[500], value: dec(1, 'ether') })
    assert.isTrue(await sortedCdps.contains(accounts[500]))

    // Account 500 is liquidated, creates pending distribution rewards for all
    await priceFeed.setPrice(dec(100, 18))
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[500]))
    await priceFeed.setPrice(dec(200, 18))

    // Check all defaulters have pending rewards 
    for (account of _40_Defaulters) { assert.isTrue(await cdpManager.hasPendingRewards(account)) }

    // Whale opens cdp and fills SP with 1 billion EBTC
    const whale = accounts[999]
    await borrowerOperations.openCdp(dec(9, 28), whale,ZERO_ADDRESS, { from: whale, value: dec(1, 27) })
    await stabilityPool.provideToSP(dec(9, 28), ZERO_ADDRESS, { from: whale })

    // Check SP has 9e28 EBTC
    const EBTCinSP = (await stabilityPool.getTotalEBTCDeposits()).toString()
    assert.equal(EBTCinSP, dec(9, 28))

    // Price drops, defaulters falls below MCR
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()

    // Check Recovery Mode is true
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    // Check defaulter ICRs are all between 100% and 110%
    for (account of _40_Defaulters) { assert.isTrue(await th.ICRbetween100and110(account, cdpManager, price)) }

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(40, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    // Check Cdps are closed
    for (account of _40_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    // Check initial cdps with starting 10E/90EBTC, and whale's cdp, are still open
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }
    assert.isTrue(await sortedCdps.contains(whale))

    //Check EBTC in SP has decreased but is still > 0
    const EBTCinSP_After = await stabilityPool.getTotalEBTCDeposits()
    assert.isTrue(EBTCinSP_After.lt(web3.utils.toBN(dec(9, 28))))
    assert.isTrue(EBTCinSP_After.gt(web3.utils.toBN('0')))

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 45 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 45. All fully offset with Stability Pool. Has pending distribution rewards. In Recovery Mode'
    // 10 accts each open Cdp
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(1000, 'ether'), dec(90000, 18))
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }

    //45 accts opens
    const _45_Defaulters = accounts.slice(1, 46)
    await th.openCdp_allAccounts(_45_Defaulters, contracts, dec(100, 'ether'), dec(9500, 18))

    // Check all defaulters are active
    for (account of _45_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 opens
    await borrowerOperations.openCdp(dec(11000, 18), accounts[500],ZERO_ADDRESS, { from: accounts[500], value: dec(100, 'ether') })
    assert.isTrue(await sortedCdps.contains(accounts[500]))

    // Account 500 is liquidated, creates pending distribution rewards for all
    await priceFeed.setPrice(dec(100, 18))
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[500]))
    await priceFeed.setPrice(dec(200, 18))

    // Check all defaulters have pending rewards 
    for (account of _45_Defaulters) { assert.isTrue(await cdpManager.hasPendingRewards(account)) }

    // Whale opens cdp and fills SP with 1 billion EBTC
    const whale = accounts[999]
    await borrowerOperations.openCdp(dec(9, 28), whale,ZERO_ADDRESS, { from: whale, value: dec(1, 27) })
    await stabilityPool.provideToSP(dec(9, 28), ZERO_ADDRESS, { from: whale })

    // Check SP has 9e28 EBTC
    const EBTCinSP = (await stabilityPool.getTotalEBTCDeposits()).toString()
    assert.equal(EBTCinSP, dec(9, 28))

    // Price drops, defaulters falls below MCR
    await priceFeed.setPrice(dec(100, 18))
    const price = await priceFeed.getPrice()

    // Check Recovery Mode is true
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    // Check defaulter ICRs are all between 100% and 110%
    for (account of _45_Defaulters) { assert.isTrue(await th.ICRbetween100and110(account, cdpManager, price)) }

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(45, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    // Check Cdps are closed
    for (account of _45_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    // Check initial cdps with starting 10E/90EBTC, and whale's cdp, are still open
    for (account of accounts.slice(101, 111)) { assert.isTrue(await sortedCdps.contains(account)) }
    assert.isTrue(await sortedCdps.contains(whale))

    //Check EBTC in SP has decreased but is still > 0
    const EBTCinSP_After = await stabilityPool.getTotalEBTCDeposits()
    assert.isTrue(EBTCinSP_After.lt(web3.utils.toBN(dec(9, 28))))
    assert.isTrue(EBTCinSP_After.gt(web3.utils.toBN('0')))

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // --- BatchLiquidateCdps ---

  // --- Pure redistribution, no offset. WITH pending distribution rewards ---

  // 10 cdps
  it("", async () => {
    const message = 'batchLiquidateCdps(). n = 10. Pure redistribution. Has pending distribution rewards.'
    // 10 accts each open Cdp with 10 ether, withdraws EBTC

    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(1000, 'ether'), dec(13000, 18))

    // Account 500 opens with 1 ether and withdraws EBTC
    await borrowerOperations.openCdp(dec(13000, 18), accounts[500],ZERO_ADDRESS, { from: accounts[500], value: dec(100, 'ether') })

    const _10_defaulters = accounts.slice(1, 11)
    // --- Accounts to be liquidated in the test tx ---
    await th.openCdp_allAccounts(_10_defaulters, contracts, dec(100, 'ether'), dec(13000, 18))

    // Check all defaulters active
    for (account of _10_defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 is liquidated, creates pending distribution rewards for all
    await priceFeed.setPrice(dec(100, 18))
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    await priceFeed.setPrice(dec(200, 18))

    // Price drops, account[1]'s ICR falls below MCR
    await priceFeed.setPrice(dec(100, 18))

    const tx = await cdpManager.batchLiquidateCdps(_10_defaulters, { from: accounts[0] })

    // Check all defaulters liquidated
    for (account of _10_defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 40 cdps
  it("", async () => {
    const message = 'batchLiquidateCdps(). n = 40. Pure redistribution. Has pending distribution rewards.'
    // 10 accts each open Cdp with 10 ether, withdraw 180 EBTC

    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(100, 'ether'), dec(13000, 18))

    // Account 500 opens with 1 ether and withdraws 180 EBTC
    await borrowerOperations.openCdp(dec(13000, 18), accounts[500], ZERO_ADDRESS,{ from: accounts[500], value: dec(100, 'ether') })


    // --- Accounts to be liquidated in the test tx ---
    const _40_defaulters = accounts.slice(1, 41)
    await th.openCdp_allAccounts(_40_defaulters, contracts, dec(100, 'ether'), dec(13000, 18))

    // Check all defaulters active
    for (account of _40_defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 is liquidated, creates pending distribution rewards for all
    await priceFeed.setPrice(dec(100, 18))
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    await priceFeed.setPrice(dec(200, 18))

    // Price drops, account[1]'s ICR falls below MCR
    await priceFeed.setPrice(dec(100, 18))

    const tx = await cdpManager.batchLiquidateCdps(_40_defaulters, { from: accounts[0] })

    // check all defaulters liquidated
    for (account of _40_defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 45 cdps
  it("", async () => {
    const message = 'batchLiquidateCdps(). n = 45. Pure redistribution. Has pending distribution rewards.'
    // 10 accts each open Cdp with 10 ether, withdraw 180 EBTC

    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(1000, 'ether'), dec(13000, 18))

    // Account 500 opens with 1 ether and withdraws 180 EBTC
    await borrowerOperations.openCdp(dec(13000, 18), accounts[500],ZERO_ADDRESS, { from: accounts[500], value: dec(100, 'ether') })

    // --- Accounts to be liquidated in the test tx ---
    const _45_defaulters = accounts.slice(1, 46)
    await th.openCdp_allAccounts(_45_defaulters, contracts, dec(100, 'ether'), dec(13000, 18))

    // check all defaulters active
    for (account of _45_defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 is liquidated, creates pending distribution rewards for all
    await priceFeed.setPrice(dec(100, 18))
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    await priceFeed.setPrice(dec(200, 18))

    // Price drops, account[1]'s ICR falls below MCR
    await priceFeed.setPrice(dec(100, 18))

    const tx = await cdpManager.batchLiquidateCdps(_45_defaulters, { from: accounts[0] })

    // check all defaulters liquidated
    for (account of _45_defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })


  // 50 cdps
  it("", async () => {
    const message = 'batchLiquidateCdps(). n = 50. Pure redistribution. Has pending distribution rewards.'
    // 10 accts each open Cdp with 10 ether, withdraw 180 EBTC

    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(100, 'ether'), dec(13000, 18))

    // Account 500 opens with 1 ether and withdraws 180 EBTC
    await borrowerOperations.openCdp(dec(13000, 18), accounts[500],ZERO_ADDRESS, { from: accounts[500], value: dec(100, 'ether') })

    // --- Accounts to be liquidated in the test tx ---
    const _50_defaulters = accounts.slice(1, 51)
    await th.openCdp_allAccounts(_50_defaulters, contracts, dec(100, 'ether'), dec(13000, 18))

    // check all defaulters active
    for (account of _50_defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 is liquidated, creates pending distribution rewards for all
    await priceFeed.setPrice(dec(100, 18))
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    await priceFeed.setPrice(dec(200, 18))

    // Price drops, account[1]'s ICR falls below MCR
    await priceFeed.setPrice(dec(100, 18))

    const tx = await cdpManager.batchLiquidateCdps(_50_defaulters, { from: accounts[0] })

    // check all defaulters liquidated
    for (account of _50_defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })


  // --- batchLiquidateCdps - pure offset with Stability Pool ---

  // 10 cdps
  it("", async () => {
    const message = 'batchLiquidateCdps(). n = 10. All cdps fully offset. Have pending distribution rewards'
    // 10 accts each open Cdp with 10 ether, withdraw 180 EBTC

    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(1000, 'ether'), dec(13000, 18))

    // Account 500 opens with 1 ether and withdraws 180 EBTC
    await borrowerOperations.openCdp(dec(13000, 18), accounts[500],ZERO_ADDRESS, { from: accounts[500], value: dec(100, 'ether') })

    const _10_defaulters = accounts.slice(1, 11)
    // --- Accounts to be liquidated in the test tx ---
    await th.openCdp_allAccounts(_10_defaulters, contracts, dec(100, 'ether'), dec(13000, 18))

    // Check all defaulters active
    for (account of _10_defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 is liquidated, creates pending distribution rewards for all
    await priceFeed.setPrice(dec(100, 18))
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    await priceFeed.setPrice(dec(200, 18))

    // Whale opens cdp and fills SP with 1 billion EBTC
    await borrowerOperations.openCdp(dec(1, 27), accounts[999],ZERO_ADDRESS, { from: accounts[999], value: dec(1, 27) })
    await stabilityPool.provideToSP(dec(1, 27), ZERO_ADDRESS, { from: accounts[999] })

    // Price drops, account[1]'s ICR falls below MCR
    await priceFeed.setPrice(dec(100, 18))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    const tx = await cdpManager.batchLiquidateCdps(_10_defaulters, { from: accounts[0] })

    // Check all defaulters liquidated
    for (account of _10_defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })


  // 40 cdps
  it("", async () => {
    const message = 'batchLiquidateCdps(). n = 40. All cdps fully offset. Have pending distribution rewards'
    // 10 accts each open Cdp with 10 ether, withdraw 180 EBTC

    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(100, 'ether'), dec(10000, 18))

    // Account 500 opens with 1 ether and withdraws 180 EBTC
    await borrowerOperations.openCdp(dec(13000, 18), accounts[500], ZERO_ADDRESS,{ from: accounts[500], value: dec(100, 'ether') })


    // --- Accounts to be liquidated in the test tx ---
    const _40_defaulters = accounts.slice(1, 41)
    await th.openCdp_allAccounts(_40_defaulters, contracts, dec(100, 'ether'), dec(13000, 18))

    // Check all defaulters active
    for (account of _40_defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 is liquidated, creates pending distribution rewards for all
    await priceFeed.setPrice(dec(100, 18))
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    await priceFeed.setPrice(dec(200, 18))

    // Whale opens cdp and fills SP with 1 billion EBTC
    await borrowerOperations.openCdp(dec(1, 27), accounts[999],ZERO_ADDRESS, { from: accounts[999], value: dec(1, 27) })
    await stabilityPool.provideToSP(dec(1, 27), ZERO_ADDRESS, { from: accounts[999] })


    // Price drops, account[1]'s ICR falls below MCR
    await priceFeed.setPrice(dec(100, 18))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    const tx = await cdpManager.batchLiquidateCdps(_40_defaulters, { from: accounts[0] })

    // check all defaulters liquidated
    for (account of _40_defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 45 cdps
  it("", async () => {
    const message = 'batchLiquidateCdps(). n = 45. All cdps fully offset. Have pending distribution rewards'
    // 10 accts each open Cdp with 10 ether, withdraw 180 EBTC

    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(100, 'ether'), dec(13000, 18))

    // Account 500 opens with 1 ether and withdraws 180 EBTC
    await borrowerOperations.openCdp(dec(13000, 18), accounts[500],ZERO_ADDRESS, { from: accounts[500], value: dec(100, 'ether') })

    // --- Accounts to be liquidated in the test tx ---
    const _45_defaulters = accounts.slice(1, 46)
    await th.openCdp_allAccounts(_45_defaulters, contracts, dec(100, 'ether'), dec(13000, 18))

    // check all defaulters active
    for (account of _45_defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 is liquidated, creates pending distribution rewards for all
    await priceFeed.setPrice(dec(100, 18))
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    await priceFeed.setPrice(dec(200, 18))

    // Whale opens cdp and fills SP with 1 billion EBTC
    await borrowerOperations.openCdp(dec(1, 27), accounts[999],ZERO_ADDRESS, { from: accounts[999], value: dec(1, 27) })
    await stabilityPool.provideToSP(dec(1, 27), ZERO_ADDRESS, { from: accounts[999] })


    // Price drops, account[1]'s ICR falls below MCR
    await priceFeed.setPrice(dec(100, 18))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    const tx = await cdpManager.batchLiquidateCdps(_45_defaulters, { from: accounts[0] })

    // check all defaulters liquidated
    for (account of _45_defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 50 cdps
  it("", async () => {
    const message = 'batchLiquidateCdps(). n = 50. All cdps fully offset. Have pending distribution rewards'
    // 10 accts each open Cdp with 10 ether, withdraw 180 EBTC

    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(100, 'ether'), dec(13000, 18))

    // Account 500 opens with 1 ether and withdraws 180 EBTC
    await borrowerOperations.openCdp(dec(13000, 18), accounts[500],ZERO_ADDRESS, { from: accounts[500], value: dec(100, 'ether') })

    // --- Accounts to be liquidated in the test tx ---
    const _50_defaulters = accounts.slice(1, 51)
    await th.openCdp_allAccounts(_50_defaulters, contracts, dec(100, 'ether'), dec(13000, 18))

    // check all defaulters active
    for (account of _50_defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 is liquidated, creates pending distribution rewards for all
    await priceFeed.setPrice(dec(100, 18))
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    await priceFeed.setPrice(dec(200, 18))

    // Whale opens cdp and fills SP with 1 billion EBTC
    await borrowerOperations.openCdp(dec(1, 27), accounts[999],ZERO_ADDRESS, { from: accounts[999], value: dec(1, 27) })
    await stabilityPool.provideToSP(dec(1, 27), ZERO_ADDRESS, { from: accounts[999] })


    // Price drops, account[1]'s ICR falls below MCR
    await priceFeed.setPrice(dec(100, 18))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)
    
    const tx = await cdpManager.batchLiquidateCdps(_50_defaulters, { from: accounts[0] })

    // check all defaulters liquidated
    for (account of _50_defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  it("Export test data", async () => {
    fs.writeFile('gasTest/outputs/liquidateCdpsGasData.csv', data, (err) => {
      if (err) { console.log(err) } else {
        console.log("LiquidateCdps() gas test data written to gasTest/outputs/liquidateCdpsGasData.csv")
      }
    })
  })
})