const deploymentHelper = require("../utils/deploymentHelpers.js")
const testHelpers = require("../utils/testHelpers.js")

const BorrowerOperationsTester = artifacts.require("./BorrowerOperationsTester.sol")
const NonPayable = artifacts.require('NonPayable.sol')
const CdpManagerTester = artifacts.require("CdpManagerTester")
const EBTCTokenTester = artifacts.require("./EBTCTokenTester")
const MultipleCdpsTester = artifacts.require("./MultipleCdpsTester.sol")

const th = testHelpers.TestHelper

const dec = th.dec
const toBN = th.toBN
const mv = testHelpers.MoneyValues
const timeValues = testHelpers.TimeValues

const ZERO_ADDRESS = th.ZERO_ADDRESS
const assertRevert = th.assertRevert

/* NOTE: Some of the borrowing tests do not test for specific EBTC fee values. They only test that the
 * fees are non-zero when they should occur, and that they decay over time.
 *
 * Specific EBTC fee values will depend on the final fee schedule used, and the final choice for
 *  the parameter MINUTE_DECAY_FACTOR in the CdpManager, which is still TBD based on economic
 * modelling.
 * 
 */
 
const hre = require("hardhat");

contract('BorrowerOperations', async accounts => {

  const [
    owner, alice, bob, carol, dennis, whale,
    A, B, C, D, E, F, G, H,
    // defaulter_1, defaulter_2,
    frontEnd_1, frontEnd_2, frontEnd_3] = accounts;

    const bn8 = "0x00000000219ab540356cBB839Cbe05303d7705Fa";
    let [bountyAddress, lpRewardsAddress, multisig] = accounts.slice(997, 1000)
    let bn8Signer;

  // const frontEnds = [frontEnd_1, frontEnd_2, frontEnd_3]

  let priceFeed
  let ebtcToken
  let sortedCdps
  let cdpManager
  let activePool
  let defaultPool
  let borrowerOperations
  let feeRecipient

  let contracts
  let _signer 
  let authority;

  const getOpenCdpEBTCAmount = async (totalDebt) => th.getOpenCdpEBTCAmount(contracts, totalDebt)
  const getNetBorrowingAmount = async (debtWithFee) => th.getNetBorrowingAmount(contracts, debtWithFee)
  const getActualDebtFromComposite = async (compositeDebt) => th.getActualDebtFromComposite(compositeDebt, contracts)
  const openCdp = async (params) => th.openCdp(contracts, params)
  const getCdpEntireColl = async (cdp) => th.getCdpEntireColl(contracts, cdp)
  const getCdpEntireDebt = async (cdp) => th.getCdpEntireDebt(contracts, cdp)
  const getCdpStake = async (cdp) => th.getCdpStake(contracts, cdp)

  let EBTC_GAS_COMPENSATION
  let MIN_NET_DEBT
  let BORROWING_FEE_FLOOR

  before(async () => {
      // let _forkBlock = hre.network.config['forking']['blockNumber'];
      // let _forkUrl = hre.network.config['forking']['url'];
      // console.log("resetting to mainnet fork: block=" + _forkBlock + ',url=' + _forkUrl);
      // await hre.network.provider.request({ method: "hardhat_reset", params: [ { forking: { jsonRpcUrl: _forkUrl, blockNumber: _forkBlock }} ] });
	  
      await hre.network.provider.request({method: "hardhat_impersonateAccount", params: [bn8]}); 
      bn8Signer = await ethers.provider.getSigner(bn8);
      [bountyAddress, lpRewardsAddress, multisig] = [bn8Signer._address, bn8Signer._address, bn8Signer._address];
  })

  const testCorpus = ({ withProxy = false }) => {
    beforeEach(async () => {
      await deploymentHelper.setDeployGasPrice(1000000000)
      contracts = await deploymentHelper.deployTesterContractsHardhat()
      let LQTYContracts = {}
      LQTYContracts.feeRecipient = contracts.feeRecipient;

      await deploymentHelper.connectCoreContracts(contracts, LQTYContracts)

      if (withProxy) {
        const users = [alice, bob, carol, dennis, whale, A, B, C, D, E]
        await deploymentHelper.deployProxyScripts(contracts, owner, users)
      }

      priceFeed = contracts.priceFeedTestnet
      ebtcToken = contracts.ebtcToken
      sortedCdps = contracts.sortedCdps
      cdpManager = contracts.cdpManager
      activePool = contracts.activePool
      defaultPool = contracts.defaultPool
      borrowerOperations = contracts.borrowerOperations
      hintHelpers = contracts.hintHelpers
      debtToken = ebtcToken;
      LICR = await cdpManager.LICR()
      authority = contracts.authority;

      feeRecipient = contracts.feeRecipient

      MIN_NET_DEBT = await borrowerOperations.MIN_NET_STETH_BALANCE()
      BORROWING_FEE_FLOOR = await borrowerOperations.BORROWING_FEE_FLOOR()

      ownerSigner = await ethers.provider.getSigner(owner);
      let _ownerBal = await web3.eth.getBalance(owner);
      let _bn8Bal = await web3.eth.getBalance(bn8);
      let _ownerRicher = toBN(_ownerBal.toString()).gt(toBN(_bn8Bal.toString()));
      _signer = _ownerRicher? ownerSigner : bn8Signer;
	  
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("11000")});
      await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("1100")});
      await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("1100")});
      if (_signer._address != multisig){
          await _signer.sendTransaction({ to: multisig, value: ethers.utils.parseEther("1100")});		  
      }
      
    })	  
	  
    it("BorrowerOperations flashloan checks", async() => {
      let _maxFlashLoanAlloweed = await borrowerOperations.maxFlashLoan(ebtcToken.address);	
      await assertRevert(borrowerOperations.flashLoan(borrowerOperations.address, ebtcToken.address, 0, th.DUMMY_BYTES32, {from: alice}), "BorrowerOperations: Flashloan amount must be above 0");
      await assertRevert(borrowerOperations.flashLoan(borrowerOperations.address, borrowerOperations.address, _maxFlashLoanAlloweed, th.DUMMY_BYTES32, {from: alice}), "BorrowerOperations: Only eBTC token can be flashloaned");
      await assertRevert(borrowerOperations.flashLoan(borrowerOperations.address, ebtcToken.address, _maxFlashLoanAlloweed.add(toBN(1)), th.DUMMY_BYTES32, {from: alice}), "BorrowerOperations: Flashloan amount exceeds maximum for specified token flashLoan amount");
    })  
	  
    it("BorrowerOperations governance permissioned: setFeeBps() should only allow authorized caller", async() => {	  
	  await assertRevert(borrowerOperations.setFeeBps(1, {from: alice}), "Auth: UNAUTHORIZED");   

	  assert.isTrue(authority.address == (await borrowerOperations.authority()));
	  let _role123 = 123;
	  let _funcSig = await borrowerOperations.FUNC_SIG_FL_FEE();
	  await authority.setRoleCapability(_role123, borrowerOperations.address, _funcSig, true, {from: accounts[0]});	  
	  await authority.setUserRole(alice, _role123, true, {from: accounts[0]});
	  assert.isTrue((await authority.canCall(alice, borrowerOperations.address, _funcSig)));
	  await assertRevert(borrowerOperations.setFeeBps(10001, {from: alice}), "ERC3156FlashLender: _newFee should <= MAX_FEE_BPS");
	  let _newFee = await borrowerOperations.MAX_FEE_BPS()
	  assert.isTrue(_newFee.gt(await borrowerOperations.feeBps()));
	  await borrowerOperations.setFeeBps(_newFee, {from: alice})
	  assert.isTrue(_newFee.eq(await borrowerOperations.feeBps()));

    })

    it("BorrowerOperations governance permissioned: setFeeBps() should only allow authorized caller", async() => {	  
      await assertRevert(borrowerOperations.setFeeBps(1, {from: alice}), "Auth: UNAUTHORIZED");   
  
      assert.isTrue(authority.address == (await borrowerOperations.authority()));
      let _role123 = 123;
      let _funcSig = await borrowerOperations.FUNC_SIG_FL_FEE();
      await authority.setRoleCapability(_role123, borrowerOperations.address, _funcSig, true, {from: accounts[0]});	  
      await authority.setUserRole(alice, _role123, true, {from: accounts[0]});
      assert.isTrue((await authority.canCall(alice, borrowerOperations.address, _funcSig)));

      await assertRevert(borrowerOperations.setFeeBps(10001, {from: alice}), "ERC3156FlashLender: _newMaxFlashFee should <= 10000");
      let _newFee = await borrowerOperations.MAX_FEE_BPS();
      
      assert.isTrue(_newFee.lte(await borrowerOperations.MAX_FEE_BPS()));
      await borrowerOperations.setFeeBps(_newFee, {from: alice})
      assert.isTrue(_newFee.eq(await borrowerOperations.MAX_FEE_BPS()));
  
    })

    xit("openCdp(): mutiple Cdp via non-EOA smart contract", async () => {
	  mtsTester = await MultipleCdpsTester.new();
	  mtsTester.initiate(borrowerOperations.address, sortedCdps.address);	  
	  ownerSigner.sendTransaction({ to: mtsTester.address, value: ethers.utils.parseEther("1000")});
      		
	  // open multiple Cdps
	  let _count = 10;
	  const _singleCdpDebt = (await contracts.borrowerOperations.MIN_NET_DEBT()).add(toBN(dec(2, 18)));
	  let _icr = toBN(dec(25, 17));//250%
	  const _price = await priceFeed.getPrice();
	  let _singleCdpCol = _icr.mul(_singleCdpDebt).div(_price);
	  tx = await mtsTester.openCdps(_count, th._100pct, _singleCdpDebt, th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: owner, value: _singleCdpCol.mul(toBN(_count)) } );
	  let _openedCdpEvts = th.getAllEventsByName(tx, 'CdpOpened');
	  let _ei = 0;
	  for(;_ei < _openedCdpEvts.length - 1;_ei++){
	      let _cdpId = _openedCdpEvts[_ei].args[0];
	      //console.log(_cdpId);
	      let _cdpStatus = await cdpManager.getCdpStatus(_cdpId);
	      assert.equal(_cdpStatus, 1);			
	      let _cdpOwner = await sortedCdps.getOwnerAddress(_cdpId);
	      assert.equal(_cdpOwner, mtsTester.address);	  
	      let _ii = _ei + 1;
	      for(;_ii < _openedCdpEvts.length;_ii++){
	          let _iCdpId = _openedCdpEvts[_ii].args[0];
	          assert.notEqual(_iCdpId, _cdpId);
	          let _iCdpStatus = await cdpManager.getCdpStatus(_iCdpId);
	          assert.equal(_iCdpStatus, 1);  		
	          let _iCdpOwner = await sortedCdps.getOwnerAddress(_iCdpId);
	          assert.equal(_iCdpOwner, mtsTester.address);
	      }
	  }
	  //console.log(_openedCdpEvts[_openedCdpEvts.length - 1].args[0]);
    })
	
    it("openCdp(): should NOT allow open with zero collateral", async () => {	
	  await assertRevert(borrowerOperations.openCdp(123, th.DUMMY_BYTES32, th.DUMMY_BYTES32, 0, { from: bob }), "BorrowerOperations: collateral for CDP is zero");	  
    })

    it("openCdp(): mutiple Cdp per user", async () => {		  
	  // first Cdp
	  await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } });
	  let cdpSize = await sortedCdps.getSize();
	  let cdpIds = await cdpManager.getActiveCdpsCount();
	  assert.isTrue(cdpSize == 1);
	  assert.isTrue((cdpSize - cdpIds) == 0);
	  let lastCdpId = await sortedCdps.getLast();
	  let lastCdpOwner = await sortedCdps.getOwnerAddress(lastCdpId);
	  assert.isTrue(lastCdpOwner == alice);
	  let _aliceOwnedCdps = await sortedCdps.cdpCountOf(alice);
	  assert.isTrue(_aliceOwnedCdps == 1);	  
	  let _aliceOwnedCdp = await sortedCdps.cdpOfOwnerByIndex(alice, _aliceOwnedCdps - 1);
	  assert.isTrue(_aliceOwnedCdp == lastCdpId);
	  
	  // Second Cdp
	  await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } });
	  cdpSize = await sortedCdps.getSize();
	  cdpIds = await cdpManager.getActiveCdpsCount();
	  assert.isTrue(cdpSize == 2);
	  assert.isTrue((cdpIds - cdpSize) == 0);
	  lastCdpId = await sortedCdps.getLast();
	  lastCdpOwner = await sortedCdps.getOwnerAddress(lastCdpId);
	  let firstCdpId = await sortedCdps.getFirst();
	  let firstCdpOwner = await sortedCdps.getOwnerAddress(firstCdpId);
	  assert.isTrue(lastCdpOwner == alice);
	  assert.isTrue(firstCdpOwner == alice);
	  assert.isTrue(firstCdpId != lastCdpId);
	  _aliceOwnedCdps = await sortedCdps.cdpCountOf(alice);
	  assert.isTrue(_aliceOwnedCdps == 2);	  
	  let _aliceOwnedFirstCdp = await sortedCdps.cdpOfOwnerByIndex(alice, _aliceOwnedCdps - 2);
	  let _aliceOwnedSecondCdp = await sortedCdps.cdpOfOwnerByIndex(alice, _aliceOwnedCdps - 1);
	  assert.isTrue(_aliceOwnedFirstCdp == lastCdpId);
	  assert.isTrue(_aliceOwnedSecondCdp == firstCdpId);
	  
	  // Close Second Cdp	  	
	  await assertRevert(borrowerOperations.closeCdp(lastCdpId, { from: bob }), "!cdpOwner");	
	  const txClose = await borrowerOperations.closeCdp(lastCdpId, { from: alice });
	  assert.isTrue(txClose.receipt.status);
	  cdpSize = await sortedCdps.getSize();
	  cdpIds = await cdpManager.getActiveCdpsCount();
	  assert.isTrue(cdpSize == 1);
	  assert.isTrue((cdpIds - cdpSize) == 0);
	  lastCdpId = await sortedCdps.getLast();
	  lastCdpOwner = await sortedCdps.getOwnerAddress(lastCdpId);
	  assert.isTrue(firstCdpId == lastCdpId);	
	  assert.isTrue(firstCdpOwner == lastCdpOwner); 
	  _aliceOwnedCdps = await sortedCdps.cdpCountOf(alice);
	  assert.isTrue(_aliceOwnedCdps == 1);	
	  let _aliceOwnedLeftCdp = await sortedCdps.cdpOfOwnerByIndex(alice, _aliceOwnedCdps - 1);
	  assert.isTrue(_aliceOwnedLeftCdp == firstCdpId);   
    })

    it("addColl(): reverts when top-up would leave cdp with ICR < MCR", async () => {
      // alice creates a Cdp and adds first collateral
      await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openCdp({ ICR: toBN(dec(10, 18)), extraParams: { from: bob } })

      // Price drops
      await priceFeed.setPrice(dec(3000, 13))
      const price = await priceFeed.getPrice()

      assert.isFalse(await cdpManager.checkRecoveryMode(price))
      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)
      assert.isTrue((await cdpManager.getCachedICR(aliceIndex, price)).lt(toBN(dec(110, 16))))

      const collTopUp = 1  // 1 wei top up

      await assertRevert(borrowerOperations.addColl(aliceIndex, th.DUMMY_BYTES32, th.DUMMY_BYTES32, collTopUp, { from: alice }),
        "BorrowerOperations: An operation that would result in ICR < MCR is not permitted")
      })

    it("addColl(): Increases the activePool ETH and raw ether balance by correct amount", async () => {
      const { collateral: aliceColl } = await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      
      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)

      const activePool_ETH_Before = await activePool.getSystemCollShares()

      assert.isTrue(activePool_ETH_Before.eq(aliceColl))
      await borrowerOperations.addColl(aliceIndex, th.DUMMY_BYTES32, th.DUMMY_BYTES32, dec(1, 'ether'), { from: alice })

      const activePool_ETH_After = await activePool.getSystemCollShares()
      assert.isTrue(activePool_ETH_After.eq(aliceColl.add(toBN(dec(1, 'ether')))))
    })

    it("addColl(), active Cdp: adds the correct collateral amount to the Cdp", async () => {
      // alice creates a Cdp and adds first collateral
      await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)
      const alice_Cdp_Before = await cdpManager.Cdps(aliceIndex)
      const coll_before = alice_Cdp_Before[1]
      const status_Before = alice_Cdp_Before[4]

      // check status before
      assert.equal(status_Before, 1)

      // Alice adds second collateral
      await borrowerOperations.addColl(aliceIndex, th.DUMMY_BYTES32, th.DUMMY_BYTES32, dec(1, 'ether'), { from: alice })

      const alice_Cdp_After = await cdpManager.Cdps(aliceIndex)
      const coll_After = alice_Cdp_After[1]
      const status_After = alice_Cdp_After[4]

      // check coll increases by correct amount,and status remains active
      assert.isTrue(coll_After.eq(coll_before.add(toBN(dec(1, 'ether')))))
      assert.equal(status_After, 1)
    })

    it("addColl(), active Cdp: Cdp is in sortedList before and after", async () => {
      // alice creates a Cdp and adds first collateral
      await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)

      // check Alice is in list before
      const aliceCdpInList_Before = await sortedCdps.contains(aliceIndex)
      const listIsEmpty_Before = await sortedCdps.isEmpty()
      assert.equal(aliceCdpInList_Before, true)
      assert.equal(listIsEmpty_Before, false)

      await borrowerOperations.addColl(aliceIndex, th.DUMMY_BYTES32, th.DUMMY_BYTES32, dec(1, 'ether'), { from: alice })

      // check Alice is still in list after
      const aliceCdpInList_After = await sortedCdps.contains(aliceIndex)
      const listIsEmpty_After = await sortedCdps.isEmpty()
      assert.equal(aliceCdpInList_After, true)
      assert.equal(listIsEmpty_After, false)
    })

    it("addColl(), active Cdp: updates the stake and updates the total stakes", async () => {
      //  Alice creates initial Cdp with 1 ether
      await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)

      const alice_Cdp_Before = await cdpManager.Cdps(aliceIndex)
      const alice_Stake_Before = alice_Cdp_Before[2]
      const totalStakes_Before = (await cdpManager.totalStakes())

      assert.isTrue(totalStakes_Before.eq(alice_Stake_Before))

      // Alice tops up Cdp collateral with 2 ether
      await borrowerOperations.addColl(aliceIndex, th.DUMMY_BYTES32, th.DUMMY_BYTES32, dec(2, 'ether'), { from: alice })

      // Check stake and total stakes get updated
      const alice_Cdp_After = await cdpManager.Cdps(aliceIndex)
      const alice_Stake_After = alice_Cdp_After[2]
      const totalStakes_After = (await cdpManager.totalStakes())

      assert.isTrue(alice_Stake_After.eq(alice_Stake_Before.add(toBN(dec(2, 'ether')))))
      assert.isTrue(totalStakes_After.eq(totalStakes_Before.add(toBN(dec(2, 'ether')))))
    })

    it("addColl(), active Cdp: applies pending rewards and updates user's systemDebtRedistributionIndex snapshots", async () => {
      // --- SETUP ---

      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("50000")});
      await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("50000")});
      await _signer.sendTransaction({ to: carol, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: owner, value: ethers.utils.parseEther("20000")});
      const { collateral: aliceCollBefore, totalDebt: aliceDebtBefore } = await openCdp({ extraEBTCAmount: toBN(dec(150, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)
      
      const { collateral: bobCollBefore, totalDebt: bobDebtBefore } = await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: bob } })
      const bobIndex = await sortedCdps.cdpOfOwnerByIndex(bob,0)

      await openCdp({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: carol } })
      const carolIndex = await sortedCdps.cdpOfOwnerByIndex(carol,0)
      await openCdp({ extraEBTCAmount: toBN(dec(60, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: owner } })

      // --- TEST ---

      // price drops to 1ETH:100EBTC, reducing Carol's ICR below MCR
      await priceFeed.setPrice(dec(3000, 13))

      // Liquidate Carol's Cdp,
      const tx = await cdpManager.liquidate(carolIndex, { from: owner });

      assert.isFalse(await sortedCdps.contains(carolIndex))

      const systemDebtRedistributionIndex = await cdpManager.systemDebtRedistributionIndex()

      // check Alice and Bob's reward snapshots are zero before they alter their Cdps
      const alice_EBTCDebtRewardSnapshot_Before = await cdpManager.cdpDebtRedistributionIndex(aliceIndex)

      const bob_EBTCDebtRewardSnapshot_Before = await cdpManager.cdpDebtRedistributionIndex(bobIndex)

      assert.equal(alice_EBTCDebtRewardSnapshot_Before, 0)
      assert.equal(bob_EBTCDebtRewardSnapshot_Before, 0)

      const alicePendingRedistributedDebt = (await cdpManager.getPendingRedistributedDebt(aliceIndex))
      const bobPendingRedistributedDebt = (await cdpManager.getPendingRedistributedDebt(bobIndex))
      for (reward of [alicePendingRedistributedDebt, bobPendingRedistributedDebt]) {
        assert.isTrue(reward.gt(toBN('0')))
      }

      // Alice and Bob top up their Cdps
      const aliceTopUp = toBN(dec(5, 'ether'))
      const bobTopUp = toBN(dec(1, 'ether'))

      await borrowerOperations.addColl(aliceIndex, th.DUMMY_BYTES32, th.DUMMY_BYTES32, aliceTopUp, { from: alice })
      await borrowerOperations.addColl(bobIndex, th.DUMMY_BYTES32, th.DUMMY_BYTES32, bobTopUp, { from: bob })

      // Check that both alice and Bob have had pending rewards applied in addition to their top-ups. 
      const aliceNewColl = await getCdpEntireColl(aliceIndex)
      const aliceNewDebt = await getCdpEntireDebt(aliceIndex)
      const bobNewColl = await getCdpEntireColl(bobIndex)
      const bobNewDebt = await getCdpEntireDebt(bobIndex)

      assert.isTrue(aliceNewColl.eq(aliceCollBefore.add(aliceTopUp)))
      assert.isTrue(aliceNewDebt.eq(aliceDebtBefore.add(alicePendingRedistributedDebt)))
      assert.isTrue(bobNewColl.eq(bobCollBefore.add(bobTopUp)))
      assert.isTrue(bobNewDebt.eq(bobDebtBefore.add(bobPendingRedistributedDebt)))

      /* Check that both Alice and Bob's snapshots of the rewards-per-unit-staked metrics should be updated
       to the latest values of L_STETHColl and systemDebtRedistributionIndex */
      const alice_EBTCDebtRewardSnapshot_After = await cdpManager.cdpDebtRedistributionIndex(aliceIndex)

      const bob_EBTCDebtRewardSnapshot_After = await cdpManager.cdpDebtRedistributionIndex(bobIndex)

      assert.isAtMost(th.getDifference(alice_EBTCDebtRewardSnapshot_After, systemDebtRedistributionIndex), 100)
      assert.isAtMost(th.getDifference(bob_EBTCDebtRewardSnapshot_After, systemDebtRedistributionIndex), 100)
    })

    // xit("addColl(), active Cdp: adds the right corrected stake after liquidations have occured", async () => {
    //  // TODO - check stake updates for addColl/withdrawColl/adustCdp ---

    //   // --- SETUP ---
    //   // A,B,C add 15/5/5 ETH, withdraw 100/100/900 EBTC
    //   await borrowerOperations.openCdp(dec(100, 18), alice, alice, { from: alice, value: dec(15, 'ether') })
    //   await borrowerOperations.openCdp(dec(100, 18), bob, bob, { from: bob, value: dec(4, 'ether') })
    //   await borrowerOperations.openCdp(dec(900, 18), carol, carol, { from: carol, value: dec(5, 'ether') })

    //   await borrowerOperations.openCdp(0, dennis, dennis, { from: dennis, value: dec(1, 'ether') })
    //   // --- TEST ---

    //   // price drops to 1ETH:100EBTC, reducing Carol's ICR below MCR
    //   await priceFeed.setPrice('100000000000000000000');

    //   // close Carol's Cdp, liquidating her 5 ether and 900EBTC.
    //   await cdpManager.liquidate(carol, { from: owner });

    //   // dennis tops up his cdp by 1 ETH
    //   await borrowerOperations.addColl(dennis, dennis, { from: dennis, value: dec(1, 'ether') })

    //   /* Check that Dennis's recorded stake is the right corrected stake, less than his collateral. A corrected 
    //   stake is given by the formula: 

    //   s = totalStakesSnapshot / totalCollateralSnapshot 

    //   where snapshots are the values immediately after the last liquidation.  After Carol's liquidation, 
    //   the ETH from her Cdp has now become the totalPendingETHReward. So:

    //   totalStakes = (alice_Stake + bob_Stake + dennis_orig_stake ) = (15 + 4 + 1) =  20 ETH.
    //   totalCollateral = (alice_Collateral + bob_Collateral + dennis_orig_coll + totalPendingETHReward) = (15 + 4 + 1 + 5)  = 25 ETH.

    //   Therefore, as Dennis adds 1 ether collateral, his corrected stake should be:  s = 2 * (20 / 25 ) = 1.6 ETH */
    //   const dennis_Cdp = await cdpManager.Cdps(dennis)

    //   const dennis_Stake = dennis_Cdp[2]
    //   console.log(dennis_Stake.toString())

    //   assert.isAtMost(th.getDifference(dennis_Stake), 100)
    // })

    it("addColl(), reverts if cdp is not owned by caller (does not consider approved positionManagers)", async () => {
      // A, B open cdps
      await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: bob } })

      const bobIndex = await sortedCdps.cdpOfOwnerByIndex(bob,0)
      // Carol attempts to add collateral to her non-existent cdp
      try {
        const txCarol = await borrowerOperations.addColl(bobIndex, th.DUMMY_BYTES32, th.DUMMY_BYTES32, dec(1, 'ether'), { from: alice })
        assert.isFalse(txCarol.receipt.status)
      } catch (error) {
        assert.include(error.message, "BorrowerOperations: Only borrower account or approved position manager can OpenCdp on borrower's behalf")
      }
    })

    it("addColl(), reverts if cdp is non-existent or closed", async () => {
      // A, B open cdps
      await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: bob } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)
      const bobIndex = await sortedCdps.cdpOfOwnerByIndex(bob,0)
      await _signer.sendTransaction({ to: owner, value: ethers.utils.parseEther("200000")});
      await openCdp({ extraEBTCAmount: toBN(dec(600, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: owner } });

      // Price drops
      await priceFeed.setPrice(dec(3000, 13))

      // Bob gets liquidated
      await cdpManager.liquidate(bobIndex)

      assert.isFalse(await sortedCdps.contains(bobIndex))

      // Bob attempts to add collateral to his closed cdp
      try {
        const txBob = await borrowerOperations.addColl(bobIndex, th.DUMMY_BYTES32, th.DUMMY_BYTES32, dec(1, 'ether'), { from: bob })
        assert.isFalse(txBob.receipt.status)
      } catch (error) {
        assert.include(error.message, "revert")
        assert.include(error.message, "BorrowerOperations: Cdp does not exist or is closed")
      }
    })

    it("addColl(): can add collateral in Recovery Mode", async () => {
      await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)

      const aliceCollBefore = await getCdpEntireColl(aliceIndex)
      assert.isFalse(await th.checkRecoveryMode(contracts))

      await priceFeed.setPrice(dec(3000, 13))

      assert.isTrue(await th.checkRecoveryMode(contracts))

      const collTopUp = toBN(dec(1, 'ether'))
      await borrowerOperations.addColl(aliceIndex, th.DUMMY_BYTES32, th.DUMMY_BYTES32, collTopUp, { from: alice })

      // Check Alice's collateral
      const aliceCollAfter = (await cdpManager.Cdps(aliceIndex))[1]
      assert.isTrue(aliceCollAfter.eq(aliceCollBefore.add(collTopUp)))
    })

    // --- withdrawColl() ---

    it("withdrawColl(): reverts when withdrawal would leave cdp with ICR < MCR", async () => {
      // alice creates a Cdp and adds first collateral
      await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openCdp({ ICR: toBN(dec(10, 18)), extraParams: { from: bob } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)
      const bobIndex = await sortedCdps.cdpOfOwnerByIndex(bob,0)

      // Price drops
      await priceFeed.setPrice(dec(3000, 13))
      const price = await priceFeed.getPrice()

      assert.isFalse(await cdpManager.checkRecoveryMode(price))
      assert.isTrue((await cdpManager.getCachedICR(aliceIndex, price)).lt(toBN(dec(110, 16))))

      const collWithdrawal = 1  // 1 wei withdrawal

     await assertRevert(borrowerOperations.withdrawColl(aliceIndex, 1, th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: alice }),
      "BorrowerOperations: An operation that would result in ICR < MCR is not permitted")
    })

    // reverts when calling address does not have active cdp  
    it("withdrawColl(): reverts when calling address does not have active cdp", async () => {
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("20000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: bob } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)
      const bobIndex = await sortedCdps.cdpOfOwnerByIndex(bob,0)
      const carolIndex = th.RANDOM_INDEX;

      // Bob successfully withdraws some coll
      const txBob = await borrowerOperations.withdrawColl(bobIndex, dec(100, 'finney'), bobIndex, bobIndex, { from: bob })
      assert.isTrue(txBob.receipt.status)

      // Carol with no active cdp attempts to withdraw
      try {
        const txCarol = await borrowerOperations.withdrawColl(carolIndex, dec(1, 'ether'), th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: carol })
        assert.isFalse(txCarol.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    it("withdrawColl(): reverts when system is in Recovery Mode", async () => {
      await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: bob } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)
      const bobIndex = await sortedCdps.cdpOfOwnerByIndex(bob,0)

      assert.isFalse(await th.checkRecoveryMode(contracts))

      // Withdrawal possible when recoveryMode == false
      const txAlice = await borrowerOperations.withdrawColl(aliceIndex, 1000, aliceIndex, aliceIndex, { from: alice })
      assert.isTrue(txAlice.receipt.status)

      await priceFeed.setPrice(dec(3000, 13))

      assert.isTrue(await th.checkRecoveryMode(contracts))

      //Check withdrawal impossible when recoveryMode == true
      try {
        const txBob = await borrowerOperations.withdrawColl(bobIndex, 1000, bobIndex, bobIndex, { from: bob })
        assert.isFalse(txBob.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    it("withdrawColl(): reverts when requested ETH withdrawal is > the cdp's collateral", async () => {
      await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: bob } })
      await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: carol } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)
      const bobIndex = await sortedCdps.cdpOfOwnerByIndex(bob,0)
      const carolIndex = await sortedCdps.cdpOfOwnerByIndex(carol,0)

      const carolColl = await getCdpEntireColl(carolIndex)
      const bobColl = await getCdpEntireColl(bobIndex)
      // Carol withdraws exactly all her collateral
      await assertRevert(
        borrowerOperations.withdrawColl(carolIndex, carolColl, carolIndex, carolIndex, { from: carol }),
        'BorrowerOperations: An operation that would result in ICR < MCR is not permitted'
      )

      // Bob attempts to withdraw 1 wei more than his collateral
      try {
        const txBob = await borrowerOperations.withdrawColl(bobIndex, bobColl.add(toBN(1)), bobIndex, bobIndex, { from: bob })
        assert.isFalse(txBob.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    it("withdrawColl(): reverts when withdrawal would bring the user's ICR < MCR", async () => {
      await openCdp({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openCdp({ ICR: toBN(dec(111, 16)), extraParams: { from: bob } }) // 111% ICR

      const bobIndex = await sortedCdps.cdpOfOwnerByIndex(bob,0)

      // Try to withdraw .5 ETH and expect revert
      try {
        const txBob = await borrowerOperations.withdrawColl(bobIndex, toBN(500000000000000000), bobIndex, bobIndex, { from: bob })
        assert.isFalse(txBob.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    it("withdrawColl(): reverts if system is in Recovery Mode", async () => {
      // --- SETUP ---

      // A and B open cdps at 150% ICR
      await openCdp({ ICR: toBN(dec(151, 16)), extraParams: { from: bob } })
      await openCdp({ ICR: toBN(dec(151, 16)), extraParams: { from: alice } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)

      const TCR = (await th.getCachedTCR(contracts)).toString()
      assert.equal(TCR, '1509999999999999999')

      // --- TEST ---

      // price drops, reducing TCR below 150%
      await priceFeed.setPrice('742800000000000');

      //Alice tries to withdraw collateral during Recovery Mode
      try {
        const txData = await borrowerOperations.withdrawColl(aliceIndex, '1', aliceIndex, aliceIndex, { from: alice })
        assert.isFalse(txData.receipt.status)
      } catch (err) {
        assert.include(err.message, 'revert')
      }
    })

    it("withdrawColl(): doesn’t allow a user to completely withdraw all collateral from their Cdp (due to gas compensation)", async () => {
      await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: bob } })
      await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)
      const bobIndex = await sortedCdps.cdpOfOwnerByIndex(bob,0)

      const aliceColl = (await cdpManager.getSyncedDebtAndCollShares(aliceIndex))[1]

      // Check Cdp is active
      const alice_Cdp_Before = await cdpManager.Cdps(aliceIndex)
      const status_Before = alice_Cdp_Before[4]
      assert.equal(status_Before, 1)
      assert.isTrue(await sortedCdps.contains(aliceIndex))

      // Alice attempts to withdraw all collateral
      await assertRevert(
        borrowerOperations.withdrawColl(aliceIndex, aliceColl, aliceIndex, aliceIndex, { from: alice }),
        'BorrowerOperations: An operation that would result in ICR < MCR is not permitted'
      )
    })

    it("withdrawColl(): leaves the Cdp active when the user withdraws less than all the collateral", async () => {
      // Open Cdp 
      await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      
      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)

      // Check Cdp is active
      const alice_Cdp_Before = await cdpManager.Cdps(aliceIndex)
      const status_Before = alice_Cdp_Before[4]
      assert.equal(status_Before, 1)
      assert.isTrue(await sortedCdps.contains(aliceIndex))

      // Withdraw some collateral
      await borrowerOperations.withdrawColl(aliceIndex, dec(100, 'finney'), aliceIndex, aliceIndex, { from: alice })

      // Check Cdp is still active
      const alice_Cdp_After = await cdpManager.Cdps(aliceIndex)
      const status_After = alice_Cdp_After[4]
      assert.equal(status_After, 1)
      assert.isTrue(await sortedCdps.contains(aliceIndex))
    })

    it("withdrawColl(): reduces the Cdp's collateral by the correct amount", async () => {
      await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)
      const aliceCollBefore = await getCdpEntireColl(aliceIndex)

      // Alice withdraws 0.1 ether
      await borrowerOperations.withdrawColl(aliceIndex, dec(1, 17), aliceIndex, aliceIndex, { from: alice })

      // Check 1 ether remaining
      const aliceCollAfter = await getCdpEntireColl(aliceIndex)

      assert.isTrue(aliceCollAfter.eq(aliceCollBefore.sub(toBN(dec(1, 17)))))
    })

    it("withdrawColl(): reduces ActivePool ETH and raw ether by correct amount", async () => {
      await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)

      // check before
      const activePool_ETH_before = await activePool.getSystemCollShares()
      // Withdraw 0.1 ether
      await borrowerOperations.withdrawColl(aliceIndex, dec(1, 17), aliceIndex, aliceIndex, { from: alice })

      // check after
      const activePool_ETH_After = await activePool.getSystemCollShares()
      const activePool_RawEther_After = toBN(await web3.eth.getBalance(activePool.address))
      assert.isTrue(activePool_ETH_After.eq(activePool_ETH_before.sub(toBN(dec(1, 17)))))
    })

    it("withdrawColl(): updates the stake and updates the total stakes", async () => {
      //  Alice creates initial Cdp with 2 ether
      await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: alice, value: toBN(dec(5, 'ether')) } })
      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)
      const aliceColl = await getCdpEntireColl(aliceIndex)
      assert.isTrue(aliceColl.gt(toBN('0')))

      const alice_Cdp_Before = await cdpManager.Cdps(aliceIndex)
      const alice_Stake_Before = alice_Cdp_Before[2]
      const totalStakes_Before = (await cdpManager.totalStakes())

      assert.isTrue(alice_Stake_Before.eq(aliceColl))
      assert.isTrue(totalStakes_Before.eq(aliceColl))

      // Alice withdraws 0.1 ether
      await borrowerOperations.withdrawColl(aliceIndex, dec(1, 17), aliceIndex, aliceIndex, { from: alice })

      // Check stake and total stakes get updated
      const alice_Cdp_After = await cdpManager.Cdps(aliceIndex)
      const alice_Stake_After = alice_Cdp_After[2]
      const totalStakes_After = (await cdpManager.totalStakes())

      assert.isTrue(alice_Stake_After.eq(alice_Stake_Before.sub(toBN(dec(1, 17)))))
      assert.isTrue(totalStakes_After.eq(totalStakes_Before.sub(toBN(dec(1, 17)))))
    })

    it("withdrawColl(): sends the correct amount of ETH to the user", async () => {
      await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: alice, value: dec(2, 'ether') } })
      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)

      const alice_ETHBalance_Before = toBN(web3.utils.toBN(await contracts.collateral.balanceOf(alice)))
      let _tx = await borrowerOperations.withdrawColl(aliceIndex, dec(1, 17), aliceIndex, aliceIndex, { from: alice, gasPrice: 10000000000 })
      const gasUsedETH = toBN(_tx.receipt.effectiveGasPrice.toString()).mul(toBN(th.gasUsed(_tx).toString()));

      const alice_ETHBalance_After = toBN(web3.utils.toBN(await contracts.collateral.balanceOf(alice)))
      const balanceDiff = alice_ETHBalance_After.sub(alice_ETHBalance_Before);//.add(gasUsedETH)

      assert.equal(balanceDiff.toString(), toBN(dec(1, 17)).toString())
    })

    it("withdrawColl(): applies pending rewards and updates user's sL_EBTCDebt snapshots", async () => {
      // --- SETUP ---
      // Alice adds 15 ether, Bob adds 5 ether, Carol adds 1 ether
      await openCdp({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openCdp({ ICR: toBN(dec(3, 18)), extraParams: { from: alice, value: toBN(dec(100, 'ether')) } })
      await openCdp({ ICR: toBN(dec(3, 18)), extraParams: { from: bob, value: toBN(dec(100, 'ether')) } })
      await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: carol, value: toBN(dec(10, 'ether')) } })

      const whaleIndex = await sortedCdps.cdpOfOwnerByIndex(whale,0)
      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)
      const bobIndex = await sortedCdps.cdpOfOwnerByIndex(bob,0)
      const carolIndex = await sortedCdps.cdpOfOwnerByIndex(carol,0)

      const aliceCollBefore = await getCdpEntireColl(aliceIndex)
      const aliceDebtBefore = await getCdpEntireDebt(aliceIndex)
      const bobCollBefore = await getCdpEntireColl(bobIndex)
      const bobDebtBefore = await getCdpEntireDebt(bobIndex)
      await _signer.sendTransaction({ to: owner, value: ethers.utils.parseEther("200000")});
      await openCdp({ extraEBTCAmount: toBN(dec(600, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: owner } });

      // --- TEST ---

      // price drops to 1ETH:0,004EBTC, reducing Carol's ICR below MCR
      let _p = dec(3800, 13);
      await priceFeed.setPrice(_p)
      assert.isFalse((await cdpManager.checkRecoveryMode(_p)));

      // close Carol's Cdp, liquidating her 1 ether and 180EBTC.
      await cdpManager.liquidate(carolIndex, { from: owner });

      const systemDebtRedistributionIndex = await cdpManager.systemDebtRedistributionIndex()

      // check Alice and Bob's reward snapshots are zero before they alter their Cdps
      const alice_EBTCDebtRewardSnapshot_Before = await cdpManager.cdpDebtRedistributionIndex(aliceIndex)

      const bob_EBTCDebtRewardSnapshot_Before = await cdpManager.cdpDebtRedistributionIndex(bobIndex)

      assert.equal(alice_EBTCDebtRewardSnapshot_Before, 0)
      assert.equal(bob_EBTCDebtRewardSnapshot_Before, 0)

      // Check A and B have pending rewards
      const pendingDebtReward_A = (await cdpManager.getPendingRedistributedDebt(aliceIndex))
      const pendingDebtReward_B = (await cdpManager.getPendingRedistributedDebt(bobIndex))
      for (reward of [pendingDebtReward_A, pendingDebtReward_B]) {
        assert.isTrue(reward.gt(toBN('0')))
      }

      // Alice and Bob withdraw from their Cdps
      const aliceCollWithdrawal = toBN(dec(1, 'ether'))
      const bobCollWithdrawal = toBN(dec(1, 'ether'))

      await borrowerOperations.withdrawColl(aliceIndex, aliceCollWithdrawal, aliceIndex, aliceIndex, { from: alice })
      await borrowerOperations.withdrawColl(bobIndex, bobCollWithdrawal, bobIndex, bobIndex, { from: bob })

      // Check that both alice and Bob have had pending rewards applied in addition to their top-ups. 
      const aliceCollAfter = await getCdpEntireColl(aliceIndex)
      const aliceDebtAfter = await getCdpEntireDebt(aliceIndex)
      const bobCollAfter = await getCdpEntireColl(bobIndex)
      const bobDebtAfter = await getCdpEntireDebt(bobIndex)

      // Check rewards have been applied to cdps
      th.assertIsApproximatelyEqual(aliceCollAfter, aliceCollBefore.sub(aliceCollWithdrawal), 10000)
      th.assertIsApproximatelyEqual(aliceDebtAfter, aliceDebtBefore.add(pendingDebtReward_A), 10000)
      th.assertIsApproximatelyEqual(bobCollAfter, bobCollBefore.sub(bobCollWithdrawal), 10000)
      th.assertIsApproximatelyEqual(bobDebtAfter, bobDebtBefore.add(pendingDebtReward_B), 10000)

      /* After top up, both Alice and Bob's snapshots of the rewards-per-unit-staked metrics should be updated
       to the latest values of L_STETHColl and systemDebtRedistributionIndex */
      const alice_EBTCDebtRewardSnapshot_After = await cdpManager.cdpDebtRedistributionIndex(aliceIndex)

      const bob_EBTCDebtRewardSnapshot_After = await cdpManager.cdpDebtRedistributionIndex(bobIndex)

      assert.isAtMost(th.getDifference(alice_EBTCDebtRewardSnapshot_After, systemDebtRedistributionIndex), 100)
      assert.isAtMost(th.getDifference(bob_EBTCDebtRewardSnapshot_After, systemDebtRedistributionIndex), 100)
    })

    // --- withdrawDebt() ---

    it("withdrawDebt(): reverts when withdrawal would leave cdp with ICR < MCR", async () => {
      // alice creates a Cdp and adds first collateral
      await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openCdp({ ICR: toBN(dec(10, 18)), extraParams: { from: bob } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)
      const bobIndex = await sortedCdps.cdpOfOwnerByIndex(bob,0)

      // Price drops
      await priceFeed.setPrice(dec(3800, 13))
      const price = await priceFeed.getPrice()

      assert.isFalse(await cdpManager.checkRecoveryMode(price))
      assert.isTrue((await cdpManager.getCachedICR(aliceIndex, price)).lt(toBN(dec(110, 16))))

      const EBTCwithdrawal = 1  // withdraw 1 wei EBTC

     await assertRevert(borrowerOperations.withdrawDebt(aliceIndex, EBTCwithdrawal, aliceIndex, aliceIndex, { from: alice }), 
      "BorrowerOperations: An operation that would result in ICR < MCR is not permitted")
    })

    it("withdrawDebt(): does not decay a non-zero base rate", async () => {
      await openCdp({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })

      await openCdp({ extraEBTCAmount: toBN(dec(20, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openCdp({ extraEBTCAmount: toBN(dec(20, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openCdp({ extraEBTCAmount: toBN(dec(20, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })
      await openCdp({ extraEBTCAmount: toBN(dec(20, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: E } })

      const whaleIndex = await sortedCdps.cdpOfOwnerByIndex(whale,0)
      const AIndex = await sortedCdps.cdpOfOwnerByIndex(A,0)
      const BIndex = await sortedCdps.cdpOfOwnerByIndex(B,0)
      const DIndex = await sortedCdps.cdpOfOwnerByIndex(D,0)
      const EIndex = await sortedCdps.cdpOfOwnerByIndex(E,0)

      const A_EBTCBal = await ebtcToken.balanceOf(A)

      // Artificially set base rate to 5%
      await cdpManager.setBaseRate(dec(5, 16))

      // Check baseRate is now non-zero
      const baseRate_1 = await cdpManager.baseRate()
      assert.isTrue(baseRate_1.gt(toBN('0')))

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      // D withdraws EBTC
      await borrowerOperations.withdrawDebt(DIndex, dec(1, 18), AIndex, AIndex, { from: D })

      // Check baseRate should not decrease
      const baseRate_2 = await cdpManager.baseRate()
      assert.isTrue(baseRate_2.eq(baseRate_1))

      // 1 hour passes
      th.fastForwardTime(3600, web3.currentProvider)

      // E withdraws EBTC
      await borrowerOperations.withdrawDebt(EIndex, dec(1, 18), AIndex, AIndex, { from: E })

      // Check baseRate should not decrease
      const baseRate_3 = await cdpManager.baseRate()
      assert.isTrue(baseRate_3.eq(baseRate_2))
    })

    it("withdrawDebt(): reverts when calling address does not have active cdp", async () => {
      await openCdp({ ICR: toBN(dec(10, 18)), extraParams: { from: alice } })
      await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: bob } })

      const bobIndex = await sortedCdps.cdpOfOwnerByIndex(bob,0)
      const carolIndex = th.RANDOM_INDEX

      // Bob successfully withdraws EBTC
      const txBob = await borrowerOperations.withdrawDebt(bobIndex, dec(1, 16), bobIndex, bobIndex, { from: bob })
      assert.isTrue(txBob.receipt.status)

      // Carol with no active cdp attempts to withdraw EBTC
      try {
        const txCarol = await borrowerOperations.withdrawDebt(carolIndex, dec(1, 17), bobIndex, bobIndex, { from: carol })
        assert.isFalse(txCarol.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    it("withdrawDebt(): reverts when requested withdrawal amount is zero EBTC", async () => {
      await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: bob } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)  
      const bobIndex = await sortedCdps.cdpOfOwnerByIndex(bob,0)
      const carolIndex = th.RANDOM_INDEX

      // Bob successfully withdraws 1e-18 EBTC
      const txBob = await borrowerOperations.withdrawDebt(bobIndex, await borrowerOperations.MIN_CHANGE(), bobIndex, bobIndex, { from: bob })
      assert.isTrue(txBob.receipt.status)

      // Alice attempts to withdraw 0 EBTC
      try {
        const txAlice = await borrowerOperations.withdrawDebt(aliceIndex, 0, aliceIndex, aliceIndex, { from: alice })
        assert.isFalse(txAlice.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    it("withdrawDebt(): reverts when system is in Recovery Mode", async () => {
      await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: bob } })
      await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: carol } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)  
      const bobIndex = await sortedCdps.cdpOfOwnerByIndex(bob,0)
      const carolIndex = await sortedCdps.cdpOfOwnerByIndex(carol,0)

      assert.isFalse(await th.checkRecoveryMode(contracts))

      // Withdrawal possible when recoveryMode == false
      const txAlice = await borrowerOperations.withdrawDebt(aliceIndex, dec(1, 16), aliceIndex, aliceIndex, { from: alice })
      assert.isTrue(txAlice.receipt.status)

      await priceFeed.setPrice(dec(3000, 13))

      assert.isTrue(await th.checkRecoveryMode(contracts))

      //Check EBTC withdrawal impossible when recoveryMode == true
      try {
        const txBob = await borrowerOperations.withdrawDebt(bobIndex, 1, bobIndex, bobIndex, { from: bob })
        assert.isFalse(txBob.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    it("withdrawDebt(): reverts when withdrawal would bring the cdp's ICR < MCR", async () => {
      await openCdp({ ICR: toBN(dec(10, 18)), extraParams: { from: alice } })
      await openCdp({ ICR: toBN(dec(111, 16)), extraParams: { from: bob } }) // 111% ICR

      const bobIndex = await sortedCdps.cdpOfOwnerByIndex(bob,0)

      // Bob tries to withdraw EBTC that would bring his ICR < MCR
      try {
        const txBob = await borrowerOperations.withdrawDebt(bobIndex, toBN(100000000000000000), bobIndex, bobIndex, { from: bob })
        assert.isFalse(txBob.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    it("withdrawDebt(): reverts when a withdrawal would cause the TCR of the system to fall below the CCR", async () => {
      await priceFeed.setPrice(dec(3800, 13))

      // Alice and Bob creates cdps with 150% ICR.  System TCR = 151%.
      await openCdp({ ICR: toBN(dec(151, 16)), extraParams: { from: alice } })
      await openCdp({ ICR: toBN(dec(151, 16)), extraParams: { from: bob } })

      const bobIndex = await sortedCdps.cdpOfOwnerByIndex(bob,0)

      // Bob attempts to withdraw 1 EBTC.
      // System TCR would be: ((3+3) * 100 ) / (200+201) = 600/401 = 149.62%, i.e. below CCR of 150%.
      try {
        const txBob = await borrowerOperations.withdrawDebt(bobIndex, dec(1, 18), bobIndex, bobIndex, { from: bob })
        assert.isFalse(txBob.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    it("withdrawDebt(): reverts if system is in Recovery Mode", async () => {
      // --- SETUP ---
      await openCdp({ ICR: toBN(dec(155, 16)), extraParams: { from: alice } })
      await openCdp({ ICR: toBN(dec(155, 16)), extraParams: { from: bob } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)  
      const bobIndex = await sortedCdps.cdpOfOwnerByIndex(bob,0)

      // --- TEST ---

      // price drops to 1ETH:0.007EBTC, reducing TCR below 150%
      await priceFeed.setPrice('7428000000000000');
      assert.isTrue((await th.getCachedTCR(contracts)).lt(toBN(dec(15, 17))))

      try {
        const txData = await borrowerOperations.withdrawDebt(aliceIndex, '200', aliceIndex, aliceIndex, { from: alice })
        assert.isFalse(txData.receipt.status)
      } catch (err) {
        assert.include(err.message, 'revert')
      }
    })

    it("withdrawDebt(): increases the Cdp's EBTC debt by the correct amount", async () => {
      await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)  

      // check before
      const aliceDebtBefore = await getCdpEntireDebt(aliceIndex)
      assert.isTrue(aliceDebtBefore.gt(toBN(0)))

      await borrowerOperations.withdrawDebt(
        aliceIndex, 
        await getNetBorrowingAmount(await borrowerOperations.MIN_CHANGE()), aliceIndex, aliceIndex, 
        { from: alice }
      )

      // check after
      const aliceDebtAfter = await getCdpEntireDebt(aliceIndex)
      th.assertIsApproximatelyEqual(aliceDebtAfter, aliceDebtBefore.add(toBN(100)))
    })

    it("withdrawDebt(): increases EBTC debt in ActivePool by correct amount", async () => {
      await openCdp({ ICR: toBN(dec(10, 18)), extraParams: { from: alice, value: toBN(dec(100, 'ether')) } })
      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)  

      const aliceDebtBefore = await getCdpEntireDebt(aliceIndex)
      assert.isTrue(aliceDebtBefore.gt(toBN(0)))

      // check before
      const activePool_EBTC_Before = await activePool.getSystemDebt()
      assert.isTrue(activePool_EBTC_Before.eq(aliceDebtBefore))

      await borrowerOperations.withdrawDebt(aliceIndex, await getNetBorrowingAmount(dec(1, 17)), aliceIndex, aliceIndex, { from: alice })

      // check after
      const activePool_EBTC_After = await activePool.getSystemDebt()
      th.assertIsApproximatelyEqual(activePool_EBTC_After, activePool_EBTC_Before.add(toBN(dec(1, 17))))
    })

    it("withdrawDebt(): increases user EBTCToken balance by correct amount", async () => {
      await openCdp({ extraParams: { value: toBN(dec(100, 'ether')), from: alice } })
      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)  

      // check before
      const alice_EBTCTokenBalance_Before = await ebtcToken.balanceOf(alice)
      assert.isTrue(alice_EBTCTokenBalance_Before.gt(toBN('0')))

      await borrowerOperations.withdrawDebt(aliceIndex, dec(1, 17), aliceIndex, aliceIndex, { from: alice })

      // check after
      const alice_EBTCTokenBalance_After = await ebtcToken.balanceOf(alice)
      assert.isTrue(alice_EBTCTokenBalance_After.eq(alice_EBTCTokenBalance_Before.add(toBN(dec(1, 17)))))
    })

    // --- repayDebt() ---
    it("repayDebt(): reverts when repayment would leave cdp with ICR < MCR", async () => {
      // alice creates a Cdp and adds first collateral
      await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openCdp({ ICR: toBN(dec(10, 18)), extraParams: { from: bob } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)

      // Price drops
      await priceFeed.setPrice(dec(3800, 13))
      const price = await priceFeed.getPrice()

      assert.isFalse(await cdpManager.checkRecoveryMode(price))
      assert.isTrue((await cdpManager.getCachedICR(aliceIndex, price)).lt(toBN(dec(110, 16))))

      const EBTCRepayment = 1  // 1 wei repayment

     await assertRevert(borrowerOperations.repayDebt(aliceIndex, EBTCRepayment, aliceIndex, aliceIndex, { from: alice }), 
      "BorrowerOperations: An operation that would result in ICR < MCR is not permitted")
    })

    it("repayDebt(): Succeeds when it would leave cdp with net debt >= minimum net debt", async () => {
      // Make the EBTC request 2 wei above min net debt to correct for floor division, and make net debt = min net debt + 1 wei
      await _signer.sendTransaction({ to: A, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: B, value: ethers.utils.parseEther("20000")});
      let _colAmt = dec(10000, 18);
      await contracts.collateral.deposit({from: A, value: ethers.utils.parseEther("20000")});
      await contracts.collateral.deposit({from: B, value: ethers.utils.parseEther("20000")});
      await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: A});
      await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: B});
      await borrowerOperations.openCdp(await getNetBorrowingAmount(MIN_NET_DEBT.add(toBN('2'))), A, A, _colAmt, { from: A })
      const AIndex = await sortedCdps.cdpOfOwnerByIndex(A,0)

      const repayTxA = await borrowerOperations.repayDebt(AIndex, await borrowerOperations.MIN_CHANGE(), AIndex, AIndex, { from: A })
      assert.isTrue(repayTxA.receipt.status)

      let _debtAmt = dec(20, 17);
      let _repayAmt = dec(10, 17);
      await borrowerOperations.openCdp(_debtAmt, B, B, _colAmt, { from: B })
      const BIndex = await sortedCdps.cdpOfOwnerByIndex(B,0)

      const repayTxB = await borrowerOperations.repayDebt(BIndex, _repayAmt, BIndex, BIndex, { from: B })
      assert.isTrue(repayTxB.receipt.status)
    })

    it("repayDebt(): reverts when it would leave cdp with net debt > 0", async () => {
      await _signer.sendTransaction({ to: A, value: ethers.utils.parseEther("20000")});
      let _colAmt = dec(100, 18);
      const price = await priceFeed.getPrice()
      const minNetDebtEth = MIN_NET_DEBT;
      const minNetDebt = minNetDebtEth.mul(price).div(mv._1e18BN)
      const MIN_DEBT = (await getNetBorrowingAmount(minNetDebt)).add(toBN(1))
      await contracts.collateral.deposit({from: A, value: ethers.utils.parseEther("20000")});
      await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: A});
      await borrowerOperations.openCdp(MIN_DEBT.add(toBN('2')), A, A, _colAmt, { from: A })
      const AIndex = await sortedCdps.cdpOfOwnerByIndex(A,0)
      let _aDebt = await cdpManager.getCdpDebt(AIndex);

      const repayTxAPromise = borrowerOperations.repayDebt(AIndex, _aDebt, AIndex, AIndex, { from: A })
      await assertRevert(repayTxAPromise, "BorrowerOperations: Debt must be non-zero")
    })

    it("adjustCdp(): Reverts if repaid amount is greater than current debt", async () => {
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("20000")});
      const { totalDebt } = await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })
      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)  
      
      const repayAmount = totalDebt.add(toBN(1))

      await openCdp({ extraEBTCAmount: repayAmount, ICR: toBN(dec(150, 16)), extraParams: { from: bob } })
      const bobIndex = await sortedCdps.cdpOfOwnerByIndex(bob,0)

      await ebtcToken.transfer(alice, repayAmount, { from: bob })

      await assertRevert(borrowerOperations.adjustCdp(aliceIndex, 0, repayAmount, false, aliceIndex, aliceIndex, { from: alice }),
                         "SafeMath: subtraction overflow")
    })

    it("repayDebt(): reverts when calling address does not own cdp index supplied", async () => {
      await openCdp({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openCdp({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: bob } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)
      const bobIndex = await sortedCdps.cdpOfOwnerByIndex(bob,0)  

      // Bob successfully repays some EBTC
      const txBob = await borrowerOperations.repayDebt(bobIndex, dec(10, 18), bobIndex, bobIndex, { from: bob })
      assert.isTrue(txBob.receipt.status)

      // Carol with no active cdp attempts to repayDebt
      try {
        const txCarol = await borrowerOperations.repayDebt(bobIndex, dec(10, 18), bobIndex, bobIndex, { from: carol })
        assert.isFalse(txCarol.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    it("repayDebt(): reverts when attempted repayment is > the debt of the cdp", async () => {
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("20000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: bob } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)
      const bobIndex = await sortedCdps.cdpOfOwnerByIndex(bob,0)  

      const aliceDebt = await getCdpEntireDebt(aliceIndex)

      // Bob successfully repays some EBTC
      const txBob = await borrowerOperations.repayDebt(bobIndex, dec(10, 18), bobIndex, bobIndex, { from: bob })
      assert.isTrue(txBob.receipt.status)

      // Alice attempts to repay more than her debt
      try {
        const txAlice = await borrowerOperations.repayDebt(aliceIndex, aliceDebt.add(toBN(dec(1, 18))), aliceIndex, aliceIndex, { from: alice })
        assert.isFalse(txAlice.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    //repayDebt: reduces EBTC debt in Cdp
    it("repayDebt(): reduces the Cdp's EBTC debt by the correct amount", async () => {
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("20000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: bob } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)
      const bobIndex = await sortedCdps.cdpOfOwnerByIndex(bob,0)

      const aliceDebtBefore = await getCdpEntireDebt(aliceIndex)
      assert.isTrue(aliceDebtBefore.gt(toBN('0')))

      await borrowerOperations.repayDebt(aliceIndex, aliceDebtBefore.div(toBN(10)), aliceIndex, aliceIndex, { from: alice })  // Repays 1/10 her debt

      const aliceDebtAfter = await getCdpEntireDebt(aliceIndex)
      assert.isTrue(aliceDebtAfter.gt(toBN('0')))

      th.assertIsApproximatelyEqual(aliceDebtAfter, aliceDebtBefore.mul(toBN(9)).div(toBN(10)))  // check 9/10 debt remaining
    })

    it("repayDebt(): decreases EBTC debt in ActivePool by correct amount", async () => {
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("20000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: bob } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)
      const bobIndex = await sortedCdps.cdpOfOwnerByIndex(bob,0)

      const aliceDebtBefore = await getCdpEntireDebt(aliceIndex)
      assert.isTrue(aliceDebtBefore.gt(toBN('0')))

      // Check before
      const activePool_EBTC_Before = await activePool.getSystemDebt()
      assert.isTrue(activePool_EBTC_Before.gt(toBN('0')))

      await borrowerOperations.repayDebt(aliceIndex, aliceDebtBefore.div(toBN(10)), aliceIndex, aliceIndex, { from: alice })  // Repays 1/10 her debt

      // check after
      const activePool_EBTC_After = await activePool.getSystemDebt()
      th.assertIsApproximatelyEqual(activePool_EBTC_After, activePool_EBTC_Before.sub(aliceDebtBefore.div(toBN(10))))
    })

    it("repayDebt(): decreases user EBTCToken balance by correct amount", async () => {
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("20000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: bob } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)
      const bobIndex = await sortedCdps.cdpOfOwnerByIndex(bob,0)

      const aliceDebtBefore = await getCdpEntireDebt(aliceIndex)
      assert.isTrue(aliceDebtBefore.gt(toBN('0')))

      // check before
      const alice_EBTCTokenBalance_Before = await ebtcToken.balanceOf(alice)
      assert.isTrue(alice_EBTCTokenBalance_Before.gt(toBN('0')))

      await borrowerOperations.repayDebt(aliceIndex, aliceDebtBefore.div(toBN(10)), aliceIndex, aliceIndex, { from: alice })  // Repays 1/10 her debt

      // check after
      const alice_EBTCTokenBalance_After = await ebtcToken.balanceOf(alice)
      th.assertIsApproximatelyEqual(alice_EBTCTokenBalance_After, alice_EBTCTokenBalance_Before.sub(aliceDebtBefore.div(toBN(10))))
    })

    //TODO: fix
    xit("repayDebt(): can repay debt in Recovery Mode", async () => {
      await openCdp({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openCdp({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: bob } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)
      const bobIndex = await sortedCdps.cdpOfOwnerByIndex(bob,0)

      const aliceDebtBefore = await getCdpEntireDebt(aliceIndex)
      assert.isTrue(aliceDebtBefore.gt(toBN('0')))

      assert.isFalse(await th.checkRecoveryMode(contracts))

      await priceFeed.setPrice('105000000000000000000')

      assert.isTrue(await th.checkRecoveryMode(contracts))

      const tx = await borrowerOperations.repayDebt(aliceIndex, aliceDebtBefore.div(toBN(10)), aliceIndex, aliceIndex, { from: alice })
      assert.isTrue(tx.receipt.status)

      // Check Alice's debt: 110 (initial) - 50 (repaid)
      const aliceDebtAfter = await getCdpEntireDebt(alice)
      th.assertIsApproximatelyEqual(aliceDebtAfter, aliceDebtBefore.mul(toBN(9)).div(toBN(10)))
    })

    it("repayDebt(): Reverts if borrower has insufficient EBTC balance to cover his debt repayment", async () => {
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: B, value: ethers.utils.parseEther("20000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      
      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)
      const BIndex = await sortedCdps.cdpOfOwnerByIndex(B,0)

      const bobBalBefore = await ebtcToken.balanceOf(B)
      assert.isTrue(bobBalBefore.gt(toBN('0')))

      // Bob transfers all but 5 of his EBTC to Carol
      await ebtcToken.transfer(C, bobBalBefore.sub((toBN(dec(5, 18)))), { from: B })

      //Confirm B's EBTC balance has decreased to 5 EBTC
      const bobBalAfter = await ebtcToken.balanceOf(B)

      assert.isTrue(bobBalAfter.eq(toBN(dec(5, 18))))
      
      // Bob tries to repay 6 EBTC
      const repayDebtPromise_B = borrowerOperations.repayDebt(BIndex, toBN(dec(6, 18)), BIndex, BIndex, { from: B })

      await assertRevert(repayDebtPromise_B, "Caller doesnt have enough EBTC to make repayment")
    })

    // --- adjustCdp() ---

    it("adjustCdp(): reverts when adjustment would leave cdp with ICR < MCR", async () => {
      // alice creates a Cdp and adds first collateral
      await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openCdp({ ICR: toBN(dec(10, 18)), extraParams: { from: bob } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)
      const bobIndex = await sortedCdps.cdpOfOwnerByIndex(bob,0)

      // Price drops
      await priceFeed.setPrice(dec(3800, 13))
      const price = await priceFeed.getPrice()

      assert.isFalse(await cdpManager.checkRecoveryMode(price))
      assert.isTrue((await cdpManager.getCachedICR(aliceIndex, price)).lt(toBN(dec(110, 16))))

      const EBTCRepayment = 1  // 1 wei repayment
      const collTopUp = 1

     await assertRevert(borrowerOperations.adjustCdp(aliceIndex, 0, EBTCRepayment, false, aliceIndex, aliceIndex, { from: alice, value: collTopUp }), 
      "BorrowerOperations: An operation that would result in ICR < MCR is not permitted")
    })

    it("adjustCdp(): Borrowing at zero rate does not change EBTC balance of LQTY staking contract", async () => {
      await openCdp({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openCdp({ extraEBTCAmount: toBN(dec(30, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openCdp({ extraEBTCAmount: toBN(dec(40, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openCdp({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })
      await openCdp({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      const DIndex = await sortedCdps.cdpOfOwnerByIndex(D,0)

      // Origination fee is assumed to be zero

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      // Check staking EBTC balance before > 0
      const lqtyStaking_EBTCBalance_Before = await ebtcToken.balanceOf(feeRecipient.address)
      assert.isTrue(lqtyStaking_EBTCBalance_Before.eq(toBN('0')))

      // D adjusts cdp
      await borrowerOperations.adjustCdp(DIndex, 0, dec(37, 18), true, DIndex, DIndex, { from: D })

      // Check staking EBTC balance after > staking balance before
      const lqtyStaking_EBTCBalance_After = await ebtcToken.balanceOf(feeRecipient.address)
      assert.isTrue(lqtyStaking_EBTCBalance_After.eq(lqtyStaking_EBTCBalance_Before))
    })

    it("adjustCdp(): Borrowing at zero base rate sends total requested EBTC to the user", async () => {
      await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: A, value: ethers.utils.parseEther("50000")});
      await _signer.sendTransaction({ to: B, value: ethers.utils.parseEther("50000")});
      await _signer.sendTransaction({ to: C, value: ethers.utils.parseEther("50000")});
      await _signer.sendTransaction({ to: D, value: ethers.utils.parseEther("50000")});
      await openCdp({ extraEBTCAmount: toBN(dec(200, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: whale, value: toBN(dec(100, 'ether')) } })
      await openCdp({ extraEBTCAmount: toBN(dec(400, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openCdp({ extraEBTCAmount: toBN(dec(400, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openCdp({ extraEBTCAmount: toBN(dec(400, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })
      await openCdp({ extraEBTCAmount: toBN(dec(400, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      const DIndex = await sortedCdps.cdpOfOwnerByIndex(D,0)

      const D_EBTCBalBefore = await ebtcToken.balanceOf(D)

      // Origination fee is assumed to be zero

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      const DUSDBalanceBefore = await ebtcToken.balanceOf(D)

      // D adjusts cdp
      const EBTCRequest_D = toBN(dec(40, 18))
      await borrowerOperations.adjustCdp(DIndex, 0, EBTCRequest_D, true, DIndex, DIndex, { from: D })

      // Check D's EBTC balance increased by their requested EBTC
      const EBTCBalanceAfter = await ebtcToken.balanceOf(D)
      assert.isTrue(EBTCBalanceAfter.eq(D_EBTCBalBefore.add(EBTCRequest_D)))
    })

    it("adjustCdp(): reverts when calling address does not own the cdp index specified", async () => {
      await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("20000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openCdp({ extraEBTCAmount: toBN(dec(200, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: bob } })
      
      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)
      const bobIndex = await sortedCdps.cdpOfOwnerByIndex(bob,0)

      // Alice coll and debt increase(+1 ETH, +50EBTC)
      await borrowerOperations.adjustCdpWithColl(aliceIndex, 0, dec(50, 18), true, aliceIndex, aliceIndex, dec(1, 'ether'), { from: alice })

      try {
        const txCarol = await borrowerOperations.adjustCdpWithColl(aliceIndex, 0, dec(50, 18), true, aliceIndex, aliceIndex, dec(1, 'ether'), { from: carol })
        assert.isFalse(txCarol.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    it("adjustCdp(): reverts in Recovery Mode when the adjustment would reduce the TCR", async () => {
      await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("20000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openCdp({ extraEBTCAmount: toBN(dec(200, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: bob } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)
      const bobIndex = await sortedCdps.cdpOfOwnerByIndex(bob,0)

      assert.isFalse(await th.checkRecoveryMode(contracts))

      const txAlice = await borrowerOperations.adjustCdpWithColl(aliceIndex, 0, dec(50, 18), true, aliceIndex, aliceIndex, dec(1, 'ether'), { from: alice })
      assert.isTrue(txAlice.receipt.status)

      await priceFeed.setPrice(dec(3000, 13)) // trigger drop in ETH price

      assert.isTrue(await th.checkRecoveryMode(contracts))

      try { // collateral withdrawal should also fail
        const txAlice = await borrowerOperations.adjustCdp(aliceIndex, dec(1, 17), 0, false, aliceIndex, aliceIndex, { from: alice })
        assert.isFalse(txAlice.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }

      try { // debt increase should fail
        const txBob = await borrowerOperations.adjustCdp(bobIndex, 0, dec(1, 18), true, bobIndex, bobIndex, { from: bob })
        assert.isFalse(txBob.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }

      try { // debt increase that's also a collateral increase should also fail, if ICR will be worse off
        const txBob = await borrowerOperations.adjustCdp(bobIndex, 0, dec(1, 18), true, bobIndex, bobIndex, { from: bob, value: dec(1, 'ether') })
        assert.isFalse(txBob.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    it("adjustCdp(): collateral withdrawal reverts in Recovery Mode", async () => {
      await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("20000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openCdp({ extraEBTCAmount: toBN(dec(200, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: bob } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)

      assert.isFalse(await th.checkRecoveryMode(contracts))

      await priceFeed.setPrice(dec(3000, 13)) // trigger drop in ETH price

      assert.isTrue(await th.checkRecoveryMode(contracts))

      // Alice attempts an adjustment that repays half her debt BUT withdraws 1 wei collateral, and fails
      await assertRevert(borrowerOperations.adjustCdp(aliceIndex, 1, dec(5000, 18), false, aliceIndex, aliceIndex, { from: alice }),
        "BorrowerOperations: Collateral withdrawal not permitted during Recovery Mode")
    })

    it("adjustCdp(): debt increase that would leave ICR < 150% reverts in Recovery Mode", async () => {
      await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("20000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openCdp({ extraEBTCAmount: toBN(dec(200, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: bob } })
      const CCR = await cdpManager.CCR()

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)

      assert.isFalse(await th.checkRecoveryMode(contracts))

      await priceFeed.setPrice(dec(3000, 13)) // trigger drop in ETH price
      const price = await priceFeed.getPrice()

      assert.isTrue(await th.checkRecoveryMode(contracts))

      const ICR_A = await cdpManager.getCachedICR(aliceIndex, price)

      const aliceDebt = await getCdpEntireDebt(aliceIndex)
      const aliceColl = await getCdpEntireColl(aliceIndex)
      const debtIncrease = toBN(dec(1, 16))
      const collIncrease = toBN(dec(1, 'ether'))

      // Check the new ICR would be an improvement, but less than the CCR (150%)
      const newICR = await cdpManager.computeICR(aliceColl.add(collIncrease), aliceDebt.add(debtIncrease), price)

      assert.isTrue(newICR.gt(ICR_A) && newICR.lt(CCR))

      await assertRevert(borrowerOperations.adjustCdpWithColl(aliceIndex, 0, debtIncrease, true, aliceIndex, aliceIndex, collIncrease, { from: alice }),
        "BorrowerOperations: Operation must leave cdp with ICR >= CCR")
    })

    it("adjustCdp(): debt increase that would reduce the ICR reverts in Recovery Mode", async () => {
      await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("20000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(3, 18)), extraParams: { from: alice } })
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: bob } })
      const CCR = await cdpManager.CCR()

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)
      const bobIndex = await sortedCdps.cdpOfOwnerByIndex(bob,0)

      assert.isFalse(await th.checkRecoveryMode(contracts))

      await priceFeed.setPrice(dec(3200, 13)) // trigger drop in ETH price
      const price = await priceFeed.getPrice()

      assert.isTrue(await th.checkRecoveryMode(contracts))

      //--- Alice with ICR > 150% tries to reduce her ICR ---

      const ICR_A = await cdpManager.getCachedICR(aliceIndex, price)

      // Check Alice's initial ICR is above 150%
      assert.isTrue(ICR_A.gt(CCR))

      const aliceDebt = await getCdpEntireDebt(aliceIndex)
      const aliceColl = await getCdpEntireColl(aliceIndex)
      const aliceDebtIncrease = toBN(dec(1, 18))
      const aliceCollIncrease = toBN(dec(5, 'ether'))

      const newICR_A = await cdpManager.computeICR(aliceColl.add(aliceCollIncrease), aliceDebt.add(aliceDebtIncrease), price)

      // Check Alice's new ICR would reduce but still be greater than CCR
      assert.isTrue(newICR_A.lt(ICR_A) && newICR_A.gt(CCR))

      await assertRevert(borrowerOperations.adjustCdp(aliceIndex, 0, aliceDebtIncrease, true, aliceIndex, aliceIndex, { from: alice, value: aliceCollIncrease }),
        "BorrowerOperations: Cannot decrease your Cdp's ICR in Recovery Mode")

      //--- Bob with ICR < CCR tries to reduce his ICR ---

      const ICR_B = await cdpManager.getCachedICR(bobIndex, price)

      // Check Bob's initial ICR is below 150%
      assert.isTrue(ICR_B.lt(CCR))

      const bobDebt = await getCdpEntireDebt(bobIndex)
      const bobColl = await getCdpEntireColl(bobIndex)
      const bobDebtIncrease = toBN(dec(450, 18))
      const bobCollIncrease = toBN(dec(1, 'ether'))

      const newICR_B = await cdpManager.computeICR(bobColl.add(bobCollIncrease), bobDebt.add(bobDebtIncrease), price)

      // Check Bob's new ICR would reduce 
      assert.isTrue(newICR_B.lt(ICR_B))

      await assertRevert(borrowerOperations.adjustCdp(bobIndex, 0, bobDebtIncrease, true, bobIndex, bobIndex, { from: bob, value: bobCollIncrease }),
        " BorrowerOperations: Operation must leave cdp with ICR >= CCR")
    })

    it("adjustCdp(): A cdp with ICR < CCR in Recovery Mode can adjust their cdp to ICR > CCR", async () => {
      await openCdp({ extraEBTCAmount: toBN(dec(1, 17)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openCdp({ extraEBTCAmount: toBN(dec(1, 17)), ICR: toBN(dec(2, 18)), extraParams: { from: bob } })
      const CCR = await cdpManager.CCR()

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)

      assert.isFalse(await th.checkRecoveryMode(contracts))

      await priceFeed.setPrice(dec(3000, 13)) // trigger drop in ETH price
      const price = await priceFeed.getPrice()

      assert.isTrue(await th.checkRecoveryMode(contracts))

      const ICR_A = await cdpManager.getCachedICR(aliceIndex, price)
      // Check initial ICR is below 150%
      assert.isTrue(ICR_A.lt(CCR))

      const aliceDebt = await getCdpEntireDebt(aliceIndex)
      const aliceColl = await getCdpEntireColl(aliceIndex)
      const debtIncrease = toBN(dec(1, 17))
      const collIncrease = toBN(dec(15, 'ether'))

      const newICR = await cdpManager.computeICR(aliceColl.add(collIncrease), aliceDebt.add(debtIncrease), price)

      // Check new ICR would be > 150%
      assert.isTrue(newICR.gt(CCR))

      const tx = await borrowerOperations.adjustCdpWithColl(aliceIndex, 0, debtIncrease, true, aliceIndex, aliceIndex, collIncrease, { from: alice })
      assert.isTrue(tx.receipt.status)

      const actualNewICR = await cdpManager.getCachedICR(aliceIndex, price)
      assert.isTrue(actualNewICR.gt(CCR))
    })

    it("adjustCdp(): A cdp with ICR > CCR in Recovery Mode can improve their ICR", async () => {
      await openCdp({ extraEBTCAmount: toBN(dec(1, 17)), ICR: toBN(dec(3, 18)), extraParams: { from: alice } })
      await openCdp({ extraEBTCAmount: toBN(dec(1, 17)), ICR: toBN(dec(2, 18)), extraParams: { from: bob } })
      const CCR = await cdpManager.CCR()

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)

      assert.isFalse(await th.checkRecoveryMode(contracts))

      await priceFeed.setPrice(dec(3200, 13)) // trigger drop in ETH price
      const price = await priceFeed.getPrice()

      assert.isTrue(await th.checkRecoveryMode(contracts))

      const initialICR = await cdpManager.getCachedICR(aliceIndex, price)
      // Check initial ICR is above CCR
      assert.isTrue(initialICR.gt(CCR))

      const aliceDebt = await getCdpEntireDebt(aliceIndex)
      const aliceColl = await getCdpEntireColl(aliceIndex)
      const debtIncrease = toBN(dec(1, 18))
      const collIncrease = toBN(dec(100, 'ether'))

      const newICR = await cdpManager.computeICR(aliceColl.add(collIncrease), aliceDebt.add(debtIncrease), price)

      // Check new ICR would be > old ICR
      assert.isTrue(newICR.gt(initialICR))
      const tx = await borrowerOperations.adjustCdpWithColl(aliceIndex, 0, debtIncrease, true, aliceIndex, aliceIndex, collIncrease, { from: alice })
      assert.isTrue(tx.receipt.status)

      const actualNewICR = await cdpManager.getCachedICR(aliceIndex, price)
      assert.isTrue(actualNewICR.gt(initialICR))
    })

    it("adjustCdp(): reverts when change would cause the TCR of the system to fall below the CCR", async () => {
      await priceFeed.setPrice(dec(3000, 13))

      await openCdp({ ICR: toBN(dec(15, 17)), extraParams: { from: alice } })
      await openCdp({ ICR: toBN(dec(15, 17)), extraParams: { from: bob } })

      const bobIndex = await sortedCdps.cdpOfOwnerByIndex(bob,0)

      // Check TCR and Recovery Mode
      const TCR = (await th.getCachedTCR(contracts)).toString()
      assert.equal(TCR, '1500000000000000000')
      assert.isFalse(await th.checkRecoveryMode(contracts))

      // Bob attempts an operation that would bring the TCR below the CCR
      try {
        const txBob = await borrowerOperations.adjustCdp(bobIndex, 0, dec(1, 18), true, bobIndex, bobIndex, { from: bob })
        assert.isFalse(txBob.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    it("adjustCdp(): reverts when EBTC repaid is > debt of the cdp", async () => {
      await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      const bobOpenTx = (await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: bob } })).tx

      const bobIndex = await sortedCdps.cdpOfOwnerByIndex(bob,0)

      const bobDebt = await getCdpEntireDebt(bobIndex)
      assert.isTrue(bobDebt.gt(toBN('0')))

      const remainingDebt = (await cdpManager.getCdpDebt(bobIndex))

      // Bob attempts an adjustment that would repay 1 wei more than his debt
      await assertRevert(
        borrowerOperations.adjustCdp(bobIndex, 0, remainingDebt.add(toBN(1)), false, bobIndex, bobIndex, { from: bob, value: dec(1, 'ether') }),
        "revert"
      )
    })

    it("adjustCdp(): reverts when attempted ETH withdrawal is >= the cdp's collateral", async () => {
      await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: bob } })
      await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: carol } })
      const carolIndex = await sortedCdps.cdpOfOwnerByIndex(carol,0)

      const carolColl = await getCdpEntireColl(carolIndex)

      // Carol attempts an adjustment that would withdraw 1 wei more than her ETH
      try {
        const txCarol = await borrowerOperations.adjustCdp(carolIndex, carolColl.add(toBN(1)), 0, true, carolIndex, carolIndex, { from: carol })
        assert.isFalse(txCarol.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    it("adjustCdp(): reverts when change would cause the ICR of the cdp to fall below the MCR", async () => {
      await openCdp({ extraEBTCAmount: toBN(dec(1, 17)), ICR: toBN(dec(100, 18)), extraParams: { from: whale } })

      await priceFeed.setPrice(dec(3800, 13))

      await openCdp({ extraEBTCAmount: toBN(dec(1, 17)), ICR: toBN(dec(12, 17)), extraParams: { from: alice } })
      await openCdp({ extraEBTCAmount: toBN(dec(1, 17)), ICR: toBN(dec(12, 17)), extraParams: { from: bob } })

      const bobIndex = await sortedCdps.cdpOfOwnerByIndex(bob,0)

      // Bob attempts to increase debt by 100 EBTC and 1 ether, i.e. a change that constitutes a 100% ratio of coll:debt.
      // Since his ICR prior is 110%, this change would reduce his ICR below MCR.
      try {
        const txBob = await borrowerOperations.adjustCdp(bobIndex, 0, dec(1, 18), true, bobIndex, bobIndex, { from: bob, value: dec(1, 'ether') })
        assert.isFalse(txBob.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    it("adjustCdp(): With 0 coll change, doesnt change borrower's coll or ActivePool coll", async () => {
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("50000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)

      const aliceCollBefore = await getCdpEntireColl(aliceIndex)
      const activePoolCollBefore = await activePool.getSystemCollShares()

      assert.isTrue(aliceCollBefore.gt(toBN('0')))
      assert.isTrue(aliceCollBefore.eq(activePoolCollBefore))

      // Alice adjusts cdp. No coll change, and a debt increase (+1EBTC)
      await borrowerOperations.adjustCdp(aliceIndex, 0, dec(1, 18), true, aliceIndex, aliceIndex, { from: alice, value: 0 })

      const aliceCollAfter = await getCdpEntireColl(aliceIndex)
      const activePoolCollAfter = await activePool.getSystemCollShares()

      assert.isTrue(aliceCollAfter.eq(activePoolCollAfter))
      assert.isTrue(activePoolCollAfter.eq(activePoolCollAfter))
    })

    it("adjustCdp(): With 0 debt change, doesnt change borrower's debt or ActivePool debt", async () => {
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("50000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)

      const aliceDebtBefore = await getCdpEntireDebt(aliceIndex)
      const activePoolDebtBefore = await activePool.getSystemDebt()

      assert.isTrue(aliceDebtBefore.gt(toBN('0')))
      assert.isTrue(aliceDebtBefore.eq(activePoolDebtBefore))

      // Alice adjusts cdp. Coll change, no debt change
      await borrowerOperations.adjustCdpWithColl(aliceIndex, 0, 0, false, aliceIndex, aliceIndex, dec(1, 'ether'), { from: alice })

      const aliceDebtAfter = await getCdpEntireDebt(aliceIndex)
      const activePoolDebtAfter = await activePool.getSystemDebt()

      assert.isTrue(aliceDebtAfter.eq(aliceDebtBefore))
      assert.isTrue(activePoolDebtAfter.eq(activePoolDebtBefore))
    })

    it("adjustCdp(): updates borrower's debt and coll with an increase in both", async () => {
      await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("50000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)

      const debtBefore = await getCdpEntireDebt(aliceIndex)
      const collBefore = await getCdpEntireColl(aliceIndex)
      assert.isTrue(debtBefore.gt(toBN('0')))
      assert.isTrue(collBefore.gt(toBN('0')))

      // Alice adjusts cdp. Coll and debt increase(+1 ETH, +50EBTC)
      await borrowerOperations.adjustCdpWithColl(aliceIndex, 0, await getNetBorrowingAmount(dec(50, 18)), true, aliceIndex, aliceIndex, dec(1, 'ether'), { from: alice })

      const debtAfter = await getCdpEntireDebt(aliceIndex)
      const collAfter = await getCdpEntireColl(aliceIndex)

      th.assertIsApproximatelyEqual(debtAfter, debtBefore.add(toBN(dec(50, 18))), 10000)
      th.assertIsApproximatelyEqual(collAfter, collBefore.add(toBN(dec(1, 18))), 10000)
    })

    it("adjustCdp(): updates borrower's debt and coll with a decrease in both", async () => {
      await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("50000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)

      const debtBefore = await getCdpEntireDebt(aliceIndex)
      const collBefore = await getCdpEntireColl(aliceIndex)
      assert.isTrue(debtBefore.gt(toBN('0')))
      assert.isTrue(collBefore.gt(toBN('0')))

      // Alice adjusts cdp coll and debt decrease (-0.5 ETH, -50EBTC)
      await borrowerOperations.adjustCdp(aliceIndex, dec(500, 'finney'), dec(50, 18), false, aliceIndex, aliceIndex, { from: alice })

      const debtAfter = await getCdpEntireDebt(aliceIndex)
      const collAfter = await getCdpEntireColl(aliceIndex)

      assert.isTrue(debtAfter.eq(debtBefore.sub(toBN(dec(50, 18)))))
      assert.isTrue(collAfter.eq(collBefore.sub(toBN(dec(5, 17)))))
    })

    it("adjustCdp(): updates borrower's  debt and coll with coll increase, debt decrease", async () => {
      await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("50000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)

      const debtBefore = await getCdpEntireDebt(aliceIndex)
      const collBefore = await getCdpEntireColl(aliceIndex)
      assert.isTrue(debtBefore.gt(toBN('0')))
      assert.isTrue(collBefore.gt(toBN('0')))

      // Alice adjusts cdp - coll increase and debt decrease (+0.5 ETH, -50EBTC)
      await borrowerOperations.adjustCdpWithColl(aliceIndex, 0, dec(50, 18), false, aliceIndex, aliceIndex, dec(500, 'finney'), { from: alice })

      const debtAfter = await getCdpEntireDebt(aliceIndex)
      const collAfter = await getCdpEntireColl(aliceIndex)

      th.assertIsApproximatelyEqual(debtAfter, debtBefore.sub(toBN(dec(50, 18))), 10000)
      th.assertIsApproximatelyEqual(collAfter, collBefore.add(toBN(dec(5, 17))), 10000)
    })

    it("adjustCdp(): updates borrower's debt and coll with coll decrease, debt increase", async () => {
      await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("50000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)

      const debtBefore = await getCdpEntireDebt(aliceIndex)
      const collBefore = await getCdpEntireColl(aliceIndex)
      assert.isTrue(debtBefore.gt(toBN('0')))
      assert.isTrue(collBefore.gt(toBN('0')))

      // Alice adjusts cdp - coll decrease and debt increase (0.1 ETH, 10EBTC)
      await borrowerOperations.adjustCdp(aliceIndex, dec(1, 17), await getNetBorrowingAmount(dec(1, 18)), true, aliceIndex, aliceIndex, { from: alice })

      const debtAfter = await getCdpEntireDebt(aliceIndex)
      const collAfter = await getCdpEntireColl(aliceIndex)

      th.assertIsApproximatelyEqual(debtAfter, debtBefore.add(toBN(dec(1, 18))), 10000)
      th.assertIsApproximatelyEqual(collAfter, collBefore.sub(toBN(dec(1, 17))), 10000)
    })

    it("adjustCdp(): updates borrower's stake and totalStakes with a coll increase", async () => {
      await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("50000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)

      const stakeBefore = await cdpManager.getCdpStake(aliceIndex)
      const totalStakesBefore = await cdpManager.totalStakes();
      assert.isTrue(stakeBefore.gt(toBN('0')))
      assert.isTrue(totalStakesBefore.gt(toBN('0')))

      // Alice adjusts cdp - coll and debt increase (+1 ETH, +50 EBTC)
      await borrowerOperations.adjustCdpWithColl(aliceIndex, 0, dec(50, 18), true, aliceIndex, aliceIndex, dec(1, 'ether'), { from: alice })

      const stakeAfter = await cdpManager.getCdpStake(aliceIndex)
      const totalStakesAfter = await cdpManager.totalStakes();

      assert.isTrue(stakeAfter.eq(stakeBefore.add(toBN(dec(1, 18)))))
      assert.isTrue(totalStakesAfter.eq(totalStakesBefore.add(toBN(dec(1, 18)))))
    })

    it("adjustCdp(): updates borrower's stake and totalStakes with a coll decrease", async () => {
      await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("50000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)

      const stakeBefore = await cdpManager.getCdpStake(aliceIndex)
      const totalStakesBefore = await cdpManager.totalStakes();
      assert.isTrue(stakeBefore.gt(toBN('0')))
      assert.isTrue(totalStakesBefore.gt(toBN('0')))

      // Alice adjusts cdp - coll decrease and debt decrease
      await borrowerOperations.adjustCdp(aliceIndex, dec(500, 'finney'), dec(50, 18), false, aliceIndex, aliceIndex, { from: alice })

      const stakeAfter = await cdpManager.getCdpStake(aliceIndex)
      const totalStakesAfter = await cdpManager.totalStakes();

      assert.isTrue(stakeAfter.eq(stakeBefore.sub(toBN(dec(5, 17)))))
      assert.isTrue(totalStakesAfter.eq(totalStakesBefore.sub(toBN(dec(5, 17)))))
    })

    it("adjustCdp(): changes EBTCToken balance by the requested decrease", async () => {
      await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("50000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)

      const alice_EBTCTokenBalance_Before = await ebtcToken.balanceOf(alice)
      assert.isTrue(alice_EBTCTokenBalance_Before.gt(toBN('0')))

      // Alice adjusts cdp - coll decrease and debt decrease
      await borrowerOperations.adjustCdp(aliceIndex, dec(100, 'finney'), dec(10, 18), false, aliceIndex, aliceIndex, { from: alice })

      // check after
      const alice_EBTCTokenBalance_After = await ebtcToken.balanceOf(alice)
      assert.isTrue(alice_EBTCTokenBalance_After.eq(alice_EBTCTokenBalance_Before.sub(toBN(dec(10, 18)))))
    })

    it("adjustCdp(): changes EBTCToken balance by the requested increase", async () => {
      await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("50000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)

      const alice_EBTCTokenBalance_Before = await ebtcToken.balanceOf(alice)
      assert.isTrue(alice_EBTCTokenBalance_Before.gt(toBN('0')))

      // Alice adjusts cdp - coll increase and debt increase
      await borrowerOperations.adjustCdpWithColl(aliceIndex, 0, dec(100, 18), true, aliceIndex, aliceIndex, dec(1, 'ether'), { from: alice })

      // check after
      const alice_EBTCTokenBalance_After = await ebtcToken.balanceOf(alice)
      assert.isTrue(alice_EBTCTokenBalance_After.eq(alice_EBTCTokenBalance_Before.add(toBN(dec(100, 18)))))
    })

    it("adjustCdp(): Changes the activePool ETH and raw ether balance by the requested decrease", async () => {
      await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("50000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)

      const activePool_ETH_Before = await activePool.getSystemCollShares()
      assert.isTrue(activePool_ETH_Before.gt(toBN('0')))

      // Alice adjusts cdp - coll decrease and debt decrease
      await borrowerOperations.adjustCdp(aliceIndex, dec(100, 'finney'), dec(10, 18), false, aliceIndex, aliceIndex, { from: alice })

      const activePool_ETH_After = await activePool.getSystemCollShares()
      assert.isTrue(activePool_ETH_After.eq(activePool_ETH_Before.sub(toBN(dec(1, 17)))))
    })

    it("adjustCdp(): Changes the activePool ETH and raw ether balance by the amount of ETH sent", async () => {
      await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("50000")});

      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)

      const activePool_ETH_Before = await activePool.getSystemCollShares()
      assert.isTrue(activePool_ETH_Before.gt(toBN('0')))

      // Alice adjusts cdp - coll increase and debt increase
      await borrowerOperations.adjustCdpWithColl(aliceIndex, 0, dec(100, 18), true, aliceIndex, aliceIndex, dec(1, 'ether'), { from: alice })

      const activePool_ETH_After = await activePool.getSystemCollShares()
      assert.isTrue(activePool_ETH_After.eq(activePool_ETH_Before.add(toBN(dec(1, 18)))))
    })

    it("adjustCdp(): Changes the EBTC debt in ActivePool by requested decrease", async () => {
      await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("50000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)

      const activePool_EBTCDebt_Before = await activePool.getSystemDebt()
      assert.isTrue(activePool_EBTCDebt_Before.gt(toBN('0')))

      // Alice adjusts cdp - coll increase and debt decrease
      await borrowerOperations.adjustCdpWithColl(aliceIndex, 0, dec(30, 18), false, aliceIndex, aliceIndex, dec(1, 'ether'), { from: alice })

      const activePool_EBTCDebt_After = await activePool.getSystemDebt()
      assert.isTrue(activePool_EBTCDebt_After.eq(activePool_EBTCDebt_Before.sub(toBN(dec(30, 18)))))
    })

    it("adjustCdp(): Changes the EBTC debt in ActivePool by requested increase", async () => {
      await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("50000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)

      const activePool_EBTCDebt_Before = await activePool.getSystemDebt()
      assert.isTrue(activePool_EBTCDebt_Before.gt(toBN('0')))

      // Alice adjusts cdp - coll increase and debt increase
      await borrowerOperations.adjustCdpWithColl(aliceIndex, 0, await getNetBorrowingAmount(dec(100, 18)), true, aliceIndex, aliceIndex, dec(1, 'ether'), { from: alice })

      const activePool_EBTCDebt_After = await activePool.getSystemDebt()
    
      th.assertIsApproximatelyEqual(activePool_EBTCDebt_After, activePool_EBTCDebt_Before.add(toBN(dec(100, 18))))
    })

    it("adjustCdp(): new coll = 0 and new debt = 0 is not allowed, as gas compensation still counts toward ICR", async () => {
      await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("50000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)

      const aliceColl = await getCdpEntireColl(aliceIndex)
      const aliceDebt = await getCdpEntireColl(aliceIndex)
      const status_Before = await cdpManager.getCdpStatus(aliceIndex)
      const isInSortedList_Before = await sortedCdps.contains(aliceIndex)

      assert.equal(status_Before, 1)  // 1: Active
      assert.isTrue(isInSortedList_Before)

      await assertRevert(
        borrowerOperations.adjustCdp(aliceIndex, aliceColl, aliceDebt, true, aliceIndex, aliceIndex, { from: alice }),
        'BorrowerOperations: An operation that would result in ICR < MCR is not permitted'
      )
    })

    it("adjustCdp(): Reverts if requested debt increase and amount is zero", async () => {
      await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("50000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)

      await assertRevert(borrowerOperations.adjustCdp(aliceIndex, 0, 0, true, aliceIndex, aliceIndex, { from: alice }),
        'BorrowerOperations: Debt increase requires non-zero debtChange')
    })

    it("adjustCdp(): Reverts if requested coll withdrawal and ether is sent", async () => {
      await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("50000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)

      borrowerOperations.adjustCdpWithColl(
        aliceIndex, dec(1, 'ether'), dec(100, 18), true, aliceIndex, aliceIndex, dec(3, 'ether'), { from: alice }),
        'BorrowerOperations: Cannot add and withdraw collateral in same operation'
    })

    it("adjustCdp(): Reverts if it’s zero adjustment", async () => {
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("20000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })
      
      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)

      await assertRevert(borrowerOperations.adjustCdp(aliceIndex, 0, 0, false, aliceIndex, aliceIndex, { from: alice }),
                         'BorrowerOperations: There must be either a collateral change or a debt change')
    })

    it("adjustCdp(): Reverts if requested coll withdrawal is greater than cdp's collateral", async () => {
      await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("20000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)

      const aliceColl = await getCdpEntireColl(aliceIndex)

      // Requested coll withdrawal > coll in the cdp
      await assertRevert(borrowerOperations.adjustCdp(aliceIndex, aliceColl.add(toBN(1)), 0, false, aliceIndex, aliceIndex, { from: alice }))
      await assertRevert(borrowerOperations.adjustCdp(aliceIndex, aliceColl.add(toBN(dec(37, 'ether'))), 0, false, aliceIndex, aliceIndex, { from: bob }))
    })

    it("adjustCdp(): Reverts if borrower has insufficient EBTC balance to cover his debt repayment", async () => {
      await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: B, value: ethers.utils.parseEther("20000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: B } })

      const BIndex = await sortedCdps.cdpOfOwnerByIndex(B,0)
      const bobDebt = await getCdpEntireDebt(BIndex)

      // Bob transfers some EBTC to carol
      await ebtcToken.transfer(C, dec(10, 18), { from: B })

      //Confirm B's EBTC balance is less than 50 EBTC
      const B_EBTCBal = await ebtcToken.balanceOf(B)
      assert.isTrue(B_EBTCBal.lt(bobDebt))

      const repayDebtPromise_B = borrowerOperations.adjustCdp(BIndex, 0, bobDebt, false, BIndex, BIndex, { from: B })

      // B attempts to repay all his debt
      await assertRevert(repayDebtPromise_B, "revert")
    })

    // --- closeCdp() ---

    it("closeCdp(): reverts when it would lower the TCR below CCR", async () => {
      await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("10000")});
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("10000")});
      await openCdp({ ICR: toBN(dec(300, 16)), extraParams:{ from: alice } })
      await openCdp({ ICR: toBN(dec(120, 16)), extraEBTCAmount: toBN(dec(1, 17)), extraParams:{ from: bob } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)

      const price = await priceFeed.getPrice()
      
      // to compensate borrowing fees
      await ebtcToken.transfer(alice, dec(1, 17), { from: bob })

      assert.isFalse(await cdpManager.checkRecoveryMode(price))
    
      await assertRevert(
        borrowerOperations.closeCdp(aliceIndex, { from: alice }),
        "BorrowerOperations: An operation that would result in TCR < CCR is not permitted"
      )
    })

    it("closeCdp(): reverts when calling address does not own specified cdp", async () => {
      await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("50000")});
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("50000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: bob } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)

      // Carol with no active cdp attempts to close a non-existant cdp
      try {
        const txCarol = await borrowerOperations.closeCdp(aliceIndex, { from: carol })
        assert.isFalse(txCarol.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    it("closeCdp(): reverts when specified cdp does not exist", async () => {
      await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("50000")});
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("50000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: bob } })

      const carolIndex = th.RANDOM_INDEX;

      // Carol with no active cdp attempts to close a non-existant cdp
      try {
        const txCarol = await borrowerOperations.closeCdp(carolIndex, { from: carol })
        assert.isFalse(txCarol.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    it("closeCdp(): reverts when system is in Recovery Mode", async () => {
      await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("50000")});
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("80000")});
      await _signer.sendTransaction({ to: carol, value: ethers.utils.parseEther("50000")});
      await openCdp({ extraEBTCAmount: toBN(dec(1000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: bob } })
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: carol } })

      const bobIndex = await sortedCdps.cdpOfOwnerByIndex(bob,0)
      const carolIndex = await sortedCdps.cdpOfOwnerByIndex(carol,0)

      // Alice transfers her EBTC to Bob and Carol so they can cover fees
      const aliceBal = await ebtcToken.balanceOf(alice)
      await ebtcToken.transfer(bob, aliceBal.div(toBN(2)), { from: alice })
      await ebtcToken.transfer(carol, aliceBal.div(toBN(2)), { from: alice })

      // check Recovery Mode 
      assert.isFalse(await th.checkRecoveryMode(contracts))

      // Bob successfully closes his cdp
      const txBob = await borrowerOperations.closeCdp(bobIndex, { from: bob })
      assert.isTrue(txBob.receipt.status)

      await priceFeed.setPrice(dec(3800, 13))

      assert.isTrue(await th.checkRecoveryMode(contracts))

      // Carol attempts to close her cdp during Recovery Mode
      await assertRevert(borrowerOperations.closeCdp(carolIndex, { from: carol }), "BorrowerOperations: Operation not permitted during Recovery Mode")
    })

    it("closeCdp(): reverts when cdp is the only one in the system", async () => {
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("50000")});
      await openCdp({ extraEBTCAmount: toBN(dec(1000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)

      // Artificially mint to Alice so she has enough to close her cdp
      await ebtcToken.unprotectedMint(alice, dec(100000, 18))

      // Check she has more EBTC than her cdp debt
      const aliceBal = await ebtcToken.balanceOf(alice)
      const aliceDebt = await getCdpEntireDebt(aliceIndex)
      assert.isTrue(aliceBal.gt(aliceDebt))

      // check Recovery Mode
      assert.isFalse(await th.checkRecoveryMode(contracts))

      // Alice attempts to close her cdp
      await assertRevert(borrowerOperations.closeCdp(aliceIndex, { from: alice }), "CdpManager: Only one cdp in the system")
    })

    it("closeCdp(): reduces a Cdp's collateral to zero", async () => {
      await _signer.sendTransaction({ to: dennis, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("20000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: dennis } })
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)

      const aliceCollBefore = await getCdpEntireColl(aliceIndex)
      const dennisEBTC = await ebtcToken.balanceOf(dennis)
      assert.isTrue(aliceCollBefore.gt(toBN('0')))
      assert.isTrue(dennisEBTC.gt(toBN('0')))

      // To compensate borrowing fees
      await ebtcToken.transfer(alice, dennisEBTC.div(toBN(2)), { from: dennis })

      // Alice attempts to close cdp
      await borrowerOperations.closeCdp(aliceIndex, { from: alice })

      const aliceCollAfter = await getCdpEntireColl(aliceIndex)
      assert.equal(aliceCollAfter, '0')
    })

    it("closeCdp(): reduces a Cdp's debt to zero", async () => {
      await _signer.sendTransaction({ to: dennis, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("20000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: dennis } })
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)

      const aliceDebtBefore = await getCdpEntireColl(aliceIndex)
      const dennisEBTC = await ebtcToken.balanceOf(dennis)
      assert.isTrue(aliceDebtBefore.gt(toBN('0')))
      assert.isTrue(dennisEBTC.gt(toBN('0')))

      // To compensate borrowing fees
      await ebtcToken.transfer(alice, dennisEBTC.div(toBN(2)), { from: dennis })

      // Alice attempts to close cdp
      await borrowerOperations.closeCdp(aliceIndex, { from: alice })

      const aliceCollAfter = await getCdpEntireColl(aliceIndex)
      assert.equal(aliceCollAfter, '0')
    })

    it("closeCdp(): sets Cdp's stake to zero", async () => {
      await _signer.sendTransaction({ to: dennis, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("20000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: dennis } })
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)

      const aliceStakeBefore = await getCdpStake(aliceIndex)
      assert.isTrue(aliceStakeBefore.gt(toBN('0')))

      const dennisEBTC = await ebtcToken.balanceOf(dennis)
      assert.isTrue(aliceStakeBefore.gt(toBN('0')))
      assert.isTrue(dennisEBTC.gt(toBN('0')))

      // To compensate borrowing fees
      await ebtcToken.transfer(alice, dennisEBTC.div(toBN(2)), { from: dennis })

      // Alice attempts to close cdp
      await borrowerOperations.closeCdp(aliceIndex, { from: alice })

      const stakeAfter = ((await cdpManager.Cdps(aliceIndex))[2]).toString()
      assert.equal(stakeAfter, '0')
      // check withdrawal was successful
    })

    it("closeCdp(): zero's the cdps reward snapshots", async () => {
      // Dennis opens cdp and transfers tokens to alice
      await _signer.sendTransaction({ to: dennis, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: owner, value: ethers.utils.parseEther("50000")});
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("50000")});
      await _signer.sendTransaction({ to: carol, value: ethers.utils.parseEther("50000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: dennis } })
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: bob } })

      const bobIndex = await sortedCdps.cdpOfOwnerByIndex(bob,0)
      await openCdp({ extraEBTCAmount: toBN(dec(300, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: owner } });
      
      // Price drops
      await priceFeed.setPrice(dec(3000, 13))

      // Liquidate Bob
      await cdpManager.liquidate(bobIndex)
      assert.isFalse(await sortedCdps.contains(bobIndex))

      // Price bounces back
      await priceFeed.setPrice(dec(7427, 13))

      // Alice and Carol open cdps
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: carol } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)
      const carolIndex = await sortedCdps.cdpOfOwnerByIndex(carol,0)

      // Price drops ...again
      await priceFeed.setPrice(dec(3000, 13))

      // Get Alice's pending reward snapshots 
      const L_EBTCDebt_A_Snapshot = (await cdpManager.cdpDebtRedistributionIndex(aliceIndex))
      assert.isTrue(L_EBTCDebt_A_Snapshot.gt(toBN('0')))

      // Liquidate Carol
      await cdpManager.liquidate(carolIndex)
      assert.isFalse(await sortedCdps.contains(carolIndex))

      // Get Alice's pending reward snapshots after Carol's liquidation. Check above 0
      const L_EBTCDebt_Snapshot_A_AfterLiquidation = (await cdpManager.cdpDebtRedistributionIndex(aliceIndex))

      assert.isTrue(L_EBTCDebt_Snapshot_A_AfterLiquidation.gt(toBN('0')))

      // to compensate borrowing fees
      await ebtcToken.transfer(alice, await ebtcToken.balanceOf(dennis), { from: dennis })

      await priceFeed.setPrice(dec(200, 18))

      // Alice closes cdp
      await borrowerOperations.closeCdp(aliceIndex, { from: alice })

      // Check Alice's pending reward snapshots are zero
      const L_EBTCDebt_Snapshot_A_afterAliceCloses = (await cdpManager.cdpDebtRedistributionIndex(aliceIndex))

      assert.equal(L_EBTCDebt_Snapshot_A_afterAliceCloses, '0')
    })

    it("closeCdp(): sets cdp's status to closed and removes it from sorted cdps list", async () => {
      await _signer.sendTransaction({ to: dennis, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("20000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: dennis } })
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)

      // Check Cdp is active
      const alice_Cdp_Before = await cdpManager.Cdps(aliceIndex)
      const status_Before = alice_Cdp_Before[4]

      assert.equal(status_Before, 1)
      assert.isTrue(await sortedCdps.contains(aliceIndex))

      // to compensate borrowing fees
      await ebtcToken.transfer(alice, await ebtcToken.balanceOf(dennis), { from: dennis })

      // Close the cdp
      await borrowerOperations.closeCdp(aliceIndex, { from: alice })

      const alice_Cdp_After = await cdpManager.Cdps(aliceIndex)
      const status_After = alice_Cdp_After[4]

      assert.equal(status_After, 2)
      assert.isFalse(await sortedCdps.contains(aliceIndex))
    })

    it("closeCdp(): reduces ActivePool ETH and raw ether by correct amount", async () => {
      await _signer.sendTransaction({ to: dennis, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("20000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: dennis } })
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)
      const dennisIndex = await sortedCdps.cdpOfOwnerByIndex(dennis,0)

      const dennisColl = await getCdpEntireColl(dennisIndex)
      const aliceColl = await getCdpEntireColl(aliceIndex)
      assert.isTrue(dennisColl.gt('0'))
      assert.isTrue(aliceColl.gt('0'))

      // Check active Pool ETH before
      const activePool_ETH_before = await activePool.getSystemCollShares()
      assert.isTrue(activePool_ETH_before.eq(aliceColl.add(dennisColl)))
      assert.isTrue(activePool_ETH_before.gt(toBN('0')))

      // to compensate borrowing fees
      await ebtcToken.transfer(alice, await ebtcToken.balanceOf(dennis), { from: dennis })

      // Close the cdp
      await borrowerOperations.closeCdp(aliceIndex, { from: alice })

      // Check after
      const activePool_ETH_After = await activePool.getSystemCollShares()
      assert.isTrue(activePool_ETH_After.eq(dennisColl))
    })

    it("closeCdp(): reduces ActivePool debt by correct amount", async () => {
      await _signer.sendTransaction({ to: dennis, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("20000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: dennis } })
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)
      const dennisIndex = await sortedCdps.cdpOfOwnerByIndex(dennis,0)

      const dennisDebt = await getCdpEntireDebt(dennisIndex)
      const aliceDebt = await getCdpEntireDebt(aliceIndex)
      assert.isTrue(dennisDebt.gt('0'))
      assert.isTrue(aliceDebt.gt('0'))

      // Check before
      const activePool_Debt_before = await activePool.getSystemDebt()
      assert.isTrue(activePool_Debt_before.eq(aliceDebt.add(dennisDebt)))
      assert.isTrue(activePool_Debt_before.gt(toBN('0')))

      // to compensate borrowing fees
      await ebtcToken.transfer(alice, await ebtcToken.balanceOf(dennis), { from: dennis })

      // Close the cdp
      await borrowerOperations.closeCdp(aliceIndex, { from: alice })

      // Check after
      const activePool_Debt_After = (await activePool.getSystemDebt()).toString()
      th.assertIsApproximatelyEqual(activePool_Debt_After, dennisDebt)
    })

    it("closeCdp(): updates the the total stakes", async () => {
      await _signer.sendTransaction({ to: dennis, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("20000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: dennis } })
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: bob } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)
      const bobIndex = await sortedCdps.cdpOfOwnerByIndex(bob,0)
      const dennisIndex = await sortedCdps.cdpOfOwnerByIndex(dennis,0)

      // Get individual stakes
      const aliceStakeBefore = await getCdpStake(aliceIndex)
      const bobStakeBefore = await getCdpStake(bobIndex)
      const dennisStakeBefore = await getCdpStake(dennisIndex)
      assert.isTrue(aliceStakeBefore.gt('0'))
      assert.isTrue(bobStakeBefore.gt('0'))
      assert.isTrue(dennisStakeBefore.gt('0'))

      const totalStakesBefore = await cdpManager.totalStakes()

      assert.isTrue(totalStakesBefore.eq(aliceStakeBefore.add(bobStakeBefore).add(dennisStakeBefore)))

      // to compensate borrowing fees
      await ebtcToken.transfer(alice, await ebtcToken.balanceOf(dennis), { from: dennis })

      // Alice closes cdp
      await borrowerOperations.closeCdp(aliceIndex, { from: alice })

      // Check stake and total stakes get updated
      const aliceStakeAfter = await getCdpStake(aliceIndex)
      const totalStakesAfter = await cdpManager.totalStakes()

      assert.equal(aliceStakeAfter, 0)
      assert.isTrue(totalStakesAfter.eq(totalStakesBefore.sub(aliceStakeBefore)))
    })

    if (!withProxy) { // TODO: wrap web3.eth.getBalance to be able to go through proxies
      xit("closeCdp(): sends the correct amount of ETH to the user", async () => {
        await openCdp({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: dennis } })
        await openCdp({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })

        const aliceColl = await getCdpEntireColl(aliceIndex)
        assert.isTrue(aliceColl.gt(toBN('0')))

        const alice_ETHBalance_Before = web3.utils.toBN(await web3.eth.getBalance(alice))

        // to compensate borrowing fees
        await ebtcToken.transfer(alice, await ebtcToken.balanceOf(dennis), { from: dennis })

        await borrowerOperations.closeCdp(aliceIndex, { from: alice, gasPrice: 0 })

        const alice_ETHBalance_After = web3.utils.toBN(await web3.eth.getBalance(alice))
        const balanceDiff = alice_ETHBalance_After.sub(alice_ETHBalance_Before)

        assert.isTrue(balanceDiff.eq(aliceColl))
      })
    }

    it("closeCdp(): subtracts the debt of the closed Cdp from the Borrower's EBTCToken balance", async () => {
      await _signer.sendTransaction({ to: dennis, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("20000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: dennis } })
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)

      const aliceDebt = await getCdpEntireDebt(aliceIndex)
      assert.isTrue(aliceDebt.gt(toBN('0')))

      // to compensate borrowing fees
      await ebtcToken.transfer(alice, await ebtcToken.balanceOf(dennis), { from: dennis })

      const alice_EBTCBalance_Before = await ebtcToken.balanceOf(alice)
      assert.isTrue(alice_EBTCBalance_Before.gt(toBN('0')))

      // close cdp
      await borrowerOperations.closeCdp(aliceIndex, { from: alice })

      // check alice EBTC balance after
      const alice_EBTCBalance_After = await ebtcToken.balanceOf(alice)
      th.assertIsApproximatelyEqual(alice_EBTCBalance_After, alice_EBTCBalance_Before.sub(aliceDebt))
    })

    it("closeCdp(): applies pending rewards", async () => {
      // --- SETUP ---
      await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("200000")});
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: carol, value: ethers.utils.parseEther("20000")});
      await openCdp({ extraEBTCAmount: toBN(dec(1000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })

      const whaleIndex = await sortedCdps.cdpOfOwnerByIndex(whale,0)

      const whaleDebt = await getCdpEntireDebt(whaleIndex)
      const whaleColl = await getCdpEntireColl(whaleIndex)

      await openCdp({ extraEBTCAmount: toBN(dec(150, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openCdp({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: bob } })
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: carol } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)
      const bobIndex = await sortedCdps.cdpOfOwnerByIndex(bob,0)
      const carolIndex = await sortedCdps.cdpOfOwnerByIndex(carol,0)
	  
      let _carolDebtColl = await cdpManager.getSyncedDebtAndCollShares(carolIndex)
      let _carolDebt = _carolDebtColl[0]
      let _carolColl = _carolDebtColl[1]

      // Whale transfers to A and B to cover their fees
      await ebtcToken.transfer(alice, dec(100, 18), { from: whale })
      await ebtcToken.transfer(bob, dec(100, 18), { from: whale })
      await _signer.sendTransaction({ to: owner, value: ethers.utils.parseEther("50000")});
      await openCdp({ extraEBTCAmount: toBN(dec(300, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: owner } });

      // --- TEST ---

      // price drops to 1ETH:100EBTC, reducing Carol's ICR below MCR
      await priceFeed.setPrice(dec(3800, 13));
      const price = await priceFeed.getPrice()

      // liquidate Carol's Cdp, Alice and Bob earn rewards.
      const liquidationTx = await cdpManager.liquidate(carolIndex, { from: owner });
      const [liquidatedDebt_C, liquidatedColl_C, gasComp_C] = th.getEmittedLiquidationValues(liquidationTx)

      // Carol opens a new Cdp
      await _signer.sendTransaction({ to: carol, value: ethers.utils.parseEther("20000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: carol } })

      const carolIndex2 = await sortedCdps.cdpOfOwnerByIndex(carol,0)

      // Second cdp should have a new index
      assert.notEqual(carolIndex, carolIndex2);

      // check Alice and Bob's reward snapshots are zero before they alter their Cdps
      const alice_EBTCDebtRewardSnapshot_Before = await cdpManager.cdpDebtRedistributionIndex(aliceIndex)

      const bob_EBTCDebtRewardSnapshot_Before = await cdpManager.cdpDebtRedistributionIndex(bobIndex)

      assert.equal(alice_EBTCDebtRewardSnapshot_Before, 0)
      assert.equal(bob_EBTCDebtRewardSnapshot_Before, 0)

      const pendingDebtReward_A = (await cdpManager.getPendingRedistributedDebt(aliceIndex))
      assert.isTrue(pendingDebtReward_A.gt(toBN('0')))

      // Close Alice's cdp. Alice's pending rewards should be removed from the DefaultPool when she close.
      await borrowerOperations.closeCdp(aliceIndex, { from: alice })

      // whale adjusts cdp, pulling their rewards out of DefaultPool
      await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("10000")});
      await borrowerOperations.adjustCdp(whaleIndex, 0, dec(1, 18), true, whaleIndex, whaleIndex, { from: whale })

      // Close Bob's cdp. Expect DefaultPool debt still exist since some other CDP not pulls rewards yet.
      await borrowerOperations.closeCdp(bobIndex, { from: bob })
    })

    it("closeCdp(): reverts if borrower has insufficient EBTC balance to repay his entire debt", async () => {
      await _signer.sendTransaction({ to: A, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: B, value: ethers.utils.parseEther("20000")});
      await openCdp({ extraEBTCAmount: toBN(dec(150, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openCdp({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })

      const AIndex = await sortedCdps.cdpOfOwnerByIndex(A,0)
      const BIndex = await sortedCdps.cdpOfOwnerByIndex(B,0)

      // Confirm Bob's EBTC balance is less than his cdp debt
      // Without borrowing fees, we expect balance + gas compensation pool amount to equal debt, so we have to transfer some away otherwise there will be sufficient eBTC in the user's wallet
      let B_EBTCBal = await ebtcToken.balanceOf(B)
      const B_cdpDebt = await getCdpEntireDebt(BIndex)

      assert.isTrue(B_cdpDebt.eq(B_EBTCBal))

      await ebtcToken.transfer(A, 1, {from: B})
      
      B_EBTCBal = await ebtcToken.balanceOf(B)
      assert.isTrue(B_EBTCBal.lt(toBN(B_cdpDebt)))

      const closeCdpPromise_B = borrowerOperations.closeCdp(BIndex, { from: B })

      // Check closing cdp reverts
      await assertRevert(closeCdpPromise_B, "BorrowerOperations: Caller doesnt have enough EBTC to make repayment")
    })

    // --- openCdp() ---

    if (!withProxy) { // TODO: use rawLogs instead of logs
      it("openCdp(): emits a CdpUpdated event with the correct output", async () => {
        await _signer.sendTransaction({ to: A, value: ethers.utils.parseEther("20000")});
        await _signer.sendTransaction({ to: B, value: ethers.utils.parseEther("20000")});
        await _signer.sendTransaction({ to: C, value: ethers.utils.parseEther("50000")});
        const txA = (await openCdp({ extraEBTCAmount: toBN(dec(150, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })).tx
        const txB = (await openCdp({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })).tx
        const txC = (await openCdp({ extraEBTCAmount: toBN(dec(30, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })).tx

        const AIndex = await sortedCdps.cdpOfOwnerByIndex(A,0)
        const BIndex = await sortedCdps.cdpOfOwnerByIndex(B,0)
        const CIndex = await sortedCdps.cdpOfOwnerByIndex(C,0)

        const A_Coll = await getCdpEntireColl(AIndex)
        const B_Coll = await getCdpEntireColl(BIndex)
        const C_Coll = await getCdpEntireColl(CIndex)
        const A_Debt = await getCdpEntireDebt(AIndex)
        const B_Debt = await getCdpEntireDebt(BIndex)
        const C_Debt = await getCdpEntireDebt(CIndex)

        const A_emitted = th.parseCdpUpdatedEvent(txA)
        const B_emitted = th.parseCdpUpdatedEvent(txB)
        const C_emitted = th.parseCdpUpdatedEvent(txC)

        const A_expected = {
          cdpId: AIndex,
          borrower: A,
          oldDebt: toBN(0),
          oldColl: toBN(0),
          debt: A_Debt,
          coll: A_Coll,
          stake: toBN(await cdpManager.getCdpStake(AIndex)),
          operation: toBN(0), //CdpOperation.openCDP
        };

        const B_expected = {
          cdpId: BIndex,
          borrower: B,
          oldDebt: toBN(0),
          oldColl: toBN(0),
          debt: B_Debt,
          coll: B_Coll,
          stake: toBN(await cdpManager.getCdpStake(BIndex)),
          operation: toBN(0), //CdpOperation.openCDP
        };

        const C_expected = {
          cdpId: CIndex,
          borrower: C,
          oldDebt: toBN(0),
          oldColl: toBN(0),
          debt: C_Debt,
          coll: C_Coll,
          stake: toBN(await cdpManager.getCdpStake(CIndex)),
          operation: toBN(0), //CdpOperation.openCDP
        };

        const checkEmittedValues = (expected, emitted) => {
          assert.isTrue(expected.cdpId === emitted.cdpId);
          assert.isTrue(expected.borrower === emitted.borrower);
          assert.isTrue(expected.oldDebt.eq(emitted.oldDebt));
          assert.isTrue(expected.oldColl.eq(emitted.oldColl));
          assert.isTrue(expected.debt.eq(emitted.debt));
          assert.isTrue(expected.coll.eq(emitted.coll));
          assert.isTrue(expected.stake.eq(emitted.stake));
          assert.isTrue(expected.operation.eq(emitted.operation));
        }

        checkEmittedValues(A_expected, A_emitted)
        checkEmittedValues(B_expected, B_emitted)
        checkEmittedValues(C_expected, C_emitted)
        
        const baseRateBefore = await cdpManager.baseRate()

        // Artificially make baseRate 5%
        await cdpManager.setBaseRate(dec(5, 16))
        await cdpManager.setLastFeeOpTimeToNow()

        assert.isTrue((await cdpManager.baseRate()).gt(baseRateBefore))

        await _signer.sendTransaction({ to: D, value: ethers.utils.parseEther("20000")});
        await _signer.sendTransaction({ to: E, value: ethers.utils.parseEther("20000")});
        const txD = (await openCdp({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })).tx
        const txE = (await openCdp({ extraEBTCAmount: toBN(dec(30, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: E } })).tx

        const DIndex = await sortedCdps.cdpOfOwnerByIndex(D,0)
        const EIndex = await sortedCdps.cdpOfOwnerByIndex(E,0)
        
        const D_Coll = await getCdpEntireColl(DIndex)
        const E_Coll = await getCdpEntireColl(EIndex)
        const D_Debt = await getCdpEntireDebt(DIndex)
        const E_Debt = await getCdpEntireDebt(EIndex)

        const D_emittedDebt = toBN(th.getEventArgByName(txD, "CdpUpdated", "_debt"))
        const D_emittedColl = toBN(th.getEventArgByName(txD, "CdpUpdated", "_coll"))

        const E_emittedDebt = toBN(th.getEventArgByName(txE, "CdpUpdated", "_debt"))
        const E_emittedColl = toBN(th.getEventArgByName(txE, "CdpUpdated", "_coll"))

        // Check emitted debt values are correct
        assert.isTrue(D_Debt.eq(D_emittedDebt))
        assert.isTrue(E_Debt.eq(E_emittedDebt))

        // Check emitted coll values are correct
        assert.isTrue(D_Coll.eq(D_emittedColl))
        assert.isTrue(E_Coll.eq(E_emittedColl))
      })
    }

    it("openCdp(): Opens a cdp with net debt >= minimum net debt", async () => {
      // Add 1 wei to correct for rounding error in helper function
      await _signer.sendTransaction({ to: A, value: ethers.utils.parseEther("10000")});
      await _signer.sendTransaction({ to: C, value: ethers.utils.parseEther("20000")});
      let _colAmt = dec(5000, 18);
      await contracts.collateral.deposit({from: A, value: ethers.utils.parseEther("10000")});
      await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: A});
      await contracts.collateral.deposit({from: C, value: ethers.utils.parseEther("20000")});
      await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: C});
      const txA = await borrowerOperations.openCdp(await getNetBorrowingAmount(MIN_NET_DEBT.add(toBN(1))), th.DUMMY_BYTES32, th.DUMMY_BYTES32, _colAmt, { from: A })
      assert.isTrue(txA.receipt.status)
      const AIndex = await sortedCdps.cdpOfOwnerByIndex(A,0)
      assert.isTrue(await sortedCdps.contains(AIndex))

      let _debtAmt = toBN(dec(47789898,10));
      const txC = await borrowerOperations.openCdp(await getNetBorrowingAmount(MIN_NET_DEBT.add(_debtAmt)), th.DUMMY_BYTES32, th.DUMMY_BYTES32, _colAmt, { from: C })
      assert.isTrue(txC.receipt.status)

      const CIndex = await sortedCdps.cdpOfOwnerByIndex(C,0)
      assert.isTrue(await sortedCdps.contains(CIndex))
    })

    it("openCdp(): reverts if net debt < minimum net debt", async () => {
      let _colAmt = dec(1000, 18);
      await contracts.collateral.deposit({from: A, value: _colAmt});
      await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: A});
      await contracts.collateral.deposit({from: B, value: _colAmt});
      await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: B});
      await contracts.collateral.deposit({from: C, value: _colAmt});
      await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: C});
      const txAPromise = borrowerOperations.openCdp(0, th.DUMMY_BYTES32, th.DUMMY_BYTES32, _colAmt, { from: A })
      await assertRevert(txAPromise, "revert")
      const price = await priceFeed.getPrice()
      const minNetDebtEth = MIN_NET_DEBT
      const minNetDebt = minNetDebtEth.mul(price).div(mv._1e18BN)
      const MIN_DEBT = (await getNetBorrowingAmount(minNetDebt)).sub(toBN(1))
      const txBPromise = borrowerOperations.openCdp(1, th.DUMMY_BYTES32, th.DUMMY_BYTES32, MIN_DEBT, { from: B })
      await assertRevert(txBPromise, "revert")

      const txCPromise = borrowerOperations.openCdp(toBN(dec(1, 16)), th.DUMMY_BYTES32, th.DUMMY_BYTES32, MIN_DEBT, { from: C })
      await assertRevert(txCPromise, "revert")
    })

    it("openCdp(): does not decay a non-zero base rate", async () => {
      await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("10000")});
      await _signer.sendTransaction({ to: A, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: B, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: C, value: ethers.utils.parseEther("50000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openCdp({ extraEBTCAmount: toBN(dec(200, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openCdp({ extraEBTCAmount: toBN(dec(300, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openCdp({ extraEBTCAmount: toBN(dec(400, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })

      // Artificially make baseRate 5%
      await cdpManager.setBaseRate(dec(5, 16))
      await cdpManager.setLastFeeOpTimeToNow()

      // Check baseRate is now non-zero
      const baseRate_1 = await cdpManager.baseRate()
      assert.isTrue(baseRate_1.gt(toBN('0')))

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      // D opens cdp 
      await openCdp({ extraEBTCAmount: toBN(dec(37, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      // Check baseRate has not changed
      const baseRate_2 = await cdpManager.baseRate()
      assert.isTrue(baseRate_2.eq(baseRate_1))

      // 1 hour passes
      th.fastForwardTime(3600, web3.currentProvider)

      // E opens cdp 
      await openCdp({ extraEBTCAmount: toBN(dec(12, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: E } })

      // Base rate should not be decayed by CDP open
      const baseRate_3 = await cdpManager.baseRate()
      assert.isTrue(baseRate_3.eq(baseRate_2))
    })

    it("openCdp(): doesn't change base rate if it is already zero", async () => {
      await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("10000")});
      await _signer.sendTransaction({ to: A, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: B, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: C, value: ethers.utils.parseEther("50000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openCdp({ extraEBTCAmount: toBN(dec(200, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openCdp({ extraEBTCAmount: toBN(dec(300, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openCdp({ extraEBTCAmount: toBN(dec(400, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })

      // Check baseRate is zero
      const baseRate_1 = await cdpManager.baseRate()
      assert.equal(baseRate_1, '0')

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      // D opens cdp 
      await openCdp({ extraEBTCAmount: toBN(dec(37, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      // Check baseRate is still 0
      const baseRate_2 = await cdpManager.baseRate()
      assert.equal(baseRate_2, '0')

      // 1 hour passes
      th.fastForwardTime(3600, web3.currentProvider)

      // E opens cdp 
      await openCdp({ extraEBTCAmount: toBN(dec(12, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: E } })

      const baseRate_3 = await cdpManager.baseRate()
      assert.equal(baseRate_3, '0')
    })

    // Fee doesn't decay on openCDP anymore
    xit("openCdp(): lastFeeOpTime doesn't update if less time than decay interval has passed since the last fee operation", async () => {
      await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("10000")});
      await _signer.sendTransaction({ to: A, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: B, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: C, value: ethers.utils.parseEther("50000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openCdp({ extraEBTCAmount: toBN(dec(200, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openCdp({ extraEBTCAmount: toBN(dec(300, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openCdp({ extraEBTCAmount: toBN(dec(400, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })

      // Artificially make baseRate 5%
      await cdpManager.setBaseRate(dec(5, 16))
      await cdpManager.setLastFeeOpTimeToNow()

      // Check baseRate is now non-zero
      const baseRate_1 = await cdpManager.baseRate()
      assert.isTrue(baseRate_1.gt(toBN('0')))

      const lastFeeOpTime_1 = await cdpManager.lastRedemptionTimestamp()

      // Borrower D triggers a fee
      await openCdp({ extraEBTCAmount: toBN(dec(1, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      const lastFeeOpTime_2 = await cdpManager.lastRedemptionTimestamp()

      // Check that the last fee operation time did not update, as borrower D's debt issuance occured
      // since before minimum interval had passed 
      assert.isTrue(lastFeeOpTime_2.eq(lastFeeOpTime_1))

      // 1 minute passes
      th.fastForwardTime(60, web3.currentProvider)

      // Check that now, at least one minute has passed since lastFeeOpTime_1
      const timeNow = await th.getLatestBlockTimestamp(web3)
      assert.isTrue(toBN(timeNow).sub(lastFeeOpTime_1).gte(3600))

      // Borrower E triggers a fee
      await openCdp({ extraEBTCAmount: toBN(dec(1, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: E } })

      const lastFeeOpTime_3 = await cdpManager.lastRedemptionTimestamp()

      // Check that the last fee operation time DID update, as borrower's debt issuance occured
      // after minimum interval had passed 
      assert.isTrue(lastFeeOpTime_3.gt(lastFeeOpTime_1))
    })

    // Skip as we no longer have fees or the associated reverts related to fee limits
    xit("openCdp(): reverts if max fee > 100%", async () => {
      await contracts.collateral.deposit({from: A, value: dec(1000, 'ether')});
      await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: A});
      await contracts.collateral.deposit({from: B, value: dec(1000, 'ether')});
      await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: B});
      await assertRevert(borrowerOperations.openCdp(dec(2, 18), dec(10000, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, dec(1000, 'ether'), { from: A }), "Max fee percentage must be between 0.5% and 100%")
      await assertRevert(borrowerOperations.openCdp('1000000000000000001', dec(20000, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, dec(1000, 'ether'), { from: B }), "Max fee percentage must be between 0.5% and 100%")
    })
    
    // Skip as we no longer have fees or the associated reverts related to fee limits
    xit("openCdp(): reverts if max fee < 0.5% in Normal mode", async () => {
      await contracts.collateral.deposit({from: A, value: dec(10000, 'ether')});
      await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: A});
      await contracts.collateral.deposit({from: B, value: dec(10000, 'ether')});
      await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: B});
      await assertRevert(borrowerOperations.openCdp(0, dec(195000, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, dec(1200, 'ether'), { from: A }), "Max fee percentage must be between 0.5% and 100%")
      await assertRevert(borrowerOperations.openCdp(1, dec(195000, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, dec(1000, 'ether'), { from: A }), "Max fee percentage must be between 0.5% and 100%")
      await assertRevert(borrowerOperations.openCdp('4999999999999999', dec(195000, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, dec(1200, 'ether'), { from: B }), "Max fee percentage must be between 0.5% and 100%")
    })

    // Skip as we no longer have fees or the associated reverts related to fee limits
    xit("openCdp(): allows max fee < 0.5% in Recovery Mode", async () => {
      await contracts.collateral.deposit({from: A, value: dec(1000, 'ether')});
      await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: A});
      await contracts.collateral.deposit({from: B, value: dec(1000, 'ether')});
      await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: B});
      await contracts.collateral.deposit({from: C, value: dec(1000, 'ether')});
      await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: C});
      await contracts.collateral.deposit({from: D, value: dec(100000, 'ether')});
      await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: D});
      await borrowerOperations.openCdp(dec(1, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, dec(50, 'ether'), { from: A })

      await priceFeed.setPrice(dec(1500, 13))
      assert.isTrue(await th.checkRecoveryMode(contracts))
      await borrowerOperations.openCdp(0, dec(1, 17), th.DUMMY_BYTES32, th.DUMMY_BYTES32, dec(100, 'ether'), { from: B })
      await priceFeed.setPrice(dec(750, 13))
      assert.isTrue(await th.checkRecoveryMode(contracts))

      await borrowerOperations.openCdp(1, dec(1, 17), th.DUMMY_BYTES32, th.DUMMY_BYTES32, dec(50, 'ether'), { from: C })
      await priceFeed.setPrice(dec(500, 13))
      assert.isTrue(await th.checkRecoveryMode(contracts))

      await borrowerOperations.openCdp('4999999999999999', dec(1, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, dec(3100, 'ether'), { from: D })
    })

    // Skip as we no longer have fees or the associated reverts related to fee limits
    xit("openCdp(): reverts if fee exceeds max fee percentage", async () => {
      await _signer.sendTransaction({ to: A, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: B, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: C, value: ethers.utils.parseEther("50000")});
      await openCdp({ extraEBTCAmount: toBN(dec(200, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openCdp({ extraEBTCAmount: toBN(dec(300, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openCdp({ extraEBTCAmount: toBN(dec(400, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })

      const totalSupply = await ebtcToken.totalSupply()

      // Artificially make baseRate 5%
      await cdpManager.setBaseRate(dec(5, 16))
      await cdpManager.setLastFeeOpTimeToNow()

      //       actual fee percentage: 0.005000000186264514
      // user's max fee percentage:  0.0049999999999999999
      let borrowingRate = await cdpManager.getBorrowingRate() // expect max(0.5 + 5%, 5%) rate
      assert.isTrue(borrowingRate.eq(BORROWING_FEE_FLOOR))

      const lessThan5pct = '49999999999999999'
      await contracts.collateral.deposit({from: D, value: dec(100000, 'ether')});
      await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: D});
      await assertRevert(borrowerOperations.openCdp(lessThan5pct, dec(30000, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, dec(1000, 'ether'), { from: D }), "Fee exceeded provided maximum")

      borrowingRate = await cdpManager.getBorrowingRate() // expect 5% rate
      assert.isTrue(borrowingRate.eq(BORROWING_FEE_FLOOR))
      // Attempt with maxFee 1%
      await assertRevert(borrowerOperations.openCdp(dec(1, 16), dec(30000, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, dec(1000, 'ether'), { from: D}), "Fee exceeded provided maximum")

      borrowingRate = await cdpManager.getBorrowingRate() // expect 5% rate
      assert.isTrue(borrowingRate.eq(BORROWING_FEE_FLOOR))
      // Attempt with maxFee 3.754%
      await assertRevert(borrowerOperations.openCdp(dec(3754, 13), dec(30000, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, dec(1000, 'ether'), { from: D }), "Fee exceeded provided maximum")

      borrowingRate = await cdpManager.getBorrowingRate() // expect 5% rate
      assert.isTrue(borrowingRate.eq(BORROWING_FEE_FLOOR))
      // Attempt with maxFee 1e-16%
      await assertRevert(borrowerOperations.openCdp(dec(5, 15), dec(30000, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, dec(1000, 'ether'), { from: D }), "Fee exceeded provided maximum")
    })
    
    // Skip as we no longer have fees or the associated reverts related to fee limits
    xit("openCdp(): succeeds when fee is less than max fee percentage", async () => {
      await _signer.sendTransaction({ to: A, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: B, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: C, value: ethers.utils.parseEther("50000")});
      await openCdp({ extraEBTCAmount: toBN(dec(200, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openCdp({ extraEBTCAmount: toBN(dec(300, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openCdp({ extraEBTCAmount: toBN(dec(400, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })

      // Artificially make baseRate 5%
      await cdpManager.setBaseRate(dec(5, 16))
      await cdpManager.setLastFeeOpTimeToNow()

      let borrowingRate = await cdpManager.getBorrowingRate() // expect min(0.5 + 5%, 5%) rate
      assert.isTrue(borrowingRate.eq(BORROWING_FEE_FLOOR))

      // Attempt with maxFee > 5%
      const moreThan5pct = '50000000000000001'
      await contracts.collateral.deposit({from: D, value: dec(100000, 'ether')});
      await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: D});
      const tx1 = await borrowerOperations.openCdp(dec(100, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, dec(2000, 'ether'), { from: D })
      assert.isTrue(tx1.receipt.status)

      borrowingRate = await cdpManager.getBorrowingRate() // expect 5% rate
      assert.isTrue(borrowingRate.eq(BORROWING_FEE_FLOOR))

      // Attempt with maxFee = 5%
      await contracts.collateral.deposit({from: H, value: dec(100000, 'ether')});
      await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: H});
      const tx2 = await borrowerOperations.openCdp(dec(5, 16), dec(100, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, dec(2000, 'ether'), { from: H })
      assert.isTrue(tx2.receipt.status)

      borrowingRate = await cdpManager.getBorrowingRate() // expect 5% rate
      assert.isTrue(borrowingRate.eq(BORROWING_FEE_FLOOR))

      // Attempt with maxFee 10%
      await contracts.collateral.deposit({from: E, value: dec(100000, 'ether')});
      await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: E});
      const tx3 = await borrowerOperations.openCdp(dec(1, 17), dec(100, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, dec(2000, 'ether'), { from: E })
      assert.isTrue(tx3.receipt.status)

      borrowingRate = await cdpManager.getBorrowingRate() // expect 5% rate
      assert.isTrue(borrowingRate.eq(BORROWING_FEE_FLOOR))

      // Attempt with maxFee 37.659%
      await contracts.collateral.deposit({from: F, value: dec(100000, 'ether')});
      await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: F});
      const tx4 = await borrowerOperations.openCdp(dec(37659, 13), dec(100, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, dec(2000, 'ether'), { from: F })
      assert.isTrue(tx4.receipt.status)

      // Attempt with maxFee 100%
      await contracts.collateral.deposit({from: G, value: dec(100000, 'ether')});
      await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: G});
      const tx5 = await borrowerOperations.openCdp(dec(1, 18), dec(100, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, dec(2000, 'ether'), { from: G })
      assert.isTrue(tx5.receipt.status)
    })

    // openCDP doesn't affect baseRate anymore
    xit("openCdp(): borrower can't grief the baseRate and stop it decaying by issuing debt at higher frequency than the decay granularity", async () => {
      await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("5000")});
      await _signer.sendTransaction({ to: A, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: B, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: C, value: ethers.utils.parseEther("50000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openCdp({ extraEBTCAmount: toBN(dec(200, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openCdp({ extraEBTCAmount: toBN(dec(300, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openCdp({ extraEBTCAmount: toBN(dec(400, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })

      // Artificially make baseRate 5%
      await cdpManager.setBaseRate(dec(5, 16))
      await cdpManager.setLastFeeOpTimeToNow()

      // Check baseRate is non-zero
      const baseRate_1 = await cdpManager.baseRate()
      assert.isTrue(baseRate_1.gt(toBN('0')))

      // 59 minutes pass
      th.fastForwardTime(3540, web3.currentProvider)

      // Assume Borrower also owns accounts D and E
      // Borrower triggers a fee, before decay interval has passed
      await openCdp({ extraEBTCAmount: toBN(dec(1, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      // 1 minute pass
      th.fastForwardTime(3540, web3.currentProvider)

      // Borrower triggers another fee
      await openCdp({ extraEBTCAmount: toBN(dec(1, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: E } })

      // Check base rate has decreased even though Borrower tried to stop it decaying
      const baseRate_2 = await cdpManager.baseRate()
      assert.isTrue(baseRate_2.lt(baseRate_1))
    })

    //skip: There is never a non-zero base rate for borrowing
    xit("openCdp(): borrowing at non-zero base rate sends EBTC fee to LQTY staking contract", async () => {
      // time fast-forwards 1 year, and multisig stakes 1 LQTY
      await th.fastForwardTime(timeValues.SECONDS_IN_ONE_YEAR, web3.currentProvider)
      await lqtyToken.approve(feeRecipient.address, dec(1, 18), { from: multisig })
      await feeRecipient.stake(dec(1, 18), { from: multisig })

      // Check LQTY EBTC balance before == 0
      const lqtyStaking_EBTCBalance_Before = await ebtcToken.balanceOf(feeRecipient.address)
      assert.equal(lqtyStaking_EBTCBalance_Before, '0')

      await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("5000")});
      await _signer.sendTransaction({ to: A, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: B, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: C, value: ethers.utils.parseEther("50000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openCdp({ extraEBTCAmount: toBN(dec(200, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openCdp({ extraEBTCAmount: toBN(dec(300, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openCdp({ extraEBTCAmount: toBN(dec(400, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })

      // Artificially make baseRate 5%
      await cdpManager.setBaseRate(dec(5, 16))
      await cdpManager.setLastFeeOpTimeToNow()

      // Check baseRate is now non-zero
      const baseRate_1 = await cdpManager.baseRate()
      assert.isTrue(baseRate_1.gt(toBN('0')))

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      // D opens cdp 
      await _signer.sendTransaction({ to: D, value: ethers.utils.parseEther("50000")});
      await openCdp({ extraEBTCAmount: toBN(dec(400, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      // Check LQTY EBTC balance after has increased
      const lqtyStaking_EBTCBalance_After = await ebtcToken.balanceOf(feeRecipient.address)
      assert.isTrue(lqtyStaking_EBTCBalance_After.gt(lqtyStaking_EBTCBalance_Before))
    })
    
    // skip: There is never a non-zero base rate for borrowing
    xit("openCdp(): Borrowing at non-zero base rate increases the LQTY staking contract EBTC fees-per-unit-staked", async () => {
      // time fast-forwards 1 year, and multisig stakes 1 LQTY
      await th.fastForwardTime(timeValues.SECONDS_IN_ONE_YEAR, web3.currentProvider)
      await lqtyToken.approve(feeRecipient.address, dec(1, 18), { from: multisig })
      await feeRecipient.stake(dec(1, 18), { from: multisig })

      // Check LQTY contract EBTC fees-per-unit-staked is zero
      const F_EBTC_Before = await feeRecipient.F_EBTC()
      assert.equal(F_EBTC_Before, '0')

      await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("5000")});
      await _signer.sendTransaction({ to: A, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: B, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: C, value: ethers.utils.parseEther("50000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openCdp({ extraEBTCAmount: toBN(dec(200, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openCdp({ extraEBTCAmount: toBN(dec(300, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openCdp({ extraEBTCAmount: toBN(dec(400, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })

      // Artificially make baseRate 5%
      await cdpManager.setBaseRate(dec(5, 16))
      await cdpManager.setLastFeeOpTimeToNow()

      // Check baseRate is now non-zero
      const baseRate_1 = await cdpManager.baseRate()
      assert.isTrue(baseRate_1.gt(toBN('0')))

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      // D opens cdp 
      await openCdp({ extraEBTCAmount: toBN(dec(37, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      // Check LQTY contract EBTC fees-per-unit-staked has increased
      const F_EBTC_After = await feeRecipient.F_EBTC()
      assert.isTrue(F_EBTC_After.gt(F_EBTC_Before))
    })
  
    // skip: There is never a non-zero base rate for borrowing
    xit("openCdp(): Borrowing at non-zero base rate sends requested amount to the user", async () => {
      // time fast-forwards 1 year, and multisig stakes 1 LQTY
      await th.fastForwardTime(timeValues.SECONDS_IN_ONE_YEAR, web3.currentProvider)
      await lqtyToken.approve(feeRecipient.address, dec(1, 18), { from: multisig })
      await feeRecipient.stake(dec(1, 18), { from: multisig })

      // Check LQTY Staking contract balance before == 0
      const lqtyStaking_EBTCBalance_Before = await ebtcToken.balanceOf(feeRecipient.address)
      assert.equal(lqtyStaking_EBTCBalance_Before, '0')

      await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("5000")});
      await _signer.sendTransaction({ to: A, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: B, value: ethers.utils.parseEther("20000")});
      await _signer.sendTransaction({ to: C, value: ethers.utils.parseEther("50000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openCdp({ extraEBTCAmount: toBN(dec(200, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openCdp({ extraEBTCAmount: toBN(dec(300, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openCdp({ extraEBTCAmount: toBN(dec(400, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })

      // Artificially make baseRate 5%
      await cdpManager.setBaseRate(dec(5, 16))
      await cdpManager.setLastFeeOpTimeToNow()

      // Check baseRate is non-zero
      const baseRate_1 = await cdpManager.baseRate()
      assert.isTrue(baseRate_1.gt(toBN('0')))

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      // D opens cdp 
      const EBTCRequest_D = toBN(dec(20, 18))
      await borrowerOperations.openCdp(EBTCRequest_D, th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: D, value: dec(500, 'ether') })

      // Check LQTY staking EBTC balance has increased
      const lqtyStaking_EBTCBalance_After = await ebtcToken.balanceOf(feeRecipient.address)
      assert.isTrue(lqtyStaking_EBTCBalance_After.gt(lqtyStaking_EBTCBalance_Before))

      // Check D's EBTC balance now equals their requested EBTC
      const EBTCBalance_D = await ebtcToken.balanceOf(D)
      assert.isTrue(EBTCRequest_D.eq(EBTCBalance_D))
    })

    // skip: No staking for variables to change 
    xit("openCdp(): Borrowing at zero base rate changes the LQTY staking contract EBTC fees-per-unit-staked", async () => {
      await _signer.sendTransaction({ to: A, value: ethers.utils.parseEther("5000")});
      await _signer.sendTransaction({ to: B, value: ethers.utils.parseEther("10000")});
      await _signer.sendTransaction({ to: C, value: ethers.utils.parseEther("10000")});
      await openCdp({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openCdp({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openCdp({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })

      // Check baseRate is zero
      const baseRate_1 = await cdpManager.baseRate()
      assert.equal(baseRate_1, '0')

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      // Check EBTC reward per LQTY staked == 0
      const F_EBTC_Before = await feeRecipient.F_EBTC()
      assert.equal(F_EBTC_Before, '0')

      // A stakes LQTY
      await lqtyToken.unprotectedMint(A, dec(100, 18))
      await feeRecipient.stake(dec(100, 18), { from: A })

      // D opens cdp 
      await openCdp({ extraEBTCAmount: toBN(dec(37, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      // Check EBTC reward per LQTY staked > 0
      const F_EBTC_After = await feeRecipient.F_EBTC()
      assert.isTrue(F_EBTC_After.eq(toBN('0')))
    })

    it("openCdp(): Borrowing at zero base rate allocates tokens as expected", async () => {
      await _signer.sendTransaction({ to: A, value: ethers.utils.parseEther("5000")});
      await _signer.sendTransaction({ to: B, value: ethers.utils.parseEther("10000")});
      await openCdp({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openCdp({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })

      await contracts.collateral.deposit({from: C, value: dec(100000, 'ether')});
      await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: C});
      const EBTCRequest = toBN(dec(2, 18))
      const txC = await borrowerOperations.openCdp(EBTCRequest, ZERO_ADDRESS, ZERO_ADDRESS, dec(100, 'ether'), { from: C })

      // We don't have a fee, so expect user tokens to equal the debt requested minus gas comp pool
      const userCDebt = await ebtcToken.balanceOf(C)

      // TODO: should this factor in gas comp?
      assert.isTrue(userCDebt.eq(EBTCRequest))

    })

    it("openCdp(): reverts when system is in Recovery Mode and ICR < CCR", async () => {
      await openCdp({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: whale } })
      await openCdp({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      assert.isFalse(await th.checkRecoveryMode(contracts))

      // price drops, and Recovery Mode kicks in
      await priceFeed.setPrice(dec(3000, 13))

      assert.isTrue(await th.checkRecoveryMode(contracts))

      // Bob tries to open a cdp with ICR below CCR during Recovery Mode
      try {
        const txBob = await openCdp({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(124, 16)), extraParams: { from: alice } })
        assert.isFalse(txBob.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    it("openCdp(): reverts when cdp ICR < MCR", async () => {
      await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("5000")});
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("10000")});
      await openCdp({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: whale } })
      await openCdp({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })

      assert.isFalse(await th.checkRecoveryMode(contracts))

      // Bob attempts to open a 109% ICR cdp in Normal Mode
      try {
        const txBob = (await openCdp({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(109, 16)), extraParams: { from: bob } })).tx
        assert.isFalse(txBob.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }

      // price drops, and Recovery Mode kicks in
      await priceFeed.setPrice(dec(3000, 13))

      assert.isTrue(await th.checkRecoveryMode(contracts))

      // Bob attempts to open a 109% ICR cdp in Recovery Mode
      try {
        const txBob = await openCdp({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(109, 16)), extraParams: { from: bob } })
        assert.isFalse(txBob.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    it("openCdp(): reverts when opening the cdp would cause the TCR of the system to fall below the CCR", async () => {
      await priceFeed.setPrice(dec(3800, 13))
      await openCdp({ICR: toBN(dec(126, 16)), extraParams: { from: alice } })

      const TCR = await th.getCachedTCR(contracts)

      // Bob attempts to open a cdp with ICR to make System TCR would fall below CCR
      try {
        const txBob = await openCdp({ extraEBTCAmount: toBN(dec(1, 17)), ICR: toBN(dec(124, 16)), extraParams: { from: bob } })
        assert.isFalse(txBob.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    it("openCdp(): account can open multiple cdps", async () => {
      await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("5000")});
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("10000")});
      await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("5000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })

      await openCdp({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(15, 17)), extraParams: { from: alice } })
      await openCdp({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(15, 17)), extraParams: { from: bob } })

      await openCdp({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(3, 18)), extraParams: { from: bob } })
      await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
    })

    xit("[TODO] openCdp(): multiple cdps opened by same account have different indicies", async () => {
    })

    it("openCdp(): Can open a cdp with ICR >= CCR when system is in Recovery Mode", async () => {
      // --- SETUP ---
      //  Alice and Bob add coll and withdraw such  that the TCR is ~150%
      await openCdp({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(151, 16)), extraParams: { from: alice } })
      await openCdp({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(151, 16)), extraParams: { from: bob } })

      const TCR = (await th.getCachedTCR(contracts)).toString()
      th.assertIsApproximatelyEqual(toBN(TCR), dec(150, 16), 10000000000000000)

      // price drops to 1ETH:100EBTC, reducing TCR below 150%
      await priceFeed.setPrice(dec(3000, 13))
      const price = await priceFeed.getPrice()
      
      assert.isTrue(await th.checkRecoveryMode(contracts))

      // Carol opens at 150% ICR in Recovery Mode
      await _signer.sendTransaction({ to: carol, value: ethers.utils.parseEther("5000")});
      const txCarol = (await openCdp({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(15, 17)), extraParams: { from: carol } })).tx
      assert.isTrue(txCarol.receipt.status)
      const carolIndex = await sortedCdps.cdpOfOwnerByIndex(carol,0)
      assert.isTrue(await sortedCdps.contains(carolIndex))

      const carol_CdpStatus = await cdpManager.getCdpStatus(carolIndex)
      assert.equal(carol_CdpStatus, 1)

      const carolICR = await cdpManager.getCachedICR(carolIndex, price)
      assert.isTrue(carolICR.gte(toBN(dec(150, 16))))
    })

    it("openCdp(): Reverts opening a cdp with min debt when system is in Recovery Mode", async () => {
      // --- SETUP ---
      //  Alice and Bob add coll and withdraw such  that the TCR is ~150%
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("5000")});
      await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("5000")});
      await contracts.collateral.deposit({from: carol, value: dec(5000, 'ether')});
      await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: carol});
      await openCdp({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(151, 16)), extraParams: { from: alice } })
      await openCdp({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(151, 16)), extraParams: { from: bob } })

      const TCR = (await th.getCachedTCR(contracts)).toString()
      th.assertIsApproximatelyEqual(toBN(TCR), dec(150, 16), 10000000000000000)

      // price drops to 1ETH:0.003, reducing TCR below 150%
      await priceFeed.setPrice(dec(3000, 13))

      assert.isTrue(await th.checkRecoveryMode(contracts))

      await assertRevert(borrowerOperations.openCdp(await getNetBorrowingAmount(MIN_NET_DEBT), th.DUMMY_BYTES32, th.DUMMY_BYTES32, dec(1, 'ether'), { from: carol }))
    })

    it("openCdp(): creates a new Cdp and assigns the correct collateral and debt amount", async () => {

      // We can't know the cdpID beforehand unless we know the block at which the operation will be mined and ensure no more cdps are minted in the intermediate term
      const aliceIndexNonExistant = th.RANDOM_INDEX
      const debt_Before = await getCdpEntireDebt(aliceIndexNonExistant)
      const coll_Before = await getCdpEntireColl(aliceIndexNonExistant)
      const status_Before = await cdpManager.getCdpStatus(aliceIndexNonExistant)

      // check coll and debt before
      assert.equal(debt_Before, 0)
      assert.equal(coll_Before, 0)

      // check non-existent status
      assert.equal(status_Before, 0)

      const EBTCRequest = MIN_NET_DEBT
      await contracts.collateral.deposit({from: alice, value: dec(5000, 'ether')});
      await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: alice});
      await borrowerOperations.openCdp(MIN_NET_DEBT, th.DUMMY_BYTES32, th.DUMMY_BYTES32, dec(100, 'ether'), { from: alice })
      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)

      // Get the expected debt based on the EBTC request (adding fee and liq. reserve on top)
      const expectedDebt = EBTCRequest
      const debt_After = await getCdpEntireDebt(aliceIndex)
      const coll_After = await getCdpEntireColl(aliceIndex)
      const status_After = await cdpManager.getCdpStatus(aliceIndex)
      // check coll and debt after
      assert.isTrue(coll_After.gt('0'))
      assert.isTrue(debt_After.gt('0'))

      assert.isTrue(debt_After.eq(expectedDebt))

      // check active status
      assert.equal(status_After, 1)
    })

    it("openCdp(): adds Cdp ID to CdpID array", async () => {
      const CdpIdsCount_Before = (await cdpManager.getActiveCdpsCount()).toString();
      assert.equal(CdpIdsCount_Before, '0')

      await openCdp({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(151, 16)), extraParams: { from: alice } })

      const CdpIdsCount_After = (await cdpManager.getActiveCdpsCount()).toString();
      assert.equal(CdpIdsCount_After, '1')
    })

    xit("[TODO] openCdp(): adds Cdp owner to CdpOwners array [Or: if we're not doing this, how do we enumerate all active cdp owners?]", async () => {
    })

    it("openCdp(): creates a stake and adds it to total stakes", async () => {
      // TODO: Call this function to see where alice's next cdp would get deployed if it did. Then, check this index.
      // Can a cdp ever be opened at the same index twice?
      const aliceStakeBefore = await getCdpStake(alice)
      const totalStakesBefore = await cdpManager.totalStakes()

      assert.equal(aliceStakeBefore, '0')
      assert.equal(totalStakesBefore, '0')

      await openCdp({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)

      const aliceCollAfter = await getCdpEntireColl(aliceIndex)
      const aliceStakeAfter = await getCdpStake(aliceIndex)

      assert.isTrue(aliceCollAfter.gt(toBN('0')))
      assert.isTrue(aliceStakeAfter.eq(aliceCollAfter))

      const totalStakesAfter = await cdpManager.totalStakes()

      assert.isTrue(totalStakesAfter.eq(aliceStakeAfter))
    })

    it("openCdp(): inserts Cdp to Sorted Cdps list", async () => {
      // Check before
      const aliceCdpInList_Before = await sortedCdps.contains(alice)
      const listIsEmpty_Before = await sortedCdps.isEmpty()
      assert.equal(aliceCdpInList_Before, false)
      assert.equal(listIsEmpty_Before, true)

      await openCdp({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)

      // check after
      const aliceCdpInList_After = await sortedCdps.contains(aliceIndex)
      const emptyCdpNotInList_After = await sortedCdps.contains(alice)
      const listIsEmpty_After = await sortedCdps.isEmpty()
      assert.equal(aliceCdpInList_After, true)
      assert.equal(emptyCdpNotInList_After, false)
      assert.equal(listIsEmpty_After, false)
    })

    it("openCdp(): Increases the activePool ETH and raw ether balance by correct amount", async () => {
      const activePool_ETH_Before = await activePool.getSystemCollShares()
      const activePool_RawEther_Before = await web3.eth.getBalance(activePool.address)
      assert.equal(activePool_ETH_Before, 0)
      assert.equal(activePool_RawEther_Before, 0)

      await openCdp({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)
      const aliceCollAfter = await getCdpEntireColl(aliceIndex)

      const activePool_ETH_After = await activePool.getSystemCollShares()
      assert.isTrue(activePool_ETH_After.eq(aliceCollAfter))
    })

    it("openCdp(): records up-to-date initial snapshots of L_STETHColl and systemDebtRedistributionIndex", async () => {
      // --- SETUP ---
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("5000")});
      await _signer.sendTransaction({ to: carol, value: ethers.utils.parseEther("5000")});
      await openCdp({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openCdp({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: carol } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)
      const carolIndex = await sortedCdps.cdpOfOwnerByIndex(carol,0)
      await _signer.sendTransaction({ to: owner, value: ethers.utils.parseEther("5000")});
      await openCdp({ extraEBTCAmount: toBN(dec(200, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: owner } });

      // --- TEST ---

      // price drops to 1ETH:100EBTC, reducing Carol's ICR below MCR
      let _newPrice = dec(3000, 13);
      await priceFeed.setPrice(_newPrice)

      // close Carol's Cdp, liquidating her 1 ether and 180EBTC.
      const liquidationTx = await cdpManager.liquidate(carolIndex, { from: owner });
      const [liquidatedDebt, liquidatedColl, gasComp] = th.getEmittedLiquidationValues(liquidationTx)

      /* with total stakes = 10 ether, after liquidation, L_STETHColl should equal 1/10 ether per-ether-staked,
       and L_EBTC should equal 18 EBTC per-ether-staked. */

      const L_EBTC = await cdpManager.systemDebtRedistributionIndex()

      assert.isTrue(L_EBTC.gt(toBN('0')))

      // Bob opens cdp
      await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("5000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: bob } })
      const bobIndex = await sortedCdps.cdpOfOwnerByIndex(bob,0)

      // Check Bob's snapshots of L_STETHColl and L_EBTC equal the respective current values
      const bob_EBTCDebtRewardSnapshot = await cdpManager.cdpDebtRedistributionIndex(bobIndex)

      assert.isAtMost(th.getDifference(bob_EBTCDebtRewardSnapshot, L_EBTC), 1000)
    })

    it("openCdp(): allows a user to open a Cdp, then close it, then re-open it", async () => {
      // Open Cdps
      await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("4000")});
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("4000")});
      await _signer.sendTransaction({ to: carol, value: ethers.utils.parseEther("4000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: whale } })
      await openCdp({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openCdp({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: carol } })

      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)

      // Check Cdp is active
      const alice_Cdp_1 = await cdpManager.Cdps(aliceIndex)
      const status_1 = alice_Cdp_1[4]
      assert.equal(status_1, 1)
      assert.isTrue(await sortedCdps.contains(aliceIndex))

      // to compensate borrowing fees
      await ebtcToken.transfer(alice, dec(100, 18), { from: whale })

      // Repay and close Cdp
      await borrowerOperations.closeCdp(aliceIndex, { from: alice })

      // Check Cdp is closed
      const alice_Cdp_2 = await cdpManager.Cdps(aliceIndex)
      const status_2 = alice_Cdp_2[4]
      assert.equal(status_2, 2)
      assert.isFalse(await sortedCdps.contains(aliceIndex))

      // Re-open Cdp
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("4000")});
      await openCdp({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })

      const aliceIndex2 = await sortedCdps.cdpOfOwnerByIndex(alice,0)

      assert.notEqual(aliceIndex, aliceIndex2)

      // Check Cdp is re-opened
      const alice_Cdp_3 = await cdpManager.Cdps(aliceIndex2)
      const status_3 = alice_Cdp_3[4]
      assert.equal(status_3, 1)
      assert.isTrue(await sortedCdps.contains(aliceIndex2))
      assert.isFalse(await sortedCdps.contains(aliceIndex))
    })

    it("openCdp(): increases the Cdp's EBTC debt by the correct amount", async () => {
      // check before
      const alice_Cdp_Before = await cdpManager.Cdps(alice)
      const debt_Before = alice_Cdp_Before[0]
      assert.equal(debt_Before, 0)
      await contracts.collateral.deposit({from: alice, value: dec(5000, 'ether')});
      await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: alice});
      await borrowerOperations.openCdp(await getOpenCdpEBTCAmount(dec(1, 18)), alice, alice, dec(100, 'ether'), { from: alice })
      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)

      // check after
      const alice_Cdp_After = await cdpManager.Cdps(aliceIndex)
      const debt_After = alice_Cdp_After[0]
      th.assertIsApproximatelyEqual(debt_After, dec(1, 18), 10000)
    })

    it("openCdp(): increases EBTC debt in ActivePool by the debt of the cdp", async () => {
      const activePool_EBTCDebt_Before = await activePool.getSystemDebt()
      assert.equal(activePool_EBTCDebt_Before, 0)

      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("21000")});
      await openCdp({ extraEBTCAmount: toBN(dec(100, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      const aliceIndex = await sortedCdps.cdpOfOwnerByIndex(alice,0)
      
      const aliceDebt = await getCdpEntireDebt(aliceIndex)
      assert.isTrue(aliceDebt.gt(toBN('0')))

      const activePool_EBTCDebt_After = await activePool.getSystemDebt()
      assert.isTrue(activePool_EBTCDebt_After.eq(aliceDebt))
    })

    it("openCdp(): increases user EBTCToken balance by correct amount", async () => {
      // check before
      const alice_EBTCTokenBalance_Before = await ebtcToken.balanceOf(alice)
      assert.equal(alice_EBTCTokenBalance_Before, 0)
      await contracts.collateral.deposit({from: alice, value: dec(5000, 'ether')});
      await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: alice});
      await borrowerOperations.openCdp(dec(1, 18), alice, alice, dec(100, 'ether'), { from: alice })

      // check after
      const alice_EBTCTokenBalance_After = await ebtcToken.balanceOf(alice)
      assert.equal(alice_EBTCTokenBalance_After, dec(1, 18))
    })

    //  --- getNewICRFromCdpChange - (external wrapper in Tester contract calls internal function) ---

    describe("getNewICRFromCdpChange() returns the correct ICR", async () => {


      // 0, 0
      it("collChange = 0, debtChange = 0", async () => {
        price = await priceFeed.getPrice()
        const initialColl = dec(1000, 'ether')
        const initialDebt = dec(100, 18)
        const collChange = 0
        const debtChange = 0

        const newICR = (await borrowerOperations.getNewICRFromCdpChange(initialColl, initialDebt, collChange, true, debtChange, true, price)).toString()
        assert.equal(newICR, '742800000000000000')
      })

      // 0, +ve
      it("collChange = 0, debtChange is positive", async () => {
        price = await priceFeed.getPrice()
        const initialColl = dec(30, 'ether')
        const initialDebt = dec(1, 18)
        const collChange = 0
        const debtChange = dec(1, 17)

        const newICR = (await borrowerOperations.getNewICRFromCdpChange(initialColl, initialDebt, collChange, true, debtChange, true, price)).toString()
        assert.isAtMost(th.getDifference(newICR, '2025818181818181818'), 10)
      })

      // 0, -ve
      it("collChange = 0, debtChange is negative", async () => {
        price = await priceFeed.getPrice()
        const initialColl = dec(30, 'ether')
        const initialDebt = dec(1, 18)
        const collChange = 0
        const debtChange = dec(1, 17)
        const newICR = (await borrowerOperations.getNewICRFromCdpChange(initialColl, initialDebt, collChange, true, debtChange, false, price)).toString()
        assert.equal(newICR, '2476000000000000000')
      })

      // +ve, 0
      it("collChange is positive, debtChange is 0", async () => {
        price = await priceFeed.getPrice()
        const initialColl = dec(100, 'ether')
        const initialDebt = dec(1, 18)
        const collChange = dec(1, 'ether')
        const debtChange = 0

        const newICR = (await borrowerOperations.getNewICRFromCdpChange(initialColl, initialDebt, collChange, true, debtChange, true, price)).toString()
        assert.equal(newICR, '7502280000000000000')
      })

      // -ve, 0
      it("collChange is negative, debtChange is 0", async () => {
        price = await priceFeed.getPrice()
        const initialColl = dec(100, 'ether')
        const initialDebt = dec(1, 18)
        const collChange = dec(5, 17)
        const debtChange = 0

        const newICR = (await borrowerOperations.getNewICRFromCdpChange(initialColl, initialDebt, collChange, false, debtChange, true, price)).toString()
        assert.equal(newICR, '7390860000000000000')
      })

      // -ve, -ve
      it("collChange is negative, debtChange is negative", async () => {
        price = await priceFeed.getPrice()
        const initialColl = dec(100, 'ether')
        const initialDebt = dec(1, 18)
        const collChange = dec(5, 18)
        const debtChange = dec(1, 17)

        const newICR = (await borrowerOperations.getNewICRFromCdpChange(initialColl, initialDebt, collChange, false, debtChange, false, price)).toString()
        assert.equal(newICR, '7840666666666666666')
      })

      // +ve, +ve 
      it("collChange is positive, debtChange is positive", async () => {
        price = await priceFeed.getPrice()
        const initialColl = dec(100, 'ether')
        const initialDebt = dec(1, 18)
        const collChange = dec(1, 'ether')
        const debtChange = dec(1, 18)

        const newICR = (await borrowerOperations.getNewICRFromCdpChange(initialColl, initialDebt, collChange, true, debtChange, true, price)).toString()
        assert.equal(newICR, '3751140000000000000')
      })

      // +ve, -ve
      it("collChange is positive, debtChange is negative", async () => {
        price = await priceFeed.getPrice()
        const initialColl = dec(100, 'ether')
        const initialDebt = dec(1, 18)
        const collChange = dec(1, 'ether')
        const debtChange = dec(1, 17)

        const newICR = (await borrowerOperations.getNewICRFromCdpChange(initialColl, initialDebt, collChange, true, debtChange, false, price)).toString()
        assert.equal(newICR, '8335866666666666666')
      })

      // -ve, +ve
      it("collChange is negative, debtChange is positive", async () => {
        price = await priceFeed.getPrice()
        const initialColl = dec(100, 'ether')
        const initialDebt = dec(1, 18)
        const collChange = dec(5, 17)
        const debtChange = dec(1, 17)

        const newICR = (await borrowerOperations.getNewICRFromCdpChange(initialColl, initialDebt, collChange, false, debtChange, true, price)).toString()
        assert.equal(newICR, '6718963636363636363')
      })
    })

    //  --- getNewTCRFromCdpChange  - (external wrapper in Tester contract calls internal function) ---

    describe("getNewTCRFromCdpChange() returns the correct TCR", async () => {

      // 0, 0
      it("collChange = 0, debtChange = 0", async () => {
        // --- SETUP --- Create a Liquity instance with an Active Pool and pending rewards (Default Pool)
        const cdpColl = toBN(dec(1000, 'ether'))
        const cdpTotalDebt = toBN(dec(10, 18))
        const cdpEBTCAmount = await getOpenCdpEBTCAmount(cdpTotalDebt)
        await contracts.collateral.deposit({from: alice, value: dec(5000, 'ether')});
        await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: alice});
        await contracts.collateral.deposit({from: bob, value: dec(5000, 'ether')});
        await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: bob});
        await borrowerOperations.openCdp(cdpEBTCAmount, th.DUMMY_BYTES32, th.DUMMY_BYTES32, cdpColl, { from: alice })
        await borrowerOperations.openCdp(cdpEBTCAmount, th.DUMMY_BYTES32, th.DUMMY_BYTES32, cdpColl, { from: bob })

        let _newPrice = dec(1000, 13);
        await priceFeed.setPrice(_newPrice)

        let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
        let _aliceDebtAndColl = await cdpManager.getSyncedDebtAndCollShares(_aliceCdpId);
        let _aliceDebt = _aliceDebtAndColl[0];
        let _aliceColl = _aliceDebtAndColl[1];
        let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
        let _bobDebtAndColl = await cdpManager.getSyncedDebtAndCollShares(_bobCdpId);
        let _bobDebt = _bobDebtAndColl[0];
        let _bobColl = _bobDebtAndColl[1];
		
        await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), { from: alice});
        await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), { from: bob});

        const liquidationTx = await cdpManager.liquidate(_bobCdpId, {from: owner})
        assert.isFalse(await sortedCdps.contains(_bobCdpId))

        const [liquidatedDebt, liquidatedColl, gasComp] = th.getEmittedLiquidationValues(liquidationTx)

        await priceFeed.setPrice(dec(7428, 13))
        const price = await priceFeed.getPrice()

        // --- TEST ---
        const collChange = 0
        const debtChange = 0
        const newTCR = await borrowerOperations.getNewTCRFromCdpChange(collChange, true, debtChange, true, price)

        const expectedTCR = _aliceColl.mul(price).div(_aliceDebt.add(_bobDebt.sub(_bobColl.mul(toBN(_newPrice)).div(LICR))))

        th.assertIsApproximatelyEqual(newTCR.toString(), expectedTCR.toString())
      })

      // 0, +ve
      it("collChange = 0, debtChange is positive", async () => {
        // --- SETUP --- Create a Liquity instance with an Active Pool and pending rewards (Default Pool)
        const cdpColl = toBN(dec(1000, 'ether'))
        const cdpTotalDebt = toBN(dec(10, 18))
        const cdpEBTCAmount = await getOpenCdpEBTCAmount(cdpTotalDebt)
        await contracts.collateral.deposit({from: alice, value: dec(5000, 'ether')});
        await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: alice});
        await contracts.collateral.deposit({from: bob, value: dec(5000, 'ether')});
        await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: bob});

        await borrowerOperations.openCdp(cdpEBTCAmount, th.DUMMY_BYTES32, th.DUMMY_BYTES32, cdpColl, { from: alice })
        await borrowerOperations.openCdp(cdpEBTCAmount, th.DUMMY_BYTES32, th.DUMMY_BYTES32, cdpColl, { from: bob })

        let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
        let _aliceDebtAndColl = await cdpManager.getSyncedDebtAndCollShares(_aliceCdpId);
        let _aliceDebt = _aliceDebtAndColl[0];
        let _aliceColl = _aliceDebtAndColl[1];
        let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
        let _bobDebtAndColl = await cdpManager.getSyncedDebtAndCollShares(_bobCdpId);
        let _bobDebt = _bobDebtAndColl[0];
        let _bobColl = _bobDebtAndColl[1];
		
        await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), { from: alice});
        await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), { from: bob});

        let _newPrice = dec(150, 13);
        await priceFeed.setPrice(_newPrice)

        const liquidationTx = await cdpManager.liquidate(_bobCdpId, {from: owner})
        assert.isFalse(await sortedCdps.contains(_bobCdpId))

        th.getEmittedLiquidationValues(liquidationTx)

        await priceFeed.setPrice(dec(7428, 13))
        const price = await priceFeed.getPrice()

        // --- TEST ---
        const collChange = 0
        const debtChange = dec(2, 18)
        const newTCR = (await borrowerOperations.getNewTCRFromCdpChange(collChange, true, debtChange, true, price))

        const expectedTCR = _aliceColl.mul(price).div(_aliceDebt.add(toBN(debtChange)).add(_bobDebt.sub(_bobColl.mul(toBN(_newPrice)).div(LICR))))

        th.assertIsApproximatelyEqual(newTCR, expectedTCR, 1)
      })

      // 0, -ve
      it("collChange = 0, debtChange is negative", async () => {
        // --- SETUP --- Create a Liquity instance with an Active Pool and pending rewards (Default Pool)
        const cdpColl = toBN(dec(1000, 'ether'))
        const cdpTotalDebt = toBN(dec(10, 18))
        const cdpEBTCAmount = await getOpenCdpEBTCAmount(cdpTotalDebt)
        await contracts.collateral.deposit({from: alice, value: dec(5000, 'ether')});
        await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: alice});
        await contracts.collateral.deposit({from: bob, value: dec(5000, 'ether')});
        await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: bob});
        await borrowerOperations.openCdp(cdpEBTCAmount, th.DUMMY_BYTES32, th.DUMMY_BYTES32, cdpColl, { from: alice })
        await borrowerOperations.openCdp(cdpEBTCAmount, th.DUMMY_BYTES32, th.DUMMY_BYTES32, cdpColl, { from: bob })

        let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
        let _aliceDebtAndColl = await cdpManager.getSyncedDebtAndCollShares(_aliceCdpId);
        let _aliceDebt = _aliceDebtAndColl[0];
        let _aliceColl = _aliceDebtAndColl[1];
        let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
        let _bobDebtAndColl = await cdpManager.getSyncedDebtAndCollShares(_bobCdpId);
        let _bobDebt = _bobDebtAndColl[0];
        let _bobColl = _bobDebtAndColl[1];
		
        await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), { from: alice});
        await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), { from: bob});

        let _newPrice = dec(1000, 13);
        await priceFeed.setPrice(_newPrice)

        const liquidationTx = await cdpManager.liquidate(_bobCdpId, {from: owner})
        assert.isFalse(await sortedCdps.contains(_bobCdpId))

        const [liquidatedDebt, liquidatedColl, gasComp] = th.getEmittedLiquidationValues(liquidationTx)

        await priceFeed.setPrice(dec(7428, 13))
        const price = await priceFeed.getPrice()
        // --- TEST ---
        const collChange = 0
        const debtChange = dec(15, 16)
        const newTCR = (await borrowerOperations.getNewTCRFromCdpChange(collChange, true, debtChange, false, price))

        const expectedTCR = _aliceColl.mul(price).div(_aliceDebt.sub(toBN(debtChange)).add(_bobDebt.sub(_bobColl.mul(toBN(_newPrice)).div(LICR))))

        th.assertIsApproximatelyEqual(newTCR, expectedTCR, 10)
      })

      // +ve, 0
      it("collChange is positive, debtChange is 0", async () => {
        // --- SETUP --- Create a Liquity instance with an Active Pool and pending rewards (Default Pool)
        const cdpColl = toBN(dec(1000, 'ether'))
        const cdpTotalDebt = toBN(dec(5, 18))
        const cdpEBTCAmount = await getOpenCdpEBTCAmount(cdpTotalDebt)
        await contracts.collateral.deposit({from: alice, value: dec(5000, 'ether')});
        await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: alice});
        await contracts.collateral.deposit({from: bob, value: dec(5000, 'ether')});
        await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: bob})
        await borrowerOperations.openCdp(cdpEBTCAmount, th.DUMMY_BYTES32, th.DUMMY_BYTES32, cdpColl, { from: alice })
        await borrowerOperations.openCdp(cdpEBTCAmount, th.DUMMY_BYTES32, th.DUMMY_BYTES32, cdpColl, { from: bob })

        let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
        let _aliceDebtAndColl = await cdpManager.getSyncedDebtAndCollShares(_aliceCdpId);
        let _aliceDebt = _aliceDebtAndColl[0];
        let _aliceColl = _aliceDebtAndColl[1];
        let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
        let _bobDebtAndColl = await cdpManager.getSyncedDebtAndCollShares(_bobCdpId);
        let _bobDebt = _bobDebtAndColl[0];
        let _bobColl = _bobDebtAndColl[1];
		
        await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), { from: alice});
        await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), { from: bob});

        let _newPrice = dec(150, 13);
        await priceFeed.setPrice(_newPrice)

        const liquidationTx = await cdpManager.liquidate(_bobCdpId)
        assert.isFalse(await sortedCdps.contains(_bobCdpId))

        const [liquidatedDebt, liquidatedColl, gasComp] = th.getEmittedLiquidationValues(liquidationTx)

        await priceFeed.setPrice(dec(7428, 13))
        const price = await priceFeed.getPrice()
        // --- TEST ---
        const collChange = dec(2, 'ether')
        const debtChange = 0
        const newTCR = (await borrowerOperations.getNewTCRFromCdpChange(collChange, true, debtChange, true, price))

        const expectedTCR = _aliceColl.add(toBN(collChange)).mul(price).div(_aliceDebt.add(_bobDebt.sub(_bobColl.mul(toBN(_newPrice)).div(LICR))));

        th.assertIsApproximatelyEqual(newTCR, expectedTCR, 10)
      })

      // -ve, 0
      it("collChange is negative, debtChange is 0", async () => {
        // --- SETUP --- Create a Liquity instance with an Active Pool and pending rewards (Default Pool)
        const cdpColl = toBN(dec(1000, 'ether'))
        const cdpTotalDebt = toBN(dec(10, 18))
        const cdpEBTCAmount = await getOpenCdpEBTCAmount(cdpTotalDebt)
        await contracts.collateral.deposit({from: alice, value: dec(5000, 'ether')});
        await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: alice});
        await contracts.collateral.deposit({from: bob, value: dec(5000, 'ether')});
        await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: bob})
        await borrowerOperations.openCdp(cdpEBTCAmount, th.DUMMY_BYTES32, th.DUMMY_BYTES32, cdpColl, { from: alice })
        await borrowerOperations.openCdp(cdpEBTCAmount, th.DUMMY_BYTES32, th.DUMMY_BYTES32, cdpColl, { from: bob })
        let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
        let _aliceDebtAndColl = await cdpManager.getSyncedDebtAndCollShares(_aliceCdpId);
        let _aliceDebt = _aliceDebtAndColl[0];
        let _aliceColl = _aliceDebtAndColl[1];
        let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
        let _bobDebtAndColl = await cdpManager.getSyncedDebtAndCollShares(_bobCdpId);
        let _bobDebt = _bobDebtAndColl[0];
        let _bobColl = _bobDebtAndColl[1];

        await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), { from: alice});
        await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), { from: bob});

        let _newPrice = dec(150, 13);
        await priceFeed.setPrice(_newPrice)

        const liquidationTx = await cdpManager.liquidate(_bobCdpId, {from: owner})
        assert.isFalse(await sortedCdps.contains(_bobCdpId))

        const [liquidatedDebt, liquidatedColl, gasComp] = th.getEmittedLiquidationValues(liquidationTx)

        await priceFeed.setPrice(dec(7428, 13))
        const price = await priceFeed.getPrice()

        // --- TEST ---
        const collChange = dec(1, 18)
        const debtChange = 0
        const newTCR = (await borrowerOperations.getNewTCRFromCdpChange(collChange, false, debtChange, true, price))

        const expectedTCR = _aliceColl.sub(toBN(collChange)).mul(price).div(_aliceDebt.add(_bobDebt.sub(_bobColl.mul(toBN(_newPrice)).div(LICR))))

        th.assertIsApproximatelyEqual(newTCR.toString(), expectedTCR.toString())
      })

      // -ve, -ve
      it("collChange is negative, debtChange is negative", async () => {
        // --- SETUP --- Create a Liquity instance with an Active Pool and pending rewards (Default Pool)
        const cdpColl = toBN(dec(1000, 'ether'))
        const cdpTotalDebt = toBN(dec(10, 18))
        const cdpEBTCAmount = await getOpenCdpEBTCAmount(cdpTotalDebt)
        await contracts.collateral.deposit({from: alice, value: dec(5000, 'ether')});
        await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: alice});
        await contracts.collateral.deposit({from: bob, value: dec(5000, 'ether')});
        await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: bob})
        await borrowerOperations.openCdp(cdpEBTCAmount, th.DUMMY_BYTES32, th.DUMMY_BYTES32, cdpColl, { from: alice })
        await borrowerOperations.openCdp(cdpEBTCAmount, th.DUMMY_BYTES32, th.DUMMY_BYTES32, cdpColl, { from: bob })

        const bobIndex = await sortedCdps.cdpOfOwnerByIndex(bob,0)
        await _signer.sendTransaction({ to: owner, value: ethers.utils.parseEther("51000")});
        await openCdp({ extraEBTCAmount: toBN(dec(200, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: owner } });

        await priceFeed.setPrice(dec(150, 13))

        const liquidationTx = await cdpManager.liquidate(bobIndex, {from: owner})
        assert.isFalse(await sortedCdps.contains(bobIndex))

        const [liquidatedDebt, liquidatedColl, gasComp] = th.getEmittedLiquidationValues(liquidationTx)

        await priceFeed.setPrice(dec(7428, 13))
        const price = await priceFeed.getPrice()

        // --- TEST ---
        const collChange = dec(100, 18)
        const debtChange = dec(1, 18)
        const newTCR = (await borrowerOperations.getNewTCRFromCdpChange(collChange, false, debtChange, false, price))

        let _cdpColl = await cdpManager.getSystemCollShares();
        let _cdpTotalDebt = await cdpManager.getSystemDebt();
        const expectedTCR = (_cdpColl.add(toBN('0')).sub(toBN(collChange))).mul(price)
          .div(_cdpTotalDebt.add(toBN('0')).sub(toBN(debtChange)))

        th.assertIsApproximatelyEqual(newTCR, expectedTCR, 10)
      })

      // +ve, +ve 
      it("collChange is positive, debtChange is positive", async () => {
        // --- SETUP --- Create a Liquity instance with an Active Pool and pending rewards (Default Pool)
        const cdpColl = toBN(dec(1000, 'ether'))
        const cdpTotalDebt = toBN(dec(10, 18))
        const cdpEBTCAmount = await getOpenCdpEBTCAmount(cdpTotalDebt)
        await contracts.collateral.deposit({from: alice, value: dec(5000, 'ether')});
        await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: alice});
        await contracts.collateral.deposit({from: bob, value: dec(5000, 'ether')});
        await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: bob})
        await borrowerOperations.openCdp(cdpEBTCAmount, th.DUMMY_BYTES32, th.DUMMY_BYTES32, cdpColl, { from: alice })
        await borrowerOperations.openCdp(cdpEBTCAmount, th.DUMMY_BYTES32, th.DUMMY_BYTES32, cdpColl, { from: bob })

        const bobIndex = await sortedCdps.cdpOfOwnerByIndex(bob,0)
        await _signer.sendTransaction({ to: owner, value: ethers.utils.parseEther("51000")});	
        await openCdp({ extraEBTCAmount: toBN(dec(200, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: owner } });

        await priceFeed.setPrice(dec(150, 13))

        const liquidationTx = await cdpManager.liquidate(bobIndex, {from: owner})
        assert.isFalse(await sortedCdps.contains(bobIndex))

        const [liquidatedDebt, liquidatedColl, gasComp] = th.getEmittedLiquidationValues(liquidationTx)

        await priceFeed.setPrice(dec(7428, 13))
        const price = await priceFeed.getPrice()

        // --- TEST ---
        const collChange = dec(1, 'ether')
        const debtChange = dec(100, 18)
        const newTCR = (await borrowerOperations.getNewTCRFromCdpChange(collChange, true, debtChange, true, price))

        let _cdpColl = await cdpManager.getSystemCollShares();
        let _cdpTotalDebt = await cdpManager.getSystemDebt();
        const expectedTCR = (_cdpColl.add(toBN('0')).add(toBN(collChange))).mul(price)
          .div(_cdpTotalDebt.add(toBN('0')).add(toBN(debtChange)))

        assert.isTrue(newTCR.eq(expectedTCR))
      })

      // +ve, -ve
      it("collChange is positive, debtChange is negative", async () => {
        // --- SETUP --- Create a Liquity instance with an Active Pool and pending rewards (Default Pool)
        const cdpColl = toBN(dec(1000, 'ether'))
        const cdpTotalDebt = toBN(dec(10, 18))
        const cdpEBTCAmount = await getOpenCdpEBTCAmount(cdpTotalDebt)
        await contracts.collateral.deposit({from: alice, value: dec(5000, 'ether')});
        await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: alice});
        await contracts.collateral.deposit({from: bob, value: dec(5000, 'ether')});
        await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: bob})
        await borrowerOperations.openCdp(cdpEBTCAmount, alice, alice, cdpColl, { from: alice })
        await borrowerOperations.openCdp(cdpEBTCAmount, bob, bob, cdpColl, { from: bob })

        const bobIndex = await sortedCdps.cdpOfOwnerByIndex(bob,0)
        await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), { from: alice});
        await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), { from: bob});

        await priceFeed.setPrice(dec(150, 13))

        const liquidationTx = await cdpManager.liquidate(bobIndex, {from: owner})
        assert.isFalse(await sortedCdps.contains(bobIndex))

        const [liquidatedDebt, liquidatedColl, gasComp] = th.getEmittedLiquidationValues(liquidationTx)

        await priceFeed.setPrice(dec(7428, 13))
        const price = await priceFeed.getPrice()

        // --- TEST ---
        const collChange = dec(100, 'ether')
        const debtChange = dec(1, 18)
        const newTCR = (await borrowerOperations.getNewTCRFromCdpChange(collChange, true, debtChange, false, price))
        
        let _cdpColl = await cdpManager.getSystemCollShares();
        let _cdpTotalDebt = await cdpManager.getSystemDebt();
        const expectedTCR = (_cdpColl.add(toBN('0')).add(toBN(collChange))).mul(price)
          .div(_cdpTotalDebt.add(toBN('0')).sub(toBN(debtChange)))

        assert.isTrue(newTCR.eq(expectedTCR))
      })

      // -ve, +ve
      xit("collChange is negative, debtChange is positive", async () => {
        // --- SETUP --- Create a Liquity instance with an Active Pool and pending rewards (Default Pool)
        const cdpColl = toBN(dec(1000, 'ether'))
        const cdpTotalDebt = toBN(dec(100000, 18))
        const cdpEBTCAmount = await getOpenCdpEBTCAmount(cdpTotalDebt)
        await borrowerOperations.openCdp(cdpEBTCAmount, alice, alice, { from: alice, value: cdpColl })
        await borrowerOperations.openCdp(cdpEBTCAmount, bob, bob, { from: bob, value: cdpColl })

        const bobIndex = await sortedCdps.cdpOfOwnerByIndex(bob,0)

        await priceFeed.setPrice(dec(3800, 13))

        const liquidationTx = await cdpManager.liquidate(bobIndex)
        assert.isFalse(await sortedCdps.contains(bobIndex))

        const [liquidatedDebt, liquidatedColl, gasComp] = th.getEmittedLiquidationValues(liquidationTx)

        await priceFeed.setPrice(dec(200, 18))
        const price = await priceFeed.getPrice()

        // --- TEST ---
        const collChange = dec(1, 18)
        const debtChange = await getNetBorrowingAmount(dec(200, 18))
        const newTCR = (await borrowerOperations.getNewTCRFromCdpChange(collChange, false, debtChange, true, price))

        const expectedTCR = (cdpColl.add(liquidatedColl).sub(toBN(collChange))).mul(price)
          .div(cdpTotalDebt.add(liquidatedDebt).add(toBN(debtChange)))

        assert.isTrue(newTCR.eq(expectedTCR))
      })
    })

    if (!withProxy) {
      xit("closeCdp(): fails if owner cannot receive ETH", async () => {
        const nonPayable = await NonPayable.new()

        // we need 2 cdps to be able to close 1 and have 1 remaining in the system
        await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("10000")});
        await borrowerOperations.openCdp(dec(1, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: alice, value: dec(1000, 18) })

        // Alice sends EBTC to NonPayable so its EBTC balance covers its debt
        await ebtcToken.transfer(nonPayable.address, dec(1, 18), {from: alice})

        // open cdp from NonPayable proxy contract
        const _100pctHex = '0xde0b6b3a7640000'
        const _1e18Hex = '0xDE0B6B3A7640000'
        const openCdpData = th.getTransactionData('openCdp(uint256,uint256,bytes32,bytes32)', [_100pctHex, _1e18Hex, th.DUMMY_BYTES32, th.DUMMY_BYTES32])
        await _signer.sendTransaction({ to: owner, value: ethers.utils.parseEther("24000")});
        await nonPayable.forward(borrowerOperations.address, openCdpData, { value: dec(20000, 'ether') })

        const nonPayableIndex = await sortedCdps.cdpOfOwnerByIndex(nonPayable.address,0)

        assert.equal((await cdpManager.getCdpStatus(nonPayableIndex)).toString(), '1', 'NonPayable proxy should have a cdp')
        assert.isFalse(await th.checkRecoveryMode(contracts), 'System should not be in Recovery Mode')
        // open cdp from NonPayable proxy contract
        const closeCdpData = th.getTransactionData('closeCdp(bytes32)', [nonPayableIndex])
        await th.assertRevert(nonPayable.forward(borrowerOperations.address, closeCdpData), 'ActivePool: sending ETH failed')
      })
    }
  }

  describe('Without proxy', async () => {
    testCorpus({ withProxy: false })
  })

  // describe('With proxy', async () => {
  //   testCorpus({ withProxy: true })
  // })
})

contract('Reset chain state', async accounts => { })

/* TODO:

 1) Test SortedList re-ordering by ICR. ICR ratio
 changes with addColl, withdrawColl, withdrawDebt, repayDebt, etc. Can split them up and put them with
 individual functions, or give ordering it's own 'describe' block.

 2)In security phase:
 -'Negative' tests for all the above functions.
 */
