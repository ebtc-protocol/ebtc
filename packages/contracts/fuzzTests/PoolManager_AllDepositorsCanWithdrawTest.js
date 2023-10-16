const deploymentHelper = require("../utils/deploymentHelpers.js")
const testHelpers = require("../utils/testHelpers.js")

const th = testHelpers.TestHelper
const dec = th.dec
const toBN = th.toBN

const ZERO_ADDRESS = th.ZERO_ADDRESS

const ZERO = toBN('0')

/*
* Naive fuzz test that checks whether all SP depositors can successfully withdraw from the SP, after a random sequence
* of deposits and liquidations.
*
* The test cases tackle different size ranges for liquidated collateral and SP deposits.
*/

contract("PoolManager - random liquidations/deposits, then check all depositors can withdraw", async accounts => {

  const whale = accounts[accounts.length - 1]
  const bountyAddress = accounts[998]
  const lpRewardsAddress = accounts[999]

  let priceFeed
  let ebtcToken
  let cdpManager
  let stabilityPool
  let sortedCdps
  let borrowerOperations

  const skyrocketPriceAndCheckAllCdpsSafe = async () => {
        // price skyrockets, therefore no undercollateralized troes
        await priceFeed.setPrice(dec(1000, 18));
        const lowestICR = await cdpManager.getCachedICR(await sortedCdps.getLast(), dec(1000, 18))
        assert.isTrue(lowestICR.gt(toBN(dec(110, 16))))
  }

  const performLiquidation = async (remainingDefaulters, liquidatedAccountsDict) => {
    if (remainingDefaulters.length === 0) { return }

    const randomDefaulterIndex = Math.floor(Math.random() * (remainingDefaulters.length))
    const randomDefaulter = remainingDefaulters[randomDefaulterIndex]

    const liquidatedEBTC = (await cdpManager.Cdps(randomDefaulter))[0]
    const liquidatedETH = (await cdpManager.Cdps(randomDefaulter))[1]

    const price = await priceFeed.getPrice()
    const ICR = (await cdpManager.getCachedICR(randomDefaulter, price)).toString()
    const ICRPercent = ICR.slice(0, ICR.length - 16)

    console.log(`SP address: ${stabilityPool.address}`)
    const EBTCinPoolBefore = await stabilityPool.getTotalEBTCDeposits()
    const liquidatedTx = await cdpManager.liquidate(randomDefaulter, { from: accounts[0] })
    const EBTCinPoolAfter = await stabilityPool.getTotalEBTCDeposits()

    assert.isTrue(liquidatedTx.receipt.status)

    if (liquidatedTx.receipt.status) {
      liquidatedAccountsDict[randomDefaulter] = true
      remainingDefaulters.splice(randomDefaulterIndex, 1)
    }
    if (await cdpManager.checkRecoveryMode(price)) { console.log("recovery mode: TRUE") }

    console.log(`Liquidation. addr: ${th.squeezeAddr(randomDefaulter)} ICR: ${ICRPercent}% coll: ${liquidatedETH} debt: ${liquidatedEBTC} SP EBTC before: ${EBTCinPoolBefore} SP EBTC after: ${EBTCinPoolAfter} tx success: ${liquidatedTx.receipt.status}`)
  }

  const performSPDeposit = async (depositorAccounts, currentDepositors, currentDepositorsDict) => {
    const randomIndex = Math.floor(Math.random() * (depositorAccounts.length))
    const randomDepositor = depositorAccounts[randomIndex]

    const userBalance = (await ebtcToken.balanceOf(randomDepositor))
    const maxEBTCDeposit = userBalance.div(toBN(dec(1, 18)))

    const randomEBTCAmount = th.randAmountInWei(1, maxEBTCDeposit)

    const depositTx = await stabilityPool.provideToSP(randomEBTCAmount, ZERO_ADDRESS, { from: randomDepositor })

    assert.isTrue(depositTx.receipt.status)

    if (depositTx.receipt.status && !currentDepositorsDict[randomDepositor]) {
      currentDepositorsDict[randomDepositor] = true
      currentDepositors.push(randomDepositor)
    }

    console.log(`SP deposit. addr: ${th.squeezeAddr(randomDepositor)} amount: ${randomEBTCAmount} tx success: ${depositTx.receipt.status} `)
  }

  const randomOperation = async (depositorAccounts,
    remainingDefaulters,
    currentDepositors,
    liquidatedAccountsDict,
    currentDepositorsDict,
  ) => {
    const randomSelection = Math.floor(Math.random() * 2)

    if (randomSelection === 0) {
      await performLiquidation(remainingDefaulters, liquidatedAccountsDict)

    } else if (randomSelection === 1) {
      await performSPDeposit(depositorAccounts, currentDepositors, currentDepositorsDict)
    }
  }

  const systemContainsCdpUnder110 = async (price) => {
    const lowestICR = await cdpManager.getCachedICR(await sortedCdps.getLast(), price)
    console.log(`lowestICR: ${lowestICR}, lowestICR.lt(dec(110, 16)): ${lowestICR.lt(toBN(dec(110, 16)))}`)
    return lowestICR.lt(dec(110, 16))
  }

  const systemContainsCdpUnder100 = async (price) => {
    const lowestICR = await cdpManager.getCachedICR(await sortedCdps.getLast(), price)
    console.log(`lowestICR: ${lowestICR}, lowestICR.lt(dec(100, 16)): ${lowestICR.lt(toBN(dec(100, 16)))}`)
    return lowestICR.lt(dec(100, 16))
  }

  const getTotalDebtFromUndercollateralizedCdps = async (n, price) => {
    let totalDebt = ZERO
    let cdp = await sortedCdps.getLast()

    for (let i = 0; i < n; i++) {
      const ICR = await cdpManager.getCachedICR(cdp, price)
      const debt = ICR.lt(toBN(dec(110, 16))) ? (await cdpManager.getSyncedDebtAndCollShares(cdp))[0] : ZERO

      totalDebt = totalDebt.add(debt)
      cdp = await sortedCdps.getPrev(cdp)
    }

    return totalDebt
  }

  const clearAllUndercollateralizedCdps = async (price) => {
    /* Somewhat arbitrary way to clear under-collateralized cdps: 
    *
    * - If system is in Recovery Mode and contains cdps with ICR < 100, whale draws the lowest cdp's debt amount 
    * and sends to lowest cdp owner, who then closes their cdp.
    *
    * - If system contains cdps with ICR < 110, whale simply draws and makes an SP deposit 
    * equal to the debt of the last 50 cdps, before a liquidateCdps tx hits the last 50 cdps.
    *
    * The intent is to avoid the system entering an endless loop where the SP is empty and debt is being forever liquidated/recycled 
    * between active cdps, and the existence of some under-collateralized cdps blocks all SP depositors from withdrawing.
    * 
    * Since the purpose of the fuzz test is to see if SP depositors can indeed withdraw *when they should be able to*,
    * we first need to put the system in a state with no under-collateralized cdps (which are supposed to block SP withdrawals).
    */
    while(await systemContainsCdpUnder100(price) && await cdpManager.checkRecoveryMode()) {
      const lowestCdp = await sortedCdps.getLast()
      const lastCdpDebt = (await cdpManager.getSyncedDebtAndCollShares(cdp))[0]
      await borrowerOperations.adjustCdp(0, lastCdpDebt, true, whale, {from: whale})
      await ebtcToken.transfer(lowestCdp, lowestCdpDebt, {from: whale})
      await borrowerOperations.closeCdp({from: lowestCdp})
    }

    while (await systemContainsCdpUnder110(price)) {
      const debtLowest50Cdps = await getTotalDebtFromUndercollateralizedCdps(50, price)
      
      if (debtLowest50Cdps.gt(ZERO)) {
        await borrowerOperations.adjustCdp(0, debtLowest50Cdps, true, whale, {from: whale})
        await stabilityPool.provideToSP(debtLowest50Cdps, {from: whale})
      }
      
      await cdpManager.liquidateCdps(50)
    }
  }

  const attemptWithdrawAllDeposits = async (currentDepositors) => {
    // First, liquidate all remaining undercollateralized cdps, so that SP depositors may withdraw

    console.log("\n")
    console.log("--- Attempt to withdraw all deposits ---")
    console.log(`Depositors count: ${currentDepositors.length}`)

    for (depositor of currentDepositors) {
      const initialDeposit = (await stabilityPool.deposits(depositor))[0]
      const finalDeposit = await stabilityPool.getCompoundedEBTCDeposit(depositor)
      const ETHGain = await stabilityPool.getDepositorETHGain(depositor)
      const ETHinSP = (await stabilityPool.getSystemCollShares()).toString()
      const EBTCinSP = (await stabilityPool.getTotalEBTCDeposits()).toString()

      // Attempt to withdraw
      const withdrawalTx = await stabilityPool.withdrawFromSP(dec(1, 36), { from: depositor })

      const ETHinSPAfter = (await stabilityPool.getSystemCollShares()).toString()
      const EBTCinSPAfter = (await stabilityPool.getTotalEBTCDeposits()).toString()
      const EBTCBalanceSPAfter = (await ebtcToken.balanceOf(stabilityPool.address))
      const depositAfter = await stabilityPool.getCompoundedEBTCDeposit(depositor)

      console.log(`--Before withdrawal--
                    withdrawer addr: ${th.squeezeAddr(depositor)}
                     initial deposit: ${initialDeposit}
                     ETH gain: ${ETHGain}
                     ETH in SP: ${ETHinSP}
                     compounded deposit: ${finalDeposit} 
                     EBTC in SP: ${EBTCinSP}
                    
                    --After withdrawal--
                     Withdrawal tx success: ${withdrawalTx.receipt.status} 
                     Deposit after: ${depositAfter}
                     ETH remaining in SP: ${ETHinSPAfter}
                     SP EBTC deposits tracker after: ${EBTCinSPAfter}
                     SP EBTC balance after: ${EBTCBalanceSPAfter}
                     `)
      // Check each deposit can be withdrawn
      assert.isTrue(withdrawalTx.receipt.status)
      assert.equal(depositAfter, '0')
    }
  }

  describe("Stability Pool Withdrawals", async () => {

    before(async () => {
      console.log(`Number of accounts: ${accounts.length}`)
    })

    beforeEach(async () => {
      contracts = await deploymentHelper.deployLiquityCore()
      const LQTYContracts = await deploymentHelper.deployLQTYContracts(bountyAddress, lpRewardsAddress)

      stabilityPool = contracts.stabilityPool
      priceFeed = contracts.priceFeedTestnet
      ebtcToken = contracts.ebtcToken
      stabilityPool = contracts.stabilityPool
      cdpManager = contracts.cdpManager
      borrowerOperations = contracts.borrowerOperations
      sortedCdps = contracts.sortedCdps

      await deploymentHelper.connectLQTYContracts(LQTYContracts)
      await deploymentHelper.connectCoreContracts(contracts, LQTYContracts)
      await deploymentHelper.connectLQTYContractsToCore(LQTYContracts, contracts)
    })

    // mixed deposits/liquidations

    // ranges: low-low, low-high, high-low, high-high, full-full

    // full offsets, partial offsets
    // ensure full offset with whale2 in S
    // ensure partial offset with whale 3 in L

    it("Defaulters' Collateral in range [1, 1e8]. SP Deposits in range [100, 1e10]. ETH:USD = 100", async () => {
      // whale adds coll that holds TCR > 150%
      await borrowerOperations.openCdp(0, 0, whale, whale, { from: whale, value: dec(5, 29) })

      const numberOfOps = 5
      const defaulterAccounts = accounts.slice(1, numberOfOps)
      const depositorAccounts = accounts.slice(numberOfOps + 1, numberOfOps * 2)

      const defaulterCollMin = 1
      const defaulterCollMax = 100000000
      const defaulterEBTCProportionMin = 91
      const defaulterEBTCProportionMax = 180

      const depositorCollMin = 1
      const depositorCollMax = 100000000
      const depositorEBTCProportionMin = 100
      const depositorEBTCProportionMax = 100

      const remainingDefaulters = [...defaulterAccounts]
      const currentDepositors = []
      const liquidatedAccountsDict = {}
      const currentDepositorsDict = {}

      // setup:
      // account set L all add coll and withdraw EBTC
      await th.openCdp_allAccounts_randomETH_randomEBTC(defaulterCollMin,
        defaulterCollMax,
        defaulterAccounts,
        contracts,
        defaulterEBTCProportionMin,
        defaulterEBTCProportionMax,
        true)

      // account set S all add coll and withdraw EBTC
      await th.openCdp_allAccounts_randomETH_randomEBTC(depositorCollMin,
        depositorCollMax,
        depositorAccounts,
        contracts,
        depositorEBTCProportionMin,
        depositorEBTCProportionMax,
        true)

      // price drops, all L liquidateable
      await priceFeed.setPrice(dec(1, 18));

      // Random sequence of operations: liquidations and SP deposits
      for (i = 0; i < numberOfOps; i++) {
        await randomOperation(depositorAccounts,
          remainingDefaulters,
          currentDepositors,
          liquidatedAccountsDict,
          currentDepositorsDict)
      }

      await skyrocketPriceAndCheckAllCdpsSafe()

      const totalEBTCDepositsBeforeWithdrawals = await stabilityPool.getTotalEBTCDeposits()
      const totalETHRewardsBeforeWithdrawals = await stabilityPool.getSystemCollShares()

      await attemptWithdrawAllDeposits(currentDepositors)

      const totalEBTCDepositsAfterWithdrawals = await stabilityPool.getTotalEBTCDeposits()
      const totalETHRewardsAfterWithdrawals = await stabilityPool.getSystemCollShares()

      console.log(`Total EBTC deposits before any withdrawals: ${totalEBTCDepositsBeforeWithdrawals}`)
      console.log(`Total ETH rewards before any withdrawals: ${totalETHRewardsBeforeWithdrawals}`)

      console.log(`Remaining EBTC deposits after withdrawals: ${totalEBTCDepositsAfterWithdrawals}`)
      console.log(`Remaining ETH rewards after withdrawals: ${totalETHRewardsAfterWithdrawals}`)

      console.log(`current depositors length: ${currentDepositors.length}`)
      console.log(`remaining defaulters length: ${remainingDefaulters.length}`)
    })

    it("Defaulters' Collateral in range [1, 10]. SP Deposits in range [1e8, 1e10]. ETH:USD = 100", async () => {
      // whale adds coll that holds TCR > 150%
      await borrowerOperations.openCdp(0, 0, whale, whale, { from: whale, value: dec(5, 29) })

      const numberOfOps = 5
      const defaulterAccounts = accounts.slice(1, numberOfOps)
      const depositorAccounts = accounts.slice(numberOfOps + 1, numberOfOps * 2)

      const defaulterCollMin = 1
      const defaulterCollMax = 10
      const defaulterEBTCProportionMin = 91
      const defaulterEBTCProportionMax = 180

      const depositorCollMin = 1000000
      const depositorCollMax = 100000000
      const depositorEBTCProportionMin = 100
      const depositorEBTCProportionMax = 100

      const remainingDefaulters = [...defaulterAccounts]
      const currentDepositors = []
      const liquidatedAccountsDict = {}
      const currentDepositorsDict = {}

      // setup:
      // account set L all add coll and withdraw EBTC
      await th.openCdp_allAccounts_randomETH_randomEBTC(defaulterCollMin,
        defaulterCollMax,
        defaulterAccounts,
        contracts,
        defaulterEBTCProportionMin,
        defaulterEBTCProportionMax)

      // account set S all add coll and withdraw EBTC
      await th.openCdp_allAccounts_randomETH_randomEBTC(depositorCollMin,
        depositorCollMax,
        depositorAccounts,
        contracts,
        depositorEBTCProportionMin,
        depositorEBTCProportionMax)

      // price drops, all L liquidateable
      await priceFeed.setPrice(dec(100, 18));

      // Random sequence of operations: liquidations and SP deposits
      for (i = 0; i < numberOfOps; i++) {
        await randomOperation(depositorAccounts,
          remainingDefaulters,
          currentDepositors,
          liquidatedAccountsDict,
          currentDepositorsDict)
      }

      await skyrocketPriceAndCheckAllCdpsSafe()

      const totalEBTCDepositsBeforeWithdrawals = await stabilityPool.getTotalEBTCDeposits()
      const totalETHRewardsBeforeWithdrawals = await stabilityPool.getSystemCollShares()

      await attemptWithdrawAllDeposits(currentDepositors)

      const totalEBTCDepositsAfterWithdrawals = await stabilityPool.getTotalEBTCDeposits()
      const totalETHRewardsAfterWithdrawals = await stabilityPool.getSystemCollShares()

      console.log(`Total EBTC deposits before any withdrawals: ${totalEBTCDepositsBeforeWithdrawals}`)
      console.log(`Total ETH rewards before any withdrawals: ${totalETHRewardsBeforeWithdrawals}`)

      console.log(`Remaining EBTC deposits after withdrawals: ${totalEBTCDepositsAfterWithdrawals}`)
      console.log(`Remaining ETH rewards after withdrawals: ${totalETHRewardsAfterWithdrawals}`)

      console.log(`current depositors length: ${currentDepositors.length}`)
      console.log(`remaining defaulters length: ${remainingDefaulters.length}`)
    })

    it("Defaulters' Collateral in range [1e6, 1e8]. SP Deposits in range [100, 1000]. Every liquidation empties the Pool. ETH:USD = 100", async () => {
      // whale adds coll that holds TCR > 150%
      await borrowerOperations.openCdp(0, 0, whale, whale, { from: whale, value: dec(5, 29) })

      const numberOfOps = 5
      const defaulterAccounts = accounts.slice(1, numberOfOps)
      const depositorAccounts = accounts.slice(numberOfOps + 1, numberOfOps * 2)

      const defaulterCollMin = 1000000
      const defaulterCollMax = 100000000
      const defaulterEBTCProportionMin = 91
      const defaulterEBTCProportionMax = 180

      const depositorCollMin = 1
      const depositorCollMax = 10
      const depositorEBTCProportionMin = 100
      const depositorEBTCProportionMax = 100

      const remainingDefaulters = [...defaulterAccounts]
      const currentDepositors = []
      const liquidatedAccountsDict = {}
      const currentDepositorsDict = {}

      // setup:
      // account set L all add coll and withdraw EBTC
      await th.openCdp_allAccounts_randomETH_randomEBTC(defaulterCollMin,
        defaulterCollMax,
        defaulterAccounts,
        contracts,
        defaulterEBTCProportionMin,
        defaulterEBTCProportionMax)

      // account set S all add coll and withdraw EBTC
      await th.openCdp_allAccounts_randomETH_randomEBTC(depositorCollMin,
        depositorCollMax,
        depositorAccounts,
        contracts,
        depositorEBTCProportionMin,
        depositorEBTCProportionMax)

      // price drops, all L liquidateable
      await priceFeed.setPrice(dec(100, 18));

      // Random sequence of operations: liquidations and SP deposits
      for (i = 0; i < numberOfOps; i++) {
        await randomOperation(depositorAccounts,
          remainingDefaulters,
          currentDepositors,
          liquidatedAccountsDict,
          currentDepositorsDict)
      }

      await skyrocketPriceAndCheckAllCdpsSafe()

      const totalEBTCDepositsBeforeWithdrawals = await stabilityPool.getTotalEBTCDeposits()
      const totalETHRewardsBeforeWithdrawals = await stabilityPool.getSystemCollShares()

      await attemptWithdrawAllDeposits(currentDepositors)

      const totalEBTCDepositsAfterWithdrawals = await stabilityPool.getTotalEBTCDeposits()
      const totalETHRewardsAfterWithdrawals = await stabilityPool.getSystemCollShares()

      console.log(`Total EBTC deposits before any withdrawals: ${totalEBTCDepositsBeforeWithdrawals}`)
      console.log(`Total ETH rewards before any withdrawals: ${totalETHRewardsBeforeWithdrawals}`)

      console.log(`Remaining EBTC deposits after withdrawals: ${totalEBTCDepositsAfterWithdrawals}`)
      console.log(`Remaining ETH rewards after withdrawals: ${totalETHRewardsAfterWithdrawals}`)

      console.log(`current depositors length: ${currentDepositors.length}`)
      console.log(`remaining defaulters length: ${remainingDefaulters.length}`)
    })

    it("Defaulters' Collateral in range [1e6, 1e8]. SP Deposits in range [1e8 1e10]. ETH:USD = 100", async () => {
      // whale adds coll that holds TCR > 150%
      await borrowerOperations.openCdp(0, 0, whale, whale, { from: whale, value: dec(5, 29) })

      // price drops, all L liquidateable
      const numberOfOps = 5
      const defaulterAccounts = accounts.slice(1, numberOfOps)
      const depositorAccounts = accounts.slice(numberOfOps + 1, numberOfOps * 2)

      const defaulterCollMin = 1000000
      const defaulterCollMax = 100000000
      const defaulterEBTCProportionMin = 91
      const defaulterEBTCProportionMax = 180

      const depositorCollMin = 1000000
      const depositorCollMax = 100000000
      const depositorEBTCProportionMin = 100
      const depositorEBTCProportionMax = 100

      const remainingDefaulters = [...defaulterAccounts]
      const currentDepositors = []
      const liquidatedAccountsDict = {}
      const currentDepositorsDict = {}

      // setup:
      // account set L all add coll and withdraw EBTC
      await th.openCdp_allAccounts_randomETH_randomEBTC(defaulterCollMin,
        defaulterCollMax,
        defaulterAccounts,
        contracts,
        defaulterEBTCProportionMin,
        defaulterEBTCProportionMax)

      // account set S all add coll and withdraw EBTC
      await th.openCdp_allAccounts_randomETH_randomEBTC(depositorCollMin,
        depositorCollMax,
        depositorAccounts,
        contracts,
        depositorEBTCProportionMin,
        depositorEBTCProportionMax)

      // price drops, all L liquidateable
      await priceFeed.setPrice(dec(100, 18));

      // Random sequence of operations: liquidations and SP deposits
      for (i = 0; i < numberOfOps; i++) {
        await randomOperation(depositorAccounts,
          remainingDefaulters,
          currentDepositors,
          liquidatedAccountsDict,
          currentDepositorsDict)
      }

      await skyrocketPriceAndCheckAllCdpsSafe()

      const totalEBTCDepositsBeforeWithdrawals = await stabilityPool.getTotalEBTCDeposits()
      const totalETHRewardsBeforeWithdrawals = await stabilityPool.getSystemCollShares()

      await attemptWithdrawAllDeposits(currentDepositors)

      const totalEBTCDepositsAfterWithdrawals = await stabilityPool.getTotalEBTCDeposits()
      const totalETHRewardsAfterWithdrawals = await stabilityPool.getSystemCollShares()

      console.log(`Total EBTC deposits before any withdrawals: ${totalEBTCDepositsBeforeWithdrawals}`)
      console.log(`Total ETH rewards before any withdrawals: ${totalETHRewardsBeforeWithdrawals}`)

      console.log(`Remaining EBTC deposits after withdrawals: ${totalEBTCDepositsAfterWithdrawals}`)
      console.log(`Remaining ETH rewards after withdrawals: ${totalETHRewardsAfterWithdrawals}`)

      console.log(`current depositors length: ${currentDepositors.length}`)
      console.log(`remaining defaulters length: ${remainingDefaulters.length}`)
    })
  })
})
