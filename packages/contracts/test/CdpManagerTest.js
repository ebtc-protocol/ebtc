const deploymentHelper = require("../utils/deploymentHelpers.js")
const testHelpers = require("../utils/testHelpers.js")
const CdpManagerTester = artifacts.require("./CdpManagerTester.sol")
const EBTCTokenTester = artifacts.require("./EBTCTokenTester.sol")

const th = testHelpers.TestHelper
const dec = th.dec
const toBN = th.toBN
const assertRevert = th.assertRevert
const mv = testHelpers.MoneyValues
const timeValues = testHelpers.TimeValues

const GAS_PRICE = 10000000000 //10 GWEI

const hre = require("hardhat");

/* NOTE: Some tests involving ETH redemption fees do not test for specific fee values.
 * Some only test that the fees are non-zero when they should occur.
 *
 * Specific ETH gain values will depend on the final fee schedule used, and the final choices for
 * the parameter BETA in the CdpManager, which is still TBD based on economic modelling.
 * 
 */ 
contract('CdpManager', async accounts => {

  const _18_zeros = '000000000000000000'
  const ZERO_ADDRESS = th.ZERO_ADDRESS

  const [
    owner,
    alice, bob, carol, dennis, erin, flyn, graham, harriet, ida,
    defaulter_1, defaulter_2, defaulter_3, defaulter_4, whale,
    A, B, C, D, E] = accounts;

    const [bountyAddress, lpRewardsAddress, multisig] = accounts.slice(accounts.length - 3, accounts.length)
    const beadp = "0x00000000219ab540356cBB839Cbe05303d7705Fa";//beacon deposit
    let beadpSigner;

  let priceFeed
  let ebtcToken
  let sortedCdps
  let cdpManager
  let activePool
  let collSurplusPool
  let defaultPool
  let borrowerOperations
  let hintHelpers
  let authority;
  let contracts
  let _signer
  let collToken;
  let liqReward;

  const getOpenCdpTotalDebt = async (ebtcAmount) => th.getOpenCdpTotalDebt(contracts, ebtcAmount)
  const getOpenCdpEBTCAmount = async (totalDebt) => th.getOpenCdpEBTCAmount(contracts, totalDebt)
  const getActualDebtFromComposite = async (compositeDebt) => th.getActualDebtFromComposite(compositeDebt, contracts)
  const getNetBorrowingAmount = async (debtWithFee) => th.getNetBorrowingAmount(contracts, debtWithFee)
  const openCdp = async (params) => th.openCdp(contracts, params)
  const withdrawDebt = async (params) => th.withdrawDebt(contracts, params)

  before(async () => {	  
    await hre.network.provider.request({method: "hardhat_impersonateAccount", params: [beadp]}); 
    beadpSigner = await ethers.provider.getSigner(beadp);	
  })

  beforeEach(async () => {
    await deploymentHelper.setDeployGasPrice(GAS_PRICE)
    contracts = await deploymentHelper.deployTesterContractsHardhat()
    let LQTYContracts = {}
    LQTYContracts.feeRecipient = contracts.feeRecipient;

    priceFeed = contracts.priceFeedTestnet
    ebtcToken = contracts.ebtcToken
    sortedCdps = contracts.sortedCdps
    cdpManager = contracts.cdpManager
    activePool = contracts.activePool
    defaultPool = contracts.defaultPool
    collSurplusPool = contracts.collSurplusPool
    borrowerOperations = contracts.borrowerOperations
    hintHelpers = contracts.hintHelpers
    debtToken = ebtcToken;
    LICR = await cdpManager.LICR()
    MIN_CDP_SIZE = await cdpManager.MIN_NET_STETH_BALANCE()
    collToken = contracts.collateral;  
    liqReward = await contracts.borrowerOperations.LIQUIDATOR_REWARD();	

    feeRecipient = LQTYContracts.feeRecipient
    authority = contracts.authority;

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

  it("liquidate(): closes a Cdp that has ICR < MCR", async () => {
    await openCdp({ ICR: toBN(dec(20, 18)), extraParams: { from: whale } })
    await openCdp({ ICR: toBN(dec(4, 18)), extraParams: { from: alice } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);

    const price = await priceFeed.getPrice()
    const ICR_Before = await cdpManager.getCachedICR(_aliceCdpId, price)
    assert.equal(ICR_Before, '3999999999999999999')

    const MCR = (await cdpManager.MCR()).toString()
    assert.equal(MCR.toString(), '1100000000000000000')

    // Alice increases debt to 180 EBTC, lowering her ICR to 1.11
    const A_EBTCWithdrawal = await getNetBorrowingAmount(dec(130, 18))

    const targetICR = toBN('1111111111111111111')
    await withdrawDebt({_cdpId: _aliceCdpId, ICR: targetICR, extraParams: { from: alice } })

    const ICR_AfterWithdrawal = await cdpManager.getCachedICR(_aliceCdpId, price)
    assert.isAtMost(th.getDifference(ICR_AfterWithdrawal, targetICR), 100)

    // price drops to 1ETH:100EBTC, reducing Alice's ICR below MCR
    await priceFeed.setPrice(dec(3714, 13))

    // Confirm system is not in Recovery Mode
    assert.isFalse(await th.checkRecoveryMode(contracts));

    // close Cdp
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from: alice});	 
    await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from: whale});
    await cdpManager.liquidate(_aliceCdpId, { from: owner });

    // check the Cdp is successfully closed, and removed from sortedList
    const status = (await cdpManager.Cdps(_aliceCdpId))[4]
    assert.equal(status, 3)  // status enum 3 corresponds to "Closed by liquidation"
    const alice_Cdp_isInSortedList = await sortedCdps.contains(_aliceCdpId)
    assert.isFalse(alice_Cdp_isInSortedList)
  })

  it("liquidate(): decreases ActivePool ETH and EBTCDebt by correct amounts", async () => {
    // --- SETUP ---
    const { collateral: A_collateral, totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(4, 18)), extraParams: { from: alice } })
    const { collateral: B_collateral, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(21, 17)), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);

    // --- TEST ---

    // check ActivePool ETH and EBTC debt before
    const activePool_ETH_Before = (await activePool.getSystemCollShares()).toString()
    const activePool_collateral_Before = (await contracts.collateral.balanceOf(activePool.address)).toString()
    const activePool_EBTCDebt_Before = (await activePool.getSystemDebt()).toString()

    assert.equal(activePool_ETH_Before, A_collateral.add(B_collateral))
    assert.equal(activePool_collateral_Before, A_collateral.add(liqReward).add(B_collateral).add(liqReward))
    th.assertIsApproximatelyEqual(activePool_EBTCDebt_Before, A_totalDebt.add(B_totalDebt))

    // price drops to 1ETH:100EBTC, reducing Bob's ICR below MCR
    await priceFeed.setPrice(dec(3714, 13))

    // Confirm system is not in Recovery Mode
    assert.isFalse(await th.checkRecoveryMode(contracts));

    /* close Bob's Cdp. Should liquidate his ether and EBTC, 
    leaving Alice’s ether and EBTC debt in the ActivePool. */
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from: alice});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from: bob});
    await cdpManager.liquidate(_bobCdpId, { from: owner });

    // check ActivePool ETH and EBTC debt 
    const activePool_ETH_After = (await activePool.getSystemCollShares()).toString()
    const activePool_RawEther_After = (await contracts.collateral.balanceOf(activePool.address)).toString()
    const activePool_EBTCDebt_After = (await activePool.getSystemDebt()).toString()

    assert.equal(activePool_ETH_After, A_collateral)
    assert.equal(activePool_RawEther_After, A_collateral.add(liqReward))
    th.assertIsApproximatelyEqual(activePool_EBTCDebt_After, A_totalDebt)
  })

  it("liquidate(): removes the Cdp's stake from the total stakes", async () => {
    // --- SETUP ---
    const { collateral: A_collateral, totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(4, 18)), extraParams: { from: alice } })
    const { collateral: B_collateral, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(21, 17)), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);

    // --- TEST ---

    // check totalStakes before
    const totalStakes_Before = (await cdpManager.totalStakes()).toString()
    assert.equal(totalStakes_Before, A_collateral.add(B_collateral))

    // price drops to 1ETH:100EBTC, reducing Bob's ICR below MCR
    await priceFeed.setPrice(dec(3714, 13))

    // Confirm system is not in Recovery Mode
    assert.isFalse(await th.checkRecoveryMode(contracts));

    // Close Bob's Cdp
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from: alice});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from: bob});
    await cdpManager.liquidate(_bobCdpId, { from: owner });

    // check totalStakes after
    const totalStakes_After = (await cdpManager.totalStakes()).toString()
    assert.equal(totalStakes_After, A_collateral)
  })

  it("liquidate(): updates the snapshots of total stakes and total collateral", async () => {
    // --- SETUP ---
    const { collateral: A_collateral, totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(4, 18)), extraParams: { from: alice } })
    const { collateral: B_collateral, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(21, 17)), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);

    // --- TEST ---

    // check snapshots before 
    const totalStakesSnapshot_Before = (await cdpManager.totalStakesSnapshot()).toString()
    const totalCollateralSnapshot_Before = (await cdpManager.totalCollateralSnapshot()).toString()
    assert.equal(totalStakesSnapshot_Before, '0')
    assert.equal(totalCollateralSnapshot_Before, '0')

    // price drops to 1ETH:100EBTC, reducing Bob's ICR below MCR
    await priceFeed.setPrice(dec(3714, 13))

    // Confirm system is not in Recovery Mode
    assert.isFalse(await th.checkRecoveryMode(contracts));

    // close Bob's Cdp.  His ether*0.995 and EBTC should be added to the DefaultPool.
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from: alice});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from: bob});
    await cdpManager.liquidate(_bobCdpId, { from: owner });

    /* check snapshots after. Total stakes should be equal to the  remaining stake then the system: 
    10 ether, Alice's stake.
     
    Total collateral should be equal to Alice's collateral plus her pending ETH reward (Bob’s collaterale*0.995 ether), earned
    from the liquidation of Bob's Cdp */
    const totalStakesSnapshot_After = (await cdpManager.totalStakesSnapshot()).toString()
    const totalCollateralSnapshot_After = (await cdpManager.totalCollateralSnapshot()).toString()

    assert.equal(totalStakesSnapshot_After, A_collateral)
    assert.equal(totalCollateralSnapshot_After, A_collateral.add(th.applyLiquidationFee(toBN('0'))))
  })

  xit("liquidate(): updates the L_STETHColl and systemDebtRedistributionIndex reward-per-unit-staked totals", async () => {
    // --- SETUP ---
    const { collateral: A_collateral, totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(8, 18)), extraParams: { from: alice } })
    const { collateral: B_collateral, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(4, 18)), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    const { collateral: C_collateral, totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(111, 16)), extraParams: { from: carol } })
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    // --- TEST ---

    // price drops to 1ETH:100EBTC, reducing Carols's ICR below MCR
    let _newPrice = dec(3714, 13)
    await priceFeed.setPrice(_newPrice)

    // Confirm system is not in Recovery Mode
    assert.isFalse(await th.checkRecoveryMode(contracts));

    // close Carol's Cdp.  
    assert.isTrue(await sortedCdps.contains(_carolCdpId))
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from: carol});	
    await openCdp({ ICR: toBN(dec(111, 16)), extraParams: { from: owner } })
    await cdpManager.liquidate(_carolCdpId, { from: owner });
    assert.isFalse(await sortedCdps.contains(_carolCdpId))

    // Carol's ether*0.995 and EBTC should be added to the DefaultPool.
    const L_EBTCDebt_AfterCarolLiquidated = (await cdpManager.systemDebtRedistributionIndex())

    const L_EBTCDebt_expected_1 = C_totalDebt.sub(C_collateral.mul(toBN(_newPrice)).div(LICR)).mul(mv._1e18BN).div(await cdpManager.totalStakes());
    assert.isAtMost(th.getDifference(L_EBTCDebt_AfterCarolLiquidated, L_EBTCDebt_expected_1), 100)

    // Bob now withdraws EBTC, bringing his ICR to 1.11
    const { increasedTotalDebt: B_increasedTotalDebt } = await withdrawDebt({_cdpId: _bobCdpId, ICR: toBN(dec(111, 16)), extraParams: { from: bob } })
    let _bobTotalDebt = (await cdpManager.getSyncedDebtAndCollShares(_bobCdpId))[0]

    // Confirm system is not in Recovery Mode
    assert.isFalse(await th.checkRecoveryMode(contracts));

    // price drops to 1ETH:50EBTC, reducing Bob's ICR below MCR
    await priceFeed.setPrice(dec(2500, 13))
    const price = await priceFeed.getPrice()
    assert.isTrue(await th.checkRecoveryMode(contracts));

    // close Bob's Cdp 
    assert.isTrue(await sortedCdps.contains(_bobCdpId))
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from: alice});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from: bob});
    await cdpManager.liquidate(_bobCdpId, { from: owner });
    assert.isFalse(await sortedCdps.contains(_bobCdpId))

    /* Alice now has all the active stake. totalStakes in the system is now 10 ether.
   
   Bob's pending collateral reward and debt reward are applied to his Cdp
   before his liquidation.
   His total collateral*0.995 and debt are then added to the DefaultPool. 
   
   The system rewards-per-unit-staked should now be:
   
   systemDebtRedistributionIndex = (180 / 20) + (890 / 10) = 98 EBTC */
    const L_EBTCDebt_AfterBobLiquidated = (await cdpManager.systemDebtRedistributionIndex()).div(mv._1e18BN)

    const L_EBTCDebt_expected_2 = L_EBTCDebt_expected_1.add((_bobTotalDebt.sub(B_collateral.mul(price).div(LICR))).mul(mv._1e18BN).div(await cdpManager.totalStakes()))
    assert.isAtMost(th.getDifference(L_EBTCDebt_AfterBobLiquidated, L_EBTCDebt_expected_2), 1000)
  })

  it("liquidate(): Liquidates undercollateralized cdp if there are two cdps in the system", async () => {
    await openCdp({ ICR: toBN(dec(200, 18)), extraParams: { from: bob, value: dec(100, 'ether') } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);

    // Alice creates a single cdp with 0.7 ETH and a debt of 70 EBTC, and provides 10 EBTC to SP
    const { collateral: A_collateral, totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);

    // Set ETH:USD price to 105
    await priceFeed.setPrice(dec(3900, 13))
    const price = await priceFeed.getPrice()

    assert.isFalse(await th.checkRecoveryMode(contracts))

    const alice_ICR = (await cdpManager.getCachedICR(_aliceCdpId, price)).toString()
    assert.equal(alice_ICR, '1050080775444264943')

    const activeCdpsCount_Before = await cdpManager.getActiveCdpsCount()

    assert.equal(activeCdpsCount_Before, 2)

    // Confirm system is not in Recovery Mode
    assert.isFalse(await th.checkRecoveryMode(contracts));

    // Liquidate the cdp
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from: alice});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from: bob});
    await cdpManager.liquidate(_aliceCdpId, { from: owner })

    // Check Alice's cdp is removed, and bob remains
    const activeCdpsCount_After = await cdpManager.getActiveCdpsCount()
    assert.equal(activeCdpsCount_After, 1)

    const alice_isInSortedList = await sortedCdps.contains(_aliceCdpId)
    assert.isFalse(alice_isInSortedList)

    const bob_isInSortedList = await sortedCdps.contains(_bobCdpId)
    assert.isTrue(bob_isInSortedList)
  })

  it("liquidate(): reverts if cdp is non-existent", async () => {
    await openCdp({ ICR: toBN(dec(4, 18)), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(21, 17)), extraParams: { from: bob } })

    assert.equal(await cdpManager.getCdpStatus(carol), 0) // check cdp non-existent

    assert.isFalse(await sortedCdps.contains(carol))

    // Confirm system is not in Recovery Mode
    assert.isFalse(await th.checkRecoveryMode(contracts));

    try {
      const txCarol = await cdpManager.liquidate(carol)

      assert.isFalse(txCarol.receipt.status)
    } catch (err) {
      console.log(err)
      console.log(err.message)
      assert.include(err.message, "revert")
      assert.include(err.message, "Cdp does not exist or is closed")
    }
  })

  it("liquidate(): reverts if cdp has been closed", async () => {
    await openCdp({ ICR: toBN(dec(8, 18)), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(4, 18)), extraParams: { from: bob } })
    await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: carol } })
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    assert.isTrue(await sortedCdps.contains(_carolCdpId))

    // price drops, Carol ICR falls below MCR
    await priceFeed.setPrice(dec(3714, 13))

    // Carol liquidated, and her cdp is closed
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from: alice});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from: carol});
    const txCarol_L1 = await cdpManager.liquidate(_carolCdpId, { from: owner })
    assert.isTrue(txCarol_L1.receipt.status)

    assert.isFalse(await sortedCdps.contains(_carolCdpId))

    assert.equal(await cdpManager.getCdpStatus(_carolCdpId), 3)  // check cdp closed by liquidation

    // Confirm system is not in Recovery Mode
    assert.isFalse(await th.checkRecoveryMode(contracts));

    try {
      await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from: bob});
      const txCarol_L2 = await cdpManager.liquidate(_carolCdpId, { from: owner })

      assert.isFalse(txCarol_L2.receipt.status)
    } catch (err) {
      assert.include(err.message, "revert")
      assert.include(err.message, "Cdp does not exist or is closed")
    }
  })

  it("liquidate(): does nothing if cdp has >= 110% ICR", async () => {
    await openCdp({ ICR: toBN(dec(3, 18)), extraParams: { from: whale } })
    let _whaleCdpId = await sortedCdps.cdpOfOwnerByIndex(whale, 0);
    await openCdp({ ICR: toBN(dec(3, 18)), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);

    const TCR_Before = (await th.getCachedTCR(contracts)).toString()
    const listSize_Before = (await sortedCdps.getSize()).toString()

    const price = await priceFeed.getPrice()

    // Check Bob's ICR > 110%
    const bob_ICR = await cdpManager.getCachedICR(_bobCdpId, price)
    assert.isTrue(bob_ICR.gte(mv._MCR))

    // Confirm system is not in Recovery Mode
    assert.isFalse(await th.checkRecoveryMode(contracts));

    // Attempt to liquidate bob
    await assertRevert(cdpManager.liquidate(_bobCdpId), "CdpManager: nothing to liquidate")

    // Check bob active, check whale active
    assert.isTrue((await sortedCdps.contains(_bobCdpId)))
    assert.isTrue((await sortedCdps.contains(_whaleCdpId)))

    const TCR_After = (await th.getCachedTCR(contracts)).toString()
    const listSize_After = (await sortedCdps.getSize()).toString()

    assert.equal(TCR_Before, TCR_After)
    assert.equal(listSize_Before, listSize_After)
  })

  it("liquidate(): Given the same price and no other cdp changes, complete Pool offsets restore the TCR to its value prior to the defaulters opening cdps", async () => {
    // Whale provides EBTC to SP
    const spDeposit = toBN(dec(100, 19))
    await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("51200")});
    await openCdp({ ICR: toBN(dec(4, 18)), extraEBTCAmount: spDeposit, extraParams: { from: whale } })

    await openCdp({ ICR: toBN(dec(10, 18)), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(70, 18)), extraParams: { from: bob } })
    await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: carol } })
    await openCdp({ ICR: toBN(dec(200, 18)), extraParams: { from: dennis } })

    const TCR_Before = (await th.getCachedTCR(contracts)).toString()

    await openCdp({ ICR: toBN(dec(202, 16)), extraParams: { from: defaulter_1 } })
    await openCdp({ ICR: toBN(dec(190, 16)), extraParams: { from: defaulter_2 } })
    await openCdp({ ICR: toBN(dec(196, 16)), extraParams: { from: defaulter_3 } })
    await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: defaulter_4 } })
    let _defaulter1CdpId = await sortedCdps.cdpOfOwnerByIndex(defaulter_1, 0);
    let _defaulter2CdpId = await sortedCdps.cdpOfOwnerByIndex(defaulter_2, 0);
    let _defaulter3CdpId = await sortedCdps.cdpOfOwnerByIndex(defaulter_3, 0);
    let _defaulter4CdpId = await sortedCdps.cdpOfOwnerByIndex(defaulter_4, 0);

    assert.isTrue((await sortedCdps.contains(_defaulter1CdpId)))
    assert.isTrue((await sortedCdps.contains(_defaulter2CdpId)))
    assert.isTrue((await sortedCdps.contains(_defaulter3CdpId)))
    assert.isTrue((await sortedCdps.contains(_defaulter4CdpId)))

    // Price drop
    await priceFeed.setPrice(dec(3714, 13))

    // Confirm system is not in Recovery Mode
    assert.isFalse(await th.checkRecoveryMode(contracts));

    // All defaulters liquidated
    await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from: whale});	
    await debtToken.transfer(owner, (await debtToken.balanceOf(defaulter_1)), {from: defaulter_1});
    await cdpManager.liquidate(_defaulter1CdpId)
    assert.isFalse((await sortedCdps.contains(_defaulter1CdpId)))

    await debtToken.transfer(owner, (await debtToken.balanceOf(defaulter_2)), {from: defaulter_2});
    await cdpManager.liquidate(_defaulter2CdpId)
    assert.isFalse((await sortedCdps.contains(_defaulter2CdpId)))

    await debtToken.transfer(owner, (await debtToken.balanceOf(defaulter_3)), {from: defaulter_3});
    await cdpManager.liquidate(_defaulter3CdpId)
    assert.isFalse((await sortedCdps.contains(_defaulter3CdpId)))

    await debtToken.transfer(owner, (await debtToken.balanceOf(defaulter_4)), {from: defaulter_4});
    await cdpManager.liquidate(_defaulter4CdpId)
    assert.isFalse((await sortedCdps.contains(_defaulter4CdpId)))

    // Price bounces back
    await priceFeed.setPrice(dec(7428, 13))

    const TCR_After = (await th.getCachedTCR(contracts)).toString()
    assert.isTrue(toBN(TCR_Before).gt(toBN(TCR_After)))
  })


  it("liquidate(): Pool offsets increase the TCR", async () => {
    // Whale provides EBTC to SP
    const spDeposit = toBN(dec(100, 19))
    await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("51200")});
    await openCdp({ ICR: toBN(dec(4, 18)), extraEBTCAmount: spDeposit, extraParams: { from: whale } })

    await openCdp({ ICR: toBN(dec(10, 18)), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(70, 18)), extraParams: { from: bob } })
    await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: carol } })
    await openCdp({ ICR: toBN(dec(200, 18)), extraParams: { from: dennis } })

    await openCdp({ ICR: toBN(dec(202, 16)), extraParams: { from: defaulter_1 } })
    await openCdp({ ICR: toBN(dec(190, 16)), extraParams: { from: defaulter_2 } })
    await openCdp({ ICR: toBN(dec(196, 16)), extraParams: { from: defaulter_3 } })
    await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: defaulter_4 } })
    let _defaulter1CdpId = await sortedCdps.cdpOfOwnerByIndex(defaulter_1, 0);
    let _defaulter2CdpId = await sortedCdps.cdpOfOwnerByIndex(defaulter_2, 0);
    let _defaulter3CdpId = await sortedCdps.cdpOfOwnerByIndex(defaulter_3, 0);
    let _defaulter4CdpId = await sortedCdps.cdpOfOwnerByIndex(defaulter_4, 0);

    assert.isTrue((await sortedCdps.contains(_defaulter1CdpId)))
    assert.isTrue((await sortedCdps.contains(_defaulter2CdpId)))
    assert.isTrue((await sortedCdps.contains(_defaulter3CdpId)))
    assert.isTrue((await sortedCdps.contains(_defaulter4CdpId)))

    await priceFeed.setPrice(dec(3714, 13))

    const TCR_1 = await th.getCachedTCR(contracts)

    // Confirm system is not in Recovery Mode
    assert.isFalse(await th.checkRecoveryMode(contracts));

    // Check TCR improves with each liquidation that is offset with Pool
    await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from: whale});
    await debtToken.transfer(owner, (await debtToken.balanceOf(defaulter_1)), {from: defaulter_1});
    await cdpManager.liquidate(_defaulter1CdpId)
    assert.isFalse((await sortedCdps.contains(_defaulter1CdpId)))
    const TCR_2 = await th.getCachedTCR(contracts)
    assert.isTrue(TCR_2.gte(TCR_1))

    await debtToken.transfer(owner, (await debtToken.balanceOf(defaulter_2)), {from: defaulter_2});
    await cdpManager.liquidate(_defaulter2CdpId)
    assert.isFalse((await sortedCdps.contains(_defaulter2CdpId)))
    const TCR_3 = await th.getCachedTCR(contracts)
    assert.isTrue(TCR_3.gte(TCR_2))

    await debtToken.transfer(owner, (await debtToken.balanceOf(defaulter_3)), {from: defaulter_3});
    await cdpManager.liquidate(_defaulter3CdpId)
    assert.isFalse((await sortedCdps.contains(_defaulter3CdpId)))
    const TCR_4 = await th.getCachedTCR(contracts)
    assert.isTrue(TCR_4.gte(TCR_3))

    await debtToken.transfer(owner, (await debtToken.balanceOf(defaulter_4)), {from: defaulter_4});
    await cdpManager.liquidate(_defaulter4CdpId)
    assert.isFalse((await sortedCdps.contains(_defaulter4CdpId)))
    const TCR_5 = await th.getCachedTCR(contracts)
    assert.isTrue(TCR_5.gte(TCR_4))
  })

  it("liquidate(): a pure redistribution reduces the TCR only as a result of compensation", async () => {
    await openCdp({ ICR: toBN(dec(4, 18)), extraParams: { from: whale } })

    await openCdp({ ICR: toBN(dec(10, 18)), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(70, 18)), extraParams: { from: bob } })
    await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: carol } })
    await openCdp({ ICR: toBN(dec(200, 18)), extraParams: { from: dennis } })

    const { collateral: D1_coll, totalDebt: D1_debt } = await openCdp({ ICR: toBN(dec(202, 16)), extraParams: { from: defaulter_1 } })
    const { collateral: D2_coll, totalDebt: D2_debt } = await openCdp({ ICR: toBN(dec(190, 16)), extraParams: { from: defaulter_2 } })
    const { collateral: D3_coll, totalDebt: D3_debt } = await openCdp({ ICR: toBN(dec(196, 16)), extraParams: { from: defaulter_3 } })
    const { collateral: D4_coll, totalDebt: D4_debt } = await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: defaulter_4 } })
    let _defaulter1CdpId = await sortedCdps.cdpOfOwnerByIndex(defaulter_1, 0);
    let _defaulter2CdpId = await sortedCdps.cdpOfOwnerByIndex(defaulter_2, 0);
    let _defaulter3CdpId = await sortedCdps.cdpOfOwnerByIndex(defaulter_3, 0);
    let _defaulter4CdpId = await sortedCdps.cdpOfOwnerByIndex(defaulter_4, 0);

    assert.isTrue((await sortedCdps.contains(_defaulter1CdpId)))
    assert.isTrue((await sortedCdps.contains(_defaulter2CdpId)))
    assert.isTrue((await sortedCdps.contains(_defaulter3CdpId)))
    assert.isTrue((await sortedCdps.contains(_defaulter4CdpId)))

    await priceFeed.setPrice(dec(3714, 13))
    const price = await priceFeed.getPrice()

    const TCR_0 = await th.getCachedTCR(contracts)

    const entireSystemCollBefore = await cdpManager.getSystemCollShares()
    const entireSystemDebtBefore = await cdpManager.getSystemDebt()

    const expectedTCR_0 = entireSystemCollBefore.mul(price).div(entireSystemDebtBefore)

    assert.isTrue(expectedTCR_0.eq(TCR_0))

    // Confirm system is not in Recovery Mode
    assert.isFalse(await th.checkRecoveryMode(contracts));

    // Check TCR does not decrease with each liquidation 
    await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from: whale});
    await debtToken.transfer(owner, (await debtToken.balanceOf(defaulter_1)), {from: defaulter_1});
    const liquidationTx_1 = await cdpManager.liquidate(_defaulter1CdpId)
    const [liquidatedDebt_1, liquidatedColl_1, gasComp_1] = th.getEmittedLiquidationValues(liquidationTx_1)
    assert.isFalse((await sortedCdps.contains(_defaulter1CdpId)))
    const TCR_1 = await th.getCachedTCR(contracts)

    // Expect only change to TCR to be due to the issued gas compensation
    const expectedTCR_1 = (entireSystemCollBefore
      .sub(D1_coll))
      .mul(price)
      .div(entireSystemDebtBefore.sub(D1_coll.mul(price).div(LICR)))

    assert.isTrue(expectedTCR_1.eq(TCR_1))

    await debtToken.transfer(owner, (await debtToken.balanceOf(defaulter_2)), {from: defaulter_2});
    const liquidationTx_2 = await cdpManager.liquidate(_defaulter2CdpId)
    const [liquidatedDebt_2, liquidatedColl_2, gasComp_2] = th.getEmittedLiquidationValues(liquidationTx_2)
    assert.isFalse((await sortedCdps.contains(_defaulter2CdpId)))

    const TCR_2 = await th.getCachedTCR(contracts)

    const expectedTCR_2 = (entireSystemCollBefore
      .sub(D1_coll)
      .sub(D2_coll))
      .mul(price)
      .div(entireSystemDebtBefore.sub(D1_coll.mul(price).div(LICR)).sub(D2_coll.mul(price).div(LICR)))

    assert.isTrue(expectedTCR_2.eq(TCR_2))

    await debtToken.transfer(owner, (await debtToken.balanceOf(defaulter_3)), {from: defaulter_3});
    const liquidationTx_3 = await cdpManager.liquidate(_defaulter3CdpId)
    const [liquidatedDebt_3, liquidatedColl_3, gasComp_3] = th.getEmittedLiquidationValues(liquidationTx_3)
    assert.isFalse((await sortedCdps.contains(_defaulter3CdpId)))

    const TCR_3 = await th.getCachedTCR(contracts)

    const expectedTCR_3 = (entireSystemCollBefore
      .sub(D1_coll)
      .sub(D2_coll)
      .sub(D3_coll))
      .mul(price)
      .div(entireSystemDebtBefore.sub(D1_coll.mul(price).div(LICR)).sub(D2_coll.mul(price).div(LICR)).sub(D3_coll.mul(price).div(LICR)))

    assert.isTrue(expectedTCR_3.eq(TCR_3))

    await debtToken.transfer(owner, (await debtToken.balanceOf(defaulter_4)), {from: defaulter_4});
    const liquidationTx_4 = await cdpManager.liquidate(_defaulter4CdpId)
    const [liquidatedDebt_4, liquidatedColl_4, gasComp_4] = th.getEmittedLiquidationValues(liquidationTx_4)
    assert.isFalse((await sortedCdps.contains(_defaulter4CdpId)))

    const TCR_4 = await th.getCachedTCR(contracts)

    const expectedTCR_4 = (entireSystemCollBefore
      .sub(D1_coll)
      .sub(D2_coll)
      .sub(D3_coll)
      .sub(D4_coll))
      .mul(price)
      .div(entireSystemDebtBefore.sub(D1_coll.mul(price).div(LICR)).sub(D2_coll.mul(price).div(LICR)).sub(D3_coll.mul(price).div(LICR)).sub(D4_coll.mul(price).div(LICR)))

    assert.isTrue(expectedTCR_4.eq(TCR_4))
  })

  it("liquidate(): does not affect the SP deposit or ETH gain when called on an SP depositor's address that has no cdp", async () => {
    await openCdp({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
    const spDeposit = toBN(dec(1, 21))	
	
    await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("39999")});
    await openCdp({ ICR: toBN(dec(3, 18)), extraEBTCAmount: spDeposit, extraParams: { from: bob } })
    const { C_totalDebt, C_collateral } = await openCdp({ ICR: toBN(dec(218, 16)), extraEBTCAmount: toBN(dec(100, 18)), extraParams: { from: carol } })
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    // Bob sends tokens to Dennis, who has no cdp
    await ebtcToken.transfer(dennis, spDeposit, { from: bob })

    // Carol gets liquidated
    await priceFeed.setPrice(dec(3714, 13))
    await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from: whale});
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from: carol});
    await _signer.sendTransaction({ to: owner, value: ethers.utils.parseEther("10681")});
    await openCdp({ ICR: toBN(dec(218, 16)), extraEBTCAmount: toBN(dec(100, 18)), extraParams: { from: owner } })
    const liquidationTX_C = await cdpManager.liquidate(_carolCdpId, { from: owner })
    const [liquidatedDebt, liquidatedColl, gasComp] = th.getEmittedLiquidationValues(liquidationTX_C)

    assert.isFalse(await sortedCdps.contains(_carolCdpId))

    // Confirm system is not in Recovery Mode
    assert.isFalse(await th.checkRecoveryMode(contracts));

    // Attempt to liquidate Dennis
    try {
      const txDennis = await cdpManager.liquidate(dennis, { from: owner })
      assert.isFalse(txDennis.receipt.status)
    } catch (err) {
      console.log(err)
      console.log(err.message)
      assert.include(err.message, "revert")
      assert.include(err.message, "Cdp does not exist or is closed")
    }
  })

  it("liquidate(): does not liquidate a SP depositor's cdp with ICR > 110%, and does not affect their SP deposit or ETH gain", async () => {
    await openCdp({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
    const spDeposit = toBN(dec(1, 21))
	
    await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("51200")});
    await _signer.sendTransaction({ to: carol, value: ethers.utils.parseEther("10681")});
    await openCdp({ ICR: toBN(dec(3, 18)), extraEBTCAmount: spDeposit, extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    await openCdp({ ICR: toBN(dec(218, 16)), extraEBTCAmount: toBN(dec(100, 18)), extraParams: { from: carol } })
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    // Carol gets liquidated
    await priceFeed.setPrice(dec(3714, 13))
    await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from: whale});
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from: carol});
    await _signer.sendTransaction({ to: owner, value: ethers.utils.parseEther("10681")});
    await openCdp({ ICR: toBN(dec(218, 16)), extraEBTCAmount: toBN(dec(100, 18)), extraParams: { from: owner } })
    const liquidationTX_C = await cdpManager.liquidate(_carolCdpId, {from: owner})
    const [liquidatedDebt, liquidatedColl, gasComp] = th.getEmittedLiquidationValues(liquidationTX_C)
    assert.isFalse(await sortedCdps.contains(_carolCdpId))

    // price bounces back - Bob's cdp is >110% ICR again
    await priceFeed.setPrice(dec(7428, 13))
    const price = await priceFeed.getPrice()
    assert.isTrue((await cdpManager.getCachedICR(_bobCdpId, price)).gt(mv._MCR))

    // Confirm system is not in Recovery Mode
    assert.isFalse(await th.checkRecoveryMode(contracts));

    // Attempt to liquidate Bob
    await assertRevert(cdpManager.liquidate(_bobCdpId), "CdpManager: ICR is not below liquidation threshold in current mode")

    // Confirm Bob's cdp is still active
    assert.isTrue(await sortedCdps.contains(_bobCdpId))
  })

  it("liquidate(): liquidates a SP depositor's cdp with ICR < 110%, and the liquidation correctly impacts their SP deposit and ETH gain", async () => {
    const A_spDeposit = toBN(dec(1, 21))
    const B_spDeposit = toBN(dec(1, 21))
    await openCdp({ ICR: toBN(dec(20, 18)), extraParams: { from: whale } })
    await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("120681")});
    await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("50681")});
    await _signer.sendTransaction({ to: carol, value: ethers.utils.parseEther("10681")});
    await openCdp({ ICR: toBN(dec(8, 18)), extraEBTCAmount: A_spDeposit, extraParams: { from: alice } })
    const { collateral: B_collateral, totalDebt: B_debt } = await openCdp({ ICR: toBN(dec(218, 16)), extraEBTCAmount: B_spDeposit, extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    const { collateral: C_collateral, totalDebt: C_debt } = await openCdp({ ICR: toBN(dec(210, 16)), extraEBTCAmount: toBN(dec(100, 18)), extraParams: { from: carol } })
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    await openCdp({ ICR: toBN(dec(210, 16)), extraEBTCAmount: toBN(dec(100, 18)), extraParams: { from: owner } })
    // Carol gets liquidated
    await priceFeed.setPrice(dec(3714, 13))
    await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from: whale});
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from: carol});
    await cdpManager.liquidate(_carolCdpId, { from: owner })

    // Confirm system is not in Recovery Mode
    assert.isFalse(await th.checkRecoveryMode(contracts));

    // Liquidate Bob
    await _signer.sendTransaction({ to: owner, value: ethers.utils.parseEther("220000")});
    await openCdp({ ICR: toBN(dec(218, 16)), extraEBTCAmount: B_spDeposit.add(toBN(dec(500, 18))), extraParams: { from: owner } })
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from: bob});
    await cdpManager.liquidate(_bobCdpId, { from: owner })

    // Confirm Bob's cdp has been closed
    assert.isFalse(await sortedCdps.contains(_bobCdpId))
    const bob_Cdp_Status = ((await cdpManager.Cdps(_bobCdpId))[4]).toString()
    assert.equal(bob_Cdp_Status, 3) // check closed by liquidation

    /* Alice's EBTC Loss = (300 / 400) * 200 = 150 EBTC
       Alice's ETH gain = (300 / 400) * 2*0.995 = 1.4925 ETH

       Bob's EBTCLoss = (100 / 400) * 200 = 50 EBTC
       Bob's ETH gain = (100 / 400) * 2*0.995 = 0.4975 ETH

     Check Bob' SP deposit has been reduced to 50 EBTC, and his ETH gain has increased to 1.5 ETH. */
  })

  it("liquidate(): does not alter the liquidated user's token balance", async () => {
    await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("10701")});
    await openCdp({ ICR: toBN(dec(10, 18)), extraEBTCAmount: toBN(dec(100, 18)), extraParams: { from: whale } })
    const { ebtcAmount: A_ebtcAmount } = await openCdp({ ICR: toBN(dec(2, 18)), extraEBTCAmount: toBN(dec(30, 18)), extraParams: { from: alice } })
    const { ebtcAmount: B_ebtcAmount } = await openCdp({ ICR: toBN(dec(2, 18)), extraEBTCAmount: toBN(dec(20, 18)), extraParams: { from: bob } })
    const { ebtcAmount: C_ebtcAmount } = await openCdp({ ICR: toBN(dec(2, 18)), extraEBTCAmount: toBN(dec(10, 18)), extraParams: { from: carol } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    await priceFeed.setPrice(dec(4000, 13))

    // Check sortedList size
    assert.equal((await sortedCdps.getSize()).toString(), '4')


    // Liquidate A, B and C

    await cdpManager.liquidate(_aliceCdpId, {from: whale})
    const activeEBTCDebt_A = await activePool.getSystemDebt()

    await cdpManager.liquidate(_bobCdpId, {from: whale})
    const activeEBTCDebt_B = await activePool.getSystemDebt()

    await cdpManager.liquidate(_carolCdpId, {from: whale})

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

  it("liquidate(): liquidates based on entire/collateral debt (including pending rewards), not raw collateral/debt", async () => {
    await openCdp({ ICR: toBN(dec(8, 18)), extraEBTCAmount: toBN(dec(100, 18)), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(221, 16)), extraEBTCAmount: toBN(dec(100, 18)), extraParams: { from: bob } })
    await openCdp({ ICR: toBN(dec(2, 18)), extraEBTCAmount: toBN(dec(100, 18)), extraParams: { from: carol } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    // Defaulter opens with 60 EBTC, 0.6 ETH
    await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: defaulter_1 } })
    let _defaulter1CdpId = await sortedCdps.cdpOfOwnerByIndex(defaulter_1, 0);

    // Price drops
    await priceFeed.setPrice(dec(3714, 13))
    const price = await priceFeed.getPrice()

    const alice_ICR_Before = await cdpManager.getCachedICR(_aliceCdpId, price)
    const bob_ICR_Before = await cdpManager.getCachedICR(_bobCdpId, price)
    const carol_ICR_Before = await cdpManager.getCachedICR(_carolCdpId, price)

    /* Before liquidation: 
    Alice ICR: = (2 * 100 / 50) = 400%
    Bob ICR: (1 * 100 / 90.5) = 110.5%
    Carol ICR: (1 * 100 / 100 ) =  100%

    Therefore Alice and Bob above the MCR, Carol is below */
    assert.isTrue(alice_ICR_Before.gte(mv._MCR))
    assert.isTrue(bob_ICR_Before.gte(mv._MCR))
    assert.isTrue(carol_ICR_Before.lte(mv._MCR))

    // Confirm system is not in Recovery Mode
    assert.isFalse(await th.checkRecoveryMode(contracts));

    /* Liquidate defaulter. 30 EBTC and 0.3 ETH is distributed between A, B and C.

    A receives (30 * 2/4) = 15 EBTC, and (0.3*2/4) = 0.15 ETH
    B receives (30 * 1/4) = 7.5 EBTC, and (0.3*1/4) = 0.075 ETH
    C receives (30 * 1/4) = 7.5 EBTC, and (0.3*1/4) = 0.075 ETH
    */
    await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from: alice});
    await debtToken.transfer(owner, (await debtToken.balanceOf(defaulter_1)), {from: defaulter_1});
    await cdpManager.liquidate(_defaulter1CdpId)

    const alice_ICR_After = await cdpManager.getCachedICR(_aliceCdpId, price)
    const bob_ICR_After = await cdpManager.getCachedICR(_bobCdpId, price)
    const carol_ICR_After = await cdpManager.getCachedICR(_carolCdpId, price)

    /* After liquidation: 

    Alice ICR: (10.15 * 100 / 60) = 183.33%
    Bob ICR:(1.075 * 100 / 98) =  109.69%
    Carol ICR: (1.075 *100 /  107.5 ) = 100.0%

    Check Alice is above MCR, Bob below, Carol below. */


    assert.isTrue(alice_ICR_After.gte(mv._MCR))
    assert.isTrue(bob_ICR_After.gte(mv._MCR))
    assert.isTrue(carol_ICR_After.lte(mv._MCR))

    /* Though Bob's true ICR (including pending rewards) is below the MCR, 
    check that Bob's raw coll and debt has not changed, and that his "raw" ICR is above the MCR */
    const bob_Coll = (await cdpManager.Cdps(_bobCdpId))[1]
    const bob_Debt = (await cdpManager.Cdps(_bobCdpId))[0]

    const bob_rawICR = bob_Coll.mul(toBN(dec(100, 18))).div(bob_Debt)
    assert.isTrue(bob_rawICR.gte(mv._MCR))

    // Whale enters system, pulling it into Normal Mode
    await openCdp({ ICR: toBN(dec(20, 18)), extraParams: { from: whale } })
    assert.isFalse(await th.checkRecoveryMode(contracts))

    // Liquidate Alice, Bob, Carol
    await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from: bob});
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from: carol});
    await assertRevert(cdpManager.liquidate(_aliceCdpId), "CdpManager: ICR is not below liquidation threshold in current mode")
    await assertRevert(cdpManager.liquidate(_bobCdpId), "CdpManager: ICR is not below liquidation threshold in current mode")
    await cdpManager.liquidate(_carolCdpId, {from: owner})

    /* Check Alice stays active, Carol gets liquidated, and Bob gets liquidated 
   (because his pending rewards bring his ICR < MCR) */
    assert.isTrue(await sortedCdps.contains(_aliceCdpId))
    assert.isTrue(await sortedCdps.contains(_bobCdpId))
    assert.isFalse(await sortedCdps.contains(_carolCdpId))

    // Check cdp statuses - A active (1),  B and C liquidated (3)
    assert.equal((await cdpManager.Cdps(_aliceCdpId))[4].toString(), '1')
    assert.equal((await cdpManager.Cdps(_bobCdpId))[4].toString(), '1')
    assert.equal((await cdpManager.Cdps(_carolCdpId))[4].toString(), '3')
  })

  it("liquidate(): when SP > 0, triggers LQTY reward event - increases the sum G", async () => {
    await openCdp({ ICR: toBN(dec(100, 18)), extraParams: { from: whale } })

    // A, B, C open cdps 
    await openCdp({ ICR: toBN(dec(4, 18)), extraParams: { from: A } })
    await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: B } })
    await openCdp({ ICR: toBN(dec(3, 18)), extraParams: { from: C } })

    await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: defaulter_1 } })
    let _defaulter1CdpId = await sortedCdps.cdpOfOwnerByIndex(defaulter_1, 0);

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Price drops to 1ETH:100EBTC, reducing defaulters to below MCR
    await priceFeed.setPrice(dec(3714, 13));
    const price = await priceFeed.getPrice()
    assert.isFalse(await th.checkRecoveryMode(contracts))

    // Liquidate cdp
    await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from: whale});
    await debtToken.transfer(owner, (await debtToken.balanceOf(defaulter_1)), {from: defaulter_1});
    await cdpManager.liquidate(_defaulter1CdpId)
    assert.isFalse(await sortedCdps.contains(_defaulter1CdpId))
  })

  it("liquidate(): when SP is empty, doesn't update G", async () => {
    await openCdp({ ICR: toBN(dec(100, 18)), extraParams: { from: whale } })

    // A, B, C open cdps 
    await openCdp({ ICR: toBN(dec(4, 18)), extraParams: { from: A } })
    await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: B } })
    await openCdp({ ICR: toBN(dec(3, 18)), extraParams: { from: C } })

    await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: defaulter_1 } })
    let _defaulter1CdpId = await sortedCdps.cdpOfOwnerByIndex(defaulter_1, 0);

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Price drops to 1ETH:100EBTC, reducing defaulters to below MCR
    await priceFeed.setPrice(dec(3714, 13));
    const price = await priceFeed.getPrice()
    assert.isFalse(await th.checkRecoveryMode(contracts))

    // liquidate cdp
    await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from: whale});
    await debtToken.transfer(owner, (await debtToken.balanceOf(defaulter_1)), {from: defaulter_1});
    await cdpManager.liquidate(_defaulter1CdpId)
    assert.isFalse(await sortedCdps.contains(_defaulter1CdpId))
  })

  // --- liquidateCdps() ---

  it('liquidateCdps(): liquidates a Cdp that a) was skipped in a previous liquidation and b) has pending rewards', async () => {
    // A, B, C, D, E open cdps
    await openCdp({ ICR: toBN(dec(333, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: D } })
    await openCdp({ ICR: toBN(dec(333, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: E } })
    await openCdp({ ICR: toBN(dec(120, 16)), extraParams: { from: A } })
    await openCdp({ ICR: toBN(dec(133, 16)), extraParams: { from: B } })
    await openCdp({ ICR: toBN(dec(3, 18)), extraParams: { from: C } })
    let _aCdpId = await sortedCdps.cdpOfOwnerByIndex(A, 0);
    let _bCdpId = await sortedCdps.cdpOfOwnerByIndex(B, 0);
    let _cCdpId = await sortedCdps.cdpOfOwnerByIndex(C, 0);
    let _dCdpId = await sortedCdps.cdpOfOwnerByIndex(D, 0);
    let _eCdpId = await sortedCdps.cdpOfOwnerByIndex(E, 0);

    // Price drops
    await priceFeed.setPrice(dec(6000, 13))
    
    // Confirm system is not in Recovery Mode
    assert.isFalse(await th.checkRecoveryMode(contracts))

    // A gets liquidated, creates pending rewards for all
    let _spAmt = dec(10, 15)
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(A)).toString()).sub(toBN(_spAmt)), {from: A});
    await openCdp({ ICR: toBN(dec(170, 16)), extraParams: { from: owner } })
    let _ownerCdpId = await sortedCdps.cdpOfOwnerByIndex(owner, 0);
    const liqTxA = await cdpManager.liquidate(_aCdpId, { from: owner })
    assert.isTrue(liqTxA.receipt.status)
    assert.isFalse(await sortedCdps.contains(_aCdpId))

    // Price drops
    await priceFeed.setPrice(dec(2600, 13))
    price = await priceFeed.getPrice()
    // Confirm system is now in Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Confirm C has ICR > TCR
    await borrowerOperations.addColl(_cCdpId, _cCdpId, _cCdpId, dec(6, 'ether'), { from: C })
    await borrowerOperations.addColl(_dCdpId, _dCdpId, _dCdpId, dec(6, 'ether'), { from: D })
    const TCR = await cdpManager.getCachedTCR(price)
    const ICR_C = await cdpManager.getCachedICR(_cCdpId, price)
  
    assert.isTrue(ICR_C.gt(TCR))

    // Attempt to liquidate B and C, which skips C in the liquidation since it is immune
    let _repayAmt = dec(1, 15);
    await debtToken.transfer(owner, (await debtToken.balanceOf(B)), {from: B});
    await debtToken.transfer(owner, (await debtToken.balanceOf(C)), {from: C});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(D)).toString()).sub(toBN(_repayAmt)), {from: D});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(E)).toString()).sub(toBN(_repayAmt)), {from: E});
	
    const liqTxBC = await th.liquidateCdps(2, price, contracts, {extraParams: {from: owner}})
    assert.isTrue(liqTxBC.receipt.status)
    assert.isFalse(await sortedCdps.contains(_bCdpId))
    assert.isFalse(await sortedCdps.contains(_ownerCdpId))
    assert.isTrue(await sortedCdps.contains(_cCdpId))
    assert.isTrue(await sortedCdps.contains(_dCdpId))
    assert.isTrue(await sortedCdps.contains(_eCdpId))

    // // All remaining cdps D and E repay a little debt, applying their pending rewards
    assert.isTrue((await sortedCdps.getSize()).eq(toBN('3')))
    await borrowerOperations.repayDebt(_dCdpId, _repayAmt, _dCdpId, _dCdpId, {from: D})
    await borrowerOperations.repayDebt(_eCdpId, _repayAmt, _eCdpId, _eCdpId, {from: E})

    // Check D & E pending rewards already applied
    assert.isTrue(await cdpManager.hasPendingRedistributedDebt(_cCdpId))
    assert.isFalse(await cdpManager.hasPendingRedistributedDebt(_dCdpId))
    assert.isFalse(await cdpManager.hasPendingRedistributedDebt(_eCdpId))

    // Check C's pending coll and debt rewards are <= the coll and debt in the DefaultPool
    const pendingEBTCDebt_C = (await cdpManager.getPendingRedistributedDebt(_cCdpId))

    // Confirm system is still in Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    await priceFeed.setPrice(dec(2500, 13))
    await borrowerOperations.addColl(_eCdpId, _eCdpId, _eCdpId, dec(10, 'ether'), { from: E })	  
	  	  
    // trigger cooldown and pass the liq wait
    await th.syncGlobalStateAndGracePeriod(contracts, ethers.provider);

    // Try to liquidate C again. 
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(D)).toString()), {from: D});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(E)).toString()), {from: E});
    const liqTx2 = await th.liquidateCdps(2, dec(2500, 13), contracts, {extraParams: {from: owner}})
    assert.isTrue(liqTx2.receipt.status)
    assert.isTrue(await sortedCdps.contains(_cCdpId))
    assert.isFalse(await sortedCdps.contains(_dCdpId))
    assert.isFalse(await sortedCdps.contains(_eCdpId))
    assert.isTrue((await sortedCdps.getSize()).eq(toBN('1')))
  })

  it('liquidateCdps(): closes every Cdp with ICR < MCR, when n > number of undercollateralized cdps', async () => {
    // --- SETUP ---
    await openCdp({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
    let _whaleCdpId = await sortedCdps.cdpOfOwnerByIndex(whale, 0);

    // create 5 Cdps with varying ICRs
    await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(190, 16)), extraParams: { from: bob } })
    await openCdp({ ICR: toBN(dec(210, 16)), extraParams: { from: carol } })
    await openCdp({ ICR: toBN(dec(195, 16)), extraParams: { from: erin } })
    await openCdp({ ICR: toBN(dec(120, 16)), extraParams: { from: flyn } })

    // G,H, I open high-ICR cdps
    await openCdp({ ICR: toBN(dec(100, 18)), extraParams: { from: graham } })
    await openCdp({ ICR: toBN(dec(90, 18)), extraParams: { from: harriet } })
    await openCdp({ ICR: toBN(dec(80, 18)), extraParams: { from: ida } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _erinCdpId = await sortedCdps.cdpOfOwnerByIndex(erin, 0);
    let _flynCdpId = await sortedCdps.cdpOfOwnerByIndex(flyn, 0);
    let _grahamCdpId = await sortedCdps.cdpOfOwnerByIndex(graham, 0);
    let _harrietCdpId = await sortedCdps.cdpOfOwnerByIndex(harriet, 0);
    let _idaCdpId = await sortedCdps.cdpOfOwnerByIndex(ida, 0);

    // --- TEST ---

    // Price drops to 1ETH:100EBTC, reducing Bob and Carol's ICR below MCR
    await priceFeed.setPrice(dec(3714, 13));
    const price = await priceFeed.getPrice()

    // Confirm system is not in Recovery Mode
    assert.isFalse(await th.checkRecoveryMode(contracts));

    // Confirm cdps A-E are ICR < 110%
    assert.isTrue((await cdpManager.getCachedICR(_aliceCdpId, price)).lte(mv._MCR))
    assert.isTrue((await cdpManager.getCachedICR(_bobCdpId, price)).lte(mv._MCR))
    assert.isTrue((await cdpManager.getCachedICR(_carolCdpId, price)).lte(mv._MCR))
    assert.isTrue((await cdpManager.getCachedICR(_erinCdpId, price)).lte(mv._MCR))
    assert.isTrue((await cdpManager.getCachedICR(_flynCdpId, price)).lte(mv._MCR))

    // Confirm cdps G, H, I are ICR > 110%
    assert.isTrue((await cdpManager.getCachedICR(graham, price)).gte(mv._MCR))
    assert.isTrue((await cdpManager.getCachedICR(harriet, price)).gte(mv._MCR))
    assert.isTrue((await cdpManager.getCachedICR(ida, price)).gte(mv._MCR))

    // Confirm Whale is ICR > 110% 
    assert.isTrue((await cdpManager.getCachedICR(_whaleCdpId, price)).gte(mv._MCR))

    // Liquidate 5 cdps
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(flyn)).toString()), {from: flyn});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(erin)).toString()), {from: erin});		
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});		
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(carol)).toString()), {from: carol});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(whale)).toString()), {from: whale});
    await th.liquidateCdps(5, price, contracts, {extraParams: {from: owner}});

    // Confirm cdps A-E have been removed from the system
    assert.isFalse(await sortedCdps.contains(_aliceCdpId))
    assert.isFalse(await sortedCdps.contains(_bobCdpId))
    assert.isFalse(await sortedCdps.contains(_carolCdpId))
    assert.isFalse(await sortedCdps.contains(_erinCdpId))
    assert.isFalse(await sortedCdps.contains(_flynCdpId))

    // Check all cdps A-E are now closed by liquidation
    assert.equal((await cdpManager.Cdps(_aliceCdpId))[4].toString(), '3')
    assert.equal((await cdpManager.Cdps(_bobCdpId))[4].toString(), '3')
    assert.equal((await cdpManager.Cdps(_carolCdpId))[4].toString(), '3')
    assert.equal((await cdpManager.Cdps(_erinCdpId))[4].toString(), '3')
    assert.equal((await cdpManager.Cdps(_flynCdpId))[4].toString(), '3')

    // Check sorted list has been reduced to length 4 
    assert.equal((await sortedCdps.getSize()).toString(), '4')
  })

  it('liquidateCdps(): liquidates  up to the requested number of undercollateralized cdps', async () => {
    // --- SETUP --- 
    await openCdp({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })

    // Alice, Bob, Carol, Dennis, Erin open cdps with consecutively decreasing collateral ratio
    await openCdp({ ICR: toBN(dec(202, 16)), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(204, 16)), extraParams: { from: bob } })
    await openCdp({ ICR: toBN(dec(206, 16)), extraParams: { from: carol } })
    await openCdp({ ICR: toBN(dec(208, 16)), extraParams: { from: dennis } })
    await openCdp({ ICR: toBN(dec(210, 16)), extraParams: { from: erin } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);
    let _erinCdpId = await sortedCdps.cdpOfOwnerByIndex(erin, 0);

    // --- TEST --- 

    // Price drops
    await priceFeed.setPrice(dec(3714, 13))

    // Confirm system is not in Recovery Mode
    assert.isFalse(await th.checkRecoveryMode(contracts));

    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});		
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(carol)).toString()), {from: carol});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(whale)).toString()), {from: whale});
    await th.liquidateCdps(3, dec(3714, 13), contracts, {extraParams: {from: owner}})

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

  it('liquidateCdps(): does nothing if all cdps have ICR > 110%', async () => {
    await openCdp({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
    await openCdp({ ICR: toBN(dec(222, 16)), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(222, 16)), extraParams: { from: bob } })
    await openCdp({ ICR: toBN(dec(222, 16)), extraParams: { from: carol } })
    let _whaleCdpId = await sortedCdps.cdpOfOwnerByIndex(whale, 0);
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    // Price drops, but all cdps remain active at 111% ICR
    await priceFeed.setPrice(dec(3714, 13))
    const price = await priceFeed.getPrice()

    assert.isTrue((await sortedCdps.contains(_whaleCdpId)))
    assert.isTrue((await sortedCdps.contains(_aliceCdpId)))
    assert.isTrue((await sortedCdps.contains(_bobCdpId)))
    assert.isTrue((await sortedCdps.contains(_carolCdpId)))

    const TCR_Before = (await th.getCachedTCR(contracts)).toString()
    const listSize_Before = (await sortedCdps.getSize()).toString()

    assert.isTrue((await cdpManager.getCachedICR(_whaleCdpId, price)).gte(mv._MCR))
    assert.isTrue((await cdpManager.getCachedICR(_aliceCdpId, price)).gte(mv._MCR))
    assert.isTrue((await cdpManager.getCachedICR(_bobCdpId, price)).gte(mv._MCR))
    assert.isTrue((await cdpManager.getCachedICR(_carolCdpId, price)).gte(mv._MCR))

    // Confirm system is not in Recovery Mode
    assert.isFalse(await th.checkRecoveryMode(contracts));

    // Attempt liqudation sequence
    await assertRevert(th.liquidateCdps(10, dec(3714, 13), contracts, {extraParams: {from: owner}}), "CdpManager: nothing to liquidate")

    // Check all cdps remain active
    assert.isTrue((await sortedCdps.contains(_whaleCdpId)))
    assert.isTrue((await sortedCdps.contains(_aliceCdpId)))
    assert.isTrue((await sortedCdps.contains(_bobCdpId)))
    assert.isTrue((await sortedCdps.contains(_carolCdpId)))

    const TCR_After = (await th.getCachedTCR(contracts)).toString()
    const listSize_After = (await sortedCdps.getSize()).toString()

    assert.equal(TCR_Before, TCR_After)
    assert.equal(listSize_Before, listSize_After)
  })

  
  it("liquidateCdps(): liquidates based on entire/collateral debt (including pending rewards), not raw collateral/debt", async () => {
    await openCdp({ ICR: toBN(dec(400, 16)), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(221, 16)), extraParams: { from: bob } })
    await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: carol } })
    await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: defaulter_1 } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _defaulter1CdpId = await sortedCdps.cdpOfOwnerByIndex(defaulter_1, 0);

    // Price drops
    await priceFeed.setPrice(dec(3714, 13))
    const price = await priceFeed.getPrice()

    const alice_ICR_Before = await cdpManager.getCachedICR(_aliceCdpId, price)
    const bob_ICR_Before = await cdpManager.getCachedICR(_bobCdpId, price)
    const carol_ICR_Before = await cdpManager.getCachedICR(_carolCdpId, price)

    /* Before liquidation: 
    Alice ICR: = (2 * 100 / 100) = 200%
    Bob ICR: (1 * 100 / 90.5) = 110.5%
    Carol ICR: (1 * 100 / 100 ) =  100%

    Therefore Alice and Bob above the MCR, Carol is below */
    assert.isTrue(alice_ICR_Before.gte(mv._MCR))
    assert.isTrue(bob_ICR_Before.gte(mv._MCR))
    assert.isTrue(carol_ICR_Before.lte(mv._MCR))

    // Liquidate defaulter. 30 EBTC and 0.3 ETH is distributed uniformly between A, B and C. Each receive 10 EBTC, 0.1 ETH
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(carol)).toString()), {from: carol});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(defaulter_1)).toString()), {from: defaulter_1});
    await cdpManager.liquidate(_defaulter1CdpId)

    const alice_ICR_After = await cdpManager.getCachedICR(_aliceCdpId, price)
    const bob_ICR_After = await cdpManager.getCachedICR(_bobCdpId, price)
    const carol_ICR_After = await cdpManager.getCachedICR(_carolCdpId, price)

    /* After liquidation: 

    Alice ICR: (1.0995 * 100 / 60) = 183.25%
    Bob ICR:(1.0995 * 100 / 100.5) =  109.40%
    Carol ICR: (1.0995 * 100 / 110 ) 99.95%

    Check Alice is above MCR, Bob below, Carol below. */
    assert.isTrue(alice_ICR_After.gte(mv._MCR))
    assert.isTrue(bob_ICR_After.lte(mv._MCR))
    assert.isTrue(carol_ICR_After.lte(mv._MCR))

    /* Though Bob's true ICR (including pending rewards) is below the MCR, check that Bob's raw coll and debt has not changed */
    const bob_Coll = (await cdpManager.Cdps(_bobCdpId))[1]
    const bob_Debt = (await cdpManager.Cdps(_bobCdpId))[0]

    const bob_rawICR = bob_Coll.mul(toBN(dec(100, 18))).div(bob_Debt)
    assert.isTrue(bob_rawICR.gte(mv._MCR))

    // Whale enters system, pulling it into Normal Mode
    await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("100701")});
    await openCdp({ ICR: toBN(dec(10, 18)), extraEBTCAmount: dec(1, 20), extraParams: { from: whale } })

    // Confirm system is not in Recovery Mode
    assert.isFalse(await th.checkRecoveryMode(contracts));

    //liquidate A, B, C
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(whale)).toString()), {from: whale});
    await th.liquidateCdps(10, price, contracts, {extraParams: {from: owner}})

    // Check A stays active, B and C get liquidated
    assert.isTrue(await sortedCdps.contains(_aliceCdpId))
    assert.isFalse(await sortedCdps.contains(_bobCdpId))
    assert.isFalse(await sortedCdps.contains(_carolCdpId))

    // check cdp statuses - A & B active (1),  C closed by liquidation (3)
    assert.equal((await cdpManager.Cdps(_aliceCdpId))[4].toString(), '1')
    assert.equal((await cdpManager.Cdps(_bobCdpId))[4].toString(), '3')
    assert.equal((await cdpManager.Cdps(_carolCdpId))[4].toString(), '3')
  })

  it("liquidateCdps(): reverts if n = 0", async () => {
    await openCdp({ ICR: toBN(dec(20, 18)), extraParams: { from: whale } })
    await openCdp({ ICR: toBN(dec(210, 16)), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(218, 16)), extraParams: { from: bob } })
    await openCdp({ ICR: toBN(dec(206, 16)), extraParams: { from: carol } })
    let _whaleCdpId = await sortedCdps.cdpOfOwnerByIndex(whale, 0);
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

    // Confirm system is not in Recovery Mode
    assert.isFalse(await th.checkRecoveryMode(contracts));

    // Liquidation with n = 0
    await assertRevert(th.liquidateCdps(0, price, contracts, {extraParams: {from: owner}}), "CdpManager: nothing to liquidate")

    // Check all cdps are still in the system
    assert.isTrue(await sortedCdps.contains(_whaleCdpId))
    assert.isTrue(await sortedCdps.contains(_aliceCdpId))
    assert.isTrue(await sortedCdps.contains(_bobCdpId))
    assert.isTrue(await sortedCdps.contains(_carolCdpId))

    const TCR_After = (await th.getCachedTCR(contracts)).toString()

    // Check TCR has not changed after liquidation
    assert.equal(TCR_Before, TCR_After)
  })

  it("liquidateCdps():  liquidates cdps with ICR < MCR", async () => {
    await openCdp({ ICR: toBN(dec(20, 18)), extraParams: { from: whale } })

    // A, B, C open cdps that will remain active when price drops to 100
    await openCdp({ ICR: toBN(dec(220, 16)), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(230, 16)), extraParams: { from: bob } })
    await openCdp({ ICR: toBN(dec(240, 16)), extraParams: { from: carol } })

    // D, E, F open cdps that will fall below MCR when price drops to 100
    await openCdp({ ICR: toBN(dec(218, 16)), extraParams: { from: dennis } })
    await openCdp({ ICR: toBN(dec(216, 16)), extraParams: { from: erin } })
    await openCdp({ ICR: toBN(dec(210, 16)), extraParams: { from: flyn } })
    let _whaleCdpId = await sortedCdps.cdpOfOwnerByIndex(whale, 0);
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);
    let _erinCdpId = await sortedCdps.cdpOfOwnerByIndex(erin, 0);
    let _flynCdpId = await sortedCdps.cdpOfOwnerByIndex(flyn, 0);

    // Check list size is 7
    assert.equal((await sortedCdps.getSize()).toString(), '7')

    // Price drops
    await priceFeed.setPrice(dec(3720, 13))
    const price = await priceFeed.getPrice()

    const alice_ICR = await cdpManager.getCachedICR(_aliceCdpId, price)
    const bob_ICR = await cdpManager.getCachedICR(_bobCdpId, price)
    const carol_ICR = await cdpManager.getCachedICR(_carolCdpId, price)
    const dennis_ICR = await cdpManager.getCachedICR(_dennisCdpId, price)
    const erin_ICR = await cdpManager.getCachedICR(_erinCdpId, price)
    const flyn_ICR = await cdpManager.getCachedICR(_flynCdpId, price)

    // Check A, B, C have ICR above MCR
    assert.isTrue(alice_ICR.gte(mv._MCR))
    assert.isTrue(bob_ICR.gte(mv._MCR))
    assert.isTrue(carol_ICR.gte(mv._MCR))

    // Check D, E, F have ICR below MCR
    assert.isTrue(dennis_ICR.lte(mv._MCR))
    assert.isTrue(erin_ICR.lte(mv._MCR))
    assert.isTrue(flyn_ICR.lte(mv._MCR))

    // Confirm system is not in Recovery Mode
    assert.isFalse(await th.checkRecoveryMode(contracts));

    //Liquidate sequence
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});		
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(carol)).toString()), {from: carol});		
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(dennis)).toString()), {from: dennis});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(erin)).toString()), {from: erin});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(flyn)).toString()), {from: flyn});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(whale)).toString()), {from: whale});
    await th.liquidateCdps(10, price, contracts, {extraParams: {from: owner}})

    // check list size reduced to 4
    assert.equal((await sortedCdps.getSize()).toString(), '4')

    // Check Whale and A, B, C remain in the system
    assert.isTrue(await sortedCdps.contains(_whaleCdpId))
    assert.isTrue(await sortedCdps.contains(_aliceCdpId))
    assert.isTrue(await sortedCdps.contains(_bobCdpId))
    assert.isTrue(await sortedCdps.contains(_carolCdpId))

    // Check D, E, F have been removed
    assert.isFalse(await sortedCdps.contains(_dennisCdpId))
    assert.isFalse(await sortedCdps.contains(_erinCdpId))
    assert.isFalse(await sortedCdps.contains(_flynCdpId))
  })

  it("liquidateCdps(): does not affect the liquidated user's token balances", async () => {
    await openCdp({ ICR: toBN(dec(20, 18)), extraParams: { from: whale } })

    // D, E, F open cdps that will fall below MCR when price drops to 100
    await openCdp({ ICR: toBN(dec(218, 16)), extraParams: { from: dennis } })
    await openCdp({ ICR: toBN(dec(216, 16)), extraParams: { from: erin } })
    await openCdp({ ICR: toBN(dec(210, 16)), extraParams: { from: flyn } })
    let _whaleCdpId = await sortedCdps.cdpOfOwnerByIndex(whale, 0);
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);
    let _erinCdpId = await sortedCdps.cdpOfOwnerByIndex(erin, 0);
    let _flynCdpId = await sortedCdps.cdpOfOwnerByIndex(flyn, 0);

    const D_balanceBefore = await ebtcToken.balanceOf(dennis)
    const E_balanceBefore = await ebtcToken.balanceOf(erin)
    const F_balanceBefore = await ebtcToken.balanceOf(flyn)

    // Check list size is 4
    assert.equal((await sortedCdps.getSize()).toString(), '4')

    // Price drops
    await priceFeed.setPrice(dec(3714, 13))
    const price = await priceFeed.getPrice()

    // Confirm system is not in Recovery Mode
    assert.isFalse(await th.checkRecoveryMode(contracts));

    //Liquidate sequence	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(flyn)).toString()), {from: flyn});		
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(erin)).toString()), {from: erin});		
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(dennis)).toString()), {from: dennis});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(whale)).toString()), {from: whale});
    await th.liquidateCdps(10, dec(3714, 13), contracts, {extraParams: {from: owner}})

    // check list size reduced to 1
    assert.equal((await sortedCdps.getSize()).toString(), '1')

    // Check Whale remains in the system
    assert.isTrue(await sortedCdps.contains(_whaleCdpId))

    // Check D, E, F have been removed
    assert.isFalse(await sortedCdps.contains(_dennisCdpId))
    assert.isFalse(await sortedCdps.contains(_erinCdpId))
    assert.isFalse(await sortedCdps.contains(_flynCdpId))
  })

  it("liquidateCdps(): A liquidation sequence containing Pool offsets increases the TCR", async () => {
    await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("250101")});
    await openCdp({ ICR: toBN(dec(100, 18)), extraEBTCAmount: toBN(dec(100, 18)), extraParams: { from: whale } })

    await openCdp({ ICR: toBN(dec(4, 18)), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(28, 18)), extraParams: { from: bob } })
    await openCdp({ ICR: toBN(dec(8, 18)), extraParams: { from: carol } })
    await openCdp({ ICR: toBN(dec(80, 18)), extraParams: { from: dennis } })

    await openCdp({ ICR: toBN(dec(199, 16)), extraParams: { from: defaulter_1 } })
    await openCdp({ ICR: toBN(dec(156, 16)), extraParams: { from: defaulter_2 } })
    await openCdp({ ICR: toBN(dec(183, 16)), extraParams: { from: defaulter_3 } })
    await openCdp({ ICR: toBN(dec(166, 16)), extraParams: { from: defaulter_4 } })
    let _defaulter1CdpId = await sortedCdps.cdpOfOwnerByIndex(defaulter_1, 0);
    let _defaulter2CdpId = await sortedCdps.cdpOfOwnerByIndex(defaulter_2, 0);
    let _defaulter3CdpId = await sortedCdps.cdpOfOwnerByIndex(defaulter_3, 0);
    let _defaulter4CdpId = await sortedCdps.cdpOfOwnerByIndex(defaulter_4, 0);

    assert.isTrue((await sortedCdps.contains(_defaulter1CdpId)))
    assert.isTrue((await sortedCdps.contains(_defaulter2CdpId)))
    assert.isTrue((await sortedCdps.contains(_defaulter3CdpId)))
    assert.isTrue((await sortedCdps.contains(_defaulter4CdpId)))

    assert.equal((await sortedCdps.getSize()).toString(), '9')

    // Price drops
    await priceFeed.setPrice(dec(3714, 13))

    const TCR_Before = await th.getCachedTCR(contracts)

    // Confirm system is not in Recovery Mode
    assert.isFalse(await th.checkRecoveryMode(contracts));

    // Liquidate cdps
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});		
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(carol)).toString()), {from: carol});		
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(dennis)).toString()), {from: dennis});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(defaulter_1)).toString()), {from: defaulter_1});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(defaulter_2)).toString()), {from: defaulter_2});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(defaulter_3)).toString()), {from: defaulter_3});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(defaulter_4)).toString()), {from: defaulter_4});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(whale)).toString()), {from: whale});
    await th.liquidateCdps(10, dec(3714, 13), contracts, {extraParams: {from: owner}})

    // Check all defaulters have been liquidated
    assert.isFalse((await sortedCdps.contains(_defaulter1CdpId)))
    assert.isFalse((await sortedCdps.contains(_defaulter2CdpId)))
    assert.isFalse((await sortedCdps.contains(_defaulter3CdpId)))
    assert.isFalse((await sortedCdps.contains(_defaulter4CdpId)))

    // check system sized reduced to 5 cdps
    assert.equal((await sortedCdps.getSize()).toString(), '5')

    // Check that the liquidation sequence has improved the TCR
    const TCR_After = await th.getCachedTCR(contracts)
    assert.isTrue(TCR_After.gte(TCR_Before))
  })

  it("liquidateCdps(): A liquidation sequence of pure redistributions increases the TCR", async () => {
    const { collateral: W_coll, totalDebt: W_debt } = await openCdp({ ICR: toBN(dec(100, 18)), extraParams: { from: whale } })
    const { collateral: A_coll, totalDebt: A_debt } = await openCdp({ ICR: toBN(dec(4, 18)), extraParams: { from: alice } })
    const { collateral: B_coll, totalDebt: B_debt } = await openCdp({ ICR: toBN(dec(28, 18)), extraParams: { from: bob } })
    const { collateral: C_coll, totalDebt: C_debt } = await openCdp({ ICR: toBN(dec(8, 18)), extraParams: { from: carol } })
    const { collateral: D_coll, totalDebt: D_debt } = await openCdp({ ICR: toBN(dec(80, 18)), extraParams: { from: dennis } })

    const { collateral: d1_coll, totalDebt: d1_debt } = await openCdp({ ICR: toBN(dec(199, 16)), extraParams: { from: defaulter_1 } })
    const { collateral: d2_coll, totalDebt: d2_debt } = await openCdp({ ICR: toBN(dec(156, 16)), extraParams: { from: defaulter_2 } })
    const { collateral: d3_coll, totalDebt: d3_debt } = await openCdp({ ICR: toBN(dec(183, 16)), extraParams: { from: defaulter_3 } })
    const { collateral: d4_coll, totalDebt: d4_debt } = await openCdp({ ICR: toBN(dec(166, 16)), extraParams: { from: defaulter_4 } })
    let _defaulter1CdpId = await sortedCdps.cdpOfOwnerByIndex(defaulter_1, 0);
    let _defaulter2CdpId = await sortedCdps.cdpOfOwnerByIndex(defaulter_2, 0);
    let _defaulter3CdpId = await sortedCdps.cdpOfOwnerByIndex(defaulter_3, 0);
    let _defaulter4CdpId = await sortedCdps.cdpOfOwnerByIndex(defaulter_4, 0);

    const totalCollNonDefaulters = W_coll.add(A_coll).add(B_coll).add(C_coll).add(D_coll)
    const totalCollDefaulters = d1_coll.add(d2_coll).add(d3_coll).add(d4_coll)
    const totalColl = totalCollNonDefaulters.add(totalCollDefaulters)
    const totalDebt = W_debt.add(A_debt).add(B_debt).add(C_debt).add(D_debt).add(d1_debt).add(d2_debt).add(d3_debt).add(d4_debt)
    let totalDebtNonDefaulter = W_debt.add(A_debt).add(B_debt).add(C_debt).add(D_debt)
    const totalDebtDefaulter = d1_debt.add(d2_debt).add(d3_debt).add(d4_debt);

    assert.isTrue((await sortedCdps.contains(_defaulter1CdpId)))
    assert.isTrue((await sortedCdps.contains(_defaulter2CdpId)))
    assert.isTrue((await sortedCdps.contains(_defaulter3CdpId)))
    assert.isTrue((await sortedCdps.contains(_defaulter4CdpId)))

    assert.equal((await sortedCdps.getSize()).toString(), '9')

    // Price drops
    const price = toBN(dec(3720, 13))
    await priceFeed.setPrice(price)

    const TCR_Before = await th.getCachedTCR(contracts)
    assert.isAtMost(th.getDifference(TCR_Before, totalColl.mul(price).div(totalDebt)), 1000)

    // Confirm system is not in Recovery Mode
    assert.isFalse(await th.checkRecoveryMode(contracts));

    // Liquidate
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});		
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(carol)).toString()), {from: carol});		
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(dennis)).toString()), {from: dennis});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(defaulter_1)).toString()), {from: defaulter_1});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(defaulter_2)).toString()), {from: defaulter_2});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(defaulter_3)).toString()), {from: defaulter_3});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(defaulter_4)).toString()), {from: defaulter_4});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(whale)).toString()), {from: whale});
    await th.liquidateCdps(10, price, contracts, {extraParams: {from: owner}})
	totalDebtNonDefaulter = totalDebtNonDefaulter.add(totalDebtDefaulter.sub(totalCollDefaulters.mul(toBN(price)).div(LICR)));

    // Check all defaulters have been liquidated
    assert.isFalse((await sortedCdps.contains(_defaulter1CdpId)))
    assert.isFalse((await sortedCdps.contains(_defaulter2CdpId)))
    assert.isFalse((await sortedCdps.contains(_defaulter3CdpId)))
    assert.isFalse((await sortedCdps.contains(_defaulter4CdpId)))

    // check system sized reduced to 5 cdps
    assert.equal((await sortedCdps.getSize()).toString(), '5')

    // Check that the liquidation sequence has increased the TCR
    const TCR_After = await th.getCachedTCR(contracts)
    assert.isAtMost(th.getDifference(TCR_After, totalCollNonDefaulters.add(th.applyLiquidationFee(toBN('0'))).mul(price).div(totalDebtNonDefaulter)), 1000)
    assert.isTrue(TCR_Before.lte(TCR_After))
  })

  it("liquidateCdps(): Liquidating cdps with SP deposits correctly impacts their SP deposit and ETH gain", async () => {
    const whaleDeposit = toBN(dec(100, 18))
    await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("310101")});
    await openCdp({ ICR: toBN(dec(100, 18)), extraEBTCAmount: whaleDeposit, extraParams: { from: whale } })

    const A_deposit = toBN(dec(1000, 18))
    const B_deposit = toBN(dec(3000, 18))
    await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("50101")});
    await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("50101")});
    const { collateral: A_coll, totalDebt: A_debt } = await openCdp({ ICR: toBN(dec(2, 18)), extraEBTCAmount: A_deposit, extraParams: { from: alice } })
    const { collateral: B_coll, totalDebt: B_debt } = await openCdp({ ICR: toBN(dec(2, 18)), extraEBTCAmount: B_deposit, extraParams: { from: bob } })
    const { collateral: C_coll, totalDebt: C_debt } = await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: carol } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    const liquidatedColl = A_coll.add(B_coll).add(C_coll)
    const liquidatedDebt = A_debt.add(B_debt).add(C_debt)

    assert.equal((await sortedCdps.getSize()).toString(), '4')

    // Price drops
    await priceFeed.setPrice(dec(3714, 13))

    // Check 800 EBTC in Pool
    const totalDeposits = whaleDeposit.add(A_deposit).add(B_deposit)

    // Confirm system is not in Recovery Mode
    assert.isFalse(await th.checkRecoveryMode(contracts));

    // Liquidate
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});		
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(carol)).toString()), {from: carol});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(whale)).toString()), {from: whale});
    await th.liquidateCdps(10, dec(3714, 13), contracts, {extraParams: {from: owner}})

    // Check all defaulters have been liquidated
    assert.isFalse((await sortedCdps.contains(_aliceCdpId)))
    assert.isFalse((await sortedCdps.contains(_bobCdpId)))
    assert.isFalse((await sortedCdps.contains(_carolCdpId)))

    // check system sized reduced to 1 cdps
    assert.equal((await sortedCdps.getSize()).toString(), '1')

    /* Prior to liquidation, SP deposits were:
    Whale: 400 EBTC
    Alice: 100 EBTC
    Bob:   300 EBTC
    Carol: 0 EBTC

    Total EBTC in Pool: 800 EBTC

    Then, liquidation hits A,B,C: 

    Total liquidated debt = 150 + 350 + 150 = 650 EBTC
    Total liquidated ETH = 1.1 + 3.1 + 1.1 = 5.3 ETH

    whale ebtc loss: 650 * (400/800) = 325 ebtc
    alice ebtc loss:  650 *(100/800) = 81.25 ebtc
    bob ebtc loss: 650 * (300/800) = 243.75 ebtc

    whale remaining deposit: (400 - 325) = 75 ebtc
    alice remaining deposit: (100 - 81.25) = 18.75 ebtc
    bob remaining deposit: (300 - 243.75) = 56.25 ebtc

    whale eth gain: 5*0.995 * (400/800) = 2.4875 eth
    alice eth gain: 5*0.995 *(100/800) = 0.621875 eth
    bob eth gain: 5*0.995 * (300/800) = 1.865625 eth

    Total remaining deposits: 150 EBTC
    Total ETH gain: 4.975 ETH */
  })

  it("liquidateCdps(): when SP > 0, triggers LQTY reward event - increases the sum G", async () => {
    await openCdp({ ICR: toBN(dec(100, 18)), extraParams: { from: whale } })

    // A, B, C open cdps
    await openCdp({ ICR: toBN(dec(4, 18)), extraParams: { from: A } })
    await openCdp({ ICR: toBN(dec(3, 18)), extraEBTCAmount: toBN(dec(100, 18)), extraParams: { from: B } })
    await openCdp({ ICR: toBN(dec(3, 18)), extraParams: { from: C } })

    await openCdp({ ICR: toBN(dec(219, 16)), extraParams: { from: defaulter_1 } })
    await openCdp({ ICR: toBN(dec(213, 16)), extraParams: { from: defaulter_2 } })
    let _defaulter1CdpId = await sortedCdps.cdpOfOwnerByIndex(defaulter_1, 0);
    let _defaulter2CdpId = await sortedCdps.cdpOfOwnerByIndex(defaulter_2, 0);

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Price drops to 1ETH:100EBTC, reducing defaulters to below MCR
    await priceFeed.setPrice(dec(3714, 13));
    const price = await priceFeed.getPrice()
    assert.isFalse(await th.checkRecoveryMode(contracts))

    // Liquidate cdps
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(defaulter_1)).toString()), {from: defaulter_1});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(defaulter_2)).toString()), {from: defaulter_2});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(whale)).toString()), {from: whale});
    await th.liquidateCdps(2, price, contracts, {extraParams: {from: owner}})
    assert.isFalse(await sortedCdps.contains(_defaulter1CdpId))
    assert.isFalse(await sortedCdps.contains(_defaulter2CdpId))
  })

  it("liquidateCdps(): when SP is empty, doesn't update G", async () => {
    await openCdp({ ICR: toBN(dec(100, 18)), extraParams: { from: whale } })

    // A, B, C open cdps
    await openCdp({ ICR: toBN(dec(4, 18)), extraParams: { from: A } })
    await openCdp({ ICR: toBN(dec(3, 18)), extraEBTCAmount: toBN(dec(100, 18)), extraParams: { from: B } })
    await openCdp({ ICR: toBN(dec(3, 18)), extraParams: { from: C } })

    await openCdp({ ICR: toBN(dec(219, 16)), extraParams: { from: defaulter_1 } })
    await openCdp({ ICR: toBN(dec(213, 16)), extraParams: { from: defaulter_2 } })
    let _defaulter1CdpId = await sortedCdps.cdpOfOwnerByIndex(defaulter_1, 0);
    let _defaulter2CdpId = await sortedCdps.cdpOfOwnerByIndex(defaulter_2, 0);

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Price drops to 1ETH:100EBTC, reducing defaulters to below MCR
    await priceFeed.setPrice(dec(3714, 13));
    const price = await priceFeed.getPrice()
    assert.isFalse(await th.checkRecoveryMode(contracts))

    // liquidate cdps
    await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from: whale});
    await debtToken.transfer(owner, (await debtToken.balanceOf(defaulter_1)), {from: defaulter_1});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(defaulter_2)).toString()), {from: defaulter_2});
    await th.liquidateCdps(2, price, contracts, {extraParams: {from: owner}})
    assert.isFalse(await sortedCdps.contains(_defaulter1CdpId))
    assert.isFalse(await sortedCdps.contains(_defaulter2CdpId))
  })


  // --- batchLiquidateCdps() ---

  it('batchLiquidateCdps(): liquidates a Cdp that a) was skipped in a previous liquidation and b) has pending rewards', async () => {
    // A, B, C, D, E open cdps 
    await openCdp({ ICR: toBN(dec(303, 16)), extraParams: { from: C } })
    await openCdp({ ICR: toBN(dec(304, 16)), extraParams: { from: D } })
    await openCdp({ ICR: toBN(dec(304, 16)), extraParams: { from: E } })
    await openCdp({ ICR: toBN(dec(120, 16)), extraParams: { from: A } })
    await openCdp({ ICR: toBN(dec(133, 16)), extraParams: { from: B } })
    let _aCdpId = await sortedCdps.cdpOfOwnerByIndex(A, 0);
    let _bCdpId = await sortedCdps.cdpOfOwnerByIndex(B, 0);
    let _cCdpId = await sortedCdps.cdpOfOwnerByIndex(C, 0);
    let _dCdpId = await sortedCdps.cdpOfOwnerByIndex(D, 0);
    let _eCdpId = await sortedCdps.cdpOfOwnerByIndex(E, 0);

    // Price drops
    await priceFeed.setPrice(dec(5000, 13))
    let price = await priceFeed.getPrice()
    
    // Confirm system is not in Recovery Mode
    assert.isFalse(await th.checkRecoveryMode(contracts))

    // A gets liquidated, creates pending rewards for all
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(E)).toString()).sub(toBN(dec(1, 15))), {from: E});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(A)).toString()).sub(toBN(dec(10, 15))), {from: A});
    const liqTxA = await cdpManager.liquidate(_aCdpId)
    assert.isTrue(liqTxA.receipt.status)
    assert.isFalse(await sortedCdps.contains(_aCdpId))

    // Price drops
    await priceFeed.setPrice(dec(3674, 13))
    price = await priceFeed.getPrice()
    // Confirm system is now in Recovery Mode
    assert.isTrue(await th.checkRecoveryMode(contracts))

    // Confirm C has ICR > TCR
    const TCR = await cdpManager.getCachedTCR(price)
    const ICR_C = await cdpManager.getCachedICR(_cCdpId, price)
  
    assert.isTrue(ICR_C.gt(TCR))

    // Attempt to liquidate B and C, which skips C in the liquidation since it is immune
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(B)).toString()), {from: B});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(C)).toString()), {from: C});
    const liqTxBC = await th.liquidateCdps(2, price, contracts, {extraParams: {from: owner}})
    assert.isTrue(liqTxBC.receipt.status)
    assert.isFalse(await sortedCdps.contains(_bCdpId))
    assert.isTrue(await sortedCdps.contains(_cCdpId))
    assert.isTrue(await sortedCdps.contains(_dCdpId))
    assert.isTrue(await sortedCdps.contains(_eCdpId))

    // // All remaining cdps D and E repay a little debt, applying their pending rewards
    assert.isTrue((await sortedCdps.getSize()).eq(toBN('3')))
    await borrowerOperations.repayDebt(_dCdpId, dec(1, 15), _dCdpId, _dCdpId, {from: D})
    await borrowerOperations.repayDebt(_eCdpId, dec(1, 15), _eCdpId, _eCdpId, {from: E})

    // Check all pending rewards already applied
    assert.isTrue(await cdpManager.hasPendingRedistributedDebt(_cCdpId))
    assert.isFalse(await cdpManager.hasPendingRedistributedDebt(_dCdpId))
    assert.isFalse(await cdpManager.hasPendingRedistributedDebt(_eCdpId))

    // Check C's pending coll and debt rewards are <= the coll and debt in the DefaultPool
    const pendingEBTCDebt_C = (await cdpManager.getPendingRedistributedDebt(_cCdpId))

    // Confirm system is not in Recovery Mode any more
    assert.isFalse(await th.checkRecoveryMode(contracts))

    await priceFeed.setPrice(dec(1000, 13))

    // Try to liquidate C again. Check it succeeds and closes C's cdp
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(C)).toString()), {from: C});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(D)).toString()), {from: D});
    const liqTx2 = await cdpManager.batchLiquidateCdps([_cCdpId,_dCdpId])
    assert.isTrue(liqTx2.receipt.status)
    assert.isFalse(await sortedCdps.contains(_cCdpId))
    assert.isFalse(await sortedCdps.contains(_dCdpId))
    assert.isTrue(await sortedCdps.contains(_eCdpId))
    assert.isTrue((await sortedCdps.getSize()).eq(toBN('1')))
  })

  it('batchLiquidateCdps(): closes every cdp with ICR < MCR in the given array', async () => {
    // --- SETUP ---
    await openCdp({ ICR: toBN(dec(100, 18)), extraParams: { from: whale } })

    await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(133, 16)), extraParams: { from: bob } })
    await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: carol } })
    await openCdp({ ICR: toBN(dec(2000, 16)), extraParams: { from: dennis } })
    await openCdp({ ICR: toBN(dec(1800, 16)), extraParams: { from: erin } })
    let _whaleCdpId = await sortedCdps.cdpOfOwnerByIndex(whale, 0);
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);
    let _erinCdpId = await sortedCdps.cdpOfOwnerByIndex(erin, 0);

    // Check full sorted list size is 6
    assert.equal((await sortedCdps.getSize()).toString(), '6')

    // --- TEST ---

    // Price drops to 1ETH:100EBTC, reducing A, B, C ICR below MCR
    await priceFeed.setPrice(dec(3714, 13));
    const price = await priceFeed.getPrice()

    // Confirm system is not in Recovery Mode
    assert.isFalse(await th.checkRecoveryMode(contracts));

    // Confirm cdps A-C are ICR < 110%
    assert.isTrue((await cdpManager.getCachedICR(_aliceCdpId, price)).lt(mv._MCR))
    assert.isTrue((await cdpManager.getCachedICR(_bobCdpId, price)).lt(mv._MCR))
    assert.isTrue((await cdpManager.getCachedICR(_carolCdpId, price)).lt(mv._MCR))

    // Confirm D-E are ICR > 110%
    assert.isTrue((await cdpManager.getCachedICR(_dennisCdpId, price)).gte(mv._MCR))
    assert.isTrue((await cdpManager.getCachedICR(_erinCdpId, price)).gte(mv._MCR))

    // Confirm Whale is ICR >= 110% 
    assert.isTrue((await cdpManager.getCachedICR(_whaleCdpId, price)).gte(mv._MCR))

    liquidationArray = [_aliceCdpId, _bobCdpId, _carolCdpId, _dennisCdpId, _erinCdpId]
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(carol)).toString()), {from: carol});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(dennis)).toString()), {from: dennis});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(erin)).toString()), {from: erin});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(whale)).toString()), {from: whale});
    await cdpManager.batchLiquidateCdps(liquidationArray);

    // Confirm cdps A-C have been removed from the system
    assert.isFalse(await sortedCdps.contains(_aliceCdpId))
    assert.isFalse(await sortedCdps.contains(_bobCdpId))
    assert.isFalse(await sortedCdps.contains(_carolCdpId))

    // Check all cdps A-C are now closed by liquidation
    assert.equal((await cdpManager.Cdps(_aliceCdpId))[4].toString(), '3')
    assert.equal((await cdpManager.Cdps(_bobCdpId))[4].toString(), '3')
    assert.equal((await cdpManager.Cdps(_carolCdpId))[4].toString(), '3')

    // Check sorted list has been reduced to length 3
    assert.equal((await sortedCdps.getSize()).toString(), '3')
  })

  it('batchLiquidateCdps(): does not liquidate cdps that are not in the given array', async () => {
    // --- SETUP ---
    await openCdp({ ICR: toBN(dec(100, 18)), extraParams: { from: whale } })

    await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(180, 16)), extraParams: { from: bob } })
    await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: carol } })
    await _signer.sendTransaction({ to: dennis, value: ethers.utils.parseEther("5000")});
    await _signer.sendTransaction({ to: erin, value: ethers.utils.parseEther("5000")});
    await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: toBN(dec(500, 18)), extraParams: { from: dennis } })
    await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: toBN(dec(500, 18)), extraParams: { from: erin } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);
    let _erinCdpId = await sortedCdps.cdpOfOwnerByIndex(erin, 0);

    // Check full sorted list size is 6
    assert.equal((await sortedCdps.getSize()).toString(), '6')

    // --- TEST ---

    // Price drops, reducing A, B, C ICR below MCR
    await priceFeed.setPrice(dec(4000, 13));
    const price = await priceFeed.getPrice()

    // Confirm cdps A-E are ICR < 110%
    assert.isTrue((await cdpManager.getCachedICR(_aliceCdpId, price)).lt(mv._MCR))
    assert.isTrue((await cdpManager.getCachedICR(_bobCdpId, price)).lt(mv._MCR))
    assert.isTrue((await cdpManager.getCachedICR(_carolCdpId, price)).lt(mv._MCR))
    assert.isTrue((await cdpManager.getCachedICR(_dennisCdpId, price)).lt(mv._MCR))
    assert.isTrue((await cdpManager.getCachedICR(_erinCdpId, price)).lt(mv._MCR))

    liquidationArray = [_aliceCdpId, _bobCdpId]  // C-E not included
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(whale)).toString()), {from: whale});
    await cdpManager.batchLiquidateCdps(liquidationArray);

    // Confirm cdps A-B have been removed from the system
    assert.isFalse(await sortedCdps.contains(_aliceCdpId))
    assert.isFalse(await sortedCdps.contains(_bobCdpId))

    // Check all cdps A-B are now closed by liquidation
    assert.equal((await cdpManager.Cdps(_aliceCdpId))[4].toString(), '3')
    assert.equal((await cdpManager.Cdps(_bobCdpId))[4].toString(), '3')

    // Confirm cdps C-E remain in the system
    assert.isTrue(await sortedCdps.contains(_carolCdpId))
    assert.isTrue(await sortedCdps.contains(_dennisCdpId))
    assert.isTrue(await sortedCdps.contains(_erinCdpId))

    // Check all cdps C-E are still active
    assert.equal((await cdpManager.Cdps(_carolCdpId))[4].toString(), '1')
    assert.equal((await cdpManager.Cdps(_dennisCdpId))[4].toString(), '1')
    assert.equal((await cdpManager.Cdps(_erinCdpId))[4].toString(), '1')

    // Check sorted list has been reduced to length 4
    assert.equal((await sortedCdps.getSize()).toString(), '4')
  })

  it('batchLiquidateCdps(): does not close cdps with ICR >= MCR in the given array', async () => {
    // --- SETUP ---
    await openCdp({ ICR: toBN(dec(100, 18)), extraParams: { from: whale } })

    await openCdp({ ICR: toBN(dec(190, 16)), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(120, 16)), extraParams: { from: bob } })
    await openCdp({ ICR: toBN(dec(195, 16)), extraParams: { from: carol } })
    await openCdp({ ICR: toBN(dec(2000, 16)), extraParams: { from: dennis } })
    await openCdp({ ICR: toBN(dec(1800, 16)), extraParams: { from: erin } })
    let _whaleCdpId = await sortedCdps.cdpOfOwnerByIndex(whale, 0);
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);
    let _erinCdpId = await sortedCdps.cdpOfOwnerByIndex(erin, 0);

    // Check full sorted list size is 6
    assert.equal((await sortedCdps.getSize()).toString(), '6')

    // --- TEST ---

    // Price drops to 1ETH:100EBTC, reducing A, B, C ICR below MCR
    await priceFeed.setPrice(dec(3714, 13));
    const price = await priceFeed.getPrice()

    // Confirm system is not in Recovery Mode
    assert.isFalse(await th.checkRecoveryMode(contracts));

    // Confirm cdps A-C are ICR < 110%
    assert.isTrue((await cdpManager.getCachedICR(_aliceCdpId, price)).lt(mv._MCR))
    assert.isTrue((await cdpManager.getCachedICR(_bobCdpId, price)).lt(mv._MCR))
    assert.isTrue((await cdpManager.getCachedICR(_carolCdpId, price)).lt(mv._MCR))

    // Confirm D-E are ICR >= 110%
    assert.isTrue((await cdpManager.getCachedICR(_dennisCdpId, price)).gte(mv._MCR))
    assert.isTrue((await cdpManager.getCachedICR(_erinCdpId, price)).gte(mv._MCR))

    // Confirm Whale is ICR > 110% 
    assert.isTrue((await cdpManager.getCachedICR(_whaleCdpId, price)).gte(mv._MCR))

    liquidationArray = [_aliceCdpId, _bobCdpId, _carolCdpId, _dennisCdpId, _erinCdpId]
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(carol)).toString()), {from: carol});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(dennis)).toString()), {from: dennis});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(erin)).toString()), {from: erin});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(whale)).toString()), {from: whale});
    await cdpManager.batchLiquidateCdps(liquidationArray);

    // Confirm cdps D-E and whale remain in the system
    assert.isTrue(await sortedCdps.contains(_dennisCdpId))
    assert.isTrue(await sortedCdps.contains(_erinCdpId))
    assert.isTrue(await sortedCdps.contains(_whaleCdpId))

    // Check all cdps D-E and whale remain active
    assert.equal((await cdpManager.Cdps(_dennisCdpId))[4].toString(), '1')
    assert.equal((await cdpManager.Cdps(_erinCdpId))[4].toString(), '1')
    assert.isTrue(await sortedCdps.contains(_whaleCdpId))

    // Check sorted list has been reduced to length 3
    assert.equal((await sortedCdps.getSize()).toString(), '3')
  })

  it('batchLiquidateCdps(): reverts if array is empty', async () => {
    // --- SETUP ---
    await openCdp({ ICR: toBN(dec(100, 18)), extraParams: { from: whale } })

    await openCdp({ ICR: toBN(dec(190, 16)), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(120, 16)), extraParams: { from: bob } })
    await openCdp({ ICR: toBN(dec(195, 16)), extraParams: { from: carol } })
    await openCdp({ ICR: toBN(dec(2000, 16)), extraParams: { from: dennis } })
    await openCdp({ ICR: toBN(dec(1800, 16)), extraParams: { from: erin } })

    // Check full sorted list size is 6
    assert.equal((await sortedCdps.getSize()).toString(), '6')

    // --- TEST ---

    // Price drops to 1ETH:100EBTC, reducing A, B, C ICR below MCR
    await priceFeed.setPrice(dec(3714, 13));
    const price = await priceFeed.getPrice()

    // Confirm system is not in Recovery Mode
    assert.isFalse(await th.checkRecoveryMode(contracts));

    liquidationArray = []
    try {
      const tx = await cdpManager.batchLiquidateCdps(liquidationArray);
      assert.isFalse(tx.receipt.status)
    } catch (error) {
      console.log(error)
      console.log(error.message)
      assert.include(error.message, "LiquidationLibrary: Calldata address array must not be empty")
    }
  })

  it("batchLiquidateCdps(): skips if cdp is non-existent", async () => {
    // --- SETUP ---
    const spDeposit = toBN(dec(200, 18))
    await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("252251")});
    await openCdp({ ICR: toBN(dec(100, 18)), extraEBTCAmount: spDeposit, extraParams: { from: whale } })

    const { totalDebt: A_debt } = await openCdp({ ICR: toBN(dec(190, 16)), extraParams: { from: alice } })
    const { totalDebt: B_debt } = await openCdp({ ICR: toBN(dec(120, 16)), extraParams: { from: bob } })
    await _signer.sendTransaction({ to: dennis, value: ethers.utils.parseEther("25221")});
    await _signer.sendTransaction({ to: erin, value: ethers.utils.parseEther("25221")});
    await openCdp({ ICR: toBN(dec(2000, 16)), extraParams: { from: dennis } })
    await openCdp({ ICR: toBN(dec(1800, 16)), extraParams: { from: erin } })
    let _whaleCdpId = await sortedCdps.cdpOfOwnerByIndex(whale, 0);
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);
    let _erinCdpId = await sortedCdps.cdpOfOwnerByIndex(erin, 0);

    assert.equal(await cdpManager.getCdpStatus(carol), 0) // check cdp non-existent

    // Check full sorted list size is 6
    assert.equal((await sortedCdps.getSize()).toString(), '5')

    // --- TEST ---

    // Price drops to 1ETH:100EBTC, reducing A, B, C ICR below MCR
    await priceFeed.setPrice(dec(3714, 13));
    const price = await priceFeed.getPrice()

    // Confirm system is not in Recovery Mode
    assert.isFalse(await th.checkRecoveryMode(contracts));

    // Confirm cdps A-B are ICR < 110%
    assert.isTrue((await cdpManager.getCachedICR(_aliceCdpId, price)).lt(mv._MCR))
    assert.isTrue((await cdpManager.getCachedICR(_bobCdpId, price)).lt(mv._MCR))

    // Confirm D-E are ICR > 110%
    assert.isTrue((await cdpManager.getCachedICR(_dennisCdpId, price)).gte(mv._MCR))
    assert.isTrue((await cdpManager.getCachedICR(_erinCdpId, price)).gte(mv._MCR))

    // Confirm Whale is ICR >= 110% 
    assert.isTrue((await cdpManager.getCachedICR(_whaleCdpId, price)).gte(mv._MCR))

    // Liquidate - cdp C in between the ones to be liquidated!
    const liquidationArray = [_aliceCdpId, carol, _bobCdpId, _dennisCdpId, _erinCdpId]
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(dennis)).toString()), {from: dennis});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(erin)).toString()), {from: erin});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(whale)).toString()), {from: whale});
    await cdpManager.batchLiquidateCdps(liquidationArray);

    // Confirm cdps A-B have been removed from the system
    assert.isFalse(await sortedCdps.contains(_aliceCdpId))
    assert.isFalse(await sortedCdps.contains(_bobCdpId))

    // Check all cdps A-B are now closed by liquidation
    assert.equal((await cdpManager.Cdps(_aliceCdpId))[4].toString(), '3')
    assert.equal((await cdpManager.Cdps(_bobCdpId))[4].toString(), '3')

    // Check sorted list has been reduced to length 3
    assert.equal((await sortedCdps.getSize()).toString(), '3')

    // Confirm cdp C non-existent
    assert.isFalse(await sortedCdps.contains(carol))
    assert.equal((await cdpManager.Cdps(carol))[4].toString(), '0')

    // Confirm system is not in Recovery Mode
    assert.isFalse(await th.checkRecoveryMode(contracts));
  })

  it("batchLiquidateCdps(): skips if a cdp has been closed", async () => {
    // --- SETUP ---
    const spDeposit = toBN(dec(100, 18))
    await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("252251")});
    await openCdp({ ICR: toBN(dec(100, 18)), extraEBTCAmount: spDeposit, extraParams: { from: whale } })

    const { totalDebt: A_debt } = await openCdp({ ICR: toBN(dec(190, 16)), extraParams: { from: alice } })
    const { totalDebt: B_debt } = await openCdp({ ICR: toBN(dec(120, 16)), extraParams: { from: bob } })
    await openCdp({ ICR: toBN(dec(195, 16)), extraParams: { from: carol } })
    await openCdp({ ICR: toBN(dec(2000, 16)), extraParams: { from: dennis } })
    await openCdp({ ICR: toBN(dec(1800, 16)), extraParams: { from: erin } })
    let _whaleCdpId = await sortedCdps.cdpOfOwnerByIndex(whale, 0);
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);
    let _erinCdpId = await sortedCdps.cdpOfOwnerByIndex(erin, 0);

    assert.isTrue(await sortedCdps.contains(_carolCdpId))

    // Check full sorted list size is 6
    assert.equal((await sortedCdps.getSize()).toString(), '6')

    // Whale transfers to Carol so she can close her cdp
    await ebtcToken.transfer(carol, dec(100, 18), { from: whale })

    // --- TEST ---

    // Price drops to 1ETH:100EBTC, reducing A, B, C ICR below MCR
    await priceFeed.setPrice(dec(3714, 13));
    const price = await priceFeed.getPrice()

    // Carol liquidated, and her cdp is closed
    const txCarolClose = await borrowerOperations.closeCdp(_carolCdpId, { from: carol })
    assert.isTrue(txCarolClose.receipt.status)

    assert.isFalse(await sortedCdps.contains(_carolCdpId))

    assert.equal(await cdpManager.getCdpStatus(_carolCdpId), 2)  // check cdp closed

    // Confirm system is not in Recovery Mode
    assert.isFalse(await th.checkRecoveryMode(contracts));

    // Confirm cdps A-B are ICR < 110%
    assert.isTrue((await cdpManager.getCachedICR(_aliceCdpId, price)).lt(mv._MCR))
    assert.isTrue((await cdpManager.getCachedICR(_bobCdpId, price)).lt(mv._MCR))

    // Confirm D-E are ICR > 110%
    assert.isTrue((await cdpManager.getCachedICR(_dennisCdpId, price)).gte(mv._MCR))
    assert.isTrue((await cdpManager.getCachedICR(_erinCdpId, price)).gte(mv._MCR))

    // Confirm Whale is ICR >= 110% 
    assert.isTrue((await cdpManager.getCachedICR(_whaleCdpId, price)).gte(mv._MCR))

    // Liquidate - cdp C in between the ones to be liquidated!
    const liquidationArray = [_aliceCdpId, _carolCdpId, _bobCdpId, _dennisCdpId, _erinCdpId]
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(carol)).toString()), {from: carol});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(dennis)).toString()), {from: dennis});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(erin)).toString()), {from: erin});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(whale)).toString()), {from: whale});	
    await cdpManager.batchLiquidateCdps(liquidationArray);

    // Confirm cdps A-B have been removed from the system
    assert.isFalse(await sortedCdps.contains(_aliceCdpId))
    assert.isFalse(await sortedCdps.contains(_bobCdpId))

    // Check all cdps A-B are now closed by liquidation
    assert.equal((await cdpManager.Cdps(_aliceCdpId))[4].toString(), '3')
    assert.equal((await cdpManager.Cdps(_bobCdpId))[4].toString(), '3')
    // Cdp C still closed by user
    assert.equal((await cdpManager.Cdps(_carolCdpId))[4].toString(), '2')

    // Check sorted list has been reduced to length 3
    assert.equal((await sortedCdps.getSize()).toString(), '3')

    // Confirm system is not in Recovery Mode
    assert.isFalse(await th.checkRecoveryMode(contracts));
  })

  it("batchLiquidateCdps: when SP > 0, triggers LQTY reward event - increases the sum G", async () => {
    await openCdp({ ICR: toBN(dec(100, 18)), extraParams: { from: whale } })

    // A, B, C open cdps
    await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: A } })
    await openCdp({ ICR: toBN(dec(133, 16)), extraParams: { from: B } })
    await openCdp({ ICR: toBN(dec(167, 16)), extraParams: { from: C } })

    await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: defaulter_1 } })
    await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: defaulter_2 } })
    let _defaulter1CdpId = await sortedCdps.cdpOfOwnerByIndex(defaulter_1, 0);
    let _defaulter2CdpId = await sortedCdps.cdpOfOwnerByIndex(defaulter_2, 0);

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Price drops to 1ETH:100EBTC, reducing defaulters to below MCR
    await priceFeed.setPrice(dec(3714, 13));
    const price = await priceFeed.getPrice()
    assert.isFalse(await th.checkRecoveryMode(contracts))

    // Liquidate cdps
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(defaulter_1)).toString()), {from: defaulter_1});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(defaulter_2)).toString()), {from: defaulter_2});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(whale)).toString()), {from: whale});	
    await cdpManager.batchLiquidateCdps([_defaulter1CdpId, _defaulter2CdpId])
    assert.isFalse(await sortedCdps.contains(_defaulter1CdpId))
    assert.isFalse(await sortedCdps.contains(_defaulter2CdpId))
  })

  it("batchLiquidateCdps(): when SP is empty, doesn't update G", async () => {
    await openCdp({ ICR: toBN(dec(100, 18)), extraParams: { from: whale } })

    // A, B, C open cdps
    await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: A } })
    await openCdp({ ICR: toBN(dec(133, 16)), extraParams: { from: B } })
    await openCdp({ ICR: toBN(dec(167, 16)), extraParams: { from: C } })

    await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: defaulter_1 } })
    await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: defaulter_2 } })
    let _defaulter1CdpId = await sortedCdps.cdpOfOwnerByIndex(defaulter_1, 0);
    let _defaulter2CdpId = await sortedCdps.cdpOfOwnerByIndex(defaulter_2, 0);

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

    // Price drops to 1ETH:100EBTC, reducing defaulters to below MCR
    await priceFeed.setPrice(dec(3714, 13));
    const price = await priceFeed.getPrice()
    assert.isFalse(await th.checkRecoveryMode(contracts))

    // liquidate cdps
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(defaulter_1)).toString()), {from: defaulter_1});	
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(defaulter_2)).toString()), {from: defaulter_2});
    await debtToken.transfer(owner, toBN((await debtToken.balanceOf(whale)).toString()), {from: whale});	
    await cdpManager.batchLiquidateCdps([_defaulter1CdpId, _defaulter2CdpId])
    assert.isFalse(await sortedCdps.contains(_defaulter1CdpId))
    assert.isFalse(await sortedCdps.contains(_defaulter2CdpId))
  })

  // --- redemptions ---


  it('getRedemptionHints(): gets the address of the first Cdp and the final ICR of the last Cdp involved in a redemption', async () => {
    // --- SETUP ---
    const partialRedemptionAmount = toBN(dec(1, 18))
    const { collateral: A_coll, totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(310, 16)), extraEBTCAmount: toBN(dec(10, 18)), extraParams: { from: alice } })
    const { netDebt: B_debt } = await openCdp({ ICR: toBN(dec(290, 16)), extraEBTCAmount: partialRedemptionAmount, extraParams: { from: bob } })
    const { netDebt: C_debt } = await openCdp({ ICR: toBN(dec(250, 16)), extraParams: { from: carol } })
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    // Dennis' Cdp should be untouched by redemption, because its ICR will be < 110% after the price drop
    await openCdp({ ICR: toBN(dec(120, 16)), extraParams: { from: dennis } })

    // Drop the price
    const price = toBN(dec(3720, 13))
    await priceFeed.setPrice(price);

    // --- TEST ---
    const redemptionAmount = C_debt.add(B_debt).add(partialRedemptionAmount)
    const {
      firstRedemptionHint,
      partialRedemptionHintNICR
    } = await hintHelpers.getRedemptionHints(redemptionAmount, price, 0)

    assert.equal(firstRedemptionHint, _carolCdpId)
    const expectedICR = A_coll.mul(mv._100e18BN).div(A_totalDebt.sub(partialRedemptionAmount))
    th.assertIsApproximatelyEqual(partialRedemptionHintNICR, expectedICR, 1000000000000000000000)
  });

  it('getRedemptionHints(): returns 0 as partialRedemptionHintNICR when reaching _maxIterations', async () => {
    // --- SETUP ---
    await openCdp({ ICR: toBN(dec(310, 16)), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(290, 16)), extraParams: { from: bob } })
    await openCdp({ ICR: toBN(dec(250, 16)), extraParams: { from: carol } })
    await openCdp({ ICR: toBN(dec(180, 16)), extraParams: { from: dennis } })

    const price = await priceFeed.getPrice();

    // --- TEST ---

    // Get hints for a redemption of 170 + 30 + some extra EBTC. At least 3 iterations are needed
    // for total redemption of the given amount.
    const {
      partialRedemptionHintNICR
    } = await hintHelpers.getRedemptionHints('210' + _18_zeros, price, 2) // limit _maxIterations to 2

    assert.equal(partialRedemptionHintNICR, '0')
  });

  it('redeemCollateral(): cancels the provided EBTC with debt from Cdps with the lowest ICRs and sends an equivalent amount of Ether', async () => {
    // --- SETUP ---
    const { totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(310, 16)), extraEBTCAmount: dec(10, 18), extraParams: { from: alice } })
    const { netDebt: B_netDebt } = await openCdp({ ICR: toBN(dec(290, 16)), extraEBTCAmount: dec(8, 18), extraParams: { from: bob } })
    const { netDebt: C_netDebt } = await openCdp({ ICR: toBN(dec(250, 16)), extraEBTCAmount: dec(10, 18), extraParams: { from: carol } })
    const partialRedemptionAmount = toBN(2)
    const redemptionAmount = C_netDebt.add(B_netDebt).add(partialRedemptionAmount)
    await openCdp({ ICR: toBN(dec(100, 18)), extraEBTCAmount: redemptionAmount, extraParams: { from: dennis } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);

    const dennis_ETHBalance_Before = toBN(await contracts.collateral.balanceOf(dennis))

    const dennis_EBTCBalance_Before = await ebtcToken.balanceOf(dennis)

    const price = await priceFeed.getPrice()

    // --- TEST ---
    await th.syncTwapSystemDebt(contracts, ethers.provider);

    // Find hints for redeeming 20 EBTC
    const {
      firstRedemptionHint,
      partialRedemptionHintNICR
    } = await hintHelpers.getRedemptionHints(redemptionAmount, price, 0)

    // We don't need to use getApproxHint for this test, since it's not the subject of this
    // test case, and the list is very small, so the correct position is quickly found
    const { 0: upperPartialRedemptionHint, 1: lowerPartialRedemptionHint } = await sortedCdps.findInsertPosition(
      partialRedemptionHintNICR,
      _dennisCdpId,
      _dennisCdpId
    )

    // Dennis redeems 20 EBTC
    // Don't pay for gas, as it makes it easier to calculate the received Ether
    const redemptionTx = await cdpManager.redeemCollateral(
      redemptionAmount,
      firstRedemptionHint,
      upperPartialRedemptionHint,
      lowerPartialRedemptionHint,
      partialRedemptionHintNICR,
      0, th._100pct,
      {
        from: dennis,
        gasPrice: GAS_PRICE
      }
    )

    const feeCollShares = th.getEmittedRedemptionValues(redemptionTx)[3]

    const alice_Cdp_After = await cdpManager.Cdps(_aliceCdpId)
    const bob_Cdp_After = await cdpManager.Cdps(_bobCdpId)
    const carol_Cdp_After = await cdpManager.Cdps(_carolCdpId)

    const alice_debt_After = alice_Cdp_After[0].toString()
    const bob_debt_After = bob_Cdp_After[0].toString()
    const carol_debt_After = carol_Cdp_After[0].toString()

    /* check that Dennis' redeemed 20 EBTC has been cancelled with debt from Bobs's Cdp (8) and Carol's Cdp (10).
    The remaining lot (2) is sent to Alice's Cdp, who had the best ICR.
    It leaves her with (3) EBTC debt + 50 for gas compensation. */
    th.assertIsApproximatelyEqual(alice_debt_After, A_totalDebt.sub(partialRedemptionAmount))
    assert.equal(bob_debt_After, '0')
    assert.equal(carol_debt_After, '0')

    const dennis_ETHBalance_After = toBN(await contracts.collateral.balanceOf(dennis))
    const receivedETH = dennis_ETHBalance_After.sub(dennis_ETHBalance_Before)

    const expectedTotalCollDrawn = redemptionAmount.mul(mv._1e18BN).div(price) // convert redemptionAmount EBTC to collateral at given price
    const expectedReceivedETH = expectedTotalCollDrawn.sub(toBN(feeCollShares))
    
    // console.log("*********************************************************************************")
    // console.log("feeCollShares: " + feeCollShares)
    // console.log("dennis_ETHBalance_Before: " + dennis_ETHBalance_Before)
    // console.log("GAS_USED: " + th.gasUsed(redemptionTx))
    // console.log("dennis_ETHBalance_After: " + dennis_ETHBalance_After)
    // console.log("expectedTotalCollDrawn: " + expectedTotalCollDrawn)
    // console.log("recived  : " + receivedETH)
    // console.log("expected : " + expectedReceivedETH)
    // console.log("wanted :   " + expectedReceivedETH.sub(toBN(GAS_PRICE)))
    // console.log("*********************************************************************************")
    th.assertIsApproximatelyEqual(expectedReceivedETH, receivedETH)

    const dennis_EBTCBalance_After = (await ebtcToken.balanceOf(dennis)).toString()
    assert.equal(dennis_EBTCBalance_After, dennis_EBTCBalance_Before.sub(redemptionAmount))
  })

  it('redeemCollateral(): with invalid first hint, zero address', async () => {
    // --- SETUP ---
    const { totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(310, 16)), extraEBTCAmount: dec(10, 18), extraParams: { from: alice } })
    const { netDebt: B_netDebt } = await openCdp({ ICR: toBN(dec(290, 16)), extraEBTCAmount: dec(8, 18), extraParams: { from: bob } })
    const { netDebt: C_netDebt } = await openCdp({ ICR: toBN(dec(250, 16)), extraEBTCAmount: dec(10, 18), extraParams: { from: carol } })
    const partialRedemptionAmount = toBN(2)
    const redemptionAmount = C_netDebt.add(B_netDebt).add(partialRedemptionAmount)
    // start Dennis with a high ICR
    await _signer.sendTransaction({ to: dennis, value: ethers.utils.parseEther("28200")});
    await openCdp({ ICR: toBN(dec(100, 18)), extraEBTCAmount: redemptionAmount, extraParams: { from: dennis } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);

    const dennis_ETHBalance_Before = toBN(await contracts.collateral.balanceOf(dennis))

    const dennis_EBTCBalance_Before = await ebtcToken.balanceOf(dennis)

    const price = await priceFeed.getPrice()

    // --- TEST ---
    await th.syncTwapSystemDebt(contracts, ethers.provider);

    // Find hints for redeeming 20 EBTC
    const {
      firstRedemptionHint,
      partialRedemptionHintNICR
    } = await hintHelpers.getRedemptionHints(redemptionAmount, price, 0)

    // We don't need to use getApproxHint for this test, since it's not the subject of this
    // test case, and the list is very small, so the correct position is quickly found
    const { 0: upperPartialRedemptionHint, 1: lowerPartialRedemptionHint } = await sortedCdps.findInsertPosition(
      partialRedemptionHintNICR,
      _dennisCdpId,
      _dennisCdpId
    )

    // Dennis redeems 20 EBTC
    // Don't pay for gas, as it makes it easier to calculate the received Ether
    const redemptionTx = await cdpManager.redeemCollateral(
      redemptionAmount,
      th.DUMMY_BYTES32, // invalid first hint
      upperPartialRedemptionHint,
      lowerPartialRedemptionHint,
      partialRedemptionHintNICR,
      0, th._100pct,
      {
        from: dennis,
        gasPrice: GAS_PRICE 
      }
    )

    const feeCollShares = th.getEmittedRedemptionValues(redemptionTx)[3]

    const alice_Cdp_After = await cdpManager.Cdps(_aliceCdpId)
    const bob_Cdp_After = await cdpManager.Cdps(_bobCdpId)
    const carol_Cdp_After = await cdpManager.Cdps(_carolCdpId)

    const alice_debt_After = alice_Cdp_After[0].toString()
    const bob_debt_After = bob_Cdp_After[0].toString()
    const carol_debt_After = carol_Cdp_After[0].toString()

    /* check that Dennis' redeemed 20 EBTC has been cancelled with debt from Bobs's Cdp (8) and Carol's Cdp (10).
    The remaining lot (2) is sent to Alice's Cdp, who had the best ICR.
    It leaves her with (3) EBTC debt + 50 for gas compensation. */
    th.assertIsApproximatelyEqual(alice_debt_After, A_totalDebt.sub(partialRedemptionAmount))
    assert.equal(bob_debt_After, '0')
    assert.equal(carol_debt_After, '0')

    const dennis_ETHBalance_After = toBN(await contracts.collateral.balanceOf(dennis))
    const receivedETH = dennis_ETHBalance_After.sub(dennis_ETHBalance_Before)

    const expectedTotalCollDrawn = redemptionAmount.mul(mv._1e18BN).div(price) // convert redemptionAmount EBTC to collateral at given price
    const expectedReceivedETH = expectedTotalCollDrawn.sub(toBN(feeCollShares))

    th.assertIsApproximatelyEqual(expectedReceivedETH, receivedETH)

    const dennis_EBTCBalance_After = (await ebtcToken.balanceOf(dennis)).toString()
    assert.equal(dennis_EBTCBalance_After, dennis_EBTCBalance_Before.sub(redemptionAmount))
  })

  it('redeemCollateral(): with invalid first hint, non-existent cdp', async () => {
    // --- SETUP ---
    const { totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(310, 16)), extraEBTCAmount: dec(10, 18), extraParams: { from: alice } })
    const { netDebt: B_netDebt } = await openCdp({ ICR: toBN(dec(290, 16)), extraEBTCAmount: dec(8, 18), extraParams: { from: bob } })
    const { netDebt: C_netDebt } = await openCdp({ ICR: toBN(dec(250, 16)), extraEBTCAmount: dec(10, 18), extraParams: { from: carol } })
    const partialRedemptionAmount = toBN(2)
    const redemptionAmount = C_netDebt.add(B_netDebt).add(partialRedemptionAmount)
    // start Dennis with a high ICR
    await _signer.sendTransaction({ to: dennis, value: ethers.utils.parseEther("30000")});
    await openCdp({ ICR: toBN(dec(100, 18)), extraEBTCAmount: redemptionAmount, extraParams: { from: dennis } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);

    const dennis_ETHBalance_Before = toBN(await contracts.collateral.balanceOf(dennis))

    const dennis_EBTCBalance_Before = await ebtcToken.balanceOf(dennis)

    const price = await priceFeed.getPrice()

    // --- TEST ---
    await th.syncTwapSystemDebt(contracts, ethers.provider);

    // Find hints for redeeming 20 EBTC
    const {
      firstRedemptionHint,
      partialRedemptionHintNICR
    } = await hintHelpers.getRedemptionHints(redemptionAmount, price, 0)

    // We don't need to use getApproxHint for this test, since it's not the subject of this
    // test case, and the list is very small, so the correct position is quickly found
    const { 0: upperPartialRedemptionHint, 1: lowerPartialRedemptionHint } = await sortedCdps.findInsertPosition(
      partialRedemptionHintNICR,
      _dennisCdpId,
      _dennisCdpId
    )



    // Dennis redeems 20 EBTC
    // Don't pay for gas, as it makes it easier to calculate the received Ether
    const redemptionTx = await cdpManager.redeemCollateral(
      redemptionAmount,
      th.DUMMY_BYTES32, // invalid first hint, it doesn’t have a cdp
      upperPartialRedemptionHint,
      lowerPartialRedemptionHint,
      partialRedemptionHintNICR,
      0, th._100pct,
      {
        from: dennis,
        gasPrice: GAS_PRICE
      }
    )

    const feeCollShares = th.getEmittedRedemptionValues(redemptionTx)[3]

    const alice_Cdp_After = await cdpManager.Cdps(_aliceCdpId)
    const bob_Cdp_After = await cdpManager.Cdps(_bobCdpId)
    const carol_Cdp_After = await cdpManager.Cdps(_carolCdpId)

    const alice_debt_After = alice_Cdp_After[0].toString()
    const bob_debt_After = bob_Cdp_After[0].toString()
    const carol_debt_After = carol_Cdp_After[0].toString()

    /* check that Dennis' redeemed 20 EBTC has been cancelled with debt from Bobs's Cdp (8) and Carol's Cdp (10).
    The remaining lot (2) is sent to Alice's Cdp, who had the best ICR.
    It leaves her with (3) EBTC debt + 50 for gas compensation. */
    th.assertIsApproximatelyEqual(alice_debt_After, A_totalDebt.sub(partialRedemptionAmount))
    assert.equal(bob_debt_After, '0')
    assert.equal(carol_debt_After, '0')

    const dennis_ETHBalance_After = toBN(await contracts.collateral.balanceOf(dennis))
    const receivedETH = dennis_ETHBalance_After.sub(dennis_ETHBalance_Before)

    const expectedTotalCollDrawn = redemptionAmount.mul(mv._1e18BN).div(price) // convert redemptionAmount EBTC to collateral at given price
    const expectedReceivedETH = expectedTotalCollDrawn.sub(toBN(feeCollShares))

    th.assertIsApproximatelyEqual(expectedReceivedETH, receivedETH)

    const dennis_EBTCBalance_After = (await ebtcToken.balanceOf(dennis)).toString()
    assert.equal(dennis_EBTCBalance_After, dennis_EBTCBalance_Before.sub(redemptionAmount))
  })

  it('redeemCollateral(): with invalid first hint, cdp below MCR', async () => {
    // --- SETUP ---
    const { totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(310, 16)), extraEBTCAmount: dec(10, 18), extraParams: { from: alice } })
    const { netDebt: B_netDebt } = await openCdp({ ICR: toBN(dec(290, 16)), extraEBTCAmount: dec(8, 18), extraParams: { from: bob } })
    const { netDebt: C_netDebt } = await openCdp({ ICR: toBN(dec(250, 16)), extraEBTCAmount: dec(10, 18), extraParams: { from: carol } })
    const partialRedemptionAmount = toBN(2)
    const redemptionAmount = C_netDebt.add(B_netDebt).add(partialRedemptionAmount)
    // start Dennis with a high ICR
    await _signer.sendTransaction({ to: dennis, value: ethers.utils.parseEther("20000")});
    await openCdp({ ICR: toBN(dec(100, 18)), extraEBTCAmount: redemptionAmount, extraParams: { from: dennis } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);

    const dennis_ETHBalance_Before = toBN(await contracts.collateral.balanceOf(dennis))

    const dennis_EBTCBalance_Before = await ebtcToken.balanceOf(dennis)

    const price = await priceFeed.getPrice()

    // Increase price to start Erin, and decrease it again so its ICR is under MCR
    await priceFeed.setPrice(price.mul(toBN(2)))
    await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: erin } })
    let _erinCdpId = await sortedCdps.cdpOfOwnerByIndex(erin, 0);
    await priceFeed.setPrice(price)


    // --- TEST ---
    await th.syncTwapSystemDebt(contracts, ethers.provider);

    // Find hints for redeeming 20 EBTC
    const {
      firstRedemptionHint,
      partialRedemptionHintNICR
    } = await hintHelpers.getRedemptionHints(redemptionAmount, price, 0)

    // We don't need to use getApproxHint for this test, since it's not the subject of this
    // test case, and the list is very small, so the correct position is quickly found
    const { 0: upperPartialRedemptionHint, 1: lowerPartialRedemptionHint } = await sortedCdps.findInsertPosition(
      partialRedemptionHintNICR,
      _dennisCdpId,
      _dennisCdpId
    )



    // Dennis redeems 20 EBTC
    // Don't pay for gas, as it makes it easier to calculate the received Ether
    const redemptionTx = await cdpManager.redeemCollateral(
      redemptionAmount,
      _erinCdpId, // invalid cdp, below MCR
      upperPartialRedemptionHint,
      lowerPartialRedemptionHint,
      partialRedemptionHintNICR,
      0, th._100pct,
      {
        from: dennis,
        gasPrice: GAS_PRICE
      }
    )

    const feeCollShares = th.getEmittedRedemptionValues(redemptionTx)[3]

    const alice_Cdp_After = await cdpManager.Cdps(_aliceCdpId)
    const bob_Cdp_After = await cdpManager.Cdps(_bobCdpId)
    const carol_Cdp_After = await cdpManager.Cdps(_carolCdpId)

    const alice_debt_After = alice_Cdp_After[0].toString()
    const bob_debt_After = bob_Cdp_After[0].toString()
    const carol_debt_After = carol_Cdp_After[0].toString()

    /* check that Dennis' redeemed 20 EBTC has been cancelled with debt from Bobs's Cdp (8) and Carol's Cdp (10).
    The remaining lot (2) is sent to Alice's Cdp, who had the best ICR.
    It leaves her with (3) EBTC debt + 50 for gas compensation. */
    th.assertIsApproximatelyEqual(alice_debt_After, A_totalDebt.sub(partialRedemptionAmount))
    assert.equal(bob_debt_After, '0')
    assert.equal(carol_debt_After, '0')

    const dennis_ETHBalance_After = toBN(await contracts.collateral.balanceOf(dennis))
    const receivedETH = dennis_ETHBalance_After.sub(dennis_ETHBalance_Before)

    const expectedTotalCollDrawn = redemptionAmount.mul(mv._1e18BN).div(price) // convert redemptionAmount EBTC to collateral at given price
    const expectedReceivedETH = expectedTotalCollDrawn.sub(toBN(feeCollShares))

    th.assertIsApproximatelyEqual(expectedReceivedETH, receivedETH)

    const dennis_EBTCBalance_After = (await ebtcToken.balanceOf(dennis)).toString()
    assert.equal(dennis_EBTCBalance_After, dennis_EBTCBalance_Before.sub(redemptionAmount))
  })

  it('redeemCollateral(): ends the redemption sequence when the token redemption request has been filled', async () => {
    // --- SETUP --- 
    await openCdp({ ICR: toBN(dec(100, 18)), extraParams: { from: whale } })

    // Alice, Bob, Carol, Dennis, Erin open cdps
    const { netDebt: A_debt } = await openCdp({ ICR: toBN(dec(290, 16)), extraEBTCAmount: dec(20, 18), extraParams: { from: alice } })
    const { netDebt: B_debt } = await openCdp({ ICR: toBN(dec(290, 16)), extraEBTCAmount: dec(20, 18), extraParams: { from: bob } })
    const { netDebt: C_debt } = await openCdp({ ICR: toBN(dec(290, 16)), extraEBTCAmount: dec(20, 18), extraParams: { from: carol } })
    const redemptionAmount = A_debt.add(B_debt).add(C_debt)
    const { totalDebt: D_totalDebt, collateral: D_coll } = await openCdp({ ICR: toBN(dec(300, 16)), extraEBTCAmount: dec(10, 18), extraParams: { from: dennis } })
    const { totalDebt: E_totalDebt, collateral: E_coll } = await openCdp({ ICR: toBN(dec(300, 16)), extraEBTCAmount: dec(10, 18), extraParams: { from: erin } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);
    let _erinCdpId = await sortedCdps.cdpOfOwnerByIndex(erin, 0);

    // --- TEST --- 
    await th.syncTwapSystemDebt(contracts, ethers.provider);

    // open cdp from redeemer.  Redeemer has highest ICR (100ETH, 100 EBTC), 20000%
    await _signer.sendTransaction({ to: flyn, value: ethers.utils.parseEther("340000")});
    const { ebtcAmount: F_ebtcAmount } = await openCdp({ ICR: toBN(dec(200, 18)), extraEBTCAmount: redemptionAmount.mul(toBN(2)), extraParams: { from: flyn } })
    let _flynCdpId = await sortedCdps.cdpOfOwnerByIndex(flyn, 0);



    // Flyn redeems collateral
    await cdpManager.redeemCollateral(redemptionAmount, _aliceCdpId, _aliceCdpId, _aliceCdpId, 0, 0, th._100pct, { from: flyn })

    // Check Flyn's redemption has reduced his balance from 100 to (100-60) = 40 EBTC
    const flynBalance = await ebtcToken.balanceOf(flyn)
    th.assertIsApproximatelyEqual(flynBalance, F_ebtcAmount.sub(redemptionAmount))

    // Check debt of Alice, Bob, Carol
    const alice_Debt = await cdpManager.getCdpDebt(_aliceCdpId)
    const bob_Debt = await cdpManager.getCdpDebt(_bobCdpId)
    const carol_Debt = await cdpManager.getCdpDebt(_carolCdpId)

    assert.equal(alice_Debt, 0)
    assert.equal(bob_Debt, 0)
    assert.equal(carol_Debt, 0)

    // check Alice, Bob and Carol cdps are closed by redemption
    const alice_Status = await cdpManager.getCdpStatus(_aliceCdpId)
    const bob_Status = await cdpManager.getCdpStatus(_bobCdpId)
    const carol_Status = await cdpManager.getCdpStatus(_carolCdpId)
    assert.equal(alice_Status, 4)
    assert.equal(bob_Status, 4)
    assert.equal(carol_Status, 4)

    // check debt and coll of Dennis, Erin has not been impacted by redemption
    const dennis_Debt = await cdpManager.getCdpDebt(_dennisCdpId)
    const erin_Debt = await cdpManager.getCdpDebt(_erinCdpId)

    th.assertIsApproximatelyEqual(dennis_Debt, D_totalDebt)
    th.assertIsApproximatelyEqual(erin_Debt, E_totalDebt)

    const dennis_Coll = await cdpManager.getCdpCollShares(_dennisCdpId)
    const erin_Coll = await cdpManager.getCdpCollShares(_erinCdpId)

    assert.equal(dennis_Coll.toString(), D_coll.toString())
    assert.equal(erin_Coll.toString(), E_coll.toString())
  })

  it('redeemCollateral(): ends the redemption sequence when max iterations have been reached', async () => {
    // --- SETUP --- 
    await openCdp({ ICR: toBN(dec(100, 18)), extraParams: { from: whale } })

    // Alice, Bob, Carol open cdps with equal collateral ratio
    const { netDebt: A_debt } = await openCdp({ ICR: toBN(dec(286, 16)), extraEBTCAmount: dec(20, 18), extraParams: { from: alice } })
    const { netDebt: B_debt } = await openCdp({ ICR: toBN(dec(286, 16)), extraEBTCAmount: dec(20, 18), extraParams: { from: bob } })
    const { netDebt: C_debt, totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(286, 16)), extraEBTCAmount: dec(20, 18), extraParams: { from: carol } })
    const redemptionAmount = A_debt.add(B_debt)
    const attemptedRedemptionAmount = redemptionAmount.add(C_debt)

    // --- TEST --- 
    await th.syncTwapSystemDebt(contracts, ethers.provider);

    // open cdp from redeemer.  Redeemer has highest ICR (100ETH, 100 EBTC), 20000%
    await _signer.sendTransaction({ to: flyn, value: ethers.utils.parseEther("240000")});
    const { ebtcAmount: F_ebtcAmount } = await openCdp({ ICR: toBN(dec(200, 18)), extraEBTCAmount: redemptionAmount.mul(toBN(2)), extraParams: { from: flyn } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);



    // Flyn redeems collateral with only two iterations
    await cdpManager.redeemCollateral(attemptedRedemptionAmount, _aliceCdpId, _aliceCdpId, _aliceCdpId, 0, 2, th._100pct, { from: flyn })

    // Check Flyn's redemption has reduced his balance from 100 to (100-40) = 60 EBTC
    const flynBalance = (await ebtcToken.balanceOf(flyn)).toString()
    th.assertIsApproximatelyEqual(flynBalance, F_ebtcAmount.sub(redemptionAmount))

    // Check debt of Alice, Bob, Carol
    const alice_Debt = await cdpManager.getCdpDebt(_aliceCdpId)
    const bob_Debt = await cdpManager.getCdpDebt(_bobCdpId)
    const carol_Debt = await cdpManager.getCdpDebt(_carolCdpId)

    assert.equal(alice_Debt, 0)
    assert.equal(bob_Debt, 0)
    th.assertIsApproximatelyEqual(carol_Debt, C_totalDebt)

    // check Alice and Bob cdps are closed, but Carol is not
    const alice_Status = await cdpManager.getCdpStatus(_aliceCdpId)
    const bob_Status = await cdpManager.getCdpStatus(_bobCdpId)
    const carol_Status = await cdpManager.getCdpStatus(_carolCdpId)
    assert.equal(alice_Status, 4)
    assert.equal(bob_Status, 4)
    assert.equal(carol_Status, 1)
  })

  it("redeemCollateral(): performs partial redemption if resultant debt is > minimum net debt", async () => {
    await contracts.collateral.deposit({from: A, value: dec(1000, 'ether')});
    await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: A});
    await contracts.collateral.deposit({from: B, value: dec(1000, 'ether')});
    await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: B});
    await contracts.collateral.deposit({from: C, value: dec(1000, 'ether')});
    await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: C});
    await borrowerOperations.openCdp(await getOpenCdpEBTCAmount(dec(1, 18)), A, A, dec(1000, 'ether'), { from: A })
    await borrowerOperations.openCdp(await getOpenCdpEBTCAmount(dec(2, 18)), B, B, dec(1000, 'ether'), { from: B })
    await borrowerOperations.openCdp(await getOpenCdpEBTCAmount(dec(3, 18)), C, C, dec(1000, 'ether'), { from: C })
    let _aCdpId = await sortedCdps.cdpOfOwnerByIndex(A, 0);
    let _bCdpId = await sortedCdps.cdpOfOwnerByIndex(B, 0);
    let _cCdpId = await sortedCdps.cdpOfOwnerByIndex(C, 0);
    const A_debtBefore = await cdpManager.getCdpDebt(_aCdpId)

    // A and C send all their tokens to B
    await ebtcToken.transfer(B, await ebtcToken.balanceOf(A), {from: A})
    await ebtcToken.transfer(B, await ebtcToken.balanceOf(C), {from: C})
    
    await cdpManager.setBaseRate(0) 
    await th.syncTwapSystemDebt(contracts, ethers.provider);



    const EBTCRedemption = dec(5, 18)
    await th.redeemCollateralAndGetTxObject(B, contracts, EBTCRedemption, GAS_PRICE, th._100pct)
    
    // Check B, C closed and A remains active
    assert.isTrue(await sortedCdps.contains(_aCdpId))
    assert.isFalse(await sortedCdps.contains(_bCdpId))
    assert.isFalse(await sortedCdps.contains(_cCdpId))

    const A_debt = await cdpManager.getCdpDebt(_aCdpId)
    await th.assertIsApproximatelyEqual(A_debt, A_debtBefore, 1000)
  })

  it("redeemCollateral(): doesn't perform partial redemption if resultant debt would be < minimum net debt", async () => {
    await contracts.collateral.deposit({from: A, value: dec(1000, 'ether')});
    await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: A});
    await contracts.collateral.deposit({from: B, value: dec(1000, 'ether')});
    await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: B});
    await contracts.collateral.deposit({from: C, value: dec(1000, 'ether')});
    await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: C});
    await borrowerOperations.openCdp(await getOpenCdpEBTCAmount(dec(10, 18)), A, A, dec(1000, 'ether'), { from: A })
    await borrowerOperations.openCdp(await getOpenCdpEBTCAmount(dec(5, 18)), B, B, dec(1000, 'ether'), { from: B })
    await borrowerOperations.openCdp(await getOpenCdpEBTCAmount(dec(3, 18)), C, C, dec(1000, 'ether'), { from: C })
    let _aCdpId = await sortedCdps.cdpOfOwnerByIndex(A, 0);
    let _bCdpId = await sortedCdps.cdpOfOwnerByIndex(B, 0);
    let _cCdpId = await sortedCdps.cdpOfOwnerByIndex(C, 0);

    // A and C send all their tokens to B
    await ebtcToken.transfer(B, await ebtcToken.balanceOf(A), {from: A})
    await ebtcToken.transfer(B, await ebtcToken.balanceOf(C), {from: C})

    await cdpManager.setBaseRate(0) 
    await th.syncTwapSystemDebt(contracts, ethers.provider);



    const EBTCRedemption = dec(10, 18)
    await th.redeemCollateralAndGetTxObject(B, contracts, EBTCRedemption, GAS_PRICE, th._100pct)
    
    // Check B, C closed and A remains active
    assert.isFalse(await sortedCdps.contains(_aCdpId))
    assert.isTrue(await sortedCdps.contains(_bCdpId))
    assert.isTrue(await sortedCdps.contains(_cCdpId))

    const A_debt = await cdpManager.getCdpDebt(_cCdpId)
    await th.assertIsApproximatelyEqual(A_debt, '2999999999999999999')
  })

  it('redeemCollateral(): doesnt perform the final partial redemption in the sequence if the hint is out-of-date', async () => {
    // --- SETUP ---
    const { totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(363, 16)), extraEBTCAmount: dec(5, 18), extraParams: { from: alice } })
    const { netDebt: B_netDebt } = await openCdp({ ICR: toBN(dec(344, 16)), extraEBTCAmount: dec(8, 18), extraParams: { from: bob } })
    const { netDebt: C_netDebt } = await openCdp({ ICR: toBN(dec(333, 16)), extraEBTCAmount: dec(10, 18), extraParams: { from: carol } })
	
    const partialRedemptionAmount = toBN(2)
    const fullfilledRedemptionAmount = C_netDebt.add(B_netDebt)
    const redemptionAmount = fullfilledRedemptionAmount.add(partialRedemptionAmount)

    await _signer.sendTransaction({ to: dennis, value: ethers.utils.parseEther("20000")});
    await openCdp({ ICR: toBN(dec(100, 18)), extraEBTCAmount: redemptionAmount, extraParams: { from: dennis } })
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);

    const dennis_ETHBalance_Before = toBN(await contracts.collateral.balanceOf(dennis))

    const dennis_EBTCBalance_Before = await ebtcToken.balanceOf(dennis)

    const price = await priceFeed.getPrice()

    // --- TEST --- 
    await th.syncTwapSystemDebt(contracts, ethers.provider);

    const {
      firstRedemptionHint,
      partialRedemptionHintNICR
    } = await hintHelpers.getRedemptionHints(redemptionAmount, price, 0)

    const { 0: upperPartialRedemptionHint, 1: lowerPartialRedemptionHint } = await sortedCdps.findInsertPosition(
      partialRedemptionHintNICR,
      _dennisCdpId,
      _dennisCdpId
    )

    const frontRunRedepmtion = toBN(dec(1, 18))
    // Oops, another transaction gets in the way
    {
      const {
        firstRedemptionHint,
        partialRedemptionHintNICR
      } = await hintHelpers.getRedemptionHints(dec(1, 18), price, 0)

      const { 0: upperPartialRedemptionHint, 1: lowerPartialRedemptionHint } = await sortedCdps.findInsertPosition(
        partialRedemptionHintNICR,
        _dennisCdpId,
        _dennisCdpId
      )

      // Alice redeems 1 EBTC from Carol's Cdp
      await cdpManager.redeemCollateral(
        frontRunRedepmtion,
        firstRedemptionHint,
        upperPartialRedemptionHint,
        lowerPartialRedemptionHint,
        partialRedemptionHintNICR,
        0, th._100pct,
        { from: alice }
      )
    }

    // Dennis tries to redeem 20 EBTC
    const redemptionTx = await cdpManager.redeemCollateral(
      redemptionAmount,
      firstRedemptionHint,
      upperPartialRedemptionHint,
      lowerPartialRedemptionHint,
      partialRedemptionHintNICR,
      0, th._100pct,
      {
        from: dennis,
        gasPrice: GAS_PRICE
      }
    )

    const redeemFee = th.getEmittedRedemptionValues(redemptionTx)[3]

    // Since Alice already redeemed 1 EBTC from Carol's Cdp, Dennis was  able to redeem:
    //  - 9 EBTC from Carol's
    //  - 8 EBTC from Bob's
    // for a total of 17 EBTC.

    // Dennis calculated his hint for redeeming 2 EBTC from Alice's Cdp, but after Alice's transaction
    // got in the way, he would have needed to redeem 3 EBTC to fully complete his redemption of 20 EBTC.
    // This would have required a different hint, therefore he ended up with a partial redemption.

    const dennis_ETHBalance_After = toBN(await contracts.collateral.balanceOf(dennis))
    const receivedETH = dennis_ETHBalance_After.sub(dennis_ETHBalance_Before)

    // Expect only 17 worth of ETH drawn
    const expectedTotalCollDrawn = fullfilledRedemptionAmount.sub(frontRunRedepmtion).mul(mv._1e18BN).div(price) // redempted EBTC converted to collateral at given price
    const expectedReceivedETH = expectedTotalCollDrawn.sub(redeemFee)

    th.assertIsApproximatelyEqual(expectedReceivedETH, receivedETH)

    const dennis_EBTCBalance_After = (await ebtcToken.balanceOf(dennis)).toString()
    th.assertIsApproximatelyEqual(dennis_EBTCBalance_After, dennis_EBTCBalance_Before.sub(fullfilledRedemptionAmount.sub(frontRunRedepmtion)))
  })

  // active debt cannot be zero, as there’s a positive min debt enforced, and at least a cdp must exist
  it.skip("redeemCollateral(): can redeem if there is zero active debt but non-zero debt in DefaultPool", async () => {
    // --- SETUP ---

    const amount = await getOpenCdpEBTCAmount(dec(110, 18))
    await openCdp({ ICR: toBN(dec(20, 18)), extraParams: { from: alice } })
    let _alicCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    await openCdp({ ICR: toBN(dec(133, 16)), extraEBTCAmount: amount, extraParams: { from: bob } })

    await ebtcToken.transfer(carol, amount, { from: bob })

    const price = dec(3714, 13);
    await priceFeed.setPrice(price)

    // Liquidate Bob's Cdp
    await cdpManager.liquidateCdps(1)

    // --- TEST --- 

    const carol_ETHBalance_Before = toBN(await web3.eth.getBalance(carol))



    const redemptionTx = await cdpManager.redeemCollateral(
      amount,
      _alicCdpId,
      th.DUMMY_BYTES32,
      th.DUMMY_BYTES32,
      '10367038690476190477',
      0,
      th._100pct,
      {
        from: carol,
        gasPrice: GAS_PRICE
      }
    )

    const feeCollShares = th.getEmittedRedemptionValues(redemptionTx)[3]

    const carol_ETHBalance_After = toBN(await web3.eth.getBalance(carol))

    const expectedTotalCollDrawn = toBN(amount).div(price) // convert 100 EBTC to collateral at given price
    const expectedReceivedETH = expectedTotalCollDrawn.sub(feeCollShares)

    const receivedETH = carol_ETHBalance_After.sub(carol_ETHBalance_Before)
    assert.isTrue(expectedReceivedETH.eq(receivedETH))

    const carol_EBTCBalance_After = (await ebtcToken.balanceOf(carol)).toString()
    assert.equal(carol_EBTCBalance_After, '0')
  })

  it("redeemCollateral(): doesn't touch Cdps with ICR < 110%", async () => {
    // --- SETUP ---

    const { netDebt: A_debt } = await openCdp({ ICR: toBN(dec(13, 18)), extraParams: { from: alice } })
    let _alicCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    const { ebtcAmount: B_ebtcAmount, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(133, 16)), extraEBTCAmount: A_debt, extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);

    await ebtcToken.transfer(carol, B_ebtcAmount, { from: bob })

    // Put Bob's Cdp below 110% ICR
    const price = dec(3714, 13);
    await priceFeed.setPrice(price)
	
    await openCdp({ ICR: toBN(dec(10, 18)), extraEBTCAmount: A_debt, extraParams: { from: carol } })

    // --- TEST --- 
    await th.syncTwapSystemDebt(contracts, ethers.provider);



    await cdpManager.redeemCollateral(
      A_debt,
      _alicCdpId,
      th.DUMMY_BYTES32,
      th.DUMMY_BYTES32,
      0,
      0,
      th._100pct,
      { from: carol }
    );

    // Alice's Cdp was cleared of debt
    const { debt: alice_Debt_After } = await cdpManager.Cdps(_alicCdpId)
    assert.equal(alice_Debt_After, '0')

    // Bob's Cdp was left untouched
    const { debt: bob_Debt_After } = await cdpManager.Cdps(_bobCdpId)
    th.assertIsApproximatelyEqual(bob_Debt_After, B_totalDebt)
  });

  xit("redeemCollateral(): finds the last Cdp with ICR == 110% even if there is more than one", async () => {
    // --- SETUP ---
    const amount1 = toBN(dec(100, 18))
    const { totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(196, 16)), extraEBTCAmount: amount1, extraParams: { from: alice } })
    const { totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: amount1, extraParams: { from: bob } })
    const { totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: amount1, extraParams: { from: carol} } )
    const redemptionAmount = C_totalDebt.add(B_totalDebt).add(A_totalDebt);
    await _signer.sendTransaction({ to: dennis, value: ethers.utils.parseEther("3000")});
    const { totalDebt: D_totalDebt } = await openCdp({ ICR: toBN(dec(195, 16)), extraEBTCAmount: redemptionAmount, extraParams: { from: dennis } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);

    // This will put Dennis slightly below 110%, and everyone else exactly at 110%
    await priceFeed.setPrice(dec(3900, 13));

    const orderOfCdps = [];
    let current = await sortedCdps.getFirst();

    while (current !== th.DUMMY_BYTES32) {
      orderOfCdps.push((await sortedCdps.existCdpOwners(current)));
      current = await sortedCdps.getNext(current);
    }

    assert.deepEqual(orderOfCdps, [carol, bob, alice, dennis]);

    await openCdp({ ICR: toBN(dec(100, 18)), extraEBTCAmount: dec(10, 18), extraParams: { from: whale } })



    const tx = await cdpManager.redeemCollateral(
      redemptionAmount,
      _carolCdpId, // try to trick redeemCollateral by passing a hint that doesn't exactly point to the last Cdp with ICR == 110% (which would be Alice's)
      th.DUMMY_BYTES32,
      th.DUMMY_BYTES32,
      0,
      0,
      th._100pct,
      { from: dennis }
    )
    
    const { debt: alice_Debt_After } = await cdpManager.Cdps(_aliceCdpId)
    console.log(redemptionAmount.toString())
    console.log(D_totalDebt.toString())
    console.log(alice_Debt_After.toString())
    assert.equal(alice_Debt_After, '0')

    const { debt: bob_Debt_After } = await cdpManager.Cdps(_bobCdpId)
    assert.equal(bob_Debt_After, '0')

    const { debt: carol_Debt_After } = await cdpManager.Cdps(_carolCdpId)
    assert.equal(carol_Debt_After, '0')

    const { debt: dennis_Debt_After } = await cdpManager.Cdps(_dennisCdpId)
    th.assertIsApproximatelyEqual(dennis_Debt_After, D_totalDebt)
  });

  it("redeemCollateral(): reverts when TCR < MCR", async () => {
    await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: bob } })
    await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: carol } })
    await openCdp({ ICR: toBN(dec(196, 16)), extraParams: { from: dennis } })

    // This will put Dennis slightly below 110%, and everyone else exactly at 110%
  
    await priceFeed.setPrice(dec(3900, 13));
    
    const TCR = (await th.getCachedTCR(contracts))
    assert.isTrue(TCR.lt(toBN('1100000000000000000')))



    await assertRevert(th.redeemCollateral(carol, contracts, 1, GAS_PRICE, dec(270, 18)), "CdpManager: Cannot redeem when TCR < MCR")
  });

  it("redeemCollateral(): reverts when argument _amount is 0", async () => {
    await openCdp({ ICR: toBN(dec(20, 18)), extraParams: { from: whale } })

    // Alice opens cdp and transfers 500EBTC to Erin, the would-be redeemer
    await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(500, 18), extraParams: { from: alice } })
    await ebtcToken.transfer(erin, dec(500, 18), { from: alice })

    // B, C and D open cdps
    await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: bob } })
    await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: carol } })
    await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: dennis } })



    // Erin attempts to redeem with _amount = 0
    const redemptionTxPromise = cdpManager.redeemCollateral(0, th.DUMMY_BYTES32, th.DUMMY_BYTES32, th.DUMMY_BYTES32, 0, 0, th._100pct, { from: erin })
    await assertRevert(redemptionTxPromise, "CdpManager: Amount must be greater than zero")
  })

  it("redeemCollateral(): reverts if max fee > 100%", async () => {
    await _signer.sendTransaction({ to: A, value: ethers.utils.parseEther("2000")});
    await _signer.sendTransaction({ to: B, value: ethers.utils.parseEther("2000")});
    await _signer.sendTransaction({ to: C, value: ethers.utils.parseEther("2000")});
    await _signer.sendTransaction({ to: D, value: ethers.utils.parseEther("2000")});
    await openCdp({ ICR: toBN(dec(400, 16)), extraEBTCAmount: dec(10, 18), extraParams: { from: A } })
    await openCdp({ ICR: toBN(dec(400, 16)), extraEBTCAmount: dec(20, 18), extraParams: { from: B } })
    await openCdp({ ICR: toBN(dec(400, 16)), extraEBTCAmount: dec(30, 18), extraParams: { from: C } })
    await openCdp({ ICR: toBN(dec(400, 16)), extraEBTCAmount: dec(40, 18), extraParams: { from: D } })



    await assertRevert(th.redeemCollateralAndGetTxObject(A, contracts, dec(10, 18), GAS_PRICE ,dec(2, 18)), "Max fee percentage must be between 0.5% and 100%")
    await assertRevert(th.redeemCollateralAndGetTxObject(A, contracts, dec(10, 18), GAS_PRICE, '1000000000000000001'), "Max fee percentage must be between 0.5% and 100%")
  })

  it("redeemCollateral(): reverts if max fee < 0.5%", async () => { 
    await _signer.sendTransaction({ to: A, value: ethers.utils.parseEther("2000")});
    await _signer.sendTransaction({ to: B, value: ethers.utils.parseEther("2000")});
    await _signer.sendTransaction({ to: C, value: ethers.utils.parseEther("2000")});
    await _signer.sendTransaction({ to: D, value: ethers.utils.parseEther("2000")});
    await openCdp({ ICR: toBN(dec(400, 16)), extraEBTCAmount: dec(10, 18), extraParams: { from: A } })
    await openCdp({ ICR: toBN(dec(400, 16)), extraEBTCAmount: dec(20, 18), extraParams: { from: B } })
    await openCdp({ ICR: toBN(dec(400, 16)), extraEBTCAmount: dec(30, 18), extraParams: { from: C } })
    await openCdp({ ICR: toBN(dec(400, 16)), extraEBTCAmount: dec(40, 18), extraParams: { from: D } })



    await assertRevert(th.redeemCollateralAndGetTxObject(A, contracts, 1, GAS_PRICE, dec(10, 18), 0), "Max fee percentage must be between 0.5% and 100%")
    await assertRevert(th.redeemCollateralAndGetTxObject(A, contracts, 1, GAS_PRICE, dec(10, 18), 1), "Max fee percentage must be between 0.5% and 100%")
    await assertRevert(th.redeemCollateralAndGetTxObject(A, contracts, 1, GAS_PRICE, dec(10, 18), '4999999999999999'), "Max fee percentage must be between 0.5% and 100%")
  })

  // Disabled as actual fee never exceeds 0.5%
  xit("redeemCollateral(): reverts if fee exceeds max fee percentage", async () => {
    await _signer.sendTransaction({ to: A, value: ethers.utils.parseEther("3000")});
    await _signer.sendTransaction({ to: B, value: ethers.utils.parseEther("3000")});
    await _signer.sendTransaction({ to: C, value: ethers.utils.parseEther("3000")});
    const { totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(400, 16)), extraEBTCAmount: dec(80, 18), extraParams: { from: A } })
    const { totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(400, 16)), extraEBTCAmount: dec(90, 18), extraParams: { from: B } })
    const { totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(400, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: C } })
    const expectedTotalSupply = A_totalDebt.add(B_totalDebt).add(C_totalDebt)

    // Check total EBTC supply
    const totalSupply = await ebtcToken.totalSupply()
    th.assertIsApproximatelyEqual(totalSupply, expectedTotalSupply)

    await cdpManager.setBaseRate(0) 



    // EBTC redemption is 27 USD: a redemption that incurs a fee of 27/(270 * 2) = 5%
    const attemptedEBTCRedemption = expectedTotalSupply.div(toBN(10))

    // Max fee is <5%
    const lessThan5pct = '49999999999999999'
    await assertRevert(th.redeemCollateralAndGetTxObject(A, contracts, attemptedEBTCRedemption, GAS_PRICE, lessThan5pct), "Fee exceeded provided maximum")
  
    await cdpManager.setBaseRate(0)  // artificially zero the baseRate
    
    // Max fee is 1%
    await assertRevert(th.redeemCollateralAndGetTxObject(A, contracts, attemptedEBTCRedemption, GAS_PRICE, dec(1, 16)), "Fee exceeded provided maximum")
  
    await cdpManager.setBaseRate(0)

     // Max fee is 3.754%
    await assertRevert(th.redeemCollateralAndGetTxObject(A, contracts, attemptedEBTCRedemption, GAS_PRICE, dec(3754, 13)), "Fee exceeded provided maximum")
  
    await cdpManager.setBaseRate(0)

    // Max fee is 0.5%
    await assertRevert(th.redeemCollateralAndGetTxObject(A, contracts, attemptedEBTCRedemption, GAS_PRICE, dec(5, 15)), "Fee exceeded provided maximum")
  })

  it.skip("redeemCollateral(): succeeds if fee is less than max fee percentage", async () => {
    const { totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(400, 16)), extraEBTCAmount: dec(9500, 18), extraParams: { from: A } })
    const { totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(395, 16)), extraEBTCAmount: dec(9000, 18), extraParams: { from: B } })
    const { totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(390, 16)), extraEBTCAmount: dec(10000, 18), extraParams: { from: C } })
    const expectedTotalSupply = A_totalDebt.add(B_totalDebt).add(C_totalDebt)

    // Check total EBTC supply
    const totalSupply = await ebtcToken.totalSupply()
    th.assertIsApproximatelyEqual(totalSupply, expectedTotalSupply)

    await cdpManager.setBaseRate(0) 



    // EBTC redemption fee with 10% of the supply will be 0.5% + 1/(10*2)
    const attemptedEBTCRedemption = expectedTotalSupply.div(toBN(10))

    // Attempt with maxFee > 5.5%
    const price = await priceFeed.getPrice()
    const ETHDrawn = attemptedEBTCRedemption.mul(mv._1e18BN).div(price)
    const slightlyMoreThanFee = (await cdpManager.getRedemptionFeeWithDecay(ETHDrawn))
    const tx1 = await th.redeemCollateralAndGetTxObject(A, contracts, attemptedEBTCRedemption, GAS_PRICE, slightlyMoreThanFee)
    assert.isTrue(tx1.receipt.status)

    await cdpManager.setBaseRate(0)  // Artificially zero the baseRate
    
    // Attempt with maxFee = 5.5%
    const exactSameFee = (await cdpManager.getRedemptionFeeWithDecay(ETHDrawn))
    const tx2 = await th.redeemCollateralAndGetTxObject(C, contracts, attemptedEBTCRedemption, GAS_PRICE, exactSameFee)
    assert.isTrue(tx2.receipt.status)

    await cdpManager.setBaseRate(0)

     // Max fee is 10%
    const tx3 = await th.redeemCollateralAndGetTxObject(B, contracts, attemptedEBTCRedemption, GAS_PRICE, dec(1, 17))
    assert.isTrue(tx3.receipt.status)

    await cdpManager.setBaseRate(0)

    // Max fee is 37.659%
    const tx4 = await th.redeemCollateralAndGetTxObject(A, contracts, attemptedEBTCRedemption, GAS_PRICE, dec(37659, 13))
    assert.isTrue(tx4.receipt.status)

    await cdpManager.setBaseRate(0)

    // Max fee is 100%
    const tx5 = await th.redeemCollateralAndGetTxObject(C, contracts, attemptedEBTCRedemption, GAS_PRICE, dec(1, 18))
    assert.isTrue(tx5.receipt.status)
  })

  it("redeemCollateral(): doesn't affect the Stability Pool deposits or ETH gain of redeemed-from cdps", async () => {
    await openCdp({ ICR: toBN(dec(20, 18)), extraParams: { from: whale } })

    // B, C, D, F open cdp
    await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("3000")});
    await _signer.sendTransaction({ to: carol, value: ethers.utils.parseEther("3000")});
    await _signer.sendTransaction({ to: dennis, value: ethers.utils.parseEther("3000")});
    await _signer.sendTransaction({ to: flyn, value: ethers.utils.parseEther("3000")});
    const { totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: bob } })
    const { totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(195, 16)), extraEBTCAmount: dec(200, 18), extraParams: { from: carol } })
    const { totalDebt: D_totalDebt } = await openCdp({ ICR: toBN(dec(190, 16)), extraEBTCAmount: dec(400, 18), extraParams: { from: dennis } })
    const { totalDebt: F_totalDebt } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: flyn } })

    const redemptionAmount = B_totalDebt.add(C_totalDebt).add(D_totalDebt).add(F_totalDebt)
    // Alice opens cdp and transfers EBTC to Erin, the would-be redeemer
    await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("9000")});
    await openCdp({ ICR: toBN(dec(300, 16)), extraEBTCAmount: redemptionAmount, extraParams: { from: alice } })
    await ebtcToken.transfer(erin, redemptionAmount, { from: alice })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);
    let _flynCdpId = await sortedCdps.cdpOfOwnerByIndex(flyn, 0);

    let price = await priceFeed.getPrice()
    const bob_ICR_before = await cdpManager.getCachedICR(_bobCdpId, price)
    const carol_ICR_before = await cdpManager.getCachedICR(_carolCdpId, price)
    const dennis_ICR_before = await cdpManager.getCachedICR(_dennisCdpId, price)

    // Price drops
    await priceFeed.setPrice(dec(3714, 13))

    assert.isTrue(await sortedCdps.contains(_flynCdpId))
    await th.syncTwapSystemDebt(contracts, ethers.provider);

    // Liquidate Flyn
    await debtToken.transfer(owner, (await debtToken.balanceOf(flyn)), {from: flyn});	 
    await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from: whale});
    await _signer.sendTransaction({ to: owner, value: ethers.utils.parseEther("2000")});
    const { totalDebt: Owner_totalDebt } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: owner } })
    await cdpManager.liquidate(_flynCdpId, {from: owner})
    assert.isFalse(await sortedCdps.contains(_flynCdpId))

    // Price bounces back, bringing B, C, D back above MCR
    await priceFeed.setPrice(dec(7428, 13))



    // Erin redeems EBTC
    await th.redeemCollateral(erin, contracts, redemptionAmount, GAS_PRICE, th._100pct)

    price = await priceFeed.getPrice()
    const bob_ICR_after = await cdpManager.getCachedICR(_bobCdpId, price)
    const carol_ICR_after = await cdpManager.getCachedICR(_carolCdpId, price)
    const dennis_ICR_after = await cdpManager.getCachedICR(_dennisCdpId, price)

    // Check ICR of B, C and D cdps has increased,i.e. they have been hit by redemptions
    assert.isTrue(bob_ICR_after.gte(bob_ICR_before))
    assert.isTrue(carol_ICR_after.gte(carol_ICR_before))
    assert.isTrue(dennis_ICR_after.gte(dennis_ICR_before))
  })

  it("redeemCollateral(): caller can redeem their entire EBTCToken balance", async () => {
    const { collateral: W_coll, totalDebt: W_totalDebt } = await openCdp({ ICR: toBN(dec(20, 18)), extraParams: { from: whale } })

    // Alice opens cdp and transfers 400 EBTC to Erin, the would-be redeemer
    const { collateral: A_coll, totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(300, 16)), extraEBTCAmount: dec(400, 18), extraParams: { from: alice } })
    await ebtcToken.transfer(erin, dec(400, 18), { from: alice })

    // Check Erin's balance before
    const erin_balance_before = await ebtcToken.balanceOf(erin)
    assert.equal(erin_balance_before, dec(400, 18))

    // B, C, D open cdp
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(300, 16)), extraEBTCAmount: dec(6, 18), extraParams: { from: bob } })
    const { collateral: C_coll, totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(300, 16)), extraEBTCAmount: dec(12, 18), extraParams: { from: carol } })
    const { collateral: D_coll, totalDebt: D_totalDebt } = await openCdp({ ICR: toBN(dec(500, 16)), extraEBTCAmount: dec(12, 18), extraParams: { from: dennis } })

    const totalDebt = W_totalDebt.add(A_totalDebt).add(B_totalDebt).add(C_totalDebt).add(D_totalDebt)
    const totalColl = W_coll.add(A_coll).add(B_coll).add(C_coll).add(D_coll)

    // Get active debt and coll before redemption
    const activePool_debt_before = await activePool.getSystemDebt()
    const activePool_coll_before = await activePool.getSystemCollShares()

    th.assertIsApproximatelyEqual(activePool_debt_before, totalDebt)
    assert.equal(activePool_coll_before.toString(), totalColl)

    const price = await priceFeed.getPrice()
    await th.syncTwapSystemDebt(contracts, ethers.provider);



    // Erin attempts to redeem 400 EBTC
    const {
      firstRedemptionHint,
      partialRedemptionHintNICR
    } = await hintHelpers.getRedemptionHints(dec(400, 18), price, 0)

    const { 0: upperPartialRedemptionHint, 1: lowerPartialRedemptionHint } = await sortedCdps.findInsertPosition(
      partialRedemptionHintNICR,
      th.DUMMY_BYTES32,
      th.DUMMY_BYTES32
    )

    await cdpManager.redeemCollateral(
      dec(400, 18),
      firstRedemptionHint,
      upperPartialRedemptionHint,
      lowerPartialRedemptionHint,
      partialRedemptionHintNICR,
      0, th._100pct,
      { from: erin })

    // Check activePool debt reduced
    const activePool_debt_after = await activePool.getSystemDebt()
    assert.equal(activePool_debt_before.sub(activePool_debt_after).toString(), dec(400, 18))

    // Check Erin's balance after
    const erin_balance_after = (await ebtcToken.balanceOf(erin)).toString()
    assert.equal(erin_balance_after, '0')
  })

  it("redeemCollateral(): reverts when requested redemption amount exceeds caller's EBTC token balance", async () => {
    const { collateral: W_coll, totalDebt: W_totalDebt } = await openCdp({ ICR: toBN(dec(20, 18)), extraParams: { from: whale } })

    // Alice opens cdp and transfers 400 EBTC to Erin, the would-be redeemer
    await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("3000")});
    const { collateral: A_coll, totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(300, 16)), extraEBTCAmount: dec(400, 18), extraParams: { from: alice } })
    await ebtcToken.transfer(erin, dec(400, 18), { from: alice })

    // Check Erin's balance before
    const erin_balance_before = await ebtcToken.balanceOf(erin)
    assert.equal(erin_balance_before, dec(400, 18))

    // B, C, D open cdp
    await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("4000")});
    await _signer.sendTransaction({ to: carol, value: ethers.utils.parseEther("200000")});
    await _signer.sendTransaction({ to: dennis, value: ethers.utils.parseEther("200000")});
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(300, 16)), extraEBTCAmount: dec(590, 18), extraParams: { from: bob } })
    const { collateral: C_coll, totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(300, 16)), extraEBTCAmount: dec(1990, 18), extraParams: { from: carol } })
    const { collateral: D_coll, totalDebt: D_totalDebt } = await openCdp({ ICR: toBN(dec(500, 16)), extraEBTCAmount: dec(1990, 18), extraParams: { from: dennis } })

    const totalDebt = W_totalDebt.add(A_totalDebt).add(B_totalDebt).add(C_totalDebt).add(D_totalDebt)
    const totalColl = W_coll.add(A_coll).add(B_coll).add(C_coll).add(D_coll)

    // Get active debt and coll before redemption
    const activePool_debt_before = await activePool.getSystemDebt()
    const activePool_coll_before = (await activePool.getSystemCollShares()).toString()

    th.assertIsApproximatelyEqual(activePool_debt_before, totalDebt)
    assert.equal(activePool_coll_before, totalColl)

    const price = await priceFeed.getPrice()

    let firstRedemptionHint
    let partialRedemptionHintNICR



    // Erin tries to redeem 1000 EBTC
    try {
      ({
        firstRedemptionHint,
        partialRedemptionHintNICR
      } = await hintHelpers.getRedemptionHints(dec(1000, 18), price, 0))

      const { 0: upperPartialRedemptionHint_1, 1: lowerPartialRedemptionHint_1 } = await sortedCdps.findInsertPosition(
        partialRedemptionHintNICR,
        th.DUMMY_BYTES32,
        th.DUMMY_BYTES32
      )

      const redemptionTx = await cdpManager.redeemCollateral(
        dec(1000, 18),
        firstRedemptionHint,
        upperPartialRedemptionHint_1,
        lowerPartialRedemptionHint_1,
        partialRedemptionHintNICR,
        0, th._100pct,
        { from: erin })

      assert.isFalse(redemptionTx.receipt.status)
    } catch (error) {
      assert.include(error.message, "revert")
      assert.include(error.message, "Requested redemption amount must be <= user's EBTC token balance")
    }

    // Erin tries to redeem 401 EBTC
    try {
      ({
        firstRedemptionHint,
        partialRedemptionHintNICR
      } = await hintHelpers.getRedemptionHints('401000000000000000000', price, 0))

      const { 0: upperPartialRedemptionHint_2, 1: lowerPartialRedemptionHint_2 } = await sortedCdps.findInsertPosition(
        partialRedemptionHintNICR,
        th.DUMMY_BYTES32,
        th.DUMMY_BYTES32
      )

      const redemptionTx = await cdpManager.redeemCollateral(
        '401000000000000000000', firstRedemptionHint,
        upperPartialRedemptionHint_2,
        lowerPartialRedemptionHint_2,
        partialRedemptionHintNICR,
        0, th._100pct,
        { from: erin })
      assert.isFalse(redemptionTx.receipt.status)
    } catch (error) {
      assert.include(error.message, "revert")
      assert.include(error.message, "Requested redemption amount must be <= user's EBTC token balance")
    }

    // Erin tries to redeem 239482309 EBTC
    try {
      ({
        firstRedemptionHint,
        partialRedemptionHintNICR
      } = await hintHelpers.getRedemptionHints('239482309000000000000000000', price, 0))

      const { 0: upperPartialRedemptionHint_3, 1: lowerPartialRedemptionHint_3 } = await sortedCdps.findInsertPosition(
        partialRedemptionHintNICR,
        th.DUMMY_BYTES32,
        th.DUMMY_BYTES32
      )

      const redemptionTx = await cdpManager.redeemCollateral(
        '239482309000000000000000000', firstRedemptionHint,
        upperPartialRedemptionHint_3,
        lowerPartialRedemptionHint_3,
        partialRedemptionHintNICR,
        0, th._100pct,
        { from: erin })
      assert.isFalse(redemptionTx.receipt.status)
    } catch (error) {
      assert.include(error.message, "revert")
      assert.include(error.message, "Requested redemption amount must be <= user's EBTC token balance")
    }

    // Erin tries to redeem 2^256 - 1 EBTC
    const maxBytes32 = toBN('0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff')

    try {
      ({
        firstRedemptionHint,
        partialRedemptionHintNICR
      } = await hintHelpers.getRedemptionHints('239482309000000000000000000', price, 0))

      const { 0: upperPartialRedemptionHint_4, 1: lowerPartialRedemptionHint_4 } = await sortedCdps.findInsertPosition(
        partialRedemptionHintNICR,
        th.DUMMY_BYTES32,
        th.DUMMY_BYTES32
      )

      const redemptionTx = await cdpManager.redeemCollateral(
        maxBytes32, firstRedemptionHint,
        upperPartialRedemptionHint_4,
        lowerPartialRedemptionHint_4,
        partialRedemptionHintNICR,
        0, th._100pct,
        { from: erin })
      assert.isFalse(redemptionTx.receipt.status)
    } catch (error) {
      assert.include(error.message, "revert")
      assert.include(error.message, "Requested redemption amount must be <= user's EBTC token balance")
    }
  })

  it("redeemCollateral(): value of issued ETH == face value of redeemed EBTC (assuming 1 EBTC has value of $1)", async () => {
    const { collateral: W_coll } = await openCdp({ ICR: toBN(dec(20, 18)), extraParams: { from: whale } })

    // Alice opens cdp and transfers 1000 EBTC each to Erin, Flyn, Graham
    await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("270000")});
    const { collateral: A_coll, totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(400, 16)), extraEBTCAmount: dec(4990, 18), extraParams: { from: alice } })
    await ebtcToken.transfer(erin, dec(1000, 18), { from: alice })
    await ebtcToken.transfer(flyn, dec(1000, 18), { from: alice })
    await ebtcToken.transfer(graham, dec(1000, 18), { from: alice })

    // B, C, D open cdp
    await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("150000")});
    await _signer.sendTransaction({ to: carol, value: ethers.utils.parseEther("150000")});
    await _signer.sendTransaction({ to: dennis, value: ethers.utils.parseEther("150000")});
    const { collateral: B_coll } = await openCdp({ ICR: toBN(dec(300, 16)), extraEBTCAmount: dec(1590, 18), extraParams: { from: bob } })
    const { collateral: C_coll } = await openCdp({ ICR: toBN(dec(600, 16)), extraEBTCAmount: dec(1090, 18), extraParams: { from: carol } })
    const { collateral: D_coll } = await openCdp({ ICR: toBN(dec(800, 16)), extraEBTCAmount: dec(1090, 18), extraParams: { from: dennis } })

    const totalColl = W_coll.add(A_coll).add(B_coll).add(C_coll).add(D_coll)

    const price = await priceFeed.getPrice()
    await th.syncTwapSystemDebt(contracts, ethers.provider);

    const _120_EBTC = '120000000000000000000'
    const _373_EBTC = '373000000000000000000'
    const _950_EBTC = '950000000000000000000'

    // Check Ether in activePool
    const activeETH_0 = await activePool.getSystemCollShares()
    assert.equal(activeETH_0, totalColl.toString());

    let firstRedemptionHint
    let partialRedemptionHintNICR


    // Erin redeems 120 EBTC
    ({
      firstRedemptionHint,
      partialRedemptionHintNICR
    } = await hintHelpers.getRedemptionHints(_120_EBTC, price, 0))

    const { 0: upperPartialRedemptionHint_1, 1: lowerPartialRedemptionHint_1 } = await sortedCdps.findInsertPosition(
      partialRedemptionHintNICR,
      th.DUMMY_BYTES32,
      th.DUMMY_BYTES32
    )



    const redemption_1 = await cdpManager.redeemCollateral(
      _120_EBTC,
      firstRedemptionHint,
      upperPartialRedemptionHint_1,
      lowerPartialRedemptionHint_1,
      partialRedemptionHintNICR,
      0, th._100pct,
      { from: erin })

    assert.isTrue(redemption_1.receipt.status);

    /* 120 EBTC redeemed.  Expect $120 worth of ETH removed. At ETH:USD price of $200, 
    ETH removed = (120/200) = 0.6 ETH
    Total active ETH = 280 - 0.6 = 279.4 ETH */

    const activeETH_1 = await activePool.getSystemCollShares()
    assert.equal(activeETH_1.toString(), activeETH_0.sub(toBN(_120_EBTC).mul(mv._1e18BN).div(price)));

    // Flyn redeems 373 EBTC
    ({
      firstRedemptionHint,
      partialRedemptionHintNICR
    } = await hintHelpers.getRedemptionHints(_373_EBTC, price, 0))

    const { 0: upperPartialRedemptionHint_2, 1: lowerPartialRedemptionHint_2 } = await sortedCdps.findInsertPosition(
      partialRedemptionHintNICR,
      th.DUMMY_BYTES32,
      th.DUMMY_BYTES32
    )

    const redemption_2 = await cdpManager.redeemCollateral(
      _373_EBTC,
      firstRedemptionHint,
      upperPartialRedemptionHint_2,
      lowerPartialRedemptionHint_2,
      partialRedemptionHintNICR,
      0, th._100pct,
      { from: flyn })

    assert.isTrue(redemption_2.receipt.status);

    /* 373 EBTC redeemed.  Expect $373 worth of ETH removed. At ETH:USD price of $200, 
    ETH removed = (373/200) = 1.865 ETH
    Total active ETH = 279.4 - 1.865 = 277.535 ETH */
    const activeETH_2 = await activePool.getSystemCollShares()
    assert.equal(activeETH_2.toString(), activeETH_1.sub(toBN(_373_EBTC).mul(mv._1e18BN).div(price)));

    // Graham redeems 950 EBTC
    ({
      firstRedemptionHint,
      partialRedemptionHintNICR
    } = await hintHelpers.getRedemptionHints(_950_EBTC, price, 0))

    const { 0: upperPartialRedemptionHint_3, 1: lowerPartialRedemptionHint_3 } = await sortedCdps.findInsertPosition(
      partialRedemptionHintNICR,
      th.DUMMY_BYTES32,
      th.DUMMY_BYTES32
    )

    const redemption_3 = await cdpManager.redeemCollateral(
      _950_EBTC,
      firstRedemptionHint,
      upperPartialRedemptionHint_3,
      lowerPartialRedemptionHint_3,
      partialRedemptionHintNICR,
      0, th._100pct,
      { from: graham })

    assert.isTrue(redemption_3.receipt.status);

    /* 950 EBTC redeemed.  Expect $950 worth of ETH removed. At ETH:USD price of $200, 
    ETH removed = (950/200) = 4.75 ETH
    Total active ETH = 277.535 - 4.75 = 272.785 ETH */
    const activeETH_3 = (await activePool.getSystemCollShares()).toString()
    assert.equal(activeETH_3.toString(), activeETH_2.sub(toBN(_950_EBTC).mul(mv._1e18BN).div(price)));
  })

  // it doesn’t make much sense as there’s now min debt enforced and at least one cdp must remain active
  // the only way to test it is before any cdp is opened
  it("redeemCollateral(): reverts if there is zero outstanding system debt", async () => {
    // --- SETUP --- illegally mint EBTC to Bob
    await ebtcToken.unprotectedMint(bob, dec(100, 18))

    assert.equal((await ebtcToken.balanceOf(bob)), dec(100, 18))

    const price = await priceFeed.getPrice()

    const {
      firstRedemptionHint,
      partialRedemptionHintNICR
    } = await hintHelpers.getRedemptionHints(dec(100, 18), price, 0)

    const { 0: upperPartialRedemptionHint, 1: lowerPartialRedemptionHint } = await sortedCdps.findInsertPosition(
      partialRedemptionHintNICR,
      th.DUMMY_BYTES32,
      th.DUMMY_BYTES32
    )

    // Bob tries to redeem his illegally obtained EBTC
    try {
      const redemptionTx = await cdpManager.redeemCollateral(
        dec(100, 18),
        firstRedemptionHint,
        upperPartialRedemptionHint,
        lowerPartialRedemptionHint,
        partialRedemptionHintNICR,
        0, th._100pct,
        { from: bob })
    } catch (error) {
      assert.include(error.message, "VM Exception while processing transaction")
    }

    // assert.isFalse(redemptionTx.receipt.status);
  })

  it("redeemCollateral(): reverts if caller's tries to redeem more than the outstanding system debt", async () => {
    // --- SETUP --- illegally mint EBTC to Bob
    await ebtcToken.unprotectedMint(bob, '101000000000000000000')

    assert.equal((await ebtcToken.balanceOf(bob)), '101000000000000000000')

    const { collateral: C_coll, totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(1000, 16)), extraEBTCAmount: dec(40, 18), extraParams: { from: carol } })
    const { collateral: D_coll, totalDebt: D_totalDebt } = await openCdp({ ICR: toBN(dec(1000, 16)), extraEBTCAmount: dec(40, 18), extraParams: { from: dennis } })

    const totalDebt = C_totalDebt.add(D_totalDebt)
    th.assertIsApproximatelyEqual((await activePool.getSystemDebt()).toString(), totalDebt)

    const price = await priceFeed.getPrice()
    const {
      firstRedemptionHint,
      partialRedemptionHintNICR
    } = await hintHelpers.getRedemptionHints('101000000000000000000', price, 0)

    const { 0: upperPartialRedemptionHint, 1: lowerPartialRedemptionHint } = await sortedCdps.findInsertPosition(
      partialRedemptionHintNICR,
      th.DUMMY_BYTES32,
      th.DUMMY_BYTES32
    )



    // Bob attempts to redeem his ill-gotten 101 EBTC, from a system that has 100 EBTC outstanding debt
    try {
      const redemptionTx = await cdpManager.redeemCollateral(
        totalDebt.add(toBN(dec(100, 18))),
        firstRedemptionHint,
        upperPartialRedemptionHint,
        lowerPartialRedemptionHint,
        partialRedemptionHintNICR,
        0, th._100pct,
        { from: bob })
    } catch (error) {
      assert.include(error.message, "VM Exception while processing transaction")
    }
  })

  // Redemption fees 
  it("redeemCollateral(): a redemption made when base rate is zero increases the base rate", async () => {
    await openCdp({ ICR: toBN(dec(20, 18)), extraParams: { from: whale } })

    await _signer.sendTransaction({ to: A, value: ethers.utils.parseEther("2000")});
    await _signer.sendTransaction({ to: B, value: ethers.utils.parseEther("2000")});
    await _signer.sendTransaction({ to: C, value: ethers.utils.parseEther("2000")});

    await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: A } })
    await openCdp({ ICR: toBN(dec(190, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: B } })
    await openCdp({ ICR: toBN(dec(180, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: C } })

    // Check baseRate == 0
    assert.equal(await cdpManager.baseRate(), '0')
    await th.syncTwapSystemDebt(contracts, ethers.provider);



    const A_balanceBefore = await ebtcToken.balanceOf(A)

    await th.redeemCollateral(A, contracts, dec(10, 18), GAS_PRICE)

    // Check A's balance has decreased by 10 EBTC
    assert.equal(await ebtcToken.balanceOf(A), A_balanceBefore.sub(toBN(dec(10, 18))).toString())

    // Check baseRate is now non-zero
    assert.isTrue((await cdpManager.baseRate()).gt(toBN('0')))
  })

  it("redeemCollateral(): a redemption made when base rate is non-zero increases the base rate, for negligible time passed", async () => {
    // time fast-forwards 1 year, and multisig stakes 1 LQTY
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_YEAR, web3.currentProvider)

    await openCdp({ ICR: toBN(dec(20, 18)), extraParams: { from: whale } })

    await _signer.sendTransaction({ to: A, value: ethers.utils.parseEther("2000")});
    await _signer.sendTransaction({ to: B, value: ethers.utils.parseEther("2000")});
    await _signer.sendTransaction({ to: C, value: ethers.utils.parseEther("2000")});

    await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: A } })
    await openCdp({ ICR: toBN(dec(190, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: B } })
    await openCdp({ ICR: toBN(dec(180, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: C } })

    // Check baseRate == 0
    assert.equal(await cdpManager.baseRate(), '0')
    await th.syncTwapSystemDebt(contracts, ethers.provider);

    const A_balanceBefore = await ebtcToken.balanceOf(A)
    const B_balanceBefore = await ebtcToken.balanceOf(B)

    // A redeems 10 EBTC
    const redemptionTx_A = await th.redeemCollateralAndGetTxObject(A, contracts, dec(10, 18), GAS_PRICE)
    const timeStamp_A = await th.getTimestampFromTx(redemptionTx_A, web3)

    // Check A's balance has decreased by 10 EBTC
    assert.equal(await ebtcToken.balanceOf(A), A_balanceBefore.sub(toBN(dec(10, 18))).toString())

    // Check baseRate is now non-zero
    const baseRate_1 = await cdpManager.baseRate()
    assert.isTrue(baseRate_1.gt(toBN('0')))

    // B redeems 10 EBTC
    const redemptionTx_B = await th.redeemCollateralAndGetTxObject(B, contracts, dec(10, 18), GAS_PRICE)
    const timeStamp_B = await th.getTimestampFromTx(redemptionTx_B, web3)

    // Check B's balance has decreased by 10 EBTC
    assert.equal(await ebtcToken.balanceOf(B), B_balanceBefore.sub(toBN(dec(10, 18))).toString())

    // Check negligible time difference (< 1 minute) between txs
    assert.isTrue(Number(timeStamp_B) - Number(timeStamp_A) < 60)

    const baseRate_2 = await cdpManager.baseRate()

    // Check baseRate has again increased
    assert.isTrue(baseRate_2.gt(baseRate_1))
  })

  it("redeemCollateral(): lastFeeOpTime doesn't update if less time than decay interval has passed since the last fee operation [ @skip-on-coverage ]", async () => {
    await openCdp({ ICR: toBN(dec(20, 18)), extraParams: { from: whale } })

    await _signer.sendTransaction({ to: A, value: ethers.utils.parseEther("2000")});
    await _signer.sendTransaction({ to: B, value: ethers.utils.parseEther("2000")});
    await _signer.sendTransaction({ to: C, value: ethers.utils.parseEther("2000")});

    await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: A } })
    await openCdp({ ICR: toBN(dec(190, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: B } })
    await openCdp({ ICR: toBN(dec(180, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: C } })



    const A_balanceBefore = await ebtcToken.balanceOf(A)
    await th.syncTwapSystemDebt(contracts, ethers.provider);

    // A redeems 10 EBTC
    await th.redeemCollateral(A, contracts, dec(10, 18), GAS_PRICE)

    // Check A's balance has decreased by 10 EBTC
    assert.equal(A_balanceBefore.sub(await ebtcToken.balanceOf(A)), dec(10, 18))

    // Check baseRate is now non-zero
    const baseRate_1 = await cdpManager.baseRate()
    assert.isTrue(baseRate_1.gt(toBN('0')))

    const lastFeeOpTime_1 = await cdpManager.lastRedemptionTimestamp()

    // 45 seconds pass
    th.fastForwardTime(45, web3.currentProvider)

    // Borrower A triggers a fee
    let _m = await cdpManager.minutesPassedSinceLastRedemption();
    await th.redeemCollateral(A, contracts, dec(1, 18), GAS_PRICE)

    const lastFeeOpTime_2 = await cdpManager.lastRedemptionTimestamp()

    // Check that the last fee operation time did not update, as borrower A's 2nd redemption occured
    // since before minimum interval had passed 
    assert.isTrue(lastFeeOpTime_2.eq(lastFeeOpTime_1.add(toBN(_m * 60))))

    // 15 seconds passes
    th.fastForwardTime(15, web3.currentProvider)

    // Check that now, at least one hour has passed since lastFeeOpTime_1
    const timeNow = await th.getLatestBlockTimestamp(web3)
    assert.isTrue(toBN(timeNow).sub(lastFeeOpTime_1).gte(3600))

    // Borrower A triggers a fee
    await th.redeemCollateral(A, contracts, dec(1, 18), GAS_PRICE)

    const lastFeeOpTime_3 = await cdpManager.lastRedemptionTimestamp()

    // Check that the last fee operation time DID update, as A's 2rd redemption occured
    // after minimum interval had passed 
    assert.isTrue(lastFeeOpTime_3.gt(lastFeeOpTime_1))
  })

  it("redeemCollateral(): a redemption made at zero base rate send a non-zero feeCollShares to FeeRecipient", async () => {
    // time fast-forwards 1 year, and multisig stakes 1 LQTY
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_YEAR, web3.currentProvider)

    await openCdp({ ICR: toBN(dec(20, 18)), extraParams: { from: whale } })

    await _signer.sendTransaction({ to: A, value: ethers.utils.parseEther("3000")});
    await _signer.sendTransaction({ to: B, value: ethers.utils.parseEther("3000")});
    await _signer.sendTransaction({ to: C, value: ethers.utils.parseEther("3000")});
    await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: A } })
    await openCdp({ ICR: toBN(dec(190, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: B } })
    await openCdp({ ICR: toBN(dec(180, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: C } })

    // Check baseRate == 0
    assert.equal(await cdpManager.baseRate(), '0')

    // Check LQTY Staking contract balance before is zero
    const lqtyStakingBalance_Before = toBN(await contracts.collateral.balanceOf(feeRecipient.address))
    assert.equal(lqtyStakingBalance_Before, '0')
    await th.syncTwapSystemDebt(contracts, ethers.provider);

    const A_balanceBefore = await ebtcToken.balanceOf(A)

    // A redeems 10 EBTC
    await th.redeemCollateral(A, contracts, dec(10, 18), GAS_PRICE)

    // Check A's balance has decreased by 10 EBTC
    assert.equal(await ebtcToken.balanceOf(A), A_balanceBefore.sub(toBN(dec(10, 18))).toString())

    // Check baseRate is now non-zero
    const baseRate_1 = await cdpManager.baseRate()
    assert.isTrue(baseRate_1.gt(toBN('0')))

    // Check LQTY Staking contract balance after is non-zero
    const lqtyStakingBalance_After = toBN(await contracts.activePool.getFeeRecipientClaimableCollShares())
    assert.isTrue(lqtyStakingBalance_After.gt(toBN('0')))
  })

  it("redeemCollateral(): a redemption made at zero base processes fee to FeeRecipient", async () => {
    // time fast-forwards 1 year, and multisig stakes 1 LQTY
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_YEAR, web3.currentProvider)

    await openCdp({ ICR: toBN(dec(20, 18)), extraParams: { from: whale } })

    await _signer.sendTransaction({ to: A, value: ethers.utils.parseEther("2000")});
    await _signer.sendTransaction({ to: B, value: ethers.utils.parseEther("2000")});
    await _signer.sendTransaction({ to: C, value: ethers.utils.parseEther("2000")});
    await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: A } })
    await openCdp({ ICR: toBN(dec(190, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: B } })
    await openCdp({ ICR: toBN(dec(180, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: C } })

    // Check baseRate == 0
    assert.equal(await cdpManager.baseRate(), '0')

    // Check feeRecipient balance beforehand
    const feeRecipientBalanceBefore = toBN(await contracts.collateral.balanceOf(feeRecipient.address))
    assert.equal(feeRecipientBalanceBefore, '0')
    await th.syncTwapSystemDebt(contracts, ethers.provider);

    const A_balanceBefore = await ebtcToken.balanceOf(A)

    // A redeems 10 EBTC
    await th.redeemCollateral(A, contracts, dec(10, 18), GAS_PRICE)

    // Check A's balance has decreased by 10 EBTC
    assert.equal(await ebtcToken.balanceOf(A), A_balanceBefore.sub(toBN(dec(10, 18))).toString())

    // Check baseRate is now non-zero
    const baseRate_1 = await cdpManager.baseRate()
    assert.isTrue(baseRate_1.gt(toBN('0')))

    // Check LQTY Staking ETH-fees-per-LQTY-staked after is non-zero
    const feeRecipientBalanceAfter = toBN(await contracts.collateral.balanceOf(feeRecipient.address))
    assert.isTrue(feeRecipientBalanceAfter.gt('0'))
  })

  it("redeemCollateral(): a redemption made at a non-zero base rate send a non-zero fee to FeeRecipient", async () => {
    // time fast-forwards 1 year, and multisig stakes 1 LQTY
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_YEAR, web3.currentProvider)

    await openCdp({ ICR: toBN(dec(20, 18)), extraParams: { from: whale } })

    await _signer.sendTransaction({ to: A, value: ethers.utils.parseEther("3000")});
    await _signer.sendTransaction({ to: B, value: ethers.utils.parseEther("3000")});
    await _signer.sendTransaction({ to: C, value: ethers.utils.parseEther("3000")});
    await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: A } })
    await openCdp({ ICR: toBN(dec(190, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: B } })
    await openCdp({ ICR: toBN(dec(180, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: C } })

    // Check baseRate == 0
    assert.equal(await cdpManager.baseRate(), '0')
    await th.syncTwapSystemDebt(contracts, ethers.provider);

    const A_balanceBefore = await ebtcToken.balanceOf(A)
    const B_balanceBefore = await ebtcToken.balanceOf(B)

    // A redeems 10 EBTC
    await th.redeemCollateral(A, contracts, dec(10, 18), GAS_PRICE)

    // Check A's balance has decreased by 10 EBTC
    assert.equal(await ebtcToken.balanceOf(A), A_balanceBefore.sub(toBN(dec(10, 18))).toString())

    // Check baseRate is now non-zero
    const baseRate_1 = await cdpManager.baseRate()
    assert.isTrue(baseRate_1.gt(toBN('0')))

    const lqtyStakingBalance_Before = toBN(await contracts.collateral.balanceOf(feeRecipient.address))

    // B redeems 10 EBTC
    await th.redeemCollateral(B, contracts, dec(10, 18), GAS_PRICE)

    // Check B's balance has decreased by 10 EBTC
    assert.equal(await ebtcToken.balanceOf(B), B_balanceBefore.sub(toBN(dec(10, 18))).toString())

    const lqtyStakingBalance_After = toBN(await contracts.collateral.balanceOf(feeRecipient.address))

    // check LQTY Staking balance has increased
    const feeRecipientBalanceAfter = toBN(await contracts.collateral.balanceOf(feeRecipient.address))
    assert.isTrue(feeRecipientBalanceAfter.gt('0'))
  })

  it("redeemCollateral(): a redemption made at a non-zero base rate increases ETH-per-LQTY-staked in the staking contract", async () => {
    // time fast-forwards 1 year, and multisig stakes 1 LQTY
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_YEAR, web3.currentProvider)

    await openCdp({ ICR: toBN(dec(20, 18)), extraParams: { from: whale } })

    await _signer.sendTransaction({ to: A, value: ethers.utils.parseEther("2000")});
    await _signer.sendTransaction({ to: B, value: ethers.utils.parseEther("2000")});
    await _signer.sendTransaction({ to: C, value: ethers.utils.parseEther("2000")});
    await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: A } })
    await openCdp({ ICR: toBN(dec(190, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: B } })
    await openCdp({ ICR: toBN(dec(180, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: C } })

    // Check baseRate == 0
    assert.equal(await cdpManager.baseRate(), '0')
    await th.syncTwapSystemDebt(contracts, ethers.provider);

    const A_balanceBefore = await ebtcToken.balanceOf(A)
    const B_balanceBefore = await ebtcToken.balanceOf(B)

    // A redeems 10 EBTC
    await th.redeemCollateral(A, contracts, dec(10, 18), GAS_PRICE)

    // Check A's balance has decreased by 10 EBTC
    assert.equal(await ebtcToken.balanceOf(A), A_balanceBefore.sub(toBN(dec(10, 18))).toString())

    // Check baseRate is now non-zero
    const baseRate_1 = await cdpManager.baseRate()
    assert.isTrue(baseRate_1.gt(toBN('0')))

    // Check feeRecipient balance beforehand
    const feeRecipientBalanceBefore = toBN(await contracts.activePool.getFeeRecipientClaimableCollShares())

    // B redeems 10 EBTC
    await th.redeemCollateral(B, contracts, dec(10, 18), GAS_PRICE)

    // Check B's balance has decreased by 10 EBTC
    assert.equal(await ebtcToken.balanceOf(B), B_balanceBefore.sub(toBN(dec(10, 18))).toString())
    
    // Ensure balance has increased
    const feeRecipientBalanceAfter = toBN(await contracts.activePool.getFeeRecipientClaimableCollShares())
    assert.isTrue(feeRecipientBalanceAfter.gt(feeRecipientBalanceBefore))
  })

  it("redeemCollateral(): a redemption sends the ETH remainder (ETHDrawn - feeCollShares) to the redeemer", async () => {
    // time fast-forwards 1 year, and multisig stakes 1 LQTY
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_YEAR, web3.currentProvider)

    const { totalDebt: W_totalDebt } = await openCdp({ ICR: toBN(dec(20, 18)), extraParams: { from: whale } })

    await _signer.sendTransaction({ to: A, value: ethers.utils.parseEther("3000")});
    await _signer.sendTransaction({ to: B, value: ethers.utils.parseEther("3000")});
    await _signer.sendTransaction({ to: C, value: ethers.utils.parseEther("3000")});
    const { totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: A } })
    const { totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(190, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: B } })
    const { totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(180, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: C } })
    const totalDebt = W_totalDebt.add(A_totalDebt).add(B_totalDebt).add(C_totalDebt)

    const A_balanceBefore = toBN(await contracts.collateral.balanceOf(A))

    // Confirm baseRate before redemption is 0
    const baseRate = await cdpManager.baseRate()
    assert.equal(baseRate, '0')
    await th.syncTwapSystemDebt(contracts, ethers.provider);

    // Check total EBTC supply
    const activeEBTC = await activePool.getSystemDebt()

    const totalEBTCSupply = activeEBTC
    th.assertIsApproximatelyEqual(totalEBTCSupply, totalDebt)

    // A redeems 9 EBTC
    const redemptionAmount = toBN(dec(9, 18))
    const price = await priceFeed.getPrice()
    const ETHDrawn = redemptionAmount.mul(mv._1e18BN).div(price)
	
    let _weightedMean = await th.simulateObserveForTWAP(contracts, ethers.provider, 1);
	
    let _updatedBaseRate = await cdpManager.getUpdatedBaseRateFromRedemptionWithSystemDebt(ETHDrawn, price, _weightedMean);
    let _updatedRate = _updatedBaseRate.add(await cdpManager.redemptionFeeFloor());

    const gasUsed = await th.redeemCollateral(A, contracts, redemptionAmount, GAS_PRICE)

    /*
    At ETH:USD price of 200:
    ETHDrawn = (9 / 200) = 0.045 ETH
    ETHfee = (0.005 + (1/2) *( 9/260)) * ETHDrawn = 0.00100384615385 ETH
    ETHRemainder = 0.045 - 0.001003... = 0.0439961538462
    */

    const A_balanceAfter = toBN(await contracts.collateral.balanceOf(A))

    // check A's ETH balance has increased by 0.045 ETH 
    th.assertIsApproximatelyEqual(
      A_balanceAfter.sub(A_balanceBefore),
      ETHDrawn.sub(
        _updatedRate.mul(ETHDrawn).div(mv._1e18BN)
      ),
      100000000
    )
  })

  it("redeemCollateral(): a full redemption (leaving cdp with 0 debt), closes the cdp", async () => {
    // time fast-forwards 1 year, and multisig stakes 1 LQTY
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_YEAR, web3.currentProvider)

    await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("10000")});
    const { netDebt: W_netDebt } = await openCdp({ ICR: toBN(dec(20, 18)), extraEBTCAmount: dec(1000, 18), extraParams: { from: whale } })

    await _signer.sendTransaction({ to: A, value: ethers.utils.parseEther("3000")});
    await _signer.sendTransaction({ to: B, value: ethers.utils.parseEther("3000")});
    await _signer.sendTransaction({ to: C, value: ethers.utils.parseEther("3000")});
    await _signer.sendTransaction({ to: D, value: ethers.utils.parseEther("3000")});
    const { netDebt: A_netDebt } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: A } })
    const { netDebt: B_netDebt } = await openCdp({ ICR: toBN(dec(190, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: B } })
    const { netDebt: C_netDebt } = await openCdp({ ICR: toBN(dec(180, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: C } })
    const { netDebt: D_netDebt } = await openCdp({ ICR: toBN(dec(280, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: D } })
    let _aCdpId = await sortedCdps.cdpOfOwnerByIndex(A, 0);
    let _bCdpId = await sortedCdps.cdpOfOwnerByIndex(B, 0);
    let _cCdpId = await sortedCdps.cdpOfOwnerByIndex(C, 0);
    let _dCdpId = await sortedCdps.cdpOfOwnerByIndex(D, 0);
    const redemptionAmount = A_netDebt.add(B_netDebt).add(C_netDebt).add(toBN(dec(10, 18)))

    const A_balanceBefore = toBN(await web3.eth.getBalance(A))
    const B_balanceBefore = toBN(await web3.eth.getBalance(B))
    const C_balanceBefore = toBN(await web3.eth.getBalance(C))
    await th.syncTwapSystemDebt(contracts, ethers.provider);

    // whale redeems 360 EBTC.  Expect this to fully redeem A, B, C, and partially redeem D.
    await th.redeemCollateral(whale, contracts, redemptionAmount, GAS_PRICE)

    // Check A, B, C have been closed
    assert.isFalse(await sortedCdps.contains(_aCdpId))
    assert.isFalse(await sortedCdps.contains(_bCdpId))
    assert.isFalse(await sortedCdps.contains(_cCdpId))

    // Check D remains active
    assert.isTrue(await sortedCdps.contains(_dCdpId))
  })

  const redeemCollateral3Full1Partial = async () => {
    // time fast-forwards 1 year, and multisig stakes 1 LQTY
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_YEAR, web3.currentProvider)
    
    await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("270000")});
    const { netDebt: W_netDebt } = await openCdp({ ICR: toBN(dec(20, 18)), extraEBTCAmount: dec(1000, 18), extraParams: { from: whale } })

    await _signer.sendTransaction({ to: A, value: ethers.utils.parseEther("3000")});
    await _signer.sendTransaction({ to: B, value: ethers.utils.parseEther("3000")});
    await _signer.sendTransaction({ to: C, value: ethers.utils.parseEther("3000")});
    await _signer.sendTransaction({ to: D, value: ethers.utils.parseEther("3000")});
    const { netDebt: A_netDebt, collateral: A_coll } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: A } })
    const { netDebt: B_netDebt, collateral: B_coll } = await openCdp({ ICR: toBN(dec(190, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: B } })
    const { netDebt: C_netDebt, collateral: C_coll } = await openCdp({ ICR: toBN(dec(180, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: C } })
    const { netDebt: D_netDebt } = await openCdp({ ICR: toBN(dec(280, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: D } })
    let _aCdpId = await sortedCdps.cdpOfOwnerByIndex(A, 0);
    let _bCdpId = await sortedCdps.cdpOfOwnerByIndex(B, 0);
    let _cCdpId = await sortedCdps.cdpOfOwnerByIndex(C, 0);
    let _dCdpId = await sortedCdps.cdpOfOwnerByIndex(D, 0);
    const redemptionAmount = A_netDebt.add(B_netDebt).add(C_netDebt).add(toBN(dec(10, 18)))

    const A_balanceBefore = toBN(await web3.eth.getBalance(A))
    const B_balanceBefore = toBN(await web3.eth.getBalance(B))
    const C_balanceBefore = toBN(await web3.eth.getBalance(C))
    const D_balanceBefore = toBN(await web3.eth.getBalance(D))

    const A_collBefore = await cdpManager.getCdpCollShares(_aCdpId)
    const B_collBefore = await cdpManager.getCdpCollShares(_bCdpId)
    const C_collBefore = await cdpManager.getCdpCollShares(_cCdpId)
    const D_collBefore = await cdpManager.getCdpCollShares(_dCdpId)

    // Confirm baseRate before redemption is 0
    const baseRate = await cdpManager.baseRate()
    assert.equal(baseRate, '0')
    await th.syncTwapSystemDebt(contracts, ethers.provider);    

    // whale redeems EBTC.  Expect this to fully redeem A, B, C, and partially redeem D.
    await th.redeemCollateral(whale, contracts, redemptionAmount, GAS_PRICE)

    // Check A, B, C have been closed
    assert.isFalse(await sortedCdps.contains(_aCdpId))
    assert.isFalse(await sortedCdps.contains(_bCdpId))
    assert.isFalse(await sortedCdps.contains(_cCdpId))

    // Check D stays active
    assert.isTrue(await sortedCdps.contains(_dCdpId))
    
    /*
    At ETH:USD price of 200, with full redemptions from A, B, C:

    ETHDrawn from A = 100/200 = 0.5 ETH --> Surplus = (1-0.5) = 0.5
    ETHDrawn from B = 120/200 = 0.6 ETH --> Surplus = (1-0.6) = 0.4
    ETHDrawn from C = 130/200 = 0.65 ETH --> Surplus = (2-0.65) = 1.35
    */

    const A_balanceAfter = toBN(await web3.eth.getBalance(A))
    const B_balanceAfter = toBN(await web3.eth.getBalance(B))
    const C_balanceAfter = toBN(await web3.eth.getBalance(C))
    const D_balanceAfter = toBN(await web3.eth.getBalance(D))

    // Check A, B, C’s cdp collateral balance is zero (fully redeemed-from cdps)
    const A_collAfter = await cdpManager.getCdpCollShares(_aCdpId)
    const B_collAfter = await cdpManager.getCdpCollShares(_bCdpId)
    const C_collAfter = await cdpManager.getCdpCollShares(_cCdpId)
    assert.isTrue(A_collAfter.eq(toBN(0)))
    assert.isTrue(B_collAfter.eq(toBN(0)))
    assert.isTrue(C_collAfter.eq(toBN(0)))

    // check D's cdp collateral balances have decreased (the partially redeemed-from cdp)
    const D_collAfter = await cdpManager.getCdpCollShares(_dCdpId)
    assert.isTrue(D_collAfter.lt(D_collBefore))

    // Check A, B, C (fully redeemed-from cdps), and D's (the partially redeemed-from cdp) balance has not changed
    assert.isTrue(A_balanceAfter.eq(A_balanceBefore))
    assert.isTrue(B_balanceAfter.eq(B_balanceBefore))
    assert.isTrue(C_balanceAfter.eq(C_balanceBefore))
    assert.isTrue(D_balanceAfter.eq(D_balanceBefore))

    // Deprecated D is not closed, so cannot open cdp
    // await assertRevert(borrowerOperations.openCdp(0, th.DUMMY_BYTES32, ZERO_ADDRESS, { from: D, value: dec(10, 18) }), 'BorrowerOperations: Cdp is active')

    return {
      A_netDebt, A_coll,
      B_netDebt, B_coll,
      C_netDebt, C_coll,
    }
  }

  it("redeemCollateral(): emits correct debt and coll values in each redeemed cdp's CdpUpdated event", async () => {
    await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("20000")});
    const { netDebt: W_netDebt } = await openCdp({ ICR: toBN(dec(20, 18)), extraEBTCAmount: dec(1000, 18), extraParams: { from: whale } })

    await _signer.sendTransaction({ to: A, value: ethers.utils.parseEther("3000")});
    await _signer.sendTransaction({ to: B, value: ethers.utils.parseEther("3000")});
    await _signer.sendTransaction({ to: C, value: ethers.utils.parseEther("3000")});
    const { netDebt: A_netDebt } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: A } })
    const { netDebt: B_netDebt } = await openCdp({ ICR: toBN(dec(190, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: B } })
    const { netDebt: C_netDebt } = await openCdp({ ICR: toBN(dec(180, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: C } })
    await _signer.sendTransaction({ to: D, value: ethers.utils.parseEther("20000")});
    const { totalDebt: D_totalDebt, collateral: D_coll } = await openCdp({ ICR: toBN(dec(280, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: D } })
    let _aCdpId = await sortedCdps.cdpOfOwnerByIndex(A, 0);
    let _bCdpId = await sortedCdps.cdpOfOwnerByIndex(B, 0);
    let _cCdpId = await sortedCdps.cdpOfOwnerByIndex(C, 0);
    let _dCdpId = await sortedCdps.cdpOfOwnerByIndex(D, 0);
    const partialAmount = toBN(dec(15, 18))
    const redemptionAmount = A_netDebt.add(B_netDebt).add(C_netDebt).add(partialAmount)
    await th.syncTwapSystemDebt(contracts, ethers.provider);



    // whale redeems EBTC.  Expect this to fully redeem A, B, C, and partially redeem 15 EBTC from D.
    const redemptionTx = await th.redeemCollateralAndGetTxObject(whale, contracts, redemptionAmount, GAS_PRICE, th._100pct)

    // Check A, B, C have been closed
    assert.isFalse(await sortedCdps.contains(_aCdpId))
    assert.isFalse(await sortedCdps.contains(_bCdpId))
    assert.isFalse(await sortedCdps.contains(_cCdpId))

    // Check D stays active
    assert.isTrue(await sortedCdps.contains(_dCdpId))

    const cdpUpdatedEvents = th.getAllEventsByName(redemptionTx, "CdpUpdated")

    // Get each cdp's emitted debt and coll 
    const [A_emittedDebt, A_emittedColl] = th.getDebtAndCollFromCdpUpdatedEvents(cdpUpdatedEvents, _aCdpId)
    const [B_emittedDebt, B_emittedColl] = th.getDebtAndCollFromCdpUpdatedEvents(cdpUpdatedEvents, _bCdpId)
    const [C_emittedDebt, C_emittedColl] = th.getDebtAndCollFromCdpUpdatedEvents(cdpUpdatedEvents, _cCdpId)
    const [D_emittedDebt, D_emittedColl] = th.getDebtAndCollFromCdpUpdatedEvents(cdpUpdatedEvents, _dCdpId)

    // Expect A, B, C to have 0 emitted debt and coll, since they were closed
    assert.equal(A_emittedDebt, '0')
    assert.equal(A_emittedColl, '0')
    assert.equal(B_emittedDebt, '0')
    assert.equal(B_emittedColl, '0')
    assert.equal(C_emittedDebt, '0')
    assert.equal(C_emittedColl, '0')

    /* Expect D to have lost 15 debt and (at ETH price of 200) 15/200 = 0.075 ETH. 
    So, expect remaining debt = (85 - 15) = 70, and remaining ETH = 1 - 15/200 = 0.925 remaining. */
    const price = await priceFeed.getPrice()
    th.assertIsApproximatelyEqual(D_emittedDebt, D_totalDebt.sub(partialAmount))
    th.assertIsApproximatelyEqual(D_emittedColl, D_coll.sub(partialAmount.mul(mv._1e18BN).div(price)))
  })

  it("redeemCollateral(): a redemption that closes a cdp leaves the cdp's ETH surplus (collateral - ETH drawn) available for the cdp owner to claim", async () => {
    const {
      A_netDebt, A_coll,
      B_netDebt, B_coll,
      C_netDebt, C_coll,
    } = await redeemCollateral3Full1Partial()

    const A_balanceBefore = toBN(await contracts.collateral.balanceOf(A))
    const B_balanceBefore = toBN(await contracts.collateral.balanceOf(B))
    const C_balanceBefore = toBN(await contracts.collateral.balanceOf(C))

    // CollSurplusPool endpoint cannot be called directly
    await assertRevert(collSurplusPool.claimSurplusCollShares(A), 'CollSurplusPool: Caller is not Borrower Operations')

    const A_GAS = th.gasUsed(await borrowerOperations.claimSurplusCollShares({ from: A, gasPrice: GAS_PRICE  }))
    const B_GAS = th.gasUsed(await borrowerOperations.claimSurplusCollShares({ from: B, gasPrice: GAS_PRICE  }))
    const C_GAS = th.gasUsed(await borrowerOperations.claimSurplusCollShares({ from: C, gasPrice: GAS_PRICE  }))

    const A_expectedBalance = A_balanceBefore
    const B_expectedBalance = B_balanceBefore
    const C_expectedBalance = C_balanceBefore

    const A_balanceAfter = toBN(await contracts.collateral.balanceOf(A))
    const B_balanceAfter = toBN(await contracts.collateral.balanceOf(B))
    const C_balanceAfter = toBN(await contracts.collateral.balanceOf(C))

    const price = toBN(await priceFeed.getPrice())

    th.assertIsApproximatelyEqual(A_balanceAfter, A_expectedBalance.add(A_coll.sub(A_netDebt.mul(mv._1e18BN).div(price)).add(liqReward)))
    th.assertIsApproximatelyEqual(B_balanceAfter, B_expectedBalance.add(B_coll.sub(B_netDebt.mul(mv._1e18BN).div(price)).add(liqReward)))
    th.assertIsApproximatelyEqual(C_balanceAfter, C_expectedBalance.add(C_coll.sub(C_netDebt.mul(mv._1e18BN).div(price)).add(liqReward)))
  })

  it("redeemCollateral(): a redemption that closes a cdp leaves the cdp's ETH surplus (collateral - ETH drawn) available for the cdp owner after re-opening cdp", async () => {
    const {
      A_netDebt, A_coll: A_collBefore,
      B_netDebt, B_coll: B_collBefore,
      C_netDebt, C_coll: C_collBefore,
    } = await redeemCollateral3Full1Partial()

    const price = await priceFeed.getPrice()
    const A_surplus = A_collBefore.sub(A_netDebt.mul(mv._1e18BN).div(price)).add(liqReward)
    const B_surplus = B_collBefore.sub(B_netDebt.mul(mv._1e18BN).div(price)).add(liqReward)
    const C_surplus = C_collBefore.sub(C_netDebt.mul(mv._1e18BN).div(price)).add(liqReward)

    const { collateral: A_coll } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: A } })
    const { collateral: B_coll } = await openCdp({ ICR: toBN(dec(190, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: B } })
    const { collateral: C_coll } = await openCdp({ ICR: toBN(dec(180, 16)), extraEBTCAmount: dec(100, 18), extraParams: { from: C } })
    let _aCdpId = await sortedCdps.cdpOfOwnerByIndex(A, 0);
    let _bCdpId = await sortedCdps.cdpOfOwnerByIndex(B, 0);
    let _cCdpId = await sortedCdps.cdpOfOwnerByIndex(C, 0);

    const A_collAfter = await cdpManager.getCdpCollShares(_aCdpId)
    const B_collAfter = await cdpManager.getCdpCollShares(_bCdpId)
    const C_collAfter = await cdpManager.getCdpCollShares(_cCdpId)

    assert.isTrue(A_collAfter.eq(A_coll))
    assert.isTrue(B_collAfter.eq(B_coll))
    assert.isTrue(C_collAfter.eq(C_coll))

    const A_balanceBefore = toBN(await contracts.collateral.balanceOf(A))
    const B_balanceBefore = toBN(await contracts.collateral.balanceOf(B))
    const C_balanceBefore = toBN(await contracts.collateral.balanceOf(C))

    const A_GAS = th.gasUsed(await borrowerOperations.claimSurplusCollShares({ from: A, gasPrice: GAS_PRICE  }))
    const B_GAS = th.gasUsed(await borrowerOperations.claimSurplusCollShares({ from: B, gasPrice: GAS_PRICE  }))
    const C_GAS = th.gasUsed(await borrowerOperations.claimSurplusCollShares({ from: C, gasPrice: GAS_PRICE  }))

    const A_expectedBalance = A_balanceBefore
    const B_expectedBalance = B_balanceBefore
    const C_expectedBalance = C_balanceBefore

    const A_balanceAfter = toBN(await contracts.collateral.balanceOf(A))
    const B_balanceAfter = toBN(await contracts.collateral.balanceOf(B))
    const C_balanceAfter = toBN(await contracts.collateral.balanceOf(C))

    th.assertIsApproximatelyEqual(A_balanceAfter, A_expectedBalance.add(A_surplus))
    th.assertIsApproximatelyEqual(B_balanceAfter, B_expectedBalance.add(B_surplus))
    th.assertIsApproximatelyEqual(C_balanceAfter, C_expectedBalance.add(C_surplus))
  })
 
  it('redeemCollateral(): reverts if fee eats up all returned collateral', async () => {
    // --- SETUP ---
    await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("10000")});
    const { ebtcAmount } = await openCdp({ ICR: toBN(dec(200, 16)), extraEBTCAmount: dec(1, 21), extraParams: { from: alice } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    await openCdp({ ICR: toBN(dec(150, 16)), extraParams: { from: bob } })

    const price = await priceFeed.getPrice()
    let _adjustColl = ebtcAmount.mul(mv._1e18BN).div(price);

    // --- TEST ---
    await th.syncTwapSystemDebt(contracts, ethers.provider);

    // keep redeeming until we get the base rate to the ceiling of 100%
    // With zero borrowing fee, [total supply of EBTC] is reduced since no more minting of fee to staking
    // thus the redemption rate is increased more quickly due to [total supply of EBTC] is used in denominator for rate update
    for (let i = 0; i < 1; i++) {
      // Find hints for redeeming
      const {
        firstRedemptionHint,
        partialRedemptionHintNICR
      } = await hintHelpers.getRedemptionHints(ebtcAmount, price, 0)

      // Don't pay for gas, as it makes it easier to calculate the received Ether
      const redemptionTx = await cdpManager.redeemCollateral(
        ebtcAmount,
        firstRedemptionHint,
        th.DUMMY_BYTES32,
        _aliceCdpId,
        partialRedemptionHintNICR,
        0, th._100pct,
        {
          from: alice,
          gasPrice: GAS_PRICE
        }
      )

      await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("10000")});
      await openCdp({ ICR: toBN(dec(150, 16)), extraParams: { from: bob } })
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("10000")});
      await collToken.deposit({from: alice, value: _adjustColl})
      await borrowerOperations.adjustCdpWithColl(_aliceCdpId, 0, ebtcAmount, true, _aliceCdpId, _aliceCdpId, _adjustColl, { from: alice })
    }

    const {
      firstRedemptionHint,
      partialRedemptionHintNICR
    } = await hintHelpers.getRedemptionHints(ebtcAmount, price, 0)
    // Since we apply static redemption fee rate, 
    // thus the fee calculated as [fixedRate.mul(_ETHDrawn).div(1e18)] 
    // would never exceed underlying collateral
    let _updatedBaseRate = await cdpManager.getUpdatedBaseRateFromRedemption(_adjustColl, price);
    let _updatedRate = _updatedBaseRate.add(await cdpManager.redemptionFeeFloor());
    assert.isTrue(_updatedRate.gt(mv._1e18BN));
    await assertRevert(
      cdpManager.redeemCollateral(
        ebtcAmount,
        firstRedemptionHint,
        th.DUMMY_BYTES32,
        _aliceCdpId,
        partialRedemptionHintNICR,
        0, th._100pct,
        {
          from: alice,
          gasPrice: GAS_PRICE
        }
      ),
      'CdpManager: Fee would eat up all returned collateral'
    )
  })

  it("getPendingRedistributedDebt(): Returns 0 if there is no pending EBTCDebt reward", async () => {
    // Make some cdps
    const { totalDebt } = await openCdp({ ICR: toBN(dec(2, 18)), extraEBTCAmount: dec(100, 18), extraParams: { from: defaulter_1 } })
    let _defaulter1CdpId = await sortedCdps.cdpOfOwnerByIndex(defaulter_1, 0);

    await openCdp({ ICR: toBN(dec(3, 18)), extraEBTCAmount: dec(20, 18), extraParams: { from: carol } })
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    await openCdp({ ICR: toBN(dec(20, 18)), extraEBTCAmount: totalDebt, extraParams: { from: whale } })

    // Price drops
    await priceFeed.setPrice(dec(3714, 13))

    await debtToken.transfer(owner, (await debtToken.balanceOf(defaulter_1)), {from: defaulter_1});	 
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from: carol});
    await cdpManager.liquidate(_defaulter1CdpId, {from: owner})

    // Confirm defaulter_1 liquidated
    assert.isFalse(await sortedCdps.contains(_defaulter1CdpId))

    // Confirm there are some pending rewards from liquidation
    const current_L_EBTCDebt = await cdpManager.systemDebtRedistributionIndex()
    assert.isTrue(current_L_EBTCDebt.gt(toBN('0')))

    const carolSnapshot_L_EBTCDebt = (await cdpManager.cdpDebtRedistributionIndex(_carolCdpId))
    assert.equal(carolSnapshot_L_EBTCDebt, 0)

    const carol_PendingRedistributedDebt = (await cdpManager.getPendingRedistributedDebt(_carolCdpId))
    assert.isTrue(carol_PendingRedistributedDebt.gt(toBN('0')))
  })

  it("getPendingETHReward(): Returns 0 if there is no pending ETH reward", async () => {
    // make some cdps
    const { totalDebt } = await openCdp({ ICR: toBN(dec(2, 18)), extraEBTCAmount: dec(100, 18), extraParams: { from: defaulter_1 } })
    let _defaulter1CdpId = await sortedCdps.cdpOfOwnerByIndex(defaulter_1, 0);

    await openCdp({ ICR: toBN(dec(3, 18)), extraEBTCAmount: dec(20, 18), extraParams: { from: carol } })
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

    await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("27000")});
    await openCdp({ ICR: toBN(dec(20, 18)), extraEBTCAmount: totalDebt, extraParams: { from: whale } })

    // Price drops
    await priceFeed.setPrice(dec(3714, 13))

    await debtToken.transfer(owner, (await debtToken.balanceOf(defaulter_1)), {from: defaulter_1});	 
    await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from: carol});	 
    await cdpManager.liquidate(_defaulter1CdpId, {from: owner})

    // Confirm defaulter_1 liquidated
    assert.isFalse(await sortedCdps.contains(_defaulter1CdpId))
  })

  // --- computeICR ---

  it("computeICR(): Returns 0 if cdp's coll is worth 0", async () => {
    const price = 0
    const coll = dec(1, 'ether')
    const debt = dec(100, 18)

    const ICR = (await cdpManager.computeICR(coll, debt, price)).toString()

    assert.equal(ICR, 0)
  })

  it("computeICR(): Returns 2^256-1 for ETH:USD = 1, coll = 100 ETH, debt = 100 EBTC", async () => {
    const price = dec(3714, 13);
    const coll = dec(100, 'ether')
    const debt = dec(1, 18)

    const ICR = (await cdpManager.computeICR(coll, debt, price)).toString()
    assert.equal(ICR, dec(3714, 15))
  })

  it("computeICR(): returns correct ICR for ETH:USD = 100, coll = 200 ETH, debt = 3 EBTC", async () => {
    const price = dec(3714, 13);
    const coll = dec(200, 'ether')
    const debt = dec(3, 18)

    const ICR = (await cdpManager.computeICR(coll, debt, price)).toString()
    assert.isAtMost(th.getDifference(ICR, '2476000000000000000'), 1000)
  })

  it("computeICR(): returns correct ICR for ETH:USD = 250, coll = 1350 ETH, debt = 127 EBTC", async () => {
    const price = '250000000000000000000'
    const coll = '1350000000000000000000'
    const debt = '127000000000000000000'

    const ICR = (await cdpManager.computeICR(coll, debt, price))

    assert.isAtMost(th.getDifference(ICR, '2657480314960630000000'), 1000000)
  })

  it("computeICR(): returns correct ICR for ETH:USD = 100, coll = 1 ETH, debt = 54321 EBTC", async () => {
    const price = dec(3714, 13);
    const coll = dec(1, 'ether')
    const debt = '54321000000000000000000'

    const ICR = (await cdpManager.computeICR(coll, debt, price)).toString()
    assert.isAtMost(th.getDifference(ICR, '683713480974'), 1000)
  })


  it("computeICR(): Returns 2^256-1 if cdp has non-zero coll and zero debt", async () => {
    const price = dec(3714, 13);
    const coll = dec(1, 'ether')
    const debt = 0

    const ICR = web3.utils.toHex(await cdpManager.computeICR(coll, debt, price))
    const maxBytes32 = '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'

    assert.equal(ICR, maxBytes32)
  })

  // --- checkRecoveryMode ---

  //TCR < 150%
  it("checkRecoveryMode(): Returns true when TCR < 150%", async () => {
    await openCdp({ ICR: toBN(dec(151, 16)), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(151, 16)), extraParams: { from: bob } })

    await priceFeed.setPrice(dec(3714, 13))

    const TCR = (await th.getCachedTCR(contracts))

    assert.isTrue(TCR.lte(toBN('1500000000000000000')))

    assert.isTrue(await th.checkRecoveryMode(contracts))
  })

  // TCR == 150%
  it("checkRecoveryMode(): Returns false when TCR == 150%", async () => {
    await priceFeed.setPrice(dec(3714, 13))

    await openCdp({ ICR: toBN(dec(1501, 15)), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(1501, 15)), extraParams: { from: bob } })

    const TCR = (await th.getCachedTCR(contracts))
    assert.equal(TCR, '1500999999999999999')

    assert.isFalse(await th.checkRecoveryMode(contracts))
  })

  // > 150%
  it("checkRecoveryMode(): Returns false when TCR > 150%", async () => {
    await priceFeed.setPrice(dec(3714, 13))

    await openCdp({ ICR: toBN(dec(1501, 15)), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(1501, 15)), extraParams: { from: bob } })

    await priceFeed.setPrice(dec(3800, 13))

    const TCR = (await th.getCachedTCR(contracts))

    assert.isTrue(TCR.gte(toBN('1500000000000000000')))

    assert.isFalse(await th.checkRecoveryMode(contracts))
  })

  // check 0
  it("checkRecoveryMode(): Returns false when TCR == 0", async () => {
    await priceFeed.setPrice(dec(3714, 13))

    await openCdp({ ICR: toBN(dec(1501, 15)), extraParams: { from: alice } })
    await openCdp({ ICR: toBN(dec(1501, 15)), extraParams: { from: bob } })

    await priceFeed.setPrice(0)

    const TCR = (await th.getCachedTCR(contracts)).toString()

    assert.equal(TCR, 0)

    assert.isTrue(await th.checkRecoveryMode(contracts))
  })

  // --- Getters ---

  it("getCdpStake(): Returns stake", async () => {
    const { collateral: A_coll } = await openCdp({ ICR: toBN(dec(1501, 15)), extraParams: { from: A } })
    const { collateral: B_coll } = await openCdp({ ICR: toBN(dec(1501, 15)), extraParams: { from: B } })
    let _aCdpId = await sortedCdps.cdpOfOwnerByIndex(A, 0);
    let _bCdpId = await sortedCdps.cdpOfOwnerByIndex(B, 0);

    const A_Stake = await cdpManager.getCdpStake(_aCdpId)
    const B_Stake = await cdpManager.getCdpStake(_bCdpId)

    assert.equal(A_Stake, A_coll.toString())
    assert.equal(B_Stake, B_coll.toString())
  })

  it("getCdpCollShares(): Returns coll", async () => {
    const { collateral: A_coll } = await openCdp({ ICR: toBN(dec(1501, 15)), extraParams: { from: A } })
    const { collateral: B_coll } = await openCdp({ ICR: toBN(dec(1501, 15)), extraParams: { from: B } })
    let _aCdpId = await sortedCdps.cdpOfOwnerByIndex(A, 0);
    let _bCdpId = await sortedCdps.cdpOfOwnerByIndex(B, 0);

    assert.equal(await cdpManager.getCdpCollShares(_aCdpId), A_coll.toString())
    assert.equal(await cdpManager.getCdpCollShares(_bCdpId), B_coll.toString())
  })

  it("getCdpDebt(): Returns debt", async () => {
    const { totalDebt: totalDebtA } = await openCdp({ ICR: toBN(dec(1501, 15)), extraParams: { from: A } })
    const { totalDebt: totalDebtB } = await openCdp({ ICR: toBN(dec(1501, 15)), extraParams: { from: B } })
    let _aCdpId = await sortedCdps.cdpOfOwnerByIndex(A, 0);
    let _bCdpId = await sortedCdps.cdpOfOwnerByIndex(B, 0);

    const A_Debt = await cdpManager.getCdpDebt(_aCdpId)
    const B_Debt = await cdpManager.getCdpDebt(_bCdpId)

    // Expect debt = requested + 0.5% fee + 50 (due to gas comp)

    assert.equal(A_Debt, totalDebtA.toString())
    assert.equal(B_Debt, totalDebtB.toString())
  })

  it("getCdpStatus(): Returns status", async () => {
    const { totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(1501, 15)), extraParams: { from: B } })
    await openCdp({ ICR: toBN(dec(1501, 15)), extraEBTCAmount: B_totalDebt, extraParams: { from: A } })
    let _aCdpId = await sortedCdps.cdpOfOwnerByIndex(A, 0);
    let _bCdpId = await sortedCdps.cdpOfOwnerByIndex(B, 0);

    // to be able to repay:
    await ebtcToken.transfer(B, B_totalDebt, { from: A })
    await borrowerOperations.closeCdp(_bCdpId, {from: B})

    const A_Status = await cdpManager.getCdpStatus(_aCdpId)
    const B_Status = await cdpManager.getCdpStatus(_bCdpId)
    const C_Status = await cdpManager.getCdpStatus(C)

    assert.equal(A_Status, '1')  // active
    assert.equal(B_Status, '2')  // closed by user
    assert.equal(C_Status, '0')  // non-existent
  })

  it("hasPendingRedistributedDebt(): Returns false it cdp is not active", async () => {
    assert.isFalse(await cdpManager.hasPendingRedistributedDebt(alice))
  })
  
  it("CDPManager governance permissioned: requiresAuth() should only allow authorized caller", async() => {	  
      await assertRevert(cdpManager.someFunc1({from: alice}), "Auth: UNAUTHORIZED");   
	  	  
      assert.isTrue(authority.address == (await cdpManager.authority()));
      const accounts = await web3.eth.getAccounts()
      assert.isTrue(accounts[0] == (await authority.owner()));
      let _role123 = 123;
      let _func1Sig = await cdpManager.FUNC_SIG1();
      await authority.setRoleCapability(_role123, cdpManager.address, _func1Sig, true, {from: accounts[0]});	  
      await authority.setUserRole(alice, _role123, true, {from: accounts[0]});
      assert.isTrue((await authority.canCall(alice, cdpManager.address, _func1Sig)));
      await cdpManager.someFunc1({from: alice}); 
	  
  })
  
  it("CDPManager governance permissioned: setRedemptionFeeFloor() should only allow authorized caller", async() => {	  
      await assertRevert(cdpManager.setRedemptionFeeFloor(1, {from: alice}), "Auth: UNAUTHORIZED");   
	  	  
      assert.isTrue(authority.address == (await cdpManager.authority()));
      let _role123 = 123;
      let _funcSig = await cdpManager.FUNC_SIG_REDEMP_FLOOR();
      await authority.setRoleCapability(_role123, cdpManager.address, _funcSig, true, {from: accounts[0]});	  
      await authority.setUserRole(alice, _role123, true, {from: accounts[0]});
      assert.isTrue((await authority.canCall(alice, cdpManager.address, _funcSig)));
      await assertRevert(cdpManager.setRedemptionFeeFloor(1, {from: alice}), "CDPManager: new redemption fee floor is lower than minimum");
      let _newFloor = mv._1e18BN.mul(toBN("999")).div(toBN("1000"));
      assert.isTrue(_newFloor.gt(await cdpManager.redemptionFeeFloor()));
      await cdpManager.setRedemptionFeeFloor(_newFloor, {from: alice})
      assert.isTrue(_newFloor.eq(await cdpManager.redemptionFeeFloor()));
	  
  })
  
  it("CDPManager governance permissioned: setMinuteDecayFactor() should only allow authorized caller", async() => {	  
      await assertRevert(cdpManager.setMinuteDecayFactor(1, {from: alice}), "Auth: UNAUTHORIZED");   
	  	  
      assert.isTrue(authority.address == (await cdpManager.authority()));
      let _role123 = 123;
      let _funcSig = await cdpManager.FUNC_SIG_DECAY_FACTOR();
      await authority.setRoleCapability(_role123, cdpManager.address, _funcSig, true, {from: accounts[0]});	  
      await authority.setUserRole(alice, _role123, true, {from: accounts[0]});
      assert.isTrue((await authority.canCall(alice, cdpManager.address, _funcSig)));
	  
      // advance to sometime later to decay the baseRate
      let _minutes = 100
      await network.provider.send("evm_increaseTime", [_minutes * 60])
      await network.provider.send("evm_mine") 
      await cdpManager.setLastFeeOpTimeToNow();
      let _updatedBaseRate = await cdpManager.getDecayedBaseRate();
	  
      let _newFactor = toBN("1");
      assert.isTrue(_newFactor.lt(await cdpManager.minuteDecayFactor()));
      await cdpManager.setMinuteDecayFactor(_newFactor, {from: alice})
	  
      // check new factor
      assert.isTrue(_newFactor.eq(await cdpManager.minuteDecayFactor()));
	  
      // check baseRate updated according to previous factor
      assert.isTrue(_updatedBaseRate.eq(await cdpManager.baseRate()));
	  
  })
  
  it("CDPManager _updateLastRedemptionTimestamp(): use elapsed minutes instead block.timestamp", async() => {
	  
      // advance to sometime later to update lastRedemptionTimestamp
      await cdpManager.setLastFeeOpTimeToNow();
      let _opLastBefore = await cdpManager.lastRedemptionTimestamp();
	  
      let _minutes = 100
      let _seconds = 12 // this should not be included in updated lastRedemptionTimestamp
      await network.provider.send("evm_increaseTime", [_minutes * 60 + _seconds])
      await network.provider.send("evm_mine") 
	  
      // update to elapsed minute
      await cdpManager.unprotectedUpdateLastFeeOpTime();
      let _opLastAfter = await cdpManager.lastRedemptionTimestamp();
	  
      // final check
      let _expectedTime = _opLastBefore.add(toBN(_minutes * 60))
      assert.isTrue(_expectedTime.eq(_opLastAfter));
	  
  }) 

  it("check on HintHelpers.getRedemptionHints() during redemption: should return correct values if partial redemption occur", async () => {
    const { collateral: W_coll, totalDebt: W_totalDebt  } = await openCdp({ ICR: toBN(dec(20, 18)), extraParams: { from: whale } })

    // Alice opens cdp and transfers 1000 EBTC each to Erin, Flyn, Graham
    await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("270000")});
    const { collateral: A_coll, totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(127, 16)), extraEBTCAmount: dec(1, 17), extraParams: { from: alice } })

    // B, C, D open cdp
    await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("150000")});
    await _signer.sendTransaction({ to: carol, value: ethers.utils.parseEther("150000")});
    await _signer.sendTransaction({ to: dennis, value: ethers.utils.parseEther("150000")});
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(126, 16)), extraEBTCAmount: dec(1590, 18), extraParams: { from: bob } })
    const { collateral: C_coll, totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(600, 16)), extraEBTCAmount: dec(1090, 18), extraParams: { from: carol } })
    const { collateral: D_coll, totalDebt: D_totalDebt } = await openCdp({ ICR: toBN(dec(800, 16)), extraEBTCAmount: dec(1090, 18), extraParams: { from: dennis } })
    let _aCdpID = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    let _bCdpID = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    let _cCdpID = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    let _dCdpID = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);

    const totalDebt = W_totalDebt.add(A_totalDebt).add(B_totalDebt).add(C_totalDebt).add(D_totalDebt)

    const price = await priceFeed.getPrice()

    const _partialRedeem_EBTC = B_totalDebt.add(toBN('123456789'))

    let firstRedemptionHint
    let partialRedemptionHintNICR
    let truncatedEBTCamount
    let partialRedemptionNewColl

    // redeems hint with CDP ordering from lowest ICR: B < A < C < D < W
    ({
      firstRedemptionHint,
      partialRedemptionHintNICR,
      truncatedEBTCamount,
      partialRedemptionNewColl
    } = await hintHelpers.getRedemptionHints(_partialRedeem_EBTC, price, 0))
	
    assert.isTrue(firstRedemptionHint == _bCdpID);
    assert.isTrue(truncatedEBTCamount.eq(toBN(_partialRedeem_EBTC)));
	
    // A will be partially redeemed
    let _partialDebt = toBN(_partialRedeem_EBTC).sub(B_totalDebt)
    let _partialNewColl = A_coll.sub(_partialDebt.mul(mv._1e18BN).div(price));
    let _newPartialNICR = _partialNewColl.mul(toBN(dec(1,20))).div(A_totalDebt.sub(_partialDebt))
    assert.isTrue(partialRedemptionNewColl.eq(_partialNewColl));
    assert.isTrue(partialRedemptionHintNICR.eq(_newPartialNICR));

    // redeems only with full redemption of CDP, skip partially due to minimum CDP size check
    const _onlyFullRedeem_EBTC = B_totalDebt.add(A_totalDebt).sub(toBN('1234567890'));
	
    let _hints = await hintHelpers.getRedemptionHints(_onlyFullRedeem_EBTC, price, 0)
    let firstRedemptionHint2 = _hints[0]
    let partialRedemptionHintNICR2 = _hints[1]
    let truncatedEBTCamount2 = _hints[2]
    let partialRedemptionNewColl2 = _hints[3]

    assert.isTrue(firstRedemptionHint2 == _bCdpID);
	
    // A will be skipped
    assert.isTrue(partialRedemptionHintNICR2.eq(toBN('0')));
	
    // only part of full redemption
    assert.isTrue(truncatedEBTCamount2.eq(B_totalDebt));
	
  }); 

  it("Partial redemption should only bail out if CDP drops below min size", async () => {
    const { collateral: W_coll, totalDebt: W_totalDebt  } = await openCdp({ ICR: toBN(dec(20, 18)), extraParams: { from: whale } })

    // Alice opens cdp
    await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("270000")});
    let _aICR = toBN(dec(111, 16));
    const { collateral: A_coll, totalDebt: A_totalDebt } = await openCdp({ICR : _aICR, extraEBTCAmount: dec(1, 17), extraParams: { from: alice } })
    let _aCdpID = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    const totalDebt = W_totalDebt.add(A_totalDebt)

    const price = await priceFeed.getPrice()
    let _oldIndex = mv._1e18BN;
    let _newIndex = toBN("1100000000000000000");	  	  
    await ethers.provider.send("evm_increaseTime", [86400]);
    await ethers.provider.send("evm_mine");
    await collToken.setEthPerShare(_newIndex);
    _newIndex = await collToken.getEthPerShare();
    console.log('_newIndex=' + _newIndex);

    const _leftColl = MIN_CDP_SIZE.mul(toBN("10001")).div(toBN("10000"))
    assert.isTrue((await collToken.getSharesByPooledEth(_leftColl)).lt(MIN_CDP_SIZE));
    let _aColl = (await cdpManager.getSyncedDebtAndCollShares(_aCdpID))[1]
    const _partialRedeem_EBTC = (_aColl).sub(_leftColl).mul(price).div(mv._1e18BN)

    let firstRedemptionHint
    let partialRedemptionHintNICR
    let truncatedEBTCamount
    let partialRedemptionNewColl

    // redeems hint with CDP ordering from lowest ICR: A < W
    ({
      firstRedemptionHint,
      partialRedemptionHintNICR,
      truncatedEBTCamount,
      partialRedemptionNewColl
    } = await hintHelpers.getRedemptionHints(_partialRedeem_EBTC, price, 0))
	
    // check hints to indicate CDP will be partially redeemed
    assert.isTrue(firstRedemptionHint == _aCdpID);
    assert.isTrue(truncatedEBTCamount.eq(_partialRedeem_EBTC));	
    let _deltaFeePerUnit = (await cdpManager.calcFeeUponStakingReward(_newIndex, _oldIndex))[1];
    let _newStFeePerUnit = _deltaFeePerUnit.add(await cdpManager.systemStEthFeePerUnitIndex());
    let _collAfterFee = (await cdpManager.getAccumulatedFeeSplitApplied(_aCdpID, _newStFeePerUnit))[1];
    let _partialNewColl = _collAfterFee.sub(await collToken.getSharesByPooledEth(_partialRedeem_EBTC.mul(mv._1e18BN).div(price)));	
    let _newPartialNICR = _partialNewColl.mul(toBN(dec(1,20))).div(A_totalDebt.sub(_partialRedeem_EBTC))
    assert.isTrue(partialRedemptionHintNICR.eq(_newPartialNICR));
    //console.log('truncatedEBTCamount=' + truncatedEBTCamount + ', A_totalDebt=' + A_totalDebt + ', _partialRedeem_EBTC=' + _partialRedeem_EBTC + ', partialRedemptionHintNICR=' + partialRedemptionHintNICR + ', partialRedemptionNewColl=' + partialRedemptionNewColl + ', _partialNewColl=' + _partialNewColl)
    assert.isTrue(partialRedemptionNewColl.eq(_partialNewColl));
	
    // redemption should leave CDP partially redeemed
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_WEEK * 2, web3.currentProvider)
    await cdpManager.redeemCollateral(
      _partialRedeem_EBTC,
      firstRedemptionHint,
      firstRedemptionHint,
      firstRedemptionHint,
      partialRedemptionHintNICR,
      0, th._100pct,
      {
        from: alice,
        gasPrice: GAS_PRICE
      }
    )
    let _debtAfter = await cdpManager.getCdpDebt(_aCdpID);
    assert.isTrue(_debtAfter.eq(A_totalDebt.sub(_partialRedeem_EBTC)));  
	
  });
  
})

contract('Reset chain state', async accounts => { })
