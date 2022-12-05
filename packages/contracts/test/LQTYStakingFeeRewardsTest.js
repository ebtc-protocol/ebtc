const Decimal = require("decimal.js");
const deploymentHelper = require("../utils/deploymentHelpers.js")
const { BNConverter } = require("../utils/BNConverter.js")
const testHelpers = require("../utils/testHelpers.js")

const LQTYStakingTester = artifacts.require('LQTYStakingTester')
const TroveManagerTester = artifacts.require("TroveManagerTester")
const NonPayable = artifacts.require("./NonPayable.sol")

const th = testHelpers.TestHelper
const timeValues = testHelpers.TimeValues
const dec = th.dec
const assertRevert = th.assertRevert

const toBN = th.toBN
const ZERO = th.toBN('0')

const GAS_PRICE = 10000000

/* NOTE: These tests do not test for specific ETH and EBTC gain values. They only test that the 
 * gains are non-zero, occur when they should, and are in correct proportion to the user's stake. 
 *
 * Specific ETH/EBTC gain values will depend on the final fee schedule used, and the final choices for
 * parameters BETA and MINUTE_DECAY_FACTOR in the TroveManager, which are still TBD based on economic
 * modelling.
 * 
 */ 

contract('LQTYStaking revenue share tests', async accounts => {

  const [bountyAddress, lpRewardsAddress, multisig] = accounts.slice(accounts.length - 3, accounts.length)
  
  const [owner, A, B, C, D, E, F, G, whale] = accounts;

  let priceFeed
  let ebtcToken
  let sortedTroves
  let cdpManager
  let activePool
  let stabilityPool
  let defaultPool
  let borrowerOperations
  let lqtyStaking
  let lqtyToken

  let contracts

  const openTrove = async (params) => th.openTrove(contracts, params)

  beforeEach(async () => {
    contracts = await deploymentHelper.deployLiquityCore()
    contracts.cdpManager = await TroveManagerTester.new()
    contracts = await deploymentHelper.deployEBTCTokenTester(contracts)
    const LQTYContracts = await deploymentHelper.deployLQTYTesterContractsHardhat(bountyAddress, lpRewardsAddress, multisig)
    
    await deploymentHelper.connectLQTYContracts(LQTYContracts)
    await deploymentHelper.connectCoreContracts(contracts, LQTYContracts)
    await deploymentHelper.connectLQTYContractsToCore(LQTYContracts, contracts)

    nonPayable = await NonPayable.new() 
    priceFeed = contracts.priceFeedTestnet
    ebtcToken = contracts.ebtcToken
    sortedTroves = contracts.sortedTroves
    cdpManager = contracts.cdpManager
    activePool = contracts.activePool
    stabilityPool = contracts.stabilityPool
    defaultPool = contracts.defaultPool
    borrowerOperations = contracts.borrowerOperations
    hintHelpers = contracts.hintHelpers

    lqtyToken = LQTYContracts.lqtyToken
    lqtyStaking = LQTYContracts.lqtyStaking
  })

  it('stake(): reverts if amount is zero', async () => {
    // FF time one year so owner can transfer LQTY
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_YEAR, web3.currentProvider)

    // multisig transfers LQTY to staker A
    await lqtyToken.transfer(A, dec(100, 18), {from: multisig})

    // console.log(`A lqty bal: ${await lqtyToken.balanceOf(A)}`)

    // A makes stake
    await lqtyToken.approve(lqtyStaking.address, dec(100, 18), {from: A})
    await assertRevert(lqtyStaking.stake(0, {from: A}), "LQTYStaking: Amount must be non-zero")
  })

  it("ETH fee per LQTY staked increases when a redemption fee is triggered and totalStakes > 0", async () => {
    await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
    await openTrove({ extraEBTCAmount: toBN(dec(20000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
    await openTrove({ extraEBTCAmount: toBN(dec(30000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
    await openTrove({ extraEBTCAmount: toBN(dec(40000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })

    // FF time one year so owner can transfer LQTY
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_YEAR, web3.currentProvider)

    // multisig transfers LQTY to staker A
    await lqtyToken.transfer(A, dec(100, 18), {from: multisig, gasPrice: GAS_PRICE})

    // console.log(`A lqty bal: ${await lqtyToken.balanceOf(A)}`)

    // A makes stake
    await lqtyToken.approve(lqtyStaking.address, dec(100, 18), {from: A})
    await lqtyStaking.stake(dec(100, 18), {from: A})

    // Check ETH fee per unit staked is zero
    const F_ETH_Before = await lqtyStaking.F_ETH()
    assert.equal(F_ETH_Before, '0')

    const B_BalBeforeREdemption = await ebtcToken.balanceOf(B)
    // B redeems
    const redemptionTx = await th.redeemCollateralAndGetTxObject(B, contracts, dec(100, 18), GAS_PRICE)
    
    const B_BalAfterRedemption = await ebtcToken.balanceOf(B)
    assert.isTrue(B_BalAfterRedemption.lt(B_BalBeforeREdemption))

    // check ETH fee emitted in event is non-zero
    const emittedETHFee = toBN((await th.getEmittedRedemptionValues(redemptionTx))[3])
    assert.isTrue(emittedETHFee.gt(toBN('0')))

    // Check ETH fee per unit staked has increased by correct amount
    const F_ETH_After = await lqtyStaking.F_ETH()

    // Expect fee per unit staked = fee/100, since there is 100 EBTC totalStaked
    const expected_F_ETH_After = emittedETHFee.div(toBN('100')) 

    assert.isTrue(expected_F_ETH_After.eq(F_ETH_After))
  })

  it("ETH fee per LQTY staked doesn't change when a redemption fee is triggered and totalStakes == 0", async () => {
    await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
    await openTrove({ extraEBTCAmount: toBN(dec(20000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
    await openTrove({ extraEBTCAmount: toBN(dec(30000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
    await openTrove({ extraEBTCAmount: toBN(dec(40000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })
    await openTrove({ extraEBTCAmount: toBN(dec(50000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

    // FF time one year so owner can transfer LQTY
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_YEAR, web3.currentProvider)

    // multisig transfers LQTY to staker A
    await lqtyToken.transfer(A, dec(100, 18), {from: multisig, gasPrice: GAS_PRICE})

    // Check ETH fee per unit staked is zero
    const F_ETH_Before = await lqtyStaking.F_ETH()
    assert.equal(F_ETH_Before, '0')

    const B_BalBeforeREdemption = await ebtcToken.balanceOf(B)
    // B redeems
    const redemptionTx = await th.redeemCollateralAndGetTxObject(B, contracts, dec(100, 18), GAS_PRICE)
    
    const B_BalAfterRedemption = await ebtcToken.balanceOf(B)
    assert.isTrue(B_BalAfterRedemption.lt(B_BalBeforeREdemption))

    // check ETH fee emitted in event is non-zero
    const emittedETHFee = toBN((await th.getEmittedRedemptionValues(redemptionTx))[3])
    assert.isTrue(emittedETHFee.gt(toBN('0')))

    // Check ETH fee per unit staked has not increased 
    const F_ETH_After = await lqtyStaking.F_ETH()
    assert.equal(F_ETH_After, '0')
  })

  it("EBTC fee per LQTY staked increases when a redemption fee is triggered and totalStakes > 0", async () => {
    await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
    await openTrove({ extraEBTCAmount: toBN(dec(20000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
    await openTrove({ extraEBTCAmount: toBN(dec(30000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
    await openTrove({ extraEBTCAmount: toBN(dec(40000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })
    await openTrove({ extraEBTCAmount: toBN(dec(50000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })
    let _dTroveId = await sortedTroves.cdpOfOwnerByIndex(D, 0);

    // FF time one year so owner can transfer LQTY
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_YEAR, web3.currentProvider)

    // multisig transfers LQTY to staker A
    await lqtyToken.transfer(A, dec(100, 18), {from: multisig})

    // A makes stake
    await lqtyToken.approve(lqtyStaking.address, dec(100, 18), {from: A})
    await lqtyStaking.stake(dec(100, 18), {from: A})

    // Check EBTC fee per unit staked is zero
    const F_EBTC_Before = await lqtyStaking.F_ETH()
    assert.equal(F_EBTC_Before, '0')

    const B_BalBeforeREdemption = await ebtcToken.balanceOf(B)
    // B redeems
    const redemptionTx = await th.redeemCollateralAndGetTxObject(B, contracts, dec(100, 18), gasPrice= GAS_PRICE)
    
    const B_BalAfterRedemption = await ebtcToken.balanceOf(B)
    assert.isTrue(B_BalAfterRedemption.lt(B_BalBeforeREdemption))

    // Check base rate is now non-zero
    const baseRate = await cdpManager.baseRate()
    assert.isTrue(baseRate.gt(toBN('0')))

    // D draws debt
    const tx = await borrowerOperations.withdrawEBTC(_dTroveId, th._100pct, dec(27, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, {from: D})
    
    // Check EBTC fee value in event is non-zero
    const emittedEBTCFee = toBN(th.getEBTCFeeFromEBTCBorrowingEvent(tx))
    assert.isTrue(emittedEBTCFee.gt(toBN('0')))
    
    // Check EBTC fee per unit staked has increased by correct amount
    const F_EBTC_After = await lqtyStaking.F_EBTC()

    // Expect fee per unit staked = fee/100, since there is 100 EBTC totalStaked
    const expected_F_EBTC_After = emittedEBTCFee.div(toBN('100')) 

    assert.isTrue(expected_F_EBTC_After.eq(F_EBTC_After))
  })

  it("EBTC fee per LQTY staked doesn't change when a redemption fee is triggered and totalStakes == 0", async () => {
    await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
    await openTrove({ extraEBTCAmount: toBN(dec(20000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
    await openTrove({ extraEBTCAmount: toBN(dec(30000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
    await openTrove({ extraEBTCAmount: toBN(dec(40000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })
    await openTrove({ extraEBTCAmount: toBN(dec(50000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })
    let _dTroveId = await sortedTroves.cdpOfOwnerByIndex(D, 0);

    // FF time one year so owner can transfer LQTY
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_YEAR, web3.currentProvider)

    // multisig transfers LQTY to staker A
    await lqtyToken.transfer(A, dec(100, 18), {from: multisig})

    // Check EBTC fee per unit staked is zero
    const F_EBTC_Before = await lqtyStaking.F_ETH()
    assert.equal(F_EBTC_Before, '0')

    const B_BalBeforeREdemption = await ebtcToken.balanceOf(B)
    // B redeems
    const redemptionTx = await th.redeemCollateralAndGetTxObject(B, contracts, dec(100, 18), gasPrice = GAS_PRICE)
    
    const B_BalAfterRedemption = await ebtcToken.balanceOf(B)
    assert.isTrue(B_BalAfterRedemption.lt(B_BalBeforeREdemption))

    // Check base rate is now non-zero
    const baseRate = await cdpManager.baseRate()
    assert.isTrue(baseRate.gt(toBN('0')))

    // D draws debt
    const tx = await borrowerOperations.withdrawEBTC(_dTroveId, th._100pct, dec(27, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, {from: D})
    
    // Check EBTC fee value in event is non-zero
    const emittedEBTCFee = toBN(th.getEBTCFeeFromEBTCBorrowingEvent(tx))
    assert.isTrue(emittedEBTCFee.gt(toBN('0')))
    
    // Check EBTC fee per unit staked did not increase, is still zero
    const F_EBTC_After = await lqtyStaking.F_EBTC()
    assert.equal(F_EBTC_After, '0')
  })

  it("LQTY Staking: A single staker earns all ETH and LQTY fees that occur", async () => {
    await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
    await openTrove({ extraEBTCAmount: toBN(dec(20000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
    await openTrove({ extraEBTCAmount: toBN(dec(30000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
    let _bTroveId = await sortedTroves.cdpOfOwnerByIndex(B, 0);
    await openTrove({ extraEBTCAmount: toBN(dec(40000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })
    await openTrove({ extraEBTCAmount: toBN(dec(50000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })
    let _dTroveId = await sortedTroves.cdpOfOwnerByIndex(D, 0);

    // FF time one year so owner can transfer LQTY
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_YEAR, web3.currentProvider)

    // multisig transfers LQTY to staker A
    await lqtyToken.transfer(A, dec(100, 18), {from: multisig})

    // A makes stake
    await lqtyToken.approve(lqtyStaking.address, dec(100, 18), {from: A})
    await lqtyStaking.stake(dec(100, 18), {from: A})

    const B_BalBeforeREdemption = await ebtcToken.balanceOf(B)
    // B redeems
    const redemptionTx_1 = await th.redeemCollateralAndGetTxObject(B, contracts, dec(100, 18), gasPrice = GAS_PRICE)
    
    const B_BalAfterRedemption = await ebtcToken.balanceOf(B)
    assert.isTrue(B_BalAfterRedemption.lt(B_BalBeforeREdemption))

    // check ETH fee 1 emitted in event is non-zero
    const emittedETHFee_1 = toBN((await th.getEmittedRedemptionValues(redemptionTx_1))[3])
    assert.isTrue(emittedETHFee_1.gt(toBN('0')))

    const C_BalBeforeREdemption = await ebtcToken.balanceOf(C)
    // C redeems
    const redemptionTx_2 = await th.redeemCollateralAndGetTxObject(C, contracts, dec(100, 18), gasPrice = GAS_PRICE)
    
    const C_BalAfterRedemption = await ebtcToken.balanceOf(C)
    assert.isTrue(C_BalAfterRedemption.lt(C_BalBeforeREdemption))
 
     // check ETH fee 2 emitted in event is non-zero
     const emittedETHFee_2 = toBN((await th.getEmittedRedemptionValues(redemptionTx_2))[3])
     assert.isTrue(emittedETHFee_2.gt(toBN('0')))

    // D draws debt
    const borrowingTx_1 = await borrowerOperations.withdrawEBTC(_dTroveId, th._100pct, dec(104, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, {from: D})
    
    // Check EBTC fee value in event is non-zero
    const emittedEBTCFee_1 = toBN(th.getEBTCFeeFromEBTCBorrowingEvent(borrowingTx_1))
    assert.isTrue(emittedEBTCFee_1.gt(toBN('0')))

    // B draws debt
    const borrowingTx_2 = await borrowerOperations.withdrawEBTC(_bTroveId, th._100pct, dec(17, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, {from: B})
    
    // Check EBTC fee value in event is non-zero
    const emittedEBTCFee_2 = toBN(th.getEBTCFeeFromEBTCBorrowingEvent(borrowingTx_2))
    assert.isTrue(emittedEBTCFee_2.gt(toBN('0')))

    const expectedTotalETHGain = emittedETHFee_1.add(emittedETHFee_2)
    const expectedTotalEBTCGain = emittedEBTCFee_1.add(emittedEBTCFee_2)

    const A_ETHBalance_Before = toBN(await web3.eth.getBalance(A))
    const A_EBTCBalance_Before = toBN(await ebtcToken.balanceOf(A))

    // A un-stakes
    const GAS_Used = th.gasUsed(await lqtyStaking.unstake(dec(100, 18), {from: A, gasPrice: GAS_PRICE }))

    const A_ETHBalance_After = toBN(await web3.eth.getBalance(A))
    const A_EBTCBalance_After = toBN(await ebtcToken.balanceOf(A))


    const A_ETHGain = A_ETHBalance_After.sub(A_ETHBalance_Before).add(toBN(GAS_Used * GAS_PRICE))
    const A_EBTCGain = A_EBTCBalance_After.sub(A_EBTCBalance_Before)

    assert.isAtMost(th.getDifference(expectedTotalETHGain, A_ETHGain), 1000)
    assert.isAtMost(th.getDifference(expectedTotalEBTCGain, A_EBTCGain), 1000)
  })

  it("stake(): Top-up sends out all accumulated ETH and EBTC gains to the staker", async () => { 
    await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
    await openTrove({ extraEBTCAmount: toBN(dec(20000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
    await openTrove({ extraEBTCAmount: toBN(dec(30000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
    let _bTroveId = await sortedTroves.cdpOfOwnerByIndex(B, 0);
    await openTrove({ extraEBTCAmount: toBN(dec(40000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })
    await openTrove({ extraEBTCAmount: toBN(dec(50000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })
    let _dTroveId = await sortedTroves.cdpOfOwnerByIndex(D, 0);

    // FF time one year so owner can transfer LQTY
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_YEAR, web3.currentProvider)

    // multisig transfers LQTY to staker A
    await lqtyToken.transfer(A, dec(100, 18), {from: multisig})

    // A makes stake
    await lqtyToken.approve(lqtyStaking.address, dec(100, 18), {from: A})
    await lqtyStaking.stake(dec(50, 18), {from: A})

    const B_BalBeforeREdemption = await ebtcToken.balanceOf(B)
    // B redeems
    const redemptionTx_1 = await th.redeemCollateralAndGetTxObject(B, contracts, dec(100, 18), gasPrice = GAS_PRICE)
    
    const B_BalAfterRedemption = await ebtcToken.balanceOf(B)
    assert.isTrue(B_BalAfterRedemption.lt(B_BalBeforeREdemption))

    // check ETH fee 1 emitted in event is non-zero
    const emittedETHFee_1 = toBN((await th.getEmittedRedemptionValues(redemptionTx_1))[3])
    assert.isTrue(emittedETHFee_1.gt(toBN('0')))

    const C_BalBeforeREdemption = await ebtcToken.balanceOf(C)
    // C redeems
    const redemptionTx_2 = await th.redeemCollateralAndGetTxObject(C, contracts, dec(100, 18), gasPrice = GAS_PRICE)
    
    const C_BalAfterRedemption = await ebtcToken.balanceOf(C)
    assert.isTrue(C_BalAfterRedemption.lt(C_BalBeforeREdemption))
 
     // check ETH fee 2 emitted in event is non-zero
     const emittedETHFee_2 = toBN((await th.getEmittedRedemptionValues(redemptionTx_2))[3])
     assert.isTrue(emittedETHFee_2.gt(toBN('0')))

    // D draws debt
    const borrowingTx_1 = await borrowerOperations.withdrawEBTC(_dTroveId, th._100pct, dec(104, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, {from: D})
    
    // Check EBTC fee value in event is non-zero
    const emittedEBTCFee_1 = toBN(th.getEBTCFeeFromEBTCBorrowingEvent(borrowingTx_1))
    assert.isTrue(emittedEBTCFee_1.gt(toBN('0')))

    // B draws debt
    const borrowingTx_2 = await borrowerOperations.withdrawEBTC(_bTroveId, th._100pct, dec(17, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, {from: B})
    
    // Check EBTC fee value in event is non-zero
    const emittedEBTCFee_2 = toBN(th.getEBTCFeeFromEBTCBorrowingEvent(borrowingTx_2))
    assert.isTrue(emittedEBTCFee_2.gt(toBN('0')))

    const expectedTotalETHGain = emittedETHFee_1.add(emittedETHFee_2)
    const expectedTotalEBTCGain = emittedEBTCFee_1.add(emittedEBTCFee_2)

    const A_ETHBalance_Before = toBN(await web3.eth.getBalance(A))
    const A_EBTCBalance_Before = toBN(await ebtcToken.balanceOf(A))

    // A tops up
    const GAS_Used = th.gasUsed(await lqtyStaking.stake(dec(50, 18), {from: A, gasPrice: GAS_PRICE }))

    const A_ETHBalance_After = toBN(await web3.eth.getBalance(A))
    const A_EBTCBalance_After = toBN(await ebtcToken.balanceOf(A))

    const A_ETHGain = A_ETHBalance_After.sub(A_ETHBalance_Before).add(toBN(GAS_Used * GAS_PRICE))
    const A_EBTCGain = A_EBTCBalance_After.sub(A_EBTCBalance_Before)

    assert.isAtMost(th.getDifference(expectedTotalETHGain, A_ETHGain), 1000)
    assert.isAtMost(th.getDifference(expectedTotalEBTCGain, A_EBTCGain), 1000)
  })

  it("getPendingETHGain(): Returns the staker's correct pending ETH gain", async () => { 
    await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
    await openTrove({ extraEBTCAmount: toBN(dec(20000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
    await openTrove({ extraEBTCAmount: toBN(dec(30000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
    await openTrove({ extraEBTCAmount: toBN(dec(40000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })
    await openTrove({ extraEBTCAmount: toBN(dec(50000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

    // FF time one year so owner can transfer LQTY
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_YEAR, web3.currentProvider)

    // multisig transfers LQTY to staker A
    await lqtyToken.transfer(A, dec(100, 18), {from: multisig})

    // A makes stake
    await lqtyToken.approve(lqtyStaking.address, dec(100, 18), {from: A})
    await lqtyStaking.stake(dec(50, 18), {from: A})

    const B_BalBeforeREdemption = await ebtcToken.balanceOf(B)
    // B redeems
    const redemptionTx_1 = await th.redeemCollateralAndGetTxObject(B, contracts, dec(100, 18), gasPrice = GAS_PRICE)
    
    const B_BalAfterRedemption = await ebtcToken.balanceOf(B)
    assert.isTrue(B_BalAfterRedemption.lt(B_BalBeforeREdemption))

    // check ETH fee 1 emitted in event is non-zero
    const emittedETHFee_1 = toBN((await th.getEmittedRedemptionValues(redemptionTx_1))[3])
    assert.isTrue(emittedETHFee_1.gt(toBN('0')))

    const C_BalBeforeREdemption = await ebtcToken.balanceOf(C)
    // C redeems
    const redemptionTx_2 = await th.redeemCollateralAndGetTxObject(C, contracts, dec(100, 18), gasPrice = GAS_PRICE)
    
    const C_BalAfterRedemption = await ebtcToken.balanceOf(C)
    assert.isTrue(C_BalAfterRedemption.lt(C_BalBeforeREdemption))
 
     // check ETH fee 2 emitted in event is non-zero
     const emittedETHFee_2 = toBN((await th.getEmittedRedemptionValues(redemptionTx_2))[3])
     assert.isTrue(emittedETHFee_2.gt(toBN('0')))

    const expectedTotalETHGain = emittedETHFee_1.add(emittedETHFee_2)

    const A_ETHGain = await lqtyStaking.getPendingETHGain(A)

    assert.isAtMost(th.getDifference(expectedTotalETHGain, A_ETHGain), 1000)
  })

  it("getPendingEBTCGain(): Returns the staker's correct pending EBTC gain", async () => { 
    await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
    await openTrove({ extraEBTCAmount: toBN(dec(20000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
    await openTrove({ extraEBTCAmount: toBN(dec(30000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
    let _bTroveId = await sortedTroves.cdpOfOwnerByIndex(B, 0);
    await openTrove({ extraEBTCAmount: toBN(dec(40000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })
    await openTrove({ extraEBTCAmount: toBN(dec(50000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })
    let _dTroveId = await sortedTroves.cdpOfOwnerByIndex(D, 0);

    // FF time one year so owner can transfer LQTY
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_YEAR, web3.currentProvider)

    // multisig transfers LQTY to staker A
    await lqtyToken.transfer(A, dec(100, 18), {from: multisig})

    // A makes stake
    await lqtyToken.approve(lqtyStaking.address, dec(100, 18), {from: A})
    await lqtyStaking.stake(dec(50, 18), {from: A})

    const B_BalBeforeREdemption = await ebtcToken.balanceOf(B)
    // B redeems
    const redemptionTx_1 = await th.redeemCollateralAndGetTxObject(B, contracts, dec(100, 18), gasPrice = GAS_PRICE)
    
    const B_BalAfterRedemption = await ebtcToken.balanceOf(B)
    assert.isTrue(B_BalAfterRedemption.lt(B_BalBeforeREdemption))

    // check ETH fee 1 emitted in event is non-zero
    const emittedETHFee_1 = toBN((await th.getEmittedRedemptionValues(redemptionTx_1))[3])
    assert.isTrue(emittedETHFee_1.gt(toBN('0')))

    const C_BalBeforeREdemption = await ebtcToken.balanceOf(C)
    // C redeems
    const redemptionTx_2 = await th.redeemCollateralAndGetTxObject(C, contracts, dec(100, 18), gasPrice = GAS_PRICE)
    
    const C_BalAfterRedemption = await ebtcToken.balanceOf(C)
    assert.isTrue(C_BalAfterRedemption.lt(C_BalBeforeREdemption))
 
     // check ETH fee 2 emitted in event is non-zero
     const emittedETHFee_2 = toBN((await th.getEmittedRedemptionValues(redemptionTx_2))[3])
     assert.isTrue(emittedETHFee_2.gt(toBN('0')))

    // D draws debt
    const borrowingTx_1 = await borrowerOperations.withdrawEBTC(_dTroveId, th._100pct, dec(104, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, {from: D})
    
    // Check EBTC fee value in event is non-zero
    const emittedEBTCFee_1 = toBN(th.getEBTCFeeFromEBTCBorrowingEvent(borrowingTx_1))
    assert.isTrue(emittedEBTCFee_1.gt(toBN('0')))

    // B draws debt
    const borrowingTx_2 = await borrowerOperations.withdrawEBTC(_bTroveId, th._100pct, dec(17, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, {from: B})
    
    // Check EBTC fee value in event is non-zero
    const emittedEBTCFee_2 = toBN(th.getEBTCFeeFromEBTCBorrowingEvent(borrowingTx_2))
    assert.isTrue(emittedEBTCFee_2.gt(toBN('0')))

    const expectedTotalEBTCGain = emittedEBTCFee_1.add(emittedEBTCFee_2)
    const A_EBTCGain = await lqtyStaking.getPendingEBTCGain(A)

    assert.isAtMost(th.getDifference(expectedTotalEBTCGain, A_EBTCGain), 1000)
  })

  // - multi depositors, several rewards
  it("LQTY Staking: Multiple stakers earn the correct share of all ETH and LQTY fees, based on their stake size", async () => {
    await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
    await openTrove({ extraEBTCAmount: toBN(dec(20000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
    await openTrove({ extraEBTCAmount: toBN(dec(30000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
    await openTrove({ extraEBTCAmount: toBN(dec(40000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })
    await openTrove({ extraEBTCAmount: toBN(dec(50000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })
    await openTrove({ extraEBTCAmount: toBN(dec(40000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: E } })
    await openTrove({ extraEBTCAmount: toBN(dec(50000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: F } })
    let _fTroveId = await sortedTroves.cdpOfOwnerByIndex(F, 0);
    await openTrove({ extraEBTCAmount: toBN(dec(50000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: G } })
    let _gTroveId = await sortedTroves.cdpOfOwnerByIndex(G, 0);

    // FF time one year so owner can transfer LQTY
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_YEAR, web3.currentProvider)

    // multisig transfers LQTY to staker A, B, C
    await lqtyToken.transfer(A, dec(100, 18), {from: multisig})
    await lqtyToken.transfer(B, dec(200, 18), {from: multisig})
    await lqtyToken.transfer(C, dec(300, 18), {from: multisig})

    // A, B, C make stake
    await lqtyToken.approve(lqtyStaking.address, dec(100, 18), {from: A})
    await lqtyToken.approve(lqtyStaking.address, dec(200, 18), {from: B})
    await lqtyToken.approve(lqtyStaking.address, dec(300, 18), {from: C})
    await lqtyStaking.stake(dec(100, 18), {from: A})
    await lqtyStaking.stake(dec(200, 18), {from: B})
    await lqtyStaking.stake(dec(300, 18), {from: C})

    // Confirm staking contract holds 600 LQTY
    // console.log(`lqty staking LQTY bal: ${await lqtyToken.balanceOf(lqtyStaking.address)}`)
    assert.equal(await lqtyToken.balanceOf(lqtyStaking.address), dec(600, 18))
    assert.equal(await lqtyStaking.totalLQTYStaked(), dec(600, 18))

    // F redeems
    const redemptionTx_1 = await th.redeemCollateralAndGetTxObject(F, contracts, dec(45, 18), gasPrice = GAS_PRICE)
    const emittedETHFee_1 = toBN((await th.getEmittedRedemptionValues(redemptionTx_1))[3])
    assert.isTrue(emittedETHFee_1.gt(toBN('0')))

     // G redeems
     const redemptionTx_2 = await th.redeemCollateralAndGetTxObject(G, contracts, dec(197, 18), gasPrice = GAS_PRICE)
     const emittedETHFee_2 = toBN((await th.getEmittedRedemptionValues(redemptionTx_2))[3])
     assert.isTrue(emittedETHFee_2.gt(toBN('0')))

    // F draws debt
    const borrowingTx_1 = await borrowerOperations.withdrawEBTC(_fTroveId, th._100pct, dec(104, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, {from: F})
    const emittedEBTCFee_1 = toBN(th.getEBTCFeeFromEBTCBorrowingEvent(borrowingTx_1))
    assert.isTrue(emittedEBTCFee_1.gt(toBN('0')))

    // G draws debt
    const borrowingTx_2 = await borrowerOperations.withdrawEBTC(_gTroveId, th._100pct, dec(17, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, {from: G})
    const emittedEBTCFee_2 = toBN(th.getEBTCFeeFromEBTCBorrowingEvent(borrowingTx_2))
    assert.isTrue(emittedEBTCFee_2.gt(toBN('0')))

    // D obtains LQTY from owner and makes a stake
    await lqtyToken.transfer(D, dec(50, 18), {from: multisig})
    await lqtyToken.approve(lqtyStaking.address, dec(50, 18), {from: D})
    await lqtyStaking.stake(dec(50, 18), {from: D})

    // Confirm staking contract holds 650 LQTY
    assert.equal(await lqtyToken.balanceOf(lqtyStaking.address), dec(650, 18))
    assert.equal(await lqtyStaking.totalLQTYStaked(), dec(650, 18))

     // G redeems
     const redemptionTx_3 = await th.redeemCollateralAndGetTxObject(C, contracts, dec(197, 18), gasPrice = GAS_PRICE)
     const emittedETHFee_3 = toBN((await th.getEmittedRedemptionValues(redemptionTx_3))[3])
     assert.isTrue(emittedETHFee_3.gt(toBN('0')))

     // G draws debt
    const borrowingTx_3 = await borrowerOperations.withdrawEBTC(_gTroveId, th._100pct, dec(17, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, {from: G})
    const emittedEBTCFee_3 = toBN(th.getEBTCFeeFromEBTCBorrowingEvent(borrowingTx_3))
    assert.isTrue(emittedEBTCFee_3.gt(toBN('0')))
     
    /*  
    Expected rewards:

    A_ETH: (100* ETHFee_1)/600 + (100* ETHFee_2)/600 + (100*ETH_Fee_3)/650
    B_ETH: (200* ETHFee_1)/600 + (200* ETHFee_2)/600 + (200*ETH_Fee_3)/650
    C_ETH: (300* ETHFee_1)/600 + (300* ETHFee_2)/600 + (300*ETH_Fee_3)/650
    D_ETH:                                             (100*ETH_Fee_3)/650

    A_EBTC: (100*EBTCFee_1 )/600 + (100* EBTCFee_2)/600 + (100*EBTCFee_3)/650
    B_EBTC: (200* EBTCFee_1)/600 + (200* EBTCFee_2)/600 + (200*EBTCFee_3)/650
    C_EBTC: (300* EBTCFee_1)/600 + (300* EBTCFee_2)/600 + (300*EBTCFee_3)/650
    D_EBTC:                                               (100*EBTCFee_3)/650
    */

    // Expected ETH gains
    const expectedETHGain_A = toBN('100').mul(emittedETHFee_1).div( toBN('600'))
                            .add(toBN('100').mul(emittedETHFee_2).div( toBN('600')))
                            .add(toBN('100').mul(emittedETHFee_3).div( toBN('650')))

    const expectedETHGain_B = toBN('200').mul(emittedETHFee_1).div( toBN('600'))
                            .add(toBN('200').mul(emittedETHFee_2).div( toBN('600')))
                            .add(toBN('200').mul(emittedETHFee_3).div( toBN('650')))

    const expectedETHGain_C = toBN('300').mul(emittedETHFee_1).div( toBN('600'))
                            .add(toBN('300').mul(emittedETHFee_2).div( toBN('600')))
                            .add(toBN('300').mul(emittedETHFee_3).div( toBN('650')))

    const expectedETHGain_D = toBN('50').mul(emittedETHFee_3).div( toBN('650'))

    // Expected EBTC gains:
    const expectedEBTCGain_A = toBN('100').mul(emittedEBTCFee_1).div( toBN('600'))
                            .add(toBN('100').mul(emittedEBTCFee_2).div( toBN('600')))
                            .add(toBN('100').mul(emittedEBTCFee_3).div( toBN('650')))

    const expectedEBTCGain_B = toBN('200').mul(emittedEBTCFee_1).div( toBN('600'))
                            .add(toBN('200').mul(emittedEBTCFee_2).div( toBN('600')))
                            .add(toBN('200').mul(emittedEBTCFee_3).div( toBN('650')))

    const expectedEBTCGain_C = toBN('300').mul(emittedEBTCFee_1).div( toBN('600'))
                            .add(toBN('300').mul(emittedEBTCFee_2).div( toBN('600')))
                            .add(toBN('300').mul(emittedEBTCFee_3).div( toBN('650')))
    
    const expectedEBTCGain_D = toBN('50').mul(emittedEBTCFee_3).div( toBN('650'))


    const A_ETHBalance_Before = toBN(await web3.eth.getBalance(A))
    const A_EBTCBalance_Before = toBN(await ebtcToken.balanceOf(A))
    const B_ETHBalance_Before = toBN(await web3.eth.getBalance(B))
    const B_EBTCBalance_Before = toBN(await ebtcToken.balanceOf(B))
    const C_ETHBalance_Before = toBN(await web3.eth.getBalance(C))
    const C_EBTCBalance_Before = toBN(await ebtcToken.balanceOf(C))
    const D_ETHBalance_Before = toBN(await web3.eth.getBalance(D))
    const D_EBTCBalance_Before = toBN(await ebtcToken.balanceOf(D))

    // A-D un-stake
    const A_GAS_Used = th.gasUsed(await lqtyStaking.unstake(dec(100, 18), {from: A, gasPrice: GAS_PRICE }))
    const B_GAS_Used = th.gasUsed(await lqtyStaking.unstake(dec(200, 18), {from: B, gasPrice: GAS_PRICE }))
    const C_GAS_Used = th.gasUsed(await lqtyStaking.unstake(dec(400, 18), {from: C, gasPrice: GAS_PRICE }))
    const D_GAS_Used = th.gasUsed(await lqtyStaking.unstake(dec(50, 18), {from: D, gasPrice: GAS_PRICE }))

    // Confirm all depositors could withdraw

    //Confirm pool Size is now 0
    assert.equal((await lqtyToken.balanceOf(lqtyStaking.address)), '0')
    assert.equal((await lqtyStaking.totalLQTYStaked()), '0')

    // Get A-D ETH and EBTC balances
    const A_ETHBalance_After = toBN(await web3.eth.getBalance(A))
    const A_EBTCBalance_After = toBN(await ebtcToken.balanceOf(A))
    const B_ETHBalance_After = toBN(await web3.eth.getBalance(B))
    const B_EBTCBalance_After = toBN(await ebtcToken.balanceOf(B))
    const C_ETHBalance_After = toBN(await web3.eth.getBalance(C))
    const C_EBTCBalance_After = toBN(await ebtcToken.balanceOf(C))
    const D_ETHBalance_After = toBN(await web3.eth.getBalance(D))
    const D_EBTCBalance_After = toBN(await ebtcToken.balanceOf(D))

    // Get ETH and EBTC gains
    const A_ETHGain = A_ETHBalance_After.sub(A_ETHBalance_Before).add(toBN(A_GAS_Used * GAS_PRICE))
    const A_EBTCGain = A_EBTCBalance_After.sub(A_EBTCBalance_Before)
    const B_ETHGain = B_ETHBalance_After.sub(B_ETHBalance_Before).add(toBN(B_GAS_Used * GAS_PRICE))
    const B_EBTCGain = B_EBTCBalance_After.sub(B_EBTCBalance_Before)
    const C_ETHGain = C_ETHBalance_After.sub(C_ETHBalance_Before).add(toBN(C_GAS_Used * GAS_PRICE))
    const C_EBTCGain = C_EBTCBalance_After.sub(C_EBTCBalance_Before)
    const D_ETHGain = D_ETHBalance_After.sub(D_ETHBalance_Before).add(toBN(D_GAS_Used * GAS_PRICE))
    const D_EBTCGain = D_EBTCBalance_After.sub(D_EBTCBalance_Before)

    // Check gains match expected amounts
    assert.isAtMost(th.getDifference(expectedETHGain_A, A_ETHGain), 1000)
    assert.isAtMost(th.getDifference(expectedEBTCGain_A, A_EBTCGain), 1000)
    assert.isAtMost(th.getDifference(expectedETHGain_B, B_ETHGain), 1000)
    assert.isAtMost(th.getDifference(expectedEBTCGain_B, B_EBTCGain), 1000)
    assert.isAtMost(th.getDifference(expectedETHGain_C, C_ETHGain), 1000)
    assert.isAtMost(th.getDifference(expectedEBTCGain_C, C_EBTCGain), 1000)
    assert.isAtMost(th.getDifference(expectedETHGain_D, D_ETHGain), 1000)
    assert.isAtMost(th.getDifference(expectedEBTCGain_D, D_EBTCGain), 1000)
  })
 
  it("unstake(): reverts if caller has ETH gains and can't receive ETH",  async () => {
    await openTrove({ extraEBTCAmount: toBN(dec(20000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: whale } })  
    await openTrove({ extraEBTCAmount: toBN(dec(20000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
    await openTrove({ extraEBTCAmount: toBN(dec(30000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
    await openTrove({ extraEBTCAmount: toBN(dec(40000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })
    await openTrove({ extraEBTCAmount: toBN(dec(50000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_YEAR, web3.currentProvider)

    // multisig transfers LQTY to staker A and the non-payable proxy
    await lqtyToken.transfer(A, dec(100, 18), {from: multisig})
    await lqtyToken.transfer(nonPayable.address, dec(100, 18), {from: multisig})

    //  A makes stake
    const A_stakeTx = await lqtyStaking.stake(dec(100, 18), {from: A})
    assert.isTrue(A_stakeTx.receipt.status)

    //  A tells proxy to make a stake
    const proxystakeTxData = await th.getTransactionData('stake(uint256)', ['0x56bc75e2d63100000'])  // proxy stakes 100 LQTY
    await nonPayable.forward(lqtyStaking.address, proxystakeTxData, {from: A})


    // B makes a redemption, creating ETH gain for proxy
    const redemptionTx_1 = await th.redeemCollateralAndGetTxObject(B, contracts, dec(45, 18), gasPrice = GAS_PRICE)
    
    const proxy_ETHGain = await lqtyStaking.getPendingETHGain(nonPayable.address)
    assert.isTrue(proxy_ETHGain.gt(toBN('0')))

    // Expect this tx to revert: stake() tries to send nonPayable proxy's accumulated ETH gain (albeit 0),
    //  A tells proxy to unstake
    const proxyUnStakeTxData = await th.getTransactionData('unstake(uint256)', ['0x56bc75e2d63100000'])  // proxy stakes 100 LQTY
    const proxyUnstakeTxPromise = nonPayable.forward(lqtyStaking.address, proxyUnStakeTxData, {from: A})
   
    // but nonPayable proxy can not accept ETH - therefore stake() reverts.
    await assertRevert(proxyUnstakeTxPromise)
  })

  it("receive(): reverts when it receives ETH from an address that is not the Active Pool",  async () => { 
    const ethSendTxPromise1 = web3.eth.sendTransaction({to: lqtyStaking.address, from: A, value: dec(1, 'ether')})
    const ethSendTxPromise2 = web3.eth.sendTransaction({to: lqtyStaking.address, from: owner, value: dec(1, 'ether')})

    await assertRevert(ethSendTxPromise1)
    await assertRevert(ethSendTxPromise2)
  })

  it("unstake(): reverts if user has no stake",  async () => {  
    const unstakeTxPromise1 = lqtyStaking.unstake(1, {from: A})
    const unstakeTxPromise2 = lqtyStaking.unstake(1, {from: owner})

    await assertRevert(unstakeTxPromise1)
    await assertRevert(unstakeTxPromise2)
  })

  it('Test requireCallerIsTroveManager', async () => {
    const lqtyStakingTester = await LQTYStakingTester.new()
    await assertRevert(lqtyStakingTester.requireCallerIsTroveManager(), 'LQTYStaking: caller is not TroveM')
  })
})
