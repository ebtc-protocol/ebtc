const deploymentHelper = require("../utils/deploymentHelpers.js")
const testHelpers = require("../utils/testHelpers.js")

const th = testHelpers.TestHelper
const { dec, toBN } = th
const moneyVals = testHelpers.MoneyValues

let latestRandomSeed = 31337

const CdpManagerTester = artifacts.require("CdpManagerTester")
const EBTCToken = artifacts.require("EBTCToken")

contract('HintHelpers', async accounts => {
 
  const [owner] = accounts;

  const [bountyAddress, lpRewardsAddress, multisig] = accounts.slice(accounts.length - 3, accounts.length)

  let sortedCdps
  let cdpManager
  let borrowerOperations
  let hintHelpers
  let priceFeed

  let contracts

  let numAccounts;

  const getNetBorrowingAmount = async (debtWithFee) => th.getNetBorrowingAmount(contracts, debtWithFee)

  /* Open a Cdp for each account. EBTC debt is 200 EBTC each, with collateral beginning at
  1.5 ether, and rising by 0.01 ether per Cdp.  Hence, the ICR of account (i + 1) is always 1% greater than the ICR of account i. 
 */

 // Open Cdps in parallel, then withdraw EBTC in parallel
 const makeCdpsInParallel = async (accounts, n) => {
  activeAccounts = accounts.slice(0,n)
  // console.log(`number of accounts used is: ${activeAccounts.length}`)
  // console.time("makeCdpsInParallel")
  const openCdppromises = activeAccounts.map((account, index) => openCdp(account, index))
  await Promise.all(openCdppromises)
  const withdrawDebtpromises = activeAccounts.map(account => withdrawDebtfromCdp(account))
  await Promise.all(withdrawDebtpromises)
  // console.timeEnd("makeCdpsInParallel")
 }

 const openCdp = async (account, index) => {
   const amountFinney = 2000 + index * 10
   const coll = web3.utils.toWei((amountFinney.toString()), 'finney')
   await borrowerOperations.openCdp(0, account, account, { from: account, value: coll })
 }

 const withdrawDebtfromCdp = async (account) => {
  await borrowerOperations.withdrawDebt(th._100pct, '100000000000000000000', account, account, { from: account })
 }

 // Sequentially add coll and withdraw EBTC, 1 account at a time
  const makeCdpsInSequence = async (accounts, n) => {
    activeAccounts = accounts.slice(0,n)
    // console.log(`number of accounts used is: ${activeAccounts.length}`)

    let ICR = 200

    // console.time('makeCdpsInSequence')
    for (const account of activeAccounts) {
      const ICR_BN = toBN(ICR.toString().concat('0'.repeat(16)))
      await th.openCdp(contracts, { extraEBTCAmount: toBN(dec(1, 18)), ICR: ICR_BN, extraParams: { from: account } })

      ICR += 1
    }
    // console.timeEnd('makeCdpsInSequence')
  }

  before(async () => {
    contracts = await deploymentHelper.deployTesterContractsHardhat()
    let LQTYContracts = {}
    LQTYContracts.feeRecipient = contracts.feeRecipient;

    sortedCdps = contracts.sortedCdps
    cdpManager = contracts.cdpManager
    borrowerOperations = contracts.borrowerOperations
    hintHelpers = contracts.hintHelpers
    priceFeed = contracts.priceFeedTestnet
  
    await deploymentHelper.connectCoreContracts(contracts, LQTYContracts)

    numAccounts = 10

    await priceFeed.setPrice(dec(7428, 13))
    await makeCdpsInSequence(accounts, numAccounts) 
    // await makeCdpsInParallel(accounts, numAccounts)  
  })

  it("setup: makes accounts with nominal ICRs increasing by 1% consecutively", async () => {
    // check first 10 accounts
    const price = await priceFeed.getPrice()
    const ICR_0 = await cdpManager.getCachedICR(await sortedCdps.cdpOfOwnerByIndex(accounts[0],0), price)
    const ICR_1 = await cdpManager.getCachedICR(await sortedCdps.cdpOfOwnerByIndex(accounts[1],0), price)
    const ICR_2 = await cdpManager.getCachedICR(await sortedCdps.cdpOfOwnerByIndex(accounts[2],0), price)
    const ICR_3 = await cdpManager.getCachedICR(await sortedCdps.cdpOfOwnerByIndex(accounts[3],0), price)
    const ICR_4 = await cdpManager.getCachedICR(await sortedCdps.cdpOfOwnerByIndex(accounts[4],0), price)
    const ICR_5 = await cdpManager.getCachedICR(await sortedCdps.cdpOfOwnerByIndex(accounts[5],0), price)
    const ICR_6 = await cdpManager.getCachedICR(await sortedCdps.cdpOfOwnerByIndex(accounts[6],0), price)
    const ICR_7 = await cdpManager.getCachedICR(await sortedCdps.cdpOfOwnerByIndex(accounts[7],0), price)
    const ICR_8 = await cdpManager.getCachedICR(await sortedCdps.cdpOfOwnerByIndex(accounts[8],0), price)
    const ICR_9 = await cdpManager.getCachedICR(await sortedCdps.cdpOfOwnerByIndex(accounts[9],0), price)
    assert.isTrue(ICR_0.eq(toBN('1999999999999999999')))
    assert.isTrue(ICR_1.eq(toBN('2009999999999999999')))
    assert.isTrue(ICR_2.eq(toBN('2019999999999999999')))
    assert.isTrue(ICR_3.eq(toBN('2029999999999999999')))
    assert.isTrue(ICR_4.eq(toBN('2039999999999999999')))
    assert.isTrue(ICR_5.eq(toBN('2049999999999999999')))
    assert.isTrue(ICR_6.eq(toBN('2059999999999999999')))
    assert.isTrue(ICR_7.eq(toBN('2069999999999999999')))
    assert.isTrue(ICR_8.eq(toBN('2079999999999999999')))
    assert.isTrue(ICR_9.eq(toBN('2089999999999999999')))
  })

  it("getApproxHint(): returns the address of a Cdp within sqrt(length) positions of the correct insert position", async () => {
    const price = await priceFeed.getPrice()
    const sqrtLength = Math.ceil(Math.sqrt(numAccounts))

    /* As per the setup, the ICRs of Cdps are monotonic and seperated by 1% intervals. Therefore, the difference in ICR between 
    the given CR and the ICR of the hint address equals the number of positions between the hint address and the correct insert position 
    for a Cdp with the given CR. */

    // CR = 250%
    const CR_250 = '2500000000000000000'
    const CRPercent_250 = Number(web3.utils.fromWei(CR_250, 'ether')) * 100

    // const hintAddress_250 = await functionCaller.cdpManager_getApproxHint(CR_250, sqrtLength * 10)
    let _approxHints = await hintHelpers.getApproxHint(CR_250, sqrtLength * 10, latestRandomSeed)
	
    const ICR_hintAddress_250 = await cdpManager.getCachedICR(_approxHints[0], price)
    const ICRPercent_hintAddress_250 = Number(web3.utils.fromWei(ICR_hintAddress_250, 'ether')) * 100

    // check the hint position is at most sqrtLength positions away from the correct position
    ICR_Difference_250 = (ICRPercent_hintAddress_250 - CRPercent_250)
    assert.isBelow(ICR_Difference_250, sqrtLength)

    // CR = 287% 
    const CR_287 = '2870000000000000000'
    const CRPercent_287 = Number(web3.utils.fromWei(CR_287, 'ether')) * 100

    // const hintAddress_287 = await functionCaller.cdpManager_getApproxHint(CR_287, sqrtLength * 10)
    let _approxHints287 = await hintHelpers.getApproxHint(CR_287, sqrtLength * 10, latestRandomSeed)
    const ICR_hintAddress_287 = await cdpManager.getCachedICR(_approxHints287[0], price)
    const ICRPercent_hintAddress_287 = Number(web3.utils.fromWei(ICR_hintAddress_287, 'ether')) * 100
    
    // check the hint position is at most sqrtLength positions away from the correct position
    ICR_Difference_287 = (ICRPercent_hintAddress_287 - CRPercent_287)
    assert.isBelow(ICR_Difference_287, sqrtLength)

    // CR = 213%
    const CR_213 = '2130000000000000000'
    const CRPercent_213 = Number(web3.utils.fromWei(CR_213, 'ether')) * 100

    // const hintAddress_213 = await functionCaller.cdpManager_getApproxHint(CR_213, sqrtLength * 10)
    let _approxHints213 = await hintHelpers.getApproxHint(CR_213, sqrtLength * 10, latestRandomSeed)
    const ICR_hintAddress_213 = await cdpManager.getCachedICR(_approxHints213[0], price)
    const ICRPercent_hintAddress_213 = Number(web3.utils.fromWei(ICR_hintAddress_213, 'ether')) * 100
    
    // check the hint position is at most sqrtLength positions away from the correct position
    ICR_Difference_213 = (ICRPercent_hintAddress_213 - CRPercent_213)
    assert.isBelow(ICR_Difference_213, sqrtLength)

     // CR = 201%
     const CR_201 = '2010000000000000000'
     const CRPercent_201 = Number(web3.utils.fromWei(CR_201, 'ether')) * 100
 
    //  const hintAddress_201 = await functionCaller.cdpManager_getApproxHint(CR_201, sqrtLength * 10)
     let _approxHints201 = await hintHelpers.getApproxHint(CR_201, sqrtLength * 10, latestRandomSeed)
     const ICR_hintAddress_201 = await cdpManager.getCachedICR(_approxHints201[0], price)
     const ICRPercent_hintAddress_201 = Number(web3.utils.fromWei(ICR_hintAddress_201, 'ether')) * 100
     
     // check the hint position is at most sqrtLength positions away from the correct position
     ICR_Difference_201 = (ICRPercent_hintAddress_201 - CRPercent_201)
     assert.isBelow(ICR_Difference_201, sqrtLength)
  })

  /* Pass 100 random collateral ratios to getApproxHint(). For each, check whether the returned hint address is within 
  sqrt(length) positions of where a Cdp with that CR should be inserted. */
  // it("getApproxHint(): for 100 random CRs, returns the address of a Cdp within sqrt(length) positions of the correct insert position", async () => {
  //   const sqrtLength = Math.ceil(Math.sqrt(numAccounts))

  //   for (i = 0; i < 100; i++) {
  //     // get random ICR between 200% and (200 + numAccounts)%
  //     const min = 200
  //     const max = 200 + numAccounts
  //     const ICR_Percent = (Math.floor(Math.random() * (max - min) + min)) 

  //     // Convert ICR to a duint
  //     const ICR = web3.utils.toWei((ICR_Percent * 10).toString(), 'finney') 
  
  //     const hintAddress = await hintHelpers.getApproxHint(ICR, sqrtLength * 10)
  //     const ICR_hintAddress = await cdpManager.getCachedNominalICR(hintAddress)
  //     const ICRPercent_hintAddress = Number(web3.utils.fromWei(ICR_hintAddress, 'ether')) * 100
      
  //     // check the hint position is at most sqrtLength positions away from the correct position
  //     ICR_Difference = (ICRPercent_hintAddress - ICR_Percent)
  //     assert.isBelow(ICR_Difference, sqrtLength)
  //   }
  // })

  it("getApproxHint(): returns the head of the list if the CR is the max uint256 value", async () => {
    const sqrtLength = Math.ceil(Math.sqrt(numAccounts))

    // CR = Maximum value, i.e. 2**256 -1 
    const CR_Max = '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'

    // const hintAddress_Max = await functionCaller.cdpManager_getApproxHint(CR_Max, sqrtLength * 10)
    let _approxHints = await hintHelpers.getApproxHint(CR_Max, sqrtLength * 10, latestRandomSeed)

    const ICR_hintAddress_Max = await cdpManager.getCachedNominalICR(_approxHints[0])
    const ICRPercent_hintAddress_Max = Number(web3.utils.fromWei(ICR_hintAddress_Max, 'ether')) * 100

     const firstCdp = await sortedCdps.getFirst()
     const ICR_FirstCdp = await cdpManager.getCachedNominalICR(firstCdp)
     const ICRPercent_FirstCdp = Number(web3.utils.fromWei(ICR_FirstCdp, 'ether')) * 100
 
     // check the hint position is at most sqrtLength positions away from the correct position
     ICR_Difference_Max = (ICRPercent_hintAddress_Max - ICRPercent_FirstCdp)
     assert.isBelow(ICR_Difference_Max, sqrtLength)
  })

  it("getApproxHint(): returns the tail of the list if the CR is lower than ICR of any Cdp", async () => {
    const sqrtLength = Math.ceil(Math.sqrt(numAccounts))

     // CR = MCR
     const CR_Min = '1100000000000000000'

    //  const hintAddress_Min = await functionCaller.cdpManager_getApproxHint(CR_Min, sqrtLength * 10)
    let _approxHints = await hintHelpers.getApproxHint(CR_Min, sqrtLength * 10, latestRandomSeed)
    const ICR_hintAddress_Min = await cdpManager.getCachedNominalICR(_approxHints[0])
    const ICRPercent_hintAddress_Min = Number(web3.utils.fromWei(ICR_hintAddress_Min, 'ether')) * 100

     const lastCdp = await sortedCdps.getLast()
     const ICR_LastCdp = await cdpManager.getCachedNominalICR(lastCdp)
     const ICRPercent_LastCdp = Number(web3.utils.fromWei(ICR_LastCdp, 'ether')) * 100
 
     // check the hint position is at most sqrtLength positions away from the correct position
     const ICR_Difference_Min = (ICRPercent_hintAddress_Min - ICRPercent_LastCdp)
     assert.isBelow(ICR_Difference_Min, sqrtLength)
  })

  it('computeNominalCR()', async () => {
    const NICR = await hintHelpers.computeNominalCR(dec(3, 18), dec(200, 18))
    assert.equal(NICR.toString(), dec(150, 16))
  })

})

// Gas usage:  See gas costs spreadsheet. Cost per trial = 10k-ish.
