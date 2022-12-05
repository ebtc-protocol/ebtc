const deploymentHelper = require("../utils/deploymentHelpers.js")
const testHelpers = require("../utils/testHelpers.js")

const SortedTroves = artifacts.require("SortedTroves")
const SortedTrovesTester = artifacts.require("SortedTrovesTester")
const TroveManagerTester = artifacts.require("TroveManagerTester")
const EBTCToken = artifacts.require("EBTCToken")

const th = testHelpers.TestHelper
const dec = th.dec
const toBN = th.toBN
const mv = testHelpers.MoneyValues

const hre = require("hardhat");

contract('SortedTroves', async accounts => {
  
  const assertSortedListIsOrdered = async (contracts) => {
    const price = await contracts.priceFeedTestnet.getPrice()

    let trove = await contracts.sortedTroves.getLast()
    while (trove !== (await contracts.sortedTroves.getFirst())) {
      
      // Get the adjacent upper trove ("prev" moves up the list, from lower ICR -> higher ICR)
      const prevTrove = await contracts.sortedTroves.getPrev(trove)
     
      const troveICR = await contracts.troveManager.getCurrentICR(trove, price)
      const prevTroveICR = await contracts.troveManager.getCurrentICR(prevTrove, price)
      
      assert.isTrue(prevTroveICR.gte(troveICR))

      const troveNICR = await contracts.troveManager.getNominalICR(trove)
      const prevTroveNICR = await contracts.troveManager.getNominalICR(prevTrove)
      
      assert.isTrue(prevTroveNICR.gte(troveNICR))

      // climb the list
      trove = prevTrove
    }
  }

  const [
    owner,
    alice, bob, carol, dennis, erin,
    defaulter_1,
    A, B, C, D, E, F, G, H, whale] = accounts;

  let priceFeed
  let sortedTroves
  let troveManager
  let borrowerOperations
  let ebtcToken

  const [bountyAddress, lpRewardsAddress, multisig] = accounts.slice(accounts.length - 3, accounts.length)
  const bn8 = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";//wrapped Ether
  let bn8Signer;

  let contracts

  const getOpenTroveEBTCAmount = async (totalDebt) => th.getOpenTroveEBTCAmount(contracts, totalDebt)
  const openTrove = async (params) => th.openTrove(contracts, params)

  describe('SortedTroves', () => {	

    before(async () => {	
      await hre.network.provider.request({method: "hardhat_impersonateAccount", params: [bn8]}); 
      bn8Signer = await ethers.provider.getSigner(bn8);
    })  
	
    beforeEach(async () => {
      contracts = await deploymentHelper.deployLiquityCore()
      contracts.troveManager = await TroveManagerTester.new()
      contracts.ebtcToken = await EBTCToken.new(
        contracts.troveManager.address,
        contracts.stabilityPool.address,
        contracts.borrowerOperations.address
      )
      const LQTYContracts = await deploymentHelper.deployLQTYContracts(bountyAddress, lpRewardsAddress, multisig)

      priceFeed = contracts.priceFeedTestnet
      sortedTroves = contracts.sortedTroves
      troveManager = contracts.troveManager
      borrowerOperations = contracts.borrowerOperations
      ebtcToken = contracts.ebtcToken

      await deploymentHelper.connectLQTYContracts(LQTYContracts)
      await deploymentHelper.connectCoreContracts(contracts, LQTYContracts)
      await deploymentHelper.connectLQTYContractsToCore(LQTYContracts, contracts)
	
      ownerSigner = await ethers.provider.getSigner(owner);
      let _ownerBal = await web3.eth.getBalance(owner);
      let _bn8Bal = await web3.eth.getBalance(bn8);
      let _ownerRicher = toBN(_ownerBal.toString()).gt(toBN(_bn8Bal.toString()));
      let _signer = _ownerRicher? ownerSigner : bn8Signer;
    
      await _signer.sendTransaction({ to: carol, value: ethers.utils.parseEther("21000")});
      await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("21000")});
      await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("21000")});
      
      const signer_address = await _signer.getAddress()
      const b8nSigner_address = await bn8Signer.getAddress()
  
      // Ensure bn8Signer has funds if it doesn't in this fork state
      if (signer_address != b8nSigner_address) {
        await _signer.sendTransaction({ to: b8nSigner_address, value: ethers.utils.parseEther("2000000")});
      }
    })

    it('contains(): returns true for addresses that have opened troves', async () => {
      await openTrove({ ICR: toBN(dec(150, 16)), extraParams: { from: alice } })
      let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
      await openTrove({ ICR: toBN(dec(20, 18)), extraParams: { from: bob } })
      let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
      await openTrove({ ICR: toBN(dec(2000, 18)), extraParams: { from: carol } })
      let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);

      // Confirm trove statuses became active
      assert.equal((await troveManager.Troves(_aliceTroveId))[3], '1')
      assert.equal((await troveManager.Troves(_bobTroveId))[3], '1')
      assert.equal((await troveManager.Troves(_carolTroveId))[3], '1')

      // Check sorted list contains troves
      assert.isTrue(await sortedTroves.contains(_aliceTroveId))
      assert.isTrue(await sortedTroves.contains(_bobTroveId))
      assert.isTrue(await sortedTroves.contains(_carolTroveId))
    })

    it('contains(): returns false for addresses that have not opened troves', async () => {
      await openTrove({ ICR: toBN(dec(150, 16)), extraParams: { from: alice } })
      await openTrove({ ICR: toBN(dec(20, 18)), extraParams: { from: bob } })
      await openTrove({ ICR: toBN(dec(2000, 18)), extraParams: { from: carol } })

      // Confirm troves have non-existent status
      assert.equal((await troveManager.Troves(dennis))[3], '0')
      assert.equal((await troveManager.Troves(erin))[3], '0')

      // Check sorted list do not contain troves
      assert.isFalse(await sortedTroves.contains(dennis))
      assert.isFalse(await sortedTroves.contains(erin))
    })

    it('contains(): returns false for addresses that opened and then closed a trove', async () => {
      await openTrove({ ICR: toBN(dec(1000, 18)), extraEBTCAmount: toBN(dec(3000, 18)), extraParams: { from: whale } })

      await openTrove({ ICR: toBN(dec(150, 16)), extraParams: { from: alice } })
      let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
      await openTrove({ ICR: toBN(dec(20, 18)), extraParams: { from: bob } })
      let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
      await openTrove({ ICR: toBN(dec(2000, 18)), extraParams: { from: carol } })
      let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);

      // to compensate borrowing fees
      await ebtcToken.transfer(alice, dec(1000, 18), { from: whale })
      await ebtcToken.transfer(bob, dec(1000, 18), { from: whale })
      await ebtcToken.transfer(carol, dec(1000, 18), { from: whale })

      // A, B, C close troves
      await borrowerOperations.closeTrove(_aliceTroveId, { from: alice })
      await borrowerOperations.closeTrove(_bobTroveId, { from:bob })
      await borrowerOperations.closeTrove(_carolTroveId, { from:carol })

      // Confirm trove statuses became closed
      assert.equal((await troveManager.Troves(_aliceTroveId))[3], '2')
      assert.equal((await troveManager.Troves(_bobTroveId))[3], '2')
      assert.equal((await troveManager.Troves(_carolTroveId))[3], '2')

      // Check sorted list does not contain troves
      assert.isFalse(await sortedTroves.contains(_aliceTroveId))
      assert.isFalse(await sortedTroves.contains(_bobTroveId))
      assert.isFalse(await sortedTroves.contains(_carolTroveId))
    })

    // true for addresses that opened -> closed -> opened a trove
    it('contains(): returns true for addresses that opened, closed and then re-opened a trove', async () => {
      await openTrove({ ICR: toBN(dec(1000, 18)), extraEBTCAmount: toBN(dec(3000, 18)), extraParams: { from: whale } })

      await openTrove({ ICR: toBN(dec(150, 16)), extraParams: { from: alice } })
      let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
      await openTrove({ ICR: toBN(dec(20, 18)), extraParams: { from: bob } })
      let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
      await openTrove({ ICR: toBN(dec(2000, 18)), extraParams: { from: carol } })
      let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);

      // to compensate borrowing fees
      await ebtcToken.transfer(alice, dec(1000, 18), { from: whale })
      await ebtcToken.transfer(bob, dec(1000, 18), { from: whale })
      await ebtcToken.transfer(carol, dec(1000, 18), { from: whale })

      // A, B, C close troves
      await borrowerOperations.closeTrove(_aliceTroveId, { from: alice })
      await borrowerOperations.closeTrove(_bobTroveId, { from:bob })
      await borrowerOperations.closeTrove(_carolTroveId, { from:carol })

      // Confirm trove statuses became closed
      assert.equal((await troveManager.Troves(_aliceTroveId))[3], '2')
      assert.equal((await troveManager.Troves(_bobTroveId))[3], '2')
      assert.equal((await troveManager.Troves(_carolTroveId))[3], '2')

      await openTrove({ ICR: toBN(dec(1000, 16)), extraParams: { from: alice } })
      let _aliceTroveId2 = await sortedTroves.troveOfOwnerByIndex(alice, 0);
      await openTrove({ ICR: toBN(dec(2000, 18)), extraParams: { from: bob } })
      let _bobTroveId2 = await sortedTroves.troveOfOwnerByIndex(bob, 0);
      await openTrove({ ICR: toBN(dec(3000, 18)), extraParams: { from: carol } })
      let _carolTroveId2 = await sortedTroves.troveOfOwnerByIndex(carol, 0);

      // Confirm trove statuses became open again
      assert.equal((await troveManager.Troves(_aliceTroveId2))[3], '1')
      assert.equal((await troveManager.Troves(_bobTroveId2))[3], '1')
      assert.equal((await troveManager.Troves(_carolTroveId2))[3], '1')

      // Check sorted list does  contain troves
      assert.isTrue(await sortedTroves.contains(_aliceTroveId2))
      assert.isTrue(await sortedTroves.contains(_bobTroveId2))
      assert.isTrue(await sortedTroves.contains(_carolTroveId2))
    })

    // false when list size is 0
    it('contains(): returns false when there are no troves in the system', async () => {
      assert.isFalse(await sortedTroves.contains(alice))
      assert.isFalse(await sortedTroves.contains(bob))
      assert.isFalse(await sortedTroves.contains(carol))
    })

    // true when list size is 1 and the trove the only one in system
    it('contains(): true when list size is 1 and the trove the only one in system', async () => {
      await openTrove({ ICR: toBN(dec(150, 16)), extraParams: { from: alice } })
      let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);

      assert.isTrue(await sortedTroves.contains(_aliceTroveId))
    })

    // false when list size is 1 and trove is not in the system
    it('contains(): false when list size is 1 and trove is not in the system', async () => {
      await openTrove({ ICR: toBN(dec(150, 16)), extraParams: { from: alice } })

      assert.isFalse(await sortedTroves.contains(bob))
    })

    // --- getMaxSize ---

    it("getMaxSize(): Returns the maximum list size", async () => {
      const max = await sortedTroves.getMaxSize()
      assert.equal(web3.utils.toHex(max), th.maxBytes32)
    })

    // --- findInsertPosition ---

    it("Finds the correct insert position given two addresses that loosely bound the correct position", async () => { 
      await priceFeed.setPrice(dec(100, 18))

      // NICR sorted in descending order
      await openTrove({ ICR: toBN(dec(500, 18)), extraParams: { from: whale } })
      await openTrove({ ICR: toBN(dec(10, 18)), extraParams: { from: A } })
      let _aTroveId = await sortedTroves.troveOfOwnerByIndex(A, 0);
      await openTrove({ ICR: toBN(dec(5, 18)), extraParams: { from: B } })
      let _bTroveId = await sortedTroves.troveOfOwnerByIndex(B, 0);
      await openTrove({ ICR: toBN(dec(250, 16)), extraParams: { from: C } })
      let _cTroveId = await sortedTroves.troveOfOwnerByIndex(C, 0);
      await openTrove({ ICR: toBN(dec(166, 16)), extraParams: { from: D } })
      await openTrove({ ICR: toBN(dec(125, 16)), extraParams: { from: E } })
      let _eTroveId = await sortedTroves.troveOfOwnerByIndex(E, 0);

      // Expect a trove with NICR 300% to be inserted between B and C
      const targetNICR = dec(3, 18)

      // Pass addresses that loosely bound the right postiion
      const hints = await sortedTroves.findInsertPosition(targetNICR, _aTroveId, _eTroveId)

      // Expect the exact correct insert hints have been returned
      assert.equal(hints[0], _bTroveId)
      assert.equal(hints[1], _cTroveId)

      // The price doesn’t affect the hints
      await priceFeed.setPrice(dec(500, 18))
      const hints2 = await sortedTroves.findInsertPosition(targetNICR, _aTroveId, _eTroveId)

      // Expect the exact correct insert hints have been returned
      assert.equal(hints2[0], _bTroveId)
      assert.equal(hints2[1], _cTroveId)
    })

    //--- Ordering --- 
    // infinte ICR (zero collateral) is not possible anymore, therefore, skipping
    it.skip("stays ordered after troves with 'infinite' ICR receive a redistribution", async () => {

      // make several troves with 0 debt and collateral, in random order
      await borrowerOperations.openTrove(th._100pct, 0, whale, whale, { from: whale, value: dec(50, 'ether') })
      await borrowerOperations.openTrove(th._100pct, 0, A, A, { from: A, value: dec(1, 'ether') })
      await borrowerOperations.openTrove(th._100pct, 0, B, B, { from: B, value: dec(37, 'ether') })
      await borrowerOperations.openTrove(th._100pct, 0, C, C, { from: C, value: dec(5, 'ether') })
      await borrowerOperations.openTrove(th._100pct, 0, D, D, { from: D, value: dec(4, 'ether') })
      await borrowerOperations.openTrove(th._100pct, 0, E, E, { from: E, value: dec(19, 'ether') })

      // Make some troves with non-zero debt, in random order
      await borrowerOperations.openTrove(th._100pct, dec(5, 19), F, F, { from: F, value: dec(1, 'ether') })
      await borrowerOperations.openTrove(th._100pct, dec(3, 18), G, G, { from: G, value: dec(37, 'ether') })
      await borrowerOperations.openTrove(th._100pct, dec(2, 20), H, H, { from: H, value: dec(5, 'ether') })
      await borrowerOperations.openTrove(th._100pct, dec(17, 18), I, I, { from: I, value: dec(4, 'ether') })
      await borrowerOperations.openTrove(th._100pct, dec(5, 21), J, J, { from: J, value: dec(1345, 'ether') })

      const price_1 = await priceFeed.getPrice()
      
      // Check troves are ordered
      await assertSortedListIsOrdered(contracts)

      await borrowerOperations.openTrove(th._100pct, dec(100, 18), defaulter_1, defaulter_1, { from: defaulter_1, value: dec(1, 'ether') })
      assert.isTrue(await sortedTroves.contains(defaulter_1))

      // Price drops
      await priceFeed.setPrice(dec(100, 18))
      const price_2 = await priceFeed.getPrice()

      // Liquidate a trove
      await troveManager.liquidate(defaulter_1)
      assert.isFalse(await sortedTroves.contains(defaulter_1))

      // Check troves are ordered
      await assertSortedListIsOrdered(contracts)
    })
  })

  describe('SortedTroves with mock dependencies', () => {
    let sortedTrovesTester

    beforeEach(async () => {
      sortedTroves = await SortedTroves.new()
      sortedTrovesTester = await SortedTrovesTester.new()

      await sortedTrovesTester.setSortedTroves(sortedTroves.address)
    })

    context('when params are wrongly set', () => {
      it('setParams(): reverts if size is zero', async () => {
        await th.assertRevert(sortedTroves.setParams(0, sortedTrovesTester.address, sortedTrovesTester.address), 'SortedTroves: Size can’t be zero')
      })
    })

    context('when params are properly set', () => {
      beforeEach('set params', async() => {
        await sortedTroves.setParams(2, sortedTrovesTester.address, sortedTrovesTester.address)
      })

      it('insert(): fails if list is full', async () => {
        await sortedTrovesTester.insert(alice, 1, th.DUMMY_BYTES32, th.DUMMY_BYTES32)
        let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
        await sortedTrovesTester.insert(bob, 1, _aliceTroveId, _aliceTroveId)
        await th.assertRevert(sortedTrovesTester.insert(carol, 1, _aliceTroveId, _aliceTroveId), 'SortedTroves: List is full')
      })

      it('insert(): success even if list already contains the node', async () => {
        await sortedTrovesTester.insert(alice, 1, th.DUMMY_BYTES32, th.DUMMY_BYTES32)
        let _aliceTroves = await sortedTroves.troveCountOf(alice);
        assert.equal(_aliceTroves, 1);
		
        await sortedTrovesTester.insert(alice, 1, alice, alice)
        _aliceTroves = await sortedTroves.troveCountOf(alice);
        assert.equal(_aliceTroves, 2);
      })

      it('insert(): fails if id is zero', async () => {
        await th.assertRevert(sortedTrovesTester.insert(alice, th.DUMMY_BYTES32, 1, th.DUMMY_BYTES32, th.DUMMY_BYTES32), 'SortedTroves: Id cannot be zero')
      })

      it('insert(): fails if NICR is zero', async () => {
        await th.assertRevert(sortedTrovesTester.insert(alice, 0, th.DUMMY_BYTES32, th.DUMMY_BYTES32), 'SortedTroves: NICR must be positive')
      })

      it('remove(): fails if id is not in the list', async () => {
        await th.assertRevert(sortedTrovesTester.remove(alice), 'SortedTroves: List does not contain the id')
      })

      it('reInsert(): fails if list doesn’t contain the node', async () => {
        await th.assertRevert(sortedTrovesTester.reInsert(alice, 1, th.DUMMY_BYTES32, th.DUMMY_BYTES32), 'SortedTroves: List does not contain the id')
      })

      it('reInsert(): fails if new NICR is zero', async () => {
        await sortedTrovesTester.insert(alice, 1, th.DUMMY_BYTES32, th.DUMMY_BYTES32)
        let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
        assert.isTrue(await sortedTroves.contains(_aliceTroveId), 'list should contain element')
        await th.assertRevert(sortedTrovesTester.reInsert(_aliceTroveId, 0, _aliceTroveId, _aliceTroveId), 'SortedTroves: NICR must be positive')
        assert.isTrue(await sortedTroves.contains(_aliceTroveId), 'list should contain element')
      })

      it('findInsertPosition(): No prevId for hint - ascend list starting from nextId, result is after the tail', async () => {
        await sortedTrovesTester.insert(alice, 1, th.DUMMY_BYTES32, th.DUMMY_BYTES32)
        let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
        const pos = await sortedTroves.findInsertPosition(1, th.DUMMY_BYTES32, _aliceTroveId)
        assert.equal(pos[0], _aliceTroveId, 'prevId result should be nextId param')
        assert.equal(pos[1], th.DUMMY_BYTES32, 'nextId result should be zero')
      })
    })
  })
})
