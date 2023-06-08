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
    defaultPool = contracts.defaultPool
    borrowerOperations = contracts.borrowerOperations
    hintHelpers = contracts.hintHelpers

    functionCaller = contracts.functionCaller

    feeRecipient = LQTYContracts.feeRecipient

    await deploymentHelper.connectCoreContracts(contracts, LQTYContracts)
    await deploymentHelper.connectLQTYContractsToCore(LQTYContracts, contracts)
  })

  // --- TESTS ---


  // --- liquidate Cdps - all cdps liquidated - no pending distribution rewards ---

  // 1 cdp
  it("", async () => {
    let _liqCnt = 1;
    const message = 'Test,liquidateCdps(). n = ' + _liqCnt + '. All fully liquidated. No pending distribution rewards.'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(2000, 'ether'), dec(10, 18))

    // --- Accounts to be liquidated in the test tx --
    const _Defaulters = accounts.slice(1, 1 + _liqCnt)
    await th.openCdp_allAccounts(_Defaulters, contracts, dec(100, 'ether'), dec(5, 18))

    // Check all defaulters active
    let _toLqiuidateCdpIds = [];
    for (account of _Defaulters) { 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))    
         _toLqiuidateCdpIds.push(_cdpId); 
    }

    // Whale opens cdp to get enough debt to repay/liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(400, 18), extraParams: { from: _liquidator, value: dec(8000, 'ether') }})

    // Price drops, defaulters' ICR fall below MCR
    let _droppedPrice = dec(5500, 13);
    await priceFeed.setPrice(_droppedPrice)

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(_liqCnt, { from: _liquidator })
    assert.isTrue(tx.receipt.status)

    // Check all defaulters liquidated
    for (account of _toLqiuidateCdpIds) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 2 cdps
  it("", async () => {
    let _liqCnt = 2;
    const message = 'Test,liquidateCdps(). n = ' + _liqCnt + '. All fully liquidated. No pending distribution rewards.'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(2000, 'ether'), dec(10, 18))

    // --- Accounts to be liquidated in the test tx --
    const _Defaulters = accounts.slice(1, 1 + _liqCnt)
    await th.openCdp_allAccounts(_Defaulters, contracts, dec(100, 'ether'), dec(5, 18))

    // Check all defaulters active
    let _toLqiuidateCdpIds = [];
    for (account of _Defaulters) { 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))    
         _toLqiuidateCdpIds.push(_cdpId); 
    }

    // Whale opens cdp to get enough debt to repay/liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(400, 18), extraParams: { from: _liquidator, value: dec(8000, 'ether') }})

    // Price drops, defaulters' ICR fall below MCR
    let _droppedPrice = dec(5500, 13);
    await priceFeed.setPrice(_droppedPrice)

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(_liqCnt, { from: _liquidator })
    assert.isTrue(tx.receipt.status)

    // Check all defaulters liquidated
    for (account of _toLqiuidateCdpIds) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 3 cdps
  it("", async () => {
    let _liqCnt = 3;
    const message = 'Test,liquidateCdps(). n = ' + _liqCnt + '. All fully liquidated. No pending distribution rewards.'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(2000, 'ether'), dec(10, 18))

    // --- Accounts to be liquidated in the test tx --
    const _Defaulters = accounts.slice(1, 1 + _liqCnt)
    await th.openCdp_allAccounts(_Defaulters, contracts, dec(100, 'ether'), dec(5, 18))

    // Check all defaulters active
    let _toLqiuidateCdpIds = [];
    for (account of _Defaulters) { 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))    
         _toLqiuidateCdpIds.push(_cdpId); 
    }

    // Whale opens cdp to get enough debt to repay/liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(400, 18), extraParams: { from: _liquidator, value: dec(8000, 'ether') }})

    // Price drops, defaulters' ICR fall below MCR
    let _droppedPrice = dec(5500, 13);
    await priceFeed.setPrice(_droppedPrice)

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(_liqCnt, { from: _liquidator })
    assert.isTrue(tx.receipt.status)

    // Check all defaulters liquidated
    for (account of _toLqiuidateCdpIds) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
    th.appendData({ gas: gas }, message, data)
  })

  // 5 cdps
  it("", async () => {
    let _liqCnt = 5;
    const message = 'Test,liquidateCdps(). n = ' + _liqCnt + '. All fully liquidated. No pending distribution rewards.'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(2000, 'ether'), dec(10, 18))

    // --- Accounts to be liquidated in the test tx --
    const _Defaulters = accounts.slice(1, 1 + _liqCnt)
    await th.openCdp_allAccounts(_Defaulters, contracts, dec(100, 'ether'), dec(5, 18))

    // Check all defaulters active
    let _toLqiuidateCdpIds = [];
    for (account of _Defaulters) { 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))    
         _toLqiuidateCdpIds.push(_cdpId); 
    }

    // Whale opens cdp to get enough debt to repay/liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(400, 18), extraParams: { from: _liquidator, value: dec(8000, 'ether') }})

    // Price drops, defaulters' ICR fall below MCR
    let _droppedPrice = dec(5500, 13);
    await priceFeed.setPrice(_droppedPrice)

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(_liqCnt, { from: _liquidator })
    assert.isTrue(tx.receipt.status)

    // Check all defaulters liquidated
    for (account of _toLqiuidateCdpIds) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 10 cdps
  it("", async () => {
    let _liqCnt = 10;
    const message = 'Test,liquidateCdps(). n = ' + _liqCnt + '. All fully liquidated. No pending distribution rewards.'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(2000, 'ether'), dec(10, 18))

    // --- Accounts to be liquidated in the test tx --
    const _Defaulters = accounts.slice(1, 1 + _liqCnt)
    await th.openCdp_allAccounts(_Defaulters, contracts, dec(100, 'ether'), dec(5, 18))

    // Check all defaulters active
    let _toLqiuidateCdpIds = [];
    for (account of _Defaulters) { 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))    
         _toLqiuidateCdpIds.push(_cdpId); 
    }

    // Whale opens cdp to get enough debt to repay/liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(400, 18), extraParams: { from: _liquidator, value: dec(8000, 'ether') }})

    // Price drops, defaulters' ICR fall below MCR
    let _droppedPrice = dec(5500, 13);
    await priceFeed.setPrice(_droppedPrice)

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(_liqCnt, { from: _liquidator })
    assert.isTrue(tx.receipt.status)

    // Check all defaulters liquidated
    for (account of _toLqiuidateCdpIds) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 20 cdps
  it("", async () => {
    let _liqCnt = 20;
    const message = 'Test,liquidateCdps(). n = ' + _liqCnt + '. All fully liquidated. No pending distribution rewards.'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(2000, 'ether'), dec(10, 18))

    // --- Accounts to be liquidated in the test tx --
    const _Defaulters = accounts.slice(1, 1 + _liqCnt)
    await th.openCdp_allAccounts(_Defaulters, contracts, dec(100, 'ether'), dec(5, 18))

    // Check all defaulters active
    let _toLqiuidateCdpIds = [];
    for (account of _Defaulters) { 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))    
         _toLqiuidateCdpIds.push(_cdpId); 
    }

    // Whale opens cdp to get enough debt to repay/liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(400, 18), extraParams: { from: _liquidator, value: dec(8000, 'ether') }})

    // Price drops, defaulters' ICR fall below MCR
    let _droppedPrice = dec(5500, 13);
    await priceFeed.setPrice(_droppedPrice)

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(_liqCnt, { from: _liquidator })
    assert.isTrue(tx.receipt.status)

    // Check all defaulters liquidated
    for (account of _toLqiuidateCdpIds) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })


  // 30 cdps
  it("", async () => {
    let _liqCnt = 30;
    const message = 'Test,liquidateCdps(). n = ' + _liqCnt + '. All fully liquidated. No pending distribution rewards.'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(2000, 'ether'), dec(10, 18))

    // --- Accounts to be liquidated in the test tx --
    const _Defaulters = accounts.slice(1, 1 + _liqCnt)
    await th.openCdp_allAccounts(_Defaulters, contracts, dec(100, 'ether'), dec(5, 18))

    // Check all defaulters active
    let _toLqiuidateCdpIds = [];
    for (account of _Defaulters) { 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))    
         _toLqiuidateCdpIds.push(_cdpId); 
    }

    // Whale opens cdp to get enough debt to repay/liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(400, 18), extraParams: { from: _liquidator, value: dec(8000, 'ether') }})

    // Price drops, defaulters' ICR fall below MCR
    let _droppedPrice = dec(5500, 13);
    await priceFeed.setPrice(_droppedPrice)

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(_liqCnt, { from: _liquidator })
    assert.isTrue(tx.receipt.status)

    // Check all defaulters liquidated
    for (account of _toLqiuidateCdpIds) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 40 cdps
  it("", async () => {
    let _liqCnt = 40;
    const message = 'Test,liquidateCdps(). n = ' + _liqCnt + '. All fully liquidated. No pending distribution rewards.'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(2000, 'ether'), dec(10, 18))

    // --- Accounts to be liquidated in the test tx --
    const _Defaulters = accounts.slice(1, 1 + _liqCnt)
    await th.openCdp_allAccounts(_Defaulters, contracts, dec(100, 'ether'), dec(5, 18))

    // Check all defaulters active
    let _toLqiuidateCdpIds = [];
    for (account of _Defaulters) { 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))    
         _toLqiuidateCdpIds.push(_cdpId); 
    }

    // Whale opens cdp to get enough debt to repay/liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(400, 18), extraParams: { from: _liquidator, value: dec(8000, 'ether') }})

    // Price drops, defaulters' ICR fall below MCR
    let _droppedPrice = dec(5500, 13);
    await priceFeed.setPrice(_droppedPrice)

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(_liqCnt, { from: _liquidator })
    assert.isTrue(tx.receipt.status)

    // Check all defaulters liquidated
    for (account of _toLqiuidateCdpIds) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 50 cdps
  it("", async () => {
    let _liqCnt = 50;
    const message = 'Test,liquidateCdps(). n = ' + _liqCnt + '. All fully liquidated. No pending distribution rewards.'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(2000, 'ether'), dec(10, 18))

    // --- Accounts to be liquidated in the test tx --
    const _Defaulters = accounts.slice(1, 1 + _liqCnt)
    await th.openCdp_allAccounts(_Defaulters, contracts, dec(100, 'ether'), dec(5, 18))

    // Check all defaulters active
    let _toLqiuidateCdpIds = [];
    for (account of _Defaulters) { 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))    
         _toLqiuidateCdpIds.push(_cdpId); 
    }

    // Whale opens cdp to get enough debt to repay/liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(400, 18), extraParams: { from: _liquidator, value: dec(8000, 'ether') }})

    // Price drops, defaulters' ICR fall below MCR
    let _droppedPrice = dec(5500, 13);
    await priceFeed.setPrice(_droppedPrice)

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(_liqCnt, { from: _liquidator })
    assert.isTrue(tx.receipt.status)

    // Check all defaulters liquidated
    for (account of _toLqiuidateCdpIds) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 55 cdps
  it("", async () => {
    const message = 'Test,liquidateCdps(). n = 55. All fully liquidated. No pending distribution rewards.'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(2000, 'ether'), dec(10, 18))

    // --- Accounts to be liquidated in the test tx --
    let _liqCnt = 55;
    const _Defaulters = accounts.slice(1, 1 + _liqCnt)
    await th.openCdp_allAccounts(_Defaulters, contracts, dec(100, 'ether'), dec(5, 18))

    // Check all defaulters active
    let _toLqiuidateCdpIds = [];
    for (account of _Defaulters) { 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))    
         _toLqiuidateCdpIds.push(_cdpId); 
    }

    // Whale opens cdp to get enough debt to repay/liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(400, 18), extraParams: { from: _liquidator, value: dec(8000, 'ether') }})

    // Price drops, defaulters' ICR fall below MCR
    let _droppedPrice = dec(5500, 13);
    await priceFeed.setPrice(_droppedPrice)

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(_liqCnt, { from: _liquidator })
    assert.isTrue(tx.receipt.status)

    // Check all defaulters liquidated
    for (account of _toLqiuidateCdpIds) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })


  // --- liquidate Cdps - all cdps liquidated - Has pending distribution rewards ---

  // 1 cdp
  it("", async () => {
    const message = 'Test,liquidateCdps(). n = 1. All fully liquidated. Has pending distribution rewards.'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(2000, 'ether'), dec(10, 18))

    // Account 500 opens CDP to be liquidated later
    await th.openCdp(contracts, {extraEBTCAmount: dec(1, 18), extraParams: { from: accounts[500], value: dec(25, 'ether') }})
    let _cdpIdLiq = await sortedCdps.cdpOfOwnerByIndex(accounts[500], 0);
    assert.isTrue(await sortedCdps.contains(_cdpIdLiq))

    // --- 1 Accounts to be liquidated in the test tx --
    const _1_Defaulters = accounts.slice(1, 2)
    await th.openCdp_allAccounts(_1_Defaulters, contracts, dec(80, 'ether'), dec(5, 18))

    // Check all defaulters active
    let _toLqiuidateCdpIds = [];
    for (account of _1_Defaulters) { 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))    
         _toLqiuidateCdpIds.push(_cdpId); 
    }

    // Whale opens cdp to get enough debt to repay/liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(400, 18), extraParams: { from: _liquidator, value: dec(8000, 'ether') }})

    // Account 500 is liquidated, creates pending distribution rewards for all
    let _droppedPrice = dec(3714, 13);
    await priceFeed.setPrice(_droppedPrice)
    await cdpManager.liquidate(_cdpIdLiq, { from: _liquidator })
    assert.isFalse(await sortedCdps.contains(_cdpIdLiq))
    await priceFeed.setPrice(dec(7428, 13))

    // Price drops, defaulters' ICR fall below MCR
    await priceFeed.setPrice(_droppedPrice)

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(1, { from: _liquidator })
    assert.isTrue(tx.receipt.status)

    // Check all defaulters liquidated
    for (account of _toLqiuidateCdpIds) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 2 cdps
  it("", async () => {
    const message = 'Test,liquidateCdps(). n = 2. All fully liquidated. Has pending distribution rewards.'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(2000, 'ether'), dec(10, 18))

    // Account 500 opens CDP to be liquidated later
    await th.openCdp(contracts, {extraEBTCAmount: dec(1, 18), extraParams: { from: accounts[500], value: dec(25, 'ether') }})
    let _cdpIdLiq = await sortedCdps.cdpOfOwnerByIndex(accounts[500], 0);
    assert.isTrue(await sortedCdps.contains(_cdpIdLiq))

    // --- 2 Accounts to be liquidated in the test tx --
    const _2_Defaulters = accounts.slice(1, 3)
    await th.openCdp_allAccounts(_2_Defaulters, contracts, dec(80, 'ether'), dec(5, 18))

    // Check all defaulters active
    let _toLqiuidateCdpIds = [];
    for (account of _2_Defaulters) { 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))    
         _toLqiuidateCdpIds.push(_cdpId); 
    }

    // Whale opens cdp to get enough debt to repay/liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(400, 18), extraParams: { from: _liquidator, value: dec(8000, 'ether') }})

    // Account 500 is liquidated, creates pending distribution rewards for all
    let _droppedPrice = dec(3714, 13);
    await priceFeed.setPrice(_droppedPrice)
    await cdpManager.liquidate(_cdpIdLiq, { from: _liquidator })
    assert.isFalse(await sortedCdps.contains(_cdpIdLiq))
    await priceFeed.setPrice(dec(7428, 13))

    // Price drops, defaulters' ICR fall below MCR
    await priceFeed.setPrice(_droppedPrice)

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(2, { from: _liquidator })
    assert.isTrue(tx.receipt.status)

    // Check all defaulters liquidated
    for (account of _toLqiuidateCdpIds) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 3 cdps
  it("", async () => {
    const message = 'Test,liquidateCdps(). n = 3. All fully liquidated. Has pending distribution rewards.'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(2000, 'ether'), dec(10, 18))

    // Account 500 opens CDP to be liquidated later
    await th.openCdp(contracts, {extraEBTCAmount: dec(1, 18), extraParams: { from: accounts[500], value: dec(25, 'ether') }})
    let _cdpIdLiq = await sortedCdps.cdpOfOwnerByIndex(accounts[500], 0);
    assert.isTrue(await sortedCdps.contains(_cdpIdLiq))

    // --- 3 Accounts to be liquidated in the test tx --
    const _3_Defaulters = accounts.slice(1, 4)
    await th.openCdp_allAccounts(_3_Defaulters, contracts, dec(80, 'ether'), dec(5, 18))

    // Check all defaulters active
    let _toLqiuidateCdpIds = [];
    for (account of _3_Defaulters) { 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))    
         _toLqiuidateCdpIds.push(_cdpId); 
    }

    // Whale opens cdp to get enough debt to repay/liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(400, 18), extraParams: { from: _liquidator, value: dec(8000, 'ether') }})

    // Account 500 is liquidated, creates pending distribution rewards for all
    let _droppedPrice = dec(3714, 13);
    await priceFeed.setPrice(_droppedPrice)
    await cdpManager.liquidate(_cdpIdLiq, { from: _liquidator })
    assert.isFalse(await sortedCdps.contains(_cdpIdLiq))
    await priceFeed.setPrice(dec(7428, 13))

    // Price drops, defaulters' ICR fall below MCR
    await priceFeed.setPrice(_droppedPrice)

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(3, { from: _liquidator })
    assert.isTrue(tx.receipt.status)

    // Check all defaulters liquidated
    for (account of _toLqiuidateCdpIds) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 5 cdps
  it("", async () => {
    const message = 'Test,liquidateCdps(). n = 5. All fully liquidated. Has pending distribution rewards.'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(2000, 'ether'), dec(10, 18))

    // Account 500 opens CDP to be liquidated later
    await th.openCdp(contracts, {extraEBTCAmount: dec(1, 18), extraParams: { from: accounts[500], value: dec(25, 'ether') }})
    let _cdpIdLiq = await sortedCdps.cdpOfOwnerByIndex(accounts[500], 0);
    assert.isTrue(await sortedCdps.contains(_cdpIdLiq))

    // --- 5 Accounts to be liquidated in the test tx --
    const _5_Defaulters = accounts.slice(1, 6)
    await th.openCdp_allAccounts(_5_Defaulters, contracts, dec(80, 'ether'), dec(5, 18))

    // Check all defaulters active
    let _toLqiuidateCdpIds = [];
    for (account of _5_Defaulters) { 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))    
         _toLqiuidateCdpIds.push(_cdpId); 
    }

    // Whale opens cdp to get enough debt to repay/liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(400, 18), extraParams: { from: _liquidator, value: dec(8000, 'ether') }})

    // Account 500 is liquidated, creates pending distribution rewards for all
    let _droppedPrice = dec(3714, 13);
    await priceFeed.setPrice(_droppedPrice)
    await cdpManager.liquidate(_cdpIdLiq, { from: _liquidator })
    assert.isFalse(await sortedCdps.contains(_cdpIdLiq))
    await priceFeed.setPrice(dec(7428, 13))

    // Price drops, defaulters' ICR fall below MCR
    await priceFeed.setPrice(_droppedPrice)

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(5, { from: _liquidator })
    assert.isTrue(tx.receipt.status)

    // Check all defaulters liquidated
    for (account of _toLqiuidateCdpIds) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 10 cdps
  it("", async () => {
    const message = 'Test,liquidateCdps(). n = 10. All fully liquidated. Has pending distribution rewards.'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(2000, 'ether'), dec(10, 18))

    // Account 500 opens CDP to be liquidated later
    await th.openCdp(contracts, {extraEBTCAmount: dec(1, 18), extraParams: { from: accounts[500], value: dec(25, 'ether') }})
    let _cdpIdLiq = await sortedCdps.cdpOfOwnerByIndex(accounts[500], 0);
    assert.isTrue(await sortedCdps.contains(_cdpIdLiq))

    // --- 10 Accounts to be liquidated in the test tx --
    const _10_Defaulters = accounts.slice(1, 11)
    await th.openCdp_allAccounts(_10_Defaulters, contracts, dec(80, 'ether'), dec(5, 18))

    // Check all defaulters active
    let _toLqiuidateCdpIds = [];
    for (account of _10_Defaulters) { 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))    
         _toLqiuidateCdpIds.push(_cdpId); 
    }

    // Whale opens cdp to get enough debt to repay/liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(400, 18), extraParams: { from: _liquidator, value: dec(8000, 'ether') }})

    // Account 500 is liquidated, creates pending distribution rewards for all
    let _droppedPrice = dec(3714, 13);
    await priceFeed.setPrice(_droppedPrice)
    await cdpManager.liquidate(_cdpIdLiq, { from: _liquidator })
    assert.isFalse(await sortedCdps.contains(_cdpIdLiq))
    await priceFeed.setPrice(dec(7428, 13))

    // Price drops, defaulters' ICR fall below MCR
    await priceFeed.setPrice(_droppedPrice)

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(10, { from: _liquidator })
    assert.isTrue(tx.receipt.status)

    // Check all defaulters liquidated
    for (account of _toLqiuidateCdpIds) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 20 cdps
  it("", async () => {
    const message = 'Test,liquidateCdps(). n = 20. All fully liquidated. Has pending distribution rewards.'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(2000, 'ether'), dec(10, 18))

    // Account 500 opens CDP to be liquidated later
    await th.openCdp(contracts, {extraEBTCAmount: dec(1, 18), extraParams: { from: accounts[500], value: dec(25, 'ether') }})
    let _cdpIdLiq = await sortedCdps.cdpOfOwnerByIndex(accounts[500], 0);
    assert.isTrue(await sortedCdps.contains(_cdpIdLiq))

    // --- 20 Accounts to be liquidated in the test tx --
    const _20_Defaulters = accounts.slice(1, 21)
    await th.openCdp_allAccounts(_20_Defaulters, contracts, dec(80, 'ether'), dec(5, 18))

    // Check all defaulters active
    let _toLqiuidateCdpIds = [];
    for (account of _20_Defaulters) { 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))    
         _toLqiuidateCdpIds.push(_cdpId); 
    }

    // Whale opens cdp to get enough debt to repay/liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(400, 18), extraParams: { from: _liquidator, value: dec(8000, 'ether') }})

    // Account 500 is liquidated, creates pending distribution rewards for all
    let _droppedPrice = dec(3714, 13);
    await priceFeed.setPrice(_droppedPrice)
    await cdpManager.liquidate(_cdpIdLiq, { from: _liquidator })
    assert.isFalse(await sortedCdps.contains(_cdpIdLiq))
    await priceFeed.setPrice(dec(7428, 13))

    // Price drops, defaulters' ICR fall below MCR
    await priceFeed.setPrice(_droppedPrice)

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(20, { from: _liquidator })
    assert.isTrue(tx.receipt.status)

    // Check all defaulters liquidated
    for (account of _toLqiuidateCdpIds) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 30 cdps
  it("", async () => {
    const message = 'Test,liquidateCdps(). n = 30. All fully liquidated. Has pending distribution rewards.'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(2000, 'ether'), dec(10, 18))

    // Account 500 opens CDP to be liquidated later
    await th.openCdp(contracts, {extraEBTCAmount: dec(1, 18), extraParams: { from: accounts[500], value: dec(25, 'ether') }})
    let _cdpIdLiq = await sortedCdps.cdpOfOwnerByIndex(accounts[500], 0);
    assert.isTrue(await sortedCdps.contains(_cdpIdLiq))

    // --- 30 Accounts to be liquidated in the test tx --
    const _30_Defaulters = accounts.slice(1, 31)
    await th.openCdp_allAccounts(_30_Defaulters, contracts, dec(80, 'ether'), dec(5, 18))

    // Check all defaulters active
    let _toLqiuidateCdpIds = [];
    for (account of _30_Defaulters) { 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))    
         _toLqiuidateCdpIds.push(_cdpId); 
    }

    // Whale opens cdp to get enough debt to repay/liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(400, 18), extraParams: { from: _liquidator, value: dec(8000, 'ether') }})

    // Account 500 is liquidated, creates pending distribution rewards for all
    let _droppedPrice = dec(3714, 13);
    await priceFeed.setPrice(_droppedPrice)
    await cdpManager.liquidate(_cdpIdLiq, { from: _liquidator })
    assert.isFalse(await sortedCdps.contains(_cdpIdLiq))
    await priceFeed.setPrice(dec(7428, 13))

    // Price drops, defaulters' ICR fall below MCR
    await priceFeed.setPrice(_droppedPrice)

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(30, { from: _liquidator })
    assert.isTrue(tx.receipt.status)

    // Check all defaulters liquidated
    for (account of _toLqiuidateCdpIds) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 40 cdps
  it("", async () => {
    const message = 'Test,liquidateCdps(). n = 40. All fully liquidated. Has pending distribution rewards.'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(2000, 'ether'), dec(10, 18))

    // Account 500 opens CDP to be liquidated later
    await th.openCdp(contracts, {extraEBTCAmount: dec(1, 18), extraParams: { from: accounts[500], value: dec(25, 'ether') }})
    let _cdpIdLiq = await sortedCdps.cdpOfOwnerByIndex(accounts[500], 0);
    assert.isTrue(await sortedCdps.contains(_cdpIdLiq))

    // --- 40 Accounts to be liquidated in the test tx --
    const _40_Defaulters = accounts.slice(1, 41)
    await th.openCdp_allAccounts(_40_Defaulters, contracts, dec(80, 'ether'), dec(5, 18))

    // Check all defaulters active
    let _toLqiuidateCdpIds = [];
    for (account of _40_Defaulters) { 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))    
         _toLqiuidateCdpIds.push(_cdpId); 
    }

    // Whale opens cdp to get enough debt to repay/liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(400, 18), extraParams: { from: _liquidator, value: dec(8000, 'ether') }})

    // Account 500 is liquidated, creates pending distribution rewards for all
    let _droppedPrice = dec(3714, 13);
    await priceFeed.setPrice(_droppedPrice)
    await cdpManager.liquidate(_cdpIdLiq, { from: _liquidator })
    assert.isFalse(await sortedCdps.contains(_cdpIdLiq))
    await priceFeed.setPrice(dec(7428, 13))

    // Price drops, defaulters' ICR fall below MCR
    await priceFeed.setPrice(_droppedPrice)

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(40, { from: _liquidator })
    assert.isTrue(tx.receipt.status)

    // Check all defaulters liquidated
    for (account of _toLqiuidateCdpIds) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })


  // 45 cdps
  it("", async () => {
    const message = 'Test,liquidateCdps(). n = 45. All fully liquidated. Has pending distribution rewards.'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(2000, 'ether'), dec(10, 18))

    // Account 500 opens cDP to be liquidated later
    await th.openCdp(contracts, {extraEBTCAmount: dec(1, 18), extraParams: { from: accounts[500], value: dec(25, 'ether') }})
    let _cdpIdLiq = await sortedCdps.cdpOfOwnerByIndex(accounts[500], 0);
    assert.isTrue(await sortedCdps.contains(_cdpIdLiq))

    // --- 45 Accounts to be liquidated in the test tx --
    const _45_Defaulters = accounts.slice(1, 46)
    await th.openCdp_allAccounts(_45_Defaulters, contracts, dec(80, 'ether'), dec(5, 18))

    // Check all defaulters active
    let _toLqiuidateCdpIds = [];
    for (account of _45_Defaulters) { 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))   
         _toLqiuidateCdpIds.push(_cdpId); 
    }

    // Whale opens cdp to get enough debt to repay/liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(400, 18), extraParams: { from: _liquidator, value: dec(8000, 'ether') }})

    // Account 500 is liquidated, creates pending distribution rewards for all
    let _droppedPrice = dec(3714, 13);
    await priceFeed.setPrice(_droppedPrice)
    await cdpManager.liquidate(_cdpIdLiq, { from: _liquidator })
    assert.isFalse(await sortedCdps.contains(_cdpIdLiq))
    await priceFeed.setPrice(dec(7428, 13))

    // Price drops, defaulters' ICR fall below MCR
    await priceFeed.setPrice(_droppedPrice)

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(45, { from: _liquidator })
    assert.isTrue(tx.receipt.status)

    // Check all defaulters liquidated
    for (account of _toLqiuidateCdpIds) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 50 cdps
  it("", async () => {
    const message = 'Test,liquidateCdps(). n = 50. All fully liquidated. Has pending distribution rewards.'
    // 10 accts each open Cdp
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(2000, 'ether'), dec(10, 18))

    // Account 500 opens CDP to be liquidated later
    await th.openCdp(contracts, {extraEBTCAmount: dec(1, 18), extraParams: { from: accounts[500], value: dec(25, 'ether') }})
    let _cdpIdLiq = await sortedCdps.cdpOfOwnerByIndex(accounts[500], 0);
    assert.isTrue(await sortedCdps.contains(_cdpIdLiq))

    // --- 50 Accounts to be liquidated in the test tx --
    const _50_Defaulters = accounts.slice(1, 51)
    await th.openCdp_allAccounts(_50_Defaulters, contracts, dec(80, 'ether'), dec(5, 18))

    // Check all defaulters active
    let _toLqiuidateCdpIds = [];
    for (account of _50_Defaulters) { 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))  
         _toLqiuidateCdpIds.push(_cdpId); 
    }

    // Whale opens cdp to get enough debt to repay/liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(400, 18), extraParams: { from: _liquidator, value: dec(8000, 'ether') }})

    // Account 500 is liquidated, creates pending distribution rewards for all
    let _droppedPrice = dec(3714, 13);
    await priceFeed.setPrice(_droppedPrice)
    await cdpManager.liquidate(_cdpIdLiq, { from: _liquidator })
    assert.isFalse(await sortedCdps.contains(_cdpIdLiq))
    await priceFeed.setPrice(dec(7428, 13))

    // Price drops, defaulters' ICR fall below MCR
    await priceFeed.setPrice(_droppedPrice)

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.liquidateCdps(50, { from: _liquidator })
    assert.isTrue(tx.receipt.status)

    // Check all defaulters liquidated
    for (account of _toLqiuidateCdpIds) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // ---batchLiquidateCdps(): Full liquidation, no pending rewards ---

  // 10 cdps
  it("", async () => {
    const message = 'Test,batchLiquidateCdps(). batch size = 10. All fully liquidated. No pending distribution rewards.'
    // 10 accts each open Cdp
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(200, 'ether'), dec(2, 18))

    // Whale opens cdp to get enough debt to repay/liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})

    //10 accts open Cdp to be liquidated in the test tx
    const _10_Defaulters = accounts.slice(1, 11)
    await th.openCdp_allAccounts(_10_Defaulters, contracts, dec(20, 'ether'), dec(1, 18))

    // Check all defaulters are active
    let _toLqiuidateCdpIds = [];
    for (account of _10_Defaulters) { 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))  
         _toLqiuidateCdpIds.push(_cdpId); 
    }

    // Price drops, defaulters falls below MCR
    await priceFeed.setPrice(dec(5500, 13))

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.batchLiquidateCdps(_toLqiuidateCdpIds, { from: _liquidator })
    assert.isTrue(tx.receipt.status)

    // Check Cdps are closed
    for (account of _toLqiuidateCdpIds) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  it("", async () => {
    const message = 'Test,batchLiquidateCdps(). batch size = 50. All fully liquidated. No pending distribution rewards.'
    // 10 accts each open Cdp
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(200, 'ether'), dec(2, 18))

    // Whale opens cdp to get enough debt to repay/liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})

    //50 accts open Cdp to be liquidated in the test tx
    const _50_Defaulters = accounts.slice(1, 51)
    await th.openCdp_allAccounts(_50_Defaulters, contracts, dec(20, 'ether'), dec(1, 18))

    // Check all defaulters are active
    let _toLqiuidateCdpIds = [];
    for (account of _50_Defaulters) { 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId)) 
         _toLqiuidateCdpIds.push(_cdpId); 
    }

    // Price drops, defaulters falls below MCR
    await priceFeed.setPrice(dec(5500, 13))

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.batchLiquidateCdps(_toLqiuidateCdpIds, { from: _liquidator })
    assert.isTrue(tx.receipt.status)

    // Check Cdps are closed
    for (account of _toLqiuidateCdpIds) {    
         assert.isFalse(await sortedCdps.contains(account))
    }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })


  // ---batchLiquidateCdps(): Full liquidation, HAS pending rewards ---

  it("", async () => {
    const message = 'Test,batchLiquidateCdps(). batch size = 10. All fully liquidated. Has pending distribution rewards.'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(200, 'ether'), dec(2, 18))

    // Account 500 opens to be liquidated later
    await th.openCdp(contracts, {extraEBTCAmount: dec(2, 18), extraParams: { from: accounts[500], value: dec(35, 'ether') }})
    let _cdpIdLiq = await sortedCdps.cdpOfOwnerByIndex(accounts[500], 0);
    assert.isTrue(await sortedCdps.contains(_cdpIdLiq))

    // --- 10 Accounts to be liquidated in the test tx --
    const _10_Defaulters = accounts.slice(1, 11)
    await th.openCdp_allAccounts(_10_Defaulters, contracts, dec(20, 'ether'), dec(1, 18))

    // Check all defaulters active
    let _toLqiuidateCdpIds = [];
    for (account of _10_Defaulters) {  
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0); 
         assert.isTrue(await sortedCdps.contains(_cdpId)) 
         _toLqiuidateCdpIds.push(_cdpId);
    }

    // Whale opens cdp to get enough debt to repay/liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})

    // Account 500 is liquidated, creates pending distribution rewards for all
    let _droppedPrice = dec(3714, 13);
    await priceFeed.setPrice(_droppedPrice)
    await cdpManager.liquidate(_cdpIdLiq, { from: _liquidator })
    assert.isFalse(await sortedCdps.contains(_cdpIdLiq))
    await priceFeed.setPrice(dec(7428, 18))

    // Price drops, defaulters' ICR fall below MCR
    await priceFeed.setPrice(_droppedPrice)

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Liquidate cdps
    const tx = await cdpManager.batchLiquidateCdps(_toLqiuidateCdpIds, { from: _liquidator })
    assert.isTrue(tx.receipt.status)

    // Check all defaulters liquidated
    for (account of _toLqiuidateCdpIds) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  it("", async () => {
    const message = 'Test,batchLiquidateCdps(). batch size = 50. All fully liquidated. Has pending distribution rewards.'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(200, 'ether'), dec(2, 18))

    // Account 500 opens CDP to be liquidated later
    await th.openCdp(contracts, {extraEBTCAmount: dec(2, 18), extraParams: { from: accounts[500], value: dec(35, 'ether') }})
    let _cdpIdLiq = await sortedCdps.cdpOfOwnerByIndex(accounts[500], 0);
    assert.isTrue(await sortedCdps.contains(_cdpIdLiq))

    // --- 50 Accounts to be liquidated in the test tx --
    const _50_Defaulters = accounts.slice(1, 51)
    await th.openCdp_allAccounts(_50_Defaulters, contracts, dec(20, 'ether'), dec(1, 18))

    // Check all defaulters active
    let _toLqiuidateCdpIds = [];
    for (account of _50_Defaulters) { 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0); 
         assert.isTrue(await sortedCdps.contains(_cdpId)) 
         _toLqiuidateCdpIds.push(_cdpId);
    }

    // Whale opens cdp to get enough debt to repay/liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})

    // Account 500 is liquidated, creates pending distribution rewards for all
    let _droppedPrice = dec(3714, 13);
    await priceFeed.setPrice(_droppedPrice)
    await cdpManager.liquidate(_cdpIdLiq, { from: _liquidator })
    assert.isFalse(await sortedCdps.contains(_cdpIdLiq))
    await priceFeed.setPrice(dec(7428, 13))

    // Price drops, defaulters' ICR fall below MCR
    await priceFeed.setPrice(_droppedPrice)

    // Check Recovery Mode is false
    assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)
    
    // Liquidate cdps
    const tx = await cdpManager.batchLiquidateCdps(_toLqiuidateCdpIds, { from: _liquidator })
    assert.isTrue(tx.receipt.status)

    // Check all defaulters liquidated
    for (cdpId of _toLqiuidateCdpIds) { assert.isFalse(await sortedCdps.contains(cdpId)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  it("Export test data", async () => {
    let _lineCnt = 1;
    let _content = '';
    for(let i = 0;i < data.length;i++){
        console.log('#L' + _lineCnt + ':' + data[i]);
        _lineCnt = _lineCnt + 1;	
        _content = _content + data[i]	
    }
	
    fs.writeFile('gasTest/outputs/liquidateCdpsGasData.csv', _content, (err) => {
        if (err) { 
            console.log(err) 
        } else {
            console.log("LiquidateCdps() gas test data written to gasTest/outputs/liquidateCdpsGasData.csv")
        }
    })
  })
})