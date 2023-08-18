/* Script that logs gas costs for Liquity operations under various conditions. 
  Note: uses Mocha testing structure, but simply prints gas costs of transactions. No assertions.
*/
const fs = require('fs')
const deploymentHelper = require("../utils/deploymentHelpers.js")
const testHelpers = require("../utils/testHelpers.js")

const {TestHelper: th, TimeValues: timeValues } = testHelpers
const dec = th.dec
const toBN = th.toBN

const ZERO_ADDRESS = th.ZERO_ADDRESS
const _100pct = th._100pct

contract('Gas cost tests', async accounts => {

  const [owner] = accounts;
  const [A,B,C,D,E,F,G,H,I, J] = accounts;
  const _10_Accounts = accounts.slice(0, 10)
  const _20_Accounts = accounts.slice(0, 20)
  const _30_Accounts = accounts.slice(0, 30)
  const _40_Accounts = accounts.slice(0, 40)
  const _50_Accounts = accounts.slice(0, 50)
  const _100_Accounts = accounts.slice(0, 100)

  const whale = accounts[999]
  const bountyAddress = accounts[998]
  const lpRewardsAddress = accounts[999]

  const address_0 = '0x0000000000000000000000000000000000000000'

  let contracts

  let priceFeed
  let ebtcToken
  let sortedCdps
  let cdpManager
  let activePool
  let stabilityPool
  let defaultPool
  let borrowerOperations
  let hintHelpers
  let functionCaller

  let data = []


  beforeEach(async () => {
    contracts = await deploymentHelper.deployTesterContractsHardhat()
    const LQTYContracts = await deploymentHelper.deployLQTYContracts(bountyAddress, lpRewardsAddress)

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
	  
    await deploymentHelper.connectCoreContracts(contracts, LQTYContracts)
    await deploymentHelper.connectLQTYContractsToCore(LQTYContracts, contracts)
  })

  // ---TESTS ---

  it("runs the test helper", async () => {
    assert.equal(th.getDifference('2000', '1000'), 1000)
  })

  it.only("helper - getBorrowerOpsListHint(): returns the right position in the list", async () => {
    // Accounts A - J open cdps at sequentially lower ICR
    await th.openCdp(contracts, {extraEBTCAmount: dec(1, 18), extraParams: { from: A, value: dec(35, 'ether') }})	
    let _cdpIdA = await sortedCdps.cdpOfOwnerByIndex(A, 0);
    console.log("_cdpIdA=" + _cdpIdA + ",icr=" + (await cdpManager.getNominalICR(_cdpIdA)));
    await th.openCdp(contracts, {extraEBTCAmount: dec(1, 18), extraParams: { from: B, value: dec(37, 'ether') }})	
    let _cdpIdB = await sortedCdps.cdpOfOwnerByIndex(B, 0);
    console.log("_cdpIdB=" + _cdpIdB + ",icr=" + (await cdpManager.getNominalICR(_cdpIdB)));
    await th.openCdp(contracts, {extraEBTCAmount: dec(1, 18), extraParams: { from: C, value: dec(39, 'ether') }})	
    let _cdpIdC = await sortedCdps.cdpOfOwnerByIndex(C, 0);
    console.log("_cdpIdC=" + _cdpIdC + ",icr=" + (await cdpManager.getNominalICR(_cdpIdC)));
    await th.openCdp(contracts, {extraEBTCAmount: dec(1, 18), extraParams: { from: D, value: dec(41, 'ether') }})	
    let _cdpIdD = await sortedCdps.cdpOfOwnerByIndex(D, 0);
    console.log("_cdpIdD=" + _cdpIdD + ",icr=" + (await cdpManager.getNominalICR(_cdpIdD)));
    await th.openCdp(contracts, {extraEBTCAmount: dec(1, 18), extraParams: { from: E, value: dec(43, 'ether') }})	
    let _cdpIdE = await sortedCdps.cdpOfOwnerByIndex(E, 0);
    console.log("_cdpIdE=" + _cdpIdE + ",icr=" + (await cdpManager.getNominalICR(_cdpIdE)));
    await th.openCdp(contracts, {extraEBTCAmount: dec(1, 18), extraParams: { from: F, value: dec(45, 'ether') }})	
    let _cdpIdF = await sortedCdps.cdpOfOwnerByIndex(F, 0);
    console.log("_cdpIdF=" + _cdpIdF + ",icr=" + (await cdpManager.getNominalICR(_cdpIdF)));
    await th.openCdp(contracts, {extraEBTCAmount: dec(1, 18), extraParams: { from: G, value: dec(47, 'ether') }})	
    let _cdpIdG = await sortedCdps.cdpOfOwnerByIndex(G, 0);
    console.log("_cdpIdG=" + _cdpIdG + ",icr=" + (await cdpManager.getNominalICR(_cdpIdG)));
    await th.openCdp(contracts, {extraEBTCAmount: dec(1, 18), extraParams: { from: H, value: dec(49, 'ether') }})	
    let _cdpIdH = await sortedCdps.cdpOfOwnerByIndex(H, 0);
    console.log("_cdpIdH=" + _cdpIdH + ",icr=" + (await cdpManager.getNominalICR(_cdpIdH)));
    await th.openCdp(contracts, {extraEBTCAmount: dec(1, 18), extraParams: { from: I, value: dec(51, 'ether') }})	
    let _cdpIdI = await sortedCdps.cdpOfOwnerByIndex(I, 0);
    console.log("_cdpIdI=" + _cdpIdI + ",icr=" + (await cdpManager.getNominalICR(_cdpIdI)));
    await th.openCdp(contracts, {extraEBTCAmount: dec(1, 18), extraParams: { from: J, value: dec(53, 'ether') }})	
    let _cdpIdJ = await sortedCdps.cdpOfOwnerByIndex(J, 0);
    console.log("_cdpIdJ=" + _cdpIdJ + ",icr=" + (await cdpManager.getNominalICR(_cdpIdJ)));

    // Between F and G
    let amount = dec(1, 18)
    let debt = (await th.getCompositeDebt(contracts, amount));
    let {upperHint, lowerHint, newNICR} = await th.getBorrowerOpsListHint(contracts, dec(40, 'ether'), debt)  
    assert.equal(upperHint, _cdpIdG)
    assert.equal(lowerHint, _cdpIdF)

    // Bottom of the list
    amount = dec(1, 18)
    debt = (await th.getCompositeDebt(contracts, amount));
    ({upperHint, lowerHint, newNICR} = await th.getBorrowerOpsListHint(contracts, dec(60, 'ether'), debt)) 
     
    assert.equal(upperHint, th.DUMMY_BYTES32)
    assert.equal(lowerHint, _cdpIdJ)

    // Top of the list
    amount = dec(1, 18)
    debt = (await th.getCompositeDebt(contracts, amount));
    ({upperHint, lowerHint} = await th.getBorrowerOpsListHint(contracts, dec(30, 'ether'), debt))
     
    assert.equal(upperHint, _cdpIdA)
    assert.equal(lowerHint, th.DUMMY_BYTES32)
  })

  // --- Cdp Manager function calls ---

  // --- openCdp() ---

  // it("", async () => {
  //   const message = 'openCdp(), single account, 0 existing Cdps in system. Adds 10 ether and issues 100 EBTC'
  //   const tx = await borrowerOperations.openCdp(dec(100, 18), accounts[2], ZERO_ADDRESS, { from: accounts[2], value: dec(10, 'ether') })
  //   const gas = th.gasUsed(tx)
  //   th.logGas(gas, message)

  //   th.appendData({ gas: gas }, message, data)
  // })

  // it("", async () => {
  //   const message = 'openCdp(), single account, 1 existing Cdp in system. Adds 10 ether and issues 100 EBTC'
  //   await borrowerOperations.openCdp(dec(100, 18), accounts[1], ZERO_ADDRESS, { from: accounts[1], value: dec(10, 'ether') })

  //   const tx = await borrowerOperations.openCdp(dec(100, 18), accounts[2], ZERO_ADDRESS, { from: accounts[2], value: dec(10, 'ether') })
  //   const gas = th.gasUsed(tx)
  //   th.logGas(gas, message)

  //   th.appendData({ gas: gas }, message, data)
  // })

  // it("", async () => {
  //   const message = 'openCdp(), single account, Inserts between 2 existing CDs in system. Adds 10 ether and issues 80 EBTC. '

  //   await borrowerOperations.openCdp(dec(100, 18), accounts[1], ZERO_ADDRESS, { from: accounts[1], value: dec(10, 'ether') })
  //   await borrowerOperations.openCdp(dec(50, 18), accounts[2], ZERO_ADDRESS, { from: accounts[2], value: dec(10, 'ether') })

  //   const tx = await borrowerOperations.openCdp(dec(80, 18), accounts[3], ZERO_ADDRESS, { from: accounts[3], value: dec(10, 'ether') })

  //   const gas = th.gasUsed(tx)
  //   th.logGas(gas, message)

  //   th.appendData({ gas: gas }, message, data)
  // })

  // it("", async () => {
  //   const message = 'openCdp(), 10 accounts, each account adds 10 ether and issues 100 EBTC'

  //   const amountETH = dec(10, 'ether')
  //   const amountEBTC = 0
  //   const gasResults = await th.openCdp_allAccounts(_10_Accounts, contracts, amountETH, amountEBTC)
  //   th.logGasMetrics(gasResults, message)
  //   th.logAllGasCosts(gasResults)

  //   th.appendData(gasResults, message, data)
  // })

  // it("", async () => {
  //   const message = 'openCdp(), 10 accounts, each account adds 10 ether and issues less EBTC than the previous one'
  //   const amountETH = dec(10, 'ether')
  //   const amountEBTC = 200
  //   const gasResults = await th.openCdp_allAccounts_decreasingEBTCAmounts(_10_Accounts, contracts, amountETH, amountEBTC)
  //   th.logGasMetrics(gasResults, message)
  //   th.logAllGasCosts(gasResults)

  //   th.appendData(gasResults, message, data)
  // })

  it("", async () => {
    const message = 'openCdp(), 50 accounts, each account adds random ether and random EBTC'
    const gasResults = await th.openCdp_allAccounts_randomETH_randomEBTC(150, 290, _50_Accounts, contracts, 0.05428, 0.05428, true)
    th.logGasMetrics(gasResults, message)
    th.logAllGasCosts(gasResults)

    th.appendData(gasResults, message, data)
  })

  // --- adjustCdp ---

  // it("", async () => {
  //   const message = 'adjustCdp(). ETH/EBTC Increase/Increase. 10 accounts, each account adjusts up -  1 ether and 100 EBTC'
  //   await borrowerOperations.openCdp(0, accounts[999], ZERO_ADDRESS, { from: accounts[999], value: dec(100, 'ether') })

  //   const amountETH = dec(10, 'ether')
  //   const amountEBTC = dec(100, 18)
  //   await th.openCdp_allAccounts(_10_Accounts, contracts, amountETH, amountEBTC)


  //   const amountETH_2 = dec(1, 'ether')
  //   const amountEBTC_2 = dec(100, 18)
  //   const gasResults = await th.adjustCdp_allAccounts(_10_Accounts, contracts, amountETH_2, amountEBTC_2)

  //   th.logGasMetrics(gasResults, message)
  //   th.logAllGasCosts(gasResults)

  //   th.appendData(gasResults, message, data)
  // })

  // it("", async () => {
  //   const message = 'adjustCdp(). ETH/EBTC Decrease/Decrease. 10 accounts, each account adjusts down by 0.1 ether and 10 EBTC'
  //   await borrowerOperations.openCdp(0, accounts[999], ZERO_ADDRESS, { from: accounts[999], value: dec(100, 'ether') })

  //   const amountETH = dec(10, 'ether')
  //   const amountEBTC = dec(100, 18)
  //   await th.openCdp_allAccounts(_10_Accounts, contracts, amountETH, amountEBTC)

  //   const amountETH_2 = "-100000000000000000"  // coll decrease of 0.1 ETH 
  //   const amountEBTC_2 = "-10000000000000000000" // debt decrease of 10 EBTC 
  //   const gasResults = await th.adjustCdp_allAccounts(_10_Accounts, contracts, amountETH_2, amountEBTC_2)

  //   th.logGasMetrics(gasResults, message)
  //   th.logAllGasCosts(gasResults)

  //   th.appendData(gasResults, message, data)
  // })

  // it("", async () => {
  //   const message = 'adjustCdp(). ETH/EBTC Increase/Decrease. 10 accounts, each account adjusts up by 0.1 ether and down by 10 EBTC'
  //   await borrowerOperations.openCdp(0, accounts[999], ZERO_ADDRESS, { from: accounts[999], value: dec(100, 'ether') })

  //   const amountETH = dec(10, 'ether')
  //   const amountEBTC = dec(100, 18)
  //   await th.openCdp_allAccounts(_10_Accounts, contracts, amountETH, amountEBTC)

  //   const amountETH_2 = "100000000000000000"  // coll increase of 0.1 ETH 
  //   const amountEBTC_2 = "-10000000000000000000" // debt decrease of 10 EBTC 
  //   const gasResults = await th.adjustCdp_allAccounts(_10_Accounts, contracts, amountETH_2, amountEBTC_2)

  //   th.logGasMetrics(gasResults, message)
  //   th.logAllGasCosts(gasResults)

  //   th.appendData(gasResults, message, data)
  // })

  // it("", async () => {
  //   const message = 'adjustCdp(). 30 accounts, each account adjusts up by random amounts. No size range transition'
  //   await borrowerOperations.openCdp(0, accounts[999], ZERO_ADDRESS, { from: accounts[999], value: dec(100, 'ether') })

  //   const amountETH = dec(10, 'ether')
  //   const amountEBTC = dec(100, 18)
  //   await th.openCdp_allAccounts(_30_Accounts, contracts, amountETH, amountEBTC)

  //   // Randomly add between 1-9 ETH, and withdraw 1-100 EBTC
  //   const gasResults = await th.adjustCdp_allAccounts_randomAmount(_30_Accounts, contracts, 1, 9, 1, 100)

  //   th.logGasMetrics(gasResults, message)
  //   th.logAllGasCosts(gasResults)

  //   th.appendData(gasResults, message, data)
  // })

  it("", async () => {
    const message = 'adjustCdp(). 40 accounts, each account adjusts up by random amounts. HAS size range transition'

    const amountETH = dec(100, 'ether')
    const amountEBTC = dec(1, 18)
    await th.openCdp_allAccounts(_40_Accounts, contracts, amountETH, amountEBTC)
    
    let _allCdpIds = [];
    for (let i = 0;i < _40_Accounts.length;i++){ 
         let account = accounts[i];
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))  
         _allCdpIds.push(_cdpId);		
    }
    // Randomly add between 1-9 ETH, and withdraw 1-1.5 EBTC
    const gasResults = await th.adjustCdp_allAccounts_randomAmount(_40_Accounts, contracts, 1, 9, 1, 1.5, _allCdpIds)

    th.logGasMetrics(gasResults, message)
    th.logAllGasCosts(gasResults)

    th.appendData(gasResults, message, data)
  })

  // --- closeCdp() ---

  it("", async () => {
    const message = 'closeCdp(), 10 accounts, 1 account closes its cdp'

    await th.openCdp_allAccounts_decreasingEBTCAmounts(_10_Accounts, contracts, dec(400, 'ether'), 21)
    let _cdpId = await sortedCdps.cdpOfOwnerByIndex(accounts[1], 0);

    const tx = await borrowerOperations.closeCdp(_cdpId, { from: accounts[1] })
    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  it("", async () => {
    const message = 'closeCdp(), 20 accounts, each account adds 10 ether and issues less EBTC than the previous one. First 10 accounts close their cdp. '

    await th.openCdp_allAccounts_decreasingEBTCAmounts(_20_Accounts, contracts, dec(400, 'ether'), 21)
    
    let _allCdpIds = [];
    let _allCdpOwners = [];
    for (let i = 0;i < _20_Accounts.length;i++){ 
         let account = accounts[i];
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))  
         _allCdpIds.push(_cdpId);
         _allCdpOwners.push(account);	
         if (i >= 10){
             break;
         } 
    }
    
    const gasResults = await th.closeCdp_allAccounts(_allCdpOwners, contracts, _allCdpIds)

    th.logGasMetrics(gasResults, message)
    th.logAllGasCosts(gasResults)

    th.appendData(gasResults, message, data)
  })

  // --- addColl() ---

  // it("", async () => {
  //   const message = 'addColl(), second deposit, 0 other Cdps in system. Adds 10 ether'
  //   await th.openCdp_allAccounts([accounts[2]], contracts, dec(10, 'ether'), 0)

  //   const tx = await borrowerOperations.addColl(accounts[2], accounts[2], { from: accounts[2], value: dec(10, 'ether') })
  //   const gas = th.gasUsed(tx)
  //   th.logGas(gas, message)

  //   th.appendData({ gas: gas }, message, data)
  // })

  // it("", async () => {
  //   const message = 'addColl(), second deposit, 10 existing Cdps in system. Adds 10 ether'
  //   await th.openCdp_allAccounts(_10_Accounts, contracts, dec(10, 'ether'), 0)

  //   await th.openCdp_allAccounts([accounts[99]], contracts, dec(10, 'ether'), 0)
  //   const tx = await borrowerOperations.addColl(accounts[99], accounts[99], { from: accounts[99], value: dec(10, 'ether') })
  //   const gas = th.gasUsed(tx)
  //   th.logGas(gas, message)

  //   th.appendData({ gas: gas }, message, data)
  // })

  // it("", async () => {
  //   const message = 'addColl(), second deposit, 10 accounts, each account adds 10 ether'
  //   await th.openCdp_allAccounts(_10_Accounts, contracts, dec(10, 'ether'), 0)

  //   const gasResults = await th.addColl_allAccounts(_10_Accounts, contracts, dec(10, 'ether'))
  //   th.logGasMetrics(gasResults, message)
  //   th.logAllGasCosts(gasResults)

  //   th.appendData(gasResults, message, data)
  // })

  it("", async () => {
    const message = 'addColl(), second deposit, 30 accounts, each account adds random amount. No size range transition'
    const amount = dec(10, 'ether')
    await th.openCdp_allAccounts(_30_Accounts, contracts, dec(100, 'ether'), dec(1, 18))
    
    let _allCdpIds = [];
    for (let i = 0;i < _30_Accounts.length;i++){ 
         let account = accounts[i];
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))  
         _allCdpIds.push(_cdpId);		
    }

    const gasResults = await th.addColl_allAccounts_randomAmount(0.000000001, 10000, _30_Accounts, contracts, _allCdpIds)
    th.logGasMetrics(gasResults, message)
    th.logAllGasCosts(gasResults)

    th.appendData(gasResults, message, data)
  })

  // --- withdrawColl() ---

  // it("", async () => {
  //   const message = 'withdrawColl(), first withdrawal. 10 accounts in system. 1 account withdraws 5 ether'
  //   await th.openCdp_allAccounts(_10_Accounts, contracts, dec(10, 'ether'), 0)

  //   const tx = await borrowerOperations.withdrawColl(dec(5, 'ether'), accounts[9], ZERO_ADDRESS, { from: accounts[9] })
  //   const gas = th.gasUsed(tx)
  //   th.logGas(gas, message)

  //   th.appendData({ gas: gas }, message, data)
  // })

  // it("", async () => {
  //   const message = 'withdrawColl(), first withdrawal, 10 accounts, each account withdraws 5 ether'
  //   await th.openCdp_allAccounts(_10_Accounts, contracts, dec(10, 'ether'), 0)

  //   const gasResults = await th.withdrawColl_allAccounts(_10_Accounts, contracts, dec(5, 'ether'))
  //   th.logGasMetrics(gasResults, message)
  //   th.logAllGasCosts(gasResults)

  //   th.appendData(gasResults, message, data)
  // })

  // it("", async () => {
  //   const message = 'withdrawColl(), second withdrawal, 10 accounts, each account withdraws 5 ether'
  //   await th.openCdp_allAccounts(_10_Accounts, contracts, dec(10, 'ether'), 0)
  //   await th.withdrawColl_allAccounts(_10_Accounts, contracts, dec(1, 'ether'))

  //   const gasResults = await th.withdrawColl_allAccounts(_10_Accounts, contracts, dec(5, 'ether'))
  //   th.logGasMetrics(gasResults, message)
  //   th.logAllGasCosts(gasResults)

  //   th.appendData(gasResults, message, data)
  // })

  it("", async () => {
    const message = 'withdrawColl(), first withdrawal, 30 accounts, each account withdraws random amount. HAS size range transition'
    await th.openCdp_allAccounts(_30_Accounts, contracts, dec(100, 'ether'), dec(1, 18))
    
    let _allCdpIds = [];
    for (let i = 0;i < _30_Accounts.length;i++){ 
         let account = accounts[i];
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))  
         _allCdpIds.push(_cdpId);		
    }

    const gasResults = await th.withdrawColl_allAccounts_randomAmount(1, 8, _30_Accounts, contracts, _allCdpIds)
    th.logGasMetrics(gasResults, message)
    th.logAllGasCosts(gasResults)

    th.appendData(gasResults, message, data)
  })

  it("", async () => {
    const message = 'withdrawColl(), second withdrawal, 10 accounts, each account withdraws random amount'
    await th.openCdp_allAccounts(_10_Accounts, contracts, dec(100, 'ether'), dec(1, 18))
    
    let _allCdpIds = [];
    for (let i = 0;i < _10_Accounts.length;i++){ 
         let account = accounts[i];
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))  
         _allCdpIds.push(_cdpId);		
    }
    await th.withdrawColl_allAccounts(_10_Accounts, contracts, dec(1, 'ether'), _allCdpIds)

    const gasResults = await th.withdrawColl_allAccounts_randomAmount(1, 1.5, _10_Accounts, contracts, _allCdpIds)
    th.logGasMetrics(gasResults, message)
    th.logAllGasCosts(gasResults)

    th.appendData(gasResults, message, data)
  })

  // --- withdrawEBTC() --- 

  // it("", async () => {
  //   const message = 'withdrawEBTC(), first withdrawal, 10 accounts, each account withdraws 100 EBTC'
  //   await th.openCdp_allAccounts(_10_Accounts, contracts, dec(10, 'ether'), 0)

  //   const gasResults = await th.withdrawEBTC_allAccounts(_10_Accounts, contracts, dec(100, 18))
  //   th.logGasMetrics(gasResults, message)
  //   th.logAllGasCosts(gasResults)

  //   th.appendData(gasResults, message, data)
  // })

  // it("", async () => {
  //   const message = 'withdrawEBTC(), second withdrawal, 10 accounts, each account withdraws 100 EBTC'
  //   await th.openCdp_allAccounts(_10_Accounts, contracts, dec(10, 'ether'), 0)
  //   await th.withdrawEBTC_allAccounts(_10_Accounts, contracts, dec(100, 18))

  //   const gasResults = await th.withdrawEBTC_allAccounts(_10_Accounts, contracts, dec(100, 18))
  //   th.logGasMetrics(gasResults, message)
  //   th.logAllGasCosts(gasResults)

  //   th.appendData(gasResults, message, data)
  // })

  it("", async () => {
    const message = 'withdrawEBTC(), first withdrawal, 30 accounts, each account withdraws a random EBTC amount'
    await th.openCdp_allAccounts(_30_Accounts, contracts, dec(10, 'ether'), dec(1, 18))
    
    let _allCdpIds = [];
    for (let i = 0;i < _30_Accounts.length;i++){ 
         let account = accounts[i];
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))  
         _allCdpIds.push(_cdpId);		
    }

    const gasResults = await th.withdrawEBTC_allAccounts_randomAmount(1, 1.8, _30_Accounts, contracts, _allCdpIds)
    th.logGasMetrics(gasResults, message)
    th.logAllGasCosts(gasResults)

    th.appendData(gasResults, message, data)
  })

  it("", async () => {
    const message = 'withdrawEBTC(), second withdrawal, 30 accounts, each account withdraws a random EBTC amount'
    await th.openCdp_allAccounts(_30_Accounts, contracts, dec(100, 'ether'), dec(1, 18))
    
    let _allCdpIds = [];
    for (let i = 0;i < _30_Accounts.length;i++){ 
         let account = accounts[i];
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))  
         _allCdpIds.push(_cdpId);		
    }
    await th.withdrawEBTC_allAccounts(_30_Accounts, contracts, dec(1, 18), _allCdpIds)

    const gasResults = await th.withdrawEBTC_allAccounts_randomAmount(1, 1.5, _30_Accounts, contracts, _allCdpIds)
    th.logGasMetrics(gasResults, message)
    th.logAllGasCosts(gasResults)

    th.appendData(gasResults, message, data)
  })

  // --- repayEBTC() ---

  // it("", async () => {
  //   const message = 'repayEBTC(), partial repayment, 10 accounts, repay 30 EBTC (of 100 EBTC)'
  //   await th.openCdp_allAccounts(_10_Accounts, contracts, dec(10, 'ether'), 0)
  //   await th.withdrawEBTC_allAccounts(_10_Accounts, contracts, dec(100, 18))

  //   const gasResults = await th.repayEBTC_allAccounts(_10_Accounts, contracts, dec(30, 18))
  //   th.logGasMetrics(gasResults, message)
  //   th.logAllGasCosts(gasResults)

  //   th.appendData(gasResults, message, data)
  // })

  // it("", async () => {
  //   const message = 'repayEBTC(), second partial repayment, 10 accounts, repay 30 EBTC (of 70 EBTC)'
  //   await th.openCdp_allAccounts(_30_Accounts, contracts, dec(10, 'ether'), 0)
  //   await th.withdrawEBTC_allAccounts(_30_Accounts, contracts, dec(100, 18))
  //   await th.repayEBTC_allAccounts(_30_Accounts, contracts, dec(30, 18))

  //   const gasResults = await th.repayEBTC_allAccounts(_30_Accounts, contracts, dec(30, 18))
  //   th.logGasMetrics(gasResults, message)
  //   th.logAllGasCosts(gasResults)

  //   th.appendData(gasResults, message, data)
  // })

  it("", async () => {
    const message = 'repayEBTC(), partial repayment, 30 accounts, repay random amount of EBTC'
    await th.openCdp_allAccounts(_30_Accounts, contracts, dec(100, 'ether'), dec(1, 18))
    
    let _allCdpIds = [];
    for (let i = 0;i < _30_Accounts.length;i++){ 
         let account = accounts[i];
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))  
         _allCdpIds.push(_cdpId);		
    }
    await th.withdrawEBTC_allAccounts(_30_Accounts, contracts, dec(1, 18), _allCdpIds)

    const gasResults = await th.repayEBTC_allAccounts_randomAmount(1, 1.5, _30_Accounts, contracts, _allCdpIds)
    th.logGasMetrics(gasResults, message)
    th.logAllGasCosts(gasResults)

    th.appendData(gasResults, message, data)
  })

  // it("", async () => {
  //   const message = 'repayEBTC(), first repayment, 10 accounts, repay in full (100 of 100 EBTC)'
  //   await th.openCdp_allAccounts(_10_Accounts, contracts, dec(10, 'ether'), 0)
  //   await th.withdrawEBTC_allAccounts(_10_Accounts, contracts, dec(100, 18))

  //   const gasResults = await th.repayEBTC_allAccounts(_10_Accounts, contracts, dec(100, 18))
  //   th.logGasMetrics(gasResults, message)
  //   th.logAllGasCosts(gasResults)

  //   th.appendData(gasResults, message, data)
  // })

  it("", async () => {
    const message = 'repayEBTC(), first repayment, 30 accounts, repay in full'
    await th.openCdp_allAccounts(_30_Accounts, contracts, dec(100, 'ether'), dec(1, 18))
    
    let _allCdpIds = [];
    for (let i = 0;i < _30_Accounts.length;i++){ 
         let account = accounts[i];
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))  
         _allCdpIds.push(_cdpId);		
    }
	
    await th.withdrawEBTC_allAccounts(_30_Accounts, contracts, dec(1, 18), _allCdpIds)

    const gasResults = await th.repayEBTC_allAccounts(_30_Accounts, contracts, dec(1, 18), _allCdpIds)
    th.logGasMetrics(gasResults, message)
    th.logAllGasCosts(gasResults)

    th.appendData(gasResults, message, data)
  })

  // --- getICR() ---

  it("", async () => {
    const message = 'single getICR() call'

    await th.openCdp_allAccounts([accounts[1]], contracts, dec(200, 'ether'), dec(1, 18))
    let _cdpId = await sortedCdps.cdpOfOwnerByIndex(accounts[1], 0);
    const randEBTCAmount = th.randAmountInWei(1, 10)
    await borrowerOperations.withdrawEBTC(_cdpId, randEBTCAmount, accounts[1], accounts[1], { from: accounts[1] })

    const price = await priceFeed.getPrice()
    const tx = await functionCaller.cdpManager_getCurrentICR(accounts[1], price)

    const gas = th.gasUsed(tx) - 21000
    th.logGas(gas, message)
  })

  it("", async () => {
    const message = 'getICR(), Cdps with 10 ether and 100 EBTC withdrawn'
    await th.openCdp_allAccounts(_10_Accounts, contracts, dec(200, 'ether'), dec(1, 18))

    const gasResults = await th.getCurrentICR_allAccounts(_10_Accounts, contracts, functionCaller)
    th.logGasMetrics(gasResults, message)
    th.logAllGasCosts(gasResults)

    th.appendData(gasResults, message, data)
  })

  it("", async () => {
    const message = 'getICR(), Cdps with 10 ether and random EBTC amount withdrawn'
    await th.openCdp_allAccounts(_10_Accounts, contracts, dec(200, 'ether'), dec(1, 18))
    
    let _allCdpIds = [];
    for (let i = 0;i < _10_Accounts.length;i++){ 
         let account = accounts[i];
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))  
         _allCdpIds.push(_cdpId);		
    }
    await th.withdrawEBTC_allAccounts_randomAmount(1, 10, _10_Accounts, contracts, _allCdpIds)
	
    const gasResults = await th.getCurrentICR_allAccounts(_10_Accounts, contracts, functionCaller)
    th.logGasMetrics(gasResults, message)
    th.logAllGasCosts(gasResults)

    th.appendData(gasResults, message, data)
  })

  // --- getICR() with pending distribution rewards ---

  it("", async () => {
    const message = 'single getICR() call, WITH pending rewards'

    const randEBTCAmount = th.randAmountInWei(1, 10)
    let _randColl = toBN(randEBTCAmount.toString()).div(await priceFeed.getPrice()).mul(toBN('2000000000000000000'));
    await th.openCdp(contracts, {extraEBTCAmount: randEBTCAmount, extraParams: { from: accounts[1], value: _randColl }})
    let _cdpId = await sortedCdps.cdpOfOwnerByIndex(accounts[1], 0);

    // acct 500 adds coll, withdraws EBTC
    await th.openCdp(contracts, {extraEBTCAmount: dec(2, 18), extraParams: { from: accounts[500], value: dec(35, 'ether') }})
    let _cdpIdLiq = await sortedCdps.cdpOfOwnerByIndex(accounts[500], 0);

    // Whale opens cdp to get enough debt to liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})

    // Price drops, account[555]'s ICR falls below MCR, and gets liquidated
    let _droppedPrice = dec(3314, 13);
    await priceFeed.setPrice(_droppedPrice)	
    await cdpManager.liquidate(_cdpIdLiq, { from: _liquidator })

    const price = await priceFeed.getPrice()
    const tx = await functionCaller.cdpManager_getCurrentICR(_cdpId, price)

    const gas = th.gasUsed(tx) - 21000
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  it("", async () => {
    const message = 'getICR(), new Cdps with 10 ether and no withdrawals,  WITH pending rewards'
    await th.openCdp_allAccounts(_10_Accounts, contracts, dec(100, 'ether'), dec(3, 18))

    // acct 500 adds coll, withdraws EBTC
    await th.openCdp(contracts, {extraEBTCAmount: dec(2, 18), extraParams: { from: accounts[500], value: dec(35, 'ether') }})
    let _cdpIdLiq = await sortedCdps.cdpOfOwnerByIndex(accounts[500], 0);

    // Whale opens cdp to get enough debt to liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})

    // Price drops, account[555]'s ICR falls below MCR, and gets liquidated
    let _droppedPrice = dec(3314, 13);
    await priceFeed.setPrice(_droppedPrice)	
    await cdpManager.liquidate(_cdpIdLiq, { from: _liquidator })
    
    let _allCdpIds = [];
    for (account of _10_Accounts){ 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))  
         _allCdpIds.push(_cdpId);		
    }
    const gasResults = await th.getCurrentICR_allAccounts(_allCdpIds, contracts, functionCaller)
    th.logGasMetrics(gasResults, message)
    th.logAllGasCosts(gasResults)

    th.appendData(gasResults, message, data)
  })

  it("", async () => {
    const message = 'getICR(), Cdps with 10 ether and 2 EBTC withdrawn, WITH pending rewards'
    await th.openCdp_allAccounts(_10_Accounts, contracts, dec(100, 'ether'), dec(1, 18))

    // acct 500 adds coll, withdraws EBTC
    await th.openCdp(contracts, {extraEBTCAmount: dec(2, 18), extraParams: { from: accounts[500], value: dec(35, 'ether') }})
    let _cdpIdLiq = await sortedCdps.cdpOfOwnerByIndex(accounts[500], 0);

    // Whale opens cdp to get enough debt to liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})

    // Price drops, account[555]'s ICR falls below MCR, and gets liquidated
    let _droppedPrice = dec(3314, 13);
    await priceFeed.setPrice(_droppedPrice)	
    await cdpManager.liquidate(_cdpIdLiq, { from: _liquidator })
    
    let _allCdpIds = [];
    for (account of _10_Accounts){ 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))  
         _allCdpIds.push(_cdpId);		
    }
    const gasResults = await th.getCurrentICR_allAccounts(_allCdpIds, contracts, functionCaller)
    th.logGasMetrics(gasResults, message)
    th.logAllGasCosts(gasResults)

    th.appendData(gasResults, message, data)
  })

  it("", async () => {
    const message = 'getICR(), Cdps with 10 ether WITH pending rewards'
    await th.openCdp_allAccounts(_10_Accounts, contracts, dec(100, 'ether'), dec(2, 18))

    // acct 500 adds coll, withdraws EBTC
    await th.openCdp(contracts, {extraEBTCAmount: dec(2, 18), extraParams: { from: accounts[500], value: dec(35, 'ether') }})
    let _cdpIdLiq = await sortedCdps.cdpOfOwnerByIndex(accounts[500], 0);

    // Whale opens cdp to get enough debt to liquidate
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})

    // Price drops, account[555]'s ICR falls below MCR, and gets liquidated
    let _droppedPrice = dec(3314, 13);
    await priceFeed.setPrice(_droppedPrice)	
    await cdpManager.liquidate(_cdpIdLiq, { from: _liquidator })
    
    let _allCdpIds = [];
    for (account of _10_Accounts){ 
         let _cdpId = await sortedCdps.cdpOfOwnerByIndex(account, 0);
         assert.isTrue(await sortedCdps.contains(_cdpId))  
         _allCdpIds.push(_cdpId);		
    }
    const gasResults = await th.getCurrentICR_allAccounts(_allCdpIds, contracts, functionCaller)
    th.logGasMetrics(gasResults, message)
    th.logAllGasCosts(gasResults)

    th.appendData(gasResults, message, data)
  })

  // --- redeemCollateral() ---
  it("", async () => {
    const message = 'redeemCollateral(), redemption hits 1 Cdps'
    await th.openCdp_allAccounts(_30_Accounts, contracts, dec(100, 'ether'), dec(2, 18)) 

    // Whale opens cdp to get enough debt to redeem
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})
    
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_MONTH, web3.currentProvider)
    const gas = await th.redeemCollateral(_liquidator, contracts, dec(2, 18))
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  it("", async () => {
    const message = 'redeemCollateral(), redemption hits 1 Cdp. No pending rewards. 3 accounts in system, partial redemption'
    // 3 accounts add coll
    await th.openCdp_allAccounts(accounts.slice(0, 3), contracts, dec(100, 'ether'), dec(2, 18)) 

    // Whale opens cdp to get enough debt to redeem
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_MONTH, web3.currentProvider)
    const gas = await th.redeemCollateral(_liquidator, contracts, dec(2, 18))
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  it("", async () => {
    const message = 'redeemCollateral(), redemption hits 2 Cdps'
    await th.openCdp_allAccounts(_30_Accounts, contracts, dec(100, 'ether'), dec(2, 18)) 

    // Whale opens cdp to get enough debt to redeem
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})
    
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_MONTH, web3.currentProvider)
    const gas = await th.redeemCollateral(_liquidator, contracts, dec(4, 18))
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  it("", async () => {
    const message = 'redeemCollateral(), redemption hits 3 Cdps'
    await th.openCdp_allAccounts(_30_Accounts, contracts, dec(100, 'ether'), dec(2, 18)) 

    // Whale opens cdp to get enough debt to redeem
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})
    
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_MONTH, web3.currentProvider)
    const gas = await th.redeemCollateral(_liquidator, contracts, dec(6, 18))
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  it("", async () => {
    const message = 'redeemCollateral(), redemption hits 5 Cdps'
    await th.openCdp_allAccounts(_30_Accounts, contracts, dec(100, 'ether'), dec(2, 18)) 

    // Whale opens cdp to get enough debt to redeem
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})
    
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_MONTH, web3.currentProvider)
    const gas = await th.redeemCollateral(_liquidator, contracts, dec(10, 18))
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  it("", async () => {
    const message = 'redeemCollateral(), redemption hits 10 Cdps'
    await th.openCdp_allAccounts(_30_Accounts, contracts, dec(100, 'ether'), dec(2, 18)) 

    // Whale opens cdp to get enough debt to redeem
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})
    
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_MONTH, web3.currentProvider)
    const gas = await th.redeemCollateral(_liquidator, contracts, dec(20, 18))
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  it("", async () => {
    const message = 'redeemCollateral(), redemption hits 15 Cdps'
    await th.openCdp_allAccounts(_30_Accounts, contracts, dec(100, 'ether'), dec(2, 18)) 

    // Whale opens cdp to get enough debt to redeem
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})
    
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_MONTH, web3.currentProvider)
    const gas = await th.redeemCollateral(_liquidator, contracts, dec(30, 18))
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  it("", async () => {
    const message = 'redeemCollateral(), redemption hits 20 Cdps'
    await th.openCdp_allAccounts(_30_Accounts, contracts, dec(100, 'ether'), dec(2, 18)) 

    // Whale opens cdp to get enough debt to redeem
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})
    
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_MONTH, web3.currentProvider)
    const gas = await th.redeemCollateral(_liquidator, contracts, dec(40, 18))
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // Slow test

  // it("", async () => { 
  //   const message = 'redeemCollateral(),  EBTC, each redemption only hits the first Cdp, never closes it'
  //   await th.addColl_allAccounts(_20_Accounts, cdpManager, dec(10, 'ether'))
  //   await th.withdrawEBTC_allAccounts(_20_Accounts, cdpManager, dec(100, 18))

  //   const gasResults = await th.redeemCollateral_allAccounts_randomAmount( 1, 10, _10_Accounts, cdpManager)
  //   th.logGasMetrics(gasResults, message)
  //   th.logAllGasCosts(gasResults)

  //   th.appendData(gasResults, message, data)
  // })

  // --- redeemCollateral(), with pending redistribution rewards --- 

  it("", async () => {
    const message = 'Test,redeemCollateral(), redemption hits 1 Cdp, WITH pending rewards. One account in system'
    await th.openCdp_allAccounts([accounts[1]], contracts, dec(100, 'ether'), dec(2, 18))  
    let _cdpId1 = await sortedCdps.cdpOfOwnerByIndex(accounts[1], 0); 

    // Whale opens cdp to get enough debt to redeem
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})

    // acct 998 adds coll, withdraws EBTC
    await th.openCdp_allAccounts([accounts[998]], contracts, dec(30, 'ether'), dec(2, 18))
    let _cdpIdLiq = await sortedCdps.cdpOfOwnerByIndex(accounts[998], 0);

    // Price drops, account[998]'s ICR falls below MCR, and gets liquidated
    let _droppedPrice = dec(7028, 13);
    await priceFeed.setPrice(_droppedPrice)	
    await cdpManager.liquidate(_cdpIdLiq, { from: _liquidator })

	console.log('tcr='+ (await cdpManager.getTCR(_droppedPrice)));
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_MONTH, web3.currentProvider)
    const gas = await th.redeemCollateral(_liquidator, contracts, dec(2, 18))

    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  it("", async () => {
    const message = 'Test,redeemCollateral(), redeemed (hits 1 Cdps) WITH pending rewards'
    await th.openCdp_allAccounts(_30_Accounts, contracts, dec(200, 'ether'), dec(2, 18))    

    // Whale opens cdp to get enough debt to redeem
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})

    // acct 998 adds coll, withdraws EBTC
    await th.openCdp_allAccounts([accounts[998]], contracts, dec(60, 'ether'), dec(2, 18))
    let _cdpIdLiq = await sortedCdps.cdpOfOwnerByIndex(accounts[998], 0);

    // Price drops, account[998]'s ICR falls below MCR, and gets liquidated
    let _droppedPrice = dec(3314, 13);
    await priceFeed.setPrice(_droppedPrice)	
    await cdpManager.liquidate(_cdpIdLiq, { from: _liquidator })

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_MONTH, web3.currentProvider)
	let _first = await sortedCdps.getFirst();
	let _firstDebtAndColl = await cdpManager.getVirtualDebtAndCollShares(_first);
    const gas = await th.redeemCollateral(_liquidator, contracts, _firstDebtAndColl[0])
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  it("", async () => {
    const message = 'Test,redeemCollateral(), redeemed (hits 5 Cdps) WITH pending rewards'
    await th.openCdp_allAccounts(_30_Accounts, contracts, dec(200, 'ether'), dec(2, 18))    

    // Whale opens cdp to get enough debt to redeem
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})

    // acct 998 adds coll, withdraws EBTC
    await th.openCdp_allAccounts([accounts[998]], contracts, dec(60, 'ether'), dec(2, 18))
    let _cdpIdLiq = await sortedCdps.cdpOfOwnerByIndex(accounts[998], 0);

    // Price drops, account[998]'s ICR falls below MCR, and gets liquidated
    let _droppedPrice = dec(3314, 13);
    await priceFeed.setPrice(_droppedPrice)	
    await cdpManager.liquidate(_cdpIdLiq, { from: _liquidator })

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_MONTH, web3.currentProvider)
    const gas = await th.redeemCollateral(_liquidator, contracts, dec(10, 18))
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  it("", async () => {
    const message = 'Test,redeemCollateral(), redeemed (hits 10 Cdps) WITH pending rewards'
    await th.openCdp_allAccounts(_30_Accounts, contracts, dec(200, 'ether'), dec(2, 18))    

    // Whale opens cdp to get enough debt to redeem
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})

    // acct 998 adds coll, withdraws EBTC
    await th.openCdp_allAccounts([accounts[998]], contracts, dec(60, 'ether'), dec(2, 18))
    let _cdpIdLiq = await sortedCdps.cdpOfOwnerByIndex(accounts[998], 0);

    // Price drops, account[998]'s ICR falls below MCR, and gets liquidated
    let _droppedPrice = dec(3314, 13);
    await priceFeed.setPrice(_droppedPrice)	
    await cdpManager.liquidate(_cdpIdLiq, { from: _liquidator })

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_MONTH, web3.currentProvider)
    const gas = await th.redeemCollateral(_liquidator, contracts, dec(20, 18))
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  it("", async () => {
    const message = 'Test,redeemCollateral(), redeemed (hits 15 Cdps) WITH pending rewards'
    await th.openCdp_allAccounts(_30_Accounts, contracts, dec(200, 'ether'), dec(2, 18))    

    // Whale opens cdp to get enough debt to redeem
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})

    // acct 998 adds coll, withdraws EBTC
    await th.openCdp_allAccounts([accounts[998]], contracts, dec(60, 'ether'), dec(2, 18))
    let _cdpIdLiq = await sortedCdps.cdpOfOwnerByIndex(accounts[998], 0);

    // Price drops, account[998]'s ICR falls below MCR, and gets liquidated
    let _droppedPrice = dec(3314, 13);
    await priceFeed.setPrice(_droppedPrice)	
    await cdpManager.liquidate(_cdpIdLiq, { from: _liquidator })

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_MONTH, web3.currentProvider)
    const gas = await th.redeemCollateral(_liquidator, contracts, dec(30, 18))
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  it("", async () => {
    const message = 'Test,redeemCollateral(), redeemed (hits 20 Cdps) WITH pending rewards'
    await th.openCdp_allAccounts(_30_Accounts, contracts, dec(200, 'ether'), dec(2, 18))    

    // Whale opens cdp to get enough debt to redeem
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})

    // acct 998 adds coll, withdraws EBTC
    await th.openCdp_allAccounts([accounts[998]], contracts, dec(60, 'ether'), dec(2, 18))
    let _cdpIdLiq = await sortedCdps.cdpOfOwnerByIndex(accounts[998], 0);

    // Price drops, account[998]'s ICR falls below MCR, and gets liquidated
    let _droppedPrice = dec(3314, 13);
    await priceFeed.setPrice(_droppedPrice)	
	console.log('icr='+ (await cdpManager.getICR(_cdpIdLiq, _droppedPrice)));
    await cdpManager.liquidate(_cdpIdLiq, { from: _liquidator })

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_MONTH, web3.currentProvider)
    const gas = await th.redeemCollateral(_liquidator, contracts, dec(40, 18))
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // Slow test

  // it("", async () => { 
  //   const message = 'redeemCollateral(),  EBTC, each redemption only hits the first Cdp, never closes it, WITH pending rewards'
  //   await th.addColl_allAccounts(_20_Accounts, cdpManager, dec(10, 'ether'))
  //   await th.withdrawEBTC_allAccounts(_20_Accounts, cdpManager, dec(100, 18))

  //    // acct 999 adds coll, withdraws EBTC, sits at 111% ICR
  //    await borrowerOperations.addColl(accounts[999], {from: accounts[999], value:dec(1, 'ether')})
  //    await borrowerOperations.withdrawEBTC(_100pct, dec(130, 18), accounts[999], ZERO_ADDRESS, { from: accounts[999]})

  //     // Price drops, account[999]'s ICR falls below MCR, and gets liquidated
  //    await priceFeed.setPrice(dec(100, 18))
  //    await cdpManager.liquidate(accounts[999], ZERO_ADDRESS, { from: accounts[0]})

  //   const gasResults = await th.redeemCollateral_allAccounts_randomAmount( 1, 10, _10_Accounts, cdpManager)
  //   th.logGasMetrics(gasResults, message)
  //   th.logAllGasCosts(gasResults)

  //   th.appendData(gasResults, message, data)
  // })


  // --- getApproxHint() ---

  // it("", async () => {
  //   const message = 'getApproxHint(), numTrials = 10, 10 calls, each with random CR'
  //   await th.openCdp_allAccounts(_10_Accounts, contracts, dec(10, 'ether'), 0 )
  //   await th.withdrawEBTC_allAccounts_randomAmount(1, 180, _10_Accounts, borrowerOperations)

  //   gasCostList = []

  //   for (i = 0; i < 10; i++) {
  //     randomCR = th.randAmountInWei(1, 5)
  //     const tx = await functionCaller.cdpManager_getApproxHint(randomCR, 10)
  //     const gas = th.gasUsed(tx) - 21000
  //     gasCostList.push(gas)
  //   }

  //   const gasResults = th.getGasMetrics(gasCostList)
  //   th.logGasMetrics(gasResults)
  //   th.logAllGasCosts(gasResults)

  //   th.appendData(gasResults, message, data)
  // })

  // it("", async () => {
  //   const message = 'getApproxHint(), numTrials = 10:  i.e. k = 1, list size = 1'
  //   await th.openCdp_allAccounts(_10_Accounts, contracts, dec(10, 'ether'), 0 )
  //   await th.withdrawEBTC_allAccounts_randomAmount(1, 180, _10_Accounts, borrowerOperations)

  //   const CR = '200000000000000000000'
  //   tx = await functionCaller.cdpManager_getApproxHint(CR, 10)
  //   const gas = th.gasUsed(tx) - 21000
  //   th.logGas(gas, message)

  //   th.appendData({ gas: gas }, message, data)
  // })

  // it("", async () => {
  //   const message = 'getApproxHint(), numTrials = 32:  i.e. k = 10, list size = 10'
  //   await th.openCdp_allAccounts(_10_Accounts, contracts, dec(10, 'ether'), 0 )
  //   await th.withdrawEBTC_allAccounts_randomAmount(1, 180, _10_Accounts, borrowerOperations)


  //   const CR = '200000000000000000000'
  //   tx = await functionCaller.cdpManager_getApproxHint(CR, 32)
  //   const gas = th.gasUsed(tx) - 21000
  //   th.logGas(gas, message)

  //   th.appendData({ gas: gas }, message, data)
  // })

  // it("", async () => {
  //   const message = 'getApproxHint(), numTrials = 100: i.e. k = 10, list size = 100'
  //   await th.openCdp_allAccounts(_10_Accounts, contracts, dec(10, 'ether'), 0 )
  //   await th.withdrawEBTC_allAccounts_randomAmount(1, 180, _10_Accounts, borrowerOperations)

  //   const CR = '200000000000000000000'
  //   tx = await functionCaller.cdpManager_getApproxHint(CR, 100)
  //   const gas = th.gasUsed(tx) - 21000
  //   th.logGas(gas, message)

  //   th.appendData({ gas: gas }, message, data)
  // })

  // Slow tests

  // it("", async () => { //8mil. gas
  //   const message = 'getApproxHint(), numTrials = 320: i.e. k = 10, list size = 1000'
  //   await th.addColl_allAccounts(_10_Accounts, cdpManager, dec(10, 'ether'))
  //   await th.withdrawEBTC_allAccounts_randomAmount(1, 180, _10_Accounts, cdpManager)

  //   const CR = '200000000000000000000'
  //   tx = await functionCaller.cdpManager_getApproxHint(CR, 320)
  //   const gas = th.gasUsed(tx) - 21000
  //   th.logGas(gas, message)

  //   th.appendData({gas: gas}, message, data)
  // })

  // it("", async () => { // 25mil. gas
  //   const message = 'getApproxHint(), numTrials = 1000:  i.e. k = 10, list size = 10000'
  //   await th.addColl_allAccounts(_10_Accounts, cdpManager, dec(10, 'ether'))
  //   await th.withdrawEBTC_allAccounts_randomAmount(1, 180, _10_Accounts, cdpManager)

  //   const CR = '200000000000000000000'
  //   tx = await functionCaller.cdpManager_getApproxHint(CR, 1000)
  //   const gas = th.gasUsed(tx) - 21000
  //   th.logGas(gas, message)

  //   th.appendData({gas: gas}, message, data)
  // })

  // it("", async () => { // 81mil. gas
  //   const message = 'getApproxHint(), numTrials = 3200:  i.e. k = 10, list size = 100000'
  //   await th.addColl_allAccounts(_10_Accounts, cdpManager, dec(10, 'ether'))
  //   await th.withdrawEBTC_allAccounts_randomAmount(1, 180, _10_Accounts, cdpManager)

  //   const CR = '200000000000000000000'
  //   tx = await functionCaller.cdpManager_getApproxHint(CR, 3200)
  //   const gas = th.gasUsed(tx) - 21000
  //   th.logGas(gas, message)

  //   th.appendData({gas: gas}, message, data)
  // })


  // Test hangs 

  // it("", async () => { 
  //   const message = 'getApproxHint(), numTrials = 10000:  i.e. k = 10, list size = 1000000'
  //   await th.addColl_allAccounts(_10_Accounts, cdpManager, dec(10, 'ether'))
  //   await th.withdrawEBTC_allAccounts_randomAmount(1, 180, _10_Accounts, cdpManager)

  //   const CR = '200000000000000000000'
  //   tx = await functionCaller.cdpManager_getApproxHint(CR, 10000)
  //   const gas = th.gasUsed(tx) - 21000
  //   th.logGas(gas, message)

  //   th.appendData({gas: gas}, message, data)
  // })

  // --- provideToSP(): No pending rewards

  // --- First deposit ---

  // it("", async () => {
  //   const message = 'provideToSP(), No pending rewards, part of issued EBTC: all accounts withdraw 180 EBTC, all make first deposit, provide 100 EBTC'
  //   await th.openCdp_allAccounts(_10_Accounts, contracts, dec(10, 'ether'), 0)
  //   await th.withdrawEBTC_allAccounts(_10_Accounts, contracts, dec(130, 18))

  //   // first funds provided
  //   const gasResults = await th.provideToSP_allAccounts(_10_Accounts, stabilityPool, dec(100, 18))
  //   th.logGasMetrics(gasResults, message)
  //   th.logAllGasCosts(gasResults)

  //   th.appendData(gasResults, message, data)
  // })

  // it("", async () => {
  //   const message = 'provideToSP(), No pending rewards, all issued EBTC: all accounts withdraw 180 EBTC, all make first deposit, 180 EBTC'
  //   await th.openCdp_allAccounts(_10_Accounts, contracts, dec(10, 'ether'), 0)
  //   await th.withdrawEBTC_allAccounts(_10_Accounts, contracts, dec(130, 18))

  //   // first funds provided
  //   const gasResults = await th.provideToSP_allAccounts(_10_Accounts, stabilityPool, dec(130, 18))
  //   th.logGasMetrics(gasResults, message)
  //   th.logAllGasCosts(gasResults)

  //   th.appendData(gasResults, message, data)
  // })

  // --- withdrawETHGainToCdp() ---

  // --- withdrawETHGainToCdp() - deposit has pending rewards ---
  // it("", async () => {
  //   const message = 'withdrawETHGainToCdp(), pending rewards in system. Accounts withdraw 180 EBTC, provide 180 EBTC, then withdraw all to SP after a liquidation'
  //   // 10 accts each open Cdp with 10 ether, withdraw 180 EBTC, and provide 130 EBTC to Stability Pool
  //   await th.openCdp_allAccounts(accounts.slice(2, 12), contracts, dec(10, 'ether'), dec(130, 18))
  //   await th.provideToSP_allAccounts(accounts.slice(2, 12), stabilityPool, dec(130, 18))

  //   //1 acct open Cdp with 1 ether and withdraws 170 EBTC
  //   await borrowerOperations.openCdp(0, accounts[1], ZERO_ADDRESS, { from: accounts[1], value: dec(1, 'ether') })
  //   await borrowerOperations.withdrawEBTC(_100pct, dec(130, 18), accounts[1], ZERO_ADDRESS, { from: accounts[1] })

  //   await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

  //   // Price drops, account[0]'s ICR falls below MCR
  //   await priceFeed.setPrice(dec(100, 18))
  //   await cdpManager.liquidate(accounts[1], { from: accounts[0] })
  //   assert.isFalse(await sortedCdps.contains(accounts[1]))

  //    // Check accounts have LQTY gains from liquidations
  //    for (account of accounts.slice(2, 12)) {
  //     const LQTYGain = await stabilityPool.getDepositorLQTYGain(account)
  //     assert.isTrue(LQTYGain.gt(toBN('0')))
  //   }

  //   await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

  //   // 5 active Cdps withdraw their ETH gain to their cdp
  //   const gasResults = await th.withdrawETHGainToCdp_allAccounts(accounts.slice(7, 12), contracts)
  //   th.logGasMetrics(gasResults, message)
  //   th.logAllGasCosts(gasResults)

  //   th.appendData(gasResults, message, data)
  // })

  // --- liquidate() ---

  // Full liquidation with NO pending rewards
  it("", async () => {
    const message = 'Test,Single liquidate() call. Liquidee has NO pending rewards. Pure offset with SP'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(100, 110), contracts, dec(200, 'ether'), dec(2, 18))

    //3 acct open Cdp with 1 ether and withdraws 180 EBTC (inc gas comp)
    await th.openCdp_allAccounts(accounts.slice(0, 4), contracts, dec(30, 'ether'), dec(2, 18))
    let _cdpIdLiq = await sortedCdps.cdpOfOwnerByIndex(accounts[2], 0);
    let _cdpIdLiq2 = await sortedCdps.cdpOfOwnerByIndex(accounts[3], 0);
    let _cdpIdLiq3 = await sortedCdps.cdpOfOwnerByIndex(accounts[1], 0);

    // Acct 999 as liquidator
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})

    // Price drops
    let _droppedPrice = dec(7218, 13);
    await priceFeed.setPrice(_droppedPrice)

    // Initial liquidations - full liquidation
    await cdpManager.liquidate(_cdpIdLiq, { from: _liquidator })
    await cdpManager.liquidate(_cdpIdLiq2, { from: _liquidator })

    const hasPendingDebtRedistribution = await cdpManager.hasPendingDebtRedistribution(_cdpIdLiq3)
    assert.isFalse(hasPendingDebtRedistribution)

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Account 1 liquidated - liquidation
    const tx = await cdpManager.liquidate(_cdpIdLiq3, { from: _liquidator })
    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // Full liquidation WITH pending rewards
  it("", async () => {
    const message = 'Test,Single liquidate() call. Liquidee has pending rewards'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(100, 110), contracts, dec(200, 'ether'), dec(2, 18))

    // 4 acct open Cdp with 1 ether and withdraws 180 EBTC (inc gas comp)
    await th.openCdp_allAccounts(accounts.slice(0, 5), contracts, dec(30, 'ether'), dec(2, 18))
    let _cdpIdLiq = await sortedCdps.cdpOfOwnerByIndex(accounts[2], 0);
    let _cdpIdLiq2 = await sortedCdps.cdpOfOwnerByIndex(accounts[3], 0);
    let _cdpIdLiq3 = await sortedCdps.cdpOfOwnerByIndex(accounts[1], 0);
    let _cdpIdLiq4 = await sortedCdps.cdpOfOwnerByIndex(accounts[4], 0);

    // Acct 999 as liquidator
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})

    // Price drops
    let _droppedPrice = dec(7218, 13);
    await priceFeed.setPrice(_droppedPrice)

    // Initial liquidations - full liquidation
    await cdpManager.liquidate(_cdpIdLiq, { from: _liquidator })
    await cdpManager.liquidate(_cdpIdLiq2, { from: _liquidator })

    // redistribution - creates pending dist. rewards for account 1
    await priceFeed.setPrice(dec(3014, 13))
    await cdpManager.liquidate(_cdpIdLiq4, { from: _liquidator })

    const hasPendingDebtRedistribution = await cdpManager.hasPendingDebtRedistribution(_cdpIdLiq3)
    assert.isTrue(hasPendingDebtRedistribution)

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Account 1 liquidated - full liquidation
    const tx = await cdpManager.liquidate(_cdpIdLiq3, { from: _liquidator })
    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // WITH pending rewards
  it("", async () => {
    const message = 'Test,Single liquidate() call. Liquidee has pending rewards'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(100, 110), contracts, dec(200, 'ether'), dec(2, 18))

    // 3 acct open Cdps
    await th.openCdp_allAccounts(accounts.slice(0, 4), contracts, dec(30, 'ether'), dec(2, 18))
    let _cdpIdLiq = await sortedCdps.cdpOfOwnerByIndex(accounts[2], 0);
    let _cdpIdLiq2 = await sortedCdps.cdpOfOwnerByIndex(accounts[3], 0);
    let _cdpIdLiq3 = await sortedCdps.cdpOfOwnerByIndex(accounts[1], 0);

    // Acct 999 as liquidator
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})

    // Price drops
    let _droppedPrice = dec(3014, 13);
    await priceFeed.setPrice(_droppedPrice)

    // Set up some "previous" liquidations triggering partial offsets, and pending rewards for all cdps
    await cdpManager.liquidate(_cdpIdLiq, { from: _liquidator })
    await cdpManager.liquidate(_cdpIdLiq2, { from: _liquidator })

    const hasPendingDebtRedistribution = await cdpManager.hasPendingDebtRedistribution(_cdpIdLiq3)
    assert.isTrue(hasPendingDebtRedistribution)

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // account 1 liquidated
    const tx = await cdpManager.liquidate(_cdpIdLiq3, { from: _liquidator })
    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // NO pending rewards
  it("", async () => {
    const message = 'Test,Single liquidate() call. Liquidee has NO pending rewards'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(100, 110), contracts, dec(200, 'ether'), dec(2, 18))

    //2 acct open Cdp
    await th.openCdp_allAccounts(accounts.slice(2, 4), contracts, dec(30, 'ether'), dec(2, 18))
    let _cdpIdLiq = await sortedCdps.cdpOfOwnerByIndex(accounts[2], 0);
    let _cdpIdLiq2 = await sortedCdps.cdpOfOwnerByIndex(accounts[3], 0);

    // Acct 999 as liquidator
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})
	
    // Price drops
    let _droppedPrice = dec(3014, 13);
    await priceFeed.setPrice(_droppedPrice)

    // Account 1 opens cdp
    await th.openCdp(contracts, {extraEBTCAmount: dec(1, 18), extraParams: { from: accounts[1], value: dec(75, 'ether') }})
    let _cdpIdLiq3 = await sortedCdps.cdpOfOwnerByIndex(accounts[1], 0);

    // Set up some "previous" liquidations that trigger partial offsets, 
    //and create pending rewards for all cdps
    await cdpManager.liquidate(_cdpIdLiq, { from: _liquidator })
    await cdpManager.liquidate(_cdpIdLiq2, { from: _liquidator })

    // Price drops
    await priceFeed.setPrice(dec(1500, 13))

    const hasPendingDebtRedistribution = await cdpManager.hasPendingDebtRedistribution(_cdpIdLiq3)
    assert.isTrue(hasPendingDebtRedistribution)

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // account 1 liquidated
    const tx = await cdpManager.liquidate(_cdpIdLiq3, { from: _liquidator })
    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // With pending dist. rewards (Highest gas cost scenario in Normal Mode)
  it("", async () => {
    const message = 'Test,liquidate() liquidated Cdp has redistribution rewards.'
    // 10 accts each open Cdps
    await th.openCdp_allAccounts(accounts.slice(100, 110), contracts, dec(200, 'ether'), dec(2, 18))

    //Account 99 and 98 each open Cdp
    await th.openCdp_allAccounts([accounts[99]], contracts, dec(28, 'ether'), dec(1, 18))
    let _cdpIdLiq = await sortedCdps.cdpOfOwnerByIndex(accounts[99], 0);
    await th.openCdp_allAccounts([accounts[98]], contracts, dec(28, 'ether'), dec(1, 18))
    let _cdpIdLiq2 = await sortedCdps.cdpOfOwnerByIndex(accounts[98], 0);

    // Acct 999 as liquidator
    let _liquidator = accounts[999];
    await th.openCdp(contracts, {extraEBTCAmount: dec(100, 18), extraParams: { from: _liquidator, value: dec(3000, 'ether') }})

    //Account 97 opens Cdp
    await th.openCdp_allAccounts([accounts[97]], contracts, dec(32, 'ether'), dec(1, 18))
    let _cdpIdLiq3 = await sortedCdps.cdpOfOwnerByIndex(accounts[97], 0);

    // Price drops too $100, accounts 99 and 100 ICR fall below MCR	
    let _droppedPrice = dec(3014, 13);
    await priceFeed.setPrice(_droppedPrice)
    const price = await priceFeed.getPrice()

    /* Liquidate account 97 */
    await cdpManager.liquidate(_cdpIdLiq3, { from: _liquidator })
    assert.isFalse(await sortedCdps.contains(_cdpIdLiq3))

    // Account 98 is liquidated which creates pending rewards from distribution.
    await cdpManager.liquidate(_cdpIdLiq2, { from: _liquidator })

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    const tx = await cdpManager.liquidate(_cdpIdLiq, { from: _liquidator })
    assert.isFalse(await sortedCdps.contains(_cdpIdLiq))

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // --- findInsertPosition ---

  // --- Insert at head, 0 traversals ---

  // it("", async () => {
  //   const message = 'findInsertPosition(), 10 Cdps with ICRs 200-209%, ICR > head ICR, no hint, 0 traversals'

  //   // makes 10 Cdps with ICRs 200 to 209%
  //   await th.makeCdpsIncreasingICR(_10_Accounts, contracts)

  //   // 300% ICR, higher than Cdp at head of list
  //   const CR = web3.utils.toWei('3', 'ether')
  //   const address_0 = '0x0000000000000000000000000000000000000000'

  //   const price = await priceFeed.getPrice()
  //   const tx = await functionCaller.sortedCdps_findInsertPosition(CR, address_0, address_0)
  //   const gas = th.gasUsed(tx) - 21000
  //   th.logGas(gas, message)

  //   th.appendData({ gas: gas }, message, data)
  // })

  // it("", async () => {
  //   const message = 'findInsertPosition(), 50 Cdps with ICRs 200-209%, ICR > head ICR, no hint, 0 traversals'

  //   // makes 10 Cdps with ICRs 200 to 209%
  //   await th.makeCdpsIncreasingICR(_50_Accounts, contracts)

  //   // 300% ICR, higher than Cdp at head of list
  //   const CR = web3.utils.toWei('3', 'ether')
  //   const address_0 = '0x0000000000000000000000000000000000000000'

  //   const price = await priceFeed.getPrice()
  //   const tx = await functionCaller.sortedCdps_findInsertPosition(CR, price, address_0, address_0)
  //   const gas = th.gasUsed(tx) - 21000
  //   th.logGas(gas, message)

  //   th.appendData({ gas: gas }, message, data)
  // })

  // // --- Insert at tail, so num. traversals = listSize ---

  // it("", async () => {
  //   const message = 'findInsertPosition(), 10 Cdps with ICRs 200-209%, ICR < tail ICR, no hint, 10 traversals'

  //   // makes 10 Cdps with ICRs 200 to 209%
  //   await th.makeCdpsIncreasingICR(_10_Accounts, contracts)

  //   // 200% ICR, lower than Cdp at tail of list
  //   const CR = web3.utils.toWei('2', 'ether')
  //   const address_0 = '0x0000000000000000000000000000000000000000'

  //   const price = await priceFeed.getPrice()
  //   const tx = await functionCaller.sortedCdps_findInsertPosition(CR, price, address_0, address_0)
  //   const gas = th.gasUsed(tx) - 21000
  //   th.logGas(gas, message)

  //   th.appendData({ gas: gas }, message, data)
  // })

  // it("", async () => {
  //   const message = 'findInsertPosition(), 20 Cdps with ICRs 200-219%, ICR <  tail ICR, no hint, 20 traversals'

  //   // makes 20 Cdps with ICRs 200 to 219%
  //   await th.makeCdpsIncreasingICR(_20_Accounts, contracts)

  //   // 200% ICR, lower than Cdp at tail of list
  //   const CR = web3.utils.toWei('2', 'ether')

  //   const price = await priceFeed.getPrice()
  //   const tx = await functionCaller.sortedCdps_findInsertPosition(CR, price, address_0, address_0)
  //   const gas = th.gasUsed(tx) - 21000
  //   th.logGas(gas, message)

  //   th.appendData({ gas: gas }, message, data)
  // })

  // it("", async () => {
  //   const message = 'findInsertPosition(), 50 Cdps with ICRs 200-249%, ICR <  tail ICR, no hint, 50 traversals'

  //   // makes 50 Cdps with ICRs 200 to 249%
  //   await th.makeCdpsIncreasingICR(_50_Accounts, contracts)

  //   // 200% ICR, lower than Cdp at tail of list
  //   const CR = web3.utils.toWei('2', 'ether')

  //   const price = await priceFeed.getPrice()
  //   const tx = await functionCaller.sortedCdps_findInsertPosition(CR, price, address_0, address_0)
  //   const gas = th.gasUsed(tx) - 21000
  //   th.logGas(gas, message)

  //   th.appendData({ gas: gas }, message, data)
  // })

  // --- Write test output data to CSV file

  it("Export test data", async () => {
    let _lineCnt = 1;
    let _content = '';
    for(let i = 0;i < dataOneMonth.length;i++){
        console.log('#L' + _lineCnt + ':' + dataOneMonth[i]);
        _lineCnt = _lineCnt + 1;	
        _content = _content + dataOneMonth[i]	
    }
	
    fs.writeFile('gasTest/outputs/gasTestData.csv', _content, (err) => {
        if (err) { 
            console.log(err) 
        } else {
            console.log("Gas test data written to gasTest/outputs/gasTestData.csv")
        }
    })
  })

})


/* TODO:
-Liquidations in Recovery Mode
---
Parameters to vary for gas tests:
- Number of accounts
- Function call parameters - low, high, random, average of many random
  -Pre-existing state:
  --- Rewards accumulated (or not)
  --- EBTC in StabilityPool (or not)
  --- State variables non-zero e.g. Cdp already opened, stake already made, etc
  - Steps in the the operation:
  --- number of liquidations to perform
  --- number of cdps to redeem from
  --- number of trials to run
  Extremes/edges:
  - Lowest or highest ICR
  - empty list, max size list
  - the only Cdp, the newest Cdp
  etc.
*/
