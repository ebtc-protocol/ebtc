
const { TestHelper: th } = require("../utils/testHelpers.js")
const dh = require("./deploymentHelpers.js")

// const [borrower, A, B, C] = (() => Array.from(Array(4), x => web3.eth.accounts.create().address))()

async function main() {
  const accounts = await web3.eth.getAccounts()
  const [borrower, A, B] = accounts

  const coreContracts = await dh.deployLiquityCoreHardhat()
  const ARBITRARY_ADDRESS = "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419" 
  const LQTYContracts = await dh.deployLQTYContractsHardhat(
      ARBITRARY_ADDRESS, 
      ARBITRARY_ADDRESS,
      ARBITRARY_ADDRESS
    )

 const { cdpManager, borrowerOperations, hintHelpers, sortedTroves, priceFeedTestnet } = coreContracts

  await dh.connectCoreContracts(coreContracts, LQTYContracts)
  await dh.connectLQTYContracts(LQTYContracts)
  await dh.connectLQTYContractsToCore(LQTYContracts, coreContracts)

  // Examples of off-chain hint calculation for Open Trove

  const toWei = web3.utils.toWei
  const toBN = web3.utils.toBN

  const price = toBN(toWei('2500'))
  await priceFeedTestnet.setPrice(toBN(toWei('2500')))

  const EBTCAmount = toBN(toWei('2500')) // borrower wants to withdraw 2500 EBTC
  const ETHColl = toBN(toWei('5')) // borrower wants to lock 5 ETH collateral

  // Call deployed TroveManager contract to read the liquidation reserve and latest borrowing fee
  const liquidationReserve = await cdpManager.EBTC_GAS_COMPENSATION()
  const expectedFee = await cdpManager.getBorrowingFeeWithDecay(EBTCAmount)
  
  // Total debt of the new cdp = EBTC amount drawn, plus fee, plus the liquidation reserve
  const expectedDebt = EBTCAmount.add(expectedFee).add(liquidationReserve)

  // Get the nominal NICR of the new cdp
  const _1e20 = toBN(toWei('100'))
  let NICR = ETHColl.mul(_1e20).div(expectedDebt)

  // Get an approximate address hint from the deployed HintHelper contract. Use (15 * number of cdps) trials 
  // to get an approx. hint that is close to the right position.
  let numTroves = await sortedTroves.getSize()
  let numTrials = numTroves.mul(toBN('15'))
  let { 0: approxHint } = await hintHelpers.getApproxHint(NICR, numTrials, 42)  // random seed of 42

  // Use the approximate hint to get the exact upper and lower hints from the deployed SortedTroves contract
  let { 0: upperHint, 1: lowerHint } = await sortedTroves.findInsertPosition(NICR, approxHint, approxHint)

  // Finally, call openTrove with the exact upperHint and lowerHint
  const maxFee = '5'.concat('0'.repeat(16)) // Slippage protection: 5%
  await borrowerOperations.openTrove(maxFee, EBTCAmount, upperHint, lowerHint, { value: ETHColl })

  // --- adjust cdp --- 

  const collIncrease = toBN(toWei('1'))  // borrower wants to add 1 ETH
  const EBTCRepayment = toBN(toWei('230')) // borrower wants to repay 230 EBTC

  // Get cdp's current debt and coll
  const {0: debt, 1: coll} = await cdpManager.getEntireDebtAndColl(borrower)
  
  const newDebt = debt.sub(EBTCRepayment)
  const newColl = coll.add(collIncrease)

  NICR = newColl.mul(_1e20).div(newDebt)

  // Get an approximate address hint from the deployed HintHelper contract. Use (15 * number of cdps) trials 
  // to get an approx. hint that is close to the right position.
  numTroves = await sortedTroves.getSize()
  numTrials = numTroves.mul(toBN('15'))
  ({0: approxHint} = await hintHelpers.getApproxHint(NICR, numTrials, 42))

  // Use the approximate hint to get the exact upper and lower hints from the deployed SortedTroves contract
  ({ 0: upperHint, 1: lowerHint } = await sortedTroves.findInsertPosition(NICR, approxHint, approxHint))

  // Call adjustTrove with the exact upperHint and lowerHint
  await borrowerOperations.adjustTrove(maxFee, 0, EBTCRepayment, false, upperHint, lowerHint, {value: collIncrease})


  // --- RedeemCollateral ---

  // Get the redemptions hints from the deployed HintHelpers contract
  const redemptionhint = await hintHelpers.getRedemptionHints(EBTCAmount, price, 50)

  const {0: firstRedemptionHint, 1: partialRedemptionNewICR, 2: truncatedEBTCAmount} = redemptionhint

  // Get the approximate partial redemption hint
  const {
    hintAddress: approxPartialRedemptionHint,
    latestRandomSeed
  } = await contracts.hintHelpers.getApproxHint(partialRedemptionNewICR, numTrials, 42)
  
  /* Use the approximate partial redemption hint to get the exact partial redemption hint from the 
  * deployed SortedTroves contract
  */
  const exactPartialRedemptionHint = (await sortedTroves.findInsertPosition(partialRedemptionNewICR,
    approxPartialRedemptionHint,
    approxPartialRedemptionHint))

  /* Finally, perform the on-chain redemption, passing the truncated EBTC amount, the correct hints, and the expected
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
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });

