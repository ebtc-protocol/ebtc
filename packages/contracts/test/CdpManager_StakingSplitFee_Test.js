const deploymentHelper = require("../utils/deploymentHelpers.js")
const { TestHelper: th, MoneyValues: mv } = require("../utils/testHelpers.js")
const { toBN, dec, ZERO_ADDRESS } = th

const CdpManagerTester = artifacts.require("./CdpManagerTester")
const EBTCToken = artifacts.require("./EBTCToken.sol")
const SimpleLiquidationTester = artifacts.require("./SimpleLiquidationTester.sol");
const GovernorTester = artifacts.require("./GovernorTester.sol");

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
  let _CCR;
  let collToken;
  let splitFeeRecipient;
  let authority;

  const openCdp = async (params) => th.openCdp(contracts, params)

  beforeEach(async () => {
    await deploymentHelper.setDeployGasPrice(1000000000)
    contracts = await deploymentHelper.deployTesterContractsHardhat()
    let LQTYContracts = {}
    LQTYContracts.feeRecipient = contracts.feeRecipient;
	
    cdpManager = contracts.cdpManager
    priceFeed = contracts.priceFeedTestnet
    sortedCdps = contracts.sortedCdps
    debtToken = contracts.ebtcToken;
    activePool = contracts.activePool;
    defaultPool = contracts.defaultPool;
    feeSplit = await contracts.cdpManager.stakingRewardSplit();	
    liq_stipend = await  contracts.cdpManager.LIQUIDATOR_REWARD();
    minDebt = await contracts.borrowerOperations.MIN_NET_STETH_BALANCE();
    _MCR = await cdpManager.MCR();
    _CCR = await cdpManager.CCR();
    LICR = await cdpManager.LICR();
    borrowerOperations = contracts.borrowerOperations;
    collSurplusPool = contracts.collSurplusPool;
    collToken = contracts.collateral;
    hintHelpers = contracts.hintHelpers;
    authority = contracts.authority;

    await deploymentHelper.connectCoreContracts(contracts, LQTYContracts)
	
    splitFeeRecipient = await LQTYContracts.feeRecipient;
  })  

  // Skip: fee recipient is allowed to use standard owner functionality
  xit("FeeRecipient can't renounce owner", async() => {
      await assertRevert(splitFeeRecipient.renounceOwnership({from: owner}), "FeeRecipient: can't renounce owner for sweepToken()");	  
  }) 
  
  it("Claim split fee when there is staking reward coming", async() => {
      	  
      let _oldIndex = mv._1e18BN;
      let _deltaIndex = mv._1_5e18BN.sub(_oldIndex);
      let _newIndex = _oldIndex.add(_deltaIndex);
	  	  
      await ethers.provider.send("evm_increaseTime", [86400]);
      await ethers.provider.send("evm_mine");	  
	  
      // sugardaddy some collateral staking reward by increasing its PPFS
      // to verify we get the collateral accounting correctly
      await collToken.setEthPerShare(_newIndex);
	  
      let _apBalBefore = await collToken.balanceOf(activePool.address);
      let _securityDepositShare = liq_stipend.mul(mv._1e18BN).div(_newIndex);
      await openCdp({ ICR: toBN(dec(299, 16)), extraParams: { from: alice } })
      let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
      let _apBalAfter = await collToken.balanceOf(activePool.address);
	  
      let _aliceColl = await cdpManager.getCdpCollShares(_aliceCdpId); 
      let _totalColl = await cdpManager.getSystemCollShares(); 
      th.assertIsApproximatelyEqual(_aliceColl, _totalColl, 0);	
	  
      let _underlyingBalBefore = _totalColl.mul(_newIndex).div(mv._1e18BN);
      let _underlyingBalTotal = (_totalColl.add(_securityDepositShare)).mul(_newIndex).div(mv._1e18BN);
      let _diffApBal = _apBalAfter.sub(_apBalBefore);
      th.assertIsApproximatelyEqual(_diffApBal, _underlyingBalTotal);
	  
      let _price = await priceFeed.getPrice();
      let _icrBefore = await cdpManager.getCachedICR(_aliceCdpId, _price);
      let _tcrBefore = await cdpManager.getCachedTCR(_price);
	  
      // sugardaddy some collateral staking reward by increasing its PPFS again
      _oldIndex = _newIndex;
      _newIndex = _newIndex.add(_deltaIndex);
      await collToken.setEthPerShare(_newIndex);  
	  
      await ethers.provider.send("evm_increaseTime", [86400]);
      await ethers.provider.send("evm_mine");
      let _errorTolerance = 1000;// compared to decimal of 1e18
	  
      let _fees = await cdpManager.calcFeeUponStakingReward(_newIndex, _oldIndex);
      let _expectedFee = _fees[0].mul(_newIndex).div(mv._1e18BN);
      
      let _feeBalBefore = await activePool.getFeeRecipientClaimableCollShares();
      await cdpManager.syncGlobalAccountingAndGracePeriod();  
      let _feeBalAfter = await activePool.getFeeRecipientClaimableCollShares();
	  
      th.assertIsApproximatelyEqual(_feeBalAfter.sub(_feeBalBefore), _fees[0]);
	  
      // apply accumulated fee split to CDP	upon user operations  	  
      let _expectedFeeShare = _fees[0];
      await borrowerOperations.withdrawDebt(
        _aliceCdpId, await borrowerOperations.MIN_CHANGE(), _aliceCdpId, _aliceCdpId, 
        { from: alice, value: 0 }
      )
      let _aliceCollAfter = await cdpManager.getCdpCollShares(_aliceCdpId); 
      let _totalCollAfter = await cdpManager.getSystemCollShares(); 
      th.assertIsApproximatelyEqual(_aliceCollAfter, _aliceColl.sub(_expectedFeeShare), _errorTolerance);
      th.assertIsApproximatelyEqual(_totalCollAfter, _totalColl.sub(_expectedFeeShare), _errorTolerance);
	  
      // CDP should get more underlying collateral since there is staking reward 
      let _underlyingBalAfter = _aliceCollAfter.mul(_newIndex).div(mv._1e18BN);
      assert.isTrue(toBN(_underlyingBalAfter.toString()).gt(toBN(_underlyingBalBefore.toString())));
	  
      // As a result, TCR and the CDP ICR improve as well
      let _icrAfter = await cdpManager.getCachedICR(_aliceCdpId, _price);
      let _tcrAfter = await cdpManager.getCachedTCR(_price);
      assert.isTrue(toBN(_icrAfter.toString()).gt(toBN(_icrBefore.toString())));
      assert.isTrue(toBN(_tcrAfter.toString()).gt(toBN(_tcrBefore.toString())));
	  
      // ensure syncGlobalAccountingAndGracePeriod() could be called any time
      let _loop = 10;
      for(let i = 0;i < _loop;i++){
          _newIndex = _newIndex.add(_deltaIndex.div(toBN("10")));
          await collToken.setEthPerShare(_newIndex);  
          let _newBalClaimable = await activePool.getFeeRecipientClaimableCollShares();
          await cdpManager.syncGlobalAccountingAndGracePeriod();
          assert.isTrue(_newBalClaimable.lt(await activePool.getFeeRecipientClaimableCollShares()));
          console.log('_newIndex=' + _newIndex);
          console.log('cdpMgr.stEthIndex=' + (await cdpManager.stEthIndex()));
          th.assertIsApproximatelyEqual(_newIndex, (await cdpManager.stEthIndex()), _errorTolerance);		  
      }
  })
  
  it("Fee would be applied to all CDPs when there is staking reward coming", async() => {
      // try some big numbers here:
      // with current ETH/BTC exchange rate (0.07428 BTC/ETH)
      // the collateral require is around 800K for each CDP
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
          th.assertIsApproximatelyEqual(_totalStakeAdded, _totalStake, _errorTolerance);
          let _aliceColl = (await cdpManager.getSyncedDebtAndCollShares(_aliceCdpId))[1]; 
          let _bobColl = (await cdpManager.getSyncedDebtAndCollShares(_bobCdpId))[1]; 
          let _totalColl = await cdpManager.getSystemCollShares(); 
          let _totalCollBeforeAdded = toBN(_aliceColl.toString()).add(toBN(_bobColl.toString()));
          th.assertIsApproximatelyEqual(_totalCollBeforeAdded, _totalColl, _errorTolerance);
          
          let difference = _totalCollBeforeAdded.sub(_totalColl);
          console.log(`[loop${i}] _totalCollBeforeAdded - _totalColl: ${difference}`)
          let _systemStEthFeePerUnitIndexError = await cdpManager.systemStEthFeePerUnitIndexError();
          console.log(`[loop${i}] systemStEthFeePerUnitIndexError: ${_systemStEthFeePerUnitIndexError}`);
          console.log(`[loop${i}] systemStEthFeePerUnitIndexError/1e18: ${_systemStEthFeePerUnitIndexError / 1e18}`);
          let differenceToError = difference.mul(mv._1e18BN).sub(_systemStEthFeePerUnitIndexError);
          console.log(`[loop${i}] differenceToError: ${differenceToError}`)
          console.log(`[loop${i}] differenceToError/1e18: ${differenceToError / 1e18}`)
		  
          let _underlyingBalBefore = _totalCollBeforeAdded.mul(_oldIndex).div(mv._1e18BN);
          let _aliceIcrBefore = await cdpManager.getCachedICR(_aliceCdpId, _price);
          let _bobIcrBefore = await cdpManager.getCachedICR(_bobCdpId, _price);
          let _tcrBefore = await cdpManager.getCachedTCR(_price);
	  
          // sugardaddy some collateral staking reward by increasing its PPFS
          await collToken.setEthPerShare(_newIndex); 	  
          await ethers.provider.send("evm_increaseTime", [86400]);
          await ethers.provider.send("evm_mine");	  
	  
          let _fees = await cdpManager.calcFeeUponStakingReward(_newIndex, _oldIndex);  
          let _expectedFeeShare = _fees[0];
          let _expectedFee = _expectedFeeShare.mul(_newIndex).div(mv._1e18BN);
          let _feeBalBefore = await activePool.getFeeRecipientClaimableCollShares(); 
          await cdpManager.syncGlobalAccountingAndGracePeriod();  	 
          let _feeBalAfter = await activePool.getFeeRecipientClaimableCollShares();
          let _actualFee = _feeBalAfter.sub(_feeBalBefore);
	  
          //console.log('i[' + i + ']:_totalCollBeforeAdded=' + _totalCollBeforeAdded + ',_totalColl=' + _totalColl + ',diff=' + (_totalColl.sub(_totalCollBeforeAdded)) + ',_aliceColl=' + _aliceColl + ',_bobColl=' + _bobColl + ',_expectedFee=' + _expectedFee + ',_feeBalDelta=' + _actualFee + ',diffFee=' + (_actualFee.sub(_expectedFee))); 
          th.assertIsApproximatelyEqual(_actualFee, _expectedFeeShare, _errorTolerance);
	  
          // get collateral after applying accumulated split fee
          let _aliceCollAfter = (await cdpManager.getSyncedDebtAndCollShares(_aliceCdpId))[1]; 
          let _bobCollAfter = (await cdpManager.getSyncedDebtAndCollShares(_bobCdpId))[1];
	  
          let _systemStEthFeePerUnitIndex = await cdpManager.systemStEthFeePerUnitIndex();
          _systemStEthFeePerUnitIndexError = await cdpManager.systemStEthFeePerUnitIndexError();
          let _totalStakeAfter = await cdpManager.totalStakes();
          let _aliceExpectedFeeApplied = await cdpManager.getAccumulatedFeeSplitApplied(_aliceCdpId, _systemStEthFeePerUnitIndex);
          let _bobExpectedFeeApplied = await cdpManager.getAccumulatedFeeSplitApplied(_bobCdpId, _systemStEthFeePerUnitIndex);
	     
          let _totalCollAfter = await cdpManager.getSystemCollShares();  	 
	  
          th.assertIsApproximatelyEqual(_aliceCollAfter, _aliceExpectedFeeApplied[1], _errorTolerance);
          th.assertIsApproximatelyEqual(_bobCollAfter, _bobExpectedFeeApplied[1], _errorTolerance);
          th.assertIsApproximatelyEqual(_totalCollAfter, _totalColl.sub(_expectedFeeShare), _errorTolerance); 
	  
          // CDPs should get more underlying collateral since there is staking reward
          let _totalCollAfterAdded = toBN(_aliceCollAfter.toString()).add(toBN(_bobCollAfter.toString()));
          let _underlyingBalAfter = _totalCollAfterAdded.mul(_newIndex).div(mv._1e18BN);
          assert.isTrue(toBN(_underlyingBalAfter.toString()).gt(toBN(_underlyingBalBefore.toString())));
	  
          // As a result, TCR and the CDP ICRs improve as well
          let _aliceIcrAfter = await cdpManager.getCachedICR(_aliceCdpId, _price);
          let _bobIcrAfter = await cdpManager.getCachedICR(_bobCdpId, _price);
          let _tcrAfter = await cdpManager.getCachedTCR(_price);
          assert.isTrue(toBN(_aliceIcrAfter.toString()).gt(toBN(_aliceIcrBefore.toString())));
          assert.isTrue(toBN(_bobIcrAfter.toString()).gt(toBN(_bobIcrBefore.toString())));
          assert.isTrue(toBN(_tcrAfter.toString()).gt(toBN(_tcrBefore.toString())));
	  
          // apply accumulated fee split to CDP	upon user operations 
          await borrowerOperations.withdrawDebt(
            _aliceCdpId, await borrowerOperations.MIN_CHANGE(), _aliceCdpId, _aliceCdpId, 
            { from: alice, value: 0 }
          )
          await borrowerOperations.withdrawDebt(
            _bobCdpId, await borrowerOperations.MIN_CHANGE(), _bobCdpId, _bobCdpId, 
            { from: bob, value: 0 }
          )	  
	  	  
          _oldIndex = _newIndex;
          _newIndex = _newIndex.add((mv._1_5e18BN.sub(mv._1e18BN)));// increase by 0.05 for next
      }
  })  
  
  it("Claim split fee when there is staking reward coming after liquidation and redemption", async() => {
      	  
      let _oldIndex = mv._1e18BN;
      let _deltaIndex = mv._1_5e18BN.sub(_oldIndex);
      let _newIndex = _oldIndex.add(_deltaIndex);
	  	  
      await ethers.provider.send("evm_increaseTime", [86400]);
      await ethers.provider.send("evm_mine");	  
	  
      let _errorTolerance = 1000;// compared to decimal of 1e18
	  
      // sugardaddy some collateral staking reward by increasing its PPFS
      // to verify we get the collateral accounting correctly
      await collToken.setEthPerShare(_newIndex);
	  
      await openCdp({ ICR: toBN(dec(299, 16)), extraEBTCAmount: toBN(minDebt.toString()).mul(toBN("10")), extraParams: { from: alice } })
      await openCdp({ ICR: toBN(dec(499, 16)), extraParams: { from: bob } })
      let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
      let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
      let _sugarDebt = await debtToken.balanceOf(alice); 
      await debtToken.transfer(owner, _sugarDebt, {from : alice});
      await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
	  
      let _aliceColl = await cdpManager.getCdpCollShares(_aliceCdpId);
      let _bobColl = await cdpManager.getCdpCollShares(_bobCdpId);
      assert.isTrue((await sortedCdps.getFirst()) == _bobCdpId);
	  
      // partially liquidate the CDP	  
      let _newPrice = dec(2800, 13);
      await priceFeed.setPrice(_newPrice);
      let _icrBefore = await cdpManager.getCachedICR(_aliceCdpId, _newPrice);
      let _tcrBefore = await cdpManager.getCachedTCR(_newPrice);	 
      assert.isTrue(toBN(_icrBefore.toString()).gt(LICR));
      assert.isTrue(toBN(_icrBefore.toString()).gt(_MCR));
      let _partialDebtRepaid = minDebt;
      let _expectedSeizedColl = toBN(_partialDebtRepaid.toString()).mul(_MCR).div(toBN(_newPrice));
      let _expectedLiquidatedColl = _expectedSeizedColl.mul(mv._1e18BN).div(_newIndex);
      let _collBeforeLiquidator = await collToken.balanceOf(owner);		  
	  	  
      // trigger cooldown and pass the liq wait
      await th.syncGlobalStateAndGracePeriod(contracts, ethers.provider);
	  
      await cdpManager.partiallyLiquidate(_aliceCdpId, _partialDebtRepaid, _aliceCdpId, _aliceCdpId, {from: owner});
      let _collAfterLiquidator = await collToken.balanceOf(owner);	
      let _aliceCollAfterLiq = await cdpManager.getCdpCollShares(_aliceCdpId);  
      th.assertIsApproximatelyEqual(_collAfterLiquidator.sub(_collBeforeLiquidator), _expectedSeizedColl, _errorTolerance);
      th.assertIsApproximatelyEqual(_aliceColl.sub(_aliceCollAfterLiq), _expectedLiquidatedColl, _errorTolerance);
      _aliceColl = _aliceCollAfterLiq;
	  
      // sugardaddy some collateral staking reward by increasing its PPFS again
      let _oi = _newIndex;
      _newIndex = _newIndex.add(_deltaIndex);
      await collToken.setEthPerShare(_newIndex); 
      await th.syncTwapSystemDebt(contracts, ethers.provider); 
	  
      // redeem alice CDP
      await ethers.provider.send("evm_mine");
	  
      let _redeemDebt = _partialDebtRepaid.mul(toBN("9"));
      const {firstRedemptionHint, partialRedemptionHintNICR, truncatedEBTCamount, partialRedemptionNewColl} = await hintHelpers.getRedemptionHints(_redeemDebt, _newPrice, 0);
      let _expectedColl = toBN(_redeemDebt.toString()).mul(mv._1e18BN).div(toBN(_newPrice));
      let _expectedRedeemedColl = _expectedColl.mul(mv._1e18BN).div(_newIndex);
      let _expectedRedeemFloor = await cdpManager.redemptionFeeFloor();	  
      let _collBeforeRedeemer = await collToken.balanceOf(owner); 
      let _newFeeIndex = await cdpManager.calcFeeUponStakingReward(_newIndex, _oi);
      let _splitFeeAccumulated = await cdpManager.getAccumulatedFeeSplitApplied(_aliceCdpId, _newFeeIndex[1].add(await cdpManager.systemStEthFeePerUnitIndex()));
      let _weightedMean = await th.simulateObserveForTWAP(contracts, ethers.provider, 1);
      let _expectedBaseRate = await cdpManager.getUpdatedBaseRateFromRedemptionWithSystemDebt(_expectedRedeemedColl, _newPrice, _weightedMean);
      await cdpManager.redeemCollateral(_redeemDebt, firstRedemptionHint, _aliceCdpId, _aliceCdpId, partialRedemptionHintNICR, 0, th._100pct, {from: owner});
      let _collAfterRedeemer = await collToken.balanceOf(owner);	
      let _aliceCollAfterRedeem = await cdpManager.getCdpCollShares(_aliceCdpId);  
      assert.isTrue(_aliceCollAfterRedeem.eq(partialRedemptionNewColl));
      let _expectedCollAfterFee = _expectedRedeemedColl.sub(_expectedRedeemedColl.mul(_expectedRedeemFloor.add(_expectedBaseRate)).div(mv._1e18BN)).mul(_newIndex).div(mv._1e18BN);
      th.assertIsApproximatelyEqual(_collAfterRedeemer.sub(_collBeforeRedeemer), _expectedCollAfterFee, 100000000);
      th.assertIsApproximatelyEqual(_splitFeeAccumulated[1].sub(partialRedemptionNewColl), _expectedRedeemedColl, _errorTolerance);
      _aliceColl = _aliceCollAfterRedeem;
      assert.isTrue((await sortedCdps.getFirst()) == _aliceCdpId);// reinsertion after redemption 
	  
      // sugardaddy some collateral staking reward by increasing its PPFS one more time
      _oldIndex = _newIndex;
      _newIndex = _newIndex.add(_deltaIndex);
      await collToken.setEthPerShare(_newIndex);
	  
      await ethers.provider.send("evm_increaseTime", [86400]);
      await ethers.provider.send("evm_mine");
	  
      let _fees = await cdpManager.calcFeeUponStakingReward(_newIndex, _oldIndex);
      let _expectedFeeShare = _fees[0];
      let _expectedFee = _expectedFeeShare.mul(_newIndex).div(mv._1e18BN);
	  
      let _feeBalBefore = await activePool.getFeeRecipientClaimableCollShares();
      await cdpManager.syncGlobalAccountingAndGracePeriod();  
      let _feeBalAfter = await activePool.getFeeRecipientClaimableCollShares();
	  
      let _systemStEthFeePerUnitIndex = await cdpManager.systemStEthFeePerUnitIndex();
      let _systemStEthFeePerUnitIndexError = await cdpManager.systemStEthFeePerUnitIndexError();
      let _totalStake = await cdpManager.totalStakes();
      let _aliceExpectedFeeApplied = await cdpManager.getAccumulatedFeeSplitApplied(_aliceCdpId, _systemStEthFeePerUnitIndex);
      let _bobExpectedFeeApplied = await cdpManager.getAccumulatedFeeSplitApplied(_bobCdpId, _systemStEthFeePerUnitIndex);
	  
      th.assertIsApproximatelyEqual(_feeBalAfter.sub(_feeBalBefore), _expectedFeeShare, _errorTolerance);
	  
      // check after accumulated fee split applied to CDPs
      let _aliceCollAfter = (await cdpManager.getSyncedDebtAndCollShares(_aliceCdpId))[1];
      th.assertIsApproximatelyEqual(_aliceCollAfter, _aliceExpectedFeeApplied[1], _errorTolerance);
      let _bobCollDebtAfter = await cdpManager.getSyncedDebtAndCollShares(_bobCdpId);
      th.assertIsApproximatelyEqual(_bobCollDebtAfter[1], _bobExpectedFeeApplied[1], _errorTolerance);
	  
      // fully liquidate the riskiest CDP with fee split applied	  
      _newPrice = dec(1520, 13);
      await priceFeed.setPrice(_newPrice);
      let _icrBobAfter = await cdpManager.getCachedICR(_bobCdpId, _newPrice);
      assert.isTrue(toBN(_icrBobAfter.toString()).gt(LICR));
      let _expectedLiquidatedCollBob = (_bobCollDebtAfter[0].mul(_icrBobAfter).div(toBN(_newPrice))).mul(mv._1e18BN).div(_newIndex);
      await cdpManager.liquidate(_bobCdpId, {from: owner});
      let _surplusToClaimBob = await collSurplusPool.getSurplusCollShares(bob);
      th.assertIsApproximatelyEqual(_surplusToClaimBob, _bobCollDebtAfter[1].sub(_expectedLiquidatedCollBob), _errorTolerance);
  })
  
  it("SetStakingRewardSplit() should only allow authorized caller", async() => {	  
      await assertRevert(cdpManager.setStakingRewardSplit(1, {from: alice}), "Auth: UNAUTHORIZED");   
      await assertRevert(cdpManager.setStakingRewardSplit(10001, {from: owner}), "CDPManager: new staking reward split exceeds max");
      assert.isTrue(5000 == (await cdpManager.stakingRewardSplit())); 
	  	  
      assert.isTrue(authority.address == (await cdpManager.authority()));
      const accounts = await web3.eth.getAccounts()
      assert.isTrue(accounts[0] == (await authority.owner()));
      let _role123 = 123;
      let _splitRewardSig = "0xb6fe918a";//cdpManager#SET_STAKING_REWARD_SPLIT_SIG;
      await authority.setRoleCapability(_role123, cdpManager.address, _splitRewardSig, true, {from: accounts[0]});	  
      await authority.setUserRole(alice, _role123, true, {from: accounts[0]});
      assert.isTrue((await authority.canCall(alice, cdpManager.address, _splitRewardSig)));
      let _newSplitFee = 9876;
      await cdpManager.setStakingRewardSplit(_newSplitFee, {from: alice}); 
      assert.isTrue(_newSplitFee == (await cdpManager.stakingRewardSplit()));  
  })
  
  it("Test fee split claim with weird slashing and rewarding", async() => {
      let _errorTolerance = toBN("2000000");//compared to 1e18
      	  
      // slashing: decreaseCollateralRate(1)	  	  
      await ethers.provider.send("evm_increaseTime", [43924]);
      await ethers.provider.send("evm_mine");
      let _newIndex = 1;// yep, one wei
      await collToken.setEthPerShare(_newIndex);
	  
      // open CDP
      let _collAmt = toBN("9751958561574716850");
      let _ebtcAmt = toBN("148960105069686413");
      await collToken.deposit({from: owner, value: _collAmt});
      await collToken.approve(borrowerOperations.address, mv._1Be18BN, {from: owner});
      await borrowerOperations.openCdp(_ebtcAmt, th.DUMMY_BYTES32, th.DUMMY_BYTES32, _collAmt);
      let _cdpId = await sortedCdps.cdpOfOwnerByIndex(owner, 0);
      let _cdpDebtColl = await cdpManager.getSyncedDebtAndCollShares(_cdpId);
      let _activeColl = await activePool.getSystemCollShares();
      let _systemDebt = await cdpManager.getSystemDebt();
      th.assertIsApproximatelyEqual(_activeColl, _cdpDebtColl[1], _errorTolerance.toNumber());
      th.assertIsApproximatelyEqual(_systemDebt, _cdpDebtColl[0], _errorTolerance.toNumber());
	  
      // rewarding: increaseCollateralRate(6)	  	  
      await ethers.provider.send("evm_increaseTime", [44823]);
      await ethers.provider.send("evm_mine");  
      _newIndex = 6;
      await collToken.setEthPerShare(_newIndex);  
	  
      // claim fee
      await cdpManager.syncGlobalAccountingAndGracePeriod();
	  
      // final check
      _cdpDebtColl = await cdpManager.getSyncedDebtAndCollShares(_cdpId);
      _systemDebt = await cdpManager.getSystemDebt();
      th.assertIsApproximatelyEqual(_systemDebt, _cdpDebtColl[0], _errorTolerance.toNumber());
	  
      _cdpColl = _cdpDebtColl[1];
      _activeColl = await activePool.getSystemCollShares();
      let _diff = _cdpColl.gt(_activeColl)? _cdpColl.sub(_activeColl).mul(mv._1e18BN) : _activeColl.sub(_cdpColl).mul(mv._1e18BN);
      let _divisor = _cdpColl.gt(_activeColl)? _cdpColl : _activeColl;
      let _target = _errorTolerance.mul(_divisor);
      assert.isTrue(_diff.lt(_target));  
  })
  
  it("Test fee split claim before TCR calculation for Borrower Operations", async() => {	  
      await openCdp({ ICR: toBN(dec(130, 16)), extraParams: { from: owner } });
	  
      // make some fee to claim
      await ethers.provider.send("evm_increaseTime", [43924]);
      await ethers.provider.send("evm_mine");
      let _oldIndex = web3.utils.toBN('1000000000000000000');
      let _newIndex = web3.utils.toBN('1500000000000000000');
      await collToken.setEthPerShare(_newIndex);
	  
      // price drops
      let _originalPrice = await priceFeed.getPrice();	  
      let _newPrice = dec(7000, 13);
      await priceFeed.setPrice(_newPrice);
      assert.isFalse(await cdpManager.checkRecoveryMode(_newPrice));
	  	  
      assert.isTrue(authority.address == (await cdpManager.authority()));
      const accounts = await web3.eth.getAccounts()
      assert.isTrue(accounts[0] == (await authority.owner()));
      let _role123 = 123;
      let _splitRewardSig = "0xb6fe918a";//cdpManager#SET_STAKING_REWARD_SPLIT_SIG;
      await authority.setRoleCapability(_role123, cdpManager.address, _splitRewardSig, true, {from: accounts[0]});	  
      await authority.setUserRole(alice, _role123, true, {from: accounts[0]});
      assert.isTrue((await authority.canCall(alice, cdpManager.address, _splitRewardSig)));
      let _newSplitFee = 9999;
      await cdpManager.setStakingRewardSplit(_newSplitFee, {from: alice}); 
      assert.isTrue(_newSplitFee == (await cdpManager.stakingRewardSplit()));  
	  
      // open CDP will revert due to TCR reduce after fee claim
      let _collAmt = toBN("19751958561574716850");
      let _ebtcAmt = toBN("1158960105069686413");
      await collToken.deposit({from: owner, value: _collAmt});    
      let _deltaRequiredIdx = await cdpManager.getDeltaIndexToTriggerRM(_newIndex, _newPrice, _newSplitFee);
      assert.isTrue(_newIndex.sub(_oldIndex).gte(_deltaRequiredIdx));  
      await assertRevert(borrowerOperations.openCdp(_ebtcAmt, th.DUMMY_BYTES32, th.DUMMY_BYTES32, _collAmt), "BorrowerOperations: Operation must leave cdp with ICR >= CCR");
	  
      // price rebounce and open CDP  
      await priceFeed.setPrice(_originalPrice);    
      await borrowerOperations.openCdp(_ebtcAmt, th.DUMMY_BYTES32, th.DUMMY_BYTES32, _collAmt);
      let _cdpId = await sortedCdps.cdpOfOwnerByIndex(owner, 0);
	  
      // make some fee to claim
      await ethers.provider.send("evm_increaseTime", [43924]);
      await ethers.provider.send("evm_mine");
      _oldIndex = _newIndex;
      _newIndex = web3.utils.toBN('1750000000000000000');
      await collToken.setEthPerShare(_newIndex);
	  
      // price drop again
      await priceFeed.setPrice(_newPrice);
      assert.isFalse(await cdpManager.checkRecoveryMode(_newPrice));
	  
      // adjust CDP will revert due to TCR reduce after fee claim	   
      let _moreDebt = toBN("708960105069686413");	 
      _deltaRequiredIdx = await cdpManager.getDeltaIndexToTriggerRM(_newIndex, _newPrice, _newSplitFee);
      assert.isTrue(_newIndex.sub(_oldIndex).gte(_deltaRequiredIdx));    
      await assertRevert(borrowerOperations.withdrawDebt(_cdpId, _moreDebt, th.DUMMY_BYTES32, th.DUMMY_BYTES32), "BorrowerOperations: Operation must leave cdp with ICR >= CCR");
	  
      // price rebounce and adjust CDP  
      await priceFeed.setPrice(_originalPrice);
      borrowerOperations.withdrawDebt(_cdpId, _moreDebt, th.DUMMY_BYTES32, th.DUMMY_BYTES32)
	  	  
      // make some fee to claim
      await ethers.provider.send("evm_increaseTime", [43924]);
      await ethers.provider.send("evm_mine");
      _oldIndex = _newIndex;
      _newIndex = web3.utils.toBN('1950000000000000000');
      await collToken.setEthPerShare(_newIndex);
	  
      // price drop deeper and closeCdp revert due to TCR reduce after claim fee
      _newPrice = dec(6000,13)
      await priceFeed.setPrice(_newPrice);
      assert.isFalse(await cdpManager.checkRecoveryMode(_newPrice));
      _deltaRequiredIdx = await cdpManager.getDeltaIndexToTriggerRM(_newIndex, _newPrice, _newSplitFee);
      assert.isTrue(_newIndex.sub(_oldIndex).gte(_deltaRequiredIdx));
      await assertRevert(borrowerOperations.closeCdp(_cdpId), "BorrowerOperations: Operation not permitted during Recovery Mode")
  })
  
  it("Test first ICR compared to TCR when there is staking reward", async() => {
      let _errorTolerance = toBN("10000000000000");//1e13 compared to 1e18
	  
      // open several CDPs
      let _collAmt = toBN("1000000000000000000000");
      let _ebtcAmt = toBN("6400");
      await collToken.approve(borrowerOperations.address, mv._1Be18BN, {from: owner});
      await collToken.deposit({from: owner, value: _collAmt});
      await borrowerOperations.openCdp(_ebtcAmt, th.DUMMY_BYTES32, th.DUMMY_BYTES32, _collAmt);
      await collToken.deposit({from: owner, value: _collAmt});
      await borrowerOperations.openCdp(_ebtcAmt, th.DUMMY_BYTES32, th.DUMMY_BYTES32, _collAmt);
	  
      // rewarding: increaseCollateralRate(1022581370615858762)	  	  
      await ethers.provider.send("evm_increaseTime", [44823]);
      await ethers.provider.send("evm_mine");  
      let _newIndex = toBN("1022581370615858762");
      await collToken.setEthPerShare(_newIndex); 
	  
      // final check
      let _price = await priceFeed.getPrice();
      let _firstId = await sortedCdps.getFirst();
      let _firstICR = await cdpManager.getCachedICR(_firstId, _price);
      let _tcr = await cdpManager.getCachedTCR(_price);
      th.assertIsApproximatelyEqual(_firstICR, _tcr, _errorTolerance.toNumber());
	  	  
      // get a CDP to be liquidated with bad debt
      await openCdp({ ICR: toBN(dec(126, 16)), extraParams: { from: alice } });
      let _liqId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
      let _liqDebt = await cdpManager.getCdpDebt(_liqId);
      _price = toBN("58000000000000000");
      await priceFeed.setPrice(_price);
      let _toLiqICR = await cdpManager.getCachedICR(_liqId, _price);
      assert.isTrue(_toLiqICR.lt(LICR));
      await debtToken.transfer(owner, _liqDebt, {from: alice});
      await cdpManager.liquidate(_liqId, {from: owner});
      let _pendingDebt = await cdpManager.getPendingRedistributedDebt(_firstId);
      assert.isTrue(_pendingDebt.gt(toBN("0")));
	  
      // check synced state before change applied
      let _syncedColl = await cdpManager.getSyncedCdpCollShares(_firstId);
      let _syncedDebt = await cdpManager.getSyncedCdpDebt(_firstId);
      let _syncedICR = await cdpManager.getSyncedICR(_firstId, _price);
      let _syncedTCR = await cdpManager.getSyncedTCR(_price);
	  
      // apply CDP sync with staking split fee
      await borrowerOperations.withdrawDebt(_firstId, await borrowerOperations.MIN_CHANGE(), th.DUMMY_BYTES32, th.DUMMY_BYTES32);
      await borrowerOperations.repayDebt(_firstId, await borrowerOperations.MIN_CHANGE(), th.DUMMY_BYTES32, th.DUMMY_BYTES32);
      let _newIdxCached = await cdpManager.stEthIndex();
      assert.isTrue(_newIdxCached.eq(_newIndex));
      let _cdpCollAfter = await cdpManager.getCdpCollShares(_firstId);
      let _cdpDebtAfter = await cdpManager.getCdpDebt(_firstId);
      let _cdpIcrAfter = await cdpManager.getCachedICR(_firstId, _price);
      let _tcrAfter = await cdpManager.getCachedTCR(_price);
      assert.isTrue(_cdpCollAfter.eq(_syncedColl));
      assert.isTrue(_cdpDebtAfter.eq(_syncedDebt));
      assert.isTrue(_cdpIcrAfter.eq(_syncedICR));
      assert.isTrue(_tcrAfter.eq(_syncedTCR));
  })    
  
  it("Test new CDP won't have split fee & redistributed debt if there is staking reward and bad-debt liquidation before its initialization", async() => {
      let _errorTolerance = toBN("10000000000000");//1e13 compared to 1e18
	  
      // open several CDPs
      let _collAmt = toBN("1000000000000000000000");
      let _ebtcAmt = toBN("6400");
      await collToken.approve(borrowerOperations.address, mv._1Be18BN, {from: owner});
      await collToken.deposit({from: owner, value: _collAmt});
      await borrowerOperations.openCdp(_ebtcAmt, th.DUMMY_BYTES32, th.DUMMY_BYTES32, _collAmt);
      await collToken.deposit({from: owner, value: _collAmt});
      await borrowerOperations.openCdp(_ebtcAmt, th.DUMMY_BYTES32, th.DUMMY_BYTES32, _collAmt);
	  
      // rewarding: increaseCollateralRate(1022581370615858762)	  	  
      await ethers.provider.send("evm_increaseTime", [44823]);
      await ethers.provider.send("evm_mine");  
      let _newIndex = toBN("1022581370615858762");
      await collToken.setEthPerShare(_newIndex); 
	  
      // final check
      let _price = await priceFeed.getPrice();
      let _firstId = await sortedCdps.getFirst();
      let _firstICR = await cdpManager.getCachedICR(_firstId, _price);
      let _tcr = await cdpManager.getCachedTCR(_price);
      th.assertIsApproximatelyEqual(_firstICR, _tcr, _errorTolerance.toNumber());
	  	  
      // get a CDP to be liquidated with bad debt
      await openCdp({ ICR: toBN(dec(126, 16)), extraParams: { from: alice } });
      let _liqId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
      let _liqDebt = await cdpManager.getCdpDebt(_liqId);
      _price = toBN("58000000000000000");
      await priceFeed.setPrice(_price);
      let _toLiqICR = await cdpManager.getCachedICR(_liqId, _price);
      assert.isTrue(_toLiqICR.lt(LICR));
      await debtToken.transfer(owner, _liqDebt, {from: alice});
      await cdpManager.liquidate(_liqId, {from: owner});
      let _pendingDebt = await cdpManager.getPendingRedistributedDebt(_firstId);
      assert.isTrue(_pendingDebt.gt(toBN("0")));
	  
      // create a new CDP at this moment 
      // when system got some debt redistribution and some split fee to charge	  	  
      await ethers.provider.send("evm_increaseTime", [44823]);
      await ethers.provider.send("evm_mine");  
      let _newIndex2 = _newIndex.add(toBN("12345678901234567"));
      await collToken.setEthPerShare(_newIndex2); 
      let { tx: opBobTx, _finalColl: bob_coll, totalDebt: bob_totalDebt } = await openCdp({ ICR: toBN(dec(196, 16)), extraParams: { from: bob } });
      let _bobId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
	  
      // check synced state after CDP initialization
      let _bobDebtIndex = await cdpManager.cdpDebtRedistributionIndex(_bobId);
      let _globalDebtIndex = await cdpManager.systemDebtRedistributionIndex();
      assert.isTrue(_globalDebtIndex.eq(_bobDebtIndex));
      let _bobFeeIndex = await cdpManager.cdpStEthFeePerUnitIndex(_bobId);
      let _globalFeeIndex = await cdpManager.systemStEthFeePerUnitIndex();
      assert.isTrue(_globalFeeIndex.eq(_bobFeeIndex));
	  
      // check CDP coll & debt after initialization
      let _bobDebt = await cdpManager.getCdpDebt(_bobId);
      let _bobColl = await cdpManager.getCdpCollShares(_bobId);
      let _emittedDebt = await th.getEventArgByName(opBobTx, "CdpUpdated", "_debt");
      let _emittedColl = await th.getEventArgByName(opBobTx, "CdpUpdated", "_coll");
      let bob_collShare = bob_coll.sub(liq_stipend).mul(mv._1e18BN).div(_newIndex2);
	  
      assert.isTrue(toBN(_emittedDebt).eq(_bobDebt));
      assert.isTrue(toBN(_emittedDebt).eq(bob_totalDebt));
      assert.isTrue(toBN(_emittedColl).eq(_bobColl));
      th.assertIsApproximatelyEqual(toBN(_emittedColl), bob_collShare, _errorTolerance.toNumber());
  })  

  it("Malicious Recovery Mode triggering should fail within Borrower Operations: openCDP() due to sync-up of staking index", async() => {	  
      await openCdp({ ICR: toBN(dec(126, 16)), extraParams: { from: owner } });
      let _victimId = await sortedCdps.cdpOfOwnerByIndex(owner, 0);	  
      await openCdp({ ICR: toBN(dec(129, 16)), extraParams: { from: owner } });

      let _price = dec(7228, 13);
      await priceFeed.setPrice(_price);

      // modify split fee
      assert.isTrue(authority.address == (await cdpManager.authority()));
      const accounts = await web3.eth.getAccounts()
      assert.isTrue(accounts[0] == (await authority.owner()));
      let _role123 = 123;
      let _splitRewardSig = "0xb6fe918a";//cdpManager#SET_STAKING_REWARD_SPLIT_SIG;
      await authority.setRoleCapability(_role123, cdpManager.address, _splitRewardSig, true, {from: accounts[0]});	  
      await authority.setUserRole(alice, _role123, true, {from: accounts[0]});
      assert.isTrue((await authority.canCall(alice, cdpManager.address, _splitRewardSig)));
      let _splitFee = 2399;
      await cdpManager.setStakingRewardSplit(_splitFee, {from: alice});
      let _s = await cdpManager.stakingRewardSplit(); 
      assert.isTrue(_splitFee == _s); 

      // make some fee to claim
      await ethers.provider.send("evm_increaseTime", [43924]);
      await ethers.provider.send("evm_mine");
      let _oldIndex = web3.utils.toBN('1000000000000000000');
      let _newIndex = web3.utils.toBN('1010000000000000000');
      let _deltaIndex = _newIndex.sub(_oldIndex);
      let _idxPrime = _newIndex.sub(_deltaIndex.mul(_s).div(toBN("10000")));// I' = (I - deltaI * splitFee)
      await collToken.setEthPerShare(_newIndex);

      // check TCR for victim
      let _tcrBefore = await cdpManager.getCachedTCR(_price);
      let _victimICRBefore = await cdpManager.getCachedICR(_victimId, _price);
      assert.isTrue(_tcrBefore.gt(_CCR));
      assert.isTrue(_victimICRBefore.lt(_CCR));
      let _1e36 = mv._1e18BN.mul(mv._1e18BN);

      // calculate triggering CDP parameters
      let _totalC = await cdpManager.getSystemCollShares();
      let _totalD = await cdpManager.getSystemDebt();	  
      let _icrUpper = _CCR// icr < CCR
      let _numerator = _totalC.mul(_idxPrime).mul(toBN(_price)).div(_1e36).sub(_CCR.mul(_totalD).div(mv._1e18BN));// (C * I' * p - CCR * D)
      let _icrLower = _CCR.mul(_newIndex).mul(toBN(_price)).mul(minDebt).div(_1e36).div(_numerator.add(minDebt.mul(toBN(_price)).mul(_newIndex).div(_1e36)))// icr > (2 * p * I * CCR) / (C * I' * p - CCR * D + 2 * p * I)
      let _icr = toBN("1249753714546239750");
      let _denominator = _CCR.sub(_icr);// CCR - icr
      let _ebtcAmt = _numerator.mul(mv._1e18BN).div(_denominator).add(toBN("1234567890"));

      // attacker open CDP to facilitate Recovery Mode triggering deliberately
      let _collAmt = liq_stipend.add(_ebtcAmt.mul(_icr).div(toBN(_price)));
      //console.log('_totalC=' + _totalC + ', _totalD=' + _totalD + ", _I'=" + _idxPrime + ', _d=' + _ebtcAmt + ', _c=' + _collAmt + ', _icrLower=' + _icrLower);
      await collToken.deposit({from: bob, value: _collAmt});   
      await collToken.approve(borrowerOperations.address, mv._1Be18BN, {from: bob});  
      let _deltaRequiredIdx = await cdpManager.getDeltaIndexToTriggerRM(_newIndex, _price, _splitFee);
      assert.isTrue(_deltaIndex.lte(_deltaRequiredIdx));  
      let _idxBefore = await cdpManager.stEthIndex();
      assert.isTrue(_idxBefore.eq(_oldIndex));
      await assertRevert(borrowerOperations.openCdp(_ebtcAmt, th.DUMMY_BYTES32, th.DUMMY_BYTES32, _collAmt, {from: bob}), "BorrowerOps: An operation that would result in TCR < CCR is not permitted");
  })  
  
  it("Test Invariants BO-03 (Medusa): Adding collateral improves Nominal ICR", async() => {
      let _errorTolerance = toBN("2000000");//compared to 1e18
      	  
      // slashing a bit	  	  
      await ethers.provider.send("evm_increaseTime", [43924]);
      await ethers.provider.send("evm_mine");
      let _newIndex = toBN("909090909090909202");
      await collToken.setEthPerShare(_newIndex);
	  
      // open CDP
      let _collAmt = toBN("2200000000000107717");
      let _ebtcAmt = toBN("6401");
      await collToken.deposit({from: owner, value: _collAmt});
      await collToken.approve(borrowerOperations.address, mv._1Be18BN, {from: owner});
      await borrowerOperations.openCdp(_ebtcAmt, th.DUMMY_BYTES32, th.DUMMY_BYTES32, _collAmt);
      let _cdpId = await sortedCdps.cdpOfOwnerByIndex(owner, 0);
      let _cdpDebtColl = await cdpManager.getSyncedDebtAndCollShares(_cdpId);
      let _nicrStart = await cdpManager.getCachedNominalICR(_cdpId);
      let _cdpSplitIdxStart = await cdpManager.cdpStEthFeePerUnitIndex(_cdpId); 
      console.log('startNICR:' + _nicrStart + ', _cdpSplitIdxStart=' + _cdpSplitIdxStart);	  
	  
      // now there is staking reward to split
      let _newIndex2 = toBN("1000000000000000000");
      await collToken.setEthPerShare(_newIndex2);
	  
      // check split fee to be applied
      let _totalFee = await cdpManager.calcFeeUponStakingReward(_newIndex2, _newIndex);
      let _deltaIdxPerUnit = _totalFee[1];
      let _expectedNewIdxPerUnit = _cdpSplitIdxStart.add(_deltaIdxPerUnit);
      let _expectedFeeApplied = await cdpManager.getAccumulatedFeeSplitApplied(_cdpId, _expectedNewIdxPerUnit);	
      let _expectedFeeAppliedToCdp = _expectedFeeApplied[0].div(mv._1e18BN);
      console.log('_expectedNewIdxPerUnit:' + _expectedNewIdxPerUnit + ', _expectedFeeApplied:' + _expectedFeeAppliedToCdp);  
      let _expectedLeftColl = _cdpDebtColl[1].sub(_expectedFeeAppliedToCdp);
	  
      let _addedColl = await borrowerOperations.MIN_CHANGE();
      assert.isTrue(_expectedFeeApplied[0].gt(_addedColl));// split fee take more collateral than added so NICR could decrease
      await collToken.deposit({from: owner, value: _addedColl});
      await borrowerOperations.addColl(_cdpId, _cdpId, _cdpId, _addedColl, { from: owner, value: 0 })
      let _cdpSplitIdxAfter = await cdpManager.cdpStEthFeePerUnitIndex(_cdpId); 
      assert.isTrue(_cdpSplitIdxAfter.eq(_expectedNewIdxPerUnit));
	  
      let _nicrAfter = await cdpManager.getCachedNominalICR(_cdpId);
      console.log('_nicrAfter:' + _nicrAfter + ', _cdpSplitIdxAfter=' + _cdpSplitIdxAfter);	
      assert.isTrue(_nicrAfter.lt(_nicrStart));
	  
      let _cdpCollAfter = await cdpManager.getCdpCollShares(_cdpId);
      console.log('_expectedLeftColl=' + _expectedLeftColl + ', _cdpCollAfter=' + _cdpCollAfter);
      th.assertIsApproximatelyEqual(_cdpCollAfter, _expectedLeftColl, _errorTolerance.toNumber());
  })
  
  
})