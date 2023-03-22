const deploymentHelper = require("../utils/deploymentHelpers.js")
const { TestHelper: th, MoneyValues: mv } = require("../utils/testHelpers.js")
const { toBN, dec, ZERO_ADDRESS } = th

const CdpManagerTester = artifacts.require("./CdpManagerTester")
const EBTCToken = artifacts.require("./EBTCToken.sol")

contract('CdpManager - in Recovery Mode - back to normal mode in 1 tx', async accounts => {
  const [bountyAddress, lpRewardsAddress, multisig] = accounts.slice(accounts.length - 3, accounts.length)
  const [
    owner,
    alice, bob, carol, dennis, erin, freddy, greta, harry, ida,
    whale, defaulter_1, defaulter_2, defaulter_3, defaulter_4,
    A, B, C, D, E, F, G, H, I
  ] = accounts;

  let contracts
  let cdpManager
  let priceFeed
  let sortedCdps

  const openCdp = async (params) => th.openCdp(contracts, params)

  beforeEach(async () => {
    contracts = await deploymentHelper.deployLiquityCore()
    contracts.cdpManager = await CdpManagerTester.new()
    contracts.ebtcToken = await EBTCToken.new(
      contracts.cdpManager.address,
      contracts.borrowerOperations.address
    )
    const LQTYContracts = await deploymentHelper.deployLQTYContracts(bountyAddress, lpRewardsAddress, multisig)

    cdpManager = contracts.cdpManager
    priceFeed = contracts.priceFeedTestnet
    sortedCdps = contracts.sortedCdps
    debtToken = contracts.ebtcToken;

    await deploymentHelper.connectLQTYContracts(LQTYContracts)
    await deploymentHelper.connectCoreContracts(contracts, LQTYContracts)
    await deploymentHelper.connectLQTYContractsToCore(LQTYContracts, contracts)
  })

  context('Batch liquidations', () => {
    const setup = async () => {
      const { collateral: A_coll, totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(296, 16)), extraParams: { from: alice } })
      const { collateral: B_coll, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(280, 16)), extraParams: { from: bob } })
      const { collateral: C_coll, totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(150, 16)), extraParams: { from: carol } })
      let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
      let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
      let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

      const totalLiquidatedDebt = A_totalDebt.add(B_totalDebt).add(C_totalDebt)

      await openCdp({ ICR: toBN(dec(340, 16)), extraEBTCAmount: totalLiquidatedDebt, extraParams: { from: whale } })

      // Price drops
      await priceFeed.setPrice(dec(3500, 13))
      const price = await priceFeed.getPrice()
      const TCR = await th.getTCR(contracts)

      // Check Recovery Mode is active
      assert.isTrue(await th.checkRecoveryMode(contracts))

      // Check cdps A, B are in range 110% < ICR < TCR, C is below 100%
      const ICR_A = await cdpManager.getCurrentICR(_aliceCdpId, price)
      const ICR_B = await cdpManager.getCurrentICR(_bobCdpId, price)
      const ICR_C = await cdpManager.getCurrentICR(_carolCdpId, price)

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

    it('First cdp only doesn’t get out of Recovery Mode', async () => {
      await setup()
      let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
      await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});
      await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});
      const tx = await cdpManager.batchLiquidateCdps([_aliceCdpId])

      const TCR = await th.getTCR(contracts)
      assert.isTrue(await th.checkRecoveryMode(contracts))
    })

    it('Two cdps over MCR are liquidated', async () => {
      await setup()
      let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
      let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
      let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
      await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});
      await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});
      await debtToken.transfer(owner, toBN((await debtToken.balanceOf(carol)).toString()), {from: carol});
      await debtToken.transfer(owner, toBN((await debtToken.balanceOf(whale)).toString()), {from: whale});
      const tx = await cdpManager.batchLiquidateCdps([_aliceCdpId, _bobCdpId, _carolCdpId])

      const liquidationEvents = th.getAllEventsByName(tx, 'CdpLiquidated')
      assert.equal(liquidationEvents.length, 3, 'Not enough liquidations')

      // Confirm all cdps removed
      assert.isFalse(await sortedCdps.contains(_aliceCdpId))
      assert.isFalse(await sortedCdps.contains(_bobCdpId))
      assert.isFalse(await sortedCdps.contains(_carolCdpId))

      // Confirm cdps have status 'closed by liquidation' (Status enum element idx 3)
      assert.equal((await cdpManager.Cdps(_aliceCdpId))[3], '3')
      assert.equal((await cdpManager.Cdps(_bobCdpId))[3], '3')
      assert.equal((await cdpManager.Cdps(_carolCdpId))[3], '3')
    })

    it('A cdp over TCR is not liquidated', async () => {
      const { collateral: A_coll, totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(280, 16)), extraParams: { from: alice } })
      const { collateral: B_coll, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(276, 16)), extraParams: { from: bob } })
      const { collateral: C_coll, totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(150, 16)), extraParams: { from: carol } })
      let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
      let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
      let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

      const totalLiquidatedDebt = A_totalDebt.add(B_totalDebt).add(C_totalDebt)

      await openCdp({ ICR: toBN(dec(310, 16)), extraEBTCAmount: totalLiquidatedDebt, extraParams: { from: whale } })

      // Price drops
      await priceFeed.setPrice(dec(3500, 13))
      const price = await priceFeed.getPrice()
      const TCR = await th.getTCR(contracts)

      // Check Recovery Mode is active
      assert.isTrue(await th.checkRecoveryMode(contracts))

      // Check cdps A, B are in range 110% < ICR < TCR, C is below 100%
      const ICR_A = await cdpManager.getCurrentICR(_aliceCdpId, price)
      const ICR_B = await cdpManager.getCurrentICR(_bobCdpId, price)
      const ICR_C = await cdpManager.getCurrentICR(_carolCdpId, price)

      assert.isTrue(ICR_A.gt(TCR))
      assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
      assert.isTrue(ICR_C.lt(mv._ICR100))

      await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});
      await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});
      await debtToken.transfer(owner, toBN((await debtToken.balanceOf(carol)).toString()), {from: carol});
      const tx = await cdpManager.batchLiquidateCdps([_bobCdpId, _aliceCdpId])

      const liquidationEvents = th.getAllEventsByName(tx, 'CdpLiquidated')
      assert.equal(liquidationEvents.length, 1, 'Not enough liquidations')

      // Confirm only Bob’s cdp removed
      assert.isTrue(await sortedCdps.contains(_aliceCdpId))
      assert.isFalse(await sortedCdps.contains(_bobCdpId))
      assert.isTrue(await sortedCdps.contains(_carolCdpId))

      // Confirm cdps have status 'closed by liquidation' (Status enum element idx 3)
      assert.equal((await cdpManager.Cdps(_bobCdpId))[3], '3')
      // Confirm cdps have status 'open' (Status enum element idx 1)
      assert.equal((await cdpManager.Cdps(_aliceCdpId))[3], '1')
      assert.equal((await cdpManager.Cdps(_carolCdpId))[3], '1')
    })
  })

  context('Sequential liquidations', () => {
    const setup = async () => {
      const { collateral: A_coll, totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(299, 16)), extraParams: { from: alice } })
      const { collateral: B_coll, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(298, 16)), extraParams: { from: bob } })
      let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
      let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);

      const totalLiquidatedDebt = A_totalDebt.add(B_totalDebt)

      await openCdp({ ICR: toBN(dec(300, 16)), extraEBTCAmount: totalLiquidatedDebt, extraParams: { from: whale } })
	  
      // Price drops
      await priceFeed.setPrice(dec(3500, 13))
      const price = await priceFeed.getPrice()
      const TCR = await th.getTCR(contracts)

      // Check Recovery Mode is active
      assert.isTrue(await th.checkRecoveryMode(contracts))

      // Check cdps A, B are in range 110% < ICR < TCR, C is below 100%
      const ICR_A = await cdpManager.getCurrentICR(_aliceCdpId, price)
      const ICR_B = await cdpManager.getCurrentICR(_bobCdpId, price)

      assert.isTrue(ICR_A.gt(mv._MCR) && ICR_A.lt(TCR))
      assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))

      return {
        A_coll, A_totalDebt,
        B_coll, B_totalDebt,
        totalLiquidatedDebt,
        price,
      }
    }

    it('First cdp only doesn’t get out of Recovery Mode', async () => {
      await setup()
      await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});
      await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});
      const tx = await cdpManager.liquidateCdps(1)

      const TCR = await th.getTCR(contracts)
      assert.isTrue(await th.checkRecoveryMode(contracts))
    })

    it('Two cdps over MCR are liquidated', async () => {
      await setup()
      let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
      let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
		
      await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});
      await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});
      await debtToken.transfer(owner, toBN((await debtToken.balanceOf(whale)).toString()), {from: whale});
      const tx = await cdpManager.liquidateCdps(10)

      const liquidationEvents = th.getAllEventsByName(tx, 'CdpLiquidated')
      assert.equal(liquidationEvents.length, 2, 'Not enough liquidations')

      // Confirm all cdps removed
      assert.isFalse(await sortedCdps.contains(_aliceCdpId))
      assert.isFalse(await sortedCdps.contains(_bobCdpId))

      // Confirm cdps have status 'closed by liquidation' (Status enum element idx 3)
      assert.equal((await cdpManager.Cdps(_aliceCdpId))[3], '3')
      assert.equal((await cdpManager.Cdps(_bobCdpId))[3], '3')
    })
  })
})
