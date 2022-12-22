const deploymentHelper = require("../utils/deploymentHelpers.js")
const testHelpers = require("../utils/testHelpers.js")

const th = testHelpers.TestHelper
const dec = th.dec
const toBN = th.toBN
const assertRevert = th.assertRevert
const mv = testHelpers.MoneyValues
const timeValues = testHelpers.TimeValues

const CdpManagerTester = artifacts.require("./CdpManagerTester")
const EBTCToken = artifacts.require("./EBTCToken.sol")

const GAS_PRICE = 10000000000 //10 GWEI

const hre = require("hardhat");

contract('CdpManager - in Recovery Mode', async accounts => {
  const _1_Ether = web3.utils.toWei('1', 'ether')
  const _2_Ether = web3.utils.toWei('2', 'ether')
  const _3_Ether = web3.utils.toWei('3', 'ether')
  const _3pt5_Ether = web3.utils.toWei('3.5', 'ether')
  const _6_Ether = web3.utils.toWei('6', 'ether')
  const _10_Ether = web3.utils.toWei('10', 'ether')
  const _20_Ether = web3.utils.toWei('20', 'ether')
  const _21_Ether = web3.utils.toWei('21', 'ether')
  const _22_Ether = web3.utils.toWei('22', 'ether')
  const _24_Ether = web3.utils.toWei('24', 'ether')
  const _25_Ether = web3.utils.toWei('25', 'ether')
  const _30_Ether = web3.utils.toWei('30', 'ether')

  const ZERO_ADDRESS = th.ZERO_ADDRESS
  let [
    owner,
    alice, bob, carol, dennis, erin, freddy, greta, harry, ida,
    whale, defaulter_1, defaulter_2, defaulter_3, defaulter_4,
    A, B, C, D, E, F, G, H, I] = accounts;

    const [bountyAddress, lpRewardsAddress, multisig] = accounts.slice(accounts.length - 3, accounts.length)
    const beadp = "0x00000000219ab540356cBB839Cbe05303d7705Fa";//beacon deposit
    let beadpSigner;

  let priceFeed
  let ebtcToken
  let sortedCdps
  let cdpManager
  let activePool
  let stabilityPool
  let defaultPool
  let functionCaller
  let borrowerOperations
  let collSurplusPool

  let contracts

  const getOpenCdpEBTCAmount = async (totalDebt) => th.getOpenCdpEBTCAmount(contracts, totalDebt)
  const getNetBorrowingAmount = async (debtWithFee) => th.getNetBorrowingAmount(contracts, debtWithFee)
  const openCdp = async (params) => th.openCdp(contracts, params)

  before(async () => {	  
    // let _forkBlock = hre.network.config['forking']['blockNumber'];
    // let _forkUrl = hre.network.config['forking']['url'];
    // console.log("resetting to mainnet fork: block=" + _forkBlock + ',url=' + _forkUrl);
    // await hre.network.provider.request({ method: "hardhat_reset", params: [ { forking: { jsonRpcUrl: _forkUrl, blockNumber: _forkBlock }} ] });
    await hre.network.provider.request({method: "hardhat_impersonateAccount", params: [beadp]}); 
    beadpSigner = await ethers.provider.getSigner(beadp);	
  })

  beforeEach(async () => {
    contracts = await deploymentHelper.deployTesterContractsHardhat()
    contracts.cdpManager = await CdpManagerTester.new()
    contracts.ebtcToken = await EBTCToken.new(
      contracts.cdpManager.address,
      contracts.stabilityPool.address,
      contracts.borrowerOperations.address
    )
    const LQTYContracts = await deploymentHelper.deployLQTYContracts(bountyAddress, lpRewardsAddress, multisig)

    priceFeed = contracts.priceFeedTestnet
    ebtcToken = contracts.ebtcToken
    sortedCdps = contracts.sortedCdps
    cdpManager = contracts.cdpManager
    activePool = contracts.activePool
    stabilityPool = contracts.stabilityPool
    defaultPool = contracts.defaultPool
    functionCaller = contracts.functionCaller
    borrowerOperations = contracts.borrowerOperations
    collSurplusPool = contracts.collSurplusPool

    await deploymentHelper.connectLQTYContracts(LQTYContracts)
    await deploymentHelper.connectCoreContracts(contracts, LQTYContracts)
    await deploymentHelper.connectLQTYContractsToCore(LQTYContracts, contracts)

    ownerSigner = await ethers.provider.getSigner(owner);
    let _signer = ownerSigner;
  
    await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("1000")});
    await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("1000")});
    await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("1000")});
    await _signer.sendTransaction({ to: carol, value: ethers.utils.parseEther("1000")});

    await _signer.sendTransaction({ to: beadp, value: ethers.utils.parseEther("2000000")});
  })

  it("checkRecoveryMode(): Returns true if TCR falls below CCR", async () => {
    // --- SETUP ---
    //  Alice and Bob withdraw such that the TCR is ~150%
    await openCdp({ ICR: toBN(dec(150, 16)), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(150, 16)), extraParams: { from: bob } })

    const TCR = (await th.getTCR(contracts)).toString()
    assert.equal(TCR, dec(15, 17))

    const recoveryMode_Before = await th.checkRecoveryMode(contracts);
    assert.isFalse(recoveryMode_Before)

    // --- TEST ---

    // price drops to 1ETH:150EBTC, reducing TCR below 150%.  setPrice() calls checkTCRAndSetRecoveryMode() internally.
    await priceFeed.setPrice(dec(15, 17))

    // const price = await priceFeed.getPrice()
    // await cdpManager.checkTCRAndSetRecoveryMode(price)

    const recoveryMode_After = await th.checkRecoveryMode(contracts);
    assert.isTrue(recoveryMode_After)
  })

  it("checkRecoveryMode(): Returns true if TCR stays less than CCR", async () => {
    // --- SETUP ---
    await openCdp({ ICR: toBN(dec(150, 16)), extraParams: { from: alice } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    await openCdp({ ICR: toBN(dec(150, 16)), extraParams: { from: bob } })

    const TCR = (await th.getTCR(contracts)).toString()
    assert.equal(TCR, '1500000000000000000')

    // --- TEST ---

    // price drops to 1ETH:150EBTC, reducing TCR below 150%
    await priceFeed.setPrice('150000000000000000000')

    const recoveryMode_Before = await th.checkRecoveryMode(contracts);
    assert.isTrue(recoveryMode_Before)

    await borrowerOperations.addColl(_aliceCdpId, _aliceCdpId, _aliceCdpId, { from: alice, value: '1' })

    const recoveryMode_After = await th.checkRecoveryMode(contracts);
    assert.isTrue(recoveryMode_After)
  })

  it("checkRecoveryMode(): returns false if TCR stays above CCR", async () => {
    // --- SETUP ---
    await openCdp({ ICR: toBN(dec(450, 16)), extraParams: { from: alice } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    await openCdp({ ICR: toBN(dec(150, 16)), extraParams: { from: bob } })

    // --- TEST ---
    const recoveryMode_Before = await th.checkRecoveryMode(contracts);
    assert.isFalse(recoveryMode_Before)

    await borrowerOperations.withdrawColl(_aliceCdpId, _1_Ether, _aliceCdpId, _aliceCdpId, { from: alice })

    const recoveryMode_After = await th.checkRecoveryMode(contracts);
    assert.isFalse(recoveryMode_After)
  })

  it("checkRecoveryMode(): returns false if TCR rises above CCR", async () => {
    // --- SETUP ---
    const { collateral: A_coll } = await openCdp({ ICR: toBN(dec(150, 16)), extraParams: { from: alice } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    await openCdp({ ICR: toBN(dec(150, 16)), extraParams: { from: bob } })

    const TCR = (await th.getTCR(contracts)).toString()
    assert.equal(TCR, '1500000000000000000')

    // --- TEST ---
    // price drops to 1ETH:150EBTC, reducing TCR below 150%
    await priceFeed.setPrice('150000000000000000000')

    const recoveryMode_Before = await th.checkRecoveryMode(contracts);
    assert.isTrue(recoveryMode_Before)

    await borrowerOperations.addColl(_aliceCdpId, _aliceCdpId, _aliceCdpId, { from: alice, value: A_coll })

    const recoveryMode_After = await th.checkRecoveryMode(contracts);
    assert.isFalse(recoveryMode_After)
  })

  // --- liquidate() with ICR < 100% ---

  it("liquidate(), with ICR < 100%: removes stake and updates totalStakes", async () => {
    // --- SETUP ---
    //  Alice and Bob withdraw such that the TCR is ~150%
    const { collateral: A_coll } = await openCdp({ ICR: toBN(dec(150, 16)), extraParams: { from: alice } })
    const { collateral: B_coll } = await openCdp({ ICR: toBN(dec(150, 16)), extraEBTCAmount: dec(2000, 18), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);

    const TCR = (await th.getTCR(contracts)).toString()
    assert.equal(TCR, '1500000000000000000')


    const bob_Stake_Before = (await cdpManager.Cdps(_bobCdpId))[2]
    const totalStakes_Before = await cdpManager.totalStakes()

    assert.equal(bob_Stake_Before.toString(), B_coll)
    assert.equal(totalStakes_Before.toString(), A_coll.add(B_coll))

    // --- TEST ---
    // price drops to 1ETH:100EBTC, reducing TCR below 150%
    await priceFeed.setPrice('100000000000000000000')
    const price = await priceFeed.getPrice()

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // check Bob's ICR falls to 75%
    const bob_ICR = await cdpManager.getCurrentICR(_bobCdpId, price);
    assert.equal(bob_ICR, '750000000000000000')

    // Liquidate Bob
    await cdpManager.liquidate(_bobCdpId, { from: owner })

    const bob_Stake_After = (await cdpManager.Cdps(_bobCdpId))[2]
    const totalStakes_After = await cdpManager.totalStakes()

    assert.equal(bob_Stake_After, 0)
    assert.equal(totalStakes_After.toString(), A_coll)
  })

  it("liquidate(), with ICR < 100%: updates system snapshots correctly", async () => {
    // --- SETUP ---
    //  Alice, Bob and Dennis withdraw such that their ICRs and the TCR is ~150%
    const { collateral: A_coll } = await openCdp({ ICR: toBN(dec(150, 16)), extraParams: { from: alice } })
    const { collateral: B_coll } = await openCdp({ ICR: toBN(dec(150, 16)), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    const { collateral: D_coll } = await openCdp({ ICR: toBN(dec(150, 16)), extraParams: { from: dennis } })
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);

    const TCR = (await th.getTCR(contracts)).toString()
    assert.equal(TCR, '1500000000000000000')

    // --- TEST ---
    // price drops to 1ETH:100EBTC, reducing TCR below 150%, and all Cdps below 100% ICR
    await priceFeed.setPrice('100000000000000000000')

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // Dennis is liquidated
    await cdpManager.liquidate(_dennisCdpId, { from: owner })

    const totalStakesSnaphot_before = (await cdpManager.totalStakesSnapshot()).toString()
    const totalCollateralSnapshot_before = (await cdpManager.totalCollateralSnapshot()).toString()

    assert.equal(totalStakesSnaphot_before, A_coll.add(B_coll))
    assert.equal(totalCollateralSnapshot_before, A_coll.add(B_coll).add(th.applyLiquidationFee(D_coll))) // 6 + 3*0.995

    const A_reward  = th.applyLiquidationFee(D_coll).mul(A_coll).div(A_coll.add(B_coll))
    const B_reward  = th.applyLiquidationFee(D_coll).mul(B_coll).div(A_coll.add(B_coll))

    // Liquidate Bob
    await cdpManager.liquidate(_bobCdpId, { from: owner })

    const totalStakesSnaphot_After = (await cdpManager.totalStakesSnapshot())
    const totalCollateralSnapshot_After = (await cdpManager.totalCollateralSnapshot())

    assert.equal(totalStakesSnaphot_After.toString(), A_coll)
    // total collateral should always be 9 minus gas compensations, as all liquidations in this test case are full redistributions
    assert.isAtMost(th.getDifference(totalCollateralSnapshot_After, A_coll.add(A_reward).add(th.applyLiquidationFee(B_coll.add(B_reward)))), 1000) // 3 + 4.5*0.995 + 1.5*0.995^2
  })

  it("liquidate(), with ICR < 100%: closes the Cdp and removes it from the Cdp array", async () => {
    // --- SETUP ---
    //  Alice and Bob withdraw such that the TCR is ~150%
    await openCdp({ ICR: toBN(dec(150, 16)), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(150, 16)), extraEBTCAmount: dec(2000, 18), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);

    const TCR = (await th.getTCR(contracts)).toString()
    assert.equal(TCR, '1500000000000000000')

    const bob_CdpStatus_Before = (await cdpManager.Cdps(_bobCdpId))[3]
    const bob_Cdp_isInSortedList_Before = await sortedCdps.contains(_bobCdpId)

    assert.equal(bob_CdpStatus_Before, 1) // status enum element 1 corresponds to "Active"
    assert.isTrue(bob_Cdp_isInSortedList_Before)

    // --- TEST ---
    // price drops to 1ETH:100EBTC, reducing TCR below 150%
    await priceFeed.setPrice('100000000000000000000')
    const price = await priceFeed.getPrice()

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // check Bob's ICR falls to 75%
    const bob_ICR = await cdpManager.getCurrentICR(_bobCdpId, price);
    assert.equal(bob_ICR, '750000000000000000')

    // Liquidate Bob
    await cdpManager.liquidate(_bobCdpId, { from: owner })

    // check Bob's Cdp is successfully closed, and removed from sortedList
    const bob_CdpStatus_After = (await cdpManager.Cdps(_bobCdpId))[3]
    const bob_Cdp_isInSortedList_After = await sortedCdps.contains(_bobCdpId)
    assert.equal(bob_CdpStatus_After, 3)  // status enum element 3 corresponds to "Closed by liquidation"
    assert.isFalse(bob_Cdp_isInSortedList_After)
  })

  it("liquidate(), with ICR < 100%: only redistributes to active Cdps - no offset to Stability Pool", async () => {
    // --- SETUP ---
    //  Alice, Bob and Dennis withdraw such that their ICRs and the TCR is ~150%
    const spDeposit = toBN(dec(390, 18))
    const { collateral: A_coll } = await openCdp({ ICR: toBN(dec(150, 16)), extraEBTCAmount: spDeposit, extraParams: { from: alice } })
    const { collateral: B_coll } = await openCdp({ ICR: toBN(dec(150, 16)), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    const { collateral: D_coll } = await openCdp({ ICR: toBN(dec(150, 16)), extraParams: { from: dennis } })

    // Alice deposits to SP
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: alice })

    // check rewards-per-unit-staked before
    const P_Before = (await stabilityPool.P()).toString()

    assert.equal(P_Before, '1000000000000000000')

    // const TCR = (await th.getTCR(contracts)).toString()
    // assert.equal(TCR, '1500000000000000000')

    // --- TEST ---
    // price drops to 1ETH:100EBTC, reducing TCR below 150%, and all Cdps below 100% ICR
    await priceFeed.setPrice('100000000000000000000')

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // liquidate bob
    await cdpManager.liquidate(_bobCdpId, { from: owner })

    // check SP rewards-per-unit-staked after liquidation - should be no increase
    const P_After = (await stabilityPool.P()).toString()

    assert.equal(P_After, '1000000000000000000')
  })

  // --- liquidate() with 100% < ICR < 110%

  it("liquidate(), with 100 < ICR < 110%: removes stake and updates totalStakes", async () => {
    // --- SETUP ---
    //  Bob withdraws up to 2000 EBTC of debt, bringing his ICR to 210%
    const { collateral: A_coll, totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(150, 16)), extraParams: { from: alice } })
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(210, 16)), extraEBTCAmount: dec(2000, 18), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);

    let price = await priceFeed.getPrice()
    // Total TCR = 24*200/2050 = 234%
    const TCR = await th.getTCR(contracts)
    assert.isAtMost(th.getDifference(TCR, A_coll.add(B_coll).mul(price).div(A_totalDebt.add(B_totalDebt))), 1000)

    const bob_Stake_Before = (await cdpManager.Cdps(_bobCdpId))[2]
    const totalStakes_Before = await cdpManager.totalStakes()

    assert.equal(bob_Stake_Before.toString(), B_coll)
    assert.equal(totalStakes_Before.toString(), A_coll.add(B_coll))

    // --- TEST ---
    // price drops to 1ETH:100EBTC, reducing TCR to 117%
    await priceFeed.setPrice('100000000000000000000')
    price = await priceFeed.getPrice()

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // check Bob's ICR falls to 105%
    const bob_ICR = await cdpManager.getCurrentICR(_bobCdpId, price);
    assert.equal(bob_ICR, '1050000000000000000')

    // Liquidate Bob
    await cdpManager.liquidate(_bobCdpId, { from: owner })

    const bob_Stake_After = (await cdpManager.Cdps(_bobCdpId))[2]
    const totalStakes_After = await cdpManager.totalStakes()

    assert.equal(bob_Stake_After, 0)
    assert.equal(totalStakes_After.toString(), A_coll)
  })

  it("liquidate(), with 100% < ICR < 110%: updates system snapshots correctly", async () => {
    // --- SETUP ---
    //  Alice and Dennis withdraw such that their ICR is ~150%
    //  Bob withdraws up to 20000 EBTC of debt, bringing his ICR to 210%
    const { collateral: A_coll, totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(150, 16)), extraParams: { from: alice } })
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(210, 16)), extraEBTCAmount: dec(20000, 18), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    const { collateral: D_coll } = await openCdp({ ICR: toBN(dec(150, 16)), extraParams: { from: dennis } })
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);

    const totalStakesSnaphot_1 = (await cdpManager.totalStakesSnapshot()).toString()
    const totalCollateralSnapshot_1 = (await cdpManager.totalCollateralSnapshot()).toString()
    assert.equal(totalStakesSnaphot_1, 0)
    assert.equal(totalCollateralSnapshot_1, 0)

    // --- TEST ---
    // price drops to 1ETH:100EBTC, reducing TCR below 150%, and all Cdps below 100% ICR
    await priceFeed.setPrice('100000000000000000000')
    const price = await priceFeed.getPrice()

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // Dennis is liquidated
    await cdpManager.liquidate(_dennisCdpId, { from: owner })

    const A_reward  = th.applyLiquidationFee(D_coll).mul(A_coll).div(A_coll.add(B_coll))
    const B_reward  = th.applyLiquidationFee(D_coll).mul(B_coll).div(A_coll.add(B_coll))

    /*
    Prior to Dennis liquidation, total stakes and total collateral were each 27 ether. 
  
    Check snapshots. Dennis' liquidated collateral is distributed and remains in the system. His 
    stake is removed, leaving 24+3*0.995 ether total collateral, and 24 ether total stakes. */

    const totalStakesSnaphot_2 = (await cdpManager.totalStakesSnapshot()).toString()
    const totalCollateralSnapshot_2 = (await cdpManager.totalCollateralSnapshot()).toString()
    assert.equal(totalStakesSnaphot_2, A_coll.add(B_coll))
    assert.equal(totalCollateralSnapshot_2, A_coll.add(B_coll).add(th.applyLiquidationFee(D_coll))) // 24 + 3*0.995

    // check Bob's ICR is now in range 100% < ICR 110%
    const _110percent = web3.utils.toBN('1100000000000000000')
    const _100percent = web3.utils.toBN('1000000000000000000')

    const bob_ICR = (await cdpManager.getCurrentICR(_bobCdpId, price))

    assert.isTrue(bob_ICR.lt(_110percent))
    assert.isTrue(bob_ICR.gt(_100percent))

    // Liquidate Bob
    await cdpManager.liquidate(_bobCdpId, { from: owner })

    /* After Bob's liquidation, Bob's stake (21 ether) should be removed from total stakes, 
    but his collateral should remain in the system (*0.995). */
    const totalStakesSnaphot_3 = (await cdpManager.totalStakesSnapshot())
    const totalCollateralSnapshot_3 = (await cdpManager.totalCollateralSnapshot())
    assert.equal(totalStakesSnaphot_3.toString(), A_coll)
    // total collateral should always be 27 minus gas compensations, as all liquidations in this test case are full redistributions
    assert.isAtMost(th.getDifference(totalCollateralSnapshot_3.toString(), A_coll.add(A_reward).add(th.applyLiquidationFee(B_coll.add(B_reward)))), 1000)
  })

  it("liquidate(), with 100% < ICR < 110%: closes the Cdp and removes it from the Cdp array", async () => {
    // --- SETUP ---
    //  Bob withdraws up to 2000 EBTC of debt, bringing his ICR to 210%
    const { collateral: A_coll, totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(150, 16)), extraParams: { from: alice } })
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(210, 16)), extraEBTCAmount: dec(2000, 18), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);

    const bob_CdpStatus_Before = (await cdpManager.Cdps(_bobCdpId))[3]
    const bob_Cdp_isInSortedList_Before = await sortedCdps.contains(_bobCdpId)

    assert.equal(bob_CdpStatus_Before, 1) // status enum element 1 corresponds to "Active"
    assert.isTrue(bob_Cdp_isInSortedList_Before)

    // --- TEST ---
    // price drops to 1ETH:100EBTC, reducing TCR below 150%
    await priceFeed.setPrice('100000000000000000000')
    const price = await priceFeed.getPrice()


    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // check Bob's ICR has fallen to 105%
    const bob_ICR = await cdpManager.getCurrentICR(_bobCdpId, price);
    assert.equal(bob_ICR, '1050000000000000000')

    // Liquidate Bob
    await cdpManager.liquidate(_bobCdpId, { from: owner })

    // check Bob's Cdp is successfully closed, and removed from sortedList
    const bob_CdpStatus_After = (await cdpManager.Cdps(_bobCdpId))[3]
    const bob_Cdp_isInSortedList_After = await sortedCdps.contains(_bobCdpId)
    assert.equal(bob_CdpStatus_After, 3)  // status enum element 3 corresponds to "Closed by liquidation"
    assert.isFalse(bob_Cdp_isInSortedList_After)
  })

  it("liquidate(), with 100% < ICR < 110%: offsets as much debt as possible with the Stability Pool, then redistributes the remainder coll and debt", async () => {
    // --- SETUP ---
    //  Alice and Dennis withdraw such that their ICR is ~150%
    //  Bob withdraws up to 2000 EBTC of debt, bringing his ICR to 210%
    const spDeposit = toBN(dec(390, 18))
    const { collateral: A_coll } = await openCdp({ ICR: toBN(dec(150, 16)), extraEBTCAmount: spDeposit, extraParams: { from: alice } })
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(210, 16)), extraEBTCAmount: dec(2000, 18), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    const { collateral: D_coll } = await openCdp({ ICR: toBN(dec(150, 16)), extraParams: { from: dennis } })

    // Alice deposits 390EBTC to the Stability Pool
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: alice })

    // --- TEST ---
    // price drops to 1ETH:100EBTC, reducing TCR below 150%
    await priceFeed.setPrice('100000000000000000000')
    const price = await priceFeed.getPrice()

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // check Bob's ICR has fallen to 105%
    const bob_ICR = await cdpManager.getCurrentICR(_bobCdpId, price);
    assert.equal(bob_ICR, '1050000000000000000')

    // check pool EBTC before liquidation
    const stabilityPoolEBTC_Before = (await stabilityPool.getTotalEBTCDeposits()).toString()
    assert.equal(stabilityPoolEBTC_Before, '390000000000000000000')

    // check Pool reward term before liquidation
    const P_Before = (await stabilityPool.P()).toString()

    assert.equal(P_Before, '1000000000000000000')

    /* Now, liquidate Bob. Liquidated coll is 21 ether, and liquidated debt is 2000 EBTC.
    
    With 390 EBTC in the StabilityPool, 390 EBTC should be offset with the pool, leaving 0 in the pool.
  
    Stability Pool rewards for alice should be:
    EBTCLoss: 390EBTC
    ETHGain: (390 / 2000) * 21*0.995 = 4.074525 ether

    After offsetting 390 EBTC and 4.074525 ether, the remainders - 1610 EBTC and 16.820475 ether - should be redistributed to all active Cdps.
   */
    // Liquidate Bob
    await cdpManager.liquidate(_bobCdpId, { from: owner })

    const aliceDeposit = await stabilityPool.getCompoundedEBTCDeposit(alice)
    const aliceETHGain = await stabilityPool.getDepositorETHGain(alice)
    const aliceExpectedETHGain = spDeposit.mul(th.applyLiquidationFee(B_coll)).div(B_totalDebt)

    assert.equal(aliceDeposit.toString(), 0)
    assert.equal(aliceETHGain.toString(), aliceExpectedETHGain)

    /* Now, check redistribution to active Cdps. Remainders of 1610 EBTC and 16.82 ether are distributed.
    
    Now, only Alice and Dennis have a stake in the system - 3 ether each, thus total stakes is 6 ether.
  
    Rewards-per-unit-staked from the redistribution should be:
  
    L_EBTCDebt = 1610 / 6 = 268.333 EBTC
    L_ETH = 16.820475 /6 =  2.8034125 ether
    */
    const L_EBTCDebt = (await cdpManager.L_EBTCDebt()).toString()
    const L_ETH = (await cdpManager.L_ETH()).toString()

    assert.isAtMost(th.getDifference(L_EBTCDebt, B_totalDebt.sub(spDeposit).mul(mv._1e18BN).div(A_coll.add(D_coll))), 100)
    assert.isAtMost(th.getDifference(L_ETH, th.applyLiquidationFee(B_coll.sub(B_coll.mul(spDeposit).div(B_totalDebt)).mul(mv._1e18BN).div(A_coll.add(D_coll)))), 100)
  })

  // --- liquidate(), applied to cdp with ICR > 110% that has the lowest ICR 

  it("liquidate(), with ICR > 110%, cdp has lowest ICR, and StabilityPool is empty: does nothing", async () => {
    // --- SETUP ---
    // Alice and Dennis withdraw, resulting in ICRs of 266%. 
    // Bob withdraws, resulting in ICR of 240%. Bob has lowest ICR.
    const { collateral: A_coll } = await openCdp({ ICR: toBN(dec(266, 16)), extraParams: { from: alice } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(240, 16)), extraEBTCAmount: dec(2000, 18), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    const { collateral: D_coll } = await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: dec(2000, 18), extraParams: { from: dennis } })
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);

    // --- TEST ---
    // price drops to 1ETH:100EBTC, reducing TCR below 150%
    await priceFeed.setPrice('100000000000000000000')
    const price = await priceFeed.getPrice()

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // Check Bob's ICR is >110% but still lowest
    const bob_ICR = (await cdpManager.getCurrentICR(_bobCdpId, price)).toString()
    const alice_ICR = (await cdpManager.getCurrentICR(_aliceCdpId, price)).toString()
    const dennis_ICR = (await cdpManager.getCurrentICR(_dennisCdpId, price)).toString()
    assert.equal(bob_ICR, '1200000000000000000')
    assert.equal(alice_ICR, dec(133, 16))
    assert.equal(dennis_ICR, dec(133, 16))

    // console.log(`TCR: ${await th.getTCR(contracts)}`)
    // Try to liquidate Bob
    await assertRevert(cdpManager.liquidate(_bobCdpId, { from: owner }), "CdpManager: nothing to liquidate")

    // Check that Pool rewards don't change
    const P_Before = (await stabilityPool.P()).toString()

    assert.equal(P_Before, '1000000000000000000')

    // Check that redistribution rewards don't change
    const L_EBTCDebt = (await cdpManager.L_EBTCDebt()).toString()
    const L_ETH = (await cdpManager.L_ETH()).toString()

    assert.equal(L_EBTCDebt, '0')
    assert.equal(L_ETH, '0')

    // Check that Bob's Cdp and stake remains active with unchanged coll and debt
    const bob_Cdp = await cdpManager.Cdps(_bobCdpId);
    const bob_Debt = bob_Cdp[0].toString()
    const bob_Coll = bob_Cdp[1].toString()
    const bob_Stake = bob_Cdp[2].toString()
    const bob_CdpStatus = bob_Cdp[3].toString()
    const bob_isInSortedCdpsList = await sortedCdps.contains(_bobCdpId)

    th.assertIsApproximatelyEqual(bob_Debt.toString(), B_totalDebt)
    assert.equal(bob_Coll.toString(), B_coll)
    assert.equal(bob_Stake.toString(), B_coll)
    assert.equal(bob_CdpStatus, '1')
    assert.isTrue(bob_isInSortedCdpsList)
  })

  // --- liquidate(), applied to cdp with ICR > 110% that has the lowest ICR, and Stability Pool EBTC is GREATER THAN liquidated debt ---

  it("liquidate(), with 110% < ICR < TCR, and StabilityPool EBTC > debt to liquidate: offsets the cdp entirely with the pool", async () => {
    // --- SETUP ---
    // Alice withdraws up to 1500 EBTC of debt, and Dennis up to 150, resulting in ICRs of 266%.
    // Bob withdraws up to 250 EBTC of debt, resulting in ICR of 240%. Bob has lowest ICR.
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(240, 16)), extraEBTCAmount: dec(250, 18), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    const { collateral: A_coll } = await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: B_totalDebt, extraParams: { from: alice } })
    const { collateral: D_coll } = await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: dec(2000, 18), extraParams: { from: dennis } })

    // Alice deposits EBTC in the Stability Pool
    const spDeposit = B_totalDebt.add(toBN(1))
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: alice })

    // --- TEST ---
    // price drops to 1ETH:100EBTC, reducing TCR below 150%
    await priceFeed.setPrice('100000000000000000000')
    const price = await priceFeed.getPrice()
    const TCR = await th.getTCR(contracts)

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // Check Bob's ICR is between 110 and TCR
    const bob_ICR = await cdpManager.getCurrentICR(_bobCdpId, price)
    assert.isTrue(bob_ICR.gt(mv._MCR) && bob_ICR.lt(TCR))

    // Liquidate Bob
    await cdpManager.liquidate(_bobCdpId, { from: owner })

    /* Check accrued Stability Pool rewards after. Total Pool deposits was 1490 EBTC, Alice sole depositor.
    As liquidated debt (250 EBTC) was completely offset

    Alice's expected compounded deposit: (1490 - 250) = 1240EBTC
    Alice's expected ETH gain:  Bob's liquidated capped coll (minus gas comp), 2.75*0.995 ether
  
    */
    const aliceExpectedDeposit = await stabilityPool.getCompoundedEBTCDeposit(alice)
    const aliceExpectedETHGain = await stabilityPool.getDepositorETHGain(alice)

    assert.isAtMost(th.getDifference(aliceExpectedDeposit.toString(), spDeposit.sub(B_totalDebt)), 2000)
    assert.isAtMost(th.getDifference(aliceExpectedETHGain, th.applyLiquidationFee(B_totalDebt.mul(th.toBN(dec(11, 17))).div(price))), 3000)

    // check Bob’s collateral surplus
    const bob_remainingCollateral = B_coll.sub(B_totalDebt.mul(th.toBN(dec(11, 17))).div(price))
    th.assertIsApproximatelyEqual(await collSurplusPool.getCollateral(bob), bob_remainingCollateral)
    // can claim collateral
    const bob_balanceBefore = th.toBN(await web3.eth.getBalance(bob))
    const BOB_GAS = th.gasUsed(await borrowerOperations.claimCollateral({ from: bob, gasPrice: GAS_PRICE  }))
    const bob_expectedBalance = bob_balanceBefore.sub(th.toBN(BOB_GAS * GAS_PRICE))
    const bob_balanceAfter = th.toBN(await web3.eth.getBalance(bob))
    th.assertIsApproximatelyEqual(bob_balanceAfter, bob_expectedBalance.add(th.toBN(bob_remainingCollateral)))
  })

  it("liquidate(), with ICR% = 110 < TCR, and StabilityPool EBTC > debt to liquidate: offsets the cdp entirely with the pool, there’s no collateral surplus", async () => {
    // --- SETUP ---
    // Alice withdraws up to 1500 EBTC of debt, and Dennis up to 150, resulting in ICRs of 266%.
    // Bob withdraws up to 250 EBTC of debt, resulting in ICR of 220%. Bob has lowest ICR.
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(220, 16)), extraEBTCAmount: dec(250, 18), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    const { collateral: A_coll } = await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: B_totalDebt, extraParams: { from: alice } })
    const { collateral: D_coll } = await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: dec(2000, 18), extraParams: { from: dennis } })

    // Alice deposits EBTC in the Stability Pool
    const spDeposit = B_totalDebt.add(toBN(1))
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: alice })

    // --- TEST ---
    // price drops to 1ETH:100EBTC, reducing TCR below 150%
    await priceFeed.setPrice('100000000000000000000')
    const price = await priceFeed.getPrice()
    const TCR = await th.getTCR(contracts)

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // Check Bob's ICR = 110
    const bob_ICR = await cdpManager.getCurrentICR(_bobCdpId, price)
    assert.isTrue(bob_ICR.eq(mv._MCR))

    // Liquidate Bob
    await cdpManager.liquidate(_bobCdpId, { from: owner })

    /* Check accrued Stability Pool rewards after. Total Pool deposits was 1490 EBTC, Alice sole depositor.
    As liquidated debt (250 EBTC) was completely offset

    Alice's expected compounded deposit: (1490 - 250) = 1240EBTC
    Alice's expected ETH gain:  Bob's liquidated capped coll (minus gas comp), 2.75*0.995 ether

    */
    const aliceExpectedDeposit = await stabilityPool.getCompoundedEBTCDeposit(alice)
    const aliceExpectedETHGain = await stabilityPool.getDepositorETHGain(alice)

    assert.isAtMost(th.getDifference(aliceExpectedDeposit.toString(), spDeposit.sub(B_totalDebt)), 2000)
    assert.isAtMost(th.getDifference(aliceExpectedETHGain, th.applyLiquidationFee(B_totalDebt.mul(th.toBN(dec(11, 17))).div(price))), 3000)

    // check Bob’s collateral surplus
    th.assertIsApproximatelyEqual(await collSurplusPool.getCollateral(bob), '0')
  })

  it("liquidate(), with  110% < ICR < TCR, and StabilityPool EBTC > debt to liquidate: removes stake and updates totalStakes", async () => {
    // --- SETUP ---
    // Alice withdraws up to 1500 EBTC of debt, and Dennis up to 150, resulting in ICRs of 266%.
    // Bob withdraws up to 250 EBTC of debt, resulting in ICR of 240%. Bob has lowest ICR.
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(240, 16)), extraEBTCAmount: dec(250, 18), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    const { collateral: A_coll } = await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: B_totalDebt, extraParams: { from: alice } })
    const { collateral: D_coll } = await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: dec(2000, 18), extraParams: { from: dennis } })

    // Alice deposits EBTC in the Stability Pool
    await stabilityPool.provideToSP(B_totalDebt.add(toBN(1)), ZERO_ADDRESS, { from: alice })

    // --- TEST ---
    // price drops to 1ETH:100EBTC, reducing TCR below 150%
    await priceFeed.setPrice('100000000000000000000')
    const price = await priceFeed.getPrice()

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // check stake and totalStakes before
    const bob_Stake_Before = (await cdpManager.Cdps(_bobCdpId))[2]
    const totalStakes_Before = await cdpManager.totalStakes()

    assert.equal(bob_Stake_Before.toString(), B_coll)
    assert.equal(totalStakes_Before.toString(), A_coll.add(B_coll).add(D_coll))

    // Check Bob's ICR is between 110 and 150
    const bob_ICR = await cdpManager.getCurrentICR(_bobCdpId, price)
    assert.isTrue(bob_ICR.gt(mv._MCR) && bob_ICR.lt(await th.getTCR(contracts)))

    // Liquidate Bob
    await cdpManager.liquidate(_bobCdpId, { from: owner })

    // check stake and totalStakes after
    const bob_Stake_After = (await cdpManager.Cdps(_bobCdpId))[2]
    const totalStakes_After = await cdpManager.totalStakes()

    assert.equal(bob_Stake_After, 0)
    assert.equal(totalStakes_After.toString(), A_coll.add(D_coll))

    // check Bob’s collateral surplus
    const bob_remainingCollateral = B_coll.sub(B_totalDebt.mul(th.toBN(dec(11, 17))).div(price))
    th.assertIsApproximatelyEqual(await collSurplusPool.getCollateral(bob), bob_remainingCollateral)
    // can claim collateral
    const bob_balanceBefore = th.toBN(await web3.eth.getBalance(bob))
    const BOB_GAS = th.gasUsed(await borrowerOperations.claimCollateral({ from: bob, gasPrice: GAS_PRICE  }))
    const bob_expectedBalance = bob_balanceBefore.sub(th.toBN(BOB_GAS * GAS_PRICE))
    const bob_balanceAfter = th.toBN(await web3.eth.getBalance(bob))
    th.assertIsApproximatelyEqual(bob_balanceAfter, bob_expectedBalance.add(th.toBN(bob_remainingCollateral)))
  })

  it("liquidate(), with  110% < ICR < TCR, and StabilityPool EBTC > debt to liquidate: updates system snapshots", async () => {
    // --- SETUP ---
    // Alice withdraws up to 1500 EBTC of debt, and Dennis up to 150, resulting in ICRs of 266%.
    // Bob withdraws up to 250 EBTC of debt, resulting in ICR of 240%. Bob has lowest ICR.
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(240, 16)), extraEBTCAmount: dec(250, 18), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    const { collateral: A_coll } = await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: B_totalDebt, extraParams: { from: alice } })
    const { collateral: D_coll } = await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: dec(2000, 18), extraParams: { from: dennis } })

    // Alice deposits EBTC in the Stability Pool
    await stabilityPool.provideToSP(B_totalDebt.add(toBN(1)), ZERO_ADDRESS, { from: alice })

    // --- TEST ---
    // price drops to 1ETH:100EBTC, reducing TCR below 150%
    await priceFeed.setPrice('100000000000000000000')
    const price = await priceFeed.getPrice()

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // check system snapshots before
    const totalStakesSnaphot_before = (await cdpManager.totalStakesSnapshot()).toString()
    const totalCollateralSnapshot_before = (await cdpManager.totalCollateralSnapshot()).toString()

    assert.equal(totalStakesSnaphot_before, '0')
    assert.equal(totalCollateralSnapshot_before, '0')

    // Check Bob's ICR is between 110 and TCR
    const bob_ICR = await cdpManager.getCurrentICR(_bobCdpId, price)
    assert.isTrue(bob_ICR.gt(mv._MCR) && bob_ICR.lt(await th.getTCR(contracts)))

    // Liquidate Bob
    await cdpManager.liquidate(_bobCdpId, { from: owner })

    const totalStakesSnaphot_After = (await cdpManager.totalStakesSnapshot())
    const totalCollateralSnapshot_After = (await cdpManager.totalCollateralSnapshot())

    // totalStakesSnapshot should have reduced to 22 ether - the sum of Alice's coll( 20 ether) and Dennis' coll (2 ether )
    assert.equal(totalStakesSnaphot_After.toString(), A_coll.add(D_coll))
    // Total collateral should also reduce, since all liquidated coll has been moved to a reward for Stability Pool depositors
    assert.equal(totalCollateralSnapshot_After.toString(), A_coll.add(D_coll))
  })

  it("liquidate(), with 110% < ICR < TCR, and StabilityPool EBTC > debt to liquidate: closes the Cdp", async () => {
    // --- SETUP ---
    // Alice withdraws up to 1500 EBTC of debt, and Dennis up to 150, resulting in ICRs of 266%.
    // Bob withdraws up to 250 EBTC of debt, resulting in ICR of 240%. Bob has lowest ICR.
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(240, 16)), extraEBTCAmount: dec(250, 18), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    const { collateral: A_coll } = await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: B_totalDebt, extraParams: { from: alice } })
    const { collateral: D_coll } = await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: dec(2000, 18), extraParams: { from: dennis } })

    // Alice deposits EBTC in the Stability Pool
    await stabilityPool.provideToSP(B_totalDebt.add(toBN(1)), ZERO_ADDRESS, { from: alice })

    // --- TEST ---
    // price drops to 1ETH:100EBTC, reducing TCR below 150%
    await priceFeed.setPrice('100000000000000000000')
    const price = await priceFeed.getPrice()

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // Check Bob's Cdp is active
    const bob_CdpStatus_Before = (await cdpManager.Cdps(_bobCdpId))[3]
    const bob_Cdp_isInSortedList_Before = await sortedCdps.contains(_bobCdpId)

    assert.equal(bob_CdpStatus_Before, 1) // status enum element 1 corresponds to "Active"
    assert.isTrue(bob_Cdp_isInSortedList_Before)

    // Check Bob's ICR is between 110 and TCR
    const bob_ICR = await cdpManager.getCurrentICR(_bobCdpId, price)
    assert.isTrue(bob_ICR.gt(mv._MCR) && bob_ICR.lt(await th.getTCR(contracts)))

    // Liquidate Bob
    await cdpManager.liquidate(_bobCdpId, { from: owner })

    // Check Bob's Cdp is closed after liquidation
    const bob_CdpStatus_After = (await cdpManager.Cdps(_bobCdpId))[3]
    const bob_Cdp_isInSortedList_After = await sortedCdps.contains(_bobCdpId)

    assert.equal(bob_CdpStatus_After, 3) // status enum element 3 corresponds to "Closed by liquidation"
    assert.isFalse(bob_Cdp_isInSortedList_After)

    // check Bob’s collateral surplus
    const bob_remainingCollateral = B_coll.sub(B_totalDebt.mul(th.toBN(dec(11, 17))).div(price))
    th.assertIsApproximatelyEqual(await collSurplusPool.getCollateral(bob), bob_remainingCollateral)
    // can claim collateral
    const bob_balanceBefore = th.toBN(await web3.eth.getBalance(bob))
    const BOB_GAS = th.gasUsed(await borrowerOperations.claimCollateral({ from: bob, gasPrice: GAS_PRICE  }))
    const bob_expectedBalance = bob_balanceBefore.sub(th.toBN(BOB_GAS * GAS_PRICE))
    const bob_balanceAfter = th.toBN(await web3.eth.getBalance(bob))
    th.assertIsApproximatelyEqual(bob_balanceAfter, bob_expectedBalance.add(th.toBN(bob_remainingCollateral)))
  })

  it("liquidate(), with 110% < ICR < TCR, and StabilityPool EBTC > debt to liquidate: can liquidate cdps out of order", async () => {
    // taking out 1000 EBTC, CR of 200%
    const { collateral: A_coll, totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: alice } })
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(202, 16)), extraParams: { from: bob } })
    const { collateral: C_coll, totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(204, 16)), extraParams: { from: carol } })
    const { collateral: D_coll, totalDebt: D_totalDebt } = await openCdp({ ICR: toBN(dec(206, 16)), extraParams: { from: dennis } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);
    const { collateral: E_coll } = await openCdp({ ICR: toBN(dec(240, 16)), extraParams: { from: erin } })
    const { collateral: F_coll } = await openCdp({ ICR: toBN(dec(240, 16)), extraParams: { from: freddy } })

    const totalLiquidatedDebt = A_totalDebt.add(B_totalDebt).add(C_totalDebt).add(D_totalDebt)

    await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: totalLiquidatedDebt, extraParams: { from: whale } })
    await stabilityPool.provideToSP(totalLiquidatedDebt, ZERO_ADDRESS, { from: whale })

    // Price drops 
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()
    const TCR = await th.getTCR(contracts)
  
    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check cdps A-D are in range 110% < ICR < TCR
    const ICR_A = await cdpManager.getCurrentICR(_aliceCdpId, price)
    const ICR_B = await cdpManager.getCurrentICR(_bobCdpId, price)
    const ICR_C = await cdpManager.getCurrentICR(_carolCdpId, price)
    const ICR_D = await cdpManager.getCurrentICR(_dennisCdpId, price)
    
    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C.gt(mv._MCR) && ICR_C.lt(TCR))
    assert.isTrue(ICR_D.gt(mv._MCR) && ICR_D.lt(TCR))

    // Cdps are ordered by ICR, low to high: A, B, C, D.

    // Liquidate out of ICR order: D, B, C.  Confirm Recovery Mode is active prior to each.
    const liquidationTx_D = await cdpManager.liquidate(_dennisCdpId)
  
    assert.isTrue(await th.checkRecoveryMode(contracts))
    const liquidationTx_B = await cdpManager.liquidate(_bobCdpId)

    assert.isTrue(await th.checkRecoveryMode(contracts))
    const liquidationTx_C = await cdpManager.liquidate(_carolCdpId)
    
    // Check transactions all succeeded
    assert.isTrue(liquidationTx_D.receipt.status)
    assert.isTrue(liquidationTx_B.receipt.status)
    assert.isTrue(liquidationTx_C.receipt.status)

    // Confirm cdps D, B, C removed
    assert.isFalse(await sortedCdps.contains(_dennisCdpId))
    assert.isFalse(await sortedCdps.contains(_bobCdpId))
    assert.isFalse(await sortedCdps.contains(_carolCdpId))

    // Confirm cdps have status 'closed by liquidation' (Status enum element idx 3)
    assert.equal((await cdpManager.Cdps(_dennisCdpId))[3], '3')
    assert.equal((await cdpManager.Cdps(_bobCdpId))[3], '3')
    assert.equal((await cdpManager.Cdps(_carolCdpId))[3], '3')

    // check collateral surplus
    const dennis_remainingCollateral = D_coll.sub(D_totalDebt.mul(th.toBN(dec(11, 17))).div(price))
    const bob_remainingCollateral = B_coll.sub(B_totalDebt.mul(th.toBN(dec(11, 17))).div(price))
    const carol_remainingCollateral = C_coll.sub(C_totalDebt.mul(th.toBN(dec(11, 17))).div(price))
    th.assertIsApproximatelyEqual(await collSurplusPool.getCollateral(dennis), dennis_remainingCollateral)
    th.assertIsApproximatelyEqual(await collSurplusPool.getCollateral(bob), bob_remainingCollateral)
    th.assertIsApproximatelyEqual(await collSurplusPool.getCollateral(carol), carol_remainingCollateral)

    // can claim collateral
    const dennis_balanceBefore = th.toBN(await web3.eth.getBalance(dennis))
    const DENNIS_GAS = th.gasUsed(await borrowerOperations.claimCollateral({ from: dennis, gasPrice: GAS_PRICE  }))
    const dennis_expectedBalance = dennis_balanceBefore.sub(th.toBN(DENNIS_GAS * GAS_PRICE))
    const dennis_balanceAfter = th.toBN(await web3.eth.getBalance(dennis))
    assert.isTrue(dennis_balanceAfter.eq(dennis_expectedBalance.add(th.toBN(dennis_remainingCollateral))))

    const bob_balanceBefore = th.toBN(await web3.eth.getBalance(bob))
    const BOB_GAS = th.gasUsed(await borrowerOperations.claimCollateral({ from: bob, gasPrice: GAS_PRICE  }))
    const bob_expectedBalance = bob_balanceBefore.sub(th.toBN(BOB_GAS * GAS_PRICE))
    const bob_balanceAfter = th.toBN(await web3.eth.getBalance(bob))
    th.assertIsApproximatelyEqual(bob_balanceAfter, bob_expectedBalance.add(th.toBN(bob_remainingCollateral)))

    const carol_balanceBefore = th.toBN(await web3.eth.getBalance(carol))
    const CAROL_GAS = th.gasUsed(await borrowerOperations.claimCollateral({ from: carol, gasPrice: GAS_PRICE  }))
    const carol_expectedBalance = carol_balanceBefore.sub(th.toBN(CAROL_GAS * GAS_PRICE))
    const carol_balanceAfter = th.toBN(await web3.eth.getBalance(carol))
    th.assertIsApproximatelyEqual(carol_balanceAfter, carol_expectedBalance.add(th.toBN(carol_remainingCollateral)))
  })


  /* --- liquidate() applied to cdp with ICR > 110% that has the lowest ICR, and Stability Pool 
  EBTC is LESS THAN the liquidated debt: a non fullfilled liquidation --- */

  it("liquidate(), with ICR > 110%, and StabilityPool EBTC < liquidated debt: Cdp remains active", async () => {
    // --- SETUP ---
    // Alice withdraws up to 1500 EBTC of debt, and Dennis up to 150, resulting in ICRs of 266%.
    // Bob withdraws up to 250 EBTC of debt, resulting in ICR of 240%. Bob has lowest ICR.
    const { collateral: A_coll } = await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: dec(1500, 18), extraParams: { from: alice } })
    const { collateral: B_coll } = await openCdp({ ICR: toBN(dec(240, 16)), extraEBTCAmount: dec(250, 18), extraParams: { from: bob } })
    const { collateral: D_coll } = await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: dec(2000, 18), extraParams: { from: dennis } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);

    // Alice deposits 1490 EBTC in the Stability Pool
    await stabilityPool.provideToSP('1490000000000000000000', ZERO_ADDRESS, { from: alice })

    // --- TEST ---
    // price drops to 1ETH:100EBTC, reducing TCR below 150%
    await priceFeed.setPrice('100000000000000000000')

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // Check Bob's Cdp is active
    const bob_CdpStatus_Before = (await cdpManager.Cdps(_bobCdpId))[3]
    const bob_Cdp_isInSortedList_Before = await sortedCdps.contains(_bobCdpId)

    assert.equal(bob_CdpStatus_Before, 1) // status enum element 1 corresponds to "Active"
    assert.isTrue(bob_Cdp_isInSortedList_Before)

    // Try to liquidate Bob
    await assertRevert(cdpManager.liquidate(_bobCdpId, { from: owner }), "CdpManager: nothing to liquidate")

    /* Since the pool only contains 100 EBTC, and Bob's pre-liquidation debt was 250 EBTC,
    expect Bob's cdp to remain untouched, and remain active after liquidation */

    const bob_CdpStatus_After = (await cdpManager.Cdps(_bobCdpId))[3]
    const bob_Cdp_isInSortedList_After = await sortedCdps.contains(_bobCdpId)

    assert.equal(bob_CdpStatus_After, 1) // status enum element 1 corresponds to "Active"
    assert.isTrue(bob_Cdp_isInSortedList_After)
  })

  it("liquidate(), with ICR > 110%, and StabilityPool EBTC < liquidated debt: Cdp remains in CdpOwners array", async () => {
    // --- SETUP ---
    // Alice withdraws up to 1500 EBTC of debt, and Dennis up to 150, resulting in ICRs of 266%.
    // Bob withdraws up to 250 EBTC of debt, resulting in ICR of 240%. Bob has lowest ICR.
    const { collateral: A_coll } = await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: dec(1500, 18), extraParams: { from: alice } })
    const { collateral: B_coll } = await openCdp({ ICR: toBN(dec(240, 16)), extraEBTCAmount: dec(250, 18), extraParams: { from: bob } })
    const { collateral: D_coll } = await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: dec(2000, 18), extraParams: { from: dennis } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);

    // Alice deposits 100 EBTC in the Stability Pool
    await stabilityPool.provideToSP(dec(100, 18), ZERO_ADDRESS, { from: alice })

    // --- TEST ---
    // price drops to 1ETH:100EBTC, reducing TCR below 150%
    await priceFeed.setPrice('100000000000000000000')

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // Check Bob's Cdp is active
    const bob_CdpStatus_Before = (await cdpManager.Cdps(_bobCdpId))[3]
    const bob_Cdp_isInSortedList_Before = await sortedCdps.contains(_bobCdpId)

    assert.equal(bob_CdpStatus_Before, 1) // status enum element 1 corresponds to "Active"
    assert.isTrue(bob_Cdp_isInSortedList_Before)

    // Try to liquidate Bob
    await assertRevert(cdpManager.liquidate(_bobCdpId, { from: owner }), "CdpManager: nothing to liquidate")

    /* Since the pool only contains 100 EBTC, and Bob's pre-liquidation debt was 250 EBTC, 
    expect Bob's cdp to only be partially offset, and remain active after liquidation */

    // Check Bob is in Cdp owners array
    const arrayLength = (await cdpManager.getCdpIdsCount()).toNumber()
    let addressFound = false;
    let addressIdx = 0;

    for (let i = 0; i < arrayLength; i++) {
      const address = (await cdpManager.CdpIds(i)).toString()
      if (address == _bobCdpId) {
        addressFound = true
        addressIdx = i
      }
    }

    assert.isTrue(addressFound);

    // Check CdpOwners idx on cdp struct == idx of address found in CdpOwners array
    const idxOnStruct = (await cdpManager.Cdps(_bobCdpId))[4].toString()
    assert.equal(addressIdx.toString(), idxOnStruct)
  })

  it("liquidate(), with ICR > 110%, and StabilityPool EBTC < liquidated debt: nothing happens", async () => {
    // --- SETUP ---
    // Alice withdraws up to 1500 EBTC of debt, and Dennis up to 150, resulting in ICRs of 266%.
    // Bob withdraws up to 250 EBTC of debt, resulting in ICR of 240%. Bob has lowest ICR.
    const { collateral: A_coll } = await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: dec(1500, 18), extraParams: { from: alice } })
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(240, 16)), extraEBTCAmount: dec(250, 18), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    const { collateral: D_coll } = await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: dec(2000, 18), extraParams: { from: dennis } })

    // Alice deposits 100 EBTC in the Stability Pool
    await stabilityPool.provideToSP(dec(100, 18), ZERO_ADDRESS, { from: alice })

    // --- TEST ---
    // price drops to 1ETH:100EBTC, reducing TCR below 150%
    await priceFeed.setPrice('100000000000000000000')

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // Try to liquidate Bob
    await assertRevert(cdpManager.liquidate(_bobCdpId, { from: owner }), "CdpManager: nothing to liquidate")

    /*  Since Bob's debt (250 EBTC) is larger than all EBTC in the Stability Pool, Liquidation won’t happen

    After liquidation, totalStakes snapshot should equal Alice's stake (20 ether) + Dennis stake (2 ether) = 22 ether.

    Since there has been no redistribution, the totalCollateral snapshot should equal the totalStakes snapshot: 22 ether.

    Bob's new coll and stake should remain the same, and the updated totalStakes should still equal 25 ether.
    */
    const bob_Cdp = await cdpManager.Cdps(_bobCdpId)
    const bob_DebtAfter = bob_Cdp[0].toString()
    const bob_CollAfter = bob_Cdp[1].toString()
    const bob_StakeAfter = bob_Cdp[2].toString()

    th.assertIsApproximatelyEqual(bob_DebtAfter, B_totalDebt)
    assert.equal(bob_CollAfter.toString(), B_coll)
    assert.equal(bob_StakeAfter.toString(), B_coll)

    const totalStakes_After = (await cdpManager.totalStakes()).toString()
    assert.equal(totalStakes_After.toString(), A_coll.add(B_coll).add(D_coll))
  })

  it("liquidate(), with ICR > 110%, and StabilityPool EBTC < liquidated debt: updates system shapshots", async () => {
    // --- SETUP ---
    // Alice withdraws up to 1500 EBTC of debt, and Dennis up to 150, resulting in ICRs of 266%.
    // Bob withdraws up to 250 EBTC of debt, resulting in ICR of 240%. Bob has lowest ICR.
    const { collateral: A_coll } = await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: dec(1500, 18), extraParams: { from: alice } })
    const { collateral: B_coll } = await openCdp({ ICR: toBN(dec(240, 16)), extraEBTCAmount: dec(250, 18), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    const { collateral: D_coll } = await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: dec(2000, 18), extraParams: { from: dennis } })

    // Alice deposits 100 EBTC in the Stability Pool
    await stabilityPool.provideToSP(dec(100, 18), ZERO_ADDRESS, { from: alice })

    // --- TEST ---
    // price drops to 1ETH:100EBTC, reducing TCR below 150%
    await priceFeed.setPrice('100000000000000000000')

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // Check snapshots before
    const totalStakesSnaphot_Before = (await cdpManager.totalStakesSnapshot()).toString()
    const totalCollateralSnapshot_Before = (await cdpManager.totalCollateralSnapshot()).toString()

    assert.equal(totalStakesSnaphot_Before, 0)
    assert.equal(totalCollateralSnapshot_Before, 0)

    // Liquidate Bob, it won’t happen as there are no funds in the SP
    await assertRevert(cdpManager.liquidate(_bobCdpId, { from: owner }), "CdpManager: nothing to liquidate")

    /* After liquidation, totalStakes snapshot should still equal the total stake: 25 ether

    Since there has been no redistribution, the totalCollateral snapshot should equal the totalStakes snapshot: 25 ether.*/

    const totalStakesSnaphot_After = (await cdpManager.totalStakesSnapshot()).toString()
    const totalCollateralSnapshot_After = (await cdpManager.totalCollateralSnapshot()).toString()

    assert.equal(totalStakesSnaphot_After, totalStakesSnaphot_Before)
    assert.equal(totalCollateralSnapshot_After, totalCollateralSnapshot_Before)
  })

  it("liquidate(), with ICR > 110%, and StabilityPool EBTC < liquidated debt: causes correct Pool offset and ETH gain, and doesn't redistribute to active cdps", async () => {
    // --- SETUP ---
    // Alice withdraws up to 1500 EBTC of debt, and Dennis up to 150, resulting in ICRs of 266%.
    // Bob withdraws up to 250 EBTC of debt, resulting in ICR of 240%. Bob has lowest ICR.
    const { collateral: A_coll } = await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: dec(1500, 18), extraParams: { from: alice } })
    const { collateral: B_coll } = await openCdp({ ICR: toBN(dec(240, 16)), extraEBTCAmount: dec(250, 18), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    const { collateral: D_coll } = await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: dec(2000, 18), extraParams: { from: dennis } })

    // Alice deposits 100 EBTC in the Stability Pool
    await stabilityPool.provideToSP(dec(100, 18), ZERO_ADDRESS, { from: alice })

    // --- TEST ---
    // price drops to 1ETH:100EBTC, reducing TCR below 150%
    await priceFeed.setPrice('100000000000000000000')

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // Try to liquidate Bob. Shouldn’t happen
    await assertRevert(cdpManager.liquidate(_bobCdpId, { from: owner }), "CdpManager: nothing to liquidate")

    // check Stability Pool rewards. Nothing happened, so everything should remain the same

    const aliceExpectedDeposit = await stabilityPool.getCompoundedEBTCDeposit(alice)
    const aliceExpectedETHGain = await stabilityPool.getDepositorETHGain(alice)

    assert.equal(aliceExpectedDeposit.toString(), dec(100, 18))
    assert.equal(aliceExpectedETHGain.toString(), '0')

    /* For this Recovery Mode test case with ICR > 110%, there should be no redistribution of remainder to active Cdps. 
    Redistribution rewards-per-unit-staked should be zero. */

    const L_EBTCDebt_After = (await cdpManager.L_EBTCDebt()).toString()
    const L_ETH_After = (await cdpManager.L_ETH()).toString()

    assert.equal(L_EBTCDebt_After, '0')
    assert.equal(L_ETH_After, '0')
  })

  it("liquidate(), with ICR > 110%, and StabilityPool EBTC < liquidated debt: ICR of non liquidated cdp does not change", async () => {
    // --- SETUP ---
    // Alice withdraws up to 1500 EBTC of debt, and Dennis up to 150, resulting in ICRs of 266%.
    // Bob withdraws up to 250 EBTC of debt, resulting in ICR of 240%. Bob has lowest ICR.
    // Carol withdraws up to debt of 240 EBTC, -> ICR of 250%.
    const { collateral: A_coll } = await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: dec(1500, 18), extraParams: { from: alice } })
    const { collateral: B_coll } = await openCdp({ ICR: toBN(dec(240, 16)), extraEBTCAmount: dec(250, 18), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    const { collateral: D_coll } = await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: dec(2000, 18), extraParams: { from: dennis } })
    const { collateral: C_coll } = await openCdp({ ICR: toBN(dec(250, 16)), extraEBTCAmount: dec(240, 18), extraParams: { from: carol } })
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    // Alice deposits 100 EBTC in the Stability Pool
    await stabilityPool.provideToSP(dec(100, 18), ZERO_ADDRESS, { from: alice })

    // --- TEST ---
    // price drops to 1ETH:100EBTC, reducing TCR below 150%
    await priceFeed.setPrice(dec(100, 18))
    const price = await priceFeed.getPrice()

    const bob_ICR_Before = (await cdpManager.getCurrentICR(_bobCdpId, price)).toString()
    const carol_ICR_Before = (await cdpManager.getCurrentICR(_carolCdpId, price)).toString()

    assert.isTrue(await th.checkRecoveryMode(contracts))

    const bob_Coll_Before = (await cdpManager.Cdps(_bobCdpId))[1]
    const bob_Debt_Before = (await cdpManager.Cdps(_bobCdpId))[0]

    // confirm Bob is last cdp in list, and has >110% ICR
    assert.equal((await sortedCdps.getLast()).toString(), _bobCdpId)
    assert.isTrue((await cdpManager.getCurrentICR(_bobCdpId, price)).gt(mv._MCR))

    // L1: Try to liquidate Bob. Nothing happens
    await assertRevert(cdpManager.liquidate(_bobCdpId, { from: owner }), "CdpManager: nothing to liquidate")

    //Check SP EBTC has been completely emptied
    assert.equal((await stabilityPool.getTotalEBTCDeposits()).toString(), dec(100, 18))

    // Check Bob remains active
    assert.isTrue(await sortedCdps.contains(_bobCdpId))

    // Check Bob's collateral and debt remains the same
    const bob_Coll_After = (await cdpManager.Cdps(_bobCdpId))[1]
    const bob_Debt_After = (await cdpManager.Cdps(_bobCdpId))[0]
    assert.isTrue(bob_Coll_After.eq(bob_Coll_Before))
    assert.isTrue(bob_Debt_After.eq(bob_Debt_Before))

    const bob_ICR_After = (await cdpManager.getCurrentICR(_bobCdpId, price)).toString()

    // check Bob's ICR has not changed
    assert.equal(bob_ICR_After, bob_ICR_Before)


    // to compensate borrowing fees
    await ebtcToken.transfer(bob, dec(100, 18), { from: alice })

    // Remove Bob from system to test Carol's cdp: price rises, Bob closes cdp, price drops to 100 again
    await priceFeed.setPrice(dec(200, 18))
    await borrowerOperations.closeCdp(_bobCdpId, { from: bob })
    await priceFeed.setPrice(dec(100, 18))
    assert.isFalse(await sortedCdps.contains(_bobCdpId))

    // Alice provides another 50 EBTC to pool
    await stabilityPool.provideToSP(dec(50, 18), ZERO_ADDRESS, { from: alice })

    assert.isTrue(await th.checkRecoveryMode(contracts))

    const carol_Coll_Before = (await cdpManager.Cdps(_carolCdpId))[1]
    const carol_Debt_Before = (await cdpManager.Cdps(_carolCdpId))[0]

    // Confirm Carol is last cdp in list, and has >110% ICR
    assert.equal((await sortedCdps.getLast()), _carolCdpId)
    assert.isTrue((await cdpManager.getCurrentICR(_carolCdpId, price)).gt(mv._MCR))

    // L2: Try to liquidate Carol. Nothing happens
    await assertRevert(cdpManager.liquidate(_carolCdpId), "CdpManager: nothing to liquidate")

    //Check SP EBTC has been completely emptied
    assert.equal((await stabilityPool.getTotalEBTCDeposits()).toString(), dec(150, 18))

    // Check Carol's collateral and debt remains the same
    const carol_Coll_After = (await cdpManager.Cdps(_carolCdpId))[1]
    const carol_Debt_After = (await cdpManager.Cdps(_carolCdpId))[0]
    assert.isTrue(carol_Coll_After.eq(carol_Coll_Before))
    assert.isTrue(carol_Debt_After.eq(carol_Debt_Before))

    const carol_ICR_After = (await cdpManager.getCurrentICR(_carolCdpId, price)).toString()

    // check Carol's ICR has not changed
    assert.equal(carol_ICR_After, carol_ICR_Before)

    //Confirm liquidations have not led to any redistributions to cdps
    const L_EBTCDebt_After = (await cdpManager.L_EBTCDebt()).toString()
    const L_ETH_After = (await cdpManager.L_ETH()).toString()

    assert.equal(L_EBTCDebt_After, '0')
    assert.equal(L_ETH_After, '0')
  })

  it("liquidate() with ICR > 110%, and StabilityPool EBTC < liquidated debt: total liquidated coll and debt is correct", async () => {
    // Whale provides 50 EBTC to the SP
    await openCdp({ ICR: toBN(dec(300, 16)), extraEBTCAmount: dec(50, 18), extraParams: { from: whale } })
    await stabilityPool.provideToSP(dec(50, 18), ZERO_ADDRESS, { from: whale })

    const { collateral: A_coll } = await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: alice } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    const { collateral: B_coll } = await openCdp({ ICR: toBN(dec(202, 16)), extraParams: { from: bob } })
    const { collateral: C_coll } = await openCdp({ ICR: toBN(dec(204, 16)), extraParams: { from: carol } })
    const { collateral: D_coll } = await openCdp({ ICR: toBN(dec(206, 16)), extraParams: { from: dennis } })
    const { collateral: E_coll } = await openCdp({ ICR: toBN(dec(208, 16)), extraParams: { from: erin } })

    // Price drops 
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check C is in range 110% < ICR < 150%
    const ICR_A = await cdpManager.getCurrentICR(_aliceCdpId, price)
    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(await th.getTCR(contracts)))

    const entireSystemCollBefore = await cdpManager.getEntireSystemColl()
    const entireSystemDebtBefore = await cdpManager.getEntireSystemDebt()

    // Try to liquidate Alice
    await assertRevert(cdpManager.liquidate(_aliceCdpId), "CdpManager: nothing to liquidate")

    // Expect system debt and system coll not reduced
    const entireSystemCollAfter = await cdpManager.getEntireSystemColl()
    const entireSystemDebtAfter = await cdpManager.getEntireSystemDebt()

    const changeInEntireSystemColl = entireSystemCollBefore.sub(entireSystemCollAfter)
    const changeInEntireSystemDebt = entireSystemDebtBefore.sub(entireSystemDebtAfter)

    assert.equal(changeInEntireSystemColl, '0')
    assert.equal(changeInEntireSystemDebt, '0')
  })

  // --- 

  it("liquidate(): Doesn't liquidate undercollateralized cdp if it is the only cdp in the system", async () => {
    // Alice creates a single cdp with 0.62 ETH and a debt of 62 EBTC, and provides 10 EBTC to SP
    await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: alice } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    await stabilityPool.provideToSP(dec(10, 18), ZERO_ADDRESS, { from: alice })

    assert.isFalse(await th.checkRecoveryMode(contracts))

    // Set ETH:USD price to 105
    await priceFeed.setPrice('105000000000000000000')
    const price = await priceFeed.getPrice()

    assert.isTrue(await th.checkRecoveryMode(contracts))

    const alice_ICR = (await cdpManager.getCurrentICR(_aliceCdpId, price)).toString()
    assert.equal(alice_ICR, '1050000000000000000')

    const activeCdpsCount_Before = await cdpManager.getCdpIdsCount()

    assert.equal(activeCdpsCount_Before, 1)

    // Try to liquidate the cdp
    await assertRevert(cdpManager.liquidate(_aliceCdpId, { from: owner }), "CdpManager: nothing to liquidate")

    // Check Alice's cdp has not been removed
    const activeCdpsCount_After = await cdpManager.getCdpIdsCount()
    assert.equal(activeCdpsCount_After, 1)

    const alice_isInSortedList = await sortedCdps.contains(_aliceCdpId)
    assert.isTrue(alice_isInSortedList)
  })

  it("liquidate(): Liquidates undercollateralized cdp if there are two cdps in the system", async () => {
    await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);

    // Alice creates a single cdp with 0.62 ETH and a debt of 62 EBTC, and provides 10 EBTC to SP
    await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: alice } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);

    // Alice proves 10 EBTC to SP
    await stabilityPool.provideToSP(dec(10, 18), ZERO_ADDRESS, { from: alice })

    assert.isFalse(await th.checkRecoveryMode(contracts))

    // Set ETH:USD price to 105
    await priceFeed.setPrice('105000000000000000000')
    const price = await priceFeed.getPrice()

    assert.isTrue(await th.checkRecoveryMode(contracts))

    const alice_ICR = (await cdpManager.getCurrentICR(_aliceCdpId, price)).toString()
    assert.equal(alice_ICR, '1050000000000000000')

    const activeCdpsCount_Before = await cdpManager.getCdpIdsCount()

    assert.equal(activeCdpsCount_Before, 2)

    // Liquidate the cdp
    await cdpManager.liquidate(_aliceCdpId, { from: owner })

    // Check Alice's cdp is removed, and bob remains
    const activeCdpsCount_After = await cdpManager.getCdpIdsCount()
    assert.equal(activeCdpsCount_After, 1)

    const alice_isInSortedList = await sortedCdps.contains(_aliceCdpId)
    assert.isFalse(alice_isInSortedList)

    const bob_isInSortedList = await sortedCdps.contains(_bobCdpId)
    assert.isTrue(bob_isInSortedList)
  })

  it("liquidate(): does nothing if cdp has >= 110% ICR and the Stability Pool is empty", async () => {
    await openCdp({ ICR: toBN(dec(400, 16)), extraParams: { from: alice } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    await openCdp({ ICR: toBN(dec(220, 16)), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    await openCdp({ ICR: toBN(dec(266, 16)), extraParams: { from: carol } })
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    await priceFeed.setPrice(dec(100, 18))
    const price = await priceFeed.getPrice()

    const TCR_Before = (await th.getTCR(contracts)).toString()
    const listSize_Before = (await sortedCdps.getSize()).toString()

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check Bob's ICR > 110%
    const bob_ICR = await cdpManager.getCurrentICR(_bobCdpId, price)
    assert.isTrue(bob_ICR.gte(mv._MCR))

    // Confirm SP is empty
    const EBTCinSP = (await stabilityPool.getTotalEBTCDeposits()).toString()
    assert.equal(EBTCinSP, '0')

    // Attempt to liquidate bob
    await assertRevert(cdpManager.liquidate(_bobCdpId), "CdpManager: nothing to liquidate")

    // check A, B, C remain active
    assert.isTrue((await sortedCdps.contains(_bobCdpId)))
    assert.isTrue((await sortedCdps.contains(_aliceCdpId)))
    assert.isTrue((await sortedCdps.contains(_carolCdpId)))

    const TCR_After = (await th.getTCR(contracts)).toString()
    const listSize_After = (await sortedCdps.getSize()).toString()

    // Check TCR and list size have not changed
    assert.equal(TCR_Before, TCR_After)
    assert.equal(listSize_Before, listSize_After)
  })

  it("liquidate(): does nothing if cdp ICR >= TCR, and SP covers cdp's debt", async () => { 
    await openCdp({ ICR: toBN(dec(166, 16)), extraParams: { from: A } })
    await openCdp({ ICR: toBN(dec(154, 16)), extraParams: { from: B } })
    await openCdp({ ICR: toBN(dec(142, 16)), extraParams: { from: C } })
    let _aCdpId = await sortedCdps.cdpOfOwnerByIndex(A, 0);
    let _bCdpId = await sortedCdps.cdpOfOwnerByIndex(B, 0);
    let _cCdpId = await sortedCdps.cdpOfOwnerByIndex(C, 0);

    // C fills SP with 130 EBTC
    await stabilityPool.provideToSP(dec(130, 18), ZERO_ADDRESS, {from: C})

    await priceFeed.setPrice(dec(150, 18))
    const price = await priceFeed.getPrice()
    assert.isTrue(await th.checkRecoveryMode(contracts))

    const TCR = await th.getTCR(contracts)

    const ICR_A = await cdpManager.getCurrentICR(_aCdpId, price)
    const ICR_B = await cdpManager.getCurrentICR(_bCdpId, price)
    const ICR_C = await cdpManager.getCurrentICR(_cCdpId, price)

    assert.isTrue(ICR_A.gt(TCR))
    // Try to liquidate A
    await assertRevert(cdpManager.liquidate(_aCdpId), "CdpManager: nothing to liquidate")

    // Check liquidation of A does nothing - cdp remains in system
    assert.isTrue(await sortedCdps.contains(_aCdpId))
    assert.equal(await cdpManager.getCdpStatus(_aCdpId), 1) // Status 1 -> active

    // Check C, with ICR < TCR, can be liquidated
    assert.isTrue(ICR_C.lt(TCR))
    const liqTxC = await cdpManager.liquidate(_cCdpId)
    assert.isTrue(liqTxC.receipt.status)

    assert.isFalse(await sortedCdps.contains(_cCdpId))
    assert.equal(await cdpManager.getCdpStatus(_cCdpId), 3) // Status liquidated
  })

  it("liquidate(): reverts if cdp is non-existent", async () => {
    await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(133, 16)), extraParams: { from: bob } })

    await priceFeed.setPrice(dec(100, 18))

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check Carol does not have an existing cdp
    assert.equal(await cdpManager.getCdpStatus(carol), 0)
    assert.isFalse(await sortedCdps.contains(carol))

    try {
      await cdpManager.liquidate(carol)

      assert.isFalse(txCarol.receipt.status)
    } catch (err) {
      assert.include(err.message, "revert")
    }
  })

  it("liquidate(): reverts if cdp has been closed", async () => {
    await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(133, 16)), extraParams: { from: bob } })
    await openCdp({ ICR: toBN(dec(133, 16)), extraParams: { from: carol } })
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    assert.isTrue(await sortedCdps.contains(_carolCdpId))

    // Price drops, Carol ICR falls below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Carol liquidated, and her cdp is closed
    const txCarol_L1 = await cdpManager.liquidate(_carolCdpId)
    assert.isTrue(txCarol_L1.receipt.status)

    // Check Carol's cdp is closed by liquidation
    assert.isFalse(await sortedCdps.contains(_carolCdpId))
    assert.equal(await cdpManager.getCdpStatus(_carolCdpId), 3)

    try {
      await cdpManager.liquidate(_carolCdpId)
    } catch (err) {
      assert.include(err.message, "revert")
    }
  })

  it("liquidate(): liquidates based on entire/collateral debt (including pending rewards), not raw collateral/debt", async () => {
    await openCdp({ ICR: toBN(dec(400, 16)), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(220, 16)), extraParams: { from: bob } })
    await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: carol } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    // Defaulter opens with 60 EBTC, 0.6 ETH
    await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: defaulter_1 } })
    let _defaulter1CdpId = await sortedCdps.cdpOfOwnerByIndex(defaulter_1, 0);

    // Price drops
    await priceFeed.setPrice(dec(100, 18))
    const price = await priceFeed.getPrice()

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    const alice_ICR_Before = await cdpManager.getCurrentICR(_aliceCdpId, price)
    const bob_ICR_Before = await cdpManager.getCurrentICR(_bobCdpId, price)
    const carol_ICR_Before = await cdpManager.getCurrentICR(_carolCdpId, price)

    /* Before liquidation: 
    Alice ICR: = (1 * 100 / 50) = 200%
    Bob ICR: (1 * 100 / 90.5) = 110.5%
    Carol ICR: (1 * 100 / 100 ) =  100%

    Therefore Alice and Bob above the MCR, Carol is below */
    assert.isTrue(alice_ICR_Before.gte(mv._MCR))
    assert.isTrue(bob_ICR_Before.gte(mv._MCR))
    assert.isTrue(carol_ICR_Before.lte(mv._MCR))

    // Liquidate defaulter. 30 EBTC and 0.3 ETH is distributed uniformly between A, B and C. Each receive 10 EBTC, 0.1 ETH
    await cdpManager.liquidate(_defaulter1CdpId)

    const alice_ICR_After = await cdpManager.getCurrentICR(_aliceCdpId, price)
    const bob_ICR_After = await cdpManager.getCurrentICR(_bobCdpId, price)
    const carol_ICR_After = await cdpManager.getCurrentICR(_carolCdpId, price)

    /* After liquidation: 

    Alice ICR: (1.1 * 100 / 60) = 183.33%
    Bob ICR:(1.1 * 100 / 100.5) =  109.45%
    Carol ICR: (1.1 * 100 ) 100%

    Check Alice is above MCR, Bob below, Carol below. */
    assert.isTrue(alice_ICR_After.gte(mv._MCR))
    assert.isTrue(bob_ICR_After.lte(mv._MCR))
    assert.isTrue(carol_ICR_After.lte(mv._MCR))

    /* Though Bob's true ICR (including pending rewards) is below the MCR, 
    check that Bob's raw coll and debt has not changed, and that his "raw" ICR is above the MCR */
    const bob_Coll = (await cdpManager.Cdps(_bobCdpId))[1]
    const bob_Debt = (await cdpManager.Cdps(_bobCdpId))[0]

    const bob_rawICR = bob_Coll.mul(th.toBN(dec(100, 18))).div(bob_Debt)
    assert.isTrue(bob_rawICR.gte(mv._MCR))

    //liquidate A, B, C
    await assertRevert(cdpManager.liquidate(_aliceCdpId), "CdpManager: nothing to liquidate")
    await cdpManager.liquidate(_bobCdpId)
    await cdpManager.liquidate(_carolCdpId)

    /*  Since there is 0 EBTC in the stability Pool, A, with ICR >110%, should stay active.
    Check Alice stays active, Carol gets liquidated, and Bob gets liquidated 
    (because his pending rewards bring his ICR < MCR) */
    assert.isTrue(await sortedCdps.contains(_aliceCdpId))
    assert.isFalse(await sortedCdps.contains(_bobCdpId))
    assert.isFalse(await sortedCdps.contains(_carolCdpId))

    // check cdp statuses - A active (1), B and C liquidated (3)
    assert.equal((await cdpManager.Cdps(_aliceCdpId))[3].toString(), '1')
    assert.equal((await cdpManager.Cdps(_bobCdpId))[3].toString(), '3')
    assert.equal((await cdpManager.Cdps(_carolCdpId))[3].toString(), '3')
  })

  it("liquidate(): does not affect the SP deposit or ETH gain when called on an SP depositor's address that has no cdp", async () => {
    const { collateral: C_coll, totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: carol } })
    const spDeposit = C_totalDebt.add(toBN(dec(1000, 18)))
    await openCdp({ ICR: toBN(dec(220, 16)), extraEBTCAmount: spDeposit, extraParams: { from: bob } })
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    // Bob sends tokens to Dennis, who has no cdp
    await ebtcToken.transfer(dennis, spDeposit, { from: bob })

    //Dennis provides 200 EBTC to SP
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: dennis })

    // Price drop
    await priceFeed.setPrice(dec(105, 18))

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Carol gets liquidated
    await cdpManager.liquidate(_carolCdpId)

    // Check Dennis' SP deposit has absorbed Carol's debt, and he has received her liquidated ETH
    const dennis_Deposit_Before = (await stabilityPool.getCompoundedEBTCDeposit(dennis)).toString()
    const dennis_ETHGain_Before = (await stabilityPool.getDepositorETHGain(dennis)).toString()
    assert.isAtMost(th.getDifference(dennis_Deposit_Before, spDeposit.sub(C_totalDebt)), 1000)
    assert.isAtMost(th.getDifference(dennis_ETHGain_Before, th.applyLiquidationFee(C_coll)), 1000)

    // Attempt to liquidate Dennis
    try {
      await cdpManager.liquidate(dennis)
    } catch (err) {
      assert.include(err.message, "revert")
    }

    // Check Dennis' SP deposit does not change after liquidation attempt
    const dennis_Deposit_After = (await stabilityPool.getCompoundedEBTCDeposit(dennis)).toString()
    const dennis_ETHGain_After = (await stabilityPool.getDepositorETHGain(dennis)).toString()
    assert.equal(dennis_Deposit_Before, dennis_Deposit_After)
    assert.equal(dennis_ETHGain_Before, dennis_ETHGain_After)
  })

  it("liquidate(): does not alter the liquidated user's token balance", async () => {
    await openCdp({ ICR: toBN(dec(220, 16)), extraEBTCAmount: dec(1000, 18), extraParams: { from: whale } })

    const { ebtcAmount: A_ebtcAmount } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(300, 18), extraParams: { from: alice } })
    const { ebtcAmount: B_ebtcAmount } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(200, 18), extraParams: { from: bob } })
    const { ebtcAmount: C_ebtcAmount } = await openCdp({ ICR: toBN(dec(206, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: carol } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    await priceFeed.setPrice(dec(105, 18))

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check token balances 
    assert.equal((await ebtcToken.balanceOf(alice)).toString(), A_ebtcAmount)
    assert.equal((await ebtcToken.balanceOf(bob)).toString(), B_ebtcAmount)
    assert.equal((await ebtcToken.balanceOf(carol)).toString(), C_ebtcAmount)

    // Check sortedList size is 4
    assert.equal((await sortedCdps.getSize()).toString(), '4')

    // Liquidate A, B and C
    await cdpManager.liquidate(_aliceCdpId)
    await cdpManager.liquidate(_bobCdpId)
    await cdpManager.liquidate(_carolCdpId)

    // Confirm A, B, C closed
    assert.isFalse(await sortedCdps.contains(_aliceCdpId))
    assert.isFalse(await sortedCdps.contains(_bobCdpId))
    assert.isFalse(await sortedCdps.contains(_carolCdpId))

    // Check sortedList size reduced to 1
    assert.equal((await sortedCdps.getSize()).toString(), '1')

    // Confirm token balances have not changed
    assert.equal((await ebtcToken.balanceOf(alice)).toString(), A_ebtcAmount)
    assert.equal((await ebtcToken.balanceOf(bob)).toString(), B_ebtcAmount)
    assert.equal((await ebtcToken.balanceOf(carol)).toString(), C_ebtcAmount)
  })

  it("liquidate(), with 110% < ICR < TCR, can claim collateral, re-open, be reedemed and claim again", async () => {
    // --- SETUP ---
    // Alice withdraws up to 1500 EBTC of debt, resulting in ICRs of 266%.
    // Bob withdraws up to 480 EBTC of debt, resulting in ICR of 240%. Bob has lowest ICR.
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(240, 16)), extraEBTCAmount: dec(480, 18), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    const { collateral: A_coll } = await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: B_totalDebt, extraParams: { from: alice } })

    // Alice deposits EBTC in the Stability Pool
    await stabilityPool.provideToSP(B_totalDebt, ZERO_ADDRESS, { from: alice })

    // --- TEST ---
    // price drops to 1ETH:100EBTC, reducing TCR below 150%
    await priceFeed.setPrice('100000000000000000000')
    let price = await priceFeed.getPrice()
    const TCR = await th.getTCR(contracts)

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // Check Bob's ICR is between 110 and TCR
    const bob_ICR = await cdpManager.getCurrentICR(_bobCdpId, price)
    assert.isTrue(bob_ICR.gt(mv._MCR) && bob_ICR.lt(TCR))

    // Liquidate Bob
    await cdpManager.liquidate(_bobCdpId, { from: owner })

    // check Bob’s collateral surplus: 5.76 * 100 - 480 * 1.1
    const bob_remainingCollateral = B_coll.sub(B_totalDebt.mul(th.toBN(dec(11, 17))).div(price))
    th.assertIsApproximatelyEqual(await collSurplusPool.getCollateral(bob), bob_remainingCollateral)
    // can claim collateral
    const bob_balanceBefore = th.toBN(await web3.eth.getBalance(bob))
    const BOB_GAS = th.gasUsed(await borrowerOperations.claimCollateral({ from: bob, gasPrice: GAS_PRICE  }))
    const bob_expectedBalance = bob_balanceBefore.sub(th.toBN(BOB_GAS * GAS_PRICE))
    const bob_balanceAfter = th.toBN(await web3.eth.getBalance(bob))
    th.assertIsApproximatelyEqual(bob_balanceAfter, bob_expectedBalance.add(th.toBN(bob_remainingCollateral)))

    // skip bootstrapping phase
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_WEEK * 2, web3.currentProvider)

    // Bob re-opens the cdp, price 200, total debt 80 EBTC, ICR = 120% (lowest one)
    // Dennis redeems 30, so Bob has a surplus of (200 * 0.48 - 30) / 200 = 0.33 ETH
    await priceFeed.setPrice('200000000000000000000')
    const { collateral: B_coll_2, netDebt: B_netDebt_2 } = await openCdp({ ICR: toBN(dec(150, 16)), extraEBTCAmount: dec(480, 18), extraParams: { from: bob, value: bob_remainingCollateral } })
    const { collateral: D_coll } = await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: B_netDebt_2, extraParams: { from: dennis } })
    await th.redeemCollateral(dennis, contracts, B_netDebt_2,GAS_PRICE)
    price = await priceFeed.getPrice()
    const bob_surplus = B_coll_2.sub(B_netDebt_2.mul(mv._1e18BN).div(price))
    th.assertIsApproximatelyEqual(await collSurplusPool.getCollateral(bob), bob_surplus)
    // can claim collateral
    const bob_balanceBefore_2 = th.toBN(await web3.eth.getBalance(bob))
    const BOB_GAS_2 = th.gasUsed(await borrowerOperations.claimCollateral({ from: bob, gasPrice: GAS_PRICE  }))
    const bob_expectedBalance_2 = bob_balanceBefore_2.sub(th.toBN(BOB_GAS_2 * GAS_PRICE))
    const bob_balanceAfter_2 = th.toBN(await web3.eth.getBalance(bob))
    th.assertIsApproximatelyEqual(bob_balanceAfter_2, bob_expectedBalance_2.add(th.toBN(bob_surplus)))
  })

  it("liquidate(), with 110% < ICR < TCR, can claim collateral, after another claim from a redemption", async () => {
    // --- SETUP ---
    // Bob withdraws up to 90 EBTC of debt, resulting in ICR of 222%
    const { collateral: B_coll, netDebt: B_netDebt } = await openCdp({ ICR: toBN(dec(222, 16)), extraEBTCAmount: dec(90, 18), extraParams: { from: bob } })
    // Dennis withdraws to 150 EBTC of debt, resulting in ICRs of 266%.
    const { collateral: D_coll } = await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: B_netDebt, extraParams: { from: dennis } })

    // --- TEST ---
    // skip bootstrapping phase
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_WEEK * 2, web3.currentProvider)

    // Dennis redeems 40, so Bob has a surplus of (200 * 1 - 40) / 200 = 0.8 ETH	
    await th.redeemCollateral(dennis, contracts, B_netDebt, GAS_PRICE)
    let price = await priceFeed.getPrice()
    const bob_surplus = B_coll.sub(B_netDebt.mul(mv._1e18BN).div(price))
    th.assertIsApproximatelyEqual(await collSurplusPool.getCollateral(bob), bob_surplus)

    // can claim collateral
    const bob_balanceBefore = th.toBN(await web3.eth.getBalance(bob))
    const BOB_GAS = th.gasUsed(await borrowerOperations.claimCollateral({ from: bob, gasPrice: GAS_PRICE  }))
    const bob_expectedBalance = bob_balanceBefore.sub(th.toBN(BOB_GAS * GAS_PRICE))
    const bob_balanceAfter = th.toBN(await web3.eth.getBalance(bob))
    th.assertIsApproximatelyEqual(bob_balanceAfter, bob_expectedBalance.add(bob_surplus))

    // Bob re-opens the cdp, price 200, total debt 250 EBTC, ICR = 240% (lowest one)
    const { collateral: B_coll_2, totalDebt: B_totalDebt_2 } = await openCdp({ ICR: toBN(dec(240, 16)), extraParams: { from: bob, value: _3_Ether } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    // Alice deposits EBTC in the Stability Pool
    await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: B_totalDebt_2, extraParams: { from: alice } })
    await stabilityPool.provideToSP(B_totalDebt_2, ZERO_ADDRESS, { from: alice })

    // price drops to 1ETH:100EBTC, reducing TCR below 150%
    await priceFeed.setPrice('100000000000000000000')
    price = await priceFeed.getPrice()
    const TCR = await th.getTCR(contracts)

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // Check Bob's ICR is between 110 and TCR
    const bob_ICR = await cdpManager.getCurrentICR(_bobCdpId, price)
    assert.isTrue(bob_ICR.gt(mv._MCR) && bob_ICR.lt(TCR))
    // debt is increased by fee, due to previous redemption
    const bob_debt = await cdpManager.getCdpDebt(_bobCdpId)

    // Liquidate Bob
    await cdpManager.liquidate(_bobCdpId, { from: owner })

    // check Bob’s collateral surplus
    const bob_remainingCollateral = B_coll_2.sub(B_totalDebt_2.mul(th.toBN(dec(11, 17))).div(price))
    th.assertIsApproximatelyEqual((await collSurplusPool.getCollateral(bob)).toString(), bob_remainingCollateral.toString())

    // can claim collateral
    const bob_balanceBefore_2 = th.toBN(await web3.eth.getBalance(bob))
    const BOB_GAS_2 = th.gasUsed(await borrowerOperations.claimCollateral({ from: bob, gasPrice: GAS_PRICE  }))
    const bob_expectedBalance_2 = bob_balanceBefore_2.sub(th.toBN(BOB_GAS_2 * GAS_PRICE))
    const bob_balanceAfter_2 = th.toBN(await web3.eth.getBalance(bob))
    th.assertIsApproximatelyEqual(bob_balanceAfter_2, bob_expectedBalance_2.add(th.toBN(bob_remainingCollateral)))
  })

  // --- liquidateCdps ---

  it("liquidateCdps(): With all ICRs > 110%, Liquidates Cdps until system leaves recovery mode", async () => {
    // make 8 Cdps accordingly
    // --- SETUP ---

    // Everyone withdraws some EBTC from their Cdp, resulting in different ICRs
    await openCdp({ ICR: toBN(dec(350, 16)), extraParams: { from: bob } })
    await openCdp({ ICR: toBN(dec(286, 16)), extraParams: { from: carol } })
    await openCdp({ ICR: toBN(dec(273, 16)), extraParams: { from: dennis } })
    const { totalDebt: E_totalDebt } = await openCdp({ ICR: toBN(dec(261, 16)), extraParams: { from: erin } })
    const { totalDebt: F_totalDebt } = await openCdp({ ICR: toBN(dec(250, 16)), extraParams: { from: freddy } })
    const { totalDebt: G_totalDebt } = await openCdp({ ICR: toBN(dec(235, 16)), extraParams: { from: greta } })
    const { totalDebt: H_totalDebt } = await openCdp({ ICR: toBN(dec(222, 16)), extraEBTCAmount: dec(5000, 18), extraParams: { from: harry } })
    const liquidationAmount = E_totalDebt.add(F_totalDebt).add(G_totalDebt).add(H_totalDebt)
    await openCdp({ ICR: toBN(dec(400, 16)), extraEBTCAmount: liquidationAmount, extraParams: { from: alice } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);
    let _erinCdpId = await sortedCdps.cdpOfOwnerByIndex(erin, 0);
    let _freddyCdpId = await sortedCdps.cdpOfOwnerByIndex(freddy, 0);
    let _gretaCdpId = await sortedCdps.cdpOfOwnerByIndex(greta, 0);
    let _harryCdpId = await sortedCdps.cdpOfOwnerByIndex(harry, 0);

    // Alice deposits EBTC to Stability Pool
    await stabilityPool.provideToSP(liquidationAmount, ZERO_ADDRESS, { from: alice })

    // price drops
    // price drops to 1ETH:90EBTC, reducing TCR below 150%
    await priceFeed.setPrice('90000000000000000000')
    const price = await priceFeed.getPrice()

    const recoveryMode_Before = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode_Before)

    // check TCR < 150%
    const _150percent = web3.utils.toBN('1500000000000000000')
    const TCR_Before = await th.getTCR(contracts)
    assert.isTrue(TCR_Before.lt(_150percent))

    /* 
   After the price drop and prior to any liquidations, ICR should be:

    Cdp         ICR
    Alice       161%
    Bob         158%
    Carol       129%
    Dennis      123%
    Elisa       117%
    Freddy      113%
    Greta       106%
    Harry       100%

    */
    const alice_ICR = await cdpManager.getCurrentICR(_aliceCdpId, price)
    const bob_ICR = await cdpManager.getCurrentICR(_bobCdpId, price)
    const carol_ICR = await cdpManager.getCurrentICR(_carolCdpId, price)
    const dennis_ICR = await cdpManager.getCurrentICR(_dennisCdpId, price)
    const erin_ICR = await cdpManager.getCurrentICR(_erinCdpId, price)
    const freddy_ICR = await cdpManager.getCurrentICR(_freddyCdpId, price)
    const greta_ICR = await cdpManager.getCurrentICR(_gretaCdpId, price)
    const harry_ICR = await cdpManager.getCurrentICR(_harryCdpId, price)
    const TCR = await th.getTCR(contracts)

    // Alice and Bob should have ICR > TCR
    assert.isTrue(alice_ICR.gt(TCR))
    assert.isTrue(bob_ICR.gt(TCR))
    // All other Cdps should have ICR < TCR
    assert.isTrue(carol_ICR.lt(TCR))
    assert.isTrue(dennis_ICR.lt(TCR))
    assert.isTrue(erin_ICR.lt(TCR))
    assert.isTrue(freddy_ICR.lt(TCR))
    assert.isTrue(greta_ICR.lt(TCR))
    assert.isTrue(harry_ICR.lt(TCR))

    /* Liquidations should occur from the lowest ICR Cdp upwards, i.e. 
    1) Harry, 2) Greta, 3) Freddy, etc.

      Cdp         ICR
    Alice       161%
    Bob         158%
    Carol       129%
    Dennis      123%
    ---- CUTOFF ----
    Elisa       117%
    Freddy      113%
    Greta       106%
    Harry       100%

    If all Cdps below the cutoff are liquidated, the TCR of the system rises above the CCR, to 152%.  (see calculations in Google Sheet)

    Thus, after liquidateCdps(), expect all Cdps to be liquidated up to the cut-off.  
    
    Only Alice, Bob, Carol and Dennis should remain active - all others should be closed. */

    // call liquidate Cdps
    await cdpManager.liquidateCdps(10);

    // check system is no longer in Recovery Mode
    const recoveryMode_After = await th.checkRecoveryMode(contracts)
    assert.isFalse(recoveryMode_After)

    // After liquidation, TCR should rise to above 150%. 
    const TCR_After = await th.getTCR(contracts)
    assert.isTrue(TCR_After.gt(_150percent))

    // get all Cdps
    const alice_Cdp = await cdpManager.Cdps(_aliceCdpId)
    const bob_Cdp = await cdpManager.Cdps(_bobCdpId)
    const carol_Cdp = await cdpManager.Cdps(_carolCdpId)
    const dennis_Cdp = await cdpManager.Cdps(_dennisCdpId)
    const erin_Cdp = await cdpManager.Cdps(_erinCdpId)
    const freddy_Cdp = await cdpManager.Cdps(_freddyCdpId)
    const greta_Cdp = await cdpManager.Cdps(_gretaCdpId)
    const harry_Cdp = await cdpManager.Cdps(_harryCdpId)

    // check that Alice, Bob, Carol, & Dennis' Cdps remain active
    assert.equal(alice_Cdp[3], 1)
    assert.equal(bob_Cdp[3], 1)
    assert.equal(carol_Cdp[3], 1)
    assert.equal(dennis_Cdp[3], 1)
    assert.isTrue(await sortedCdps.contains(_aliceCdpId))
    assert.isTrue(await sortedCdps.contains(_bobCdpId))
    assert.isTrue(await sortedCdps.contains(_carolCdpId))
    assert.isTrue(await sortedCdps.contains(_dennisCdpId))

    // check all other Cdps are liquidated
    assert.equal(erin_Cdp[3], 3)
    assert.equal(freddy_Cdp[3], 3)
    assert.equal(greta_Cdp[3], 3)
    assert.equal(harry_Cdp[3], 3)
    assert.isFalse(await sortedCdps.contains(_erinCdpId))
    assert.isFalse(await sortedCdps.contains(_freddyCdpId))
    assert.isFalse(await sortedCdps.contains(_gretaCdpId))
    assert.isFalse(await sortedCdps.contains(_harryCdpId))
  })

  it("liquidateCdps(): Liquidates Cdps until 1) system has left recovery mode AND 2) it reaches a Cdp with ICR >= 110%", async () => {
    // make 6 Cdps accordingly
    // --- SETUP ---
    const { totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(240, 16)), extraParams: { from: bob } })
    const { totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(240, 16)), extraParams: { from: carol } })
    const { totalDebt: D_totalDebt } = await openCdp({ ICR: toBN(dec(230, 16)), extraParams: { from: dennis } })
    const { totalDebt: E_totalDebt } = await openCdp({ ICR: toBN(dec(240, 16)), extraParams: { from: erin } })
    const { totalDebt: F_totalDebt } = await openCdp({ ICR: toBN(dec(240, 16)), extraParams: { from: freddy } })

    const liquidationAmount = B_totalDebt.add(C_totalDebt).add(D_totalDebt).add(E_totalDebt).add(F_totalDebt)
    await openCdp({ ICR: toBN(dec(400, 16)), extraEBTCAmount: liquidationAmount, extraParams: { from: alice } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);
    let _erinCdpId = await sortedCdps.cdpOfOwnerByIndex(erin, 0);
    let _freddyCdpId = await sortedCdps.cdpOfOwnerByIndex(freddy, 0);

    // Alice deposits EBTC to Stability Pool
    await stabilityPool.provideToSP(liquidationAmount, ZERO_ADDRESS, { from: alice })

    // price drops to 1ETH:85EBTC, reducing TCR below 150%
    await priceFeed.setPrice('85000000000000000000')
    const price = await priceFeed.getPrice()

    // check Recovery Mode kicks in

    const recoveryMode_Before = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode_Before)

    // check TCR < 150%
    const _150percent = web3.utils.toBN('1500000000000000000')
    const TCR_Before = await th.getTCR(contracts)
    assert.isTrue(TCR_Before.lt(_150percent))

    /* 
   After the price drop and prior to any liquidations, ICR should be:

    Cdp         ICR
    Alice       182%
    Bob         102%
    Carol       102%
    Dennis      102%
    Elisa       102%
    Freddy      102%
    */
    alice_ICR = await cdpManager.getCurrentICR(_aliceCdpId, price)
    bob_ICR = await cdpManager.getCurrentICR(_bobCdpId, price)
    carol_ICR = await cdpManager.getCurrentICR(_carolCdpId, price)
    dennis_ICR = await cdpManager.getCurrentICR(_dennisCdpId, price)
    erin_ICR = await cdpManager.getCurrentICR(_erinCdpId, price)
    freddy_ICR = await cdpManager.getCurrentICR(_freddyCdpId, price)

    // Alice should have ICR > 150%
    assert.isTrue(alice_ICR.gt(_150percent))
    // All other Cdps should have ICR < 150%
    assert.isTrue(carol_ICR.lt(_150percent))
    assert.isTrue(dennis_ICR.lt(_150percent))
    assert.isTrue(erin_ICR.lt(_150percent))
    assert.isTrue(freddy_ICR.lt(_150percent))

    /* Liquidations should occur from the lowest ICR Cdp upwards, i.e. 
    1) Freddy, 2) Elisa, 3) Dennis.

    After liquidating Freddy and Elisa, the the TCR of the system rises above the CCR, to 154%.  
   (see calculations in Google Sheet)

    Liquidations continue until all Cdps with ICR < MCR have been closed. 
    Only Alice should remain active - all others should be closed. */

    // call liquidate Cdps
    await cdpManager.liquidateCdps(6);

    // check system is no longer in Recovery Mode
    const recoveryMode_After = await th.checkRecoveryMode(contracts)
    assert.isFalse(recoveryMode_After)

    // After liquidation, TCR should rise to above 150%. 
    const TCR_After = await th.getTCR(contracts)
    assert.isTrue(TCR_After.gt(_150percent))

    // get all Cdps
    const alice_Cdp = await cdpManager.Cdps(_aliceCdpId)
    const bob_Cdp = await cdpManager.Cdps(_bobCdpId)
    const carol_Cdp = await cdpManager.Cdps(_carolCdpId)
    const dennis_Cdp = await cdpManager.Cdps(_dennisCdpId)
    const erin_Cdp = await cdpManager.Cdps(_erinCdpId)
    const freddy_Cdp = await cdpManager.Cdps(_freddyCdpId)

    // check that Alice's Cdp remains active
    assert.equal(alice_Cdp[3], 1)
    assert.isTrue(await sortedCdps.contains(_aliceCdpId))

    // check all other Cdps are liquidated
    assert.equal(bob_Cdp[3], 3)
    assert.equal(carol_Cdp[3], 3)
    assert.equal(dennis_Cdp[3], 3)
    assert.equal(erin_Cdp[3], 3)
    assert.equal(freddy_Cdp[3], 3)

    assert.isFalse(await sortedCdps.contains(_bobCdpId))
    assert.isFalse(await sortedCdps.contains(_carolCdpId))
    assert.isFalse(await sortedCdps.contains(_dennisCdpId))
    assert.isFalse(await sortedCdps.contains(_erinCdpId))
    assert.isFalse(await sortedCdps.contains(_freddyCdpId))
  })

  it('liquidateCdps(): liquidates only up to the requested number of undercollateralized cdps', async () => {
    await openCdp({ ICR: toBN(dec(300, 16)), extraParams: { from: whale, value: dec(300, 'ether') } })

    // --- SETUP --- 
    // Alice, Bob, Carol, Dennis, Erin open cdps with consecutively increasing collateral ratio
    await openCdp({ ICR: toBN(dec(210, 16)), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(212, 16)), extraParams: { from: bob } })
    await openCdp({ ICR: toBN(dec(214, 16)), extraParams: { from: carol } })
    await openCdp({ ICR: toBN(dec(216, 16)), extraParams: { from: dennis } })
    await openCdp({ ICR: toBN(dec(218, 16)), extraParams: { from: erin } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);
    let _erinCdpId = await sortedCdps.cdpOfOwnerByIndex(erin, 0);

    await priceFeed.setPrice(dec(100, 18))

    const TCR = await th.getTCR(contracts)

    assert.isTrue(TCR.lte(web3.utils.toBN(dec(150, 18))))
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // --- TEST --- 

    // Price drops
    await priceFeed.setPrice(dec(100, 18))

    await cdpManager.liquidateCdps(3)

    // Check system still in Recovery Mode after liquidation tx
    assert.isTrue(await th.checkRecoveryMode(contracts))

    const CdpOwnersArrayLength = await cdpManager.getCdpIdsCount()
    assert.equal(CdpOwnersArrayLength, '3')

    // Check Alice, Bob, Carol cdps have been closed
    const aliceCdpStatus = (await cdpManager.getCdpStatus(_aliceCdpId)).toString()
    const bobCdpStatus = (await cdpManager.getCdpStatus(_bobCdpId)).toString()
    const carolCdpStatus = (await cdpManager.getCdpStatus(_carolCdpId)).toString()

    assert.equal(aliceCdpStatus, '3')
    assert.equal(bobCdpStatus, '3')
    assert.equal(carolCdpStatus, '3')

    //  Check Alice, Bob, and Carol's cdp are no longer in the sorted list
    const alice_isInSortedList = await sortedCdps.contains(_aliceCdpId)
    const bob_isInSortedList = await sortedCdps.contains(_bobCdpId)
    const carol_isInSortedList = await sortedCdps.contains(_carolCdpId)

    assert.isFalse(alice_isInSortedList)
    assert.isFalse(bob_isInSortedList)
    assert.isFalse(carol_isInSortedList)

    // Check Dennis, Erin still have active cdps
    const dennisCdpStatus = (await cdpManager.getCdpStatus(_dennisCdpId)).toString()
    const erinCdpStatus = (await cdpManager.getCdpStatus(_erinCdpId)).toString()

    assert.equal(dennisCdpStatus, '1')
    assert.equal(erinCdpStatus, '1')

    // Check Dennis, Erin still in sorted list
    const dennis_isInSortedList = await sortedCdps.contains(_dennisCdpId)
    const erin_isInSortedList = await sortedCdps.contains(_erinCdpId)

    assert.isTrue(dennis_isInSortedList)
    assert.isTrue(erin_isInSortedList)
  })

  it("liquidateCdps(): does nothing if n = 0", async () => {
    await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(200, 18), extraParams: { from: bob } })
    await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(300, 18), extraParams: { from: carol } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    await priceFeed.setPrice(dec(100, 18))
    const price = await priceFeed.getPrice()

    const TCR_Before = (await th.getTCR(contracts)).toString()

    // Confirm A, B, C ICRs are below 110%

    const alice_ICR = await cdpManager.getCurrentICR(_aliceCdpId, price)
    const bob_ICR = await cdpManager.getCurrentICR(_bobCdpId, price)
    const carol_ICR = await cdpManager.getCurrentICR(_carolCdpId, price)
    assert.isTrue(alice_ICR.lte(mv._MCR))
    assert.isTrue(bob_ICR.lte(mv._MCR))
    assert.isTrue(carol_ICR.lte(mv._MCR))

    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Liquidation with n = 0
    await assertRevert(cdpManager.liquidateCdps(0), "CdpManager: nothing to liquidate")

    // Check all cdps are still in the system
    assert.isTrue(await sortedCdps.contains(_aliceCdpId))
    assert.isTrue(await sortedCdps.contains(_bobCdpId))
    assert.isTrue(await sortedCdps.contains(_carolCdpId))

    const TCR_After = (await th.getTCR(contracts)).toString()

    // Check TCR has not changed after liquidation
    assert.equal(TCR_Before, TCR_After)
  })

  it('liquidateCdps(): closes every Cdp with ICR < MCR, when n > number of undercollateralized cdps', async () => {
    // --- SETUP --- 
    await openCdp({ ICR: toBN(dec(300, 16)), extraParams: { from: whale, value: dec(300, 'ether') } })

    // create 5 Cdps with varying ICRs
    await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(133, 16)), extraParams: { from: bob } })
    await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(300, 18), extraParams: { from: carol } })
    await openCdp({ ICR: toBN(dec(182, 16)), extraParams: { from: erin } })
    await openCdp({ ICR: toBN(dec(111, 16)), extraParams: { from: freddy } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _freddyCdpId = await sortedCdps.cdpOfOwnerByIndex(freddy, 0);
    let _erinCdpId = await sortedCdps.cdpOfOwnerByIndex(erin, 0);

    // Whale puts some tokens in Stability Pool
    await stabilityPool.provideToSP(dec(300, 18), ZERO_ADDRESS, { from: whale })

    // --- TEST ---

    // Price drops to 1ETH:100EBTC, reducing Bob and Carol's ICR below MCR
    await priceFeed.setPrice(dec(100, 18));
    const price = await priceFeed.getPrice()

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Confirm cdps A-E are ICR < 110%
    assert.isTrue((await cdpManager.getCurrentICR(_aliceCdpId, price)).lte(mv._MCR))
    assert.isTrue((await cdpManager.getCurrentICR(_bobCdpId, price)).lte(mv._MCR))
    assert.isTrue((await cdpManager.getCurrentICR(_carolCdpId, price)).lte(mv._MCR))
    assert.isTrue((await cdpManager.getCurrentICR(_erinCdpId, price)).lte(mv._MCR))
    assert.isTrue((await cdpManager.getCurrentICR(_freddyCdpId, price)).lte(mv._MCR))

    // Confirm Whale is ICR > 110% 
    assert.isTrue((await cdpManager.getCurrentICR(whale, price)).gte(mv._MCR))

    // Liquidate 5 cdps
    await cdpManager.liquidateCdps(5);

    // Confirm cdps A-E have been removed from the system
    assert.isFalse(await sortedCdps.contains(_aliceCdpId))
    assert.isFalse(await sortedCdps.contains(_bobCdpId))
    assert.isFalse(await sortedCdps.contains(_carolCdpId))
    assert.isFalse(await sortedCdps.contains(_erinCdpId))
    assert.isFalse(await sortedCdps.contains(_freddyCdpId))

    // Check all cdps are now liquidated
    assert.equal((await cdpManager.Cdps(_aliceCdpId))[3].toString(), '3')
    assert.equal((await cdpManager.Cdps(_bobCdpId))[3].toString(), '3')
    assert.equal((await cdpManager.Cdps(_carolCdpId))[3].toString(), '3')
    assert.equal((await cdpManager.Cdps(_erinCdpId))[3].toString(), '3')
    assert.equal((await cdpManager.Cdps(_freddyCdpId))[3].toString(), '3')
  })

  it("liquidateCdps(): a liquidation sequence containing Pool offsets increases the TCR", async () => {
    // Whale provides 500 EBTC to SP
    await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(500, 18), extraParams: { from: whale } })
    await stabilityPool.provideToSP(dec(500, 18), ZERO_ADDRESS, { from: whale })

    await openCdp({ ICR: toBN(dec(300, 16)), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(320, 16)), extraParams: { from: carol } })
    await openCdp({ ICR: toBN(dec(340, 16)), extraParams: { from: dennis } })

    await openCdp({ ICR: toBN(dec(198, 16)), extraEBTCAmount: dec(101, 18), extraParams: { from: defaulter_1 } })
    await openCdp({ ICR: toBN(dec(184, 16)), extraEBTCAmount: dec(217, 18), extraParams: { from: defaulter_2 } })
    await openCdp({ ICR: toBN(dec(183, 16)), extraEBTCAmount: dec(328, 18), extraParams: { from: defaulter_3 } })
    await openCdp({ ICR: toBN(dec(186, 16)), extraEBTCAmount: dec(431, 18), extraParams: { from: defaulter_4 } })
    let _defaulter1CdpId = await sortedCdps.cdpOfOwnerByIndex(defaulter_1, 0);
    let _defaulter2CdpId = await sortedCdps.cdpOfOwnerByIndex(defaulter_2, 0);
    let _defaulter3CdpId = await sortedCdps.cdpOfOwnerByIndex(defaulter_3, 0);
    let _defaulter4CdpId = await sortedCdps.cdpOfOwnerByIndex(defaulter_4, 0);

    assert.isTrue((await sortedCdps.contains(_defaulter1CdpId)))
    assert.isTrue((await sortedCdps.contains(_defaulter2CdpId)))
    assert.isTrue((await sortedCdps.contains(_defaulter3CdpId)))
    assert.isTrue((await sortedCdps.contains(_defaulter4CdpId)))


    // Price drops
    await priceFeed.setPrice(dec(110, 18))
    const price = await priceFeed.getPrice()

    assert.isTrue(await th.ICRbetween100and110(_defaulter1CdpId, cdpManager, price))
    assert.isTrue(await th.ICRbetween100and110(_defaulter2CdpId, cdpManager, price))
    assert.isTrue(await th.ICRbetween100and110(_defaulter3CdpId, cdpManager, price))
    assert.isTrue(await th.ICRbetween100and110(_defaulter4CdpId, cdpManager, price))

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    const TCR_Before = await th.getTCR(contracts)

    // Check Stability Pool has 500 EBTC
    assert.equal((await stabilityPool.getTotalEBTCDeposits()).toString(), dec(500, 18))

    await cdpManager.liquidateCdps(8)

    // assert.isFalse((await sortedCdps.contains(defaulter_1)))
    // assert.isFalse((await sortedCdps.contains(defaulter_2)))
    // assert.isFalse((await sortedCdps.contains(defaulter_3)))
    assert.isFalse((await sortedCdps.contains(_defaulter4CdpId)))

    // Check Stability Pool has been emptied by the liquidations
    assert.equal((await stabilityPool.getTotalEBTCDeposits()).toString(), '0')

    // Check that the liquidation sequence has improved the TCR
    const TCR_After = await th.getTCR(contracts)
    assert.isTrue(TCR_After.gte(TCR_Before))
  })

  it("liquidateCdps(): A liquidation sequence of pure redistributions decreases the TCR, due to gas compensation, but up to 0.5%", async () => {
    const { collateral: W_coll, totalDebt: W_totalDebt } = await openCdp({ ICR: toBN(dec(250, 16)), extraEBTCAmount: dec(500, 18), extraParams: { from: whale } })

    const { collateral: A_coll, totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(300, 16)), extraParams: { from: alice } })
    const { collateral: C_coll, totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(400, 16)), extraParams: { from: carol } })
    const { collateral: D_coll, totalDebt: D_totalDebt } = await openCdp({ ICR: toBN(dec(600, 16)), extraParams: { from: dennis } })

    const { collateral: d1_coll, totalDebt: d1_totalDebt } = await openCdp({ ICR: toBN(dec(198, 16)), extraEBTCAmount: dec(101, 18), extraParams: { from: defaulter_1 } })
    const { collateral: d2_coll, totalDebt: d2_totalDebt } = await openCdp({ ICR: toBN(dec(184, 16)), extraEBTCAmount: dec(217, 18), extraParams: { from: defaulter_2 } })
    const { collateral: d3_coll, totalDebt: d3_totalDebt } = await openCdp({ ICR: toBN(dec(183, 16)), extraEBTCAmount: dec(328, 18), extraParams: { from: defaulter_3 } })
    const { collateral: d4_coll, totalDebt: d4_totalDebt } = await openCdp({ ICR: toBN(dec(166, 16)), extraEBTCAmount: dec(431, 18), extraParams: { from: defaulter_4 } })
    let _defaulter1CdpId = await sortedCdps.cdpOfOwnerByIndex(defaulter_1, 0);
    let _defaulter2CdpId = await sortedCdps.cdpOfOwnerByIndex(defaulter_2, 0);
    let _defaulter3CdpId = await sortedCdps.cdpOfOwnerByIndex(defaulter_3, 0);
    let _defaulter4CdpId = await sortedCdps.cdpOfOwnerByIndex(defaulter_4, 0);

    assert.isTrue((await sortedCdps.contains(_defaulter1CdpId)))
    assert.isTrue((await sortedCdps.contains(_defaulter2CdpId)))
    assert.isTrue((await sortedCdps.contains(_defaulter3CdpId)))
    assert.isTrue((await sortedCdps.contains(_defaulter4CdpId)))

    // Price drops
    const price = toBN(dec(100, 18))
    await priceFeed.setPrice(price)

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    const TCR_Before = await th.getTCR(contracts)
    // (5+1+2+3+1+2+3+4)*100/(410+50+50+50+101+257+328+480)
    const totalCollBefore = W_coll.add(A_coll).add(C_coll).add(D_coll).add(d1_coll).add(d2_coll).add(d3_coll).add(d4_coll)
    const totalDebtBefore = W_totalDebt.add(A_totalDebt).add(C_totalDebt).add(D_totalDebt).add(d1_totalDebt).add(d2_totalDebt).add(d3_totalDebt).add(d4_totalDebt)
    assert.isAtMost(th.getDifference(TCR_Before, totalCollBefore.mul(price).div(totalDebtBefore)), 1000)

    // Check pool is empty before liquidation
    assert.equal((await stabilityPool.getTotalEBTCDeposits()).toString(), '0')

    // Liquidate
    await cdpManager.liquidateCdps(8)

    // Check all defaulters have been liquidated
    assert.isFalse((await sortedCdps.contains(_defaulter1CdpId)))
    assert.isFalse((await sortedCdps.contains(_defaulter2CdpId)))
    assert.isFalse((await sortedCdps.contains(_defaulter3CdpId)))
    assert.isFalse((await sortedCdps.contains(_defaulter4CdpId)))

    // Check that the liquidation sequence has reduced the TCR
    const TCR_After = await th.getTCR(contracts)
    // ((5+1+2+3)+(1+2+3+4)*0.995)*100/(410+50+50+50+101+257+328+480)
    const totalCollAfter = W_coll.add(A_coll).add(C_coll).add(D_coll).add(th.applyLiquidationFee(d1_coll.add(d2_coll).add(d3_coll).add(d4_coll)))
    const totalDebtAfter = W_totalDebt.add(A_totalDebt).add(C_totalDebt).add(D_totalDebt).add(d1_totalDebt).add(d2_totalDebt).add(d3_totalDebt).add(d4_totalDebt)
    assert.isAtMost(th.getDifference(TCR_After, totalCollAfter.mul(price).div(totalDebtAfter)), 1000)
    assert.isTrue(TCR_Before.gte(TCR_After))
    assert.isTrue(TCR_After.gte(TCR_Before.mul(th.toBN(995)).div(th.toBN(1000))))
  })

  it("liquidateCdps(): liquidates based on entire/collateral debt (including pending rewards), not raw collateral/debt", async () => {
    await openCdp({ ICR: toBN(dec(400, 16)), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(220, 16)), extraParams: { from: bob } })
    await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: carol } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    // Defaulter opens with 60 EBTC, 0.6 ETH
    await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: defaulter_1 } })
    let _defaulter1CdpId = await sortedCdps.cdpOfOwnerByIndex(defaulter_1, 0);

    // Price drops
    await priceFeed.setPrice(dec(100, 18))
    const price = await priceFeed.getPrice()

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    const alice_ICR_Before = await cdpManager.getCurrentICR(_aliceCdpId, price)
    const bob_ICR_Before = await cdpManager.getCurrentICR(_bobCdpId, price)
    const carol_ICR_Before = await cdpManager.getCurrentICR(_carolCdpId, price)

    /* Before liquidation: 
    Alice ICR: = (1 * 100 / 50) = 200%
    Bob ICR: (1 * 100 / 90.5) = 110.5%
    Carol ICR: (1 * 100 / 100 ) =  100%

    Therefore Alice and Bob above the MCR, Carol is below */
    assert.isTrue(alice_ICR_Before.gte(mv._MCR))
    assert.isTrue(bob_ICR_Before.gte(mv._MCR))
    assert.isTrue(carol_ICR_Before.lte(mv._MCR))

    // Liquidate defaulter. 30 EBTC and 0.3 ETH is distributed uniformly between A, B and C. Each receive 10 EBTC, 0.1 ETH
    await cdpManager.liquidate(_defaulter1CdpId)

    const alice_ICR_After = await cdpManager.getCurrentICR(_aliceCdpId, price)
    const bob_ICR_After = await cdpManager.getCurrentICR(_bobCdpId, price)
    const carol_ICR_After = await cdpManager.getCurrentICR(_carolCdpId, price)

    /* After liquidation: 

    Alice ICR: (1.1 * 100 / 60) = 183.33%
    Bob ICR:(1.1 * 100 / 100.5) =  109.45%
    Carol ICR: (1.1 * 100 ) 100%

    Check Alice is above MCR, Bob below, Carol below. */
    assert.isTrue(alice_ICR_After.gte(mv._MCR))
    assert.isTrue(bob_ICR_After.lte(mv._MCR))
    assert.isTrue(carol_ICR_After.lte(mv._MCR))

    /* Though Bob's true ICR (including pending rewards) is below the MCR, 
   check that Bob's raw coll and debt has not changed, and that his "raw" ICR is above the MCR */
    const bob_Coll = (await cdpManager.Cdps(_bobCdpId))[1]
    const bob_Debt = (await cdpManager.Cdps(_bobCdpId))[0]

    const bob_rawICR = bob_Coll.mul(th.toBN(dec(100, 18))).div(bob_Debt)
    assert.isTrue(bob_rawICR.gte(mv._MCR))

    // Liquidate A, B, C
    await cdpManager.liquidateCdps(10)

    /*  Since there is 0 EBTC in the stability Pool, A, with ICR >110%, should stay active.
   Check Alice stays active, Carol gets liquidated, and Bob gets liquidated 
   (because his pending rewards bring his ICR < MCR) */
    assert.isTrue(await sortedCdps.contains(_aliceCdpId))
    assert.isFalse(await sortedCdps.contains(_bobCdpId))
    assert.isFalse(await sortedCdps.contains(_carolCdpId))

    // check cdp statuses - A active (1),  B and C liquidated (3)
    assert.equal((await cdpManager.Cdps(_aliceCdpId))[3].toString(), '1')
    assert.equal((await cdpManager.Cdps(_bobCdpId))[3].toString(), '3')
    assert.equal((await cdpManager.Cdps(_carolCdpId))[3].toString(), '3')
  })

  it('liquidateCdps(): does nothing if all cdps have ICR > 110% and Stability Pool is empty', async () => {
    await openCdp({ ICR: toBN(dec(222, 16)), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(250, 16)), extraParams: { from: bob } })
    await openCdp({ ICR: toBN(dec(285, 16)), extraParams: { from: carol } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    // Price drops, but all cdps remain active
    await priceFeed.setPrice(dec(100, 18))
    const price = await priceFeed.getPrice()

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    assert.isTrue((await sortedCdps.contains(_aliceCdpId)))
    assert.isTrue((await sortedCdps.contains(_bobCdpId)))
    assert.isTrue((await sortedCdps.contains(_carolCdpId)))

    const TCR_Before = (await th.getTCR(contracts)).toString()
    const listSize_Before = (await sortedCdps.getSize()).toString()


    assert.isTrue((await cdpManager.getCurrentICR(_aliceCdpId, price)).gte(mv._MCR))
    assert.isTrue((await cdpManager.getCurrentICR(_bobCdpId, price)).gte(mv._MCR))
    assert.isTrue((await cdpManager.getCurrentICR(_carolCdpId, price)).gte(mv._MCR))

    // Confirm 0 EBTC in Stability Pool
    assert.equal((await stabilityPool.getTotalEBTCDeposits()).toString(), '0')

    // Attempt liqudation sequence
    await assertRevert(cdpManager.liquidateCdps(10), "CdpManager: nothing to liquidate")

    // Check all cdps remain active
    assert.isTrue((await sortedCdps.contains(_aliceCdpId)))
    assert.isTrue((await sortedCdps.contains(_bobCdpId)))
    assert.isTrue((await sortedCdps.contains(_carolCdpId)))

    const TCR_After = (await th.getTCR(contracts)).toString()
    const listSize_After = (await sortedCdps.getSize()).toString()

    assert.equal(TCR_Before, TCR_After)
    assert.equal(listSize_Before, listSize_After)
  })

  it('liquidateCdps(): emits liquidation event with correct values when all cdps have ICR > 110% and Stability Pool covers a subset of cdps', async () => {
    // Cdps to be absorbed by SP
    const { collateral: F_coll, totalDebt: F_totalDebt } = await openCdp({ ICR: toBN(dec(222, 16)), extraParams: { from: freddy } })
    const { collateral: G_coll, totalDebt: G_totalDebt } = await openCdp({ ICR: toBN(dec(222, 16)), extraParams: { from: greta } })

    // Cdps to be spared
    await openCdp({ ICR: toBN(dec(250, 16)), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(266, 16)), extraParams: { from: bob } })
    await openCdp({ ICR: toBN(dec(285, 16)), extraParams: { from: carol } })
    await openCdp({ ICR: toBN(dec(308, 16)), extraParams: { from: dennis } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);
    let _freddyCdpId = await sortedCdps.cdpOfOwnerByIndex(freddy, 0);
    let _gretaCdpId = await sortedCdps.cdpOfOwnerByIndex(greta, 0);

    // Whale adds EBTC to SP
    const spDeposit = F_totalDebt.add(G_totalDebt)
    await openCdp({ ICR: toBN(dec(285, 16)), extraEBTCAmount: spDeposit, extraParams: { from: whale } })
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: whale })
    let _whaleCdpId = await sortedCdps.cdpOfOwnerByIndex(whale, 0);

    // Price drops, but all cdps remain active
    await priceFeed.setPrice(dec(100, 18))
    const price = await priceFeed.getPrice()

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Confirm all cdps have ICR > MCR
    assert.isTrue((await cdpManager.getCurrentICR(_freddyCdpId, price)).gte(mv._MCR))
    assert.isTrue((await cdpManager.getCurrentICR(_gretaCdpId, price)).gte(mv._MCR))
    assert.isTrue((await cdpManager.getCurrentICR(_aliceCdpId, price)).gte(mv._MCR))
    assert.isTrue((await cdpManager.getCurrentICR(_bobCdpId, price)).gte(mv._MCR))
    assert.isTrue((await cdpManager.getCurrentICR(_carolCdpId, price)).gte(mv._MCR))

    // Confirm EBTC in Stability Pool
    assert.equal((await stabilityPool.getTotalEBTCDeposits()).toString(), spDeposit.toString())

    // Attempt liqudation sequence
    const liquidationTx = await cdpManager.liquidateCdps(10)
    const [liquidatedDebt, liquidatedColl, gasComp] = th.getEmittedLiquidationValues(liquidationTx)

    // Check F and G were liquidated
    assert.isFalse(await sortedCdps.contains(_freddyCdpId))
    assert.isFalse(await sortedCdps.contains(_gretaCdpId))

    // Check whale and A-D remain active
    assert.isTrue(await sortedCdps.contains(_aliceCdpId))
    assert.isTrue(await sortedCdps.contains(_bobCdpId))
    assert.isTrue(await sortedCdps.contains(_carolCdpId))
    assert.isTrue(await sortedCdps.contains(_dennisCdpId))
    assert.isTrue(await sortedCdps.contains(_whaleCdpId))

    // Liquidation event emits coll = (F_debt + G_debt)/price*1.1*0.995, and debt = (F_debt + G_debt)
    th.assertIsApproximatelyEqual(liquidatedDebt, F_totalDebt.add(G_totalDebt))
    th.assertIsApproximatelyEqual(liquidatedColl, th.applyLiquidationFee(F_totalDebt.add(G_totalDebt).mul(toBN(dec(11, 17))).div(price)))

    // check collateral surplus
    const freddy_remainingCollateral = F_coll.sub(F_totalDebt.mul(th.toBN(dec(11, 17))).div(price))
    const greta_remainingCollateral = G_coll.sub(G_totalDebt.mul(th.toBN(dec(11, 17))).div(price))
    th.assertIsApproximatelyEqual(await collSurplusPool.getCollateral(freddy), freddy_remainingCollateral)
    th.assertIsApproximatelyEqual(await collSurplusPool.getCollateral(greta), greta_remainingCollateral)

    // can claim collateral
    const freddy_balanceBefore = th.toBN(await web3.eth.getBalance(freddy))
    const FREDDY_GAS = th.gasUsed(await borrowerOperations.claimCollateral({ from: freddy, gasPrice: GAS_PRICE  }))
    const freddy_expectedBalance = freddy_balanceBefore.sub(th.toBN(FREDDY_GAS * GAS_PRICE))
    const freddy_balanceAfter = th.toBN(await web3.eth.getBalance(freddy))
    th.assertIsApproximatelyEqual(freddy_balanceAfter, freddy_expectedBalance.add(th.toBN(freddy_remainingCollateral)))

    const greta_balanceBefore = th.toBN(await web3.eth.getBalance(greta))
    const GRETA_GAS = th.gasUsed(await borrowerOperations.claimCollateral({ from: greta, gasPrice: GAS_PRICE  }))
    const greta_expectedBalance = greta_balanceBefore.sub(th.toBN(GRETA_GAS * GAS_PRICE))
    const greta_balanceAfter = th.toBN(await web3.eth.getBalance(greta))
    th.assertIsApproximatelyEqual(greta_balanceAfter, greta_expectedBalance.add(th.toBN(greta_remainingCollateral)))
  })

  it('liquidateCdps():  emits liquidation event with correct values when all cdps have ICR > 110% and Stability Pool covers a subset of cdps, including a partial', async () => {
    // Cdps to be absorbed by SP
    const { collateral: F_coll, totalDebt: F_totalDebt } = await openCdp({ ICR: toBN(dec(222, 16)), extraParams: { from: freddy } })
    const { collateral: G_coll, totalDebt: G_totalDebt } = await openCdp({ ICR: toBN(dec(222, 16)), extraParams: { from: greta } })

    // Cdps to be spared
    const { collateral: A_coll, totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(250, 16)), extraParams: { from: alice } })
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(266, 16)), extraParams: { from: bob } })
    const { collateral: C_coll, totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(285, 16)), extraParams: { from: carol } })
    const { collateral: D_coll, totalDebt: D_totalDebt } = await openCdp({ ICR: toBN(dec(308, 16)), extraParams: { from: dennis } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);
    let _freddyCdpId = await sortedCdps.cdpOfOwnerByIndex(freddy, 0);
    let _gretaCdpId = await sortedCdps.cdpOfOwnerByIndex(greta, 0);

    // Whale adds EBTC to SP
    const spDeposit = F_totalDebt.add(G_totalDebt).add(A_totalDebt.div(toBN(2)))
    const { collateral: W_coll, totalDebt: W_totalDebt } = await openCdp({ ICR: toBN(dec(285, 16)), extraEBTCAmount: spDeposit, extraParams: { from: whale } })
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: whale })
    let _whaleCdpId = await sortedCdps.cdpOfOwnerByIndex(whale, 0);

    // Price drops, but all cdps remain active
    await priceFeed.setPrice(dec(100, 18))
    const price = await priceFeed.getPrice()

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Confirm all cdps have ICR > MCR
    assert.isTrue((await cdpManager.getCurrentICR(_freddyCdpId, price)).gte(mv._MCR))
    assert.isTrue((await cdpManager.getCurrentICR(_gretaCdpId, price)).gte(mv._MCR))
    assert.isTrue((await cdpManager.getCurrentICR(_aliceCdpId, price)).gte(mv._MCR))
    assert.isTrue((await cdpManager.getCurrentICR(_bobCdpId, price)).gte(mv._MCR))
    assert.isTrue((await cdpManager.getCurrentICR(_carolCdpId, price)).gte(mv._MCR))

    // Confirm EBTC in Stability Pool
    assert.equal((await stabilityPool.getTotalEBTCDeposits()).toString(), spDeposit.toString())

    // Attempt liqudation sequence
    const liquidationTx = await cdpManager.liquidateCdps(10)
    const [liquidatedDebt, liquidatedColl, gasComp] = th.getEmittedLiquidationValues(liquidationTx)

    // Check F and G were liquidated
    assert.isFalse(await sortedCdps.contains(_freddyCdpId))
    assert.isFalse(await sortedCdps.contains(_gretaCdpId))

    // Check whale and A-D remain active
    assert.isTrue(await sortedCdps.contains(_aliceCdpId))
    assert.isTrue(await sortedCdps.contains(_bobCdpId))
    assert.isTrue(await sortedCdps.contains(_carolCdpId))
    assert.isTrue(await sortedCdps.contains(_dennisCdpId))
    assert.isTrue(await sortedCdps.contains(_whaleCdpId))

    // Check A's collateral and debt remain the same
    const entireColl_A = (await cdpManager.Cdps(_aliceCdpId))[1].add(await cdpManager.getPendingETHReward(_aliceCdpId))
    const entireDebt_A = (await cdpManager.Cdps(_aliceCdpId))[0].add((await cdpManager.getPendingEBTCDebtReward(_aliceCdpId))[0])

    assert.equal(entireColl_A.toString(), A_coll)
    assert.equal(entireDebt_A.toString(), A_totalDebt)

    /* Liquidation event emits:
    coll = (F_debt + G_debt)/price*1.1*0.995
    debt = (F_debt + G_debt) */
    th.assertIsApproximatelyEqual(liquidatedDebt, F_totalDebt.add(G_totalDebt))
    th.assertIsApproximatelyEqual(liquidatedColl, th.applyLiquidationFee(F_totalDebt.add(G_totalDebt).mul(toBN(dec(11, 17))).div(price)))

    // check collateral surplus
    const freddy_remainingCollateral = F_coll.sub(F_totalDebt.mul(th.toBN(dec(11, 17))).div(price))
    const greta_remainingCollateral = G_coll.sub(G_totalDebt.mul(th.toBN(dec(11, 17))).div(price))
    th.assertIsApproximatelyEqual(await collSurplusPool.getCollateral(freddy), freddy_remainingCollateral)
    th.assertIsApproximatelyEqual(await collSurplusPool.getCollateral(greta), greta_remainingCollateral)

    // can claim collateral
    const freddy_balanceBefore = th.toBN(await web3.eth.getBalance(freddy))
    const FREDDY_GAS = th.gasUsed(await borrowerOperations.claimCollateral({ from: freddy, gasPrice: GAS_PRICE  }))
    const freddy_expectedBalance = freddy_balanceBefore.sub(th.toBN(FREDDY_GAS * GAS_PRICE))
    const freddy_balanceAfter = th.toBN(await web3.eth.getBalance(freddy))
    th.assertIsApproximatelyEqual(freddy_balanceAfter, freddy_expectedBalance.add(th.toBN(freddy_remainingCollateral)))

    const greta_balanceBefore = th.toBN(await web3.eth.getBalance(greta))
    const GRETA_GAS = th.gasUsed(await borrowerOperations.claimCollateral({ from: greta, gasPrice: GAS_PRICE  }))
    const greta_expectedBalance = greta_balanceBefore.sub(th.toBN(GRETA_GAS * GAS_PRICE))
    const greta_balanceAfter = th.toBN(await web3.eth.getBalance(greta))
    th.assertIsApproximatelyEqual(greta_balanceAfter, greta_expectedBalance.add(th.toBN(greta_remainingCollateral)))
  })

  it("liquidateCdps(): does not affect the liquidated user's token balances", async () => {
    await openCdp({ ICR: toBN(dec(300, 16)), extraParams: { from: whale } })

    // D, E, F open cdps that will fall below MCR when price drops to 100
    const { ebtcAmount: ebtcAmountD } = await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: dennis } })
    const { ebtcAmount: ebtcAmountE } = await openCdp({ ICR: toBN(dec(133, 16)), extraParams: { from: erin } })
    const { ebtcAmount: ebtcAmountF } = await openCdp({ ICR: toBN(dec(111, 16)), extraParams: { from: freddy } })
    let _whaleCdpId = await sortedCdps.cdpOfOwnerByIndex(whale, 0);
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);
    let _freddyCdpId = await sortedCdps.cdpOfOwnerByIndex(freddy, 0);
    let _erinCdpId = await sortedCdps.cdpOfOwnerByIndex(erin, 0);

    // Check list size is 4
    assert.equal((await sortedCdps.getSize()).toString(), '4')

    // Check token balances before
    assert.equal((await ebtcToken.balanceOf(dennis)).toString(), ebtcAmountD)
    assert.equal((await ebtcToken.balanceOf(erin)).toString(), ebtcAmountE)
    assert.equal((await ebtcToken.balanceOf(freddy)).toString(), ebtcAmountF)

    // Price drops
    await priceFeed.setPrice(dec(100, 18))

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    //Liquidate sequence
    await cdpManager.liquidateCdps(10)

    // Check Whale remains in the system
    assert.isTrue(await sortedCdps.contains(_whaleCdpId))

    // Check D, E, F have been removed
    assert.isFalse(await sortedCdps.contains(_dennisCdpId))
    assert.isFalse(await sortedCdps.contains(_erinCdpId))
    assert.isFalse(await sortedCdps.contains(_freddyCdpId))

    // Check token balances of users whose cdps were liquidated, have not changed
    assert.equal((await ebtcToken.balanceOf(dennis)).toString(), ebtcAmountD)
    assert.equal((await ebtcToken.balanceOf(erin)).toString(), ebtcAmountE)
    assert.equal((await ebtcToken.balanceOf(freddy)).toString(), ebtcAmountF)
  })

  it("liquidateCdps(): Liquidating cdps at 100 < ICR < 110 with SP deposits correctly impacts their SP deposit and ETH gain", async () => {
    // Whale provides EBTC to the SP
    const { ebtcAmount: W_ebtcAmount } = await openCdp({ ICR: toBN(dec(300, 16)), extraEBTCAmount: dec(4000, 18), extraParams: { from: whale } })
    await stabilityPool.provideToSP(W_ebtcAmount, ZERO_ADDRESS, { from: whale })

    const { ebtcAmount: A_ebtcAmount, totalDebt: A_totalDebt, collateral: A_coll } = await openCdp({ ICR: toBN(dec(191, 16)), extraEBTCAmount: dec(40, 18), extraParams: { from: alice } })
    const { ebtcAmount: B_ebtcAmount, totalDebt: B_totalDebt, collateral: B_coll } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(240, 18), extraParams: { from: bob } })
    const { totalDebt: C_totalDebt, collateral: C_coll} = await openCdp({ ICR: toBN(dec(209, 16)), extraParams: { from: carol } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    // A, B provide to the SP
    await stabilityPool.provideToSP(A_ebtcAmount, ZERO_ADDRESS, { from: alice })
    await stabilityPool.provideToSP(B_ebtcAmount, ZERO_ADDRESS, { from: bob })

    const totalDeposit = W_ebtcAmount.add(A_ebtcAmount).add(B_ebtcAmount)

    assert.equal((await sortedCdps.getSize()).toString(), '4')

    // Price drops
    await priceFeed.setPrice(dec(105, 18))
    const price = await priceFeed.getPrice()

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check EBTC in Pool
    assert.equal((await stabilityPool.getTotalEBTCDeposits()).toString(), totalDeposit)

    // *** Check A, B, C ICRs 100<ICR<110
    const alice_ICR = await cdpManager.getCurrentICR(_aliceCdpId, price)
    const bob_ICR = await cdpManager.getCurrentICR(_bobCdpId, price)
    const carol_ICR = await cdpManager.getCurrentICR(_carolCdpId, price)

    assert.isTrue(alice_ICR.gte(mv._ICR100) && alice_ICR.lte(mv._MCR))
    assert.isTrue(bob_ICR.gte(mv._ICR100) && bob_ICR.lte(mv._MCR))
    assert.isTrue(carol_ICR.gte(mv._ICR100) && carol_ICR.lte(mv._MCR))

    // Liquidate
    await cdpManager.liquidateCdps(10)

    // Check all defaulters have been liquidated
    assert.isFalse((await sortedCdps.contains(_aliceCdpId)))
    assert.isFalse((await sortedCdps.contains(_bobCdpId)))
    assert.isFalse((await sortedCdps.contains(_carolCdpId)))

    // check system sized reduced to 1 cdps
    assert.equal((await sortedCdps.getSize()).toString(), '1')

    /* Prior to liquidation, SP deposits were:
    Whale: 400 EBTC
    Alice:  40 EBTC
    Bob:   240 EBTC
    Carol: 0 EBTC

    Total EBTC in Pool: 680 EBTC

    Then, liquidation hits A,B,C: 

    Total liquidated debt = 100 + 300 + 100 = 500 EBTC
    Total liquidated ETH = 1 + 3 + 1 = 5 ETH

    Whale EBTC Loss: 500 * (400/680) = 294.12 EBTC
    Alice EBTC Loss:  500 *(40/680) = 29.41 EBTC
    Bob EBTC Loss: 500 * (240/680) = 176.47 EBTC

    Whale remaining deposit: (400 - 294.12) = 105.88 EBTC
    Alice remaining deposit: (40 - 29.41) = 10.59 EBTC
    Bob remaining deposit: (240 - 176.47) = 63.53 EBTC

    Whale ETH Gain: 5*0.995 * (400/680) = 2.93 ETH
    Alice ETH Gain: 5*0.995 *(40/680) = 0.293 ETH
    Bob ETH Gain: 5*0.995 * (240/680) = 1.76 ETH

    Total remaining deposits: 180 EBTC
    Total ETH gain: 5*0.995 ETH */

    const EBTCinSP = (await stabilityPool.getTotalEBTCDeposits()).toString()
    const ETHinSP = (await stabilityPool.getETH()).toString()

    // Check remaining EBTC Deposits and ETH gain, for whale and depositors whose cdps were liquidated
    const whale_Deposit_After = (await stabilityPool.getCompoundedEBTCDeposit(whale)).toString()
    const alice_Deposit_After = (await stabilityPool.getCompoundedEBTCDeposit(alice)).toString()
    const bob_Deposit_After = (await stabilityPool.getCompoundedEBTCDeposit(bob)).toString()

    const whale_ETHGain = (await stabilityPool.getDepositorETHGain(whale)).toString()
    const alice_ETHGain = (await stabilityPool.getDepositorETHGain(alice)).toString()
    const bob_ETHGain = (await stabilityPool.getDepositorETHGain(bob)).toString()

    const liquidatedDebt = A_totalDebt.add(B_totalDebt).add(C_totalDebt)
    const liquidatedColl = A_coll.add(B_coll).add(C_coll)
    assert.isAtMost(th.getDifference(whale_Deposit_After, W_ebtcAmount.sub(liquidatedDebt.mul(W_ebtcAmount).div(totalDeposit))), 100000)
    assert.isAtMost(th.getDifference(alice_Deposit_After, A_ebtcAmount.sub(liquidatedDebt.mul(A_ebtcAmount).div(totalDeposit))), 100000)
    assert.isAtMost(th.getDifference(bob_Deposit_After, B_ebtcAmount.sub(liquidatedDebt.mul(B_ebtcAmount).div(totalDeposit))), 100000)

    assert.isAtMost(th.getDifference(whale_ETHGain, th.applyLiquidationFee(liquidatedColl).mul(W_ebtcAmount).div(totalDeposit)), 2000)
    assert.isAtMost(th.getDifference(alice_ETHGain, th.applyLiquidationFee(liquidatedColl).mul(A_ebtcAmount).div(totalDeposit)), 2000)
    assert.isAtMost(th.getDifference(bob_ETHGain, th.applyLiquidationFee(liquidatedColl).mul(B_ebtcAmount).div(totalDeposit)), 2000)

    // Check total remaining deposits and ETH gain in Stability Pool
    const total_EBTCinSP = (await stabilityPool.getTotalEBTCDeposits()).toString()
    const total_ETHinSP = (await stabilityPool.getETH()).toString()

    assert.isAtMost(th.getDifference(total_EBTCinSP, totalDeposit.sub(liquidatedDebt)), 1000)
    assert.isAtMost(th.getDifference(total_ETHinSP, th.applyLiquidationFee(liquidatedColl)), 1000)
  })

  it("liquidateCdps(): Liquidating cdps at ICR <=100% with SP deposits does not alter their deposit or ETH gain", async () => {
    // Whale provides 400 EBTC to the SP
    await openCdp({ ICR: toBN(dec(300, 16)), extraEBTCAmount: dec(400, 18), extraParams: { from: whale } })
    await stabilityPool.provideToSP(dec(400, 18), ZERO_ADDRESS, { from: whale })

    await openCdp({ ICR: toBN(dec(182, 16)), extraEBTCAmount: dec(170, 18), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(180, 16)), extraEBTCAmount: dec(300, 18), extraParams: { from: bob } })
    await openCdp({ ICR: toBN(dec(170, 16)), extraParams: { from: carol } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    // A, B provide 100, 300 to the SP
    await stabilityPool.provideToSP(dec(100, 18), ZERO_ADDRESS, { from: alice })
    await stabilityPool.provideToSP(dec(300, 18), ZERO_ADDRESS, { from: bob })

    assert.equal((await sortedCdps.getSize()).toString(), '4')

    // Price drops
    await priceFeed.setPrice(dec(100, 18))
    const price = await priceFeed.getPrice()

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check EBTC and ETH in Pool  before
    const EBTCinSP_Before = (await stabilityPool.getTotalEBTCDeposits()).toString()
    const ETHinSP_Before = (await stabilityPool.getETH()).toString()
    assert.equal(EBTCinSP_Before, dec(800, 18))
    assert.equal(ETHinSP_Before, '0')

    // *** Check A, B, C ICRs < 100
    assert.isTrue((await cdpManager.getCurrentICR(_aliceCdpId, price)).lte(mv._ICR100))
    assert.isTrue((await cdpManager.getCurrentICR(_bobCdpId, price)).lte(mv._ICR100))
    assert.isTrue((await cdpManager.getCurrentICR(_carolCdpId, price)).lte(mv._ICR100))

    // Liquidate
    await cdpManager.liquidateCdps(10)

    // Check all defaulters have been liquidated
    assert.isFalse((await sortedCdps.contains(_aliceCdpId)))
    assert.isFalse((await sortedCdps.contains(_bobCdpId)))
    assert.isFalse((await sortedCdps.contains(_carolCdpId)))

    // check system sized reduced to 1 cdps
    assert.equal((await sortedCdps.getSize()).toString(), '1')

    // Check EBTC and ETH in Pool after
    const EBTCinSP_After = (await stabilityPool.getTotalEBTCDeposits()).toString()
    const ETHinSP_After = (await stabilityPool.getETH()).toString()
    assert.equal(EBTCinSP_Before, EBTCinSP_After)
    assert.equal(ETHinSP_Before, ETHinSP_After)

    // Check remaining EBTC Deposits and ETH gain, for whale and depositors whose cdps were liquidated
    const whale_Deposit_After = (await stabilityPool.getCompoundedEBTCDeposit(whale)).toString()
    const alice_Deposit_After = (await stabilityPool.getCompoundedEBTCDeposit(alice)).toString()
    const bob_Deposit_After = (await stabilityPool.getCompoundedEBTCDeposit(bob)).toString()

    const whale_ETHGain_After = (await stabilityPool.getDepositorETHGain(whale)).toString()
    const alice_ETHGain_After = (await stabilityPool.getDepositorETHGain(alice)).toString()
    const bob_ETHGain_After = (await stabilityPool.getDepositorETHGain(bob)).toString()

    assert.equal(whale_Deposit_After, dec(400, 18))
    assert.equal(alice_Deposit_After, dec(100, 18))
    assert.equal(bob_Deposit_After, dec(300, 18))

    assert.equal(whale_ETHGain_After, '0')
    assert.equal(alice_ETHGain_After, '0')
    assert.equal(bob_ETHGain_After, '0')
  })

  it("liquidateCdps() with a non fullfilled liquidation: non liquidated cdp remains active", async () => {
    const { totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(196, 16)), extraParams: { from: alice } })
    const { totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(198, 16)), extraParams: { from: bob } })
    const { totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: carol } })
    await openCdp({ ICR: toBN(dec(206, 16)), extraParams: { from: dennis } })
    await openCdp({ ICR: toBN(dec(208, 16)), extraParams: { from: erin } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    // Whale provides EBTC to the SP
    const spDeposit = A_totalDebt.add(B_totalDebt).add(C_totalDebt.div(toBN(2)))
    await openCdp({ ICR: toBN(dec(300, 16)), extraEBTCAmount: spDeposit, extraParams: { from: whale } })
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: whale })

    // Price drops 
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()
    const TCR = await th.getTCR(contracts)

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check A, B, C, D, E cdps are in range 110% < ICR < TCR
    const ICR_A = await cdpManager.getCurrentICR(_aliceCdpId, price)
    const ICR_B = await cdpManager.getCurrentICR(_bobCdpId, price)
    const ICR_C = await cdpManager.getCurrentICR(_carolCdpId, price)

    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C.gt(mv._MCR) && ICR_C.lt(TCR))

    /* Liquidate cdps. Cdps are ordered by ICR, from low to high:  A, B, C, D, E.
    With 253 in the SP, Alice (102 debt) and Bob (101 debt) should be entirely liquidated. 
    That leaves 50 EBTC in the Pool to absorb exactly half of Carol's debt (100) */
    await cdpManager.liquidateCdps(10)

    // Check A and B closed
    assert.isFalse(await sortedCdps.contains(_aliceCdpId))
    assert.isFalse(await sortedCdps.contains(_bobCdpId))

    // Check C remains active
    assert.isTrue(await sortedCdps.contains(_carolCdpId))
    assert.equal((await cdpManager.Cdps(_carolCdpId))[3].toString(), '1') // check Status is active
  })

  it("liquidateCdps() with a non fullfilled liquidation: non liquidated cdp remains in CdpOwners Array", async () => {
    const { totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(210, 16)), extraParams: { from: alice } })
    const { totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(211, 16)), extraParams: { from: bob } })
    const { totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(212, 16)), extraParams: { from: carol } })
    await openCdp({ ICR: toBN(dec(219, 16)), extraParams: { from: dennis } })
    await openCdp({ ICR: toBN(dec(221, 16)), extraParams: { from: erin } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    // Whale provides EBTC to the SP
    const spDeposit = A_totalDebt.add(B_totalDebt).add(C_totalDebt.div(toBN(2)))
    await openCdp({ ICR: toBN(dec(220, 16)), extraEBTCAmount: spDeposit, extraParams: { from: whale } })
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: whale })

    // Price drops 
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()
    const TCR = await th.getTCR(contracts)

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check A, B, C cdps are in range 110% < ICR < TCR
    const ICR_A = await cdpManager.getCurrentICR(_aliceCdpId, price)
    const ICR_B = await cdpManager.getCurrentICR(_bobCdpId, price)
    const ICR_C = await cdpManager.getCurrentICR(_carolCdpId, price)

    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C.gt(mv._MCR) && ICR_C.lt(TCR))

    /* Liquidate cdps. Cdps are ordered by ICR, from low to high:  A, B, C.
    With 253 in the SP, Alice (102 debt) and Bob (101 debt) should be entirely liquidated. 
    That leaves 50 EBTC in the Pool to absorb exactly half of Carol's debt (100) */
    await cdpManager.liquidateCdps(10)

    // Check C is in Cdp owners array
    const arrayLength = (await cdpManager.getCdpIdsCount()).toNumber()
    let addressFound = false;
    let addressIdx = 0;

    for (let i = 0; i < arrayLength; i++) {
      const address = (await cdpManager.CdpIds(i)).toString()
      if (address == _carolCdpId) {
        addressFound = true
        addressIdx = i
      }
    }

    assert.isTrue(addressFound);

    // Check CdpOwners idx on cdp struct == idx of address found in CdpOwners array
    const idxOnStruct = (await cdpManager.Cdps(_carolCdpId))[4].toString()
    assert.equal(addressIdx.toString(), idxOnStruct)
  })

  it("liquidateCdps() with a non fullfilled liquidation: still can liquidate further cdps after the non-liquidated, emptied pool", async () => {
    const { totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(196, 16)), extraParams: { from: alice } })
    const { totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(198, 16)), extraParams: { from: bob } })
    const { totalDebt: D_totalDebt } = await openCdp({ ICR: toBN(dec(206, 16)), extraParams: { from: dennis } })
    const { totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: D_totalDebt, extraParams: { from: carol } })
    await openCdp({ ICR: toBN(dec(208, 16)), extraParams: { from: erin } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);
    let _erinCdpId = await sortedCdps.cdpOfOwnerByIndex(erin, 0);

    // Whale provides EBTC to the SP
    const spDeposit = A_totalDebt.add(B_totalDebt).add(D_totalDebt)
    await openCdp({ ICR: toBN(dec(220, 16)), extraEBTCAmount: spDeposit, extraParams: { from: whale } })
    let _whaleCdpId = await sortedCdps.cdpOfOwnerByIndex(whale, 0);
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: whale })

    // Price drops 
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()
    const TCR = await th.getTCR(contracts)

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check A, B, C, D, E cdps are in range 110% < ICR < TCR
    const ICR_A = await cdpManager.getCurrentICR(_aliceCdpId, price)
    const ICR_B = await cdpManager.getCurrentICR(_bobCdpId, price)
    const ICR_C = await cdpManager.getCurrentICR(_carolCdpId, price)
    const ICR_D = await cdpManager.getCurrentICR(_dennisCdpId, price)
    const ICR_E = await cdpManager.getCurrentICR(_erinCdpId, price)

    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C.gt(mv._MCR) && ICR_C.lt(TCR))
    assert.isTrue(ICR_D.gt(mv._MCR) && ICR_D.lt(TCR))
    assert.isTrue(ICR_E.gt(mv._MCR) && ICR_E.lt(TCR))

    /* Liquidate cdps. Cdps are ordered by ICR, from low to high:  A, B, C, D, E.
     With 300 in the SP, Alice (102 debt) and Bob (101 debt) should be entirely liquidated.
     That leaves 97 EBTC in the Pool that won’t be enough to absorb Carol,
     but it will be enough to liquidate Dennis. Afterwards the pool will be empty,
     so Erin won’t liquidated. */
    const tx = await cdpManager.liquidateCdps(10)
    console.log('gasUsed: ', tx.receipt.gasUsed)

    // Check A, B and D are closed
    assert.isFalse(await sortedCdps.contains(_aliceCdpId))
    assert.isFalse(await sortedCdps.contains(_bobCdpId))
    console.log(await sortedCdps.contains(_carolCdpId))
    assert.isFalse(await sortedCdps.contains(_dennisCdpId))

    // Check whale, C and E stay active
    assert.isTrue(await sortedCdps.contains(_whaleCdpId))
    assert.isTrue(await sortedCdps.contains(_carolCdpId))
    assert.isTrue(await sortedCdps.contains(_erinCdpId))
  })

  it("liquidateCdps() with a non fullfilled liquidation: still can liquidate further cdps after the non-liquidated, non emptied pool", async () => {
    const { totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(196, 16)), extraParams: { from: alice } })
    const { totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(198, 16)), extraParams: { from: bob } })
    const { totalDebt: D_totalDebt } = await openCdp({ ICR: toBN(dec(206, 16)), extraParams: { from: dennis } })
    const { totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: D_totalDebt, extraParams: { from: carol } })
    await openCdp({ ICR: toBN(dec(208, 16)), extraParams: { from: erin } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);
    let _erinCdpId = await sortedCdps.cdpOfOwnerByIndex(erin, 0);

    // Whale provides EBTC to the SP
    const spDeposit = A_totalDebt.add(B_totalDebt).add(D_totalDebt)
    await openCdp({ ICR: toBN(dec(220, 16)), extraEBTCAmount: spDeposit, extraParams: { from: whale } })
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: whale })
    let _whaleCdpId = await sortedCdps.cdpOfOwnerByIndex(whale, 0);

    // Price drops 
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()
    const TCR = await th.getTCR(contracts)

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check A, B, C, D, E cdps are in range 110% < ICR < TCR
    const ICR_A = await cdpManager.getCurrentICR(_aliceCdpId, price)
    const ICR_B = await cdpManager.getCurrentICR(_bobCdpId, price)
    const ICR_C = await cdpManager.getCurrentICR(_carolCdpId, price)
    const ICR_D = await cdpManager.getCurrentICR(_dennisCdpId, price)
    const ICR_E = await cdpManager.getCurrentICR(_erinCdpId, price)

    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C.gt(mv._MCR) && ICR_C.lt(TCR))
    assert.isTrue(ICR_D.gt(mv._MCR) && ICR_D.lt(TCR))
    assert.isTrue(ICR_E.gt(mv._MCR) && ICR_E.lt(TCR))

    /* Liquidate cdps. Cdps are ordered by ICR, from low to high:  A, B, C, D, E.
     With 301 in the SP, Alice (102 debt) and Bob (101 debt) should be entirely liquidated.
     That leaves 97 EBTC in the Pool that won’t be enough to absorb Carol,
     but it will be enough to liquidate Dennis. Afterwards the pool will be empty,
     so Erin won’t liquidated.
     Note that, compared to the previous test, this one will make 1 more loop iteration,
     so it will consume more gas. */
    const tx = await cdpManager.liquidateCdps(10)
    console.log('gasUsed: ', tx.receipt.gasUsed)

    // Check A, B and D are closed
    assert.isFalse(await sortedCdps.contains(_aliceCdpId))
    assert.isFalse(await sortedCdps.contains(_bobCdpId))
    assert.isFalse(await sortedCdps.contains(_dennisCdpId))

    // Check whale, C and E stay active
    assert.isTrue(await sortedCdps.contains(_whaleCdpId))
    assert.isTrue(await sortedCdps.contains(_carolCdpId))
    assert.isTrue(await sortedCdps.contains(_erinCdpId))
  })

  it("liquidateCdps() with a non fullfilled liquidation: total liquidated coll and debt is correct", async () => {
    const { collateral: A_coll, totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(196, 16)), extraParams: { from: alice } })
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(198, 16)), extraParams: { from: bob } })
    const { totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: carol } })
    await openCdp({ ICR: toBN(dec(206, 16)), extraParams: { from: dennis } })
    await openCdp({ ICR: toBN(dec(208, 16)), extraParams: { from: erin } })

    // Whale provides EBTC to the SP
    const spDeposit = A_totalDebt.add(B_totalDebt).add(C_totalDebt.div(toBN(2)))
    await openCdp({ ICR: toBN(dec(220, 16)), extraEBTCAmount: spDeposit, extraParams: { from: whale } })
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: whale })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    // Price drops 
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()
    const TCR = await th.getTCR(contracts)

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check A, B, C cdps are in range 110% < ICR < TCR
    const ICR_A = await cdpManager.getCurrentICR(_aliceCdpId, price)
    const ICR_B = await cdpManager.getCurrentICR(_bobCdpId, price)
    const ICR_C = await cdpManager.getCurrentICR(_carolCdpId, price)

    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C.gt(mv._MCR) && ICR_C.lt(TCR))

    const entireSystemCollBefore = await cdpManager.getEntireSystemColl()
    const entireSystemDebtBefore = await cdpManager.getEntireSystemDebt()

    /* Liquidate cdps. Cdps are ordered by ICR, from low to high:  A, B, C, D, E.
    With 253 in the SP, Alice (102 debt) and Bob (101 debt) should be entirely liquidated. 
    That leaves 50 EBTC in the Pool that won’t be enough to absorb any other cdp */
    const tx = await cdpManager.liquidateCdps(10)

    // Expect system debt reduced by 203 EBTC and system coll 2.3 ETH
    const entireSystemCollAfter = await cdpManager.getEntireSystemColl()
    const entireSystemDebtAfter = await cdpManager.getEntireSystemDebt()

    const changeInEntireSystemColl = entireSystemCollBefore.sub(entireSystemCollAfter)
    const changeInEntireSystemDebt = entireSystemDebtBefore.sub(entireSystemDebtAfter)

    assert.equal(changeInEntireSystemColl.toString(), A_coll.add(B_coll))
    th.assertIsApproximatelyEqual(changeInEntireSystemDebt.toString(), A_totalDebt.add(B_totalDebt))
  })

  it("liquidateCdps() with a non fullfilled liquidation: emits correct liquidation event values", async () => {
    const { collateral: A_coll, totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(210, 16)), extraParams: { from: alice } })
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(211, 16)), extraParams: { from: bob } })
    const { totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(212, 16)), extraParams: { from: carol } })
    await openCdp({ ICR: toBN(dec(219, 16)), extraParams: { from: dennis } })
    await openCdp({ ICR: toBN(dec(221, 16)), extraParams: { from: erin } })

    // Whale provides EBTC to the SP
    const spDeposit = A_totalDebt.add(B_totalDebt).add(C_totalDebt.div(toBN(2)))
    await openCdp({ ICR: toBN(dec(240, 16)), extraEBTCAmount: spDeposit, extraParams: { from: whale } })
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: whale })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    // Price drops 
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()
    const TCR = await th.getTCR(contracts)

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check A, B, C cdps are in range 110% < ICR < TCR
    const ICR_A = await cdpManager.getCurrentICR(_aliceCdpId, price)
    const ICR_B = await cdpManager.getCurrentICR(_bobCdpId, price)
    const ICR_C = await cdpManager.getCurrentICR(_carolCdpId, price)

    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C.gt(mv._MCR) && ICR_C.lt(TCR))

    /* Liquidate cdps. Cdps are ordered by ICR, from low to high:  A, B, C, D, E.
    With 253 in the SP, Alice (102 debt) and Bob (101 debt) should be entirely liquidated. 
    That leaves 50 EBTC in the Pool which won’t be enough for any other liquidation */
    const liquidationTx = await cdpManager.liquidateCdps(10)

    const [liquidatedDebt, liquidatedColl, collGasComp, ebtcGasComp] = th.getEmittedLiquidationValues(liquidationTx)

    th.assertIsApproximatelyEqual(liquidatedDebt, A_totalDebt.add(B_totalDebt))
    const equivalentColl = A_totalDebt.add(B_totalDebt).mul(toBN(dec(11, 17))).div(price)
    th.assertIsApproximatelyEqual(liquidatedColl, th.applyLiquidationFee(equivalentColl))
    th.assertIsApproximatelyEqual(collGasComp, equivalentColl.sub(th.applyLiquidationFee(equivalentColl))) // 0.5% of 283/120*1.1
    assert.equal(ebtcGasComp.toString(), dec(400, 18))

    // check collateral surplus
    const alice_remainingCollateral = A_coll.sub(A_totalDebt.mul(th.toBN(dec(11, 17))).div(price))
    const bob_remainingCollateral = B_coll.sub(B_totalDebt.mul(th.toBN(dec(11, 17))).div(price))
    th.assertIsApproximatelyEqual(await collSurplusPool.getCollateral(alice), alice_remainingCollateral)
    th.assertIsApproximatelyEqual(await collSurplusPool.getCollateral(bob), bob_remainingCollateral)

    // can claim collateral
    const alice_balanceBefore = th.toBN(await web3.eth.getBalance(alice))
    const ALICE_GAS = th.gasUsed(await borrowerOperations.claimCollateral({ from: alice, gasPrice: GAS_PRICE  }))
    const alice_balanceAfter = th.toBN(await web3.eth.getBalance(alice))
    th.assertIsApproximatelyEqual(alice_balanceAfter, alice_balanceBefore.add(th.toBN(alice_remainingCollateral).sub(th.toBN(ALICE_GAS * GAS_PRICE))))

    const bob_balanceBefore = th.toBN(await web3.eth.getBalance(bob))
    const BOB_GAS = th.gasUsed(await borrowerOperations.claimCollateral({ from: bob, gasPrice: GAS_PRICE  }))
    const bob_balanceAfter = th.toBN(await web3.eth.getBalance(bob))
    th.assertIsApproximatelyEqual(bob_balanceAfter, bob_balanceBefore.add(th.toBN(bob_remainingCollateral).sub(th.toBN(BOB_GAS * GAS_PRICE))))
  })

  it("liquidateCdps() with a non fullfilled liquidation: ICR of non liquidated cdp does not change", async () => {
    const { totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(196, 16)), extraParams: { from: alice } })
    const { totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(198, 16)), extraParams: { from: bob } })
    const { totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: carol } })
    await openCdp({ ICR: toBN(dec(206, 16)), extraParams: { from: dennis } })
    await openCdp({ ICR: toBN(dec(208, 16)), extraParams: { from: erin } })

    // Whale provides EBTC to the SP
    const spDeposit = A_totalDebt.add(B_totalDebt).add(C_totalDebt.div(toBN(2)))
    await openCdp({ ICR: toBN(dec(220, 16)), extraEBTCAmount: spDeposit, extraParams: { from: whale } })
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: whale })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    // Price drops 
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()
    const TCR = await th.getTCR(contracts)

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check A, B, C cdps are in range 110% < ICR < TCR
    const ICR_A = await cdpManager.getCurrentICR(_aliceCdpId, price)
    const ICR_B = await cdpManager.getCurrentICR(_bobCdpId, price)
    const ICR_C_Before = await cdpManager.getCurrentICR(_carolCdpId, price)

    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C_Before.gt(mv._MCR) && ICR_C_Before.lt(TCR))

    /* Liquidate cdps. Cdps are ordered by ICR, from low to high:  A, B, C, D, E.
    With 253 in the SP, Alice (102 debt) and Bob (101 debt) should be entirely liquidated. 
    That leaves 50 EBTC in the Pool to absorb exactly half of Carol's debt (100) */
    await cdpManager.liquidateCdps(10)

    const ICR_C_After = await cdpManager.getCurrentICR(_carolCdpId, price)
    assert.equal(ICR_C_Before.toString(), ICR_C_After)
  })

  // TODO: LiquidateCdps tests that involve cdps with ICR > TCR

  // --- batchLiquidateCdps() ---

  it("batchLiquidateCdps(): Liquidates all cdps with ICR < 110%, transitioning Normal -> Recovery Mode", async () => {
    // make 6 Cdps accordingly
    // --- SETUP ---
    const { totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(240, 16)), extraParams: { from: bob } })
    const { totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(240, 16)), extraParams: { from: carol } })
    const { totalDebt: D_totalDebt } = await openCdp({ ICR: toBN(dec(230, 16)), extraParams: { from: dennis } })
    const { totalDebt: E_totalDebt } = await openCdp({ ICR: toBN(dec(240, 16)), extraParams: { from: erin } })
    const { totalDebt: F_totalDebt } = await openCdp({ ICR: toBN(dec(240, 16)), extraParams: { from: freddy } })

    const spDeposit = B_totalDebt.add(C_totalDebt).add(D_totalDebt).add(E_totalDebt).add(F_totalDebt)
    await openCdp({ ICR: toBN(dec(426, 16)), extraEBTCAmount: spDeposit, extraParams: { from: alice } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);
    let _erinCdpId = await sortedCdps.cdpOfOwnerByIndex(erin, 0);
    let _freddyCdpId = await sortedCdps.cdpOfOwnerByIndex(freddy, 0);

    // Alice deposits EBTC to Stability Pool
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: alice })

    // price drops to 1ETH:85EBTC, reducing TCR below 150%
    await priceFeed.setPrice('85000000000000000000')
    const price = await priceFeed.getPrice()

    // check Recovery Mode kicks in

    const recoveryMode_Before = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode_Before)

    // check TCR < 150%
    const _150percent = web3.utils.toBN('1500000000000000000')
    const TCR_Before = await th.getTCR(contracts)
    assert.isTrue(TCR_Before.lt(_150percent))

    /* 
    After the price drop and prior to any liquidations, ICR should be:

    Cdp         ICR
    Alice       182%
    Bob         102%
    Carol       102%
    Dennis      102%
    Elisa       102%
    Freddy      102%
    */
    alice_ICR = await cdpManager.getCurrentICR(_aliceCdpId, price)
    bob_ICR = await cdpManager.getCurrentICR(_bobCdpId, price)
    carol_ICR = await cdpManager.getCurrentICR(_carolCdpId, price)
    dennis_ICR = await cdpManager.getCurrentICR(_dennisCdpId, price)
    erin_ICR = await cdpManager.getCurrentICR(_erinCdpId, price)
    freddy_ICR = await cdpManager.getCurrentICR(_freddyCdpId, price)

    // Alice should have ICR > 150%
    assert.isTrue(alice_ICR.gt(_150percent))
    // All other Cdps should have ICR < 150%
    assert.isTrue(carol_ICR.lt(_150percent))
    assert.isTrue(dennis_ICR.lt(_150percent))
    assert.isTrue(erin_ICR.lt(_150percent))
    assert.isTrue(freddy_ICR.lt(_150percent))

    /* After liquidating Bob and Carol, the the TCR of the system rises above the CCR, to 154%.  
    (see calculations in Google Sheet)

    Liquidations continue until all Cdps with ICR < MCR have been closed. 
    Only Alice should remain active - all others should be closed. */

    // call batchLiquidateCdps
    await cdpManager.batchLiquidateCdps([_aliceCdpId, _bobCdpId, _carolCdpId, _dennisCdpId, _erinCdpId, _freddyCdpId]);

    // check system is no longer in Recovery Mode
    const recoveryMode_After = await th.checkRecoveryMode(contracts)
    assert.isFalse(recoveryMode_After)

    // After liquidation, TCR should rise to above 150%. 
    const TCR_After = await th.getTCR(contracts)
    assert.isTrue(TCR_After.gt(_150percent))

    // get all Cdps
    const alice_Cdp = await cdpManager.Cdps(_aliceCdpId)
    const bob_Cdp = await cdpManager.Cdps(_bobCdpId)
    const carol_Cdp = await cdpManager.Cdps(_carolCdpId)
    const dennis_Cdp = await cdpManager.Cdps(_dennisCdpId)
    const erin_Cdp = await cdpManager.Cdps(_erinCdpId)
    const freddy_Cdp = await cdpManager.Cdps(_freddyCdpId)

    // check that Alice's Cdp remains active
    assert.equal(alice_Cdp[3], 1)
    assert.isTrue(await sortedCdps.contains(_aliceCdpId))

    // check all other Cdps are liquidated
    assert.equal(bob_Cdp[3], 3)
    assert.equal(carol_Cdp[3], 3)
    assert.equal(dennis_Cdp[3], 3)
    assert.equal(erin_Cdp[3], 3)
    assert.equal(freddy_Cdp[3], 3)

    assert.isFalse(await sortedCdps.contains(_bobCdpId))
    assert.isFalse(await sortedCdps.contains(_carolCdpId))
    assert.isFalse(await sortedCdps.contains(_dennisCdpId))
    assert.isFalse(await sortedCdps.contains(_erinCdpId))
    assert.isFalse(await sortedCdps.contains(_freddyCdpId))
  })

  it("batchLiquidateCdps(): Liquidates all cdps with ICR < 110%, transitioning Recovery -> Normal Mode", async () => {
    /* This is essentially the same test as before, but changing the order of the batch,
     * now the remaining cdp (alice) goes at the end.
     * This way alice will be skipped in a different part of the code, as in the previous test,
     * when attempting alice the system was in Recovery mode, while in this test,
     * when attempting alice the system has gone back to Normal mode
     * (see function `_getTotalFromBatchLiquidate_RecoveryMode`)
     */
    // make 6 Cdps accordingly
    // --- SETUP ---

    const { totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(240, 16)), extraParams: { from: bob } })
    const { totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(240, 16)), extraParams: { from: carol } })
    const { totalDebt: D_totalDebt } = await openCdp({ ICR: toBN(dec(230, 16)), extraParams: { from: dennis } })
    const { totalDebt: E_totalDebt } = await openCdp({ ICR: toBN(dec(240, 16)), extraParams: { from: erin } })
    const { totalDebt: F_totalDebt } = await openCdp({ ICR: toBN(dec(240, 16)), extraParams: { from: freddy } })

    const spDeposit = B_totalDebt.add(C_totalDebt).add(D_totalDebt).add(E_totalDebt).add(F_totalDebt)
    await openCdp({ ICR: toBN(dec(426, 16)), extraEBTCAmount: spDeposit, extraParams: { from: alice } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);
    let _erinCdpId = await sortedCdps.cdpOfOwnerByIndex(erin, 0);
    let _freddyCdpId = await sortedCdps.cdpOfOwnerByIndex(freddy, 0);

    // Alice deposits EBTC to Stability Pool
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: alice })

    // price drops to 1ETH:85EBTC, reducing TCR below 150%
    await priceFeed.setPrice('85000000000000000000')
    const price = await priceFeed.getPrice()

    // check Recovery Mode kicks in

    const recoveryMode_Before = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode_Before)

    // check TCR < 150%
    const _150percent = web3.utils.toBN('1500000000000000000')
    const TCR_Before = await th.getTCR(contracts)
    assert.isTrue(TCR_Before.lt(_150percent))

    /*
    After the price drop and prior to any liquidations, ICR should be:

    Cdp         ICR
    Alice       182%
    Bob         102%
    Carol       102%
    Dennis      102%
    Elisa       102%
    Freddy      102%
    */
    const alice_ICR = await cdpManager.getCurrentICR(_aliceCdpId, price)
    const bob_ICR = await cdpManager.getCurrentICR(_bobCdpId, price)
    const carol_ICR = await cdpManager.getCurrentICR(_carolCdpId, price)
    const dennis_ICR = await cdpManager.getCurrentICR(_dennisCdpId, price)
    const erin_ICR = await cdpManager.getCurrentICR(_erinCdpId, price)
    const freddy_ICR = await cdpManager.getCurrentICR(_freddyCdpId, price)

    // Alice should have ICR > 150%
    assert.isTrue(alice_ICR.gt(_150percent))
    // All other Cdps should have ICR < 150%
    assert.isTrue(carol_ICR.lt(_150percent))
    assert.isTrue(dennis_ICR.lt(_150percent))
    assert.isTrue(erin_ICR.lt(_150percent))
    assert.isTrue(freddy_ICR.lt(_150percent))

    /* After liquidating Bob and Carol, the the TCR of the system rises above the CCR, to 154%.  
    (see calculations in Google Sheet)

    Liquidations continue until all Cdps with ICR < MCR have been closed. 
    Only Alice should remain active - all others should be closed. */

    // call batchLiquidateCdps
    await cdpManager.batchLiquidateCdps([_bobCdpId, _carolCdpId, _dennisCdpId, _erinCdpId, _freddyCdpId, _aliceCdpId]);

    // check system is no longer in Recovery Mode
    const recoveryMode_After = await th.checkRecoveryMode(contracts)
    assert.isFalse(recoveryMode_After)

    // After liquidation, TCR should rise to above 150%. 
    const TCR_After = await th.getTCR(contracts)
    assert.isTrue(TCR_After.gt(_150percent))

    // get all Cdps
    const alice_Cdp = await cdpManager.Cdps(_aliceCdpId)
    const bob_Cdp = await cdpManager.Cdps(_bobCdpId)
    const carol_Cdp = await cdpManager.Cdps(_carolCdpId)
    const dennis_Cdp = await cdpManager.Cdps(_dennisCdpId)
    const erin_Cdp = await cdpManager.Cdps(_erinCdpId)
    const freddy_Cdp = await cdpManager.Cdps(_freddyCdpId)

    // check that Alice's Cdp remains active
    assert.equal(alice_Cdp[3], 1)
    assert.isTrue(await sortedCdps.contains(_aliceCdpId))

    // check all other Cdps are liquidated
    assert.equal(bob_Cdp[3], 3)
    assert.equal(carol_Cdp[3], 3)
    assert.equal(dennis_Cdp[3], 3)
    assert.equal(erin_Cdp[3], 3)
    assert.equal(freddy_Cdp[3], 3)

    assert.isFalse(await sortedCdps.contains(_bobCdpId))
    assert.isFalse(await sortedCdps.contains(_carolCdpId))
    assert.isFalse(await sortedCdps.contains(_dennisCdpId))
    assert.isFalse(await sortedCdps.contains(_erinCdpId))
    assert.isFalse(await sortedCdps.contains(_freddyCdpId))
  })

  it("batchLiquidateCdps(): Liquidates all cdps with ICR < 110%, transitioning Normal -> Recovery Mode", async () => {
    // This is again the same test as the before the last one, but now Alice is skipped because she is not active
    // It also skips bob, as he is added twice, for being already liquidated
    // make 6 Cdps accordingly
    // --- SETUP ---
    const { totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(240, 16)), extraParams: { from: bob } })
    const { totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(240, 16)), extraParams: { from: carol } })
    const { totalDebt: D_totalDebt } = await openCdp({ ICR: toBN(dec(230, 16)), extraParams: { from: dennis } })
    const { totalDebt: E_totalDebt } = await openCdp({ ICR: toBN(dec(240, 16)), extraParams: { from: erin } })
    const { totalDebt: F_totalDebt } = await openCdp({ ICR: toBN(dec(240, 16)), extraParams: { from: freddy } })

    const spDeposit = B_totalDebt.add(C_totalDebt).add(D_totalDebt).add(E_totalDebt).add(F_totalDebt)
    const { totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(426, 16)), extraEBTCAmount: spDeposit, extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(426, 16)), extraEBTCAmount: A_totalDebt, extraParams: { from: whale } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);
    let _erinCdpId = await sortedCdps.cdpOfOwnerByIndex(erin, 0);
    let _freddyCdpId = await sortedCdps.cdpOfOwnerByIndex(freddy, 0);

    // Alice deposits EBTC to Stability Pool
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: alice })

    // to compensate borrowing fee
    await ebtcToken.transfer(alice, A_totalDebt, { from: whale })
    // Deprecated Alice closes cdp. If cdp closed, ntohing to liquidate later
    await borrowerOperations.closeCdp(_aliceCdpId, { from: alice })

    // price drops to 1ETH:85EBTC, reducing TCR below 150%
    await priceFeed.setPrice('85000000000000000000')
    const price = await priceFeed.getPrice()

    // check Recovery Mode kicks in
    const recoveryMode_Before = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode_Before)

    // check TCR < 150%
    const _150percent = web3.utils.toBN('1500000000000000000')
    const TCR_Before = await th.getTCR(contracts)
    assert.isTrue(TCR_Before.lt(_150percent))

    /*
    After the price drop and prior to any liquidations, ICR should be:

    Cdp         ICR
    Alice       182%
    Bob         102%
    Carol       102%
    Dennis      102%
    Elisa       102%
    Freddy      102%
    */
    //alice_ICR = await cdpManager.getCurrentICR(_aliceCdpId, price)
    bob_ICR = await cdpManager.getCurrentICR(_bobCdpId, price)
    carol_ICR = await cdpManager.getCurrentICR(_carolCdpId, price)
    dennis_ICR = await cdpManager.getCurrentICR(_dennisCdpId, price)
    erin_ICR = await cdpManager.getCurrentICR(_erinCdpId, price)
    freddy_ICR = await cdpManager.getCurrentICR(_freddyCdpId, price)

    // Alice should have ICR > 150%
    //assert.isTrue(alice_ICR.gt(_150percent))
    // All other Cdps should have ICR < 150%
    assert.isTrue(carol_ICR.lt(_150percent))
    assert.isTrue(dennis_ICR.lt(_150percent))
    assert.isTrue(erin_ICR.lt(_150percent))
    assert.isTrue(freddy_ICR.lt(_150percent))

    /* After liquidating Bob and Carol, the the TCR of the system rises above the CCR, to 154%.
    (see calculations in Google Sheet)

    Liquidations continue until all Cdps with ICR < MCR have been closed.
    Only Alice should remain active - all others should be closed. */

    // call batchLiquidateCdps
    await cdpManager.batchLiquidateCdps([_aliceCdpId, _bobCdpId, _carolCdpId, _dennisCdpId, _erinCdpId, _freddyCdpId]);

    // check system is no longer in Recovery Mode
    const recoveryMode_After = await th.checkRecoveryMode(contracts)
    assert.isFalse(recoveryMode_After)

    // After liquidation, TCR should rise to above 150%.
    const TCR_After = await th.getTCR(contracts)
    assert.isTrue(TCR_After.gt(_150percent))

    // get all Cdps
    const alice_Cdp = await cdpManager.Cdps(_aliceCdpId)
    const bob_Cdp = await cdpManager.Cdps(_bobCdpId)
    const carol_Cdp = await cdpManager.Cdps(_carolCdpId)
    const dennis_Cdp = await cdpManager.Cdps(_dennisCdpId)
    const erin_Cdp = await cdpManager.Cdps(_erinCdpId)
    const freddy_Cdp = await cdpManager.Cdps(_freddyCdpId)

    // check that Alice's Cdp is closed
    assert.equal(alice_Cdp[3], 2)

    // check all other Cdps are liquidated
    assert.equal(bob_Cdp[3], 3)
    assert.equal(carol_Cdp[3], 3)
    assert.equal(dennis_Cdp[3], 3)
    assert.equal(erin_Cdp[3], 3)
    assert.equal(freddy_Cdp[3], 3)

    assert.isFalse(await sortedCdps.contains(_bobCdpId))
    assert.isFalse(await sortedCdps.contains(_carolCdpId))
    assert.isFalse(await sortedCdps.contains(_dennisCdpId))
    assert.isFalse(await sortedCdps.contains(_erinCdpId))
    assert.isFalse(await sortedCdps.contains(_freddyCdpId))
  })

  it("batchLiquidateCdps() with a non fullfilled liquidation: non liquidated cdp remains active", async () => {
    const { totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(211, 16)), extraParams: { from: alice } })
    const { totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(212, 16)), extraParams: { from: bob } })
    const { totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(210, 16)), extraParams: { from: carol } })
    await openCdp({ ICR: toBN(dec(219, 16)), extraParams: { from: dennis } })
    await openCdp({ ICR: toBN(dec(221, 16)), extraParams: { from: erin } })

    // Whale provides EBTC to the SP
    const spDeposit = A_totalDebt.add(B_totalDebt).add(C_totalDebt.div(toBN(2)))
    await openCdp({ ICR: toBN(dec(220, 16)), extraEBTCAmount: spDeposit, extraParams: { from: whale } })
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: whale })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    // Price drops 
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()
    const TCR = await th.getTCR(contracts)

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check A, B, C cdps are in range 110% < ICR < TCR
    const ICR_A = await cdpManager.getCurrentICR(_aliceCdpId, price)
    const ICR_B = await cdpManager.getCurrentICR(_bobCdpId, price)
    const ICR_C = await cdpManager.getCurrentICR(_carolCdpId, price)

    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C.gt(mv._MCR) && ICR_C.lt(TCR))

    const cdpsToLiquidate = [_aliceCdpId, _bobCdpId, _carolCdpId]
    await cdpManager.batchLiquidateCdps(cdpsToLiquidate)

    // Check A and B closed
    assert.isFalse(await sortedCdps.contains(_aliceCdpId))
    assert.isFalse(await sortedCdps.contains(_bobCdpId))

    // Check C remains active
    assert.isTrue(await sortedCdps.contains(_carolCdpId))
    assert.equal((await cdpManager.Cdps(_carolCdpId))[3].toString(), '1') // check Status is active
  })

  it("batchLiquidateCdps() with a non fullfilled liquidation: non liquidated cdp remains in Cdp Owners array", async () => {
    const { totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(211, 16)), extraParams: { from: alice } })
    const { totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(212, 16)), extraParams: { from: bob } })
    const { totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(210, 16)), extraParams: { from: carol } })
    await openCdp({ ICR: toBN(dec(219, 16)), extraParams: { from: dennis } })
    await openCdp({ ICR: toBN(dec(221, 16)), extraParams: { from: erin } })

    // Whale provides EBTC to the SP
    const spDeposit = A_totalDebt.add(B_totalDebt).add(C_totalDebt.div(toBN(2)))
    await openCdp({ ICR: toBN(dec(220, 16)), extraEBTCAmount: spDeposit, extraParams: { from: whale } })
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: whale })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    // Price drops 
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()
    const TCR = await th.getTCR(contracts)

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check A, B, C cdps are in range 110% < ICR < TCR
    const ICR_A = await cdpManager.getCurrentICR(_aliceCdpId, price)
    const ICR_B = await cdpManager.getCurrentICR(_bobCdpId, price)
    const ICR_C = await cdpManager.getCurrentICR(_carolCdpId, price)

    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C.gt(mv._MCR) && ICR_C.lt(TCR))

    const cdpsToLiquidate = [_aliceCdpId, _bobCdpId, _carolCdpId]
    await cdpManager.batchLiquidateCdps(cdpsToLiquidate)

    // Check C is in Cdp owners array
    const arrayLength = (await cdpManager.getCdpIdsCount()).toNumber()
    let addressFound = false;
    let addressIdx = 0;

    for (let i = 0; i < arrayLength; i++) {
      const address = (await cdpManager.CdpIds(i)).toString()
      if (address == _carolCdpId) {
        addressFound = true
        addressIdx = i
      }
    }

    assert.isTrue(addressFound);

    // Check CdpOwners idx on cdp struct == idx of address found in CdpOwners array
    const idxOnStruct = (await cdpManager.Cdps(_carolCdpId))[4].toString()
    assert.equal(addressIdx.toString(), idxOnStruct)
  })

  it("batchLiquidateCdps() with a non fullfilled liquidation: still can liquidate further cdps after the non-liquidated, emptied pool", async () => {
    const { totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(196, 16)), extraParams: { from: alice } })
    const { totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(198, 16)), extraParams: { from: bob } })
    const { totalDebt: D_totalDebt } = await openCdp({ ICR: toBN(dec(206, 16)), extraParams: { from: dennis } })
    const { totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: D_totalDebt, extraParams: { from: carol } })
    await openCdp({ ICR: toBN(dec(208, 16)), extraParams: { from: erin } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);
    let _erinCdpId = await sortedCdps.cdpOfOwnerByIndex(erin, 0);

    // Whale provides EBTC to the SP
    const spDeposit = A_totalDebt.add(B_totalDebt).add(C_totalDebt.div(toBN(2)))
    await openCdp({ ICR: toBN(dec(220, 16)), extraEBTCAmount: spDeposit, extraParams: { from: whale } })
    let _whaleCdpId = await sortedCdps.cdpOfOwnerByIndex(whale, 0);
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: whale })

    // Price drops 
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()
    const TCR = await th.getTCR(contracts)

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check A, B, C, D, E cdps are in range 110% < ICR < TCR
    const ICR_A = await cdpManager.getCurrentICR(_aliceCdpId, price)
    const ICR_B = await cdpManager.getCurrentICR(_bobCdpId, price)
    const ICR_C = await cdpManager.getCurrentICR(_carolCdpId, price)
    const ICR_D = await cdpManager.getCurrentICR(_dennisCdpId, price)
    const ICR_E = await cdpManager.getCurrentICR(_erinCdpId, price)

    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C.gt(mv._MCR) && ICR_C.lt(TCR))
    assert.isTrue(ICR_D.gt(mv._MCR) && ICR_D.lt(TCR))
    assert.isTrue(ICR_E.gt(mv._MCR) && ICR_E.lt(TCR))

    /* With 300 in the SP, Alice (102 debt) and Bob (101 debt) should be entirely liquidated.
     That leaves 97 EBTC in the Pool that won’t be enough to absorb Carol,
     but it will be enough to liquidate Dennis. Afterwards the pool will be empty,
     so Erin won’t liquidated. */
    const cdpsToLiquidate = [_aliceCdpId, _bobCdpId, _carolCdpId, _dennisCdpId, _erinCdpId]
    const tx = await cdpManager.batchLiquidateCdps(cdpsToLiquidate)
    console.log('gasUsed: ', tx.receipt.gasUsed)

    // Check A, B and D are closed
    assert.isFalse(await sortedCdps.contains(_aliceCdpId))
    assert.isFalse(await sortedCdps.contains(_bobCdpId))
    assert.isFalse(await sortedCdps.contains(_dennisCdpId))

    // Check whale, C, D and E stay active
    assert.isTrue(await sortedCdps.contains(_whaleCdpId))
    assert.isTrue(await sortedCdps.contains(_carolCdpId))
    assert.isTrue(await sortedCdps.contains(_erinCdpId))
  })

  it("batchLiquidateCdps() with a non fullfilled liquidation: still can liquidate further cdps after the non-liquidated, non emptied pool", async () => {
    const { totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(196, 16)), extraParams: { from: alice } })
    const { totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(198, 16)), extraParams: { from: bob } })
    const { totalDebt: D_totalDebt } = await openCdp({ ICR: toBN(dec(206, 16)), extraParams: { from: dennis } })
    const { totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: D_totalDebt, extraParams: { from: carol } })
    await openCdp({ ICR: toBN(dec(208, 16)), extraParams: { from: erin } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);
    let _erinCdpId = await sortedCdps.cdpOfOwnerByIndex(erin, 0);

    // Whale provides EBTC to the SP
    const spDeposit = A_totalDebt.add(B_totalDebt).add(C_totalDebt.div(toBN(2)))
    await openCdp({ ICR: toBN(dec(220, 16)), extraEBTCAmount: spDeposit, extraParams: { from: whale } })
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: whale })
    let _whaleCdpId = await sortedCdps.cdpOfOwnerByIndex(whale, 0);

    // Price drops 
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()
    const TCR = await th.getTCR(contracts)

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check A, B, C, D, E cdps are in range 110% < ICR < TCR
    const ICR_A = await cdpManager.getCurrentICR(_aliceCdpId, price)
    const ICR_B = await cdpManager.getCurrentICR(_bobCdpId, price)
    const ICR_C = await cdpManager.getCurrentICR(_carolCdpId, price)
    const ICR_D = await cdpManager.getCurrentICR(_dennisCdpId, price)
    const ICR_E = await cdpManager.getCurrentICR(_erinCdpId, price)

    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C.gt(mv._MCR) && ICR_C.lt(TCR))
    assert.isTrue(ICR_D.gt(mv._MCR) && ICR_D.lt(TCR))
    assert.isTrue(ICR_E.gt(mv._MCR) && ICR_E.lt(TCR))

    /* With 301 in the SP, Alice (102 debt) and Bob (101 debt) should be entirely liquidated.
     That leaves 97 EBTC in the Pool that won’t be enough to absorb Carol,
     but it will be enough to liquidate Dennis. Afterwards the pool will be empty,
     so Erin won’t liquidated.
     Note that, compared to the previous test, this one will make 1 more loop iteration,
     so it will consume more gas. */
    const cdpsToLiquidate = [_aliceCdpId, _bobCdpId, _carolCdpId, _dennisCdpId, _erinCdpId]
    const tx = await cdpManager.batchLiquidateCdps(cdpsToLiquidate)
    console.log('gasUsed: ', tx.receipt.gasUsed)

    // Check A, B and D are closed
    assert.isFalse(await sortedCdps.contains(_aliceCdpId))
    assert.isFalse(await sortedCdps.contains(_bobCdpId))
    assert.isFalse(await sortedCdps.contains(_dennisCdpId))

    // Check whale, C, D and E stay active
    assert.isTrue(await sortedCdps.contains(_whaleCdpId))
    assert.isTrue(await sortedCdps.contains(_carolCdpId))
    assert.isTrue(await sortedCdps.contains(_erinCdpId))
  })

  it("batchLiquidateCdps() with a non fullfilled liquidation: total liquidated coll and debt is correct", async () => {
    const { collateral: A_coll, totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(196, 16)), extraParams: { from: alice } })
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(198, 16)), extraParams: { from: bob } })
    const { collateral: C_coll, totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: carol } })
    const { collateral: D_coll, totalDebt: D_totalDebt } = await openCdp({ ICR: toBN(dec(206, 16)), extraParams: { from: dennis } })
    const { collateral: E_coll, totalDebt: E_totalDebt } = await openCdp({ ICR: toBN(dec(208, 16)), extraParams: { from: erin } })

    // Whale provides EBTC to the SP
    const spDeposit = A_totalDebt.add(B_totalDebt).add(C_totalDebt.div(toBN(2)))
    await openCdp({ ICR: toBN(dec(220, 16)), extraEBTCAmount: spDeposit, extraParams: { from: whale } })
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: whale })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    // Price drops 
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()
    const TCR = await th.getTCR(contracts)

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check A, B, C, D, E cdps are in range 110% < ICR < TCR
    const ICR_A = await cdpManager.getCurrentICR(_aliceCdpId, price)
    const ICR_B = await cdpManager.getCurrentICR(_bobCdpId, price)
    const ICR_C = await cdpManager.getCurrentICR(_carolCdpId, price)

    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C.gt(mv._MCR) && ICR_C.lt(TCR))

    const entireSystemCollBefore = await cdpManager.getEntireSystemColl()
    const entireSystemDebtBefore = await cdpManager.getEntireSystemDebt()

    const cdpsToLiquidate = [_aliceCdpId, _bobCdpId, _carolCdpId]
    await cdpManager.batchLiquidateCdps(cdpsToLiquidate)

    // Expect system debt reduced by 203 EBTC and system coll by 2 ETH
    const entireSystemCollAfter = await cdpManager.getEntireSystemColl()
    const entireSystemDebtAfter = await cdpManager.getEntireSystemDebt()

    const changeInEntireSystemColl = entireSystemCollBefore.sub(entireSystemCollAfter)
    const changeInEntireSystemDebt = entireSystemDebtBefore.sub(entireSystemDebtAfter)

    assert.equal(changeInEntireSystemColl.toString(), A_coll.add(B_coll))
    th.assertIsApproximatelyEqual(changeInEntireSystemDebt.toString(), A_totalDebt.add(B_totalDebt))
  })

  it("batchLiquidateCdps() with a non fullfilled liquidation: emits correct liquidation event values", async () => {
    const { collateral: A_coll, totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(210, 16)), extraParams: { from: alice } })
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(211, 16)), extraParams: { from: bob } })
    const { totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(212, 16)), extraParams: { from: carol } })
    await openCdp({ ICR: toBN(dec(219, 16)), extraParams: { from: dennis } })
    await openCdp({ ICR: toBN(dec(221, 16)), extraParams: { from: erin } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    // Whale provides EBTC to the SP
    const spDeposit = A_totalDebt.add(B_totalDebt).add(C_totalDebt.div(toBN(2)))
    await openCdp({ ICR: toBN(dec(220, 16)), extraEBTCAmount: spDeposit, extraParams: { from: whale } })
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: whale })

    // Price drops 
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()
    const TCR = await th.getTCR(contracts)

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check A, B, C cdps are in range 110% < ICR < TCR
    const ICR_A = await cdpManager.getCurrentICR(_aliceCdpId, price)
    const ICR_B = await cdpManager.getCurrentICR(_bobCdpId, price)
    const ICR_C = await cdpManager.getCurrentICR(_carolCdpId, price)

    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C.gt(mv._MCR) && ICR_C.lt(TCR))

    const cdpsToLiquidate = [_aliceCdpId, _bobCdpId, _carolCdpId]
    const liquidationTx = await cdpManager.batchLiquidateCdps(cdpsToLiquidate)

    const [liquidatedDebt, liquidatedColl, collGasComp, ebtcGasComp] = th.getEmittedLiquidationValues(liquidationTx)

    th.assertIsApproximatelyEqual(liquidatedDebt, A_totalDebt.add(B_totalDebt))
    const equivalentColl = A_totalDebt.add(B_totalDebt).mul(toBN(dec(11, 17))).div(price)
    th.assertIsApproximatelyEqual(liquidatedColl, th.applyLiquidationFee(equivalentColl))
    th.assertIsApproximatelyEqual(collGasComp, equivalentColl.sub(th.applyLiquidationFee(equivalentColl))) // 0.5% of 283/120*1.1
    assert.equal(ebtcGasComp.toString(), dec(400, 18))

    // check collateral surplus
    const alice_remainingCollateral = A_coll.sub(A_totalDebt.mul(th.toBN(dec(11, 17))).div(price))
    const bob_remainingCollateral = B_coll.sub(B_totalDebt.mul(th.toBN(dec(11, 17))).div(price))
    th.assertIsApproximatelyEqual(await collSurplusPool.getCollateral(alice), alice_remainingCollateral)
    th.assertIsApproximatelyEqual(await collSurplusPool.getCollateral(bob), bob_remainingCollateral)

    // can claim collateral
    const alice_balanceBefore = th.toBN(await web3.eth.getBalance(alice))
    const ALICE_GAS = th.gasUsed(await borrowerOperations.claimCollateral({ from: alice, gasPrice: GAS_PRICE  }))
    const alice_balanceAfter = th.toBN(await web3.eth.getBalance(alice))
    //th.assertIsApproximatelyEqual(alice_balanceAfter, alice_balanceBefore.add(th.toBN(alice_remainingCollateral).sub(th.toBN(ALICE_GAS * GAS_PRICE))))

    const bob_balanceBefore = th.toBN(await web3.eth.getBalance(bob))
    const BOB_GAS = th.gasUsed(await borrowerOperations.claimCollateral({ from: bob, gasPrice: GAS_PRICE  }))
    const bob_balanceAfter = th.toBN(await web3.eth.getBalance(bob))
    th.assertIsApproximatelyEqual(bob_balanceAfter, bob_balanceBefore.add(th.toBN(bob_remainingCollateral).sub(th.toBN(BOB_GAS * GAS_PRICE))))
  })

  it("batchLiquidateCdps() with a non fullfilled liquidation: ICR of non liquidated cdp does not change", async () => {
    const { totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(211, 16)), extraParams: { from: alice } })
    const { totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(212, 16)), extraParams: { from: bob } })
    const { totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(210, 16)), extraParams: { from: carol } })
    await openCdp({ ICR: toBN(dec(219, 16)), extraParams: { from: dennis } })
    await openCdp({ ICR: toBN(dec(221, 16)), extraParams: { from: erin } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    // Whale provides EBTC to the SP
    const spDeposit = A_totalDebt.add(B_totalDebt).add(C_totalDebt.div(toBN(2)))
    await openCdp({ ICR: toBN(dec(220, 16)), extraEBTCAmount: spDeposit, extraParams: { from: whale } })
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: whale })

    // Price drops 
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()
    const TCR = await th.getTCR(contracts)

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check A, B, C cdps are in range 110% < ICR < TCR
    const ICR_A = await cdpManager.getCurrentICR(_aliceCdpId, price)
    const ICR_B = await cdpManager.getCurrentICR(_bobCdpId, price)
    const ICR_C_Before = await cdpManager.getCurrentICR(_carolCdpId, price)

    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C_Before.gt(mv._MCR) && ICR_C_Before.lt(TCR))

    const cdpsToLiquidate = [_aliceCdpId, _bobCdpId, _carolCdpId]
    await cdpManager.batchLiquidateCdps(cdpsToLiquidate)

    const ICR_C_After = await cdpManager.getCurrentICR(_carolCdpId, price)
    assert.equal(ICR_C_Before.toString(), ICR_C_After)
  })

  it("batchLiquidateCdps(), with 110% < ICR < TCR, and StabilityPool EBTC > debt to liquidate: can liquidate cdps out of order", async () => {
    const { totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: alice } })
    const { totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(202, 16)), extraParams: { from: bob } })
    const { totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(204, 16)), extraParams: { from: carol } })
    const { totalDebt: D_totalDebt } = await openCdp({ ICR: toBN(dec(206, 16)), extraParams: { from: dennis } })
    await openCdp({ ICR: toBN(dec(280, 16)), extraEBTCAmount: dec(500, 18), extraParams: { from: erin } })
    await openCdp({ ICR: toBN(dec(282, 16)), extraEBTCAmount: dec(500, 18), extraParams: { from: freddy } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);

    // Whale provides 1000 EBTC to the SP
    const spDeposit = A_totalDebt.add(C_totalDebt).add(D_totalDebt)
    await openCdp({ ICR: toBN(dec(219, 16)), extraEBTCAmount: spDeposit, extraParams: { from: whale } })
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: whale })

    // Price drops
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check cdps A-D are in range 110% < ICR < TCR
    const ICR_A = await cdpManager.getCurrentICR(_aliceCdpId, price)
    const ICR_B = await cdpManager.getCurrentICR(_bobCdpId, price)
    const ICR_C = await cdpManager.getCurrentICR(_carolCdpId, price)
    const ICR_D = await cdpManager.getCurrentICR(_dennisCdpId, price)
    const TCR = await th.getTCR(contracts)

    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C.gt(mv._MCR) && ICR_C.lt(TCR))
    assert.isTrue(ICR_D.gt(mv._MCR) && ICR_D.lt(TCR))

    // Cdps are ordered by ICR, low to high: A, B, C, D.

    // Liquidate out of ICR order: D, B, C. A (lowest ICR) not included.
    const cdpsToLiquidate = [_dennisCdpId, _bobCdpId, _carolCdpId]

    const liquidationTx = await cdpManager.batchLiquidateCdps(cdpsToLiquidate)

    // Check transaction succeeded
    assert.isTrue(liquidationTx.receipt.status)

    // Confirm cdps D, B, C removed
    assert.isFalse(await sortedCdps.contains(_dennisCdpId))
    assert.isFalse(await sortedCdps.contains(_bobCdpId))
    assert.isFalse(await sortedCdps.contains(_carolCdpId))

    // Confirm cdps have status 'liquidated' (Status enum element idx 3)
    assert.equal((await cdpManager.Cdps(_dennisCdpId))[3], '3')
    assert.equal((await cdpManager.Cdps(_bobCdpId))[3], '3')
    assert.equal((await cdpManager.Cdps(_carolCdpId))[3], '3')
  })

  it("batchLiquidateCdps(), with 110% < ICR < TCR, and StabilityPool empty: doesn't liquidate any cdps", async () => {
    await openCdp({ ICR: toBN(dec(222, 16)), extraParams: { from: alice } })
    const { totalDebt: bobDebt_Before } = await openCdp({ ICR: toBN(dec(224, 16)), extraParams: { from: bob } })
    const { totalDebt: carolDebt_Before } = await openCdp({ ICR: toBN(dec(226, 16)), extraParams: { from: carol } })
    const { totalDebt: dennisDebt_Before } = await openCdp({ ICR: toBN(dec(228, 16)), extraParams: { from: dennis } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);

    const bobColl_Before = (await cdpManager.Cdps(_bobCdpId))[1]
    const carolColl_Before = (await cdpManager.Cdps(_carolCdpId))[1]
    const dennisColl_Before = (await cdpManager.Cdps(_dennisCdpId))[1]

    await openCdp({ ICR: toBN(dec(228, 16)), extraParams: { from: erin } })
    await openCdp({ ICR: toBN(dec(230, 16)), extraParams: { from: freddy } })

    // Price drops
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()
    const TCR = await th.getTCR(contracts)

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check cdps A-D are in range 110% < ICR < TCR
    const ICR_A = await cdpManager.getCurrentICR(_aliceCdpId, price)
    const ICR_B = await cdpManager.getCurrentICR(_bobCdpId, price)
    const ICR_C = await cdpManager.getCurrentICR(_carolCdpId, price)

    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C.gt(mv._MCR) && ICR_C.lt(TCR))

    // Cdps are ordered by ICR, low to high: A, B, C, D. 
    // Liquidate out of ICR order: D, B, C. A (lowest ICR) not included.
    const cdpsToLiquidate = [_dennisCdpId, _bobCdpId, _carolCdpId]
    await assertRevert(cdpManager.batchLiquidateCdps(cdpsToLiquidate), "CdpManager: nothing to liquidate")

    // Confirm cdps D, B, C remain in system
    assert.isTrue(await sortedCdps.contains(_dennisCdpId))
    assert.isTrue(await sortedCdps.contains(_bobCdpId))
    assert.isTrue(await sortedCdps.contains(_carolCdpId))

    // Confirm cdps have status 'active' (Status enum element idx 1)
    assert.equal((await cdpManager.Cdps(_dennisCdpId))[3], '1')
    assert.equal((await cdpManager.Cdps(_bobCdpId))[3], '1')
    assert.equal((await cdpManager.Cdps(_carolCdpId))[3], '1')

    // Confirm D, B, C coll & debt have not changed
    const dennisDebt_After = (await cdpManager.Cdps(_dennisCdpId))[0].add((await cdpManager.getPendingEBTCDebtReward(dennis))[0])
    const bobDebt_After = (await cdpManager.Cdps(_bobCdpId))[0].add((await cdpManager.getPendingEBTCDebtReward(bob))[0])
    const carolDebt_After = (await cdpManager.Cdps(_carolCdpId))[0].add((await cdpManager.getPendingEBTCDebtReward(carol))[0])

    const dennisColl_After = (await cdpManager.Cdps(_dennisCdpId))[1].add(await cdpManager.getPendingETHReward(dennis))  
    const bobColl_After = (await cdpManager.Cdps(_bobCdpId))[1].add(await cdpManager.getPendingETHReward(bob))
    const carolColl_After = (await cdpManager.Cdps(_carolCdpId))[1].add(await cdpManager.getPendingETHReward(carol))

    assert.isTrue(dennisColl_After.eq(dennisColl_Before))
    assert.isTrue(bobColl_After.eq(bobColl_Before))
    assert.isTrue(carolColl_After.eq(carolColl_Before))

    th.assertIsApproximatelyEqual(th.toBN(dennisDebt_Before).toString(), dennisDebt_After.toString())
    th.assertIsApproximatelyEqual(th.toBN(bobDebt_Before).toString(), bobDebt_After.toString())
    th.assertIsApproximatelyEqual(th.toBN(carolDebt_Before).toString(), carolDebt_After.toString())
  })

  it('batchLiquidateCdps(): skips liquidation of cdps with ICR > TCR, regardless of Stability Pool size', async () => {
    // Cdps that will fall into ICR range 100-MCR
    const { totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(194, 16)), extraParams: { from: A } })
    const { totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(196, 16)), extraParams: { from: B } })
    const { totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(198, 16)), extraParams: { from: C } })

    // Cdps that will fall into ICR range 110-TCR
    const { totalDebt: D_totalDebt } = await openCdp({ ICR: toBN(dec(221, 16)), extraParams: { from: D } })
    await openCdp({ ICR: toBN(dec(223, 16)), extraParams: { from: E } })
    F = freddy
    G = greta
    H = harry
    I = ida	
    await openCdp({ ICR: toBN(dec(225, 16)), extraParams: { from: F } })

    // Cdps that will fall into ICR range >= TCR
    const { totalDebt: G_totalDebt } = await openCdp({ ICR: toBN(dec(250, 16)), extraParams: { from: G } })
    const { totalDebt: H_totalDebt } = await openCdp({ ICR: toBN(dec(270, 16)), extraParams: { from: H } })
    const { totalDebt: I_totalDebt } = await openCdp({ ICR: toBN(dec(290, 16)), extraParams: { from: I } })

    // Whale adds EBTC to SP
    const spDeposit = A_totalDebt.add(C_totalDebt).add(D_totalDebt).add(G_totalDebt).add(H_totalDebt).add(I_totalDebt)
    await openCdp({ ICR: toBN(dec(245, 16)), extraEBTCAmount: spDeposit, extraParams: { from: whale } })
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: whale })
    let _aCdpId = await sortedCdps.cdpOfOwnerByIndex(A, 0);
    let _bCdpId = await sortedCdps.cdpOfOwnerByIndex(B, 0);
    let _cCdpId = await sortedCdps.cdpOfOwnerByIndex(C, 0);
    let _dCdpId = await sortedCdps.cdpOfOwnerByIndex(D, 0);
    let _eCdpId = await sortedCdps.cdpOfOwnerByIndex(E, 0);
    let _fCdpId = await sortedCdps.cdpOfOwnerByIndex(F, 0);
    let _gCdpId = await sortedCdps.cdpOfOwnerByIndex(G, 0);
    let _hCdpId = await sortedCdps.cdpOfOwnerByIndex(H, 0);
    let _iCdpId = await sortedCdps.cdpOfOwnerByIndex(I, 0);

    // Price drops, but all cdps remain active
    await priceFeed.setPrice(dec(110, 18)) 
    const price = await priceFeed.getPrice()
    const TCR = await th.getTCR(contracts)

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    const G_collBefore = (await cdpManager.Cdps(_gCdpId))[1]
    const G_debtBefore = (await cdpManager.Cdps(_gCdpId))[0]
    const H_collBefore = (await cdpManager.Cdps(_hCdpId))[1]
    const H_debtBefore = (await cdpManager.Cdps(_hCdpId))[0]
    const I_collBefore = (await cdpManager.Cdps(_iCdpId))[1]
    const I_debtBefore = (await cdpManager.Cdps(_iCdpId))[0]

    const ICR_A = await cdpManager.getCurrentICR(_aCdpId, price) 
    const ICR_B = await cdpManager.getCurrentICR(_bCdpId, price) 
    const ICR_C = await cdpManager.getCurrentICR(_cCdpId, price) 
    const ICR_D = await cdpManager.getCurrentICR(_dCdpId, price)
    const ICR_E = await cdpManager.getCurrentICR(_eCdpId, price)
    const ICR_F = await cdpManager.getCurrentICR(_fCdpId, price)
    const ICR_G = await cdpManager.getCurrentICR(_gCdpId, price)
    const ICR_H = await cdpManager.getCurrentICR(_hCdpId, price)
    const ICR_I = await cdpManager.getCurrentICR(_iCdpId, price)

    // Check A-C are in range 100-110
    assert.isTrue(ICR_A.gte(mv._ICR100) && ICR_A.lt(mv._MCR))
    assert.isTrue(ICR_B.gte(mv._ICR100) && ICR_B.lt(mv._MCR))
    assert.isTrue(ICR_C.gte(mv._ICR100) && ICR_C.lt(mv._MCR))

    // Check D-F are in range 110-TCR
    assert.isTrue(ICR_D.gt(mv._MCR) && ICR_D.lt(TCR))
    assert.isTrue(ICR_E.gt(mv._MCR) && ICR_E.lt(TCR))
    assert.isTrue(ICR_F.gt(mv._MCR) && ICR_F.lt(TCR))

    // Check G-I are in range >= TCR
    assert.isTrue(ICR_G.gte(TCR))
    assert.isTrue(ICR_H.gte(TCR))
    assert.isTrue(ICR_I.gte(TCR))

    // Attempt to liquidate only cdps with ICR > TCR% 
    await assertRevert(cdpManager.batchLiquidateCdps([_gCdpId, _hCdpId, _iCdpId]), "CdpManager: nothing to liquidate")

    // Check G, H, I remain in system
    assert.isTrue(await sortedCdps.contains(_gCdpId))
    assert.isTrue(await sortedCdps.contains(_hCdpId))
    assert.isTrue(await sortedCdps.contains(_iCdpId))

    // Check G, H, I coll and debt have not changed
    assert.equal(G_collBefore.eq(await cdpManager.Cdps(_gCdpId))[1])
    assert.equal(G_debtBefore.eq(await cdpManager.Cdps(_gCdpId))[0])
    assert.equal(H_collBefore.eq(await cdpManager.Cdps(_hCdpId))[1])
    assert.equal(H_debtBefore.eq(await cdpManager.Cdps(_hCdpId))[0])
    assert.equal(I_collBefore.eq(await cdpManager.Cdps(_iCdpId))[1])
    assert.equal(I_debtBefore.eq(await cdpManager.Cdps(_iCdpId))[0])

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))
  
    // Attempt to liquidate a variety of cdps with SP covering whole batch.
    // Expect A, C, D to be liquidated, and G, H, I to remain in system
    await cdpManager.batchLiquidateCdps([_cCdpId, _dCdpId, _gCdpId, _hCdpId, _aCdpId, _iCdpId])
    
    // Confirm A, C, D liquidated  
    assert.isFalse(await sortedCdps.contains(_cCdpId))
    assert.isFalse(await sortedCdps.contains(_aCdpId))
    assert.isFalse(await sortedCdps.contains(_dCdpId))
    
    // Check G, H, I remain in system
    assert.isTrue(await sortedCdps.contains(_gCdpId))
    assert.isTrue(await sortedCdps.contains(_hCdpId))
    assert.isTrue(await sortedCdps.contains(_iCdpId))

    // Check coll and debt have not changed
    assert.equal(G_collBefore.eq(await cdpManager.Cdps(_gCdpId))[1])
    assert.equal(G_debtBefore.eq(await cdpManager.Cdps(_gCdpId))[0])
    assert.equal(H_collBefore.eq(await cdpManager.Cdps(_hCdpId))[1])
    assert.equal(H_debtBefore.eq(await cdpManager.Cdps(_hCdpId))[0])
    assert.equal(I_collBefore.eq(await cdpManager.Cdps(_iCdpId))[1])
    assert.equal(I_debtBefore.eq(await cdpManager.Cdps(_iCdpId))[0])

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Whale withdraws entire deposit, and re-deposits 132 EBTC
    // Increasing the price for a moment to avoid pending liquidations to block withdrawal
    await priceFeed.setPrice(dec(200, 18))
    await stabilityPool.withdrawFromSP(spDeposit, {from: whale})
    await priceFeed.setPrice(dec(110, 18))
    await stabilityPool.provideToSP(B_totalDebt.add(toBN(dec(50, 18))), ZERO_ADDRESS, {from: whale})

    // B and E are still in range 110-TCR.
    // Attempt to liquidate B, G, H, I, E.
    // Expected Stability Pool to fully absorb B (92 EBTC + 10 virtual debt), 
    // but not E as there are not enough funds in Stability Pool
    
    const stabilityBefore = await stabilityPool.getTotalEBTCDeposits()
    const dEbtBefore = (await cdpManager.Cdps(_eCdpId))[0]

    await cdpManager.batchLiquidateCdps([_bCdpId, _gCdpId, _hCdpId, _iCdpId, _eCdpId])
    
    const dEbtAfter = (await cdpManager.Cdps(_eCdpId))[0]
    const stabilityAfter = await stabilityPool.getTotalEBTCDeposits()
    
    const stabilityDelta = stabilityBefore.sub(stabilityAfter)  
    const dEbtDelta = dEbtBefore.sub(dEbtAfter)

    th.assertIsApproximatelyEqual(stabilityDelta, B_totalDebt)
    assert.equal((dEbtDelta.toString()), '0')
    
    // Confirm B removed and E active 
    assert.isFalse(await sortedCdps.contains(_bCdpId)) 
    assert.isTrue(await sortedCdps.contains(_eCdpId))

    // Check G, H, I remain in system
    assert.isTrue(await sortedCdps.contains(_gCdpId))
    assert.isTrue(await sortedCdps.contains(_hCdpId))
    assert.isTrue(await sortedCdps.contains(_iCdpId))

    // Check coll and debt have not changed
    assert.equal(G_collBefore.eq(await cdpManager.Cdps(_gCdpId))[1])
    assert.equal(G_debtBefore.eq(await cdpManager.Cdps(_gCdpId))[0])
    assert.equal(H_collBefore.eq(await cdpManager.Cdps(_hCdpId))[1])
    assert.equal(H_debtBefore.eq(await cdpManager.Cdps(_hCdpId))[0])
    assert.equal(I_collBefore.eq(await cdpManager.Cdps(_iCdpId))[1])
    assert.equal(I_debtBefore.eq(await cdpManager.Cdps(_iCdpId))[0])
  })

  it('batchLiquidateCdps(): emits liquidation event with correct values when all cdps have ICR > 110% and Stability Pool covers a subset of cdps', async () => {
    // Cdps to be absorbed by SP
    const { collateral: F_coll, totalDebt: F_totalDebt } = await openCdp({ ICR: toBN(dec(222, 16)), extraParams: { from: freddy } })
    const { collateral: G_coll, totalDebt: G_totalDebt } = await openCdp({ ICR: toBN(dec(222, 16)), extraParams: { from: greta } })

    // Cdps to be spared
    await openCdp({ ICR: toBN(dec(250, 16)), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(266, 16)), extraParams: { from: bob } })
    await openCdp({ ICR: toBN(dec(285, 16)), extraParams: { from: carol } })
    await openCdp({ ICR: toBN(dec(308, 16)), extraParams: { from: dennis } })

    // Whale adds EBTC to SP
    const spDeposit = F_totalDebt.add(G_totalDebt)
    await openCdp({ ICR: toBN(dec(285, 16)), extraEBTCAmount: spDeposit, extraParams: { from: whale } })
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: whale })
    let _whaleCdpId = await sortedCdps.cdpOfOwnerByIndex(whale, 0);
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);
    let _freddyCdpId = await sortedCdps.cdpOfOwnerByIndex(freddy, 0);
    let _gretaCdpId = await sortedCdps.cdpOfOwnerByIndex(greta, 0);

    // Price drops, but all cdps remain active
    await priceFeed.setPrice(dec(100, 18))
    const price = await priceFeed.getPrice()

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Confirm all cdps have ICR > MCR
    assert.isTrue((await cdpManager.getCurrentICR(_freddyCdpId, price)).gte(mv._MCR))
    assert.isTrue((await cdpManager.getCurrentICR(_gretaCdpId, price)).gte(mv._MCR))
    assert.isTrue((await cdpManager.getCurrentICR(_aliceCdpId, price)).gte(mv._MCR))
    assert.isTrue((await cdpManager.getCurrentICR(_bobCdpId, price)).gte(mv._MCR))
    assert.isTrue((await cdpManager.getCurrentICR(_carolCdpId, price)).gte(mv._MCR))

    // Confirm EBTC in Stability Pool
    assert.equal((await stabilityPool.getTotalEBTCDeposits()).toString(), spDeposit.toString())

    const cdpsToLiquidate = [_freddyCdpId, _gretaCdpId, _aliceCdpId, _bobCdpId, _carolCdpId, _dennisCdpId, _whaleCdpId]

    // Attempt liqudation sequence
    const liquidationTx = await cdpManager.batchLiquidateCdps(cdpsToLiquidate)
    const [liquidatedDebt, liquidatedColl, gasComp] = th.getEmittedLiquidationValues(liquidationTx)

    // Check F and G were liquidated
    assert.isFalse(await sortedCdps.contains(_freddyCdpId))
    assert.isFalse(await sortedCdps.contains(_gretaCdpId))

    // Check whale and A-D remain active
    assert.isTrue(await sortedCdps.contains(_aliceCdpId))
    assert.isTrue(await sortedCdps.contains(_bobCdpId))
    assert.isTrue(await sortedCdps.contains(_carolCdpId))
    assert.isTrue(await sortedCdps.contains(_dennisCdpId))
    assert.isTrue(await sortedCdps.contains(_whaleCdpId))

    // Liquidation event emits coll = (F_debt + G_debt)/price*1.1*0.995, and debt = (F_debt + G_debt)
    th.assertIsApproximatelyEqual(liquidatedDebt, F_totalDebt.add(G_totalDebt))
    th.assertIsApproximatelyEqual(liquidatedColl, th.applyLiquidationFee(F_totalDebt.add(G_totalDebt).mul(toBN(dec(11, 17))).div(price)))

    // check collateral surplus
    const freddy_remainingCollateral = F_coll.sub(F_totalDebt.mul(th.toBN(dec(11, 17))).div(price))
    const greta_remainingCollateral = G_coll.sub(G_totalDebt.mul(th.toBN(dec(11, 17))).div(price))
    th.assertIsApproximatelyEqual(await collSurplusPool.getCollateral(freddy), freddy_remainingCollateral)
    th.assertIsApproximatelyEqual(await collSurplusPool.getCollateral(greta), greta_remainingCollateral)

    // can claim collateral
    const freddy_balanceBefore = th.toBN(await web3.eth.getBalance(freddy))
    const FREDDY_GAS = th.gasUsed(await borrowerOperations.claimCollateral({ from: freddy, gasPrice: GAS_PRICE  }))
    const freddy_expectedBalance = freddy_balanceBefore.sub(th.toBN(FREDDY_GAS * GAS_PRICE))
    const freddy_balanceAfter = th.toBN(await web3.eth.getBalance(freddy))
    th.assertIsApproximatelyEqual(freddy_balanceAfter, freddy_expectedBalance.add(th.toBN(freddy_remainingCollateral)))

    const greta_balanceBefore = th.toBN(await web3.eth.getBalance(greta))
    const GRETA_GAS = th.gasUsed(await borrowerOperations.claimCollateral({ from: greta, gasPrice: GAS_PRICE  }))
    const greta_expectedBalance = greta_balanceBefore.sub(th.toBN(GRETA_GAS * GAS_PRICE))
    const greta_balanceAfter = th.toBN(await web3.eth.getBalance(greta))
    th.assertIsApproximatelyEqual(greta_balanceAfter, greta_expectedBalance.add(th.toBN(greta_remainingCollateral)))
  })

  it('batchLiquidateCdps(): emits liquidation event with correct values when all cdps have ICR > 110% and Stability Pool covers a subset of cdps, including a partial', async () => {
    // Cdps to be absorbed by SP
    const { collateral: F_coll, totalDebt: F_totalDebt } = await openCdp({ ICR: toBN(dec(222, 16)), extraParams: { from: freddy } })
    const { collateral: G_coll, totalDebt: G_totalDebt } = await openCdp({ ICR: toBN(dec(222, 16)), extraParams: { from: greta } })

    // Cdps to be spared
    const { collateral: A_coll, totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(250, 16)), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(266, 16)), extraParams: { from: bob } })
    await openCdp({ ICR: toBN(dec(285, 16)), extraParams: { from: carol } })
    await openCdp({ ICR: toBN(dec(308, 16)), extraParams: { from: dennis } })

    // Whale opens cdp and adds 220 EBTC to SP
    const spDeposit = F_totalDebt.add(G_totalDebt).add(A_totalDebt.div(toBN(2)))
    await openCdp({ ICR: toBN(dec(285, 16)), extraEBTCAmount: spDeposit, extraParams: { from: whale } })
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: whale })
    let _whaleCdpId = await sortedCdps.cdpOfOwnerByIndex(whale, 0);
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);
    let _freddyCdpId = await sortedCdps.cdpOfOwnerByIndex(freddy, 0);
    let _gretaCdpId = await sortedCdps.cdpOfOwnerByIndex(greta, 0);

    // Price drops, but all cdps remain active
    await priceFeed.setPrice(dec(100, 18))
    const price = await priceFeed.getPrice()

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Confirm all cdps have ICR > MCR
    assert.isTrue((await cdpManager.getCurrentICR(_freddyCdpId, price)).gte(mv._MCR))
    assert.isTrue((await cdpManager.getCurrentICR(_gretaCdpId, price)).gte(mv._MCR))
    assert.isTrue((await cdpManager.getCurrentICR(_aliceCdpId, price)).gte(mv._MCR))
    assert.isTrue((await cdpManager.getCurrentICR(_bobCdpId, price)).gte(mv._MCR))
    assert.isTrue((await cdpManager.getCurrentICR(_carolCdpId, price)).gte(mv._MCR))

    // Confirm EBTC in Stability Pool
    assert.equal((await stabilityPool.getTotalEBTCDeposits()).toString(), spDeposit.toString())

    const cdpsToLiquidate = [_freddyCdpId, _gretaCdpId, _aliceCdpId, _bobCdpId, _carolCdpId, _dennisCdpId, _whaleCdpId]

    // Attempt liqudation sequence
    const liquidationTx = await cdpManager.batchLiquidateCdps(cdpsToLiquidate)
    const [liquidatedDebt, liquidatedColl, gasComp] = th.getEmittedLiquidationValues(liquidationTx)

    // Check F and G were liquidated
    assert.isFalse(await sortedCdps.contains(_freddyCdpId))
    assert.isFalse(await sortedCdps.contains(_gretaCdpId))

    // Check whale and A-D remain active
    assert.isTrue(await sortedCdps.contains(_aliceCdpId))
    assert.isTrue(await sortedCdps.contains(_bobCdpId))
    assert.isTrue(await sortedCdps.contains(_carolCdpId))
    assert.isTrue(await sortedCdps.contains(_dennisCdpId))
    assert.isTrue(await sortedCdps.contains(_whaleCdpId))

    // Check A's collateral and debt are the same
    const entireColl_A = (await cdpManager.Cdps(_aliceCdpId))[1].add(await cdpManager.getPendingETHReward(_aliceCdpId))
    const entireDebt_A = (await cdpManager.Cdps(_aliceCdpId))[0].add((await cdpManager.getPendingEBTCDebtReward(_aliceCdpId))[0])

    assert.equal(entireColl_A.toString(), A_coll)
    th.assertIsApproximatelyEqual(entireDebt_A.toString(), A_totalDebt)

    /* Liquidation event emits:
    coll = (F_debt + G_debt)/price*1.1*0.995
    debt = (F_debt + G_debt) */
    th.assertIsApproximatelyEqual(liquidatedDebt, F_totalDebt.add(G_totalDebt))
    th.assertIsApproximatelyEqual(liquidatedColl, th.applyLiquidationFee(F_totalDebt.add(G_totalDebt).mul(toBN(dec(11, 17))).div(price)))

    // check collateral surplus
    const freddy_remainingCollateral = F_coll.sub(F_totalDebt.mul(th.toBN(dec(11, 17))).div(price))
    const greta_remainingCollateral = G_coll.sub(G_totalDebt.mul(th.toBN(dec(11, 17))).div(price))
    let _fColResidue = await collSurplusPool.getCollateral(freddy);
    th.assertIsApproximatelyEqual(_fColResidue, freddy_remainingCollateral)
    th.assertIsApproximatelyEqual(await collSurplusPool.getCollateral(greta), greta_remainingCollateral)

    // can claim collateral
    const freddy_balanceBefore = th.toBN(await web3.eth.getBalance(freddy))
    const FREDDY_GAS = th.gasUsed(await borrowerOperations.claimCollateral({ from: freddy, gasPrice: GAS_PRICE  }))
    const freddy_expectedBalance = freddy_balanceBefore.sub(th.toBN(FREDDY_GAS * GAS_PRICE))
    const freddy_balanceAfter = th.toBN(await web3.eth.getBalance(freddy))
    th.assertIsApproximatelyEqual(freddy_balanceAfter, freddy_expectedBalance.add(th.toBN(freddy_remainingCollateral)))

    const greta_balanceBefore = th.toBN(await web3.eth.getBalance(greta))
    const GRETA_GAS = th.gasUsed(await borrowerOperations.claimCollateral({ from: greta, gasPrice: GAS_PRICE  }))
    const greta_expectedBalance = greta_balanceBefore.sub(th.toBN(GRETA_GAS * GAS_PRICE))
    const greta_balanceAfter = th.toBN(await web3.eth.getBalance(greta))
    th.assertIsApproximatelyEqual(greta_balanceAfter, greta_expectedBalance.add(th.toBN(greta_remainingCollateral)))
  })

})

contract('Reset chain state', async accounts => { })
