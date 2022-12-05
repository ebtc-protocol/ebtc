const deploymentHelper = require("../utils/deploymentHelpers.js")
const testHelpers = require("../utils/testHelpers.js")

const TroveManagerTester = artifacts.require("TroveManagerTester")
const LQTYTokenTester = artifacts.require("LQTYTokenTester")

const th = testHelpers.TestHelper

const dec = th.dec
const toBN = th.toBN
const mv = testHelpers.MoneyValues
const timeValues = testHelpers.TimeValues

const ZERO_ADDRESS = th.ZERO_ADDRESS
const assertRevert = th.assertRevert

const GAS_PRICE = 10000000000 //10GWEI


const {
  buildUserProxies,
  BorrowerOperationsProxy,
  BorrowerWrappersProxy,
  TroveManagerProxy,
  StabilityPoolProxy,
  SortedTrovesProxy,
  TokenProxy,
  LQTYStakingProxy
} = require('../utils/proxyHelpers.js')

contract('BorrowerWrappers', async accounts => {

  const [
    owner, alice, bob, carol, dennis, whale,
    A, B, C, D, E,
    defaulter_1, defaulter_2,
    // frontEnd_1, frontEnd_2, frontEnd_3
  ] = accounts;

  const [bountyAddress, lpRewardsAddress, multisig] = accounts.slice(accounts.length - 3, accounts.length)

  let priceFeed
  let ebtcToken
  let sortedTroves
  let cdpManagerOriginal
  let cdpManager
  let activePool
  let stabilityPool
  let defaultPool
  let collSurplusPool
  let borrowerOperations
  let borrowerWrappers
  let lqtyTokenOriginal
  let lqtyToken
  let lqtyStaking

  let contracts

  let EBTC_GAS_COMPENSATION

  const getOpenTroveEBTCAmount = async (totalDebt) => th.getOpenTroveEBTCAmount(contracts, totalDebt)
  const getActualDebtFromComposite = async (compositeDebt) => th.getActualDebtFromComposite(compositeDebt, contracts)
  const getNetBorrowingAmount = async (debtWithFee) => th.getNetBorrowingAmount(contracts, debtWithFee)
  const openTrove = async (params) => th.openTrove(contracts, params)

  beforeEach(async () => {
    contracts = await deploymentHelper.deployLiquityCore()
    contracts.cdpManager = await TroveManagerTester.new()
    contracts = await deploymentHelper.deployEBTCToken(contracts)
    const LQTYContracts = await deploymentHelper.deployLQTYTesterContractsHardhat(bountyAddress, lpRewardsAddress, multisig)

    await deploymentHelper.connectLQTYContracts(LQTYContracts)
    await deploymentHelper.connectCoreContracts(contracts, LQTYContracts)
    await deploymentHelper.connectLQTYContractsToCore(LQTYContracts, contracts)

    cdpManagerOriginal = contracts.cdpManager
    lqtyTokenOriginal = LQTYContracts.lqtyToken

    const users = [ alice, bob, carol, dennis, whale, A, B, C, D, E, defaulter_1, defaulter_2 ]
    await deploymentHelper.deployProxyScripts(contracts, LQTYContracts, owner, users)

    priceFeed = contracts.priceFeedTestnet
    ebtcToken = contracts.ebtcToken
    sortedTroves = contracts.sortedTroves
    cdpManager = contracts.cdpManager
    activePool = contracts.activePool
    stabilityPool = contracts.stabilityPool
    defaultPool = contracts.defaultPool
    collSurplusPool = contracts.collSurplusPool
    borrowerOperations = contracts.borrowerOperations
    borrowerWrappers = contracts.borrowerWrappers
    lqtyStaking = LQTYContracts.lqtyStaking
    lqtyToken = LQTYContracts.lqtyToken

    EBTC_GAS_COMPENSATION = await borrowerOperations.EBTC_GAS_COMPENSATION()
  })

  it('proxy owner can recover ETH', async () => {
    const amount = toBN(dec(1, 18))
    const proxyAddress = borrowerWrappers.getProxyAddressFromUser(alice)

    // send some ETH to proxy
    await web3.eth.sendTransaction({ from: owner, to: proxyAddress, value: amount, gasPrice: GAS_PRICE })
    assert.equal(await web3.eth.getBalance(proxyAddress), amount.toString())

    const balanceBefore = toBN(await web3.eth.getBalance(alice))

    // recover ETH
    const gas_Used = th.gasUsed(await borrowerWrappers.transferETH(alice, amount, { from: alice, gasPrice: GAS_PRICE }))
    
    const balanceAfter = toBN(await web3.eth.getBalance(alice))
    const expectedBalance = toBN(balanceBefore.sub(toBN(gas_Used * GAS_PRICE)))
    assert.equal(balanceAfter.sub(expectedBalance), amount.toString())
  })

  it('non proxy owner cannot recover ETH', async () => {
    const amount = toBN(dec(1, 18))
    const proxyAddress = borrowerWrappers.getProxyAddressFromUser(alice)

    // send some ETH to proxy
    await web3.eth.sendTransaction({ from: owner, to: proxyAddress, value: amount })
    assert.equal(await web3.eth.getBalance(proxyAddress), amount.toString())

    const balanceBefore = toBN(await web3.eth.getBalance(alice))

    // try to recover ETH
    const proxy = borrowerWrappers.getProxyFromUser(alice)
    const signature = 'transferETH(address,uint256)'
    const calldata = th.getTransactionData(signature, [alice, amount])
    await assertRevert(proxy.methods["execute(address,bytes)"](borrowerWrappers.scriptAddress, calldata, { from: bob }), 'ds-auth-unauthorized')

    assert.equal(await web3.eth.getBalance(proxyAddress), amount.toString())

    const balanceAfter = toBN(await web3.eth.getBalance(alice))
    assert.equal(balanceAfter, balanceBefore.toString())
  })

  // --- claimCollateralAndOpenTrove ---

  it('claimCollateralAndOpenTrove(): reverts if nothing to claim', async () => {
    // Whale opens Trove
    await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: whale } })

    // alice opens Trove
    const { ebtcAmount, collateral } = await openTrove({ ICR: toBN(dec(15, 17)), extraParams: { from: alice } })

    const proxyAddress = borrowerWrappers.getProxyAddressFromUser(alice)
    assert.equal(await web3.eth.getBalance(proxyAddress), '0')
    let _aliceTroveId = await sortedTroves.cdpOfOwnerByIndex(proxyAddress, 0);

    // skip bootstrapping phase
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_WEEK * 2, web3.currentProvider)

    // alice claims collateral and re-opens the cdp
    await assertRevert(
      borrowerWrappers.claimCollateralAndOpenTrove(th._100pct, ebtcAmount, alice, alice, { from: alice }),
      'CollSurplusPool: No collateral available to claim'
    )

    // check everything remain the same
    assert.equal(await web3.eth.getBalance(proxyAddress), '0')
    th.assertIsApproximatelyEqual(await collSurplusPool.getCollateral(proxyAddress), '0')
    th.assertIsApproximatelyEqual(await ebtcToken.balanceOf(proxyAddress), ebtcAmount)
    assert.equal(await cdpManager.getTroveStatus(_aliceTroveId), 1)
    th.assertIsApproximatelyEqual(await cdpManager.getTroveColl(_aliceTroveId), collateral)
  })

  it('claimCollateralAndOpenTrove(): without sending any value', async () => {
    // alice opens Trove
    const { ebtcAmount, netDebt: redeemAmount, collateral } = await openTrove({extraEBTCAmount: 0, ICR: toBN(dec(3, 18)), extraParams: { from: alice } })
    // Whale opens Trove
    await openTrove({ extraEBTCAmount: redeemAmount, ICR: toBN(dec(5, 18)), extraParams: { from: whale } })

    const proxyAddress = borrowerWrappers.getProxyAddressFromUser(alice)
    assert.equal(await web3.eth.getBalance(proxyAddress), '0')
    let _aliceTroveId = await sortedTroves.cdpOfOwnerByIndex(proxyAddress, 0);

    // skip bootstrapping phase
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_WEEK * 2, web3.currentProvider)

    // whale redeems 150 EBTC
    await th.redeemCollateral(whale, contracts, redeemAmount, GAS_PRICE)
    assert.equal(await web3.eth.getBalance(proxyAddress), '0')

    // surplus: 5 - 150/200
    const price = await priceFeed.getPrice();
    const expectedSurplus = collateral.sub(redeemAmount.mul(mv._1e18BN).div(price))
    th.assertIsApproximatelyEqual(await collSurplusPool.getCollateral(proxyAddress), expectedSurplus)
    assert.equal(await cdpManager.getTroveStatus(_aliceTroveId), 4) // closed by redemption

    // alice claims collateral and re-opens the cdp
    await borrowerWrappers.claimCollateralAndOpenTrove(th._100pct, ebtcAmount, alice, alice, { from: alice })
    let _aliceTroveId2 = await sortedTroves.cdpOfOwnerByIndex(proxyAddress, 0);

    assert.equal(await web3.eth.getBalance(proxyAddress), '0')
    th.assertIsApproximatelyEqual(await collSurplusPool.getCollateral(proxyAddress), '0')
    th.assertIsApproximatelyEqual(await ebtcToken.balanceOf(proxyAddress), ebtcAmount.mul(toBN(2)))
    assert.equal(await cdpManager.getTroveStatus(_aliceTroveId2), 1)
    th.assertIsApproximatelyEqual(await cdpManager.getTroveColl(_aliceTroveId2), expectedSurplus)
  })

  it('claimCollateralAndOpenTrove(): sending value in the transaction', async () => {
    // alice opens Trove
    const { ebtcAmount, netDebt: redeemAmount, collateral } = await openTrove({ extraParams: { from: alice } })
    // Whale opens Trove
    await openTrove({ extraEBTCAmount: redeemAmount, ICR: toBN(dec(2, 18)), extraParams: { from: whale } })

    const proxyAddress = borrowerWrappers.getProxyAddressFromUser(alice)
    assert.equal(await web3.eth.getBalance(proxyAddress), '0')
    let _aliceTroveId = await sortedTroves.cdpOfOwnerByIndex(proxyAddress, 0);

    // skip bootstrapping phase
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_WEEK * 2, web3.currentProvider)

    // whale redeems 150 EBTC
    await th.redeemCollateral(whale, contracts, redeemAmount, GAS_PRICE)
    assert.equal(await web3.eth.getBalance(proxyAddress), '0')

    // surplus: 5 - 150/200
    const price = await priceFeed.getPrice();
    const expectedSurplus = collateral.sub(redeemAmount.mul(mv._1e18BN).div(price))
    th.assertIsApproximatelyEqual(await collSurplusPool.getCollateral(proxyAddress), expectedSurplus)
    assert.equal(await cdpManager.getTroveStatus(_aliceTroveId), 4) // closed by redemption

    // alice claims collateral and re-opens the cdp
    await borrowerWrappers.claimCollateralAndOpenTrove(th._100pct, ebtcAmount, alice, alice, { from: alice, value: collateral })
    let _aliceTroveId2 = await sortedTroves.cdpOfOwnerByIndex(proxyAddress, 0);

    assert.equal(await web3.eth.getBalance(proxyAddress), '0')
    th.assertIsApproximatelyEqual(await collSurplusPool.getCollateral(proxyAddress), '0')
    th.assertIsApproximatelyEqual(await ebtcToken.balanceOf(proxyAddress), ebtcAmount.mul(toBN(2)))
    assert.equal(await cdpManager.getTroveStatus(_aliceTroveId2), 1)
    th.assertIsApproximatelyEqual(await cdpManager.getTroveColl(_aliceTroveId2), expectedSurplus.add(collateral))
  })

  // --- claimSPRewardsAndRecycle ---

  it('claimSPRewardsAndRecycle(): only owner can call it', async () => {
    // Whale opens Trove
    await openTrove({ extraEBTCAmount: toBN(dec(1850, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: whale } })
    // Whale deposits 1850 EBTC in StabilityPool
    await stabilityPool.provideToSP(dec(1850, 18), ZERO_ADDRESS, { from: whale })

    // alice opens cdp and provides 150 EBTC to StabilityPool
    await openTrove({ extraEBTCAmount: toBN(dec(150, 18)), extraParams: { from: alice } })
    await stabilityPool.provideToSP(dec(150, 18), ZERO_ADDRESS, { from: alice })

    // Defaulter Trove opened
    await openTrove({ ICR: toBN(dec(210, 16)), extraParams: { from: defaulter_1 } })
    const defaulterProxyAddress = borrowerWrappers.getProxyAddressFromUser(defaulter_1);
    let _defaulterTroveId1 = await sortedTroves.cdpOfOwnerByIndex(defaulterProxyAddress, 0);

    // price drops: defaulters' Troves fall below MCR, alice and whale Trove remain active
    const price = toBN(dec(100, 18))
    await priceFeed.setPrice(price);

    // Defaulter cdp closed
    const liquidationTX_1 = await cdpManager.liquidate(_defaulterTroveId1, { from: owner })
    const [liquidatedDebt_1] = await th.getEmittedLiquidationValues(liquidationTX_1)

    // Bob tries to claims SP rewards in behalf of Alice
    const proxy = borrowerWrappers.getProxyFromUser(alice)
    const signature = 'claimSPRewardsAndRecycle(uint256,address,address)'
    const calldata = th.getTransactionData(signature, [th._100pct, alice, alice])
    await assertRevert(proxy.methods["execute(address,bytes)"](borrowerWrappers.scriptAddress, calldata, { from: bob }), 'ds-auth-unauthorized')
  })

  it('claimSPRewardsAndRecycle():', async () => {
    // Whale opens Trove
    const whaleDeposit = toBN(dec(2350, 18))
    await openTrove({ extraEBTCAmount: whaleDeposit, ICR: toBN(dec(4, 18)), extraParams: { from: whale } })
    // Whale deposits 1850 EBTC in StabilityPool
    await stabilityPool.provideToSP(whaleDeposit, ZERO_ADDRESS, { from: whale })

    // alice opens cdp and provides 150 EBTC to StabilityPool
    const aliceDeposit = toBN(dec(150, 18))
    await openTrove({ extraEBTCAmount: aliceDeposit, ICR: toBN(dec(3, 18)), extraParams: { from: alice } })
    await stabilityPool.provideToSP(aliceDeposit, ZERO_ADDRESS, { from: alice })
    const aliceProxyAddress = borrowerWrappers.getProxyAddressFromUser(alice);
    let _aliceTroveId = await sortedTroves.cdpOfOwnerByIndex(aliceProxyAddress, 0);

    // Defaulter Trove opened
    const { ebtcAmount, netDebt, collateral } = await openTrove({ ICR: toBN(dec(210, 16)), extraParams: { from: defaulter_1 } })
    const defaulterProxyAddress = borrowerWrappers.getProxyAddressFromUser(defaulter_1);
    let _defaulterTroveId1 = await sortedTroves.cdpOfOwnerByIndex(defaulterProxyAddress, 0);

    // price drops: defaulters' Troves fall below MCR, alice and whale Trove remain active
    const price = toBN(dec(100, 18))
    await priceFeed.setPrice(price);

    // Defaulter cdp closed
    const liquidationTX_1 = await cdpManager.liquidate(_defaulterTroveId1, { from: owner })
    const [liquidatedDebt_1] = await th.getEmittedLiquidationValues(liquidationTX_1)

    // Alice EBTCLoss is ((150/2500) * liquidatedDebt)
    const totalDeposits = whaleDeposit.add(aliceDeposit)
    const expectedEBTCLoss_A = liquidatedDebt_1.mul(aliceDeposit).div(totalDeposits)

    const expectedCompoundedEBTCDeposit_A = toBN(dec(150, 18)).sub(expectedEBTCLoss_A)
    const compoundedEBTCDeposit_A = await stabilityPool.getCompoundedEBTCDeposit(alice)
    // collateral * 150 / 2500 * 0.995
    const expectedETHGain_A = collateral.mul(aliceDeposit).div(totalDeposits).mul(toBN(dec(995, 15))).div(mv._1e18BN)

    assert.isAtMost(th.getDifference(expectedCompoundedEBTCDeposit_A, compoundedEBTCDeposit_A), 1000)

    const ethBalanceBefore = await web3.eth.getBalance(borrowerOperations.getProxyAddressFromUser(alice))
    const cdpCollBefore = await cdpManager.getTroveColl(_aliceTroveId)
    const ebtcBalanceBefore = await ebtcToken.balanceOf(alice)
    const cdpDebtBefore = await cdpManager.getTroveDebt(_aliceTroveId)
    const lqtyBalanceBefore = await lqtyToken.balanceOf(alice)
    const ICRBefore = await cdpManager.getCurrentICR(_aliceTroveId, price)
    const depositBefore = (await stabilityPool.deposits(alice))[0]
    const stakeBefore = await lqtyStaking.stakes(alice)

    const proportionalEBTC = expectedETHGain_A.mul(price).div(ICRBefore)
    const borrowingRate = await cdpManagerOriginal.getBorrowingRateWithDecay()
    const netDebtChange = proportionalEBTC.mul(mv._1e18BN).div(mv._1e18BN.add(borrowingRate))

    // to force LQTY issuance
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_WEEK * 2, web3.currentProvider)

    const expectedLQTYGain_A = toBN('50373424199406504708132')

    await priceFeed.setPrice(price.mul(toBN(2)));

    // Alice claims SP rewards and puts them back in the system through the proxy
    const proxyAddress = borrowerWrappers.getProxyAddressFromUser(alice)
    await borrowerWrappers.claimSPRewardsAndRecycle(_aliceTroveId, th._100pct, _aliceTroveId, _aliceTroveId, { from: alice })

    const ethBalanceAfter = await web3.eth.getBalance(borrowerOperations.getProxyAddressFromUser(alice))
    const cdpCollAfter = await cdpManager.getTroveColl(_aliceTroveId)
    const ebtcBalanceAfter = await ebtcToken.balanceOf(alice)
    const cdpDebtAfter = await cdpManager.getTroveDebt(_aliceTroveId)
    const lqtyBalanceAfter = await lqtyToken.balanceOf(alice)
    const ICRAfter = await cdpManager.getCurrentICR(_aliceTroveId, price)
    const depositAfter = (await stabilityPool.deposits(alice))[0]
    const stakeAfter = await lqtyStaking.stakes(alice)

    // check proxy balances remain the same
    assert.equal(ethBalanceAfter.toString(), ethBalanceBefore.toString())
    assert.equal(ebtcBalanceAfter.toString(), ebtcBalanceBefore.toString())
    assert.equal(lqtyBalanceAfter.toString(), lqtyBalanceBefore.toString())
    // check cdp has increased debt by the ICR proportional amount to ETH gain
    th.assertIsApproximatelyEqual(cdpDebtAfter, cdpDebtBefore.add(proportionalEBTC))
    // check cdp has increased collateral by the ETH gain
    th.assertIsApproximatelyEqual(cdpCollAfter, cdpCollBefore.add(expectedETHGain_A))
    // check that ICR remains constant
    th.assertIsApproximatelyEqual(ICRAfter, ICRBefore)
    // check that Stability Pool deposit
    th.assertIsApproximatelyEqual(depositAfter, depositBefore.sub(expectedEBTCLoss_A).add(netDebtChange))
    // check lqty balance remains the same
    th.assertIsApproximatelyEqual(lqtyBalanceAfter, lqtyBalanceBefore)

    // LQTY staking
    th.assertIsApproximatelyEqual(stakeAfter, stakeBefore.add(expectedLQTYGain_A))

    // Expect Alice has withdrawn all ETH gain
    const alice_pendingETHGain = await stabilityPool.getDepositorETHGain(alice)
    assert.equal(alice_pendingETHGain, 0)
  })


  // --- claimStakingGainsAndRecycle ---

  it('claimStakingGainsAndRecycle(): only owner can call it', async () => {
    // Whale opens Trove
    await openTrove({ extraEBTCAmount: toBN(dec(1850, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: whale } })

    // alice opens cdp
    await openTrove({ extraEBTCAmount: toBN(dec(150, 18)), extraParams: { from: alice } })

    // mint some LQTY
    await lqtyTokenOriginal.unprotectedMint(borrowerOperations.getProxyAddressFromUser(whale), dec(1850, 18))
    await lqtyTokenOriginal.unprotectedMint(borrowerOperations.getProxyAddressFromUser(alice), dec(150, 18))

    // stake LQTY
    await lqtyStaking.stake(dec(1850, 18), { from: whale })
    await lqtyStaking.stake(dec(150, 18), { from: alice })

    // Defaulter Trove opened
    const { ebtcAmount, netDebt, totalDebt, collateral } = await openTrove({ ICR: toBN(dec(210, 16)), extraParams: { from: defaulter_1 } })

    // skip bootstrapping phase
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_WEEK * 2, web3.currentProvider)

    // whale redeems 100 EBTC
    const redeemedAmount = toBN(dec(100, 18))
    await th.redeemCollateral(whale, contracts, redeemedAmount, GAS_PRICE)

    // Bob tries to claims staking gains in behalf of Alice
    const proxy = borrowerWrappers.getProxyFromUser(alice)
    const signature = 'claimStakingGainsAndRecycle(uint256,address,address)'
    const calldata = th.getTransactionData(signature, [th._100pct, alice, alice])
    await assertRevert(proxy.methods["execute(address,bytes)"](borrowerWrappers.scriptAddress, calldata, { from: bob }), 'ds-auth-unauthorized')
  })

  it('claimStakingGainsAndRecycle(): reverts if user has no cdp', async () => {
    const price = toBN(dec(200, 18))

    // Whale opens Trove
    await openTrove({ extraEBTCAmount: toBN(dec(1850, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: whale } })
    // Whale deposits 1850 EBTC in StabilityPool
    await stabilityPool.provideToSP(dec(1850, 18), ZERO_ADDRESS, { from: whale })

    // alice opens cdp and provides 150 EBTC to StabilityPool
    //await openTrove({ extraEBTCAmount: toBN(dec(150, 18)), extraParams: { from: alice } })
    //await stabilityPool.provideToSP(dec(150, 18), ZERO_ADDRESS, { from: alice })

    // mint some LQTY
    await lqtyTokenOriginal.unprotectedMint(borrowerOperations.getProxyAddressFromUser(whale), dec(1850, 18))
    await lqtyTokenOriginal.unprotectedMint(borrowerOperations.getProxyAddressFromUser(alice), dec(150, 18))

    // stake LQTY
    await lqtyStaking.stake(dec(1850, 18), { from: whale })
    await lqtyStaking.stake(dec(150, 18), { from: alice })

    // Defaulter Trove opened
    const { ebtcAmount, netDebt, totalDebt, collateral } = await openTrove({ ICR: toBN(dec(210, 16)), extraParams: { from: defaulter_1 } })
    const borrowingFee = netDebt.sub(ebtcAmount)

    // Alice EBTC gain is ((150/2000) * borrowingFee)
    const expectedEBTCGain_A = borrowingFee.mul(toBN(dec(150, 18))).div(toBN(dec(2000, 18)))

    // skip bootstrapping phase
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_WEEK * 2, web3.currentProvider)

    // whale redeems 100 EBTC
    const redeemedAmount = toBN(dec(100, 18))
    await th.redeemCollateral(whale, contracts, redeemedAmount, GAS_PRICE)

    const ethBalanceBefore = await web3.eth.getBalance(borrowerOperations.getProxyAddressFromUser(alice))
    const cdpCollBefore = await cdpManager.getTroveColl(th.DUMMY_BYTES32)
    const ebtcBalanceBefore = await ebtcToken.balanceOf(alice)
    const cdpDebtBefore = await cdpManager.getTroveDebt(th.DUMMY_BYTES32)
    const lqtyBalanceBefore = await lqtyToken.balanceOf(alice)
    const ICRBefore = await cdpManager.getCurrentICR(th.DUMMY_BYTES32, price)
    const depositBefore = (await stabilityPool.deposits(alice))[0]
    const stakeBefore = await lqtyStaking.stakes(alice)

    // Alice claims staking rewards and puts them back in the system through the proxy
    await assertRevert(
      borrowerWrappers.claimStakingGainsAndRecycle(th.DUMMY_BYTES32, th._100pct, th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: alice }),
      'BorrowerWrappersScript: caller must have an active cdp'
    )

    const ethBalanceAfter = await web3.eth.getBalance(borrowerOperations.getProxyAddressFromUser(alice))
    const cdpCollAfter = await cdpManager.getTroveColl(th.DUMMY_BYTES32)
    const ebtcBalanceAfter = await ebtcToken.balanceOf(alice)
    const cdpDebtAfter = await cdpManager.getTroveDebt(th.DUMMY_BYTES32)
    const lqtyBalanceAfter = await lqtyToken.balanceOf(alice)
    const ICRAfter = await cdpManager.getCurrentICR(th.DUMMY_BYTES32, price)
    const depositAfter = (await stabilityPool.deposits(alice))[0]
    const stakeAfter = await lqtyStaking.stakes(alice)

    // check everything remains the same
    assert.equal(ethBalanceAfter.toString(), ethBalanceBefore.toString())
    assert.equal(ebtcBalanceAfter.toString(), ebtcBalanceBefore.toString())
    assert.equal(lqtyBalanceAfter.toString(), lqtyBalanceBefore.toString())
    th.assertIsApproximatelyEqual(cdpDebtAfter, cdpDebtBefore, 10000)
    th.assertIsApproximatelyEqual(cdpCollAfter, cdpCollBefore)
    th.assertIsApproximatelyEqual(ICRAfter, ICRBefore)
    th.assertIsApproximatelyEqual(depositAfter, depositBefore, 10000)
    th.assertIsApproximatelyEqual(lqtyBalanceBefore, lqtyBalanceAfter)
    // LQTY staking
    th.assertIsApproximatelyEqual(stakeAfter, stakeBefore)

    // Expect Alice has withdrawn all ETH gain
    const alice_pendingETHGain = await stabilityPool.getDepositorETHGain(alice)
    assert.equal(alice_pendingETHGain, 0)
  })

  it('claimStakingGainsAndRecycle(): with only ETH gain', async () => {
    const price = toBN(dec(200, 18))

    // Whale opens Trove
    await openTrove({ extraEBTCAmount: toBN(dec(1850, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: whale } })

    // Defaulter Trove opened
    const { ebtcAmount, netDebt, collateral } = await openTrove({ ICR: toBN(dec(210, 16)), extraParams: { from: defaulter_1 } })
    const borrowingFee = netDebt.sub(ebtcAmount)

    // alice opens cdp and provides 150 EBTC to StabilityPool
    await openTrove({ extraEBTCAmount: toBN(dec(150, 18)), extraParams: { from: alice } })
    await stabilityPool.provideToSP(dec(150, 18), ZERO_ADDRESS, { from: alice })
    const aliceProxyAddress = borrowerWrappers.getProxyAddressFromUser(alice);
    let _aliceTroveId = await sortedTroves.cdpOfOwnerByIndex(aliceProxyAddress, 0);

    // mint some LQTY
    await lqtyTokenOriginal.unprotectedMint(borrowerOperations.getProxyAddressFromUser(whale), dec(1850, 18))
    await lqtyTokenOriginal.unprotectedMint(borrowerOperations.getProxyAddressFromUser(alice), dec(150, 18))

    // stake LQTY
    await lqtyStaking.stake(dec(1850, 18), { from: whale })
    await lqtyStaking.stake(dec(150, 18), { from: alice })

    // skip bootstrapping phase
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_WEEK * 2, web3.currentProvider)

    // whale redeems 100 EBTC
    const redeemedAmount = toBN(dec(100, 18))
    await th.redeemCollateral(whale, contracts, redeemedAmount, GAS_PRICE)

    // Alice ETH gain is ((150/2000) * (redemption fee over redeemedAmount) / price)
    const redemptionFee = await cdpManager.getRedemptionFeeWithDecay(redeemedAmount)
    const expectedETHGain_A = redemptionFee.mul(toBN(dec(150, 18))).div(toBN(dec(2000, 18))).mul(mv._1e18BN).div(price)

    const ethBalanceBefore = await web3.eth.getBalance(borrowerOperations.getProxyAddressFromUser(alice))
    const cdpCollBefore = await cdpManager.getTroveColl(_aliceTroveId)
    const ebtcBalanceBefore = await ebtcToken.balanceOf(alice)
    const cdpDebtBefore = await cdpManager.getTroveDebt(_aliceTroveId)
    const lqtyBalanceBefore = await lqtyToken.balanceOf(alice)
    const ICRBefore = await cdpManager.getCurrentICR(_aliceTroveId, price)
    const depositBefore = (await stabilityPool.deposits(alice))[0]
    const stakeBefore = await lqtyStaking.stakes(alice)

    const proportionalEBTC = expectedETHGain_A.mul(price).div(ICRBefore)
    const borrowingRate = await cdpManagerOriginal.getBorrowingRateWithDecay()
    const netDebtChange = proportionalEBTC.mul(toBN(dec(1, 18))).div(toBN(dec(1, 18)).add(borrowingRate))

    const expectedLQTYGain_A = toBN('839557069990108416000000')

    const proxyAddress = borrowerWrappers.getProxyAddressFromUser(alice)
    // Alice claims staking rewards and puts them back in the system through the proxy
    await borrowerWrappers.claimStakingGainsAndRecycle(_aliceTroveId, th._100pct, _aliceTroveId, _aliceTroveId, { from: alice })

    // Alice new EBTC gain due to her own Trove adjustment: ((150/2000) * (borrowing fee over netDebtChange))
    const newBorrowingFee = await cdpManagerOriginal.getBorrowingFeeWithDecay(netDebtChange)
    const expectedNewEBTCGain_A = newBorrowingFee.mul(toBN(dec(150, 18))).div(toBN(dec(2000, 18)))

    const ethBalanceAfter = await web3.eth.getBalance(borrowerOperations.getProxyAddressFromUser(alice))
    const cdpCollAfter = await cdpManager.getTroveColl(_aliceTroveId)
    const ebtcBalanceAfter = await ebtcToken.balanceOf(alice)
    const cdpDebtAfter = await cdpManager.getTroveDebt(_aliceTroveId)
    const lqtyBalanceAfter = await lqtyToken.balanceOf(alice)
    const ICRAfter = await cdpManager.getCurrentICR(_aliceTroveId, price)
    const depositAfter = (await stabilityPool.deposits(alice))[0]
    const stakeAfter = await lqtyStaking.stakes(alice)

    // check proxy balances remain the same
    assert.equal(ethBalanceAfter.toString(), ethBalanceBefore.toString())
    assert.equal(lqtyBalanceAfter.toString(), lqtyBalanceBefore.toString())
    // check proxy ebtc balance has increased by own adjust cdp reward
    th.assertIsApproximatelyEqual(ebtcBalanceAfter, ebtcBalanceBefore.add(expectedNewEBTCGain_A))
    // check cdp has increased debt by the ICR proportional amount to ETH gain
    th.assertIsApproximatelyEqual(cdpDebtAfter, cdpDebtBefore.add(proportionalEBTC), 10000)
    // check cdp has increased collateral by the ETH gain
    th.assertIsApproximatelyEqual(cdpCollAfter, cdpCollBefore.add(expectedETHGain_A))
    // check that ICR remains constant
    th.assertIsApproximatelyEqual(ICRAfter, ICRBefore)
    // check that Stability Pool deposit
    th.assertIsApproximatelyEqual(depositAfter, depositBefore.add(netDebtChange), 10000)
    // check lqty balance remains the same
    th.assertIsApproximatelyEqual(lqtyBalanceBefore, lqtyBalanceAfter)

    // LQTY staking
    th.assertIsApproximatelyEqual(stakeAfter, stakeBefore.add(expectedLQTYGain_A))

    // Expect Alice has withdrawn all ETH gain
    const alice_pendingETHGain = await stabilityPool.getDepositorETHGain(alice)
    assert.equal(alice_pendingETHGain, 0)
  })

  it('claimStakingGainsAndRecycle(): with only EBTC gain', async () => {
    const price = toBN(dec(200, 18))

    // Whale opens Trove
    await openTrove({ extraEBTCAmount: toBN(dec(1850, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: whale } })

    // alice opens cdp and provides 150 EBTC to StabilityPool
    await openTrove({ extraEBTCAmount: toBN(dec(150, 18)), extraParams: { from: alice } })
    await stabilityPool.provideToSP(dec(150, 18), ZERO_ADDRESS, { from: alice })
    const aliceProxyAddress = borrowerWrappers.getProxyAddressFromUser(alice);
    let _aliceTroveId = await sortedTroves.cdpOfOwnerByIndex(aliceProxyAddress, 0);

    // mint some LQTY
    await lqtyTokenOriginal.unprotectedMint(borrowerOperations.getProxyAddressFromUser(whale), dec(1850, 18))
    await lqtyTokenOriginal.unprotectedMint(borrowerOperations.getProxyAddressFromUser(alice), dec(150, 18))

    // stake LQTY
    await lqtyStaking.stake(dec(1850, 18), { from: whale })
    await lqtyStaking.stake(dec(150, 18), { from: alice })

    // Defaulter Trove opened
    const { ebtcAmount, netDebt, collateral } = await openTrove({ ICR: toBN(dec(210, 16)), extraParams: { from: defaulter_1 } })
    const borrowingFee = netDebt.sub(ebtcAmount)

    // Alice EBTC gain is ((150/2000) * borrowingFee)
    const expectedEBTCGain_A = borrowingFee.mul(toBN(dec(150, 18))).div(toBN(dec(2000, 18)))

    const ethBalanceBefore = await web3.eth.getBalance(borrowerOperations.getProxyAddressFromUser(alice))
    const cdpCollBefore = await cdpManager.getTroveColl(_aliceTroveId)
    const ebtcBalanceBefore = await ebtcToken.balanceOf(alice)
    const cdpDebtBefore = await cdpManager.getTroveDebt(_aliceTroveId)
    const lqtyBalanceBefore = await lqtyToken.balanceOf(alice)
    const ICRBefore = await cdpManager.getCurrentICR(_aliceTroveId, price)
    const depositBefore = (await stabilityPool.deposits(alice))[0]
    const stakeBefore = await lqtyStaking.stakes(alice)

    const borrowingRate = await cdpManagerOriginal.getBorrowingRateWithDecay()

    // Alice claims staking rewards and puts them back in the system through the proxy
    await borrowerWrappers.claimStakingGainsAndRecycle(_aliceTroveId, th._100pct, _aliceTroveId, _aliceTroveId, { from: alice })

    const ethBalanceAfter = await web3.eth.getBalance(borrowerOperations.getProxyAddressFromUser(alice))
    const cdpCollAfter = await cdpManager.getTroveColl(_aliceTroveId)
    const ebtcBalanceAfter = await ebtcToken.balanceOf(alice)
    const cdpDebtAfter = await cdpManager.getTroveDebt(_aliceTroveId)
    const lqtyBalanceAfter = await lqtyToken.balanceOf(alice)
    const ICRAfter = await cdpManager.getCurrentICR(_aliceTroveId, price)
    const depositAfter = (await stabilityPool.deposits(alice))[0]
    const stakeAfter = await lqtyStaking.stakes(alice)

    // check proxy balances remain the same
    assert.equal(ethBalanceAfter.toString(), ethBalanceBefore.toString())
    assert.equal(lqtyBalanceAfter.toString(), lqtyBalanceBefore.toString())
    // check proxy ebtc balance has increased by own adjust cdp reward
    th.assertIsApproximatelyEqual(ebtcBalanceAfter, ebtcBalanceBefore)
    // check cdp has increased debt by the ICR proportional amount to ETH gain
    th.assertIsApproximatelyEqual(cdpDebtAfter, cdpDebtBefore, 10000)
    // check cdp has increased collateral by the ETH gain
    th.assertIsApproximatelyEqual(cdpCollAfter, cdpCollBefore)
    // check that ICR remains constant
    th.assertIsApproximatelyEqual(ICRAfter, ICRBefore)
    // check that Stability Pool deposit
    th.assertIsApproximatelyEqual(depositAfter, depositBefore.add(expectedEBTCGain_A), 10000)
    // check lqty balance remains the same
    th.assertIsApproximatelyEqual(lqtyBalanceBefore, lqtyBalanceAfter)

    // Expect Alice has withdrawn all ETH gain
    const alice_pendingETHGain = await stabilityPool.getDepositorETHGain(alice)
    assert.equal(alice_pendingETHGain, 0)
  })

  it('claimStakingGainsAndRecycle(): with both ETH and EBTC gains', async () => {
    const price = toBN(dec(200, 18))

    // Whale opens Trove
    await openTrove({ extraEBTCAmount: toBN(dec(1850, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: whale } })

    // alice opens cdp and provides 150 EBTC to StabilityPool
    await openTrove({ extraEBTCAmount: toBN(dec(150, 18)), extraParams: { from: alice } })
    await stabilityPool.provideToSP(dec(150, 18), ZERO_ADDRESS, { from: alice })
    const aliceProxyAddress = borrowerWrappers.getProxyAddressFromUser(alice);
    let _aliceTroveId = await sortedTroves.cdpOfOwnerByIndex(aliceProxyAddress, 0);

    // mint some LQTY
    await lqtyTokenOriginal.unprotectedMint(borrowerOperations.getProxyAddressFromUser(whale), dec(1850, 18))
    await lqtyTokenOriginal.unprotectedMint(borrowerOperations.getProxyAddressFromUser(alice), dec(150, 18))

    // stake LQTY
    await lqtyStaking.stake(dec(1850, 18), { from: whale })
    await lqtyStaking.stake(dec(150, 18), { from: alice })

    // Defaulter Trove opened
    const { ebtcAmount, netDebt, collateral } = await openTrove({ ICR: toBN(dec(210, 16)), extraParams: { from: defaulter_1 } })
    const borrowingFee = netDebt.sub(ebtcAmount)

    // Alice EBTC gain is ((150/2000) * borrowingFee)
    const expectedEBTCGain_A = borrowingFee.mul(toBN(dec(150, 18))).div(toBN(dec(2000, 18)))

    // skip bootstrapping phase
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_WEEK * 2, web3.currentProvider)

    // whale redeems 100 EBTC
    const redeemedAmount = toBN(dec(100, 18))
    await th.redeemCollateral(whale, contracts, redeemedAmount, GAS_PRICE)

    // Alice ETH gain is ((150/2000) * (redemption fee over redeemedAmount) / price)
    const redemptionFee = await cdpManager.getRedemptionFeeWithDecay(redeemedAmount)
    const expectedETHGain_A = redemptionFee.mul(toBN(dec(150, 18))).div(toBN(dec(2000, 18))).mul(mv._1e18BN).div(price)

    const ethBalanceBefore = await web3.eth.getBalance(borrowerOperations.getProxyAddressFromUser(alice))
    const cdpCollBefore = await cdpManager.getTroveColl(_aliceTroveId)
    const ebtcBalanceBefore = await ebtcToken.balanceOf(alice)
    const cdpDebtBefore = await cdpManager.getTroveDebt(_aliceTroveId)
    const lqtyBalanceBefore = await lqtyToken.balanceOf(alice)
    const ICRBefore = await cdpManager.getCurrentICR(_aliceTroveId, price)
    const depositBefore = (await stabilityPool.deposits(alice))[0]
    const stakeBefore = await lqtyStaking.stakes(alice)

    const proportionalEBTC = expectedETHGain_A.mul(price).div(ICRBefore)
    const borrowingRate = await cdpManagerOriginal.getBorrowingRateWithDecay()
    const netDebtChange = proportionalEBTC.mul(toBN(dec(1, 18))).div(toBN(dec(1, 18)).add(borrowingRate))
    const expectedTotalEBTC = expectedEBTCGain_A.add(netDebtChange)

    const expectedLQTYGain_A = toBN('839557069990108416000000')

    // Alice claims staking rewards and puts them back in the system through the proxy
    await borrowerWrappers.claimStakingGainsAndRecycle(_aliceTroveId, th._100pct, _aliceTroveId, _aliceTroveId, { from: alice })

    // Alice new EBTC gain due to her own Trove adjustment: ((150/2000) * (borrowing fee over netDebtChange))
    const newBorrowingFee = await cdpManagerOriginal.getBorrowingFeeWithDecay(netDebtChange)
    const expectedNewEBTCGain_A = newBorrowingFee.mul(toBN(dec(150, 18))).div(toBN(dec(2000, 18)))

    const ethBalanceAfter = await web3.eth.getBalance(borrowerOperations.getProxyAddressFromUser(alice))
    const cdpCollAfter = await cdpManager.getTroveColl(_aliceTroveId)
    const ebtcBalanceAfter = await ebtcToken.balanceOf(alice)
    const cdpDebtAfter = await cdpManager.getTroveDebt(_aliceTroveId)
    const lqtyBalanceAfter = await lqtyToken.balanceOf(alice)
    const ICRAfter = await cdpManager.getCurrentICR(_aliceTroveId, price)
    const depositAfter = (await stabilityPool.deposits(alice))[0]
    const stakeAfter = await lqtyStaking.stakes(alice)

    // check proxy balances remain the same
    assert.equal(ethBalanceAfter.toString(), ethBalanceBefore.toString())
    assert.equal(lqtyBalanceAfter.toString(), lqtyBalanceBefore.toString())
    // check proxy ebtc balance has increased by own adjust cdp reward
    th.assertIsApproximatelyEqual(ebtcBalanceAfter, ebtcBalanceBefore.add(expectedNewEBTCGain_A))
    // check cdp has increased debt by the ICR proportional amount to ETH gain
    th.assertIsApproximatelyEqual(cdpDebtAfter, cdpDebtBefore.add(proportionalEBTC), 10000)
    // check cdp has increased collateral by the ETH gain
    th.assertIsApproximatelyEqual(cdpCollAfter, cdpCollBefore.add(expectedETHGain_A))
    // check that ICR remains constant
    th.assertIsApproximatelyEqual(ICRAfter, ICRBefore)
    // check that Stability Pool deposit
    th.assertIsApproximatelyEqual(depositAfter, depositBefore.add(expectedTotalEBTC), 10000)
    // check lqty balance remains the same
    th.assertIsApproximatelyEqual(lqtyBalanceBefore, lqtyBalanceAfter)

    // LQTY staking
    th.assertIsApproximatelyEqual(stakeAfter, stakeBefore.add(expectedLQTYGain_A))

    // Expect Alice has withdrawn all ETH gain
    const alice_pendingETHGain = await stabilityPool.getDepositorETHGain(alice)
    assert.equal(alice_pendingETHGain, 0)
  })

})
