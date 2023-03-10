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
      let _underlyingBalBefore = _aliceColl; 
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
      th.assertIsApproximatelyEqual(_aliceColl, _totalColl, 0); 
	  
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
  
  
})