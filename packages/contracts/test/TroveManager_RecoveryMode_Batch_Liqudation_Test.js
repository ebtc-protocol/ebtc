const deploymentHelper = require("../utils/deploymentHelpers.js")
const { TestHelper: th, MoneyValues: mv } = require("../utils/testHelpers.js")
const { toBN, dec, ZERO_ADDRESS } = th

const TroveManagerTester = artifacts.require("./TroveManagerTester")
const LUSDToken = artifacts.require("./LUSDToken.sol")

contract('TroveManager - in Recovery Mode - back to normal mode in 1 tx', async accounts => {
  const [bountyAddress, lpRewardsAddress, multisig] = accounts.slice(accounts.length - 3, accounts.length)
  const [
    owner,
    alice, bob, carol, dennis, erin, freddy, greta, harry, ida,
    whale, defaulter_1, defaulter_2, defaulter_3, defaulter_4,
    A, B, C, D, E, F, G, H, I
  ] = accounts;

  let contracts
  let troveManager
  let stabilityPool
  let priceFeed
  let sortedTroves

  const openTrove = async (params) => th.openTrove(contracts, params)

  beforeEach(async () => {
    contracts = await deploymentHelper.deployLiquityCore()
    contracts.troveManager = await TroveManagerTester.new()
    contracts.lusdToken = await LUSDToken.new(
      contracts.troveManager.address,
      contracts.stabilityPool.address,
      contracts.borrowerOperations.address
    )
    const LQTYContracts = await deploymentHelper.deployLQTYContracts(bountyAddress, lpRewardsAddress, multisig)

    troveManager = contracts.troveManager
    stabilityPool = contracts.stabilityPool
    priceFeed = contracts.priceFeedTestnet
    sortedTroves = contracts.sortedTroves
    debtToken = contracts.lusdToken;

    await deploymentHelper.connectLQTYContracts(LQTYContracts)
    await deploymentHelper.connectCoreContracts(contracts, LQTYContracts)
    await deploymentHelper.connectLQTYContractsToCore(LQTYContracts, contracts)
  })

  context('Batch liquidations', () => {
    const setup = async () => {
      const { collateral: A_coll, totalDebt: A_totalDebt } = await openTrove({ ICR: toBN(dec(296, 16)), extraParams: { from: alice } })
      const { collateral: B_coll, totalDebt: B_totalDebt } = await openTrove({ ICR: toBN(dec(280, 16)), extraParams: { from: bob } })
      const { collateral: C_coll, totalDebt: C_totalDebt } = await openTrove({ ICR: toBN(dec(150, 16)), extraParams: { from: carol } })
      let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
      let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
      let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);

      const totalLiquidatedDebt = A_totalDebt.add(B_totalDebt).add(C_totalDebt)

      await openTrove({ ICR: toBN(dec(340, 16)), extraLUSDAmount: totalLiquidatedDebt, extraParams: { from: whale } })
      await stabilityPool.provideToSP(totalLiquidatedDebt, ZERO_ADDRESS, { from: whale })

      // Price drops
      await priceFeed.setPrice(dec(100, 18))
      const price = await priceFeed.getPrice()
      const TCR = await th.getTCR(contracts)

      // Check Recovery Mode is active
      assert.isTrue(await th.checkRecoveryMode(contracts))

      // Check troves A, B are in range 110% < ICR < TCR, C is below 100%
      const ICR_A = await troveManager.getCurrentICR(_aliceTroveId, price)
      const ICR_B = await troveManager.getCurrentICR(_bobTroveId, price)
      const ICR_C = await troveManager.getCurrentICR(_carolTroveId, price)

      assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
      assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
      assert.isTrue(ICR_C.lt(mv._ICR100))

      return {
        A_coll, A_totalDebt,
        B_coll, B_totalDebt,
        C_coll, C_totalDebt,
        totalLiquidatedDebt,
        price,
      }
    }

    it('First trove only doesn’t get out of Recovery Mode', async () => {
      await setup()
      let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
      await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from : whale}); 
      await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol}); 
      await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob}); 
      await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice}); 
      const tx = await troveManager.liquidateInBatchRecovery([_aliceTroveId], {from : owner})

      const TCR = await th.getTCR(contracts)
      assert.isTrue(await th.checkRecoveryMode(contracts))
    })

    it('Two troves over MCR are liquidated', async () => {
      await setup()
      let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
      let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
      let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);
      await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from : whale}); 
      await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice}); 
      await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob}); 
      await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol}); 
      const tx = await troveManager.liquidateInBatchRecovery([_aliceTroveId, _bobTroveId, _carolTroveId], {from : owner})

      const liquidationEvents = th.getAllEventsByName(tx, 'TroveLiquidated')
      assert.equal(liquidationEvents.length, 3, 'Not enough liquidations')

      // Confirm all troves removed
      assert.isFalse(await sortedTroves.contains(_aliceTroveId))
      assert.isFalse(await sortedTroves.contains(_bobTroveId))
      assert.isFalse(await sortedTroves.contains(_carolTroveId))

      // Confirm troves have status 'closed by liquidation' (Status enum element idx 3)
      assert.equal((await troveManager.Troves(_aliceTroveId))[3], '3')
      assert.equal((await troveManager.Troves(_bobTroveId))[3], '3')
      assert.equal((await troveManager.Troves(_carolTroveId))[3], '3')
    })

    it('Stability Pool profit matches', async () => {
      const {
        A_coll, A_totalDebt,
        C_coll, C_totalDebt,
        totalLiquidatedDebt,
        price,
      } = await setup()
      let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
      let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
      let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);

      const spEthBefore = await stabilityPool.getETH()
      const spLusdBefore = await stabilityPool.getTotalLUSDDeposits()

      await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
      await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol}); 
      await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from : whale}); 
      await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob}); 
      const tx = await troveManager.liquidateInBatchRecovery([_aliceTroveId, _carolTroveId], {from : owner})

      // Confirm all troves removed
      assert.isFalse(await sortedTroves.contains(_aliceTroveId))
      assert.isFalse(await sortedTroves.contains(_carolTroveId))

      // Confirm troves have status 'closed by liquidation' (Status enum element idx 3)
      assert.equal((await troveManager.Troves(_aliceTroveId))[3], '3')
      assert.equal((await troveManager.Troves(_carolTroveId))[3], '3')

      const spEthAfter = await stabilityPool.getETH()
      const spLusdAfter = await stabilityPool.getTotalLUSDDeposits()

      // liquidate collaterals with the gas compensation fee subtracted
      const expectedCollateralLiquidatedA = th.applyLiquidationFee(toBN('0').mul(mv._MCR).div(price))
      const expectedCollateralLiquidatedC = th.applyLiquidationFee(C_coll)
      // Stability Pool gains
      const expectedGainInLUSD = toBN('0').mul(price).div(mv._1e18BN).sub(toBN('0'))
      const realGainInLUSD = spEthAfter.sub(spEthBefore).mul(price).div(mv._1e18BN).sub(spLusdBefore.sub(spLusdAfter))

      assert.equal(spEthAfter.sub(spEthBefore).toString(), expectedCollateralLiquidatedA.toString(), 'Stability Pool ETH doesn’t match')
      assert.equal(spLusdBefore.sub(spLusdAfter).toString(), toBN('0').toString(), 'Stability Pool LUSD doesn’t match')
      assert.equal(realGainInLUSD.toString(), expectedGainInLUSD.toString(), 'Stability Pool gains don’t match')
    })

    it('A trove over TCR is not liquidated', async () => {
      const { collateral: A_coll, totalDebt: A_totalDebt } = await openTrove({ ICR: toBN(dec(280, 16)), extraParams: { from: alice } })
      const { collateral: B_coll, totalDebt: B_totalDebt } = await openTrove({ ICR: toBN(dec(276, 16)), extraParams: { from: bob } })
      const { collateral: C_coll, totalDebt: C_totalDebt } = await openTrove({ ICR: toBN(dec(150, 16)), extraParams: { from: carol } })
      let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
      let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
      let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);

      const totalLiquidatedDebt = A_totalDebt.add(B_totalDebt).add(C_totalDebt)

      await openTrove({ ICR: toBN(dec(310, 16)), extraLUSDAmount: totalLiquidatedDebt, extraParams: { from: whale } })
      await stabilityPool.provideToSP(totalLiquidatedDebt, ZERO_ADDRESS, { from: whale })

      // Price drops
      await priceFeed.setPrice(dec(100, 18))
      const price = await priceFeed.getPrice()
      const TCR = await th.getTCR(contracts)

      // Check Recovery Mode is active
      assert.isTrue(await th.checkRecoveryMode(contracts))

      // Check troves A, B are in range 110% < ICR < TCR, C is below 100%
      const ICR_A = await troveManager.getCurrentICR(_aliceTroveId, price)
      const ICR_B = await troveManager.getCurrentICR(_bobTroveId, price)
      const ICR_C = await troveManager.getCurrentICR(_carolTroveId, price)

      assert.isTrue(ICR_A.gt(TCR))
      assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
      assert.isTrue(ICR_C.lt(mv._ICR100))

      await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
      await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob}); 
      const tx = await troveManager.liquidateInBatchRecovery([_bobTroveId, _aliceTroveId], {from : owner})

      const liquidationEvents = th.getAllEventsByName(tx, 'TroveLiquidated')
      assert.equal(liquidationEvents.length, 1, 'Not enough liquidations')

      // Confirm only Bob’s trove removed
      assert.isTrue(await sortedTroves.contains(_aliceTroveId))
      assert.isFalse(await sortedTroves.contains(_bobTroveId))
      assert.isTrue(await sortedTroves.contains(_carolTroveId))

      // Confirm troves have status 'closed by liquidation' (Status enum element idx 3)
      assert.equal((await troveManager.Troves(_bobTroveId))[3], '3')
      // Confirm troves have status 'open' (Status enum element idx 1)
      assert.equal((await troveManager.Troves(_aliceTroveId))[3], '1')
      assert.equal((await troveManager.Troves(_carolTroveId))[3], '1')
    })
  })

  context('Sequential liquidations', () => {
    const setup = async () => {
      const { collateral: A_coll, totalDebt: A_totalDebt } = await openTrove({ ICR: toBN(dec(299, 16)), extraParams: { from: alice } })
      const { collateral: B_coll, totalDebt: B_totalDebt } = await openTrove({ ICR: toBN(dec(298, 16)), extraParams: { from: bob } })
      let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
      let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);

      const totalLiquidatedDebt = A_totalDebt.add(B_totalDebt)

      await openTrove({ ICR: toBN(dec(300, 16)), extraLUSDAmount: totalLiquidatedDebt, extraParams: { from: whale } })
      await stabilityPool.provideToSP(totalLiquidatedDebt, ZERO_ADDRESS, { from: whale })

      // Price drops
      await priceFeed.setPrice(dec(100, 18))
      const price = await priceFeed.getPrice()
      const TCR = await th.getTCR(contracts)

      // Check Recovery Mode is active
      assert.isTrue(await th.checkRecoveryMode(contracts))

      // Check troves A, B are in range 110% < ICR < TCR, C is below 100%
      const ICR_A = await troveManager.getCurrentICR(_aliceTroveId, price)
      const ICR_B = await troveManager.getCurrentICR(_bobTroveId, price)

      assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
      assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
	  	  
      debtToken = contracts.lusdToken;

      return {
        A_coll, A_totalDebt,
        B_coll, B_totalDebt,
        totalLiquidatedDebt,
        price,
      }
    }

    it('First trove only doesn’t get out of Recovery Mode', async () => {
      await setup()
      await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from : whale});
      await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
      await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
      const tx = await troveManager.liquidateSequentiallyInRecovery(1, {from: owner})

      const TCR = await th.getTCR(contracts)
      assert.isTrue(await th.checkRecoveryMode(contracts))
    })

    it('Two troves over MCR are liquidated', async () => {
      await setup()
      let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
      let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
      await debtToken.transfer(owner, (await debtToken.balanceOf(whale)), {from : whale});
      await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
      await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
      const tx = await troveManager.liquidateSequentiallyInRecovery(10, {from: owner})

      const liquidationEvents = th.getAllEventsByName(tx, 'TroveLiquidated')
      assert.equal(liquidationEvents.length, 2, 'Not enough liquidations')

      // Confirm all troves removed
      assert.isFalse(await sortedTroves.contains(_aliceTroveId))
      assert.isFalse(await sortedTroves.contains(_bobTroveId))

      // Confirm troves have status 'closed by liquidation' (Status enum element idx 3)
      assert.equal((await troveManager.Troves(_aliceTroveId))[3], '3')
      assert.equal((await troveManager.Troves(_bobTroveId))[3], '3')
    })
  })
})
