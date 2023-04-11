/* Script that logs gas costs for Liquity operations under various conditions. 

  Note: uses Mocha testing structure, but the purpose of each test is simply to print gas costs.

  'asserts' are only used to confirm the setup conditions.
*/
const fs = require('fs')

const deploymentHelper = require("../utils/deploymentHelpers.js")
const testHelpers = require("../utils/testHelpers.js")

const th = testHelpers.TestHelper
const timeValues = testHelpers.TimeValues
const dec = th.dec

const ZERO_ADDRESS = th.ZERO_ADDRESS
const _100pct = th._100pct

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
    contracts = await deploymentHelper.deployTesterContractsHardhat()
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

    functionCaller = contracts.functionCaller

    feeRecipient = LQTYContracts.feeRecipient

    await deploymentHelper.connectLQTYContracts(LQTYContracts)
    await deploymentHelper.connectCoreContracts(contracts, LQTYContracts)
    await deploymentHelper.connectLQTYContractsToCore(LQTYContracts, contracts)
  })

  // --- TESTS ---


  // --- liquidateCdps() -  pure redistributions ---

  // 1 cdp
  it("", async () => {
    const message = 'liquidateCdps(). n = 1. Pure redistribution'
    // 10 accts each open Cdp with 10 ether, withdraw 100 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(100, 18))

    //1 accts open Cdp with 1 ether and withdraw 100 EBTC
    const _1_Defaulter = accounts.slice(1, 2)
    await th.openCdp_allAccounts(_1_Defaulter, contracts, dec(1, 'ether'), dec(100, 18))

    // Check all defaulters are active
    for (account of _1_Defaulter) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 opens with 1 ether and withdraws 100 EBTC
    await borrowerOperations.openCdp(dec(110, 18), accounts[500], ZERO_ADDRESS, { from: accounts[500], value: dec(1, 'ether') })
    assert.isTrue(await sortedCdps.contains(accounts[500]))

    // Price drops, defaulters' cdps fall below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    // Account 500 is liquidated, creates pending distribution rewards for all
    await cdpManager.liquidateCdps(1, { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[500]))

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    const tx = await cdpManager.liquidateCdps(1, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check defaulters' cdps have been closed
    for (account of _1_Defaulter) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 2 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 2. Pure redistribution'
    // 10 accts each open Cdp with 10 ether, withdraw 100 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(100, 18))

    //2 accts open Cdp with 1 ether and withdraw 100 EBTC
    const _2_Defaulters = accounts.slice(1, 3)
    await th.openCdp_allAccounts(_2_Defaulters, contracts, dec(1, 'ether'), dec(100, 18))

    // Check all defaulters are active
    for (account of _2_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 opens with 1 ether and withdraws 110 EBTC
    await borrowerOperations.openCdp(dec(110, 18), accounts[500], ZERO_ADDRESS,{ from: accounts[500], value: dec(1, 'ether') })
    assert.isTrue(await sortedCdps.contains(accounts[500]))

    // Price drops, defaulters' cdps fall below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Account 500 is liquidated, creates pending distribution rewards for all
    await cdpManager.liquidateCdps(1, { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[500]))

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    const tx = await cdpManager.liquidateCdps(2, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check defaulters' cdps have been closed
    for (account of _2_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 3 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 3. Pure redistribution'
    // 10 accts each open Cdp with 10 ether, withdraw 100 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(100, 18))

    //3 accts open Cdp with 1 ether and withdraw 100 EBTC
    const _3_Defaulters = accounts.slice(1, 4)
    await th.openCdp_allAccounts(_3_Defaulters, contracts, dec(1, 'ether'), dec(100, 18))

    // Check all defaulters are active
    for (account of _3_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 opens with 1 ether and withdraws 100 EBTC
    await borrowerOperations.openCdp(dec(100, 18), accounts[500], ZERO_ADDRESS,{ from: accounts[500], value: dec(1, 'ether') })
    assert.isTrue(await sortedCdps.contains(accounts[500]))

    // Price drops, defaulters' cdps fall below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Account 500 is liquidated, creates pending distribution rewards for all
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[500]))

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    const tx = await cdpManager.liquidateCdps(3, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check defaulters' cdps have been closed
    for (account of _3_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 5 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 5. Pure redistribution'
    // 10 accts each open Cdp with 10 ether, withdraw 100 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(100, 18))

    //5 accts open Cdp with 1 ether and withdraw 100 EBTC
    const _5_Defaulters = accounts.slice(1, 6)
    await th.openCdp_allAccounts(_5_Defaulters, contracts, dec(1, 'ether'), dec(100, 18))

    // Check all defaulters are active
    for (account of _5_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 opens with 1 ether and withdraws 100 EBTC
    await borrowerOperations.openCdp(dec(100, 18), accounts[500],ZERO_ADDRESS, { from: accounts[500], value: dec(1, 'ether') })
    assert.isTrue(await sortedCdps.contains(accounts[500]))

    // Price drops, defaulters' cdps fall below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Account 500 is liquidated, creates pending distribution rewards for all
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[500]))

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    const tx = await cdpManager.liquidateCdps(5, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check defaulters' cdps have been closed
    for (account of _5_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 10 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 10. Pure redistribution'
    // 10 accts each open Cdp with 10 ether, withdraw 100 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(100, 18))

    //10 accts open Cdp with 1 ether and withdraw 100 EBTC
    const _10_Defaulters = accounts.slice(1, 11)
    await th.openCdp_allAccounts(_10_Defaulters, contracts, dec(1, 'ether'), dec(100, 18))

    // Check all defaulters are active
    for (account of _10_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 opens with 1 ether and withdraws 100 EBTC
    await borrowerOperations.openCdp(dec(100, 18), accounts[500], ZERO_ADDRESS,{ from: accounts[500], value: dec(1, 'ether') })
    assert.isTrue(await sortedCdps.contains(accounts[500]))

    // Price drops, defaulters' cdps fall below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Account 500 is liquidated, creates pending distribution rewards for all
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[500]))

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    const tx = await cdpManager.liquidateCdps(10, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check defaulters' cdps have been closed
    for (account of _10_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  //20 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 20. Pure redistribution'
    // 10 accts each open Cdp with 10 ether, withdraw 100 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(100, 18))

    //20 accts open Cdp with 1 ether and withdraw 100 EBTC
    const _20_Defaulters = accounts.slice(1, 21)
    await th.openCdp_allAccounts(_20_Defaulters, contracts, dec(1, 'ether'), dec(100, 18))

    // Check all defaulters are active
    for (account of _20_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 opens with 1 ether and withdraws 100 EBTC
    await borrowerOperations.openCdp(dec(100, 18), accounts[500],ZERO_ADDRESS, { from: accounts[500], value: dec(1, 'ether') })
    assert.isTrue(await sortedCdps.contains(accounts[500]))

    // Price drops, defaulters' cdps fall below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Account 500 is liquidated, creates pending distribution rewards for all
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[500]))

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    const tx = await cdpManager.liquidateCdps(20, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check defaulters' cdps have been closed
    for (account of _20_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 30 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 30. Pure redistribution'
    // 10 accts each open Cdp with 10 ether, withdraw 100 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(100, 18))

    //30 accts open Cdp with 1 ether and withdraw 100 EBTC
    const _30_Defaulters = accounts.slice(1, 31)
    await th.openCdp_allAccounts(_30_Defaulters, contracts, dec(1, 'ether'), dec(100, 18))

    // Check all defaulters are active
    for (account of _30_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 opens with 1 ether and withdraws 100 EBTC
    await borrowerOperations.openCdp(dec(100, 18), accounts[500], ZERO_ADDRESS,{ from: accounts[500], value: dec(1, 'ether') })
    assert.isTrue(await sortedCdps.contains(accounts[500]))

    // Price drops, defaulters' cdps fall below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Account 500 is liquidated, creates pending distribution rewards for all
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[500]))

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    const tx = await cdpManager.liquidateCdps(30, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check defaulters' cdps have been closed
    for (account of _30_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 40 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 40. Pure redistribution'
    // 10 accts each open Cdp with 10 ether, withdraw 100 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(100, 18))

    //40 accts open Cdp with 1 ether and withdraw 100 EBTC
    const _40_Defaulters = accounts.slice(1, 41)
    await th.openCdp_allAccounts(_40_Defaulters, contracts, dec(1, 'ether'), dec(100, 18))

    // Check all defaulters are active
    for (account of _40_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 opens with 1 ether and withdraws 100 EBTC
    await borrowerOperations.openCdp(dec(100, 18), accounts[500],ZERO_ADDRESS, { from: accounts[500], value: dec(1, 'ether') })
    assert.isTrue(await sortedCdps.contains(accounts[500]))

    // Price drops, defaulters' cdps fall below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Account 500 is liquidated, creates pending distribution rewards for all
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[500]))

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    const tx = await cdpManager.liquidateCdps(40, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check defaulters' cdps have been closed
    for (account of _40_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 45 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 45. Pure redistribution'
    // 10 accts each open Cdp with 10 ether, withdraw 100 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(100, 18))

    //45 accts open Cdp with 1 ether and withdraw 100 EBTC
    const _45_Defaulters = accounts.slice(1, 46)
    await th.openCdp_allAccounts(_45_Defaulters, contracts, dec(1, 'ether'), dec(100, 18))

    // Check all defaulters are active
    for (account of _45_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 opens with 1 ether and withdraws 100 EBTC
    await borrowerOperations.openCdp(dec(100, 18), accounts[500], ZERO_ADDRESS,{ from: accounts[500], value: dec(1, 'ether') })
    assert.isTrue(await sortedCdps.contains(accounts[500]))

    // Price drops, defaulters' cdps fall below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Account 500 is liquidated, creates pending distribution rewards for all
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[500]))

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    const tx = await cdpManager.liquidateCdps(45, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check defaulters' cdps have been closed
    for (account of _45_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 50 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 50. Pure redistribution'
    // 10 accts each open Cdp
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(1000, 'ether'), dec(10000, 18))

    //50 accts open Cdp
    const _50_Defaulters = accounts.slice(1, 51)
    await th.openCdp_allAccounts(_50_Defaulters, contracts, dec(100, 'ether'), dec(9500, 18))

    // Check all defaulters are active
    for (account of _50_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 opens
    await borrowerOperations.openCdp(dec(10000, 18), accounts[500],ZERO_ADDRESS, { from: accounts[500], value: dec(100, 'ether') })
    assert.isTrue(await sortedCdps.contains(accounts[500]))

    // Price drops, defaulters' cdps fall below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Account 500 is liquidated, creates pending distribution rewards for all
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[500]))

    const TCR = await cdpManager.getTCR(await priceFeed.getPrice())
    console.log(`TCR: ${TCR}`)
    
    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    const tx = await cdpManager.liquidateCdps(50, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check defaulters' cdps have been closed
    for (account of _50_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  it("", async () => {
    const message = 'liquidateCdps(). n = 60. Pure redistribution'
    // 10 accts each open Cdp with 10 ether, withdraw 100 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(100, 18))

    //60 accts open Cdp with 1 ether and withdraw 100 EBTC
    const _60_Defaulters = accounts.slice(1, 61)
    await th.openCdp_allAccounts(_60_Defaulters, contracts, dec(1, 'ether'), dec(100, 18))

    // Check all defaulters are active
    for (account of _60_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 opens with 1 ether and withdraws 100 EBTC
    await borrowerOperations.openCdp(dec(100, 18), accounts[500],ZERO_ADDRESS, { from: accounts[500], value: dec(1, 'ether') })
    assert.isTrue(await sortedCdps.contains(accounts[500]))

    // Price drops, defaulters' cdps fall below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Account 500 is liquidated, creates pending distribution rewards for all
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[500]))

    const TCR = await cdpManager.getTCR(await priceFeed.getPrice())
    console.log(`TCR: ${TCR}`)

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    const tx = await cdpManager.liquidateCdps(60, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check defaulters' cdps have been closed
    for (account of _60_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 65 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 65. Pure redistribution'
    // 10 accts each open Cdp with 15 ether, withdraw 100 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(15, 'ether'), dec(100, 18))

    //65 accts open Cdp with 1 ether and withdraw 100 EBTC
    const _65_Defaulters = accounts.slice(1, 66)
    await th.openCdp_allAccounts(_65_Defaulters, contracts, dec(1, 'ether'), dec(100, 18))

    // Check all defaulters are active
    for (account of _65_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 opens with 1 ether and withdraws 100 EBTC
    await borrowerOperations.openCdp(dec(100, 18), accounts[500], ZERO_ADDRESS,{ from: accounts[500], value: dec(1, 'ether') })
    assert.isTrue(await sortedCdps.contains(accounts[500]))

    // Price drops, defaulters' cdps fall below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Account 500 is liquidated, creates pending distribution rewards for all
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[500]))

    const TCR = await cdpManager.getTCR(await priceFeed.getPrice())
    console.log(`TCR: ${TCR}`)
    // 1451258961356880573
    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    const tx = await cdpManager.liquidateCdps(65, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check defaulters' cdps have been closed
    for (account of _65_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })



  // --- liquidate Cdps - all cdps offset by Stability Pool - no pending distribution rewards ---

  // 1 cdp
  it("", async () => {
    const message = 'liquidateCdps(). n = 1. All fully offset with Stability Pool. No pending distribution rewards.'
    // 10 accts each open Cdp with 10 ether, withdraw 100 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(100, 18))

    // Whale opens cdp and fills SP with 1 billion EBTC
    await borrowerOperations.openCdp(dec(1, 27), accounts[999],ZERO_ADDRESS, { from: accounts[999], value: dec(1, 27) })
    await stabilityPool.provideToSP(dec(1, 27), ZERO_ADDRESS, { from: accounts[999] })

    //1 acct opens Cdp with 1 ether and withdraw 100 EBTC
    const _1_Defaulter = accounts.slice(1, 2)
    await th.openCdp_allAccounts(_1_Defaulter, contracts, dec(1, 'ether'), dec(100, 18))

    // Check all defaulters are active
    for (account of _1_Defaulter) { assert.isTrue(await sortedCdps.contains(account)) }

    // Price drops, defaulters falls below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(1, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check Cdps are closed
    for (account of _1_Defaulter) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 2 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 2. All fully offset with Stability Pool. No pending distribution rewards.'
    // 10 accts each open Cdp with 10 ether, withdraw 100 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(100, 18))

    // Whale opens cdp and fills SP with 1 billion EBTC
    await borrowerOperations.openCdp(dec(1, 27), accounts[999],ZERO_ADDRESS, { from: accounts[999], value: dec(1, 27) })
    await stabilityPool.provideToSP(dec(1, 27), ZERO_ADDRESS, { from: accounts[999] })

    //2 accts open Cdp with 1 ether and withdraw 100 EBTC
    const _2_Defaulters = accounts.slice(1, 3)
    await th.openCdp_allAccounts(_2_Defaulters, contracts, dec(1, 'ether'), dec(100, 18))

    // Check all defaulters are active
    for (account of _2_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Price drops, defaulters falls below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(2, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check Cdps are closed
    for (account of _2_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 3 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 3. All fully offset with Stability Pool. No pending distribution rewards.'
    // 10 accts each open Cdp with 10 ether, withdraw 100 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(100, 18))

    // Whale opens cdp and fills SP with 1 billion EBTC
    await borrowerOperations.openCdp(dec(1, 27), accounts[999],ZERO_ADDRESS, { from: accounts[999], value: dec(1, 27) })
    await stabilityPool.provideToSP(dec(1, 27), ZERO_ADDRESS, { from: accounts[999] })

    //3 accts open Cdp with 1 ether and withdraw 100 EBTC
    const _3_Defaulters = accounts.slice(1, 4)
    await th.openCdp_allAccounts(_3_Defaulters, contracts, dec(1, 'ether'), dec(100, 18))

    // Check all defaulters are active
    for (account of _3_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Price drops, defaulters falls below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(3, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check Cdps are closed
    for (account of _3_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 5 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 5. All fully offset with Stability Pool. No pending distribution rewards.'
    // 10 accts each open Cdp with 10 ether, withdraw 100 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(100, 18))

    // Whale opens cdp and fills SP with 1 billion EBTC
    await borrowerOperations.openCdp(dec(1, 27), accounts[999], ZERO_ADDRESS,{ from: accounts[999], value: dec(1, 27) })
    await stabilityPool.provideToSP(dec(1, 27), ZERO_ADDRESS, { from: accounts[999] })

    //5 accts open Cdp with 1 ether and withdraw 100 EBTC
    const _5_Defaulters = accounts.slice(1, 6)
    await th.openCdp_allAccounts(_5_Defaulters, contracts, dec(1, 'ether'), dec(100, 18))

    // Check all defaulters are active
    for (account of _5_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Price drops, defaulters falls below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(5, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check Cdps are closed
    for (account of _5_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 10 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 10. All fully offset with Stability Pool. No pending distribution rewards.'
    // 10 accts each open Cdp with 10 ether, withdraw 100 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(100, 18))

    // Whale opens cdp and fills SP with 1 billion EBTC
    await borrowerOperations.openCdp(dec(1, 27), accounts[999], ZERO_ADDRESS,{ from: accounts[999], value: dec(1, 27) })
    await stabilityPool.provideToSP(dec(1, 27), ZERO_ADDRESS, { from: accounts[999] })

    //10 accts open Cdp with 1 ether and withdraw 100 EBTC
    const _10_Defaulters = accounts.slice(1, 11)
    await th.openCdp_allAccounts(_10_Defaulters, contracts, dec(1, 'ether'), dec(100, 18))

    // Check all defaulters are active
    for (account of _10_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Price drops, defaulters falls below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(10, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check Cdps are closed
    for (account of _10_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 20 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 20. All fully offset with Stability Pool. No pending distribution rewards.'
    // 10 accts each open Cdp with 10 ether, withdraw 100 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(100, 18))

    // Whale opens cdp and fills SP with 1 billion EBTC
    await borrowerOperations.openCdp(dec(1, 27), accounts[999],ZERO_ADDRESS, { from: accounts[999], value: dec(1, 27) })
    await stabilityPool.provideToSP(dec(1, 27), ZERO_ADDRESS, { from: accounts[999] })

    //20 accts open Cdp with 1 ether and withdraw 100 EBTC
    const _20_Defaulters = accounts.slice(1, 21)
    await th.openCdp_allAccounts(_20_Defaulters, contracts, dec(1, 'ether'), dec(100, 18))

    // Check all defaulters are active
    for (account of _20_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Price drops, defaulters falls below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(20, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check Cdps are closed
    for (account of _20_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })


  // 30 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 30. All fully offset with Stability Pool. No pending distribution rewards.'
    // 10 accts each open Cdp with 10 ether, withdraw 100 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(100, 18))

    // Whale opens cdp and fills SP with 1 billion EBTC
    await borrowerOperations.openCdp(dec(1, 27), accounts[999],ZERO_ADDRESS, { from: accounts[999], value: dec(1, 27) })
    await stabilityPool.provideToSP(dec(1, 27), ZERO_ADDRESS, { from: accounts[999] })

    //30 accts open Cdp with 1 ether and withdraw 100 EBTC
    const _30_Defaulters = accounts.slice(1, 31)
    await th.openCdp_allAccounts(_30_Defaulters, contracts, dec(1, 'ether'), dec(100, 18))

    // Check all defaulters are active
    for (account of _30_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Price drops, defaulters falls below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(30, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check Cdps are closed
    for (account of _30_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 40 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 40. All fully offset with Stability Pool. No pending distribution rewards.'
    // 10 accts each open Cdp with 10 ether, withdraw 100 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(100, 18))

    // Whale opens cdp and fills SP with 1 billion EBTC
    await borrowerOperations.openCdp(dec(1, 27), accounts[999],ZERO_ADDRESS, { from: accounts[999], value: dec(1, 27) })
    await stabilityPool.provideToSP(dec(1, 27), ZERO_ADDRESS, { from: accounts[999] })

    //40 accts open Cdp with 1 ether and withdraw 100 EBTC
    const _40_Defaulters = accounts.slice(1, 41)
    await th.openCdp_allAccounts(_40_Defaulters, contracts, dec(1, 'ether'), dec(100, 18))

    // Check all defaulters are active
    for (account of _40_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Price drops, defaulters falls below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(40, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check Cdps are closed
    for (account of _40_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 50 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 50. All fully offset with Stability Pool. No pending distribution rewards.'
    // 10 accts each open Cdp with 10 ether, withdraw 100 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(1000, 'ether'), dec(10000, 18))

    // Whale opens cdp and fills SP with 1 billion EBTC
    await borrowerOperations.openCdp(dec(1, 27), accounts[999],ZERO_ADDRESS, { from: accounts[999], value: dec(1, 27) })
    await stabilityPool.provideToSP(dec(1, 27), ZERO_ADDRESS, { from: accounts[999] })

    //50 accts open Cdp with 1 ether and withdraw 100 EBTC
    const _50_Defaulters = accounts.slice(1, 51)
    await th.openCdp_allAccounts(_50_Defaulters, contracts, dec(100, 'ether'), dec(9500, 18))

    // Check all defaulters are active
    for (account of _50_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Price drops, defaulters falls below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(50, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check Cdps are closed
    for (account of _50_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 55 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 55. All fully offset with Stability Pool. No pending distribution rewards.'
    // 10 accts each open Cdp with 10 ether, withdraw 100 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(100, 18))

    // Whale opens cdp and fills SP with 1 billion EBTC
    await borrowerOperations.openCdp(dec(1, 27), accounts[999],ZERO_ADDRESS, { from: accounts[999], value: dec(1, 27) })
    await stabilityPool.provideToSP(dec(1, 27), ZERO_ADDRESS, { from: accounts[999] })

    //50 accts open Cdp with 1 ether and withdraw 100 EBTC
    const _55_Defaulters = accounts.slice(1, 56)
    await th.openCdp_allAccounts(_55_Defaulters, contracts, dec(1, 'ether'), dec(100, 18))

    // Check all defaulters are active
    for (account of _55_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Price drops, defaulters falls below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(55, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check Cdps are closed
    for (account of _55_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })


  // --- liquidate Cdps - all cdps offset by Stability Pool - Has pending distribution rewards ---

  // 1 cdp
  it("", async () => {
    const message = 'liquidateCdps(). n = 1. All fully offset with Stability Pool. Has pending distribution rewards.'
    // 10 accts each open Cdp with 10 ether, withdraw 100 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(100, 18))

    // Account 500 opens with 1 ether and withdraws 100 EBTC
    await borrowerOperations.openCdp(dec(100, 18), accounts[500],ZERO_ADDRESS, { from: accounts[500], value: dec(1, 'ether') })
    assert.isTrue(await sortedCdps.contains(accounts[500]))

    // --- 1 Accounts to be liquidated in the test tx --
    const _1_Defaulter = accounts.slice(1, 2)
    await th.openCdp_allAccounts(_1_Defaulter, contracts, dec(1, 'ether'), dec(100, 18))

    // Check all defaulters active
    for (account of _1_Defaulter) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 is liquidated, creates pending distribution rewards for all
    await priceFeed.setPrice(dec(100, 18))
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[500]))
    await priceFeed.setPrice(dec(200, 18))

    // Whale opens cdp and fills SP with 1 billion EBTC
    await borrowerOperations.openCdp(dec(1, 27), accounts[999],ZERO_ADDRESS, { from: accounts[999], value: dec(1, 27) })
    await stabilityPool.provideToSP(dec(1, 27), ZERO_ADDRESS, { from: accounts[999] })
    assert.equal((await stabilityPool.getTotalEBTCDeposits()), dec(1, 27))

    // Price drops, defaulters' ICR fall below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(1, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check all defaulters liquidated
    for (account of _1_Defaulter) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 2 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 2. All fully offset with Stability Pool. Has pending distribution rewards.'
    // 10 accts each open Cdp with 10 ether, withdraw 100 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(100, 18))

    // Account 500 opens with 1 ether and withdraws 100 EBTC
    await borrowerOperations.openCdp(dec(100, 18), accounts[500],ZERO_ADDRESS, { from: accounts[500], value: dec(1, 'ether') })
    assert.isTrue(await sortedCdps.contains(accounts[500]))

    // --- 2 Accounts to be liquidated in the test tx --
    const _2_Defaulters = accounts.slice(1, 3)
    await th.openCdp_allAccounts(_2_Defaulters, contracts, dec(1, 'ether'), dec(100, 18))

    // Check all defaulters active
    for (account of _2_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 is liquidated, creates pending distribution rewards for all
    await priceFeed.setPrice(dec(100, 18))
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[500]))
    await priceFeed.setPrice(dec(200, 18))

    // Whale opens cdp and fills SP with 1 billion EBTC
    await borrowerOperations.openCdp(dec(1, 27), accounts[999], ZERO_ADDRESS,{ from: accounts[999], value: dec(1, 27) })
    await stabilityPool.provideToSP(dec(1, 27), ZERO_ADDRESS, { from: accounts[999] })
    assert.equal((await stabilityPool.getTotalEBTCDeposits()), dec(1, 27))

    // Price drops, defaulters' ICR fall below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(2, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check all defaulters liquidated
    for (account of _2_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 3 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 3. All fully offset with Stability Pool. Has pending distribution rewards.'
    // 10 accts each open Cdp with 10 ether, withdraw 100 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(100, 18))

    // Account 500 opens with 1 ether and withdraws 100 EBTC
    await borrowerOperations.openCdp(dec(100, 18), accounts[500],ZERO_ADDRESS, { from: accounts[500], value: dec(1, 'ether') })
    assert.isTrue(await sortedCdps.contains(accounts[500]))

    // --- 3 Accounts to be liquidated in the test tx --
    const _3_Defaulters = accounts.slice(1, 4)
    await th.openCdp_allAccounts(_3_Defaulters, contracts, dec(1, 'ether'), dec(100, 18))

    // Check all defaulters active
    for (account of _3_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 is liquidated, creates pending distribution rewards for all
    await priceFeed.setPrice(dec(100, 18))
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[500]))
    await priceFeed.setPrice(dec(200, 18))

    // Whale opens cdp and fills SP with 1 billion EBTC
    await borrowerOperations.openCdp(dec(1, 27), accounts[999],ZERO_ADDRESS, { from: accounts[999], value: dec(1, 27) })
    await stabilityPool.provideToSP(dec(1, 27), ZERO_ADDRESS, { from: accounts[999] })
    assert.equal((await stabilityPool.getTotalEBTCDeposits()), dec(1, 27))

    // Price drops, defaulters' ICR fall below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(3, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check all defaulters liquidated
    for (account of _3_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 5 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 5. All fully offset with Stability Pool. Has pending distribution rewards.'
    // 10 accts each open Cdp with 10 ether, withdraw 100 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(100, 18))

    // Account 500 opens with 1 ether and withdraws 100 EBTC
    await borrowerOperations.openCdp(dec(100, 18), accounts[500],ZERO_ADDRESS, { from: accounts[500], value: dec(1, 'ether') })
    assert.isTrue(await sortedCdps.contains(accounts[500]))

    // --- 5 Accounts to be liquidated in the test tx --
    const _5_Defaulters = accounts.slice(1, 6)
    await th.openCdp_allAccounts(_5_Defaulters, contracts, dec(1, 'ether'), dec(100, 18))

    // Check all defaulters active
    for (account of _5_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 is liquidated, creates pending distribution rewards for all
    await priceFeed.setPrice(dec(100, 18))
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[500]))
    await priceFeed.setPrice(dec(200, 18))

    // Whale opens cdp and fills SP with 1 billion EBTC
    await borrowerOperations.openCdp(dec(1, 27), accounts[999],ZERO_ADDRESS, { from: accounts[999], value: dec(1, 27) })
    await stabilityPool.provideToSP(dec(1, 27), ZERO_ADDRESS, { from: accounts[999] })
    assert.equal((await stabilityPool.getTotalEBTCDeposits()), dec(1, 27))

    // Price drops, defaulters' ICR fall below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(5, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check all defaulters liquidated
    for (account of _5_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 10 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 10. All fully offset with Stability Pool. Has pending distribution rewards.'
    // 10 accts each open Cdp with 10 ether, withdraw 100 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(100, 18))

    // Account 500 opens with 1 ether and withdraws 100 EBTC
    await borrowerOperations.openCdp(dec(100, 18), accounts[500], ZERO_ADDRESS,{ from: accounts[500], value: dec(1, 'ether') })
    assert.isTrue(await sortedCdps.contains(accounts[500]))

    // --- 10 Accounts to be liquidated in the test tx --
    const _10_Defaulters = accounts.slice(1, 11)
    await th.openCdp_allAccounts(_10_Defaulters, contracts, dec(1, 'ether'), dec(100, 18))

    // Check all defaulters active
    for (account of _10_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 is liquidated, creates pending distribution rewards for all
    await priceFeed.setPrice(dec(100, 18))
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[500]))
    await priceFeed.setPrice(dec(200, 18))

    // Whale opens cdp and fills SP with 1 billion EBTC
    await borrowerOperations.openCdp(dec(1, 27), accounts[999],ZERO_ADDRESS, { from: accounts[999], value: dec(1, 27) })
    await stabilityPool.provideToSP(dec(1, 27), ZERO_ADDRESS, { from: accounts[999] })
    assert.equal((await stabilityPool.getTotalEBTCDeposits()), dec(1, 27))

    // Price drops, defaulters' ICR fall below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(10, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check all defaulters liquidated
    for (account of _10_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 20 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 20. All fully offset with Stability Pool. Has pending distribution rewards.'
    // 10 accts each open Cdp with 10 ether, withdraw 100 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(100, 18))

    // Account 500 opens with 1 ether and withdraws 100 EBTC
    await borrowerOperations.openCdp(dec(100, 18), accounts[500],ZERO_ADDRESS, { from: accounts[500], value: dec(1, 'ether') })
    assert.isTrue(await sortedCdps.contains(accounts[500]))

    // --- 20 Accounts to be liquidated in the test tx --
    const _20_Defaulters = accounts.slice(1, 21)
    await th.openCdp_allAccounts(_20_Defaulters, contracts, dec(1, 'ether'), dec(100, 18))

    // Check all defaulters active
    for (account of _20_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 is liquidated, creates pending distribution rewards for all
    await priceFeed.setPrice(dec(100, 18))
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[500]))
    await priceFeed.setPrice(dec(200, 18))

    // Whale opens cdp and fills SP with 1 billion EBTC
    await borrowerOperations.openCdp(dec(1, 27), accounts[999],ZERO_ADDRESS, { from: accounts[999], value: dec(1, 27) })
    await stabilityPool.provideToSP(dec(1, 27), ZERO_ADDRESS, { from: accounts[999] })
    assert.equal((await stabilityPool.getTotalEBTCDeposits()), dec(1, 27))

    // Price drops, defaulters' ICR fall below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(20, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check all defaulters liquidated
    for (account of _20_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 30 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 30. All fully offset with Stability Pool. Has pending distribution rewards.'
    // 10 accts each open Cdp with 10 ether, withdraw 100 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(100, 18))

    // Account 500 opens with 1 ether and withdraws 100 EBTC
    await borrowerOperations.openCdp(dec(100, 18), accounts[500],ZERO_ADDRESS, { from: accounts[500], value: dec(1, 'ether') })
    assert.isTrue(await sortedCdps.contains(accounts[500]))

    // --- 30 Accounts to be liquidated in the test tx --
    const _30_Defaulters = accounts.slice(1, 31)
    await th.openCdp_allAccounts(_30_Defaulters, contracts, dec(1, 'ether'), dec(100, 18))

    // Check all defaulters active
    for (account of _30_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 is liquidated, creates pending distribution rewards for all
    await priceFeed.setPrice(dec(100, 18))
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[500]))
    await priceFeed.setPrice(dec(200, 18))

    // Whale opens cdp and fills SP with 1 billion EBTC
    await borrowerOperations.openCdp(dec(1, 27), accounts[999],ZERO_ADDRESS, { from: accounts[999], value: dec(1, 27) })
    await stabilityPool.provideToSP(dec(1, 27), ZERO_ADDRESS, { from: accounts[999] })
    assert.equal((await stabilityPool.getTotalEBTCDeposits()), dec(1, 27))

    // Price drops, defaulters' ICR fall below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(30, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check all defaulters liquidated
    for (account of _30_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 40 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 40. All fully offset with Stability Pool. Has pending distribution rewards.'
    // 10 accts each open Cdp with 10 ether, withdraw 100 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(100, 18))

    // Account 500 opens with 1 ether and withdraws 100 EBTC
    await borrowerOperations.openCdp(dec(100, 18), accounts[500],ZERO_ADDRESS, { from: accounts[500], value: dec(1, 'ether') })
    assert.isTrue(await sortedCdps.contains(accounts[500]))

    // --- 40 Accounts to be liquidated in the test tx --
    const _40_Defaulters = accounts.slice(1, 41)
    await th.openCdp_allAccounts(_40_Defaulters, contracts, dec(1, 'ether'), dec(100, 18))

    // Check all defaulters active
    for (account of _40_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 is liquidated, creates pending distribution rewards for all
    await priceFeed.setPrice(dec(100, 18))
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[500]))
    await priceFeed.setPrice(dec(200, 18))

    // Whale opens cdp and fills SP with 1 billion EBTC
    await borrowerOperations.openCdp(dec(1, 27), accounts[999],ZERO_ADDRESS, { from: accounts[999], value: dec(1, 27) })
    await stabilityPool.provideToSP(dec(1, 27), ZERO_ADDRESS, { from: accounts[999] })
    assert.equal((await stabilityPool.getTotalEBTCDeposits()), dec(1, 27))

    // Price drops, defaulters' ICR fall below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(40, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check all defaulters liquidated
    for (account of _40_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })


  // 45 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 45. All fully offset with Stability Pool. Has pending distribution rewards.'
    // 10 accts each open Cdp with 10 ether, withdraw 100 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(10, 'ether'), dec(100, 18))

    // Account 500 opens with 1 ether and withdraws 100 EBTC
    await borrowerOperations.openCdp(dec(100, 18), accounts[500],ZERO_ADDRESS, { from: accounts[500], value: dec(1, 'ether') })
    assert.isTrue(await sortedCdps.contains(accounts[500]))

    // --- 50 Accounts to be liquidated in the test tx --
    const _45_Defaulters = accounts.slice(1, 46)
    await th.openCdp_allAccounts(_45_Defaulters, contracts, dec(1, 'ether'), dec(100, 18))

    // Check all defaulters active
    for (account of _45_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 is liquidated, creates pending distribution rewards for all
    await priceFeed.setPrice(dec(100, 18))
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[500]))
    await priceFeed.setPrice(dec(200, 18))

    // Whale opens cdp and fills SP with 1 billion EBTC
    await borrowerOperations.openCdp(dec(1, 27), accounts[999],ZERO_ADDRESS, { from: accounts[999], value: dec(1, 27) })
    await stabilityPool.provideToSP(dec(1, 27), ZERO_ADDRESS, { from: accounts[999] })
    assert.equal((await stabilityPool.getTotalEBTCDeposits()), dec(1, 27))

    // Price drops, defaulters' ICR fall below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(45, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check all defaulters liquidated
    for (account of _45_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 50 cdps
  it("", async () => {
    const message = 'liquidateCdps(). n = 50. All fully offset with Stability Pool. Has pending distribution rewards.'
    // 10 accts each open Cdp with 10 ether, withdraw 100 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(1000, 'ether'), dec(10000, 18))

    // Account 500 opens with 1 ether and withdraws 100 EBTC
    await borrowerOperations.openCdp(dec(10000, 18), accounts[500], ZERO_ADDRESS,{ from: accounts[500], value: dec(100, 'ether') })
    assert.isTrue(await sortedCdps.contains(accounts[500]))

    // --- 50 Accounts to be liquidated in the test tx --
    const _50_Defaulters = accounts.slice(1, 51)
    await th.openCdp_allAccounts(_50_Defaulters, contracts, dec(100, 'ether'), dec(9500, 18))

    // Check all defaulters active
    for (account of _50_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 is liquidated, creates pending distribution rewards for all
    await priceFeed.setPrice(dec(100, 18))
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[500]))
    await priceFeed.setPrice(dec(200, 18))

    // Whale opens cdp and fills SP with 1 billion EBTC
    await borrowerOperations.openCdp(dec(1, 27), accounts[999],ZERO_ADDRESS, { from: accounts[999], value: dec(1, 27) })
    await stabilityPool.provideToSP(dec(1, 27), ZERO_ADDRESS, { from: accounts[999] })
    assert.equal((await stabilityPool.getTotalEBTCDeposits()), dec(1, 27))

    // Price drops, defaulters' ICR fall below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(50, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check all defaulters liquidated
    for (account of _50_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // --- batchLiquidateCdps ---

  // ---batchLiquidateCdps(): Pure redistribution ---
  it("", async () => {
    const message = 'batchLiquidateCdps(). batch size = 10. Pure redistribution'
    // 10 accts each open Cdp with 10 ether, withdraw 100 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(200, 'ether'), dec(2000, 18))

    //10 accts open Cdp with 1 ether and withdraw 100 EBTC
    const _10_Defaulters = accounts.slice(1, 11)
    await th.openCdp_allAccounts(_10_Defaulters, contracts, dec(20, 'ether'), dec(2000, 18))

    // Check all defaulters are active
    for (account of _10_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 opens with 1 ether and withdraws 100 EBTC
    await borrowerOperations.openCdp(dec(2000, 18), accounts[500],ZERO_ADDRESS, { from: accounts[500], value: dec(20, 'ether') })
    assert.isTrue(await sortedCdps.contains(accounts[500]))

    // Price drops, defaulters' cdps fall below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Account 500 is liquidated, creates pending distribution rewards for all
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[500]))

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    const tx = await cdpManager.batchLiquidateCdps(_10_Defaulters, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check defaulters' cdps have been closed
    for (account of _10_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  it("", async () => {
    const message = 'batchLiquidateCdps(). batch size = 50. Pure redistribution'
    // 10 accts each open Cdp with 10 ether, withdraw 100 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(200, 'ether'), dec(2000, 18))

    //50 accts open Cdp with 1 ether and withdraw 100 EBTC
    const _50_Defaulters = accounts.slice(1, 51)
    await th.openCdp_allAccounts(_50_Defaulters, contracts, dec(20, 'ether'), dec(2000, 18))

    // Check all defaulters are active
    for (account of _50_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 opens with 1 ether and withdraws 100 EBTC
    await borrowerOperations.openCdp(dec(2000, 18), accounts[500],ZERO_ADDRESS, { from: accounts[500], value: dec(20, 'ether') })
    assert.isTrue(await sortedCdps.contains(accounts[500]))

    // Price drops, defaulters' cdps fall below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Account 500 is liquidated, creates pending distribution rewards for all
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[500]))

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    const tx = await cdpManager.batchLiquidateCdps(_50_Defaulters, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check defaulters' cdps have been closed
    for (account of _50_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // ---batchLiquidateCdps(): Full SP offset, no pending rewards ---

  // 10 cdps
  it("", async () => {
    const message = 'batchLiquidateCdps(). batch size = 10. All fully offset with Stability Pool. No pending distribution rewards.'
    // 10 accts each open Cdp with 10 ether, withdraw 100 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(200, 'ether'), dec(2000, 18))

    // Whale opens cdp and fills SP with 1 billion EBTC
    await borrowerOperations.openCdp(dec(1, 27), accounts[999],ZERO_ADDRESS, { from: accounts[999], value: dec(1, 27) })
    await stabilityPool.provideToSP(dec(1, 27), ZERO_ADDRESS, { from: accounts[999] })

    //10 accts open Cdp with 1 ether and withdraw 100 EBTC
    const _10_Defaulters = accounts.slice(1, 11)
    await th.openCdp_allAccounts(_10_Defaulters, contracts, dec(20, 'ether'), dec(2000, 18))

    // Check all defaulters are active
    for (account of _10_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Price drops, defaulters falls below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.batchLiquidateCdps(_10_Defaulters, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check Cdps are closed
    for (account of _10_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  it("", async () => {
    const message = 'batchLiquidateCdps(). batch size = 50. All fully offset with Stability Pool. No pending distribution rewards.'
    // 10 accts each open Cdp with 10 ether, withdraw 100 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(200, 'ether'), dec(2000, 18))

    // Whale opens cdp and fills SP with 1 billion EBTC
    await borrowerOperations.openCdp(dec(1, 27), accounts[999], ZERO_ADDRESS,{ from: accounts[999], value: dec(1, 27) })
    await stabilityPool.provideToSP(dec(1, 27), ZERO_ADDRESS, { from: accounts[999] })

    //50 accts open Cdp with 1 ether and withdraw 100 EBTC
    const _50_Defaulters = accounts.slice(1, 51)
    await th.openCdp_allAccounts(_50_Defaulters, contracts, dec(20, 'ether'), dec(2000, 18))

    // Check all defaulters are active
    for (account of _50_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Price drops, defaulters falls below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.batchLiquidateCdps(_50_Defaulters, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check Cdps are closed
    for (account of _50_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })


  // ---batchLiquidateCdps(): Full SP offset, HAS pending rewards ---

  it("", async () => {
    const message = 'batchLiquidateCdps(). batch size = 10. All fully offset with Stability Pool. Has pending distribution rewards.'
    // 10 accts each open Cdp with 10 ether, withdraw 100 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(200, 'ether'), dec(2000, 18))

    // Account 500 opens with 1 ether and withdraws 100 EBTC
    await borrowerOperations.openCdp(dec(2000, 18), accounts[500],ZERO_ADDRESS, { from: accounts[500], value: dec(20, 'ether') })
    assert.isTrue(await sortedCdps.contains(accounts[500]))

    // --- 10 Accounts to be liquidated in the test tx --
    const _10_Defaulters = accounts.slice(1, 11)
    await th.openCdp_allAccounts(_10_Defaulters, contracts, dec(20, 'ether'), dec(2000, 18))

    // Check all defaulters active
    for (account of _10_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 is liquidated, creates pending distribution rewards for all
    await priceFeed.setPrice(dec(100, 18))
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[500]))
    await priceFeed.setPrice(dec(200, 18))

    // Whale opens cdp and fills SP with 1 billion EBTC
    await borrowerOperations.openCdp(dec(1, 27), accounts[999],ZERO_ADDRESS, { from: accounts[999], value: dec(1, 27) })
    await stabilityPool.provideToSP(dec(1, 27), ZERO_ADDRESS, { from: accounts[999] })
    assert.equal((await stabilityPool.getTotalEBTCDeposits()), dec(1, 27))

    // Price drops, defaulters' ICR fall below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.batchLiquidateCdps(_10_Defaulters, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check all defaulters liquidated
    for (account of _10_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  it("", async () => {
    const message = 'batchLiquidateCdps(). batch size = 50. All fully offset with Stability Pool. Has pending distribution rewards.'
    // 10 accts each open Cdp with 10 ether, withdraw 2000 EBTC
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(200, 'ether'), dec(2000, 18))

    // Account 500 opens with 1 ether and withdraws 2000 EBTC
    await borrowerOperations.openCdp(dec(2000, 18), accounts[500],ZERO_ADDRESS, { from: accounts[500], value: dec(20, 'ether') })
    assert.isTrue(await sortedCdps.contains(accounts[500]))

    // --- 50 Accounts to be liquidated in the test tx --
    const _50_Defaulters = accounts.slice(1, 51)
    await th.openCdp_allAccounts(_50_Defaulters, contracts, dec(20, 'ether'), dec(2000, 18))

    // Check all defaulters active
    for (account of _50_Defaulters) { assert.isTrue(await sortedCdps.contains(account)) }

    // Account 500 is liquidated, creates pending distribution rewards for all
    await priceFeed.setPrice(dec(100, 18))
    await cdpManager.liquidate(accounts[500], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[500]))
    await priceFeed.setPrice(dec(200, 18))

    // Whale opens cdp and fills SP with 1 billion EBTC
    await borrowerOperations.openCdp(dec(1, 27), accounts[999],ZERO_ADDRESS, { from: accounts[999], value: dec(1, 27) })
    await stabilityPool.provideToSP(dec(1, 27), ZERO_ADDRESS, { from: accounts[999] })
    assert.equal((await stabilityPool.getTotalEBTCDeposits()), dec(1, 27))

    // Price drops, defaulters' ICR fall below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)
    
    // Liquidate cdps
    const tx = await cdpManager.batchLiquidateCdps(_50_Defaulters, { from: accounts[0] })
    assert.isTrue(tx.receipt.status)

    // Check all defaulters liquidated
    for (account of _50_Defaulters) { assert.isFalse(await sortedCdps.contains(account)) }

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