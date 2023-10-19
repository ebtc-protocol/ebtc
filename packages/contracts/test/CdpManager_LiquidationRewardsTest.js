const deploymentHelper = require("../utils/deploymentHelpers.js")
const testHelpers = require("../utils/testHelpers.js")

const th = testHelpers.TestHelper
const dec = th.dec
const toBN = th.toBN
const getDifference = th.getDifference
const mv = testHelpers.MoneyValues

const CdpManagerTester = artifacts.require("CdpManagerTester")
const EBTCToken = artifacts.require("EBTCToken")

const GAS_PRICE = 10000000000 //10 GWEI

const hre = require("hardhat");

contract('CdpManager - Redistribution reward calculations', async accounts => {

  const [
    owner,
    alice, bob, carol, dennis, erin, freddy, greta, harry, ida,
    A, B, C, D, E,
    whale, defaulter_1, defaulter_2, defaulter_3, defaulter_4] = accounts;

    const [bountyAddress, lpRewardsAddress, multisig] = accounts.slice(accounts.length - 3, accounts.length)
    const beadp = "0x00000000219ab540356cBB839Cbe05303d7705Fa";//beacon deposit
    let beadpSigner;

  let priceFeed
  let ebtcToken
  let sortedCdps
  let cdpManager
  let nameRegistry
  let activePool
  let defaultPool
  let functionCaller
  let borrowerOperations

  let contracts
  let _signer 

  const getOpenCdpEBTCAmount = async (totalDebt) => th.getOpenCdpEBTCAmount(contracts, totalDebt)
  const getNetBorrowingAmount = async (debtWithFee) => th.getNetBorrowingAmount(contracts, debtWithFee)
  const openCdp = async (params) => th.openCdp(contracts, params)

  before(async () => {	 
    await hre.network.provider.request({method: "hardhat_impersonateAccount", params: [beadp]}); 
    beadpSigner = await ethers.provider.getSigner(beadp);	
  })

  beforeEach(async () => {
    contracts = await deploymentHelper.deployTesterContractsHardhat()
    let LQTYContracts = {}
    LQTYContracts.feeRecipient = contracts.feeRecipient;

    priceFeed = contracts.priceFeedTestnet
    ebtcToken = contracts.ebtcToken
    sortedCdps = contracts.sortedCdps
    cdpManager = contracts.cdpManager
    nameRegistry = contracts.nameRegistry
    activePool = contracts.activePool
    defaultPool = contracts.defaultPool
    functionCaller = contracts.functionCaller
    borrowerOperations = contracts.borrowerOperations
    debtToken = ebtcToken;
    LICR = await cdpManager.LICR()

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
    await _signer.sendTransaction({ to: erin, value: ethers.utils.parseEther("1000")});

    let _signerBal = toBN((await web3.eth.getBalance(_signer._address)).toString());
    let _bigDeal = toBN(dec(2000000, 18));
    if (_signerBal.gt(_bigDeal) && _signer._address != beadp){
        await _signer.sendTransaction({ to: beadp, value: ethers.utils.parseEther("200000")});
    }
  })

  it("redistribution: A, B Open. B Liquidated. C, D Open. D Liquidated. Distributes correct rewards", async () => {
    // A, B open cdp
    const { collateral: A_coll } = await openCdp({ ICR: toBN(dec(400, 16)), extraParams: { from: alice } })
    const { collateral: B_coll } = await openCdp({ ICR: toBN(dec(210, 16)), extraParams: { from: bob } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);

    // Price drops
    await priceFeed.setPrice(dec(3714, 13))

    // Confirm not in Recovery Mode
    assert.isFalse(await th.checkRecoveryMode(contracts))

    // L1: B liquidated
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from: alice});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from: bob});
    const txB = await cdpManager.liquidate(_bobCdpId, {from: owner})
    assert.isTrue(txB.receipt.status)
    assert.isFalse(await sortedCdps.contains(_bobCdpId))

    // Price bounces back
    await priceFeed.setPrice(dec(7428, 13))

    // C, D open cdps
    const { collateral: C_coll } = await openCdp({ ICR: toBN(dec(400, 16)), extraParams: { from: carol } })
    const { collateral: D_coll } = await openCdp({ ICR: toBN(dec(210, 16)), extraParams: { from: dennis } })
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);

    // Price drops to 100 $/E
    await priceFeed.setPrice(dec(3714, 13))

    // Confirm not in Recovery Mode
    assert.isFalse(await th.checkRecoveryMode(contracts))

    // L2: D Liquidated
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from: dennis});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from: carol});
    const txD = await cdpManager.liquidate(_dennisCdpId, {from: owner})
    assert.isTrue(txB.receipt.status)
    assert.isFalse(await sortedCdps.contains(_dennisCdpId))

    // Get entire coll of A and C
    const alice_Coll = ((await cdpManager.Cdps(_aliceCdpId))[1]).toString()
    const carol_Coll = ((await cdpManager.Cdps(_carolCdpId))[1]).toString()

    /* Expected collateral:
    A: Alice receives 0.995 ETH from L1, and ~3/5*0.995 ETH from L2.
    expect aliceColl = 2 + 0.995 + 2.995/4.995 * 0.995 = 3.5916 ETH

    C: Carol receives ~2/5 ETH from L2
    expect carolColl = 2 + 2/4.995 * 0.995 = 2.398 ETH

    Total coll = 4 + 2 * 0.995 ETH
    */
    const A_collAfterL1 = A_coll.add(th.applyLiquidationFee(toBN('0')))
    assert.isAtMost(th.getDifference(alice_Coll, A_collAfterL1.add(A_collAfterL1.mul(th.applyLiquidationFee(toBN('0'))).div(A_collAfterL1.add(C_coll)))), 1000)
    assert.isAtMost(th.getDifference(carol_Coll, C_coll.add(C_coll.mul(th.applyLiquidationFee(toBN('0'))).div(A_collAfterL1.add(C_coll)))), 1000)


    const entireSystemColl = (await activePool.getSystemCollShares()).toString()
    assert.equal(entireSystemColl, A_coll.add(C_coll).add(th.applyLiquidationFee(toBN('0').add(toBN('0')))))

    // check EBTC gas compensation
//    assert.equal((await ebtcToken.balanceOf(owner)).toString(), dec(2, 16))
  })

  it("redistribution: A, B, C Open. C Liquidated. D, E, F Open. F Liquidated. Distributes correct rewards", async () => {
    // A, B C open cdps
    const { collateral: A_coll } = await openCdp({ ICR: toBN(dec(400, 16)), extraParams: { from: alice } })
    const { collateral: B_coll } = await openCdp({ ICR: toBN(dec(400, 16)), extraParams: { from: bob } })
    const { collateral: C_coll } = await openCdp({ ICR: toBN(dec(210, 16)), extraParams: { from: carol } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    // Price drops
    await priceFeed.setPrice(dec(3714, 13))

    // Confirm not in Recovery Mode
    assert.isFalse(await th.checkRecoveryMode(contracts))

    // L1: C liquidated
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from: carol});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from: alice});
    const txC = await cdpManager.liquidate(_carolCdpId, {from: owner})
    assert.isTrue(txC.receipt.status)
    assert.isFalse(await sortedCdps.contains(_carolCdpId))

    // Price bounces back
    await priceFeed.setPrice(dec(7428, 13))

    // D, E, F open cdps
    const { collateral: D_coll } = await openCdp({ ICR: toBN(dec(400, 16)), extraParams: { from: dennis } })
    const { collateral: E_coll } = await openCdp({ ICR: toBN(dec(400, 16)), extraParams: { from: erin } })
    const { collateral: F_coll } = await openCdp({ ICR: toBN(dec(210, 16)), extraParams: { from: freddy } })
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);
    let _erinCdpId = await sortedCdps.cdpOfOwnerByIndex(erin, 0);
    let _freddyCdpId = await sortedCdps.cdpOfOwnerByIndex(freddy, 0);

    // Price drops
    await priceFeed.setPrice(dec(3714, 13))

    // Confirm not in Recovery Mode
    assert.isFalse(await th.checkRecoveryMode(contracts))

    // L2: F Liquidated
    await debtToken.transfer(owner, (await debtToken.balanceOf(freddy)), {from: freddy});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(erin)), {from: erin});
    const txF = await cdpManager.liquidate(_freddyCdpId, {from: owner})
    assert.isTrue(txF.receipt.status)
    assert.isFalse(await sortedCdps.contains(_freddyCdpId))

    // Get entire coll of A, B, D and E
    const alice_Coll = ((await cdpManager.Cdps(_aliceCdpId))[1]).toString()
    const bob_Coll = ((await cdpManager.Cdps(_bobCdpId))[1]).toString()
    const dennis_Coll = ((await cdpManager.Cdps(_dennisCdpId))[1]).toString()
    const erin_Coll = ((await cdpManager.Cdps(_erinCdpId))[1]).toString()

    /* Expected collateral:
    A and B receives 1/2 ETH * 0.995 from L1.
    total Coll: 3

    A, B, receive (2.4975)/8.995 * 0.995 ETH from L2.
    
    D, E receive 2/8.995 * 0.995 ETH from L2.

    expect A, B coll  = 2 +  0.4975 + 0.2763  =  ETH
    expect D, E coll  = 2 + 0.2212  =  ETH

    Total coll = 8 (non-liquidated) + 2 * 0.995 (liquidated and redistributed)
    */
    const A_collAfterL1 = A_coll.add(A_coll.mul(th.applyLiquidationFee(toBN('0'))).div(A_coll.add(B_coll)))
    const B_collAfterL1 = B_coll.add(B_coll.mul(th.applyLiquidationFee(toBN('0'))).div(A_coll.add(B_coll)))
    const totalBeforeL2 = A_collAfterL1.add(B_collAfterL1).add(D_coll).add(E_coll)
    const expected_A = A_collAfterL1.add(A_collAfterL1.mul(th.applyLiquidationFee(toBN('0'))).div(totalBeforeL2))
    const expected_B = B_collAfterL1.add(B_collAfterL1.mul(th.applyLiquidationFee(toBN('0'))).div(totalBeforeL2))
    const expected_D = D_coll.add(D_coll.mul(th.applyLiquidationFee(toBN('0'))).div(totalBeforeL2))
    const expected_E = E_coll.add(E_coll.mul(th.applyLiquidationFee(toBN('0'))).div(totalBeforeL2))
    assert.isAtMost(th.getDifference(alice_Coll, expected_A), 1000)
    assert.isAtMost(th.getDifference(bob_Coll, expected_B), 1000)
    assert.isAtMost(th.getDifference(dennis_Coll, expected_D), 1000)
    assert.isAtMost(th.getDifference(erin_Coll, expected_E), 1000)

    const entireSystemColl = (await activePool.getSystemCollShares()).toString()
    assert.equal(entireSystemColl, A_coll.add(B_coll).add(D_coll).add(E_coll).add(th.applyLiquidationFee(toBN('0').add(toBN('0')))))

    // check EBTC gas compensation
//    assert.equal((await ebtcToken.balanceOf(owner)).toString(), dec(2, 16))
  })
  ////

  it("redistribution: Sequence of alternate opening/liquidation: final surviving cdp has ETH from all previously liquidated cdps", async () => {
    // A, B  open cdps
    const { collateral: A_coll } = await openCdp({ ICR: toBN(dec(400, 16)), extraParams: { from: alice } })
    const { collateral: B_coll } = await openCdp({ ICR: toBN(dec(400, 16)), extraParams: { from: bob } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);

    // Price drops
    await priceFeed.setPrice(dec(100, 13))

    // L1: A liquidated
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from: bob});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from: alice});
    const txA = await cdpManager.liquidate(_aliceCdpId, {from: owner})
    assert.isTrue(txA.receipt.status)
    assert.isFalse(await sortedCdps.contains(_aliceCdpId))

    // Price bounces back
    await priceFeed.setPrice(dec(7428, 13))
    // C, opens cdp
    const { collateral: C_coll } = await openCdp({ ICR: toBN(dec(210, 16)), extraParams: { from: carol } })
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    // Price drops
    await priceFeed.setPrice(dec(100, 13))

    // L2: B Liquidated
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from: carol});	
    const txB = await cdpManager.liquidate(_bobCdpId, {from: owner})
    assert.isTrue(txB.receipt.status)
    assert.isFalse(await sortedCdps.contains(_bobCdpId))

    // Price bounces back
    await priceFeed.setPrice(dec(7428, 13))
    // D opens cdp
    const { collateral: D_coll } = await openCdp({ ICR: toBN(dec(210, 16)), extraParams: { from: dennis } })
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);

    // Price drops to 100 $/E
    await priceFeed.setPrice(dec(100, 13))

    // L3: C Liquidated
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from: dennis});	
    const txC = await cdpManager.liquidate(_carolCdpId, {from: owner})
    assert.isTrue(txC.receipt.status)
    assert.isFalse(await sortedCdps.contains(_carolCdpId))

    // Price bounces back to 200 $/E
    await priceFeed.setPrice(dec(7428, 13))
    // E opens cdp
    const { collateral: E_coll } = await openCdp({ ICR: toBN(dec(210, 16)), extraParams: { from: erin } })
    let _erinCdpId = await sortedCdps.cdpOfOwnerByIndex(erin, 0);

    // Price drops to 100 $/E
    await priceFeed.setPrice(dec(100, 13))

    // L4: D Liquidated
    await debtToken.transfer(owner, (await debtToken.balanceOf(erin)), {from: erin});
    const txD = await cdpManager.liquidate(_dennisCdpId, {from: owner})
    assert.isTrue(txD.receipt.status)
    assert.isFalse(await sortedCdps.contains(_dennisCdpId))

    // Price bounces back to 200 $/E
    await priceFeed.setPrice(dec(7428, 13))
    // F opens cdp
    const { collateral: F_coll } = await openCdp({ ICR: toBN(dec(210, 16)), extraParams: { from: freddy } })
    let _freddyCdpId = await sortedCdps.cdpOfOwnerByIndex(freddy, 0);

    // Price drops to 100 $/E
    await priceFeed.setPrice(dec(100, 13))

    // L5: E Liquidated
    await debtToken.transfer(owner, (await debtToken.balanceOf(freddy)), {from: freddy});
    const txE = await cdpManager.liquidate(_erinCdpId, {from: owner})
    assert.isTrue(txE.receipt.status)
    assert.isFalse(await sortedCdps.contains(_erinCdpId))

    // Get entire coll of A, B, D, E and F
    const alice_Coll = ((await cdpManager.Cdps(_aliceCdpId))[1]).toString()
    const bob_Coll = ((await cdpManager.Cdps(_bobCdpId))[1]).toString()
    const carol_Coll = ((await cdpManager.Cdps(_carolCdpId))[1]).toString()
    const dennis_Coll = ((await cdpManager.Cdps(_dennisCdpId))[1]).toString()
    const erin_Coll = ((await cdpManager.Cdps(_erinCdpId))[1]).toString()

    const freddy_rawColl = (await cdpManager.Cdps(_freddyCdpId))[1].toString()

    /* Expected collateral:
     A-E should have been liquidated
     cdp F should have acquired all ETH in the system: 1 ETH initial coll, and 0.995^5+0.995^4+0.995^3+0.995^2+0.995 from rewards = 5.925 ETH
    */
    assert.isAtMost(th.getDifference(alice_Coll, '0'), 1000)
    assert.isAtMost(th.getDifference(bob_Coll, '0'), 1000)
    assert.isAtMost(th.getDifference(carol_Coll, '0'), 1000)
    assert.isAtMost(th.getDifference(dennis_Coll, '0'), 1000)
    assert.isAtMost(th.getDifference(erin_Coll, '0'), 1000)

    assert.isAtMost(th.getDifference(freddy_rawColl, F_coll), 1000)

    const entireSystemColl = (await activePool.getSystemCollShares()).toString()
    assert.isAtMost(th.getDifference(entireSystemColl, F_coll), 1000)

    // check EBTC gas compensation
//    assert.equal((await ebtcToken.balanceOf(owner)).toString(), dec(5, 16))
  })

  // ---Cdp adds collateral --- 

  // Test based on scenario in: https://docs.google.com/spreadsheets/d/1F5p3nZy749K5jwO-bwJeTsRoY7ewMfWIQ3QHtokxqzo/edit?usp=sharing
  it("redistribution: A,B,C,D,E open. Liq(A). B adds coll. Liq(C). B and D have correct coll and debt", async () => {
    // A, B, C, D, E open cdps
    await _signer.sendTransaction({ to: A, value: ethers.utils.parseEther("270000")});
    await _signer.sendTransaction({ to: B, value: ethers.utils.parseEther("270000")});
    await _signer.sendTransaction({ to: C, value: ethers.utils.parseEther("270000")});
    await _signer.sendTransaction({ to: D, value: ethers.utils.parseEther("20000")});
    await _signer.sendTransaction({ to: E, value: ethers.utils.parseEther("270000")});
    const { collateral: A_coll } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(10000, 18), extraParams: { from: A } })
    const { collateral: B_coll } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(10000, 18), extraParams: { from: B } })
    const { collateral: C_coll } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(10000, 18), extraParams: { from: C } })
    const { collateral: D_coll } = await openCdp({ ICR: toBN(dec(20000, 16)), extraEBTCAmount: dec(10, 18), extraParams: { from: D } })
    const { collateral: E_coll } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(10000, 18), extraParams: { from: E } })
    let _aCdpId = await sortedCdps.cdpOfOwnerByIndex(A, 0);
    let _bCdpId = await sortedCdps.cdpOfOwnerByIndex(B, 0);
    let _cCdpId = await sortedCdps.cdpOfOwnerByIndex(C, 0);
    let _dCdpId = await sortedCdps.cdpOfOwnerByIndex(D, 0);
    let _eCdpId = await sortedCdps.cdpOfOwnerByIndex(E, 0);

    // Price drops to 100 $/E
    await priceFeed.setPrice(dec(3714, 13))

    // Liquidate A
    // console.log(`ICR A: ${await cdpManager.getCachedICR(A, price)}`)
    await debtToken.transfer(owner, (await debtToken.balanceOf(B)), {from: B});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(A)), {from: A});
    const txA = await cdpManager.liquidate(_aCdpId, {from: owner})
    assert.isTrue(txA.receipt.status)
    assert.isFalse(await sortedCdps.contains(_aCdpId))

    // Check entireColl for each cdp:
    const B_entireColl_1 = (await th.getEntireCollAndDebt(contracts, _bCdpId)).entireColl
    const C_entireColl_1 = (await th.getEntireCollAndDebt(contracts, _cCdpId)).entireColl
    const D_entireColl_1 = (await th.getEntireCollAndDebt(contracts, _dCdpId)).entireColl
    const E_entireColl_1 = (await th.getEntireCollAndDebt(contracts, _eCdpId)).entireColl

    const totalCollAfterL1 = B_coll.add(C_coll).add(D_coll).add(E_coll)
    const B_collAfterL1 = B_coll.add(th.applyLiquidationFee(toBN('0')).mul(B_coll).div(totalCollAfterL1))
    const C_collAfterL1 = C_coll.add(th.applyLiquidationFee(toBN('0')).mul(C_coll).div(totalCollAfterL1))
    const D_collAfterL1 = D_coll.add(th.applyLiquidationFee(toBN('0')).mul(D_coll).div(totalCollAfterL1))
    const E_collAfterL1 = E_coll.add(th.applyLiquidationFee(toBN('0')).mul(E_coll).div(totalCollAfterL1))
    assert.isAtMost(getDifference(B_entireColl_1, B_collAfterL1), 1e8)
    assert.isAtMost(getDifference(C_entireColl_1, C_collAfterL1), 1e8)
    assert.isAtMost(getDifference(D_entireColl_1, D_collAfterL1), 1e8)
    assert.isAtMost(getDifference(E_entireColl_1, E_collAfterL1), 1e8)

    // Bob adds 1 ETH to his cdp
    const addedColl1 = toBN(dec(110, 'ether'))
    await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: B});
    await contracts.collateral.deposit({from: B, value: addedColl1});
    await borrowerOperations.addColl(_bCdpId, _bCdpId, _bCdpId, addedColl1, { from: B, value: 0 })

    // Liquidate C
    await debtToken.transfer(owner, (await debtToken.balanceOf(C)), {from: C});
    const txC = await cdpManager.liquidate(_cCdpId, {from: owner})
    assert.isTrue(txC.receipt.status)
    assert.isFalse(await sortedCdps.contains(_cCdpId))

    const D_entireColl_2 = (await th.getEntireCollAndDebt(contracts, _dCdpId)).entireColl
    const E_entireColl_2 = (await th.getEntireCollAndDebt(contracts, _eCdpId)).entireColl

    const totalCollAfterL2 = B_collAfterL1.add(addedColl1).add(D_collAfterL1).add(E_collAfterL1)
    const B_collAfterL2 = B_collAfterL1.add(addedColl1).add(th.applyLiquidationFee(toBN('0')).mul(B_collAfterL1.add(addedColl1)).div(totalCollAfterL2))
    const D_collAfterL2 = D_collAfterL1.add(th.applyLiquidationFee(toBN('0')).mul(D_collAfterL1).div(totalCollAfterL2))
    const E_collAfterL2 = E_collAfterL1.add(th.applyLiquidationFee(toBN('0')).mul(E_collAfterL1).div(totalCollAfterL2))
    // console.log(`D_entireColl_2: ${D_entireColl_2}`)
    // console.log(`E_entireColl_2: ${E_entireColl_2}`)
    //assert.isAtMost(getDifference(B_entireColl_2, B_collAfterL2), 1e8)
    assert.isAtMost(getDifference(D_entireColl_2, D_collAfterL2), 1e8)
    assert.isAtMost(getDifference(E_entireColl_2, E_collAfterL2), 1e8)

    // Bob adds 1 ETH to his cdp
    const addedColl2 = toBN(dec(1, 'ether'))
    await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: B});
    await contracts.collateral.deposit({from: B, value: addedColl2});
    await borrowerOperations.addColl(_bCdpId, _bCdpId, _bCdpId, addedColl2, { from: B, value: 0 })

    // Liquidate E
    await debtToken.transfer(owner, (await debtToken.balanceOf(E)), {from: E});	
    const txE = await cdpManager.liquidate(_eCdpId, {from: owner})
    assert.isTrue(txE.receipt.status)
    assert.isFalse(await sortedCdps.contains(_eCdpId))

    const totalCollAfterL3 = B_collAfterL2.add(addedColl2).add(D_collAfterL2)
    const B_collAfterL3 = B_collAfterL2.add(addedColl2).add(th.applyLiquidationFee(toBN('0')).mul(B_collAfterL2.add(addedColl2)).div(totalCollAfterL3))
    const D_collAfterL3 = D_collAfterL2.add(th.applyLiquidationFee(toBN('0')).mul(D_collAfterL2).div(totalCollAfterL3))

    const B_entireColl_3 = (await th.getEntireCollAndDebt(contracts, _bCdpId)).entireColl
    const D_entireColl_3 = (await th.getEntireCollAndDebt(contracts, _dCdpId)).entireColl

    const diff_entireColl_B = getDifference(B_entireColl_3, B_collAfterL3)
    const diff_entireColl_D = getDifference(D_entireColl_3, D_collAfterL3)

    assert.isAtMost(diff_entireColl_B, 1e8)
    assert.isAtMost(diff_entireColl_D, 1e8)
  })

  // Test based on scenario in: https://docs.google.com/spreadsheets/d/1F5p3nZy749K5jwO-bwJeTsRoY7ewMfWIQ3QHtokxqzo/edit?usp=sharing
  it("redistribution: A,B,C,D open. Liq(A). B adds coll. Liq(C). B and D have correct coll and debt", async () => {
    // A, B, C, D, E open cdps
    await _signer.sendTransaction({ to: A, value: ethers.utils.parseEther("270000")});
    await _signer.sendTransaction({ to: B, value: ethers.utils.parseEther("270000")});
    await _signer.sendTransaction({ to: C, value: ethers.utils.parseEther("270000")});
    await _signer.sendTransaction({ to: D, value: ethers.utils.parseEther("30000")});
    await _signer.sendTransaction({ to: E, value: ethers.utils.parseEther("270000")});
    const { collateral: A_coll } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(10000, 18), extraParams: { from: A } })
    const { collateral: B_coll } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(10000, 18), extraParams: { from: B } })
    const { collateral: C_coll } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(10000, 18), extraParams: { from: C } })
    const { collateral: D_coll } = await openCdp({ ICR: toBN(dec(20000, 16)), extraEBTCAmount: dec(10, 18), extraParams: { from: D } })
    const { collateral: E_coll } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(10000, 18), extraParams: { from: E } })
    let _aCdpId = await sortedCdps.cdpOfOwnerByIndex(A, 0);
    let _bCdpId = await sortedCdps.cdpOfOwnerByIndex(B, 0);
    let _cCdpId = await sortedCdps.cdpOfOwnerByIndex(C, 0);
    let _dCdpId = await sortedCdps.cdpOfOwnerByIndex(D, 0);
    let _eCdpId = await sortedCdps.cdpOfOwnerByIndex(E, 0);

    // Price drops
    await priceFeed.setPrice(dec(3714, 13))

    // Check entireColl for each cdp:
    const A_entireColl_0 = (await th.getEntireCollAndDebt(contracts, _aCdpId)).entireColl
    const B_entireColl_0 = (await th.getEntireCollAndDebt(contracts, _bCdpId)).entireColl
    const C_entireColl_0 = (await th.getEntireCollAndDebt(contracts, _cCdpId)).entireColl
    const D_entireColl_0 = (await th.getEntireCollAndDebt(contracts, _dCdpId)).entireColl
    const E_entireColl_0 = (await th.getEntireCollAndDebt(contracts, _eCdpId)).entireColl

    // entireSystemColl, excluding A 
    const denominatorColl_1 = (await cdpManager.getSystemCollShares()).sub(A_entireColl_0)

    // Liquidate A
    // console.log(`ICR A: ${await cdpManager.getCachedICR(A, price)}`)
    await debtToken.transfer(owner, (await debtToken.balanceOf(B)), {from: B});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(A)), {from: A});
    const txA = await cdpManager.liquidate(_aCdpId, {from: owner})
    assert.isTrue(txA.receipt.status)
    assert.isFalse(await sortedCdps.contains(_aCdpId))

    // // Bob adds 1 ETH to his cdp
    await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: B});
    await contracts.collateral.deposit({from: B, value: dec(110, 'ether')});
    await borrowerOperations.addColl(_bCdpId, _bCdpId, _bCdpId, dec(110, 'ether'), { from: B, value: 0 })

    // Check entireColl for each cdp
    const B_entireColl_1 = (await th.getEntireCollAndDebt(contracts, _bCdpId)).entireColl
    const C_entireColl_1 = (await th.getEntireCollAndDebt(contracts, _cCdpId)).entireColl
    const D_entireColl_1 = (await th.getEntireCollAndDebt(contracts, _dCdpId)).entireColl
    const E_entireColl_1 = (await th.getEntireCollAndDebt(contracts, _eCdpId)).entireColl

    // entireSystemColl, excluding C
    const denominatorColl_2 = (await cdpManager.getSystemCollShares()).sub(C_entireColl_1)

    // Liquidate C
    await debtToken.transfer(owner, (await debtToken.balanceOf(C)), {from: C});	
    const txC = await cdpManager.liquidate(_cCdpId, {from: owner})
    assert.isTrue(txC.receipt.status)
    assert.isFalse(await sortedCdps.contains(_cCdpId))

    // // Bob adds 1 ETH to his cdp
    await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: B});
    await contracts.collateral.deposit({from: B, value: dec(1, 'ether')});
    await borrowerOperations.addColl(_bCdpId, _bCdpId, _bCdpId, dec(1, 'ether'), { from: B, value: 0 })

    // Check entireColl for each cdp
    const B_entireColl_2 = (await th.getEntireCollAndDebt(contracts, _bCdpId)).entireColl
    const D_entireColl_2 = (await th.getEntireCollAndDebt(contracts, _dCdpId)).entireColl
    const E_entireColl_2 = (await th.getEntireCollAndDebt(contracts, _eCdpId)).entireColl

    // entireSystemColl, excluding E
    const denominatorColl_3 = (await cdpManager.getSystemCollShares()).sub(E_entireColl_2)

    // Liquidate E
    await debtToken.transfer(owner, (await debtToken.balanceOf(E)), {from: E});	
    const txE = await cdpManager.liquidate(_eCdpId, {from: owner})
    assert.isTrue(txE.receipt.status)
    assert.isFalse(await sortedCdps.contains(_eCdpId))
  })

  it("redistribution: A,B,C Open. Liq(C). B adds coll. Liq(A). B acquires all coll and debt", async () => {
    // A, B, C open cdps
    const { collateral: A_coll, totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(400, 16)), extraParams: { from: alice } })
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(110, 18), extraParams: { from: bob } })
    const { collateral: C_coll, totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(110, 18), extraParams: { from: carol } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    // Price drops to 100 $/E
    let _newPrice = dec(3714, 13)
    await priceFeed.setPrice(_newPrice)

    // Liquidate Carol
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from: carol});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from: bob});
    const txC = await cdpManager.liquidate(_carolCdpId, {from: owner})
    assert.isTrue(txC.receipt.status)
    assert.isFalse(await sortedCdps.contains(_carolCdpId))
	
    let _totalStakesAfterCarolLiq = await cdpManager.totalStakes();
    let _carolDebtRedistributed = C_totalDebt.sub(C_coll.mul(toBN(_newPrice)).div(LICR));

    // Price bounces back to 200 $/E
    await priceFeed.setPrice(dec(7428, 13))

    // Alice withdraws EBTC
    await borrowerOperations.withdrawDebt(_aliceCdpId, await getNetBorrowingAmount(A_totalDebt), _aliceCdpId, _aliceCdpId, { from: alice })

    // Price drops to 100 $/E
    await priceFeed.setPrice(_newPrice)
    let _aliceTotalDebt = (await cdpManager.getSyncedDebtAndCollShares(_aliceCdpId))[0];

    // Liquidate Alice	
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from: alice});
    const txA = await cdpManager.liquidate(_aliceCdpId, {from: owner})
    assert.isTrue(txA.receipt.status)
    assert.isFalse(await sortedCdps.contains(_aliceCdpId))
	
    let _totalStakesAfterAliceLiq = await cdpManager.totalStakes();
    let _aliceDebtRedistributed = _aliceTotalDebt.sub(A_coll.mul(toBN(_newPrice)).div(LICR));
	
    let _carolDebtRedistributedToBob = _carolDebtRedistributed.mul((await cdpManager.getCdpStake(_bobCdpId))).div(_totalStakesAfterCarolLiq);
    let _aliceDebtRedistributedToBob = _aliceDebtRedistributed.mul((await cdpManager.getCdpStake(_bobCdpId))).div(_totalStakesAfterAliceLiq);

    // Expect Bob now holds all Ether and EBTCDebt in the system: 2 + 0.4975+0.4975*0.995+0.995 Ether and 110*3 EBTC (10 each for gas compensation)
    const bob_Coll = ((await cdpManager.Cdps(_bobCdpId))[1]).toString()
    
    let _pendingDebtRewards = await cdpManager.getPendingRedistributedDebt(_bobCdpId);
    const bob_EBTCDebt = ((await cdpManager.Cdps(_bobCdpId))[0]
      .add(_pendingDebtRewards))
      .toString()

    const expected_B_coll = B_coll
          .add(toBN('0'))
          .add(th.applyLiquidationFee(toBN('0')))
          .add(th.applyLiquidationFee(toBN('0')).mul(B_coll).div(A_coll.add(B_coll)))
          .add(th.applyLiquidationFee(th.applyLiquidationFee(toBN('0')).mul(A_coll).div(A_coll.add(B_coll))))
    assert.isAtMost(th.getDifference(bob_Coll, expected_B_coll), 1000)
    assert.isAtMost(th.getDifference(bob_EBTCDebt, _carolDebtRedistributedToBob.add(B_totalDebt).add(_aliceDebtRedistributedToBob)), 3000)
  })

  it("redistribution: A,B,C Open. Liq(C). B tops up coll. D Opens. Liq(D). Distributes correct rewards.", async () => {
    // A, B, C open cdps
    const { collateral: A_coll, totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(400, 16)), extraParams: { from: alice } })
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(110, 18), extraParams: { from: bob } })
    const { collateral: C_coll, totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(110, 18), extraParams: { from: carol } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    // Price drops to 100 $/E
    let _newPrice = dec(3714, 13)
    await priceFeed.setPrice(_newPrice)

    // Liquidate Carol
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from: carol});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from: bob});
    const txC = await cdpManager.liquidate(_carolCdpId, {from: owner})
    assert.isTrue(txC.receipt.status)
    assert.isFalse(await sortedCdps.contains(_carolCdpId))
	
    let _totalStakesAfterCarolLiq = await cdpManager.totalStakes();
    let _carolDebtRedistributed = C_totalDebt.sub(C_coll.mul(toBN(_newPrice)).div(LICR));

    // Price bounces back to 200 $/E
    await priceFeed.setPrice(dec(7428, 13))

    // D opens cdp
    const { collateral: D_coll, totalDebt: D_totalDebt } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(110, 18), extraParams: { from: dennis } })
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);

    // Price drops to 100 $/E
    await priceFeed.setPrice(_newPrice)

    // Liquidate D
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from: dennis});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from: alice});
    const txA = await cdpManager.liquidate(_dennisCdpId, {from: owner})
    assert.isTrue(txA.receipt.status)
    assert.isFalse(await sortedCdps.contains(_dennisCdpId))
	
    let _totalStakesAfterDennisLiq = await cdpManager.totalStakes();
    let _dennisDebtRedistributed = D_totalDebt.sub(D_coll.mul(toBN(_newPrice)).div(LICR));
	
    let _carolDebtRedistributedToAlice = _carolDebtRedistributed.mul((await cdpManager.getCdpStake(_aliceCdpId))).div(_totalStakesAfterCarolLiq);
    let _carolDebtRedistributedToBob = _carolDebtRedistributed.mul((await cdpManager.getCdpStake(_bobCdpId))).div(_totalStakesAfterCarolLiq);
    let _dennisDebtRedistributedToAlice = _dennisDebtRedistributed.mul((await cdpManager.getCdpStake(_aliceCdpId))).div(_totalStakesAfterDennisLiq);
    let _dennisDebtRedistributedToBob = _dennisDebtRedistributed.mul((await cdpManager.getCdpStake(_bobCdpId))).div(_totalStakesAfterDennisLiq);

    /* Bob rewards:
     L1: 1/2*0.995 ETH, 55 EBTC
     L2: (2.4975/3.995)*0.995 = 0.622 ETH , 110*(2.4975/3.995)= 68.77 EBTCDebt

    coll: 3.1195 ETH
    debt: 233.77 EBTCDebt

     Alice rewards:
    L1 1/2*0.995 ETH, 55 EBTC
    L2 (1.4975/3.995)*0.995 = 0.3730 ETH, 110*(1.4975/3.995) = 41.23 EBTCDebt

    coll: 1.8705 ETH
    debt: 146.23 EBTCDebt

    totalColl: 4.99 ETH
    totalDebt 380 EBTC (includes 50 each for gas compensation)
    */
    const bob_Coll = ((await cdpManager.Cdps(_bobCdpId))[1]).toString()

    let _bobPendingDebtRewards = await cdpManager.getPendingRedistributedDebt(_bobCdpId);
    const bob_EBTCDebt = ((await cdpManager.Cdps(_bobCdpId))[0]
      .add(_bobPendingDebtRewards))
      .toString()

    const alice_Coll = ((await cdpManager.Cdps(_aliceCdpId))[1]).toString()

    let _alicePendingDebtRewards = await cdpManager.getPendingRedistributedDebt(_aliceCdpId);
    const alice_EBTCDebt = ((await cdpManager.Cdps(_aliceCdpId))[0]
      .add(_alicePendingDebtRewards))
      .toString()

    const totalCollAfterL1 = A_coll.add(B_coll).add(toBN('0')).add(th.applyLiquidationFee(toBN('0')))
    const B_collAfterL1 = B_coll.add(B_coll.mul(th.applyLiquidationFee(toBN('0'))).div(A_coll.add(B_coll))).add(toBN('0'))
    const expected_B_coll = B_collAfterL1.add(B_collAfterL1.mul(th.applyLiquidationFee(toBN('0'))).div(totalCollAfterL1))
    const expected_B_debt = B_totalDebt
          .add(_carolDebtRedistributedToBob)
          .add(_dennisDebtRedistributedToBob)
    assert.isAtMost(th.getDifference(bob_Coll, expected_B_coll), 1000)
    assert.isAtMost(th.getDifference(bob_EBTCDebt, expected_B_debt), 10000)

    const A_collAfterL1 = A_coll.add(A_coll.mul(th.applyLiquidationFee(toBN('0'))).div(A_coll.add(B_coll)))
    const expected_A_coll = A_collAfterL1.add(A_collAfterL1.mul(th.applyLiquidationFee(toBN('0'))).div(totalCollAfterL1))
    const expected_A_debt = A_totalDebt
          .add(_carolDebtRedistributedToAlice)
          .add(_dennisDebtRedistributedToAlice)
    assert.isAtMost(th.getDifference(alice_Coll, expected_A_coll), 1000)
    assert.isAtMost(th.getDifference(alice_EBTCDebt, expected_A_debt), 10000)
  })

  it("redistribution: Cdp with the majority stake tops up. A,B,C, D open. Liq(D). C tops up. E Enters, Liq(E). Distributes correct rewards", async () => {
    const _998_Ether = toBN('998000000000000000000')
    // A, B, C, D open cdps
    const { collateral: A_coll } = await openCdp({ ICR: toBN(dec(400, 16)), extraParams: { from: alice } })
    const { collateral: B_coll } = await openCdp({ ICR: toBN(dec(400, 16)), extraEBTCAmount: dec(110, 18), extraParams: { from: bob } })
    const { collateral: C_coll } = await openCdp({ extraEBTCAmount: dec(11, 18), extraParams: { from: carol, value: _998_Ether } })
    const { collateral: D_coll } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(110, 18), extraParams: { from: dennis, value: dec(1000, 'ether') } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);

    // Price drops to 100 $/E
    await priceFeed.setPrice(dec(3714, 13))

    // Liquidate Dennis
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from: dennis});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from: bob});
    const txD = await cdpManager.liquidate(_dennisCdpId, {from: owner})
    assert.isTrue(txD.receipt.status)
    assert.isFalse(await sortedCdps.contains(_dennisCdpId))

    // Price bounces back to 200 $/E
    await priceFeed.setPrice(dec(7428, 13))

    //Expect 1000 + 1000*0.995 ETH in system now
    const entireSystemColl_1 = (await activePool.getSystemCollShares()).toString()
    assert.equal(entireSystemColl_1, A_coll.add(B_coll).add(C_coll).add(th.applyLiquidationFee(toBN('0'))))

    const totalColl = A_coll.add(B_coll).add(C_coll)

    //Carol adds 1 ETH to her cdp, brings it to 1992.01 total coll
    const C_addedColl = toBN(dec(1, 'ether'))
    await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: carol});
    await contracts.collateral.deposit({from: carol, value: dec(1, 'ether')});
    await borrowerOperations.addColl(_carolCdpId, _carolCdpId, _carolCdpId, dec(1, 'ether'), { from: carol, value: 0 })

    //Expect 1996 ETH in system now
    const entireSystemColl_2 = (await activePool.getSystemCollShares())
    th.assertIsApproximatelyEqual(entireSystemColl_2, totalColl.add(th.applyLiquidationFee(toBN('0'))).add(C_addedColl))

    // E opens with another 1996 ETH
    const { collateral: E_coll } = await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: erin, value: entireSystemColl_2 } })
    let _erinCdpId = await sortedCdps.cdpOfOwnerByIndex(erin, 0);

    // Price drops to 100 $/E
    await priceFeed.setPrice(dec(3714, 13))

    // Liquidate Erin
    await debtToken.transfer(owner, (await debtToken.balanceOf(erin)), {from: erin});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from: alice});
    const txE = await cdpManager.liquidate(_erinCdpId, {from: owner})
    assert.isTrue(txE.receipt.status)
    assert.isFalse(await sortedCdps.contains(_erinCdpId))

    /* Expected ETH rewards: 
     Carol = 1992.01/1996 * 1996*0.995 = 1982.05 ETH
     Alice = 1.995/1996 * 1996*0.995 = 1.985025 ETH
     Bob = 1.995/1996 * 1996*0.995 = 1.985025 ETH

    therefore, expected total collateral:

    Carol = 1991.01 + 1991.01 = 3974.06
    Alice = 1.995 + 1.985025 = 3.980025 ETH
    Bob = 1.995 + 1.985025 = 3.980025 ETH

    total = 3982.02 ETH
    */

    const alice_Coll = ((await cdpManager.Cdps(_aliceCdpId))[1]).toString()

    const bob_Coll = ((await cdpManager.Cdps(_bobCdpId))[1]).toString()

    const carol_Coll = ((await cdpManager.Cdps(_carolCdpId))[1]).toString()

    const totalCollAfterL1 = A_coll.add(B_coll).add(C_coll).add(th.applyLiquidationFee(toBN('0'))).add(C_addedColl)
    const A_collAfterL1 = A_coll.add(A_coll.mul(th.applyLiquidationFee(toBN('0'))).div(A_coll.add(B_coll).add(C_coll)))
    const expected_A_coll = A_collAfterL1.add(A_collAfterL1.mul(th.applyLiquidationFee(toBN('0'))).div(totalCollAfterL1))
    const B_collAfterL1 = B_coll.add(B_coll.mul(th.applyLiquidationFee(toBN('0'))).div(A_coll.add(B_coll).add(C_coll)))
    const expected_B_coll = B_collAfterL1.add(B_collAfterL1.mul(th.applyLiquidationFee(toBN('0'))).div(totalCollAfterL1))
    const C_collAfterL1 = C_coll.add(C_coll.mul(th.applyLiquidationFee(toBN('0'))).div(A_coll.add(B_coll).add(C_coll))).add(C_addedColl)
    const expected_C_coll = C_collAfterL1.add(C_collAfterL1.mul(th.applyLiquidationFee(toBN('0'))).div(totalCollAfterL1))

    assert.isAtMost(th.getDifference(alice_Coll, expected_A_coll), 1000)
    assert.isAtMost(th.getDifference(bob_Coll, expected_B_coll), 1000)
    assert.isAtMost(th.getDifference(carol_Coll, expected_C_coll), 1000)

    //Expect 3982.02 ETH in system now
    const entireSystemColl_3 = (await activePool.getSystemCollShares()).toString()
    th.assertIsApproximatelyEqual(entireSystemColl_3, totalCollAfterL1.add(th.applyLiquidationFee(toBN('0'))))

    // check EBTC gas compensation
//    th.assertIsApproximatelyEqual((await ebtcToken.balanceOf(owner)).toString(), dec(2, 16))
  })

  it("redistribution: Cdp with the majority stake tops up. A,B,C, D open. Liq(D). A, B, C top up. E Enters, Liq(E). Distributes correct rewards", async () => {
    const _998_Ether = toBN('998000000000000000000')
    // A, B, C open cdps
    const { collateral: A_coll } = await openCdp({ ICR: toBN(dec(400, 16)), extraParams: { from: alice } })
    const { collateral: B_coll } = await openCdp({ ICR: toBN(dec(400, 16)), extraEBTCAmount: dec(110, 18), extraParams: { from: bob } })
    const { collateral: C_coll } = await openCdp({ extraEBTCAmount: dec(11, 18), extraParams: { from: carol, value: _998_Ether } })
    const { collateral: D_coll } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(110, 18), extraParams: { from: dennis, value: dec(1000, 'ether') } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);

    // Price drops to 100 $/E
    await priceFeed.setPrice(dec(3714, 13))

    // Liquidate Dennis
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from: dennis});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from: bob});
    const txD = await cdpManager.liquidate(_dennisCdpId, {from: owner})
    assert.isTrue(txD.receipt.status)
    assert.isFalse(await sortedCdps.contains(_dennisCdpId))

    // Price bounces back to 200 $/E
    await priceFeed.setPrice(dec(7428, 13))

    //Expect 1995 ETH in system now
    const entireSystemColl_1 = (await activePool.getSystemCollShares()).toString()
    assert.equal(entireSystemColl_1, A_coll.add(B_coll).add(C_coll).add(th.applyLiquidationFee(toBN('0'))))

    const totalColl = A_coll.add(B_coll).add(C_coll)

    /* Alice, Bob, Carol each adds 1 ETH to their cdps, 
    bringing them to 2.995, 2.995, 1992.01 total coll each. */

    const addedColl = toBN(dec(1, 'ether'))
    await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: alice});
    await contracts.collateral.deposit({from: alice, value: addedColl});
    await borrowerOperations.addColl(_aliceCdpId, _aliceCdpId, _aliceCdpId, addedColl, { from: alice, value: 0 })
    await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: bob});
    await contracts.collateral.deposit({from: bob, value: addedColl});
    await borrowerOperations.addColl(_bobCdpId, _bobCdpId, _bobCdpId, addedColl, { from: bob, value: 0 })
    await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: carol});
    await contracts.collateral.deposit({from: carol, value: addedColl});
    await borrowerOperations.addColl(_carolCdpId, _carolCdpId, _carolCdpId, addedColl, { from: carol, value: 0 })

    //Expect 1998 ETH in system now
    const entireSystemColl_2 = (await activePool.getSystemCollShares()).toString()
    th.assertIsApproximatelyEqual(entireSystemColl_2, totalColl.add(th.applyLiquidationFee(toBN('0'))).add(addedColl.mul(toBN(3))))

    // E opens with another 1998 ETH
    const { collateral: E_coll } = await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: erin, value: entireSystemColl_2 } })
    let _erinCdpId = await sortedCdps.cdpOfOwnerByIndex(erin, 0);

    // Price drops to 100 $/E
    await priceFeed.setPrice(dec(3714, 13))

    // Liquidate Erin
    await debtToken.transfer(owner, (await debtToken.balanceOf(erin)), {from: erin});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from: alice});
    const txE = await cdpManager.liquidate(_erinCdpId)
    assert.isTrue(txE.receipt.status)
    assert.isFalse(await sortedCdps.contains(_erinCdpId))

    /* Expected ETH rewards: 
     Carol = 1992.01/1998 * 1998*0.995 = 1982.04995 ETH
     Alice = 2.995/1998 * 1998*0.995 = 2.980025 ETH
     Bob = 2.995/1998 * 1998*0.995 = 2.980025 ETH

    therefore, expected total collateral:

    Carol = 1992.01 + 1982.04995 = 3974.05995
    Alice = 2.995 + 2.980025 = 5.975025 ETH
    Bob = 2.995 + 2.980025 = 5.975025 ETH

    total = 3986.01 ETH
    */

    const alice_Coll = ((await cdpManager.Cdps(_aliceCdpId))[1]).toString()

    const bob_Coll = ((await cdpManager.Cdps(_bobCdpId))[1]).toString()

    const carol_Coll = ((await cdpManager.Cdps(_carolCdpId))[1]).toString()

    const totalCollAfterL1 = A_coll.add(B_coll).add(C_coll).add(th.applyLiquidationFee(toBN('0'))).add(addedColl.mul(toBN(3)))
    const A_collAfterL1 = A_coll.add(A_coll.mul(th.applyLiquidationFee(toBN('0'))).div(A_coll.add(B_coll).add(C_coll))).add(addedColl)
    const expected_A_coll = A_collAfterL1.add(A_collAfterL1.mul(th.applyLiquidationFee(toBN('0'))).div(totalCollAfterL1))
    const B_collAfterL1 = B_coll.add(B_coll.mul(th.applyLiquidationFee(toBN('0'))).div(A_coll.add(B_coll).add(C_coll))).add(addedColl)
    const expected_B_coll = B_collAfterL1.add(B_collAfterL1.mul(th.applyLiquidationFee(toBN('0'))).div(totalCollAfterL1))
    const C_collAfterL1 = C_coll.add(C_coll.mul(th.applyLiquidationFee(toBN('0'))).div(A_coll.add(B_coll).add(C_coll))).add(addedColl)
    const expected_C_coll = C_collAfterL1.add(C_collAfterL1.mul(th.applyLiquidationFee(toBN('0'))).div(totalCollAfterL1))

    assert.isAtMost(th.getDifference(alice_Coll, expected_A_coll), 1000)
    assert.isAtMost(th.getDifference(bob_Coll, expected_B_coll), 1000)
    assert.isAtMost(th.getDifference(carol_Coll, expected_C_coll), 1000)

    //Expect 3986.01 ETH in system now
    const entireSystemColl_3 = (await activePool.getSystemCollShares())
    th.assertIsApproximatelyEqual(entireSystemColl_3, totalCollAfterL1.add(th.applyLiquidationFee(toBN('0'))))

    // check EBTC gas compensation
//    th.assertIsApproximatelyEqual((await ebtcToken.balanceOf(owner)).toString(), dec(2, 16))
  })

  // --- Cdp withdraws collateral ---

  it("redistribution: A,B,C Open. Liq(C). B withdraws coll. Liq(A). B acquires all coll and debt", async () => {
    // A, B, C open cdps
    await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("2000")});
    await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("2000")});
    await _signer.sendTransaction({ to: carol, value: ethers.utils.parseEther("2000")});
    const { collateral: A_coll, totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(400, 16)), extraParams: { from: alice } })
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(110, 18), extraParams: { from: bob } })
    const { collateral: C_coll, totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(110, 18), extraParams: { from: carol } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    // Price drops to 100 $/E
    let _newPrice = dec(3714, 13)
    await priceFeed.setPrice(_newPrice)

    // Liquidate Carol
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from: carol});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from: bob});
    const txC = await cdpManager.liquidate(_carolCdpId, {from: owner})
    assert.isTrue(txC.receipt.status)
    assert.isFalse(await sortedCdps.contains(_carolCdpId))
	
    let _totalStakesAfterCarolLiq = await cdpManager.totalStakes();
    let _carolDebtRedistributed = C_totalDebt.sub(C_coll.mul(toBN(_newPrice)).div(LICR));

    // Price bounces back to 200 $/E
    await priceFeed.setPrice(dec(7428, 13))

    // Alice withdraws EBTC
    await borrowerOperations.withdrawDebt(_aliceCdpId, await getNetBorrowingAmount(A_totalDebt), _aliceCdpId, _aliceCdpId, { from: alice })

    // Price drops to 100 $/E
    await priceFeed.setPrice(_newPrice)	
    let _aliceTotalDebt = (await cdpManager.getSyncedDebtAndCollShares(_aliceCdpId))[0];

    // Liquidate Alice
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from: alice});
    const txA = await cdpManager.liquidate(_aliceCdpId, {from: owner})
    assert.isTrue(txA.receipt.status)
    assert.isFalse(await sortedCdps.contains(_aliceCdpId))
	
    let _totalStakesAfterAliceLiq = await cdpManager.totalStakes();
    let _aliceDebtRedistributed = _aliceTotalDebt.sub(A_coll.mul(toBN(_newPrice)).div(LICR));

    // Expect Bob now holds all Ether and EBTCDebt in the system: 2.5 Ether and 300 EBTC
    // 1 + 0.995/2 - 0.5 + 1.4975*0.995
    const bob_Coll = ((await cdpManager.Cdps(_bobCdpId))[1]).toString()

    let _bobPendingDebtRewards = await cdpManager.getPendingRedistributedDebt(_bobCdpId);
    const bob_EBTCDebt = ((await cdpManager.Cdps(_bobCdpId))[0]
      .add(_bobPendingDebtRewards))
      .toString()
	
    let _carolDebtRedistributedToBob = _carolDebtRedistributed.mul((await cdpManager.getCdpStake(_bobCdpId))).div(_totalStakesAfterCarolLiq);
    let _aliceDebtRedistributedToBob = _aliceDebtRedistributed.mul((await cdpManager.getCdpStake(_bobCdpId))).div(_totalStakesAfterAliceLiq);

    const expected_B_coll = B_coll
          .sub(toBN('0'))
          .add(th.applyLiquidationFee(toBN('0')))
          .add(th.applyLiquidationFee(toBN('0')).mul(B_coll).div(A_coll.add(B_coll)))
          .add(th.applyLiquidationFee(th.applyLiquidationFee(toBN('0')).mul(A_coll).div(A_coll.add(B_coll))))
    assert.isAtMost(th.getDifference(bob_Coll, expected_B_coll), 1000)
    assert.isAtMost(th.getDifference(bob_EBTCDebt, _carolDebtRedistributedToBob.add(B_totalDebt).add(_aliceDebtRedistributedToBob)), 2000)
  })

  it("redistribution: A,B,C Open. Liq(C). B withdraws coll. D Opens. Liq(D). Distributes correct rewards.", async () => {
    // A, B, C open cdps
    await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("2000")});
    await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("2000")});
    await _signer.sendTransaction({ to: carol, value: ethers.utils.parseEther("2000")});
    const { collateral: A_coll, totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(400, 16)), extraParams: { from: alice } })
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(110, 18), extraParams: { from: bob } })
    const { collateral: C_coll, totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(110, 18), extraParams: { from: carol } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    // Price drops to 100 $/E
    let _newPrice = dec(3714, 13);
    await priceFeed.setPrice(_newPrice)

    // Liquidate Carol
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from: carol});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from: alice});
    const { collateral: Owner_coll, totalDebt: Owner_totalDebt } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: owner } })
    let _ownerCdpId = await sortedCdps.cdpOfOwnerByIndex(owner, 0);
    const txC = await cdpManager.liquidate(_carolCdpId, {from: owner})
    assert.isTrue(txC.receipt.status)
    assert.isFalse(await sortedCdps.contains(_carolCdpId))
	
    let _totalStakesAfterCarolLiq = await cdpManager.totalStakes();
    let _carolDebtRedistributed = C_totalDebt.sub(C_coll.mul(toBN(_newPrice)).div(LICR));

    // Price bounces back to 200 $/E
    await priceFeed.setPrice(dec(7428, 13))

    // D opens cdp
    await _signer.sendTransaction({ to: dennis, value: ethers.utils.parseEther("2000")});
    const { collateral: D_coll, totalDebt: D_totalDebt } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(110, 18), extraParams: { from: dennis } })
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);

    // Price drops to 100 $/E
    await priceFeed.setPrice(_newPrice)

    // Liquidate D
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from: dennis});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from: bob});
    const txA = await cdpManager.liquidate(_dennisCdpId, {from: owner})
    assert.isTrue(txA.receipt.status)
    assert.isFalse(await sortedCdps.contains(_dennisCdpId))
	
    let _totalStakesAfterDennisLiq = await cdpManager.totalStakes();
    let _dennisDebtRedistributed = D_totalDebt.sub(D_coll.mul(toBN(_newPrice)).div(LICR));
	
    let _carolDebtRedistributedToAlice = _carolDebtRedistributed.mul((await cdpManager.getCdpStake(_aliceCdpId))).div(_totalStakesAfterCarolLiq);
    let _carolDebtRedistributedToBob = _carolDebtRedistributed.mul((await cdpManager.getCdpStake(_bobCdpId))).div(_totalStakesAfterCarolLiq);
    let _dennisDebtRedistributedToAlice = _dennisDebtRedistributed.mul((await cdpManager.getCdpStake(_aliceCdpId))).div(_totalStakesAfterDennisLiq);
    let _dennisDebtRedistributedToBob = _dennisDebtRedistributed.mul((await cdpManager.getCdpStake(_bobCdpId))).div(_totalStakesAfterDennisLiq);

    /* Bob rewards:
     L1: 0.4975 ETH, 55 EBTC
     L2: (0.9975/2.495)*0.995 = 0.3978 ETH , 110*(0.9975/2.495)= 43.98 EBTCDebt

    coll: (1 + 0.4975 - 0.5 + 0.3968) = 1.3953 ETH
    debt: (110 + 55 + 43.98 = 208.98 EBTCDebt 

     Alice rewards:
    L1 0.4975, 55 EBTC
    L2 (1.4975/2.495)*0.995 = 0.5972 ETH, 110*(1.4975/2.495) = 66.022 EBTCDebt

    coll: (1 + 0.4975 + 0.5972) = 2.0947 ETH
    debt: (50 + 55 + 66.022) = 171.022 EBTC Debt

    totalColl: 3.49 ETH
    totalDebt 380 EBTC (Includes 50 in each cdp for gas compensation)
    */
    const bob_Coll = ((await cdpManager.Cdps(_bobCdpId))[1]).toString()

    let _bobPendingDebtRewards = await cdpManager.getPendingRedistributedDebt(_bobCdpId);
    const bob_EBTCDebt = ((await cdpManager.Cdps(_bobCdpId))[0]
      .add(_bobPendingDebtRewards))
      .toString()

    const alice_Coll = ((await cdpManager.Cdps(_aliceCdpId))[1]).toString()

    let _alicePendingDebtRewards = await cdpManager.getPendingRedistributedDebt(_aliceCdpId);
    const alice_EBTCDebt = ((await cdpManager.Cdps(_aliceCdpId))[0]
      .add(_alicePendingDebtRewards))
      .toString()

    const totalCollAfterL1 = A_coll.add(B_coll).sub(toBN('0')).add(th.applyLiquidationFee(toBN('0')))
    const B_collAfterL1 = B_coll.add(B_coll.mul(th.applyLiquidationFee(toBN('0'))).div(A_coll.add(B_coll))).sub(toBN('0'))
    const expected_B_coll = B_collAfterL1.add(B_collAfterL1.mul(th.applyLiquidationFee(toBN('0'))).div(totalCollAfterL1))
    const expected_B_debt = B_totalDebt
          .add(_carolDebtRedistributedToBob)
          .add(_dennisDebtRedistributedToBob)
    assert.isAtMost(th.getDifference(bob_Coll, expected_B_coll), 1000)
    assert.isAtMost(th.getDifference(bob_EBTCDebt, expected_B_debt), 10000)

    const A_collAfterL1 = A_coll.add(A_coll.mul(th.applyLiquidationFee(toBN('0'))).div(A_coll.add(B_coll)))
    const expected_A_coll = A_collAfterL1.add(A_collAfterL1.mul(th.applyLiquidationFee(toBN('0'))).div(totalCollAfterL1))
    const expected_A_debt = A_totalDebt
          .add(_carolDebtRedistributedToAlice)
          .add(_dennisDebtRedistributedToAlice)
    assert.isAtMost(th.getDifference(alice_Coll, expected_A_coll), 1000)
    assert.isAtMost(th.getDifference(alice_EBTCDebt, expected_A_debt), 10000)

    const entireSystemColl = (await activePool.getSystemCollShares())
    th.assertIsApproximatelyEqual(entireSystemColl, A_coll.add(B_coll).add(Owner_coll).add(th.applyLiquidationFee(toBN('0'))).sub(toBN('0')).add(th.applyLiquidationFee(toBN('0'))))
    const entireSystemDebt = (await activePool.getSystemDebt())
    let _aliceDebt = await cdpManager.getCdpDebt(_aliceCdpId);
    let _bobDebt = await cdpManager.getCdpDebt(_bobCdpId);
    let _ownerDebt = await cdpManager.getCdpDebt(_ownerCdpId);
    th.assertIsApproximatelyEqual(entireSystemDebt, _aliceDebt.add(_bobDebt).add(_ownerDebt).add(_carolDebtRedistributed).add(_dennisDebtRedistributed))
  })

  it("redistribution: Cdp with the majority stake withdraws. A,B,C,D open. Liq(D). C withdraws some coll. E Enters, Liq(E). Distributes correct rewards", async () => {
    const _998_Ether = toBN('998000000000000000000')
    // A, B, C, D open cdps
    await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("5000")});
    await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("5000")});
    await _signer.sendTransaction({ to: carol, value: ethers.utils.parseEther("3000")});
    await _signer.sendTransaction({ to: dennis, value: ethers.utils.parseEther("3000")});
    const { collateral: A_coll } = await openCdp({ ICR: toBN(dec(400, 16)), extraParams: { from: alice } })
    const { collateral: B_coll } = await openCdp({ ICR: toBN(dec(400, 16)), extraEBTCAmount: dec(110, 18), extraParams: { from: bob } })
    const { collateral: C_coll } = await openCdp({ extraEBTCAmount: dec(11, 18), extraParams: { from: carol, value: _998_Ether } })
    const { collateral: D_coll } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(110, 18), extraParams: { from: dennis, value: dec(1000, 'ether') } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);

    // Price drops to 100 $/E
    await priceFeed.setPrice(dec(3714, 13))

    // Liquidate Dennis
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from: dennis});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from: alice});
    await _signer.sendTransaction({ to: owner, value: ethers.utils.parseEther("2000")});
    const { collateral: Owner_coll } = await openCdp({ ICR: toBN(dec(400, 16)), extraEBTCAmount: dec(110, 18), extraParams: { from: owner } })
    const txD = await cdpManager.liquidate(_dennisCdpId, {from: owner})
    assert.isTrue(txD.receipt.status)
    assert.isFalse(await sortedCdps.contains(_dennisCdpId))

    // Price bounces back to 200 $/E
    await priceFeed.setPrice(dec(7428, 13))

    //Expect 1995 ETH in system now
    const entireSystemColl_1 = (await activePool.getSystemCollShares())
    th.assertIsApproximatelyEqual(entireSystemColl_1, A_coll.add(B_coll).add(C_coll).add(Owner_coll).add(th.applyLiquidationFee(toBN('0'))))

    const totalColl = A_coll.add(B_coll).add(C_coll).add(Owner_coll)

    //Carol wthdraws 1 ETH from her cdp, brings it to 1990.01 total coll
    const C_withdrawnColl = toBN(dec(1, 'ether'))
    await borrowerOperations.withdrawColl(_carolCdpId, C_withdrawnColl, _carolCdpId, _carolCdpId, { from: carol })

    //Expect 1994 ETH in system now
    const entireSystemColl_2 = (await activePool.getSystemCollShares())
    th.assertIsApproximatelyEqual(entireSystemColl_2, totalColl.add(th.applyLiquidationFee(toBN('0'))).sub(C_withdrawnColl))

    // E opens with another 1994 ETH
    const { collateral: E_coll } = await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: erin, value: entireSystemColl_2 } })
    let _erinCdpId = await sortedCdps.cdpOfOwnerByIndex(erin, 0);

    // Price drops to 100 $/E
    await priceFeed.setPrice(dec(3714, 13))

    // Liquidate Erin
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from: bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(erin)), {from: erin});
    const txE = await cdpManager.liquidate(_erinCdpId, {from: owner})
    assert.isTrue(txE.receipt.status)
    assert.isFalse(await sortedCdps.contains(_erinCdpId))

    /* Expected ETH rewards: 
     Carol = 1990.01/1994 * 1994*0.995 = 1980.05995 ETH
     Alice = 1.995/1994 * 1994*0.995 = 1.985025 ETH
     Bob = 1.995/1994 * 1994*0.995 = 1.985025 ETH

    therefore, expected total collateral:

    Carol = 1990.01 + 1980.05995 = 3970.06995
    Alice = 1.995 + 1.985025 = 3.980025 ETH
    Bob = 1.995 + 1.985025 = 3.980025 ETH

    total = 3978.03 ETH
    */

    const alice_Coll = ((await cdpManager.Cdps(_aliceCdpId))[1]).toString()

    const bob_Coll = ((await cdpManager.Cdps(_bobCdpId))[1]).toString()

    const carol_Coll = ((await cdpManager.Cdps(_carolCdpId))[1]).toString()

    const totalCollAfterL1 = A_coll.add(B_coll).add(C_coll).add(Owner_coll).add(th.applyLiquidationFee(toBN('0'))).sub(C_withdrawnColl)
    const A_collAfterL1 = A_coll.add(A_coll.mul(th.applyLiquidationFee(toBN('0'))).div(A_coll.add(B_coll).add(C_coll)))
    const expected_A_coll = A_collAfterL1.add(A_collAfterL1.mul(th.applyLiquidationFee(toBN('0'))).div(totalCollAfterL1))
    const B_collAfterL1 = B_coll.add(B_coll.mul(th.applyLiquidationFee(toBN('0'))).div(A_coll.add(B_coll).add(C_coll)))
    const expected_B_coll = B_collAfterL1.add(B_collAfterL1.mul(th.applyLiquidationFee(toBN('0'))).div(totalCollAfterL1))
    const C_collAfterL1 = C_coll.add(C_coll.mul(th.applyLiquidationFee(toBN('0'))).div(A_coll.add(B_coll).add(C_coll))).sub(C_withdrawnColl)
    const expected_C_coll = C_collAfterL1.add(C_collAfterL1.mul(th.applyLiquidationFee(toBN('0'))).div(totalCollAfterL1))

    assert.isAtMost(th.getDifference(alice_Coll, expected_A_coll), 1000)
    assert.isAtMost(th.getDifference(bob_Coll, expected_B_coll), 1000)
    assert.isAtMost(th.getDifference(carol_Coll, expected_C_coll), 1000)

    //Expect 3978.03 ETH in system now
    const entireSystemColl_3 = (await activePool.getSystemCollShares())
    th.assertIsApproximatelyEqual(entireSystemColl_3, totalCollAfterL1.add(th.applyLiquidationFee(toBN('0'))))

    // check EBTC gas compensation
//    assert.equal((await ebtcToken.balanceOf(owner)).toString(), dec(2, 16))
  })

  it("redistribution: Cdp with the majority stake withdraws. A,B,C,D open. Liq(D). A, B, C withdraw. E Enters, Liq(E). Distributes correct rewards", async () => {
    const _998_Ether = toBN('998000000000000000000')
    // A, B, C, D open cdps
    await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("5000")});
    await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("5000")});
    await _signer.sendTransaction({ to: carol, value: ethers.utils.parseEther("3000")});
    await _signer.sendTransaction({ to: dennis, value: ethers.utils.parseEther("3000")});
    const { collateral: A_coll } = await openCdp({ ICR: toBN(dec(400, 16)), extraParams: { from: alice } })
    const { collateral: B_coll } = await openCdp({ ICR: toBN(dec(400, 16)), extraEBTCAmount: dec(110, 18), extraParams: { from: bob } })
    const { collateral: C_coll } = await openCdp({ extraEBTCAmount: dec(11, 18), extraParams: { from: carol, value: _998_Ether } })
    const { collateral: D_coll } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(110, 18), extraParams: { from: dennis, value: dec(1000, 'ether') } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);

    // Price drops to 100 $/E
    await priceFeed.setPrice(dec(3714, 13))

    // Liquidate Dennis
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from: dennis});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from: alice});
    await _signer.sendTransaction({ to: owner, value: ethers.utils.parseEther("2000")});
    const { collateral: Owner_coll } = await openCdp({ ICR: toBN(dec(400, 16)), extraEBTCAmount: dec(110, 18), extraParams: { from: owner } })
    const txD = await cdpManager.liquidate(_dennisCdpId, {from: owner})
    assert.isTrue(txD.receipt.status)
    assert.isFalse(await sortedCdps.contains(_dennisCdpId))

    // Price bounces back to 200 $/E
    await priceFeed.setPrice(dec(7428, 13))

    //Expect 1995 ETH in system now
    const entireSystemColl_1 = (await activePool.getSystemCollShares())
    th.assertIsApproximatelyEqual(entireSystemColl_1, A_coll.add(B_coll).add(C_coll).add(Owner_coll).add(th.applyLiquidationFee(toBN('0'))))

    const totalColl = A_coll.add(B_coll).add(C_coll).add(Owner_coll)

    /* Alice, Bob, Carol each withdraw 0.5 ETH to their cdps, 
    bringing them to 1.495, 1.495, 1990.51 total coll each. */
    const withdrawnColl = toBN(dec(500, 'finney'))
    await borrowerOperations.withdrawColl(_aliceCdpId, withdrawnColl, _aliceCdpId, _aliceCdpId, { from: alice })
    await borrowerOperations.withdrawColl(_bobCdpId, withdrawnColl, _bobCdpId, _bobCdpId, { from: bob })
    await borrowerOperations.withdrawColl(_carolCdpId, withdrawnColl, _carolCdpId, _carolCdpId, { from: carol })

    const alice_Coll_1 = ((await cdpManager.Cdps(_aliceCdpId))[1]).toString()

    const bob_Coll_1 = ((await cdpManager.Cdps(_bobCdpId))[1]).toString()

    const carol_Coll_1 = ((await cdpManager.Cdps(_carolCdpId))[1]).toString()

    const totalColl_1 = A_coll.add(B_coll).add(C_coll)
    assert.isAtMost(th.getDifference(alice_Coll_1, A_coll.add(th.applyLiquidationFee(toBN('0')).mul(A_coll).div(totalColl_1)).sub(withdrawnColl)), 1000)
    assert.isAtMost(th.getDifference(bob_Coll_1, B_coll.add(th.applyLiquidationFee(toBN('0')).mul(B_coll).div(totalColl_1)).sub(withdrawnColl)), 1000)
    assert.isAtMost(th.getDifference(carol_Coll_1, C_coll.add(th.applyLiquidationFee(toBN('0')).mul(C_coll).div(totalColl_1)).sub(withdrawnColl)), 1000)

    //Expect 1993.5 ETH in system now
    const entireSystemColl_2 = (await activePool.getSystemCollShares())
    th.assertIsApproximatelyEqual(entireSystemColl_2, totalColl.add(th.applyLiquidationFee(toBN('0'))).sub(withdrawnColl.mul(toBN(3))))

    // E opens with another 1993.5 ETH
    const { collateral: E_coll } = await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: erin, value: entireSystemColl_2 } })
    let _erinCdpId = await sortedCdps.cdpOfOwnerByIndex(erin, 0);

    // Price drops to 100 $/E
    await priceFeed.setPrice(dec(3714, 13))

    // Liquidate Erin
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from: bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(erin)), {from: erin});
    const txE = await cdpManager.liquidate(_erinCdpId, {from: owner})
    assert.isTrue(txE.receipt.status)
    assert.isFalse(await sortedCdps.contains(_erinCdpId))

    /* Expected ETH rewards: 
     Carol = 1990.51/1993.5 * 1993.5*0.995 = 1980.55745 ETH
     Alice = 1.495/1993.5 * 1993.5*0.995 = 1.487525 ETH
     Bob = 1.495/1993.5 * 1993.5*0.995 = 1.487525 ETH

    therefore, expected total collateral:

    Carol = 1990.51 + 1980.55745 = 3971.06745
    Alice = 1.495 + 1.487525 = 2.982525 ETH
    Bob = 1.495 + 1.487525 = 2.982525 ETH

    total = 3977.0325 ETH
    */

    const alice_Coll_2 = ((await cdpManager.Cdps(_aliceCdpId))[1]).toString()

    const bob_Coll_2 = ((await cdpManager.Cdps(_bobCdpId))[1]).toString()

    const carol_Coll_2 = ((await cdpManager.Cdps(_carolCdpId))[1]).toString()

    const totalCollAfterL1 = A_coll.add(B_coll).add(C_coll).add(Owner_coll).add(th.applyLiquidationFee(toBN('0'))).sub(withdrawnColl.mul(toBN(3)))
    const A_collAfterL1 = A_coll.add(A_coll.mul(th.applyLiquidationFee(toBN('0'))).div(A_coll.add(B_coll).add(C_coll))).sub(withdrawnColl)
    const expected_A_coll = A_collAfterL1.add(A_collAfterL1.mul(th.applyLiquidationFee(toBN('0'))).div(totalCollAfterL1))
    const B_collAfterL1 = B_coll.add(B_coll.mul(th.applyLiquidationFee(toBN('0'))).div(A_coll.add(B_coll).add(C_coll))).sub(withdrawnColl)
    const expected_B_coll = B_collAfterL1.add(B_collAfterL1.mul(th.applyLiquidationFee(toBN('0'))).div(totalCollAfterL1))
    const C_collAfterL1 = C_coll.add(C_coll.mul(th.applyLiquidationFee(toBN('0'))).div(A_coll.add(B_coll).add(C_coll))).sub(withdrawnColl)
    const expected_C_coll = C_collAfterL1.add(C_collAfterL1.mul(th.applyLiquidationFee(toBN('0'))).div(totalCollAfterL1))

    assert.isAtMost(th.getDifference(alice_Coll_2, expected_A_coll), 1000)
    assert.isAtMost(th.getDifference(bob_Coll_2, expected_B_coll), 1000)
    assert.isAtMost(th.getDifference(carol_Coll_2, expected_C_coll), 1000)

    //Expect 3977.0325 ETH in system now
    const entireSystemColl_3 = (await activePool.getSystemCollShares())
    th.assertIsApproximatelyEqual(entireSystemColl_3, totalCollAfterL1.add(th.applyLiquidationFee(toBN('0'))))

    // check EBTC gas compensation
//    assert.equal((await ebtcToken.balanceOf(owner)).toString(), dec(2, 16))
  })

  // For calculations of correct values used in test, see scenario 1:
  // https://docs.google.com/spreadsheets/d/1F5p3nZy749K5jwO-bwJeTsRoY7ewMfWIQ3QHtokxqzo/edit?usp=sharing
  it("redistribution, all operations: A,B,C open. Liq(A). D opens. B adds, C withdraws. Liq(B). E & F open. D adds. Liq(F). Distributes correct rewards", async () => {
    // A, B, C open cdps
    await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("2000")});
    await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("2000")});
    await _signer.sendTransaction({ to: carol, value: ethers.utils.parseEther("2000")});
    const { collateral: A_coll } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: alice } })
    const { collateral: B_coll } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: bob } })
    const { collateral: C_coll } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: carol } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    // Price drops to 1 $/E
    await priceFeed.setPrice(dec(100, 13))

    // Liquidate A 
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from: carol});	 
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from: alice});	 
    const txA = await cdpManager.liquidate(_aliceCdpId, {from: owner})
    assert.isTrue(txA.receipt.status)
    assert.isFalse(await sortedCdps.contains(_aliceCdpId))

    const totalStakesSnapshotAfterL1 = B_coll.add(C_coll)
    const totalCollateralSnapshotAfterL1 = totalStakesSnapshotAfterL1.add(th.applyLiquidationFee(toBN('0')))
    th.assertIsApproximatelyEqual(await cdpManager.totalStakesSnapshot(), totalStakesSnapshotAfterL1)
    th.assertIsApproximatelyEqual(await cdpManager.totalCollateralSnapshot(), totalCollateralSnapshotAfterL1)

    // Price rises to 1000
    await priceFeed.setPrice(dec(9000, 13))

    // D opens cdp
    await _signer.sendTransaction({ to: dennis, value: ethers.utils.parseEther("3000")});
    const { collateral: D_coll, totalDebt: D_totalDebt } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(110, 18), extraParams: { from: dennis } })
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);

    //Bob adds 1 ETH to his cdp
    const B_addedColl = toBN(dec(1, 'ether'))
    await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: bob});
    await contracts.collateral.deposit({from: bob, value: B_addedColl});
    await borrowerOperations.addColl(_bobCdpId, _bobCdpId, _bobCdpId, B_addedColl, { from: bob, value: 0  })

    //Carol  withdraws 1 ETH from her cdp
    const C_withdrawnColl = toBN(dec(1, 'ether'))
    await borrowerOperations.withdrawColl(_carolCdpId, C_withdrawnColl, _carolCdpId, _carolCdpId, { from: carol })

    const B_collAfterL1 = B_coll.add(B_addedColl)
    const C_collAfterL1 = C_coll.sub(C_withdrawnColl)

    // Price drops
    await priceFeed.setPrice(dec(100, 13))

    // Liquidate B
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from: bob});	 
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from: dennis});
    const txB = await cdpManager.liquidate(_bobCdpId, {from: owner})
    assert.isTrue(txB.receipt.status)
    assert.isFalse(await sortedCdps.contains(_bobCdpId))

    const totalStakesSnapshotAfterL2 = totalStakesSnapshotAfterL1.add(D_coll.mul(totalStakesSnapshotAfterL1).div(totalCollateralSnapshotAfterL1)).sub(B_coll).sub(C_withdrawnColl.mul(totalStakesSnapshotAfterL1).div(totalCollateralSnapshotAfterL1))
    const totalCollateralSnapshotAfterL2 = C_coll.sub(C_withdrawnColl).add(D_coll)
    th.assertIsApproximatelyEqual(await cdpManager.totalStakesSnapshot(), totalStakesSnapshotAfterL2)
    th.assertIsApproximatelyEqual(await cdpManager.totalCollateralSnapshot(), totalCollateralSnapshotAfterL2)

    // Price rises to 1000
    await priceFeed.setPrice(dec(9000, 13))

    // E and F open cdps
    await _signer.sendTransaction({ to: erin, value: ethers.utils.parseEther("2000")});
    await _signer.sendTransaction({ to: freddy, value: ethers.utils.parseEther("2000")});
    const { collateral: E_coll, totalDebt: E_totalDebt } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(110, 18), extraParams: { from: erin } })
    const { collateral: F_coll, totalDebt: F_totalDebt } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(110, 18), extraParams: { from: freddy } })
    let _erinCdpId = await sortedCdps.cdpOfOwnerByIndex(erin, 0);
    let _freddyCdpId = await sortedCdps.cdpOfOwnerByIndex(freddy, 0);

    // D tops up
    const D_addedColl = toBN(dec(1, 'ether'))
    await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: dennis});
    await contracts.collateral.deposit({from: dennis, value: D_addedColl});
    await borrowerOperations.addColl(_dennisCdpId, _dennisCdpId, _dennisCdpId, D_addedColl, { from: dennis, value: 0 })

    // Price drops to 1
    await priceFeed.setPrice(dec(100, 13))

    // Liquidate F
    await debtToken.transfer(owner, (await debtToken.balanceOf(freddy)), {from: freddy});	 
    await debtToken.transfer(owner, (await debtToken.balanceOf(erin)), {from: erin});
    const txF = await cdpManager.liquidate(_freddyCdpId, {from: owner})
    assert.isTrue(txF.receipt.status)
    assert.isFalse(await sortedCdps.contains(_freddyCdpId))

    // Grab remaining cdps' collateral
    const carol_rawColl = (await cdpManager.Cdps(_carolCdpId))[1].toString()

    const dennis_rawColl = (await cdpManager.Cdps(_dennisCdpId))[1].toString()

    const erin_rawColl = (await cdpManager.Cdps(_erinCdpId))[1].toString()

    // Check raw collateral of C, D, E
    const C_collAfterL2 = C_collAfterL1
    const D_collAfterL2 = D_coll.add(D_addedColl)
    const totalCollForL3 = C_collAfterL2.add(D_collAfterL2).add(E_coll)
    const C_collAfterL3 = C_collAfterL2.add(C_collAfterL2.mul(th.applyLiquidationFee(toBN('0'))).div(totalCollForL3))
    const D_collAfterL3 = D_collAfterL2.add(D_collAfterL2.mul(th.applyLiquidationFee(toBN('0'))).div(totalCollForL3))
    const E_collAfterL3 = E_coll.add(E_coll.mul(th.applyLiquidationFee(toBN('0'))).div(totalCollForL3))
    assert.isAtMost(th.getDifference(carol_rawColl, C_collAfterL1), 1000)
    assert.isAtMost(th.getDifference(dennis_rawColl, D_collAfterL2), 1000000)
    assert.isAtMost(th.getDifference(erin_rawColl, E_coll), 1000)

    // Check systemic collateral
    const activeColl = (await activePool.getSystemCollShares()).toString()

    assert.isAtMost(th.getDifference(activeColl, C_collAfterL1.add(D_collAfterL2.add(E_coll))), 1000000)

    // Check system snapshots
    const totalStakesSnapshotAfterL3 = totalStakesSnapshotAfterL2.add(D_addedColl.add(E_coll).mul(totalStakesSnapshotAfterL2).div(totalCollateralSnapshotAfterL2))
    const totalCollateralSnapshotAfterL3 = C_coll.sub(C_withdrawnColl).add(D_coll).add(D_addedColl).add(E_coll)
    const totalStakesSnapshot = (await cdpManager.totalStakesSnapshot()).toString()
    const totalCollateralSnapshot = (await cdpManager.totalCollateralSnapshot()).toString()
    th.assertIsApproximatelyEqual(totalStakesSnapshot, totalStakesSnapshotAfterL3)
    th.assertIsApproximatelyEqual(totalCollateralSnapshot, totalCollateralSnapshotAfterL3)

    // check EBTC gas compensation
//    assert.equal((await ebtcToken.balanceOf(owner)).toString(), dec(3, 16))
  })

  // For calculations of correct values used in test, see scenario 2:
  // https://docs.google.com/spreadsheets/d/1F5p3nZy749K5jwO-bwJeTsRoY7ewMfWIQ3QHtokxqzo/edit?usp=sharing
  it("redistribution, all operations: A,B,C open. Liq(A). D opens. B adds, C withdraws. Liq(B). E & F open. D adds. Liq(F). Varying coll. Distributes correct rewards", async () => {
    /* A, B, C open cdps.
    A: 450 ETH
    B: 8901 ETH
    C: 23.902 ETH
    */
    const { collateral: A_coll } = await openCdp({ ICR: toBN(dec(90000, 16)), extraParams: { from: alice, value: toBN('450000000000000000000') } })
	
    await beadpSigner.sendTransaction({ to: bob, value: ethers.utils.parseEther("180001")});
    const { collateral: B_coll } = await openCdp({ ICR: toBN(dec(1800000, 16)), extraParams: { from: bob, value: toBN('8901000000000000000000') } })
    const { collateral: C_coll } = await openCdp({ ICR: toBN(dec(4600, 16)), extraParams: { from: carol, value: toBN('23902000000000000000') } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    // Price drops 
    await priceFeed.setPrice('1')

    // Liquidate A
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from: alice});	 
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from: carol});	 
    const txA = await cdpManager.liquidate(_aliceCdpId, {from: owner})
    assert.isTrue(txA.receipt.status)
    assert.isFalse(await sortedCdps.contains(_aliceCdpId))

    const totalStakesSnapshotAfterL1 = B_coll.add(C_coll)
    const totalCollateralSnapshotAfterL1 = totalStakesSnapshotAfterL1.add(th.applyLiquidationFee(toBN('0')))
    th.assertIsApproximatelyEqual(await cdpManager.totalStakesSnapshot(), totalStakesSnapshotAfterL1)
    th.assertIsApproximatelyEqual(await cdpManager.totalCollateralSnapshot(), totalCollateralSnapshotAfterL1)

    // Price rises 
    await priceFeed.setPrice(dec(1, 27))

    // D opens cdp: 350 ETH
    const { collateral: D_coll} = await openCdp({ extraEBTCAmount: dec(100, 18), extraParams: { from: dennis, value: toBN(dec(350, 18)) } })
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);

    // Bob adds 11.33909 ETH to his cdp
    const B_addedColl = toBN('11339090000000000000')
    await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: bob});
    await contracts.collateral.deposit({from: bob, value: B_addedColl});
    await borrowerOperations.addColl(_bobCdpId, _bobCdpId, _bobCdpId, B_addedColl, { from: bob, value: 0 })

    // Carol withdraws 15 ETH from her cdp
    const C_withdrawnColl = toBN(dec(15, 'ether'))
    await borrowerOperations.withdrawColl(_carolCdpId, C_withdrawnColl, _carolCdpId, _carolCdpId, { from: carol })

    const B_collAfterL1 = B_coll.add(B_addedColl)
    const C_collAfterL1 = C_coll.sub(C_withdrawnColl)

    // Price drops
    await priceFeed.setPrice('1')

    // Liquidate B
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from: bob});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(dennis)), {from: dennis});
    const txB = await cdpManager.liquidate(_bobCdpId, {from: owner})
    assert.isTrue(txB.receipt.status)
    assert.isFalse(await sortedCdps.contains(_bobCdpId))
	
    const C_collAfterL2 = C_collAfterL1;

    const totalStakesSnapshotAfterL2 = totalStakesSnapshotAfterL1.add(D_coll.mul(totalStakesSnapshotAfterL1).div(totalCollateralSnapshotAfterL1)).sub(B_coll).sub(C_withdrawnColl.mul(totalStakesSnapshotAfterL1).div(totalCollateralSnapshotAfterL1))
    const totalCollateralSnapshotAfterL2 = C_coll.sub(C_withdrawnColl).add(D_coll)
    th.assertIsApproximatelyEqual(await cdpManager.totalStakesSnapshot(), totalStakesSnapshotAfterL2)
    th.assertIsApproximatelyEqual(await cdpManager.totalCollateralSnapshot(), totalCollateralSnapshotAfterL2)

    // Price rises 
    await priceFeed.setPrice(dec(1, 27))

    /* E and F open cdps.
    E: 10000 ETH
    F: 700 ETH
    */
    const { collateral: E_coll, totalDebt: E_totalDebt } = await openCdp({ extraEBTCAmount: dec(100, 18), extraParams: { from: erin, value: toBN(dec(1, 22)) } })
    const { collateral: F_coll, totalDebt: F_totalDebt } = await openCdp({ extraEBTCAmount: dec(100, 18), extraParams: { from: freddy, value: toBN(dec(700, 18)) } })
    let _erinCdpId = await sortedCdps.cdpOfOwnerByIndex(erin, 0);
    let _freddyCdpId = await sortedCdps.cdpOfOwnerByIndex(freddy, 0);

    // D tops up
    const D_addedColl = toBN(dec(1, 'ether'))
    await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: dennis});
    await contracts.collateral.deposit({from: dennis, value: D_addedColl});
    await borrowerOperations.addColl(_dennisCdpId, _dennisCdpId, _dennisCdpId, D_addedColl, { from: dennis, value: 0 })

    const D_collAfterL2 = D_coll.add(D_addedColl)

    // Price drops 
    await priceFeed.setPrice('1')

    // Liquidate F
    await debtToken.transfer(owner, (await debtToken.balanceOf(erin)), {from: erin});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(freddy)), {from: freddy});	
    const txF = await cdpManager.liquidate(_freddyCdpId, {from: owner})
    assert.isTrue(txF.receipt.status)
    assert.isFalse(await sortedCdps.contains(_freddyCdpId))

    // Grab remaining cdps' collateral
    const carol_rawColl = (await cdpManager.Cdps(_carolCdpId))[1].toString()
    const carol_Stake = (await cdpManager.Cdps(_carolCdpId))[2].toString()

    const dennis_rawColl = (await cdpManager.Cdps(_dennisCdpId))[1].toString()
    const dennis_Stake = (await cdpManager.Cdps(_dennisCdpId))[2].toString()

    const erin_rawColl = (await cdpManager.Cdps(_erinCdpId))[1].toString()
    const erin_Stake = (await cdpManager.Cdps(_erinCdpId))[2].toString()

    // Check raw collateral of C, D, E
    const totalCollForL3 = C_collAfterL2.add(D_collAfterL2).add(E_coll)
    const C_collAfterL3 = C_collAfterL2.add(C_collAfterL2.mul(th.applyLiquidationFee(toBN('0'))).div(totalCollForL3))
    const D_collAfterL3 = D_collAfterL2.add(D_collAfterL2.mul(th.applyLiquidationFee(toBN('0'))).div(totalCollForL3))
    const E_collAfterL3 = E_coll.add(E_coll.mul(th.applyLiquidationFee(toBN('0'))).div(totalCollForL3))
    assert.isAtMost(th.getDifference(carol_rawColl, C_collAfterL1), 1000)
    assert.isAtMost(th.getDifference(dennis_rawColl, D_collAfterL2), 1000000)
    assert.isAtMost(th.getDifference(erin_rawColl, E_coll), 1000)

    // Check systemic collateral
    const activeColl = (await activePool.getSystemCollShares()).toString()

    assert.isAtMost(th.getDifference(activeColl, C_collAfterL1.add(D_collAfterL2.add(E_coll))), 1000000)

    // Check system snapshots
    const totalStakesSnapshotAfterL3 = totalStakesSnapshotAfterL2.add(D_addedColl.add(E_coll).mul(totalStakesSnapshotAfterL2).div(totalCollateralSnapshotAfterL2))
    const totalCollateralSnapshotAfterL3 = C_coll.sub(C_withdrawnColl).add(D_coll).add(D_addedColl).add(E_coll)
    const totalStakesSnapshot = (await cdpManager.totalStakesSnapshot()).toString()
    const totalCollateralSnapshot = (await cdpManager.totalCollateralSnapshot()).toString()
    th.assertIsApproximatelyEqual(totalStakesSnapshot, totalStakesSnapshotAfterL3)
    th.assertIsApproximatelyEqual(totalCollateralSnapshot, totalCollateralSnapshotAfterL3)

    // check EBTC gas compensation
//    assert.equal((await ebtcToken.balanceOf(owner)).toString(), dec(3, 16))
  })
})