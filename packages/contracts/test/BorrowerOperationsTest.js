const deploymentHelper = require("../utils/deploymentHelpers.js")
const testHelpers = require("../utils/testHelpers.js")

const BorrowerOperationsTester = artifacts.require("./BorrowerOperationsTester.sol")
const NonPayable = artifacts.require('NonPayable.sol')
const TroveManagerTester = artifacts.require("TroveManagerTester")
const EBTCTokenTester = artifacts.require("./EBTCTokenTester")
const MultipleTrovesTester = artifacts.require("./MultipleTrovesTester.sol")

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
 *  the parameter MINUTE_DECAY_FACTOR in the TroveManager, which is still TBD based on economic
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

    const bn8 = "0xF977814e90dA44bFA03b6295A0616a897441aceC";
    let [bountyAddress, lpRewardsAddress, multisig] = accounts.slice(997, 1000)
    let bn8Signer;

  // const frontEnds = [frontEnd_1, frontEnd_2, frontEnd_3]

  let priceFeed
  let lusdToken
  let sortedTroves
  let troveManager
  let activePool
  let stabilityPool
  let defaultPool
  let borrowerOperations
  let lqtyStaking
  let lqtyToken

  let contracts

  const getOpenTroveEBTCAmount = async (totalDebt) => th.getOpenTroveEBTCAmount(contracts, totalDebt)
  const getNetBorrowingAmount = async (debtWithFee) => th.getNetBorrowingAmount(contracts, debtWithFee)
  const getActualDebtFromComposite = async (compositeDebt) => th.getActualDebtFromComposite(compositeDebt, contracts)
  const openTrove = async (params) => th.openTrove(contracts, params)
  const getTroveEntireColl = async (trove) => th.getTroveEntireColl(contracts, trove)
  const getTroveEntireDebt = async (trove) => th.getTroveEntireDebt(contracts, trove)
  const getTroveStake = async (trove) => th.getTroveStake(contracts, trove)

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
      contracts = await deploymentHelper.deployLiquityCore()
      contracts.borrowerOperations = await BorrowerOperationsTester.new()
      contracts.troveManager = await TroveManagerTester.new()
      contracts = await deploymentHelper.deployEBTCTokenTester(contracts)
      const LQTYContracts = await deploymentHelper.deployLQTYTesterContractsHardhat(bountyAddress, lpRewardsAddress, multisig)

      await deploymentHelper.connectLQTYContracts(LQTYContracts)
      await deploymentHelper.connectCoreContracts(contracts, LQTYContracts)
      await deploymentHelper.connectLQTYContractsToCore(LQTYContracts, contracts)

      if (withProxy) {
        const users = [alice, bob, carol, dennis, whale, A, B, C, D, E]
        await deploymentHelper.deployProxyScripts(contracts, LQTYContracts, owner, users)
      }

      priceFeed = contracts.priceFeedTestnet
      lusdToken = contracts.lusdToken
      sortedTroves = contracts.sortedTroves
      troveManager = contracts.troveManager
      activePool = contracts.activePool
      stabilityPool = contracts.stabilityPool
      defaultPool = contracts.defaultPool
      borrowerOperations = contracts.borrowerOperations
      hintHelpers = contracts.hintHelpers

      lqtyStaking = LQTYContracts.lqtyStaking
      lqtyToken = LQTYContracts.lqtyToken
      communityIssuance = LQTYContracts.communityIssuance
      lockupContractFactory = LQTYContracts.lockupContractFactory

      EBTC_GAS_COMPENSATION = await borrowerOperations.EBTC_GAS_COMPENSATION()
      MIN_NET_DEBT = await borrowerOperations.MIN_NET_DEBT()
      BORROWING_FEE_FLOOR = await borrowerOperations.BORROWING_FEE_FLOOR()

      ownerSigner = await ethers.provider.getSigner(owner);
      let _ownerBal = await web3.eth.getBalance(owner);
      let _bn8Bal = await web3.eth.getBalance(bn8);
      let _ownerRicher = toBN(_ownerBal.toString()).gt(toBN(_bn8Bal.toString()));
      let _signer = _ownerRicher? ownerSigner : bn8Signer;
	  
      await _signer.sendTransaction({ to: alice, value: ethers.utils.parseEther("11000")});
      await _signer.sendTransaction({ to: bob, value: ethers.utils.parseEther("1100")});
      await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("1100")});
      await _signer.sendTransaction({ to: multisig, value: ethers.utils.parseEther("1100")});
      
    })

    it("openTrove(): mutiple Trove via non-EOA smart contract", async () => {
	  mtsTester = await MultipleTrovesTester.new();
	  mtsTester.initiate(borrowerOperations.address, sortedTroves.address);	  
	  ownerSigner.sendTransaction({ to: mtsTester.address, value: ethers.utils.parseEther("1000")});
      		
	  // open multiple Troves
	  let _count = 10;
	  const _singleTroveDebt = (await contracts.borrowerOperations.MIN_NET_DEBT()).add(toBN(dec(2, 18)));
	  let _icr = toBN(dec(25, 17));//250%
	  const _price = await priceFeed.getPrice();
	  let _singleTroveCol = _icr.mul(_singleTroveDebt).div(_price);
	  tx = await mtsTester.openTroves(_count, th._100pct, _singleTroveDebt, th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: owner, value: _singleTroveCol.mul(toBN(_count)) } );
	  let _openedTroveEvts = th.getAllEventsByName(tx, 'TroveOpened');
	  let _ei = 0;
	  for(;_ei < _openedTroveEvts.length - 1;_ei++){
	      let _troveId = _openedTroveEvts[_ei].args[0];
	      //console.log(_troveId);
	      let _troveStatus = await troveManager.getTroveStatus(_troveId);
	      assert.equal(_troveStatus, 1);			
	      let _troveOwner = await sortedTroves.existTroveOwners(_troveId);
	      assert.equal(_troveOwner, mtsTester.address);	  
	      let _ii = _ei + 1;
	      for(;_ii < _openedTroveEvts.length;_ii++){
	          let _iTroveId = _openedTroveEvts[_ii].args[0];
	          assert.notEqual(_iTroveId, _troveId);
	          let _iTroveStatus = await troveManager.getTroveStatus(_iTroveId);
	          assert.equal(_iTroveStatus, 1);  		
	          let _iTroveOwner = await sortedTroves.existTroveOwners(_iTroveId);
	          assert.equal(_iTroveOwner, mtsTester.address);
	      }
	  }
	  //console.log(_openedTroveEvts[_openedTroveEvts.length - 1].args[0]);
    })

    it("openTrove(): mutiple Trove per user", async () => {		  
	  // first Trove
	  await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } });
	  let troveSize = await sortedTroves.getSize();
	  let troveIds = await troveManager.getTroveIdsCount();
	  assert.isTrue(troveSize == 1);
	  assert.isTrue((troveSize - troveIds) == 0);
	  let lastTroveId = await sortedTroves.getLast();
	  let lastTroveOwner = await sortedTroves.existTroveOwners(lastTroveId);
	  assert.isTrue(lastTroveOwner == alice);
	  let _aliceOwnedTroves = await sortedTroves.troveCountOf(alice);
	  assert.isTrue(_aliceOwnedTroves == 1);	  
	  let _aliceOwnedTrove = await sortedTroves.troveOfOwnerByIndex(alice, _aliceOwnedTroves - 1);
	  assert.isTrue(_aliceOwnedTrove == lastTroveId);
	  
	  // Second Trove
	  await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } });
	  troveSize = await sortedTroves.getSize();
	  troveIds = await troveManager.getTroveIdsCount();
	  assert.isTrue(troveSize == 2);
	  assert.isTrue((troveIds - troveSize) == 0);
	  lastTroveId = await sortedTroves.getLast();
	  lastTroveOwner = await sortedTroves.existTroveOwners(lastTroveId);
	  let firstTroveId = await sortedTroves.getFirst();
	  let firstTroveOwner = await sortedTroves.existTroveOwners(firstTroveId);
	  assert.isTrue(lastTroveOwner == alice);
	  assert.isTrue(firstTroveOwner == alice);
	  assert.isTrue(firstTroveId != lastTroveId);
	  _aliceOwnedTroves = await sortedTroves.troveCountOf(alice);
	  assert.isTrue(_aliceOwnedTroves == 2);	  
	  let _aliceOwnedFirstTrove = await sortedTroves.troveOfOwnerByIndex(alice, _aliceOwnedTroves - 2);
	  let _aliceOwnedSecondTrove = await sortedTroves.troveOfOwnerByIndex(alice, _aliceOwnedTroves - 1);
	  assert.isTrue(_aliceOwnedFirstTrove == lastTroveId);
	  assert.isTrue(_aliceOwnedSecondTrove == firstTroveId);
	  
	  // Close Second Trove	  	
	  await assertRevert(borrowerOperations.closeTrove(lastTroveId, { from: bob }), "!troveOwner");	
	  const txClose = await borrowerOperations.closeTrove(lastTroveId, { from: alice });
	  assert.isTrue(txClose.receipt.status);
	  troveSize = await sortedTroves.getSize();
	  troveIds = await troveManager.getTroveIdsCount();
	  assert.isTrue(troveSize == 1);
	  assert.isTrue((troveIds - troveSize) == 0);
	  lastTroveId = await sortedTroves.getLast();
	  lastTroveOwner = await sortedTroves.existTroveOwners(lastTroveId);
	  assert.isTrue(firstTroveId == lastTroveId);	
	  assert.isTrue(firstTroveOwner == lastTroveOwner); 
	  _aliceOwnedTroves = await sortedTroves.troveCountOf(alice);
	  assert.isTrue(_aliceOwnedTroves == 1);	
	  let _aliceOwnedLeftTrove = await sortedTroves.troveOfOwnerByIndex(alice, _aliceOwnedTroves - 1);
	  assert.isTrue(_aliceOwnedLeftTrove == firstTroveId);   
    })

    it("addColl(): reverts when top-up would leave trove with ICR < MCR", async () => {
      // alice creates a Trove and adds first collateral
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openTrove({ ICR: toBN(dec(10, 18)), extraParams: { from: bob } })

      // Price drops
      await priceFeed.setPrice(dec(100, 18))
      const price = await priceFeed.getPrice()

      assert.isFalse(await troveManager.checkRecoveryMode(price))
      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
      const icr = await troveManager.getCurrentICR(aliceIndex, price)
      assert.isTrue((await troveManager.getCurrentICR(aliceIndex, price)).lt(toBN(dec(110, 16))))

      const collTopUp = 1  // 1 wei top up

     await assertRevert(borrowerOperations.addColl(aliceIndex, th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: alice, value: collTopUp }), 
      "BorrowerOps: An operation that would result in ICR < MCR is not permitted")
    })

    it("addColl(): Increases the activePool ETH and raw ether balance by correct amount", async () => {
      const { collateral: aliceColl } = await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      
      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)

      const activePool_ETH_Before = await activePool.getETH()
      const activePool_RawEther_Before = toBN(await web3.eth.getBalance(activePool.address))

      assert.isTrue(activePool_ETH_Before.eq(aliceColl))
      assert.isTrue(activePool_RawEther_Before.eq(aliceColl))

      await borrowerOperations.addColl(aliceIndex, th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: alice, value: dec(1, 'ether') })

      const activePool_ETH_After = await activePool.getETH()
      const activePool_RawEther_After = toBN(await web3.eth.getBalance(activePool.address))
      assert.isTrue(activePool_ETH_After.eq(aliceColl.add(toBN(dec(1, 'ether')))))
      assert.isTrue(activePool_RawEther_After.eq(aliceColl.add(toBN(dec(1, 'ether')))))
    })

    it("addColl(), active Trove: adds the correct collateral amount to the Trove", async () => {
      // alice creates a Trove and adds first collateral
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)

      const alice_Trove_Before = await troveManager.Troves(aliceIndex)
      const coll_before = alice_Trove_Before[1]
      const status_Before = alice_Trove_Before[3]

      // check status before
      assert.equal(status_Before, 1)

      // Alice adds second collateral
      await borrowerOperations.addColl(aliceIndex, th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: alice, value: dec(1, 'ether') })

      const alice_Trove_After = await troveManager.Troves(aliceIndex)
      const coll_After = alice_Trove_After[1]
      const status_After = alice_Trove_After[3]

      // check coll increases by correct amount,and status remains active
      assert.isTrue(coll_After.eq(coll_before.add(toBN(dec(1, 'ether')))))
      assert.equal(status_After, 1)
    })

    it("addColl(), active Trove: Trove is in sortedList before and after", async () => {
      // alice creates a Trove and adds first collateral
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)

      // check Alice is in list before
      const aliceTroveInList_Before = await sortedTroves.contains(aliceIndex)
      const listIsEmpty_Before = await sortedTroves.isEmpty()
      assert.equal(aliceTroveInList_Before, true)
      assert.equal(listIsEmpty_Before, false)

      await borrowerOperations.addColl(aliceIndex, th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: alice, value: dec(1, 'ether') })

      // check Alice is still in list after
      const aliceTroveInList_After = await sortedTroves.contains(aliceIndex)
      const listIsEmpty_After = await sortedTroves.isEmpty()
      assert.equal(aliceTroveInList_After, true)
      assert.equal(listIsEmpty_After, false)
    })

    it("addColl(), active Trove: updates the stake and updates the total stakes", async () => {
      //  Alice creates initial Trove with 1 ether
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)

      const alice_Trove_Before = await troveManager.Troves(aliceIndex)
      const alice_Stake_Before = alice_Trove_Before[2]
      const totalStakes_Before = (await troveManager.totalStakes())

      assert.isTrue(totalStakes_Before.eq(alice_Stake_Before))

      // Alice tops up Trove collateral with 2 ether
      await borrowerOperations.addColl(aliceIndex, th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: alice, value: dec(2, 'ether') })

      // Check stake and total stakes get updated
      const alice_Trove_After = await troveManager.Troves(aliceIndex)
      const alice_Stake_After = alice_Trove_After[2]
      const totalStakes_After = (await troveManager.totalStakes())

      assert.isTrue(alice_Stake_After.eq(alice_Stake_Before.add(toBN(dec(2, 'ether')))))
      assert.isTrue(totalStakes_After.eq(totalStakes_Before.add(toBN(dec(2, 'ether')))))
    })

    it("addColl(), active Trove: applies pending rewards and updates user's L_ETH, L_EBTCDebt snapshots", async () => {
      // --- SETUP ---

      const { collateral: aliceCollBefore, totalDebt: aliceDebtBefore } = await openTrove({ extraEBTCAmount: toBN(dec(15000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
      
      const { collateral: bobCollBefore, totalDebt: bobDebtBefore } = await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: bob } })
      const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)

      await openTrove({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: carol } })
      const carolIndex = await sortedTroves.troveOfOwnerByIndex(carol,0)

      // --- TEST ---

      // price drops to 1ETH:100EBTC, reducing Carol's ICR below MCR
      await priceFeed.setPrice('100000000000000000000');

      // Liquidate Carol's Trove,
      const tx = await troveManager.liquidate(carolIndex, { from: owner });

      assert.isFalse(await sortedTroves.contains(carolIndex))

      const L_ETH = await troveManager.L_ETH()
      const L_EBTCDebt = await troveManager.L_EBTCDebt()

      // check Alice and Bob's reward snapshots are zero before they alter their Troves
      const alice_rewardSnapshot_Before = await troveManager.rewardSnapshots(aliceIndex)
      const alice_ETHrewardSnapshot_Before = alice_rewardSnapshot_Before[0]
      const alice_EBTCDebtRewardSnapshot_Before = alice_rewardSnapshot_Before[1]

      const bob_rewardSnapshot_Before = await troveManager.rewardSnapshots(bobIndex)
      const bob_ETHrewardSnapshot_Before = bob_rewardSnapshot_Before[0]
      const bob_EBTCDebtRewardSnapshot_Before = bob_rewardSnapshot_Before[1]

      assert.equal(alice_ETHrewardSnapshot_Before, 0)
      assert.equal(alice_EBTCDebtRewardSnapshot_Before, 0)
      assert.equal(bob_ETHrewardSnapshot_Before, 0)
      assert.equal(bob_EBTCDebtRewardSnapshot_Before, 0)

      const alicePendingETHReward = await troveManager.getPendingETHReward(aliceIndex)
      const bobPendingETHReward = await troveManager.getPendingETHReward(bobIndex)
      const alicePendingEBTCDebtReward = await troveManager.getPendingEBTCDebtReward(aliceIndex)
      const bobPendingEBTCDebtReward = await troveManager.getPendingEBTCDebtReward(bobIndex)
      for (reward of [alicePendingETHReward, bobPendingETHReward, alicePendingEBTCDebtReward, bobPendingEBTCDebtReward]) {
        assert.isTrue(reward.gt(toBN('0')))
      }

      // Alice and Bob top up their Troves
      const aliceTopUp = toBN(dec(5, 'ether'))
      const bobTopUp = toBN(dec(1, 'ether'))

      await borrowerOperations.addColl(aliceIndex, th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: alice, value: aliceTopUp })
      await borrowerOperations.addColl(bobIndex, th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: bob, value: bobTopUp })

      // Check that both alice and Bob have had pending rewards applied in addition to their top-ups. 
      const aliceNewColl = await getTroveEntireColl(aliceIndex)
      const aliceNewDebt = await getTroveEntireDebt(aliceIndex)
      const bobNewColl = await getTroveEntireColl(bobIndex)
      const bobNewDebt = await getTroveEntireDebt(bobIndex)

      assert.isTrue(aliceNewColl.eq(aliceCollBefore.add(alicePendingETHReward).add(aliceTopUp)))
      assert.isTrue(aliceNewDebt.eq(aliceDebtBefore.add(alicePendingEBTCDebtReward)))
      assert.isTrue(bobNewColl.eq(bobCollBefore.add(bobPendingETHReward).add(bobTopUp)))
      assert.isTrue(bobNewDebt.eq(bobDebtBefore.add(bobPendingEBTCDebtReward)))

      /* Check that both Alice and Bob's snapshots of the rewards-per-unit-staked metrics should be updated
       to the latest values of L_ETH and L_EBTCDebt */
      const alice_rewardSnapshot_After = await troveManager.rewardSnapshots(aliceIndex)
      const alice_ETHrewardSnapshot_After = alice_rewardSnapshot_After[0]
      const alice_EBTCDebtRewardSnapshot_After = alice_rewardSnapshot_After[1]

      const bob_rewardSnapshot_After = await troveManager.rewardSnapshots(bobIndex)
      const bob_ETHrewardSnapshot_After = bob_rewardSnapshot_After[0]
      const bob_EBTCDebtRewardSnapshot_After = bob_rewardSnapshot_After[1]

      assert.isAtMost(th.getDifference(alice_ETHrewardSnapshot_After, L_ETH), 100)
      assert.isAtMost(th.getDifference(alice_EBTCDebtRewardSnapshot_After, L_EBTCDebt), 100)
      assert.isAtMost(th.getDifference(bob_ETHrewardSnapshot_After, L_ETH), 100)
      assert.isAtMost(th.getDifference(bob_EBTCDebtRewardSnapshot_After, L_EBTCDebt), 100)
    })

    // xit("addColl(), active Trove: adds the right corrected stake after liquidations have occured", async () => {
    //  // TODO - check stake updates for addColl/withdrawColl/adustTrove ---

    //   // --- SETUP ---
    //   // A,B,C add 15/5/5 ETH, withdraw 100/100/900 EBTC
    //   await borrowerOperations.openTrove(th._100pct, dec(100, 18), alice, alice, { from: alice, value: dec(15, 'ether') })
    //   await borrowerOperations.openTrove(th._100pct, dec(100, 18), bob, bob, { from: bob, value: dec(4, 'ether') })
    //   await borrowerOperations.openTrove(th._100pct, dec(900, 18), carol, carol, { from: carol, value: dec(5, 'ether') })

    //   await borrowerOperations.openTrove(th._100pct, 0, dennis, dennis, { from: dennis, value: dec(1, 'ether') })
    //   // --- TEST ---

    //   // price drops to 1ETH:100EBTC, reducing Carol's ICR below MCR
    //   await priceFeed.setPrice('100000000000000000000');

    //   // close Carol's Trove, liquidating her 5 ether and 900EBTC.
    //   await troveManager.liquidate(carol, { from: owner });

    //   // dennis tops up his trove by 1 ETH
    //   await borrowerOperations.addColl(dennis, dennis, { from: dennis, value: dec(1, 'ether') })

    //   /* Check that Dennis's recorded stake is the right corrected stake, less than his collateral. A corrected 
    //   stake is given by the formula: 

    //   s = totalStakesSnapshot / totalCollateralSnapshot 

    //   where snapshots are the values immediately after the last liquidation.  After Carol's liquidation, 
    //   the ETH from her Trove has now become the totalPendingETHReward. So:

    //   totalStakes = (alice_Stake + bob_Stake + dennis_orig_stake ) = (15 + 4 + 1) =  20 ETH.
    //   totalCollateral = (alice_Collateral + bob_Collateral + dennis_orig_coll + totalPendingETHReward) = (15 + 4 + 1 + 5)  = 25 ETH.

    //   Therefore, as Dennis adds 1 ether collateral, his corrected stake should be:  s = 2 * (20 / 25 ) = 1.6 ETH */
    //   const dennis_Trove = await troveManager.Troves(dennis)

    //   const dennis_Stake = dennis_Trove[2]
    //   console.log(dennis_Stake.toString())

    //   assert.isAtMost(th.getDifference(dennis_Stake), 100)
    // })

    it("addColl(), reverts if trove is not owned by caller", async () => {
      // A, B open troves
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: bob } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
      const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)

      // random index
      const carolIndex = th.RANDOM_INDEX;

      // Carol attempts to add collateral to her non-existent trove
      try {
        const txCarol = await borrowerOperations.addColl(bobIndex, th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: carol, value: dec(1, 'ether') })
        assert.isFalse(txCarol.receipt.status)
      } catch (error) {
        assert.include(error.message, "revert")
        assert.include(error.message, "BorrowerOps: Caller must be trove owner")
      }
    })

    it("addColl(), reverts if trove is non-existent or closed", async () => {
      // A, B open troves
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: bob } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
      const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)

      // Price drops
      await priceFeed.setPrice(dec(100, 18))

      // Bob gets liquidated
      await troveManager.liquidate(bobIndex)

      assert.isFalse(await sortedTroves.contains(bobIndex))

      // Bob attempts to add collateral to his closed trove
      try {
        const txBob = await borrowerOperations.addColl(bobIndex, th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: bob, value: dec(1, 'ether') })
        assert.isFalse(txBob.receipt.status)
      } catch (error) {
        assert.include(error.message, "revert")
        assert.include(error.message, "BorrowerOps: Caller must be trove owner")
      }
    })

    it("addColl(): can add collateral in Recovery Mode", async () => {
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)

      const aliceCollBefore = await getTroveEntireColl(aliceIndex)
      assert.isFalse(await th.checkRecoveryMode(contracts))

      await priceFeed.setPrice('105000000000000000000')

      assert.isTrue(await th.checkRecoveryMode(contracts))

      const collTopUp = toBN(dec(1, 'ether'))
      await borrowerOperations.addColl(aliceIndex, th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: alice, value: collTopUp })

      // Check Alice's collateral
      const aliceCollAfter = (await troveManager.Troves(aliceIndex))[1]
      assert.isTrue(aliceCollAfter.eq(aliceCollBefore.add(collTopUp)))
    })

    // --- withdrawColl() ---

    it("withdrawColl(): reverts when withdrawal would leave trove with ICR < MCR", async () => {
      // alice creates a Trove and adds first collateral
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openTrove({ ICR: toBN(dec(10, 18)), extraParams: { from: bob } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
      const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)

      // Price drops
      await priceFeed.setPrice(dec(100, 18))
      const price = await priceFeed.getPrice()

      assert.isFalse(await troveManager.checkRecoveryMode(price))
      assert.isTrue((await troveManager.getCurrentICR(aliceIndex, price)).lt(toBN(dec(110, 16))))

      const collWithdrawal = 1  // 1 wei withdrawal

     await assertRevert(borrowerOperations.withdrawColl(aliceIndex, 1, th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: alice }), 
      "BorrowerOps: An operation that would result in ICR < MCR is not permitted")
    })

    // reverts when calling address does not have active trove  
    it("withdrawColl(): reverts when calling address does not have active trove", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: bob } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
      const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)
      const carolIndex = th.RANDOM_INDEX;

      // Bob successfully withdraws some coll
      const txBob = await borrowerOperations.withdrawColl(bobIndex, dec(100, 'finney'), bobIndex, bobIndex, { from: bob })
      assert.isTrue(txBob.receipt.status)

      // Carol with no active trove attempts to withdraw
      try {
        const txCarol = await borrowerOperations.withdrawColl(carolIndex, dec(1, 'ether'), th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: carol })
        assert.isFalse(txCarol.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    it("withdrawColl(): reverts when system is in Recovery Mode", async () => {
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: bob } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
      const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)

      assert.isFalse(await th.checkRecoveryMode(contracts))

      // Withdrawal possible when recoveryMode == false
      const txAlice = await borrowerOperations.withdrawColl(aliceIndex, 1000, aliceIndex, aliceIndex, { from: alice })
      assert.isTrue(txAlice.receipt.status)

      await priceFeed.setPrice('105000000000000000000')

      assert.isTrue(await th.checkRecoveryMode(contracts))

      //Check withdrawal impossible when recoveryMode == true
      try {
        const txBob = await borrowerOperations.withdrawColl(bobIndex, 1000, bobIndex, bobIndex, { from: bob })
        assert.isFalse(txBob.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    it("withdrawColl(): reverts when requested ETH withdrawal is > the trove's collateral", async () => {
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: bob } })
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: carol } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
      const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)
      const carolIndex = await sortedTroves.troveOfOwnerByIndex(carol,0)

      const carolColl = await getTroveEntireColl(carolIndex)
      const bobColl = await getTroveEntireColl(bobIndex)
      // Carol withdraws exactly all her collateral
      await assertRevert(
        borrowerOperations.withdrawColl(carolIndex, carolColl, carolIndex, carolIndex, { from: carol }),
        'BorrowerOps: An operation that would result in ICR < MCR is not permitted'
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
      await openTrove({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openTrove({ ICR: toBN(dec(11, 17)), extraParams: { from: bob } }) // 110% ICR

      const whaleIndex = await sortedTroves.troveOfOwnerByIndex(whale,0)
      const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)

      // Bob attempts to withdraws 1 wei, Which would leave him with < 110% ICR.

      try {
        const txBob = await borrowerOperations.withdrawColl(bobIndex, 1, bobIndex, bobIndex, { from: bob })
        assert.isFalse(txBob.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    it("withdrawColl(): reverts if system is in Recovery Mode", async () => {
      // --- SETUP ---

      // A and B open troves at 150% ICR
      await openTrove({ ICR: toBN(dec(15, 17)), extraParams: { from: bob } })
      await openTrove({ ICR: toBN(dec(15, 17)), extraParams: { from: alice } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
      const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)

      const TCR = (await th.getTCR(contracts)).toString()
      assert.equal(TCR, '1500000000000000000')

      // --- TEST ---

      // price drops to 1ETH:150EBTC, reducing TCR below 150%
      await priceFeed.setPrice('150000000000000000000');

      //Alice tries to withdraw collateral during Recovery Mode
      try {
        const txData = await borrowerOperations.withdrawColl(aliceIndex, '1', aliceIndex, aliceIndex, { from: alice })
        assert.isFalse(txData.receipt.status)
      } catch (err) {
        assert.include(err.message, 'revert')
      }
    })

    it("withdrawColl(): doesn’t allow a user to completely withdraw all collateral from their Trove (due to gas compensation)", async () => {
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: bob } })
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
      const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)

      const aliceColl = (await troveManager.getEntireDebtAndColl(aliceIndex))[1]

      // Check Trove is active
      const alice_Trove_Before = await troveManager.Troves(aliceIndex)
      const status_Before = alice_Trove_Before[3]
      assert.equal(status_Before, 1)
      assert.isTrue(await sortedTroves.contains(aliceIndex))

      // Alice attempts to withdraw all collateral
      await assertRevert(
        borrowerOperations.withdrawColl(aliceIndex, aliceColl, aliceIndex, aliceIndex, { from: alice }),
        'BorrowerOps: An operation that would result in ICR < MCR is not permitted'
      )
    })

    it("withdrawColl(): leaves the Trove active when the user withdraws less than all the collateral", async () => {
      // Open Trove 
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      
      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)

      // Check Trove is active
      const alice_Trove_Before = await troveManager.Troves(aliceIndex)
      const status_Before = alice_Trove_Before[3]
      assert.equal(status_Before, 1)
      assert.isTrue(await sortedTroves.contains(aliceIndex))

      // Withdraw some collateral
      await borrowerOperations.withdrawColl(aliceIndex, dec(100, 'finney'), aliceIndex, aliceIndex, { from: alice })

      // Check Trove is still active
      const alice_Trove_After = await troveManager.Troves(aliceIndex)
      const status_After = alice_Trove_After[3]
      assert.equal(status_After, 1)
      assert.isTrue(await sortedTroves.contains(aliceIndex))
    })

    it("withdrawColl(): reduces the Trove's collateral by the correct amount", async () => {
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
      const aliceCollBefore = await getTroveEntireColl(aliceIndex)

      // Alice withdraws 1 ether
      await borrowerOperations.withdrawColl(aliceIndex, dec(1, 'ether'), aliceIndex, aliceIndex, { from: alice })

      // Check 1 ether remaining
      const alice_Trove_After = await troveManager.Troves(aliceIndex)
      const aliceCollAfter = await getTroveEntireColl(aliceIndex)

      assert.isTrue(aliceCollAfter.eq(aliceCollBefore.sub(toBN(dec(1, 'ether')))))
    })

    it("withdrawColl(): reduces ActivePool ETH and raw ether by correct amount", async () => {
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
      const aliceCollBefore = await getTroveEntireColl(aliceIndex)

      // check before
      const activePool_ETH_before = await activePool.getETH()
      const activePool_RawEther_before = toBN(await web3.eth.getBalance(activePool.address))

      await borrowerOperations.withdrawColl(aliceIndex, dec(1, 'ether'), aliceIndex, aliceIndex, { from: alice })

      // check after
      const activePool_ETH_After = await activePool.getETH()
      const activePool_RawEther_After = toBN(await web3.eth.getBalance(activePool.address))
      assert.isTrue(activePool_ETH_After.eq(activePool_ETH_before.sub(toBN(dec(1, 'ether')))))
      assert.isTrue(activePool_RawEther_After.eq(activePool_RawEther_before.sub(toBN(dec(1, 'ether')))))
    })

    it("withdrawColl(): updates the stake and updates the total stakes", async () => {
      //  Alice creates initial Trove with 2 ether
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: alice, value: toBN(dec(5, 'ether')) } })
      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
      const aliceColl = await getTroveEntireColl(aliceIndex)
      assert.isTrue(aliceColl.gt(toBN('0')))

      const alice_Trove_Before = await troveManager.Troves(aliceIndex)
      const alice_Stake_Before = alice_Trove_Before[2]
      const totalStakes_Before = (await troveManager.totalStakes())

      assert.isTrue(alice_Stake_Before.eq(aliceColl))
      assert.isTrue(totalStakes_Before.eq(aliceColl))

      // Alice withdraws 1 ether
      await borrowerOperations.withdrawColl(aliceIndex, dec(1, 'ether'), aliceIndex, aliceIndex, { from: alice })

      // Check stake and total stakes get updated
      const alice_Trove_After = await troveManager.Troves(aliceIndex)
      const alice_Stake_After = alice_Trove_After[2]
      const totalStakes_After = (await troveManager.totalStakes())

      assert.isTrue(alice_Stake_After.eq(alice_Stake_Before.sub(toBN(dec(1, 'ether')))))
      assert.isTrue(totalStakes_After.eq(totalStakes_Before.sub(toBN(dec(1, 'ether')))))
    })

    it("withdrawColl(): sends the correct amount of ETH to the user", async () => {
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: alice, value: dec(2, 'ether') } })
      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)

      const alice_ETHBalance_Before = toBN(web3.utils.toBN(await web3.eth.getBalance(alice)))
      await borrowerOperations.withdrawColl(aliceIndex, dec(1, 'ether'), aliceIndex, aliceIndex, { from: alice, gasPrice: 0 })

      const alice_ETHBalance_After = toBN(web3.utils.toBN(await web3.eth.getBalance(alice)))
      const balanceDiff = alice_ETHBalance_After.sub(alice_ETHBalance_Before)

      assert.isTrue(balanceDiff.eq(toBN(dec(1, 'ether'))))
    })

    it("withdrawColl(): applies pending rewards and updates user's L_ETH, L_EBTCDebt snapshots", async () => {
      // --- SETUP ---
      // Alice adds 15 ether, Bob adds 5 ether, Carol adds 1 ether
      await openTrove({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openTrove({ ICR: toBN(dec(3, 18)), extraParams: { from: alice, value: toBN(dec(100, 'ether')) } })
      await openTrove({ ICR: toBN(dec(3, 18)), extraParams: { from: bob, value: toBN(dec(100, 'ether')) } })
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: carol, value: toBN(dec(10, 'ether')) } })

      const whaleIndex = await sortedTroves.troveOfOwnerByIndex(whale,0)
      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
      const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)
      const carolIndex = await sortedTroves.troveOfOwnerByIndex(carol,0)

      const aliceCollBefore = await getTroveEntireColl(aliceIndex)
      const aliceDebtBefore = await getTroveEntireDebt(aliceIndex)
      const bobCollBefore = await getTroveEntireColl(bobIndex)
      const bobDebtBefore = await getTroveEntireDebt(bobIndex)

      // --- TEST ---

      // price drops to 1ETH:100EBTC, reducing Carol's ICR below MCR
      await priceFeed.setPrice('100000000000000000000');

      // close Carol's Trove, liquidating her 1 ether and 180EBTC.
      await troveManager.liquidate(carolIndex, { from: owner });

      const L_ETH = await troveManager.L_ETH()
      const L_EBTCDebt = await troveManager.L_EBTCDebt()

      // check Alice and Bob's reward snapshots are zero before they alter their Troves
      const alice_rewardSnapshot_Before = await troveManager.rewardSnapshots(aliceIndex)
      const alice_ETHrewardSnapshot_Before = alice_rewardSnapshot_Before[0]
      const alice_EBTCDebtRewardSnapshot_Before = alice_rewardSnapshot_Before[1]

      const bob_rewardSnapshot_Before = await troveManager.rewardSnapshots(bobIndex)
      const bob_ETHrewardSnapshot_Before = bob_rewardSnapshot_Before[0]
      const bob_EBTCDebtRewardSnapshot_Before = bob_rewardSnapshot_Before[1]

      assert.equal(alice_ETHrewardSnapshot_Before, 0)
      assert.equal(alice_EBTCDebtRewardSnapshot_Before, 0)
      assert.equal(bob_ETHrewardSnapshot_Before, 0)
      assert.equal(bob_EBTCDebtRewardSnapshot_Before, 0)

      // Check A and B have pending rewards
      const pendingCollReward_A = await troveManager.getPendingETHReward(aliceIndex)
      const pendingDebtReward_A = await troveManager.getPendingEBTCDebtReward(aliceIndex)
      const pendingCollReward_B = await troveManager.getPendingETHReward(bobIndex)
      const pendingDebtReward_B = await troveManager.getPendingEBTCDebtReward(bobIndex)
      for (reward of [pendingCollReward_A, pendingDebtReward_A, pendingCollReward_B, pendingDebtReward_B]) {
        assert.isTrue(reward.gt(toBN('0')))
      }

      // Alice and Bob withdraw from their Troves
      const aliceCollWithdrawal = toBN(dec(5, 'ether'))
      const bobCollWithdrawal = toBN(dec(1, 'ether'))

      await borrowerOperations.withdrawColl(aliceIndex, aliceCollWithdrawal, aliceIndex, aliceIndex, { from: alice })
      await borrowerOperations.withdrawColl(bobIndex, bobCollWithdrawal, bobIndex, bobIndex, { from: bob })

      // Check that both alice and Bob have had pending rewards applied in addition to their top-ups. 
      const aliceCollAfter = await getTroveEntireColl(aliceIndex)
      const aliceDebtAfter = await getTroveEntireDebt(aliceIndex)
      const bobCollAfter = await getTroveEntireColl(bobIndex)
      const bobDebtAfter = await getTroveEntireDebt(bobIndex)

      // Check rewards have been applied to troves
      th.assertIsApproximatelyEqual(aliceCollAfter, aliceCollBefore.add(pendingCollReward_A).sub(aliceCollWithdrawal), 10000)
      th.assertIsApproximatelyEqual(aliceDebtAfter, aliceDebtBefore.add(pendingDebtReward_A), 10000)
      th.assertIsApproximatelyEqual(bobCollAfter, bobCollBefore.add(pendingCollReward_B).sub(bobCollWithdrawal), 10000)
      th.assertIsApproximatelyEqual(bobDebtAfter, bobDebtBefore.add(pendingDebtReward_B), 10000)

      /* After top up, both Alice and Bob's snapshots of the rewards-per-unit-staked metrics should be updated
       to the latest values of L_ETH and L_EBTCDebt */
      const alice_rewardSnapshot_After = await troveManager.rewardSnapshots(aliceIndex)
      const alice_ETHrewardSnapshot_After = alice_rewardSnapshot_After[0]
      const alice_EBTCDebtRewardSnapshot_After = alice_rewardSnapshot_After[1]

      const bob_rewardSnapshot_After = await troveManager.rewardSnapshots(bobIndex)
      const bob_ETHrewardSnapshot_After = bob_rewardSnapshot_After[0]
      const bob_EBTCDebtRewardSnapshot_After = bob_rewardSnapshot_After[1]

      assert.isAtMost(th.getDifference(alice_ETHrewardSnapshot_After, L_ETH), 100)
      assert.isAtMost(th.getDifference(alice_EBTCDebtRewardSnapshot_After, L_EBTCDebt), 100)
      assert.isAtMost(th.getDifference(bob_ETHrewardSnapshot_After, L_ETH), 100)
      assert.isAtMost(th.getDifference(bob_EBTCDebtRewardSnapshot_After, L_EBTCDebt), 100)
    })

    // --- withdrawEBTC() ---

    it("withdrawEBTC(): reverts when withdrawal would leave trove with ICR < MCR", async () => {
      // alice creates a Trove and adds first collateral
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openTrove({ ICR: toBN(dec(10, 18)), extraParams: { from: bob } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
      const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)

      // Price drops
      await priceFeed.setPrice(dec(100, 18))
      const price = await priceFeed.getPrice()

      assert.isFalse(await troveManager.checkRecoveryMode(price))
      assert.isTrue((await troveManager.getCurrentICR(aliceIndex, price)).lt(toBN(dec(110, 16))))

      const EBTCwithdrawal = 1  // withdraw 1 wei EBTC

     await assertRevert(borrowerOperations.withdrawEBTC(aliceIndex, th._100pct, EBTCwithdrawal, aliceIndex, aliceIndex, { from: alice }), 
      "BorrowerOps: An operation that would result in ICR < MCR is not permitted")
    })

    it("withdrawEBTC(): decays a non-zero base rate", async () => {
      await openTrove({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })

      await openTrove({ extraEBTCAmount: toBN(dec(20, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openTrove({ extraEBTCAmount: toBN(dec(20, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openTrove({ extraEBTCAmount: toBN(dec(20, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })
      await openTrove({ extraEBTCAmount: toBN(dec(20, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: E } })

      const whaleIndex = await sortedTroves.troveOfOwnerByIndex(whale,0)
      const AIndex = await sortedTroves.troveOfOwnerByIndex(A,0)
      const BIndex = await sortedTroves.troveOfOwnerByIndex(B,0)
      const DIndex = await sortedTroves.troveOfOwnerByIndex(D,0)
      const EIndex = await sortedTroves.troveOfOwnerByIndex(E,0)

      const A_EBTCBal = await lusdToken.balanceOf(A)

      // Artificially set base rate to 5%
      await troveManager.setBaseRate(dec(5, 16))

      // Check baseRate is now non-zero
      const baseRate_1 = await troveManager.baseRate()
      assert.isTrue(baseRate_1.gt(toBN('0')))

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      // D withdraws EBTC
      await borrowerOperations.withdrawEBTC(DIndex, th._100pct, dec(1, 18), AIndex, AIndex, { from: D })

      // Check baseRate has decreased
      const baseRate_2 = await troveManager.baseRate()
      assert.isTrue(baseRate_2.lt(baseRate_1))

      // 1 hour passes
      th.fastForwardTime(3600, web3.currentProvider)

      // E withdraws EBTC
      await borrowerOperations.withdrawEBTC(EIndex, th._100pct, dec(1, 18), AIndex, AIndex, { from: E })

      const baseRate_3 = await troveManager.baseRate()
      assert.isTrue(baseRate_3.lt(baseRate_2))
    })

    it("withdrawEBTC(): reverts if max fee > 100%", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openTrove({ extraEBTCAmount: toBN(dec(20, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openTrove({ extraEBTCAmount: toBN(dec(40, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })
      await openTrove({ extraEBTCAmount: toBN(dec(40, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      const AIndex = await sortedTroves.troveOfOwnerByIndex(A,0)

      await assertRevert(borrowerOperations.withdrawEBTC(AIndex, dec(2, 18), dec(1, 18), AIndex, AIndex, { from: A }), "Max fee percentage must be between 0.5% and 100%")
      await assertRevert(borrowerOperations.withdrawEBTC(AIndex, '1000000000000000001', dec(1, 18), AIndex, AIndex, { from: A }), "Max fee percentage must be between 0.5% and 100%")
    })

    it("withdrawEBTC(): reverts if max fee < 0.5% in Normal mode", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openTrove({ extraEBTCAmount: toBN(dec(20, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openTrove({ extraEBTCAmount: toBN(dec(40, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })
      await openTrove({ extraEBTCAmount: toBN(dec(40, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      const AIndex = await sortedTroves.troveOfOwnerByIndex(A,0)

      await assertRevert(borrowerOperations.withdrawEBTC(AIndex, 0, dec(1, 18), AIndex, AIndex, { from: A }), "Max fee percentage must be between 0.5% and 100%")
      await assertRevert(borrowerOperations.withdrawEBTC(AIndex, 1, dec(1, 18), AIndex, AIndex, { from: A }), "Max fee percentage must be between 0.5% and 100%")
      await assertRevert(borrowerOperations.withdrawEBTC(AIndex, '4999999999999999', dec(1, 18), AIndex, AIndex, { from: A }), "Max fee percentage must be between 0.5% and 100%")
    })

    xit("withdrawEBTC(): reverts if fee exceeds max fee percentage", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(60, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openTrove({ extraEBTCAmount: toBN(dec(60, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openTrove({ extraEBTCAmount: toBN(dec(70, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })
      await openTrove({ extraEBTCAmount: toBN(dec(80, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })
      await openTrove({ extraEBTCAmount: toBN(dec(180, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: E } })

      const whaleIndex = await sortedTroves.troveOfOwnerByIndex(whale,0)
      const AIndex = await sortedTroves.troveOfOwnerByIndex(A,0)
      const BIndex = await sortedTroves.troveOfOwnerByIndex(B,0)
      const CIndex = await sortedTroves.troveOfOwnerByIndex(C,0)
      const DIndex = await sortedTroves.troveOfOwnerByIndex(D,0)
      const EIndex = await sortedTroves.troveOfOwnerByIndex(E,0)

      const totalSupply = await lusdToken.totalSupply()

      // Artificially make baseRate 5%
      await troveManager.setBaseRate(dec(5, 16))
      await troveManager.setLastFeeOpTimeToNow()

      let baseRate = await troveManager.baseRate() // expect 5% base rate
      assert.equal(baseRate, dec(5, 16))

      // 100%: 1e18,  10%: 1e17,  1%: 1e16,  0.1%: 1e15
      // 5%: 5e16
      // 0.5%: 5e15
      // actual: 0.5%, 5e15


      // EBTCFee:                  15000000558793542
      // absolute _fee:            15000000558793542
      // actual feePercentage:      5000000186264514
      // user's _maxFeePercentage: 49999999999999999

      const lessThan5pct = '49999999999999999'
      await assertRevert(borrowerOperations.withdrawEBTC(AIndex, lessThan5pct, dec(3, 18), AIndex, AIndex, { from: A }), "Fee exceeded provided maximum")

      baseRate = await troveManager.baseRate() // expect 5% base rate
      assert.equal(baseRate, dec(5, 16))
      // Attempt with maxFee 1%
      await assertRevert(borrowerOperations.withdrawEBTC(BIndex, dec(1, 16), dec(1, 18), AIndex, AIndex, { from: B }), "Fee exceeded provided maximum")

      baseRate = await troveManager.baseRate()  // expect 5% base rate
      assert.equal(baseRate, dec(5, 16))
      // Attempt with maxFee 3.754%
      await assertRevert(borrowerOperations.withdrawEBTC(CIndex, dec(3754, 13), dec(1, 18), AIndex, AIndex, { from: C }), "Fee exceeded provided maximum")

      baseRate = await troveManager.baseRate()  // expect 5% base rate
      assert.equal(baseRate, dec(5, 16))
      // Attempt with maxFee 0.5%%
      await assertRevert(borrowerOperations.withdrawEBTC(DIndex, dec(5, 15), dec(1, 18), AIndex, AIndex, { from: D }), "Fee exceeded provided maximum")
    })

    xit("withdrawEBTC(): succeeds when fee is less than max fee percentage", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(60, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openTrove({ extraEBTCAmount: toBN(dec(60, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openTrove({ extraEBTCAmount: toBN(dec(70, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })
      await openTrove({ extraEBTCAmount: toBN(dec(80, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })
      await openTrove({ extraEBTCAmount: toBN(dec(180, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: E } })

      const AIndex = await sortedTroves.troveOfOwnerByIndex(A,0)
      const BIndex = await sortedTroves.troveOfOwnerByIndex(B,0)
      const CIndex = await sortedTroves.troveOfOwnerByIndex(C,0)
      const DIndex = await sortedTroves.troveOfOwnerByIndex(D,0)
      const EIndex = await sortedTroves.troveOfOwnerByIndex(E,0)

      const totalSupply = await lusdToken.totalSupply()

      // Artificially make baseRate 5%
      await troveManager.setBaseRate(dec(5, 16))
      await troveManager.setLastFeeOpTimeToNow()

      let baseRate = await troveManager.baseRate() // expect 5% base rate
      assert.isTrue(baseRate.eq(toBN(dec(5, 16))))

      // Attempt with maxFee > 5%
      const moreThan5pct = '50000000000000001'
      const tx1 = await borrowerOperations.withdrawEBTC(AIndex, moreThan5pct, dec(1, 18), AIndex, AIndex, { from: A })
      assert.isTrue(tx1.receipt.status)

      baseRate = await troveManager.baseRate() // expect 5% base rate
      assert.equal(baseRate, dec(5, 16))

      // Attempt with maxFee = 5%
      const tx2 = await borrowerOperations.withdrawEBTC(BIndex, dec(5, 16), dec(1, 18), AIndex, AIndex, { from: B })
      assert.isTrue(tx2.receipt.status)

      baseRate = await troveManager.baseRate() // expect 5% base rate
      assert.equal(baseRate, dec(5, 16))

      // Attempt with maxFee 10%
      const tx3 = await borrowerOperations.withdrawEBTC(CIndex, dec(1, 17), dec(1, 18), AIndex, AIndex, { from: C })
      assert.isTrue(tx3.receipt.status)

      baseRate = await troveManager.baseRate() // expect 5% base rate
      assert.equal(baseRate, dec(5, 16))

      // Attempt with maxFee 37.659%
      const tx4 = await borrowerOperations.withdrawEBTC(DIndex, dec(37659, 13), dec(1, 18), AIndex, AIndex, { from: D })
      assert.isTrue(tx4.receipt.status)

      // Attempt with maxFee 100%
      const tx5 = await borrowerOperations.withdrawEBTC(EIndex, dec(1, 18), dec(1, 18), AIndex, AIndex, { from: E })
      assert.isTrue(tx5.receipt.status)
    })

    xit("withdrawEBTC(): doesn't change base rate if it is already zero", async () => {
      await openTrove({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })

      await openTrove({ extraEBTCAmount: toBN(dec(30, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openTrove({ extraEBTCAmount: toBN(dec(40, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openTrove({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })
      await openTrove({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })
      await openTrove({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: E } })

      const AIndex = await sortedTroves.troveOfOwnerByIndex(A,0)
      const BIndex = await sortedTroves.troveOfOwnerByIndex(B,0)
      const CIndex = await sortedTroves.troveOfOwnerByIndex(C,0)
      const DIndex = await sortedTroves.troveOfOwnerByIndex(D,0)
      const EIndex = await sortedTroves.troveOfOwnerByIndex(E,0)

      // Check baseRate is zero
      const baseRate_1 = await troveManager.baseRate()
      assert.equal(baseRate_1, '0')

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      // D withdraws EBTC
      await borrowerOperations.withdrawEBTC(DIndex, th._100pct, dec(37, 18), AIndex, AIndex, { from: D })

      // Check baseRate is still 0
      const baseRate_2 = await troveManager.baseRate()
      assert.equal(baseRate_2, '0')

      // 1 hour passes
      th.fastForwardTime(3600, web3.currentProvider)

      // E opens trove 
      await borrowerOperations.withdrawEBTC(EIndex, th._100pct, dec(12, 18), AIndex, AIndex, { from: E })

      const baseRate_3 = await troveManager.baseRate()
      assert.equal(baseRate_3, '0')
    })

    it("withdrawEBTC(): lastFeeOpTime doesn't update if less time than decay interval has passed since the last fee operation", async () => {
      await openTrove({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })

      await openTrove({ extraEBTCAmount: toBN(dec(30, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openTrove({ extraEBTCAmount: toBN(dec(40, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openTrove({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })

      const CIndex = await sortedTroves.troveOfOwnerByIndex(C,0)

      // Artificially make baseRate 5%
      await troveManager.setBaseRate(dec(5, 16))
      await troveManager.setLastFeeOpTimeToNow()

      // Check baseRate is now non-zero
      const baseRate_1 = await troveManager.baseRate()
      assert.isTrue(baseRate_1.gt(toBN('0')))

      const lastFeeOpTime_1 = await troveManager.lastFeeOperationTime()

      // 10 seconds pass
      th.fastForwardTime(10, web3.currentProvider)

      // Borrower C triggers a fee
      await borrowerOperations.withdrawEBTC(CIndex, th._100pct, dec(1, 18), CIndex, CIndex, { from: C })

      const lastFeeOpTime_2 = await troveManager.lastFeeOperationTime()

      // Check that the last fee operation time did not update, as borrower D's debt issuance occured
      // since before minimum interval had passed 
      assert.isTrue(lastFeeOpTime_2.eq(lastFeeOpTime_1))

      // 60 seconds passes
      th.fastForwardTime(60, web3.currentProvider)

      // Check that now, at least one minute has passed since lastFeeOpTime_1
      const timeNow = await th.getLatestBlockTimestamp(web3)
      assert.isTrue(toBN(timeNow).sub(lastFeeOpTime_1).gte(60))

      // Borrower C triggers a fee
      await borrowerOperations.withdrawEBTC(CIndex, th._100pct, dec(1, 18), CIndex, CIndex, { from: C })

      const lastFeeOpTime_3 = await troveManager.lastFeeOperationTime()

      // Check that the last fee operation time DID update, as borrower's debt issuance occured
      // after minimum interval had passed 
      assert.isTrue(lastFeeOpTime_3.gt(lastFeeOpTime_1))
    })


    xit("withdrawEBTC(): borrower can't grief the baseRate and stop it decaying by issuing debt at higher frequency than the decay granularity", async () => {
      await openTrove({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openTrove({ extraEBTCAmount: toBN(dec(30, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openTrove({ extraEBTCAmount: toBN(dec(40, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openTrove({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })

      // Artificially make baseRate 5%
      await troveManager.setBaseRate(dec(5, 16))
      await troveManager.setLastFeeOpTimeToNow()

      // Check baseRate is now non-zero
      const baseRate_1 = await troveManager.baseRate()
      assert.isTrue(baseRate_1.gt(toBN('0')))

      // 30 seconds pass
      th.fastForwardTime(30, web3.currentProvider)

      // Borrower C triggers a fee, before decay interval has passed
      await borrowerOperations.withdrawEBTC(th._100pct, dec(1, 18), C, C, { from: C })

      // 30 seconds pass
      th.fastForwardTime(30, web3.currentProvider)

      // Borrower C triggers another fee
      await borrowerOperations.withdrawEBTC(th._100pct, dec(1, 18), C, C, { from: C })

      // Check base rate has decreased even though Borrower tried to stop it decaying
      const baseRate_2 = await troveManager.baseRate()
      assert.isTrue(baseRate_2.lt(baseRate_1))
    })

    xit("withdrawEBTC(): borrowing at non-zero base rate sends EBTC fee to LQTY staking contract", async () => {
      // time fast-forwards 1 year, and multisig stakes 1 LQTY
      await th.fastForwardTime(timeValues.SECONDS_IN_ONE_YEAR, web3.currentProvider)
      await lqtyToken.approve(lqtyStaking.address, dec(1, 18), { from: multisig })
      await lqtyStaking.stake(dec(1, 18), { from: multisig })

      // Check LQTY EBTC balance before == 0
      const lqtyStaking_EBTCBalance_Before = await lusdToken.balanceOf(lqtyStaking.address)
      assert.equal(lqtyStaking_EBTCBalance_Before, '0')

      await openTrove({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openTrove({ extraEBTCAmount: toBN(dec(30, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openTrove({ extraEBTCAmount: toBN(dec(40, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openTrove({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })
      await openTrove({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      // Artificially make baseRate 5%
      await troveManager.setBaseRate(dec(5, 16))
      await troveManager.setLastFeeOpTimeToNow()

      // Check baseRate is now non-zero
      const baseRate_1 = await troveManager.baseRate()
      assert.isTrue(baseRate_1.gt(toBN('0')))

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      // D withdraws EBTC
      await borrowerOperations.withdrawEBTC(th._100pct, dec(37, 18), C, C, { from: D })

      // Check LQTY EBTC balance after has increased
      const lqtyStaking_EBTCBalance_After = await lusdToken.balanceOf(lqtyStaking.address)
      assert.isTrue(lqtyStaking_EBTCBalance_After.gt(lqtyStaking_EBTCBalance_Before))
    })

    if (!withProxy) { // TODO: use rawLogs instead of logs
      xit("withdrawEBTC(): borrowing at non-zero base records the (drawn debt + fee) on the Trove struct", async () => {
        // time fast-forwards 1 year, and multisig stakes 1 LQTY
        await th.fastForwardTime(timeValues.SECONDS_IN_ONE_YEAR, web3.currentProvider)
        await lqtyToken.approve(lqtyStaking.address, dec(1, 18), { from: multisig })
        await lqtyStaking.stake(dec(1, 18), { from: multisig })

        await openTrove({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
        await openTrove({ extraEBTCAmount: toBN(dec(30, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
        await openTrove({ extraEBTCAmount: toBN(dec(40, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
        await openTrove({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })
        await openTrove({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })
        const D_debtBefore = await getTroveEntireDebt(D)

        // Artificially make baseRate 5%
        await troveManager.setBaseRate(dec(5, 16))
        await troveManager.setLastFeeOpTimeToNow()

        // Check baseRate is now non-zero
        const baseRate_1 = await troveManager.baseRate()
        assert.isTrue(baseRate_1.gt(toBN('0')))

        // 2 hours pass
        th.fastForwardTime(7200, web3.currentProvider)

        // D withdraws EBTC
        const withdrawal_D = toBN(dec(37, 18))
        const withdrawalTx = await borrowerOperations.withdrawEBTC(th._100pct, toBN(dec(37, 18)), D, D, { from: D })

        const emittedFee = toBN(th.getEBTCFeeFromEBTCBorrowingEvent(withdrawalTx))
        assert.isTrue(emittedFee.gt(toBN('0')))

        const newDebt = (await troveManager.Troves(D))[0]

        // Check debt on Trove struct equals initial debt + withdrawal + emitted fee
        th.assertIsApproximatelyEqual(newDebt, D_debtBefore.add(withdrawal_D).add(emittedFee), 10000)
      })
    }

    xit("withdrawEBTC(): Borrowing at non-zero base rate increases the LQTY staking contract EBTC fees-per-unit-staked", async () => {
      // time fast-forwards 1 year, and multisig stakes 1 LQTY
      await th.fastForwardTime(timeValues.SECONDS_IN_ONE_YEAR, web3.currentProvider)
      await lqtyToken.approve(lqtyStaking.address, dec(1, 18), { from: multisig })
      await lqtyStaking.stake(dec(1, 18), { from: multisig })

      // Check LQTY contract EBTC fees-per-unit-staked is zero
      const F_EBTC_Before = await lqtyStaking.F_EBTC()
      assert.equal(F_EBTC_Before, '0')

      await openTrove({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openTrove({ extraEBTCAmount: toBN(dec(30, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openTrove({ extraEBTCAmount: toBN(dec(40, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openTrove({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })
      await openTrove({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      // Artificially make baseRate 5%
      await troveManager.setBaseRate(dec(5, 16))
      await troveManager.setLastFeeOpTimeToNow()

      // Check baseRate is now non-zero
      const baseRate_1 = await troveManager.baseRate()
      assert.isTrue(baseRate_1.gt(toBN('0')))

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      // D withdraws EBTC
      await borrowerOperations.withdrawEBTC(th._100pct, toBN(dec(37, 18)), D, D, { from: D })

      // Check LQTY contract EBTC fees-per-unit-staked has increased
      const F_EBTC_After = await lqtyStaking.F_EBTC()
      assert.isTrue(F_EBTC_After.gt(F_EBTC_Before))
    })

    xit("withdrawEBTC(): Borrowing at non-zero base rate sends requested amount to the user", async () => {
      // time fast-forwards 1 year, and multisig stakes 1 LQTY
      await th.fastForwardTime(timeValues.SECONDS_IN_ONE_YEAR, web3.currentProvider)
      await lqtyToken.approve(lqtyStaking.address, dec(1, 18), { from: multisig })
      await lqtyStaking.stake(dec(1, 18), { from: multisig })

      // Check LQTY Staking contract balance before == 0
      const lqtyStaking_EBTCBalance_Before = await lusdToken.balanceOf(lqtyStaking.address)
      assert.equal(lqtyStaking_EBTCBalance_Before, '0')

      await openTrove({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openTrove({ extraEBTCAmount: toBN(dec(30, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openTrove({ extraEBTCAmount: toBN(dec(40, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openTrove({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })
      await openTrove({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      // Artificially make baseRate 5%
      await troveManager.setBaseRate(dec(5, 16))
      await troveManager.setLastFeeOpTimeToNow()

      // Check baseRate is now non-zero
      const baseRate_1 = await troveManager.baseRate()
      assert.isTrue(baseRate_1.gt(toBN('0')))

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      const D_EBTCBalanceBefore = await lusdToken.balanceOf(D)

      // D withdraws EBTC
      const D_EBTCRequest = toBN(dec(37, 18))
      await borrowerOperations.withdrawEBTC(th._100pct, D_EBTCRequest, D, D, { from: D })

      // Check LQTY staking EBTC balance has increased
      const lqtyStaking_EBTCBalance_After = await lusdToken.balanceOf(lqtyStaking.address)
      assert.isTrue(lqtyStaking_EBTCBalance_After.gt(lqtyStaking_EBTCBalance_Before))

      // Check D's EBTC balance now equals their initial balance plus request EBTC
      const D_EBTCBalanceAfter = await lusdToken.balanceOf(D)
      assert.isTrue(D_EBTCBalanceAfter.eq(D_EBTCBalanceBefore.add(D_EBTCRequest)))
    })

    xit("withdrawEBTC(): Borrowing at zero base rate changes EBTC fees-per-unit-staked", async () => {
      await openTrove({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openTrove({ extraEBTCAmount: toBN(dec(30, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openTrove({ extraEBTCAmount: toBN(dec(40, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openTrove({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })
      await openTrove({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      // Check baseRate is zero
      const baseRate_1 = await troveManager.baseRate()
      assert.equal(baseRate_1, '0')

      // A artificially receives LQTY, then stakes it
      await lqtyToken.unprotectedMint(A, dec(100, 18))
      await lqtyStaking.stake(dec(100, 18), { from: A })

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      // Check LQTY EBTC balance before == 0
      const F_EBTC_Before = await lqtyStaking.F_EBTC()
      assert.equal(F_EBTC_Before, '0')

      // D withdraws EBTC
      await borrowerOperations.withdrawEBTC(th._100pct, dec(37, 18), D, D, { from: D })

      // Check LQTY EBTC balance after > 0
      const F_EBTC_After = await lqtyStaking.F_EBTC()
      assert.isTrue(F_EBTC_After.gt('0'))
    })

    xit("withdrawEBTC(): Borrowing at zero base rate sends debt request to user", async () => {
      await openTrove({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openTrove({ extraEBTCAmount: toBN(dec(30, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openTrove({ extraEBTCAmount: toBN(dec(40, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openTrove({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })
      await openTrove({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      // Check baseRate is zero
      const baseRate_1 = await troveManager.baseRate()
      assert.equal(baseRate_1, '0')

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      const D_EBTCBalanceBefore = await lusdToken.balanceOf(D)

      // D withdraws EBTC
      const D_EBTCRequest = toBN(dec(37, 18))
      await borrowerOperations.withdrawEBTC(th._100pct, dec(37, 18), D, D, { from: D })

      // Check D's EBTC balance now equals their requested EBTC
      const D_EBTCBalanceAfter = await lusdToken.balanceOf(D)

      // Check D's trove debt == D's EBTC balance + liquidation reserve
      assert.isTrue(D_EBTCBalanceAfter.eq(D_EBTCBalanceBefore.add(D_EBTCRequest)))
    })

    it("withdrawEBTC(): reverts when calling address does not have active trove", async () => {
      await openTrove({ ICR: toBN(dec(10, 18)), extraParams: { from: alice } })
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: bob } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)  
      const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)
      const carolIndex = th.RANDOM_INDEX

      // Bob successfully withdraws EBTC
      const txBob = await borrowerOperations.withdrawEBTC(bobIndex, th._100pct, dec(100, 18), bobIndex, bobIndex, { from: bob })
      assert.isTrue(txBob.receipt.status)

      // Carol with no active trove attempts to withdraw EBTC
      try {
        const txCarol = await borrowerOperations.withdrawEBTC(carolIndex, th._100pct, dec(100, 18), bobIndex, bobIndex, { from: carol })
        assert.isFalse(txCarol.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    it("withdrawEBTC(): reverts when requested withdrawal amount is zero EBTC", async () => {
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: bob } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)  
      const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)
      const carolIndex = th.RANDOM_INDEX

      // Bob successfully withdraws 1e-18 EBTC
      const txBob = await borrowerOperations.withdrawEBTC(bobIndex, th._100pct, 1, bobIndex, bobIndex, { from: bob })
      assert.isTrue(txBob.receipt.status)

      // Alice attempts to withdraw 0 EBTC
      try {
        const txAlice = await borrowerOperations.withdrawEBTC(aliceIndex, th._100pct, 0, aliceIndex, aliceIndex, { from: alice })
        assert.isFalse(txAlice.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    it("withdrawEBTC(): reverts when system is in Recovery Mode", async () => {
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: bob } })
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: carol } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)  
      const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)
      const carolIndex = await sortedTroves.troveOfOwnerByIndex(carol,0)

      assert.isFalse(await th.checkRecoveryMode(contracts))

      // Withdrawal possible when recoveryMode == false
      const txAlice = await borrowerOperations.withdrawEBTC(aliceIndex, th._100pct, dec(100, 18), aliceIndex, aliceIndex, { from: alice })
      assert.isTrue(txAlice.receipt.status)

      await priceFeed.setPrice('50000000000000000000')

      assert.isTrue(await th.checkRecoveryMode(contracts))

      //Check EBTC withdrawal impossible when recoveryMode == true
      try {
        const txBob = await borrowerOperations.withdrawEBTC(bobIndex, th._100pct, 1, bobIndex, bobIndex, { from: bob })
        assert.isFalse(txBob.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    it("withdrawEBTC(): reverts when withdrawal would bring the trove's ICR < MCR", async () => {
      await openTrove({ ICR: toBN(dec(10, 18)), extraParams: { from: alice } })
      await openTrove({ ICR: toBN(dec(11, 17)), extraParams: { from: bob } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)  
      const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)

      // Bob tries to withdraw EBTC that would bring his ICR < MCR
      try {
        const txBob = await borrowerOperations.withdrawEBTC(bobIndex, th._100pct, 1, bobIndex, bobIndex, { from: bob })
        assert.isFalse(txBob.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    it("withdrawEBTC(): reverts when a withdrawal would cause the TCR of the system to fall below the CCR", async () => {
      await priceFeed.setPrice(dec(100, 18))
      const price = await priceFeed.getPrice()

      // Alice and Bob creates troves with 150% ICR.  System TCR = 150%.
      await openTrove({ ICR: toBN(dec(15, 17)), extraParams: { from: alice } })
      await openTrove({ ICR: toBN(dec(15, 17)), extraParams: { from: bob } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)  
      const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)

      var TCR = (await th.getTCR(contracts)).toString()
      assert.equal(TCR, '1500000000000000000')

      // Bob attempts to withdraw 1 EBTC.
      // System TCR would be: ((3+3) * 100 ) / (200+201) = 600/401 = 149.62%, i.e. below CCR of 150%.
      try {
        const txBob = await borrowerOperations.withdrawEBTC(bobIndex, th._100pct, dec(1, 18), bobIndex, bobIndex, { from: bob })
        assert.isFalse(txBob.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    it("withdrawEBTC(): reverts if system is in Recovery Mode", async () => {
      // --- SETUP ---
      await openTrove({ ICR: toBN(dec(15, 17)), extraParams: { from: alice } })
      await openTrove({ ICR: toBN(dec(15, 17)), extraParams: { from: bob } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)  
      const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)

      // --- TEST ---

      // price drops to 1ETH:150EBTC, reducing TCR below 150%
      await priceFeed.setPrice('150000000000000000000');
      assert.isTrue((await th.getTCR(contracts)).lt(toBN(dec(15, 17))))

      try {
        const txData = await borrowerOperations.withdrawEBTC(aliceIndex, th._100pct, '200', aliceIndex, aliceIndex, { from: alice })
        assert.isFalse(txData.receipt.status)
      } catch (err) {
        assert.include(err.message, 'revert')
      }
    })

    it("withdrawEBTC(): increases the Trove's EBTC debt by the correct amount", async () => {
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)  

      // check before
      const aliceDebtBefore = await getTroveEntireDebt(aliceIndex)
      assert.isTrue(aliceDebtBefore.gt(toBN(0)))

      await borrowerOperations.withdrawEBTC(aliceIndex, th._100pct, await getNetBorrowingAmount(100), aliceIndex, aliceIndex, { from: alice })

      // check after
      const aliceDebtAfter = await getTroveEntireDebt(aliceIndex)
      th.assertIsApproximatelyEqual(aliceDebtAfter, aliceDebtBefore.add(toBN(100)))
    })

    it("withdrawEBTC(): increases EBTC debt in ActivePool by correct amount", async () => {
      await openTrove({ ICR: toBN(dec(10, 18)), extraParams: { from: alice, value: toBN(dec(100, 'ether')) } })
      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)  

      const aliceDebtBefore = await getTroveEntireDebt(aliceIndex)
      assert.isTrue(aliceDebtBefore.gt(toBN(0)))

      // check before
      const activePool_EBTC_Before = await activePool.getEBTCDebt()
      assert.isTrue(activePool_EBTC_Before.eq(aliceDebtBefore))

      await borrowerOperations.withdrawEBTC(aliceIndex, th._100pct, await getNetBorrowingAmount(dec(10000, 18)), aliceIndex, aliceIndex, { from: alice })

      // check after
      const activePool_EBTC_After = await activePool.getEBTCDebt()
      th.assertIsApproximatelyEqual(activePool_EBTC_After, activePool_EBTC_Before.add(toBN(dec(10000, 18))))
    })

    it("withdrawEBTC(): increases user EBTCToken balance by correct amount", async () => {
      await openTrove({ extraParams: { value: toBN(dec(100, 'ether')), from: alice } })
      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)  

      // check before
      const alice_EBTCTokenBalance_Before = await lusdToken.balanceOf(alice)
      assert.isTrue(alice_EBTCTokenBalance_Before.gt(toBN('0')))

      await borrowerOperations.withdrawEBTC(aliceIndex, th._100pct, dec(10000, 18), aliceIndex, aliceIndex, { from: alice })

      // check after
      const alice_EBTCTokenBalance_After = await lusdToken.balanceOf(alice)
      assert.isTrue(alice_EBTCTokenBalance_After.eq(alice_EBTCTokenBalance_Before.add(toBN(dec(10000, 18)))))
    })

    // --- repayEBTC() ---
    it("repayEBTC(): reverts when repayment would leave trove with ICR < MCR", async () => {
      // alice creates a Trove and adds first collateral
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openTrove({ ICR: toBN(dec(10, 18)), extraParams: { from: bob } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)  
      const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)

      // Price drops
      await priceFeed.setPrice(dec(100, 18))
      const price = await priceFeed.getPrice()

      assert.isFalse(await troveManager.checkRecoveryMode(price))
      assert.isTrue((await troveManager.getCurrentICR(aliceIndex, price)).lt(toBN(dec(110, 16))))

      const EBTCRepayment = 1  // 1 wei repayment

     await assertRevert(borrowerOperations.repayEBTC(aliceIndex, EBTCRepayment, aliceIndex, aliceIndex, { from: alice }), 
      "BorrowerOps: An operation that would result in ICR < MCR is not permitted")
    })

    it("repayEBTC(): Succeeds when it would leave trove with net debt >= minimum net debt", async () => {
      // Make the EBTC request 2 wei above min net debt to correct for floor division, and make net debt = min net debt + 1 wei
      await borrowerOperations.openTrove(th._100pct, await getNetBorrowingAmount(MIN_NET_DEBT.add(toBN('2'))), A, A, { from: A, value: dec(100, 30) })
      const AIndex = await sortedTroves.troveOfOwnerByIndex(A,0)

      const repayTxA = await borrowerOperations.repayEBTC(AIndex, 1, AIndex, AIndex, { from: A })
      assert.isTrue(repayTxA.receipt.status)

      await borrowerOperations.openTrove(th._100pct, dec(20, 25), B, B, { from: B, value: dec(100, 30) })
      const BIndex = await sortedTroves.troveOfOwnerByIndex(B,0)

      const repayTxB = await borrowerOperations.repayEBTC(BIndex, dec(19, 25), BIndex, BIndex, { from: B })
      assert.isTrue(repayTxB.receipt.status)
    })

    it("repayEBTC(): reverts when it would leave trove with net debt < minimum net debt", async () => {
      // Make the EBTC request 2 wei above min net debt to correct for floor division, and make net debt = min net debt + 1 wei
      await borrowerOperations.openTrove(th._100pct, await getNetBorrowingAmount(MIN_NET_DEBT.add(toBN('2'))), A, A, { from: A, value: dec(100, 30) })
      const AIndex = await sortedTroves.troveOfOwnerByIndex(A,0)

      const repayTxAPromise = borrowerOperations.repayEBTC(AIndex, 2, AIndex, AIndex, { from: A })
      await assertRevert(repayTxAPromise, "BorrowerOps: Trove's net debt must be greater than minimum")
    })

    it("adjustTrove(): Reverts if repaid amount is greater than current debt", async () => {
      const { totalDebt } = await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })
      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)  
      
      EBTC_GAS_COMPENSATION = await borrowerOperations.EBTC_GAS_COMPENSATION()
      const repayAmount = totalDebt.sub(EBTC_GAS_COMPENSATION).add(toBN(1))

      await openTrove({ extraEBTCAmount: repayAmount, ICR: toBN(dec(150, 16)), extraParams: { from: bob } })
      const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)

      await lusdToken.transfer(alice, repayAmount, { from: bob })

      await assertRevert(borrowerOperations.adjustTrove(aliceIndex, th._100pct, 0, repayAmount, false, aliceIndex, aliceIndex, { from: alice }),
                         "SafeMath: subtraction overflow")
    })

    xit("repayEBTC(): reverts when calling address does not own trove index supplied", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: bob } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
      const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)  

      // Bob successfully repays some EBTC
      const txBob = await borrowerOperations.repayEBTC(bobIndex, dec(10, 18), bobIndex, bobIndex, { from: bob })
      assert.isTrue(txBob.receipt.status)

      // Carol with no active trove attempts to repayEBTC
      try {
        const txCarol = await borrowerOperations.repayEBTC(bobIndex, dec(10, 18), bobIndex, bobIndex, { from: carol })
        assert.isFalse(txCarol.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    it("repayEBTC(): reverts when attempted repayment is > the debt of the trove", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: bob } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
      const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)  

      const aliceDebt = await getTroveEntireDebt(aliceIndex)

      // Bob successfully repays some EBTC
      const txBob = await borrowerOperations.repayEBTC(bobIndex, dec(10, 18), bobIndex, bobIndex, { from: bob })
      assert.isTrue(txBob.receipt.status)

      // Alice attempts to repay more than her debt
      try {
        const txAlice = await borrowerOperations.repayEBTC(aliceIndex, aliceDebt.add(toBN(dec(1, 18))), aliceIndex, aliceIndex, { from: alice })
        assert.isFalse(txAlice.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    //repayEBTC: reduces EBTC debt in Trove
    it("repayEBTC(): reduces the Trove's EBTC debt by the correct amount", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: bob } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
      const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)

      const aliceDebtBefore = await getTroveEntireDebt(aliceIndex)
      assert.isTrue(aliceDebtBefore.gt(toBN('0')))

      await borrowerOperations.repayEBTC(aliceIndex, aliceDebtBefore.div(toBN(10)), aliceIndex, aliceIndex, { from: alice })  // Repays 1/10 her debt

      const aliceDebtAfter = await getTroveEntireDebt(aliceIndex)
      assert.isTrue(aliceDebtAfter.gt(toBN('0')))

      th.assertIsApproximatelyEqual(aliceDebtAfter, aliceDebtBefore.mul(toBN(9)).div(toBN(10)))  // check 9/10 debt remaining
    })

    it("repayEBTC(): decreases EBTC debt in ActivePool by correct amount", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: bob } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
      const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)

      const aliceDebtBefore = await getTroveEntireDebt(aliceIndex)
      assert.isTrue(aliceDebtBefore.gt(toBN('0')))

      // Check before
      const activePool_EBTC_Before = await activePool.getEBTCDebt()
      assert.isTrue(activePool_EBTC_Before.gt(toBN('0')))

      await borrowerOperations.repayEBTC(aliceIndex, aliceDebtBefore.div(toBN(10)), aliceIndex, aliceIndex, { from: alice })  // Repays 1/10 her debt

      // check after
      const activePool_EBTC_After = await activePool.getEBTCDebt()
      th.assertIsApproximatelyEqual(activePool_EBTC_After, activePool_EBTC_Before.sub(aliceDebtBefore.div(toBN(10))))
    })

    it("repayEBTC(): decreases user EBTCToken balance by correct amount", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: bob } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
      const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)

      const aliceDebtBefore = await getTroveEntireDebt(aliceIndex)
      assert.isTrue(aliceDebtBefore.gt(toBN('0')))

      // check before
      const alice_EBTCTokenBalance_Before = await lusdToken.balanceOf(alice)
      assert.isTrue(alice_EBTCTokenBalance_Before.gt(toBN('0')))

      await borrowerOperations.repayEBTC(aliceIndex, aliceDebtBefore.div(toBN(10)), aliceIndex, aliceIndex, { from: alice })  // Repays 1/10 her debt

      // check after
      const alice_EBTCTokenBalance_After = await lusdToken.balanceOf(alice)
      th.assertIsApproximatelyEqual(alice_EBTCTokenBalance_After, alice_EBTCTokenBalance_Before.sub(aliceDebtBefore.div(toBN(10))))
    })

    //TODO: fix
    xit("repayEBTC(): can repay debt in Recovery Mode", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: bob } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
      const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)

      const aliceDebtBefore = await getTroveEntireDebt(aliceIndex)
      assert.isTrue(aliceDebtBefore.gt(toBN('0')))

      assert.isFalse(await th.checkRecoveryMode(contracts))

      await priceFeed.setPrice('105000000000000000000')

      assert.isTrue(await th.checkRecoveryMode(contracts))

      const tx = await borrowerOperations.repayEBTC(aliceIndex, aliceDebtBefore.div(toBN(10)), aliceIndex, aliceIndex, { from: alice })
      assert.isTrue(tx.receipt.status)

      // Check Alice's debt: 110 (initial) - 50 (repaid)
      const aliceDebtAfter = await getTroveEntireDebt(alice)
      th.assertIsApproximatelyEqual(aliceDebtAfter, aliceDebtBefore.mul(toBN(9)).div(toBN(10)))
    })

    it("repayEBTC(): Reverts if borrower has insufficient EBTC balance to cover his debt repayment", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      
      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
      const BIndex = await sortedTroves.troveOfOwnerByIndex(B,0)

      const bobBalBefore = await lusdToken.balanceOf(B)
      assert.isTrue(bobBalBefore.gt(toBN('0')))

      // Bob transfers all but 5 of his EBTC to Carol
      await lusdToken.transfer(C, bobBalBefore.sub((toBN(dec(5, 18)))), { from: B })

      //Confirm B's EBTC balance has decreased to 5 EBTC
      const bobBalAfter = await lusdToken.balanceOf(B)

      assert.isTrue(bobBalAfter.eq(toBN(dec(5, 18))))
      
      // Bob tries to repay 6 EBTC
      const repayEBTCPromise_B = borrowerOperations.repayEBTC(BIndex, toBN(dec(6, 18)), BIndex, BIndex, { from: B })

      await assertRevert(repayEBTCPromise_B, "Caller doesnt have enough EBTC to make repayment")
    })

    // --- adjustTrove() ---

    it("adjustTrove(): reverts when adjustment would leave trove with ICR < MCR", async () => {
      // alice creates a Trove and adds first collateral
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openTrove({ ICR: toBN(dec(10, 18)), extraParams: { from: bob } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
      const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)

      // Price drops
      await priceFeed.setPrice(dec(100, 18))
      const price = await priceFeed.getPrice()

      assert.isFalse(await troveManager.checkRecoveryMode(price))
      assert.isTrue((await troveManager.getCurrentICR(aliceIndex, price)).lt(toBN(dec(110, 16))))

      const EBTCRepayment = 1  // 1 wei repayment
      const collTopUp = 1

     await assertRevert(borrowerOperations.adjustTrove(aliceIndex, th._100pct, 0, EBTCRepayment, false, aliceIndex, aliceIndex, { from: alice, value: collTopUp }), 
      "BorrowerOps: An operation that would result in ICR < MCR is not permitted")
    })

    xit("adjustTrove(): reverts if max fee < 0.5% in Normal mode", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      const AIndex = await sortedTroves.troveOfOwnerByIndex(A,0)

      await assertRevert(borrowerOperations.adjustTrove(AIndex, 0, 0, dec(1, 18), true, AIndex, AIndex, { from: A, value: dec(2, 16) }), "Max fee percentage must be between 0.5% and 100%")
      await assertRevert(borrowerOperations.adjustTrove(AIndex, 1, 0, dec(1, 18), true, AIndex, AIndex, { from: A, value: dec(2, 16) }), "Max fee percentage must be between 0.5% and 100%")
      await assertRevert(borrowerOperations.adjustTrove(AIndex, '4999999999999999', 0, dec(1, 18), true, AIndex, AIndex, { from: A, value: dec(2, 16) }), "Max fee percentage must be between 0.5% and 100%")
    })

    xit("adjustTrove(): allows max fee < 0.5% in Recovery mode", async () => {
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: whale, value: toBN(dec(100, 'ether')) } })

      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })

      await priceFeed.setPrice(dec(120, 18))
      assert.isTrue(await th.checkRecoveryMode(contracts))

      await borrowerOperations.adjustTrove(0, 0, dec(1, 9), true, A, A, { from: A, value: dec(300, 18) })
      await priceFeed.setPrice(dec(1, 18))
      assert.isTrue(await th.checkRecoveryMode(contracts))
      await borrowerOperations.adjustTrove(1, 0, dec(1, 9), true, A, A, { from: A, value: dec(30000, 18) })
      await priceFeed.setPrice(dec(1, 16))
      assert.isTrue(await th.checkRecoveryMode(contracts))
      await borrowerOperations.adjustTrove('4999999999999999', 0, dec(1, 9), true, A, A, { from: A, value: dec(3000000, 18) })
    })

    xit("adjustTrove(): decays a non-zero base rate", async () => {
      await openTrove({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openTrove({ extraEBTCAmount: toBN(dec(30, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openTrove({ extraEBTCAmount: toBN(dec(40, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openTrove({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })
      await openTrove({ extraEBTCAmount: toBN(dec(40, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })
      await openTrove({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: E } })

      // Artificially make baseRate 5%
      await troveManager.setBaseRate(dec(5, 16))
      await troveManager.setLastFeeOpTimeToNow()

      // Check baseRate is now non-zero
      const baseRate_1 = await troveManager.baseRate()
      assert.isTrue(baseRate_1.gt(toBN('0')))

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      // D adjusts trove
      await borrowerOperations.adjustTrove(th._100pct, 0, dec(37, 18), true, D, D, { from: D })

      // Check baseRate has decreased
      const baseRate_2 = await troveManager.baseRate()
      assert.isTrue(baseRate_2.lt(baseRate_1))

      // 1 hour passes
      th.fastForwardTime(3600, web3.currentProvider)

      // E adjusts trove
      await borrowerOperations.adjustTrove(th._100pct, 0, dec(37, 15), true, E, E, { from: D })

      const baseRate_3 = await troveManager.baseRate()
      assert.isTrue(baseRate_3.lt(baseRate_2))
    })

    xit("adjustTrove(): doesn't decay a non-zero base rate when user issues 0 debt", async () => {
      await openTrove({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openTrove({ extraEBTCAmount: toBN(dec(30, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openTrove({ extraEBTCAmount: toBN(dec(40, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openTrove({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })

      // Artificially make baseRate 5%
      await troveManager.setBaseRate(dec(5, 16))
      await troveManager.setLastFeeOpTimeToNow()

      // D opens trove 
      await openTrove({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      // Check baseRate is now non-zero
      const baseRate_1 = await troveManager.baseRate()
      assert.isTrue(baseRate_1.gt(toBN('0')))

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      // D adjusts trove with 0 debt
      await borrowerOperations.adjustTrove(th._100pct, 0, 0, false, D, D, { from: D, value: dec(1, 'ether') })

      // Check baseRate has not decreased 
      const baseRate_2 = await troveManager.baseRate()
      assert.isTrue(baseRate_2.eq(baseRate_1))
    })

    xit("adjustTrove(): doesn't change base rate if it is already zero", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(40, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: E } })
      await openTrove({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      // Check baseRate is zero
      const baseRate_1 = await troveManager.baseRate()
      assert.equal(baseRate_1, '0')

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      // D adjusts trove
      await borrowerOperations.adjustTrove(th._100pct, 0, dec(37, 18), true, D, D, { from: D })

      // Check baseRate is still 0
      const baseRate_2 = await troveManager.baseRate()
      assert.equal(baseRate_2, '0')

      // 1 hour passes
      th.fastForwardTime(3600, web3.currentProvider)

      // E adjusts trove
      await borrowerOperations.adjustTrove(th._100pct, 0, dec(37, 15), true, E, E, { from: D })

      const baseRate_3 = await troveManager.baseRate()
      assert.equal(baseRate_3, '0')
    })

    xit("adjustTrove(): lastFeeOpTime doesn't update if less time than decay interval has passed since the last fee operation", async () => {
      await openTrove({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openTrove({ extraEBTCAmount: toBN(dec(30, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openTrove({ extraEBTCAmount: toBN(dec(40, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openTrove({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })

      // Artificially make baseRate 5%
      await troveManager.setBaseRate(dec(5, 16))
      await troveManager.setLastFeeOpTimeToNow()

      // Check baseRate is now non-zero
      const baseRate_1 = await troveManager.baseRate()
      assert.isTrue(baseRate_1.gt(toBN('0')))

      const lastFeeOpTime_1 = await troveManager.lastFeeOperationTime()

      // 10 seconds pass
      th.fastForwardTime(10, web3.currentProvider)

      // Borrower C triggers a fee
      await borrowerOperations.adjustTrove(th._100pct, 0, dec(1, 18), true, C, C, { from: C })

      const lastFeeOpTime_2 = await troveManager.lastFeeOperationTime()

      // Check that the last fee operation time did not update, as borrower D's debt issuance occured
      // since before minimum interval had passed 
      assert.isTrue(lastFeeOpTime_2.eq(lastFeeOpTime_1))

      // 60 seconds passes
      th.fastForwardTime(60, web3.currentProvider)

      // Check that now, at least one minute has passed since lastFeeOpTime_1
      const timeNow = await th.getLatestBlockTimestamp(web3)
      assert.isTrue(toBN(timeNow).sub(lastFeeOpTime_1).gte(60))

      // Borrower C triggers a fee
      await borrowerOperations.adjustTrove(th._100pct, 0, dec(1, 18), true, C, C, { from: C })

      const lastFeeOpTime_3 = await troveManager.lastFeeOperationTime()

      // Check that the last fee operation time DID update, as borrower's debt issuance occured
      // after minimum interval had passed 
      assert.isTrue(lastFeeOpTime_3.gt(lastFeeOpTime_1))
    })

    xit("adjustTrove(): borrower can't grief the baseRate and stop it decaying by issuing debt at higher frequency than the decay granularity", async () => {
      await openTrove({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openTrove({ extraEBTCAmount: toBN(dec(30, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openTrove({ extraEBTCAmount: toBN(dec(40, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openTrove({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })

      // Artificially make baseRate 5%
      await troveManager.setBaseRate(dec(5, 16))
      await troveManager.setLastFeeOpTimeToNow()

      // Check baseRate is now non-zero
      const baseRate_1 = await troveManager.baseRate()
      assert.isTrue(baseRate_1.gt(toBN('0')))

      // Borrower C triggers a fee, before decay interval of 1 minute has passed
      await borrowerOperations.adjustTrove(th._100pct, 0, dec(1, 18), true, C, C, { from: C })

      // 1 minute passes
      th.fastForwardTime(60, web3.currentProvider)

      // Borrower C triggers another fee
      await borrowerOperations.adjustTrove(th._100pct, 0, dec(1, 18), true, C, C, { from: C })

      // Check base rate has decreased even though Borrower tried to stop it decaying
      const baseRate_2 = await troveManager.baseRate()
      assert.isTrue(baseRate_2.lt(baseRate_1))
    })

    xit("adjustTrove(): borrowing at non-zero base rate sends EBTC fee to LQTY staking contract", async () => {
      // time fast-forwards 1 year, and multisig stakes 1 LQTY
      await th.fastForwardTime(timeValues.SECONDS_IN_ONE_YEAR, web3.currentProvider)
      await lqtyToken.approve(lqtyStaking.address, dec(1, 18), { from: multisig })
      await lqtyStaking.stake(dec(1, 18), { from: multisig })

      // Check LQTY EBTC balance before == 0
      const lqtyStaking_EBTCBalance_Before = await lusdToken.balanceOf(lqtyStaking.address)
      assert.equal(lqtyStaking_EBTCBalance_Before, '0')

      await openTrove({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openTrove({ extraEBTCAmount: toBN(dec(30, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openTrove({ extraEBTCAmount: toBN(dec(40, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openTrove({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })

      // Artificially make baseRate 5%
      await troveManager.setBaseRate(dec(5, 16))
      await troveManager.setLastFeeOpTimeToNow()

      // Check baseRate is now non-zero
      const baseRate_1 = await troveManager.baseRate()
      assert.isTrue(baseRate_1.gt(toBN('0')))

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      // D adjusts trove
      await openTrove({ extraEBTCAmount: toBN(dec(37, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      // Check LQTY EBTC balance after has increased
      const lqtyStaking_EBTCBalance_After = await lusdToken.balanceOf(lqtyStaking.address)
      assert.isTrue(lqtyStaking_EBTCBalance_After.gt(lqtyStaking_EBTCBalance_Before))
    })

    if (!withProxy) { // TODO: use rawLogs instead of logs
      xit("adjustTrove(): borrowing at non-zero base records the (drawn debt + fee) on the Trove struct", async () => {
        // time fast-forwards 1 year, and multisig stakes 1 LQTY
        await th.fastForwardTime(timeValues.SECONDS_IN_ONE_YEAR, web3.currentProvider)
        await lqtyToken.approve(lqtyStaking.address, dec(1, 18), { from: multisig })
        await lqtyStaking.stake(dec(1, 18), { from: multisig })

        await openTrove({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
        await openTrove({ extraEBTCAmount: toBN(dec(30, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
        await openTrove({ extraEBTCAmount: toBN(dec(40, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
        await openTrove({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })
        await openTrove({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })
        const D_debtBefore = await getTroveEntireDebt(D)

        // Artificially make baseRate 5%
        await troveManager.setBaseRate(dec(5, 16))
        await troveManager.setLastFeeOpTimeToNow()

        // Check baseRate is now non-zero
        const baseRate_1 = await troveManager.baseRate()
        assert.isTrue(baseRate_1.gt(toBN('0')))

        // 2 hours pass
        th.fastForwardTime(7200, web3.currentProvider)

        const withdrawal_D = toBN(dec(37, 18))

        // D withdraws EBTC
        const adjustmentTx = await borrowerOperations.adjustTrove(th._100pct, 0, withdrawal_D, true, D, D, { from: D })

        const emittedFee = toBN(th.getEBTCFeeFromEBTCBorrowingEvent(adjustmentTx))
        assert.isTrue(emittedFee.gt(toBN('0')))

        const D_newDebt = (await troveManager.Troves(D))[0]
    
        // Check debt on Trove struct equals initila debt plus drawn debt plus emitted fee
        assert.isTrue(D_newDebt.eq(D_debtBefore.add(withdrawal_D).add(emittedFee)))
      })
    }

    xit("adjustTrove(): Borrowing at non-zero base rate increases the LQTY staking contract EBTC fees-per-unit-staked", async () => {
      // time fast-forwards 1 year, and multisig stakes 1 LQTY
      await th.fastForwardTime(timeValues.SECONDS_IN_ONE_YEAR, web3.currentProvider)
      await lqtyToken.approve(lqtyStaking.address, dec(1, 18), { from: multisig })
      await lqtyStaking.stake(dec(1, 18), { from: multisig })

      // Check LQTY contract EBTC fees-per-unit-staked is zero
      const F_EBTC_Before = await lqtyStaking.F_EBTC()
      assert.equal(F_EBTC_Before, '0')

      await openTrove({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openTrove({ extraEBTCAmount: toBN(dec(30, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openTrove({ extraEBTCAmount: toBN(dec(40, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openTrove({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })
      await openTrove({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      // Artificially make baseRate 5%
      await troveManager.setBaseRate(dec(5, 16))
      await troveManager.setLastFeeOpTimeToNow()

      // Check baseRate is now non-zero
      const baseRate_1 = await troveManager.baseRate()
      assert.isTrue(baseRate_1.gt(toBN('0')))

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      // D adjusts trove
      await borrowerOperations.adjustTrove(th._100pct, 0, dec(37, 18), true, D, D, { from: D })

      // Check LQTY contract EBTC fees-per-unit-staked has increased
      const F_EBTC_After = await lqtyStaking.F_EBTC()
      assert.isTrue(F_EBTC_After.gt(F_EBTC_Before))
    })

    xit("adjustTrove(): Borrowing at non-zero base rate sends requested amount to the user", async () => {
      // time fast-forwards 1 year, and multisig stakes 1 LQTY
      await th.fastForwardTime(timeValues.SECONDS_IN_ONE_YEAR, web3.currentProvider)
      await lqtyToken.approve(lqtyStaking.address, dec(1, 18), { from: multisig })
      await lqtyStaking.stake(dec(1, 18), { from: multisig })

      // Check LQTY Staking contract balance before == 0
      const lqtyStaking_EBTCBalance_Before = await lusdToken.balanceOf(lqtyStaking.address)
      assert.equal(lqtyStaking_EBTCBalance_Before, '0')

      await openTrove({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openTrove({ extraEBTCAmount: toBN(dec(30, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openTrove({ extraEBTCAmount: toBN(dec(40, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openTrove({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })
      await openTrove({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      const D_EBTCBalanceBefore = await lusdToken.balanceOf(D)

      // Artificially make baseRate 5%
      await troveManager.setBaseRate(dec(5, 16))
      await troveManager.setLastFeeOpTimeToNow()

      // Check baseRate is now non-zero
      const baseRate_1 = await troveManager.baseRate()
      assert.isTrue(baseRate_1.gt(toBN('0')))

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      // D adjusts trove
      const EBTCRequest_D = toBN(dec(40, 18))
      await borrowerOperations.adjustTrove(th._100pct, 0, EBTCRequest_D, true, D, D, { from: D })

      // Check LQTY staking EBTC balance has increased
      const lqtyStaking_EBTCBalance_After = await lusdToken.balanceOf(lqtyStaking.address)
      assert.isTrue(lqtyStaking_EBTCBalance_After.gt(lqtyStaking_EBTCBalance_Before))

      // Check D's EBTC balance has increased by their requested EBTC
      const D_EBTCBalanceAfter = await lusdToken.balanceOf(D)
      assert.isTrue(D_EBTCBalanceAfter.eq(D_EBTCBalanceBefore.add(EBTCRequest_D)))
    })

    it("adjustTrove(): Borrowing at zero base rate changes EBTC balance of LQTY staking contract", async () => {
      await openTrove({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openTrove({ extraEBTCAmount: toBN(dec(30, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openTrove({ extraEBTCAmount: toBN(dec(40, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openTrove({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })
      await openTrove({ extraEBTCAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      const DIndex = await sortedTroves.troveOfOwnerByIndex(D,0)

      // Origination fee is assumed to be zero

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      // Check staking EBTC balance before > 0
      const lqtyStaking_EBTCBalance_Before = await lusdToken.balanceOf(lqtyStaking.address)
      assert.isTrue(lqtyStaking_EBTCBalance_Before.gt(toBN('0')))

      // D adjusts trove
      await borrowerOperations.adjustTrove(DIndex, th._100pct, 0, dec(37, 18), true, DIndex, DIndex, { from: D })

      // Check staking EBTC balance after > staking balance before
      const lqtyStaking_EBTCBalance_After = await lusdToken.balanceOf(lqtyStaking.address)
      assert.isTrue(lqtyStaking_EBTCBalance_After.gt(lqtyStaking_EBTCBalance_Before))
    })

    it("adjustTrove(): Borrowing at zero base rate changes LQTY staking contract EBTC fees-per-unit-staked", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(20000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: whale, value: toBN(dec(100, 'ether')) } })
      await openTrove({ extraEBTCAmount: toBN(dec(40000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openTrove({ extraEBTCAmount: toBN(dec(40000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openTrove({ extraEBTCAmount: toBN(dec(40000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })
      await openTrove({ extraEBTCAmount: toBN(dec(40000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      const DIndex = await sortedTroves.troveOfOwnerByIndex(D,0)

      // Origination fee is assumed to be zero

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      // A artificially receives LQTY, then stakes it
      await lqtyToken.unprotectedMint(A, dec(100, 18))
      await lqtyStaking.stake(dec(100, 18), { from: A })

      // Check staking EBTC balance before == 0
      const F_EBTC_Before = await lqtyStaking.F_EBTC()
      assert.isTrue(F_EBTC_Before.eq(toBN('0')))

      // D adjusts trove
      await borrowerOperations.adjustTrove(DIndex, th._100pct, 0, dec(37, 18), true, DIndex, DIndex, { from: D })

      // Check staking EBTC balance increases
      const F_EBTC_After = await lqtyStaking.F_EBTC()
      assert.isTrue(F_EBTC_After.gt(F_EBTC_Before))
    })

    it("adjustTrove(): Borrowing at zero base rate sends total requested EBTC to the user", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(20000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: whale, value: toBN(dec(100, 'ether')) } })
      await openTrove({ extraEBTCAmount: toBN(dec(40000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openTrove({ extraEBTCAmount: toBN(dec(40000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openTrove({ extraEBTCAmount: toBN(dec(40000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })
      await openTrove({ extraEBTCAmount: toBN(dec(40000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      const DIndex = await sortedTroves.troveOfOwnerByIndex(D,0)

      const D_EBTCBalBefore = await lusdToken.balanceOf(D)

      // Origination fee is assumed to be zero

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      const DUSDBalanceBefore = await lusdToken.balanceOf(D)

      // D adjusts trove
      const EBTCRequest_D = toBN(dec(40, 18))
      await borrowerOperations.adjustTrove(DIndex, th._100pct, 0, EBTCRequest_D, true, DIndex, DIndex, { from: D })

      // Check D's EBTC balance increased by their requested EBTC
      const EBTCBalanceAfter = await lusdToken.balanceOf(D)
      assert.isTrue(EBTCBalanceAfter.eq(D_EBTCBalBefore.add(EBTCRequest_D)))
    })

    it("adjustTrove(): reverts when calling address does not own the trove index specified", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openTrove({ extraEBTCAmount: toBN(dec(20000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: bob } })
      
      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
      const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)

      // Alice coll and debt increase(+1 ETH, +50EBTC)
      await borrowerOperations.adjustTrove(aliceIndex, th._100pct, 0, dec(50, 18), true, aliceIndex, aliceIndex, { from: alice, value: dec(1, 'ether') })

      try {
        const txCarol = await borrowerOperations.adjustTrove(aliceIndex, th._100pct, 0, dec(50, 18), true, aliceIndex, aliceIndex, { from: carol, value: dec(1, 'ether') })
        assert.isFalse(txCarol.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    it("adjustTrove(): reverts in Recovery Mode when the adjustment would reduce the TCR", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openTrove({ extraEBTCAmount: toBN(dec(20000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: bob } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
      const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)

      assert.isFalse(await th.checkRecoveryMode(contracts))

      const txAlice = await borrowerOperations.adjustTrove(aliceIndex, th._100pct, 0, dec(50, 18), true, aliceIndex, aliceIndex, { from: alice, value: dec(1, 'ether') })
      assert.isTrue(txAlice.receipt.status)

      await priceFeed.setPrice(dec(120, 18)) // trigger drop in ETH price

      assert.isTrue(await th.checkRecoveryMode(contracts))

      try { // collateral withdrawal should also fail
        const txAlice = await borrowerOperations.adjustTrove(aliceIndex, th._100pct, dec(1, 'ether'), 0, false, aliceIndex, aliceIndex, { from: alice })
        assert.isFalse(txAlice.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }

      try { // debt increase should fail
        const txBob = await borrowerOperations.adjustTrove(bobIndex, th._100pct, 0, dec(50, 18), true, bobIndex, bobIndex, { from: bob })
        assert.isFalse(txBob.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }

      try { // debt increase that's also a collateral increase should also fail, if ICR will be worse off
        const txBob = await borrowerOperations.adjustTrove(bobIndex, th._100pct, 0, dec(111, 18), true, bobIndex, bobIndex, { from: bob, value: dec(1, 'ether') })
        assert.isFalse(txBob.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    it("adjustTrove(): collateral withdrawal reverts in Recovery Mode", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openTrove({ extraEBTCAmount: toBN(dec(20000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: bob } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
      const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)

      assert.isFalse(await th.checkRecoveryMode(contracts))

      await priceFeed.setPrice(dec(120, 18)) // trigger drop in ETH price

      assert.isTrue(await th.checkRecoveryMode(contracts))

      // Alice attempts an adjustment that repays half her debt BUT withdraws 1 wei collateral, and fails
      await assertRevert(borrowerOperations.adjustTrove(aliceIndex, th._100pct, 1, dec(5000, 18), false, aliceIndex, aliceIndex, { from: alice }),
        "BorrowerOps: Collateral withdrawal not permitted Recovery Mode")
    })

    it("adjustTrove(): debt increase that would leave ICR < 150% reverts in Recovery Mode", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openTrove({ extraEBTCAmount: toBN(dec(20000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: bob } })
      const CCR = await troveManager.CCR()

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
      const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)

      assert.isFalse(await th.checkRecoveryMode(contracts))

      await priceFeed.setPrice(dec(120, 18)) // trigger drop in ETH price
      const price = await priceFeed.getPrice()

      assert.isTrue(await th.checkRecoveryMode(contracts))

      const ICR_A = await troveManager.getCurrentICR(aliceIndex, price)

      const aliceDebt = await getTroveEntireDebt(aliceIndex)
      const aliceColl = await getTroveEntireColl(aliceIndex)
      const debtIncrease = toBN(dec(50, 18))
      const collIncrease = toBN(dec(1, 'ether'))

      // Check the new ICR would be an improvement, but less than the CCR (150%)
      const newICR = await troveManager.computeICR(aliceColl.add(collIncrease), aliceDebt.add(debtIncrease), price)

      assert.isTrue(newICR.gt(ICR_A) && newICR.lt(CCR))

      await assertRevert(borrowerOperations.adjustTrove(aliceIndex, th._100pct, 0, debtIncrease, true, aliceIndex, aliceIndex, { from: alice, value: collIncrease }),
        "BorrowerOps: Operation must leave trove with ICR >= CCR")
    })

    it("adjustTrove(): debt increase that would reduce the ICR reverts in Recovery Mode", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(3, 18)), extraParams: { from: alice } })
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: bob } })
      const CCR = await troveManager.CCR()

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
      const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)

      assert.isFalse(await th.checkRecoveryMode(contracts))

      await priceFeed.setPrice(dec(105, 18)) // trigger drop in ETH price
      const price = await priceFeed.getPrice()

      assert.isTrue(await th.checkRecoveryMode(contracts))

      //--- Alice with ICR > 150% tries to reduce her ICR ---

      const ICR_A = await troveManager.getCurrentICR(aliceIndex, price)

      // Check Alice's initial ICR is above 150%
      assert.isTrue(ICR_A.gt(CCR))

      const aliceDebt = await getTroveEntireDebt(aliceIndex)
      const aliceColl = await getTroveEntireColl(aliceIndex)
      const aliceDebtIncrease = toBN(dec(150, 18))
      const aliceCollIncrease = toBN(dec(1, 'ether'))

      const newICR_A = await troveManager.computeICR(aliceColl.add(aliceCollIncrease), aliceDebt.add(aliceDebtIncrease), price)

      // Check Alice's new ICR would reduce but still be greater than 150%
      assert.isTrue(newICR_A.lt(ICR_A) && newICR_A.gt(CCR))

      await assertRevert(borrowerOperations.adjustTrove(aliceIndex, th._100pct, 0, aliceDebtIncrease, true, aliceIndex, aliceIndex, { from: alice, value: aliceCollIncrease }),
        "BorrowerOps: Cannot decrease your Trove's ICR in Recovery Mode")

      //--- Bob with ICR < 150% tries to reduce his ICR ---

      const ICR_B = await troveManager.getCurrentICR(bobIndex, price)

      // Check Bob's initial ICR is below 150%
      assert.isTrue(ICR_B.lt(CCR))

      const bobDebt = await getTroveEntireDebt(bobIndex)
      const bobColl = await getTroveEntireColl(bobIndex)
      const bobDebtIncrease = toBN(dec(450, 18))
      const bobCollIncrease = toBN(dec(1, 'ether'))

      const newICR_B = await troveManager.computeICR(bobColl.add(bobCollIncrease), bobDebt.add(bobDebtIncrease), price)

      // Check Bob's new ICR would reduce 
      assert.isTrue(newICR_B.lt(ICR_B))

      await assertRevert(borrowerOperations.adjustTrove(bobIndex, th._100pct, 0, bobDebtIncrease, true, bobIndex, bobIndex, { from: bob, value: bobCollIncrease }),
        " BorrowerOps: Operation must leave trove with ICR >= CCR")
    })

    it("adjustTrove(): A trove with ICR < CCR in Recovery Mode can adjust their trove to ICR > CCR", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: bob } })
      const CCR = await troveManager.CCR()

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
      const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)

      assert.isFalse(await th.checkRecoveryMode(contracts))

      await priceFeed.setPrice(dec(100, 18)) // trigger drop in ETH price
      const price = await priceFeed.getPrice()

      assert.isTrue(await th.checkRecoveryMode(contracts))

      const ICR_A = await troveManager.getCurrentICR(aliceIndex, price)
      // Check initial ICR is below 150%
      assert.isTrue(ICR_A.lt(CCR))

      const aliceDebt = await getTroveEntireDebt(aliceIndex)
      const aliceColl = await getTroveEntireColl(aliceIndex)
      const debtIncrease = toBN(dec(5000, 18))
      const collIncrease = toBN(dec(150, 'ether'))

      const newICR = await troveManager.computeICR(aliceColl.add(collIncrease), aliceDebt.add(debtIncrease), price)

      // Check new ICR would be > 150%
      assert.isTrue(newICR.gt(CCR))

      const tx = await borrowerOperations.adjustTrove(aliceIndex, th._100pct, 0, debtIncrease, true, aliceIndex, aliceIndex, { from: alice, value: collIncrease })
      assert.isTrue(tx.receipt.status)

      const actualNewICR = await troveManager.getCurrentICR(aliceIndex, price)
      assert.isTrue(actualNewICR.gt(CCR))
    })

    it("adjustTrove(): A trove with ICR > CCR in Recovery Mode can improve their ICR", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(3, 18)), extraParams: { from: alice } })
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: bob } })
      const CCR = await troveManager.CCR()

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
      const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)

      assert.isFalse(await th.checkRecoveryMode(contracts))

      await priceFeed.setPrice(dec(105, 18)) // trigger drop in ETH price
      const price = await priceFeed.getPrice()

      assert.isTrue(await th.checkRecoveryMode(contracts))

      const initialICR = await troveManager.getCurrentICR(aliceIndex, price)
      // Check initial ICR is above 150%
      assert.isTrue(initialICR.gt(CCR))

      const aliceDebt = await getTroveEntireDebt(aliceIndex)
      const aliceColl = await getTroveEntireColl(aliceIndex)
      const debtIncrease = toBN(dec(5000, 18))
      const collIncrease = toBN(dec(150, 'ether'))

      const newICR = await troveManager.computeICR(aliceColl.add(collIncrease), aliceDebt.add(debtIncrease), price)

      // Check new ICR would be > old ICR
      assert.isTrue(newICR.gt(initialICR))

      const tx = await borrowerOperations.adjustTrove(aliceIndex, th._100pct, 0, debtIncrease, true, aliceIndex, aliceIndex, { from: alice, value: collIncrease })
      assert.isTrue(tx.receipt.status)

      const actualNewICR = await troveManager.getCurrentICR(aliceIndex, price)
      assert.isTrue(actualNewICR.gt(initialICR))
    })

    it("adjustTrove(): debt increase in Recovery Mode charges no fee", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openTrove({ extraEBTCAmount: toBN(dec(200000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: bob } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
      const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)

      assert.isFalse(await th.checkRecoveryMode(contracts))

      await priceFeed.setPrice(dec(120, 18)) // trigger drop in ETH price

      assert.isTrue(await th.checkRecoveryMode(contracts))

      // B stakes LQTY
      await lqtyToken.unprotectedMint(bob, dec(100, 18))
      await lqtyStaking.stake(dec(100, 18), { from: bob })

      const lqtyStakingEBTCBalanceBefore = await lusdToken.balanceOf(lqtyStaking.address)
      assert.isTrue(lqtyStakingEBTCBalanceBefore.gt(toBN('0')))

      const txAlice = await borrowerOperations.adjustTrove(aliceIndex, th._100pct, 0, dec(50, 18), true, aliceIndex, aliceIndex, { from: alice, value: dec(100, 'ether') })
      assert.isTrue(txAlice.receipt.status)

      // Check emitted fee = 0
      const emittedFee = toBN(await th.getEventArgByName(txAlice, 'EBTCBorrowingFeePaid', '_EBTCFee'))
      assert.isTrue(emittedFee.eq(toBN('0')))

      assert.isTrue(await th.checkRecoveryMode(contracts))

      // Check no fee was sent to staking contract
      const lqtyStakingEBTCBalanceAfter = await lusdToken.balanceOf(lqtyStaking.address)
      assert.equal(lqtyStakingEBTCBalanceAfter.toString(), lqtyStakingEBTCBalanceBefore.toString())
    })

    it("adjustTrove(): reverts when change would cause the TCR of the system to fall below the CCR", async () => {
      await priceFeed.setPrice(dec(100, 18))

      await openTrove({ ICR: toBN(dec(15, 17)), extraParams: { from: alice } })
      await openTrove({ ICR: toBN(dec(15, 17)), extraParams: { from: bob } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
      const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)

      // Check TCR and Recovery Mode
      const TCR = (await th.getTCR(contracts)).toString()
      assert.equal(TCR, '1500000000000000000')
      assert.isFalse(await th.checkRecoveryMode(contracts))

      // Bob attempts an operation that would bring the TCR below the CCR
      try {
        const txBob = await borrowerOperations.adjustTrove(bobIndex, th._100pct, 0, dec(1, 18), true, bobIndex, bobIndex, { from: bob })
        assert.isFalse(txBob.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    it("adjustTrove(): reverts when EBTC repaid is > debt of the trove", async () => {
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      const bobOpenTx = (await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: bob } })).tx
      
      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
      const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)

      const bobDebt = await getTroveEntireDebt(bobIndex)
      assert.isTrue(bobDebt.gt(toBN('0')))

      const bobFee = toBN(await th.getEventArgByIndex(bobOpenTx, 'EBTCBorrowingFeePaid', 1))
      assert.isTrue(bobFee.gt(toBN('0')))

      // Alice transfers EBTC to bob to compensate borrowing fees
      await lusdToken.transfer(bob, bobFee, { from: alice })

      const remainingDebt = (await troveManager.getTroveDebt(bobIndex)).sub(EBTC_GAS_COMPENSATION)

      // Bob attempts an adjustment that would repay 1 wei more than his debt
      await assertRevert(
        borrowerOperations.adjustTrove(bobIndex, th._100pct, 0, remainingDebt.add(toBN(1)), false, bobIndex, bobIndex, { from: bob, value: dec(1, 'ether') }),
        "revert"
      )
    })

    it("adjustTrove(): reverts when attempted ETH withdrawal is >= the trove's collateral", async () => {
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: bob } })
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: carol } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
      const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)
      const carolIndex = await sortedTroves.troveOfOwnerByIndex(carol,0)

      const carolColl = await getTroveEntireColl(carolIndex)

      // Carol attempts an adjustment that would withdraw 1 wei more than her ETH
      try {
        const txCarol = await borrowerOperations.adjustTrove(carolIndex, th._100pct, carolColl.add(toBN(1)), 0, true, carolIndex, carolIndex, { from: carol })
        assert.isFalse(txCarol.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    it("adjustTrove(): reverts when change would cause the ICR of the trove to fall below the MCR", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(100, 18)), extraParams: { from: whale } })

      await priceFeed.setPrice(dec(100, 18))

      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(11, 17)), extraParams: { from: alice } })
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(11, 17)), extraParams: { from: bob } })

      const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)

      // Bob attempts to increase debt by 100 EBTC and 1 ether, i.e. a change that constitutes a 100% ratio of coll:debt.
      // Since his ICR prior is 110%, this change would reduce his ICR below MCR.
      try {
        const txBob = await borrowerOperations.adjustTrove(bobIndex, th._100pct, 0, dec(100, 18), true, bobIndex, bobIndex, { from: bob, value: dec(1, 'ether') })
        assert.isFalse(txBob.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    it("adjustTrove(): With 0 coll change, doesnt change borrower's coll or ActivePool coll", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)

      const aliceCollBefore = await getTroveEntireColl(aliceIndex)
      const activePoolCollBefore = await activePool.getETH()

      assert.isTrue(aliceCollBefore.gt(toBN('0')))
      assert.isTrue(aliceCollBefore.eq(activePoolCollBefore))

      // Alice adjusts trove. No coll change, and a debt increase (+50EBTC)
      await borrowerOperations.adjustTrove(aliceIndex, th._100pct, 0, dec(50, 18), true, aliceIndex, aliceIndex, { from: alice, value: 0 })

      const aliceCollAfter = await getTroveEntireColl(aliceIndex)
      const activePoolCollAfter = await activePool.getETH()

      assert.isTrue(aliceCollAfter.eq(activePoolCollAfter))
      assert.isTrue(activePoolCollAfter.eq(activePoolCollAfter))
    })

    it("adjustTrove(): With 0 debt change, doesnt change borrower's debt or ActivePool debt", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)

      const aliceDebtBefore = await getTroveEntireDebt(aliceIndex)
      const activePoolDebtBefore = await activePool.getEBTCDebt()

      assert.isTrue(aliceDebtBefore.gt(toBN('0')))
      assert.isTrue(aliceDebtBefore.eq(activePoolDebtBefore))

      // Alice adjusts trove. Coll change, no debt change
      await borrowerOperations.adjustTrove(aliceIndex, th._100pct, 0, 0, false, aliceIndex, aliceIndex, { from: alice, value: dec(1, 'ether') })

      const aliceDebtAfter = await getTroveEntireDebt(aliceIndex)
      const activePoolDebtAfter = await activePool.getEBTCDebt()

      assert.isTrue(aliceDebtAfter.eq(aliceDebtBefore))
      assert.isTrue(activePoolDebtAfter.eq(activePoolDebtBefore))
    })

    it("adjustTrove(): updates borrower's debt and coll with an increase in both", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)

      const debtBefore = await getTroveEntireDebt(aliceIndex)
      const collBefore = await getTroveEntireColl(aliceIndex)
      assert.isTrue(debtBefore.gt(toBN('0')))
      assert.isTrue(collBefore.gt(toBN('0')))

      // Alice adjusts trove. Coll and debt increase(+1 ETH, +50EBTC)
      await borrowerOperations.adjustTrove(aliceIndex, th._100pct, 0, await getNetBorrowingAmount(dec(50, 18)), true, aliceIndex, aliceIndex, { from: alice, value: dec(1, 'ether') })

      const debtAfter = await getTroveEntireDebt(aliceIndex)
      const collAfter = await getTroveEntireColl(aliceIndex)

      th.assertIsApproximatelyEqual(debtAfter, debtBefore.add(toBN(dec(50, 18))), 10000)
      th.assertIsApproximatelyEqual(collAfter, collBefore.add(toBN(dec(1, 18))), 10000)
    })

    it("adjustTrove(): updates borrower's debt and coll with a decrease in both", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)

      const debtBefore = await getTroveEntireDebt(aliceIndex)
      const collBefore = await getTroveEntireColl(aliceIndex)
      assert.isTrue(debtBefore.gt(toBN('0')))
      assert.isTrue(collBefore.gt(toBN('0')))

      // Alice adjusts trove coll and debt decrease (-0.5 ETH, -50EBTC)
      await borrowerOperations.adjustTrove(aliceIndex, th._100pct, dec(500, 'finney'), dec(50, 18), false, aliceIndex, aliceIndex, { from: alice })

      const debtAfter = await getTroveEntireDebt(aliceIndex)
      const collAfter = await getTroveEntireColl(aliceIndex)

      assert.isTrue(debtAfter.eq(debtBefore.sub(toBN(dec(50, 18)))))
      assert.isTrue(collAfter.eq(collBefore.sub(toBN(dec(5, 17)))))
    })

    it("adjustTrove(): updates borrower's  debt and coll with coll increase, debt decrease", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)

      const debtBefore = await getTroveEntireDebt(aliceIndex)
      const collBefore = await getTroveEntireColl(aliceIndex)
      assert.isTrue(debtBefore.gt(toBN('0')))
      assert.isTrue(collBefore.gt(toBN('0')))

      // Alice adjusts trove - coll increase and debt decrease (+0.5 ETH, -50EBTC)
      await borrowerOperations.adjustTrove(aliceIndex, th._100pct, 0, dec(50, 18), false, aliceIndex, aliceIndex, { from: alice, value: dec(500, 'finney') })

      const debtAfter = await getTroveEntireDebt(aliceIndex)
      const collAfter = await getTroveEntireColl(aliceIndex)

      th.assertIsApproximatelyEqual(debtAfter, debtBefore.sub(toBN(dec(50, 18))), 10000)
      th.assertIsApproximatelyEqual(collAfter, collBefore.add(toBN(dec(5, 17))), 10000)
    })

    it("adjustTrove(): updates borrower's debt and coll with coll decrease, debt increase", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)

      const debtBefore = await getTroveEntireDebt(aliceIndex)
      const collBefore = await getTroveEntireColl(aliceIndex)
      assert.isTrue(debtBefore.gt(toBN('0')))
      assert.isTrue(collBefore.gt(toBN('0')))

      // Alice adjusts trove - coll decrease and debt increase (0.1 ETH, 10EBTC)
      await borrowerOperations.adjustTrove(aliceIndex, th._100pct, dec(1, 17), await getNetBorrowingAmount(dec(1, 18)), true, aliceIndex, aliceIndex, { from: alice })

      const debtAfter = await getTroveEntireDebt(aliceIndex)
      const collAfter = await getTroveEntireColl(aliceIndex)

      th.assertIsApproximatelyEqual(debtAfter, debtBefore.add(toBN(dec(1, 18))), 10000)
      th.assertIsApproximatelyEqual(collAfter, collBefore.sub(toBN(dec(1, 17))), 10000)
    })

    it("adjustTrove(): updates borrower's stake and totalStakes with a coll increase", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)

      const stakeBefore = await troveManager.getTroveStake(aliceIndex)
      const totalStakesBefore = await troveManager.totalStakes();
      assert.isTrue(stakeBefore.gt(toBN('0')))
      assert.isTrue(totalStakesBefore.gt(toBN('0')))

      // Alice adjusts trove - coll and debt increase (+1 ETH, +50 EBTC)
      await borrowerOperations.adjustTrove(aliceIndex, th._100pct, 0, dec(50, 18), true, aliceIndex, aliceIndex, { from: alice, value: dec(1, 'ether') })

      const stakeAfter = await troveManager.getTroveStake(aliceIndex)
      const totalStakesAfter = await troveManager.totalStakes();

      assert.isTrue(stakeAfter.eq(stakeBefore.add(toBN(dec(1, 18)))))
      assert.isTrue(totalStakesAfter.eq(totalStakesBefore.add(toBN(dec(1, 18)))))
    })

    it("adjustTrove(): updates borrower's stake and totalStakes with a coll decrease", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)

      const stakeBefore = await troveManager.getTroveStake(aliceIndex)
      const totalStakesBefore = await troveManager.totalStakes();
      assert.isTrue(stakeBefore.gt(toBN('0')))
      assert.isTrue(totalStakesBefore.gt(toBN('0')))

      // Alice adjusts trove - coll decrease and debt decrease
      await borrowerOperations.adjustTrove(aliceIndex, th._100pct, dec(500, 'finney'), dec(50, 18), false, aliceIndex, aliceIndex, { from: alice })

      const stakeAfter = await troveManager.getTroveStake(aliceIndex)
      const totalStakesAfter = await troveManager.totalStakes();

      assert.isTrue(stakeAfter.eq(stakeBefore.sub(toBN(dec(5, 17)))))
      assert.isTrue(totalStakesAfter.eq(totalStakesBefore.sub(toBN(dec(5, 17)))))
    })

    it("adjustTrove(): changes EBTCToken balance by the requested decrease", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)

      const alice_EBTCTokenBalance_Before = await lusdToken.balanceOf(alice)
      assert.isTrue(alice_EBTCTokenBalance_Before.gt(toBN('0')))

      // Alice adjusts trove - coll decrease and debt decrease
      await borrowerOperations.adjustTrove(aliceIndex, th._100pct, dec(100, 'finney'), dec(10, 18), false, aliceIndex, aliceIndex, { from: alice })

      // check after
      const alice_EBTCTokenBalance_After = await lusdToken.balanceOf(alice)
      assert.isTrue(alice_EBTCTokenBalance_After.eq(alice_EBTCTokenBalance_Before.sub(toBN(dec(10, 18)))))
    })

    it("adjustTrove(): changes EBTCToken balance by the requested increase", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)

      const alice_EBTCTokenBalance_Before = await lusdToken.balanceOf(alice)
      assert.isTrue(alice_EBTCTokenBalance_Before.gt(toBN('0')))

      // Alice adjusts trove - coll increase and debt increase
      await borrowerOperations.adjustTrove(aliceIndex, th._100pct, 0, dec(100, 18), true, aliceIndex, aliceIndex, { from: alice, value: dec(1, 'ether') })

      // check after
      const alice_EBTCTokenBalance_After = await lusdToken.balanceOf(alice)
      assert.isTrue(alice_EBTCTokenBalance_After.eq(alice_EBTCTokenBalance_Before.add(toBN(dec(100, 18)))))
    })

    it("adjustTrove(): Changes the activePool ETH and raw ether balance by the requested decrease", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)

      const activePool_ETH_Before = await activePool.getETH()
      const activePool_RawEther_Before = toBN(await web3.eth.getBalance(activePool.address))
      assert.isTrue(activePool_ETH_Before.gt(toBN('0')))
      assert.isTrue(activePool_RawEther_Before.gt(toBN('0')))

      // Alice adjusts trove - coll decrease and debt decrease
      await borrowerOperations.adjustTrove(aliceIndex, th._100pct, dec(100, 'finney'), dec(10, 18), false, aliceIndex, aliceIndex, { from: alice })

      const activePool_ETH_After = await activePool.getETH()
      const activePool_RawEther_After = toBN(await web3.eth.getBalance(activePool.address))
      assert.isTrue(activePool_ETH_After.eq(activePool_ETH_Before.sub(toBN(dec(1, 17)))))
      assert.isTrue(activePool_RawEther_After.eq(activePool_ETH_Before.sub(toBN(dec(1, 17)))))
    })

    it("adjustTrove(): Changes the activePool ETH and raw ether balance by the amount of ETH sent", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)

      const activePool_ETH_Before = await activePool.getETH()
      const activePool_RawEther_Before = toBN(await web3.eth.getBalance(activePool.address))
      assert.isTrue(activePool_ETH_Before.gt(toBN('0')))
      assert.isTrue(activePool_RawEther_Before.gt(toBN('0')))

      // Alice adjusts trove - coll increase and debt increase
      await borrowerOperations.adjustTrove(aliceIndex, th._100pct, 0, dec(100, 18), true, aliceIndex, aliceIndex, { from: alice, value: dec(1, 'ether') })

      const activePool_ETH_After = await activePool.getETH()
      const activePool_RawEther_After = toBN(await web3.eth.getBalance(activePool.address))
      assert.isTrue(activePool_ETH_After.eq(activePool_ETH_Before.add(toBN(dec(1, 18)))))
      assert.isTrue(activePool_RawEther_After.eq(activePool_ETH_Before.add(toBN(dec(1, 18)))))
    })

    it("adjustTrove(): Changes the EBTC debt in ActivePool by requested decrease", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)

      const activePool_EBTCDebt_Before = await activePool.getEBTCDebt()
      assert.isTrue(activePool_EBTCDebt_Before.gt(toBN('0')))

      // Alice adjusts trove - coll increase and debt decrease
      await borrowerOperations.adjustTrove(aliceIndex, th._100pct, 0, dec(30, 18), false, aliceIndex, aliceIndex, { from: alice, value: dec(1, 'ether') })

      const activePool_EBTCDebt_After = await activePool.getEBTCDebt()
      assert.isTrue(activePool_EBTCDebt_After.eq(activePool_EBTCDebt_Before.sub(toBN(dec(30, 18)))))
    })

    it("adjustTrove(): Changes the EBTC debt in ActivePool by requested increase", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)

      const activePool_EBTCDebt_Before = await activePool.getEBTCDebt()
      assert.isTrue(activePool_EBTCDebt_Before.gt(toBN('0')))

      // Alice adjusts trove - coll increase and debt increase
      await borrowerOperations.adjustTrove(aliceIndex, th._100pct, 0, await getNetBorrowingAmount(dec(100, 18)), true, aliceIndex, aliceIndex, { from: alice, value: dec(1, 'ether') })

      const activePool_EBTCDebt_After = await activePool.getEBTCDebt()
    
      th.assertIsApproximatelyEqual(activePool_EBTCDebt_After, activePool_EBTCDebt_Before.add(toBN(dec(100, 18))))
    })

    it("adjustTrove(): new coll = 0 and new debt = 0 is not allowed, as gas compensation still counts toward ICR", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)

      const aliceColl = await getTroveEntireColl(aliceIndex)
      const aliceDebt = await getTroveEntireColl(aliceIndex)
      const status_Before = await troveManager.getTroveStatus(aliceIndex)
      const isInSortedList_Before = await sortedTroves.contains(aliceIndex)

      assert.equal(status_Before, 1)  // 1: Active
      assert.isTrue(isInSortedList_Before)

      await assertRevert(
        borrowerOperations.adjustTrove(aliceIndex, th._100pct, aliceColl, aliceDebt, true, aliceIndex, aliceIndex, { from: alice }),
        'BorrowerOps: An operation that would result in ICR < MCR is not permitted'
      )
    })

    it("adjustTrove(): Reverts if requested debt increase and amount is zero", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)

      await assertRevert(borrowerOperations.adjustTrove(aliceIndex, th._100pct, 0, 0, true, aliceIndex, aliceIndex, { from: alice }),
        'BorrowerOps: Debt increase requires non-zero debtChange')
    })

    it("adjustTrove(): Reverts if requested coll withdrawal and ether is sent", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)

      await assertRevert(borrowerOperations.adjustTrove(aliceIndex, th._100pct, dec(1, 'ether'), dec(100, 18), true, aliceIndex, aliceIndex, { from: alice, value: dec(3, 'ether') }), 'BorrowerOperations: Cannot withdraw and add coll')
    })

    it("adjustTrove(): Reverts if it’s zero adjustment", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })
      
      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)

      await assertRevert(borrowerOperations.adjustTrove(aliceIndex, th._100pct, 0, 0, false, aliceIndex, aliceIndex, { from: alice }),
                         'BorrowerOps: There must be either a collateral change or a debt change')
    })

    it("adjustTrove(): Reverts if requested coll withdrawal is greater than trove's collateral", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)

      const aliceColl = await getTroveEntireColl(aliceIndex)

      // Requested coll withdrawal > coll in the trove
      await assertRevert(borrowerOperations.adjustTrove(aliceIndex, th._100pct, aliceColl.add(toBN(1)), 0, false, aliceIndex, aliceIndex, { from: alice }))
      await assertRevert(borrowerOperations.adjustTrove(aliceIndex, th._100pct, aliceColl.add(toBN(dec(37, 'ether'))), 0, false, aliceIndex, aliceIndex, { from: bob }))
    })

    it("adjustTrove(): Reverts if borrower has insufficient EBTC balance to cover his debt repayment", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: B } })

      const BIndex = await sortedTroves.troveOfOwnerByIndex(B,0)
      const bobDebt = await getTroveEntireDebt(BIndex)

      // Bob transfers some EBTC to carol
      await lusdToken.transfer(C, dec(10, 18), { from: B })

      //Confirm B's EBTC balance is less than 50 EBTC
      const B_EBTCBal = await lusdToken.balanceOf(B)
      assert.isTrue(B_EBTCBal.lt(bobDebt))

      const repayEBTCPromise_B = borrowerOperations.adjustTrove(BIndex, th._100pct, 0, bobDebt, false, BIndex, BIndex, { from: B })

      // B attempts to repay all his debt
      await assertRevert(repayEBTCPromise_B, "revert")
    })

    // --- Internal _adjustTrove() ---

    if (!withProxy) { // no need to test this with proxies
      xit("Internal _adjustTrove(): reverts when op is a withdrawal and _borrower param is not the msg.sender", async () => {
        await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
        await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: bob } })

//        const txPromise_A = borrowerOperations.callInternalAdjustLoan(alice, dec(1, 18), dec(1, 18), true, alice, alice, { from: bob })
//        await assertRevert(txPromise_A, "BorrowerOps: Caller must be the borrower for a withdrawal")
//        const txPromise_B = borrowerOperations.callInternalAdjustLoan(bob, dec(1, 18), dec(1, 18), true, alice, alice, { from: owner })
//        await assertRevert(txPromise_B, "BorrowerOps: Caller must be the borrower for a withdrawal")
//        const txPromise_C = borrowerOperations.callInternalAdjustLoan(carol, dec(1, 18), dec(1, 18), true, alice, alice, { from: bob })
//        await assertRevert(txPromise_C, "BorrowerOps: Caller must be the borrower for a withdrawal")
      })
    }

    // --- closeTrove() ---

    it("closeTrove(): reverts when it would lower the TCR below CCR", async () => {
      await openTrove({ ICR: toBN(dec(300, 16)), extraParams:{ from: alice } })
      await openTrove({ ICR: toBN(dec(120, 16)), extraEBTCAmount: toBN(dec(300, 18)), extraParams:{ from: bob } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)

      const price = await priceFeed.getPrice()
      
      // to compensate borrowing fees
      await lusdToken.transfer(alice, dec(300, 18), { from: bob })

      assert.isFalse(await troveManager.checkRecoveryMode(price))
    
      await assertRevert(
        borrowerOperations.closeTrove(aliceIndex, { from: alice }),
        "BorrowerOps: An operation that would result in TCR < CCR is not permitted"
      )
    })

    it("closeTrove(): reverts when calling address does not own specified trove", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: bob } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)

      // Carol with no active trove attempts to close a non-existant trove
      try {
        const txCarol = await borrowerOperations.closeTrove(aliceIndex, { from: carol })
        assert.isFalse(txCarol.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    it("closeTrove(): reverts when specified trove does not exist", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: bob } })

      const carolIndex = th.RANDOM_INDEX;

      // Carol with no active trove attempts to close a non-existant trove
      try {
        const txCarol = await borrowerOperations.closeTrove(carolIndex, { from: carol })
        assert.isFalse(txCarol.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    it("closeTrove(): reverts when system is in Recovery Mode", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(100000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: bob } })
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: carol } })

      const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)
      const carolIndex = await sortedTroves.troveOfOwnerByIndex(carol,0)

      // Alice transfers her EBTC to Bob and Carol so they can cover fees
      const aliceBal = await lusdToken.balanceOf(alice)
      await lusdToken.transfer(bob, aliceBal.div(toBN(2)), { from: alice })
      await lusdToken.transfer(carol, aliceBal.div(toBN(2)), { from: alice })

      // check Recovery Mode 
      assert.isFalse(await th.checkRecoveryMode(contracts))

      // Bob successfully closes his trove
      const txBob = await borrowerOperations.closeTrove(bobIndex, { from: bob })
      assert.isTrue(txBob.receipt.status)

      await priceFeed.setPrice(dec(100, 18))

      assert.isTrue(await th.checkRecoveryMode(contracts))

      // Carol attempts to close her trove during Recovery Mode
      await assertRevert(borrowerOperations.closeTrove(carolIndex, { from: carol }), "BorrowerOps: Operation not permitted during Recovery Mode")
    })

    it("closeTrove(): reverts when trove is the only one in the system", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(100000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)

      // Artificially mint to Alice so she has enough to close her trove
      await lusdToken.unprotectedMint(alice, dec(100000, 18))

      // Check she has more EBTC than her trove debt
      const aliceBal = await lusdToken.balanceOf(alice)
      const aliceDebt = await getTroveEntireDebt(aliceIndex)
      assert.isTrue(aliceBal.gt(aliceDebt))

      // check Recovery Mode
      assert.isFalse(await th.checkRecoveryMode(contracts))

      // Alice attempts to close her trove
      await assertRevert(borrowerOperations.closeTrove(aliceIndex, { from: alice }), "TroveManager: Only one trove in the system")
    })

    it("closeTrove(): reduces a Trove's collateral to zero", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: dennis } })
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)

      const aliceCollBefore = await getTroveEntireColl(aliceIndex)
      const dennisEBTC = await lusdToken.balanceOf(dennis)
      assert.isTrue(aliceCollBefore.gt(toBN('0')))
      assert.isTrue(dennisEBTC.gt(toBN('0')))

      // To compensate borrowing fees
      await lusdToken.transfer(alice, dennisEBTC.div(toBN(2)), { from: dennis })

      // Alice attempts to close trove
      await borrowerOperations.closeTrove(aliceIndex, { from: alice })

      const aliceCollAfter = await getTroveEntireColl(aliceIndex)
      assert.equal(aliceCollAfter, '0')
    })

    it("closeTrove(): reduces a Trove's debt to zero", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: dennis } })
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)

      const aliceDebtBefore = await getTroveEntireColl(aliceIndex)
      const dennisEBTC = await lusdToken.balanceOf(dennis)
      assert.isTrue(aliceDebtBefore.gt(toBN('0')))
      assert.isTrue(dennisEBTC.gt(toBN('0')))

      // To compensate borrowing fees
      await lusdToken.transfer(alice, dennisEBTC.div(toBN(2)), { from: dennis })

      // Alice attempts to close trove
      await borrowerOperations.closeTrove(aliceIndex, { from: alice })

      const aliceCollAfter = await getTroveEntireColl(aliceIndex)
      assert.equal(aliceCollAfter, '0')
    })

    it("closeTrove(): sets Trove's stake to zero", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: dennis } })
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)

      const aliceStakeBefore = await getTroveStake(aliceIndex)
      assert.isTrue(aliceStakeBefore.gt(toBN('0')))

      const dennisEBTC = await lusdToken.balanceOf(dennis)
      assert.isTrue(aliceStakeBefore.gt(toBN('0')))
      assert.isTrue(dennisEBTC.gt(toBN('0')))

      // To compensate borrowing fees
      await lusdToken.transfer(alice, dennisEBTC.div(toBN(2)), { from: dennis })

      // Alice attempts to close trove
      await borrowerOperations.closeTrove(aliceIndex, { from: alice })

      const stakeAfter = ((await troveManager.Troves(aliceIndex))[2]).toString()
      assert.equal(stakeAfter, '0')
      // check withdrawal was successful
    })

    it("closeTrove(): zero's the troves reward snapshots", async () => {
      // Dennis opens trove and transfers tokens to alice
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: dennis } })
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: bob } })

      const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)
      
      // Price drops
      await priceFeed.setPrice(dec(100, 18))

      // Liquidate Bob
      await troveManager.liquidate(bobIndex)
      assert.isFalse(await sortedTroves.contains(bobIndex))

      // Price bounces back
      await priceFeed.setPrice(dec(200, 18))

      // Alice and Carol open troves
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: carol } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
      const carolIndex = await sortedTroves.troveOfOwnerByIndex(carol,0)

      // Price drops ...again
      await priceFeed.setPrice(dec(100, 18))

      // Get Alice's pending reward snapshots 
      const L_ETH_A_Snapshot = (await troveManager.rewardSnapshots(aliceIndex))[0]
      const L_EBTCDebt_A_Snapshot = (await troveManager.rewardSnapshots(aliceIndex))[1]
      assert.isTrue(L_ETH_A_Snapshot.gt(toBN('0')))
      assert.isTrue(L_EBTCDebt_A_Snapshot.gt(toBN('0')))

      // Liquidate Carol
      await troveManager.liquidate(carolIndex)
      assert.isFalse(await sortedTroves.contains(carolIndex))

      // Get Alice's pending reward snapshots after Carol's liquidation. Check above 0
      const L_ETH_Snapshot_A_AfterLiquidation = (await troveManager.rewardSnapshots(aliceIndex))[0]
      const L_EBTCDebt_Snapshot_A_AfterLiquidation = (await troveManager.rewardSnapshots(aliceIndex))[1]

      assert.isTrue(L_ETH_Snapshot_A_AfterLiquidation.gt(toBN('0')))
      assert.isTrue(L_EBTCDebt_Snapshot_A_AfterLiquidation.gt(toBN('0')))

      // to compensate borrowing fees
      await lusdToken.transfer(alice, await lusdToken.balanceOf(dennis), { from: dennis })

      await priceFeed.setPrice(dec(200, 18))

      // Alice closes trove
      await borrowerOperations.closeTrove(aliceIndex, { from: alice })

      // Check Alice's pending reward snapshots are zero
      const L_ETH_Snapshot_A_afterAliceCloses = (await troveManager.rewardSnapshots(aliceIndex))[0]
      const L_EBTCDebt_Snapshot_A_afterAliceCloses = (await troveManager.rewardSnapshots(aliceIndex))[1]

      assert.equal(L_ETH_Snapshot_A_afterAliceCloses, '0')
      assert.equal(L_EBTCDebt_Snapshot_A_afterAliceCloses, '0')
    })

    it("closeTrove(): sets trove's status to closed and removes it from sorted troves list", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: dennis } })
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)

      // Check Trove is active
      const alice_Trove_Before = await troveManager.Troves(aliceIndex)
      const status_Before = alice_Trove_Before[3]

      assert.equal(status_Before, 1)
      assert.isTrue(await sortedTroves.contains(aliceIndex))

      // to compensate borrowing fees
      await lusdToken.transfer(alice, await lusdToken.balanceOf(dennis), { from: dennis })

      // Close the trove
      await borrowerOperations.closeTrove(aliceIndex, { from: alice })

      const alice_Trove_After = await troveManager.Troves(aliceIndex)
      const status_After = alice_Trove_After[3]

      assert.equal(status_After, 2)
      assert.isFalse(await sortedTroves.contains(aliceIndex))
    })

    it("closeTrove(): reduces ActivePool ETH and raw ether by correct amount", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: dennis } })
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
      const dennisIndex = await sortedTroves.troveOfOwnerByIndex(dennis,0)

      const dennisColl = await getTroveEntireColl(dennisIndex)
      const aliceColl = await getTroveEntireColl(aliceIndex)
      assert.isTrue(dennisColl.gt('0'))
      assert.isTrue(aliceColl.gt('0'))

      // Check active Pool ETH before
      const activePool_ETH_before = await activePool.getETH()
      const activePool_RawEther_before = toBN(await web3.eth.getBalance(activePool.address))
      assert.isTrue(activePool_ETH_before.eq(aliceColl.add(dennisColl)))
      assert.isTrue(activePool_ETH_before.gt(toBN('0')))
      assert.isTrue(activePool_RawEther_before.eq(activePool_ETH_before))

      // to compensate borrowing fees
      await lusdToken.transfer(alice, await lusdToken.balanceOf(dennis), { from: dennis })

      // Close the trove
      await borrowerOperations.closeTrove(aliceIndex, { from: alice })

      // Check after
      const activePool_ETH_After = await activePool.getETH()
      const activePool_RawEther_After = toBN(await web3.eth.getBalance(activePool.address))
      assert.isTrue(activePool_ETH_After.eq(dennisColl))
      assert.isTrue(activePool_RawEther_After.eq(dennisColl))
    })

    it("closeTrove(): reduces ActivePool debt by correct amount", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: dennis } })
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
      const dennisIndex = await sortedTroves.troveOfOwnerByIndex(dennis,0)

      const dennisDebt = await getTroveEntireDebt(dennisIndex)
      const aliceDebt = await getTroveEntireDebt(aliceIndex)
      assert.isTrue(dennisDebt.gt('0'))
      assert.isTrue(aliceDebt.gt('0'))

      // Check before
      const activePool_Debt_before = await activePool.getEBTCDebt()
      assert.isTrue(activePool_Debt_before.eq(aliceDebt.add(dennisDebt)))
      assert.isTrue(activePool_Debt_before.gt(toBN('0')))

      // to compensate borrowing fees
      await lusdToken.transfer(alice, await lusdToken.balanceOf(dennis), { from: dennis })

      // Close the trove
      await borrowerOperations.closeTrove(aliceIndex, { from: alice })

      // Check after
      const activePool_Debt_After = (await activePool.getEBTCDebt()).toString()
      th.assertIsApproximatelyEqual(activePool_Debt_After, dennisDebt)
    })

    it("closeTrove(): updates the the total stakes", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: dennis } })
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: bob } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
      const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)
      const dennisIndex = await sortedTroves.troveOfOwnerByIndex(dennis,0)

      // Get individual stakes
      const aliceStakeBefore = await getTroveStake(aliceIndex)
      const bobStakeBefore = await getTroveStake(bobIndex)
      const dennisStakeBefore = await getTroveStake(dennisIndex)
      assert.isTrue(aliceStakeBefore.gt('0'))
      assert.isTrue(bobStakeBefore.gt('0'))
      assert.isTrue(dennisStakeBefore.gt('0'))

      const totalStakesBefore = await troveManager.totalStakes()

      assert.isTrue(totalStakesBefore.eq(aliceStakeBefore.add(bobStakeBefore).add(dennisStakeBefore)))

      // to compensate borrowing fees
      await lusdToken.transfer(alice, await lusdToken.balanceOf(dennis), { from: dennis })

      // Alice closes trove
      await borrowerOperations.closeTrove(aliceIndex, { from: alice })

      // Check stake and total stakes get updated
      const aliceStakeAfter = await getTroveStake(aliceIndex)
      const totalStakesAfter = await troveManager.totalStakes()

      assert.equal(aliceStakeAfter, 0)
      assert.isTrue(totalStakesAfter.eq(totalStakesBefore.sub(aliceStakeBefore)))
    })

    if (!withProxy) { // TODO: wrap web3.eth.getBalance to be able to go through proxies
      xit("closeTrove(): sends the correct amount of ETH to the user", async () => {
        await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: dennis } })
        await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })

        const aliceColl = await getTroveEntireColl(aliceIndex)
        assert.isTrue(aliceColl.gt(toBN('0')))

        const alice_ETHBalance_Before = web3.utils.toBN(await web3.eth.getBalance(alice))

        // to compensate borrowing fees
        await lusdToken.transfer(alice, await lusdToken.balanceOf(dennis), { from: dennis })

        await borrowerOperations.closeTrove(aliceIndex, { from: alice, gasPrice: 0 })

        const alice_ETHBalance_After = web3.utils.toBN(await web3.eth.getBalance(alice))
        const balanceDiff = alice_ETHBalance_After.sub(alice_ETHBalance_Before)

        assert.isTrue(balanceDiff.eq(aliceColl))
      })
    }

    it("closeTrove(): subtracts the debt of the closed Trove from the Borrower's EBTCToken balance", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: dennis } })
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)

      const aliceDebt = await getTroveEntireDebt(aliceIndex)
      assert.isTrue(aliceDebt.gt(toBN('0')))

      // to compensate borrowing fees
      await lusdToken.transfer(alice, await lusdToken.balanceOf(dennis), { from: dennis })

      const alice_EBTCBalance_Before = await lusdToken.balanceOf(alice)
      assert.isTrue(alice_EBTCBalance_Before.gt(toBN('0')))

      // close trove
      await borrowerOperations.closeTrove(aliceIndex, { from: alice })

      // check alice EBTC balance after
      const alice_EBTCBalance_After = await lusdToken.balanceOf(alice)
      th.assertIsApproximatelyEqual(alice_EBTCBalance_After, alice_EBTCBalance_Before.sub(aliceDebt.sub(EBTC_GAS_COMPENSATION)))
    })

    it("closeTrove(): applies pending rewards", async () => {
      // --- SETUP ---
      await openTrove({ extraEBTCAmount: toBN(dec(1000000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })

      const whaleIndex = await sortedTroves.troveOfOwnerByIndex(whale,0)

      const whaleDebt = await getTroveEntireDebt(whaleIndex)
      const whaleColl = await getTroveEntireColl(whaleIndex)

      await openTrove({ extraEBTCAmount: toBN(dec(15000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openTrove({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: bob } })
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: carol } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
      const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)
      const carolIndex = await sortedTroves.troveOfOwnerByIndex(carol,0)

      const carolDebt = await getTroveEntireDebt(carolIndex)
      const carolColl = await getTroveEntireColl(carolIndex)

      // Whale transfers to A and B to cover their fees
      await lusdToken.transfer(alice, dec(10000, 18), { from: whale })
      await lusdToken.transfer(bob, dec(10000, 18), { from: whale })

      // --- TEST ---

      // price drops to 1ETH:100EBTC, reducing Carol's ICR below MCR
      await priceFeed.setPrice(dec(100, 18));
      const price = await priceFeed.getPrice()

      // liquidate Carol's Trove, Alice and Bob earn rewards.
      const liquidationTx = await troveManager.liquidate(carolIndex, { from: owner });
      const [liquidatedDebt_C, liquidatedColl_C, gasComp_C] = th.getEmittedLiquidationValues(liquidationTx)

      // Dennis opens a new Trove (Carol?)
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: carol } })

      const carolIndex2 = await sortedTroves.troveOfOwnerByIndex(carol,0)

      // Second trove should have a new index
      assert.notEqual(carolIndex, carolIndex2);

      // check Alice and Bob's reward snapshots are zero before they alter their Troves
      const alice_rewardSnapshot_Before = await troveManager.rewardSnapshots(aliceIndex)
      const alice_ETHrewardSnapshot_Before = alice_rewardSnapshot_Before[0]
      const alice_EBTCDebtRewardSnapshot_Before = alice_rewardSnapshot_Before[1]

      const bob_rewardSnapshot_Before = await troveManager.rewardSnapshots(bobIndex)
      const bob_ETHrewardSnapshot_Before = bob_rewardSnapshot_Before[0]
      const bob_EBTCDebtRewardSnapshot_Before = bob_rewardSnapshot_Before[1]

      assert.equal(alice_ETHrewardSnapshot_Before, 0)
      assert.equal(alice_EBTCDebtRewardSnapshot_Before, 0)
      assert.equal(bob_ETHrewardSnapshot_Before, 0)
      assert.equal(bob_EBTCDebtRewardSnapshot_Before, 0)

      const defaultPool_ETH = await defaultPool.getETH()
      const defaultPool_EBTCDebt = await defaultPool.getEBTCDebt()

      // Carol's liquidated coll (1 ETH) and drawn debt should have entered the Default Pool
      assert.isAtMost(th.getDifference(defaultPool_ETH, liquidatedColl_C), 100)
      assert.isAtMost(th.getDifference(defaultPool_EBTCDebt, liquidatedDebt_C), 100)

      const pendingCollReward_A = await troveManager.getPendingETHReward(aliceIndex)
      const pendingDebtReward_A = await troveManager.getPendingEBTCDebtReward(aliceIndex)
      assert.isTrue(pendingCollReward_A.gt('0'))
      assert.isTrue(pendingDebtReward_A.gt('0'))

      // Close Alice's trove. Alice's pending rewards should be removed from the DefaultPool when she close.
      await borrowerOperations.closeTrove(aliceIndex, { from: alice })

      const defaultPool_ETH_afterAliceCloses = await defaultPool.getETH()
      const defaultPool_EBTCDebt_afterAliceCloses = await defaultPool.getEBTCDebt()

      assert.isAtMost(th.getDifference(defaultPool_ETH_afterAliceCloses,
        defaultPool_ETH.sub(pendingCollReward_A)), 1000)
      assert.isAtMost(th.getDifference(defaultPool_EBTCDebt_afterAliceCloses,
        defaultPool_EBTCDebt.sub(pendingDebtReward_A)), 1000)

      // whale adjusts trove, pulling their rewards out of DefaultPool
      await borrowerOperations.adjustTrove(whaleIndex, th._100pct, 0, dec(1, 18), true, whaleIndex, whaleIndex, { from: whale })

      // Close Bob's trove. Expect DefaultPool coll and debt to drop to 0, since closing pulls his rewards out.
      await borrowerOperations.closeTrove(bobIndex, { from: bob })

      const defaultPool_ETH_afterBobCloses = await defaultPool.getETH()
      const defaultPool_EBTCDebt_afterBobCloses = await defaultPool.getEBTCDebt()

      assert.isAtMost(th.getDifference(defaultPool_ETH_afterBobCloses, 0), 100000)
      assert.isAtMost(th.getDifference(defaultPool_EBTCDebt_afterBobCloses, 0), 100000)
    })

    it("closeTrove(): reverts if borrower has insufficient EBTC balance to repay his entire debt", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(15000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openTrove({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })

      const AIndex = await sortedTroves.troveOfOwnerByIndex(A,0)
      const BIndex = await sortedTroves.troveOfOwnerByIndex(B,0)

      //Confirm Bob's EBTC balance is less than his trove debt
      const B_EBTCBal = await lusdToken.balanceOf(B)
      const B_troveDebt = await getTroveEntireDebt(BIndex)

      assert.isTrue(B_EBTCBal.lt(B_troveDebt))

      const closeTrovePromise_B = borrowerOperations.closeTrove(BIndex, { from: B })

      // Check closing trove reverts
      await assertRevert(closeTrovePromise_B, "BorrowerOps: Caller doesnt have enough EBTC to make repayment")
    })

    // --- openTrove() ---

    if (!withProxy) { // TODO: use rawLogs instead of logs
      it("openTrove(): emits a TroveUpdated event with the correct collateral and debt", async () => {
        const txA = (await openTrove({ extraEBTCAmount: toBN(dec(15000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })).tx
        const txB = (await openTrove({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })).tx
        const txC = (await openTrove({ extraEBTCAmount: toBN(dec(3000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })).tx

        const AIndex = await sortedTroves.troveOfOwnerByIndex(A,0)
        const BIndex = await sortedTroves.troveOfOwnerByIndex(B,0)
        const CIndex = await sortedTroves.troveOfOwnerByIndex(C,0)

        const A_Coll = await getTroveEntireColl(AIndex)
        const B_Coll = await getTroveEntireColl(BIndex)
        const C_Coll = await getTroveEntireColl(CIndex)
        const A_Debt = await getTroveEntireDebt(AIndex)
        const B_Debt = await getTroveEntireDebt(BIndex)
        const C_Debt = await getTroveEntireDebt(CIndex)

        const A_emittedDebt = toBN(th.getEventArgByName(txA, "TroveUpdated", "_debt"))
        const A_emittedColl = toBN(th.getEventArgByName(txA, "TroveUpdated", "_coll"))
        const B_emittedDebt = toBN(th.getEventArgByName(txB, "TroveUpdated", "_debt"))
        const B_emittedColl = toBN(th.getEventArgByName(txB, "TroveUpdated", "_coll"))
        const C_emittedDebt = toBN(th.getEventArgByName(txC, "TroveUpdated", "_debt"))
        const C_emittedColl = toBN(th.getEventArgByName(txC, "TroveUpdated", "_coll"))

        // Check emitted debt values are correct
        assert.isTrue(A_Debt.eq(A_emittedDebt))
        assert.isTrue(B_Debt.eq(B_emittedDebt))
        assert.isTrue(C_Debt.eq(C_emittedDebt))

        // Check emitted coll values are correct
        assert.isTrue(A_Coll.eq(A_emittedColl))
        assert.isTrue(B_Coll.eq(B_emittedColl))
        assert.isTrue(C_Coll.eq(C_emittedColl))

        const baseRateBefore = await troveManager.baseRate()

        // Artificially make baseRate 5%
        await troveManager.setBaseRate(dec(5, 16))
        await troveManager.setLastFeeOpTimeToNow()

        assert.isTrue((await troveManager.baseRate()).gt(baseRateBefore))

        const txD = (await openTrove({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })).tx
        const txE = (await openTrove({ extraEBTCAmount: toBN(dec(3000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: E } })).tx

        const DIndex = await sortedTroves.troveOfOwnerByIndex(D,0)
        const EIndex = await sortedTroves.troveOfOwnerByIndex(E,0)
        
        const D_Coll = await getTroveEntireColl(DIndex)
        const E_Coll = await getTroveEntireColl(EIndex)
        const D_Debt = await getTroveEntireDebt(DIndex)
        const E_Debt = await getTroveEntireDebt(EIndex)

        const D_emittedDebt = toBN(th.getEventArgByName(txD, "TroveUpdated", "_debt"))
        const D_emittedColl = toBN(th.getEventArgByName(txD, "TroveUpdated", "_coll"))

        const E_emittedDebt = toBN(th.getEventArgByName(txE, "TroveUpdated", "_debt"))
        const E_emittedColl = toBN(th.getEventArgByName(txE, "TroveUpdated", "_coll"))

        // Check emitted debt values are correct
        assert.isTrue(D_Debt.eq(D_emittedDebt))
        assert.isTrue(E_Debt.eq(E_emittedDebt))

        // Check emitted coll values are correct
        assert.isTrue(D_Coll.eq(D_emittedColl))
        assert.isTrue(E_Coll.eq(E_emittedColl))
      })
    }

    it("openTrove(): Opens a trove with net debt >= minimum net debt", async () => {
      // Add 1 wei to correct for rounding error in helper function
      const txA = await borrowerOperations.openTrove(th._100pct, await getNetBorrowingAmount(MIN_NET_DEBT.add(toBN(1))), th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: A, value: dec(100, 30) })
      assert.isTrue(txA.receipt.status)
      const AIndex = await sortedTroves.troveOfOwnerByIndex(A,0)
      assert.isTrue(await sortedTroves.contains(AIndex))

      const txC = await borrowerOperations.openTrove(th._100pct, await getNetBorrowingAmount(MIN_NET_DEBT.add(toBN(dec(47789898, 22)))), th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: C, value: dec(100, 30) })
      assert.isTrue(txC.receipt.status)

      const CIndex = await sortedTroves.troveOfOwnerByIndex(C,0)
      assert.isTrue(await sortedTroves.contains(CIndex))
    })

    it("openTrove(): reverts if net debt < minimum net debt", async () => {
      const txAPromise = borrowerOperations.openTrove(th._100pct, 0, th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: A, value: dec(100, 30) })
      await assertRevert(txAPromise, "revert")

      const txBPromise = borrowerOperations.openTrove(th._100pct, await getNetBorrowingAmount(MIN_NET_DEBT.sub(toBN(1))), th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: B, value: dec(100, 30) })
      await assertRevert(txBPromise, "revert")

      const txCPromise = borrowerOperations.openTrove(th._100pct, MIN_NET_DEBT.sub(toBN(dec(173, 18))), th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: C, value: dec(100, 30) })
      await assertRevert(txCPromise, "revert")
    })

    it("openTrove(): decays a non-zero base rate", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openTrove({ extraEBTCAmount: toBN(dec(20000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openTrove({ extraEBTCAmount: toBN(dec(30000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openTrove({ extraEBTCAmount: toBN(dec(40000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })

      // Artificially make baseRate 5%
      await troveManager.setBaseRate(dec(5, 16))
      await troveManager.setLastFeeOpTimeToNow()

      // Check baseRate is now non-zero
      const baseRate_1 = await troveManager.baseRate()
      assert.isTrue(baseRate_1.gt(toBN('0')))

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      // D opens trove 
      await openTrove({ extraEBTCAmount: toBN(dec(37, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      // Check baseRate has decreased
      const baseRate_2 = await troveManager.baseRate()
      assert.isTrue(baseRate_2.lt(baseRate_1))

      // 1 hour passes
      th.fastForwardTime(3600, web3.currentProvider)

      // E opens trove 
      await openTrove({ extraEBTCAmount: toBN(dec(12, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: E } })

      const baseRate_3 = await troveManager.baseRate()
      assert.isTrue(baseRate_3.lt(baseRate_2))
    })

    it("openTrove(): doesn't change base rate if it is already zero", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openTrove({ extraEBTCAmount: toBN(dec(20000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openTrove({ extraEBTCAmount: toBN(dec(30000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openTrove({ extraEBTCAmount: toBN(dec(40000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })

      // Check baseRate is zero
      const baseRate_1 = await troveManager.baseRate()
      assert.equal(baseRate_1, '0')

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      // D opens trove 
      await openTrove({ extraEBTCAmount: toBN(dec(37, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      // Check baseRate is still 0
      const baseRate_2 = await troveManager.baseRate()
      assert.equal(baseRate_2, '0')

      // 1 hour passes
      th.fastForwardTime(3600, web3.currentProvider)

      // E opens trove 
      await openTrove({ extraEBTCAmount: toBN(dec(12, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: E } })

      const baseRate_3 = await troveManager.baseRate()
      assert.equal(baseRate_3, '0')
    })

    it("openTrove(): lastFeeOpTime doesn't update if less time than decay interval has passed since the last fee operation", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openTrove({ extraEBTCAmount: toBN(dec(20000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openTrove({ extraEBTCAmount: toBN(dec(30000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openTrove({ extraEBTCAmount: toBN(dec(40000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })

      // Artificially make baseRate 5%
      await troveManager.setBaseRate(dec(5, 16))
      await troveManager.setLastFeeOpTimeToNow()

      // Check baseRate is now non-zero
      const baseRate_1 = await troveManager.baseRate()
      assert.isTrue(baseRate_1.gt(toBN('0')))

      const lastFeeOpTime_1 = await troveManager.lastFeeOperationTime()

      // Borrower D triggers a fee
      await openTrove({ extraEBTCAmount: toBN(dec(1, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      const lastFeeOpTime_2 = await troveManager.lastFeeOperationTime()

      // Check that the last fee operation time did not update, as borrower D's debt issuance occured
      // since before minimum interval had passed 
      assert.isTrue(lastFeeOpTime_2.eq(lastFeeOpTime_1))

      // 1 minute passes
      th.fastForwardTime(60, web3.currentProvider)

      // Check that now, at least one minute has passed since lastFeeOpTime_1
      const timeNow = await th.getLatestBlockTimestamp(web3)
      assert.isTrue(toBN(timeNow).sub(lastFeeOpTime_1).gte(3600))

      // Borrower E triggers a fee
      await openTrove({ extraEBTCAmount: toBN(dec(1, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: E } })

      const lastFeeOpTime_3 = await troveManager.lastFeeOperationTime()

      // Check that the last fee operation time DID update, as borrower's debt issuance occured
      // after minimum interval had passed 
      assert.isTrue(lastFeeOpTime_3.gt(lastFeeOpTime_1))
    })

    it("openTrove(): reverts if max fee > 100%", async () => {
      await assertRevert(borrowerOperations.openTrove(dec(2, 18), dec(10000, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: A, value: dec(1000, 'ether') }), "Max fee percentage must be between 0.5% and 100%")
      await assertRevert(borrowerOperations.openTrove('1000000000000000001', dec(20000, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: B, value: dec(1000, 'ether') }), "Max fee percentage must be between 0.5% and 100%")
    })

    it("openTrove(): reverts if max fee < 0.5% in Normal mode", async () => {
      await assertRevert(borrowerOperations.openTrove(0, dec(195000, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: A, value: dec(1200, 'ether') }), "Max fee percentage must be between 0.5% and 100%")
      await assertRevert(borrowerOperations.openTrove(1, dec(195000, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: A, value: dec(1000, 'ether') }), "Max fee percentage must be between 0.5% and 100%")
      await assertRevert(borrowerOperations.openTrove('4999999999999999', dec(195000, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: B, value: dec(1200, 'ether') }), "Max fee percentage must be between 0.5% and 100%")
    })

    it("openTrove(): allows max fee < 0.5% in Recovery Mode", async () => {
      await borrowerOperations.openTrove(th._100pct, dec(195000, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: A, value: dec(2000, 'ether') })

      await priceFeed.setPrice(dec(100, 18))
      assert.isTrue(await th.checkRecoveryMode(contracts))

      await borrowerOperations.openTrove(0, dec(19500, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: B, value: dec(3100, 'ether') })
      await priceFeed.setPrice(dec(50, 18))
      assert.isTrue(await th.checkRecoveryMode(contracts))

      await borrowerOperations.openTrove(1, dec(19500, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: C, value: dec(3100, 'ether') })
      await priceFeed.setPrice(dec(25, 18))
      assert.isTrue(await th.checkRecoveryMode(contracts))

      await borrowerOperations.openTrove('4999999999999999', dec(19500, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: D, value: dec(3100, 'ether') })
    })

    it("openTrove(): reverts if fee exceeds max fee percentage", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(20000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openTrove({ extraEBTCAmount: toBN(dec(30000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openTrove({ extraEBTCAmount: toBN(dec(40000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })

      const AIndex = await sortedTroves.troveOfOwnerByIndex(A,0)
      const BIndex = await sortedTroves.troveOfOwnerByIndex(B,0)
      const CIndex = await sortedTroves.troveOfOwnerByIndex(C,0)

      const totalSupply = await lusdToken.totalSupply()

      // Artificially make baseRate 5%
      await troveManager.setBaseRate(dec(5, 16))
      await troveManager.setLastFeeOpTimeToNow()

      //       actual fee percentage: 0.005000000186264514
      // user's max fee percentage:  0.0049999999999999999
      let borrowingRate = await troveManager.getBorrowingRate() // expect max(0.5 + 5%, 5%) rate
      assert.equal(borrowingRate, dec(5, 16))

      const lessThan5pct = '49999999999999999'
      await assertRevert(borrowerOperations.openTrove(lessThan5pct, dec(30000, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: D, value: dec(1000, 'ether') }), "Fee exceeded provided maximum")

      borrowingRate = await troveManager.getBorrowingRate() // expect 5% rate
      assert.equal(borrowingRate, dec(5, 16))
      // Attempt with maxFee 1%
      await assertRevert(borrowerOperations.openTrove(dec(1, 16), dec(30000, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: D, value: dec(1000, 'ether') }), "Fee exceeded provided maximum")

      borrowingRate = await troveManager.getBorrowingRate() // expect 5% rate
      assert.equal(borrowingRate, dec(5, 16))
      // Attempt with maxFee 3.754%
      await assertRevert(borrowerOperations.openTrove(dec(3754, 13), dec(30000, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: D, value: dec(1000, 'ether') }), "Fee exceeded provided maximum")

      borrowingRate = await troveManager.getBorrowingRate() // expect 5% rate
      assert.equal(borrowingRate, dec(5, 16))
      // Attempt with maxFee 1e-16%
      await assertRevert(borrowerOperations.openTrove(dec(5, 15), dec(30000, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: D, value: dec(1000, 'ether') }), "Fee exceeded provided maximum")
    })

    it("openTrove(): succeeds when fee is less than max fee percentage", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(20000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openTrove({ extraEBTCAmount: toBN(dec(30000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openTrove({ extraEBTCAmount: toBN(dec(40000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })

      // Artificially make baseRate 5%
      await troveManager.setBaseRate(dec(5, 16))
      await troveManager.setLastFeeOpTimeToNow()

      let borrowingRate = await troveManager.getBorrowingRate() // expect min(0.5 + 5%, 5%) rate
      assert.equal(borrowingRate, dec(5, 16))

      // Attempt with maxFee > 5%
      const moreThan5pct = '50000000000000001'
      const tx1 = await borrowerOperations.openTrove(moreThan5pct, dec(10000, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: D, value: dec(100, 'ether') })
      assert.isTrue(tx1.receipt.status)

      borrowingRate = await troveManager.getBorrowingRate() // expect 5% rate
      assert.equal(borrowingRate, dec(5, 16))

      // Attempt with maxFee = 5%
      const tx2 = await borrowerOperations.openTrove(dec(5, 16), dec(10000, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: H, value: dec(100, 'ether') })
      assert.isTrue(tx2.receipt.status)

      borrowingRate = await troveManager.getBorrowingRate() // expect 5% rate
      assert.equal(borrowingRate, dec(5, 16))

      // Attempt with maxFee 10%
      const tx3 = await borrowerOperations.openTrove(dec(1, 17), dec(10000, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: E, value: dec(100, 'ether') })
      assert.isTrue(tx3.receipt.status)

      borrowingRate = await troveManager.getBorrowingRate() // expect 5% rate
      assert.equal(borrowingRate, dec(5, 16))

      // Attempt with maxFee 37.659%
      const tx4 = await borrowerOperations.openTrove(dec(37659, 13), dec(10000, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: F, value: dec(100, 'ether') })
      assert.isTrue(tx4.receipt.status)

      // Attempt with maxFee 100%
      const tx5 = await borrowerOperations.openTrove(dec(1, 18), dec(10000, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: G, value: dec(100, 'ether') })
      assert.isTrue(tx5.receipt.status)
    })

    it("openTrove(): borrower can't grief the baseRate and stop it decaying by issuing debt at higher frequency than the decay granularity", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openTrove({ extraEBTCAmount: toBN(dec(20000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openTrove({ extraEBTCAmount: toBN(dec(30000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openTrove({ extraEBTCAmount: toBN(dec(40000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })

      // Artificially make baseRate 5%
      await troveManager.setBaseRate(dec(5, 16))
      await troveManager.setLastFeeOpTimeToNow()

      // Check baseRate is non-zero
      const baseRate_1 = await troveManager.baseRate()
      assert.isTrue(baseRate_1.gt(toBN('0')))

      // 59 minutes pass
      th.fastForwardTime(3540, web3.currentProvider)

      // Assume Borrower also owns accounts D and E
      // Borrower triggers a fee, before decay interval has passed
      await openTrove({ extraEBTCAmount: toBN(dec(1, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      // 1 minute pass
      th.fastForwardTime(3540, web3.currentProvider)

      // Borrower triggers another fee
      await openTrove({ extraEBTCAmount: toBN(dec(1, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: E } })

      // Check base rate has decreased even though Borrower tried to stop it decaying
      const baseRate_2 = await troveManager.baseRate()
      assert.isTrue(baseRate_2.lt(baseRate_1))
    })

    it("openTrove(): borrowing at non-zero base rate sends EBTC fee to LQTY staking contract", async () => {
      // time fast-forwards 1 year, and multisig stakes 1 LQTY
      await th.fastForwardTime(timeValues.SECONDS_IN_ONE_YEAR, web3.currentProvider)
      await lqtyToken.approve(lqtyStaking.address, dec(1, 18), { from: multisig })
      await lqtyStaking.stake(dec(1, 18), { from: multisig })

      // Check LQTY EBTC balance before == 0
      const lqtyStaking_EBTCBalance_Before = await lusdToken.balanceOf(lqtyStaking.address)
      assert.equal(lqtyStaking_EBTCBalance_Before, '0')

      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openTrove({ extraEBTCAmount: toBN(dec(20000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openTrove({ extraEBTCAmount: toBN(dec(30000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openTrove({ extraEBTCAmount: toBN(dec(40000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })

      // Artificially make baseRate 5%
      await troveManager.setBaseRate(dec(5, 16))
      await troveManager.setLastFeeOpTimeToNow()

      // Check baseRate is now non-zero
      const baseRate_1 = await troveManager.baseRate()
      assert.isTrue(baseRate_1.gt(toBN('0')))

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      // D opens trove 
      await openTrove({ extraEBTCAmount: toBN(dec(40000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      // Check LQTY EBTC balance after has increased
      const lqtyStaking_EBTCBalance_After = await lusdToken.balanceOf(lqtyStaking.address)
      assert.isTrue(lqtyStaking_EBTCBalance_After.gt(lqtyStaking_EBTCBalance_Before))
    })

    it("openTrove(): Borrowing at non-zero base rate increases the LQTY staking contract EBTC fees-per-unit-staked", async () => {
      // time fast-forwards 1 year, and multisig stakes 1 LQTY
      await th.fastForwardTime(timeValues.SECONDS_IN_ONE_YEAR, web3.currentProvider)
      await lqtyToken.approve(lqtyStaking.address, dec(1, 18), { from: multisig })
      await lqtyStaking.stake(dec(1, 18), { from: multisig })

      // Check LQTY contract EBTC fees-per-unit-staked is zero
      const F_EBTC_Before = await lqtyStaking.F_EBTC()
      assert.equal(F_EBTC_Before, '0')

      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openTrove({ extraEBTCAmount: toBN(dec(20000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openTrove({ extraEBTCAmount: toBN(dec(30000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openTrove({ extraEBTCAmount: toBN(dec(40000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })

      // Artificially make baseRate 5%
      await troveManager.setBaseRate(dec(5, 16))
      await troveManager.setLastFeeOpTimeToNow()

      // Check baseRate is now non-zero
      const baseRate_1 = await troveManager.baseRate()
      assert.isTrue(baseRate_1.gt(toBN('0')))

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      // D opens trove 
      await openTrove({ extraEBTCAmount: toBN(dec(37, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      // Check LQTY contract EBTC fees-per-unit-staked has increased
      const F_EBTC_After = await lqtyStaking.F_EBTC()
      assert.isTrue(F_EBTC_After.gt(F_EBTC_Before))
    })

    it("openTrove(): Borrowing at non-zero base rate sends requested amount to the user", async () => {
      // time fast-forwards 1 year, and multisig stakes 1 LQTY
      await th.fastForwardTime(timeValues.SECONDS_IN_ONE_YEAR, web3.currentProvider)
      await lqtyToken.approve(lqtyStaking.address, dec(1, 18), { from: multisig })
      await lqtyStaking.stake(dec(1, 18), { from: multisig })

      // Check LQTY Staking contract balance before == 0
      const lqtyStaking_EBTCBalance_Before = await lusdToken.balanceOf(lqtyStaking.address)
      assert.equal(lqtyStaking_EBTCBalance_Before, '0')

      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openTrove({ extraEBTCAmount: toBN(dec(20000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openTrove({ extraEBTCAmount: toBN(dec(30000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openTrove({ extraEBTCAmount: toBN(dec(40000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })

      // Artificially make baseRate 5%
      await troveManager.setBaseRate(dec(5, 16))
      await troveManager.setLastFeeOpTimeToNow()

      // Check baseRate is non-zero
      const baseRate_1 = await troveManager.baseRate()
      assert.isTrue(baseRate_1.gt(toBN('0')))

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      // D opens trove 
      const EBTCRequest_D = toBN(dec(40000, 18))
      await borrowerOperations.openTrove(th._100pct, EBTCRequest_D, th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: D, value: dec(500, 'ether') })

      // Check LQTY staking EBTC balance has increased
      const lqtyStaking_EBTCBalance_After = await lusdToken.balanceOf(lqtyStaking.address)
      assert.isTrue(lqtyStaking_EBTCBalance_After.gt(lqtyStaking_EBTCBalance_Before))

      // Check D's EBTC balance now equals their requested EBTC
      const EBTCBalance_D = await lusdToken.balanceOf(D)
      assert.isTrue(EBTCRequest_D.eq(EBTCBalance_D))
    })

    it("openTrove(): Borrowing at zero base rate changes the LQTY staking contract EBTC fees-per-unit-staked", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openTrove({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openTrove({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })

      // Check baseRate is zero
      const baseRate_1 = await troveManager.baseRate()
      assert.equal(baseRate_1, '0')

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      // Check EBTC reward per LQTY staked == 0
      const F_EBTC_Before = await lqtyStaking.F_EBTC()
      assert.equal(F_EBTC_Before, '0')

      // A stakes LQTY
      await lqtyToken.unprotectedMint(A, dec(100, 18))
      await lqtyStaking.stake(dec(100, 18), { from: A })

      // D opens trove 
      await openTrove({ extraEBTCAmount: toBN(dec(37, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      // Check EBTC reward per LQTY staked > 0
      const F_EBTC_After = await lqtyStaking.F_EBTC()
      assert.isTrue(F_EBTC_After.gt(toBN('0')))
    })

    it("openTrove(): Borrowing at zero base rate charges minimum fee", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openTrove({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })

      const EBTCRequest = toBN(dec(10000, 18))
      const txC = await borrowerOperations.openTrove(th._100pct, EBTCRequest, ZERO_ADDRESS, ZERO_ADDRESS, { value: dec(100, 'ether'), from: C })
      const _EBTCFee = toBN(th.getEventArgByName(txC, "EBTCBorrowingFeePaid", "_EBTCFee"))

      const expectedFee = BORROWING_FEE_FLOOR.mul(toBN(EBTCRequest)).div(toBN(dec(1, 18)))
      assert.isTrue(_EBTCFee.eq(expectedFee))
    })

    it("openTrove(): reverts when system is in Recovery Mode and ICR < CCR", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: whale } })
      await openTrove({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      assert.isFalse(await th.checkRecoveryMode(contracts))

      // price drops, and Recovery Mode kicks in
      await priceFeed.setPrice(dec(105, 18))

      assert.isTrue(await th.checkRecoveryMode(contracts))

      // Bob tries to open a trove with 149% ICR during Recovery Mode
      try {
        const txBob = await openTrove({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(149, 16)), extraParams: { from: alice } })
        assert.isFalse(txBob.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    it("openTrove(): reverts when trove ICR < MCR", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: whale } })
      await openTrove({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })

      assert.isFalse(await th.checkRecoveryMode(contracts))

      // Bob attempts to open a 109% ICR trove in Normal Mode
      try {
        const txBob = (await openTrove({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(109, 16)), extraParams: { from: bob } })).tx
        assert.isFalse(txBob.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }

      // price drops, and Recovery Mode kicks in
      await priceFeed.setPrice(dec(105, 18))

      assert.isTrue(await th.checkRecoveryMode(contracts))

      // Bob attempts to open a 109% ICR trove in Recovery Mode
      try {
        const txBob = await openTrove({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(109, 16)), extraParams: { from: bob } })
        assert.isFalse(txBob.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    it("openTrove(): reverts when opening the trove would cause the TCR of the system to fall below the CCR", async () => {
      await priceFeed.setPrice(dec(100, 18))

      // Alice creates trove with 150% ICR.  System TCR = 150%.
      await openTrove({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(15, 17)), extraParams: { from: alice } })

      const TCR = await th.getTCR(contracts)
      assert.equal(TCR, dec(150, 16))

      // Bob attempts to open a trove with ICR = 149% 
      // System TCR would fall below 150%
      try {
        const txBob = await openTrove({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(149, 16)), extraParams: { from: bob } })
        assert.isFalse(txBob.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    it("openTrove(): account can open multiple troves", async () => {
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })

      await openTrove({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(15, 17)), extraParams: { from: alice } })
      await openTrove({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(15, 17)), extraParams: { from: bob } })

      await openTrove({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(3, 18)), extraParams: { from: bob } })
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
    })

    xit("[TODO] openTrove(): multiple troves opened by same account have different indicies", async () => {
    })

    it("openTrove(): Can open a trove with ICR >= CCR when system is in Recovery Mode", async () => {
      // --- SETUP ---
      //  Alice and Bob add coll and withdraw such  that the TCR is ~150%
      await openTrove({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(15, 17)), extraParams: { from: alice } })
      await openTrove({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(15, 17)), extraParams: { from: bob } })

      const TCR = (await th.getTCR(contracts)).toString()
      assert.equal(TCR, '1500000000000000000')

      // price drops to 1ETH:100EBTC, reducing TCR below 150%
      await priceFeed.setPrice('100000000000000000000');
      const price = await priceFeed.getPrice()

      assert.isTrue(await th.checkRecoveryMode(contracts))

      // Carol opens at 150% ICR in Recovery Mode
      const txCarol = (await openTrove({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(15, 17)), extraParams: { from: carol } })).tx
      assert.isTrue(txCarol.receipt.status)
      const carolIndex = await sortedTroves.troveOfOwnerByIndex(carol,0)
      assert.isTrue(await sortedTroves.contains(carolIndex))

      const carol_TroveStatus = await troveManager.getTroveStatus(carolIndex)
      assert.equal(carol_TroveStatus, 1)

      const carolICR = await troveManager.getCurrentICR(carolIndex, price)
      assert.isTrue(carolICR.gt(toBN(dec(150, 16))))
    })

    it("openTrove(): Reverts opening a trove with min debt when system is in Recovery Mode", async () => {
      // --- SETUP ---
      //  Alice and Bob add coll and withdraw such  that the TCR is ~150%
      await openTrove({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(15, 17)), extraParams: { from: alice } })
      await openTrove({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(15, 17)), extraParams: { from: bob } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
      const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)

      const TCR = (await th.getTCR(contracts)).toString()
      assert.equal(TCR, '1500000000000000000')

      // price drops to 1ETH:100EBTC, reducing TCR below 150%
      await priceFeed.setPrice('100000000000000000000');

      assert.isTrue(await th.checkRecoveryMode(contracts))

      await assertRevert(borrowerOperations.openTrove(th._100pct, await getNetBorrowingAmount(MIN_NET_DEBT), th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: carol, value: dec(1, 'ether') }))
    })

    it("openTrove(): creates a new Trove and assigns the correct collateral and debt amount", async () => {

      // We can't know the troveID beforehand unless we know the block at which the operation will be mined and ensure no more troves are minted in the intermediate term
      const aliceIndexNonExistant = th.RANDOM_INDEX
      const debt_Before = await getTroveEntireDebt(aliceIndexNonExistant)
      const coll_Before = await getTroveEntireColl(aliceIndexNonExistant)
      const status_Before = await troveManager.getTroveStatus(aliceIndexNonExistant)

      // check coll and debt before
      assert.equal(debt_Before, 0)
      assert.equal(coll_Before, 0)

      // check non-existent status
      assert.equal(status_Before, 0)

      const EBTCRequest = MIN_NET_DEBT
      await borrowerOperations.openTrove(th._100pct, MIN_NET_DEBT, th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: alice, value: dec(100, 'ether') })
      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)

      // Get the expected debt based on the EBTC request (adding fee and liq. reserve on top)
      const expectedDebt = EBTCRequest
        .add(await troveManager.getBorrowingFee(EBTCRequest))
        .add(EBTC_GAS_COMPENSATION)
      const debt_After = await getTroveEntireDebt(aliceIndex)
      const coll_After = await getTroveEntireColl(aliceIndex)
      const status_After = await troveManager.getTroveStatus(aliceIndex)
      // check coll and debt after
      assert.isTrue(coll_After.gt('0'))
      assert.isTrue(debt_After.gt('0'))

      assert.isTrue(debt_After.eq(expectedDebt))

      // check active status
      assert.equal(status_After, 1)
    })

    it("openTrove(): adds Trove ID to TroveID array", async () => {
      const TroveIdsCount_Before = (await troveManager.getTroveIdsCount()).toString();
      assert.equal(TroveIdsCount_Before, '0')

      await openTrove({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(15, 17)), extraParams: { from: alice } })

      const TroveIdsCount_After = (await troveManager.getTroveIdsCount()).toString();
      assert.equal(TroveIdsCount_After, '1')
    })

    xit("[TODO] openTrove(): adds Trove owner to TroveOwners array [Or: if we're not doing this, how do we enumerate all active trove owners?]", async () => {
    })

    it("openTrove(): creates a stake and adds it to total stakes", async () => {
      // TODO: Call this function to see where alice's next trove would get deployed if it did. Then, check this index.
      // Can a trove ever be opened at the same index twice?
      const aliceStakeBefore = await getTroveStake(alice)
      const totalStakesBefore = await troveManager.totalStakes()

      assert.equal(aliceStakeBefore, '0')
      assert.equal(totalStakesBefore, '0')

      await openTrove({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)

      const aliceCollAfter = await getTroveEntireColl(aliceIndex)
      const aliceStakeAfter = await getTroveStake(aliceIndex)

      assert.isTrue(aliceCollAfter.gt(toBN('0')))
      assert.isTrue(aliceStakeAfter.eq(aliceCollAfter))

      const totalStakesAfter = await troveManager.totalStakes()

      assert.isTrue(totalStakesAfter.eq(aliceStakeAfter))
    })

    it("openTrove(): inserts Trove to Sorted Troves list", async () => {
      // Check before
      const aliceTroveInList_Before = await sortedTroves.contains(alice)
      const listIsEmpty_Before = await sortedTroves.isEmpty()
      assert.equal(aliceTroveInList_Before, false)
      assert.equal(listIsEmpty_Before, true)

      await openTrove({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)

      // check after
      const aliceTroveInList_After = await sortedTroves.contains(aliceIndex)
      const emptyTroveNotInList_After = await sortedTroves.contains(alice)
      const listIsEmpty_After = await sortedTroves.isEmpty()
      assert.equal(aliceTroveInList_After, true)
      assert.equal(emptyTroveNotInList_After, false)
      assert.equal(listIsEmpty_After, false)
    })

    it("openTrove(): Increases the activePool ETH and raw ether balance by correct amount", async () => {
      const activePool_ETH_Before = await activePool.getETH()
      const activePool_RawEther_Before = await web3.eth.getBalance(activePool.address)
      assert.equal(activePool_ETH_Before, 0)
      assert.equal(activePool_RawEther_Before, 0)

      await openTrove({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
      const aliceCollAfter = await getTroveEntireColl(aliceIndex)

      const activePool_ETH_After = await activePool.getETH()
      const activePool_RawEther_After = toBN(await web3.eth.getBalance(activePool.address))
      assert.isTrue(activePool_ETH_After.eq(aliceCollAfter))
      assert.isTrue(activePool_RawEther_After.eq(aliceCollAfter))
    })

    it("openTrove(): records up-to-date initial snapshots of L_ETH and L_EBTCDebt", async () => {
      // --- SETUP ---
      await openTrove({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openTrove({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: carol } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
      const carolIndex = await sortedTroves.troveOfOwnerByIndex(carol,0)

      // --- TEST ---

      // price drops to 1ETH:100EBTC, reducing Carol's ICR below MCR
      await priceFeed.setPrice(dec(100, 18));

      // close Carol's Trove, liquidating her 1 ether and 180EBTC.
      const liquidationTx = await troveManager.liquidate(carolIndex, { from: owner });
      const [liquidatedDebt, liquidatedColl, gasComp] = th.getEmittedLiquidationValues(liquidationTx)

      /* with total stakes = 10 ether, after liquidation, L_ETH should equal 1/10 ether per-ether-staked,
       and L_EBTC should equal 18 EBTC per-ether-staked. */

      const L_ETH = await troveManager.L_ETH()
      const L_EBTC = await troveManager.L_EBTCDebt()

      assert.isTrue(L_ETH.gt(toBN('0')))
      assert.isTrue(L_EBTC.gt(toBN('0')))

      // Bob opens trove
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: bob } })
      const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)

      // Check Bob's snapshots of L_ETH and L_EBTC equal the respective current values
      const bob_rewardSnapshot = await troveManager.rewardSnapshots(bobIndex)
      const bob_ETHrewardSnapshot = bob_rewardSnapshot[0]
      const bob_EBTCDebtRewardSnapshot = bob_rewardSnapshot[1]

      assert.isAtMost(th.getDifference(bob_ETHrewardSnapshot, L_ETH), 1000)
      assert.isAtMost(th.getDifference(bob_EBTCDebtRewardSnapshot, L_EBTC), 1000)
    })

    it("openTrove(): allows a user to open a Trove, then close it, then re-open it", async () => {
      // Open Troves
      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: whale } })
      await openTrove({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openTrove({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: carol } })

      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
      const carolIndex = await sortedTroves.troveOfOwnerByIndex(carol,0)

      // Check Trove is active
      const alice_Trove_1 = await troveManager.Troves(aliceIndex)
      const status_1 = alice_Trove_1[3]
      assert.equal(status_1, 1)
      assert.isTrue(await sortedTroves.contains(aliceIndex))

      // to compensate borrowing fees
      await lusdToken.transfer(alice, dec(10000, 18), { from: whale })

      // Repay and close Trove
      await borrowerOperations.closeTrove(aliceIndex, { from: alice })

      // Check Trove is closed
      const alice_Trove_2 = await troveManager.Troves(aliceIndex)
      const status_2 = alice_Trove_2[3]
      assert.equal(status_2, 2)
      assert.isFalse(await sortedTroves.contains(aliceIndex))

      // Re-open Trove
      await openTrove({ extraEBTCAmount: toBN(dec(5000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })

      const aliceIndex2 = await sortedTroves.troveOfOwnerByIndex(alice,0)

      assert.notEqual(aliceIndex, aliceIndex2)

      // Check Trove is re-opened
      const alice_Trove_3 = await troveManager.Troves(aliceIndex2)
      const status_3 = alice_Trove_3[3]
      assert.equal(status_3, 1)
      assert.isTrue(await sortedTroves.contains(aliceIndex2))
      assert.isFalse(await sortedTroves.contains(aliceIndex))
    })

    it("openTrove(): increases the Trove's EBTC debt by the correct amount", async () => {
      // check before
      const alice_Trove_Before = await troveManager.Troves(alice)
      const debt_Before = alice_Trove_Before[0]
      assert.equal(debt_Before, 0)

      await borrowerOperations.openTrove(th._100pct, await getOpenTroveEBTCAmount(dec(10000, 18)), alice, alice, { from: alice, value: dec(100, 'ether') })
      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)

      // check after
      const alice_Trove_After = await troveManager.Troves(aliceIndex)
      const debt_After = alice_Trove_After[0]
      th.assertIsApproximatelyEqual(debt_After, dec(10000, 18), 10000)
    })

    it("openTrove(): increases EBTC debt in ActivePool by the debt of the trove", async () => {
      const activePool_EBTCDebt_Before = await activePool.getEBTCDebt()
      assert.equal(activePool_EBTCDebt_Before, 0)

      await openTrove({ extraEBTCAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
      
      const aliceDebt = await getTroveEntireDebt(aliceIndex)
      assert.isTrue(aliceDebt.gt(toBN('0')))

      const activePool_EBTCDebt_After = await activePool.getEBTCDebt()
      assert.isTrue(activePool_EBTCDebt_After.eq(aliceDebt))
    })

    it("openTrove(): increases user EBTCToken balance by correct amount", async () => {
      // check before
      const alice_EBTCTokenBalance_Before = await lusdToken.balanceOf(alice)
      assert.equal(alice_EBTCTokenBalance_Before, 0)

      await borrowerOperations.openTrove(th._100pct, dec(10000, 18), alice, alice, { from: alice, value: dec(100, 'ether') })
      const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)

      // check after
      const alice_EBTCTokenBalance_After = await lusdToken.balanceOf(alice)
      assert.equal(alice_EBTCTokenBalance_After, dec(10000, 18))
    })

    //  --- getNewICRFromTroveChange - (external wrapper in Tester contract calls internal function) ---

    describe("getNewICRFromTroveChange() returns the correct ICR", async () => {


      // 0, 0
      it("collChange = 0, debtChange = 0", async () => {
        price = await priceFeed.getPrice()
        const initialColl = dec(1, 'ether')
        const initialDebt = dec(100, 18)
        const collChange = 0
        const debtChange = 0

        const newICR = (await borrowerOperations.getNewICRFromTroveChange(initialColl, initialDebt, collChange, true, debtChange, true, price)).toString()
        assert.equal(newICR, '2000000000000000000')
      })

      // 0, +ve
      it("collChange = 0, debtChange is positive", async () => {
        price = await priceFeed.getPrice()
        const initialColl = dec(1, 'ether')
        const initialDebt = dec(100, 18)
        const collChange = 0
        const debtChange = dec(50, 18)

        const newICR = (await borrowerOperations.getNewICRFromTroveChange(initialColl, initialDebt, collChange, true, debtChange, true, price)).toString()
        assert.isAtMost(th.getDifference(newICR, '1333333333333333333'), 100)
      })

      // 0, -ve
      it("collChange = 0, debtChange is negative", async () => {
        price = await priceFeed.getPrice()
        const initialColl = dec(1, 'ether')
        const initialDebt = dec(100, 18)
        const collChange = 0
        const debtChange = dec(50, 18)

        const newICR = (await borrowerOperations.getNewICRFromTroveChange(initialColl, initialDebt, collChange, true, debtChange, false, price)).toString()
        assert.equal(newICR, '4000000000000000000')
      })

      // +ve, 0
      it("collChange is positive, debtChange is 0", async () => {
        price = await priceFeed.getPrice()
        const initialColl = dec(1, 'ether')
        const initialDebt = dec(100, 18)
        const collChange = dec(1, 'ether')
        const debtChange = 0

        const newICR = (await borrowerOperations.getNewICRFromTroveChange(initialColl, initialDebt, collChange, true, debtChange, true, price)).toString()
        assert.equal(newICR, '4000000000000000000')
      })

      // -ve, 0
      it("collChange is negative, debtChange is 0", async () => {
        price = await priceFeed.getPrice()
        const initialColl = dec(1, 'ether')
        const initialDebt = dec(100, 18)
        const collChange = dec(5, 17)
        const debtChange = 0

        const newICR = (await borrowerOperations.getNewICRFromTroveChange(initialColl, initialDebt, collChange, false, debtChange, true, price)).toString()
        assert.equal(newICR, '1000000000000000000')
      })

      // -ve, -ve
      it("collChange is negative, debtChange is negative", async () => {
        price = await priceFeed.getPrice()
        const initialColl = dec(1, 'ether')
        const initialDebt = dec(100, 18)
        const collChange = dec(5, 17)
        const debtChange = dec(50, 18)

        const newICR = (await borrowerOperations.getNewICRFromTroveChange(initialColl, initialDebt, collChange, false, debtChange, false, price)).toString()
        assert.equal(newICR, '2000000000000000000')
      })

      // +ve, +ve 
      it("collChange is positive, debtChange is positive", async () => {
        price = await priceFeed.getPrice()
        const initialColl = dec(1, 'ether')
        const initialDebt = dec(100, 18)
        const collChange = dec(1, 'ether')
        const debtChange = dec(100, 18)

        const newICR = (await borrowerOperations.getNewICRFromTroveChange(initialColl, initialDebt, collChange, true, debtChange, true, price)).toString()
        assert.equal(newICR, '2000000000000000000')
      })

      // +ve, -ve
      it("collChange is positive, debtChange is negative", async () => {
        price = await priceFeed.getPrice()
        const initialColl = dec(1, 'ether')
        const initialDebt = dec(100, 18)
        const collChange = dec(1, 'ether')
        const debtChange = dec(50, 18)

        const newICR = (await borrowerOperations.getNewICRFromTroveChange(initialColl, initialDebt, collChange, true, debtChange, false, price)).toString()
        assert.equal(newICR, '8000000000000000000')
      })

      // -ve, +ve
      it("collChange is negative, debtChange is positive", async () => {
        price = await priceFeed.getPrice()
        const initialColl = dec(1, 'ether')
        const initialDebt = dec(100, 18)
        const collChange = dec(5, 17)
        const debtChange = dec(100, 18)

        const newICR = (await borrowerOperations.getNewICRFromTroveChange(initialColl, initialDebt, collChange, false, debtChange, true, price)).toString()
        assert.equal(newICR, '500000000000000000')
      })
    })

    // --- getCompositeDebt ---

    it("getCompositeDebt(): returns debt + gas comp", async () => {
      const res1 = await borrowerOperations.getCompositeDebt('0')
      assert.equal(res1, EBTC_GAS_COMPENSATION.toString())

      const res2 = await borrowerOperations.getCompositeDebt(dec(90, 18))
      th.assertIsApproximatelyEqual(res2, EBTC_GAS_COMPENSATION.add(toBN(dec(90, 18))))

      const res3 = await borrowerOperations.getCompositeDebt(dec(24423422357345049, 12))
      th.assertIsApproximatelyEqual(res3, EBTC_GAS_COMPENSATION.add(toBN(dec(24423422357345049, 12))))
    })

    //  --- getNewTCRFromTroveChange  - (external wrapper in Tester contract calls internal function) ---

    describe("getNewTCRFromTroveChange() returns the correct TCR", async () => {

      // 0, 0
      it("collChange = 0, debtChange = 0", async () => {
        // --- SETUP --- Create a Liquity instance with an Active Pool and pending rewards (Default Pool)
        const troveColl = toBN(dec(1000, 'ether'))
        const troveTotalDebt = toBN(dec(100000, 18))
        const troveEBTCAmount = await getOpenTroveEBTCAmount(troveTotalDebt)
        await borrowerOperations.openTrove(th._100pct, troveEBTCAmount, th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: alice, value: troveColl })
        await borrowerOperations.openTrove(th._100pct, troveEBTCAmount, th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: bob, value: troveColl })

        await priceFeed.setPrice(dec(100, 18))

        const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
        const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)

        const liquidationTx = await troveManager.liquidate(bobIndex)
        assert.isFalse(await sortedTroves.contains(bobIndex))

        const [liquidatedDebt, liquidatedColl, gasComp] = th.getEmittedLiquidationValues(liquidationTx)

        await priceFeed.setPrice(dec(200, 18))
        const price = await priceFeed.getPrice()

        // --- TEST ---
        const collChange = 0
        const debtChange = 0
        const newTCR = await borrowerOperations.getNewTCRFromTroveChange(collChange, true, debtChange, true, price)

        const expectedTCR = (troveColl.add(liquidatedColl)).mul(price)
          .div(troveTotalDebt.add(liquidatedDebt))

        assert.isTrue(newTCR.eq(expectedTCR))
      })

      // 0, +ve
      it("collChange = 0, debtChange is positive", async () => {
        // --- SETUP --- Create a Liquity instance with an Active Pool and pending rewards (Default Pool)
        const troveColl = toBN(dec(1000, 'ether'))
        const troveTotalDebt = toBN(dec(100000, 18))
        const troveEBTCAmount = await getOpenTroveEBTCAmount(troveTotalDebt)
        await borrowerOperations.openTrove(th._100pct, troveEBTCAmount, th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: alice, value: troveColl })
        await borrowerOperations.openTrove(th._100pct, troveEBTCAmount, th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: bob, value: troveColl })

        const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
        const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)

        await priceFeed.setPrice(dec(100, 18))

        const liquidationTx = await troveManager.liquidate(bobIndex)
        assert.isFalse(await sortedTroves.contains(bobIndex))

        const [liquidatedDebt, liquidatedColl, gasComp] = th.getEmittedLiquidationValues(liquidationTx)

        await priceFeed.setPrice(dec(200, 18))
        const price = await priceFeed.getPrice()

        // --- TEST ---
        const collChange = 0
        const debtChange = dec(200, 18)
        const newTCR = (await borrowerOperations.getNewTCRFromTroveChange(collChange, true, debtChange, true, price))

        const expectedTCR = (troveColl.add(liquidatedColl)).mul(price)
          .div(troveTotalDebt.add(liquidatedDebt).add(toBN(debtChange)))

        assert.isTrue(newTCR.eq(expectedTCR))
      })

      // 0, -ve
      it("collChange = 0, debtChange is negative", async () => {
        // --- SETUP --- Create a Liquity instance with an Active Pool and pending rewards (Default Pool)
        const troveColl = toBN(dec(1000, 'ether'))
        const troveTotalDebt = toBN(dec(100000, 18))
        const troveEBTCAmount = await getOpenTroveEBTCAmount(troveTotalDebt)
        await borrowerOperations.openTrove(th._100pct, troveEBTCAmount, th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: alice, value: troveColl })
        await borrowerOperations.openTrove(th._100pct, troveEBTCAmount, th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: bob, value: troveColl })

        const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
        const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)

        await priceFeed.setPrice(dec(100, 18))

        const liquidationTx = await troveManager.liquidate(bobIndex)
        assert.isFalse(await sortedTroves.contains(bobIndex))

        const [liquidatedDebt, liquidatedColl, gasComp] = th.getEmittedLiquidationValues(liquidationTx)

        await priceFeed.setPrice(dec(200, 18))
        const price = await priceFeed.getPrice()
        // --- TEST ---
        const collChange = 0
        const debtChange = dec(100, 18)
        const newTCR = (await borrowerOperations.getNewTCRFromTroveChange(collChange, true, debtChange, false, price))

        const expectedTCR = (troveColl.add(liquidatedColl)).mul(price)
          .div(troveTotalDebt.add(liquidatedDebt).sub(toBN(dec(100, 18))))

        assert.isTrue(newTCR.eq(expectedTCR))
      })

      // +ve, 0
      it("collChange is positive, debtChange is 0", async () => {
        // --- SETUP --- Create a Liquity instance with an Active Pool and pending rewards (Default Pool)
        const troveColl = toBN(dec(1000, 'ether'))
        const troveTotalDebt = toBN(dec(100000, 18))
        const troveEBTCAmount = await getOpenTroveEBTCAmount(troveTotalDebt)
        await borrowerOperations.openTrove(th._100pct, troveEBTCAmount, th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: alice, value: troveColl })
        await borrowerOperations.openTrove(th._100pct, troveEBTCAmount, th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: bob, value: troveColl })

        const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
        const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)

        await priceFeed.setPrice(dec(100, 18))

        const liquidationTx = await troveManager.liquidate(bobIndex)
        assert.isFalse(await sortedTroves.contains(bobIndex))

        const [liquidatedDebt, liquidatedColl, gasComp] = th.getEmittedLiquidationValues(liquidationTx)

        await priceFeed.setPrice(dec(200, 18))
        const price = await priceFeed.getPrice()
        // --- TEST ---
        const collChange = dec(2, 'ether')
        const debtChange = 0
        const newTCR = (await borrowerOperations.getNewTCRFromTroveChange(collChange, true, debtChange, true, price))

        const expectedTCR = (troveColl.add(liquidatedColl).add(toBN(collChange))).mul(price)
          .div(troveTotalDebt.add(liquidatedDebt))

        assert.isTrue(newTCR.eq(expectedTCR))
      })

      // -ve, 0
      it("collChange is negative, debtChange is 0", async () => {
        // --- SETUP --- Create a Liquity instance with an Active Pool and pending rewards (Default Pool)
        const troveColl = toBN(dec(1000, 'ether'))
        const troveTotalDebt = toBN(dec(100000, 18))
        const troveEBTCAmount = await getOpenTroveEBTCAmount(troveTotalDebt)
        await borrowerOperations.openTrove(th._100pct, troveEBTCAmount, th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: alice, value: troveColl })
        await borrowerOperations.openTrove(th._100pct, troveEBTCAmount, th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: bob, value: troveColl })

        const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
        const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)

        await priceFeed.setPrice(dec(100, 18))

        const liquidationTx = await troveManager.liquidate(bobIndex)
        assert.isFalse(await sortedTroves.contains(bobIndex))

        const [liquidatedDebt, liquidatedColl, gasComp] = th.getEmittedLiquidationValues(liquidationTx)

        await priceFeed.setPrice(dec(200, 18))
        const price = await priceFeed.getPrice()

        // --- TEST ---
        const collChange = dec(1, 18)
        const debtChange = 0
        const newTCR = (await borrowerOperations.getNewTCRFromTroveChange(collChange, false, debtChange, true, price))

        const expectedTCR = (troveColl.add(liquidatedColl).sub(toBN(dec(1, 'ether')))).mul(price)
          .div(troveTotalDebt.add(liquidatedDebt))

        assert.isTrue(newTCR.eq(expectedTCR))
      })

      // -ve, -ve
      it("collChange is negative, debtChange is negative", async () => {
        // --- SETUP --- Create a Liquity instance with an Active Pool and pending rewards (Default Pool)
        const troveColl = toBN(dec(1000, 'ether'))
        const troveTotalDebt = toBN(dec(100000, 18))
        const troveEBTCAmount = await getOpenTroveEBTCAmount(troveTotalDebt)
        await borrowerOperations.openTrove(th._100pct, troveEBTCAmount, th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: alice, value: troveColl })
        await borrowerOperations.openTrove(th._100pct, troveEBTCAmount, th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: bob, value: troveColl })

        const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)
        const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)

        await priceFeed.setPrice(dec(100, 18))

        const liquidationTx = await troveManager.liquidate(bobIndex)
        assert.isFalse(await sortedTroves.contains(bobIndex))

        const [liquidatedDebt, liquidatedColl, gasComp] = th.getEmittedLiquidationValues(liquidationTx)

        await priceFeed.setPrice(dec(200, 18))
        const price = await priceFeed.getPrice()

        // --- TEST ---
        const collChange = dec(1, 18)
        const debtChange = dec(100, 18)
        const newTCR = (await borrowerOperations.getNewTCRFromTroveChange(collChange, false, debtChange, false, price))

        const expectedTCR = (troveColl.add(liquidatedColl).sub(toBN(dec(1, 'ether')))).mul(price)
          .div(troveTotalDebt.add(liquidatedDebt).sub(toBN(dec(100, 18))))

        assert.isTrue(newTCR.eq(expectedTCR))
      })

      // +ve, +ve 
      it("collChange is positive, debtChange is positive", async () => {
        // --- SETUP --- Create a Liquity instance with an Active Pool and pending rewards (Default Pool)
        const troveColl = toBN(dec(1000, 'ether'))
        const troveTotalDebt = toBN(dec(100000, 18))
        const troveEBTCAmount = await getOpenTroveEBTCAmount(troveTotalDebt)
        await borrowerOperations.openTrove(th._100pct, troveEBTCAmount, th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: alice, value: troveColl })
        await borrowerOperations.openTrove(th._100pct, troveEBTCAmount, th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: bob, value: troveColl })

        const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)

        await priceFeed.setPrice(dec(100, 18))

        const liquidationTx = await troveManager.liquidate(bobIndex)
        assert.isFalse(await sortedTroves.contains(bobIndex))

        const [liquidatedDebt, liquidatedColl, gasComp] = th.getEmittedLiquidationValues(liquidationTx)

        await priceFeed.setPrice(dec(200, 18))
        const price = await priceFeed.getPrice()

        // --- TEST ---
        const collChange = dec(1, 'ether')
        const debtChange = dec(100, 18)
        const newTCR = (await borrowerOperations.getNewTCRFromTroveChange(collChange, true, debtChange, true, price))

        const expectedTCR = (troveColl.add(liquidatedColl).add(toBN(dec(1, 'ether')))).mul(price)
          .div(troveTotalDebt.add(liquidatedDebt).add(toBN(dec(100, 18))))

        assert.isTrue(newTCR.eq(expectedTCR))
      })

      // +ve, -ve
      it("collChange is positive, debtChange is negative", async () => {
        // --- SETUP --- Create a Liquity instance with an Active Pool and pending rewards (Default Pool)
        const troveColl = toBN(dec(1000, 'ether'))
        const troveTotalDebt = toBN(dec(100000, 18))
        const troveEBTCAmount = await getOpenTroveEBTCAmount(troveTotalDebt)
        await borrowerOperations.openTrove(th._100pct, troveEBTCAmount, alice, alice, { from: alice, value: troveColl })
        await borrowerOperations.openTrove(th._100pct, troveEBTCAmount, bob, bob, { from: bob, value: troveColl })

        const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)

        await priceFeed.setPrice(dec(100, 18))

        const liquidationTx = await troveManager.liquidate(bobIndex)
        assert.isFalse(await sortedTroves.contains(bobIndex))

        const [liquidatedDebt, liquidatedColl, gasComp] = th.getEmittedLiquidationValues(liquidationTx)

        await priceFeed.setPrice(dec(200, 18))
        const price = await priceFeed.getPrice()

        // --- TEST ---
        const collChange = dec(1, 'ether')
        const debtChange = dec(100, 18)
        const newTCR = (await borrowerOperations.getNewTCRFromTroveChange(collChange, true, debtChange, false, price))

        const expectedTCR = (troveColl.add(liquidatedColl).add(toBN(dec(1, 'ether')))).mul(price)
          .div(troveTotalDebt.add(liquidatedDebt).sub(toBN(dec(100, 18))))

        assert.isTrue(newTCR.eq(expectedTCR))
      })

      // -ve, +ve
      xit("collChange is negative, debtChange is positive", async () => {
        // --- SETUP --- Create a Liquity instance with an Active Pool and pending rewards (Default Pool)
        const troveColl = toBN(dec(1000, 'ether'))
        const troveTotalDebt = toBN(dec(100000, 18))
        const troveEBTCAmount = await getOpenTroveEBTCAmount(troveTotalDebt)
        await borrowerOperations.openTrove(th._100pct, troveEBTCAmount, alice, alice, { from: alice, value: troveColl })
        await borrowerOperations.openTrove(th._100pct, troveEBTCAmount, bob, bob, { from: bob, value: troveColl })

        const bobIndex = await sortedTroves.troveOfOwnerByIndex(bob,0)

        await priceFeed.setPrice(dec(100, 18))

        const liquidationTx = await troveManager.liquidate(bobIndex)
        assert.isFalse(await sortedTroves.contains(bobIndex))

        const [liquidatedDebt, liquidatedColl, gasComp] = th.getEmittedLiquidationValues(liquidationTx)

        await priceFeed.setPrice(dec(200, 18))
        const price = await priceFeed.getPrice()

        // --- TEST ---
        const collChange = dec(1, 18)
        const debtChange = await getNetBorrowingAmount(dec(200, 18))
        const newTCR = (await borrowerOperations.getNewTCRFromTroveChange(collChange, false, debtChange, true, price))

        const expectedTCR = (troveColl.add(liquidatedColl).sub(toBN(collChange))).mul(price)
          .div(troveTotalDebt.add(liquidatedDebt).add(toBN(debtChange)))

        assert.isTrue(newTCR.eq(expectedTCR))
      })
    })

    if (!withProxy) {
      it("closeTrove(): fails if owner cannot receive ETH", async () => {
        const nonPayable = await NonPayable.new()

        // we need 2 troves to be able to close 1 and have 1 remaining in the system
        await borrowerOperations.openTrove(th._100pct, dec(100000, 18), th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: alice, value: dec(1000, 18) })

        const aliceIndex = await sortedTroves.troveOfOwnerByIndex(alice,0)

        // Alice sends EBTC to NonPayable so its EBTC balance covers its debt
        await lusdToken.transfer(nonPayable.address, dec(10000, 18), {from: alice})

        // open trove from NonPayable proxy contract
        const _100pctHex = '0xde0b6b3a7640000'
        const _1e25Hex = '0xd3c21bcecceda1000000'
        const openTroveData = th.getTransactionData('openTrove(uint256,uint256,bytes32,bytes32)', [_100pctHex, _1e25Hex, th.DUMMY_BYTES32, th.DUMMY_BYTES32])
        await nonPayable.forward(borrowerOperations.address, openTroveData, { value: dec(10000, 'ether') })

        const nonPayableIndex = await sortedTroves.troveOfOwnerByIndex(nonPayable.address,0)

        assert.equal((await troveManager.getTroveStatus(nonPayableIndex)).toString(), '1', 'NonPayable proxy should have a trove')
        assert.isFalse(await th.checkRecoveryMode(contracts), 'System should not be in Recovery Mode')
        // open trove from NonPayable proxy contract
        const closeTroveData = th.getTransactionData('closeTrove(bytes32)', [nonPayableIndex])
        await th.assertRevert(nonPayable.forward(borrowerOperations.address, closeTroveData), 'ActivePool: sending ETH failed')
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
 changes with addColl, withdrawColl, withdrawEBTC, repayEBTC, etc. Can split them up and put them with
 individual functions, or give ordering it's own 'describe' block.

 2)In security phase:
 -'Negative' tests for all the above functions.
 */
