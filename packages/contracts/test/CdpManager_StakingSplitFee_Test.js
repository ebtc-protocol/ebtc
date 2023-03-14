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
    minDebt = await contracts.borrowerOperations.MIN_NET_DEBT();
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
      	  
      let _oldIndex = mv._1e18BN;
      let _deltaIndex = mv._1_5e18BN.sub(_oldIndex);
      let _newIndex = _oldIndex.add(_deltaIndex);
	  
      // sugardaddy some collateral staking reward by increasing its PPFS
      // to verify we get the collateral accounting correctly
      await collToken.setEthPerShare(_newIndex);
	  
      let _apBalBefore = await collToken.balanceOf(activePool.address);
      await openCdp({ ICR: toBN(dec(299, 16)), extraParams: { from: alice } })
      let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
      let _apBalAfter = await collToken.balanceOf(activePool.address);
	  
      let _aliceColl = await cdpManager.getCdpColl(_aliceCdpId); 
      let _totalColl = await cdpManager.getEntireSystemColl(); 
      th.assertIsApproximatelyEqual(_aliceColl, _totalColl, 0);	
	  
      let _underlyingBalBefore = _totalColl.mul(_newIndex).div(mv._1e18BN);
      th.assertIsApproximatelyEqual(_apBalAfter.sub(_apBalBefore), _underlyingBalBefore);
	  
      let _price = await priceFeed.getPrice();
      let _icrBefore = await cdpManager.getCurrentICR(_aliceCdpId, _price);
      let _tcrBefore = await cdpManager.getTCR(_price);
	  
      await assertRevert(cdpManager.claimStakingSplitFee(), "CdpManager: update index too frequent");	
	  
      // sugardaddy some collateral staking reward by increasing its PPFS again
      _newIndex = _newIndex.add(_deltaIndex);
      await collToken.setEthPerShare(_newIndex);  
	  
      await ethers.provider.send("evm_increaseTime", [86400]);
      await ethers.provider.send("evm_mine");
      let _errorTolerance = 1000;// compared to decimal of 1e18
	  
      let _fees = await cdpManager.calcFeeUponStakingReward(_newIndex, _oldIndex);
      let _expectedFee = _fees[0].mul(_newIndex).div(mv._1e18BN).div(mv._1e18BN);
      
      let _feeBalBefore = await collToken.balanceOf(splitFeeRecipient);
      await cdpManager.claimStakingSplitFee();  
      let _feeBalAfter = await collToken.balanceOf(splitFeeRecipient);
	  
      th.assertIsApproximatelyEqual(_feeBalAfter.sub(_feeBalBefore), _expectedFee);
	  
      // apply accumulated fee split to CDP	upon user operations  	  
      let _expectedFeeShare = _fees[0].div(mv._1e18BN);
      await borrowerOperations.withdrawEBTC(_aliceCdpId, th._100pct, 1, _aliceCdpId, _aliceCdpId, { from: alice, value: 0 })
      let _aliceCollAfter = await cdpManager.getCdpColl(_aliceCdpId); 
      let _totalCollAfter = await cdpManager.getEntireSystemColl(); 
      th.assertIsApproximatelyEqual(_aliceCollAfter, _aliceColl.sub(_expectedFeeShare), _errorTolerance);
      th.assertIsApproximatelyEqual(_totalCollAfter, _totalColl.sub(_expectedFeeShare), _errorTolerance);
	  
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
      // try some big numbers here:
      // with current ETH/BTC exchange rate (0.07428 BTC/ETH)
      // the collateral require is around 350K for each CDP
      await openCdp({ ICR: toBN(dec(299, 16)), extraEBTCAmount: toBN(minDebt.toString()).mul(toBN("10000")), extraParams: { from: alice } })
      let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
	  
      await openCdp({ ICR: toBN(dec(299, 16)), extraEBTCAmount: toBN(minDebt.toString()).mul(toBN("10000")), extraParams: { from: bob } })
      let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);	  
      let _price = await priceFeed.getPrice();
	  
      let _oldIndex = mv._1e18BN;// 1e18 as starting index 
      let _newIndex = mv._1_5e18BN;// 1.05e18 as the first reward
      let _errorTolerance = 2000000;// compared to decimal of 1e18
	  
      // loop to simulate multiple rewards (rebasing up)
      // locally test pass to verify the fee runs as expected with _loop=1000
      // here to make CI friendly, use _loop=10 as default
      let _loop = 10;
      for(let i = 0;i < _loop;i++){
          let _aliceStake = await cdpManager.getCdpStake(_aliceCdpId);
          let _bobStake = await cdpManager.getCdpStake(_bobCdpId); 
          let _totalStake = await cdpManager.totalStakes();
          let _totalStakeAdded = toBN(_aliceStake.toString()).add(toBN(_bobStake.toString())); 	  
          th.assertIsApproximatelyEqual(_totalStakeAdded, _totalStake, 0);
          let _aliceColl = (await cdpManager.getEntireDebtAndColl(_aliceCdpId))[1]; 
          let _bobColl = (await cdpManager.getEntireDebtAndColl(_bobCdpId))[1]; 
          let _totalColl = await cdpManager.getEntireSystemColl(); 
          let _totalCollBeforeAdded = toBN(_aliceColl.toString()).add(toBN(_bobColl.toString()));
          th.assertIsApproximatelyEqual(_totalCollBeforeAdded, _totalColl, _errorTolerance);
		  
          let _underlyingBalBefore = _totalCollBeforeAdded.mul(_oldIndex).div(mv._1e18BN);
          let _aliceIcrBefore = await cdpManager.getCurrentICR(_aliceCdpId, _price);
          let _bobIcrBefore = await cdpManager.getCurrentICR(_bobCdpId, _price);
          let _tcrBefore = await cdpManager.getTCR(_price);
	  
          // sugardaddy some collateral staking reward by increasing its PPFS
          await collToken.setEthPerShare(_newIndex); 	  
          await ethers.provider.send("evm_increaseTime", [86400]);
          await ethers.provider.send("evm_mine");	  
	  
          let _fees = await cdpManager.calcFeeUponStakingReward(_newIndex, _oldIndex); 
          let _feeBalBefore = await collToken.balanceOf(splitFeeRecipient); 
          await cdpManager.claimStakingSplitFee();  	 
          let _feeBalAfter = await collToken.balanceOf(splitFeeRecipient); 
          let _expectedFee = _fees[0].mul(_newIndex).div(mv._1e18BN).div(mv._1e18BN);
          let _actualFee = _feeBalAfter.sub(_feeBalBefore);
	  
          //console.log('i[' + i + ']:_totalCollBeforeAdded=' + _totalCollBeforeAdded + ',_totalColl=' + _totalColl + ',diff=' + (_totalColl.sub(_totalCollBeforeAdded)) + ',_aliceColl=' + _aliceColl + ',_bobColl=' + _bobColl + ',_expectedFee=' + _expectedFee + ',_feeBalDelta=' + _actualFee + ',diffFee=' + (_actualFee.sub(_expectedFee))); 
          th.assertIsApproximatelyEqual(_actualFee, _expectedFee, _errorTolerance);
	  
          // get collateral after applying accumulated split fee
          let _aliceCollAfter = (await cdpManager.getEntireDebtAndColl(_aliceCdpId))[1]; 
          let _bobCollAfter = (await cdpManager.getEntireDebtAndColl(_bobCdpId))[1];
	    
          let _expectedFeeShare = _fees[0].div(mv._1e18BN);	  
          let _totalCollAfter = await cdpManager.getEntireSystemColl();  	 
	  
          th.assertIsApproximatelyEqual(_aliceCollAfter, _aliceColl.sub(_expectedFeeShare.mul(_aliceStake).div(_totalStake)), _errorTolerance);
          th.assertIsApproximatelyEqual(_bobCollAfter, _bobColl.sub(_expectedFeeShare.mul(_bobStake).div(_totalStake)), _errorTolerance);
          th.assertIsApproximatelyEqual(_totalCollAfter, _totalColl.sub(_expectedFeeShare), _errorTolerance); 
	  
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
	  
          // apply accumulated fee split to CDP	upon user operations 
          await borrowerOperations.withdrawEBTC(_aliceCdpId, th._100pct, 1, _aliceCdpId, _aliceCdpId, { from: alice, value: 0 })
          await borrowerOperations.withdrawEBTC(_bobCdpId, th._100pct, 1, _bobCdpId, _bobCdpId, { from: bob, value: 0 })	  
	  	  
          _oldIndex = _newIndex;
          _newIndex = _newIndex.add((mv._1_5e18BN.sub(mv._1e18BN)));// increase by 0.05 for next
      }
  })
  
  
})