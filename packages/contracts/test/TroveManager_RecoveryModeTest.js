const deploymentHelper = require("../utils/deploymentHelpers.js")
const testHelpers = require("../utils/testHelpers.js")

const th = testHelpers.TestHelper
const dec = th.dec
const toBN = th.toBN
const assertRevert = th.assertRevert
const mv = testHelpers.MoneyValues
const timeValues = testHelpers.TimeValues

const TroveManagerTester = artifacts.require("./TroveManagerTester")
const LUSDToken = artifacts.require("./LUSDToken.sol")

const GAS_PRICE = 10000000000 //10 GWEI

const hre = require("hardhat");

contract('TroveManager - in Recovery Mode', async accounts => {
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
  let lusdToken
  let sortedTroves
  let troveManager
  let activePool
  let stabilityPool
  let defaultPool
  let functionCaller
  let borrowerOperations
  let collSurplusPool

  let contracts

  const getOpenTroveLUSDAmount = async (totalDebt) => th.getOpenTroveLUSDAmount(contracts, totalDebt)
  const getNetBorrowingAmount = async (debtWithFee) => th.getNetBorrowingAmount(contracts, debtWithFee)
  const openTrove = async (params) => th.openTrove(contracts, params)

  before(async () => {	  
    // let _forkBlock = hre.network.config['forking']['blockNumber'];
    // let _forkUrl = hre.network.config['forking']['url'];
    // console.log("resetting to mainnet fork: block=" + _forkBlock + ',url=' + _forkUrl);
    // await hre.network.provider.request({ method: "hardhat_reset", params: [ { forking: { jsonRpcUrl: _forkUrl, blockNumber: _forkBlock }} ] });
    await hre.network.provider.request({method: "hardhat_impersonateAccount", params: [beadp]}); 
    beadpSigner = await ethers.provider.getSigner(beadp);	
  })

  beforeEach(async () => {
    contracts = await deploymentHelper.deployLiquityCore()
    contracts.troveManager = await TroveManagerTester.new()
    contracts.lusdToken = await LUSDToken.new(
      contracts.troveManager.address,
      contracts.stabilityPool.address,
      contracts.borrowerOperations.address
    )
    const LQTYContracts = await deploymentHelper.deployLQTYContracts(bountyAddress, lpRewardsAddress, multisig)

    priceFeed = contracts.priceFeedTestnet
    lusdToken = contracts.lusdToken
    sortedTroves = contracts.sortedTroves
    troveManager = contracts.troveManager
    activePool = contracts.activePool
    stabilityPool = contracts.stabilityPool
    defaultPool = contracts.defaultPool
    functionCaller = contracts.functionCaller
    borrowerOperations = contracts.borrowerOperations
    collSurplusPool = contracts.collSurplusPool
    debtToken = contracts.lusdToken;

    await deploymentHelper.connectLQTYContracts(LQTYContracts)
    await deploymentHelper.connectCoreContracts(contracts, LQTYContracts)
    await deploymentHelper.connectLQTYContractsToCore(LQTYContracts, contracts)

    ownerSigner = await ethers.provider.getSigner(owner);
    let _ownerBal = await web3.eth.getBalance(owner);
    let _beadpBal = await web3.eth.getBalance(beadp);
    let _ownerRicher = toBN(_ownerBal.toString()).gt(toBN(_beadpBal.toString()));
    let _signer = _ownerRicher? ownerSigner : beadpSigner;
  
    await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("1000")});
    await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("1000")});
    await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("1000")});
    await _signer.sendTransaction({ to: carol, value: ethers.utils.parseEther("1000")});

    let _val = dec(2000000, 18);
    if (toBN(_ownerBal.toString()).gt(toBN(_val))){
        await _signer.sendTransaction({ to: beadp, value: ethers.utils.parseEther("2000000")});		
    }
  })

  it("checkRecoveryMode(): Returns true if TCR falls below CCR", async () => {
    // --- SETUP ---
    //  Alice and Bob withdraw such that the TCR is ~150%
    await openTrove({ ICR: toBN(dec(150, 16)), extraParams: { from: alice } })
    await openTrove({ ICR: toBN(dec(150, 16)), extraParams: { from: bob } })

    const TCR = (await th.getTCR(contracts)).toString()
    assert.equal(TCR, dec(15, 17))

    const recoveryMode_Before = await th.checkRecoveryMode(contracts);
    assert.isFalse(recoveryMode_Before)

    // --- TEST ---

    // price drops to 1ETH:150LUSD, reducing TCR below 150%.  setPrice() calls checkTCRAndSetRecoveryMode() internally.
    await priceFeed.setPrice(dec(15, 17))

    // const price = await priceFeed.getPrice()
    // await troveManager.checkTCRAndSetRecoveryMode(price)

    const recoveryMode_After = await th.checkRecoveryMode(contracts);
    assert.isTrue(recoveryMode_After)
  })

  it("checkRecoveryMode(): Returns true if TCR stays less than CCR", async () => {
    // --- SETUP ---
    await openTrove({ ICR: toBN(dec(150, 16)), extraParams: { from: alice } })
    let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
    await openTrove({ ICR: toBN(dec(150, 16)), extraParams: { from: bob } })

    const TCR = (await th.getTCR(contracts)).toString()
    assert.equal(TCR, '1500000000000000000')

    // --- TEST ---

    // price drops to 1ETH:150LUSD, reducing TCR below 150%
    await priceFeed.setPrice('150000000000000000000')

    const recoveryMode_Before = await th.checkRecoveryMode(contracts);
    assert.isTrue(recoveryMode_Before)

    await borrowerOperations.addColl(_aliceTroveId, _aliceTroveId, _aliceTroveId, { from: alice, value: '1' })

    const recoveryMode_After = await th.checkRecoveryMode(contracts);
    assert.isTrue(recoveryMode_After)
  })

  it("checkRecoveryMode(): returns false if TCR stays above CCR", async () => {
    // --- SETUP ---
    await openTrove({ ICR: toBN(dec(450, 16)), extraParams: { from: alice } })
    let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
    await openTrove({ ICR: toBN(dec(150, 16)), extraParams: { from: bob } })

    // --- TEST ---
    const recoveryMode_Before = await th.checkRecoveryMode(contracts);
    assert.isFalse(recoveryMode_Before)

    await borrowerOperations.withdrawColl(_aliceTroveId, _1_Ether, _aliceTroveId, _aliceTroveId, { from: alice })

    const recoveryMode_After = await th.checkRecoveryMode(contracts);
    assert.isFalse(recoveryMode_After)
  })

  it("checkRecoveryMode(): returns false if TCR rises above CCR", async () => {
    // --- SETUP ---
    const { collateral: A_coll } = await openTrove({ ICR: toBN(dec(150, 16)), extraParams: { from: alice } })
    let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
    await openTrove({ ICR: toBN(dec(150, 16)), extraParams: { from: bob } })

    const TCR = (await th.getTCR(contracts)).toString()
    assert.equal(TCR, '1500000000000000000')

    // --- TEST ---
    // price drops to 1ETH:150LUSD, reducing TCR below 150%
    await priceFeed.setPrice('150000000000000000000')

    const recoveryMode_Before = await th.checkRecoveryMode(contracts);
    assert.isTrue(recoveryMode_Before)

    await borrowerOperations.addColl(_aliceTroveId, _aliceTroveId, _aliceTroveId, { from: alice, value: A_coll })

    const recoveryMode_After = await th.checkRecoveryMode(contracts);
    assert.isFalse(recoveryMode_After)
  })

  // --- liquidate() with ICR < 100% ---

  it("liquidate(), with ICR < 100%: removes stake and updates totalStakes", async () => {
    // --- SETUP ---
    //  Alice and Bob withdraw such that the TCR is ~150%
    const { collateral: A_coll } = await openTrove({ ICR: toBN(dec(150, 16)), extraParams: { from: alice } })
    const { collateral: B_coll } = await openTrove({ ICR: toBN(dec(150, 16)), extraLUSDAmount: dec(2000, 18), extraParams: { from: bob } })
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);

    const TCR = (await th.getTCR(contracts)).toString()
    assert.equal(TCR, '1500000000000000000')


    const bob_Stake_Before = (await troveManager.Troves(_bobTroveId))[2]
    const totalStakes_Before = await troveManager.totalStakes()

    assert.equal(bob_Stake_Before.toString(), B_coll)
    assert.equal(totalStakes_Before.toString(), A_coll.add(B_coll))

    // --- TEST ---
    // price drops to 1ETH:100LUSD, reducing TCR below 150%
    await priceFeed.setPrice('100000000000000000000')
    const price = await priceFeed.getPrice()

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // check Bob's ICR falls to 75%
    const bob_ICR = await troveManager.getCurrentICR(_bobTroveId, price);
    assert.equal(bob_ICR, '750000000000000000')

    // Liquidate Bob
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await troveManager.liquidateInBatchRecovery([_bobTroveId], {from: owner})

    const bob_Stake_After = (await troveManager.Troves(_bobTroveId))[2]
    const totalStakes_After = await troveManager.totalStakes()

    assert.equal(bob_Stake_After, 0)
    assert.equal(totalStakes_After.toString(), A_coll)
  })

  it("liquidate(), with ICR < 100%: updates system snapshots correctly", async () => {
    // --- SETUP ---
    //  Alice, Bob and Dennis withdraw such that their ICRs and the TCR is ~150%
    const { collateral: A_coll } = await openTrove({ ICR: toBN(dec(150, 16)), extraParams: { from: alice } })
    const { collateral: B_coll } = await openTrove({ ICR: toBN(dec(150, 16)), extraParams: { from: bob } })
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    const { collateral: D_coll } = await openTrove({ ICR: toBN(dec(150, 16)), extraParams: { from: dennis } })
    let _dennisTroveId = await sortedTroves.troveOfOwnerByIndex(dennis, 0);

    const TCR = (await th.getTCR(contracts)).toString()
    assert.equal(TCR, '1500000000000000000')

    // --- TEST ---
    // price drops to 1ETH:100LUSD, reducing TCR below 150%, and all Troves below 100% ICR
    await priceFeed.setPrice('100000000000000000000')

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // Dennis is liquidated
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});
    await troveManager.liquidateInBatchRecovery([_dennisTroveId], {from: owner})

    const totalStakesSnaphot_before = (await troveManager.totalStakesSnapshot()).toString()
    const totalCollateralSnapshot_before = (await troveManager.totalCollateralSnapshot()).toString()

    assert.equal(totalStakesSnaphot_before, A_coll.add(B_coll))
    assert.equal(totalCollateralSnapshot_before, A_coll.add(B_coll).add(th.applyLiquidationFee(toBN('0')))) // 6 + 3*0.995

    const A_reward  = th.applyLiquidationFee(D_coll).mul(A_coll).div(A_coll.add(B_coll))
    const B_reward  = th.applyLiquidationFee(D_coll).mul(B_coll).div(A_coll.add(B_coll))

    // Liquidate Bob
    await troveManager.liquidateInBatchRecovery([_bobTroveId], {from: owner})

    const totalStakesSnaphot_After = (await troveManager.totalStakesSnapshot())
    const totalCollateralSnapshot_After = (await troveManager.totalCollateralSnapshot())

    assert.equal(totalStakesSnaphot_After.toString(), A_coll)
    // total collateral should always be 9 minus gas compensations, as all liquidations in this test case are full redistributions
    assert.isAtMost(th.getDifference(totalCollateralSnapshot_After, A_coll.add(toBN('0')).add(th.applyLiquidationFee(toBN('0').add(toBN('0'))))), 1000) // 3 + 4.5*0.995 + 1.5*0.995^2
  })

  it("liquidate(), with ICR < 100%: closes the Trove and removes it from the Trove array", async () => {
    // --- SETUP ---
    //  Alice and Bob withdraw such that the TCR is ~150%
    await openTrove({ ICR: toBN(dec(150, 16)), extraParams: { from: alice } })
    await openTrove({ ICR: toBN(dec(150, 16)), extraLUSDAmount: dec(2000, 18), extraParams: { from: bob } })
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);

    const TCR = (await th.getTCR(contracts)).toString()
    assert.equal(TCR, '1500000000000000000')

    const bob_TroveStatus_Before = (await troveManager.Troves(_bobTroveId))[3]
    const bob_Trove_isInSortedList_Before = await sortedTroves.contains(_bobTroveId)

    assert.equal(bob_TroveStatus_Before, 1) // status enum element 1 corresponds to "Active"
    assert.isTrue(bob_Trove_isInSortedList_Before)

    // --- TEST ---
    // price drops to 1ETH:100LUSD, reducing TCR below 150%
    await priceFeed.setPrice('100000000000000000000')
    const price = await priceFeed.getPrice()

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // check Bob's ICR falls to 75%
    const bob_ICR = await troveManager.getCurrentICR(_bobTroveId, price);
    assert.equal(bob_ICR, '750000000000000000')

    // Liquidate Bob
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await troveManager.liquidateInBatchRecovery([_bobTroveId], {from: owner})

    // check Bob's Trove is successfully closed, and removed from sortedList
    const bob_TroveStatus_After = (await troveManager.Troves(_bobTroveId))[3]
    const bob_Trove_isInSortedList_After = await sortedTroves.contains(_bobTroveId)
    assert.equal(bob_TroveStatus_After, 3)  // status enum element 3 corresponds to "Closed by liquidation"
    assert.isFalse(bob_Trove_isInSortedList_After)
  })

  it("liquidate(), with ICR < 100%: only redistributes to active Troves - no offset to Stability Pool", async () => {
    // --- SETUP ---
    //  Alice, Bob and Dennis withdraw such that their ICRs and the TCR is ~150%
    const spDeposit = toBN(dec(390, 18))
    const { collateral: A_coll } = await openTrove({ ICR: toBN(dec(150, 16)), extraLUSDAmount: spDeposit, extraParams: { from: alice } })
    const { collateral: B_coll } = await openTrove({ ICR: toBN(dec(150, 16)), extraParams: { from: bob } })
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    const { collateral: D_coll } = await openTrove({ ICR: toBN(dec(150, 16)), extraParams: { from: dennis } })

    // Alice deposits to SP
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: alice })

    // check rewards-per-unit-staked before
    const P_Before = (await stabilityPool.P()).toString()

    assert.equal(P_Before, '1000000000000000000')

    // const TCR = (await th.getTCR(contracts)).toString()
    // assert.equal(TCR, '1500000000000000000')

    // --- TEST ---
    // price drops to 1ETH:100LUSD, reducing TCR below 150%, and all Troves below 100% ICR
    await priceFeed.setPrice('100000000000000000000')

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // liquidate bob
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});
    await troveManager.liquidateInBatchRecovery([_bobTroveId], {from: owner})

    // check SP rewards-per-unit-staked after liquidation - should be no increase
    const P_After = (await stabilityPool.P()).toString()

    assert.equal(P_After, '1000000000000000000')
  })

  // --- liquidate() with 100% < ICR < 110%

  it("liquidate(), with 100 < ICR < 110%: removes stake and updates totalStakes", async () => {
    // --- SETUP ---
    //  Bob withdraws up to 2000 LUSD of debt, bringing his ICR to 210%
    const { collateral: A_coll, totalDebt: A_totalDebt } = await openTrove({ ICR: toBN(dec(150, 16)), extraParams: { from: alice } })
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openTrove({ ICR: toBN(dec(210, 16)), extraLUSDAmount: dec(2000, 18), extraParams: { from: bob } })
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);

    let price = await priceFeed.getPrice()
    // Total TCR = 24*200/2050 = 234%
    const TCR = await th.getTCR(contracts)
    assert.isAtMost(th.getDifference(TCR, A_coll.add(B_coll).mul(price).div(A_totalDebt.add(B_totalDebt))), 1000)

    const bob_Stake_Before = (await troveManager.Troves(_bobTroveId))[2]
    const totalStakes_Before = await troveManager.totalStakes()

    assert.equal(bob_Stake_Before.toString(), B_coll)
    assert.equal(totalStakes_Before.toString(), A_coll.add(B_coll))

    // --- TEST ---
    // price drops to 1ETH:100LUSD, reducing TCR to 117%
    await priceFeed.setPrice('100000000000000000000')
    price = await priceFeed.getPrice()

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // check Bob's ICR falls to 105%
    const bob_ICR = await troveManager.getCurrentICR(_bobTroveId, price);
    assert.equal(bob_ICR, '1050000000000000000')

    // Liquidate Bob
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await troveManager.liquidateInBatchRecovery([_bobTroveId], {from: owner})

    const bob_Stake_After = (await troveManager.Troves(_bobTroveId))[2]
    const totalStakes_After = await troveManager.totalStakes()

    assert.equal(bob_Stake_After, 0)
    assert.equal(totalStakes_After.toString(), A_coll)
  })

  it("liquidate(), with 100% < ICR < 110%: updates system snapshots correctly", async () => {
    // --- SETUP ---
    //  Alice and Dennis withdraw such that their ICR is ~150%
    //  Bob withdraws up to 20000 LUSD of debt, bringing his ICR to 210%
    const { collateral: A_coll, totalDebt: A_totalDebt } = await openTrove({ ICR: toBN(dec(150, 16)), extraParams: { from: alice } })
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openTrove({ ICR: toBN(dec(210, 16)), extraLUSDAmount: dec(20000, 18), extraParams: { from: bob } })
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    const { collateral: D_coll } = await openTrove({ ICR: toBN(dec(150, 16)), extraParams: { from: dennis } })
    let _dennisTroveId = await sortedTroves.troveOfOwnerByIndex(dennis, 0);

    const totalStakesSnaphot_1 = (await troveManager.totalStakesSnapshot()).toString()
    const totalCollateralSnapshot_1 = (await troveManager.totalCollateralSnapshot()).toString()
    assert.equal(totalStakesSnaphot_1, 0)
    assert.equal(totalCollateralSnapshot_1, 0)

    // --- TEST ---
    // price drops to 1ETH:100LUSD, reducing TCR below 150%, and all Troves below 100% ICR
    await priceFeed.setPrice('100000000000000000000')
    const price = await priceFeed.getPrice()

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // Dennis is liquidated
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await troveManager.liquidateInBatchRecovery([_dennisTroveId], {from: owner})

    const A_reward  = th.applyLiquidationFee(D_coll).mul(A_coll).div(A_coll.add(B_coll))
    const B_reward  = th.applyLiquidationFee(D_coll).mul(B_coll).div(A_coll.add(B_coll))

    /*
    Prior to Dennis liquidation, total stakes and total collateral were each 27 ether. 
  
    Check snapshots. Dennis' liquidated collateral is distributed and remains in the system. His 
    stake is removed, leaving 24+3*0.995 ether total collateral, and 24 ether total stakes. */

    const totalStakesSnaphot_2 = (await troveManager.totalStakesSnapshot()).toString()
    const totalCollateralSnapshot_2 = (await troveManager.totalCollateralSnapshot()).toString()
    assert.equal(totalStakesSnaphot_2, A_coll.add(B_coll))
    assert.equal(totalCollateralSnapshot_2, A_coll.add(B_coll).add(th.applyLiquidationFee(toBN('0')))) // 24 + 3*0.995

    // check Bob's ICR is now in range 100% < ICR 110%
    const _110percent = web3.utils.toBN('1100000000000000000')
    const _100percent = web3.utils.toBN('1000000000000000000')

    const bob_ICR = (await troveManager.getCurrentICR(_bobTroveId, price))

    assert.isTrue(bob_ICR.lt(_110percent))
    assert.isTrue(bob_ICR.gt(_100percent))

    // Liquidate Bob
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await troveManager.liquidate(_bobTroveId, { from: owner })

    /* After Bob's liquidation, Bob's stake (21 ether) should be removed from total stakes, 
    but his collateral should remain in the system (*0.995). */
    const totalStakesSnaphot_3 = (await troveManager.totalStakesSnapshot())
    const totalCollateralSnapshot_3 = (await troveManager.totalCollateralSnapshot())
    assert.equal(totalStakesSnaphot_3.toString(), A_coll)
    // total collateral should always be 27 minus gas compensations, as all liquidations in this test case are full redistributions
    assert.isAtMost(th.getDifference(totalCollateralSnapshot_3.toString(), A_coll.add(toBN('0')).add(th.applyLiquidationFee(toBN('0').add(toBN('0'))))), 1000)
  })

  it("liquidate(), with 100% < ICR < 110%: closes the Trove and removes it from the Trove array", async () => {
    // --- SETUP ---
    //  Bob withdraws up to 2000 LUSD of debt, bringing his ICR to 210%
    const { collateral: A_coll, totalDebt: A_totalDebt } = await openTrove({ ICR: toBN(dec(150, 16)), extraParams: { from: alice } })
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openTrove({ ICR: toBN(dec(210, 16)), extraLUSDAmount: dec(2000, 18), extraParams: { from: bob } })
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);

    const bob_TroveStatus_Before = (await troveManager.Troves(_bobTroveId))[3]
    const bob_Trove_isInSortedList_Before = await sortedTroves.contains(_bobTroveId)

    assert.equal(bob_TroveStatus_Before, 1) // status enum element 1 corresponds to "Active"
    assert.isTrue(bob_Trove_isInSortedList_Before)

    // --- TEST ---
    // price drops to 1ETH:100LUSD, reducing TCR below 150%
    await priceFeed.setPrice('100000000000000000000')
    const price = await priceFeed.getPrice()


    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // check Bob's ICR has fallen to 105%
    const bob_ICR = await troveManager.getCurrentICR(_bobTroveId, price);
    assert.equal(bob_ICR, '1050000000000000000')

    // Liquidate Bob
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await troveManager.liquidateInBatchRecovery([_bobTroveId], {from: owner})

    // check Bob's Trove is successfully closed, and removed from sortedList
    const bob_TroveStatus_After = (await troveManager.Troves(_bobTroveId))[3]
    const bob_Trove_isInSortedList_After = await sortedTroves.contains(_bobTroveId)
    assert.equal(bob_TroveStatus_After, 3)  // status enum element 3 corresponds to "Closed by liquidation"
    assert.isFalse(bob_Trove_isInSortedList_After)
  })

  it("liquidate(), with 100% < ICR < 110%: offsets as much debt as possible with the Stability Pool, then redistributes the remainder coll and debt", async () => {
    // --- SETUP ---
    //  Alice and Dennis withdraw such that their ICR is ~150%
    //  Bob withdraws up to 2000 LUSD of debt, bringing his ICR to 210%
    const spDeposit = toBN(dec(390, 18))
    const { collateral: A_coll } = await openTrove({ ICR: toBN(dec(150, 16)), extraLUSDAmount: spDeposit, extraParams: { from: alice } })
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openTrove({ ICR: toBN(dec(210, 16)), extraLUSDAmount: dec(2000, 18), extraParams: { from: bob } })
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    const { collateral: D_coll } = await openTrove({ ICR: toBN(dec(150, 16)), extraParams: { from: dennis } })

    // Alice deposits 390LUSD to the Stability Pool
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: alice })

    // --- TEST ---
    // price drops to 1ETH:100LUSD, reducing TCR below 150%
    await priceFeed.setPrice('100000000000000000000')
    const price = await priceFeed.getPrice()

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // check Bob's ICR has fallen to 105%
    const bob_ICR = await troveManager.getCurrentICR(_bobTroveId, price);
    assert.equal(bob_ICR, '1050000000000000000')

    // check pool LUSD before liquidation
    const stabilityPoolLUSD_Before = (await stabilityPool.getTotalLUSDDeposits()).toString()
    assert.equal(stabilityPoolLUSD_Before, '390000000000000000000')

    // check Pool reward term before liquidation
    const P_Before = (await stabilityPool.P()).toString()

    assert.equal(P_Before, '1000000000000000000')

    /* Now, liquidate Bob. Liquidated coll is 21 ether, and liquidated debt is 2000 LUSD.
    
    With 390 LUSD in the StabilityPool, 390 LUSD should be offset with the pool, leaving 0 in the pool.
  
    Stability Pool rewards for alice should be:
    LUSDLoss: 390LUSD
    ETHGain: (390 / 2000) * 21*0.995 = 4.074525 ether

    After offsetting 390 LUSD and 4.074525 ether, the remainders - 1610 LUSD and 16.820475 ether - should be redistributed to all active Troves.
   */
    // Liquidate Bob
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await troveManager.liquidateInBatchRecovery([_bobTroveId], {from: owner})

    const aliceDeposit = await stabilityPool.getCompoundedLUSDDeposit(alice)
    const aliceETHGain = await stabilityPool.getDepositorETHGain(alice)
    const aliceExpectedETHGain = spDeposit.mul(th.applyLiquidationFee(toBN('0'))).div(B_totalDebt)

    assert.equal(aliceDeposit.toString(), spDeposit.toString())
    assert.equal(aliceETHGain.toString(), aliceExpectedETHGain)

    /* Now, check redistribution to active Troves. Remainders of 1610 LUSD and 16.82 ether are distributed.
    
    Now, only Alice and Dennis have a stake in the system - 3 ether each, thus total stakes is 6 ether.
  
    Rewards-per-unit-staked from the redistribution should be:
  
    L_LUSDDebt = 1610 / 6 = 268.333 LUSD
    L_ETH = 16.820475 /6 =  2.8034125 ether
    */
    const L_LUSDDebt = (await troveManager.L_LUSDDebt()).toString()
    const L_ETH = (await troveManager.L_ETH()).toString()

    assert.isAtMost(th.getDifference(L_LUSDDebt, toBN('0').add(toBN('0')).mul(mv._1e18BN).div(A_coll.add(D_coll))), 100)
    assert.isAtMost(th.getDifference(L_ETH, th.applyLiquidationFee(toBN('0').sub(toBN('0').mul(spDeposit).div(B_totalDebt)).mul(mv._1e18BN).div(A_coll.add(D_coll)))), 100)
  })

  // --- liquidate(), applied to trove with ICR > 110% that has the lowest ICR 

  it("liquidate(), with ICR > 110%, trove has lowest ICR, and StabilityPool is empty: does nothing", async () => {
    // --- SETUP ---
    // Alice and Dennis withdraw, resulting in ICRs of 266%. 
    // Bob withdraws, resulting in ICR of 240%. Bob has lowest ICR.
    const { collateral: A_coll } = await openTrove({ ICR: toBN(dec(266, 16)), extraParams: { from: alice } })
    let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openTrove({ ICR: toBN(dec(240, 16)), extraLUSDAmount: dec(2000, 18), extraParams: { from: bob } })
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    const { collateral: D_coll } = await openTrove({ ICR: toBN(dec(266, 16)), extraLUSDAmount: dec(2000, 18), extraParams: { from: dennis } })
    let _dennisTroveId = await sortedTroves.troveOfOwnerByIndex(dennis, 0);

    // --- TEST ---
    // price drops to 1ETH:100LUSD, reducing TCR below 150%
    await priceFeed.setPrice('100000000000000000000')
    const price = await priceFeed.getPrice()

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // Check Bob's ICR is >110% but still lowest
    const bob_ICR = (await troveManager.getCurrentICR(_bobTroveId, price)).toString()
    const alice_ICR = (await troveManager.getCurrentICR(_aliceTroveId, price)).toString()
    const dennis_ICR = (await troveManager.getCurrentICR(_dennisTroveId, price)).toString()
    assert.equal(bob_ICR, '1200000000000000000')
    assert.equal(alice_ICR, dec(133, 16))
    assert.equal(dennis_ICR, dec(133, 16))

    // console.log(`TCR: ${await th.getTCR(contracts)}`)
    // Try to liquidate Bob
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await troveManager.liquidateInBatchRecovery([_bobTroveId], {from: owner})

    // Check that Pool rewards don't change
    const P_Before = (await stabilityPool.P()).toString()

    assert.equal(P_Before, '1000000000000000000')

    // Check that redistribution rewards don't change
    const L_LUSDDebt = (await troveManager.L_LUSDDebt()).toString()
    const L_ETH = (await troveManager.L_ETH()).toString()

    assert.equal(L_LUSDDebt, '0')
    assert.equal(L_ETH, '0')

    // Check that Bob's Trove and stake remains active with unchanged coll and debt
    const bob_Trove = await troveManager.Troves(_bobTroveId);
    const bob_Debt = bob_Trove[0].toString()
    const bob_Coll = bob_Trove[1].toString()
    const bob_Stake = bob_Trove[2].toString()
    const bob_TroveStatus = bob_Trove[3].toString()
    const bob_isInSortedTrovesList = await sortedTroves.contains(_bobTroveId)

    th.assertIsApproximatelyEqual(bob_Debt.toString(), '0')
    assert.equal(bob_Coll.toString(), '0')
    assert.equal(bob_Stake.toString(), '0')
    assert.equal(bob_TroveStatus, '3')
    assert.isFalse(bob_isInSortedTrovesList)
  })

  // --- liquidate(), applied to trove with ICR > 110% that has the lowest ICR, and Stability Pool LUSD is GREATER THAN liquidated debt ---

  it("liquidate(), with 110% < ICR < TCR, and StabilityPool LUSD > debt to liquidate: offsets the trove entirely with the pool", async () => {
    // --- SETUP ---
    // Alice withdraws up to 1500 LUSD of debt, and Dennis up to 150, resulting in ICRs of 266%.
    // Bob withdraws up to 250 LUSD of debt, resulting in ICR of 240%. Bob has lowest ICR.
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openTrove({ ICR: toBN(dec(240, 16)), extraLUSDAmount: dec(250, 18), extraParams: { from: bob } })
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    const { collateral: A_coll } = await openTrove({ ICR: toBN(dec(266, 16)), extraLUSDAmount: B_totalDebt, extraParams: { from: alice } })
    const { collateral: D_coll } = await openTrove({ ICR: toBN(dec(266, 16)), extraLUSDAmount: dec(2000, 18), extraParams: { from: dennis } })

    // Alice deposits LUSD in the Stability Pool
    const spDeposit = B_totalDebt.add(toBN(1))
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: alice })

    // --- TEST ---
    // price drops to 1ETH:100LUSD, reducing TCR below 150%
    await priceFeed.setPrice('100000000000000000000')
    const price = await priceFeed.getPrice()
    const TCR = await th.getTCR(contracts)

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // Check Bob's ICR is between 110 and TCR
    const bob_ICR = await troveManager.getCurrentICR(_bobTroveId, price)
    assert.isTrue(bob_ICR.gt(mv._MCR) && bob_ICR.lt(TCR))

    // Liquidate Bob
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await troveManager.liquidateInBatchRecovery([_bobTroveId], {from: owner})

    /* Check accrued Stability Pool rewards after. Total Pool deposits was 1490 LUSD, Alice sole depositor.
    As liquidated debt (250 LUSD) was completely offset

    Alice's expected compounded deposit: (1490 - 250) = 1240LUSD
    Alice's expected ETH gain:  Bob's liquidated capped coll (minus gas comp), 2.75*0.995 ether
  
    */
    const aliceExpectedDeposit = await stabilityPool.getCompoundedLUSDDeposit(alice)
    const aliceExpectedETHGain = await stabilityPool.getDepositorETHGain(alice)

    assert.isAtMost(th.getDifference(aliceExpectedDeposit.toString(), spDeposit.sub(toBN('0'))), 2000)
    assert.isAtMost(th.getDifference(aliceExpectedETHGain, th.applyLiquidationFee(toBN('0').mul(th.toBN(dec(11, 17))).div(price))), 3000)

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

  it("liquidate(), with ICR% = 110 < TCR, and StabilityPool LUSD > debt to liquidate: offsets the trove entirely with the pool, there’s no collateral surplus", async () => {
    // --- SETUP ---
    // Alice withdraws up to 1500 LUSD of debt, and Dennis up to 150, resulting in ICRs of 266%.
    // Bob withdraws up to 250 LUSD of debt, resulting in ICR of 220%. Bob has lowest ICR.
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openTrove({ ICR: toBN(dec(220, 16)), extraLUSDAmount: dec(250, 18), extraParams: { from: bob } })
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    const { collateral: A_coll } = await openTrove({ ICR: toBN(dec(266, 16)), extraLUSDAmount: B_totalDebt, extraParams: { from: alice } })
    const { collateral: D_coll } = await openTrove({ ICR: toBN(dec(266, 16)), extraLUSDAmount: dec(2000, 18), extraParams: { from: dennis } })

    // Alice deposits LUSD in the Stability Pool
    const spDeposit = B_totalDebt.add(toBN(1))
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: alice })

    // --- TEST ---
    // price drops to 1ETH:100LUSD, reducing TCR below 150%
    await priceFeed.setPrice('100000000000000000000')
    const price = await priceFeed.getPrice()
    const TCR = await th.getTCR(contracts)

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // Check Bob's ICR = 110
    const bob_ICR = await troveManager.getCurrentICR(_bobTroveId, price)
    assert.isTrue(bob_ICR.eq(mv._MCR))

    // Liquidate Bob
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await troveManager.liquidateInBatchRecovery([_bobTroveId], {from: owner})

    /* Check accrued Stability Pool rewards after. Total Pool deposits was 1490 LUSD, Alice sole depositor.
    As liquidated debt (250 LUSD) was completely offset

    Alice's expected compounded deposit: (1490 - 250) = 1240LUSD
    Alice's expected ETH gain:  Bob's liquidated capped coll (minus gas comp), 2.75*0.995 ether

    */
    const aliceExpectedDeposit = await stabilityPool.getCompoundedLUSDDeposit(alice)
    const aliceExpectedETHGain = await stabilityPool.getDepositorETHGain(alice)

    assert.isAtMost(th.getDifference(aliceExpectedDeposit.toString(), spDeposit.sub(toBN('0'))), 2000)
    assert.isAtMost(th.getDifference(aliceExpectedETHGain, th.applyLiquidationFee(toBN('0').mul(th.toBN(dec(11, 17))).div(price))), 3000)

    // check Bob’s collateral surplus
    th.assertIsApproximatelyEqual(await collSurplusPool.getCollateral(bob), '0')
  })

  it("liquidate(), with  110% < ICR < TCR, and StabilityPool LUSD > debt to liquidate: removes stake and updates totalStakes", async () => {
    // --- SETUP ---
    // Alice withdraws up to 1500 LUSD of debt, and Dennis up to 150, resulting in ICRs of 266%.
    // Bob withdraws up to 250 LUSD of debt, resulting in ICR of 240%. Bob has lowest ICR.
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openTrove({ ICR: toBN(dec(240, 16)), extraLUSDAmount: dec(250, 18), extraParams: { from: bob } })
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    const { collateral: A_coll } = await openTrove({ ICR: toBN(dec(266, 16)), extraLUSDAmount: B_totalDebt, extraParams: { from: alice } })
    const { collateral: D_coll } = await openTrove({ ICR: toBN(dec(266, 16)), extraLUSDAmount: dec(2000, 18), extraParams: { from: dennis } })

    // Alice deposits LUSD in the Stability Pool
    await stabilityPool.provideToSP(B_totalDebt.add(toBN(1)), ZERO_ADDRESS, { from: alice })

    // --- TEST ---
    // price drops to 1ETH:100LUSD, reducing TCR below 150%
    await priceFeed.setPrice('100000000000000000000')
    const price = await priceFeed.getPrice()

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // check stake and totalStakes before
    const bob_Stake_Before = (await troveManager.Troves(_bobTroveId))[2]
    const totalStakes_Before = await troveManager.totalStakes()

    assert.equal(bob_Stake_Before.toString(), B_coll)
    assert.equal(totalStakes_Before.toString(), A_coll.add(B_coll).add(D_coll))

    // Check Bob's ICR is between 110 and 150
    const bob_ICR = await troveManager.getCurrentICR(_bobTroveId, price)
    assert.isTrue(bob_ICR.gt(mv._MCR) && bob_ICR.lt(await th.getTCR(contracts)))

    // Liquidate Bob
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await troveManager.liquidateInBatchRecovery([_bobTroveId], {from: owner})

    // check stake and totalStakes after
    const bob_Stake_After = (await troveManager.Troves(_bobTroveId))[2]
    const totalStakes_After = await troveManager.totalStakes()

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

  it("liquidate(), with  110% < ICR < TCR, and StabilityPool LUSD > debt to liquidate: updates system snapshots", async () => {
    // --- SETUP ---
    // Alice withdraws up to 1500 LUSD of debt, and Dennis up to 150, resulting in ICRs of 266%.
    // Bob withdraws up to 250 LUSD of debt, resulting in ICR of 240%. Bob has lowest ICR.
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openTrove({ ICR: toBN(dec(240, 16)), extraLUSDAmount: dec(250, 18), extraParams: { from: bob } })
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    const { collateral: A_coll } = await openTrove({ ICR: toBN(dec(266, 16)), extraLUSDAmount: B_totalDebt, extraParams: { from: alice } })
    const { collateral: D_coll } = await openTrove({ ICR: toBN(dec(266, 16)), extraLUSDAmount: dec(2000, 18), extraParams: { from: dennis } })

    // Alice deposits LUSD in the Stability Pool
    await stabilityPool.provideToSP(B_totalDebt.add(toBN(1)), ZERO_ADDRESS, { from: alice })

    // --- TEST ---
    // price drops to 1ETH:100LUSD, reducing TCR below 150%
    await priceFeed.setPrice('100000000000000000000')
    const price = await priceFeed.getPrice()

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // check system snapshots before
    const totalStakesSnaphot_before = (await troveManager.totalStakesSnapshot()).toString()
    const totalCollateralSnapshot_before = (await troveManager.totalCollateralSnapshot()).toString()

    assert.equal(totalStakesSnaphot_before, '0')
    assert.equal(totalCollateralSnapshot_before, '0')

    // Check Bob's ICR is between 110 and TCR
    const bob_ICR = await troveManager.getCurrentICR(_bobTroveId, price)
    assert.isTrue(bob_ICR.gt(mv._MCR) && bob_ICR.lt(await th.getTCR(contracts)))

    // Liquidate Bob
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await troveManager.liquidateInBatchRecovery([_bobTroveId], {from: owner})

    const totalStakesSnaphot_After = (await troveManager.totalStakesSnapshot())
    const totalCollateralSnapshot_After = (await troveManager.totalCollateralSnapshot())

    // totalStakesSnapshot should have reduced to 22 ether - the sum of Alice's coll( 20 ether) and Dennis' coll (2 ether )
    assert.equal(totalStakesSnaphot_After.toString(), A_coll.add(D_coll))
    // Total collateral should also reduce, since all liquidated coll has been moved to a reward for Stability Pool depositors
    assert.equal(totalCollateralSnapshot_After.toString(), A_coll.add(D_coll))
  })

  it("liquidate(), with 110% < ICR < TCR, and StabilityPool LUSD > debt to liquidate: closes the Trove", async () => {
    // --- SETUP ---
    // Alice withdraws up to 1500 LUSD of debt, and Dennis up to 150, resulting in ICRs of 266%.
    // Bob withdraws up to 250 LUSD of debt, resulting in ICR of 240%. Bob has lowest ICR.
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openTrove({ ICR: toBN(dec(240, 16)), extraLUSDAmount: dec(250, 18), extraParams: { from: bob } })
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    const { collateral: A_coll } = await openTrove({ ICR: toBN(dec(266, 16)), extraLUSDAmount: B_totalDebt, extraParams: { from: alice } })
    const { collateral: D_coll } = await openTrove({ ICR: toBN(dec(266, 16)), extraLUSDAmount: dec(2000, 18), extraParams: { from: dennis } })

    // Alice deposits LUSD in the Stability Pool
    await stabilityPool.provideToSP(B_totalDebt.add(toBN(1)), ZERO_ADDRESS, { from: alice })

    // --- TEST ---
    // price drops to 1ETH:100LUSD, reducing TCR below 150%
    await priceFeed.setPrice('100000000000000000000')
    const price = await priceFeed.getPrice()

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // Check Bob's Trove is active
    const bob_TroveStatus_Before = (await troveManager.Troves(_bobTroveId))[3]
    const bob_Trove_isInSortedList_Before = await sortedTroves.contains(_bobTroveId)

    assert.equal(bob_TroveStatus_Before, 1) // status enum element 1 corresponds to "Active"
    assert.isTrue(bob_Trove_isInSortedList_Before)

    // Check Bob's ICR is between 110 and TCR
    const bob_ICR = await troveManager.getCurrentICR(_bobTroveId, price)
    assert.isTrue(bob_ICR.gt(mv._MCR) && bob_ICR.lt(await th.getTCR(contracts)))

    // Liquidate Bob
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await troveManager.liquidateInBatchRecovery([_bobTroveId], {from: owner})

    // Check Bob's Trove is closed after liquidation
    const bob_TroveStatus_After = (await troveManager.Troves(_bobTroveId))[3]
    const bob_Trove_isInSortedList_After = await sortedTroves.contains(_bobTroveId)

    assert.equal(bob_TroveStatus_After, 3) // status enum element 3 corresponds to "Closed by liquidation"
    assert.isFalse(bob_Trove_isInSortedList_After)

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

  it("liquidate(), with 110% < ICR < TCR, and StabilityPool LUSD > debt to liquidate: can liquidate troves out of order", async () => {
    // taking out 1000 LUSD, CR of 200%
    const { collateral: A_coll, totalDebt: A_totalDebt } = await openTrove({ ICR: toBN(dec(200, 16)), extraParams: { from: alice } })
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openTrove({ ICR: toBN(dec(202, 16)), extraParams: { from: bob } })
    const { collateral: C_coll, totalDebt: C_totalDebt } = await openTrove({ ICR: toBN(dec(204, 16)), extraParams: { from: carol } })
    const { collateral: D_coll, totalDebt: D_totalDebt } = await openTrove({ ICR: toBN(dec(206, 16)), extraParams: { from: dennis } })
    let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);
    let _dennisTroveId = await sortedTroves.troveOfOwnerByIndex(dennis, 0);
    const { collateral: E_coll } = await openTrove({ ICR: toBN(dec(240, 16)), extraParams: { from: erin } })
    const { collateral: F_coll } = await openTrove({ ICR: toBN(dec(240, 16)), extraParams: { from: freddy } })

    const totalLiquidatedDebt = A_totalDebt.add(B_totalDebt).add(C_totalDebt).add(D_totalDebt)

    await openTrove({ ICR: toBN(dec(200, 16)), extraLUSDAmount: totalLiquidatedDebt, extraParams: { from: whale } })
    await stabilityPool.provideToSP(totalLiquidatedDebt, ZERO_ADDRESS, { from: whale })

    // Price drops 
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()
    const TCR = await th.getTCR(contracts)
  
    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check troves A-D are in range 110% < ICR < TCR
    const ICR_A = await troveManager.getCurrentICR(_aliceTroveId, price)
    const ICR_B = await troveManager.getCurrentICR(_bobTroveId, price)
    const ICR_C = await troveManager.getCurrentICR(_carolTroveId, price)
    const ICR_D = await troveManager.getCurrentICR(_dennisTroveId, price)
    
    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C.gt(mv._MCR) && ICR_C.lt(TCR))
    assert.isTrue(ICR_D.gt(mv._MCR) && ICR_D.lt(TCR))

    // Troves are ordered by ICR, low to high: A, B, C, D.

    // Liquidate out of ICR order: D, B, C.  Confirm Recovery Mode is active prior to each.
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from : whale});
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});
    const liquidationTx_D = await troveManager.liquidateInBatchRecovery([_dennisTroveId], {from: owner})
  
    assert.isTrue(await th.checkRecoveryMode(contracts))
    const liquidationTx_B = await troveManager.liquidateInBatchRecovery([_bobTroveId], {from: owner})

    assert.isTrue(await th.checkRecoveryMode(contracts))
    const liquidationTx_C = await troveManager.liquidateInBatchRecovery([_carolTroveId], {from: owner})
    
    // Check transactions all succeeded
    assert.isTrue(liquidationTx_D.receipt.status)
    assert.isTrue(liquidationTx_B.receipt.status)
    assert.isTrue(liquidationTx_C.receipt.status)

    // Confirm troves D, B, C removed
    assert.isFalse(await sortedTroves.contains(_dennisTroveId))
    assert.isFalse(await sortedTroves.contains(_bobTroveId))
    assert.isFalse(await sortedTroves.contains(_carolTroveId))

    // Confirm troves have status 'closed by liquidation' (Status enum element idx 3)
    assert.equal((await troveManager.Troves(_dennisTroveId))[3], '3')
    assert.equal((await troveManager.Troves(_bobTroveId))[3], '3')
    assert.equal((await troveManager.Troves(_carolTroveId))[3], '3')

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


  /* --- liquidate() applied to trove with ICR > 110% that has the lowest ICR, and Stability Pool 
  LUSD is LESS THAN the liquidated debt: a non fullfilled liquidation --- */

  it("liquidate(), with ICR > 110%, and StabilityPool LUSD < liquidated debt: Trove remains active", async () => {
    // --- SETUP ---
    // Alice withdraws up to 1500 LUSD of debt, and Dennis up to 150, resulting in ICRs of 266%.
    // Bob withdraws up to 250 LUSD of debt, resulting in ICR of 240%. Bob has lowest ICR.
    const { collateral: A_coll } = await openTrove({ ICR: toBN(dec(266, 16)), extraLUSDAmount: dec(1500, 18), extraParams: { from: alice } })
    const { collateral: B_coll } = await openTrove({ ICR: toBN(dec(240, 16)), extraLUSDAmount: dec(250, 18), extraParams: { from: bob } })
    const { collateral: D_coll } = await openTrove({ ICR: toBN(dec(266, 16)), extraLUSDAmount: dec(2000, 18), extraParams: { from: dennis } })
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);

    // Alice deposits 1490 LUSD in the Stability Pool
    await stabilityPool.provideToSP('1490000000000000000000', ZERO_ADDRESS, { from: alice })

    // --- TEST ---
    // price drops to 1ETH:100LUSD, reducing TCR below 150%
    await priceFeed.setPrice('100000000000000000000')

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // Check Bob's Trove is active
    const bob_TroveStatus_Before = (await troveManager.Troves(_bobTroveId))[3]
    const bob_Trove_isInSortedList_Before = await sortedTroves.contains(_bobTroveId)

    assert.equal(bob_TroveStatus_Before, 1) // status enum element 1 corresponds to "Active"
    assert.isTrue(bob_Trove_isInSortedList_Before)

    // Try to liquidate Bob
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await troveManager.liquidateInBatchRecovery([_bobTroveId], { from: owner })

    /* Since the pool only contains 100 LUSD, and Bob's pre-liquidation debt was 250 LUSD,
    expect Bob's trove to remain untouched, and remain active after liquidation */

    const bob_TroveStatus_After = (await troveManager.Troves(_bobTroveId))[3]
    const bob_Trove_isInSortedList_After = await sortedTroves.contains(_bobTroveId)

    assert.equal(bob_TroveStatus_After, 3) // status enum element 1 corresponds to "Active"
    assert.isFalse(bob_Trove_isInSortedList_After)
  })

  it("liquidate(), with ICR > 110%, and StabilityPool LUSD < liquidated debt: Trove remains in TroveOwners array", async () => {
    // --- SETUP ---
    // Alice withdraws up to 1500 LUSD of debt, and Dennis up to 150, resulting in ICRs of 266%.
    // Bob withdraws up to 250 LUSD of debt, resulting in ICR of 240%. Bob has lowest ICR.
    const { collateral: A_coll } = await openTrove({ ICR: toBN(dec(266, 16)), extraLUSDAmount: dec(1500, 18), extraParams: { from: alice } })
    const { collateral: B_coll } = await openTrove({ ICR: toBN(dec(240, 16)), extraLUSDAmount: dec(250, 18), extraParams: { from: bob } })
    const { collateral: D_coll } = await openTrove({ ICR: toBN(dec(266, 16)), extraLUSDAmount: dec(2000, 18), extraParams: { from: dennis } })
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);

    // Alice deposits 100 LUSD in the Stability Pool
    await stabilityPool.provideToSP(dec(100, 18), ZERO_ADDRESS, { from: alice })

    // --- TEST ---
    // price drops to 1ETH:100LUSD, reducing TCR below 150%
    await priceFeed.setPrice('100000000000000000000')

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // Check Bob's Trove is active
    const bob_TroveStatus_Before = (await troveManager.Troves(_bobTroveId))[3]
    const bob_Trove_isInSortedList_Before = await sortedTroves.contains(_bobTroveId)

    assert.equal(bob_TroveStatus_Before, 1) // status enum element 1 corresponds to "Active"
    assert.isTrue(bob_Trove_isInSortedList_Before)

    // Try to liquidate Bob
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await troveManager.liquidateInBatchRecovery([_bobTroveId], { from: owner })

    /* Since the pool only contains 100 LUSD, and Bob's pre-liquidation debt was 250 LUSD, 
    expect Bob's trove to only be partially offset, and remain active after liquidation */

    // Check Bob is in Trove owners array
    const arrayLength = (await troveManager.getTroveIdsCount()).toNumber()
    let addressFound = false;
    let addressIdx = 0;

    for (let i = 0; i < arrayLength; i++) {
      const address = (await troveManager.TroveIds(i)).toString()
      if (address == _bobTroveId) {
        addressFound = true
        addressIdx = i
      }
    }

    assert.isFalse(addressFound);

    // Check TroveOwners idx on trove struct == idx of address found in TroveOwners array
    //const idxOnStruct = (await troveManager.Troves(_bobTroveId))[4].toString()
    //assert.equal(addressIdx.toString(), idxOnStruct)
  })

  it("liquidate(), with ICR > 110%, and StabilityPool LUSD < liquidated debt: nothing happens", async () => {
    // --- SETUP ---
    // Alice withdraws up to 1500 LUSD of debt, and Dennis up to 150, resulting in ICRs of 266%.
    // Bob withdraws up to 250 LUSD of debt, resulting in ICR of 240%. Bob has lowest ICR.
    const { collateral: A_coll } = await openTrove({ ICR: toBN(dec(266, 16)), extraLUSDAmount: dec(1500, 18), extraParams: { from: alice } })
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openTrove({ ICR: toBN(dec(240, 16)), extraLUSDAmount: dec(250, 18), extraParams: { from: bob } })
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    const { collateral: D_coll } = await openTrove({ ICR: toBN(dec(266, 16)), extraLUSDAmount: dec(2000, 18), extraParams: { from: dennis } })

    // Alice deposits 100 LUSD in the Stability Pool
    await stabilityPool.provideToSP(dec(100, 18), ZERO_ADDRESS, { from: alice })

    // --- TEST ---
    // price drops to 1ETH:100LUSD, reducing TCR below 150%
    await priceFeed.setPrice('100000000000000000000')

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // Try to liquidate Bob
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await troveManager.liquidateInBatchRecovery([_bobTroveId], { from: owner })

    /*  Since Bob's debt (250 LUSD) is larger than all LUSD in the Stability Pool, Liquidation won’t happen

    After liquidation, totalStakes snapshot should equal Alice's stake (20 ether) + Dennis stake (2 ether) = 22 ether.

    Since there has been no redistribution, the totalCollateral snapshot should equal the totalStakes snapshot: 22 ether.

    Bob's new coll and stake should remain the same, and the updated totalStakes should still equal 25 ether.
    */
    const bob_Trove = await troveManager.Troves(_bobTroveId)
    const bob_DebtAfter = bob_Trove[0].toString()
    const bob_CollAfter = bob_Trove[1].toString()
    const bob_StakeAfter = bob_Trove[2].toString()

    th.assertIsApproximatelyEqual(bob_DebtAfter, '0')
    assert.equal(bob_CollAfter.toString(), '0')
    assert.equal(bob_StakeAfter.toString(), '0')

    const totalStakes_After = (await troveManager.totalStakes()).toString()
    assert.equal(totalStakes_After.toString(), A_coll.add(toBN('0')).add(D_coll))
  })

  it("liquidate(), with ICR > 110%, and StabilityPool LUSD < liquidated debt: updates system shapshots", async () => {
    // --- SETUP ---
    // Alice withdraws up to 1500 LUSD of debt, and Dennis up to 150, resulting in ICRs of 266%.
    // Bob withdraws up to 250 LUSD of debt, resulting in ICR of 240%. Bob has lowest ICR.
    const { collateral: A_coll } = await openTrove({ ICR: toBN(dec(266, 16)), extraLUSDAmount: dec(1500, 18), extraParams: { from: alice } })
    const { collateral: B_coll } = await openTrove({ ICR: toBN(dec(240, 16)), extraLUSDAmount: dec(250, 18), extraParams: { from: bob } })
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    const { collateral: D_coll } = await openTrove({ ICR: toBN(dec(266, 16)), extraLUSDAmount: dec(2000, 18), extraParams: { from: dennis } })

    // Alice deposits 100 LUSD in the Stability Pool
    await stabilityPool.provideToSP(dec(100, 18), ZERO_ADDRESS, { from: alice })

    // --- TEST ---
    // price drops to 1ETH:100LUSD, reducing TCR below 150%
    await priceFeed.setPrice('100000000000000000000')

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // Check snapshots before
    const totalStakesSnaphot_Before = (await troveManager.totalStakesSnapshot()).toString()
    const totalCollateralSnapshot_Before = (await troveManager.totalCollateralSnapshot()).toString()

    assert.equal(totalStakesSnaphot_Before, 0)
    assert.equal(totalCollateralSnapshot_Before, 0)

    // Liquidate Bob, it still happen despite there are no funds in the SP
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await troveManager.liquidateInBatchRecovery([_bobTroveId], { from: owner })

    /* After liquidation, totalStakes snapshot should still equal the total stake: 25 ether

    Since there has been no redistribution, the totalCollateral snapshot should equal the totalStakes snapshot: 25 ether.*/

    const totalStakesSnaphot_After = (await troveManager.totalStakesSnapshot()).toString()
    const totalCollateralSnapshot_After = (await troveManager.totalCollateralSnapshot()).toString()

    assert.isTrue(toBN(totalStakesSnaphot_After).gt(toBN(totalStakesSnaphot_Before)))//update after liquidation
    assert.isTrue(toBN(totalCollateralSnapshot_After).gt(toBN(totalCollateralSnapshot_Before)))
  })

  it("liquidate(), with ICR > 110%, and StabilityPool LUSD < liquidated debt: causes correct Pool offset and ETH gain, and doesn't redistribute to active troves", async () => {
    // --- SETUP ---
    // Alice withdraws up to 1500 LUSD of debt, and Dennis up to 150, resulting in ICRs of 266%.
    // Bob withdraws up to 250 LUSD of debt, resulting in ICR of 240%. Bob has lowest ICR.
    const { collateral: A_coll } = await openTrove({ ICR: toBN(dec(266, 16)), extraLUSDAmount: dec(1500, 18), extraParams: { from: alice } })
    const { collateral: B_coll } = await openTrove({ ICR: toBN(dec(240, 16)), extraLUSDAmount: dec(250, 18), extraParams: { from: bob } })
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    const { collateral: D_coll } = await openTrove({ ICR: toBN(dec(266, 16)), extraLUSDAmount: dec(2000, 18), extraParams: { from: dennis } })

    // Alice deposits 100 LUSD in the Stability Pool
    await stabilityPool.provideToSP(dec(100, 18), ZERO_ADDRESS, { from: alice })

    // --- TEST ---
    // price drops to 1ETH:100LUSD, reducing TCR below 150%
    await priceFeed.setPrice('100000000000000000000')

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // Try to liquidate Bob. Shouldn’t happen
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await troveManager.liquidateInBatchRecovery([_bobTroveId], { from: owner })

    // check Stability Pool rewards. Nothing happened, so everything should remain the same

    const aliceExpectedDeposit = await stabilityPool.getCompoundedLUSDDeposit(alice)
    const aliceExpectedETHGain = await stabilityPool.getDepositorETHGain(alice)

    assert.equal(aliceExpectedDeposit.toString(), dec(100, 18))
    assert.equal(aliceExpectedETHGain.toString(), '0')

    /* For this Recovery Mode test case with ICR > 110%, there should be no redistribution of remainder to active Troves. 
    Redistribution rewards-per-unit-staked should be zero. */

    const L_LUSDDebt_After = (await troveManager.L_LUSDDebt()).toString()
    const L_ETH_After = (await troveManager.L_ETH()).toString()

    assert.equal(L_LUSDDebt_After, '0')
    assert.equal(L_ETH_After, '0')
  })

  it("liquidate(), with ICR > 110%, and StabilityPool LUSD < liquidated debt: ICR of non liquidated trove does not change", async () => {
    // --- SETUP ---
    // Alice withdraws up to 1500 LUSD of debt, and Dennis up to 150, resulting in ICRs of 266%.
    // Bob withdraws up to 250 LUSD of debt, resulting in ICR of 240%. Bob has lowest ICR.
    // Carol withdraws up to debt of 240 LUSD, -> ICR of 250%.
    const { collateral: A_coll } = await openTrove({ ICR: toBN(dec(266, 16)), extraLUSDAmount: dec(1500, 18), extraParams: { from: alice } })
    const { collateral: B_coll } = await openTrove({ ICR: toBN(dec(240, 16)), extraLUSDAmount: dec(250, 18), extraParams: { from: bob } })
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    const { collateral: D_coll } = await openTrove({ ICR: toBN(dec(266, 16)), extraLUSDAmount: dec(2000, 18), extraParams: { from: dennis } })
    const { collateral: C_coll } = await openTrove({ ICR: toBN(dec(250, 16)), extraLUSDAmount: dec(240, 18), extraParams: { from: carol } })
    let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);

    // Alice deposits 100 LUSD in the Stability Pool
    await stabilityPool.provideToSP(dec(100, 18), ZERO_ADDRESS, { from: alice })

    // --- TEST ---
    // price drops to 1ETH:100LUSD, reducing TCR below 150%
    await priceFeed.setPrice(dec(100, 18))
    const price = await priceFeed.getPrice()

    const bob_ICR_Before = (await troveManager.getCurrentICR(_bobTroveId, price)).toString()
    const carol_ICR_Before = (await troveManager.getCurrentICR(_carolTroveId, price)).toString()

    assert.isTrue(await th.checkRecoveryMode(contracts))

    const bob_Coll_Before = (await troveManager.Troves(_bobTroveId))[1]
    const bob_Debt_Before = (await troveManager.Troves(_bobTroveId))[0]

    // confirm Bob is last trove in list, and has >110% ICR
    assert.equal((await sortedTroves.getLast()).toString(), _bobTroveId)
    assert.isTrue((await troveManager.getCurrentICR(_bobTroveId, price)).gt(mv._MCR))

    // L1: Try to liquidate Bob. Nothing happens
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()).sub(toBN(dec(50, 18))), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});
    await troveManager.liquidateInBatchRecovery([_bobTroveId], { from: owner })

    //Check SP LUSD has been completely emptied
    assert.equal((await stabilityPool.getTotalLUSDDeposits()).toString(), dec(100, 18))

    // Check Bob remains active
    assert.isFalse(await sortedTroves.contains(_bobTroveId))

    // Check Bob's collateral and debt remains the same
    const bob_Coll_After = (await troveManager.Troves(_bobTroveId))[1]
    const bob_Debt_After = (await troveManager.Troves(_bobTroveId))[0]
    assert.isTrue(bob_Coll_After.lt(bob_Coll_Before))
    assert.isTrue(bob_Debt_After.lt(bob_Debt_Before))

//    const bob_ICR_After = (await troveManager.getCurrentICR(_bobTroveId, price)).toString()

    // check Bob's ICR has not changed
//    assert.equal(bob_ICR_After, bob_ICR_Before)


    // to compensate borrowing fees
//    await lusdToken.transfer(bob, dec(100, 18), { from: alice })

    // Remove Bob from system to test Carol's trove: price rises, Bob closes trove, price drops to 100 again
    await priceFeed.setPrice(dec(200, 18))
//    await borrowerOperations.closeTrove(_bobTroveId, { from: bob })
    await priceFeed.setPrice(dec(100, 18))
    assert.isFalse(await sortedTroves.contains(_bobTroveId))

    // Alice provides another 50 LUSD to pool
    await stabilityPool.provideToSP(dec(50, 18), ZERO_ADDRESS, { from: alice })

    assert.isTrue(await th.checkRecoveryMode(contracts))

    const carol_Coll_Before = (await troveManager.Troves(_carolTroveId))[1]
    const carol_Debt_Before = (await troveManager.Troves(_carolTroveId))[0]

    // Confirm Carol is last trove in list, and has >110% ICR
    assert.equal((await sortedTroves.getLast()), _carolTroveId)
    assert.isTrue((await troveManager.getCurrentICR(_carolTroveId, price)).gt(mv._MCR))

    // L2: Try to liquidate Carol. Nothing happens
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});
    await troveManager.liquidateInBatchRecovery([_carolTroveId], { from: owner })

    //Check SP LUSD has been completely emptied
    assert.equal((await stabilityPool.getTotalLUSDDeposits()).toString(), dec(150, 18))

    // Check Carol's collateral and debt remains the same
//    const carol_Coll_After = (await troveManager.Troves(_carolTroveId))[1]
//    const carol_Debt_After = (await troveManager.Troves(_carolTroveId))[0]
//    assert.isTrue(carol_Coll_After.eq(carol_Coll_Before))
//    assert.isTrue(carol_Debt_After.eq(carol_Debt_Before))

//    const carol_ICR_After = (await troveManager.getCurrentICR(_carolTroveId, price)).toString()

    // check Carol's ICR has not changed
//    assert.equal(carol_ICR_After, carol_ICR_Before)

    //Confirm liquidations have not led to any redistributions to troves
    const L_LUSDDebt_After = (await troveManager.L_LUSDDebt()).toString()
    const L_ETH_After = (await troveManager.L_ETH()).toString()

    assert.equal(L_LUSDDebt_After, '0')
    assert.equal(L_ETH_After, '0')
  })

  it("liquidate() with ICR > 110%, and StabilityPool LUSD < liquidated debt: total liquidated coll and debt is correct", async () => {
    // Whale provides 50 LUSD to the SP
    await openTrove({ ICR: toBN(dec(300, 16)), extraLUSDAmount: dec(50, 18), extraParams: { from: whale } })
    await stabilityPool.provideToSP(dec(50, 18), ZERO_ADDRESS, { from: whale })

    const { collateral: A_coll } = await openTrove({ ICR: toBN(dec(200, 16)), extraParams: { from: alice } })
    let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
    const { collateral: B_coll } = await openTrove({ ICR: toBN(dec(202, 16)), extraParams: { from: bob } })
    const { collateral: C_coll } = await openTrove({ ICR: toBN(dec(204, 16)), extraParams: { from: carol } })
    const { collateral: D_coll } = await openTrove({ ICR: toBN(dec(206, 16)), extraParams: { from: dennis } })
    const { collateral: E_coll } = await openTrove({ ICR: toBN(dec(208, 16)), extraParams: { from: erin } })

    // Price drops 
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check C is in range 110% < ICR < 150%
    const ICR_A = await troveManager.getCurrentICR(_aliceTroveId, price)
    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(await th.getTCR(contracts)))

    const entireSystemCollBefore = await troveManager.getEntireSystemColl()
    const entireSystemDebtBefore = await troveManager.getEntireSystemDebt()

    // Try to liquidate Alice
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from : whale});
    await troveManager.liquidateInBatchRecovery([_aliceTroveId], { from: owner })

    // Expect system debt and system coll not reduced
    const entireSystemCollAfter = await troveManager.getEntireSystemColl()
    const entireSystemDebtAfter = await troveManager.getEntireSystemDebt()

    const changeInEntireSystemColl = entireSystemCollBefore.sub(entireSystemCollAfter)
    const changeInEntireSystemDebt = entireSystemDebtBefore.sub(entireSystemDebtAfter)

    assert.isTrue(changeInEntireSystemColl.gt(toBN('0')))
    assert.isTrue(changeInEntireSystemDebt.gt(toBN('0')))
  })

  // --- 

  it("liquidate(): Doesn't liquidate undercollateralized trove if it is the only trove in the system", async () => {
    // Alice creates a single trove with 0.62 ETH and a debt of 62 LUSD, and provides 10 LUSD to SP
    await openTrove({ ICR: toBN(dec(200, 16)), extraParams: { from: alice } })
    let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
    await stabilityPool.provideToSP(dec(10, 18), ZERO_ADDRESS, { from: alice })

    assert.isFalse(await th.checkRecoveryMode(contracts))

    // Set ETH:USD price to 105
    await priceFeed.setPrice('105000000000000000000')
    const price = await priceFeed.getPrice()

    assert.isTrue(await th.checkRecoveryMode(contracts))

    const alice_ICR = (await troveManager.getCurrentICR(_aliceTroveId, price)).toString()
    assert.equal(alice_ICR, '1050000000000000000')

    const activeTrovesCount_Before = await troveManager.getTroveIdsCount()

    assert.equal(activeTrovesCount_Before, 1)

    // Try to liquidate the trove
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await assertRevert(troveManager.liquidateInBatchRecovery([_aliceTroveId], { from: owner }), 'TroveManager: Only one trove in the system')

    // Check Alice's trove has not been removed
    const activeTrovesCount_After = await troveManager.getTroveIdsCount()
    assert.equal(activeTrovesCount_After, 1)

    const alice_isInSortedList = await sortedTroves.contains(_aliceTroveId)
    assert.isTrue(alice_isInSortedList)
  })

  it("liquidate(): Liquidates undercollateralized trove if there are two troves in the system", async () => {
    await openTrove({ ICR: toBN(dec(200, 16)), extraParams: { from: bob } })
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);

    // Alice creates a single trove with 0.62 ETH and a debt of 62 LUSD, and provides 10 LUSD to SP
    await openTrove({ ICR: toBN(dec(200, 16)), extraParams: { from: alice } })
    let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);

    // Alice proves 10 LUSD to SP
    await stabilityPool.provideToSP(dec(10, 18), ZERO_ADDRESS, { from: alice })

    assert.isFalse(await th.checkRecoveryMode(contracts))

    // Set ETH:USD price to 105
    await priceFeed.setPrice('105000000000000000000')
    const price = await priceFeed.getPrice()

    assert.isTrue(await th.checkRecoveryMode(contracts))

    const alice_ICR = (await troveManager.getCurrentICR(_aliceTroveId, price)).toString()
    assert.equal(alice_ICR, '1050000000000000000')

    const activeTrovesCount_Before = await troveManager.getTroveIdsCount()

    assert.equal(activeTrovesCount_Before, 2)

    // Liquidate the trove
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});
    await troveManager.liquidateInBatchRecovery([_aliceTroveId], { from: owner })

    // Check Alice's trove is removed, and bob remains
    const activeTrovesCount_After = await troveManager.getTroveIdsCount()
    assert.equal(activeTrovesCount_After, 1)

    const alice_isInSortedList = await sortedTroves.contains(_aliceTroveId)
    assert.isFalse(alice_isInSortedList)

    const bob_isInSortedList = await sortedTroves.contains(_bobTroveId)
    assert.isTrue(bob_isInSortedList)
  })

  it("liquidate(): does nothing if trove has >= 110% ICR and the Stability Pool is empty", async () => {
    await openTrove({ ICR: toBN(dec(400, 16)), extraParams: { from: alice } })
    let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
    await openTrove({ ICR: toBN(dec(220, 16)), extraParams: { from: bob } })
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    await openTrove({ ICR: toBN(dec(266, 16)), extraParams: { from: carol } })
    let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);

    await priceFeed.setPrice(dec(100, 18))
    const price = await priceFeed.getPrice()

    const TCR_Before = (await th.getTCR(contracts)).toString()
    const listSize_Before = (await sortedTroves.getSize()).toString()

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check Bob's ICR > 110%
    const bob_ICR = await troveManager.getCurrentICR(_bobTroveId, price)
    assert.isTrue(bob_ICR.gte(mv._MCR))

    // Confirm SP is empty
    const LUSDinSP = (await stabilityPool.getTotalLUSDDeposits()).toString()
    assert.equal(LUSDinSP, '0')

    // Attempt to liquidate bob
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});
    await troveManager.liquidateInBatchRecovery([_bobTroveId], {from: owner})

    // check A, B, C remain active
    assert.isFalse((await sortedTroves.contains(_bobTroveId)))
    assert.isTrue((await sortedTroves.contains(_aliceTroveId)))
    assert.isTrue((await sortedTroves.contains(_carolTroveId)))

    const TCR_After = (await th.getTCR(contracts)).toString()
    const listSize_After = (await sortedTroves.getSize()).toString()

    // Check TCR and list size have not changed
    assert.isTrue(toBN(TCR_Before).lt(toBN(TCR_After)))
    assert.isTrue(toBN(listSize_Before).gt(toBN(listSize_After)))
  })

  it("liquidate(): does nothing if trove ICR >= TCR, and SP covers trove's debt", async () => { 
    await openTrove({ ICR: toBN(dec(166, 16)), extraParams: { from: A } })
    await openTrove({ ICR: toBN(dec(154, 16)), extraParams: { from: B } })
    await openTrove({ ICR: toBN(dec(142, 16)), extraParams: { from: C } })
    let _aTroveId = await sortedTroves.troveOfOwnerByIndex(A, 0);
    let _bTroveId = await sortedTroves.troveOfOwnerByIndex(B, 0);
    let _cTroveId = await sortedTroves.troveOfOwnerByIndex(C, 0);

    // C fills SP with 130 LUSD
    await stabilityPool.provideToSP(dec(130, 18), ZERO_ADDRESS, {from: C})

    await priceFeed.setPrice(dec(150, 18))
    const price = await priceFeed.getPrice()
    assert.isTrue(await th.checkRecoveryMode(contracts))

    const TCR = await th.getTCR(contracts)

    const ICR_A = await troveManager.getCurrentICR(_aTroveId, price)
    const ICR_B = await troveManager.getCurrentICR(_bTroveId, price)
    const ICR_C = await troveManager.getCurrentICR(_cTroveId, price)

    assert.isTrue(ICR_A.gt(TCR))
    // Try to liquidate A
    //await assertRevert(troveManager.liquidate(_aTroveId), "TroveManager: nothing to liquidate")

    // Check liquidation of A does nothing - trove remains in system
    assert.isTrue(await sortedTroves.contains(_aTroveId))
    assert.equal(await troveManager.getTroveStatus(_aTroveId), 1) // Status 1 -> active

    // Check C, with ICR < TCR, can be liquidated
    assert.isTrue(ICR_C.lt(TCR))
    await debtToken.transfer(owner, (await debtToken.balanceOf(A)), {from : A});
    await debtToken.transfer(owner, (await debtToken.balanceOf(B)), {from : B});
    await debtToken.transfer(owner, (await debtToken.balanceOf(C)), {from : C});
    const liqTxC = await troveManager.liquidateInBatchRecovery([_cTroveId], {from: owner})
    assert.isTrue(liqTxC.receipt.status)

    assert.isFalse(await sortedTroves.contains(_cTroveId))
    assert.equal(await troveManager.getTroveStatus(_cTroveId), 3) // Status liquidated
  })

  it("liquidate(): reverts if trove is non-existent", async () => {
    await openTrove({ ICR: toBN(dec(200, 16)), extraParams: { from: alice } })
    await openTrove({ ICR: toBN(dec(133, 16)), extraParams: { from: bob } })

    await priceFeed.setPrice(dec(100, 18))

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check Carol does not have an existing trove
    assert.equal(await troveManager.getTroveStatus(carol), 0)
    assert.isFalse(await sortedTroves.contains(carol))

    try {
      await troveManager.liquidateInBatchRecovery([carol])

      assert.isTrue(txCarol.receipt.status)
    } catch (err) {
      //assert.include(err.message, "revert")
    }
  })

  it("liquidate(): reverts if trove has been closed", async () => {
    await openTrove({ ICR: toBN(dec(200, 16)), extraParams: { from: alice } })
    await openTrove({ ICR: toBN(dec(133, 16)), extraParams: { from: bob } })
    await openTrove({ ICR: toBN(dec(133, 16)), extraParams: { from: carol } })
    let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);

    assert.isTrue(await sortedTroves.contains(_carolTroveId))

    // Price drops, Carol ICR falls below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Carol liquidated, and her trove is closed
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});
    const txCarol_L1 = await troveManager.liquidateInBatchRecovery([_carolTroveId], {from: owner})
    assert.isTrue(txCarol_L1.receipt.status)

    // Check Carol's trove is closed by liquidation
    assert.isFalse(await sortedTroves.contains(_carolTroveId))
    assert.equal(await troveManager.getTroveStatus(_carolTroveId), 3)

    try {
      await troveManager.liquidateInBatchRecovery([_carolTroveId])
    } catch (err) {
      //assert.include(err.message, "revert")
    }
  })

  it("liquidate(): liquidates based on entire/collateral debt (including pending rewards), not raw collateral/debt", async () => {
    await openTrove({ ICR: toBN(dec(400, 16)), extraParams: { from: alice } })
    await openTrove({ ICR: toBN(dec(220, 16)), extraParams: { from: bob } })
    await openTrove({ ICR: toBN(dec(200, 16)), extraParams: { from: carol } })
    let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);

    // Defaulter opens with 60 LUSD, 0.6 ETH
    await openTrove({ ICR: toBN(dec(200, 16)), extraParams: { from: defaulter_1 } })
    let _defaulter1TroveId = await sortedTroves.troveOfOwnerByIndex(defaulter_1, 0);

    // Price drops
    await priceFeed.setPrice(dec(100, 18))
    const price = await priceFeed.getPrice()

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    const alice_ICR_Before = await troveManager.getCurrentICR(_aliceTroveId, price)
    const bob_ICR_Before = await troveManager.getCurrentICR(_bobTroveId, price)
    const carol_ICR_Before = await troveManager.getCurrentICR(_carolTroveId, price)

    /* Before liquidation: 
    Alice ICR: = (1 * 100 / 50) = 200%
    Bob ICR: (1 * 100 / 90.5) = 110.5%
    Carol ICR: (1 * 100 / 100 ) =  100%

    Therefore Alice and Bob above the MCR, Carol is below */
    assert.isTrue(alice_ICR_Before.gte(mv._MCR))
    assert.isTrue(bob_ICR_Before.gte(mv._MCR))
    assert.isTrue(carol_ICR_Before.lte(mv._MCR))

    // Liquidate defaulter. 30 LUSD and 0.3 ETH is distributed uniformly between A, B and C. Each receive 10 LUSD, 0.1 ETH
    await debtToken.transfer(owner, (await debtToken.balanceOf(defaulter_1)), {from : defaulter_1});
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});
    await troveManager.liquidateInBatchRecovery([_defaulter1TroveId], {from: owner})

    const alice_ICR_After = await troveManager.getCurrentICR(_aliceTroveId, price)
    const bob_ICR_After = await troveManager.getCurrentICR(_bobTroveId, price)
    const carol_ICR_After = await troveManager.getCurrentICR(_carolTroveId, price)

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
    const bob_Coll = (await troveManager.Troves(_bobTroveId))[1]
    const bob_Debt = (await troveManager.Troves(_bobTroveId))[0]

    const bob_rawICR = bob_Coll.mul(th.toBN(dec(100, 18))).div(bob_Debt)
    assert.isTrue(bob_rawICR.gte(mv._MCR))

    //liquidate A, B, C
    assert.isTrue(await th.checkRecoveryMode(contracts))
    await troveManager.liquidateInBatchRecovery([_aliceTroveId], {from: owner})
    assert.isTrue(await th.checkRecoveryMode(contracts))
    await troveManager.liquidateInBatchRecovery([_bobTroveId], {from: owner})
    assert.isFalse(await th.checkRecoveryMode(contracts))
    await troveManager.liquidateInBatch([_carolTroveId], {from: owner})

    /*  Since there is 0 LUSD in the stability Pool, A, with ICR >110%, should stay active.
    Check Alice stays active, Carol gets liquidated, and Bob gets liquidated 
    (because his pending rewards bring his ICR < MCR) */
    assert.isTrue(await sortedTroves.contains(_aliceTroveId))
    assert.isFalse(await sortedTroves.contains(_bobTroveId))
    assert.isFalse(await sortedTroves.contains(_carolTroveId))

    // check trove statuses - A active (1), B and C liquidated (3)
    assert.equal((await troveManager.Troves(_aliceTroveId))[3].toString(), '1')
    assert.equal((await troveManager.Troves(_bobTroveId))[3].toString(), '3')
    assert.equal((await troveManager.Troves(_carolTroveId))[3].toString(), '3')
  })

  it("liquidate(): does not affect the SP deposit or ETH gain when called on an SP depositor's address that has no trove", async () => {
    const { collateral: C_coll, totalDebt: C_totalDebt } = await openTrove({ ICR: toBN(dec(200, 16)), extraParams: { from: carol } })
    const spDeposit = C_totalDebt.add(toBN(dec(1000, 18)))
    await openTrove({ ICR: toBN(dec(220, 16)), extraLUSDAmount: spDeposit, extraParams: { from: bob } })
    let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);

    // Bob sends tokens to Dennis, who has no trove
    await lusdToken.transfer(dennis, spDeposit, { from: bob })

    //Dennis provides 200 LUSD to SP
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: dennis })

    // Price drop
    await priceFeed.setPrice(dec(105, 18))

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Carol gets liquidated
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});
    await troveManager.liquidateInBatchRecovery([_carolTroveId], {from: owner})

    // Check Dennis' SP deposit has absorbed Carol's debt, and he has received her liquidated ETH
    const dennis_Deposit_Before = (await stabilityPool.getCompoundedLUSDDeposit(dennis)).toString()
    const dennis_ETHGain_Before = (await stabilityPool.getDepositorETHGain(dennis)).toString()
    assert.isAtMost(th.getDifference(dennis_Deposit_Before, spDeposit.sub(toBN('0'))), 1000)
    assert.isAtMost(th.getDifference(dennis_ETHGain_Before, th.applyLiquidationFee(toBN('0'))), 1000)

    // Attempt to liquidate Dennis
    try {
      await troveManager.liquidateInBatchRecovery([dennis])
    } catch (err) {
      //assert.include(err.message, "revert")
    }

    // Check Dennis' SP deposit does not change after liquidation attempt
    const dennis_Deposit_After = (await stabilityPool.getCompoundedLUSDDeposit(dennis)).toString()
    const dennis_ETHGain_After = (await stabilityPool.getDepositorETHGain(dennis)).toString()
    assert.equal(dennis_Deposit_Before, dennis_Deposit_After)
    assert.equal(dennis_ETHGain_Before, dennis_ETHGain_After)
  })

  it("liquidate(): does not alter the liquidated user's token balance", async () => {
    await openTrove({ ICR: toBN(dec(220, 16)), extraLUSDAmount: dec(1000, 18), extraParams: { from: whale } })

    const { lusdAmount: A_lusdAmount } = await openTrove({ ICR: toBN(dec(200, 16)), extraLUSDAmount: dec(300, 18), extraParams: { from: alice } })
    const { lusdAmount: B_lusdAmount } = await openTrove({ ICR: toBN(dec(200, 16)), extraLUSDAmount: dec(200, 18), extraParams: { from: bob } })
    const { lusdAmount: C_lusdAmount } = await openTrove({ ICR: toBN(dec(206, 16)), extraLUSDAmount: dec(100, 18), extraParams: { from: carol } })
    let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);

    await priceFeed.setPrice(dec(105, 18))

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check token balances 
    assert.equal((await lusdToken.balanceOf(alice)).toString(), A_lusdAmount)
    assert.equal((await lusdToken.balanceOf(bob)).toString(), B_lusdAmount)
    assert.equal((await lusdToken.balanceOf(carol)).toString(), C_lusdAmount)

    // Check sortedList size is 4
    assert.equal((await sortedTroves.getSize()).toString(), '4')
    await openTrove({ ICR: toBN(dec(151, 16)), extraLUSDAmount: toBN(dec(10000,18)), extraParams: { from: owner } })

    // Liquidate A, B and C
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});
    await troveManager.liquidateInBatchRecovery([_aliceTroveId], {from: owner})
    await troveManager.liquidateInBatchRecovery([_bobTroveId], {from: owner})
    await troveManager.liquidateInBatchRecovery([_carolTroveId], {from: owner})

    // Confirm A, B, C closed
    assert.isFalse(await sortedTroves.contains(_aliceTroveId))
    assert.isFalse(await sortedTroves.contains(_bobTroveId))
    assert.isFalse(await sortedTroves.contains(_carolTroveId))

    // Check sortedList size reduced to 1
    assert.equal((await sortedTroves.getSize()).toString(), '2')

    // Confirm token balances have not changed
    assert.equal((await lusdToken.balanceOf(alice)).toString(), '0')
    assert.equal((await lusdToken.balanceOf(bob)).toString(), '0')
    assert.equal((await lusdToken.balanceOf(carol)).toString(), '0')
  })

  it("liquidate(), with 110% < ICR < TCR, can claim collateral, re-open, be reedemed and claim again", async () => {
    // --- SETUP ---
    // Alice withdraws up to 1500 LUSD of debt, resulting in ICRs of 266%.
    // Bob withdraws up to 480 LUSD of debt, resulting in ICR of 240%. Bob has lowest ICR.
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openTrove({ ICR: toBN(dec(240, 16)), extraLUSDAmount: dec(480, 18), extraParams: { from: bob } })
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    const { collateral: A_coll } = await openTrove({ ICR: toBN(dec(266, 16)), extraLUSDAmount: B_totalDebt, extraParams: { from: alice } })

    // Alice deposits LUSD in the Stability Pool
    await stabilityPool.provideToSP(B_totalDebt, ZERO_ADDRESS, { from: alice })

    // --- TEST ---
    // price drops to 1ETH:100LUSD, reducing TCR below 150%
    await priceFeed.setPrice('100000000000000000000')
    let price = await priceFeed.getPrice()
    const TCR = await th.getTCR(contracts)

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // Check Bob's ICR is between 110 and TCR
    const bob_ICR = await troveManager.getCurrentICR(_bobTroveId, price)
    assert.isTrue(bob_ICR.gt(mv._MCR) && bob_ICR.lt(TCR))

    // Liquidate Bob
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await troveManager.liquidateInBatchRecovery([_bobTroveId], { from: owner })

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

    // Bob re-opens the trove, price 200, total debt 80 LUSD, ICR = 120% (lowest one)
    // Dennis redeems 30, so Bob has a surplus of (200 * 0.48 - 30) / 200 = 0.33 ETH
    await priceFeed.setPrice('200000000000000000000')
    const { collateral: B_coll_2, netDebt: B_netDebt_2 } = await openTrove({ ICR: toBN(dec(150, 16)), extraLUSDAmount: dec(480, 18), extraParams: { from: bob, value: bob_remainingCollateral } })
    const { collateral: D_coll } = await openTrove({ ICR: toBN(dec(266, 16)), extraLUSDAmount: B_netDebt_2, extraParams: { from: dennis } })
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
    // Bob withdraws up to 90 LUSD of debt, resulting in ICR of 222%
    const { collateral: B_coll, netDebt: B_netDebt } = await openTrove({ ICR: toBN(dec(222, 16)), extraLUSDAmount: dec(90, 18), extraParams: { from: bob } })
    // Dennis withdraws to 150 LUSD of debt, resulting in ICRs of 266%.
    const { collateral: D_coll } = await openTrove({ ICR: toBN(dec(266, 16)), extraLUSDAmount: B_netDebt, extraParams: { from: dennis } })

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

    // Bob re-opens the trove, price 200, total debt 250 LUSD, ICR = 240% (lowest one)
    const { collateral: B_coll_2, totalDebt: B_totalDebt_2 } = await openTrove({ ICR: toBN(dec(240, 16)), extraParams: { from: bob, value: _3_Ether } })
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    // Alice deposits LUSD in the Stability Pool
    await openTrove({ ICR: toBN(dec(266, 16)), extraLUSDAmount: B_totalDebt_2, extraParams: { from: alice } })
    await stabilityPool.provideToSP(B_totalDebt_2, ZERO_ADDRESS, { from: alice })

    // price drops to 1ETH:100LUSD, reducing TCR below 150%
    await priceFeed.setPrice('100000000000000000000')
    price = await priceFeed.getPrice()
    const TCR = await th.getTCR(contracts)

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // Check Bob's ICR is between 110 and TCR
    const bob_ICR = await troveManager.getCurrentICR(_bobTroveId, price)
    assert.isTrue(bob_ICR.gt(mv._MCR) && bob_ICR.lt(TCR))
    // debt is increased by fee, due to previous redemption
    const bob_debt = await troveManager.getTroveDebt(_bobTroveId)

    // Liquidate Bob
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});
    await troveManager.liquidateInBatchRecovery([_bobTroveId], { from: owner })

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

  // --- liquidateTroves ---

  it("liquidateTroves(): With all ICRs > 110%, Liquidates Troves until system leaves recovery mode", async () => {
    // make 8 Troves accordingly
    // --- SETUP ---

    // Everyone withdraws some LUSD from their Trove, resulting in different ICRs
    await openTrove({ ICR: toBN(dec(350, 16)), extraParams: { from: bob } })
    await openTrove({ ICR: toBN(dec(286, 16)), extraParams: { from: carol } })
    await openTrove({ ICR: toBN(dec(273, 16)), extraParams: { from: dennis } })
    const { totalDebt: E_totalDebt } = await openTrove({ ICR: toBN(dec(261, 16)), extraParams: { from: erin } })
    const { totalDebt: F_totalDebt } = await openTrove({ ICR: toBN(dec(250, 16)), extraParams: { from: freddy } })
    const { totalDebt: G_totalDebt } = await openTrove({ ICR: toBN(dec(235, 16)), extraParams: { from: greta } })
    const { totalDebt: H_totalDebt } = await openTrove({ ICR: toBN(dec(222, 16)), extraLUSDAmount: dec(5000, 18), extraParams: { from: harry } })
    const liquidationAmount = E_totalDebt.add(F_totalDebt).add(G_totalDebt).add(H_totalDebt)
    await openTrove({ ICR: toBN(dec(400, 16)), extraLUSDAmount: liquidationAmount, extraParams: { from: alice } })
    let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);
    let _dennisTroveId = await sortedTroves.troveOfOwnerByIndex(dennis, 0);
    let _erinTroveId = await sortedTroves.troveOfOwnerByIndex(erin, 0);
    let _freddyTroveId = await sortedTroves.troveOfOwnerByIndex(freddy, 0);
    let _gretaTroveId = await sortedTroves.troveOfOwnerByIndex(greta, 0);
    let _harryTroveId = await sortedTroves.troveOfOwnerByIndex(harry, 0);

    // Alice deposits LUSD to Stability Pool
    await stabilityPool.provideToSP(liquidationAmount, ZERO_ADDRESS, { from: alice })

    // price drops
    // price drops to 1ETH:90LUSD, reducing TCR below 150%
    await priceFeed.setPrice('80000000000000000000')
    const price = await priceFeed.getPrice()

    const recoveryMode_Before = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode_Before)

    // check TCR < 150%
    const _150percent = web3.utils.toBN('1500000000000000000')
    const TCR_Before = await th.getTCR(contracts)
    assert.isTrue(TCR_Before.lt(_150percent))

    /* 
   After the price drop and prior to any liquidations, ICR should be:

    Trove         ICR
    Alice       161%
    Bob         158%
    Carol       129%
    Dennis      123%
    Elisa       117%
    Freddy      113%
    Greta       106%
    Harry       100%

    */
    const alice_ICR = await troveManager.getCurrentICR(_aliceTroveId, price)
    const bob_ICR = await troveManager.getCurrentICR(_bobTroveId, price)
    const carol_ICR = await troveManager.getCurrentICR(_carolTroveId, price)
    const dennis_ICR = await troveManager.getCurrentICR(_dennisTroveId, price)
    const erin_ICR = await troveManager.getCurrentICR(_erinTroveId, price)
    const freddy_ICR = await troveManager.getCurrentICR(_freddyTroveId, price)
    const greta_ICR = await troveManager.getCurrentICR(_gretaTroveId, price)
    const harry_ICR = await troveManager.getCurrentICR(_harryTroveId, price)
    const TCR = await th.getTCR(contracts)

    // Alice and Bob should have ICR > TCR
    assert.isTrue(alice_ICR.gt(TCR))
    assert.isTrue(bob_ICR.gt(TCR))
    // All other Troves should have ICR < TCR
    assert.isTrue(carol_ICR.lt(TCR))
    assert.isTrue(dennis_ICR.lt(TCR))
    assert.isTrue(erin_ICR.lt(TCR))
    assert.isTrue(freddy_ICR.lt(TCR))
    assert.isTrue(greta_ICR.lt(TCR))
    assert.isTrue(harry_ICR.lt(TCR))

    /* Liquidations should occur from the lowest ICR Trove upwards, i.e. 
    1) Harry, 2) Greta, 3) Freddy, etc.

      Trove         ICR
    Alice       161%
    Bob         158%
    Carol       129%
    Dennis      123%
    ---- CUTOFF ----
    Elisa       117%
    Freddy      113%
    Greta       106%
    Harry       100%

    If all Troves below the cutoff are liquidated, the TCR of the system rises above the CCR, to 152%.  (see calculations in Google Sheet)

    Thus, after liquidateTroves(), expect all Troves to be liquidated up to the cut-off.  
    
    Only Alice, Bob, Carol and Dennis should remain active - all others should be closed. */

    // call liquidate Troves
    await debtToken.transfer(owner, (await debtToken.balanceOf(erin)), {from : erin});
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(freddy)), {from : freddy});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});
    await debtToken.transfer(owner, (await debtToken.balanceOf(greta)), {from : greta});
    await debtToken.transfer(owner, (await debtToken.balanceOf(harry)), {from : harry});
    await troveManager.liquidateSequentiallyInRecovery(10, {from: owner});

    // check system is no longer in Recovery Mode
    const recoveryMode_After = await th.checkRecoveryMode(contracts)
    assert.isFalse(recoveryMode_After)

    // After liquidation, TCR should rise to above 150%. 
    const TCR_After = await th.getTCR(contracts)
    assert.isTrue(TCR_After.gt(_150percent))

    // get all Troves
    const alice_Trove = await troveManager.Troves(_aliceTroveId)
    const bob_Trove = await troveManager.Troves(_bobTroveId)
    const carol_Trove = await troveManager.Troves(_carolTroveId)
    const dennis_Trove = await troveManager.Troves(_dennisTroveId)
    const erin_Trove = await troveManager.Troves(_erinTroveId)
    const freddy_Trove = await troveManager.Troves(_freddyTroveId)
    const greta_Trove = await troveManager.Troves(_gretaTroveId)
    const harry_Trove = await troveManager.Troves(_harryTroveId)

    // check that Alice, Bob, Carol, & Dennis' Troves remain active
    assert.equal(alice_Trove[3], 1)
    assert.equal(bob_Trove[3], 1)
    assert.equal(carol_Trove[3], 1)
    assert.equal(dennis_Trove[3], 3)
    assert.isTrue(await sortedTroves.contains(_aliceTroveId))
    assert.isTrue(await sortedTroves.contains(_bobTroveId))
    assert.isTrue(await sortedTroves.contains(_carolTroveId))
    assert.isFalse(await sortedTroves.contains(_dennisTroveId))

    // check all other Troves are liquidated
    assert.equal(erin_Trove[3], 3)
    assert.equal(freddy_Trove[3], 3)
    assert.equal(greta_Trove[3], 3)
    assert.equal(harry_Trove[3], 3)
    assert.isFalse(await sortedTroves.contains(_erinTroveId))
    assert.isFalse(await sortedTroves.contains(_freddyTroveId))
    assert.isFalse(await sortedTroves.contains(_gretaTroveId))
    assert.isFalse(await sortedTroves.contains(_harryTroveId))
  })

  it("liquidateTroves(): Liquidates Troves until 1) system has left recovery mode AND 2) it reaches a Trove with ICR >= 110%", async () => {
    // make 6 Troves accordingly
    // --- SETUP ---
    const { totalDebt: B_totalDebt } = await openTrove({ ICR: toBN(dec(240, 16)), extraParams: { from: bob } })
    const { totalDebt: C_totalDebt } = await openTrove({ ICR: toBN(dec(240, 16)), extraParams: { from: carol } })
    const { totalDebt: D_totalDebt } = await openTrove({ ICR: toBN(dec(230, 16)), extraParams: { from: dennis } })
    const { totalDebt: E_totalDebt } = await openTrove({ ICR: toBN(dec(240, 16)), extraParams: { from: erin } })
    const { totalDebt: F_totalDebt } = await openTrove({ ICR: toBN(dec(240, 16)), extraParams: { from: freddy } })

    const liquidationAmount = B_totalDebt.add(C_totalDebt).add(D_totalDebt).add(E_totalDebt).add(F_totalDebt)
    await openTrove({ ICR: toBN(dec(400, 16)), extraLUSDAmount: liquidationAmount, extraParams: { from: alice } })
    let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);
    let _dennisTroveId = await sortedTroves.troveOfOwnerByIndex(dennis, 0);
    let _erinTroveId = await sortedTroves.troveOfOwnerByIndex(erin, 0);
    let _freddyTroveId = await sortedTroves.troveOfOwnerByIndex(freddy, 0);

    // Alice deposits LUSD to Stability Pool
    await stabilityPool.provideToSP(liquidationAmount, ZERO_ADDRESS, { from: alice })

    // price drops to 1ETH:85LUSD, reducing TCR below 150%
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

    Trove         ICR
    Alice       182%
    Bob         102%
    Carol       102%
    Dennis      102%
    Elisa       102%
    Freddy      102%
    */
    alice_ICR = await troveManager.getCurrentICR(_aliceTroveId, price)
    bob_ICR = await troveManager.getCurrentICR(_bobTroveId, price)
    carol_ICR = await troveManager.getCurrentICR(_carolTroveId, price)
    dennis_ICR = await troveManager.getCurrentICR(_dennisTroveId, price)
    erin_ICR = await troveManager.getCurrentICR(_erinTroveId, price)
    freddy_ICR = await troveManager.getCurrentICR(_freddyTroveId, price)

    // Alice should have ICR > 150%
    assert.isTrue(alice_ICR.gt(_150percent))
    // All other Troves should have ICR < 150%
    assert.isTrue(carol_ICR.lt(_150percent))
    assert.isTrue(dennis_ICR.lt(_150percent))
    assert.isTrue(erin_ICR.lt(_150percent))
    assert.isTrue(freddy_ICR.lt(_150percent))

    /* Liquidations should occur from the lowest ICR Trove upwards, i.e. 
    1) Freddy, 2) Elisa, 3) Dennis.

    After liquidating Freddy and Elisa, the the TCR of the system rises above the CCR, to 154%.  
   (see calculations in Google Sheet)

    Liquidations continue until all Troves with ICR < MCR have been closed. 
    Only Alice should remain active - all others should be closed. */

    // call liquidate Troves

    await debtToken.transfer(owner, (await debtToken.balanceOf(erin)), {from : erin});
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(freddy)), {from : freddy});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});	
    await troveManager.liquidateSequentiallyInRecovery(6, {from: owner});

    // check system is no longer in Recovery Mode
    const recoveryMode_After = await th.checkRecoveryMode(contracts)
    assert.isFalse(recoveryMode_After)

    // After liquidation, TCR should rise to above 150%. 
    const TCR_After = await th.getTCR(contracts)
    assert.isTrue(TCR_After.gt(_150percent))

    // get all Troves
    const alice_Trove = await troveManager.Troves(_aliceTroveId)
    const bob_Trove = await troveManager.Troves(_bobTroveId)
    const carol_Trove = await troveManager.Troves(_carolTroveId)
    const dennis_Trove = await troveManager.Troves(_dennisTroveId)
    const erin_Trove = await troveManager.Troves(_erinTroveId)
    const freddy_Trove = await troveManager.Troves(_freddyTroveId)

    // check that Alice's Trove remains active
    assert.equal(alice_Trove[3], 1)
    assert.isTrue(await sortedTroves.contains(_aliceTroveId))

    // check all other Troves are liquidated
    assert.equal(bob_Trove[3], 3)
    assert.equal(carol_Trove[3], 3)
    assert.equal(dennis_Trove[3], 3)
    assert.equal(erin_Trove[3], 3)
    assert.equal(freddy_Trove[3], 3)

    assert.isFalse(await sortedTroves.contains(_bobTroveId))
    assert.isFalse(await sortedTroves.contains(_carolTroveId))
    assert.isFalse(await sortedTroves.contains(_dennisTroveId))
    assert.isFalse(await sortedTroves.contains(_erinTroveId))
    assert.isFalse(await sortedTroves.contains(_freddyTroveId))
  })

  it('liquidateTroves(): liquidates only up to the requested number of undercollateralized troves', async () => {
    await openTrove({ ICR: toBN(dec(300, 16)), extraParams: { from: whale, value: dec(300, 'ether') } })

    // --- SETUP --- 
    // Alice, Bob, Carol, Dennis, Erin open troves with consecutively increasing collateral ratio
    await openTrove({ ICR: toBN(dec(210, 16)), extraParams: { from: alice } })
    await openTrove({ ICR: toBN(dec(212, 16)), extraParams: { from: bob } })
    await openTrove({ ICR: toBN(dec(214, 16)), extraParams: { from: carol } })
    await openTrove({ ICR: toBN(dec(216, 16)), extraParams: { from: dennis } })
    await openTrove({ ICR: toBN(dec(218, 16)), extraParams: { from: erin } })
    let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);
    let _dennisTroveId = await sortedTroves.troveOfOwnerByIndex(dennis, 0);
    let _erinTroveId = await sortedTroves.troveOfOwnerByIndex(erin, 0);

    await priceFeed.setPrice(dec(100, 18))

    const TCR = await th.getTCR(contracts)

    assert.isTrue(TCR.lte(web3.utils.toBN(dec(150, 18))))	
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // --- TEST --- 

    // Price drops
    await priceFeed.setPrice(dec(80, 18))

    await debtToken.transfer(owner, (await debtToken.balanceOf(erin)), {from : erin});
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});
    await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from : whale});
    await troveManager.liquidateSequentiallyInRecovery(8, {from: owner})

    // Check system still in Recovery Mode after liquidation tx
    assert.isTrue(await th.checkRecoveryMode(contracts))

    const TroveOwnersArrayLength = await troveManager.getTroveIdsCount()
    assert.equal(TroveOwnersArrayLength, '1')

    // Check Alice, Bob, Carol troves have been closed
    const aliceTroveStatus = (await troveManager.getTroveStatus(_aliceTroveId)).toString()
    const bobTroveStatus = (await troveManager.getTroveStatus(_bobTroveId)).toString()
    const carolTroveStatus = (await troveManager.getTroveStatus(_carolTroveId)).toString()

    assert.equal(aliceTroveStatus, '3')
    assert.equal(bobTroveStatus, '3')
    assert.equal(carolTroveStatus, '3')

    //  Check Alice, Bob, and Carol's trove are no longer in the sorted list
    const alice_isInSortedList = await sortedTroves.contains(_aliceTroveId)
    const bob_isInSortedList = await sortedTroves.contains(_bobTroveId)
    const carol_isInSortedList = await sortedTroves.contains(_carolTroveId)

    assert.isFalse(alice_isInSortedList)
    assert.isFalse(bob_isInSortedList)
    assert.isFalse(carol_isInSortedList)

    // Check Dennis, Erin still have active troves
    const dennisTroveStatus = (await troveManager.getTroveStatus(_dennisTroveId)).toString()
    const erinTroveStatus = (await troveManager.getTroveStatus(_erinTroveId)).toString()

    assert.equal(dennisTroveStatus, '3')
    assert.equal(erinTroveStatus, '3')

    // Check Dennis, Erin still in sorted list
    const dennis_isInSortedList = await sortedTroves.contains(_dennisTroveId)
    const erin_isInSortedList = await sortedTroves.contains(_erinTroveId)

    assert.isFalse(dennis_isInSortedList)
    assert.isFalse(erin_isInSortedList)
  })

  it("liquidateTroves(): does nothing if n = 0", async () => {
    await openTrove({ ICR: toBN(dec(200, 16)), extraLUSDAmount: dec(100, 18), extraParams: { from: alice } })
    await openTrove({ ICR: toBN(dec(200, 16)), extraLUSDAmount: dec(200, 18), extraParams: { from: bob } })
    await openTrove({ ICR: toBN(dec(200, 16)), extraLUSDAmount: dec(300, 18), extraParams: { from: carol } })
    let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);

    await priceFeed.setPrice(dec(100, 18))
    const price = await priceFeed.getPrice()

    const TCR_Before = (await th.getTCR(contracts)).toString()

    // Confirm A, B, C ICRs are below 110%

    const alice_ICR = await troveManager.getCurrentICR(_aliceTroveId, price)
    const bob_ICR = await troveManager.getCurrentICR(_bobTroveId, price)
    const carol_ICR = await troveManager.getCurrentICR(_carolTroveId, price)
    assert.isTrue(alice_ICR.lte(mv._MCR))
    assert.isTrue(bob_ICR.lte(mv._MCR))
    assert.isTrue(carol_ICR.lte(mv._MCR))

    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Liquidation with n = 0
    //await assertRevert(troveManager.liquidateTroves(0), "TroveManager: nothing to liquidate")

    // Check all troves are still in the system
    assert.isTrue(await sortedTroves.contains(_aliceTroveId))
    assert.isTrue(await sortedTroves.contains(_bobTroveId))
    assert.isTrue(await sortedTroves.contains(_carolTroveId))

    const TCR_After = (await th.getTCR(contracts)).toString()

    // Check TCR has not changed after liquidation
    assert.equal(TCR_Before, TCR_After)
  })

  it('liquidateTroves(): closes every Trove with ICR < MCR, when n > number of undercollateralized troves', async () => {
    // --- SETUP --- 
    await openTrove({ ICR: toBN(dec(300, 16)), extraParams: { from: whale, value: dec(300, 'ether') } })

    // create 5 Troves with varying ICRs
    await openTrove({ ICR: toBN(dec(200, 16)), extraParams: { from: alice } })
    await openTrove({ ICR: toBN(dec(133, 16)), extraParams: { from: bob } })
    await openTrove({ ICR: toBN(dec(200, 16)), extraLUSDAmount: dec(300, 18), extraParams: { from: carol } })
    await openTrove({ ICR: toBN(dec(182, 16)), extraParams: { from: erin } })
    await openTrove({ ICR: toBN(dec(111, 16)), extraParams: { from: freddy } })
    let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);
    let _freddyTroveId = await sortedTroves.troveOfOwnerByIndex(freddy, 0);
    let _erinTroveId = await sortedTroves.troveOfOwnerByIndex(erin, 0);

    // Whale puts some tokens in Stability Pool
    await stabilityPool.provideToSP(dec(300, 18), ZERO_ADDRESS, { from: whale })

    // --- TEST ---

    // Price drops to 1ETH:100LUSD, reducing Bob and Carol's ICR below MCR
    await priceFeed.setPrice(dec(100, 18));
    const price = await priceFeed.getPrice()

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Confirm troves A-E are ICR < 110%
    assert.isTrue((await troveManager.getCurrentICR(_aliceTroveId, price)).lte(mv._MCR))
    assert.isTrue((await troveManager.getCurrentICR(_bobTroveId, price)).lte(mv._MCR))
    assert.isTrue((await troveManager.getCurrentICR(_carolTroveId, price)).lte(mv._MCR))
    assert.isTrue((await troveManager.getCurrentICR(_erinTroveId, price)).lte(mv._MCR))
    assert.isTrue((await troveManager.getCurrentICR(_freddyTroveId, price)).lte(mv._MCR))

    // Confirm Whale is ICR > 110% 
    assert.isTrue((await troveManager.getCurrentICR(whale, price)).gte(mv._MCR))

    // Liquidate 5 troves
    await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from : whale});
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(erin)), {from : erin});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(freddy)), {from : freddy});
    await troveManager.liquidateSequentiallyInRecovery(8, {from: owner});

    // Confirm troves A-E have been removed from the system
    assert.isFalse(await sortedTroves.contains(_aliceTroveId))
    assert.isFalse(await sortedTroves.contains(_bobTroveId))
    assert.isFalse(await sortedTroves.contains(_carolTroveId))
    assert.isFalse(await sortedTroves.contains(_erinTroveId))
    assert.isFalse(await sortedTroves.contains(_freddyTroveId))

    // Check all troves are now liquidated
    assert.equal((await troveManager.Troves(_aliceTroveId))[3].toString(), '3')
    assert.equal((await troveManager.Troves(_bobTroveId))[3].toString(), '3')
    assert.equal((await troveManager.Troves(_carolTroveId))[3].toString(), '3')
    assert.equal((await troveManager.Troves(_erinTroveId))[3].toString(), '3')
    assert.equal((await troveManager.Troves(_freddyTroveId))[3].toString(), '3')
  })

  it("liquidateTroves(): a liquidation sequence containing Pool offsets increases the TCR", async () => {
    // Whale provides 500 LUSD to SP
    await openTrove({ ICR: toBN(dec(200, 16)), extraLUSDAmount: dec(500, 18), extraParams: { from: whale } })
    await stabilityPool.provideToSP(dec(500, 18), ZERO_ADDRESS, { from: whale })

    await openTrove({ ICR: toBN(dec(300, 16)), extraParams: { from: alice } })
    await openTrove({ ICR: toBN(dec(320, 16)), extraParams: { from: carol } })
    await openTrove({ ICR: toBN(dec(340, 16)), extraParams: { from: dennis } })

    await openTrove({ ICR: toBN(dec(198, 16)), extraLUSDAmount: dec(101, 18), extraParams: { from: defaulter_1 } })
    await openTrove({ ICR: toBN(dec(184, 16)), extraLUSDAmount: dec(217, 18), extraParams: { from: defaulter_2 } })
    await openTrove({ ICR: toBN(dec(183, 16)), extraLUSDAmount: dec(328, 18), extraParams: { from: defaulter_3 } })
    await openTrove({ ICR: toBN(dec(186, 16)), extraLUSDAmount: dec(431, 18), extraParams: { from: defaulter_4 } })
    let _defaulter1TroveId = await sortedTroves.troveOfOwnerByIndex(defaulter_1, 0);
    let _defaulter2TroveId = await sortedTroves.troveOfOwnerByIndex(defaulter_2, 0);
    let _defaulter3TroveId = await sortedTroves.troveOfOwnerByIndex(defaulter_3, 0);
    let _defaulter4TroveId = await sortedTroves.troveOfOwnerByIndex(defaulter_4, 0);

    assert.isTrue((await sortedTroves.contains(_defaulter1TroveId)))
    assert.isTrue((await sortedTroves.contains(_defaulter2TroveId)))
    assert.isTrue((await sortedTroves.contains(_defaulter3TroveId)))
    assert.isTrue((await sortedTroves.contains(_defaulter4TroveId)))


    // Price drops
    await priceFeed.setPrice(dec(110, 18))
    const price = await priceFeed.getPrice()

    assert.isTrue(await th.ICRbetween100and110(_defaulter1TroveId, troveManager, price))
    assert.isTrue(await th.ICRbetween100and110(_defaulter2TroveId, troveManager, price))
    assert.isTrue(await th.ICRbetween100and110(_defaulter3TroveId, troveManager, price))
    assert.isTrue(await th.ICRbetween100and110(_defaulter4TroveId, troveManager, price))

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    const TCR_Before = await th.getTCR(contracts)

    // Check Stability Pool has 500 LUSD
    assert.equal((await stabilityPool.getTotalLUSDDeposits()).toString(), dec(500, 18))

    await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from : whale});
    await debtToken.transfer(owner, (await debtToken.balanceOf(defaulter_1)), {from : defaulter_1});
    await debtToken.transfer(owner, (await debtToken.balanceOf(defaulter_2)), {from : defaulter_2});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(defaulter_3)), {from : defaulter_3});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(defaulter_4)), {from : defaulter_4});
    await troveManager.liquidateSequentiallyInRecovery(8, {from: owner})

    // assert.isFalse((await sortedTroves.contains(defaulter_1)))
    // assert.isFalse((await sortedTroves.contains(defaulter_2)))
    // assert.isFalse((await sortedTroves.contains(defaulter_3)))
    assert.isFalse((await sortedTroves.contains(_defaulter4TroveId)))

    // Check Stability Pool has not been emptied by the liquidations
    assert.equal((await stabilityPool.getTotalLUSDDeposits()).toString(), dec(500, 18))

    // Check that the liquidation sequence has improved the TCR
    const TCR_After = await th.getTCR(contracts)
    assert.isTrue(TCR_After.gte(TCR_Before))
  })

  it("liquidateTroves(): A liquidation sequence of pure redistributions decreases the TCR, due to gas compensation, but up to 0.5%", async () => {
    const { collateral: W_coll, totalDebt: W_totalDebt } = await openTrove({ ICR: toBN(dec(250, 16)), extraLUSDAmount: dec(500, 18), extraParams: { from: whale } })

    const { collateral: A_coll, totalDebt: A_totalDebt } = await openTrove({ ICR: toBN(dec(300, 16)), extraParams: { from: alice } })
    const { collateral: C_coll, totalDebt: C_totalDebt } = await openTrove({ ICR: toBN(dec(400, 16)), extraParams: { from: carol } })
    const { collateral: D_coll, totalDebt: D_totalDebt } = await openTrove({ ICR: toBN(dec(600, 16)), extraParams: { from: dennis } })

    const { collateral: d1_coll, totalDebt: d1_totalDebt } = await openTrove({ ICR: toBN(dec(198, 16)), extraLUSDAmount: dec(101, 18), extraParams: { from: defaulter_1 } })
    const { collateral: d2_coll, totalDebt: d2_totalDebt } = await openTrove({ ICR: toBN(dec(184, 16)), extraLUSDAmount: dec(217, 18), extraParams: { from: defaulter_2 } })
    const { collateral: d3_coll, totalDebt: d3_totalDebt } = await openTrove({ ICR: toBN(dec(183, 16)), extraLUSDAmount: dec(328, 18), extraParams: { from: defaulter_3 } })
    const { collateral: d4_coll, totalDebt: d4_totalDebt } = await openTrove({ ICR: toBN(dec(166, 16)), extraLUSDAmount: dec(431, 18), extraParams: { from: defaulter_4 } })
    let _defaulter1TroveId = await sortedTroves.troveOfOwnerByIndex(defaulter_1, 0);
    let _defaulter2TroveId = await sortedTroves.troveOfOwnerByIndex(defaulter_2, 0);
    let _defaulter3TroveId = await sortedTroves.troveOfOwnerByIndex(defaulter_3, 0);
    let _defaulter4TroveId = await sortedTroves.troveOfOwnerByIndex(defaulter_4, 0);

    assert.isTrue((await sortedTroves.contains(_defaulter1TroveId)))
    assert.isTrue((await sortedTroves.contains(_defaulter2TroveId)))
    assert.isTrue((await sortedTroves.contains(_defaulter3TroveId)))
    assert.isTrue((await sortedTroves.contains(_defaulter4TroveId)))

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
    assert.equal((await stabilityPool.getTotalLUSDDeposits()).toString(), '0')

    // Liquidate
    await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from : whale});
    await debtToken.transfer(owner, (await debtToken.balanceOf(defaulter_1)), {from : defaulter_1});
    await debtToken.transfer(owner, (await debtToken.balanceOf(defaulter_2)), {from : defaulter_2});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(defaulter_3)), {from : defaulter_3});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(defaulter_4)), {from : defaulter_4});
    await troveManager.liquidateSequentiallyInRecovery(8, {from: owner})

    // Check all defaulters have been liquidated
    assert.isFalse((await sortedTroves.contains(_defaulter1TroveId)))
    assert.isFalse((await sortedTroves.contains(_defaulter2TroveId)))
    assert.isFalse((await sortedTroves.contains(_defaulter3TroveId)))
    assert.isFalse((await sortedTroves.contains(_defaulter4TroveId)))

    // Check that the liquidation sequence has reduced the TCR
    const TCR_After = await th.getTCR(contracts)
    // ((5+1+2+3)+(1+2+3+4)*0.995)*100/(410+50+50+50+101+257+328+480)
    const totalCollAfter = W_coll.add(A_coll).add(C_coll).add(D_coll).add(th.applyLiquidationFee(toBN('0').add(toBN('0')).add(toBN('0')).add(toBN('0'))))
    const totalDebtAfter = W_totalDebt.add(A_totalDebt).add(C_totalDebt).add(D_totalDebt).add(toBN('0')).add(toBN('0')).add(toBN('0')).add(toBN('0'))
    assert.isAtMost(th.getDifference(TCR_After, totalCollAfter.mul(price).div(totalDebtAfter)), 1000)
    assert.isFalse(TCR_Before.gte(TCR_After))
    assert.isTrue(TCR_After.gte(TCR_Before.mul(th.toBN(995)).div(th.toBN(1000))))
  })

  it("liquidateTroves(): liquidates based on entire/collateral debt (including pending rewards), not raw collateral/debt", async () => {
    await openTrove({ ICR: toBN(dec(400, 16)), extraParams: { from: alice } })
    await openTrove({ ICR: toBN(dec(220, 16)), extraParams: { from: bob } })
    await openTrove({ ICR: toBN(dec(200, 16)), extraParams: { from: carol } })
    let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);

    // Defaulter opens with 60 LUSD, 0.6 ETH
    await openTrove({ ICR: toBN(dec(200, 16)), extraParams: { from: defaulter_1 } })
    let _defaulter1TroveId = await sortedTroves.troveOfOwnerByIndex(defaulter_1, 0);
    await openTrove({ ICR: toBN(dec(151, 16)), extraLUSDAmount: toBN(dec(6000,18)), extraParams: { from: owner } })

    // Price drops
    await priceFeed.setPrice(dec(100, 18))
    const price = await priceFeed.getPrice()

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    const alice_ICR_Before = await troveManager.getCurrentICR(_aliceTroveId, price)
    const bob_ICR_Before = await troveManager.getCurrentICR(_bobTroveId, price)
    const carol_ICR_Before = await troveManager.getCurrentICR(_carolTroveId, price)

    /* Before liquidation: 
    Alice ICR: = (1 * 100 / 50) = 200%
    Bob ICR: (1 * 100 / 90.5) = 110.5%
    Carol ICR: (1 * 100 / 100 ) =  100%

    Therefore Alice and Bob above the MCR, Carol is below */
    assert.isTrue(alice_ICR_Before.gte(mv._MCR))
    assert.isTrue(bob_ICR_Before.gte(mv._MCR))
    assert.isTrue(carol_ICR_Before.lte(mv._MCR))

    // Liquidate defaulter. 30 LUSD and 0.3 ETH is distributed uniformly between A, B and C. Each receive 10 LUSD, 0.1 ETH
    await debtToken.transfer(owner, (await debtToken.balanceOf(defaulter_1)), {from : defaulter_1});
    await troveManager.liquidateInBatchRecovery([_defaulter1TroveId], {from: owner})

    const alice_ICR_After = await troveManager.getCurrentICR(_aliceTroveId, price)
    const bob_ICR_After = await troveManager.getCurrentICR(_bobTroveId, price)
    const carol_ICR_After = await troveManager.getCurrentICR(_carolTroveId, price)

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
    const bob_Coll = (await troveManager.Troves(_bobTroveId))[1]
    const bob_Debt = (await troveManager.Troves(_bobTroveId))[0]

    const bob_rawICR = bob_Coll.mul(th.toBN(dec(100, 18))).div(bob_Debt)
    assert.isTrue(bob_rawICR.gte(mv._MCR))

    // Liquidate A, B, C
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await troveManager.liquidateSequentiallyInRecovery(10, {from: owner})

    /*  Since there is 0 LUSD in the stability Pool, A, with ICR >110%, should stay active.
   Check Alice stays active, Carol gets liquidated, and Bob gets liquidated 
   (because his pending rewards bring his ICR < MCR) */
    assert.isTrue(await sortedTroves.contains(_aliceTroveId))
    assert.isTrue(await sortedTroves.contains(_bobTroveId))
    assert.isFalse(await sortedTroves.contains(_carolTroveId))

    // check trove statuses - A active (1),  B and C liquidated (3)
    assert.equal((await troveManager.Troves(_aliceTroveId))[3].toString(), '1')
    assert.equal((await troveManager.Troves(_bobTroveId))[3].toString(), '1')
    assert.equal((await troveManager.Troves(_carolTroveId))[3].toString(), '3')
  })

  it('liquidateTroves(): does nothing if all troves have ICR > 110% and Stability Pool is empty', async () => {
    await openTrove({ ICR: toBN(dec(222, 16)), extraParams: { from: alice } })
    await openTrove({ ICR: toBN(dec(250, 16)), extraParams: { from: bob } })
    await openTrove({ ICR: toBN(dec(285, 16)), extraParams: { from: carol } })
    let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);

    // Price drops, but all troves remain active
    await priceFeed.setPrice(dec(100, 18))
    const price = await priceFeed.getPrice()

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    assert.isTrue((await sortedTroves.contains(_aliceTroveId)))
    assert.isTrue((await sortedTroves.contains(_bobTroveId)))
    assert.isTrue((await sortedTroves.contains(_carolTroveId)))

    const TCR_Before = (await th.getTCR(contracts)).toString()
    const listSize_Before = (await sortedTroves.getSize()).toString()


    assert.isTrue((await troveManager.getCurrentICR(_aliceTroveId, price)).gte(mv._MCR))
    assert.isTrue((await troveManager.getCurrentICR(_bobTroveId, price)).gte(mv._MCR))
    assert.isTrue((await troveManager.getCurrentICR(_carolTroveId, price)).gte(mv._MCR))

    // Confirm 0 LUSD in Stability Pool
    assert.equal((await stabilityPool.getTotalLUSDDeposits()).toString(), '0')

    // Attempt liqudation sequence
    //await assertRevert(troveManager.liquidateTroves(10), "TroveManager: nothing to liquidate")

    // Check all troves remain active
    assert.isTrue((await sortedTroves.contains(_aliceTroveId)))
    assert.isTrue((await sortedTroves.contains(_bobTroveId)))
    assert.isTrue((await sortedTroves.contains(_carolTroveId)))

    const TCR_After = (await th.getTCR(contracts)).toString()
    const listSize_After = (await sortedTroves.getSize()).toString()

    assert.equal(TCR_Before, TCR_After)
    assert.equal(listSize_Before, listSize_After)
  })

  it('liquidateTroves(): emits liquidation event with correct values when all troves have ICR > 110% and Stability Pool covers a subset of troves', async () => {
    // Troves to be absorbed by SP
    const { collateral: F_coll, totalDebt: F_totalDebt } = await openTrove({ ICR: toBN(dec(222, 16)), extraParams: { from: freddy } })
    const { collateral: G_coll, totalDebt: G_totalDebt } = await openTrove({ ICR: toBN(dec(222, 16)), extraParams: { from: greta } })

    // Troves to be spared
    const { collateral: A_coll, totalDebt: A_totalDebt } = await openTrove({ ICR: toBN(dec(250, 16)), extraParams: { from: alice } })
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openTrove({ ICR: toBN(dec(266, 16)), extraParams: { from: bob } })
    const { collateral: C_coll, totalDebt: C_totalDebt } = await openTrove({ ICR: toBN(dec(285, 16)), extraParams: { from: carol } })
    const { collateral: D_coll, totalDebt: D_totalDebt } = await openTrove({ ICR: toBN(dec(308, 16)), extraParams: { from: dennis } })
    let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);
    let _dennisTroveId = await sortedTroves.troveOfOwnerByIndex(dennis, 0);
    let _freddyTroveId = await sortedTroves.troveOfOwnerByIndex(freddy, 0);
    let _gretaTroveId = await sortedTroves.troveOfOwnerByIndex(greta, 0);

    // Whale adds LUSD to SP
    const spDeposit = F_totalDebt.add(G_totalDebt)
    const { collateral: W_coll, totalDebt: W_totalDebt } = await openTrove({ ICR: toBN(dec(285, 16)), extraLUSDAmount: spDeposit, extraParams: { from: whale } })
    //await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: whale })
    let _whaleTroveId = await sortedTroves.troveOfOwnerByIndex(whale, 0);
    const { collateral: O_coll, totalDebt: O_totalDebt } = await openTrove({ ICR: toBN(dec(151, 16)), extraLUSDAmount: spDeposit, extraParams: { from: owner } })

    // Price drops, but all troves remain active
    await priceFeed.setPrice(dec(100, 18))
    const price = await priceFeed.getPrice()

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Confirm all troves have ICR > MCR
    assert.isTrue((await troveManager.getCurrentICR(_freddyTroveId, price)).gte(mv._MCR))
    assert.isTrue((await troveManager.getCurrentICR(_gretaTroveId, price)).gte(mv._MCR))
    assert.isTrue((await troveManager.getCurrentICR(_aliceTroveId, price)).gte(mv._MCR))
    assert.isTrue((await troveManager.getCurrentICR(_bobTroveId, price)).gte(mv._MCR))
    assert.isTrue((await troveManager.getCurrentICR(_carolTroveId, price)).gte(mv._MCR))

    // Confirm LUSD in Stability Pool
    assert.equal((await stabilityPool.getTotalLUSDDeposits()).toString(), '0')

    // Attempt liqudation sequence
    await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from : whale});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});
    await debtToken.transfer(owner, (await debtToken.balanceOf(freddy)), {from : freddy});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(greta)), {from : greta});
    const liquidationTx = await troveManager.liquidateSequentiallyInRecovery(10, {from: owner})
    const [liquidatedDebt, liquidatedColl, gasComp] = th.getEmittedLiquidationValues(liquidationTx)

    // Check F and G were liquidated
    assert.isFalse(await sortedTroves.contains(_freddyTroveId))
    assert.isFalse(await sortedTroves.contains(_gretaTroveId))

    // Check whale and A-D remain active
    assert.isFalse(await sortedTroves.contains(_aliceTroveId))
    assert.isFalse(await sortedTroves.contains(_bobTroveId))
    assert.isFalse(await sortedTroves.contains(_carolTroveId))
    assert.isTrue(await sortedTroves.contains(_dennisTroveId))
    assert.isFalse(await sortedTroves.contains(_whaleTroveId))

    // Liquidation event emits coll = (F_debt + G_debt)/price*1.1*0.995, and debt = (F_debt + G_debt)
    let _calculatedDebt = F_totalDebt.add(G_totalDebt).add(A_totalDebt).add(B_totalDebt).add(C_totalDebt).add(W_totalDebt).add(O_totalDebt);
    th.assertIsApproximatelyEqual(liquidatedDebt, _calculatedDebt)
    th.assertIsApproximatelyEqual(liquidatedColl, (_calculatedDebt.sub(O_totalDebt)).mul(toBN(dec(11, 17))).div(price).add(O_coll))

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

  it('liquidateTroves():  emits liquidation event with correct values when all troves have ICR > 110% and Stability Pool covers a subset of troves, including a partial', async () => {
    // Troves to be absorbed by SP
    const { collateral: F_coll, totalDebt: F_totalDebt } = await openTrove({ ICR: toBN(dec(222, 16)), extraParams: { from: freddy } })
    const { collateral: G_coll, totalDebt: G_totalDebt } = await openTrove({ ICR: toBN(dec(222, 16)), extraParams: { from: greta } })

    // Troves to be spared
    const { collateral: A_coll, totalDebt: A_totalDebt } = await openTrove({ ICR: toBN(dec(250, 16)), extraParams: { from: alice } })
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openTrove({ ICR: toBN(dec(266, 16)), extraParams: { from: bob } })
    const { collateral: C_coll, totalDebt: C_totalDebt } = await openTrove({ ICR: toBN(dec(285, 16)), extraParams: { from: carol } })
    const { collateral: D_coll, totalDebt: D_totalDebt } = await openTrove({ ICR: toBN(dec(308, 16)), extraParams: { from: dennis } })
    let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);
    let _dennisTroveId = await sortedTroves.troveOfOwnerByIndex(dennis, 0);
    let _freddyTroveId = await sortedTroves.troveOfOwnerByIndex(freddy, 0);
    let _gretaTroveId = await sortedTroves.troveOfOwnerByIndex(greta, 0);

    // Whale adds LUSD to SP
    const spDeposit = F_totalDebt.add(G_totalDebt).add(A_totalDebt.div(toBN(2)))
    const { collateral: W_coll, totalDebt: W_totalDebt } = await openTrove({ ICR: toBN(dec(285, 16)), extraLUSDAmount: spDeposit, extraParams: { from: whale } })
    //await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: whale })
    let _whaleTroveId = await sortedTroves.troveOfOwnerByIndex(whale, 0);
    const { collateral: O_coll, totalDebt: O_totalDebt } = await openTrove({ ICR: toBN(dec(151, 16)), extraLUSDAmount: spDeposit, extraParams: { from: owner } })

    // Price drops, but all troves remain active
    await priceFeed.setPrice(dec(100, 18))
    const price = await priceFeed.getPrice()

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Confirm all troves have ICR > MCR
    assert.isTrue((await troveManager.getCurrentICR(_freddyTroveId, price)).gte(mv._MCR))
    assert.isTrue((await troveManager.getCurrentICR(_gretaTroveId, price)).gte(mv._MCR))
    assert.isTrue((await troveManager.getCurrentICR(_aliceTroveId, price)).gte(mv._MCR))
    assert.isTrue((await troveManager.getCurrentICR(_bobTroveId, price)).gte(mv._MCR))
    assert.isTrue((await troveManager.getCurrentICR(_carolTroveId, price)).gte(mv._MCR))

    // Confirm LUSD in Stability Pool
    assert.equal((await stabilityPool.getTotalLUSDDeposits()).toString(), '0')

    // Attempt liqudation sequence
    await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from : whale});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});
    await debtToken.transfer(owner, (await debtToken.balanceOf(freddy)), {from : freddy});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(greta)), {from : greta});
    const liquidationTx = await troveManager.liquidateSequentiallyInRecovery(10, {from: owner})
    const [liquidatedDebt, liquidatedColl, gasComp] = th.getEmittedLiquidationValues(liquidationTx)

    // Check F and G were liquidated
    assert.isFalse(await sortedTroves.contains(_freddyTroveId))
    assert.isFalse(await sortedTroves.contains(_gretaTroveId))

    // Check whale and A-D remain active
    assert.isFalse(await sortedTroves.contains(_aliceTroveId))
    assert.isFalse(await sortedTroves.contains(_bobTroveId))
    assert.isFalse(await sortedTroves.contains(_carolTroveId))
    assert.isTrue(await sortedTroves.contains(_dennisTroveId))
    assert.isFalse(await sortedTroves.contains(_whaleTroveId))

    // Check A's collateral and debt remain the same
//    const entireColl_A = (await troveManager.Troves(_aliceTroveId))[1].add(await troveManager.getPendingETHReward(_aliceTroveId))
//    const entireDebt_A = (await troveManager.Troves(_aliceTroveId))[0].add(await troveManager.getPendingLUSDDebtReward(_aliceTroveId))

//    assert.equal(entireColl_A.toString(), A_coll)
//    assert.equal(entireDebt_A.toString(), A_totalDebt)

    /* Liquidation event emits:
    coll = (F_debt + G_debt)/price*1.1*0.995
    debt = (F_debt + G_debt) */
    let _calculatedDebt = F_totalDebt.add(G_totalDebt).add(A_totalDebt).add(B_totalDebt).add(C_totalDebt).add(W_totalDebt).add(O_totalDebt);
    th.assertIsApproximatelyEqual(liquidatedDebt, _calculatedDebt)
    th.assertIsApproximatelyEqual(liquidatedColl, (_calculatedDebt.sub(O_totalDebt)).mul(toBN(dec(11, 17))).div(price).add(O_coll))

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

  it("liquidateTroves(): does not affect the liquidated user's token balances", async () => {
    await openTrove({ ICR: toBN(dec(300, 16)), extraParams: { from: whale } })

    // D, E, F open troves that will fall below MCR when price drops to 100
    const { lusdAmount: lusdAmountD } = await openTrove({ ICR: toBN(dec(200, 16)), extraParams: { from: dennis } })
    const { lusdAmount: lusdAmountE } = await openTrove({ ICR: toBN(dec(133, 16)), extraParams: { from: erin } })
    const { lusdAmount: lusdAmountF } = await openTrove({ ICR: toBN(dec(111, 16)), extraParams: { from: freddy } })
    let _whaleTroveId = await sortedTroves.troveOfOwnerByIndex(whale, 0);
    let _dennisTroveId = await sortedTroves.troveOfOwnerByIndex(dennis, 0);
    let _freddyTroveId = await sortedTroves.troveOfOwnerByIndex(freddy, 0);
    let _erinTroveId = await sortedTroves.troveOfOwnerByIndex(erin, 0);

    // Check list size is 4
    assert.equal((await sortedTroves.getSize()).toString(), '4')
    await openTrove({ ICR: toBN(dec(151, 16)), extraLUSDAmount: toBN(dec(12000, 18)), extraParams: { from: owner } })

    // Check token balances before
    assert.equal((await lusdToken.balanceOf(dennis)).toString(), lusdAmountD)
    assert.equal((await lusdToken.balanceOf(erin)).toString(), lusdAmountE)
    assert.equal((await lusdToken.balanceOf(freddy)).toString(), lusdAmountF)

    // Price drops
    await priceFeed.setPrice(dec(80, 18))

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    //Liquidate sequence
    await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from : whale});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(freddy)), {from : freddy});
    await debtToken.transfer(owner, (await debtToken.balanceOf(erin)), {from : erin});
    await troveManager.liquidateSequentiallyInRecovery(10, {from: owner})

    // Check Whale remains in the system
    assert.isTrue(await sortedTroves.contains(_whaleTroveId))

    // Check D, E, F have been removed
    assert.isFalse(await sortedTroves.contains(_dennisTroveId))
    assert.isFalse(await sortedTroves.contains(_erinTroveId))
    assert.isFalse(await sortedTroves.contains(_freddyTroveId))

    // Check token balances of users whose troves were liquidated, have not changed
    assert.equal((await lusdToken.balanceOf(dennis)).toString(), '0')
    assert.equal((await lusdToken.balanceOf(erin)).toString(), '0')
    assert.equal((await lusdToken.balanceOf(freddy)).toString(), '0')
  })

  it("liquidateTroves(): Liquidating troves at 100 < ICR < 110 with SP deposits correctly impacts their SP deposit and ETH gain", async () => {
    // Whale provides LUSD to the SP
    const { lusdAmount: W_lusdAmount } = await openTrove({ ICR: toBN(dec(300, 16)), extraLUSDAmount: dec(4000, 18), extraParams: { from: whale } })
    await stabilityPool.provideToSP(W_lusdAmount, ZERO_ADDRESS, { from: whale })

    const { lusdAmount: A_lusdAmount, totalDebt: A_totalDebt, collateral: A_coll } = await openTrove({ ICR: toBN(dec(191, 16)), extraLUSDAmount: dec(40, 18), extraParams: { from: alice } })
    const { lusdAmount: B_lusdAmount, totalDebt: B_totalDebt, collateral: B_coll } = await openTrove({ ICR: toBN(dec(200, 16)), extraLUSDAmount: dec(240, 18), extraParams: { from: bob } })
    const { totalDebt: C_totalDebt, collateral: C_coll} = await openTrove({ ICR: toBN(dec(209, 16)), extraParams: { from: carol } })
    let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);

    // A, B provide to the SP
    await stabilityPool.provideToSP(A_lusdAmount, ZERO_ADDRESS, { from: alice })
    await stabilityPool.provideToSP(B_lusdAmount, ZERO_ADDRESS, { from: bob })

    const totalDeposit = W_lusdAmount.add(A_lusdAmount).add(B_lusdAmount)

    assert.equal((await sortedTroves.getSize()).toString(), '4')

    // Price drops
    await priceFeed.setPrice(dec(105, 18))
    const price = await priceFeed.getPrice()

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check LUSD in Pool
    assert.equal((await stabilityPool.getTotalLUSDDeposits()).toString(), totalDeposit)

    // *** Check A, B, C ICRs 100<ICR<110
    const alice_ICR = await troveManager.getCurrentICR(_aliceTroveId, price)
    const bob_ICR = await troveManager.getCurrentICR(_bobTroveId, price)
    const carol_ICR = await troveManager.getCurrentICR(_carolTroveId, price)

    assert.isTrue(alice_ICR.gte(mv._ICR100) && alice_ICR.lte(mv._MCR))
    assert.isTrue(bob_ICR.gte(mv._ICR100) && bob_ICR.lte(mv._MCR))
    assert.isTrue(carol_ICR.gte(mv._ICR100) && carol_ICR.lte(mv._MCR))

    // Liquidate
    await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from : whale});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await openTrove({ ICR: toBN(dec(151, 16)), extraLUSDAmount: totalDeposit, extraParams: { from: owner } })
    await troveManager.liquidateSequentiallyInRecovery(10, {from: owner})

    // Check all defaulters have been liquidated
    assert.isFalse((await sortedTroves.contains(_aliceTroveId)))
    assert.isFalse((await sortedTroves.contains(_bobTroveId)))
    assert.isFalse((await sortedTroves.contains(_carolTroveId)))

    // check system sized reduced to 1 troves
    assert.equal((await sortedTroves.getSize()).toString(), '2')

    /* Prior to liquidation, SP deposits were:
    Whale: 400 LUSD
    Alice:  40 LUSD
    Bob:   240 LUSD
    Carol: 0 LUSD

    Total LUSD in Pool: 680 LUSD

    Then, liquidation hits A,B,C: 

    Total liquidated debt = 100 + 300 + 100 = 500 LUSD
    Total liquidated ETH = 1 + 3 + 1 = 5 ETH

    Whale LUSD Loss: 500 * (400/680) = 294.12 LUSD
    Alice LUSD Loss:  500 *(40/680) = 29.41 LUSD
    Bob LUSD Loss: 500 * (240/680) = 176.47 LUSD

    Whale remaining deposit: (400 - 294.12) = 105.88 LUSD
    Alice remaining deposit: (40 - 29.41) = 10.59 LUSD
    Bob remaining deposit: (240 - 176.47) = 63.53 LUSD

    Whale ETH Gain: 5*0.995 * (400/680) = 2.93 ETH
    Alice ETH Gain: 5*0.995 *(40/680) = 0.293 ETH
    Bob ETH Gain: 5*0.995 * (240/680) = 1.76 ETH

    Total remaining deposits: 180 LUSD
    Total ETH gain: 5*0.995 ETH */

    const LUSDinSP = (await stabilityPool.getTotalLUSDDeposits()).toString()
    const ETHinSP = (await stabilityPool.getETH()).toString()

    // Check remaining LUSD Deposits and ETH gain, for whale and depositors whose troves were liquidated
    const whale_Deposit_After = (await stabilityPool.getCompoundedLUSDDeposit(whale)).toString()
    const alice_Deposit_After = (await stabilityPool.getCompoundedLUSDDeposit(alice)).toString()
    const bob_Deposit_After = (await stabilityPool.getCompoundedLUSDDeposit(bob)).toString()

    const whale_ETHGain = (await stabilityPool.getDepositorETHGain(whale)).toString()
    const alice_ETHGain = (await stabilityPool.getDepositorETHGain(alice)).toString()
    const bob_ETHGain = (await stabilityPool.getDepositorETHGain(bob)).toString()

    const liquidatedDebt = A_totalDebt.add(B_totalDebt).add(C_totalDebt)
    const liquidatedColl = A_coll.add(B_coll).add(C_coll)
    assert.isAtMost(th.getDifference(whale_Deposit_After, W_lusdAmount.sub(toBN('0').mul(W_lusdAmount).div(totalDeposit))), 100000)
    assert.isAtMost(th.getDifference(alice_Deposit_After, A_lusdAmount.sub(toBN('0').mul(A_lusdAmount).div(totalDeposit))), 100000)
    assert.isAtMost(th.getDifference(bob_Deposit_After, B_lusdAmount.sub(toBN('0').mul(B_lusdAmount).div(totalDeposit))), 100000)

    assert.isAtMost(th.getDifference(whale_ETHGain, th.applyLiquidationFee(toBN('0')).mul(W_lusdAmount).div(totalDeposit)), 2000)
    assert.isAtMost(th.getDifference(alice_ETHGain, th.applyLiquidationFee(toBN('0')).mul(A_lusdAmount).div(totalDeposit)), 2000)
    assert.isAtMost(th.getDifference(bob_ETHGain, th.applyLiquidationFee(toBN('0')).mul(B_lusdAmount).div(totalDeposit)), 2000)

    // Check total remaining deposits and ETH gain in Stability Pool
    const total_LUSDinSP = (await stabilityPool.getTotalLUSDDeposits()).toString()
    const total_ETHinSP = (await stabilityPool.getETH()).toString()

    assert.isAtMost(th.getDifference(total_LUSDinSP, totalDeposit.sub(toBN('0'))), 1000)
    assert.isAtMost(th.getDifference(total_ETHinSP, th.applyLiquidationFee(toBN('0'))), 1000)
  })

  it("liquidateTroves(): Liquidating troves at ICR <=100% with SP deposits does not alter their deposit or ETH gain", async () => {
    // Whale provides 400 LUSD to the SP
    await openTrove({ ICR: toBN(dec(300, 16)), extraLUSDAmount: dec(400, 18), extraParams: { from: whale } })
    await stabilityPool.provideToSP(dec(400, 18), ZERO_ADDRESS, { from: whale })

    await openTrove({ ICR: toBN(dec(182, 16)), extraLUSDAmount: dec(170, 18), extraParams: { from: alice } })
    await openTrove({ ICR: toBN(dec(180, 16)), extraLUSDAmount: dec(300, 18), extraParams: { from: bob } })
    await openTrove({ ICR: toBN(dec(170, 16)), extraParams: { from: carol } })
    let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);

    // A, B provide 100, 300 to the SP
    await stabilityPool.provideToSP(dec(100, 18), ZERO_ADDRESS, { from: alice })
    await stabilityPool.provideToSP(dec(300, 18), ZERO_ADDRESS, { from: bob })

    assert.equal((await sortedTroves.getSize()).toString(), '4')

    // Price drops
    await priceFeed.setPrice(dec(100, 18))
    const price = await priceFeed.getPrice()

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check LUSD and ETH in Pool  before
    const LUSDinSP_Before = (await stabilityPool.getTotalLUSDDeposits()).toString()
    const ETHinSP_Before = (await stabilityPool.getETH()).toString()
    assert.equal(LUSDinSP_Before, dec(800, 18))
    assert.equal(ETHinSP_Before, '0')

    // *** Check A, B, C ICRs < 100
    assert.isTrue((await troveManager.getCurrentICR(_aliceTroveId, price)).lte(mv._ICR100))
    assert.isTrue((await troveManager.getCurrentICR(_bobTroveId, price)).lte(mv._ICR100))
    assert.isTrue((await troveManager.getCurrentICR(_carolTroveId, price)).lte(mv._ICR100))

    // Liquidate
    await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from : whale});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});	
    await troveManager.liquidateSequentiallyInRecovery(10, {from: owner})

    // Check all defaulters have been liquidated
    assert.isFalse((await sortedTroves.contains(_aliceTroveId)))
    assert.isFalse((await sortedTroves.contains(_bobTroveId)))
    assert.isFalse((await sortedTroves.contains(_carolTroveId)))

    // check system sized reduced to 1 troves
    assert.equal((await sortedTroves.getSize()).toString(), '1')

    // Check LUSD and ETH in Pool after
    const LUSDinSP_After = (await stabilityPool.getTotalLUSDDeposits()).toString()
    const ETHinSP_After = (await stabilityPool.getETH()).toString()
    assert.equal(LUSDinSP_Before, LUSDinSP_After)
    assert.equal(ETHinSP_Before, ETHinSP_After)

    // Check remaining LUSD Deposits and ETH gain, for whale and depositors whose troves were liquidated
    const whale_Deposit_After = (await stabilityPool.getCompoundedLUSDDeposit(whale)).toString()
    const alice_Deposit_After = (await stabilityPool.getCompoundedLUSDDeposit(alice)).toString()
    const bob_Deposit_After = (await stabilityPool.getCompoundedLUSDDeposit(bob)).toString()

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

  it("liquidateTroves() with a non fullfilled liquidation: non liquidated trove remains active", async () => {
    const { totalDebt: A_totalDebt } = await openTrove({ ICR: toBN(dec(196, 16)), extraParams: { from: alice } })
    const { totalDebt: B_totalDebt } = await openTrove({ ICR: toBN(dec(198, 16)), extraParams: { from: bob } })
    const { totalDebt: C_totalDebt } = await openTrove({ ICR: toBN(dec(200, 16)), extraParams: { from: carol } })
    await openTrove({ ICR: toBN(dec(206, 16)), extraParams: { from: dennis } })
    await openTrove({ ICR: toBN(dec(208, 16)), extraParams: { from: erin } })
    let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);

    // Whale provides LUSD to the SP
    const spDeposit = A_totalDebt.add(B_totalDebt).add(C_totalDebt.div(toBN(2)))
    await openTrove({ ICR: toBN(dec(300, 16)), extraLUSDAmount: spDeposit, extraParams: { from: whale } })
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: whale })

    // Price drops 
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()
    const TCR = await th.getTCR(contracts)

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check A, B, C, D, E troves are in range 110% < ICR < TCR
    const ICR_A = await troveManager.getCurrentICR(_aliceTroveId, price)
    const ICR_B = await troveManager.getCurrentICR(_bobTroveId, price)
    const ICR_C = await troveManager.getCurrentICR(_carolTroveId, price)

    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C.gt(mv._MCR) && ICR_C.lt(TCR))

    /* Liquidate troves. Troves are ordered by ICR, from low to high:  A, B, C, D, E.
    With 253 in the SP, Alice (102 debt) and Bob (101 debt) should be entirely liquidated. 
    That leaves 50 LUSD in the Pool to absorb exactly half of Carol's debt (100) */
    await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from : whale});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(erin)), {from : erin});
    await troveManager.liquidateSequentiallyInRecovery(10, {from: owner})

    // Check A and B closed
    assert.isFalse(await sortedTroves.contains(_aliceTroveId))
    assert.isFalse(await sortedTroves.contains(_bobTroveId))

    // Check C remains active
    assert.isTrue(await sortedTroves.contains(_carolTroveId))
    assert.equal((await troveManager.Troves(_carolTroveId))[3].toString(), '1') // check Status is active
  })

  it("liquidateTroves() with a non fullfilled liquidation: non liquidated trove remains in TroveOwners Array", async () => {
    const { totalDebt: A_totalDebt } = await openTrove({ ICR: toBN(dec(2209, 15)), extraParams: { from: alice } })
    const { totalDebt: B_totalDebt } = await openTrove({ ICR: toBN(dec(221, 16)), extraParams: { from: bob } })
    const { totalDebt: C_totalDebt } = await openTrove({ ICR: toBN(dec(222, 16)), extraParams: { from: carol } })
    await openTrove({ ICR: toBN(dec(219, 16)), extraParams: { from: dennis } })
    await openTrove({ ICR: toBN(dec(221, 16)), extraParams: { from: erin } })
    let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);

    // Whale provides LUSD to the SP
    const spDeposit = A_totalDebt.add(B_totalDebt).add(C_totalDebt.div(toBN(2)))
    await openTrove({ ICR: toBN(dec(220, 16)), extraLUSDAmount: spDeposit, extraParams: { from: whale } })
    //await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: whale })
    await openTrove({ ICR: toBN(dec(260, 16)), extraLUSDAmount: spDeposit, extraParams: { from: owner } })

    // Price drops 
    await priceFeed.setPrice(dec(100, 18))
    const price = await priceFeed.getPrice()
    const TCR = await th.getTCR(contracts)

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check A, B, C troves are in range 110% < ICR < TCR
    const ICR_A = await troveManager.getCurrentICR(_aliceTroveId, price)
    const ICR_B = await troveManager.getCurrentICR(_bobTroveId, price)
    const ICR_C = await troveManager.getCurrentICR(_carolTroveId, price)
    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C.gt(mv._MCR) && ICR_C.lt(TCR))

    /* Liquidate troves. Troves are ordered by ICR, from low to high:  A, B, C.
    With 253 in the SP, Alice (102 debt) and Bob (101 debt) should be entirely liquidated. 
    That leaves 50 LUSD in the Pool to absorb exactly half of Carol's debt (100) */
    await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from : whale});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(erin)), {from : erin});
    await troveManager.liquidateSequentiallyInRecovery(10, {from: owner})

    // Check C is in Trove owners array
    const arrayLength = (await troveManager.getTroveIdsCount()).toNumber()
    let addressFound = false;
    let addressIdx = 0;

    for (let i = 0; i < arrayLength; i++) {
      const address = (await troveManager.TroveIds(i)).toString()
      if (address == _carolTroveId) {
        addressFound = true
        addressIdx = i
      }
    }

    assert.isFalse(addressFound);

    // Check TroveOwners idx on trove struct == idx of address found in TroveOwners array
    //const idxOnStruct = (await troveManager.Troves(_carolTroveId))[4].toString()
    //assert.equal(addressIdx.toString(), idxOnStruct)
  })

  it("liquidateTroves() with a non fullfilled liquidation: still can liquidate further troves after the non-liquidated, emptied pool", async () => {
    const { totalDebt: A_totalDebt } = await openTrove({ ICR: toBN(dec(196, 16)), extraParams: { from: alice } })
    const { totalDebt: B_totalDebt } = await openTrove({ ICR: toBN(dec(198, 16)), extraParams: { from: bob } })
    const { totalDebt: D_totalDebt } = await openTrove({ ICR: toBN(dec(206, 16)), extraParams: { from: dennis } })
    const { totalDebt: C_totalDebt } = await openTrove({ ICR: toBN(dec(200, 16)), extraLUSDAmount: D_totalDebt, extraParams: { from: carol } })
    await openTrove({ ICR: toBN(dec(208, 16)), extraParams: { from: erin } })
    let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);
    let _dennisTroveId = await sortedTroves.troveOfOwnerByIndex(dennis, 0);
    let _erinTroveId = await sortedTroves.troveOfOwnerByIndex(erin, 0);

    // Whale provides LUSD to the SP
    const spDeposit = A_totalDebt.add(B_totalDebt).add(D_totalDebt)
    await openTrove({ ICR: toBN(dec(220, 16)), extraLUSDAmount: spDeposit, extraParams: { from: whale } })
    let _whaleTroveId = await sortedTroves.troveOfOwnerByIndex(whale, 0);
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: whale })

    // Price drops 
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()
    const TCR = await th.getTCR(contracts)

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check A, B, C, D, E troves are in range 110% < ICR < TCR
    const ICR_A = await troveManager.getCurrentICR(_aliceTroveId, price)
    const ICR_B = await troveManager.getCurrentICR(_bobTroveId, price)
    const ICR_C = await troveManager.getCurrentICR(_carolTroveId, price)
    const ICR_D = await troveManager.getCurrentICR(_dennisTroveId, price)
    const ICR_E = await troveManager.getCurrentICR(_erinTroveId, price)

    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C.gt(mv._MCR) && ICR_C.lt(TCR))
    assert.isTrue(ICR_D.gt(mv._MCR) && ICR_D.lt(TCR))
    assert.isTrue(ICR_E.gt(mv._MCR) && ICR_E.lt(TCR))

    /* Liquidate troves. Troves are ordered by ICR, from low to high:  A, B, C, D, E.
     With 300 in the SP, Alice (102 debt) and Bob (101 debt) should be entirely liquidated.
     That leaves 97 LUSD in the Pool that won’t be enough to absorb Carol,
     but it will be enough to liquidate Dennis. Afterwards the pool will be empty,
     so Erin won’t liquidated. */
    await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from : whale});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(erin)), {from : erin});
    const tx = await troveManager.liquidateSequentiallyInRecovery(10, {from: owner})
    console.log('gasUsed: ', tx.receipt.gasUsed)

    // Check A, B and D are closed
    assert.isFalse(await sortedTroves.contains(_aliceTroveId))
    assert.isFalse(await sortedTroves.contains(_bobTroveId))
    console.log(await sortedTroves.contains(_carolTroveId))
    assert.isFalse(await sortedTroves.contains(_dennisTroveId))

    // Check whale, C and E stay active
    assert.isTrue(await sortedTroves.contains(_whaleTroveId))
    assert.isFalse(await sortedTroves.contains(_carolTroveId))
    assert.isFalse(await sortedTroves.contains(_erinTroveId))
  })

  it("liquidateTroves() with a non fullfilled liquidation: still can liquidate further troves after the non-liquidated, non emptied pool", async () => {
    const { totalDebt: A_totalDebt } = await openTrove({ ICR: toBN(dec(196, 16)), extraParams: { from: alice } })
    const { totalDebt: B_totalDebt } = await openTrove({ ICR: toBN(dec(198, 16)), extraParams: { from: bob } })
    const { totalDebt: D_totalDebt } = await openTrove({ ICR: toBN(dec(206, 16)), extraParams: { from: dennis } })
    const { totalDebt: C_totalDebt } = await openTrove({ ICR: toBN(dec(200, 16)), extraLUSDAmount: D_totalDebt, extraParams: { from: carol } })
    await openTrove({ ICR: toBN(dec(208, 16)), extraParams: { from: erin } })
    let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);
    let _dennisTroveId = await sortedTroves.troveOfOwnerByIndex(dennis, 0);
    let _erinTroveId = await sortedTroves.troveOfOwnerByIndex(erin, 0);

    // Whale provides LUSD to the SP
    const spDeposit = A_totalDebt.add(B_totalDebt).add(D_totalDebt)
    await openTrove({ ICR: toBN(dec(220, 16)), extraLUSDAmount: spDeposit, extraParams: { from: whale } })
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: whale })
    let _whaleTroveId = await sortedTroves.troveOfOwnerByIndex(whale, 0);

    // Price drops 
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()
    const TCR = await th.getTCR(contracts)

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check A, B, C, D, E troves are in range 110% < ICR < TCR
    const ICR_A = await troveManager.getCurrentICR(_aliceTroveId, price)
    const ICR_B = await troveManager.getCurrentICR(_bobTroveId, price)
    const ICR_C = await troveManager.getCurrentICR(_carolTroveId, price)
    const ICR_D = await troveManager.getCurrentICR(_dennisTroveId, price)
    const ICR_E = await troveManager.getCurrentICR(_erinTroveId, price)

    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C.gt(mv._MCR) && ICR_C.lt(TCR))
    assert.isTrue(ICR_D.gt(mv._MCR) && ICR_D.lt(TCR))
    assert.isTrue(ICR_E.gt(mv._MCR) && ICR_E.lt(TCR))

    /* Liquidate troves. Troves are ordered by ICR, from low to high:  A, B, C, D, E.
     With 301 in the SP, Alice (102 debt) and Bob (101 debt) should be entirely liquidated.
     That leaves 97 LUSD in the Pool that won’t be enough to absorb Carol,
     but it will be enough to liquidate Dennis. Afterwards the pool will be empty,
     so Erin won’t liquidated.
     Note that, compared to the previous test, this one will make 1 more loop iteration,
     so it will consume more gas. */
    await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from : whale});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(erin)), {from : erin});
    const tx = await troveManager.liquidateSequentiallyInRecovery(10, {from: owner})
    console.log('gasUsed: ', tx.receipt.gasUsed)

    // Check A, B and D are closed
    assert.isFalse(await sortedTroves.contains(_aliceTroveId))
    assert.isFalse(await sortedTroves.contains(_bobTroveId))
    assert.isFalse(await sortedTroves.contains(_dennisTroveId))

    // Check whale, C and E stay active
    assert.isTrue(await sortedTroves.contains(_whaleTroveId))
    assert.isFalse(await sortedTroves.contains(_carolTroveId))
    assert.isFalse(await sortedTroves.contains(_erinTroveId))
  })

  it("liquidateTroves() with a non fullfilled liquidation: total liquidated coll and debt is correct", async () => {
    const { collateral: A_coll, totalDebt: A_totalDebt } = await openTrove({ ICR: toBN(dec(196, 16)), extraParams: { from: alice } })
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openTrove({ ICR: toBN(dec(198, 16)), extraParams: { from: bob } })
    const { collateral: C_coll, totalDebt: C_totalDebt } = await openTrove({ ICR: toBN(dec(200, 16)), extraParams: { from: carol } })
    const { collateral: D_coll, totalDebt: D_totalDebt } = await openTrove({ ICR: toBN(dec(206, 16)), extraParams: { from: dennis } })
    const { collateral: E_coll, totalDebt: E_totalDebt } = await openTrove({ ICR: toBN(dec(208, 16)), extraParams: { from: erin } })

    // Whale provides LUSD to the SP
    const spDeposit = A_totalDebt.add(B_totalDebt).add(C_totalDebt.div(toBN(2)))
    const { collateral: W_coll, totalDebt: W_totalDebt } = await openTrove({ ICR: toBN(dec(220, 16)), extraLUSDAmount: spDeposit, extraParams: { from: whale } })
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: whale })
    let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);

    // Price drops 
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()
    const TCR = await th.getTCR(contracts)

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check A, B, C troves are in range 110% < ICR < TCR
    const ICR_A = await troveManager.getCurrentICR(_aliceTroveId, price)
    const ICR_B = await troveManager.getCurrentICR(_bobTroveId, price)
    const ICR_C = await troveManager.getCurrentICR(_carolTroveId, price)

    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C.gt(mv._MCR) && ICR_C.lt(TCR))

    const entireSystemCollBefore = await troveManager.getEntireSystemColl()
    const entireSystemDebtBefore = await troveManager.getEntireSystemDebt()

    /* Liquidate troves. Troves are ordered by ICR, from low to high:  A, B, C, D, E.
    With 253 in the SP, Alice (102 debt) and Bob (101 debt) should be entirely liquidated. 
    That leaves 50 LUSD in the Pool that won’t be enough to absorb any other trove */
    await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from : whale});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(erin)), {from : erin});
    const tx = await troveManager.liquidateSequentiallyInRecovery(10, {from: owner})

    // Expect system debt reduced by 203 LUSD and system coll 2.3 ETH
    const entireSystemCollAfter = await troveManager.getEntireSystemColl()
    const entireSystemDebtAfter = await troveManager.getEntireSystemDebt()

    const changeInEntireSystemColl = entireSystemCollBefore.sub(entireSystemCollAfter)
    const changeInEntireSystemDebt = entireSystemDebtBefore.sub(entireSystemDebtAfter)

    assert.equal(changeInEntireSystemColl.toString(), A_coll.add(B_coll).add(C_coll).add(D_coll).add(E_coll).toString())
    th.assertIsApproximatelyEqual(changeInEntireSystemDebt.toString(), A_totalDebt.add(B_totalDebt).add(C_totalDebt).add(D_totalDebt).add(E_totalDebt))
  })

  it("liquidateTroves() with a non fullfilled liquidation: emits correct liquidation event values", async () => {
    const { collateral: A_coll, totalDebt: A_totalDebt } = await openTrove({ ICR: toBN(dec(210, 16)), extraParams: { from: alice } })
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openTrove({ ICR: toBN(dec(211, 16)), extraParams: { from: bob } })
    const { collateral: C_coll, totalDebt: C_totalDebt } = await openTrove({ ICR: toBN(dec(212, 16)), extraParams: { from: carol } })
    const { collateral: D_coll, totalDebt: D_totalDebt } = await openTrove({ ICR: toBN(dec(219, 16)), extraParams: { from: dennis } })
    const { collateral: E_coll, totalDebt: E_totalDebt } = await openTrove({ ICR: toBN(dec(221, 16)), extraParams: { from: erin } })

    // Whale provides LUSD to the SP
    const spDeposit = A_totalDebt.add(B_totalDebt).add(C_totalDebt.div(toBN(2)))
    const { collateral: W_coll, totalDebt: W_totalDebt } = await openTrove({ ICR: toBN(dec(240, 16)), extraLUSDAmount: spDeposit, extraParams: { from: whale } })
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: whale })
    let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);

    // Price drops 
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()
    const TCR = await th.getTCR(contracts)

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check A, B, C troves are in range 110% < ICR < TCR
    const ICR_A = await troveManager.getCurrentICR(_aliceTroveId, price)
    const ICR_B = await troveManager.getCurrentICR(_bobTroveId, price)
    const ICR_C = await troveManager.getCurrentICR(_carolTroveId, price)

    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C.gt(mv._MCR) && ICR_C.lt(TCR))

    /* Liquidate troves. Troves are ordered by ICR, from low to high:  A, B, C, D, E.
    With 253 in the SP, Alice (102 debt) and Bob (101 debt) should be entirely liquidated. 
    That leaves 50 LUSD in the Pool which won’t be enough for any other liquidation */
    await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from : whale});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(erin)), {from : erin});	
    const liquidationTx = await troveManager.liquidateSequentiallyInRecovery(10, {from: owner})

    const [liquidatedDebt, liquidatedColl, collGasComp, lusdGasComp] = th.getEmittedLiquidationValues(liquidationTx)

    th.assertIsApproximatelyEqual(liquidatedDebt, A_totalDebt.add(B_totalDebt).add(C_totalDebt).add(D_totalDebt).add(E_totalDebt))
    const equivalentColl = A_totalDebt.add(B_totalDebt).add(C_totalDebt).add(D_totalDebt).add(E_totalDebt).mul(toBN(dec(11, 17))).div(price)
    th.assertIsApproximatelyEqual(liquidatedColl, equivalentColl)
    assert.equal(collGasComp.toString(), '0') // 0.5% of 283/120*1.1
    assert.equal(lusdGasComp.toString(), '0')

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

  it("liquidateTroves() with a non fullfilled liquidation: ICR of non liquidated trove does not change", async () => {
    const { totalDebt: A_totalDebt } = await openTrove({ ICR: toBN(dec(196, 16)), extraParams: { from: alice } })
    const { totalDebt: B_totalDebt } = await openTrove({ ICR: toBN(dec(198, 16)), extraParams: { from: bob } })
    const { totalDebt: C_totalDebt } = await openTrove({ ICR: toBN(dec(200, 16)), extraParams: { from: carol } })
    await openTrove({ ICR: toBN(dec(206, 16)), extraParams: { from: dennis } })
    await openTrove({ ICR: toBN(dec(208, 16)), extraParams: { from: erin } })

    // Whale provides LUSD to the SP
    const spDeposit = A_totalDebt.add(B_totalDebt).add(C_totalDebt.div(toBN(2)))
    await openTrove({ ICR: toBN(dec(220, 16)), extraLUSDAmount: spDeposit, extraParams: { from: whale } })
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: whale })
    let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);

    // Price drops 
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()
    const TCR = await th.getTCR(contracts)

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check A, B, C troves are in range 110% < ICR < TCR
    const ICR_A = await troveManager.getCurrentICR(_aliceTroveId, price)
    const ICR_B = await troveManager.getCurrentICR(_bobTroveId, price)
    const ICR_C_Before = await troveManager.getCurrentICR(_carolTroveId, price)

    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C_Before.gt(mv._MCR) && ICR_C_Before.lt(TCR))

    /* Liquidate troves. Troves are ordered by ICR, from low to high:  A, B, C, D, E.
    With 253 in the SP, Alice (102 debt) and Bob (101 debt) should be entirely liquidated. 
    That leaves 50 LUSD in the Pool to absorb exactly half of Carol's debt (100) */
    await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from : whale});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(erin)), {from : erin});	
    await troveManager.liquidateSequentiallyInRecovery(10, {from: owner})

    const STATUS_C_After = await troveManager.getTroveStatus(_carolTroveId)
    assert.equal(STATUS_C_After.toString(), '3')
  })

  // TODO: LiquidateTroves tests that involve troves with ICR > TCR

  // --- batchLiquidateTroves() ---

  it("batchLiquidateTroves(): Liquidates all troves with ICR < 110%, transitioning Normal -> Recovery Mode", async () => {
    // make 6 Troves accordingly
    // --- SETUP ---
    const { totalDebt: B_totalDebt } = await openTrove({ ICR: toBN(dec(240, 16)), extraParams: { from: bob } })
    const { totalDebt: C_totalDebt } = await openTrove({ ICR: toBN(dec(240, 16)), extraParams: { from: carol } })
    const { totalDebt: D_totalDebt } = await openTrove({ ICR: toBN(dec(230, 16)), extraParams: { from: dennis } })
    const { totalDebt: E_totalDebt } = await openTrove({ ICR: toBN(dec(240, 16)), extraParams: { from: erin } })
    const { totalDebt: F_totalDebt } = await openTrove({ ICR: toBN(dec(240, 16)), extraParams: { from: freddy } })

    const spDeposit = B_totalDebt.add(C_totalDebt).add(D_totalDebt).add(E_totalDebt).add(F_totalDebt)
    await openTrove({ ICR: toBN(dec(426, 16)), extraLUSDAmount: spDeposit, extraParams: { from: alice } })
    let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);
    let _dennisTroveId = await sortedTroves.troveOfOwnerByIndex(dennis, 0);
    let _erinTroveId = await sortedTroves.troveOfOwnerByIndex(erin, 0);
    let _freddyTroveId = await sortedTroves.troveOfOwnerByIndex(freddy, 0);

    // Alice deposits LUSD to Stability Pool
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: alice })

    // price drops to 1ETH:85LUSD, reducing TCR below 150%
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

    Trove         ICR
    Alice       182%
    Bob         102%
    Carol       102%
    Dennis      102%
    Elisa       102%
    Freddy      102%
    */
    alice_ICR = await troveManager.getCurrentICR(_aliceTroveId, price)
    bob_ICR = await troveManager.getCurrentICR(_bobTroveId, price)
    carol_ICR = await troveManager.getCurrentICR(_carolTroveId, price)
    dennis_ICR = await troveManager.getCurrentICR(_dennisTroveId, price)
    erin_ICR = await troveManager.getCurrentICR(_erinTroveId, price)
    freddy_ICR = await troveManager.getCurrentICR(_freddyTroveId, price)

    // Alice should have ICR > 150%
    assert.isTrue(alice_ICR.gt(_150percent))
    // All other Troves should have ICR < 150%
    assert.isTrue(carol_ICR.lt(_150percent))
    assert.isTrue(dennis_ICR.lt(_150percent))
    assert.isTrue(erin_ICR.lt(_150percent))
    assert.isTrue(freddy_ICR.lt(_150percent))

    /* After liquidating Bob and Carol, the the TCR of the system rises above the CCR, to 154%.  
    (see calculations in Google Sheet)

    Liquidations continue until all Troves with ICR < MCR have been closed. 
    Only Alice should remain active - all others should be closed. */

    // call batchLiquidateTroves
    await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from : whale});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(erin)), {from : erin});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(freddy)), {from : freddy});
    await troveManager.liquidateInBatchRecovery([_aliceTroveId, _bobTroveId, _carolTroveId, _dennisTroveId, _erinTroveId, _freddyTroveId], {from: owner});

    // check system is no longer in Recovery Mode
    const recoveryMode_After = await th.checkRecoveryMode(contracts)
    assert.isFalse(recoveryMode_After)

    // After liquidation, TCR should rise to above 150%. 
    const TCR_After = await th.getTCR(contracts)
    assert.isTrue(TCR_After.gt(_150percent))

    // get all Troves
    const alice_Trove = await troveManager.Troves(_aliceTroveId)
    const bob_Trove = await troveManager.Troves(_bobTroveId)
    const carol_Trove = await troveManager.Troves(_carolTroveId)
    const dennis_Trove = await troveManager.Troves(_dennisTroveId)
    const erin_Trove = await troveManager.Troves(_erinTroveId)
    const freddy_Trove = await troveManager.Troves(_freddyTroveId)

    // check that Alice's Trove remains active
    assert.equal(alice_Trove[3], 1)
    assert.isTrue(await sortedTroves.contains(_aliceTroveId))

    // check all other Troves are liquidated
    assert.equal(bob_Trove[3], 3)
    assert.equal(carol_Trove[3], 3)
    assert.equal(dennis_Trove[3], 3)
    assert.equal(erin_Trove[3], 3)
    assert.equal(freddy_Trove[3], 3)

    assert.isFalse(await sortedTroves.contains(_bobTroveId))
    assert.isFalse(await sortedTroves.contains(_carolTroveId))
    assert.isFalse(await sortedTroves.contains(_dennisTroveId))
    assert.isFalse(await sortedTroves.contains(_erinTroveId))
    assert.isFalse(await sortedTroves.contains(_freddyTroveId))
  })

  it("batchLiquidateTroves(): Liquidates all troves with ICR < 110%, transitioning Recovery -> Normal Mode", async () => {
    /* This is essentially the same test as before, but changing the order of the batch,
     * now the remaining trove (alice) goes at the end.
     * This way alice will be skipped in a different part of the code, as in the previous test,
     * when attempting alice the system was in Recovery mode, while in this test,
     * when attempting alice the system has gone back to Normal mode
     * (see function `_getTotalFromBatchLiquidate_RecoveryMode`)
     */
    // make 6 Troves accordingly
    // --- SETUP ---

    const { totalDebt: B_totalDebt } = await openTrove({ ICR: toBN(dec(240, 16)), extraParams: { from: bob } })
    const { totalDebt: C_totalDebt } = await openTrove({ ICR: toBN(dec(240, 16)), extraParams: { from: carol } })
    const { totalDebt: D_totalDebt } = await openTrove({ ICR: toBN(dec(230, 16)), extraParams: { from: dennis } })
    const { totalDebt: E_totalDebt } = await openTrove({ ICR: toBN(dec(240, 16)), extraParams: { from: erin } })
    const { totalDebt: F_totalDebt } = await openTrove({ ICR: toBN(dec(240, 16)), extraParams: { from: freddy } })

    const spDeposit = B_totalDebt.add(C_totalDebt).add(D_totalDebt).add(E_totalDebt).add(F_totalDebt)
    await openTrove({ ICR: toBN(dec(426, 16)), extraLUSDAmount: spDeposit, extraParams: { from: alice } })
    let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);
    let _dennisTroveId = await sortedTroves.troveOfOwnerByIndex(dennis, 0);
    let _erinTroveId = await sortedTroves.troveOfOwnerByIndex(erin, 0);
    let _freddyTroveId = await sortedTroves.troveOfOwnerByIndex(freddy, 0);

    // Alice deposits LUSD to Stability Pool
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: alice })

    // price drops to 1ETH:85LUSD, reducing TCR below 150%
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

    Trove         ICR
    Alice       182%
    Bob         102%
    Carol       102%
    Dennis      102%
    Elisa       102%
    Freddy      102%
    */
    const alice_ICR = await troveManager.getCurrentICR(_aliceTroveId, price)
    const bob_ICR = await troveManager.getCurrentICR(_bobTroveId, price)
    const carol_ICR = await troveManager.getCurrentICR(_carolTroveId, price)
    const dennis_ICR = await troveManager.getCurrentICR(_dennisTroveId, price)
    const erin_ICR = await troveManager.getCurrentICR(_erinTroveId, price)
    const freddy_ICR = await troveManager.getCurrentICR(_freddyTroveId, price)

    // Alice should have ICR > 150%
    assert.isTrue(alice_ICR.gt(_150percent))
    // All other Troves should have ICR < 150%
    assert.isTrue(carol_ICR.lt(_150percent))
    assert.isTrue(dennis_ICR.lt(_150percent))
    assert.isTrue(erin_ICR.lt(_150percent))
    assert.isTrue(freddy_ICR.lt(_150percent))

    /* After liquidating Bob and Carol, the the TCR of the system rises above the CCR, to 154%.  
    (see calculations in Google Sheet)

    Liquidations continue until all Troves with ICR < MCR have been closed. 
    Only Alice should remain active - all others should be closed. */

    // call batchLiquidateTroves
    await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from : whale});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(erin)), {from : erin});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(freddy)), {from : freddy});
    await troveManager.liquidateInBatchRecovery([_bobTroveId, _carolTroveId, _dennisTroveId, _erinTroveId, _freddyTroveId, _aliceTroveId], {from: owner});

    // check system is no longer in Recovery Mode
    const recoveryMode_After = await th.checkRecoveryMode(contracts)
    assert.isFalse(recoveryMode_After)

    // After liquidation, TCR should rise to above 150%. 
    const TCR_After = await th.getTCR(contracts)
    assert.isTrue(TCR_After.gt(_150percent))

    // get all Troves
    const alice_Trove = await troveManager.Troves(_aliceTroveId)
    const bob_Trove = await troveManager.Troves(_bobTroveId)
    const carol_Trove = await troveManager.Troves(_carolTroveId)
    const dennis_Trove = await troveManager.Troves(_dennisTroveId)
    const erin_Trove = await troveManager.Troves(_erinTroveId)
    const freddy_Trove = await troveManager.Troves(_freddyTroveId)

    // check that Alice's Trove remains active
    assert.equal(alice_Trove[3], 1)
    assert.isTrue(await sortedTroves.contains(_aliceTroveId))

    // check all other Troves are liquidated
    assert.equal(bob_Trove[3], 3)
    assert.equal(carol_Trove[3], 3)
    assert.equal(dennis_Trove[3], 3)
    assert.equal(erin_Trove[3], 3)
    assert.equal(freddy_Trove[3], 3)

    assert.isFalse(await sortedTroves.contains(_bobTroveId))
    assert.isFalse(await sortedTroves.contains(_carolTroveId))
    assert.isFalse(await sortedTroves.contains(_dennisTroveId))
    assert.isFalse(await sortedTroves.contains(_erinTroveId))
    assert.isFalse(await sortedTroves.contains(_freddyTroveId))
  })

  it("batchLiquidateTroves(): Liquidates all troves with ICR < 110%, transitioning Normal -> Recovery Mode", async () => {
    // This is again the same test as the before the last one, but now Alice is skipped because she is not active
    // It also skips bob, as he is added twice, for being already liquidated
    // make 6 Troves accordingly
    // --- SETUP ---
    const { totalDebt: B_totalDebt } = await openTrove({ ICR: toBN(dec(240, 16)), extraParams: { from: bob } })
    const { totalDebt: C_totalDebt } = await openTrove({ ICR: toBN(dec(240, 16)), extraParams: { from: carol } })
    const { totalDebt: D_totalDebt } = await openTrove({ ICR: toBN(dec(230, 16)), extraParams: { from: dennis } })
    const { totalDebt: E_totalDebt } = await openTrove({ ICR: toBN(dec(240, 16)), extraParams: { from: erin } })
    const { totalDebt: F_totalDebt } = await openTrove({ ICR: toBN(dec(240, 16)), extraParams: { from: freddy } })

    const spDeposit = B_totalDebt.add(C_totalDebt).add(D_totalDebt).add(E_totalDebt).add(F_totalDebt)
    const { totalDebt: A_totalDebt } = await openTrove({ ICR: toBN(dec(426, 16)), extraLUSDAmount: spDeposit, extraParams: { from: alice } })
    await openTrove({ ICR: toBN(dec(426, 16)), extraLUSDAmount: A_totalDebt, extraParams: { from: whale } })
    let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);
    let _dennisTroveId = await sortedTroves.troveOfOwnerByIndex(dennis, 0);
    let _erinTroveId = await sortedTroves.troveOfOwnerByIndex(erin, 0);
    let _freddyTroveId = await sortedTroves.troveOfOwnerByIndex(freddy, 0);

    // Alice deposits LUSD to Stability Pool
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: alice })

    // to compensate borrowing fee
    await lusdToken.transfer(alice, A_totalDebt, { from: whale })
    // Deprecated Alice closes trove. If trove closed, ntohing to liquidate later
    await borrowerOperations.closeTrove(_aliceTroveId, { from: alice })

    // price drops to 1ETH:85LUSD, reducing TCR below 150%
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

    Trove         ICR
    Alice       182%
    Bob         102%
    Carol       102%
    Dennis      102%
    Elisa       102%
    Freddy      102%
    */
    //alice_ICR = await troveManager.getCurrentICR(_aliceTroveId, price)
    bob_ICR = await troveManager.getCurrentICR(_bobTroveId, price)
    carol_ICR = await troveManager.getCurrentICR(_carolTroveId, price)
    dennis_ICR = await troveManager.getCurrentICR(_dennisTroveId, price)
    erin_ICR = await troveManager.getCurrentICR(_erinTroveId, price)
    freddy_ICR = await troveManager.getCurrentICR(_freddyTroveId, price)

    // Alice should have ICR > 150%
    //assert.isTrue(alice_ICR.gt(_150percent))
    // All other Troves should have ICR < 150%
    assert.isTrue(carol_ICR.lt(_150percent))
    assert.isTrue(dennis_ICR.lt(_150percent))
    assert.isTrue(erin_ICR.lt(_150percent))
    assert.isTrue(freddy_ICR.lt(_150percent))

    /* After liquidating Bob and Carol, the the TCR of the system rises above the CCR, to 154%.
    (see calculations in Google Sheet)

    Liquidations continue until all Troves with ICR < MCR have been closed.
    Only Alice should remain active - all others should be closed. */

    // call batchLiquidateTroves
    await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from : whale});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(erin)), {from : erin});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(freddy)), {from : freddy});
    await troveManager.liquidateInBatchRecovery([_aliceTroveId, _bobTroveId, _carolTroveId, _dennisTroveId, _erinTroveId, _freddyTroveId], {from: owner});

    // check system is no longer in Recovery Mode
    const recoveryMode_After = await th.checkRecoveryMode(contracts)
    assert.isFalse(recoveryMode_After)

    // After liquidation, TCR should rise to above 150%.
    const TCR_After = await th.getTCR(contracts)
    assert.isTrue(TCR_After.gt(_150percent))

    // get all Troves
    const alice_Trove = await troveManager.Troves(_aliceTroveId)
    const bob_Trove = await troveManager.Troves(_bobTroveId)
    const carol_Trove = await troveManager.Troves(_carolTroveId)
    const dennis_Trove = await troveManager.Troves(_dennisTroveId)
    const erin_Trove = await troveManager.Troves(_erinTroveId)
    const freddy_Trove = await troveManager.Troves(_freddyTroveId)

    // check that Alice's Trove is closed
    assert.equal(alice_Trove[3], 2)

    // check all other Troves are liquidated
    assert.equal(bob_Trove[3], 3)
    assert.equal(carol_Trove[3], 3)
    assert.equal(dennis_Trove[3], 3)
    assert.equal(erin_Trove[3], 3)
    assert.equal(freddy_Trove[3], 3)

    assert.isFalse(await sortedTroves.contains(_bobTroveId))
    assert.isFalse(await sortedTroves.contains(_carolTroveId))
    assert.isFalse(await sortedTroves.contains(_dennisTroveId))
    assert.isFalse(await sortedTroves.contains(_erinTroveId))
    assert.isFalse(await sortedTroves.contains(_freddyTroveId))
  })

  it("batchLiquidateTroves() with a non fullfilled liquidation: non liquidated trove remains active", async () => {
    const { totalDebt: A_totalDebt } = await openTrove({ ICR: toBN(dec(211, 16)), extraParams: { from: alice } })
    const { totalDebt: B_totalDebt } = await openTrove({ ICR: toBN(dec(212, 16)), extraParams: { from: bob } })
    const { totalDebt: C_totalDebt } = await openTrove({ ICR: toBN(dec(210, 16)), extraParams: { from: carol } })
    await openTrove({ ICR: toBN(dec(219, 16)), extraParams: { from: dennis } })
    await openTrove({ ICR: toBN(dec(221, 16)), extraParams: { from: erin } })

    // Whale provides LUSD to the SP
    const spDeposit = A_totalDebt.add(B_totalDebt).add(C_totalDebt.div(toBN(2)))
    await openTrove({ ICR: toBN(dec(220, 16)), extraLUSDAmount: spDeposit, extraParams: { from: whale } })
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: whale })
    let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);

    // Price drops 
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()
    const TCR = await th.getTCR(contracts)

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check A, B, C troves are in range 110% < ICR < TCR
    const ICR_A = await troveManager.getCurrentICR(_aliceTroveId, price)
    const ICR_B = await troveManager.getCurrentICR(_bobTroveId, price)
    const ICR_C = await troveManager.getCurrentICR(_carolTroveId, price)

    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C.gt(mv._MCR) && ICR_C.lt(TCR))

    const trovesToLiquidate = [_aliceTroveId, _bobTroveId, _carolTroveId]
    await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from : whale});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await troveManager.liquidateInBatchRecovery(trovesToLiquidate, {from: owner})

    // Check A and B closed
    assert.isFalse(await sortedTroves.contains(_aliceTroveId))
    assert.isFalse(await sortedTroves.contains(_bobTroveId))

    // Check C remains active
    assert.isFalse(await sortedTroves.contains(_carolTroveId))
    assert.equal((await troveManager.Troves(_carolTroveId))[3].toString(), '3') // check Status is closedByLiquidation
  })

  it("batchLiquidateTroves() with a non fullfilled liquidation: non liquidated trove remains in Trove Owners array", async () => {
    const { totalDebt: A_totalDebt } = await openTrove({ ICR: toBN(dec(211, 16)), extraParams: { from: alice } })
    const { totalDebt: B_totalDebt } = await openTrove({ ICR: toBN(dec(212, 16)), extraParams: { from: bob } })
    const { totalDebt: C_totalDebt } = await openTrove({ ICR: toBN(dec(210, 16)), extraParams: { from: carol } })
    await openTrove({ ICR: toBN(dec(219, 16)), extraParams: { from: dennis } })
    await openTrove({ ICR: toBN(dec(221, 16)), extraParams: { from: erin } })

    // Whale provides LUSD to the SP
    const spDeposit = A_totalDebt.add(B_totalDebt).add(C_totalDebt.div(toBN(2)))
    await openTrove({ ICR: toBN(dec(220, 16)), extraLUSDAmount: spDeposit, extraParams: { from: whale } })
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: whale })
    let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);

    // Price drops 
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()
    const TCR = await th.getTCR(contracts)

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check A, B, C troves are in range 110% < ICR < TCR
    const ICR_A = await troveManager.getCurrentICR(_aliceTroveId, price)
    const ICR_B = await troveManager.getCurrentICR(_bobTroveId, price)
    const ICR_C = await troveManager.getCurrentICR(_carolTroveId, price)

    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C.gt(mv._MCR) && ICR_C.lt(TCR))

    const trovesToLiquidate = [_aliceTroveId, _bobTroveId, _carolTroveId]
    await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from : whale});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await troveManager.liquidateInBatchRecovery(trovesToLiquidate, {from: owner})

    // Check C is in Trove owners array
    const arrayLength = (await troveManager.getTroveIdsCount()).toNumber()
    let addressFound = false;
    let addressIdx = 0;

    for (let i = 0; i < arrayLength; i++) {
      const address = (await troveManager.TroveIds(i)).toString()
      if (address == _carolTroveId) {
        addressFound = true
        addressIdx = i
      }
    }

    assert.isFalse(addressFound);

    // Check TroveOwners idx on trove struct == idx of address found in TroveOwners array
    //const idxOnStruct = (await troveManager.Troves(_carolTroveId))[4].toString()
    //assert.equal(addressIdx.toString(), idxOnStruct)
  })

  it("batchLiquidateTroves() with a non fullfilled liquidation: still can liquidate further troves after the non-liquidated, emptied pool", async () => {
    const { totalDebt: A_totalDebt } = await openTrove({ ICR: toBN(dec(196, 16)), extraParams: { from: alice } })
    const { totalDebt: B_totalDebt } = await openTrove({ ICR: toBN(dec(198, 16)), extraParams: { from: bob } })
    const { totalDebt: D_totalDebt } = await openTrove({ ICR: toBN(dec(206, 16)), extraParams: { from: dennis } })
    const { totalDebt: C_totalDebt } = await openTrove({ ICR: toBN(dec(200, 16)), extraLUSDAmount: D_totalDebt, extraParams: { from: carol } })
    await openTrove({ ICR: toBN(dec(208, 16)), extraParams: { from: erin } })
    let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);
    let _dennisTroveId = await sortedTroves.troveOfOwnerByIndex(dennis, 0);
    let _erinTroveId = await sortedTroves.troveOfOwnerByIndex(erin, 0);

    // Whale provides LUSD to the SP
    const spDeposit = A_totalDebt.add(B_totalDebt).add(C_totalDebt.div(toBN(2)))
    await openTrove({ ICR: toBN(dec(220, 16)), extraLUSDAmount: spDeposit, extraParams: { from: whale } })
    let _whaleTroveId = await sortedTroves.troveOfOwnerByIndex(whale, 0);
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: whale })

    // Price drops 
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()
    const TCR = await th.getTCR(contracts)

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check A, B, C, D, E troves are in range 110% < ICR < TCR
    const ICR_A = await troveManager.getCurrentICR(_aliceTroveId, price)
    const ICR_B = await troveManager.getCurrentICR(_bobTroveId, price)
    const ICR_C = await troveManager.getCurrentICR(_carolTroveId, price)
    const ICR_D = await troveManager.getCurrentICR(_dennisTroveId, price)
    const ICR_E = await troveManager.getCurrentICR(_erinTroveId, price)

    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C.gt(mv._MCR) && ICR_C.lt(TCR))
    assert.isTrue(ICR_D.gt(mv._MCR) && ICR_D.lt(TCR))
    assert.isTrue(ICR_E.gt(mv._MCR) && ICR_E.lt(TCR))

    /* With 300 in the SP, Alice (102 debt) and Bob (101 debt) should be entirely liquidated.
     That leaves 97 LUSD in the Pool that won’t be enough to absorb Carol,
     but it will be enough to liquidate Dennis. Afterwards the pool will be empty,
     so Erin won’t liquidated. */
    const trovesToLiquidate = [_aliceTroveId, _bobTroveId, _carolTroveId, _dennisTroveId, _erinTroveId]
    await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from : whale});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(erin)), {from : erin});
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});
    const tx = await troveManager.liquidateInBatchRecovery(trovesToLiquidate, {from: owner})
    console.log('gasUsed: ', tx.receipt.gasUsed)

    // Check A, B and D are closed
    assert.isFalse(await sortedTroves.contains(_aliceTroveId))
    assert.isFalse(await sortedTroves.contains(_bobTroveId))
    assert.isFalse(await sortedTroves.contains(_dennisTroveId))

    // Check whale, C, D and E stay active
    assert.isTrue(await sortedTroves.contains(_whaleTroveId))
    assert.isFalse(await sortedTroves.contains(_carolTroveId))
    assert.isFalse(await sortedTroves.contains(_erinTroveId))
  })

  it("batchLiquidateTroves() with a non fullfilled liquidation: still can liquidate further troves after the non-liquidated, non emptied pool", async () => {
    const { totalDebt: A_totalDebt } = await openTrove({ ICR: toBN(dec(196, 16)), extraParams: { from: alice } })
    const { totalDebt: B_totalDebt } = await openTrove({ ICR: toBN(dec(198, 16)), extraParams: { from: bob } })
    const { totalDebt: D_totalDebt } = await openTrove({ ICR: toBN(dec(206, 16)), extraParams: { from: dennis } })
    const { totalDebt: C_totalDebt } = await openTrove({ ICR: toBN(dec(200, 16)), extraLUSDAmount: D_totalDebt, extraParams: { from: carol } })
    await openTrove({ ICR: toBN(dec(208, 16)), extraParams: { from: erin } })
    let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);
    let _dennisTroveId = await sortedTroves.troveOfOwnerByIndex(dennis, 0);
    let _erinTroveId = await sortedTroves.troveOfOwnerByIndex(erin, 0);

    // Whale provides LUSD to the SP
    const spDeposit = A_totalDebt.add(B_totalDebt).add(C_totalDebt.div(toBN(2)))
    await openTrove({ ICR: toBN(dec(220, 16)), extraLUSDAmount: spDeposit, extraParams: { from: whale } })
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: whale })
    let _whaleTroveId = await sortedTroves.troveOfOwnerByIndex(whale, 0);

    // Price drops 
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()
    const TCR = await th.getTCR(contracts)

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check A, B, C, D, E troves are in range 110% < ICR < TCR
    const ICR_A = await troveManager.getCurrentICR(_aliceTroveId, price)
    const ICR_B = await troveManager.getCurrentICR(_bobTroveId, price)
    const ICR_C = await troveManager.getCurrentICR(_carolTroveId, price)
    const ICR_D = await troveManager.getCurrentICR(_dennisTroveId, price)
    const ICR_E = await troveManager.getCurrentICR(_erinTroveId, price)

    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C.gt(mv._MCR) && ICR_C.lt(TCR))
    assert.isTrue(ICR_D.gt(mv._MCR) && ICR_D.lt(TCR))
    assert.isTrue(ICR_E.gt(mv._MCR) && ICR_E.lt(TCR))

    /* With 301 in the SP, Alice (102 debt) and Bob (101 debt) should be entirely liquidated.
     That leaves 97 LUSD in the Pool that won’t be enough to absorb Carol,
     but it will be enough to liquidate Dennis. Afterwards the pool will be empty,
     so Erin won’t liquidated.
     Note that, compared to the previous test, this one will make 1 more loop iteration,
     so it will consume more gas. */
    const trovesToLiquidate = [_aliceTroveId, _bobTroveId, _carolTroveId, _dennisTroveId, _erinTroveId]
    await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from : whale});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(erin)), {from : erin});
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});
    const tx = await troveManager.liquidateInBatchRecovery(trovesToLiquidate, {from: owner})
    console.log('gasUsed: ', tx.receipt.gasUsed)

    // Check A, B and D are closed
    assert.isFalse(await sortedTroves.contains(_aliceTroveId))
    assert.isFalse(await sortedTroves.contains(_bobTroveId))
    assert.isFalse(await sortedTroves.contains(_dennisTroveId))

    // Check whale, C, D and E stay active
    assert.isTrue(await sortedTroves.contains(_whaleTroveId))
    assert.isFalse(await sortedTroves.contains(_carolTroveId))
    assert.isFalse(await sortedTroves.contains(_erinTroveId))
  })

  it("batchLiquidateTroves() with a non fullfilled liquidation: total liquidated coll and debt is correct", async () => {
    const { collateral: A_coll, totalDebt: A_totalDebt } = await openTrove({ ICR: toBN(dec(196, 16)), extraParams: { from: alice } })
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openTrove({ ICR: toBN(dec(198, 16)), extraParams: { from: bob } })
    const { collateral: C_coll, totalDebt: C_totalDebt } = await openTrove({ ICR: toBN(dec(200, 16)), extraParams: { from: carol } })
    const { collateral: D_coll, totalDebt: D_totalDebt } = await openTrove({ ICR: toBN(dec(206, 16)), extraParams: { from: dennis } })
    const { collateral: E_coll, totalDebt: E_totalDebt } = await openTrove({ ICR: toBN(dec(208, 16)), extraParams: { from: erin } })

    // Whale provides LUSD to the SP
    const spDeposit = A_totalDebt.add(B_totalDebt).add(C_totalDebt.div(toBN(2)))
    await openTrove({ ICR: toBN(dec(220, 16)), extraLUSDAmount: spDeposit, extraParams: { from: whale } })
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: whale })
    let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);

    // Price drops 
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()
    const TCR = await th.getTCR(contracts)

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check A, B, C, D, E troves are in range 110% < ICR < TCR
    const ICR_A = await troveManager.getCurrentICR(_aliceTroveId, price)
    const ICR_B = await troveManager.getCurrentICR(_bobTroveId, price)
    const ICR_C = await troveManager.getCurrentICR(_carolTroveId, price)

    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C.gt(mv._MCR) && ICR_C.lt(TCR))

    const entireSystemCollBefore = await troveManager.getEntireSystemColl()
    const entireSystemDebtBefore = await troveManager.getEntireSystemDebt()

    const trovesToLiquidate = [_aliceTroveId, _bobTroveId, _carolTroveId]
    await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from : whale});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await troveManager.liquidateInBatchRecovery(trovesToLiquidate, {from: owner})

    // Expect system debt reduced by 203 LUSD and system coll by 2 ETH
    const entireSystemCollAfter = await troveManager.getEntireSystemColl()
    const entireSystemDebtAfter = await troveManager.getEntireSystemDebt()

    const changeInEntireSystemColl = entireSystemCollBefore.sub(entireSystemCollAfter)
    const changeInEntireSystemDebt = entireSystemDebtBefore.sub(entireSystemDebtAfter)

    assert.equal(changeInEntireSystemColl.toString(), A_coll.add(B_coll).add(C_coll).toString())
    th.assertIsApproximatelyEqual(changeInEntireSystemDebt.toString(), A_totalDebt.add(B_totalDebt).add(C_totalDebt).toString())
  })

  it("batchLiquidateTroves() with a non fullfilled liquidation: emits correct liquidation event values", async () => {
    const { collateral: A_coll, totalDebt: A_totalDebt } = await openTrove({ ICR: toBN(dec(210, 16)), extraParams: { from: alice } })
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openTrove({ ICR: toBN(dec(211, 16)), extraParams: { from: bob } })
    const { totalDebt: C_totalDebt } = await openTrove({ ICR: toBN(dec(212, 16)), extraParams: { from: carol } })
    await openTrove({ ICR: toBN(dec(219, 16)), extraParams: { from: dennis } })
    await openTrove({ ICR: toBN(dec(221, 16)), extraParams: { from: erin } })
    let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);

    // Whale provides LUSD to the SP
    const spDeposit = A_totalDebt.add(B_totalDebt).add(C_totalDebt.div(toBN(2)))
    await openTrove({ ICR: toBN(dec(220, 16)), extraLUSDAmount: spDeposit, extraParams: { from: whale } })
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: whale })

    // Price drops 
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()
    const TCR = await th.getTCR(contracts)

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check A, B, C troves are in range 110% < ICR < TCR
    const ICR_A = await troveManager.getCurrentICR(_aliceTroveId, price)
    const ICR_B = await troveManager.getCurrentICR(_bobTroveId, price)
    const ICR_C = await troveManager.getCurrentICR(_carolTroveId, price)

    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C.gt(mv._MCR) && ICR_C.lt(TCR))

    const trovesToLiquidate = [_aliceTroveId, _bobTroveId, _carolTroveId]
    await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from : whale});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    const liquidationTx = await troveManager.liquidateInBatchRecovery(trovesToLiquidate, {from: owner})

    const [liquidatedDebt, liquidatedColl, collGasComp, lusdGasComp] = th.getEmittedLiquidationValues(liquidationTx)

    th.assertIsApproximatelyEqual(liquidatedDebt, A_totalDebt.add(B_totalDebt).add(C_totalDebt))
    const equivalentColl = A_totalDebt.add(B_totalDebt).add(C_totalDebt).mul(toBN(dec(11, 17))).div(price)
    th.assertIsApproximatelyEqual(liquidatedColl, equivalentColl)
    assert.equal(collGasComp.toString(), '0') // 0.5% of 283/120*1.1
    assert.equal(lusdGasComp.toString(), '0')

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

  it("batchLiquidateTroves() with a non fullfilled liquidation: ICR of non liquidated trove does not change", async () => {
    const { totalDebt: A_totalDebt } = await openTrove({ ICR: toBN(dec(211, 16)), extraParams: { from: alice } })
    const { totalDebt: B_totalDebt } = await openTrove({ ICR: toBN(dec(212, 16)), extraParams: { from: bob } })
    const { totalDebt: C_totalDebt } = await openTrove({ ICR: toBN(dec(210, 16)), extraParams: { from: carol } })
    await openTrove({ ICR: toBN(dec(219, 16)), extraParams: { from: dennis } })
    await openTrove({ ICR: toBN(dec(221, 16)), extraParams: { from: erin } })
    let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);

    // Whale provides LUSD to the SP
    const spDeposit = A_totalDebt.add(B_totalDebt).add(C_totalDebt.div(toBN(2)))
    await openTrove({ ICR: toBN(dec(220, 16)), extraLUSDAmount: spDeposit, extraParams: { from: whale } })
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: whale })

    // Price drops 
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()
    const TCR = await th.getTCR(contracts)

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check A, B, C troves are in range 110% < ICR < TCR
    const ICR_A = await troveManager.getCurrentICR(_aliceTroveId, price)
    const ICR_B = await troveManager.getCurrentICR(_bobTroveId, price)
    const ICR_C_Before = await troveManager.getCurrentICR(_carolTroveId, price)

    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C_Before.gt(mv._MCR) && ICR_C_Before.lt(TCR))

    const trovesToLiquidate = [_aliceTroveId, _bobTroveId, _carolTroveId]
    await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from : whale});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await troveManager.liquidateInBatchRecovery(trovesToLiquidate, {from: owner})

    const STATUS_C_After = await troveManager.getTroveStatus(_carolTroveId)
    assert.equal(STATUS_C_After.toString(), '3')
  })

  it("batchLiquidateTroves(), with 110% < ICR < TCR, and StabilityPool LUSD > debt to liquidate: can liquidate troves out of order", async () => {
    const { totalDebt: A_totalDebt } = await openTrove({ ICR: toBN(dec(200, 16)), extraParams: { from: alice } })
    const { totalDebt: B_totalDebt } = await openTrove({ ICR: toBN(dec(202, 16)), extraParams: { from: bob } })
    const { totalDebt: C_totalDebt } = await openTrove({ ICR: toBN(dec(204, 16)), extraParams: { from: carol } })
    const { totalDebt: D_totalDebt } = await openTrove({ ICR: toBN(dec(206, 16)), extraParams: { from: dennis } })
    await openTrove({ ICR: toBN(dec(280, 16)), extraLUSDAmount: dec(500, 18), extraParams: { from: erin } })
    await openTrove({ ICR: toBN(dec(282, 16)), extraLUSDAmount: dec(500, 18), extraParams: { from: freddy } })
    let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);
    let _dennisTroveId = await sortedTroves.troveOfOwnerByIndex(dennis, 0);

    // Whale provides 1000 LUSD to the SP
    const spDeposit = A_totalDebt.add(C_totalDebt).add(D_totalDebt)
    await openTrove({ ICR: toBN(dec(219, 16)), extraLUSDAmount: spDeposit, extraParams: { from: whale } })
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: whale })

    // Price drops
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check troves A-D are in range 110% < ICR < TCR
    const ICR_A = await troveManager.getCurrentICR(_aliceTroveId, price)
    const ICR_B = await troveManager.getCurrentICR(_bobTroveId, price)
    const ICR_C = await troveManager.getCurrentICR(_carolTroveId, price)
    const ICR_D = await troveManager.getCurrentICR(_dennisTroveId, price)
    const TCR = await th.getTCR(contracts)

    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C.gt(mv._MCR) && ICR_C.lt(TCR))
    assert.isTrue(ICR_D.gt(mv._MCR) && ICR_D.lt(TCR))

    // Troves are ordered by ICR, low to high: A, B, C, D.

    // Liquidate out of ICR order: D, B, C. A (lowest ICR) not included.
    const trovesToLiquidate = [_dennisTroveId, _bobTroveId, _carolTroveId]

    await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from : whale});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});
    const liquidationTx = await troveManager.liquidateInBatchRecovery(trovesToLiquidate, {from: owner})

    // Check transaction succeeded
    assert.isTrue(liquidationTx.receipt.status)

    // Confirm troves D, B, C removed
    assert.isFalse(await sortedTroves.contains(_dennisTroveId))
    assert.isFalse(await sortedTroves.contains(_bobTroveId))
    assert.isFalse(await sortedTroves.contains(_carolTroveId))

    // Confirm troves have status 'liquidated' (Status enum element idx 3)
    assert.equal((await troveManager.Troves(_dennisTroveId))[3], '3')
    assert.equal((await troveManager.Troves(_bobTroveId))[3], '3')
    assert.equal((await troveManager.Troves(_carolTroveId))[3], '3')
  })

  it("batchLiquidateTroves(), with 110% < ICR < TCR, and StabilityPool empty: doesn't liquidate any troves", async () => {
    await openTrove({ ICR: toBN(dec(222, 16)), extraParams: { from: alice } })
    const { totalDebt: bobDebt_Before } = await openTrove({ ICR: toBN(dec(224, 16)), extraParams: { from: bob } })
    const { totalDebt: carolDebt_Before } = await openTrove({ ICR: toBN(dec(226, 16)), extraParams: { from: carol } })
    const { totalDebt: dennisDebt_Before } = await openTrove({ ICR: toBN(dec(228, 16)), extraParams: { from: dennis } })
    let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);
    let _dennisTroveId = await sortedTroves.troveOfOwnerByIndex(dennis, 0);

    const bobColl_Before = (await troveManager.Troves(_bobTroveId))[1]
    const carolColl_Before = (await troveManager.Troves(_carolTroveId))[1]
    const dennisColl_Before = (await troveManager.Troves(_dennisTroveId))[1]

    await openTrove({ ICR: toBN(dec(228, 16)), extraParams: { from: erin } })
    await openTrove({ ICR: toBN(dec(230, 16)), extraParams: { from: freddy } })

    // Price drops
    await priceFeed.setPrice(dec(120, 18))
    const price = await priceFeed.getPrice()
    const TCR = await th.getTCR(contracts)

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check troves A-D are in range 110% < ICR < TCR
    const ICR_A = await troveManager.getCurrentICR(_aliceTroveId, price)
    const ICR_B = await troveManager.getCurrentICR(_bobTroveId, price)
    const ICR_C = await troveManager.getCurrentICR(_carolTroveId, price)

    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C.gt(mv._MCR) && ICR_C.lt(TCR))

    // Troves are ordered by ICR, low to high: A, B, C, D. 
    // Liquidate out of ICR order: D, B, C. A (lowest ICR) not included.
    const trovesToLiquidate = [_dennisTroveId, _bobTroveId, _carolTroveId]
    //await assertRevert(troveManager.batchLiquidateTroves(trovesToLiquidate), "TroveManager: nothing to liquidate")

    // Confirm troves D, B, C remain in system
    assert.isTrue(await sortedTroves.contains(_dennisTroveId))
    assert.isTrue(await sortedTroves.contains(_bobTroveId))
    assert.isTrue(await sortedTroves.contains(_carolTroveId))

    // Confirm troves have status 'active' (Status enum element idx 1)
    assert.equal((await troveManager.Troves(_dennisTroveId))[3], '1')
    assert.equal((await troveManager.Troves(_bobTroveId))[3], '1')
    assert.equal((await troveManager.Troves(_carolTroveId))[3], '1')

    // Confirm D, B, C coll & debt have not changed
    const dennisDebt_After = (await troveManager.Troves(_dennisTroveId))[0].add(await troveManager.getPendingLUSDDebtReward(dennis))
    const bobDebt_After = (await troveManager.Troves(_bobTroveId))[0].add(await troveManager.getPendingLUSDDebtReward(bob))
    const carolDebt_After = (await troveManager.Troves(_carolTroveId))[0].add(await troveManager.getPendingLUSDDebtReward(carol))

    const dennisColl_After = (await troveManager.Troves(_dennisTroveId))[1].add(await troveManager.getPendingETHReward(dennis))  
    const bobColl_After = (await troveManager.Troves(_bobTroveId))[1].add(await troveManager.getPendingETHReward(bob))
    const carolColl_After = (await troveManager.Troves(_carolTroveId))[1].add(await troveManager.getPendingETHReward(carol))

    assert.isTrue(dennisColl_After.eq(dennisColl_Before))
    assert.isTrue(bobColl_After.eq(bobColl_Before))
    assert.isTrue(carolColl_After.eq(carolColl_Before))

    th.assertIsApproximatelyEqual(th.toBN(dennisDebt_Before).toString(), dennisDebt_After.toString())
    th.assertIsApproximatelyEqual(th.toBN(bobDebt_Before).toString(), bobDebt_After.toString())
    th.assertIsApproximatelyEqual(th.toBN(carolDebt_Before).toString(), carolDebt_After.toString())
  })

  it('batchLiquidateTroves(): skips liquidation of troves with ICR > TCR, regardless of Stability Pool size', async () => {
    // Troves that will fall into ICR range 100-MCR
    const { totalDebt: A_totalDebt } = await openTrove({ ICR: toBN(dec(194, 16)), extraParams: { from: A } })
    const { totalDebt: B_totalDebt } = await openTrove({ ICR: toBN(dec(196, 16)), extraParams: { from: B } })
    const { totalDebt: C_totalDebt } = await openTrove({ ICR: toBN(dec(198, 16)), extraParams: { from: C } })

    // Troves that will fall into ICR range 110-TCR
    const { totalDebt: D_totalDebt } = await openTrove({ ICR: toBN(dec(221, 16)), extraParams: { from: D } })
    const { totalDebt: E_totalDebt } = await openTrove({ ICR: toBN(dec(223, 16)), extraParams: { from: E } })
    F = freddy
    G = greta
    H = harry
    I = ida	
    await openTrove({ ICR: toBN(dec(225, 16)), extraParams: { from: F } })

    // Troves that will fall into ICR range >= TCR
    const { totalDebt: G_totalDebt } = await openTrove({ ICR: toBN(dec(250, 16)), extraParams: { from: G } })
    const { totalDebt: H_totalDebt } = await openTrove({ ICR: toBN(dec(270, 16)), extraParams: { from: H } })
    const { totalDebt: I_totalDebt } = await openTrove({ ICR: toBN(dec(290, 16)), extraParams: { from: I } })

    // Whale adds LUSD to SP
    const spDeposit = A_totalDebt.add(C_totalDebt).add(D_totalDebt).add(G_totalDebt).add(H_totalDebt).add(I_totalDebt)
    await openTrove({ ICR: toBN(dec(245, 16)), extraLUSDAmount: spDeposit, extraParams: { from: whale } })
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: whale })
    let _aTroveId = await sortedTroves.troveOfOwnerByIndex(A, 0);
    let _bTroveId = await sortedTroves.troveOfOwnerByIndex(B, 0);
    let _cTroveId = await sortedTroves.troveOfOwnerByIndex(C, 0);
    let _dTroveId = await sortedTroves.troveOfOwnerByIndex(D, 0);
    let _eTroveId = await sortedTroves.troveOfOwnerByIndex(E, 0);
    let _fTroveId = await sortedTroves.troveOfOwnerByIndex(F, 0);
    let _gTroveId = await sortedTroves.troveOfOwnerByIndex(G, 0);
    let _hTroveId = await sortedTroves.troveOfOwnerByIndex(H, 0);
    let _iTroveId = await sortedTroves.troveOfOwnerByIndex(I, 0);

    // Price drops, but all troves remain active
    await priceFeed.setPrice(dec(110, 18)) 
    const price = await priceFeed.getPrice()
    const TCR = await th.getTCR(contracts)

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    const G_collBefore = (await troveManager.Troves(_gTroveId))[1]
    const G_debtBefore = (await troveManager.Troves(_gTroveId))[0]
    const H_collBefore = (await troveManager.Troves(_hTroveId))[1]
    const H_debtBefore = (await troveManager.Troves(_hTroveId))[0]
    const I_collBefore = (await troveManager.Troves(_iTroveId))[1]
    const I_debtBefore = (await troveManager.Troves(_iTroveId))[0]

    const ICR_A = await troveManager.getCurrentICR(_aTroveId, price) 
    const ICR_B = await troveManager.getCurrentICR(_bTroveId, price) 
    const ICR_C = await troveManager.getCurrentICR(_cTroveId, price) 
    const ICR_D = await troveManager.getCurrentICR(_dTroveId, price)
    const ICR_E = await troveManager.getCurrentICR(_eTroveId, price)
    const ICR_F = await troveManager.getCurrentICR(_fTroveId, price)
    const ICR_G = await troveManager.getCurrentICR(_gTroveId, price)
    const ICR_H = await troveManager.getCurrentICR(_hTroveId, price)
    const ICR_I = await troveManager.getCurrentICR(_iTroveId, price)

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

    // Attempt to liquidate only troves with ICR > TCR% 
    //await assertRevert(troveManager.batchLiquidateTroves([_gTroveId, _hTroveId, _iTroveId]), "TroveManager: nothing to liquidate")

    // Check G, H, I remain in system
    assert.isTrue(await sortedTroves.contains(_gTroveId))
    assert.isTrue(await sortedTroves.contains(_hTroveId))
    assert.isTrue(await sortedTroves.contains(_iTroveId))

    // Check G, H, I coll and debt have not changed
    assert.equal(G_collBefore.eq(await troveManager.Troves(_gTroveId))[1])
    assert.equal(G_debtBefore.eq(await troveManager.Troves(_gTroveId))[0])
    assert.equal(H_collBefore.eq(await troveManager.Troves(_hTroveId))[1])
    assert.equal(H_debtBefore.eq(await troveManager.Troves(_hTroveId))[0])
    assert.equal(I_collBefore.eq(await troveManager.Troves(_iTroveId))[1])
    assert.equal(I_debtBefore.eq(await troveManager.Troves(_iTroveId))[0])

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))
  
    // Attempt to liquidate a variety of troves with SP covering whole batch.
    // Expect A, C, D to be liquidated, and G, H, I to remain in system
    await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from : whale});
    await debtToken.transfer(owner, (await debtToken.balanceOf(A)), {from : A});
    await debtToken.transfer(owner, (await debtToken.balanceOf(C)), {from : C});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(D)), {from : D});
    await troveManager.liquidateInBatchRecovery([_cTroveId, _dTroveId, _gTroveId, _hTroveId, _aTroveId, _iTroveId], {from: owner})
    
    // Confirm A, C, D liquidated  
    assert.isFalse(await sortedTroves.contains(_cTroveId))
    assert.isFalse(await sortedTroves.contains(_aTroveId))
    assert.isFalse(await sortedTroves.contains(_dTroveId))
    
    // Check G, H, I remain in system
    assert.isTrue(await sortedTroves.contains(_gTroveId))
    assert.isTrue(await sortedTroves.contains(_hTroveId))
    assert.isTrue(await sortedTroves.contains(_iTroveId))

    // Check coll and debt have not changed
    assert.equal(G_collBefore.eq(await troveManager.Troves(_gTroveId))[1])
    assert.equal(G_debtBefore.eq(await troveManager.Troves(_gTroveId))[0])
    assert.equal(H_collBefore.eq(await troveManager.Troves(_hTroveId))[1])
    assert.equal(H_debtBefore.eq(await troveManager.Troves(_hTroveId))[0])
    assert.equal(I_collBefore.eq(await troveManager.Troves(_iTroveId))[1])
    assert.equal(I_debtBefore.eq(await troveManager.Troves(_iTroveId))[0])

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Whale withdraws entire deposit, and re-deposits 132 LUSD
    // Increasing the price for a moment to avoid pending liquidations to block withdrawal
    await priceFeed.setPrice(dec(200, 18))
    await stabilityPool.withdrawFromSP(spDeposit, {from: whale})
    await priceFeed.setPrice(dec(110, 18))
    await stabilityPool.provideToSP(B_totalDebt.add(toBN(dec(50, 18))), ZERO_ADDRESS, {from: whale})

    // B and E are still in range 110-TCR.
    // Attempt to liquidate B, G, H, I, E.
    // Expected Stability Pool to fully absorb B (92 LUSD + 10 virtual debt), 
    // but not E as there are not enough funds in Stability Pool
    
    const stabilityBefore = await stabilityPool.getTotalLUSDDeposits()
    const dEbtBefore = (await troveManager.Troves(_eTroveId))[0]

    await debtToken.transfer(owner, (await debtToken.balanceOf(B)), {from : B});
    await debtToken.transfer(owner, (await debtToken.balanceOf(E)), {from : E});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(F)), {from : F});
    await debtToken.transfer(owner, (await debtToken.balanceOf(H)), {from : H});
    await debtToken.transfer(owner, (await debtToken.balanceOf(I)), {from : I});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(G)), {from : G});
    await troveManager.liquidateInBatchRecovery([_bTroveId, _gTroveId, _hTroveId, _iTroveId, _eTroveId], {from: owner})
    
    const dEbtAfter = (await troveManager.Troves(_eTroveId))[0]
    const stabilityAfter = await stabilityPool.getTotalLUSDDeposits()
    
    const stabilityDelta = stabilityBefore.sub(stabilityAfter)  
    const dEbtDelta = dEbtBefore.sub(dEbtAfter)

    th.assertIsApproximatelyEqual(stabilityDelta, '0')
    assert.equal((dEbtDelta.toString()), E_totalDebt.toString())
    
    // Confirm B removed and E active 
    assert.isFalse(await sortedTroves.contains(_bTroveId)) 
    assert.isFalse(await sortedTroves.contains(_eTroveId))

    // Check G, H, I remain in system
    assert.isTrue(await sortedTroves.contains(_gTroveId))
    assert.isTrue(await sortedTroves.contains(_hTroveId))
    assert.isTrue(await sortedTroves.contains(_iTroveId))

    // Check coll and debt have not changed
    assert.equal(G_collBefore.eq(await troveManager.Troves(_gTroveId))[1])
    assert.equal(G_debtBefore.eq(await troveManager.Troves(_gTroveId))[0])
    assert.equal(H_collBefore.eq(await troveManager.Troves(_hTroveId))[1])
    assert.equal(H_debtBefore.eq(await troveManager.Troves(_hTroveId))[0])
    assert.equal(I_collBefore.eq(await troveManager.Troves(_iTroveId))[1])
    assert.equal(I_debtBefore.eq(await troveManager.Troves(_iTroveId))[0])
  })

  it('batchLiquidateTroves(): emits liquidation event with correct values when all troves have ICR > 110% and Stability Pool covers a subset of troves', async () => {
    // Troves to be absorbed by SP
    const { collateral: F_coll, totalDebt: F_totalDebt } = await openTrove({ ICR: toBN(dec(222, 16)), extraParams: { from: freddy } })
    const { collateral: G_coll, totalDebt: G_totalDebt } = await openTrove({ ICR: toBN(dec(222, 16)), extraParams: { from: greta } })

    // Troves to be spared
    await openTrove({ ICR: toBN(dec(250, 16)), extraParams: { from: alice } })
    await openTrove({ ICR: toBN(dec(266, 16)), extraParams: { from: bob } })
    await openTrove({ ICR: toBN(dec(285, 16)), extraParams: { from: carol } })
    await openTrove({ ICR: toBN(dec(308, 16)), extraParams: { from: dennis } })

    // Whale adds LUSD to SP
    const spDeposit = F_totalDebt.add(G_totalDebt)
    await openTrove({ ICR: toBN(dec(285, 16)), extraLUSDAmount: spDeposit, extraParams: { from: whale } })
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: whale })
    let _whaleTroveId = await sortedTroves.troveOfOwnerByIndex(whale, 0);
    let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);
    let _dennisTroveId = await sortedTroves.troveOfOwnerByIndex(dennis, 0);
    let _freddyTroveId = await sortedTroves.troveOfOwnerByIndex(freddy, 0);
    let _gretaTroveId = await sortedTroves.troveOfOwnerByIndex(greta, 0);
    await openTrove({ ICR: toBN(dec(151, 16)), extraLUSDAmount: spDeposit.mul(toBN('2')), extraParams: { from: owner } })

    // Price drops, but all troves remain active
    await priceFeed.setPrice(dec(100, 18))
    const price = await priceFeed.getPrice()

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Confirm all troves have ICR > MCR
    assert.isTrue((await troveManager.getCurrentICR(_freddyTroveId, price)).gte(mv._MCR))
    assert.isTrue((await troveManager.getCurrentICR(_gretaTroveId, price)).gte(mv._MCR))
    assert.isTrue((await troveManager.getCurrentICR(_aliceTroveId, price)).gte(mv._MCR))
    assert.isTrue((await troveManager.getCurrentICR(_bobTroveId, price)).gte(mv._MCR))
    assert.isTrue((await troveManager.getCurrentICR(_carolTroveId, price)).gte(mv._MCR))

    // Confirm LUSD in Stability Pool
    assert.equal((await stabilityPool.getTotalLUSDDeposits()).toString(), spDeposit.toString())

    const trovesToLiquidate = [_freddyTroveId, _gretaTroveId, _aliceTroveId, _bobTroveId, _carolTroveId, _dennisTroveId, _whaleTroveId]

    // Attempt liqudation sequence
    await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from : whale});
    await debtToken.transfer(owner, (await debtToken.balanceOf(freddy)), {from : freddy});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(greta)), {from : greta});
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});
    const liquidationTx = await troveManager.liquidateInBatchRecovery(trovesToLiquidate, {from: owner})
    const [liquidatedDebt, liquidatedColl, gasComp] = th.getEmittedLiquidationValues(liquidationTx)

    // Check F and G were liquidated
    assert.isFalse(await sortedTroves.contains(_freddyTroveId))
    assert.isFalse(await sortedTroves.contains(_gretaTroveId))

    // Check whale and A-D remain active
    assert.isTrue(await sortedTroves.contains(_aliceTroveId))
    assert.isTrue(await sortedTroves.contains(_bobTroveId))
    assert.isTrue(await sortedTroves.contains(_carolTroveId))
    assert.isTrue(await sortedTroves.contains(_dennisTroveId))
    assert.isTrue(await sortedTroves.contains(_whaleTroveId))

    // Liquidation event emits coll = (F_debt + G_debt)/price*1.1*0.995, and debt = (F_debt + G_debt)
    th.assertIsApproximatelyEqual(liquidatedDebt, F_totalDebt.add(G_totalDebt))
    let _calculatedColl = F_totalDebt.add(G_totalDebt).mul(toBN(dec(11, 17))).div(price);
    th.assertIsApproximatelyEqual(liquidatedColl, _calculatedColl)

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

  it('batchLiquidateTroves(): emits liquidation event with correct values when all troves have ICR > 110% and Stability Pool covers a subset of troves, including a partial', async () => {
    // Troves to be absorbed by SP
    const { collateral: F_coll, totalDebt: F_totalDebt } = await openTrove({ ICR: toBN(dec(222, 16)), extraParams: { from: freddy } })
    const { collateral: G_coll, totalDebt: G_totalDebt } = await openTrove({ ICR: toBN(dec(222, 16)), extraParams: { from: greta } })

    // Troves to be spared
    const { collateral: A_coll, totalDebt: A_totalDebt } = await openTrove({ ICR: toBN(dec(250, 16)), extraParams: { from: alice } })
    await openTrove({ ICR: toBN(dec(266, 16)), extraParams: { from: bob } })
    await openTrove({ ICR: toBN(dec(285, 16)), extraParams: { from: carol } })
    await openTrove({ ICR: toBN(dec(308, 16)), extraParams: { from: dennis } })

    // Whale opens trove and adds 220 LUSD to SP
    const spDeposit = F_totalDebt.add(G_totalDebt).add(A_totalDebt.div(toBN(2)))
    await openTrove({ ICR: toBN(dec(285, 16)), extraLUSDAmount: spDeposit, extraParams: { from: whale } })
    await stabilityPool.provideToSP(spDeposit, ZERO_ADDRESS, { from: whale })
    let _whaleTroveId = await sortedTroves.troveOfOwnerByIndex(whale, 0);
    let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
    let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
    let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);
    let _dennisTroveId = await sortedTroves.troveOfOwnerByIndex(dennis, 0);
    let _freddyTroveId = await sortedTroves.troveOfOwnerByIndex(freddy, 0);
    let _gretaTroveId = await sortedTroves.troveOfOwnerByIndex(greta, 0);
    await openTrove({ ICR: toBN(dec(151, 16)), extraLUSDAmount: spDeposit.mul(toBN('2')), extraParams: { from: owner } })

    // Price drops, but all troves remain active
    await priceFeed.setPrice(dec(100, 18))
    const price = await priceFeed.getPrice()

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Confirm all troves have ICR > MCR
    assert.isTrue((await troveManager.getCurrentICR(_freddyTroveId, price)).gte(mv._MCR))
    assert.isTrue((await troveManager.getCurrentICR(_gretaTroveId, price)).gte(mv._MCR))
    assert.isTrue((await troveManager.getCurrentICR(_aliceTroveId, price)).gte(mv._MCR))
    assert.isTrue((await troveManager.getCurrentICR(_bobTroveId, price)).gte(mv._MCR))
    assert.isTrue((await troveManager.getCurrentICR(_carolTroveId, price)).gte(mv._MCR))

    // Confirm LUSD in Stability Pool
    assert.equal((await stabilityPool.getTotalLUSDDeposits()).toString(), spDeposit.toString())

    const trovesToLiquidate = [_freddyTroveId, _gretaTroveId, _aliceTroveId, _bobTroveId, _carolTroveId, _dennisTroveId, _whaleTroveId]

    // Attempt liqudation sequence
    await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from : whale});
    await debtToken.transfer(owner, (await debtToken.balanceOf(freddy)), {from : freddy});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(greta)), {from : greta});
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});
    const liquidationTx = await troveManager.liquidateInBatchRecovery(trovesToLiquidate, {from: owner})
    const [liquidatedDebt, liquidatedColl, gasComp] = th.getEmittedLiquidationValues(liquidationTx)

    // Check F and G were liquidated
    assert.isFalse(await sortedTroves.contains(_freddyTroveId))
    assert.isFalse(await sortedTroves.contains(_gretaTroveId))

    // Check whale and A-D remain active
    assert.isTrue(await sortedTroves.contains(_aliceTroveId))
    assert.isTrue(await sortedTroves.contains(_bobTroveId))
    assert.isTrue(await sortedTroves.contains(_carolTroveId))
    assert.isTrue(await sortedTroves.contains(_dennisTroveId))
    assert.isTrue(await sortedTroves.contains(_whaleTroveId))

    // Check A's collateral and debt are the same
    const entireColl_A = (await troveManager.Troves(_aliceTroveId))[1].add(await troveManager.getPendingETHReward(_aliceTroveId))
    const entireDebt_A = (await troveManager.Troves(_aliceTroveId))[0].add(await troveManager.getPendingLUSDDebtReward(_aliceTroveId))

    assert.equal(entireColl_A.toString(), A_coll)
    th.assertIsApproximatelyEqual(entireDebt_A.toString(), A_totalDebt)

    /* Liquidation event emits:
    coll = (F_debt + G_debt)/price*1.1*0.995
    debt = (F_debt + G_debt) */
    th.assertIsApproximatelyEqual(liquidatedDebt, F_totalDebt.add(G_totalDebt))
    let _calculatedColl = F_totalDebt.add(G_totalDebt).mul(toBN(dec(11, 17))).div(price);
    th.assertIsApproximatelyEqual(liquidatedColl, _calculatedColl)

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
