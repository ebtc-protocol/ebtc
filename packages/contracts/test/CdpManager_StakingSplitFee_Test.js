const deploymentHelper = require("../utils/deploymentHelpers.js")
const { TestHelper: th, MoneyValues: mv } = require("../utils/testHelpers.js")
const { toBN, dec, ZERO_ADDRESS } = th

const CdpManagerTester = artifacts.require("./CdpManagerTester")
const EBTCToken = artifacts.require("./EBTCToken.sol")
const SimpleLiquidationTester = artifacts.require("./SimpleLiquidationTester.sol");

const assertRevert = th.assertRevert

contract('CdpManager - Simple Liquidation with external liquidators', async accounts => {
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
  let collSurplusPool;
  let _MCR;
  let collToken;
  let splitFeeRecipient;

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
    activePool = contracts.activePool;
    defaultPool = contracts.defaultPool;
    feeSplit = await contracts.cdpManager.STAKING_REWARD_SPLIT();	
    _MCR = await cdpManager.MCR();
    LICR = await cdpManager.LICR();
    borrowerOperations = contracts.borrowerOperations;
    collSurplusPool = contracts.collSurplusPool;
    collToken = contracts.collateral;

    await deploymentHelper.connectLQTYContracts(LQTYContracts)
    await deploymentHelper.connectCoreContracts(contracts, LQTYContracts)
    await deploymentHelper.connectLQTYContractsToCore(LQTYContracts, contracts)
	
    splitFeeRecipient = await contracts.cdpManager.lqtyStaking();
  })
  
  it("Claim split fee when there is staking reward coming", async() => {
      await openCdp({ ICR: toBN(dec(299, 16)), extraParams: { from: alice } })
      let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
      let _aliceColl = await cdpManager.getCdpColl(_aliceCdpId); 
      let _totalColl = await cdpManager.getEntireSystemColl(); 
      th.assertIsApproximatelyEqual(_aliceColl, _totalColl, 0);
      let _underlyingBalBefore = _aliceColl; // since we got 1e18 as starting index 
      let _oldIndex = mv._1e18BN;
	  
      let _price = await priceFeed.getPrice();
      let _icrBefore = await cdpManager.getCurrentICR(_aliceCdpId, _price);
      let _tcrBefore = await cdpManager.getTCR(_price);
	  
      let _newIndex = mv._1_5e18BN;
      await collToken.setEthPerShare(_newIndex); 
      await assertRevert(cdpManager.claimStakingSplitFee(), "CdpManager: update index too frequent");
	  
      await ethers.provider.send("evm_increaseTime", [86400]);
      await ethers.provider.send("evm_mine");	  
	  
      // sugardaddy some collateral staking reward by increasing its PPFS from 1 to 1.05
      let _expectedFee = _newIndex.sub(_oldIndex).mul(_aliceColl).mul(feeSplit).div(toBN("10000"));
      
      let _feeBalBefore = await collToken.balanceOf(splitFeeRecipient);
      await cdpManager.claimStakingSplitFee();  
      let _feeBalAfter = await collToken.balanceOf(splitFeeRecipient);
	  
      th.assertIsApproximatelyEqual(_feeBalAfter.sub(_feeBalBefore), _expectedFee.div(mv._1e18BN));
	  
      // apply accumulated fee split to CDP	upon user operations  	  
      let _expectedFeeShare = _expectedFee.div(mv._1_5e18BN);
      await borrowerOperations.withdrawEBTC(_aliceCdpId, th._100pct, 1, _aliceCdpId, _aliceCdpId, { from: alice, value: 0 })
      let _aliceCollAfter = await cdpManager.getCdpColl(_aliceCdpId); 
      let _totalCollAfter = await cdpManager.getEntireSystemColl(); 
      th.assertIsApproximatelyEqual(_aliceCollAfter, _aliceColl.sub(_expectedFeeShare), 0);
      th.assertIsApproximatelyEqual(_totalCollAfter, _totalColl.sub(_expectedFeeShare), 1);
	  
      // CDP should get more underlying collateral since there is staking reward 
      let _underlyingBalAfter = _aliceCollAfter.mul(_newIndex).div(mv._1e18BN);
      assert.isTrue(toBN(_underlyingBalAfter.toString()).gt(toBN(_underlyingBalBefore.toString())));
	  
      // As a result, TCR and the CDP ICR improve as well
      let _icrAfter = await cdpManager.getCurrentICR(_aliceCdpId, _price);
      let _tcrAfter = await cdpManager.getTCR(_price);
      assert.isTrue(toBN(_icrAfter.toString()).gt(toBN(_icrBefore.toString())));
      assert.isTrue(toBN(_tcrAfter.toString()).gt(toBN(_tcrBefore.toString())));
  })
  
  it("Sync update interval", async() => {	  
      let _oldInterval = await cdpManager.INDEX_UPD_INTERVAL();
      assert.isTrue(toBN(_oldInterval.toString()).eq(toBN("43200")));	  
	  
      await collToken.setBeaconSpec(2, 1, 1);
	  
      await cdpManager.syncUpdateIndexInterval(); 
      let _newInterval = await cdpManager.INDEX_UPD_INTERVAL();
      assert.isTrue(toBN(_newInterval.toString()).eq(toBN("1")));// = (2*1*1) / 2
  })
  
  it("Fee would be applied to all CDPs when there is staking reward coming", async() => {
      await openCdp({ ICR: toBN(dec(299, 16)), extraParams: { from: alice } })
      let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
      let _aliceColl = await cdpManager.getCdpColl(_aliceCdpId); 
	  
      await openCdp({ ICR: toBN(dec(299, 16)), extraParams: { from: bob } })
      let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
      let _bobColl = await cdpManager.getCdpColl(_bobCdpId); 
	  
      let _aliceStake = await cdpManager.getCdpStake(_aliceCdpId);
      let _bobStake = await cdpManager.getCdpStake(_bobCdpId); 
      let _totalStake = toBN(_aliceStake.toString()).add(toBN(_bobColl.toString())); 
      let _totalColl = await cdpManager.getEntireSystemColl(); 	  
      let _oldIndex = mv._1e18BN;
      let _underlyingBalBefore = toBN(_aliceColl.toString()).add(toBN(_bobColl.toString()));// since we got 1e18 as starting index 
	  
      th.assertIsApproximatelyEqual(_underlyingBalBefore, _totalColl, 0);
	  
      let _price = await priceFeed.getPrice();
      let _aliceIcrBefore = await cdpManager.getCurrentICR(_aliceCdpId, _price);
      let _bobIcrBefore = await cdpManager.getCurrentICR(_bobCdpId, _price);
      let _tcrBefore = await cdpManager.getTCR(_price);
	  
      let _newIndex = mv._1_5e18BN;
      await collToken.setEthPerShare(_newIndex); 
	  
      await ethers.provider.send("evm_increaseTime", [86400]);
      await ethers.provider.send("evm_mine");	  
	  
      // sugardaddy some collateral staking reward by increasing its PPFS from 1 to 1.05
      let _expectedFee = _newIndex.sub(_oldIndex).mul(_underlyingBalBefore).mul(feeSplit).div(toBN("10000"));
      
      let _feeBalBefore = await collToken.balanceOf(splitFeeRecipient);
      await cdpManager.claimStakingSplitFee();  
      let _feeBalAfter = await collToken.balanceOf(splitFeeRecipient);
	  
      th.assertIsApproximatelyEqual(_feeBalAfter.sub(_feeBalBefore), _expectedFee.div(mv._1e18BN));
	  
      // get collateral before applying accumulated split fee
      let _aliceCollAfterFee = (await cdpManager.getEntireDebtAndColl(_aliceCdpId))[1]; 
      let _bobCollAfterFee = (await cdpManager.getEntireDebtAndColl(_bobCdpId))[1];
	  
      // apply accumulated fee split to CDP	upon user operations  	  
      let _expectedFeeShare = _expectedFee.div(mv._1_5e18BN);
      await borrowerOperations.withdrawEBTC(_aliceCdpId, th._100pct, 1, _aliceCdpId, _aliceCdpId, { from: alice, value: 0 })
      await borrowerOperations.withdrawEBTC(_bobCdpId, th._100pct, 1, _bobCdpId, _bobCdpId, { from: bob, value: 0 })
	  
      let _aliceCollAfter = await cdpManager.getCdpColl(_aliceCdpId); 
      let _bobCollAfter = await cdpManager.getCdpColl(_bobCdpId);
	  
      th.assertIsApproximatelyEqual(_aliceCollAfter, _aliceCollAfterFee, 0);	  
      th.assertIsApproximatelyEqual(_bobCollAfter, _bobCollAfterFee, 1);
	  
      let _totalCollAfter = await cdpManager.getEntireSystemColl();  	 
	  
      th.assertIsApproximatelyEqual(_aliceCollAfter, _aliceColl.sub(_expectedFeeShare.mul(_aliceStake).div(_totalStake)), 0);
      th.assertIsApproximatelyEqual(_bobCollAfter, _bobColl.sub(_expectedFeeShare.mul(_bobStake).div(_totalStake)), 1);
      th.assertIsApproximatelyEqual(_totalCollAfter, _totalColl.sub(_expectedFeeShare), 1);
	  
      // CDPs should get more underlying collateral since there is staking reward
      let _totalCollAfterAdded = toBN(_aliceCollAfter.toString()).add(toBN(_bobCollAfter.toString()));
      let _underlyingBalAfter = _totalCollAfterAdded.mul(_newIndex).div(mv._1e18BN);
      assert.isTrue(toBN(_underlyingBalAfter.toString()).gt(toBN(_underlyingBalBefore.toString())));
	  
      // As a result, TCR and the CDP ICRs improve as well
      let _aliceIcrAfter = await cdpManager.getCurrentICR(_aliceCdpId, _price);
      let _bobIcrAfter = await cdpManager.getCurrentICR(_bobCdpId, _price);
      let _tcrAfter = await cdpManager.getTCR(_price);
      assert.isTrue(toBN(_aliceIcrAfter.toString()).gt(toBN(_aliceIcrBefore.toString())));
      assert.isTrue(toBN(_bobIcrAfter.toString()).gt(toBN(_bobIcrBefore.toString())));
      assert.isTrue(toBN(_tcrAfter.toString()).gt(toBN(_tcrBefore.toString())));
  })
  
  
})