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

    await deploymentHelper.connectLQTYContracts(LQTYContracts)
    await deploymentHelper.connectCoreContracts(contracts, LQTYContracts)
    await deploymentHelper.connectLQTYContractsToCore(LQTYContracts, contracts)
  })

  // ---TESTS ---

  it("runs the test helper", async () => {
    assert.equal(th.getDifference('2000', '1000'), 1000)
  })

  it("helper - getBorrowerOpsListHint(): returns the right position in the list", async () => {
    // Accounts A - J open cdps at sequentially lower ICR
    await borrowerOperations.openCdp(dec(100, 18), ZERO_ADDRESS, ZERO_ADDRESS, { from: A, value: dec(10, 'ether') })
    await borrowerOperations.openCdp(dec(102, 18), ZERO_ADDRESS, ZERO_ADDRESS, { from: B, value: dec(10, 'ether') })
    await borrowerOperations.openCdp(dec(104, 18), ZERO_ADDRESS, ZERO_ADDRESS, { from: C, value: dec(10, 'ether') })
    await borrowerOperations.openCdp(dec(106, 18), ZERO_ADDRESS, ZERO_ADDRESS, { from: D, value: dec(10, 'ether') })
    await borrowerOperations.openCdp(dec(108, 18), ZERO_ADDRESS, ZERO_ADDRESS, { from: E, value: dec(10, 'ether') })
    await borrowerOperations.openCdp(dec(110, 18), ZERO_ADDRESS, ZERO_ADDRESS, { from: F, value: dec(10, 'ether') })
    await borrowerOperations.openCdp(dec(112, 18), ZERO_ADDRESS, ZERO_ADDRESS, { from: G, value: dec(10, 'ether') })
    await borrowerOperations.openCdp(dec(114, 18), ZERO_ADDRESS, ZERO_ADDRESS, { from: H, value: dec(10, 'ether') })
    await borrowerOperations.openCdp(dec(116, 18), ZERO_ADDRESS, ZERO_ADDRESS, { from: I, value: dec(10, 'ether') })
    await borrowerOperations.openCdp(dec(118, 18), ZERO_ADDRESS, ZERO_ADDRESS, { from: J, value: dec(10, 'ether') })
  
    for (account of [A,B,C,D,E,F,G,H,I,J]) {
      console.log(th.squeezeAddr(account))
    }

    // Between F and G
    let amount = dec(111, 18)
    let fee = await cdpManager.getBorrowingFee(amount)
    let debt = amount.add(fee)
    let {upperHint, lowerHint} = await th.getBorrowerOpsListHint(contracts, dec(10, 'ether'), debt)  

    assert.equal(upperHint, F)
    assert.equal(lowerHint, G)

    // Bottom of the list
    amount = dec(120, 18)
    fee = await cdpManager.getBorrowingFee(amount)
    debt = amount.add(fee)
    ;({upperHint, lowerHint} = await th.getBorrowerOpsListHint(contracts, dec(10, 'ether'), debt))
     
    assert.equal(upperHint, J)
    assert.equal(lowerHint, ZERO_ADDRESS)

    // Top of the list
    amount = dec(98, 18)
    fee = await cdpManager.getBorrowingFee(amount)
    debt = amount.add(fee)
    ;({upperHint, lowerHint} = await th.getBorrowerOpsListHint(contracts, dec(10, 'ether'), debt))
     
    assert.equal(upperHint, ZERO_ADDRESS)
    assert.equal(lowerHint, A)
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
    const amountETH = dec(10, 'ether')
    const amountEBTC = 0
    const gasResults = await th.openCdp_allAccounts_randomETH_randomEBTC(1, 9, _50_Accounts, contracts, 2, 100, true)
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
    await borrowerOperations.openCdp(0, accounts[999], ZERO_ADDRESS, { from: accounts[999], value: dec(100, 'ether') })

    const amountETH = dec(9, 'ether')
    const amountEBTC = dec(100, 18)
    await th.openCdp_allAccounts(_40_Accounts, contracts, amountETH, amountEBTC)
    // Randomly add between 1-9 ETH, and withdraw 1-100 EBTC
    const gasResults = await th.adjustCdp_allAccounts_randomAmount(_40_Accounts, contracts, 1, 9, 1, 100)

    th.logGasMetrics(gasResults, message)
    th.logAllGasCosts(gasResults)

    th.appendData(gasResults, message, data)
  })

  // --- closeCdp() ---

  it("", async () => {
    const message = 'closeCdp(), 10 accounts, 1 account closes its cdp'

    await th.openCdp_allAccounts_decreasingEBTCAmounts(_10_Accounts, contracts, dec(10, 'ether'), 200)

    for (account of _10_Accounts ) {
      await ebtcToken.unprotectedMint(account, dec(1000, 18))
    }

    const tx = await borrowerOperations.closeCdp({ from: accounts[1] })
    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  it("", async () => {
    const message = 'closeCdp(), 20 accounts, each account adds 10 ether and issues less EBTC than the previous one. First 10 accounts close their cdp. '

    await th.openCdp_allAccounts_decreasingEBTCAmounts(_20_Accounts, contracts, dec(10, 'ether'), 200)

    for (account of _20_Accounts ) {
      await ebtcToken.unprotectedMint(account, dec(1000, 18))
    }
    
    const gasResults = await th.closeCdp_allAccounts(_20_Accounts.slice(1), contracts)

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
    await th.openCdp_allAccounts(_30_Accounts, contracts, dec(10, 'ether'), 0)

    const gasResults = await th.addColl_allAccounts_randomAmount(0.000000001, 10000, _30_Accounts, contracts)
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
    await th.openCdp_allAccounts(_30_Accounts, contracts, dec(10, 'ether'), 0)

    const gasResults = await th.withdrawColl_allAccounts_randomAmount(1, 8, _30_Accounts, contracts)
    th.logGasMetrics(gasResults, message)
    th.logAllGasCosts(gasResults)

    th.appendData(gasResults, message, data)
  })

  it("", async () => {
    const message = 'withdrawColl(), second withdrawal, 10 accounts, each account withdraws random amount'
    await th.openCdp_allAccounts(_10_Accounts, contracts, dec(10, 'ether'), 0)
    await th.withdrawColl_allAccounts(_10_Accounts, contracts, dec(1, 'ether'))

    const gasResults = await th.withdrawColl_allAccounts_randomAmount(1, 8, _10_Accounts, contracts)
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
    await th.openCdp_allAccounts(_30_Accounts, contracts, dec(10, 'ether'), 0)

    const gasResults = await th.withdrawEBTC_allAccounts_randomAmount(1, 180, _30_Accounts, contracts)
    th.logGasMetrics(gasResults, message)
    th.logAllGasCosts(gasResults)

    th.appendData(gasResults, message, data)
  })

  it("", async () => {
    const message = 'withdrawEBTC(), second withdrawal, 30 accounts, each account withdraws a random EBTC amount'
    await th.openCdp_allAccounts(_30_Accounts, contracts, dec(10, 'ether'), 0)
    await th.withdrawEBTC_allAccounts(_30_Accounts, contracts, dec(100, 18))

    const gasResults = await th.withdrawEBTC_allAccounts_randomAmount(1, 70, _30_Accounts, contracts)
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
    const message = 'repayEBTC(), partial repayment, 30 accounts, repay random amount of EBTC (of 100 EBTC)'
    await th.openCdp_allAccounts(_30_Accounts, contracts, dec(10, 'ether'), 0)
    await th.withdrawEBTC_allAccounts(_30_Accounts, contracts, dec(100, 18))

    const gasResults = await th.repayEBTC_allAccounts_randomAmount(1, 99, _30_Accounts, contracts)
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
    const message = 'repayEBTC(), first repayment, 30 accounts, repay in full (50 of 50 EBTC)'
    await th.openCdp_allAccounts(_30_Accounts, contracts, dec(10, 'ether'), 0)
    await th.withdrawEBTC_allAccounts(_30_Accounts, contracts, dec(100, 18))
    await th.repayEBTC_allAccounts(_30_Accounts, contracts, dec(50, 18))

    const gasResults = await th.repayEBTC_allAccounts(_30_Accounts, contracts, dec(50, 18))
    th.logGasMetrics(gasResults, message)
    th.logAllGasCosts(gasResults)

    th.appendData(gasResults, message, data)
  })

  // --- getCurrentICR() ---

  it("", async () => {
    const message = 'single getCurrentICR() call'

    await th.openCdp_allAccounts([accounts[1]], contracts, dec(10, 'ether'), 0)
    const randEBTCAmount = th.randAmountInWei(1, 180)
    await borrowerOperations.withdrawEBTC(_100pct, randEBTCAmount, accounts[1], ZERO_ADDRESS, { from: accounts[1] })

    const price = await priceFeed.getPrice()
    const tx = await functionCaller.cdpManager_getCurrentICR(accounts[1], price)

    const gas = th.gasUsed(tx) - 21000
    th.logGas(gas, message)
  })

  it("", async () => {
    const message = 'getCurrentICR(), new Cdps with 10 ether and no withdrawals'
    await th.openCdp_allAccounts(_10_Accounts, contracts, dec(10, 'ether'), 0)
    const gasResults = await th.getCurrentICR_allAccounts(_10_Accounts, contracts, functionCaller)
    th.logGasMetrics(gasResults, message)
    th.logAllGasCosts(gasResults)

    th.appendData(gasResults, message, data)
  })

  it("", async () => {
    const message = 'getCurrentICR(), Cdps with 10 ether and 100 EBTC withdrawn'
    await th.openCdp_allAccounts(_10_Accounts, contracts, dec(10, 'ether'), 0)
    await th.withdrawEBTC_allAccounts(_10_Accounts, contracts, dec(100, 18))

    const gasResults = await th.getCurrentICR_allAccounts(_10_Accounts, contracts, functionCaller)
    th.logGasMetrics(gasResults, message)
    th.logAllGasCosts(gasResults)

    th.appendData(gasResults, message, data)
  })

  it("", async () => {
    const message = 'getCurrentICR(), Cdps with 10 ether and random EBTC amount withdrawn'
    await th.openCdp_allAccounts(_10_Accounts, contracts, dec(10, 'ether'), 0)
    await th.withdrawEBTC_allAccounts_randomAmount(1, 1300, _10_Accounts, contracts)

    const gasResults = await th.getCurrentICR_allAccounts(_10_Accounts, contracts, functionCaller)
    th.logGasMetrics(gasResults, message)
    th.logAllGasCosts(gasResults)

    th.appendData(gasResults, message, data)
  })

  // --- getCurrentICR() with pending distribution rewards ---

  it("", async () => {
    const message = 'single getCurrentICR() call, WITH pending rewards'

    const randEBTCAmount = th.randAmountInWei(1, 180)
    await borrowerOperations.openCdp(randEBTCAmount, accounts[1], ZERO_ADDRESS, { from: accounts[1], value: dec(10, 'ether') })

    // acct 999 adds coll, withdraws EBTC, sits at 111% ICR
    await borrowerOperations.openCdp(dec(130, 18), accounts[999], ZERO_ADDRESS, { from: accounts[999], value: dec(1, 'ether') })

    // Price drops, account[999]'s ICR falls below MCR, and gets liquidated
    await priceFeed.setPrice(dec(100, 18))
    await cdpManager.liquidate(accounts[999], { from: accounts[0] })

    const price = await priceFeed.getPrice()
    const tx = await functionCaller.cdpManager_getCurrentICR(accounts[1], price)

    const gas = th.gasUsed(tx) - 21000
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  it("", async () => {
    const message = 'getCurrentICR(), new Cdps with 10 ether and no withdrawals,  WITH pending rewards'
    await th.openCdp_allAccounts(_10_Accounts, contracts, dec(10, 'ether'), dec(100, 18))

    // acct 999 adds coll, withdraws EBTC, sits at 111% ICR
    await borrowerOperations.openCdp(dec(130, 18), accounts[999], ZERO_ADDRESS, { from: accounts[999], value: dec(1, 'ether') })

    // Price drops, account[999]'s ICR falls below MCR, and gets liquidated
    await priceFeed.setPrice(dec(100, 18))
    await cdpManager.liquidate(accounts[999], { from: accounts[0] })

    const gasResults = await th.getCurrentICR_allAccounts(_10_Accounts, contracts, functionCaller)
    th.logGasMetrics(gasResults, message)
    th.logAllGasCosts(gasResults)

    th.appendData(gasResults, message, data)
  })

  it("", async () => {
    const message = 'getCurrentICR(), Cdps with 10 ether and 100 EBTC withdrawn, WITH pending rewards'
    await th.openCdp_allAccounts(_10_Accounts, contracts, dec(10, 'ether'), dec(100, 18))

    // acct 999 adds coll, withdraws EBTC, sits at 111% ICR
    await borrowerOperations.openCdp(dec(130, 18), accounts[999], ZERO_ADDRESS, { from: accounts[999], value: dec(1, 'ether') })


    // Price drops, account[999]'s ICR falls below MCR, and gets liquidated
    await priceFeed.setPrice(dec(100, 18))
    await cdpManager.liquidate(accounts[999], { from: accounts[0] })

    const gasResults = await th.getCurrentICR_allAccounts(_10_Accounts, contracts, functionCaller)
    th.logGasMetrics(gasResults, message)
    th.logAllGasCosts(gasResults)

    th.appendData(gasResults, message, data)
  })

  it("", async () => {
    const message = 'getCurrentICR(), Cdps with 10 ether and random EBTC amount withdrawn, WITH pending rewards'
    await th.openCdp_allAccounts(_10_Accounts, contracts, dec(10, 'ether'), dec(100, 18))

    // acct 999 adds coll, withdraws EBTC, sits at 111% ICR
    await borrowerOperations.openCdp(dec(130, 18), accounts[999], ZERO_ADDRESS, { from: accounts[999], value: dec(1, 'ether') })

    // Price drops, account[999]'s ICR falls below MCR, and gets liquidated
    await priceFeed.setPrice(dec(100, 18))
    await cdpManager.liquidate(accounts[999], { from: accounts[0] })

    const gasResults = await th.getCurrentICR_allAccounts(_10_Accounts, contracts, functionCaller)
    th.logGasMetrics(gasResults, message)
    th.logAllGasCosts(gasResults)

    th.appendData(gasResults, message, data)
  })

  // --- redeemCollateral() ---
  it("", async () => {
    const message = 'redeemCollateral(), redeems 50 EBTC, redemption hits 1 Cdp. One account in system, partial redemption'
    await th.openCdp_allAccounts([accounts[0]], contracts, dec(10, 'ether'), 0)
    await th.withdrawEBTC_allAccounts([accounts[0]], contracts, dec(100, 18))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_MONTH, web3.currentProvider)
    const gas = await th.redeemCollateral(accounts[0], contracts, dec(50, 18))
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  it("", async () => {
    const message = 'redeemCollateral(), redeems 50 EBTC, redemption hits 1 Cdp. No pending rewards. 3 accounts in system, partial redemption'
    // 3 accounts add coll
    await th.openCdp_allAccounts(accounts.slice(0, 3), contracts, dec(10, 'ether'), 0)
    // 3 accounts withdraw successively less EBTC
    await borrowerOperations.withdrawEBTC(_100pct, dec(100, 18), accounts[0], ZERO_ADDRESS, { from: accounts[0] })
    await borrowerOperations.withdrawEBTC(_100pct, dec(90, 18), accounts[1], ZERO_ADDRESS, { from: accounts[1] })
    await borrowerOperations.withdrawEBTC(_100pct, dec(80, 18), accounts[2], ZERO_ADDRESS, { from: accounts[2] })

    /* Account 2 redeems 50 EBTC. It is redeemed from account 0's Cdp, 
    leaving the Cdp active with 30 EBTC and ((200 *10 - 50 ) / 200 ) = 9.75 ETH. 
    
    It's ICR jumps from 2500% to 6500% and it is reinserted at the top of the list.
    */

   await th.fastForwardTime(timeValues.SECONDS_IN_ONE_MONTH, web3.currentProvider)
    const gas = await th.redeemCollateral(accounts[2], contracts, dec(50, 18))
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  it("", async () => {
    const message = 'redeemCollateral(), redeemed 101 EBTC, redemption hits 2 Cdps, last redemption is partial'
    await th.openCdp_allAccounts(_10_Accounts, contracts, dec(10, 'ether'), 0)
    await th.withdrawEBTC_allAccounts(_10_Accounts, contracts, dec(100, 18))

    // Whale adds 200 ether, withdraws 500 EBTC, redeems 101 EBTC
    await borrowerOperations.openCdp(0, whale, ZERO_ADDRESS, { from: whale, value: dec(200, 'ether') })
    await borrowerOperations.withdrawEBTC(_100pct, dec(500, 18), whale, ZERO_ADDRESS, { from: whale })

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_MONTH, web3.currentProvider)
    const gas = await th.redeemCollateral(whale, contracts, dec(101, 18))
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  it("", async () => {
    const message = 'redeemCollateral(), redeemed 500 EBTC, redemption hits 5 Cdps, all full redemptions'
    await th.openCdp_allAccounts(_10_Accounts, contracts, dec(10, 'ether'), 0)
    await th.withdrawEBTC_allAccounts(_10_Accounts, contracts, dec(100, 18))

    // Whale adds 200 ether, withdraws 500 EBTC, redeems 500 EBTC
    await borrowerOperations.openCdp(0, whale, ZERO_ADDRESS, { from: whale, value: dec(200, 'ether') })
    await borrowerOperations.withdrawEBTC(_100pct, dec(500, 18), whale, ZERO_ADDRESS, { from: whale })

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_MONTH, web3.currentProvider)
    const gas = await th.redeemCollateral(whale, contracts, dec(500, 18))
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  it("", async () => {
    const message = 'redeemCollateral(), redeemed 450 EBTC, redemption hits 5 Cdps,  last redemption is partial (50 of 100 EBTC)'
    await th.openCdp_allAccounts(_10_Accounts, contracts, dec(10, 'ether'), 0)
    await th.withdrawEBTC_allAccounts(_10_Accounts, contracts, dec(100, 18))

    // Whale adds 200 ether, withdraws 450 EBTC, redeems 500 EBTC
    await borrowerOperations.openCdp(0, whale, ZERO_ADDRESS, { from: whale, value: dec(200, 'ether') })
    await borrowerOperations.withdrawEBTC(_100pct, dec(450, 18), whale, ZERO_ADDRESS, { from: whale })

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_MONTH, web3.currentProvider)
    const gas = await th.redeemCollateral(whale, contracts, dec(450, 18))
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  it("", async () => {
    const message = 'redeemCollateral(), redeemed 1000 EBTC, redemption hits 10 Cdps'
    await th.openCdp_allAccounts(_10_Accounts, contracts, dec(10, 'ether'), 0)
    await th.withdrawEBTC_allAccounts(_10_Accounts, contracts, dec(100, 18))

    // Whale adds 200 ether, withdraws 1000 EBTC, redeems 500 EBTC
    await borrowerOperations.openCdp(0, whale, ZERO_ADDRESS, { from: whale, value: dec(200, 'ether') })
    await borrowerOperations.withdrawEBTC(_100pct, dec(1000, 18), whale, ZERO_ADDRESS, { from: whale })
    
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_MONTH, web3.currentProvider)
    const gas = await th.redeemCollateral(whale, contracts, dec(1000, 18))
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  it("", async () => {
    const message = 'redeemCollateral(), redeemed 1500 EBTC, redemption hits 15 Cdps'
    await th.openCdp_allAccounts(_20_Accounts, contracts, dec(10, 'ether'), 0)
    await th.withdrawEBTC_allAccounts(_20_Accounts, contracts, dec(100, 18))

    // Whale adds 200 ether, withdraws 1500 EBTC, redeems 1500 EBTC
    await borrowerOperations.openCdp(0, whale, ZERO_ADDRESS, { from: whale, value: dec(200, 'ether') })
    await borrowerOperations.withdrawEBTC(_100pct, dec(1500, 18), whale, ZERO_ADDRESS, { from: whale })
    
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_MONTH, web3.currentProvider)
    const gas = await th.redeemCollateral(whale, contracts, dec(1500, 18))
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  it("", async () => {
    const message = 'redeemCollateral(), redeemed 2000 EBTC, redemption hits 20 Cdps'
    await th.openCdp_allAccounts(_30_Accounts, contracts, dec(10, 'ether'), 0)
    await th.withdrawEBTC_allAccounts(_30_Accounts, contracts, dec(100, 18))

    // Whale adds 200 ether, withdraws 2000 EBTC, redeems 2000 EBTC
    await borrowerOperations.openCdp(0, whale, ZERO_ADDRESS, { from: whale, value: dec(200, 'ether') })
    await borrowerOperations.withdrawEBTC(_100pct, dec(2000, 18), whale, ZERO_ADDRESS, { from: whale })
    
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_MONTH, web3.currentProvider)
    const gas = await th.redeemCollateral(whale, contracts, dec(2000, 18))
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
    const message = 'redeemCollateral(), redeems 50 EBTC, redemption hits 1 Cdp, WITH pending rewards. One account in system'
    await th.openCdp_allAccounts([accounts[1]], contracts, dec(10, 'ether'), 0)
    await borrowerOperations.withdrawEBTC(_100pct, dec(100, 18), accounts[1], ZERO_ADDRESS, { from: accounts[1] })

    // acct 998 adds coll, withdraws EBTC, sits at 111% ICR
    await th.openCdp_allAccounts([accounts[998]], contracts, dec(1, 'ether'), 0)
    await borrowerOperations.withdrawEBTC(_100pct, dec(130, 18), accounts[998], ZERO_ADDRESS, { from: accounts[998] })

    // Price drops, account[998]'s ICR falls below MCR, and gets liquidated
    await priceFeed.setPrice(dec(100, 18))
    await cdpManager.liquidate(accounts[998], { from: accounts[0] })

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_MONTH, web3.currentProvider)
    const gas = await th.redeemCollateral(accounts[1], contracts, dec(50, 18))

    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  it("", async () => {
    const message = 'redeemCollateral(), redeems 50 EBTC, redemption hits 1 Cdp. WITH pending rewards. 3 accounts in system.'
    // 3 accounts add coll
    await th.openCdp_allAccounts(accounts.slice(0, 3), contracts, dec(10, 'ether'), 0)
    // 3 accounts withdraw successively less EBTC
    await borrowerOperations.withdrawEBTC(_100pct, dec(100, 18), accounts[0], ZERO_ADDRESS, { from: accounts[0] })
    await borrowerOperations.withdrawEBTC(_100pct, dec(90, 18), accounts[1], ZERO_ADDRESS, { from: accounts[1] })
    await borrowerOperations.withdrawEBTC(_100pct, dec(80, 18), accounts[2], ZERO_ADDRESS, { from: accounts[2] })

    // acct 999 adds coll, withdraws EBTC, sits at 111% ICR
    await th.openCdp_allAccounts([accounts[998]], contracts, dec(1, 'ether'), 0)
    await borrowerOperations.withdrawEBTC(_100pct, dec(130, 18), accounts[998], ZERO_ADDRESS, { from: accounts[998] })

    // Price drops, account[998]'s ICR falls below MCR, and gets liquidated
    await priceFeed.setPrice(dec(100, 18))
    await cdpManager.liquidate(accounts[998], { from: accounts[0] })

    /* Account 2 redeems 50 EBTC. It is redeemed from account 0's Cdp, 
    leaving the Cdp active with 30 EBTC and ((200 *10 - 50 ) / 200 ) = 9.75 ETH. 
    
    It's ICR jumps from 2500% to 6500% and it is reinserted at the top of the list.
    */

   await th.fastForwardTime(timeValues.SECONDS_IN_ONE_MONTH, web3.currentProvider)
    const gas = await th.redeemCollateral(accounts[2], contracts, dec(50, 18))
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  it("", async () => {
    const message = 'redeemCollateral(), redeemed 500 EBTC, WITH pending rewards, redemption hits 5 Cdps, WITH pending rewards'
    await th.openCdp_allAccounts(_10_Accounts, contracts, dec(10, 'ether'), 0)
    await th.withdrawEBTC_allAccounts(_10_Accounts, contracts, dec(100, 18))

    // Whale adds 200 ether, withdraws 500 EBTC, redeems 500 EBTC
    await borrowerOperations.openCdp(0, whale, ZERO_ADDRESS, { from: whale, value: dec(200, 'ether') })
    await borrowerOperations.withdrawEBTC(_100pct, dec(500, 18), whale, ZERO_ADDRESS, { from: whale })

    // acct 998 adds coll, withdraws EBTC, sits at 111% ICR
    await th.openCdp_allAccounts([accounts[998]], contracts, dec(1, 'ether'), 0)
    await borrowerOperations.withdrawEBTC(_100pct, dec(130, 18), accounts[998], ZERO_ADDRESS, { from: accounts[998] })

    // Price drops, account[998]'s ICR falls below MCR, and gets liquidated
    await priceFeed.setPrice(dec(100, 18))
    await cdpManager.liquidate(accounts[998], { from: accounts[0] })

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_MONTH, web3.currentProvider)
    const gas = await th.redeemCollateral(whale, contracts, dec(500, 18))
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  it("", async () => {
    const message = 'redeemCollateral(), redeemed 1000 EBTC, WITH pending rewards, redemption hits 10 Cdps, WITH pending rewards'
    await th.openCdp_allAccounts(_10_Accounts, contracts, dec(10, 'ether'), 0)
    await th.withdrawEBTC_allAccounts(_10_Accounts, contracts, dec(100, 18))

    // Whale adds 200 ether, withdraws 1000 EBTC, redeems 500 EBTC
    await borrowerOperations.openCdp(0, whale, ZERO_ADDRESS, { from: whale, value: dec(200, 'ether') })
    await borrowerOperations.withdrawEBTC(_100pct, dec(1000, 18), whale, ZERO_ADDRESS, { from: whale })

    // acct 998 adds coll, withdraws EBTC, sits at 111% ICR
    await th.openCdp_allAccounts([accounts[998]], contracts, dec(1, 'ether'), 0)
    await borrowerOperations.withdrawEBTC(_100pct, dec(130, 18), accounts[998], ZERO_ADDRESS, { from: accounts[998] })

    // Price drops, account[998]'s ICR falls below MCR, and gets liquidated
    await priceFeed.setPrice(dec(100, 18))
    await cdpManager.liquidate(accounts[998], { from: accounts[0] })

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_MONTH, web3.currentProvider)
    const gas = await th.redeemCollateral(whale, contracts, dec(1000, 18))
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  it("", async () => {
    const message = 'redeemCollateral(), redeemed 1500 EBTC, WITH pending rewards, redemption hits 15 Cdps, WITH pending rewards'
    await th.openCdp_allAccounts(_20_Accounts, contracts, dec(10, 'ether'), 0)
    await th.withdrawEBTC_allAccounts(_20_Accounts, contracts, dec(100, 18))

    // Whale adds 200 ether, withdraws 1500 EBTC, redeems 1500 EBTC
    await borrowerOperations.openCdp(0, whale, ZERO_ADDRESS, { from: whale, value: dec(200, 'ether') })
    await borrowerOperations.withdrawEBTC(_100pct, dec(1500, 18), whale, ZERO_ADDRESS, { from: whale })

    //  // acct 998 adds coll, withdraws EBTC, sits at 111% ICR
    await th.openCdp_allAccounts([accounts[998]], contracts, dec(1, 'ether'), 0)
    await borrowerOperations.withdrawEBTC(_100pct, dec(130, 18), accounts[998], ZERO_ADDRESS, { from: accounts[998] })

    // Price drops, account[998]'s ICR falls below MCR, and gets liquidated
    await priceFeed.setPrice(dec(100, 18))
    await cdpManager.liquidate(accounts[998], { from: accounts[0] })

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_MONTH, web3.currentProvider)
    const gas = await th.redeemCollateral(whale, contracts, dec(1500, 18))
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  it("", async () => {
    const message = 'redeemCollateral(), redeemed 2000 EBTC, WITH pending rewards, redemption hits 20 Cdps, WITH pending rewards'
    await th.openCdp_allAccounts(_30_Accounts, contracts, dec(10, 'ether'), 0)
    await th.withdrawEBTC_allAccounts(_30_Accounts, contracts, dec(100, 18))

    // Whale adds 200 ether, withdraws 2000 EBTC, redeems 2000 EBTC
    await borrowerOperations.openCdp(0, whale, ZERO_ADDRESS, { from: whale, value: dec(200, 'ether') })
    await borrowerOperations.withdrawEBTC(_100pct, dec(2000, 18), whale, ZERO_ADDRESS, { from: whale })

    // acct 998 adds coll, withdraws EBTC, sits at 111% ICR
    await th.openCdp_allAccounts([accounts[998]], contracts, dec(1, 'ether'), 0)
    await borrowerOperations.withdrawEBTC(_100pct, dec(130, 18), accounts[998], ZERO_ADDRESS, { from: accounts[998] })

    // Price drops, account[998]'s ICR falls below MCR, and gets liquidated
    await priceFeed.setPrice(dec(100, 18))
    await cdpManager.liquidate(accounts[998], { from: accounts[0] })

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_MONTH, web3.currentProvider)
    const gas = await th.redeemCollateral(whale, contracts, dec(2000, 18))
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

  it("", async () => {
    const message = 'provideToSP(), No pending rewards, all accounts withdraw 180 EBTC, all make first deposit, random EBTC amount'
    await th.openCdp_allAccounts(_10_Accounts, contracts, dec(10, 'ether'), 0)
    await th.withdrawEBTC_allAccounts(_10_Accounts, contracts, dec(130, 18))

    // first funds provided
    const gasResults = await th.provideToSP_allAccounts_randomAmount(1, 129, _10_Accounts, stabilityPool)
    th.logGasMetrics(gasResults, message)
    th.logAllGasCosts(gasResults)

    th.appendData(gasResults, message, data)
  })

     // --- Top-up deposit ---

  it("", async () => {
    const message = 'provideToSP(), No pending rewards, deposit part of issued EBTC: all accounts withdraw 180 EBTC, all make second deposit, provide 50 EBTC'
    await th.openCdp_allAccounts(_10_Accounts, contracts, dec(10, 'ether'), 0)
    await th.withdrawEBTC_allAccounts(_10_Accounts, contracts, dec(130, 18))
    await th.provideToSP_allAccounts(_10_Accounts, stabilityPool, dec(50, 18))

    // >>FF time and one account tops up, triggers LQTY gains for all
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)
    await stabilityPool.provideToSP(dec(1, 18), ZERO_ADDRESS, { from: _10_Accounts[0] })

    // Check the other accounts have LQTY gain
    for (account of _10_Accounts.slice(1)) {
      const LQTYGain = await stabilityPool.getDepositorLQTYGain(account)
      assert.isTrue(LQTYGain.gt(toBN('0')))
    }

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // top-up of StabilityPool Deposit
    const gasResults = await th.provideToSP_allAccounts(_10_Accounts, stabilityPool, dec(50, 18))
    th.logGasMetrics(gasResults, message)
    th.logAllGasCosts(gasResults)

    th.appendData(gasResults, message, data)
  })

  // it("", async () => {
  //   const message = 'provideToSP(), No pending rewards, deposit all issued EBTC: all accounts withdraw 180 EBTC, make second deposit, provide 90 EBTC'
  //   await th.openCdp_allAccounts(_10_Accounts, contracts, dec(10, 'ether'), 0)
  //   await th.withdrawEBTC_allAccounts(_10_Accounts, contracts, dec(130, 18))
  //   await th.provideToSP_allAccounts(_10_Accounts, stabilityPool, dec(50, 18))

  //   // >> FF time and one account tops up, triggers LQTY gains for all
  //   await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)
  //   await stabilityPool.provideToSP(dec(1, 18), ZERO_ADDRESS, { from: _10_Accounts[0] })

  //   // Check the other accounts have LQTY gain
  //   for (account of _10_Accounts.slice(1)) {
  //     const LQTYGain = await stabilityPool.getDepositorLQTYGain(account)
  //     assert.isTrue(LQTYGain.gt(toBN('0')))
  //   }

  //   await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

  //   // top-up of StabilityPool Deposit
  //   const gasResults = await th.provideToSP_allAccounts(_10_Accounts, stabilityPool, dec(50, 18))
  //   th.logGasMetrics(gasResults, message)
  //   th.logAllGasCosts(gasResults)

  //   th.appendData(gasResults, message, data)
  // })

  it("", async () => {
    const message = 'provideToSP(), No pending rewards, all accounts withdraw 180 EBTC, make second deposit, random EBTC amount'
    await th.openCdp_allAccounts(_10_Accounts, contracts, dec(10, 'ether'), 0)
    await th.withdrawEBTC_allAccounts(_10_Accounts, contracts, dec(130, 18))
    await th.provideToSP_allAccounts(_10_Accounts, stabilityPool, dec(50, 18))

    // >>FF time and one account tops up, triggers LQTY gains for all
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)
    await stabilityPool.provideToSP(dec(1, 18), ZERO_ADDRESS, { from: _10_Accounts[0] })

    // Check the other accounts have LQTY gain
    for (account of _10_Accounts.slice(1)) {
      const LQTYGain = await stabilityPool.getDepositorLQTYGain(account)
      assert.isTrue(LQTYGain.gt(toBN('0')))
    }

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // top-up of StabilityPool Deposit
    const gasResults = await th.provideToSP_allAccounts_randomAmount(1, 50, _10_Accounts, stabilityPool)
    th.logGasMetrics(gasResults, message)
    th.logAllGasCosts(gasResults)

    th.appendData(gasResults, message, data)
  })

  //   // --- provideToSP(): Pending rewards

  //   // --- Top-up deposit ---

  // it("", async () => {
  //   const message = 'provideToSP(), with pending rewards in system. deposit part of issued EBTC: all accounts make second deposit, provide 50 EBTC'
  //   // 9 accts each open Cdp with 10 ether, withdraw 180 EBTC, and provide 50 EBTC to Stability Pool
  //   await th.openCdp_allAccounts(accounts.slice(2, 12), contracts, dec(10, 'ether'), 0)
  //   await th.withdrawEBTC_allAccounts(accounts.slice(2, 12), contracts, dec(130, 18))
  //   await th.provideToSP_allAccounts(accounts.slice(2, 12), stabilityPool, dec(50, 18))

  //   //1 acct open Cdp with 1 ether and withdraws 170 EBTC
  //   await borrowerOperations.openCdp(dec(130, 18), accounts[1], ZERO_ADDRESS, { from: accounts[1], value: dec(1, 'ether') })

  //   // >>FF time and one account tops up, triggers LQTY gains for all
  //   await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

  //   // Price drops, account 1 liquidated
  //   await priceFeed.setPrice(dec(100, 18))
  //   await cdpManager.liquidate(accounts[1], { from: accounts[0] })
  //   assert.isFalse(await sortedCdps.contains(accounts[1]))

  //   // Check accounts have LQTY gains from liquidations
  //   for (account of accounts.slice(2, 12)) {
  //     const LQTYGain = await stabilityPool.getDepositorLQTYGain(account)
  //     assert.isTrue(LQTYGain.gt(toBN('0')))
  //   }

  //   await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

  //   // 9 active Cdps top up their Stability Pool deposits with 50 EBTC
  //   const gasResults = await th.provideToSP_allAccounts(accounts.slice(2, 11), stabilityPool, dec(50, 18))
  //   th.logGasMetrics(gasResults, message)
  //   th.logAllGasCosts(gasResults)

  //   th.appendData(gasResults, message, data)
  // })

  // it("", async () => {
  //   const message = 'provideToSP(), with pending rewards in system. deposit all issued EBTC: all accounts make second deposit, provide 90 EBTC'
  //   // 10 accts each open Cdp with 10 ether, withdraw 180 EBTC, and provide 90 EBTC to Stability Pool
  //   await th.openCdp_allAccounts(accounts.slice(2, 12), contracts, dec(10, 'ether'), 0)
  //   await th.withdrawEBTC_allAccounts(accounts.slice(2, 12), contracts, dec(130, 18))
  //   await th.provideToSP_allAccounts(accounts.slice(2, 12), stabilityPool, dec(50, 18))

  //   //1 acct open Cdp with 1 ether and withdraws 180 EBTC
  //   await borrowerOperations.openCdp(dec(130, 18), accounts[1], ZERO_ADDRESS, { from: accounts[1], value: dec(1, 'ether') })

  //   // >>FF time and one account tops up, triggers LQTY gains for all
  //   await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

  //   // Price drops, account[1] is liquidated
  //   await priceFeed.setPrice(dec(100, 18))
  //   await cdpManager.liquidate(accounts[1], { from: accounts[0] })
  //   assert.isFalse(await sortedCdps.contains(accounts[1]))

  //   // Check accounts have LQTY gains from liquidations
  //   for (account of accounts.slice(2, 12)) {
  //     const LQTYGain = await stabilityPool.getDepositorLQTYGain(account)
  //     assert.isTrue(LQTYGain.gt(toBN('0')))
  //   }

  //   await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

  //   // 5 active Cdps top up their Stability Pool deposits with 90 EBTC, using up all their issued EBTC
  //   const gasResults = await th.provideToSP_allAccounts(accounts.slice(7, 12), stabilityPool, dec(50, 18))
  //   th.logGasMetrics(gasResults, message)
  //   th.logAllGasCosts(gasResults)

  //   th.appendData(gasResults, message, data)
  // })

  it("", async () => {
    const message = 'provideToSP(), with pending rewards in system. deposit part of issued EBTC: all make second deposit, provide random EBTC amount'
    // 10 accts each open Cdp with 10 ether, withdraw 180 EBTC, and provide 90 EBTC to Stability Pool
    await th.openCdp_allAccounts(accounts.slice(2, 12), contracts, dec(10, 'ether'), dec(130, 18))
    await th.provideToSP_allAccounts(accounts.slice(2, 12), stabilityPool, dec(50, 18))

    //1 acct open Cdp with 1 ether and withdraws 180 EBTC
    await borrowerOperations.openCdp(dec(130, 18), accounts[1], ZERO_ADDRESS, { from: accounts[1], value: dec(1, 'ether') })

    // >>FF time and one account tops up, triggers LQTY gains for all
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Price drops, account[1] is liquidated
    await priceFeed.setPrice(dec(100, 18))
    await cdpManager.liquidate(accounts[1], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[1]))

    // Check accounts have LQTY gains from liquidations
    for (account of accounts.slice(2, 12)) {
      const LQTYGain = await stabilityPool.getDepositorLQTYGain(account)
      assert.isTrue(LQTYGain.gt(toBN('0')))
    }

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // 5 active Cdps top up their Stability Pool deposits with a random EBTC amount
    const gasResults = await th.provideToSP_allAccounts_randomAmount(1, 49, accounts.slice(7, 12), stabilityPool)
    th.logGasMetrics(gasResults, message)
    th.logAllGasCosts(gasResults)

    th.appendData(gasResults, message, data)
  })

  // --- withdrawFromSP() ---

  // --- No pending rewards ---

  // partial
  // it("", async () => {
  //   const message = 'withdrawFromSP(), no pending rewards. Stability Pool depositors make partial withdrawal - 90 EBTC of 180 EBTC deposit'
  //   await th.openCdp_allAccounts(_10_Accounts, contracts, dec(10, 'ether'), dec(190, 18))
  //   await th.provideToSP_allAccounts(_10_Accounts, stabilityPool, dec(130, 18))

  //   // >>FF time and one account tops up, triggers LQTY gains for all
  //   await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)
  //   await stabilityPool.provideToSP(dec(1, 18), ZERO_ADDRESS, { from: _10_Accounts[0] })

  //   // Check the other accounts have LQTY gain
  //   for (account of _10_Accounts.slice(1)) {
  //     const LQTYGain = await stabilityPool.getDepositorLQTYGain(account)
  //     assert.isTrue(LQTYGain.gt(toBN('0')))
  //   }
  //   await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

  //   const gasResults = await th.withdrawFromSP_allAccounts(_10_Accounts, stabilityPool, dec(90, 18))
  //   th.logGasMetrics(gasResults, message)
  //   th.logAllGasCosts(gasResults)

  //   th.appendData(gasResults, message, data)
  // })

  // full
  it("", async () => {
    const message = 'withdrawFromSP(), no pending rewards. Stability Pool depositors make full withdrawal - 130 EBTC of 130 EBTC deposit'
    await th.openCdp_allAccounts(_10_Accounts, contracts, dec(10, 'ether'), dec(190, 18))
    await th.provideToSP_allAccounts(_10_Accounts, stabilityPool, dec(130, 18))

    // >>FF time and one account tops up, triggers LQTY gains for all
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)
    await stabilityPool.provideToSP(dec(1, 18), ZERO_ADDRESS, { from: _10_Accounts[0] })

    // Check the other accounts have LQTY gain
    for (account of _10_Accounts.slice(1)) {
      const LQTYGain = await stabilityPool.getDepositorLQTYGain(account)
      assert.isTrue(LQTYGain.gt(toBN('0')))
    }
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    const gasResults = await th.withdrawFromSP_allAccounts(_10_Accounts, stabilityPool, dec(130, 18))
    th.logGasMetrics(gasResults, message)
    th.logAllGasCosts(gasResults)

    th.appendData(gasResults, message, data)
  })

  // random amount
  it("", async () => {
    const message = 'withdrawFromSP(), no pending rewards. Stability Pool depositors make partial withdrawal - random EBTC amount, less than 180 EBTC deposit'
    await th.openCdp_allAccounts(_10_Accounts, contracts, dec(10, 'ether'), dec(130, 18))
    await th.provideToSP_allAccounts(_10_Accounts, stabilityPool, dec(130, 18))

    const gasResults = await th.withdrawFromSP_allAccounts_randomAmount(1, 129, _10_Accounts, stabilityPool)
    th.logGasMetrics(gasResults, message)
    th.logAllGasCosts(gasResults)

    th.appendData(gasResults, message, data)
  })


  // // --- withdrawFromSP() ---

  // // --- Pending rewards in system ---

  // it("", async () => {
  //   const message = 'withdrawFromSP(), pending rewards in system. Stability Pool depositors make partial withdrawal - 90 EBTC of 130 EBTC deposit'
  //   // 10 accts each open Cdp with 10 ether, withdraw 180 EBTC, and provide 180 EBTC to Stability Pool
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

  //   // Check accounts have LQTY gains from liquidations
  //   for (account of accounts.slice(2, 12)) {
  //     const LQTYGain = await stabilityPool.getDepositorLQTYGain(account)
  //     assert.isTrue(LQTYGain.gt(toBN('0')))
  //   }

  //   await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

  //   // 5 active Cdps reduce their Stability Pool deposit by 90 EBTC
  //   const gasResults = await th.withdrawFromSP_allAccounts(accounts.slice(7, 12), stabilityPool, dec(90, 18))
  //   th.logGasMetrics(gasResults, message)
  //   th.logAllGasCosts(gasResults)

  //   th.appendData(gasResults, message, data)
  // })

  it("", async () => {
    const message = 'withdrawFromSP(), pending rewards in system. Stability Pool depositors make full withdrawal - 130 EBTC of 130 EBTC deposit'
    // 10 accts each open Cdp with 10 ether, withdraw 180 EBTC, and provide 180 EBTC to Stability Pool
    await th.openCdp_allAccounts(accounts.slice(2, 12), contracts, dec(10, 'ether'), dec(130, 18))
    await th.provideToSP_allAccounts(accounts.slice(2, 12), stabilityPool, dec(130, 18))

    //1 acct open Cdp with 1 ether and withdraws 170 EBTC
    await borrowerOperations.openCdp(0, accounts[1], ZERO_ADDRESS, { from: accounts[1], value: dec(1, 'ether') })
    await borrowerOperations.withdrawEBTC(_100pct, dec(130, 18), accounts[1], ZERO_ADDRESS, { from: accounts[1] })


    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Price drops, account[0]'s ICR falls below MCR
    await priceFeed.setPrice(dec(100, 18))
    await cdpManager.liquidate(accounts[1], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[1]))

    // Check accounts have LQTY gains from liquidations
    for (account of accounts.slice(2, 12)) {
      const LQTYGain = await stabilityPool.getDepositorLQTYGain(account)
      assert.isTrue(LQTYGain.gt(toBN('0')))
    }

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // 5 active Cdps reduce their Stability Pool deposit by 130 EBTC
    const gasResults = await th.withdrawFromSP_allAccounts(accounts.slice(7, 12), stabilityPool, dec(130, 18))
    th.logGasMetrics(gasResults, message)
    th.logAllGasCosts(gasResults)

    th.appendData(gasResults, message, data)
  })

  it("", async () => {
    const message = 'withdrawFromSP(), pending rewards in system. Stability Pool depositors make partial withdrawal - random amount of EBTC'
    // 10 accts each open Cdp with 10 ether, withdraw 180 EBTC, and provide 130 EBTC to Stability Pool
    await th.openCdp_allAccounts(accounts.slice(2, 12), contracts, dec(10, 'ether'), dec(130, 18))
    await th.provideToSP_allAccounts(accounts.slice(2, 12), stabilityPool, dec(130, 18))

    //1 acct open Cdp with 1 ether and withdraws 170 EBTC
    await borrowerOperations.openCdp(0, accounts[1], ZERO_ADDRESS, { from: accounts[1], value: dec(1, 'ether') })
    await borrowerOperations.withdrawEBTC(_100pct, dec(130, 18), accounts[1], ZERO_ADDRESS, { from: accounts[1] })

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Price drops, account[0]'s ICR falls below MCR
    await priceFeed.setPrice(dec(100, 18))
    await cdpManager.liquidate(accounts[1], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[1]))

    // Check accounts have LQTY gains from liquidations
    for (account of accounts.slice(2, 12)) {
      const LQTYGain = await stabilityPool.getDepositorLQTYGain(account)
      assert.isTrue(LQTYGain.gt(toBN('0')))
    }

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // 5 active Cdps reduce their Stability Pool deposit by random amount
    const gasResults = await th.withdrawFromSP_allAccounts_randomAmount(1, 129, accounts.slice(7, 12), stabilityPool)
    th.logGasMetrics(gasResults, message)
    th.logAllGasCosts(gasResults)

    th.appendData(gasResults, message, data)
  })

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

  it("", async () => {
    const message = 'withdrawETHGainToCdp(), pending rewards in system. Accounts withdraw 180 EBTC, provide a random amount, then withdraw all to SP after a liquidation'
    // 20 accts each open Cdp with 10 ether, withdraw 180 EBTC, and provide 180 EBTC to Stability Pool
    await th.openCdp_allAccounts(accounts.slice(2, 22), contracts, dec(10, 'ether'), dec(130, 18))
    await await th.provideToSP_allAccounts_randomAmount(1, 129, accounts.slice(2, 22), stabilityPool)

    //1 acct open Cdp with 1 ether and withdraws 180 EBTC
    await borrowerOperations.openCdp(0, accounts[1], ZERO_ADDRESS, { from: accounts[1], value: dec(1, 'ether') })
    await borrowerOperations.withdrawEBTC(_100pct, dec(130, 18), accounts[1], ZERO_ADDRESS, { from: accounts[1] })

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)
  
    // Price drops, account[1]'s ICR falls below MCR
    await priceFeed.setPrice(dec(100, 18))
    await cdpManager.liquidate(accounts[1], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[1]))

       // Check accounts have LQTY gains from liquidations
       for (account of accounts.slice(2, 22)) {
        const LQTYGain = await stabilityPool.getDepositorLQTYGain(account)
        assert.isTrue(LQTYGain.gt(toBN('0')))
      }
  
      await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)
  
    // 5 active Cdps withdraw their ETH gain to their cdp
    const gasResults = await th.withdrawETHGainToCdp_allAccounts(accounts.slice(2, 22), contracts)
    th.logGasMetrics(gasResults, message)
    th.logAllGasCosts(gasResults)

    th.appendData(gasResults, message, data)
  })

  // --- liquidate() ---

  // Pure redistribution WITH pending rewards
  it("", async () => {
    const message = 'Single liquidate() call. Liquidee has pending rewards. Pure redistribution'
    // 10 accts each open Cdp with 10 ether, withdraw 180 EBTC
    await th.openCdp_allAccounts(accounts.slice(100, 110), contracts, dec(10, 'ether'), 0)
    await th.withdrawEBTC_allAccounts(accounts.slice(100, 110), contracts, dec(130, 18))

    //6s acct open Cdp with 1 ether and withdraw 180 EBTC (inc gas comp)
    await th.openCdp_allAccounts(accounts.slice(0, 6), contracts, dec(1, 'ether'), dec(130, 18))
    // Price drops, account[1]'s ICR falls below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Initial distribution liquidations make system reward terms and Default Pool non-zero
    const tx1 = await cdpManager.liquidate(accounts[2], { from: accounts[0] })
    // const gas1 = th.gasUsed(tx1)
    // th.logGas(gas1, message)
    const tx2 = await cdpManager.liquidate(accounts[3], { from: accounts[0] })
    // const gas2 = th.gasUsed(tx2)
    // th.logGas(gas2, message)

    assert.isTrue(await sortedCdps.contains(accounts[1]))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    const tx5 = await cdpManager.liquidate(accounts[1], { from: accounts[0] })

    assert.isFalse(await sortedCdps.contains(accounts[1]))
    const gas5 = th.gasUsed(tx5)
    th.logGas(gas5, message)

    th.appendData({ gas: gas5 }, message, data)
  })

  it("", async () => {
    const message = 'Series of liquidate() calls. Liquidee has pending rewards. Pure redistribution'
    // 100 accts each open Cdp with 10 ether, withdraw 180 EBTC
    await th.openCdp_allAccounts(accounts.slice(100, 200), contracts, dec(10, 'ether'), 0)
    await th.withdrawEBTC_allAccounts(accounts.slice(100, 200), contracts, dec(130, 18))

    const liquidationAcctRange = accounts.slice(1, 10)

    // Accts open Cdp with 1 ether and withdraws 180 EBTC (inc gas comp)
    await th.openCdp_allAccounts(liquidationAcctRange, contracts, dec(1, 'ether'), 0)
    await th.withdrawEBTC_allAccounts(liquidationAcctRange, contracts, dec(130, 18))

    // Price drops, account[1]'s ICR falls below MCR
    await priceFeed.setPrice(dec(100, 18))

    // All cdps are liquidated
    for (account of liquidationAcctRange) {
      const hasPendingRewards = await cdpManager.hasPendingRewards(account)
      console.log("Liquidee has pending rewards: " + hasPendingRewards)

      await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

      const tx = await cdpManager.liquidate(account, { from: accounts[0] })
      assert.isFalse(await sortedCdps.contains(account))

      const gas = th.gasUsed(tx)
      th.logGas(gas, message)
    }

    // th.appendData({gas: gas}, message, data)
  })

  // Pure redistribution with NO pending rewards
  it("", async () => {
    const message = 'Single liquidate() call. Liquidee has NO pending rewards. Pure redistribution'
    // 10 accts each open Cdp with 10 ether, withdraw 180 EBTC
    await th.openCdp_allAccounts(accounts.slice(100, 110), contracts, dec(10, 'ether'), 0)
    await th.withdrawEBTC_allAccounts(accounts.slice(100, 110), contracts, dec(130, 18))

    //2 acct open Cdp with 1 ether and withdraws 180 EBTC (inc gas comp)
    await th.openCdp_allAccounts(accounts.slice(2, 4), contracts, dec(1, 'ether'), 0)
    await borrowerOperations.withdrawEBTC(_100pct, dec(130, 18), accounts[2], ZERO_ADDRESS, { from: accounts[2] })
    await borrowerOperations.withdrawEBTC(_100pct, dec(130, 18), accounts[3], ZERO_ADDRESS, { from: accounts[3] })

    // Price drops
    await priceFeed.setPrice(dec(100, 18))

    // Initial distribution liquidations make system reward terms and DefaultPool non-zero
    const tx1 = await cdpManager.liquidate(accounts[2], { from: accounts[0] })
    const tx2 = await cdpManager.liquidate(accounts[3], { from: accounts[0] })

    // Account 1 opens cdp
    await borrowerOperations.openCdp(dec(40, 18), accounts[1], ZERO_ADDRESS, { from: accounts[1], value: dec(1, 'ether') })

    // Price drops, account[1]'s ICR falls below MCR
    await priceFeed.setPrice(dec(50, 18))

    assert.isTrue(await sortedCdps.contains(accounts[1]))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    const tx3 = await cdpManager.liquidate(accounts[1], { from: accounts[0] })

    assert.isFalse(await sortedCdps.contains(accounts[1]))
    const gas = th.gasUsed(tx3)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  it("", async () => {
    const message = 'Series of liquidate() calls. Liquidee has NO pending rewards. Pure redistribution'

    // 10 accts each open Cdp with 10 ether, withdraw 180 EBTC

    await th.openCdp_allAccounts(accounts.slice(100, 110), contracts, dec(10, 'ether'), 0)
    await th.withdrawEBTC_allAccounts(accounts.slice(100, 110), contracts, dec(130, 18))

    const liquidationAcctRange = accounts.slice(1, 20)

    for (account of liquidationAcctRange) {
      await priceFeed.setPrice(dec(200, 18))
      await borrowerOperations.openCdp(dec(130, 18), account, ZERO_ADDRESS, { from: account, value: dec(1, 'ether') })

      const hasPendingRewards = await cdpManager.hasPendingRewards(account)
      console.log("Liquidee has pending rewards: " + hasPendingRewards)

      await priceFeed.setPrice(dec(100, 18))

      await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

      const tx = await cdpManager.liquidate(account, { from: accounts[0] })

      assert.isFalse(await sortedCdps.contains(account))

      const gas = th.gasUsed(tx)
      th.logGas(gas, message)
    }

    // th.appendData({gas: gas}, message, data)
  })

  // Pure offset with NO pending rewards
  it("", async () => {
    const message = 'Single liquidate() call. Liquidee has NO pending rewards. Pure offset with SP'
    // 10 accts each open Cdp with 10 ether, withdraw 180 EBTC
    await th.openCdp_allAccounts(accounts.slice(100, 110), contracts, dec(10, 'ether'), 0)
    await th.withdrawEBTC_allAccounts(accounts.slice(100, 110), contracts, dec(130, 18))

    //3 acct open Cdp with 1 ether and withdraws 180 EBTC (inc gas comp)
    await th.openCdp_allAccounts(accounts.slice(0, 4), contracts, dec(1, 'ether'), 0)
    await borrowerOperations.withdrawEBTC(_100pct, dec(130, 18), accounts[1], ZERO_ADDRESS, { from: accounts[1] })
    await borrowerOperations.withdrawEBTC(_100pct, dec(130, 18), accounts[2], ZERO_ADDRESS, { from: accounts[2] })
    await borrowerOperations.withdrawEBTC(_100pct, dec(130, 18), accounts[3], ZERO_ADDRESS, { from: accounts[3] })

    // Price drops, account[1]'s ICR falls below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Account 100 provides 600 EBTC to pool
    await borrowerOperations.withdrawEBTC(_100pct, dec(600, 18), accounts[100], ZERO_ADDRESS, { from: accounts[100] })
    await stabilityPool.provideToSP(dec(600, 18), ZERO_ADDRESS, { from: accounts[100] })

    // Initial liquidations - full offset - makes SP reward terms and SP non-zero
    await cdpManager.liquidate(accounts[2], { from: accounts[0] })
    await cdpManager.liquidate(accounts[3], { from: accounts[0] })

    const hasPendingRewards = await cdpManager.hasPendingRewards(accounts[1])
    console.log("Liquidee has pending rewards: " + hasPendingRewards)

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Account 1 liquidated - full offset
    const tx = await cdpManager.liquidate(accounts[1], { from: accounts[0] })
    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // Pure offset WITH pending rewards
  it("", async () => {
    const message = 'Single liquidate() call. Liquidee has pending rewards. Pure offset with SP'
    // 10 accts each open Cdp with 10 ether, withdraw 180 EBTC
    await th.openCdp_allAccounts(accounts.slice(100, 110), contracts, dec(10, 'ether'), 0)
    await th.withdrawEBTC_allAccounts(accounts.slice(100, 110), contracts, dec(130, 18))

    // 5 acct open Cdp with 1 ether and withdraws 180 EBTC (inc gas comp)
    await th.openCdp_allAccounts(accounts.slice(0, 5), contracts, dec(1, 'ether'), 0)
    await borrowerOperations.withdrawEBTC(_100pct, dec(130, 18), accounts[1], ZERO_ADDRESS, { from: accounts[1] })
    await borrowerOperations.withdrawEBTC(_100pct, dec(130, 18), accounts[2], ZERO_ADDRESS, { from: accounts[2] })
    await borrowerOperations.withdrawEBTC(_100pct, dec(130, 18), accounts[3], ZERO_ADDRESS, { from: accounts[3] })
    await borrowerOperations.withdrawEBTC(_100pct, dec(130, 18), accounts[4], ZERO_ADDRESS, { from: accounts[4] })

    // Price drops, account[1]'s ICR falls below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Account 100 provides 360 EBTC to SP
    await borrowerOperations.withdrawEBTC(_100pct, dec(600, 18), accounts[100], ZERO_ADDRESS, { from: accounts[100] })
    await stabilityPool.provideToSP(dec(360, 18), ZERO_ADDRESS, { from: accounts[100] })

    // Initial liquidations - full offset - makes SP reward terms and SP non-zero
    await cdpManager.liquidate(accounts[2], { from: accounts[0] })
    await cdpManager.liquidate(accounts[3], { from: accounts[0] })

    // Pure redistribution - creates pending dist. rewards for account 1
    await cdpManager.liquidate(accounts[4], { from: accounts[0] })

    // Account 5 provides another 200 to the SP
    await stabilityPool.provideToSP(dec(200, 18), ZERO_ADDRESS, { from: accounts[100] })

    const hasPendingRewards = await cdpManager.hasPendingRewards(accounts[1])
    console.log("Liquidee has pending rewards: " + hasPendingRewards)

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Account 1 liquidated - full offset
    const tx = await cdpManager.liquidate(accounts[1], { from: accounts[0] })
    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // Partial offset + redistribution WITH pending rewards
  it("", async () => {
    const message = 'Single liquidate() call. Liquidee has pending rewards. Partial offset + redistribution'
    // 10 accts each open Cdp with 10 ether, withdraw 180 EBTC
    await th.openCdp_allAccounts(accounts.slice(100, 110), contracts, dec(10, 'ether'), 0)
    await th.withdrawEBTC_allAccounts(accounts.slice(100, 110), contracts, dec(130, 18))

    //4 acct open Cdp with 1 ether and withdraws 180 EBTC (inc gas comp)
    await th.openCdp_allAccounts(accounts.slice(0, 4), contracts, dec(1, 'ether'), 0)
    await borrowerOperations.withdrawEBTC(_100pct, dec(130, 18), accounts[1], ZERO_ADDRESS, { from: accounts[1] })
    await borrowerOperations.withdrawEBTC(_100pct, dec(130, 18), accounts[2], ZERO_ADDRESS, { from: accounts[2] })
    await borrowerOperations.withdrawEBTC(_100pct, dec(130, 18), accounts[3], ZERO_ADDRESS, { from: accounts[3] })

    // Price drops, account[1]'s ICR falls below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Set up some "previous" liquidations triggering partial offsets, and pending rewards for all cdps
    await stabilityPool.provideToSP(dec(100, 18), ZERO_ADDRESS, { from: accounts[100] })
    await cdpManager.liquidate(accounts[2], { from: accounts[0] })

    await stabilityPool.provideToSP(dec(100, 18), ZERO_ADDRESS, { from: accounts[101] })
    await cdpManager.liquidate(accounts[3], { from: accounts[0] })

    // pool refilled with 100 EBTC
    await stabilityPool.provideToSP(dec(100, 18), ZERO_ADDRESS, { from: accounts[102] })

    const hasPendingRewards = await cdpManager.hasPendingRewards(accounts[1])
    console.log("Liquidee has pending rewards: " + hasPendingRewards)

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // account 1 180 EBTC liquidated  - partial offset
    const tx = await cdpManager.liquidate(accounts[1], { from: accounts[0] })
    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // Partial offset + redistribution with NO pending rewards
  it("", async () => {
    const message = 'Single liquidate() call. Liquidee has NO pending rewards. Partial offset + redistribution'
    // 10 accts each open Cdp with 10 ether, withdraw 180 EBTC
    await th.openCdp_allAccounts(accounts.slice(100, 110), contracts, dec(10, 'ether'), 0)
    await th.withdrawEBTC_allAccounts(accounts.slice(100, 110), contracts, dec(130, 18))

    //2 acct open Cdp with 1 ether and withdraws 180 EBTC (inc gas comp)
    await th.openCdp_allAccounts(accounts.slice(2, 4), contracts, dec(1, 'ether'), 0)
    await borrowerOperations.withdrawEBTC(_100pct, dec(130, 18), accounts[2], ZERO_ADDRESS, { from: accounts[2] })
    await borrowerOperations.withdrawEBTC(_100pct, dec(130, 18), accounts[3], ZERO_ADDRESS, { from: accounts[3] })

    // Price drops, account[1]'s ICR falls below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Set up some "previous" liquidations that trigger partial offsets, 
    //and create pending rewards for all cdps
    await stabilityPool.provideToSP(dec(100, 18), ZERO_ADDRESS, { from: accounts[100] })
    await cdpManager.liquidate(accounts[2], { from: accounts[0] })

    await stabilityPool.provideToSP(dec(100, 18), ZERO_ADDRESS, { from: accounts[101] })
    await cdpManager.liquidate(accounts[3], { from: accounts[0] })

    // Pool refilled with 50 EBTC
    await stabilityPool.provideToSP(dec(50, 18), ZERO_ADDRESS, { from: accounts[102] })

    // Account 1 opens cdp
    await borrowerOperations.openCdp(dec(30, 18), accounts[1], ZERO_ADDRESS, { from: accounts[1], value: dec(1, 'ether') })

    // Price drops, account[1]'s ICR falls below MCR
    await priceFeed.setPrice(dec(50, 18))

    const hasPendingRewards = await cdpManager.hasPendingRewards(accounts[1])
    console.log("Liquidee has pending rewards: " + hasPendingRewards)

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // account 1 70 EBTC liquidated  - partial offset against 50 EBTC in SP
    const tx = await cdpManager.liquidate(accounts[1], { from: accounts[0] })
    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // With pending dist. rewards and SP gains (still closes) - partial offset (Highest gas cost scenario in Normal Mode)
  it("", async () => {
    const message = 'liquidate() 1 Cdp, liquidated Cdp has pending SP rewards and redistribution rewards, offset + redistribution.'
    // 10 accts each open Cdp with 10 ether
    await th.openCdp_allAccounts(accounts.slice(100, 110), contracts, dec(10, 'ether'), 0)

    //Account 99 and 98 each open Cdp with 1 ether, and withdraw 180 EBTC (inc gas comp)
    await th.openCdp_allAccounts([accounts[99]], contracts, dec(1, 'ether'), 0)
    await borrowerOperations.withdrawEBTC(_100pct, dec(130, 18), accounts[99], ZERO_ADDRESS, { from: accounts[99] })
    await th.openCdp_allAccounts([accounts[98]], contracts, dec(1, 'ether'), 0)
    await borrowerOperations.withdrawEBTC(_100pct, dec(130, 18), accounts[98], ZERO_ADDRESS, { from: accounts[98] })

    // Acct 99 deposits 1 EBTC to SP
    await stabilityPool.provideToSP(dec(1, 18), ZERO_ADDRESS, { from: accounts[99] })

    //Account 97 opens Cdp with 1 ether and withdraws 180 EBTC (inc gas comp)
    await th.openCdp_allAccounts([accounts[97]], contracts, dec(1, 'ether'), 0)
    await borrowerOperations.withdrawEBTC(_100pct, dec(130, 18), accounts[97], ZERO_ADDRESS, { from: accounts[97] })

    // Acct 100 withdraws 1800 EBTC and deposits it to the SP
    await borrowerOperations.withdrawEBTC(_100pct, dec(1750, 18), accounts[100], ZERO_ADDRESS, { from: accounts[100] })
    await stabilityPool.provideToSP(dec(1750, 18), ZERO_ADDRESS, { from: accounts[100] })

    // Price drops too $100, accounts 99 and 100 ICR fall below MCR
    await priceFeed.setPrice(dec(100, 18))
    const price = await priceFeed.getPrice()

    /* Liquidate account 97. Account 97 is completely offset against SP and removed from system.
    This creates SP gains for accounts 99 and 7. */
    await cdpManager.liquidate(accounts[97], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[97]))

    // Price rises again to 200
    await priceFeed.setPrice(dec(200, 18))

    // Acct 100 withdraws deposit and gains from SP
    await stabilityPool.withdrawFromSP(dec(1750, 18), { from: accounts[100] })

     // Price drops again to 100
     await priceFeed.setPrice(dec(100, 18))

    // Account 98 is liquidated, with nothing in SP pool.  This creates pending rewards from distribution.
    await cdpManager.liquidate(accounts[98], { from: accounts[0] })

    // Account 7 deposits 1 EBTC in the Stability Pool
    await stabilityPool.provideToSP(dec(1, 18), ZERO_ADDRESS, { from: accounts[100] })

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    const tx = await cdpManager.liquidate(accounts[99], { from: accounts[0] })
    assert.isFalse(await sortedCdps.contains(accounts[99]))

    const gas = th.gasUsed(tx)
    th.logGas(gas, message)

    th.appendData({ gas: gas }, message, data)
  })

  // pure offset
  it("", async () => {
    const message = 'liquidate() 1 Cdp Normal Mode, 30 active Cdps, no ETH gain in pool, pure offset with SP'
    // 30 accts each open Cdp with 10 ether, withdraw 180 EBTC, and provide 180 EBTC to Stability Pool
    await th.openCdp_allAccounts(accounts.slice(100, 130), contracts, dec(10, 'ether'), 0)
    await th.withdrawEBTC_allAccounts(accounts.slice(100, 130), contracts, dec(130, 18))

    await stabilityPool.provideToSP(dec(130, 18), ZERO_ADDRESS, { from: accounts[100] })

    //1 acct open Cdp with 1 ether and withdraws 180 EBTC (inc gas comp)
    await th.openCdp_allAccounts([accounts[1]], contracts, dec(1, 'ether'), 0)
    await borrowerOperations.withdrawEBTC(_100pct, dec(130, 18), accounts[1], ZERO_ADDRESS, { from: accounts[1] })

    // Price drops, account[1]'s ICR falls below MCR
    await priceFeed.setPrice(dec(100, 18))

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)
    
    const tx = await cdpManager.liquidate(accounts[1], { from: accounts[0] })
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
    fs.writeFile('gasTest/outputs/gasTestData.csv', data, (err) => {
      if (err) { console.log(err) } else {
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
