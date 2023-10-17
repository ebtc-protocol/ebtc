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
  let collateral	

  const openCdp = async (params) => th.openCdp(contracts, params)

  beforeEach(async () => {
    await deploymentHelper.setDeployGasPrice(1000000000);
    contracts = await deploymentHelper.deployTesterContractsHardhat()
    let LQTYContracts = {}
    LQTYContracts.feeRecipient = contracts.feeRecipient;

    cdpManager = contracts.cdpManager
    priceFeed = contracts.priceFeedTestnet
    sortedCdps = contracts.sortedCdps
    debtToken = contracts.ebtcToken;
    collateral = contracts.collateral;

    await deploymentHelper.connectCoreContracts(contracts, LQTYContracts)
  })

  context('Batch liquidations', () => {
    const setup = async () => {
      const { collateral: A_coll, totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(296, 16)), extraParams: { from: alice } })
      const { collateral: B_coll, totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(280, 16)), extraParams: { from: bob } })
      const { collateral: C_coll, totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: carol } })
      let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
      let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
      let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);

      const totalLiquidatedDebt = A_totalDebt.add(B_totalDebt).add(C_totalDebt)

      await openCdp({ ICR: toBN(dec(340, 16)), extraEBTCAmount: totalLiquidatedDebt, extraParams: { from: whale } })

      // Price drops
      await priceFeed.setPrice(dec(3000, 13))
      const price = await priceFeed.getPrice()
      const TCR = await th.getCachedTCR(contracts)

      // Check Recovery Mode is active
      assert.isTrue(await th.checkRecoveryMode(contracts))

      // Check cdps A, B are in range 110% < ICR < TCR, C is below 100%
      const ICR_A = await cdpManager.getCachedICR(_aliceCdpId, price)
      const ICR_B = await cdpManager.getCachedICR(_bobCdpId, price)
      const ICR_C = await cdpManager.getCachedICR(_carolCdpId, price)

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
	  	  
      // trigger cooldown and pass the liq wait
      await th.syncGlobalStateAndGracePeriod(contracts, ethers.provider);
		
      let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
      await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});
      await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});
      const tx = await cdpManager.batchLiquidateCdps([_aliceCdpId])

      const TCR = await th.getCachedTCR(contracts)
      assert.isTrue(await th.checkRecoveryMode(contracts))
    })

    it('Two cdps over MCR are liquidated', async () => {
      let _setups = await setup()
      let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
      let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
      let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);		  
	  	  
      // trigger cooldown and pass the liq wait
      await th.syncGlobalStateAndGracePeriod(contracts, ethers.provider);
		
      await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});
      await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});
      await debtToken.transfer(owner, toBN((await debtToken.balanceOf(carol)).toString()), {from: carol});
      await debtToken.transfer(owner, toBN((await debtToken.balanceOf(whale)).toString()), {from: whale});
      let _balBefore = await collateral.balanceOf(owner);
      const tx = await cdpManager.batchLiquidateCdps([_aliceCdpId, _bobCdpId, _carolCdpId])
      let _balAfter = await collateral.balanceOf(owner);

      const liquidationEvents = th.getAllEventsByName(tx, 'CdpLiquidated')
      assert.equal(liquidationEvents.length, 3, 'Not enough liquidations')
      assert.equal(liquidationEvents[0].args[4].toString(), '5');//liquidateInRecoveryMode
      assert.equal(liquidationEvents[1].args[4].toString(), '5');//liquidateInRecoveryMode
      assert.equal(liquidationEvents[2].args[4].toString(), '4');//liquidateInNormalMode
      let _liquidator = th.getEventValByName(liquidationEvents[0], '_liquidator');
      assert.isTrue(_liquidator == owner);
      let _liqPremium1 = th.getEventValByName(liquidationEvents[0], '_premiumToLiquidator');
      let _liqPremium2 = th.getEventValByName(liquidationEvents[1], '_premiumToLiquidator');
      let _liqPremium3 = th.getEventValByName(liquidationEvents[2], '_premiumToLiquidator');
      let _liqPremium = _liqPremium1.add(_liqPremium2).add(_liqPremium3);
      let _liqDebt1 = th.getEventValByName(liquidationEvents[0], '_debt');
      let _liqDebt2 = th.getEventValByName(liquidationEvents[1], '_debt');
      let _liqDebt3 = th.getEventValByName(liquidationEvents[2], '_debt');
      let totalLiquidatedDebt = _liqDebt1.add(_liqDebt2).add(_liqDebt3);
      let _debtToColl = totalLiquidatedDebt.mul(mv._1e18BN).div(_setups['price']);
      let _premiumReceived = _balAfter.sub(_balBefore).sub(_debtToColl);
      assert.isTrue(_liqPremium.eq(_premiumReceived));

      // Confirm all cdps removed
      assert.isFalse(await sortedCdps.contains(_aliceCdpId))
      assert.isFalse(await sortedCdps.contains(_bobCdpId))
      assert.isFalse(await sortedCdps.contains(_carolCdpId))

      // Confirm cdps have status 'closed by liquidation' (Status enum element idx 3)
      assert.equal((await cdpManager.Cdps(_aliceCdpId))[4], '3')
      assert.equal((await cdpManager.Cdps(_bobCdpId))[4], '3')
      assert.equal((await cdpManager.Cdps(_carolCdpId))[4], '3')
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
      await priceFeed.setPrice(dec(3000, 13))
      const price = await priceFeed.getPrice()
      const TCR = await th.getCachedTCR(contracts)

      // Check Recovery Mode is active
      assert.isTrue(await th.checkRecoveryMode(contracts))

      // Check cdps A, B are in range 110% < ICR < TCR, C is below 100%
      const ICR_A = await cdpManager.getCachedICR(_aliceCdpId, price)
      const ICR_B = await cdpManager.getCachedICR(_bobCdpId, price)
      const ICR_C = await cdpManager.getCachedICR(_carolCdpId, price)

      assert.isTrue(ICR_A.gt(TCR))
      assert.isTrue(ICR_B.gt(mv._MCR) && ICR_B.lt(TCR))
      assert.isTrue(ICR_C.lt(mv._ICR100))		  
	  	  
      // trigger cooldown and pass the liq wait
      await cdpManager.syncGracePeriod();
      await ethers.provider.send("evm_increaseTime", [901]);
      await ethers.provider.send("evm_mine");

      await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});
      await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});
      await debtToken.transfer(owner, toBN((await debtToken.balanceOf(carol)).toString()), {from: carol});
      let _balBefore = await collateral.balanceOf(owner);
      const tx = await cdpManager.batchLiquidateCdps([_bobCdpId, _aliceCdpId])
      let _balAfter = await collateral.balanceOf(owner);

      const liquidationEvents = th.getAllEventsByName(tx, 'CdpLiquidated')
      assert.equal(liquidationEvents.length, 1, 'Not enough liquidations')
      let _liquidator = th.getEventValByName(liquidationEvents[0], '_liquidator');
      assert.isTrue(_liquidator == owner);
      let _liqPremium = th.getEventValByName(liquidationEvents[0], '_premiumToLiquidator');
      let _debtToColl = B_totalDebt.mul(mv._1e18BN).div(price);
      assert.isTrue(_liqPremium.eq(_balAfter.sub(_balBefore).sub(_debtToColl)));

      // Confirm only Bob’s cdp removed
      assert.isTrue(await sortedCdps.contains(_aliceCdpId))
      assert.isFalse(await sortedCdps.contains(_bobCdpId))
      assert.isTrue(await sortedCdps.contains(_carolCdpId))

      // Confirm cdps have status 'closed by liquidation' (Status enum element idx 3)
      assert.equal((await cdpManager.Cdps(_bobCdpId))[4], '3')
      // Confirm cdps have status 'open' (Status enum element idx 1)
      assert.equal((await cdpManager.Cdps(_aliceCdpId))[4], '1')
      assert.equal((await cdpManager.Cdps(_carolCdpId))[4], '1')
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
      await priceFeed.setPrice(dec(3000, 13))
      const price = await priceFeed.getPrice()
      const TCR = await th.getCachedTCR(contracts)

      // Check Recovery Mode is active
      assert.isTrue(await th.checkRecoveryMode(contracts))

      // Check cdps A, B are in range 110% < ICR < TCR, C is below 100%
      const ICR_A = await cdpManager.getCachedICR(_aliceCdpId, price)
      const ICR_B = await cdpManager.getCachedICR(_bobCdpId, price)

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
      let _setups = await setup()		  
	  	  
      // trigger cooldown and pass the liq wait
      await cdpManager.syncGracePeriod();
      await ethers.provider.send("evm_increaseTime", [901]);
      await ethers.provider.send("evm_mine");
		
      await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});
      await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});
      const tx = await th.liquidateCdps(1, _setups['price'], contracts, {extraParams: {from: owner}})

      const TCR = await th.getCachedTCR(contracts)
      assert.isTrue(await th.checkRecoveryMode(contracts))
    })

    it('Two cdps over MCR are liquidated', async () => {
      let _setups = await setup()
      let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
      let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);		  
	  	  
      // trigger cooldown and pass the liq wait
      await cdpManager.syncGracePeriod();
      await ethers.provider.send("evm_increaseTime", [901]);
      await ethers.provider.send("evm_mine");
		
      await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});
      await debtToken.transfer(owner, toBN((await debtToken.balanceOf(bob)).toString()), {from: bob});
      await debtToken.transfer(owner, toBN((await debtToken.balanceOf(whale)).toString()), {from: whale});
      let _balBefore = await collateral.balanceOf(owner);
      const tx = await th.liquidateCdps(10, _setups['price'], contracts, {extraParams: {from: owner}})
      let _balAfter = await collateral.balanceOf(owner);

      const liquidationEvents = th.getAllEventsByName(tx, 'CdpLiquidated')
      assert.equal(liquidationEvents.length, 2, 'Not enough liquidations')

      // Confirm all cdps removed
      assert.isFalse(await sortedCdps.contains(_aliceCdpId))
      assert.isFalse(await sortedCdps.contains(_bobCdpId))
      let _liquidator = th.getEventValByName(liquidationEvents[0], '_liquidator');
      assert.isTrue(_liquidator == owner);
      let _liqPremium1 = th.getEventValByName(liquidationEvents[0], '_premiumToLiquidator');
      let _liqPremium2 = th.getEventValByName(liquidationEvents[1], '_premiumToLiquidator');
      let _liqPremium = _liqPremium1.add(_liqPremium2);
      let _debtToColl = _setups['totalLiquidatedDebt'].mul(mv._1e18BN).div(_setups['price']);
      assert.isTrue(_liqPremium.eq(_balAfter.sub(_balBefore).sub(_debtToColl)));

      // Confirm cdps have status 'closed by liquidation' (Status enum element idx 3)
      assert.equal((await cdpManager.Cdps(_aliceCdpId))[4], '3')
      assert.equal((await cdpManager.Cdps(_bobCdpId))[4], '3')
    })
  })
})
