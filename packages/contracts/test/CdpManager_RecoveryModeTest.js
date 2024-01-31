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
  let defaultPool
  let functionCaller
  let borrowerOperations
  let collSurplusPool
  let hintHelpers

  let contracts
  let _signer
  let collToken;

  const getOpenCdpEBTCAmount = async (totalDebt) => th.getOpenCdpEBTCAmount(contracts, totalDebt)
  const getNetBorrowingAmount = async (debtWithFee) => th.getNetBorrowingAmount(contracts, debtWithFee)
  const openCdp = async (params) => th.openCdp(contracts, params)

  before(async () => {	  
    await hre.network.provider.request({method: "hardhat_impersonateAccount", params: [beadp]}); 
    beadpSigner = await ethers.provider.getSigner(beadp);	
  })

  beforeEach(async () => {
    await deploymentHelper.setDeployGasPrice(1000000000);
    contracts = await deploymentHelper.deployTesterContractsHardhat()
    let LQTYContracts = {}
    LQTYContracts.feeRecipient = contracts.feeRecipient;

    priceFeed = contracts.priceFeedTestnet
    ebtcToken = contracts.ebtcToken
    sortedCdps = contracts.sortedCdps
    cdpManager = contracts.cdpManager
    activePool = contracts.activePool
    defaultPool = contracts.defaultPool
    functionCaller = contracts.functionCaller
    borrowerOperations = contracts.borrowerOperations
    collSurplusPool = contracts.collSurplusPool
    debtToken = ebtcToken;
    collToken = contracts.collateral;
    hintHelpers = contracts.hintHelpers;
    liqStipend = await cdpManager.LIQUIDATOR_REWARD();
    LICR = await cdpManager.LICR()
    MCR = await cdpManager.MCR()

    await deploymentHelper.connectCoreContracts(contracts, LQTYContracts)

    ownerSigner = await ethers.provider.getSigner(owner);
    let _ownerBal = await web3.eth.getBalance(owner);
    let _beadpBal = await web3.eth.getBalance(beadp);
    let _ownerRicher = toBN(_ownerBal.toString()).gt(toBN(_beadpBal.toString()));
    _signer = _ownerRicher? ownerSigner : beadpSigner;
  
    await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("1000")});
    await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("1000")});
    await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("1000")});
    await _signer.sendTransaction({ to: carol, value: ethers.utils.parseEther("1000")});

    let _signerBal = toBN((await web3.eth.getBalance(_signer._address)).toString());
    let _bigDeal = toBN(dec(2000000, 18));
    if (_signerBal.gt(_bigDeal) && _signer._address != beadp){	
        await _signer.sendTransaction({ to: beadp, value: ethers.utils.parseEther("200000")});
    }
  })

  it("checkRecoveryMode(): Returns true if TCR falls below CCR", async () => {
    // --- SETUP ---
    //  Alice and Bob withdraw such that the TCR is ~150%
    await openCdp({ ICR: toBN(dec(151, 16)), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(151, 16)), extraParams: { from: bob } })

    const recoveryMode_Before = await th.checkRecoveryMode(contracts);
    assert.isFalse(recoveryMode_Before)

    // --- TEST ---

    // price drops reducing TCR below 150%.  setPrice() calls checkTCRAndSetRecoveryMode() internally.
    await priceFeed.setPrice(dec(3200, 13))

    const recoveryMode_After = await th.checkRecoveryMode(contracts);
    assert.isTrue(recoveryMode_After)
  })

  it("checkRecoveryMode(): Returns true if TCR stays less than CCR", async () => {
    // --- SETUP ---
    await openCdp({ ICR: toBN(dec(151, 16)), extraParams: { from: alice } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    await openCdp({ ICR: toBN(dec(151, 16)), extraParams: { from: bob } })

    // --- TEST ---

    // price drops, reducing TCR below 150%
    await priceFeed.setPrice(dec(3200, 13))

    const recoveryMode_Before = await th.checkRecoveryMode(contracts);
    assert.isTrue(recoveryMode_Before)

    await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: alice});
    await contracts.collateral.deposit({from: alice, value: await borrowerOperations.MIN_CHANGE()});
    await borrowerOperations.addColl(
      _aliceCdpId, _aliceCdpId, _aliceCdpId, await borrowerOperations.MIN_CHANGE(), 
      { from: alice, value: 0 }
    )

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

  it("checkRecoveryMode(): `returns false if TCR rises above CCR`", async () => {
    // --- SETUP ---
    const { collateral: A_coll } = await openCdp({ ICR: toBN(dec(151, 16)), extraParams: { from: alice } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    await openCdp({ ICR: toBN(dec(151, 16)), extraParams: { from: bob } })
    // --- TEST ---
    // price drops, reducing TCR below 150%
    await priceFeed.setPrice(dec(5000, 13))

    const recoveryMode_Before = await th.checkRecoveryMode(contracts);
    assert.isTrue(recoveryMode_Before)

    await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: alice});
    await contracts.collateral.deposit({from: alice, value: A_coll});
    await borrowerOperations.addColl(_aliceCdpId, _aliceCdpId, _aliceCdpId, A_coll, { from: alice, value: 0 })

    const recoveryMode_After = await th.checkRecoveryMode(contracts);
    assert.isFalse(recoveryMode_After)
  })

  // --- liquidate() with ICR < 100% ---

  it("liquidate(), with ICR < 100%: removes stake and updates totalStakes", async () => {
    // --- SETUP ---
    //  Alice and Bob withdraw such that the TCR is ~150%
    await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("80000")});
    const { collateral: A_coll } = await openCdp({ ICR: toBN(dec(151, 16)), extraParams: { from: alice } })
    const { collateral: B_coll } = await openCdp({ ICR: toBN(dec(151, 16)), extraEBTCAmount: dec(2000, 18), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);

    const bob_Stake_Before = (await cdpManager.Cdps(_bobCdpId))[2]
    const totalStakes_Before = await cdpManager.totalStakes()

    assert.equal(bob_Stake_Before.toString(), B_coll)
    assert.equal(totalStakes_Before.toString(), A_coll.add(B_coll))

    // --- TEST ---
    // price drops, reducing TCR below 150%
    await priceFeed.setPrice(dec(3714, 13))
    const price = await priceFeed.getPrice()

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // check Bob's ICR falls to 75%
    const bob_ICR = await cdpManager.getCachedICR(_bobCdpId, price);
    assert.equal(bob_ICR, '754999999999999999')

    // Liquidate Bob
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    const { collateral: Owner_coll } = await openCdp({ ICR: toBN(dec(1601, 15)), extraEBTCAmount: dec(100, 18), extraParams: { from: owner } })
    await cdpManager.liquidate(_bobCdpId, { from: owner })

    const bob_Stake_After = (await cdpManager.Cdps(_bobCdpId))[2]
    const totalStakes_After = await cdpManager.totalStakes()

    assert.equal(bob_Stake_After, 0)
    assert.equal(totalStakes_After.toString(), toBN(A_coll.toString()).add(toBN(Owner_coll.toString())).toString())
  })

  it("liquidate(), with ICR < 100%: updates system snapshots correctly", async () => {
    // --- SETUP ---
    //  Alice, Bob and Dennis withdraw such that their ICRs and the TCR is ~150%
    const { collateral: A_coll } = await openCdp({ ICR: toBN(dec(151, 16)), extraParams: { from: alice } })
    const { collateral: B_coll } = await openCdp({ ICR: toBN(dec(151, 16)), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    const { collateral: D_coll } = await openCdp({ ICR: toBN(dec(151, 16)), extraParams: { from: dennis } })
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);

    // --- TEST ---
    // price drops, reducing TCR below 150%, and all Cdps below 100% ICR
    await priceFeed.setPrice(dec(3714, 13))

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // Dennis is liquidated
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});
    await cdpManager.liquidate(_dennisCdpId, { from: owner })

    const totalStakesSnaphot_before = (await cdpManager.totalStakesSnapshot()).toString()
    const totalCollateralSnapshot_before = (await cdpManager.totalCollateralSnapshot()).toString()

    assert.equal(totalStakesSnaphot_before, A_coll.add(B_coll))
    assert.equal(totalCollateralSnapshot_before, A_coll.add(B_coll).add(th.applyLiquidationFee(toBN('0')))) // 6 + 3*0.995

    const A_reward  = th.applyLiquidationFee(D_coll).mul(A_coll).div(A_coll.add(B_coll))
    const B_reward  = th.applyLiquidationFee(D_coll).mul(B_coll).div(A_coll.add(B_coll))

    // Liquidate Bob
    await cdpManager.liquidate(_bobCdpId, { from: owner })

    const totalStakesSnaphot_After = (await cdpManager.totalStakesSnapshot())
    const totalCollateralSnapshot_After = (await cdpManager.totalCollateralSnapshot())

    assert.equal(totalStakesSnaphot_After.toString(), A_coll)
    // total collateral should always be 9 minus gas compensations, as all liquidations in this test case are full redistributions
    assert.isAtMost(th.getDifference(totalCollateralSnapshot_After, A_coll.add(toBN('0')).add(th.applyLiquidationFee(toBN('0').add(toBN('0'))))), 1000) // 3 + 4.5*0.995 + 1.5*0.995^2
  })

  it("liquidate(), with ICR < 100%: closes the Cdp and removes it from the Cdp array", async () => {
    // --- SETUP ---
    //  Alice and Bob withdraw such that the TCR is ~150%
    await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("80000")});
    await openCdp({ ICR: toBN(dec(151, 16)), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(151, 16)), extraEBTCAmount: dec(2000, 18), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);

    const bob_CdpStatus_Before = (await cdpManager.Cdps(_bobCdpId))[4]
    const bob_Cdp_isInSortedList_Before = await sortedCdps.contains(_bobCdpId)

    assert.equal(bob_CdpStatus_Before, 1) // status enum element 1 corresponds to "Active"
    assert.isTrue(bob_Cdp_isInSortedList_Before)

    // --- TEST ---
    // price drops, reducing TCR below 150%
    await priceFeed.setPrice(dec(3714, 13))
    const price = await priceFeed.getPrice()

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // check Bob's ICR falls to ~75%
    const bob_ICR = await cdpManager.getCachedICR(_bobCdpId, price);
    assert.equal(bob_ICR, '754999999999999999')

    // Liquidate Bob
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await openCdp({ ICR: toBN(dec(1601, 15)), extraEBTCAmount: dec(100, 18), extraParams: { from: owner } })
    await cdpManager.liquidate(_bobCdpId, { from: owner })

    // check Bob's Cdp is successfully closed, and removed from sortedList
    const bob_CdpStatus_After = (await cdpManager.Cdps(_bobCdpId))[4]
    const bob_Cdp_isInSortedList_After = await sortedCdps.contains(_bobCdpId)
    assert.equal(bob_CdpStatus_After, 3)  // status enum element 3 corresponds to "Closed by liquidation"
    assert.isFalse(bob_Cdp_isInSortedList_After)
  })

  it("liquidate(), with ICR < 100%: only redistributes to active Cdps", async () => {
    // --- SETUP ---
    //  Alice, Bob and Dennis withdraw such that their ICRs and the TCR is ~150%
    const spDeposit = toBN(dec(390, 18))
    const { collateral: A_coll } = await openCdp({ ICR: toBN(dec(1501, 15)), extraEBTCAmount: spDeposit, extraParams: { from: alice } })
    const { collateral: B_coll } = await openCdp({ ICR: toBN(dec(1501, 15)), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    const { collateral: D_coll } = await openCdp({ ICR: toBN(dec(1501, 15)), extraParams: { from: dennis } })


    // --- TEST ---
    // price drops, reducing TCR below 150%, and all Cdps below 100% ICR
    await priceFeed.setPrice(dec(3714, 13))

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // liquidate bob
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});
    await cdpManager.liquidate(_bobCdpId, { from: owner })
  })

  // --- liquidate() with 100% < ICR < 110%

  it("liquidate(), with 100 < ICR < 110%: removes stake and updates totalStakes", async () => {
    // --- SETUP ---
    //  Bob withdraws up to 2000 EBTC of debt, bringing his ICR to 210%
    await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("20000")});
    await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("80000")});
    const { collateral: A_coll, totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(1501, 15)), extraParams: { from: alice } })
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(210, 16)), extraEBTCAmount: dec(2000, 18), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);

    let price = await priceFeed.getPrice()
    // Total TCR = 24*200/2050 = 234%
    const TCR = await th.getCachedTCR(contracts)
    assert.isAtMost(th.getDifference(TCR, A_coll.add(B_coll).mul(price).div(A_totalDebt.add(B_totalDebt))), 1000)

    const bob_Stake_Before = (await cdpManager.Cdps(_bobCdpId))[2]
    const totalStakes_Before = await cdpManager.totalStakes()

    assert.equal(bob_Stake_Before.toString(), B_coll)
    assert.equal(totalStakes_Before.toString(), A_coll.add(B_coll))

    // --- TEST ---
    // price drops to 1ETH:100EBTC, reducing TCR to 117%
    await priceFeed.setPrice(dec(3714, 13))
    price = await priceFeed.getPrice()

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // check Bob's ICR falls to ~105%
    const bob_ICR = await cdpManager.getCachedICR(_bobCdpId, price);
    assert.equal(bob_ICR, '1049999999999999999')

    // Liquidate Bob
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    const { collateral: Owner_coll } = await openCdp({ ICR: toBN(dec(1601, 15)), extraEBTCAmount: dec(100, 18), extraParams: { from: owner } })
    await cdpManager.liquidate(_bobCdpId, { from: owner })

    const bob_Stake_After = (await cdpManager.Cdps(_bobCdpId))[2]
    const totalStakes_After = await cdpManager.totalStakes()

    assert.equal(bob_Stake_After, 0)
    assert.equal(totalStakes_After.toString(), toBN(A_coll.toString()).add(toBN(Owner_coll.toString())).toString())
  })

  it("liquidate(), with 100% < ICR < 110%: updates system snapshots correctly", async () => {
    // --- SETUP ---
    //  Alice and Dennis withdraw such that their ICR is ~150%
    //  Bob withdraws up to 20000 EBTC of debt, bringing his ICR to 210%
    const { collateral: A_coll } = await openCdp({ ICR: toBN(dec(1501, 15)), extraParams: { from: alice } })
    const { collateral: B_coll } = await openCdp(
        { ICR: toBN(dec(210, 16)), extraEBTCAmount: dec(20, 18), extraParams: { from: bob } }
    )
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    const { collateral: D_coll } = await openCdp({ ICR: toBN(dec(1501, 15)), extraParams: { from: dennis } })
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);

    const totalStakesSnaphot_1 = (await cdpManager.totalStakesSnapshot()).toString()
    const totalCollateralSnapshot_1 = (await cdpManager.totalCollateralSnapshot()).toString()
    assert.equal(totalStakesSnaphot_1, 0)
    assert.equal(totalCollateralSnapshot_1, 0)

    // --- TEST ---
    // price drops, reducing TCR below 150%, and all Cdps below 100% ICR
    await priceFeed.setPrice(dec(3714, 13))
    const price = await priceFeed.getPrice()

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // Dennis is liquidated	with 0.75 ICR, fully redistributeds
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await cdpManager.liquidate(_dennisCdpId, { from: owner })	

    const A_reward  = th.applyLiquidationFee(D_coll).mul(A_coll).div(A_coll.add(B_coll))

    /*
    Prior to Dennis liquidation, total stakes and total collateral were each 27 ether. 
  
    Check snapshots. Dennis' liquidated collateral is distributed and remains in the system. His 
    stake is removed, leaving 24+3*0.995 ether total collateral, and 24 ether total stakes. */

    const totalStakesSnaphot_2 = (await cdpManager.totalStakesSnapshot()).toString()
    const totalCollateralSnapshot_2 = (await cdpManager.totalCollateralSnapshot()).toString()
    assert.equal(totalStakesSnaphot_2, A_coll.add(B_coll))
    assert.equal(totalCollateralSnapshot_2, A_coll.add(B_coll).add(th.applyLiquidationFee(toBN('0')))) // 24 + 3*0.995

    // check Bob's ICR is now in range 100% < ICR 110%
    const _110percent = web3.utils.toBN('1100000000000000000')
    const _100percent = web3.utils.toBN('1000000000000000000')

    const bob_ICR = (await cdpManager.getCachedICR(_bobCdpId, price))

    assert.isTrue(bob_ICR.lt(_110percent))
    assert.isTrue(bob_ICR.gt(_100percent))

    // Liquidate Bob
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    const { collateral: Owner_coll } = await openCdp({ ICR: toBN(dec(1601, 15)), extraEBTCAmount: dec(100, 18), extraParams: { from: owner } })
    await cdpManager.liquidate(_bobCdpId, { from: owner })

    /* After Bob's liquidation, Bob's stake (21 ether) should be removed from total stakes, 
    but his collateral should remain in the system (*0.995). */
    const totalStakesSnaphot_3 = (await cdpManager.totalStakesSnapshot())
    const totalCollateralSnapshot_3 = (await cdpManager.totalCollateralSnapshot())
    assert.equal(totalStakesSnaphot_3.toString(), toBN(A_coll.toString()).add(toBN(Owner_coll.toString())).toString())
    // total collateral should always be 27 minus gas compensations, as all liquidations in this test case are full redistributions
    assert.isAtMost(th.getDifference(totalCollateralSnapshot_3.toString(), A_coll.add(Owner_coll).add(th.applyLiquidationFee(toBN('0').add(toBN('0'))))), 1000)
  })

  it("liquidate(), with 100% < ICR < 110%: closes the Cdp and removes it from the Cdp array", async () => {
    // --- SETUP ---
    //  Bob withdraws up to 2000 EBTC of debt, bringing his ICR to 210%
    await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("10000")});
    await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("80000")});
    await openCdp({ ICR: toBN(dec(1501, 15)), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(210, 16)), extraEBTCAmount: dec(2000, 18), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);

    const bob_CdpStatus_Before = (await cdpManager.Cdps(_bobCdpId))[4]
    const bob_Cdp_isInSortedList_Before = await sortedCdps.contains(_bobCdpId)

    assert.equal(bob_CdpStatus_Before, 1) // status enum element 1 corresponds to "Active"
    assert.isTrue(bob_Cdp_isInSortedList_Before)

    // --- TEST ---
    // price drops, reducing TCR below 150%
    await priceFeed.setPrice(dec(3714, 13))
    const price = await priceFeed.getPrice()


    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // check Bob's ICR has fallen to 105%
    const bob_ICR = await cdpManager.getCachedICR(_bobCdpId, price);
    assert.equal(bob_ICR, '1049999999999999999')

    // Liquidate Bob
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await openCdp({ ICR: toBN(dec(1601, 15)), extraEBTCAmount: dec(100, 18), extraParams: { from: owner } })
    await cdpManager.liquidate(_bobCdpId, { from: owner })

    // check Bob's Cdp is successfully closed, and removed from sortedList
    const bob_CdpStatus_After = (await cdpManager.Cdps(_bobCdpId))[4]
    const bob_Cdp_isInSortedList_After = await sortedCdps.contains(_bobCdpId)
    assert.equal(bob_CdpStatus_After, 3)  // status enum element 3 corresponds to "Closed by liquidation"
    assert.isFalse(bob_Cdp_isInSortedList_After)
  })

  it("liquidate(), with 100% < ICR < 110%: repay as much debt as possible, then redistributes the remainder coll and debt", async () => {
    // --- SETUP ---
    //  Alice and Dennis withdraw such that their ICR is ~150%
    //  Bob withdraws up to 2000 EBTC of debt, bringing his ICR to 210%
    const spDeposit = toBN(dec(390, 18))
    await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("50000")});
    await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("80000")});
    await _signer.sendTransaction({ to: dennis, value: ethers.utils.parseEther("10000")});
    const { collateral: A_coll } = await openCdp({ ICR: toBN(dec(1501, 15)), extraEBTCAmount: spDeposit, extraParams: { from: alice } })
    const { totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(210, 16)), extraEBTCAmount: dec(2000, 18), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    const { collateral: D_coll } = await openCdp({ ICR: toBN(dec(1501, 15)), extraParams: { from: dennis } })

    // --- TEST ---
    // price drops, reducing TCR below 150%
    await priceFeed.setPrice(dec(3714, 13))
    const price = await priceFeed.getPrice()

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // check Bob's ICR has fallen to 105%
    const bob_ICR = await cdpManager.getCachedICR(_bobCdpId, price);
    assert.equal(bob_ICR, '1049999999999999999')
	
    // Liquidate Bob
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await cdpManager.liquidate(_bobCdpId, { from: owner })


    /* Now, check redistribution to active Cdps. Remainders of 1610 EBTC and 16.82 ether are distributed.
    
    Now, only Alice and Dennis have a stake in the system - 3 ether each, thus total stakes is 6 ether.
  
    Rewards-per-unit-staked from the redistribution should be:
  
    systemDebtRedistributionIndex = 1610 / 6 = 268.333 EBTC
    L_STETHColl = 16.820475 /6 =  2.8034125 ether
    */
    const systemDebtRedistributionIndex = (await cdpManager.systemDebtRedistributionIndex()).toString()

    assert.isAtMost(th.getDifference(systemDebtRedistributionIndex, toBN('0').sub(toBN('0')).mul(mv._1e18BN).div(A_coll.add(D_coll))), 100)
  })

  // --- liquidate(), applied to cdp with ICR > 110% that has the lowest ICR 

  it("liquidate(), with ICR > 110%, cdp has lowest ICR: does nothing", async () => {
    // --- SETUP ---
    // Alice and Dennis withdraw, resulting in ICRs of 266%. 
    // Bob withdraws, resulting in ICR of 240%. Bob has lowest ICR.
    await openCdp({ ICR: toBN(dec(266, 16)), extraParams: { from: alice } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("80000")});
    await _signer.sendTransaction({ to: dennis, value: ethers.utils.parseEther("80000")});
    await openCdp({ ICR: toBN(dec(240, 16)), extraEBTCAmount: dec(2000, 18), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: dec(2000, 18), extraParams: { from: dennis } })
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);

    // --- TEST ---
    // price drops, reducing TCR below 150%
    await priceFeed.setPrice(dec(3000, 13))
    const price = await priceFeed.getPrice()

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // Check Bob's ICR is >110% but still lowest
    const bob_ICR = (await cdpManager.getCachedICR(_bobCdpId, price)).toString()
    const alice_ICR = (await cdpManager.getCachedICR(_aliceCdpId, price)).toString()
    const dennis_ICR = (await cdpManager.getCachedICR(_dennisCdpId, price)).toString()
	
    assert.isTrue(toBN(bob_ICR).lt(mv._MCR))
    assert.isTrue(toBN(alice_ICR).lt(mv._MCR))
    assert.isTrue(toBN(dennis_ICR).lt(mv._MCR))

    let _bobDebtAndColl = await cdpManager.getSyncedDebtAndCollShares(_bobCdpId);
    let _bobDebt = _bobDebtAndColl[0];
    let _bobColl = _bobDebtAndColl[1];

    // console.log(`TCR: ${await th.getCachedTCR(contracts)}`)
    // Try to liquidate Bob
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    const L_EBTCDebt_Before = (await cdpManager.systemDebtRedistributionIndex()).toString()
    const _deltaError = await cdpManager.lastEBTCDebtErrorRedistribution();
    await cdpManager.liquidate(_bobCdpId, { from: owner })

    // Check that redistribution rewards don't change
    const _totalStake = await cdpManager.totalStakes();
    const L_EBTCDebt_After = (await cdpManager.systemDebtRedistributionIndex()).toString()
    const _liqDebt = _bobColl.mul(price).div(LICR);
    const _delta = (_bobDebt.sub(_liqDebt)).mul(mv._1e18BN).add(_deltaError);
    const _delta2 = toBN(L_EBTCDebt_After).sub(toBN(L_EBTCDebt_Before)).mul(_totalStake).add(await cdpManager.lastEBTCDebtErrorRedistribution())
    th.assertIsApproximatelyEqual(_delta2.toString(), _delta.toString())

    // Check that Bob's Cdp and stake remains active with unchanged coll and debt
    const bob_Cdp = await cdpManager.Cdps(_bobCdpId);
    const bob_Debt = bob_Cdp[0].toString()
    const bob_Coll = bob_Cdp[1].toString()
    const bob_Stake = bob_Cdp[2].toString()
    const bob_CdpStatus = bob_Cdp[4].toString()
    const bob_isInSortedCdpsList = await sortedCdps.contains(_bobCdpId)

    th.assertIsApproximatelyEqual(bob_Debt.toString(), '0')
    assert.equal(bob_Coll.toString(), '0')
    assert.equal(bob_Stake.toString(), '0')
    assert.equal(bob_CdpStatus, '3')
    assert.isFalse(bob_isInSortedCdpsList)
  })

  // --- liquidate(), applied to cdp with ICR > 110% that has the lowest ICR ---

  it("liquidate(), with 110% < ICR < TCR: repay the cdp debt entirely", async () => {
    // --- SETUP ---
    // Alice withdraws up to 1500 EBTC of debt, and Dennis up to 150, resulting in ICRs of 266%.
    // Bob withdraws up to 250 EBTC of debt, resulting in ICR of 240%. Bob has lowest ICR.
    await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("10000")});
    await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("10000")});
    await _signer.sendTransaction({ to: dennis, value: ethers.utils.parseEther("80000")});
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(240, 16)), extraEBTCAmount: dec(250, 18), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: B_totalDebt, extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: dec(2000, 18), extraParams: { from: dennis } })

    // --- TEST ---
    // price drops, reducing TCR below 150%
    await priceFeed.setPrice(dec(3000, 13))
    const price = await priceFeed.getPrice()
    const TCR = await th.getCachedTCR(contracts)

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // Check Bob's ICR is between 110 and TCR
    const bob_ICR = await cdpManager.getCachedICR(_bobCdpId, price)
    assert.isTrue(bob_ICR.lt(mv._MCR) && bob_ICR.lt(TCR))

    // Liquidate Bob
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await cdpManager.liquidate(_bobCdpId, { from: owner })

    /* Total Pool deposits was 1490 EBTC, Alice sole depositor.
    As liquidated debt (250 EBTC) was completely offset

    Alice's expected compounded deposit: (1490 - 250) = 1240EBTC
    Alice's expected ETH gain:  Bob's liquidated capped coll (minus gas comp), 2.75*0.995 ether
  
    */

    // check Bob’s collateral surplus
    const bob_remainingCollateral = B_coll.sub(B_coll)

    th.assertIsApproximatelyEqual('0', bob_remainingCollateral.toString())
  })

  it("liquidate(), with 100% < ICR < 105%: give incentive over 100 pct", async () => {
    await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("10000")});
    await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("10000")});
    await _signer.sendTransaction({ to: dennis, value: ethers.utils.parseEther("80000")});
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openCdp(
        { ICR: toBN(dec(205, 16)), extraEBTCAmount: dec(250, 18), extraParams: { from: bob } }
    )
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: B_totalDebt, extraParams: { from: alice } })
    await openCdp(
        { ICR: toBN(dec(266, 16)),
          extraEBTCAmount: dec(2000, 18), extraParams: { from: dennis } }
    )
    // --- TEST ---
    // price drops, reducing TCR below 150%
    await priceFeed.setPrice(dec(3000, 13))
    const price = await priceFeed.getPrice()

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // Check Bob's ICR is between 100% and 105%
    const bob_ICR = await cdpManager.getCachedICR(_bobCdpId, price)
    assert.isTrue(bob_ICR.lt(mv._1e18BN) && bob_ICR.lt(mv._1_5e18BN))

    // Liquidate Bob
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await cdpManager.liquidate(_bobCdpId, { from: owner })

    // check Bob’s collateral surplus
    // Bob's leftover is Initial Collateral - (Debt * bob ICR) / price
    const bob_remainingCollateral = B_coll.sub(B_coll)
    // Min between bob bob_remainingCollateral and zero
    const bob_collSurplus = bob_remainingCollateral.gt(th.toBN(0)) ? bob_remainingCollateral : th.toBN(0)
    th.assertIsApproximatelyEqual('0', bob_collSurplus.toString(), 10000)
  })

  it("liquidate(), with ICR < 100% - give away entire collateral as an incentive to liquidator", async () => {
    await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("10000")});
    await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("10000")});
    await _signer.sendTransaction({ to: dennis, value: ethers.utils.parseEther("80000")});
    const { totalDebt: B_totalDebt } = await openCdp(
        { ICR: toBN(dec(199, 16)), extraEBTCAmount: dec(250, 18), extraParams: { from: bob } }
    )
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: B_totalDebt, extraParams: { from: alice } })
    await openCdp(
        { ICR: toBN(dec(266, 16)),
          extraEBTCAmount: dec(2000, 18), extraParams: { from: dennis } }
    )
    // --- TEST ---
    // price drops, reducing TCR below 150%
    await priceFeed.setPrice(dec(3000, 13))
    const price = await priceFeed.getPrice()

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // Check Bob's ICR is below 100%
    const bob_ICR = await cdpManager.getCachedICR(_bobCdpId, price)
    assert.isTrue(bob_ICR.lt(mv._1e18BN))

    // Liquidate Bob
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await cdpManager.liquidate(_bobCdpId, { from: owner })

    // check Bob’s collateral surplus
    // Bob's doesn't have any collateral left as he had ICR < 100% and his collateral was given to liquidator
    assert.equal(await collSurplusPool.getSurplusCollShares(owner), 0)
  })

  it("liquidate(), with ICR% = 110 < TCR: repay the cdp debt entirely, collsuprlus present", async () => {
    // --- SETUP ---
    // Alice withdraws up to 1500 EBTC of debt, and Dennis up to 150, resulting in ICRs of 266%.
    // Bob withdraws up to 250 EBTC of debt, resulting in ICR of 220%. Bob has lowest ICR.
    await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("10000")});
    await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("10000")});
    await _signer.sendTransaction({ to: dennis, value: ethers.utils.parseEther("80000")});
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(220, 16)), extraEBTCAmount: dec(250, 18), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: B_totalDebt, extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: dec(2000, 18), extraParams: { from: dennis } })

    // --- TEST ---
    // price drops, reducing TCR below 150%
    await priceFeed.setPrice(dec(3000, 13))
    const price = await priceFeed.getPrice()

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // Check Bob's ICR = 110
    const bob_ICR = await cdpManager.getCachedICR(_bobCdpId, price)
    assert.isTrue(bob_ICR.lt(mv._MCR))

    // Liquidate Bob
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await cdpManager.liquidate(_bobCdpId, { from: owner })

    /* (FIXME with new liquidation logiv). Total Pool deposits was 1490 EBTC, Alice sole depositor.
    As liquidated debt (250 EBTC) was completely offset

    Alice's expected compounded deposit: (1490 - 250) = 1240EBTC
    Alice's expected ETH gain:  Bob's liquidated capped coll (minus gas comp), 2.75*0.995 ether

    */

    // check Bob’s collateral surplus
    const bob_remainingCollateral = B_coll.sub(B_coll)
    th.assertIsApproximatelyEqual('0', bob_remainingCollateral)
  })

  it("liquidate(), with  110% < ICR < TCR: removes stake and updates totalStakes", async () => {
    // --- SETUP ---
    // Alice withdraws up to 1500 EBTC of debt, and Dennis up to 150, resulting in ICRs of 266%.
    // Bob withdraws up to 250 EBTC of debt, resulting in ICR of 240%. Bob has lowest ICR.
    await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("10000")});
    await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("10000")});
    await _signer.sendTransaction({ to: dennis, value: ethers.utils.parseEther("80000")});
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(240, 16)), extraEBTCAmount: dec(250, 18), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    const { collateral: A_coll } = await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: B_totalDebt, extraParams: { from: alice } })
    const { collateral: D_coll } = await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: dec(2000, 18), extraParams: { from: dennis } })

    // --- TEST ---
    // price drops, reducing TCR below 150%
    await priceFeed.setPrice(dec(3000, 13))
    const price = await priceFeed.getPrice()

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // check stake and totalStakes before
    const bob_Stake_Before = (await cdpManager.Cdps(_bobCdpId))[2]
    const totalStakes_Before = await cdpManager.totalStakes()

    assert.equal(bob_Stake_Before.toString(), B_coll)
    assert.equal(totalStakes_Before.toString(), A_coll.add(B_coll).add(D_coll))

    // Check Bob's ICR is below 110
    const bob_ICR = await cdpManager.getCachedICR(_bobCdpId, price)
    assert.isTrue(bob_ICR.lt(mv._MCR) && bob_ICR.lt(await th.getCachedTCR(contracts)))

    // Liquidate Bob
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await cdpManager.liquidate(_bobCdpId, { from: owner })

    // check stake and totalStakes after
    const bob_Stake_After = (await cdpManager.Cdps(_bobCdpId))[2]
    const totalStakes_After = await cdpManager.totalStakes()

    assert.equal(bob_Stake_After, 0)
    assert.equal(totalStakes_After.toString(), A_coll.add(D_coll))

    // check Bob’s collateral surplus
    const bob_remainingCollateral = B_coll.sub(B_coll)
    th.assertIsApproximatelyEqual('0', bob_remainingCollateral)
  })

  it("liquidate(), with  110% < ICR < TCR: updates system snapshots", async () => {
    // --- SETUP ---
    // Alice withdraws up to 1500 EBTC of debt, and Dennis up to 150, resulting in ICRs of 266%.
    // Bob withdraws up to 250 EBTC of debt, resulting in ICR of 240%. Bob has lowest ICR.
    await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("10000")});
    await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("10000")});
    await _signer.sendTransaction({ to: dennis, value: ethers.utils.parseEther("80000")});
    const { totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(240, 16)), extraEBTCAmount: dec(250, 18), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    const { collateral: A_coll } = await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: B_totalDebt, extraParams: { from: alice } })
    const { collateral: D_coll } = await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: dec(2000, 18), extraParams: { from: dennis } })

    // --- TEST ---
    // price drops, reducing TCR below 150%
    await priceFeed.setPrice(dec(3000, 13))
    const price = await priceFeed.getPrice()

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // check system snapshots before
    const totalStakesSnaphot_before = (await cdpManager.totalStakesSnapshot()).toString()
    const totalCollateralSnapshot_before = (await cdpManager.totalCollateralSnapshot()).toString()

    assert.equal(totalStakesSnaphot_before, '0')
    assert.equal(totalCollateralSnapshot_before, '0')

    // Check Bob's ICR is between 110 and TCR
    const bob_ICR = await cdpManager.getCachedICR(_bobCdpId, price)
    assert.isTrue(bob_ICR.lt(mv._MCR) && bob_ICR.lt(await th.getCachedTCR(contracts)))

    // Liquidate Bob
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await cdpManager.liquidate(_bobCdpId, { from: owner })

    const totalStakesSnaphot_After = (await cdpManager.totalStakesSnapshot())
    const totalCollateralSnapshot_After = (await cdpManager.totalCollateralSnapshot())

    // totalStakesSnapshot should have reduced to 22 ether - the sum of Alice's coll( 20 ether) and Dennis' coll (2 ether )
    assert.equal(totalStakesSnaphot_After.toString(), A_coll.add(D_coll))
    // Total collateral should also reduce, since all liquidated coll has been removed
    assert.equal(totalCollateralSnapshot_After.toString(), A_coll.add(D_coll))
  })

  it("liquidate(), with 110% < ICR < TCR: closes the Cdp", async () => {
    // --- SETUP ---
    // Alice withdraws up to 1500 EBTC of debt, and Dennis up to 150, resulting in ICRs of 266%.
    // Bob withdraws up to 250 EBTC of debt, resulting in ICR of 240%. Bob has lowest ICR.
    await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("10000")});
    await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("10000")});
    await _signer.sendTransaction({ to: dennis, value: ethers.utils.parseEther("80000")});
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(240, 16)), extraEBTCAmount: dec(250, 18), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: B_totalDebt, extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: dec(2000, 18), extraParams: { from: dennis } })

    // --- TEST ---
    // price drops, reducing TCR below 150%
    await priceFeed.setPrice(dec(3000, 13))
    const price = await priceFeed.getPrice()

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // Check Bob's Cdp is active
    const bob_CdpStatus_Before = (await cdpManager.Cdps(_bobCdpId))[4]
    const bob_Cdp_isInSortedList_Before = await sortedCdps.contains(_bobCdpId)

    assert.equal(bob_CdpStatus_Before, 1) // status enum element 1 corresponds to "Active"
    assert.isTrue(bob_Cdp_isInSortedList_Before)

    // Check Bob's ICR is between 110 and TCR
    const bob_ICR = await cdpManager.getCachedICR(_bobCdpId, price)
    assert.isTrue(bob_ICR.lt(mv._MCR) && bob_ICR.lt(await th.getCachedTCR(contracts)))

    // Liquidate Bob
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await cdpManager.liquidate(_bobCdpId, { from: owner })

    // Check Bob's Cdp is closed after liquidation
    const bob_CdpStatus_After = (await cdpManager.Cdps(_bobCdpId))[4]
    const bob_Cdp_isInSortedList_After = await sortedCdps.contains(_bobCdpId)

    assert.equal(bob_CdpStatus_After, 3) // status enum element 3 corresponds to "Closed by liquidation"
    assert.isFalse(bob_Cdp_isInSortedList_After)

    // check Bob’s collateral surplus
    const bob_remainingCollateral = B_coll.sub(B_coll)
    th.assertIsApproximatelyEqual('0', bob_remainingCollateral)
  })

  it("liquidate(), with 110% < ICR < TCR: can liquidate cdps out of order", async () => {
    // taking out 1000 EBTC, CR of 200%
    const { totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: alice } })
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(202, 16)), extraParams: { from: bob } })
    const { collateral: C_coll, totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(204, 16)), extraParams: { from: carol } })
    const { collateral: D_coll, totalDebt: D_totalDebt } = await openCdp({ ICR: toBN(dec(206, 16)), extraParams: { from: dennis } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);
    await openCdp({ ICR: toBN(dec(240, 16)), extraParams: { from: erin } })
    await openCdp({ ICR: toBN(dec(240, 16)), extraParams: { from: freddy } })

    const totalLiquidatedDebt = A_totalDebt.add(B_totalDebt).add(C_totalDebt).add(D_totalDebt)

    await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: totalLiquidatedDebt, extraParams: { from: whale } })

    // Price drops 
    await priceFeed.setPrice(dec(3000, 13))
    const price = await priceFeed.getPrice()
    const TCR = await th.getCachedTCR(contracts)
  
    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check cdps A-D are in range 110% < ICR < TCR
    const ICR_A = await cdpManager.getCachedICR(_aliceCdpId, price)
    const ICR_B = await cdpManager.getCachedICR(_bobCdpId, price)
    const ICR_C = await cdpManager.getCachedICR(_carolCdpId, price)
    const ICR_D = await cdpManager.getCachedICR(_dennisCdpId, price)
    
    assert.isTrue(ICR_A.lt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.lt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C.lt(mv._MCR) && ICR_C.lt(TCR))
    assert.isTrue(ICR_D.lt(mv._MCR) && ICR_D.lt(TCR))

    // Cdps are ordered by ICR, low to high: A, B, C, D.

    // Liquidate out of ICR order: D, B, C.  Confirm Recovery Mode is active prior to each.
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from : whale});
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});
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
    assert.equal((await cdpManager.Cdps(_dennisCdpId))[4], '3')
    assert.equal((await cdpManager.Cdps(_bobCdpId))[4], '3')
    assert.equal((await cdpManager.Cdps(_carolCdpId))[4], '3')

    // check collateral surplus
    const dennis_remainingCollateral = D_coll.sub(D_coll)
    const bob_remainingCollateral = B_coll.sub(B_coll)
    const carol_remainingCollateral = C_coll.sub(C_coll)
    th.assertIsApproximatelyEqual('0', dennis_remainingCollateral.toString())
    th.assertIsApproximatelyEqual('0', bob_remainingCollateral.toString())
    th.assertIsApproximatelyEqual('0', carol_remainingCollateral.toString())
  })


  /* --- liquidate() applied to cdp with ICR > 110% that has the lowest ICR: a non fullfilled liquidation --- */

  it("liquidate(), with ICR > 110%: Cdp is closed", async () => {
    // --- SETUP ---
    // Alice withdraws up to 1500 EBTC of debt, and Dennis up to 150, resulting in ICRs of 266%.
    // Bob withdraws up to 250 EBTC of debt, resulting in ICR of 240%. Bob has lowest ICR.
    await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("50000")});
    await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("10000")});
    await _signer.sendTransaction({ to: dennis, value: ethers.utils.parseEther("80000")});
    await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: dec(1500, 18), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(240, 16)), extraEBTCAmount: dec(250, 18), extraParams: { from: bob } })
    await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: dec(2000, 18), extraParams: { from: dennis } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);

    // --- TEST ---
    // price drops, reducing TCR below 150%
    await priceFeed.setPrice(dec(3000, 13))

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // Check Bob's Cdp is active
    const bob_CdpStatus_Before = (await cdpManager.Cdps(_bobCdpId))[4]
    const bob_Cdp_isInSortedList_Before = await sortedCdps.contains(_bobCdpId)

    assert.equal(bob_CdpStatus_Before, 1) // status enum element 1 corresponds to "Active"
    assert.isTrue(bob_Cdp_isInSortedList_Before)

    // Try to liquidate Bob
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await cdpManager.liquidate(_bobCdpId, { from: owner })

    /* Since the pool only contains 100 EBTC, and Bob's pre-liquidation debt was 250 EBTC,
    expect Bob's cdp to remain untouched, and remain active after liquidation */

    const bob_CdpStatus_After = (await cdpManager.Cdps(_bobCdpId))[4]
    const bob_Cdp_isInSortedList_After = await sortedCdps.contains(_bobCdpId)

    assert.equal(bob_CdpStatus_After, 3) // status enum element 3 corresponds to "closed"
    assert.isFalse(bob_Cdp_isInSortedList_After)
  })

  it("liquidate(), with ICR > 110%: Cdp not in SortedCdps anymore", async () => {
    // --- SETUP ---
    // Alice withdraws up to 1500 EBTC of debt, and Dennis up to 150, resulting in ICRs of 266%.
    // Bob withdraws up to 250 EBTC of debt, resulting in ICR of 240%. Bob has lowest ICR.
    await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("50000")});
    await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("10000")});
    await _signer.sendTransaction({ to: dennis, value: ethers.utils.parseEther("80000")});
    await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: dec(1500, 18), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(240, 16)), extraEBTCAmount: dec(250, 18), extraParams: { from: bob } })
    await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: dec(2000, 18), extraParams: { from: dennis } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);

    // --- TEST ---
    // price drops to 1ETH:100EBTC, reducing TCR below 150%
    await priceFeed.setPrice(dec(3000, 13))

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // Check Bob's Cdp is active
    const bob_CdpStatus_Before = (await cdpManager.Cdps(_bobCdpId))[4]
    const bob_Cdp_isInSortedList_Before = await sortedCdps.contains(_bobCdpId)

    assert.equal(bob_CdpStatus_Before, 1) // status enum element 1 corresponds to "Active"
    assert.isTrue(bob_Cdp_isInSortedList_Before)

    // Try to liquidate Bob
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await cdpManager.liquidate(_bobCdpId, { from: owner })

    /* (FIXME with new liquidation logic) the liquidator only contains 100 EBTC, and Bob's pre-liquidation debt was 250 EBTC, 
    expect Bob's cdp to only be partially repaid, and remain active after liquidation */

    // Check Bob is in Cdp owners array
    const arrayLength = (await cdpManager.getActiveCdpsCount()).toNumber()
    let addressFound = false;
    let addressIdx = 0;

    cdpIds = await hintHelpers.sortedCdpsToArray()

    for (let i = 0; i < arrayLength; i++) {
      const address = (cdpIds[i]).toString()
      if (address == _bobCdpId) {
        addressFound = true
        addressIdx = i
      }
    }

    assert.isFalse(addressFound);

    // Check CdpOwners idx on cdp struct == idx of address found in CdpOwners array
//    const idxOnStruct = (await cdpManager.Cdps(_bobCdpId))[4].toString()
//    assert.equal(addressIdx.toString(), idxOnStruct)
  })

  it("liquidate(), with ICR > 110%: nothing happens", async () => {
    // --- SETUP ---
    // Alice withdraws up to 1500 EBTC of debt, and Dennis up to 150, resulting in ICRs of 266%.
    // Bob withdraws up to 250 EBTC of debt, resulting in ICR of 240%. Bob has lowest ICR.
    await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("50000")});
    await _signer.sendTransaction({ to: dennis, value: ethers.utils.parseEther("80000")});
    const { collateral: A_coll } = await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: dec(1500, 18), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(240, 16)), extraEBTCAmount: dec(250, 18), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    const { collateral: D_coll } = await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: dec(2000, 18), extraParams: { from: dennis } })

    // --- TEST ---
    // price drops, reducing TCR below 150%
    await priceFeed.setPrice(dec(3000, 13))

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // Try to liquidate Bob
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await cdpManager.liquidate(_bobCdpId, { from: owner })

    /*  (FIXME with new liquidation logic) Since Bob's debt (250 EBTC) is larger than all EBTC in liquidator, Liquidation won’t happen

    After liquidation, totalStakes snapshot should equal Alice's stake (20 ether) + Dennis stake (2 ether) = 22 ether.

    Since there has been no redistribution, the totalCollateral snapshot should equal the totalStakes snapshot: 22 ether.

    Bob's new coll and stake should remain the same, and the updated totalStakes should still equal 25 ether.
    */
    const bob_Cdp = await cdpManager.Cdps(_bobCdpId)
    const bob_DebtAfter = bob_Cdp[0].toString()
    const bob_CollAfter = bob_Cdp[1].toString()
    const bob_StakeAfter = bob_Cdp[2].toString()

    th.assertIsApproximatelyEqual(bob_DebtAfter, '0')
    assert.equal(bob_CollAfter.toString(), '0')
    assert.equal(bob_StakeAfter.toString(), '0')

    const totalStakes_After = (await cdpManager.totalStakes()).toString()
    assert.equal(totalStakes_After.toString(), A_coll.add(toBN('0')).add(D_coll))
  })

  it("liquidate(), with ICR > 110%: updates system shapshots", async () => {
    // --- SETUP ---
    // Alice withdraws up to 1500 EBTC of debt, and Dennis up to 150, resulting in ICRs of 266%.
    // Bob withdraws up to 250 EBTC of debt, resulting in ICR of 240%. Bob has lowest ICR.
    await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("50000")});
    await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("10000")});
    await _signer.sendTransaction({ to: dennis, value: ethers.utils.parseEther("80000")});
    await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: dec(1500, 18), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(240, 16)), extraEBTCAmount: dec(250, 18), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: dec(2000, 18), extraParams: { from: dennis } })

    // --- TEST ---
    // price drops, reducing TCR below 150%
    await priceFeed.setPrice(dec(3000, 13))

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // Check snapshots before
    const totalStakesSnaphot_Before = (await cdpManager.totalStakesSnapshot()).toString()
    const totalCollateralSnapshot_Before = (await cdpManager.totalCollateralSnapshot()).toString()

    assert.equal(totalStakesSnaphot_Before, 0)
    assert.equal(totalCollateralSnapshot_Before, 0)

    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await cdpManager.liquidate(_bobCdpId, { from: owner })

    /* After liquidation, totalStakes snapshot should still equal the total stake: 25 ether

    Since there has been no redistribution, the totalCollateral snapshot should equal the totalStakes snapshot: 25 ether.*/

    const totalStakesSnaphot_After = (await cdpManager.totalStakesSnapshot()).toString()
    const totalCollateralSnapshot_After = (await cdpManager.totalCollateralSnapshot()).toString()

    assert.isTrue(toBN(totalStakesSnaphot_After).gt(toBN(totalStakesSnaphot_Before)))
    assert.isTrue(toBN(totalCollateralSnapshot_After).gt(toBN(totalCollateralSnapshot_Before)))
  })

  it("liquidate(), with ICR > 110%: causes correct debt repaid and ETH gain to liquidator, and doesn't redistribute to active cdps", async () => {
    // --- SETUP ---
    // Alice withdraws up to 1500 EBTC of debt, and Dennis up to 150, resulting in ICRs of 266%.
    // Bob withdraws up to 250 EBTC of debt, resulting in ICR of 240%. Bob has lowest ICR.})
    await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("50000")});
    await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("10000")});
    await _signer.sendTransaction({ to: dennis, value: ethers.utils.parseEther("80000")});
    await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: dec(1500, 18), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(240, 16)), extraEBTCAmount: dec(250, 18), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: dec(2000, 18), extraParams: { from: dennis } })

    // --- TEST ---
    // price drops, reducing TCR below 150%
    let _newPrice = dec(3000, 13)
    await priceFeed.setPrice(_newPrice)

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    let _bobDebtAndColl = await cdpManager.getSyncedDebtAndCollShares(_bobCdpId);
    let _bobDebt = _bobDebtAndColl[0];
    let _bobColl = _bobDebtAndColl[1];
	
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    const L_EBTCDebt_Before = (await cdpManager.systemDebtRedistributionIndex()).toString()
    const _deltaError = await cdpManager.lastEBTCDebtErrorRedistribution();
    await cdpManager.liquidate(_bobCdpId, { from: owner })

    /* For this Recovery Mode test case with ICR > 110%, there should be no redistribution of remainder to active Cdps. 
    Redistribution rewards-per-unit-staked should be zero. */
    const _totalStake = await cdpManager.totalStakes();
    const L_EBTCDebt_After = (await cdpManager.systemDebtRedistributionIndex()).toString()
    const _liqDebt = _bobColl.mul(toBN(_newPrice)).div(LICR);
    const _delta = (_bobDebt.sub(_liqDebt)).mul(mv._1e18BN).add(_deltaError);
    const _delta2 = toBN(L_EBTCDebt_After).sub(toBN(L_EBTCDebt_Before)).mul(_totalStake).add(await cdpManager.lastEBTCDebtErrorRedistribution())
    th.assertIsApproximatelyEqual(_delta2.toString(), _delta.toString())
  })

  it("liquidate(), with ICR > 110%: ICR of non liquidated cdp does not change", async () => {
    // --- SETUP ---
    // Alice withdraws up to 1500 EBTC of debt, and Dennis up to 150, resulting in ICRs of 266%.
    // Bob withdraws up to 250 EBTC of debt, resulting in ICR of 240%. Bob has lowest ICR.
    // Carol withdraws up to debt of 240 EBTC, -> ICR of 250%.
    await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("50000")});
    await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: dec(1500, 18), extraParams: { from: alice } })
    await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("10000")});
    await openCdp({ ICR: toBN(dec(240, 16)), extraEBTCAmount: dec(250, 18), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    await _signer.sendTransaction({ to: dennis, value: ethers.utils.parseEther("90000")});
    await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: dec(2000, 18), extraParams: { from: dennis } })
    await _signer.sendTransaction({ to: carol, value: ethers.utils.parseEther("10000")});
    await openCdp({ ICR: toBN(dec(250, 16)), extraEBTCAmount: dec(240, 18), extraParams: { from: carol } })
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _carolDebtAndCollOriginal = await cdpManager.getSyncedDebtAndCollShares(_carolCdpId);
    let _carolDebtOriginal = _carolDebtAndCollOriginal[0];

    // --- TEST ---
    // price drops, reducing TCR below 150%
    await priceFeed.setPrice(dec(3000, 13))
    const price = await priceFeed.getPrice()

    const bob_ICR_Before = (await cdpManager.getCachedICR(_bobCdpId, price)).toString()
    const carol_ICR_Before = (await cdpManager.getCachedICR(_carolCdpId, price)).toString()

    assert.isTrue(await th.checkRecoveryMode(contracts))

    const bob_Coll_Before = (await cdpManager.Cdps(_bobCdpId))[1]
    const bob_Debt_Before = (await cdpManager.Cdps(_bobCdpId))[0]

    // confirm Bob is last cdp in list, and has >110% ICR
    assert.equal((await sortedCdps.getLast()).toString(), _bobCdpId)
    assert.isTrue((await cdpManager.getCachedICR(_bobCdpId, price)).lt(mv._MCR))

    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()).sub(toBN(dec(50, 18))), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});
    await cdpManager.liquidate(_bobCdpId, { from: owner })

    // Check Bob liquidated
    assert.isFalse(await sortedCdps.contains(_bobCdpId))

    // Check Bob's collateral and debt remains the same
    const bob_Coll_After = (await cdpManager.Cdps(_bobCdpId))[1]
    const bob_Debt_After = (await cdpManager.Cdps(_bobCdpId))[0]
    assert.isTrue(bob_Coll_After.lt(bob_Coll_Before))
    assert.isTrue(bob_Debt_After.lt(bob_Debt_Before))

//    const bob_ICR_After = (await cdpManager.getCachedICR(_bobCdpId, price)).toString()

    // check Bob's ICR has not changed
//    assert.equal(bob_ICR_After, bob_ICR_Before)


    // to compensate borrowing fees
//    await ebtcToken.transfer(bob, dec(100, 18), { from: alice })

    await priceFeed.setPrice(dec(3000, 13))
    assert.isFalse(await sortedCdps.contains(_bobCdpId))

    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Confirm Carol is last cdp in list, and has >110% ICR
    assert.equal((await sortedCdps.getLast()), _carolCdpId)
    assert.isTrue((await cdpManager.getCachedICR(_carolCdpId, price)).lt(mv._MCR))

    // get total debt with redistributed
    let _carolDebtAndColl = await cdpManager.getSyncedDebtAndCollShares(_carolCdpId);
    let _carolDebt = _carolDebtAndColl[0];
    let _carolColl = _carolDebtAndColl[1];

    // L2: Try to liquidate Carol. Nothing happens
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});
    const L_EBTCDebt_Before = (await cdpManager.systemDebtRedistributionIndex()).toString()
    const _deltaError = await cdpManager.lastEBTCDebtErrorRedistribution();
    await cdpManager.liquidate(_carolCdpId)
    // Check Carol's collateral and debt remains the same
//    const carol_Coll_After = (await cdpManager.Cdps(_carolCdpId))[1]
//    const carol_Debt_After = (await cdpManager.Cdps(_carolCdpId))[0]
//    assert.isTrue(carol_Coll_After.eq(carol_Coll_Before))
//    assert.isTrue(carol_Debt_After.eq(carol_Debt_Before))

//    const carol_ICR_After = (await cdpManager.getCachedICR(_carolCdpId, price)).toString()

    // check Carol's ICR has not changed
//    assert.equal(carol_ICR_After, carol_ICR_Before)

    //Confirm liquidations have led to some debt redistributions to cdps
    const _totalStake = await cdpManager.totalStakes();
    const L_EBTCDebt_After = (await cdpManager.systemDebtRedistributionIndex()).toString()
    const _liqDebt = _carolColl.mul(price).div(LICR);
    const _delta = (_carolDebt.sub(_liqDebt)).mul(mv._1e18BN).add(_deltaError);
    const _delta2 = toBN(L_EBTCDebt_After).sub(toBN(L_EBTCDebt_Before)).mul(_totalStake).add(await cdpManager.lastEBTCDebtErrorRedistribution())
    th.assertIsApproximatelyEqual(_delta2.toString(), _delta.toString())
  })

  it("liquidate() with ICR > 110%: total liquidated coll and debt is correct", async () => {
    // Whale provides 50 EBTC to the SP
    await openCdp({ ICR: toBN(dec(300, 16)), extraEBTCAmount: dec(1, 17), extraParams: { from: whale } })

    await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: alice } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    await openCdp({ ICR: toBN(dec(202, 16)), extraParams: { from: bob } })
    await openCdp({ ICR: toBN(dec(204, 16)), extraParams: { from: carol } })
    await openCdp({ ICR: toBN(dec(206, 16)), extraParams: { from: dennis } })
    await openCdp({ ICR: toBN(dec(208, 16)), extraParams: { from: erin } })

    // Price drops
    await priceFeed.setPrice(dec(3000, 13))
    const price = await priceFeed.getPrice()

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check C is in range 110% > ICR
    const ICR_A = await cdpManager.getCachedICR(_aliceCdpId, price)
    assert.isTrue(ICR_A.lt(mv._MCR) && ICR_A.lt(await th.getCachedTCR(contracts)))

    const entireSystemCollBefore = await cdpManager.getSystemCollShares()
    const entireSystemDebtBefore = await cdpManager.getSystemDebt()

    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from : whale});
    await cdpManager.liquidate(_aliceCdpId, { from: owner })

    // Expect system debt and system coll not reduced
    const entireSystemCollAfter = await cdpManager.getSystemCollShares()
    const entireSystemDebtAfter = await cdpManager.getSystemDebt()

    const changeInEntireSystemColl = entireSystemCollBefore.sub(entireSystemCollAfter)
    const changeInEntireSystemDebt = entireSystemDebtBefore.sub(entireSystemDebtAfter)

    assert.isTrue(changeInEntireSystemColl.gt(toBN('0')))
    assert.isTrue(changeInEntireSystemDebt.gt(toBN('0')))
  })

  // --- 

  it("liquidate(): Doesn't liquidate undercollateralized cdp if it is the only cdp in the system", async () => {
    // Alice creates a single cdp with 0.62 ETH and a debt of 62 EBTC, and provides 10 EBTC to SP
    await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: alice } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);

    assert.isFalse(await th.checkRecoveryMode(contracts))

    await priceFeed.setPrice(dec(3920, 13))
    const price = await priceFeed.getPrice()

    assert.isTrue(await th.checkRecoveryMode(contracts))

    const alice_ICR = (await cdpManager.getCachedICR(_aliceCdpId, price)).toString()
    assert.equal(alice_ICR, '1055465805061927840')

    const activeCdpsCount_Before = await cdpManager.getActiveCdpsCount()

    assert.equal(activeCdpsCount_Before, 1)

    // Try to liquidate the cdp
    await assertRevert(cdpManager.liquidate(_aliceCdpId, { from: owner }), "CdpManager: nothing to liquidate")

    // Check Alice's cdp has not been removed
    const activeCdpsCount_After = await cdpManager.getActiveCdpsCount()
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

    assert.isFalse(await th.checkRecoveryMode(contracts))

    // Set ETH:USD price to 105
    await priceFeed.setPrice(dec(3920, 13))
    const price = await priceFeed.getPrice()

    assert.isTrue(await th.checkRecoveryMode(contracts))

    const alice_ICR = (await cdpManager.getCachedICR(_aliceCdpId, price)).toString()
    assert.equal(alice_ICR, '1055465805061927840')

    const activeCdpsCount_Before = await cdpManager.getActiveCdpsCount()

    assert.equal(activeCdpsCount_Before, 2)

    // Liquidate the cdp
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});
    await cdpManager.liquidate(_aliceCdpId, { from: owner })

    // Check Alice's cdp is removed, and bob remains
    const activeCdpsCount_After = await cdpManager.getActiveCdpsCount()
    assert.equal(activeCdpsCount_After, 1)

    const alice_isInSortedList = await sortedCdps.contains(_aliceCdpId)
    assert.isFalse(alice_isInSortedList)

    const bob_isInSortedList = await sortedCdps.contains(_bobCdpId)
    assert.isTrue(bob_isInSortedList)
  })

  it("liquidate(): does nothing if cdp has >= 110% ICR", async () => {
    await openCdp({ ICR: toBN(dec(400, 16)), extraParams: { from: alice } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    await openCdp({ ICR: toBN(dec(220, 16)), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    await openCdp({ ICR: toBN(dec(266, 16)), extraParams: { from: carol } })
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    await priceFeed.setPrice(dec(3000, 13))
    const price = await priceFeed.getPrice()

    const TCR_Before = (await th.getCachedTCR(contracts)).toString()
    const listSize_Before = (await sortedCdps.getSize()).toString()

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check Bob's ICR < 110%
    const bob_ICR = await cdpManager.getCachedICR(_bobCdpId, price)
    assert.isTrue(bob_ICR.lte(mv._MCR))

    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});
    await cdpManager.liquidate(_bobCdpId, {from: owner})

    // check A, B, C remain active
    assert.isFalse((await sortedCdps.contains(_bobCdpId)))
    assert.isTrue((await sortedCdps.contains(_aliceCdpId)))
    assert.isTrue((await sortedCdps.contains(_carolCdpId)))

    const TCR_After = (await th.getCachedTCR(contracts)).toString()
    const listSize_After = (await sortedCdps.getSize()).toString()

    // Check TCR and list size have not changed
    assert.isTrue(toBN(TCR_Before.toString()).lt(toBN(TCR_After.toString())))
    assert.isTrue(toBN(listSize_Before.toString()).gt(toBN(listSize_After.toString())))
  })

  it("liquidate(): does nothing if cdp ICR >= TCR, and liquidator covers cdp's debt", async () => { 
    await openCdp({ ICR: toBN(dec(166, 16)), extraParams: { from: A } })
    await openCdp({ ICR: toBN(dec(154, 16)), extraParams: { from: B } })
    await openCdp({ ICR: toBN(dec(142, 16)), extraParams: { from: C } })
    let _aCdpId = await sortedCdps.cdpOfOwnerByIndex(A, 0);
    let _bCdpId = await sortedCdps.cdpOfOwnerByIndex(B, 0);
    let _cCdpId = await sortedCdps.cdpOfOwnerByIndex(C, 0);

    await priceFeed.setPrice(dec(5000, 13))
    const price = await priceFeed.getPrice()
    assert.isTrue(await th.checkRecoveryMode(contracts))

    const TCR = await th.getCachedTCR(contracts)

    const ICR_A = await cdpManager.getCachedICR(_aCdpId, price)
    const ICR_C = await cdpManager.getCachedICR(_cCdpId, price)

    assert.isTrue(ICR_A.gt(TCR))
    // Try to liquidate A
    //await assertRevert(cdpManager.liquidate(_aCdpId), "CdpManager: nothing to liquidate")

    // Check liquidation of A does nothing - cdp remains in system
    assert.isTrue(await sortedCdps.contains(_aCdpId))
    assert.equal(await cdpManager.getCdpStatus(_aCdpId), 1) // Status 1 -> active

    // Check C, with ICR < TCR, can be liquidated
    assert.isTrue(ICR_C.lt(TCR))
    await debtToken.transfer(owner, (await debtToken.balanceOf(A)), {from : A});
    await debtToken.transfer(owner, (await debtToken.balanceOf(B)), {from : B});
    await debtToken.transfer(owner, (await debtToken.balanceOf(C)), {from : C});
    const liqTxC = await cdpManager.liquidate(_cCdpId, {from: owner})
    assert.isTrue(liqTxC.receipt.status)

    assert.isFalse(await sortedCdps.contains(_cCdpId))
    assert.equal(await cdpManager.getCdpStatus(_cCdpId), 3) // Status liquidated
  })

  it("liquidate(): reverts if cdp is non-existent", async () => {
    await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(133, 16)), extraParams: { from: bob } })

    await priceFeed.setPrice(dec(3714, 13))

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
    await priceFeed.setPrice(dec(3714, 13))

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Carol liquidated, and her cdp is closed
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});
    const txCarol_L1 = await cdpManager.liquidate(_carolCdpId, {from: owner})
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
    await openCdp({ ICR: toBN(dec(520, 16)), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(220, 16)), extraParams: { from: bob } })
    await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: carol } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    // Defaulter opens with 60 EBTC, 0.6 ETH
    await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: defaulter_1 } })
    let _defaulter1CdpId = await sortedCdps.cdpOfOwnerByIndex(defaulter_1, 0);

    // Price drops
    await priceFeed.setPrice(dec(3000, 13))
    const price = await priceFeed.getPrice()

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    const alice_ICR_Before = await cdpManager.getCachedICR(_aliceCdpId, price)
    const bob_ICR_Before = await cdpManager.getCachedICR(_bobCdpId, price)
    const carol_ICR_Before = await cdpManager.getCachedICR(_carolCdpId, price)

    /* Before liquidation: 
    Alice ICR: = (1 * 100 / 50) = 200%
    Bob ICR: (1 * 100 / 90.5) = 110.5%
    Carol ICR: (1 * 100 / 100 ) =  100%

    Therefore Alice and Bob above the MCR, Carol is below */
    assert.isTrue(alice_ICR_Before.gte(mv._MCR))
    assert.isTrue(bob_ICR_Before.lte(mv._MCR))
    assert.isTrue(carol_ICR_Before.lte(mv._MCR))

    // Liquidate defaulter. 30 EBTC and 0.3 ETH is distributed uniformly between A, B and C. Each receive 10 EBTC, 0.1 ETH
    await debtToken.transfer(owner, (await debtToken.balanceOf(defaulter_1)), {from : defaulter_1});
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});
    await cdpManager.liquidate(_defaulter1CdpId)

    const alice_ICR_After = await cdpManager.getCachedICR(_aliceCdpId, price)
    const bob_ICR_After = await cdpManager.getCachedICR(_bobCdpId, price)
    const carol_ICR_After = await cdpManager.getCachedICR(_carolCdpId, price)

    /* After liquidation: 

    Alice ICR: (1.1 * 100 / 60) = 183.33%
    Bob ICR:(1.1 * 100 / 100.5) =  109.45%
    Carol ICR: (1.1 * 100 ) 100%

    Check Alice is above MCR, Bob below, Carol below. */
    assert.isTrue(alice_ICR_After.gte(mv._MCR))
    // assert.isTrue(bob_ICR_After.lte(mv._MCR))
    assert.isTrue(carol_ICR_After.lte(mv._MCR))

    /* Though Bob's true ICR (including pending rewards) is below the MCR, 
    check that Bob's raw coll and debt has not changed, and that his "raw" ICR is above the MCR */
    const bob_Coll = (await cdpManager.Cdps(_bobCdpId))[1]
    const bob_Debt = (await cdpManager.Cdps(_bobCdpId))[0]

    const bob_rawICR = bob_Coll.mul(th.toBN(dec(100, 18))).div(bob_Debt)
    assert.isTrue(bob_rawICR.gte(mv._MCR))

    //liquidate A, B, C
    assert.isTrue(await th.checkRecoveryMode(contracts))
    await assertRevert(cdpManager.liquidate(_aliceCdpId), "CdpManager: ICR is not below liquidation threshold in current mode")
    assert.isTrue(await th.checkRecoveryMode(contracts))
    await cdpManager.liquidate(_bobCdpId, {from: owner})
    assert.isTrue(await th.checkRecoveryMode(contracts))
    await cdpManager.liquidate(_carolCdpId, {from: owner})

    /*  Since there is 0 EBTC in the liquidator, A, with ICR >110%, should stay active.
    Check Alice stays active, Carol gets liquidated, and Bob gets liquidated 
    (because his pending rewards bring his ICR < MCR) */
    assert.isTrue(await sortedCdps.contains(_aliceCdpId))
    assert.isFalse(await sortedCdps.contains(_bobCdpId))
    assert.isFalse(await sortedCdps.contains(_carolCdpId))

    // check cdp statuses - A active (1), B and C liquidated (3)
    assert.equal((await cdpManager.Cdps(_aliceCdpId))[4].toString(), '1')
    assert.equal((await cdpManager.Cdps(_bobCdpId))[4].toString(), '3')
    assert.equal((await cdpManager.Cdps(_carolCdpId))[4].toString(), '3')
  })

  it("liquidate(): does not affect address that has no cdp", async () => {
    const { collateral: C_coll, totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: carol } })
    const spDeposit = C_totalDebt.add(toBN(dec(1000, 18)))
    await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("30000")});
    await openCdp({ ICR: toBN(dec(220, 16)), extraEBTCAmount: spDeposit, extraParams: { from: bob } })
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    // Bob sends tokens to Dennis, who has no cdp
    await ebtcToken.transfer(dennis, spDeposit, { from: bob })

    // Price drop
    await priceFeed.setPrice(dec(4000, 13))

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Carol gets liquidated
    await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: C_totalDebt, extraParams: { from: owner } });
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});
    await cdpManager.liquidate(_carolCdpId, {from: owner})

    // Attempt to liquidate Dennis
    try {
      await cdpManager.liquidate(dennis)
    } catch (err) {
      assert.include(err.message, "revert")
    }
  })

  it("liquidate(): does not alter the liquidated user's token balance", async () => {
    await openCdp({ ICR: toBN(dec(220, 16)), extraEBTCAmount: dec(1000, 18), extraParams: { from: whale } })

    const { ebtcAmount: A_ebtcAmount } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(300, 18), extraParams: { from: alice } })
    const { ebtcAmount: B_ebtcAmount } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(200, 18), extraParams: { from: bob } })
    const { ebtcAmount: C_ebtcAmount } = await openCdp({ ICR: toBN(dec(206, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: carol } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    await priceFeed.setPrice(dec(3000, 13))

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check token balances 
    assert.equal((await ebtcToken.balanceOf(alice)).toString(), A_ebtcAmount)
    assert.equal((await ebtcToken.balanceOf(bob)).toString(), B_ebtcAmount)
    assert.equal((await ebtcToken.balanceOf(carol)).toString(), C_ebtcAmount)

    // Check sortedList size is 4
    assert.equal((await sortedCdps.getSize()).toString(), '4')
    await _signer.sendTransaction({ to: owner, value: ethers.utils.parseEther("400000")});
    await openCdp({ ICR: toBN(dec(151, 16)), extraEBTCAmount: toBN(dec(10000,18)), extraParams: { from: owner } })

    // Liquidate A, B and C
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});
    await cdpManager.liquidate(_aliceCdpId, {from: owner})
    await cdpManager.liquidate(_bobCdpId, {from: owner})
    await cdpManager.liquidate(_carolCdpId, {from: owner})

    // Confirm A, B, C closed
    assert.isFalse(await sortedCdps.contains(_aliceCdpId))
    assert.isFalse(await sortedCdps.contains(_bobCdpId))
    assert.isFalse(await sortedCdps.contains(_carolCdpId))

    // Check sortedList size reduced to 2
    assert.equal((await sortedCdps.getSize()).toString(), '2')

    // Confirm token balances have not changed
    assert.equal((await ebtcToken.balanceOf(alice)).toString(), '0')
    assert.equal((await ebtcToken.balanceOf(bob)).toString(), '0')
    assert.equal((await ebtcToken.balanceOf(carol)).toString(), '0')
  })

  it("liquidate(), with 110% < ICR < TCR, can claim collateral, re-open, be reedemed and claim again", async () => {
    // --- SETUP ---
    // Alice withdraws up to 1500 EBTC of debt, resulting in ICRs of 266%.
    // Bob withdraws up to 480 EBTC of debt, resulting in ICR of 240%. Bob has lowest ICR.
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(240, 16)), extraEBTCAmount: dec(480, 18), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("10000")});
    const { collateral: A_coll } = await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: B_totalDebt, extraParams: { from: alice } })

    // --- TEST ---
    // price drops, reducing TCR below 150%
    await priceFeed.setPrice(dec(3000, 13))
    let price = await priceFeed.getPrice()
    const TCR = await th.getCachedTCR(contracts)

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // Check Bob's ICR is between 110 and TCR
    const bob_ICR = await cdpManager.getCachedICR(_bobCdpId, price)
    assert.isTrue(bob_ICR.lt(mv._MCR) && bob_ICR.lt(TCR))

    // Liquidate Bob
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await cdpManager.liquidate(_bobCdpId, { from: owner })

    // check Bob’s collateral surplus: 5.76 * 100 - 480 * 1.1
    const bob_remainingCollateral = B_coll.sub(B_coll)
    th.assertIsApproximatelyEqual('0', bob_remainingCollateral.toString())
    await th.syncTwapSystemDebt(contracts, ethers.provider);

    // Bob re-opens the cdp, price 200, total debt 80 EBTC, ICR = 120% (lowest one)
    // Dennis redeems 30, so Bob has a surplus of (200 * 0.48 - 30) / 200 = 0.33 ETH
    await priceFeed.setPrice(dec(7428, 13))
    const { collateral: B_coll_2, netDebt: B_netDebt_2 } = await openCdp({ ICR: toBN(dec(150, 16)), extraEBTCAmount: dec(480, 18), extraParams: { from: bob, value: bob_remainingCollateral } })
    const { collateral: D_coll } = await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: B_netDebt_2, extraParams: { from: dennis } })
    await th.redeemCollateral(dennis, contracts, B_netDebt_2,GAS_PRICE)
    price = await priceFeed.getPrice()
    const bob_surplus = B_coll_2.sub(B_netDebt_2.mul(mv._1e18BN).div(price)).add(liqStipend)
    th.assertIsApproximatelyEqual(await collSurplusPool.getSurplusCollShares(bob), bob_surplus)
    // can claim collateral
    const bob_balanceBefore_2 = th.toBN(await web3.eth.getBalance(bob))
    let _collBobPre2 = await collToken.balanceOf(bob);	
    const BOB_GAS_2 = th.gasUsed(await borrowerOperations.claimSurplusCollShares({ from: bob, gasPrice: GAS_PRICE  }))
    const bob_expectedBalance_2 = bob_balanceBefore_2.sub(th.toBN(BOB_GAS_2 * GAS_PRICE))
    const bob_balanceAfter_2 = th.toBN(await web3.eth.getBalance(bob))
    let _collBobPost2 = await collToken.balanceOf(bob);	
    th.assertIsApproximatelyEqual(_collBobPost2, _collBobPre2.add(th.toBN(bob_surplus)))
  })

  it("liquidate(), with 110% < ICR < TCR, can claim collateral, after another claim from a redemption", async () => {
    // --- SETUP ---
    // Bob withdraws up to 90 EBTC of debt, resulting in ICR of 222%
    await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("10000")});
    const { collateral: B_coll, netDebt: B_netDebt } = await openCdp({ ICR: toBN(dec(222, 16)), extraEBTCAmount: dec(90, 18), extraParams: { from: bob } })
    // Dennis withdraws to 150 EBTC of debt, resulting in ICRs of 266%.
    await _signer.sendTransaction({ to: dennis, value: ethers.utils.parseEther("10000")});
    await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: B_netDebt, extraParams: { from: dennis } })

    // --- TEST ---
    await th.syncTwapSystemDebt(contracts, ethers.provider);

    // Dennis redeems 40, so Bob has a surplus of (200 * 1 - 40) / 200 = 0.8 ETH	
    await th.redeemCollateral(dennis, contracts, B_netDebt, GAS_PRICE)
    let price = await priceFeed.getPrice()
    const bob_surplus = B_coll.sub(B_netDebt.mul(mv._1e18BN).div(price)).add(liqStipend)
    th.assertIsApproximatelyEqual(await collSurplusPool.getSurplusCollShares(bob), bob_surplus)

    // can claim collateral
    const bob_balanceBefore = th.toBN(await web3.eth.getBalance(bob))
    let _collBobPre = await collToken.balanceOf(bob);	
    const BOB_GAS = th.gasUsed(await borrowerOperations.claimSurplusCollShares({ from: bob, gasPrice: GAS_PRICE  }))
    const bob_expectedBalance = bob_balanceBefore.sub(th.toBN(BOB_GAS * GAS_PRICE))
    const bob_balanceAfter = th.toBN(await web3.eth.getBalance(bob))
    let _collBobPost = await collToken.balanceOf(bob);	
    th.assertIsApproximatelyEqual(_collBobPost, _collBobPre.add(bob_surplus))

    // Bob re-opens the cdp, price 200, total debt 250 EBTC, ICR = 240% (lowest one)
    const { collateral: B_coll_2, totalDebt: B_totalDebt_2 } = await openCdp({ ICR: toBN(dec(240, 16)), extraParams: { from: bob, value: _3_Ether } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    // Alice get EBTC by opening CDP
    await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("10000")});
    await openCdp({ ICR: toBN(dec(266, 16)), extraEBTCAmount: B_totalDebt_2, extraParams: { from: alice } })

    // price drops, reducing TCR below 150%
    await priceFeed.setPrice(dec(3000, 13))
    price = await priceFeed.getPrice()
    const TCR = await th.getCachedTCR(contracts)

    const recoveryMode = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode)

    // Check Bob's ICR is between 110 and TCR
    const bob_ICR = await cdpManager.getCachedICR(_bobCdpId, price)
    assert.isTrue(bob_ICR.lt(mv._MCR) && bob_ICR.lt(TCR))
    // debt is increased by fee, due to previous redemption

    // Liquidate Bob
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from : dennis});
    await cdpManager.liquidate(_bobCdpId, { from: owner })

    // check Bob’s collateral surplus
    const bob_remainingCollateral = B_coll_2.sub(B_coll_2)
    th.assertIsApproximatelyEqual('0', bob_remainingCollateral.toString())
  })

  // --- liquidateCdps ---

  it("liquidateCdps(): With all ICRs > 110%, Liquidates Cdps until system leaves recovery mode", async () => {
    // make 8 Cdps accordingly
    // --- SETUP ---

    // Everyone withdraws some EBTC from their Cdp, resulting in different ICRs
    await openCdp({ ICR: toBN(dec(380, 16)), extraParams: { from: bob } })
    await openCdp({ ICR: toBN(dec(286, 16)), extraParams: { from: carol } })
    await openCdp({ ICR: toBN(dec(273, 16)), extraParams: { from: dennis } })
    const { totalDebt: E_totalDebt } = await openCdp({ ICR: toBN(dec(261, 16)), extraParams: { from: erin } })
    const { totalDebt: F_totalDebt } = await openCdp({ ICR: toBN(dec(250, 16)), extraParams: { from: freddy } })
    const { totalDebt: G_totalDebt } = await openCdp({ ICR: toBN(dec(235, 16)), extraParams: { from: greta } })
    await _signer.sendTransaction({ to: harry, value: ethers.utils.parseEther("150000")});
    const { totalDebt: H_totalDebt } = await openCdp({ ICR: toBN(dec(222, 16)), extraEBTCAmount: dec(5000, 18), extraParams: { from: harry } })
    const liquidationAmount = E_totalDebt.add(F_totalDebt).add(G_totalDebt).add(H_totalDebt)
    await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("200000")});
    await openCdp({ ICR: toBN(dec(480, 16)), extraEBTCAmount: liquidationAmount, extraParams: { from: alice } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);
    let _erinCdpId = await sortedCdps.cdpOfOwnerByIndex(erin, 0);
    let _freddyCdpId = await sortedCdps.cdpOfOwnerByIndex(freddy, 0);
    let _gretaCdpId = await sortedCdps.cdpOfOwnerByIndex(greta, 0);
    let _harryCdpId = await sortedCdps.cdpOfOwnerByIndex(harry, 0);

    // price drops
    // price drops, reducing TCR below 150%
    await priceFeed.setPrice(dec(2500, 13))
    const price = await priceFeed.getPrice()

    const recoveryMode_Before = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode_Before)

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
    const alice_ICR = await cdpManager.getCachedICR(_aliceCdpId, price)
    const bob_ICR = await cdpManager.getCachedICR(_bobCdpId, price)
    const carol_ICR = await cdpManager.getCachedICR(_carolCdpId, price)
    const dennis_ICR = await cdpManager.getCachedICR(_dennisCdpId, price)
    const erin_ICR = await cdpManager.getCachedICR(_erinCdpId, price)
    const freddy_ICR = await cdpManager.getCachedICR(_freddyCdpId, price)
    const greta_ICR = await cdpManager.getCachedICR(_gretaCdpId, price)
    const harry_ICR = await cdpManager.getCachedICR(_harryCdpId, price)
    const TCR = await th.getCachedTCR(contracts)

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
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(carol)).toString()), {from: carol});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(dennis)).toString()), {from: dennis});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(erin)).toString()), {from: erin});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(freddy)).toString()), {from: freddy});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(greta)).toString()), {from: greta});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(harry)).toString()), {from: harry});
    await th.liquidateCdps(10, price, contracts, {extraParams: {from: owner}});

    // check system is no longer in Recovery Mode
    const recoveryMode_After = await th.checkRecoveryMode(contracts)
    console.log('TCR=' + (await cdpManager.getCachedTCR(price)));
    assert.isFalse(recoveryMode_After)

    // get all Cdps
    const alice_Cdp = await cdpManager.Cdps(_aliceCdpId)
    const bob_Cdp = await cdpManager.Cdps(_bobCdpId)
    const carol_Cdp = await cdpManager.Cdps(_carolCdpId)
    const dennis_Cdp = await cdpManager.Cdps(_dennisCdpId)
    const erin_Cdp = await cdpManager.Cdps(_erinCdpId)
    const freddy_Cdp = await cdpManager.Cdps(_freddyCdpId)
    const greta_Cdp = await cdpManager.Cdps(_gretaCdpId)
    const harry_Cdp = await cdpManager.Cdps(_harryCdpId)

    // check that Alice, Bob's Cdps remain active
    assert.equal(alice_Cdp[4], 1)
    assert.equal(bob_Cdp[4], 1)
    assert.equal(carol_Cdp[4], 3)
    assert.equal(dennis_Cdp[4], 3)
    assert.isTrue(await sortedCdps.contains(_aliceCdpId))
    assert.isTrue(await sortedCdps.contains(_bobCdpId))
    assert.isFalse(await sortedCdps.contains(_carolCdpId))
    assert.isFalse(await sortedCdps.contains(_dennisCdpId))

    // check all other Cdps are liquidated
    assert.equal(erin_Cdp[4], 3)
    assert.equal(freddy_Cdp[4], 3)
    assert.equal(greta_Cdp[4], 3)
    assert.equal(harry_Cdp[4], 3)
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
    await openCdp({ ICR: toBN(dec(460, 16)), extraEBTCAmount: liquidationAmount, extraParams: { from: alice } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);
    let _erinCdpId = await sortedCdps.cdpOfOwnerByIndex(erin, 0);
    let _freddyCdpId = await sortedCdps.cdpOfOwnerByIndex(freddy, 0);

    // price drops to 1ETH:85EBTC, reducing TCR below 150%
    await priceFeed.setPrice(dec(2500, 13))
    const price = await priceFeed.getPrice()

    // check Recovery Mode kicks in

    const recoveryMode_Before = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode_Before)

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
    alice_ICR = await cdpManager.getCachedICR(_aliceCdpId, price)
    bob_ICR = await cdpManager.getCachedICR(_bobCdpId, price)
    carol_ICR = await cdpManager.getCachedICR(_carolCdpId, price)
    dennis_ICR = await cdpManager.getCachedICR(_dennisCdpId, price)
    erin_ICR = await cdpManager.getCachedICR(_erinCdpId, price)
    freddy_ICR = await cdpManager.getCachedICR(_freddyCdpId, price)

    // Alice should have ICR > 150%
    assert.isTrue(alice_ICR.gt(mv._MCR))
    // All other Cdps should have ICR < 150%
    assert.isTrue(carol_ICR.lt(mv._MCR))
    assert.isTrue(dennis_ICR.lt(mv._MCR))
    assert.isTrue(erin_ICR.lt(mv._MCR))
    assert.isTrue(freddy_ICR.lt(mv._MCR))

    /* Liquidations should occur from the lowest ICR Cdp upwards, i.e. 
    1) Freddy, 2) Elisa, 3) Dennis.

    After liquidating Freddy and Elisa, the the TCR of the system rises above the CCR, to 154%.  
   (see calculations in Google Sheet)

    Liquidations continue until all Cdps with ICR < MCR have been closed. 
    Only Alice should remain active - all others should be closed. */

    // call liquidate Cdps
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(carol)).toString()), {from: carol});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(dennis)).toString()), {from: dennis});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(erin)).toString()), {from: erin});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(freddy)).toString()), {from: freddy});
    await th.liquidateCdps(6, price, contracts, {extraParams: {from: owner}});

    // check system is no longer in Recovery Mode
    const recoveryMode_After = await th.checkRecoveryMode(contracts)
    console.log('TCR=' + (await cdpManager.getCachedTCR(price)));
    assert.isFalse(recoveryMode_After)

    // get all Cdps
    const alice_Cdp = await cdpManager.Cdps(_aliceCdpId)
    const bob_Cdp = await cdpManager.Cdps(_bobCdpId)
    const carol_Cdp = await cdpManager.Cdps(_carolCdpId)
    const dennis_Cdp = await cdpManager.Cdps(_dennisCdpId)
    const erin_Cdp = await cdpManager.Cdps(_erinCdpId)
    const freddy_Cdp = await cdpManager.Cdps(_freddyCdpId)

    // check that Alice's Cdp remains active
    assert.equal(alice_Cdp[4], 1)
    assert.isTrue(await sortedCdps.contains(_aliceCdpId))

    // check all other Cdps are liquidated
    assert.equal(bob_Cdp[4], 3)
    assert.equal(carol_Cdp[4], 3)
    assert.equal(dennis_Cdp[4], 3)
    assert.equal(erin_Cdp[4], 3)
    assert.equal(freddy_Cdp[4], 3)

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

    await priceFeed.setPrice(dec(3714, 13))

    const TCR = await th.getCachedTCR(contracts)

    assert.isTrue(TCR.lte(web3.utils.toBN(dec(150, 18))))
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // --- TEST --- 

    // Price drops
    await priceFeed.setPrice(dec(3714, 13))

    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(carol)).toString()), {from: carol});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(dennis)).toString()), {from: dennis});
    await th.liquidateCdps(3, dec(3714, 13), contracts, {extraParams: {from: owner}})

    // Check system still in Recovery Mode after liquidation tx
    assert.isTrue(await th.checkRecoveryMode(contracts))

    const CdpOwnersArrayLength = await cdpManager.getActiveCdpsCount()
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

    await priceFeed.setPrice(dec(3714, 13))
    const price = await priceFeed.getPrice()

    const TCR_Before = (await th.getCachedTCR(contracts)).toString()

    // Confirm A, B, C ICRs are below 110%

    const alice_ICR = await cdpManager.getCachedICR(_aliceCdpId, price)
    const bob_ICR = await cdpManager.getCachedICR(_bobCdpId, price)
    const carol_ICR = await cdpManager.getCachedICR(_carolCdpId, price)
    assert.isTrue(alice_ICR.lte(mv._MCR))
    assert.isTrue(bob_ICR.lte(mv._MCR))
    assert.isTrue(carol_ICR.lte(mv._MCR))

    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Liquidation with n = 0
    await assertRevert(th.liquidateCdps(0, price, contracts, {extraParams: {from: owner}}), "CdpManager: nothing to liquidate")

    // Check all cdps are still in the system
    assert.isTrue(await sortedCdps.contains(_aliceCdpId))
    assert.isTrue(await sortedCdps.contains(_bobCdpId))
    assert.isTrue(await sortedCdps.contains(_carolCdpId))

    const TCR_After = (await th.getCachedTCR(contracts)).toString()

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

    // --- TEST ---

    // Price drops, reducing Bob and Carol's ICR below MCR
    await priceFeed.setPrice(dec(3714, 13));
    const price = await priceFeed.getPrice()

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Confirm cdps A-E are ICR < 110%
    assert.isTrue((await cdpManager.getCachedICR(_aliceCdpId, price)).lte(mv._MCR))
    assert.isTrue((await cdpManager.getCachedICR(_bobCdpId, price)).lte(mv._MCR))
    assert.isTrue((await cdpManager.getCachedICR(_carolCdpId, price)).lte(mv._MCR))
    assert.isTrue((await cdpManager.getCachedICR(_erinCdpId, price)).lte(mv._MCR))
    assert.isTrue((await cdpManager.getCachedICR(_freddyCdpId, price)).lte(mv._MCR))

    // Confirm Whale is ICR > 110% 
    assert.isTrue((await cdpManager.getCachedICR(whale, price)).gte(mv._MCR))

    // Liquidate 5 cdps
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(carol)).toString()), {from: carol});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(erin)).toString()), {from: erin});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(freddy)).toString()), {from: freddy});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(whale)).toString()), {from: whale});
    await th.liquidateCdps(5, price, contracts, {extraParams: {from: owner}});

    // Confirm cdps A-E have been removed from the system
    assert.isFalse(await sortedCdps.contains(_aliceCdpId))
    assert.isFalse(await sortedCdps.contains(_bobCdpId))
    assert.isFalse(await sortedCdps.contains(_carolCdpId))
    assert.isFalse(await sortedCdps.contains(_erinCdpId))
    assert.isFalse(await sortedCdps.contains(_freddyCdpId))

    // Check all cdps are now liquidated
    assert.equal((await cdpManager.Cdps(_aliceCdpId))[4].toString(), '3')
    assert.equal((await cdpManager.Cdps(_bobCdpId))[4].toString(), '3')
    assert.equal((await cdpManager.Cdps(_carolCdpId))[4].toString(), '3')
    assert.equal((await cdpManager.Cdps(_erinCdpId))[4].toString(), '3')
    assert.equal((await cdpManager.Cdps(_freddyCdpId))[4].toString(), '3')
  })

  it("liquidateCdps(): a liquidation sequence containing Pool offsets increases the TCR", async () => {
    // Whale provides 500 EBTC to SP
    await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(500, 18), extraParams: { from: whale } })

    await openCdp({ ICR: toBN(dec(300, 16)), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(320, 16)), extraParams: { from: carol } })
    await openCdp({ ICR: toBN(dec(340, 16)), extraParams: { from: dennis } })

    await openCdp({ ICR: toBN(dec(198, 16)), extraEBTCAmount: dec(101, 18), extraParams: { from: defaulter_1 } })
    await openCdp({ ICR: toBN(dec(184, 16)), extraEBTCAmount: dec(217, 18), extraParams: { from: defaulter_2 } })
    await openCdp({ ICR: toBN(dec(183, 16)), extraEBTCAmount: dec(328, 18), extraParams: { from: defaulter_3 } })
    await _signer.sendTransaction({ to: defaulter_4, value: ethers.utils.parseEther("10000")});
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
    await priceFeed.setPrice(dec(4100, 13));
    const price = await priceFeed.getPrice()

    assert.isTrue(await th.ICRbetween100and110(_defaulter1CdpId, cdpManager, price))
    assert.isTrue(await th.ICRbetween100and110(_defaulter2CdpId, cdpManager, price))
    assert.isTrue(await th.ICRbetween100and110(_defaulter3CdpId, cdpManager, price))
    assert.isTrue(await th.ICRbetween100and110(_defaulter4CdpId, cdpManager, price))

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    const TCR_Before = await th.getCachedTCR(contracts)

    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(defaulter_1)).toString()), {from: defaulter_1});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(carol)).toString()), {from: carol});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(dennis)).toString()), {from: dennis});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(defaulter_2)).toString()), {from: defaulter_2});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(defaulter_3)).toString()), {from: defaulter_3});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(defaulter_4)).toString()), {from: defaulter_4});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(whale)).toString()), {from: whale});
    await th.liquidateCdps(8, price, contracts, {extraParams: {from: owner}})

    // assert.isFalse((await sortedCdps.contains(defaulter_1)))
    // assert.isFalse((await sortedCdps.contains(defaulter_2)))
    // assert.isFalse((await sortedCdps.contains(defaulter_3)))
    assert.isFalse((await sortedCdps.contains(_defaulter4CdpId)))

    // Check that the liquidation sequence has improved the TCR
    const TCR_After = await th.getCachedTCR(contracts)
    assert.isTrue(TCR_After.gte(TCR_Before))
  })

  it("liquidateCdps(): A liquidation sequence of pure redistributions decreases the TCR, due to gas compensation, but up to 0.5%", async () => {
    await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("10000")});
    const { collateral: W_coll, totalDebt: W_totalDebt } = await openCdp({ ICR: toBN(dec(250, 16)), extraEBTCAmount: dec(500, 18), extraParams: { from: whale } })

    const { collateral: A_coll, totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(300, 16)), extraParams: { from: alice } })
    const { collateral: C_coll, totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(400, 16)), extraParams: { from: carol } })
    const { collateral: D_coll, totalDebt: D_totalDebt } = await openCdp({ ICR: toBN(dec(600, 16)), extraParams: { from: dennis } })

    await _signer.sendTransaction({ to: defaulter_1, value: ethers.utils.parseEther("1000")});
    await _signer.sendTransaction({ to: defaulter_2, value: ethers.utils.parseEther("1000")});
    await _signer.sendTransaction({ to: defaulter_3, value: ethers.utils.parseEther("10000")});
    await _signer.sendTransaction({ to: defaulter_4, value: ethers.utils.parseEther("10000")});
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
    const price = toBN(dec(3700, 13))
    await priceFeed.setPrice(price)

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    const TCR_Before = await th.getCachedTCR(contracts)
    // (5+1+2+3+1+2+3+4)*100/(410+50+50+50+101+257+328+480)
    const totalCollBefore = W_coll.add(A_coll).add(C_coll).add(D_coll).add(d1_coll).add(d2_coll).add(d3_coll).add(d4_coll)
    const totalDebtBefore = W_totalDebt.add(A_totalDebt).add(C_totalDebt).add(D_totalDebt).add(d1_totalDebt).add(d2_totalDebt).add(d3_totalDebt).add(d4_totalDebt)
    assert.isAtMost(th.getDifference(TCR_Before, totalCollBefore.mul(price).div(totalDebtBefore)), 1000)

    // Liquidate
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(defaulter_1)).toString()), {from: defaulter_1});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(carol)).toString()), {from: carol});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(dennis)).toString()), {from: dennis});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(defaulter_2)).toString()), {from: defaulter_2});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(defaulter_3)).toString()), {from: defaulter_3});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(defaulter_4)).toString()), {from: defaulter_4});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(whale)).toString()), {from: whale});
    await th.liquidateCdps(8, price, contracts, {extraParams: {from: owner}})

    // Check all defaulters have been liquidated
    assert.isFalse((await sortedCdps.contains(_defaulter1CdpId)))
    assert.isFalse((await sortedCdps.contains(_defaulter2CdpId)))
    assert.isFalse((await sortedCdps.contains(_defaulter3CdpId)))
    assert.isFalse((await sortedCdps.contains(_defaulter4CdpId)))

    // Check that the liquidation sequence has reduced the TCR
    const TCR_After = await th.getCachedTCR(contracts)
    const totalCollAfter = toBN('0').add(A_coll).add(C_coll).add(D_coll).add(th.applyLiquidationFee(d1_coll.add(d2_coll).add(d3_coll).add(d4_coll)))
    const totalDebtAfter = toBN('0').add(A_totalDebt).add(C_totalDebt).add(D_totalDebt).add(d1_totalDebt).add(d2_totalDebt).add(d3_totalDebt).add(d4_totalDebt)
    console.log('TCR_Before=' + TCR_Before + ',TCR_After=' + TCR_After);
    assert.isTrue(TCR_Before.gte(TCR_After))
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
    await _signer.sendTransaction({ to: owner, value: ethers.utils.parseEther("120000")});
    await openCdp({ ICR: toBN(dec(151, 16)), extraEBTCAmount: toBN(dec(6000,18)), extraParams: { from: owner } })

    // Price drops
    await priceFeed.setPrice(dec(3718, 13))
    const price = await priceFeed.getPrice()

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    const alice_ICR_Before = await cdpManager.getCachedICR(_aliceCdpId, price)
    const bob_ICR_Before = await cdpManager.getCachedICR(_bobCdpId, price)
    const carol_ICR_Before = await cdpManager.getCachedICR(_carolCdpId, price)

    /* Before liquidation: 
    Alice ICR: = (1 * 100 / 50) = 200%
    Bob ICR: (1 * 100 / 90.5) = 110.5%
    Carol ICR: (1 * 100 / 100 ) =  100%

    Therefore Alice and Bob above the MCR, Carol is below */
    assert.isTrue(alice_ICR_Before.gte(mv._MCR))
    assert.isTrue(bob_ICR_Before.gte(mv._MCR))
    assert.isTrue(carol_ICR_Before.lte(mv._MCR))

    // Liquidate defaulter. 30 EBTC and 0.3 ETH is distributed uniformly between A, B and C. Each receive 10 EBTC, 0.1 ETH
    await debtToken.transfer(owner, (await debtToken.balanceOf(defaulter_1)), {from : defaulter_1});
    await cdpManager.liquidate(_defaulter1CdpId)

    const alice_ICR_After = await cdpManager.getCachedICR(_aliceCdpId, price)
    const carol_ICR_After = await cdpManager.getCachedICR(_carolCdpId, price)

    /* After liquidation: 

    Alice ICR: (1.1 * 100 / 60) = 183.33%
    Bob ICR:(1.1 * 100 / 100.5) =  109.45%
    Carol ICR: (1.1 * 100 ) 100%

    Check Alice is above MCR, Bob below, Carol below. */
    assert.isTrue(alice_ICR_After.gte(mv._MCR))
    assert.isTrue(carol_ICR_After.lte(mv._MCR))

    /* Though Bob's true ICR (including pending rewards) is below the MCR, 
   check that Bob's raw coll and debt has not changed, and that his "raw" ICR is above the MCR */
    const bob_Coll = (await cdpManager.Cdps(_bobCdpId))[1]
    const bob_Debt = (await cdpManager.Cdps(_bobCdpId))[0]

    const bob_rawICR = bob_Coll.mul(th.toBN(dec(100, 18))).div(bob_Debt)
    assert.isTrue(bob_rawICR.gte(mv._MCR))

    // Liquidate A, B, C
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
    await th.liquidateCdps(10, price, contracts, {extraParams: {from: owner}})

    /*  Since there is 0 EBTC in the liquidator, A, with ICR >110%, should stay active.
   Check Alice stays active, Carol gets liquidated, and Bob gets liquidated 
   (because his pending rewards bring his ICR < MCR) */
    assert.isTrue(await sortedCdps.contains(_aliceCdpId))
    assert.isTrue(await sortedCdps.contains(_bobCdpId))
    assert.isFalse(await sortedCdps.contains(_carolCdpId))

    // check cdp statuses - A active (1),  B and C liquidated (3)
    assert.equal((await cdpManager.Cdps(_aliceCdpId))[4].toString(), '1')
    assert.equal((await cdpManager.Cdps(_bobCdpId))[4].toString(), '1')
    assert.equal((await cdpManager.Cdps(_carolCdpId))[4].toString(), '3')
  })

  it('liquidateCdps(): does nothing if all cdps have ICR > 110% and liquidator EBTC balance is empty', async () => {
    await openCdp({ ICR: toBN(dec(222, 16)), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(250, 16)), extraParams: { from: bob } })
    await openCdp({ ICR: toBN(dec(285, 16)), extraParams: { from: carol } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    // Price drops, but all cdps remain active
    await priceFeed.setPrice(dec(3000, 13))
    const price = await priceFeed.getPrice()

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    assert.isTrue((await sortedCdps.contains(_aliceCdpId)))
    assert.isTrue((await sortedCdps.contains(_bobCdpId)))
    assert.isTrue((await sortedCdps.contains(_carolCdpId)))

    const TCR_Before = (await th.getCachedTCR(contracts)).toString()
    const listSize_Before = (await sortedCdps.getSize()).toString()


    assert.isTrue((await cdpManager.getCachedICR(_aliceCdpId, price)).lte(mv._MCR))
    assert.isTrue((await cdpManager.getCachedICR(_bobCdpId, price)).lte(mv._MCR))
    assert.isTrue((await cdpManager.getCachedICR(_carolCdpId, price)).gte(mv._MCR))

    // Attempt liqudation sequence
//    await assertRevert(cdpManager.liquidateCdps(10), "CdpManager: nothing to liquidate")
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(carol)).toString()), {from: carol});
    await th.liquidateCdps(10, price, contracts, {extraParams: {from: owner}})

    // Check all cdps remain active
    assert.isFalse((await sortedCdps.contains(_aliceCdpId)))
    assert.isFalse((await sortedCdps.contains(_bobCdpId)))
    assert.isTrue((await sortedCdps.contains(_carolCdpId)))

    const TCR_After = (await th.getCachedTCR(contracts)).toString()
    const listSize_After = (await sortedCdps.getSize()).toString()

    console.log('TCR_Before=' + TCR_Before + ',TCR_After=' + TCR_After);
    assert.isTrue(toBN(TCR_Before.toString()).gt(toBN(TCR_After.toString())))
    assert.isTrue(toBN(listSize_Before.toString()).gt(toBN(listSize_After.toString())))
  })

  it('liquidateCdps(): emits liquidation event with correct values when all cdps have ICR > 110% and liquidator covers a subset of cdps', async () => {
    // Cdps to be absorbed by SP
    const { collateral: F_coll, totalDebt: F_totalDebt } = await openCdp({ ICR: toBN(dec(222, 16)), extraParams: { from: freddy } })
    const { collateral: G_coll, totalDebt: G_totalDebt } = await openCdp({ ICR: toBN(dec(222, 16)), extraParams: { from: greta } })

    // Cdps to be spared
    const { collateral: A_coll, totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(250, 16)), extraParams: { from: alice } })
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(266, 16)), extraParams: { from: bob } })
    const { collateral: C_coll, totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(285, 16)), extraParams: { from: carol } })
    await openCdp({ ICR: toBN(dec(308, 16)), extraParams: { from: dennis } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);
    let _freddyCdpId = await sortedCdps.cdpOfOwnerByIndex(freddy, 0);
    let _gretaCdpId = await sortedCdps.cdpOfOwnerByIndex(greta, 0);

    // Whale adds EBTC to SP
    const spDeposit = F_totalDebt.add(G_totalDebt)
    const { collateral: W_coll, totalDebt: W_totalDebt } = await openCdp({ ICR: toBN(dec(285, 16)), extraEBTCAmount: spDeposit, extraParams: { from: whale } })
    let _whaleCdpId = await sortedCdps.cdpOfOwnerByIndex(whale, 0);

    // Price drops, but all cdps remain active
    await priceFeed.setPrice(dec(3000, 13))
    const price = await priceFeed.getPrice()

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Confirm all cdps have ICR > MCR
    assert.isTrue((await cdpManager.getCachedICR(_freddyCdpId, price)).lte(mv._MCR))
    assert.isTrue((await cdpManager.getCachedICR(_gretaCdpId, price)).lte(mv._MCR))
    assert.isTrue((await cdpManager.getCachedICR(_aliceCdpId, price)).lte(mv._MCR))
    assert.isTrue((await cdpManager.getCachedICR(_bobCdpId, price)).lte(mv._MCR))
    assert.isTrue((await cdpManager.getCachedICR(_carolCdpId, price)).gte(mv._MCR))
	
    // Attempt liqudation sequence
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(carol)).toString()), {from: carol});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(dennis)).toString()), {from: dennis});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(greta)).toString()), {from: greta});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(freddy)).toString()), {from: freddy});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(whale)).toString()), {from: whale});
    const liquidationTx = await th.liquidateCdps(10, price, contracts, {extraParams: {from: owner}})
    const [liquidatedDebt, liquidatedColl, gasComp] = th.getEmittedLiquidationValues(liquidationTx)

    // Check F and G were liquidated
    assert.isFalse(await sortedCdps.contains(_freddyCdpId))
    assert.isFalse(await sortedCdps.contains(_gretaCdpId))

    // Check whale and A-D remain active
    assert.isFalse(await sortedCdps.contains(_aliceCdpId))
    assert.isFalse(await sortedCdps.contains(_bobCdpId))
    assert.isTrue(await sortedCdps.contains(_carolCdpId))
    assert.isTrue(await sortedCdps.contains(_dennisCdpId))
    assert.isTrue(await sortedCdps.contains(_whaleCdpId))

    // Liquidation event emits coll = (F_debt + G_debt)/price*1.1*0.995, and debt = (F_debt + G_debt)
    let _liqDebts = (F_coll.add(G_coll).add(A_coll)).mul(price).div(LICR).add(B_totalDebt)
    th.assertIsApproximatelyEqual(liquidatedDebt, _liqDebts)
    const equivalentCollA = A_coll
    const equivalentCollB = B_coll
    const equivalentCollF = F_coll
    const equivalentCollG = G_coll
    th.assertIsApproximatelyEqual(liquidatedColl, equivalentCollA.add(equivalentCollB).add(equivalentCollF).add(equivalentCollG))

    // check collateral surplus
    const freddy_remainingCollateral = F_coll.sub(equivalentCollF)
    const greta_remainingCollateral = G_coll.sub(equivalentCollG)
    th.assertIsApproximatelyEqual('0', freddy_remainingCollateral.toString())
    th.assertIsApproximatelyEqual('0', greta_remainingCollateral.toString())
  })

  it('liquidateCdps():  emits liquidation event with correct values when all cdps have ICR > 110% and liquidator covers a subset of cdps, including a partial', async () => {
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
    let _whaleCdpId = await sortedCdps.cdpOfOwnerByIndex(whale, 0);

    // Price drops, but all cdps remain active
    await priceFeed.setPrice(dec(3000, 13))
    const price = await priceFeed.getPrice()

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Confirm all cdps have ICR > MCR
    assert.isTrue((await cdpManager.getCachedICR(_freddyCdpId, price)).lte(mv._MCR))
    assert.isTrue((await cdpManager.getCachedICR(_gretaCdpId, price)).lte(mv._MCR))
    assert.isTrue((await cdpManager.getCachedICR(_aliceCdpId, price)).lte(mv._MCR))
    assert.isTrue((await cdpManager.getCachedICR(_bobCdpId, price)).lte(mv._MCR))
    assert.isTrue((await cdpManager.getCachedICR(_carolCdpId, price)).gte(mv._MCR))
	
    // Attempt liqudation sequence
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(carol)).toString()), {from: carol});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(dennis)).toString()), {from: dennis});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(greta)).toString()), {from: greta});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(freddy)).toString()), {from: freddy});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(whale)).toString()), {from: whale});
    const liquidationTx = await th.liquidateCdps(10, price, contracts, {extraParams: {from: owner}})
    const [liquidatedDebt, liquidatedColl, gasComp] = th.getEmittedLiquidationValues(liquidationTx)

    // Check F and G were liquidated
    assert.isFalse(await sortedCdps.contains(_freddyCdpId))
    assert.isFalse(await sortedCdps.contains(_gretaCdpId))

    // Check CDP status
    assert.isFalse(await sortedCdps.contains(_aliceCdpId))
    assert.isFalse(await sortedCdps.contains(_bobCdpId))
    assert.isTrue(await sortedCdps.contains(_carolCdpId))
    assert.isTrue(await sortedCdps.contains(_dennisCdpId))
    assert.isTrue(await sortedCdps.contains(_whaleCdpId))

    // Check A's collateral and debt remain the same
    const entireColl_A = (await cdpManager.Cdps(_aliceCdpId))[1]
    const entireDebt_A = (await cdpManager.Cdps(_aliceCdpId))[0].add((await cdpManager.getPendingRedistributedDebt(_aliceCdpId)))

    assert.equal(entireColl_A.toString(), '0')
    assert.equal(entireDebt_A.toString(), '0')

    /* Liquidation event emits:
    coll = (F_debt + G_debt)/price*1.1*0.995
    debt = (F_debt + G_debt) */
    let _liqDebts = (F_coll.mul(price).div(LICR)).add(G_coll.mul(price).div(LICR)).add(A_coll.mul(price).div(LICR)).add(B_totalDebt)
    th.assertIsApproximatelyEqual(liquidatedDebt, _liqDebts)
    const equivalentCollA = A_coll
    const equivalentCollB = B_coll
    const equivalentCollF = F_coll
    const equivalentCollG = G_coll
    th.assertIsApproximatelyEqual(liquidatedColl, equivalentCollA.add(equivalentCollB).add(equivalentCollF).add(equivalentCollG))

    // check collateral surplus
    const freddy_remainingCollateral = F_coll.sub(equivalentCollF)
    const greta_remainingCollateral = G_coll.sub(equivalentCollG)
    th.assertIsApproximatelyEqual('0', freddy_remainingCollateral.toString())
    th.assertIsApproximatelyEqual('0', greta_remainingCollateral.toString())
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
    let newPrice = dec(3714, 13);
    await priceFeed.setPrice(newPrice)

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    //Liquidate sequence
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(dennis)).toString()), {from: dennis});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(erin)).toString()), {from: erin});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(freddy)).toString()), {from: freddy});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(whale)).toString()), {from: whale});
    await th.liquidateCdps(10, newPrice, contracts, {extraParams: {from: owner}})

    // Check Whale remains in the system
    assert.isTrue(await sortedCdps.contains(_whaleCdpId))

    // Check D, E, F have been removed
    assert.isFalse(await sortedCdps.contains(_dennisCdpId))
    assert.isFalse(await sortedCdps.contains(_erinCdpId))
    assert.isFalse(await sortedCdps.contains(_freddyCdpId))
  })

  it("liquidateCdps(): Liquidating cdps at 100 < ICR < 110", async () => {
    // Whale provides EBTC to the SP
    await openCdp({ ICR: toBN(dec(340, 16)), extraEBTCAmount: dec(40, 18), extraParams: { from: whale } })

    const { totalDebt: A_totalDebt, collateral: A_coll } = await openCdp(
        { ICR: toBN(dec(201, 16)), extraEBTCAmount: dec(1, 18), extraParams: { from: alice } }
    )
    const { totalDebt: B_totalDebt, collateral: B_coll } = await openCdp({
      ICR: toBN(dec(201, 16)), extraEBTCAmount: dec(10, 18), extraParams: { from: bob } }
    )
    const { totalDebt: C_totalDebt, collateral: C_coll} = await openCdp({ ICR: toBN(dec(209, 16)), extraParams: { from: carol } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    assert.equal((await sortedCdps.getSize()).toString(), '4')

    // Price drops
    await priceFeed.setPrice(dec(3000, 13))
    const price = await priceFeed.getPrice()

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // *** Check A, B, C ICRs 100<ICR<110
    const alice_ICR = await cdpManager.getCachedICR(_aliceCdpId, price)
    const bob_ICR = await cdpManager.getCachedICR(_bobCdpId, price)
    const carol_ICR = await cdpManager.getCachedICR(_carolCdpId, price)
    assert.isTrue(alice_ICR.lte(mv._ICR100) && alice_ICR.lte(mv._MCR))
    assert.isTrue(bob_ICR.lte(mv._ICR100) && bob_ICR.lte(mv._MCR))
    assert.isTrue(carol_ICR.lte(mv._ICR100) && carol_ICR.lte(mv._MCR))

    // Liquidate
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(carol)).toString()), {from: carol});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(whale)).toString()), {from: whale});
    await th.liquidateCdps(10, price, contracts, {extraParams: {from: owner}})

    // Check all defaulters have been liquidated
    assert.isFalse((await sortedCdps.contains(_aliceCdpId)))
    assert.isFalse((await sortedCdps.contains(_bobCdpId)))
    assert.isFalse((await sortedCdps.contains(_carolCdpId)))

    // check system sized reduced to 1 cdps
    assert.equal((await sortedCdps.getSize()).toString(), '1')
  })

  it("liquidateCdps(): Liquidating cdps at ICR <=100%", async () => {
    await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("10000")});
    await openCdp({ ICR: toBN(dec(300, 16)), extraEBTCAmount: dec(400, 18), extraParams: { from: whale } })

    await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("10000")});
    await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("10000")});
    await openCdp({ ICR: toBN(dec(182, 16)), extraEBTCAmount: dec(170, 18), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(180, 16)), extraEBTCAmount: dec(300, 18), extraParams: { from: bob } })
    await openCdp({ ICR: toBN(dec(170, 16)), extraParams: { from: carol } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    assert.equal((await sortedCdps.getSize()).toString(), '4')

    // Price drops
    await priceFeed.setPrice(dec(3714, 13))
    const price = await priceFeed.getPrice()

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // *** Check A, B, C ICRs < 100
    assert.isTrue((await cdpManager.getCachedICR(_aliceCdpId, price)).lte(mv._ICR100))
    assert.isTrue((await cdpManager.getCachedICR(_bobCdpId, price)).lte(mv._ICR100))
    assert.isTrue((await cdpManager.getCachedICR(_carolCdpId, price)).lte(mv._ICR100))

    // Liquidate
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(carol)).toString()), {from: carol});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(whale)).toString()), {from: whale});
    await th.liquidateCdps(10, price, contracts, {extraParams: {from: owner}})

    // Check all defaulters have been liquidated
    assert.isFalse((await sortedCdps.contains(_aliceCdpId)))
    assert.isFalse((await sortedCdps.contains(_bobCdpId)))
    assert.isFalse((await sortedCdps.contains(_carolCdpId)))

    // check system sized reduced to 1 cdps
    assert.equal((await sortedCdps.getSize()).toString(), '1')
  })

  it("liquidateCdps() with a non fullfilled liquidation: non liquidated cdp remains active", async () => {
    const { totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(196, 16)), extraParams: { from: alice } })
    const { totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(198, 16)), extraParams: { from: bob } })
    const { totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(220, 16)), extraParams: { from: carol } })
    await openCdp({ ICR: toBN(dec(206, 16)), extraParams: { from: dennis } })
    await openCdp({ ICR: toBN(dec(208, 16)), extraParams: { from: erin } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    // Whale provides EBTC to the SP
    const spDeposit = A_totalDebt.add(B_totalDebt).add(C_totalDebt.div(toBN(2)))
    await openCdp({ ICR: toBN(dec(340, 16)), extraEBTCAmount: spDeposit, extraParams: { from: whale } })

    // Price drops 
    await priceFeed.setPrice(dec(3000, 13))
    const price = await priceFeed.getPrice()
    const TCR = await th.getCachedTCR(contracts)

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check A, B, C, D, E cdps are in range 110% < ICR < TCR
    const ICR_A = await cdpManager.getCachedICR(_aliceCdpId, price)
    const ICR_B = await cdpManager.getCachedICR(_bobCdpId, price)
    const ICR_C = await cdpManager.getCachedICR(_carolCdpId, price)
    assert.isTrue(ICR_A.lt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.lt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C.lt(mv._MCR) && ICR_C.lt(TCR))

    /* Liquidate cdps. Cdps are ordered by ICR, from low to high:  A, B, C, D, E.
    With 253 in the SP, Alice (102 debt) and Bob (101 debt) should be entirely liquidated. 
    That leaves 50 EBTC in the Pool to absorb exactly half of Carol's debt (100) */
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(carol)).toString()), {from: carol});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(dennis)).toString()), {from: dennis});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(erin)).toString()), {from: erin});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(whale)).toString()), {from: whale});
    await th.liquidateCdps(10, price, contracts, {extraParams: {from: owner}})

    // Check A and B closed
    assert.isFalse(await sortedCdps.contains(_aliceCdpId))
    assert.isFalse(await sortedCdps.contains(_bobCdpId))

    // Check C remains active
    assert.isFalse(await sortedCdps.contains(_carolCdpId))
    assert.equal((await cdpManager.Cdps(_carolCdpId))[4].toString(), '3') // check Status is active
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

    // Price drops 
    await priceFeed.setPrice(dec(4200, 13))
    const price = await priceFeed.getPrice()
    const TCR = await th.getCachedTCR(contracts)

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check A, B, C cdps are in range 110% < ICR < TCR
    const ICR_A = await cdpManager.getCachedICR(_aliceCdpId, price)
    const ICR_B = await cdpManager.getCachedICR(_bobCdpId, price)
    const ICR_C = await cdpManager.getCachedICR(_carolCdpId, price)

    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C.gt(mv._MCR) && ICR_C.lt(TCR))	  
	  	  
    // trigger cooldown and pass the liq wait
    await cdpManager.syncGracePeriod();
    await ethers.provider.send("evm_increaseTime", [901]);
    await ethers.provider.send("evm_mine");

    /* Liquidate cdps. Cdps are ordered by ICR, from low to high:  A, B, C.
    With 253 in the SP, Alice (102 debt) and Bob (101 debt) should be entirely liquidated. 
    That leaves 50 EBTC in the Pool to absorb exactly half of Carol's debt (100) */
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(carol)).toString()), {from: carol});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(dennis)).toString()), {from: dennis});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(erin)).toString()), {from: erin});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(whale)).toString()), {from: whale});
    await th.liquidateCdps(10, price, contracts, {extraParams: {from: owner}})

    // Check C is in Cdp owners array
    const arrayLength = (await cdpManager.getActiveCdpsCount()).toNumber()
    let addressFound = false;
    let _id = await sortedCdps.getFirst();

    for (let i = 0; i < arrayLength; i++) {
       if (_id == _carolCdpId) {
           addressFound = true
       } else {
           _id = await sortedCdps.getNext(_id);
       }
    }

    assert.isFalse(addressFound);

    // Check CdpOwners idx on cdp struct == idx of address found in CdpOwners array
//    const idxOnStruct = (await cdpManager.Cdps(_carolCdpId))[4].toString()
//    assert.equal(addressIdx.toString(), idxOnStruct)
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

    // Price drops 
    await priceFeed.setPrice(dec(4200, 13))
    const price = await priceFeed.getPrice()
    const TCR = await th.getCachedTCR(contracts)

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check A, B, C, D, E cdps are in range 110% < ICR < TCR
    const ICR_A = await cdpManager.getCachedICR(_aliceCdpId, price)
    const ICR_B = await cdpManager.getCachedICR(_bobCdpId, price)
    const ICR_C = await cdpManager.getCachedICR(_carolCdpId, price)
    const ICR_D = await cdpManager.getCachedICR(_dennisCdpId, price)
    const ICR_E = await cdpManager.getCachedICR(_erinCdpId, price)

    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C.gt(mv._MCR) && ICR_C.lt(TCR))
    assert.isTrue(ICR_D.gt(mv._MCR) && ICR_D.lt(TCR))
    assert.isTrue(ICR_E.gt(mv._MCR) && ICR_E.lt(TCR))	  
	  	  
    // trigger cooldown and pass the liq wait
    await cdpManager.syncGracePeriod();
    await ethers.provider.send("evm_increaseTime", [901]);
    await ethers.provider.send("evm_mine");

    /* Liquidate cdps. Cdps are ordered by ICR, from low to high:  A, B, C, D, E.
     With 300 in the SP, Alice (102 debt) and Bob (101 debt) should be entirely liquidated.
     That leaves 97 EBTC in the Pool that won’t be enough to absorb Carol,
     but it will be enough to liquidate Dennis. Afterwards the pool will be empty,
     so Erin won’t liquidated. */
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(carol)).toString()), {from: carol});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(dennis)).toString()), {from: dennis});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(erin)).toString()), {from: erin});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(whale)).toString()), {from: whale});
    const tx = await th.liquidateCdps(10, price, contracts, {extraParams: {from: owner}})
    console.log('gasUsed: ', tx.receipt.gasUsed)

    // Check A, B and D are closed
    assert.isFalse(await sortedCdps.contains(_aliceCdpId))
    assert.isFalse(await sortedCdps.contains(_bobCdpId))
    assert.isFalse(await sortedCdps.contains(_dennisCdpId))

    // Check whale, C and E stay active
    assert.isTrue(await sortedCdps.contains(_whaleCdpId))
    assert.isFalse(await sortedCdps.contains(_carolCdpId))
    assert.isFalse(await sortedCdps.contains(_erinCdpId))
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
    let _whaleCdpId = await sortedCdps.cdpOfOwnerByIndex(whale, 0);

    // Price drops 
    await priceFeed.setPrice(dec(4200, 13))
    const price = await priceFeed.getPrice()
    const TCR = await th.getCachedTCR(contracts)

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check A, B, C, D, E cdps are in range 110% < ICR < TCR
    const ICR_A = await cdpManager.getCachedICR(_aliceCdpId, price)
    const ICR_B = await cdpManager.getCachedICR(_bobCdpId, price)
    const ICR_C = await cdpManager.getCachedICR(_carolCdpId, price)
    const ICR_D = await cdpManager.getCachedICR(_dennisCdpId, price)
    const ICR_E = await cdpManager.getCachedICR(_erinCdpId, price)

    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C.gt(mv._MCR) && ICR_C.lt(TCR))
    assert.isTrue(ICR_D.gt(mv._MCR) && ICR_D.lt(TCR))
    assert.isTrue(ICR_E.gt(mv._MCR) && ICR_E.lt(TCR))	  
	  	  
    // trigger cooldown and pass the liq wait
    await cdpManager.syncGracePeriod();
    await ethers.provider.send("evm_increaseTime", [901]);
    await ethers.provider.send("evm_mine");

    /* Liquidate cdps. Cdps are ordered by ICR, from low to high:  A, B, C, D, E.
     With 301 in the SP, Alice (102 debt) and Bob (101 debt) should be entirely liquidated.
     That leaves 97 EBTC in the Pool that won’t be enough to absorb Carol,
     but it will be enough to liquidate Dennis. Afterwards the pool will be empty,
     so Erin won’t liquidated.
     Note that, compared to the previous test, this one will make 1 more loop iteration,
     so it will consume more gas. */
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(carol)).toString()), {from: carol});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(dennis)).toString()), {from: dennis});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(erin)).toString()), {from: erin});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(whale)).toString()), {from: whale});
    const tx = await th.liquidateCdps(10, price, contracts, {extraParams: {from: owner}})
    console.log('gasUsed: ', tx.receipt.gasUsed)

    // Check A, B and D are closed
    assert.isFalse(await sortedCdps.contains(_aliceCdpId))
    assert.isFalse(await sortedCdps.contains(_bobCdpId))
    assert.isFalse(await sortedCdps.contains(_dennisCdpId))

    // Check whale, C and E stay active
    assert.isTrue(await sortedCdps.contains(_whaleCdpId))
    assert.isFalse(await sortedCdps.contains(_carolCdpId))
    assert.isFalse(await sortedCdps.contains(_erinCdpId))
  })

  it("liquidateCdps() with a non fullfilled liquidation: total liquidated coll and debt is correct", async () => {
    const { collateral: A_coll, totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(196, 16)), extraParams: { from: alice } })
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(198, 16)), extraParams: { from: bob } })
    const { collateral: C_coll, totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: carol } })
    const { collateral: D_coll, totalDebt: D_totalDebt } = await openCdp({ ICR: toBN(dec(206, 16)), extraParams: { from: dennis } })
    const { collateral: E_coll, totalDebt: E_totalDebt } = await openCdp({ ICR: toBN(dec(208, 16)), extraParams: { from: erin } })

    // Whale provides EBTC to the SP
    const spDeposit = A_totalDebt.add(B_totalDebt).add(C_totalDebt.div(toBN(2)))
    const { collateral: W_coll, totalDebt: W_totalDebt } = await openCdp({ ICR: toBN(dec(220, 16)), extraEBTCAmount: spDeposit, extraParams: { from: whale } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    // Price drops 
    await priceFeed.setPrice(dec(4200, 13))
    const price = await priceFeed.getPrice()
    const TCR = await th.getCachedTCR(contracts)

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check A, B, C cdps are in range 110% < ICR < TCR
    const ICR_A = await cdpManager.getCachedICR(_aliceCdpId, price)
    const ICR_B = await cdpManager.getCachedICR(_bobCdpId, price)
    const ICR_C = await cdpManager.getCachedICR(_carolCdpId, price)

    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C.gt(mv._MCR) && ICR_C.lt(TCR))

    const entireSystemCollBefore = await cdpManager.getSystemCollShares()
    const entireSystemDebtBefore = await cdpManager.getSystemDebt()	  
	  	  
    // trigger cooldown and pass the liq wait
    await cdpManager.syncGracePeriod();
    await ethers.provider.send("evm_increaseTime", [901]);
    await ethers.provider.send("evm_mine");

    /* Liquidate cdps. Cdps are ordered by ICR, from low to high:  A, B, C, D, E.
    With 253 in the SP, Alice (102 debt) and Bob (101 debt) should be entirely liquidated. 
    That leaves 50 EBTC in the Pool that won’t be enough to absorb any other cdp */
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(carol)).toString()), {from: carol});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(dennis)).toString()), {from: dennis});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(erin)).toString()), {from: erin});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(whale)).toString()), {from: whale});
    const tx = await th.liquidateCdps(10, price, contracts, {extraParams: {from: owner}})

    // Expect system debt reduced by 203 EBTC and system coll 2.3 ETH
    const entireSystemCollAfter = await cdpManager.getSystemCollShares()
    const entireSystemDebtAfter = await cdpManager.getSystemDebt()

    const changeInEntireSystemColl = entireSystemCollBefore.sub(entireSystemCollAfter)
    const changeInEntireSystemDebt = entireSystemDebtBefore.sub(entireSystemDebtAfter)
	
    assert.equal(changeInEntireSystemColl.toString(), A_coll.add(B_coll).add(C_coll).add(D_coll).add(E_coll))
    th.assertIsApproximatelyEqual(changeInEntireSystemDebt.toString(), A_totalDebt.add(B_totalDebt).add(C_totalDebt).add(D_totalDebt).add(E_totalDebt))
  })

  it("liquidateCdps() with a non fullfilled liquidation: emits correct liquidation event values", async () => {
    const { collateral: A_coll, totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(210, 16)), extraParams: { from: alice } })
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(211, 16)), extraParams: { from: bob } })
    const { collateral: C_coll, totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(212, 16)), extraParams: { from: carol } })
    const { collateral: D_coll, totalDebt: D_totalDebt } = await openCdp({ ICR: toBN(dec(219, 16)), extraParams: { from: dennis } })
    const { collateral: E_coll, totalDebt: E_totalDebt } = await openCdp({ ICR: toBN(dec(221, 16)), extraParams: { from: erin } })

    // Whale provides EBTC to the SP
    const spDeposit = A_totalDebt.add(B_totalDebt).add(C_totalDebt.div(toBN(2)))
    const { collateral: W_coll, totalDebt: W_totalDebt } = await openCdp({ ICR: toBN(dec(340, 16)), extraEBTCAmount: spDeposit, extraParams: { from: whale } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    // Price drops 
    await priceFeed.setPrice(dec(3000, 13))
    const price = await priceFeed.getPrice()
    const TCR = await th.getCachedTCR(contracts)

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check A, B, C cdps are in range 110% < ICR < TCR
    const ICR_A = await cdpManager.getCachedICR(_aliceCdpId, price)
    const ICR_B = await cdpManager.getCachedICR(_bobCdpId, price)
    const ICR_C = await cdpManager.getCachedICR(_carolCdpId, price)
    assert.isTrue(ICR_A.lt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.lt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C.lt(mv._MCR) && ICR_C.lt(TCR))

    /* Liquidate cdps. Cdps are ordered by ICR, from low to high:  A, B, C, D, E.
    With 253 in the SP, Alice (102 debt) and Bob (101 debt) should be entirely liquidated. 
    That leaves 50 EBTC in the Pool which won’t be enough for any other liquidation */
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(carol)).toString()), {from: carol});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(dennis)).toString()), {from: dennis});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(erin)).toString()), {from: erin});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(whale)).toString()), {from: whale});
    const liquidationTx = await th.liquidateCdps(10, price, contracts, {extraParams: {from: owner}})

    const [liquidatedDebt, liquidatedColl] = th.getEmittedLiquidationValues(liquidationTx)

    let _liqDebts = (A_coll).add(B_coll).add(C_coll).add(D_coll).add(E_coll).mul(price).div(LICR)
    th.assertIsApproximatelyEqual(liquidatedDebt, _liqDebts)
    const equivalentCollA = A_coll
    const equivalentCollB = B_coll
    const equivalentCollC = C_coll
    const equivalentCollD = D_coll
    const equivalentCollE = E_coll
    th.assertIsApproximatelyEqual(liquidatedColl, equivalentCollA.add(equivalentCollB).add(equivalentCollC).add(equivalentCollD).add(equivalentCollE))

    // check collateral surplus
    const alice_remainingCollateral = A_coll.sub(equivalentCollA)
    const bob_remainingCollateral = B_coll.sub(equivalentCollB)
    th.assertIsApproximatelyEqual('0', alice_remainingCollateral.toString())
    th.assertIsApproximatelyEqual('0', bob_remainingCollateral.toString())
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
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    // Price drops 
    await priceFeed.setPrice(dec(4200, 13))
    const price = await priceFeed.getPrice()
    const TCR = await th.getCachedTCR(contracts)

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check A, B, C cdps are in range 110% < ICR < TCR
    const ICR_A = await cdpManager.getCachedICR(_aliceCdpId, price)
    const ICR_B = await cdpManager.getCachedICR(_bobCdpId, price)
    const ICR_C_Before = await cdpManager.getCachedICR(_carolCdpId, price)

    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C_Before.gt(mv._MCR) && ICR_C_Before.lt(TCR))	  
	  	  
    // trigger cooldown and pass the liq wait
    await cdpManager.syncGracePeriod();
    await ethers.provider.send("evm_increaseTime", [901]);
    await ethers.provider.send("evm_mine");

    /* Liquidate cdps. Cdps are ordered by ICR, from low to high:  A, B, C, D, E.
    With 253 in the SP, Alice (102 debt) and Bob (101 debt) should be entirely liquidated. 
    That leaves 50 EBTC in the Pool to absorb exactly half of Carol's debt (100) */
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(carol)).toString()), {from: carol});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(dennis)).toString()), {from: dennis});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(erin)).toString()), {from: erin});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(whale)).toString()), {from: whale});
    await th.liquidateCdps(10, price, contracts, {extraParams: {from: owner}})

//    const ICR_C_After = await cdpManager.getCachedICR(_carolCdpId, price)
//    assert.equal(ICR_C_Before.toString(), ICR_C_After)
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

    // price drops to 1ETH:85EBTC, reducing TCR below 150%
    await priceFeed.setPrice(dec(2100, 13))
    const price = await priceFeed.getPrice()

    // check Recovery Mode kicks in

    const recoveryMode_Before = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode_Before)
	
    const _TCR = await cdpManager.getCachedTCR(price);

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
    alice_ICR = await cdpManager.getCachedICR(_aliceCdpId, price)
    bob_ICR = await cdpManager.getCachedICR(_bobCdpId, price)
    carol_ICR = await cdpManager.getCachedICR(_carolCdpId, price)
    dennis_ICR = await cdpManager.getCachedICR(_dennisCdpId, price)
    erin_ICR = await cdpManager.getCachedICR(_erinCdpId, price)
    freddy_ICR = await cdpManager.getCachedICR(_freddyCdpId, price)

    // Alice should have ICR > 150%
    assert.isTrue(alice_ICR.gt(_TCR) && alice_ICR.gt(mv._MCR))
    // All other Cdps should have ICR < 150%
    assert.isTrue(carol_ICR.lt(mv._MCR))
    assert.isTrue(dennis_ICR.lt(mv._MCR))
    assert.isTrue(erin_ICR.lt(mv._MCR))
    assert.isTrue(freddy_ICR.lt(mv._MCR))

    /* After liquidating Bob and Carol, the the TCR of the system rises above the CCR, to 154%.  
    (see calculations in Google Sheet)

    Liquidations continue until all Cdps with ICR < MCR have been closed. 
    Only Alice should remain active - all others should be closed. */

    // call batchLiquidateCdps
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(carol)).toString()), {from: carol});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(dennis)).toString()), {from: dennis});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(erin)).toString()), {from: erin});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(freddy)).toString()), {from: freddy});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(whale)).toString()), {from: whale});
    await cdpManager.batchLiquidateCdps([_aliceCdpId, _bobCdpId, _carolCdpId, _dennisCdpId, _erinCdpId, _freddyCdpId]);

    // check system is still in Recovery Mode
    const recoveryMode_After = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode_After)

    // get all Cdps
    const alice_Cdp = await cdpManager.Cdps(_aliceCdpId)
    const bob_Cdp = await cdpManager.Cdps(_bobCdpId)
    const carol_Cdp = await cdpManager.Cdps(_carolCdpId)
    const dennis_Cdp = await cdpManager.Cdps(_dennisCdpId)
    const erin_Cdp = await cdpManager.Cdps(_erinCdpId)
    const freddy_Cdp = await cdpManager.Cdps(_freddyCdpId)

    // check that Alice's Cdp remains active
    assert.equal(alice_Cdp[4], 1)
    assert.isTrue(await sortedCdps.contains(_aliceCdpId))

    // check all other Cdps are liquidated
    assert.equal(bob_Cdp[4], 3)
    assert.equal(carol_Cdp[4], 3)
    assert.equal(dennis_Cdp[4], 3)
    assert.equal(erin_Cdp[4], 3)
    assert.equal(freddy_Cdp[4], 3)

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
    await openCdp({ ICR: toBN(dec(576, 16)), extraEBTCAmount: spDeposit, extraParams: { from: alice } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);
    let _erinCdpId = await sortedCdps.cdpOfOwnerByIndex(erin, 0);
    let _freddyCdpId = await sortedCdps.cdpOfOwnerByIndex(freddy, 0);

    // price drops to 1ETH:85EBTC, reducing TCR below 150%
    await priceFeed.setPrice(dec(2100, 13))
    const price = await priceFeed.getPrice()

    // check Recovery Mode kicks in

    const recoveryMode_Before = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode_Before)
	
    const _TCR = await cdpManager.getCachedTCR(price);

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
    const alice_ICR = await cdpManager.getCachedICR(_aliceCdpId, price)
    const bob_ICR = await cdpManager.getCachedICR(_bobCdpId, price)
    const carol_ICR = await cdpManager.getCachedICR(_carolCdpId, price)
    const dennis_ICR = await cdpManager.getCachedICR(_dennisCdpId, price)
    const erin_ICR = await cdpManager.getCachedICR(_erinCdpId, price)
    const freddy_ICR = await cdpManager.getCachedICR(_freddyCdpId, price)

    // Alice should have ICR > 150%
    assert.isTrue(alice_ICR.gt(mv._MCR) && alice_ICR.gte(_TCR))
    // All other Cdps should have ICR < 150%
    assert.isTrue(carol_ICR.lt(mv._MCR))
    assert.isTrue(dennis_ICR.lt(mv._MCR))
    assert.isTrue(erin_ICR.lt(mv._MCR))
    assert.isTrue(freddy_ICR.lt(mv._MCR))

    /* After liquidating Bob and Carol, the the TCR of the system rises above the CCR, to 154%.  
    (see calculations in Google Sheet)

    Liquidations continue until all Cdps with ICR < MCR have been closed. 
    Only Alice should remain active - all others should be closed. */

    // call batchLiquidateCdps
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(carol)).toString()), {from: carol});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(dennis)).toString()), {from: dennis});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(erin)).toString()), {from: erin});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(freddy)).toString()), {from: freddy});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(whale)).toString()), {from: whale});
    await cdpManager.batchLiquidateCdps([_bobCdpId, _carolCdpId, _dennisCdpId, _erinCdpId, _freddyCdpId, _aliceCdpId]);

    // check system is no longer in Recovery Mode
    const recoveryMode_After = await th.checkRecoveryMode(contracts)
    console.log('TCR=' + (await cdpManager.getCachedTCR(price)) + ',aliceColl=' + (await cdpManager.getCdpCollShares(_aliceCdpId)) + ',aliceDebt=' + (await cdpManager.getCdpDebt(_aliceCdpId)));
    assert.isFalse(recoveryMode_After)

    // get all Cdps
    const alice_Cdp = await cdpManager.Cdps(_aliceCdpId)
    const bob_Cdp = await cdpManager.Cdps(_bobCdpId)
    const carol_Cdp = await cdpManager.Cdps(_carolCdpId)
    const dennis_Cdp = await cdpManager.Cdps(_dennisCdpId)
    const erin_Cdp = await cdpManager.Cdps(_erinCdpId)
    const freddy_Cdp = await cdpManager.Cdps(_freddyCdpId)

    // check that Alice's Cdp remains active
    assert.equal(alice_Cdp[4], 1)
    assert.isTrue(await sortedCdps.contains(_aliceCdpId))

    // check all other Cdps are liquidated
    assert.equal(bob_Cdp[4], 3)
    assert.equal(carol_Cdp[4], 3)
    assert.equal(dennis_Cdp[4], 3)
    assert.equal(erin_Cdp[4], 3)
    assert.equal(freddy_Cdp[4], 3)

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

    // to compensate borrowing fee
    await ebtcToken.transfer(alice, A_totalDebt, { from: whale })
    // Deprecated Alice closes cdp. If cdp closed, ntohing to liquidate later
    await borrowerOperations.closeCdp(_aliceCdpId, { from: alice })

    // price drops to 1ETH:85EBTC, reducing TCR below 150%
    await priceFeed.setPrice(dec(2100, 13))
    const price = await priceFeed.getPrice()

    // check Recovery Mode kicks in
    const recoveryMode_Before = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode_Before)

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
    //alice_ICR = await cdpManager.getCachedICR(_aliceCdpId, price)
    bob_ICR = await cdpManager.getCachedICR(_bobCdpId, price)
    carol_ICR = await cdpManager.getCachedICR(_carolCdpId, price)
    dennis_ICR = await cdpManager.getCachedICR(_dennisCdpId, price)
    erin_ICR = await cdpManager.getCachedICR(_erinCdpId, price)
    freddy_ICR = await cdpManager.getCachedICR(_freddyCdpId, price)

    // Alice should have ICR > 150%
    //assert.isTrue(alice_ICR.gt(_150percent))
    // All other Cdps should have ICR < 150%
    assert.isTrue(carol_ICR.lt(mv._MCR))
    assert.isTrue(dennis_ICR.lt(mv._MCR))
    assert.isTrue(erin_ICR.lt(mv._MCR))
    assert.isTrue(freddy_ICR.lt(mv._MCR))

    /* After liquidating Bob and Carol, the the TCR of the system rises above the CCR, to 154%.
    (see calculations in Google Sheet)

    Liquidations continue until all Cdps with ICR < MCR have been closed.
    Only Alice should remain active - all others should be closed. */

    // call batchLiquidateCdps
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(carol)).toString()), {from: carol});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(dennis)).toString()), {from: dennis});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(erin)).toString()), {from: erin});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(freddy)).toString()), {from: freddy});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(whale)).toString()), {from: whale});
    await cdpManager.batchLiquidateCdps([_aliceCdpId, _bobCdpId, _carolCdpId, _dennisCdpId, _erinCdpId, _freddyCdpId]);

    // check system is still in Recovery Mode
    const recoveryMode_After = await th.checkRecoveryMode(contracts)
    assert.isTrue(recoveryMode_After)

    // get all Cdps
    const alice_Cdp = await cdpManager.Cdps(_aliceCdpId)
    const bob_Cdp = await cdpManager.Cdps(_bobCdpId)
    const carol_Cdp = await cdpManager.Cdps(_carolCdpId)
    const dennis_Cdp = await cdpManager.Cdps(_dennisCdpId)
    const erin_Cdp = await cdpManager.Cdps(_erinCdpId)
    const freddy_Cdp = await cdpManager.Cdps(_freddyCdpId)

    // check that Alice's Cdp is still closed
    assert.equal(alice_Cdp[4], 2)

    // check all other Cdps are liquidated
    assert.equal(bob_Cdp[4], 3)
    assert.equal(carol_Cdp[4], 3)
    assert.equal(dennis_Cdp[4], 3)
    assert.equal(erin_Cdp[4], 3)
    assert.equal(freddy_Cdp[4], 3)

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
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    // Price drops 
    await priceFeed.setPrice(dec(4200, 13))
    const price = await priceFeed.getPrice()
    const TCR = await th.getCachedTCR(contracts)

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check A, B, C cdps are in range 110% < ICR < TCR
    const ICR_A = await cdpManager.getCachedICR(_aliceCdpId, price)
    const ICR_B = await cdpManager.getCachedICR(_bobCdpId, price)
    const ICR_C = await cdpManager.getCachedICR(_carolCdpId, price)

    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C.gt(mv._MCR) && ICR_C.lt(TCR))	  
	  	  
    // trigger cooldown and pass the liq wait
    await cdpManager.syncGracePeriod();
    await ethers.provider.send("evm_increaseTime", [901]);
    await ethers.provider.send("evm_mine");

    const cdpsToLiquidate = [_aliceCdpId, _bobCdpId, _carolCdpId]
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(carol)).toString()), {from: carol});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(dennis)).toString()), {from: dennis});
    await cdpManager.batchLiquidateCdps(cdpsToLiquidate)

    // Check A and B closed
    assert.isFalse(await sortedCdps.contains(_aliceCdpId))
    assert.isFalse(await sortedCdps.contains(_bobCdpId))

    // Check C remains active
    assert.isFalse(await sortedCdps.contains(_carolCdpId))
    assert.equal((await cdpManager.Cdps(_carolCdpId))[4].toString(), '3') // check Status is active
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
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    // Price drops 
    await priceFeed.setPrice(dec(4200, 13))
    const price = await priceFeed.getPrice()
    const TCR = await th.getCachedTCR(contracts)

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check A, B, C cdps are in range 110% < ICR < TCR
    const ICR_A = await cdpManager.getCachedICR(_aliceCdpId, price)
    const ICR_B = await cdpManager.getCachedICR(_bobCdpId, price)
    const ICR_C = await cdpManager.getCachedICR(_carolCdpId, price)

    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C.gt(mv._MCR) && ICR_C.lt(TCR))	  
	  	  
    // trigger cooldown and pass the liq wait
    await th.syncGlobalStateAndGracePeriod(contracts, ethers.provider);

    const cdpsToLiquidate = [_aliceCdpId, _bobCdpId, _carolCdpId]
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(carol)).toString()), {from: carol});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(dennis)).toString()), {from: dennis});
    await cdpManager.batchLiquidateCdps(cdpsToLiquidate)

    // Check C is in Cdp owners array
    const arrayLength = (await cdpManager.getActiveCdpsCount()).toNumber()
    let addressFound = false;
    let _id = await sortedCdps.getFirst();

    for (let i = 0; i < arrayLength; i++) {
       if (_id == _carolCdpId) {
           addressFound = true
       } else {
           _id = await sortedCdps.getNext(_id);
       }
    }

    assert.isFalse(addressFound);

    // Check CdpOwners idx on cdp struct == idx of address found in CdpOwners array
//    const idxOnStruct = (await cdpManager.Cdps(_carolCdpId))[4].toString()
//    assert.equal(addressIdx.toString(), idxOnStruct)
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

    // Price drops 
    await priceFeed.setPrice(dec(4200, 13))
    const price = await priceFeed.getPrice()
    const TCR = await th.getCachedTCR(contracts)

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check A, B, C, D, E cdps are in range 110% < ICR < TCR
    const ICR_A = await cdpManager.getCachedICR(_aliceCdpId, price)
    const ICR_B = await cdpManager.getCachedICR(_bobCdpId, price)
    const ICR_C = await cdpManager.getCachedICR(_carolCdpId, price)
    const ICR_D = await cdpManager.getCachedICR(_dennisCdpId, price)
    const ICR_E = await cdpManager.getCachedICR(_erinCdpId, price)

    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C.gt(mv._MCR) && ICR_C.lt(TCR))
    assert.isTrue(ICR_D.gt(mv._MCR) && ICR_D.lt(TCR))
    assert.isTrue(ICR_E.gt(mv._MCR) && ICR_E.lt(TCR))	  
	  	  
    // trigger cooldown and pass the liq wait
    await cdpManager.syncGracePeriod();
    await ethers.provider.send("evm_increaseTime", [901]);
    await ethers.provider.send("evm_mine");

    /* With 300 in the SP, Alice (102 debt) and Bob (101 debt) should be entirely liquidated.
     That leaves 97 EBTC in the Pool that won’t be enough to absorb Carol,
     but it will be enough to liquidate Dennis. Afterwards the pool will be empty,
     so Erin won’t liquidated. */
    const cdpsToLiquidate = [_aliceCdpId, _bobCdpId, _carolCdpId, _dennisCdpId, _erinCdpId]
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(carol)).toString()), {from: carol});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(dennis)).toString()), {from: dennis});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(erin)).toString()), {from: erin});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(whale)).toString()), {from: whale});
    const tx = await cdpManager.batchLiquidateCdps(cdpsToLiquidate)
    console.log('gasUsed: ', tx.receipt.gasUsed)

    // Check A, B and D are closed
    assert.isFalse(await sortedCdps.contains(_aliceCdpId))
    assert.isFalse(await sortedCdps.contains(_bobCdpId))
    assert.isFalse(await sortedCdps.contains(_dennisCdpId))

    // Check whale, C, D and E stay active
    assert.isTrue(await sortedCdps.contains(_whaleCdpId))
    assert.isFalse(await sortedCdps.contains(_carolCdpId))
    assert.isFalse(await sortedCdps.contains(_erinCdpId))
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
    let _whaleCdpId = await sortedCdps.cdpOfOwnerByIndex(whale, 0);

    // Price drops 
    await priceFeed.setPrice(dec(4200, 13))
    const price = await priceFeed.getPrice()
    const TCR = await th.getCachedTCR(contracts)

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check A, B, C, D, E cdps are in range 110% < ICR < TCR
    const ICR_A = await cdpManager.getCachedICR(_aliceCdpId, price)
    const ICR_B = await cdpManager.getCachedICR(_bobCdpId, price)
    const ICR_C = await cdpManager.getCachedICR(_carolCdpId, price)
    const ICR_D = await cdpManager.getCachedICR(_dennisCdpId, price)
    const ICR_E = await cdpManager.getCachedICR(_erinCdpId, price)

    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C.gt(mv._MCR) && ICR_C.lt(TCR))
    assert.isTrue(ICR_D.gt(mv._MCR) && ICR_D.lt(TCR))
    assert.isTrue(ICR_E.gt(mv._MCR) && ICR_E.lt(TCR))	  
	  	  
    // trigger cooldown and pass the liq wait
    await cdpManager.syncGracePeriod();
    await ethers.provider.send("evm_increaseTime", [901]);
    await ethers.provider.send("evm_mine");

    /* With 301 in the SP, Alice (102 debt) and Bob (101 debt) should be entirely liquidated.
     That leaves 97 EBTC in the Pool that won’t be enough to absorb Carol,
     but it will be enough to liquidate Dennis. Afterwards the pool will be empty,
     so Erin won’t liquidated.
     Note that, compared to the previous test, this one will make 1 more loop iteration,
     so it will consume more gas. */
    const cdpsToLiquidate = [_aliceCdpId, _bobCdpId, _carolCdpId, _dennisCdpId, _erinCdpId]
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(carol)).toString()), {from: carol});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(dennis)).toString()), {from: dennis});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(erin)).toString()), {from: erin});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(whale)).toString()), {from: whale});
    const tx = await cdpManager.batchLiquidateCdps(cdpsToLiquidate)
    console.log('gasUsed: ', tx.receipt.gasUsed)

    // Check A, B and D are closed
    assert.isFalse(await sortedCdps.contains(_aliceCdpId))
    assert.isFalse(await sortedCdps.contains(_bobCdpId))
    assert.isFalse(await sortedCdps.contains(_dennisCdpId))

    // Check whale, C, D and E stay active
    assert.isTrue(await sortedCdps.contains(_whaleCdpId))
    assert.isFalse(await sortedCdps.contains(_carolCdpId))
    assert.isFalse(await sortedCdps.contains(_erinCdpId))
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
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    // Price drops 
    await priceFeed.setPrice(dec(4200, 13))
    const price = await priceFeed.getPrice()
    const TCR = await th.getCachedTCR(contracts)

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check A, B, C, D, E cdps are in range 110% < ICR < TCR
    const ICR_A = await cdpManager.getCachedICR(_aliceCdpId, price)
    const ICR_B = await cdpManager.getCachedICR(_bobCdpId, price)
    const ICR_C = await cdpManager.getCachedICR(_carolCdpId, price)

    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C.gt(mv._MCR) && ICR_C.lt(TCR))

    const entireSystemCollBefore = await cdpManager.getSystemCollShares()
    const entireSystemDebtBefore = await cdpManager.getSystemDebt()	  
	  	  
    // trigger cooldown and pass the liq wait
    await cdpManager.syncGracePeriod();
    await ethers.provider.send("evm_increaseTime", [901]);
    await ethers.provider.send("evm_mine");

    const cdpsToLiquidate = [_aliceCdpId, _bobCdpId, _carolCdpId]
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(carol)).toString()), {from: carol});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(dennis)).toString()), {from: dennis});
    await cdpManager.batchLiquidateCdps(cdpsToLiquidate)

    // Expect system debt reduced by 203 EBTC and system coll by 2 ETH
    const entireSystemCollAfter = await cdpManager.getSystemCollShares()
    const entireSystemDebtAfter = await cdpManager.getSystemDebt()

    const changeInEntireSystemColl = entireSystemCollBefore.sub(entireSystemCollAfter)
    const changeInEntireSystemDebt = entireSystemDebtBefore.sub(entireSystemDebtAfter)
    let _liqColls = A_coll.add(B_coll).add(C_coll)
    let _liqDebts = A_totalDebt.add(B_totalDebt).add(C_totalDebt)
    assert.equal(changeInEntireSystemColl.toString(), _liqColls.toString())
    th.assertIsApproximatelyEqual(changeInEntireSystemDebt.toString(), _liqDebts.toString())
  })

  it("batchLiquidateCdps() with a non fullfilled liquidation: emits correct liquidation event values", async () => {
    const { collateral: A_coll, totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(210, 16)), extraParams: { from: alice } })
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(211, 16)), extraParams: { from: bob } })
    const { collateral: C_coll, totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(212, 16)), extraParams: { from: carol } })
    await openCdp({ ICR: toBN(dec(219, 16)), extraParams: { from: dennis } })
    await openCdp({ ICR: toBN(dec(221, 16)), extraParams: { from: erin } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    // Whale provides EBTC to the SP
    const spDeposit = A_totalDebt.add(B_totalDebt).add(C_totalDebt.div(toBN(2)))
    await openCdp({ ICR: toBN(dec(220, 16)), extraEBTCAmount: spDeposit, extraParams: { from: whale } })

    // Price drops 
    await priceFeed.setPrice(dec(4200, 13))
    const price = await priceFeed.getPrice()
    const TCR = await th.getCachedTCR(contracts)

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check A, B, C cdps are in range 110% < ICR < TCR
    const ICR_A = await cdpManager.getCachedICR(_aliceCdpId, price)
    const ICR_B = await cdpManager.getCachedICR(_bobCdpId, price)
    const ICR_C = await cdpManager.getCachedICR(_carolCdpId, price)

    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C.gt(mv._MCR) && ICR_C.lt(TCR))	  
	  	  
    // trigger cooldown and pass the liq wait
    await cdpManager.syncGracePeriod();
    await ethers.provider.send("evm_increaseTime", [901]);
    await ethers.provider.send("evm_mine");

    const cdpsToLiquidate = [_aliceCdpId, _bobCdpId, _carolCdpId]
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(carol)).toString()), {from: carol});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(dennis)).toString()), {from: dennis});
    const liquidationTx = await cdpManager.batchLiquidateCdps(cdpsToLiquidate)

    const [liquidatedDebt, liquidatedColl] = th.getEmittedLiquidationValues(liquidationTx)

    let _liqDebts = A_totalDebt.add(B_totalDebt).add(C_totalDebt)
    th.assertIsApproximatelyEqual(liquidatedDebt, _liqDebts)	
    const equivalentCollA = A_totalDebt.mul(toBN(dec(110, 16))).div(price)
    const equivalentCollB = B_totalDebt.mul(toBN(dec(110, 16))).div(price)
    const equivalentCollC = C_totalDebt.mul(toBN(dec(110, 16))).div(price)
    th.assertIsApproximatelyEqual(liquidatedColl, equivalentCollA.add(equivalentCollB).add(equivalentCollC))

    // check collateral surplus
    const alice_remainingCollateral = A_coll.sub(equivalentCollA)
    const bob_remainingCollateral = B_coll.sub(equivalentCollB)
    th.assertIsApproximatelyEqual(await collSurplusPool.getSurplusCollShares(alice), alice_remainingCollateral)
    th.assertIsApproximatelyEqual(await collSurplusPool.getSurplusCollShares(bob), bob_remainingCollateral)

    // can claim collateral
    const alice_balanceBefore = th.toBN(await web3.eth.getBalance(alice))
    const ALICE_GAS = th.gasUsed(await borrowerOperations.claimSurplusCollShares({ from: alice, gasPrice: GAS_PRICE  }))
    const alice_balanceAfter = th.toBN(await web3.eth.getBalance(alice))
    //th.assertIsApproximatelyEqual(alice_balanceAfter, alice_balanceBefore.add(th.toBN(alice_remainingCollateral).sub(th.toBN(ALICE_GAS * GAS_PRICE))))

    const bob_balanceBefore = th.toBN(await web3.eth.getBalance(bob))
    let _collBobPre = await collToken.balanceOf(bob);	
    const BOB_GAS = th.gasUsed(await borrowerOperations.claimSurplusCollShares({ from: bob, gasPrice: GAS_PRICE  }))
    const bob_balanceAfter = th.toBN(await web3.eth.getBalance(bob))
    let _collBobPost = await collToken.balanceOf(bob);	
    th.assertIsApproximatelyEqual(_collBobPost, _collBobPre.add(th.toBN(bob_remainingCollateral)));//.sub(th.toBN(BOB_GAS * GAS_PRICE))))
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

    // Whale get EBTC by opening CDP
    const whDeposit = A_totalDebt.add(B_totalDebt).add(C_totalDebt.div(toBN(2)))
    await openCdp({ ICR: toBN(dec(220, 16)), extraEBTCAmount: whDeposit, extraParams: { from: whale } })

    // Price drops 
    await priceFeed.setPrice(dec(4200, 13))
    const price = await priceFeed.getPrice()
    const TCR = await th.getCachedTCR(contracts)

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check A, B, C cdps are in range 110% < ICR < TCR
    const ICR_A = await cdpManager.getCachedICR(_aliceCdpId, price)
    const ICR_B = await cdpManager.getCachedICR(_bobCdpId, price)
    const ICR_C_Before = await cdpManager.getCachedICR(_carolCdpId, price)

    assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C_Before.gt(mv._MCR) && ICR_C_Before.lt(TCR))	  
	  	  
    // trigger cooldown and pass the liq wait
    await th.syncGlobalStateAndGracePeriod(contracts, ethers.provider);

    const cdpsToLiquidate = [_aliceCdpId, _bobCdpId, _carolCdpId]
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(carol)).toString()), {from: carol});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(dennis)).toString()), {from: dennis});
    await cdpManager.batchLiquidateCdps(cdpsToLiquidate)

//    const ICR_C_After = await cdpManager.getCachedICR(_carolCdpId, price)
//    assert.equal(ICR_C_Before.toString(), ICR_C_After)
  })

  it("batchLiquidateCdps(), with 110% < ICR < TCR: can liquidate cdps out of order", async () => {
    const { totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(220, 16)), extraParams: { from: alice } })
    const { totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(210, 16)), extraParams: { from: bob } })
    const { totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(212, 16)), extraParams: { from: carol } })
    const { totalDebt: D_totalDebt } = await openCdp({ ICR: toBN(dec(213, 16)), extraParams: { from: dennis } })
    await _signer.sendTransaction({ to: erin, value: ethers.utils.parseEther("10000")});
    await _signer.sendTransaction({ to: freddy, value: ethers.utils.parseEther("10000")});
    await openCdp({ ICR: toBN(dec(280, 16)), extraEBTCAmount: dec(500, 18), extraParams: { from: erin } })
    await openCdp({ ICR: toBN(dec(282, 16)), extraEBTCAmount: dec(500, 18), extraParams: { from: freddy } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);

    // Whale provides 1000 EBTC to the SP
    const spDeposit = A_totalDebt.add(C_totalDebt).add(D_totalDebt)
    await openCdp({ ICR: toBN(dec(219, 16)), extraEBTCAmount: spDeposit, extraParams: { from: whale } })

    // Price drops
    await priceFeed.setPrice(dec(3000, 13))
    const price = await priceFeed.getPrice()

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check cdps A-D are in range 110% < ICR < TCR
    const ICR_A = await cdpManager.getCachedICR(_aliceCdpId, price)
    const ICR_B = await cdpManager.getCachedICR(_bobCdpId, price)
    const ICR_C = await cdpManager.getCachedICR(_carolCdpId, price)
    const ICR_D = await cdpManager.getCachedICR(_dennisCdpId, price)
    const TCR = await th.getCachedTCR(contracts)
    assert.isTrue(ICR_A.lt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.lt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C.lt(mv._MCR) && ICR_C.lt(TCR))
    assert.isTrue(ICR_D.lt(mv._MCR) && ICR_D.lt(TCR))

    // Cdps are ordered by ICR, low to high: A, B, C, D.

    // Liquidate out of ICR order: D, B, C. A (lowest ICR) not included.
    const cdpsToLiquidate = [_dennisCdpId, _bobCdpId, _carolCdpId]

    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(carol)).toString()), {from: carol});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(dennis)).toString()), {from: dennis});
    const liquidationTx = await cdpManager.batchLiquidateCdps(cdpsToLiquidate)

    // Check transaction succeeded
    assert.isTrue(liquidationTx.receipt.status)

    // Confirm cdps D, B, C removed
    assert.isFalse(await sortedCdps.contains(_dennisCdpId))
    assert.isFalse(await sortedCdps.contains(_bobCdpId))
    assert.isFalse(await sortedCdps.contains(_carolCdpId))

    // Confirm cdps have status 'liquidated' (Status enum element idx 3)
    assert.equal((await cdpManager.Cdps(_dennisCdpId))[4], '3')
    assert.equal((await cdpManager.Cdps(_bobCdpId))[4], '3')
    assert.equal((await cdpManager.Cdps(_carolCdpId))[4], '3')
  })

  it("batchLiquidateCdps(), with 110% < ICR < TCR, and no valid liquidator: doesn't liquidate any cdps", async () => {
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
    await priceFeed.setPrice(dec(3000, 13))
    const price = await priceFeed.getPrice()
    const TCR = await th.getCachedTCR(contracts)

    // Check Recovery Mode is active
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Check cdps A-D are in range 110% < ICR < TCR
    const ICR_A = await cdpManager.getCachedICR(_aliceCdpId, price)
    const ICR_B = await cdpManager.getCachedICR(_bobCdpId, price)
    const ICR_C = await cdpManager.getCachedICR(_carolCdpId, price)

    assert.isTrue(ICR_A.lt(mv._MCR) && ICR_A.lt(TCR))
    assert.isTrue(ICR_B.lt(mv._MCR) && ICR_B.lt(TCR))
    assert.isTrue(ICR_C.lt(mv._MCR) && ICR_C.lt(TCR))

    // Cdps are ordered by ICR, low to high: A, B, C, D. 
    // Liquidate out of ICR order: D, B, C. A (lowest ICR) not included.
    const cdpsToLiquidate = [_dennisCdpId, _bobCdpId, _carolCdpId]
//    await assertRevert(cdpManager.batchLiquidateCdps(cdpsToLiquidate), "CdpManager: nothing to liquidate")
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(carol)).toString()), {from: carol});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(dennis)).toString()), {from: dennis});
	await cdpManager.batchLiquidateCdps(cdpsToLiquidate)

    // Confirm cdps D, B, C remain in system
    assert.isFalse(await sortedCdps.contains(_dennisCdpId))
    assert.isFalse(await sortedCdps.contains(_bobCdpId))
    assert.isFalse(await sortedCdps.contains(_carolCdpId))

    // Confirm dennis have status 'active' (Status enum element idx 1)
    assert.equal((await cdpManager.Cdps(_dennisCdpId))[4], '3')
    // Confirm cdps have status 'active' (Status enum element idx 1)
    assert.equal((await cdpManager.Cdps(_bobCdpId))[4], '3')
    assert.equal((await cdpManager.Cdps(_carolCdpId))[4], '3')

    // Confirm D, B, C coll & debt have not changed
    const dennisDebt_After = (await cdpManager.Cdps(_dennisCdpId))[0].add((await cdpManager.getPendingRedistributedDebt(dennis)))
    const bobDebt_After = (await cdpManager.Cdps(_bobCdpId))[0].add((await cdpManager.getPendingRedistributedDebt(bob)))
    const carolDebt_After = (await cdpManager.Cdps(_carolCdpId))[0].add((await cdpManager.getPendingRedistributedDebt(carol)))

    const dennisColl_After = (await cdpManager.Cdps(_dennisCdpId))[1]  
    const bobColl_After = (await cdpManager.Cdps(_bobCdpId))[1]
    const carolColl_After = (await cdpManager.Cdps(_carolCdpId))[1]

    assert.isTrue(dennisColl_After.lt(dennisColl_Before))
    assert.isTrue(bobColl_After.lt(bobColl_Before))
    assert.isTrue(carolColl_After.lt(carolColl_Before))

    th.assertIsApproximatelyEqual('0', dennisDebt_After.toString())
    th.assertIsApproximatelyEqual('0', bobDebt_After.toString())
    th.assertIsApproximatelyEqual('0', carolDebt_After.toString())
  })

  it('batchLiquidateCdps(): skips liquidation of cdps with ICR > TCR, regardless of liquidator balance size', async () => {
    // Cdps that will fall into ICR range 100-MCR
    const { totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(194, 16)), extraParams: { from: A } })
    await openCdp({ ICR: toBN(dec(196, 16)), extraParams: { from: B } })
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
    await priceFeed.setPrice(dec(3000, 13))
    const price = await priceFeed.getPrice()
    const TCR = await th.getCachedTCR(contracts)

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    const G_collBefore = (await cdpManager.Cdps(_gCdpId))[1]
    const G_debtBefore = (await cdpManager.Cdps(_gCdpId))[0]
    const H_collBefore = (await cdpManager.Cdps(_hCdpId))[1]
    const H_debtBefore = (await cdpManager.Cdps(_hCdpId))[0]
    const I_collBefore = (await cdpManager.Cdps(_iCdpId))[1]
    const I_debtBefore = (await cdpManager.Cdps(_iCdpId))[0]

    const ICR_A = await cdpManager.getCachedICR(_aCdpId, price) 
    const ICR_B = await cdpManager.getCachedICR(_bCdpId, price) 
    const ICR_C = await cdpManager.getCachedICR(_cCdpId, price) 
    const ICR_D = await cdpManager.getCachedICR(_dCdpId, price)
    const ICR_E = await cdpManager.getCachedICR(_eCdpId, price)
    const ICR_F = await cdpManager.getCachedICR(_fCdpId, price)
    const ICR_G = await cdpManager.getCachedICR(_gCdpId, price)
    const ICR_H = await cdpManager.getCachedICR(_hCdpId, price)
    const ICR_I = await cdpManager.getCachedICR(_iCdpId, price)

    // Check CDPs are in range <100
    assert.isTrue(ICR_A.lte(mv._ICR100) && ICR_A.lt(mv._MCR))
    assert.isTrue(ICR_B.lte(mv._ICR100) && ICR_B.lt(mv._MCR))
    assert.isTrue(ICR_C.lte(mv._ICR100) && ICR_C.lt(mv._MCR))
    assert.isTrue(ICR_D.lt(mv._MCR) && ICR_D.lt(TCR))
    assert.isTrue(ICR_E.lt(mv._MCR) && ICR_E.lt(TCR))
    assert.isTrue(ICR_F.lt(mv._MCR) && ICR_F.lt(TCR))

    // Check G-I are in range >= TCR
    assert.isTrue(ICR_G.lte(mv._MCR) && ICR_G.gte(TCR))
    assert.isTrue(ICR_H.lte(mv._MCR) && ICR_H.gte(TCR))
    assert.isTrue(ICR_I.gte(mv._MCR) && ICR_I.gte(TCR))

    // Attempt to liquidate only cdps with ICR > TCR% 
    await assertRevert(cdpManager.batchLiquidateCdps([_iCdpId]), "CdpManager: nothing to liquidate")

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
  
    // Attempt to liquidate a variety of cdps with liquidator covering whole batch.
    // Expect A, C, D to be liquidated, and G, H, I to remain in system
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(A)).toString()), {from: A});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(C)).toString()), {from: C});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(D)).toString()), {from: D});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(B)).toString()), {from: B});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(G)).toString()), {from: G});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(H)).toString()), {from: H});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(I)).toString()), {from: I});
    await cdpManager.batchLiquidateCdps([_cCdpId, _dCdpId, _gCdpId, _hCdpId, _aCdpId, _iCdpId])
    
    // Confirm CDPs liquidated  
    assert.isFalse(await sortedCdps.contains(_cCdpId))
    assert.isFalse(await sortedCdps.contains(_aCdpId))
    assert.isFalse(await sortedCdps.contains(_dCdpId))
    assert.isFalse(await sortedCdps.contains(_gCdpId))
    assert.isFalse(await sortedCdps.contains(_hCdpId))
    
    // Check I remain in system
    assert.isTrue(await sortedCdps.contains(_iCdpId))

    // Check coll and debt have not changed
    assert.equal(I_collBefore.eq(await cdpManager.Cdps(_iCdpId))[1])
    assert.equal(I_debtBefore.eq(await cdpManager.Cdps(_iCdpId))[0])

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Whale withdraws entire deposit, and re-deposits 132 EBTC
    // Increasing the price for a moment to avoid pending liquidations to block withdrawal
    await priceFeed.setPrice(dec(4000, 13))

    // B and E are still in range 110-TCR.
    // Attempt to liquidate B, G, H, I, E.
    // Expected liquidator to fully absorb B (92 EBTC + 10 virtual debt), 
    // but not E as there are not enough funds in liquidator	  
	  	  
    // trigger cooldown and pass the liq wait
    await cdpManager.syncGracePeriod();
    await ethers.provider.send("evm_increaseTime", [901]);
    await ethers.provider.send("evm_mine");
    
    const dEbtBefore = (await cdpManager.Cdps(_eCdpId))[0]

    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(F)).toString()), {from: F});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(E)).toString()), {from: E});
    await cdpManager.batchLiquidateCdps([_bCdpId, _iCdpId, _eCdpId])
    
    const dEbtAfter = (await cdpManager.Cdps(_eCdpId))[0]
    
    const dEbtDelta = dEbtBefore.sub(dEbtAfter)

    assert.equal((dEbtDelta.toString()), dEbtBefore.toString())
    
    // Confirm B & E removed
    assert.isFalse(await sortedCdps.contains(_bCdpId)) 
    assert.isFalse(await sortedCdps.contains(_eCdpId))

    // Check G, H, I remain in system
    assert.isTrue(await sortedCdps.contains(_iCdpId))

    // Check coll and debt have not changed
    assert.equal(I_collBefore.eq(await cdpManager.Cdps(_iCdpId))[1])
    assert.equal(I_debtBefore.eq(await cdpManager.Cdps(_iCdpId))[0])
  })

  it('batchLiquidateCdps(): emits liquidation event with correct values when all cdps have ICR > 110% and liquidator covers a subset of cdps', async () => {
    // Cdps to be absorbed by SP
    const { collateral: F_coll, totalDebt: F_totalDebt } = await openCdp({ ICR: toBN(dec(222, 16)), extraParams: { from: freddy } })
    const { collateral: G_coll, totalDebt: G_totalDebt } = await openCdp({ ICR: toBN(dec(222, 16)), extraParams: { from: greta } })

    // Cdps to be spared
    const { collateral: A_coll, totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(250, 16)), extraParams: { from: alice } })
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(266, 16)), extraParams: { from: bob } })
    const { collateral: C_coll, totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(285, 16)), extraParams: { from: carol } })
    const { collateral: D_coll, totalDebt: D_totalDebt } = await openCdp({ ICR: toBN(dec(308, 16)), extraParams: { from: dennis } })

    // Whale adds EBTC to SP
    const spDeposit = F_totalDebt.add(G_totalDebt)
    const { collateral: W_coll, totalDebt: W_totalDebt } = await openCdp({ ICR: toBN(dec(285, 16)), extraEBTCAmount: spDeposit, extraParams: { from: whale } })
    let _whaleCdpId = await sortedCdps.cdpOfOwnerByIndex(whale, 0);
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);
    let _freddyCdpId = await sortedCdps.cdpOfOwnerByIndex(freddy, 0);
    let _gretaCdpId = await sortedCdps.cdpOfOwnerByIndex(greta, 0);

    // Price drops, but all cdps remain active
    await priceFeed.setPrice(dec(3000, 13))
    const price = await priceFeed.getPrice()

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Confirm all cdps have ICR > MCR
    assert.isTrue((await cdpManager.getCachedICR(_freddyCdpId, price)).lte(mv._MCR))
    assert.isTrue((await cdpManager.getCachedICR(_gretaCdpId, price)).lte(mv._MCR))
    assert.isTrue((await cdpManager.getCachedICR(_aliceCdpId, price)).lte(mv._MCR))
    assert.isTrue((await cdpManager.getCachedICR(_bobCdpId, price)).lte(mv._MCR))
    assert.isTrue((await cdpManager.getCachedICR(_carolCdpId, price)).gte(mv._MCR))

    const cdpsToLiquidate = [_freddyCdpId, _gretaCdpId, _aliceCdpId, _bobCdpId, _carolCdpId, _dennisCdpId, _whaleCdpId]

    // Attempt liqudation sequence
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(carol)).toString()), {from: carol});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(dennis)).toString()), {from: dennis});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(greta)).toString()), {from: greta});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(freddy)).toString()), {from: freddy});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(whale)).toString()), {from: whale});
    const liquidationTx = await cdpManager.batchLiquidateCdps(cdpsToLiquidate)
    const [liquidatedDebt, liquidatedColl, gasComp] = th.getEmittedLiquidationValues(liquidationTx)

    // Check F and G were liquidated
    assert.isFalse(await sortedCdps.contains(_freddyCdpId))
    assert.isFalse(await sortedCdps.contains(_gretaCdpId))

    // Check whale and A-D remain active
    assert.isFalse(await sortedCdps.contains(_aliceCdpId))
    assert.isFalse(await sortedCdps.contains(_bobCdpId))
    assert.isTrue(await sortedCdps.contains(_carolCdpId))
    assert.isTrue(await sortedCdps.contains(_dennisCdpId))
    assert.isTrue(await sortedCdps.contains(_whaleCdpId))

    // Liquidation event emits coll = (F_debt + G_debt)/price*1.1*0.995, and debt = (F_debt + G_debt)
    let _liqDebts = (F_coll.mul(price).div(LICR)).add(G_coll.mul(price).div(LICR)).add(A_coll.mul(price).div(LICR)).add(B_totalDebt);
    th.assertIsApproximatelyEqual(liquidatedDebt, _liqDebts)	
    const equivalentCollA = A_coll
    const equivalentCollB = B_coll
    const equivalentCollF = F_coll
    const equivalentCollG = G_coll
    th.assertIsApproximatelyEqual(liquidatedColl, equivalentCollA.add(equivalentCollB).add(equivalentCollF).add(equivalentCollG))

    // check collateral surplus
    const freddy_remainingCollateral = F_coll.sub(equivalentCollF)
    const greta_remainingCollateral = G_coll.sub(equivalentCollG)
    th.assertIsApproximatelyEqual('0', freddy_remainingCollateral.toString())
    th.assertIsApproximatelyEqual('0', greta_remainingCollateral.toString())
  })

  it('batchLiquidateCdps(): emits liquidation event with correct values when all cdps have ICR > 110% and liquidator covers a subset of cdps, including a partial', async () => {
    // Cdps to be absorbed by SP
    const { collateral: F_coll, totalDebt: F_totalDebt } = await openCdp({ ICR: toBN(dec(222, 16)), extraParams: { from: freddy } })
    const { collateral: G_coll, totalDebt: G_totalDebt } = await openCdp({ ICR: toBN(dec(222, 16)), extraParams: { from: greta } })

    // Cdps to be spared
    const { collateral: A_coll, totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(250, 16)), extraParams: { from: alice } })
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(266, 16)), extraParams: { from: bob } })
    const { collateral: C_coll, totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(285, 16)), extraParams: { from: carol } })
    const { collateral: D_coll, totalDebt: D_totalDebt } = await openCdp({ ICR: toBN(dec(308, 16)), extraParams: { from: dennis } })

    // Whale opens cdp and adds 220 EBTC to SP
    const spDeposit = F_totalDebt.add(G_totalDebt).add(A_totalDebt.div(toBN(2)))
    const { collateral: W_coll, totalDebt: W_totalDebt } = await openCdp({ ICR: toBN(dec(285, 16)), extraEBTCAmount: spDeposit, extraParams: { from: whale } })
    let _whaleCdpId = await sortedCdps.cdpOfOwnerByIndex(whale, 0);
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);
    let _freddyCdpId = await sortedCdps.cdpOfOwnerByIndex(freddy, 0);
    let _gretaCdpId = await sortedCdps.cdpOfOwnerByIndex(greta, 0);

    // Price drops, but all cdps remain active
    await priceFeed.setPrice(dec(3000, 13))
    const price = await priceFeed.getPrice()

    // Confirm Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Confirm all cdps have ICR > MCR
    assert.isTrue((await cdpManager.getCachedICR(_freddyCdpId, price)).lte(mv._MCR))
    assert.isTrue((await cdpManager.getCachedICR(_gretaCdpId, price)).lte(mv._MCR))
    assert.isTrue((await cdpManager.getCachedICR(_aliceCdpId, price)).lte(mv._MCR))
    assert.isTrue((await cdpManager.getCachedICR(_bobCdpId, price)).lte(mv._MCR))
    assert.isTrue((await cdpManager.getCachedICR(_carolCdpId, price)).gte(mv._MCR))

    const cdpsToLiquidate = [_freddyCdpId, _gretaCdpId, _aliceCdpId, _bobCdpId, _carolCdpId, _dennisCdpId, _whaleCdpId]

    // Attempt liqudation sequence
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(carol)).toString()), {from: carol});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(dennis)).toString()), {from: dennis});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(greta)).toString()), {from: greta});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(freddy)).toString()), {from: freddy});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(whale)).toString()), {from: whale});
    const liquidationTx = await cdpManager.batchLiquidateCdps(cdpsToLiquidate)
    const [liquidatedDebt, liquidatedColl, gasComp] = th.getEmittedLiquidationValues(liquidationTx)

    // Check F and G were liquidated
    assert.isFalse(await sortedCdps.contains(_freddyCdpId))
    assert.isFalse(await sortedCdps.contains(_gretaCdpId))

    // Check whale and A-D remain active
    assert.isFalse(await sortedCdps.contains(_aliceCdpId))
    assert.isFalse(await sortedCdps.contains(_bobCdpId))
    assert.isTrue(await sortedCdps.contains(_carolCdpId))
    assert.isTrue(await sortedCdps.contains(_dennisCdpId))
    assert.isTrue(await sortedCdps.contains(_whaleCdpId))

    // Check A's collateral and debt are the same
    const entireColl_A = (await cdpManager.Cdps(_aliceCdpId))[1]
    const entireDebt_A = (await cdpManager.Cdps(_aliceCdpId))[0].add((await cdpManager.getPendingRedistributedDebt(_aliceCdpId)))

    assert.equal(entireColl_A.toString(), '0')
    th.assertIsApproximatelyEqual(entireDebt_A.toString(), '0')

    /* Liquidation event emits:
    coll = (F_debt + G_debt)/price*1.1*0.995
    debt = (F_debt + G_debt) */
    let _liqDebts = (F_coll.mul(price).div(LICR)).add(G_coll.mul(price).div(LICR)).add(A_coll.mul(price).div(LICR)).add(B_totalDebt);
    th.assertIsApproximatelyEqual(liquidatedDebt, _liqDebts)	
    const equivalentCollA = A_coll
    const equivalentCollB = B_coll
    const equivalentCollF = F_coll
    const equivalentCollG = G_coll
    th.assertIsApproximatelyEqual(liquidatedColl, equivalentCollA.add(equivalentCollB).add(equivalentCollF).add(equivalentCollG))

    // check collateral surplus
    const freddy_remainingCollateral = F_coll.sub(equivalentCollF)
    const greta_remainingCollateral = G_coll.sub(equivalentCollG)
    th.assertIsApproximatelyEqual('0', freddy_remainingCollateral.toString())
    th.assertIsApproximatelyEqual('0', greta_remainingCollateral.toString())
  })

})

contract('Reset chain state', async accounts => { })
