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

    feeRecipient = LQTYContracts.feeRecipient
    communityIssuance = LQTYContracts.communityIssuance
    lockupContractFactory = LQTYContracts.lockupContractFactory

    await deploymentHelper.connectCoreContracts(contracts, LQTYContracts)
    await deploymentHelper.connectLQTYContractsToCore(LQTYContracts, contracts)
  })

  // --- liquidate Cdps --- RECOVERY MODE --- Full liquidation, NO pending distribution rewards ----

  // 1 cdp
  it("", async () => {
    let _liqCnt = 1;
    const message = 'Test,liquidateCdps(). n = ' + _liqCnt + '. All fully liquidated. No pending distribution rewards. In Recovery Mode'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(200, 'ether'), dec(2, 18))

    // --- Accounts to be liquidated in the test tx ---
    const _Defaulters = accounts.slice(1, 1 + _liqCnt)
    await th.openCdp_allAccounts(_Defaulters, contracts, dec(20, 'ether'), dec(1, 18))

    // check all defaulters active
    let _toLiquidateCdpIds = [];
    for (account of _Defaulters) { 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))  
         _toLiquidateCdpIds.push(_cdpId);
    }

    // Whale opens cdp to get enough debt to repay/liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})

    // Check Recovery Mode is true		
    let _droppedPrice = dec(3014, 13);
    await priceFeed.setPrice(_droppedPrice)	
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()));

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)
    
    const tx = await cdpManager.batchLiquidateCdps(_toLiquidateCdpIds, { from: _liquidator })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()));

    // check all defaulters liquidated
    for (account of _toLiquidateCdpIds) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 2 cdps
  it("", async () => {
    let _liqCnt = 2;
    const message = 'Test,liquidateCdps(). n = ' + _liqCnt + '. All fully liquidated. No pending distribution rewards. In Recovery Mode'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(200, 'ether'), dec(2, 18))

    // --- Accounts to be liquidated in the test tx ---
    const _Defaulters = accounts.slice(1, 1 + _liqCnt)
    await th.openCdp_allAccounts(_Defaulters, contracts, dec(20, 'ether'), dec(1, 18))

    // check all defaulters active
    let _toLiquidateCdpIds = [];
    for (account of _Defaulters) { 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))  
         _toLiquidateCdpIds.push(_cdpId);
    }

    // Whale opens cdp to get enough debt to repay/liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})

    // Check Recovery Mode is true		
    let _droppedPrice = dec(3014, 13);
    await priceFeed.setPrice(_droppedPrice)	
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()));

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)
    
    const tx = await cdpManager.batchLiquidateCdps(_toLiquidateCdpIds, { from: _liquidator })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()));

    // check all defaulters liquidated
    for (account of _toLiquidateCdpIds) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })


  // 3 cdps
  it("", async () => {
    let _liqCnt = 3;
    const message = 'Test,liquidateCdps(). n = ' + _liqCnt + '. All fully liquidated. No pending distribution rewards. In Recovery Mode'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(200, 'ether'), dec(2, 18))

    // --- Accounts to be liquidated in the test tx ---
    const _Defaulters = accounts.slice(1, 1 + _liqCnt)
    await th.openCdp_allAccounts(_Defaulters, contracts, dec(20, 'ether'), dec(1, 18))

    // check all defaulters active
    let _toLiquidateCdpIds = [];
    for (account of _Defaulters) { 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))  
         _toLiquidateCdpIds.push(_cdpId);
    }

    // Whale opens cdp to get enough debt to repay/liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})

    // Check Recovery Mode is true		
    let _droppedPrice = dec(3014, 13);
    await priceFeed.setPrice(_droppedPrice)	
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()));

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)
    
    const tx = await cdpManager.batchLiquidateCdps(_toLiquidateCdpIds, { from: _liquidator })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()));

    // check all defaulters liquidated
    for (account of _toLiquidateCdpIds) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 5 cdps 
  it("", async () => {
    let _liqCnt = 5;
    const message = 'Test,liquidateCdps(). n = ' + _liqCnt + '. All fully liquidated. No pending distribution rewards. In Recovery Mode'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(200, 'ether'), dec(2, 18))

    // --- Accounts to be liquidated in the test tx ---
    const _Defaulters = accounts.slice(1, 1 + _liqCnt)
    await th.openCdp_allAccounts(_Defaulters, contracts, dec(20, 'ether'), dec(1, 18))

    // check all defaulters active
    let _toLiquidateCdpIds = [];
    for (account of _Defaulters) { 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))  
         _toLiquidateCdpIds.push(_cdpId);
    }

    // Whale opens cdp to get enough debt to repay/liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})

    // Check Recovery Mode is true		
    let _droppedPrice = dec(3014, 13);
    await priceFeed.setPrice(_droppedPrice)	
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()));

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)
    
    const tx = await cdpManager.batchLiquidateCdps(_toLiquidateCdpIds, { from: _liquidator })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()));

    // check all defaulters liquidated
    for (account of _toLiquidateCdpIds) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })


  // 10 cdps
  it("", async () => {
    let _liqCnt = 10;
    const message = 'Test,liquidateCdps(). n = ' + _liqCnt + '. All fully liquidated. No pending distribution rewards. In Recovery Mode'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(200, 'ether'), dec(2, 18))

    // --- Accounts to be liquidated in the test tx ---
    const _Defaulters = accounts.slice(1, 1 + _liqCnt)
    await th.openCdp_allAccounts(_Defaulters, contracts, dec(20, 'ether'), dec(1, 18))

    // check all defaulters active
    let _toLiquidateCdpIds = [];
    for (account of _Defaulters) { 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))  
         _toLiquidateCdpIds.push(_cdpId);
    }

    // Whale opens cdp to get enough debt to repay/liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})

    // Check Recovery Mode is true		
    let _droppedPrice = dec(3014, 13);
    await priceFeed.setPrice(_droppedPrice)	
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()));

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)
    
    const tx = await cdpManager.batchLiquidateCdps(_toLiquidateCdpIds, { from: _liquidator })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()));

    // check all defaulters liquidated
    for (account of _toLiquidateCdpIds) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 20 cdps
  it("", async () => {
    let _liqCnt = 20;
    const message = 'Test,liquidateCdps(). n = ' + _liqCnt + '. All fully liquidated. No pending distribution rewards. In Recovery Mode'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(200, 'ether'), dec(2, 18))

    // --- Accounts to be liquidated in the test tx ---
    const _Defaulters = accounts.slice(1, 1 + _liqCnt)
    await th.openCdp_allAccounts(_Defaulters, contracts, dec(20, 'ether'), dec(1, 18))

    // check all defaulters active
    let _toLiquidateCdpIds = [];
    for (account of _Defaulters) { 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))  
         _toLiquidateCdpIds.push(_cdpId);
    }

    // Whale opens cdp to get enough debt to repay/liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})

    // Check Recovery Mode is true		
    let _droppedPrice = dec(3014, 13);
    await priceFeed.setPrice(_droppedPrice)	
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()));

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)
    
    const tx = await cdpManager.batchLiquidateCdps(_toLiquidateCdpIds, { from: _liquidator })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()));

    // check all defaulters liquidated
    for (account of _toLiquidateCdpIds) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })


  // 30 cdps
  it("", async () => {
    let _liqCnt = 30;
    const message = 'Test,liquidateCdps(). n = ' + _liqCnt + '. All fully liquidated. No pending distribution rewards. In Recovery Mode'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(200, 'ether'), dec(2, 18))

    // --- Accounts to be liquidated in the test tx ---
    const _Defaulters = accounts.slice(1, 1 + _liqCnt)
    await th.openCdp_allAccounts(_Defaulters, contracts, dec(20, 'ether'), dec(1, 18))

    // check all defaulters active
    let _toLiquidateCdpIds = [];
    for (account of _Defaulters) { 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))  
         _toLiquidateCdpIds.push(_cdpId);
    }

    // Whale opens cdp to get enough debt to repay/liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})

    // Check Recovery Mode is true		
    let _droppedPrice = dec(3014, 13);
    await priceFeed.setPrice(_droppedPrice)	
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()));

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)
    
    const tx = await cdpManager.batchLiquidateCdps(_toLiquidateCdpIds, { from: _liquidator })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()));

    // check all defaulters liquidated
    for (account of _toLiquidateCdpIds) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 40 cdps
  it("", async () => {
    let _liqCnt = 40;
    const message = 'Test,liquidateCdps(). n = ' + _liqCnt + '. All fully liquidated. No pending distribution rewards. In Recovery Mode'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(200, 'ether'), dec(2, 18))

    // --- Accounts to be liquidated in the test tx ---
    const _Defaulters = accounts.slice(1, 1 + _liqCnt)
    await th.openCdp_allAccounts(_Defaulters, contracts, dec(20, 'ether'), dec(1, 18))

    // check all defaulters active
    let _toLiquidateCdpIds = [];
    for (account of _Defaulters) { 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))  
         _toLiquidateCdpIds.push(_cdpId);
    }

    // Whale opens cdp to get enough debt to repay/liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})

    // Check Recovery Mode is true		
    let _droppedPrice = dec(3014, 13);
    await priceFeed.setPrice(_droppedPrice)	
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()));

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)
    
    const tx = await cdpManager.batchLiquidateCdps(_toLiquidateCdpIds, { from: _liquidator })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()));

    // check all defaulters liquidated
    for (account of _toLiquidateCdpIds) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 45 cdps
  it("", async () => {
    let _liqCnt = 45;
    const message = 'Test,liquidateCdps(). n = ' + _liqCnt + '. All fully liquidated. No pending distribution rewards. In Recovery Mode'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(200, 'ether'), dec(2, 18))

    // --- Accounts to be liquidated in the test tx ---
    const _Defaulters = accounts.slice(1, 1 + _liqCnt)
    await th.openCdp_allAccounts(_Defaulters, contracts, dec(20, 'ether'), dec(1, 18))

    // check all defaulters active
    let _toLiquidateCdpIds = [];
    for (account of _Defaulters) { 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))  
         _toLiquidateCdpIds.push(_cdpId);
    }

    // Whale opens cdp to get enough debt to repay/liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})

    // Check Recovery Mode is true		
    let _droppedPrice = dec(3014, 13);
    await priceFeed.setPrice(_droppedPrice)	
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()));

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)
    
    const tx = await cdpManager.batchLiquidateCdps(_toLiquidateCdpIds, { from: _liquidator })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()));

    // check all defaulters liquidated
    for (account of _toLiquidateCdpIds) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // --- liquidate Cdps --- RECOVERY MODE --- Full liquidation, HAS pending distribution rewards ----

  // 1 cdp
  it("", async () => {
    let _liqCnt = 1;
    const message = 'Test,liquidateCdps(). n = ' + _liqCnt + '. All fully liquidated. Has pending distribution rewards. In Recovery Mode'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(200, 'ether'), dec(2, 18))

    // Account 500 opens CDP to be liquidated later
    await th.openCdp(contracts, {extraEBTCAmount: dec(2, 18), extraParams: { from: accounts[500], value: dec(35, 'ether') }})
    let _cdpIdLiq = await sortedCdps.cdpOfOwnerByIndex(accounts[500], 0);
    assert.isTrue(await sortedCdps.contains(_cdpIdLiq))

    // --- Accounts to be liquidated in the test tx ---
    const _Defaulters = accounts.slice(1, 1 + _liqCnt)
    await th.openCdp_allAccounts(_Defaulters, contracts, dec(20, 'ether'), dec(1, 18))

    // check all defaulters active
    let _toLiquidateCdpIds = [];
    for (account of _Defaulters) { 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))  
         _toLiquidateCdpIds.push(_cdpId);
    }

    // Whale opens cdp to get enough debt to repay/liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})

    // Account 500 is liquidated, creates pending distribution rewards for all
    let _droppedPrice = dec(3014, 13);
    await priceFeed.setPrice(_droppedPrice)	
    await cdpManager.liquidate(_cdpIdLiq, { from: _liquidator })

    // Check Recovery Mode is true
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()));

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)
    
    const tx = await cdpManager.batchLiquidateCdps(_toLiquidateCdpIds, { from: _liquidator })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()));

    // check all defaulters liquidated
    for (account of _toLiquidateCdpIds) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 2 cdps
  it("", async () => {
    let _liqCnt = 2;
    const message = 'Test,liquidateCdps(). n = ' + _liqCnt + '. All fully liquidated. Has pending distribution rewards. In Recovery Mode'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(200, 'ether'), dec(2, 18))

    // Account 500 opens CDP to be liquidated later
    await th.openCdp(contracts, {extraEBTCAmount: dec(2, 18), extraParams: { from: accounts[500], value: dec(35, 'ether') }})
    let _cdpIdLiq = await sortedCdps.cdpOfOwnerByIndex(accounts[500], 0);
    assert.isTrue(await sortedCdps.contains(_cdpIdLiq))

    // --- Accounts to be liquidated in the test tx ---
    const _Defaulters = accounts.slice(1, 1 + _liqCnt)
    await th.openCdp_allAccounts(_Defaulters, contracts, dec(20, 'ether'), dec(1, 18))

    // check all defaulters active
    let _toLiquidateCdpIds = [];
    for (account of _Defaulters) { 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))  
         _toLiquidateCdpIds.push(_cdpId);
    }

    // Whale opens cdp to get enough debt to repay/liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})

    // Account 500 is liquidated, creates pending distribution rewards for all
    let _droppedPrice = dec(3014, 13);
    await priceFeed.setPrice(_droppedPrice)	
    await cdpManager.liquidate(_cdpIdLiq, { from: _liquidator })

    // Check Recovery Mode is true
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()));

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)
    
    const tx = await cdpManager.batchLiquidateCdps(_toLiquidateCdpIds, { from: _liquidator })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()));

    // check all defaulters liquidated
    for (account of _toLiquidateCdpIds) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 3 cdps
  it("", async () => {
    let _liqCnt = 3;
    const message = 'Test,liquidateCdps(). n = ' + _liqCnt + '. All fully liquidated. Has pending distribution rewards. In Recovery Mode'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(200, 'ether'), dec(2, 18))

    // Account 500 opens CDP to be liquidated later
    await th.openCdp(contracts, {extraEBTCAmount: dec(2, 18), extraParams: { from: accounts[500], value: dec(35, 'ether') }})
    let _cdpIdLiq = await sortedCdps.cdpOfOwnerByIndex(accounts[500], 0);
    assert.isTrue(await sortedCdps.contains(_cdpIdLiq))

    // --- Accounts to be liquidated in the test tx ---
    const _Defaulters = accounts.slice(1, 1 + _liqCnt)
    await th.openCdp_allAccounts(_Defaulters, contracts, dec(20, 'ether'), dec(1, 18))

    // check all defaulters active
    let _toLiquidateCdpIds = [];
    for (account of _Defaulters) { 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))  
         _toLiquidateCdpIds.push(_cdpId);
    }

    // Whale opens cdp to get enough debt to repay/liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})

    // Account 500 is liquidated, creates pending distribution rewards for all
    let _droppedPrice = dec(3014, 13);
    await priceFeed.setPrice(_droppedPrice)	
    await cdpManager.liquidate(_cdpIdLiq, { from: _liquidator })

    // Check Recovery Mode is true
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()));

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)
    
    const tx = await cdpManager.batchLiquidateCdps(_toLiquidateCdpIds, { from: _liquidator })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()));

    // check all defaulters liquidated
    for (account of _toLiquidateCdpIds) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 5 cdps
  it("", async () => {
    let _liqCnt = 5;
    const message = 'Test,liquidateCdps(). n = ' + _liqCnt + '. All fully liquidated. Has pending distribution rewards. In Recovery Mode'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(200, 'ether'), dec(2, 18))

    // Account 500 opens CDP to be liquidated later
    await th.openCdp(contracts, {extraEBTCAmount: dec(2, 18), extraParams: { from: accounts[500], value: dec(35, 'ether') }})
    let _cdpIdLiq = await sortedCdps.cdpOfOwnerByIndex(accounts[500], 0);
    assert.isTrue(await sortedCdps.contains(_cdpIdLiq))

    // --- Accounts to be liquidated in the test tx ---
    const _Defaulters = accounts.slice(1, 1 + _liqCnt)
    await th.openCdp_allAccounts(_Defaulters, contracts, dec(20, 'ether'), dec(1, 18))

    // check all defaulters active
    let _toLiquidateCdpIds = [];
    for (account of _Defaulters) { 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))  
         _toLiquidateCdpIds.push(_cdpId);
    }

    // Whale opens cdp to get enough debt to repay/liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})

    // Account 500 is liquidated, creates pending distribution rewards for all
    let _droppedPrice = dec(3014, 13);
    await priceFeed.setPrice(_droppedPrice)	
    await cdpManager.liquidate(_cdpIdLiq, { from: _liquidator })

    // Check Recovery Mode is true
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()));

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)
    
    const tx = await cdpManager.batchLiquidateCdps(_toLiquidateCdpIds, { from: _liquidator })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()));

    // check all defaulters liquidated
    for (account of _toLiquidateCdpIds) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 10 cdps
  it("", async () => {
    let _liqCnt = 10;
    const message = 'Test,liquidateCdps(). n = ' + _liqCnt + '. All fully liquidated. Has pending distribution rewards. In Recovery Mode'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(200, 'ether'), dec(2, 18))

    // Account 500 opens CDP to be liquidated later
    await th.openCdp(contracts, {extraEBTCAmount: dec(2, 18), extraParams: { from: accounts[500], value: dec(35, 'ether') }})
    let _cdpIdLiq = await sortedCdps.cdpOfOwnerByIndex(accounts[500], 0);
    assert.isTrue(await sortedCdps.contains(_cdpIdLiq))

    // --- Accounts to be liquidated in the test tx ---
    const _Defaulters = accounts.slice(1, 1 + _liqCnt)
    await th.openCdp_allAccounts(_Defaulters, contracts, dec(20, 'ether'), dec(1, 18))

    // check all defaulters active
    let _toLiquidateCdpIds = [];
    for (account of _Defaulters) { 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))  
         _toLiquidateCdpIds.push(_cdpId);
    }

    // Whale opens cdp to get enough debt to repay/liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})

    // Account 500 is liquidated, creates pending distribution rewards for all
    let _droppedPrice = dec(3114, 13);
    await priceFeed.setPrice(_droppedPrice)	
    await cdpManager.liquidate(_cdpIdLiq, { from: _liquidator })

    // Check Recovery Mode is true
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()));

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)
    
    const tx = await cdpManager.batchLiquidateCdps(_toLiquidateCdpIds, { from: _liquidator })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()));

    // check all defaulters liquidated
    for (account of _toLiquidateCdpIds) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 20 cdps
  it("", async () => {
    let _liqCnt = 20;
    const message = 'Test,liquidateCdps(). n = ' + _liqCnt + '. All fully liquidated. Has pending distribution rewards. In Recovery Mode'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(200, 'ether'), dec(2, 18))

    // Account 500 opens CDP to be liquidated later
    await th.openCdp(contracts, {extraEBTCAmount: dec(2, 18), extraParams: { from: accounts[500], value: dec(35, 'ether') }})
    let _cdpIdLiq = await sortedCdps.cdpOfOwnerByIndex(accounts[500], 0);
    assert.isTrue(await sortedCdps.contains(_cdpIdLiq))

    // --- Accounts to be liquidated in the test tx ---
    const _Defaulters = accounts.slice(1, 1 + _liqCnt)
    await th.openCdp_allAccounts(_Defaulters, contracts, dec(20, 'ether'), dec(1, 18))

    // check all defaulters active
    let _toLiquidateCdpIds = [];
    for (account of _Defaulters) { 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))  
         _toLiquidateCdpIds.push(_cdpId);
    }

    // Whale opens cdp to get enough debt to repay/liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})

    // Account 500 is liquidated, creates pending distribution rewards for all
    let _droppedPrice = dec(3114, 13);
    await priceFeed.setPrice(_droppedPrice)	
    await cdpManager.liquidate(_cdpIdLiq, { from: _liquidator })

    // Check Recovery Mode is true
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()));

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)
    
    const tx = await cdpManager.batchLiquidateCdps(_toLiquidateCdpIds, { from: _liquidator })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()));

    // check all defaulters liquidated
    for (account of _toLiquidateCdpIds) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 30 cdps
  it("", async () => {
    let _liqCnt = 30;
    const message = 'Test,liquidateCdps(). n = ' + _liqCnt + '. All fully liquidated. Has pending distribution rewards. In Recovery Mode'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(200, 'ether'), dec(2, 18))

    // Account 500 opens CDP to be liquidated later
    await th.openCdp(contracts, {extraEBTCAmount: dec(2, 18), extraParams: { from: accounts[500], value: dec(35, 'ether') }})
    let _cdpIdLiq = await sortedCdps.cdpOfOwnerByIndex(accounts[500], 0);
    assert.isTrue(await sortedCdps.contains(_cdpIdLiq))

    // --- Accounts to be liquidated in the test tx ---
    const _Defaulters = accounts.slice(1, 1 + _liqCnt)
    await th.openCdp_allAccounts(_Defaulters, contracts, dec(20, 'ether'), dec(1, 18))

    // check all defaulters active
    let _toLiquidateCdpIds = [];
    for (account of _Defaulters) { 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))  
         _toLiquidateCdpIds.push(_cdpId);
    }

    // Whale opens cdp to get enough debt to repay/liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})

    // Account 500 is liquidated, creates pending distribution rewards for all
    let _droppedPrice = dec(3114, 13);
    await priceFeed.setPrice(_droppedPrice)	
    await cdpManager.liquidate(_cdpIdLiq, { from: _liquidator })

    // Check Recovery Mode is true
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()));

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)
    
    const tx = await cdpManager.batchLiquidateCdps(_toLiquidateCdpIds, { from: _liquidator })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()));

    // check all defaulters liquidated
    for (account of _toLiquidateCdpIds) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 40 cdps
  it("", async () => {
    let _liqCnt = 40;
    const message = 'Test,liquidateCdps(). n = ' + _liqCnt + '. All fully liquidated. Has pending distribution rewards. In Recovery Mode'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(200, 'ether'), dec(2, 18))

    // Account 500 opens CDP to be liquidated later
    await th.openCdp(contracts, {extraEBTCAmount: dec(2, 18), extraParams: { from: accounts[500], value: dec(35, 'ether') }})
    let _cdpIdLiq = await sortedCdps.cdpOfOwnerByIndex(accounts[500], 0);
    assert.isTrue(await sortedCdps.contains(_cdpIdLiq))

    // --- Accounts to be liquidated in the test tx ---
    const _Defaulters = accounts.slice(1, 1 + _liqCnt)
    await th.openCdp_allAccounts(_Defaulters, contracts, dec(20, 'ether'), dec(1, 18))

    // check all defaulters active
    let _toLiquidateCdpIds = [];
    for (account of _Defaulters) { 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))  
         _toLiquidateCdpIds.push(_cdpId);
    }

    // Whale opens cdp to get enough debt to repay/liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})

    // Account 500 is liquidated, creates pending distribution rewards for all
    let _droppedPrice = dec(3114, 13);
    await priceFeed.setPrice(_droppedPrice)	
    await cdpManager.liquidate(_cdpIdLiq, { from: _liquidator })

    // Check Recovery Mode is true
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()));

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)
    
    const tx = await cdpManager.batchLiquidateCdps(_toLiquidateCdpIds, { from: _liquidator })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()));

    // check all defaulters liquidated
    for (account of _toLiquidateCdpIds) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 45 cdps
  it("", async () => {
    let _liqCnt = 45;
    const message = 'Test,liquidateCdps(). n = ' + _liqCnt + '. All fully liquidated. Has pending distribution rewards. In Recovery Mode'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(200, 'ether'), dec(2, 18))

    // Account 500 opens CDP to be liquidated later
    await th.openCdp(contracts, {extraEBTCAmount: dec(2, 18), extraParams: { from: accounts[500], value: dec(35, 'ether') }})
    let _cdpIdLiq = await sortedCdps.cdpOfOwnerByIndex(accounts[500], 0);
    assert.isTrue(await sortedCdps.contains(_cdpIdLiq))

    // --- Accounts to be liquidated in the test tx ---
    const _Defaulters = accounts.slice(1, 1 + _liqCnt)
    await th.openCdp_allAccounts(_Defaulters, contracts, dec(20, 'ether'), dec(1, 18))

    // check all defaulters active
    let _toLiquidateCdpIds = [];
    for (account of _Defaulters) { 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))  
         _toLiquidateCdpIds.push(_cdpId);
    }

    // Whale opens cdp to get enough debt to repay/liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})

    // Account 500 is liquidated, creates pending distribution rewards for all
    let _droppedPrice = dec(3114, 13);
    await priceFeed.setPrice(_droppedPrice)	
    await cdpManager.liquidate(_cdpIdLiq, { from: _liquidator })

    // Check Recovery Mode is true
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()));

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)
    
    const tx = await cdpManager.batchLiquidateCdps(_toLiquidateCdpIds, { from: _liquidator })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()));

    // check all defaulters liquidated
    for (account of _toLiquidateCdpIds) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // --- BatchLiquidateCdps ---  

  // 10 cdps
  it("", async () => {
    let _liqCnt = 10;
    const message = 'Test,batchLiquidateCdps(). n = ' + _liqCnt + '. All cdps fully offset. Have pending distribution rewards'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(200, 'ether'), dec(2, 18))

    // Account 500 opens CDP to be liquidated later
    await th.openCdp(contracts, {extraEBTCAmount: dec(2, 18), extraParams: { from: accounts[500], value: dec(35, 'ether') }})
    let _cdpIdLiq = await sortedCdps.cdpOfOwnerByIndex(accounts[500], 0);
    assert.isTrue(await sortedCdps.contains(_cdpIdLiq))

    // --- Accounts to be liquidated in the test tx ---
    const _Defaulters = accounts.slice(1, 1 + _liqCnt)
    await th.openCdp_allAccounts(_Defaulters, contracts, dec(20, 'ether'), dec(1, 18))

    // check all defaulters active
    let _toLiquidateCdpIds = [];
    for (account of _Defaulters) { 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))  
         _toLiquidateCdpIds.push(_cdpId);
    }

    // Whale opens cdp to get enough debt to repay/liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})

    // Account 500 is liquidated, creates pending distribution rewards for all
    let _droppedPrice = dec(3114, 13);
    await priceFeed.setPrice(_droppedPrice)	
    await cdpManager.liquidate(_cdpIdLiq, { from: _liquidator })

    // Check Recovery Mode is true
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()));

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)
    
    const tx = await cdpManager.batchLiquidateCdps(_toLiquidateCdpIds, { from: _liquidator })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()));

    // check all defaulters liquidated
    for (account of _toLiquidateCdpIds) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })


  // 40 cdps
  it("", async () => {
    let _liqCnt = 40;
    const message = 'Test,batchLiquidateCdps(). n = ' + _liqCnt + '. All cdps fully offset. Have pending distribution rewards'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(200, 'ether'), dec(2, 18))

    // Account 500 opens CDP to be liquidated later
    await th.openCdp(contracts, {extraEBTCAmount: dec(2, 18), extraParams: { from: accounts[500], value: dec(35, 'ether') }})
    let _cdpIdLiq = await sortedCdps.cdpOfOwnerByIndex(accounts[500], 0);
    assert.isTrue(await sortedCdps.contains(_cdpIdLiq))

    // --- Accounts to be liquidated in the test tx ---
    const _Defaulters = accounts.slice(1, 1 + _liqCnt)
    await th.openCdp_allAccounts(_Defaulters, contracts, dec(20, 'ether'), dec(1, 18))

    // check all defaulters active
    let _toLiquidateCdpIds = [];
    for (account of _Defaulters) { 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))  
         _toLiquidateCdpIds.push(_cdpId);
    }

    // Whale opens cdp to get enough debt to repay/liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})

    // Account 500 is liquidated, creates pending distribution rewards for all
    let _droppedPrice = dec(3314, 13);
    await priceFeed.setPrice(_droppedPrice)	
    await cdpManager.liquidate(_cdpIdLiq, { from: _liquidator })

    // Check Recovery Mode is true
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()));

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)
    
    const tx = await cdpManager.batchLiquidateCdps(_toLiquidateCdpIds, { from: _liquidator })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()));

    // check all defaulters liquidated
    for (account of _toLiquidateCdpIds) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 45 cdps
  it("", async () => {
    let _liqCnt = 45;
    const message = 'Test,batchLiquidateCdps(). n = ' + _liqCnt + '. All cdps fully offset. Have pending distribution rewards'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(200, 'ether'), dec(2, 18))

    // Account 500 opens CDP to be liquidated later
    await th.openCdp(contracts, {extraEBTCAmount: dec(2, 18), extraParams: { from: accounts[500], value: dec(35, 'ether') }})
    let _cdpIdLiq = await sortedCdps.cdpOfOwnerByIndex(accounts[500], 0);
    assert.isTrue(await sortedCdps.contains(_cdpIdLiq))

    // --- Accounts to be liquidated in the test tx ---
    const _Defaulters = accounts.slice(1, 1 + _liqCnt)
    await th.openCdp_allAccounts(_Defaulters, contracts, dec(20, 'ether'), dec(1, 18))

    // check all defaulters active
    let _toLiquidateCdpIds = [];
    for (account of _Defaulters) { 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))  
         _toLiquidateCdpIds.push(_cdpId);
    }

    // Whale opens cdp to get enough debt to repay/liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})

    // Account 500 is liquidated, creates pending distribution rewards for all
    let _droppedPrice = dec(3314, 13);
    await priceFeed.setPrice(_droppedPrice)	
    await cdpManager.liquidate(_cdpIdLiq, { from: _liquidator })

    // Check Recovery Mode is true
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()));

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)
    
    const tx = await cdpManager.batchLiquidateCdps(_toLiquidateCdpIds, { from: _liquidator })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()));

    // check all defaulters liquidated
    for (account of _toLiquidateCdpIds) { assert.isFalse(await sortedCdps.contains(account)) }

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // 50 cdps
  it("", async () => {
    let _liqCnt = 50;
    const message = 'Test,batchLiquidateCdps(). n = ' + _liqCnt + '. All cdps fully offset. Have pending distribution rewards'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(101, 111), contracts, dec(200, 'ether'), dec(2, 18))

    // Account 500 opens CDP to be liquidated later
    await th.openCdp(contracts, {extraEBTCAmount: dec(2, 18), extraParams: { from: accounts[500], value: dec(35, 'ether') }})
    let _cdpIdLiq = await sortedCdps.cdpOfOwnerByIndex(accounts[500], 0);
    assert.isTrue(await sortedCdps.contains(_cdpIdLiq))

    // --- Accounts to be liquidated in the test tx ---
    const _Defaulters = accounts.slice(1, 1 + _liqCnt)
    await th.openCdp_allAccounts(_Defaulters, contracts, dec(20, 'ether'), dec(1, 18))

    // check all defaulters active
    let _toLiquidateCdpIds = [];
    for (account of _Defaulters) { 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))  
         _toLiquidateCdpIds.push(_cdpId);
    }

    // Whale opens cdp to get enough debt to repay/liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})

    // Account 500 is liquidated, creates pending distribution rewards for all
    let _droppedPrice = dec(3314, 13);
    await priceFeed.setPrice(_droppedPrice)	
    await cdpManager.liquidate(_cdpIdLiq, { from: _liquidator })

    // Check Recovery Mode is true
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()));

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)
    
    const tx = await cdpManager.batchLiquidateCdps(_toLiquidateCdpIds, { from: _liquidator })
    assert.isTrue(tx.receipt.status)

    // Check Recovery Mode is true after liquidations
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()));

    // check all defaulters liquidated
    for (account of _toLiquidateCdpIds) { assert.isFalse(await sortedCdps.contains(account)) }

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
	
    fs.writeFile('gasTest/outputs/liquidateCdpsRecoveryModeGasData.csv', _content, (err) => {
        if (err) { 
            console.log(err) 
        } else {
            console.log("LiquidateCdpsRecoveryMode() gas test data written to gasTest/outputs/liquidateCdpsRecoveryModeGasData.csv")
        }
    })
  })
})