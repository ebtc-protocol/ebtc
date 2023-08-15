const deploymentHelper = require("../utils/deploymentHelpers.js")
const testHelpers = require("../utils/testHelpers.js")

const SortedCdps = artifacts.require("SortedCdps")
const SortedCdpsTester = artifacts.require("SortedCdpsTester")
const CdpManagerTester = artifacts.require("CdpManagerTester")
const EBTCToken = artifacts.require("EBTCToken")

const th = testHelpers.TestHelper
const dec = th.dec
const toBN = th.toBN
const mv = testHelpers.MoneyValues

const hre = require("hardhat");

contract('SortedCdps', async accounts => {
  
  const assertSortedListIsOrdered = async (contracts) => {
    const price = await contracts.priceFeedTestnet.getPrice()

    let cdp = await contracts.sortedCdps.getLast()
    while (cdp !== (await contracts.sortedCdps.getFirst())) {
      
      // Get the adjacent upper cdp ("prev" moves up the list, from lower ICR -> higher ICR)
      const prevCdp = await contracts.sortedCdps.getPrev(cdp)
     
      const cdpICR = await contracts.cdpManager.getICR(cdp, price)
      const prevCdpICR = await contracts.cdpManager.getICR(prevCdp, price)
      
      assert.isTrue(prevCdpICR.gte(cdpICR))

      const cdpNICR = await contracts.cdpManager.getNominalICR(cdp)
      const prevCdpNICR = await contracts.cdpManager.getNominalICR(prevCdp)
      
      assert.isTrue(prevCdpNICR.gte(cdpNICR))

      // climb the list
      cdp = prevCdp
    }
  }

  const [
    owner,
    alice, bob, carol, dennis, erin,
    defaulter_1,
    A, B, C, D, E, F, G, H, whale] = accounts;

  let priceFeed
  let sortedCdps
  let cdpManager
  let borrowerOperations
  let ebtcToken

  const [bountyAddress, lpRewardsAddress, multisig] = accounts.slice(accounts.length - 3, accounts.length)
  const bn8 = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";//wrapped Ether
  let bn8Signer;

  let contracts

  const getOpenCdpEBTCAmount = async (totalDebt) => th.getOpenCdpEBTCAmount(contracts, totalDebt)
  const openCdp = async (params) => th.openCdp(contracts, params)

  const checkCdpId = async (_cdpId, _owner) => {
        assert.equal((await contracts.sortedCdps.getOwnerAddress(_cdpId)), _owner);
  }

  describe('SortedCdps', () => {	

    before(async () => {	
      await hre.network.provider.request({method: "hardhat_impersonateAccount", params: [bn8]}); 
      bn8Signer = await ethers.provider.getSigner(bn8);
    })  
	
    beforeEach(async () => {
      contracts = await deploymentHelper.deployTesterContractsHardhat()
      let LQTYContracts = {}
      LQTYContracts.feeRecipient = contracts.feeRecipient;

      priceFeed = contracts.priceFeedTestnet
      sortedCdps = contracts.sortedCdps
      cdpManager = contracts.cdpManager
      borrowerOperations = contracts.borrowerOperations
      ebtcToken = contracts.ebtcToken

      await deploymentHelper.connectCoreContracts(contracts, LQTYContracts)
	  
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

    it('batchRemove(): batch remove nodes from the list', async () => {
      await openCdp({ ICR: toBN(dec(30, 18)), extraParams: { from: A } })
      let _aCdpId = await sortedCdps.cdpOfOwnerByIndex(A, 0);
      await checkCdpId(_aCdpId, A);
      await openCdp({ ICR: toBN(dec(25, 18)), extraParams: { from: B } })
      let _bCdpId = await sortedCdps.cdpOfOwnerByIndex(B, 0);
      await checkCdpId(_bCdpId, B);
      await openCdp({ ICR: toBN(dec(20, 18)), extraParams: { from: C } })
      let _cCdpId = await sortedCdps.cdpOfOwnerByIndex(C, 0);
      await checkCdpId(_cCdpId, C);
      await openCdp({ ICR: toBN(dec(15, 18)), extraParams: { from: D } })
      let _dCdpId = await sortedCdps.cdpOfOwnerByIndex(D, 0);
      await checkCdpId(_dCdpId, D);

      // Confirm ordering
      let _first = await sortedCdps.getFirst();
      let _second = await sortedCdps.getNext(_first);
      let _third = await sortedCdps.getNext(_second);
      let _last = await sortedCdps.getNext(_third);
      assert.isTrue(_first == _aCdpId)
      assert.isTrue(_second == _bCdpId)
      assert.isTrue(_third == _cCdpId)
      assert.isTrue(_last == _dCdpId)
      assert.isTrue(_last == (await sortedCdps.getLast()))
      assert.isTrue(4 == (await sortedCdps.getSize()))
      assert.isTrue(await sortedCdps.contains(_bCdpId))
      assert.isTrue(await sortedCdps.contains(_cCdpId))
	  
      // batch remove revert case
      let _toRemoveIds = [_second];	  
      await th.assertRevert(cdpManager.sortedCdpsBatchRemove(_toRemoveIds), 'SortedCdps: batchRemove() only apply to multiple cdpIds!')
      _toRemoveIds = [_first, _last];	  
      await th.assertRevert(cdpManager.sortedCdpsBatchRemove(_toRemoveIds), 'SortedCdps: batchRemove() leave ZERO node left!')
	  
      // batch remove happy case
      _toRemoveIds = [_second, _third];
      await cdpManager.sortedCdpsBatchRemove(_toRemoveIds);
      _first = await sortedCdps.getFirst();
      _last = await sortedCdps.getNext(_first);
      assert.isTrue(_first == _aCdpId)
      assert.isTrue(_last == _dCdpId)
      assert.isTrue(_last == (await sortedCdps.getLast()))
      assert.isTrue(_first == (await sortedCdps.getPrev(_last)))
      assert.isTrue(2 == (await sortedCdps.getSize()))
      assert.isFalse(await sortedCdps.contains(_bCdpId))
      assert.isFalse(await sortedCdps.contains(_cCdpId))
    })

    it('batchRemove(): batch remove the first N', async () => {
      await openCdp({ ICR: toBN(dec(30, 18)), extraParams: { from: A } })
      let _aCdpId = await sortedCdps.cdpOfOwnerByIndex(A, 0);
      await checkCdpId(_aCdpId, A);
      await openCdp({ ICR: toBN(dec(25, 18)), extraParams: { from: B } })
      let _bCdpId = await sortedCdps.cdpOfOwnerByIndex(B, 0);
      await checkCdpId(_bCdpId, B);
      await openCdp({ ICR: toBN(dec(20, 18)), extraParams: { from: C } })
      let _cCdpId = await sortedCdps.cdpOfOwnerByIndex(C, 0);
      await checkCdpId(_cCdpId, C);
      await openCdp({ ICR: toBN(dec(15, 18)), extraParams: { from: D } })
      let _dCdpId = await sortedCdps.cdpOfOwnerByIndex(D, 0);
      await checkCdpId(_dCdpId, D);

      // Confirm ordering
      let _first = await sortedCdps.getFirst();
      let _second = await sortedCdps.getNext(_first);
      let _third = await sortedCdps.getNext(_second);
      let _last = await sortedCdps.getNext(_third);
      assert.isTrue(_first == _aCdpId)
      assert.isTrue(_second == _bCdpId)
      assert.isTrue(_third == _cCdpId)
      assert.isTrue(_last == _dCdpId)
      assert.isTrue(_last == (await sortedCdps.getLast()))
      assert.isTrue(4 == (await sortedCdps.getSize()))
      assert.isTrue(await sortedCdps.contains(_bCdpId))
      assert.isTrue(await sortedCdps.contains(_cCdpId))
	  
      // batch remove happy case
      _toRemoveIds = [_first, _second];
      await cdpManager.sortedCdpsBatchRemove(_toRemoveIds);
      _first = await sortedCdps.getFirst();
      _last = await sortedCdps.getNext(_first);
      assert.isTrue(_first == _cCdpId)
      assert.isTrue(_last == _dCdpId)
      assert.isTrue(_last == (await sortedCdps.getLast()))
      assert.isTrue(_first == (await sortedCdps.getPrev(_last)))
      assert.isTrue(2 == (await sortedCdps.getSize()))
      assert.isFalse(await sortedCdps.contains(_aCdpId))
      assert.isFalse(await sortedCdps.contains(_bCdpId))
    })

    it('contains(): returns true for addresses that have opened cdps', async () => {
      await openCdp({ ICR: toBN(dec(151, 16)), extraParams: { from: alice } })
      let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
      await checkCdpId(_aliceCdpId, alice);
      await openCdp({ ICR: toBN(dec(20, 18)), extraParams: { from: bob } })
      let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
      await checkCdpId(_bobCdpId, bob);
      await openCdp({ ICR: toBN(dec(2000, 18)), extraParams: { from: carol } })
      let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
      await checkCdpId(_carolCdpId, carol);

      // Confirm cdp statuses became active
      assert.equal((await cdpManager.Cdps(_aliceCdpId))[4], '1')
      assert.equal((await cdpManager.Cdps(_bobCdpId))[4], '1')
      assert.equal((await cdpManager.Cdps(_carolCdpId))[4], '1')

      // Check sorted list contains cdps
      assert.isTrue(await sortedCdps.contains(_aliceCdpId))
      assert.isTrue(await sortedCdps.contains(_bobCdpId))
      assert.isTrue(await sortedCdps.contains(_carolCdpId))
      assert.isFalse(await sortedCdps.contains(th.DUMMY_BYTES32))
    })

    it('contains(): returns false for addresses that have not opened cdps', async () => {
      await openCdp({ ICR: toBN(dec(151, 16)), extraParams: { from: alice } })
      await openCdp({ ICR: toBN(dec(20, 18)), extraParams: { from: bob } })
      await openCdp({ ICR: toBN(dec(2000, 18)), extraParams: { from: carol } })

      // Confirm cdps have non-existent status
      assert.equal((await cdpManager.Cdps(dennis))[3], '0')
      assert.equal((await cdpManager.Cdps(erin))[3], '0')

      // Check sorted list do not contain cdps
      assert.isFalse(await sortedCdps.contains(dennis))
      assert.isFalse(await sortedCdps.contains(erin))
    })

    it('contains(): returns false for addresses that opened and then closed a cdp', async () => {
      await openCdp({ ICR: toBN(dec(1000, 18)), extraEBTCAmount: toBN(dec(3000, 18)), extraParams: { from: whale } })

      await openCdp({ ICR: toBN(dec(151, 16)), extraParams: { from: alice } })
      let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
      await checkCdpId(_aliceCdpId, alice);
      await openCdp({ ICR: toBN(dec(20, 18)), extraParams: { from: bob } })
      let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
      await checkCdpId(_bobCdpId, bob);
      await openCdp({ ICR: toBN(dec(2000, 18)), extraParams: { from: carol } })
      let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
      await checkCdpId(_carolCdpId, carol);

      // to compensate borrowing fees
      await ebtcToken.transfer(alice, dec(1000, 18), { from: whale })
      await ebtcToken.transfer(bob, dec(1000, 18), { from: whale })
      await ebtcToken.transfer(carol, dec(1000, 18), { from: whale })

      // A, B, C close cdps
      await borrowerOperations.closeCdp(_aliceCdpId, { from: alice })
      await borrowerOperations.closeCdp(_bobCdpId, { from:bob })
      await borrowerOperations.closeCdp(_carolCdpId, { from:carol })

      // Confirm cdp statuses became closed
      assert.equal((await cdpManager.Cdps(_aliceCdpId))[4], '2')
      assert.equal((await cdpManager.Cdps(_bobCdpId))[4], '2')
      assert.equal((await cdpManager.Cdps(_carolCdpId))[4], '2')

      // Check sorted list does not contain cdps
      assert.isFalse(await sortedCdps.contains(_aliceCdpId))
      assert.isFalse(await sortedCdps.contains(_bobCdpId))
      assert.isFalse(await sortedCdps.contains(_carolCdpId))
    })

    // true for addresses that opened -> closed -> opened a cdp
    it('contains(): returns true for addresses that opened, closed and then re-opened a cdp', async () => {
      await openCdp({ ICR: toBN(dec(1000, 18)), extraEBTCAmount: toBN(dec(3000, 18)), extraParams: { from: whale } })

      await openCdp({ ICR: toBN(dec(151, 16)), extraParams: { from: alice } })
      let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
      await checkCdpId(_aliceCdpId, alice);
      await openCdp({ ICR: toBN(dec(20, 18)), extraParams: { from: bob } })
      let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
      await checkCdpId(_bobCdpId, bob);
      await openCdp({ ICR: toBN(dec(2000, 18)), extraParams: { from: carol } })
      let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
      await checkCdpId(_carolCdpId, carol);

      // to compensate borrowing fees
      await ebtcToken.transfer(alice, dec(1000, 18), { from: whale })
      await ebtcToken.transfer(bob, dec(1000, 18), { from: whale })
      await ebtcToken.transfer(carol, dec(1000, 18), { from: whale })

      // A, B, C close cdps
      await borrowerOperations.closeCdp(_aliceCdpId, { from: alice })
      await borrowerOperations.closeCdp(_bobCdpId, { from:bob })
      await borrowerOperations.closeCdp(_carolCdpId, { from:carol })

      // Confirm cdp statuses became closed
      assert.equal((await cdpManager.Cdps(_aliceCdpId))[4], '2')
      assert.equal((await cdpManager.Cdps(_bobCdpId))[4], '2')
      assert.equal((await cdpManager.Cdps(_carolCdpId))[4], '2')

      await openCdp({ ICR: toBN(dec(1000, 16)), extraParams: { from: alice } })
      let _aliceCdpId2 = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
      await checkCdpId(_aliceCdpId2, alice);
      await openCdp({ ICR: toBN(dec(2000, 18)), extraParams: { from: bob } })
      let _bobCdpId2 = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
      await checkCdpId(_bobCdpId2, bob);
      await openCdp({ ICR: toBN(dec(3000, 18)), extraParams: { from: carol } })
      let _carolCdpId2 = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
      await checkCdpId(_carolCdpId2, carol);

      // Confirm cdp statuses became open again
      assert.equal((await cdpManager.Cdps(_aliceCdpId2))[4], '1')
      assert.equal((await cdpManager.Cdps(_bobCdpId2))[4], '1')
      assert.equal((await cdpManager.Cdps(_carolCdpId2))[4], '1')

      // Check sorted list does  contain cdps
      assert.isTrue(await sortedCdps.contains(_aliceCdpId2))
      assert.isTrue(await sortedCdps.contains(_bobCdpId2))
      assert.isTrue(await sortedCdps.contains(_carolCdpId2))
    })

    // false when list size is 0
    it('contains(): returns false when there are no cdps in the system', async () => {
      assert.isFalse(await sortedCdps.contains(alice))
      assert.isFalse(await sortedCdps.contains(bob))
      assert.isFalse(await sortedCdps.contains(carol))
    })

    // true when list size is 1 and the cdp the only one in system
    it('contains(): true when list size is 1 and the cdp the only one in system', async () => {
      await openCdp({ ICR: toBN(dec(151, 16)), extraParams: { from: alice } })
      let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
      await checkCdpId(_aliceCdpId, alice);

      assert.isTrue(await sortedCdps.contains(_aliceCdpId))
    })

    // false when list size is 1 and cdp is not in the system
    it('contains(): false when list size is 1 and cdp is not in the system', async () => {
      await openCdp({ ICR: toBN(dec(151, 16)), extraParams: { from: alice } })

      assert.isFalse(await sortedCdps.contains(bob))
    })

    // --- getMaxSize ---

    it("getMaxSize(): Returns the maximum list size", async () => {
      const max = await sortedCdps.getMaxSize()
      assert.equal(web3.utils.toHex(max), th.maxBytes32)
    })

    it('getCdpsOf(): returns all user CDPs', async () => {
      // Open 3 cdps
      await openCdp({ ICR: toBN(dec(151, 16)), extraParams: { from: alice } })
      await openCdp({ ICR: toBN(dec(20, 18)), extraParams: { from: alice } })
      await openCdp({ ICR: toBN(dec(2000, 18)), extraParams: { from: alice } })
      const expectedCdps = [
          await sortedCdps.cdpOfOwnerByIndex(alice, 0),
          await sortedCdps.cdpOfOwnerByIndex(alice, 1),
          await sortedCdps.cdpOfOwnerByIndex(alice, 2)
      ];
      // Alice has 3 CDPs opened
      const cdps = await sortedCdps.getCdpsOf(alice);
      assert.equal(cdps.length, 3)
      // Make sure arrays are equal
      assert.deepEqual(cdps, expectedCdps);
    })

    it('getCdpsOf(): returns no CDPs if user didnt open one', async () => {
      // Alice has 3 CDPs opened
      const cdps = await sortedCdps.getCdpsOf(alice);
      assert.equal(cdps.length, 0)
      // Make sure arrays are equal
      assert.deepEqual(cdps, []);
    })

    // --- findInsertPosition ---

    it("Finds the correct insert position given two addresses that loosely bound the correct position", async () => { 
      await priceFeed.setPrice(dec(100, 18))

      // NICR sorted in descending order
      await openCdp({ ICR: toBN(dec(500, 18)), extraParams: { from: whale } })
      await openCdp({ ICR: toBN(dec(10, 18)), extraParams: { from: A } })
      let _aCdpId = await sortedCdps.cdpOfOwnerByIndex(A, 0);
      await checkCdpId(_aCdpId, A);
      await openCdp({ ICR: toBN(dec(5, 18)), extraParams: { from: B } })
      let _bCdpId = await sortedCdps.cdpOfOwnerByIndex(B, 0);
      await checkCdpId(_bCdpId, B);
      await openCdp({ ICR: toBN(dec(250, 16)), extraParams: { from: C } })
      let _cCdpId = await sortedCdps.cdpOfOwnerByIndex(C, 0);
      await checkCdpId(_cCdpId, C);
      await openCdp({ ICR: toBN(dec(166, 16)), extraParams: { from: D } })
      await openCdp({ ICR: toBN(dec(125, 16)), extraParams: { from: E } })
      let _eCdpId = await sortedCdps.cdpOfOwnerByIndex(E, 0);
      await checkCdpId(_eCdpId, E);

      // Expect a cdp with NICR 300% to be inserted between B and C
      const targetNICR = dec(3, 18)

      // Pass addresses that loosely bound the right postiion
      const hints = await sortedCdps.findInsertPosition(targetNICR, _aCdpId, _eCdpId)

      // Expect the exact correct insert hints have been returned
      assert.equal(hints[0], _bCdpId)
      assert.equal(hints[1], _cCdpId)

      // The price doesn’t affect the hints
      await priceFeed.setPrice(dec(500, 18))
      const hints2 = await sortedCdps.findInsertPosition(targetNICR, _aCdpId, _eCdpId)

      // Expect the exact correct insert hints have been returned
      assert.equal(hints2[0], _bCdpId)
      assert.equal(hints2[1], _cCdpId)
    })

    //--- Ordering --- 
    // infinte ICR (zero collateral) is not possible anymore, therefore, skipping
    it.skip("stays ordered after cdps with 'infinite' ICR receive a redistribution", async () => {

      // make several cdps with 0 debt and collateral, in random order
      await borrowerOperations.openCdp(0, whale, whale, { from: whale, value: dec(50, 'ether') })
      await borrowerOperations.openCdp(0, A, A, { from: A, value: dec(1, 'ether') })
      await borrowerOperations.openCdp(0, B, B, { from: B, value: dec(37, 'ether') })
      await borrowerOperations.openCdp(0, C, C, { from: C, value: dec(5, 'ether') })
      await borrowerOperations.openCdp(0, D, D, { from: D, value: dec(4, 'ether') })
      await borrowerOperations.openCdp(0, E, E, { from: E, value: dec(19, 'ether') })

      // Make some cdps with non-zero debt, in random order
      await borrowerOperations.openCdp(dec(5, 19), F, F, { from: F, value: dec(1, 'ether') })
      await borrowerOperations.openCdp(dec(3, 18), G, G, { from: G, value: dec(37, 'ether') })
      await borrowerOperations.openCdp(dec(2, 20), H, H, { from: H, value: dec(5, 'ether') })
      await borrowerOperations.openCdp(dec(17, 18), I, I, { from: I, value: dec(4, 'ether') })
      await borrowerOperations.openCdp(dec(5, 21), J, J, { from: J, value: dec(1345, 'ether') })

      const price_1 = await priceFeed.getPrice()
      
      // Check cdps are ordered
      await assertSortedListIsOrdered(contracts)

      await borrowerOperations.openCdp(dec(100, 18), defaulter_1, defaulter_1, { from: defaulter_1, value: dec(1, 'ether') })
      assert.isTrue(await sortedCdps.contains(defaulter_1))

      // Price drops
      await priceFeed.setPrice(dec(100, 18))
      const price_2 = await priceFeed.getPrice()

      // Liquidate a cdp
      await cdpManager.liquidate(defaulter_1)
      assert.isFalse(await sortedCdps.contains(defaulter_1))

      // Check cdps are ordered
      await assertSortedListIsOrdered(contracts)
    })
  })

  describe('SortedCdps with mock dependencies', () => {
    let sortedCdpsTester

    beforeEach(async () => {
      sortedCdpsTester = await SortedCdpsTester.new()
      sortedCdps = await SortedCdps.new(2, sortedCdpsTester.address, sortedCdpsTester.address)

      await sortedCdpsTester.setSortedCdps(sortedCdps.address)
    })

    context('when params are properly set', () => {
      beforeEach('', async() => {
        
      })

      it('insert(): fails if list is full', async () => {
        await sortedCdpsTester.insert(alice, 1, th.DUMMY_BYTES32, th.DUMMY_BYTES32)
        let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
        await sortedCdpsTester.insert(bob, 1, _aliceCdpId, _aliceCdpId)
        await th.assertRevert(sortedCdpsTester.insert(carol, 1, _aliceCdpId, _aliceCdpId), 'SortedCdps: List is full')
      })

      it('insert(): success even if list already contains the node', async () => {
        await sortedCdpsTester.insert(alice, 1, th.DUMMY_BYTES32, th.DUMMY_BYTES32)
        let _aliceCdps = await sortedCdps.cdpCountOf(alice);
        assert.equal(_aliceCdps, 1);
		
        await sortedCdpsTester.insert(alice, 1, alice, alice)
        _aliceCdps = await sortedCdps.cdpCountOf(alice);
        assert.equal(_aliceCdps, 2);
      })

      it('insert(): fails if NICR is zero', async () => {
        await th.assertRevert(sortedCdpsTester.insert(alice, 0, th.DUMMY_BYTES32, th.DUMMY_BYTES32), 'SortedCdps: NICR must be positive')
      })

      it('remove(): fails if id is not in the list', async () => {
        await th.assertRevert(sortedCdpsTester.remove(alice), 'SortedCdps: List does not contain the id')
      })

      it('reInsert(): fails if list doesn’t contain the node', async () => {
        await th.assertRevert(sortedCdpsTester.reInsert(alice, 1, th.DUMMY_BYTES32, th.DUMMY_BYTES32), 'SortedCdps: List does not contain the id')
      })

      it('reInsert(): fails if new NICR is zero', async () => {
        await sortedCdpsTester.insert(alice, 1, th.DUMMY_BYTES32, th.DUMMY_BYTES32)
        let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
        assert.isTrue(await sortedCdps.contains(_aliceCdpId), 'list should contain element')
        await th.assertRevert(sortedCdpsTester.reInsert(_aliceCdpId, 0, _aliceCdpId, _aliceCdpId), 'SortedCdps: NICR must be positive')
        assert.isTrue(await sortedCdps.contains(_aliceCdpId), 'list should contain element')
      })

      it('findInsertPosition(): No prevId for hint - ascend list starting from nextId, result is after the tail', async () => {
        await sortedCdpsTester.insert(alice, 1, th.DUMMY_BYTES32, th.DUMMY_BYTES32)
        let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
        const pos = await sortedCdps.findInsertPosition(1, th.DUMMY_BYTES32, _aliceCdpId)
        assert.equal(pos[0], _aliceCdpId, 'prevId result should be nextId param')
        assert.equal(pos[1], th.DUMMY_BYTES32, 'nextId result should be zero')
      })
    })
  })
})
