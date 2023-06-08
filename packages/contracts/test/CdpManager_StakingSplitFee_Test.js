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
  let collToken;
  let splitFeeRecipient;
  let authority;

  const openCdp = async (params) => th.openCdp(contracts, params)

  beforeEach(async () => {
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
    minDebt = await contracts.borrowerOperations.MIN_NET_COLL();
    _MCR = await cdpManager.MCR();
    LICR = await cdpManager.LICR();
    borrowerOperations = contracts.borrowerOperations;
    collSurplusPool = contracts.collSurplusPool;
    collToken = contracts.collateral;
    hintHelpers = contracts.hintHelpers;
    authority = contracts.authority;

    await deploymentHelper.connectCoreContracts(contracts, LQTYContracts)
	
    splitFeeRecipient = await LQTYContracts.feeRecipient;
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
	  
      let _aliceColl = await cdpManager.getCdpColl(_aliceCdpId); 
      let _totalColl = await cdpManager.getEntireSystemColl(); 
      th.assertIsApproximatelyEqual(_aliceColl, _totalColl, 0);	
	  
      let _underlyingBalBefore = (_totalColl.add(_securityDepositShare)).mul(_newIndex).div(mv._1e18BN);
      let _diffApBal = _apBalAfter.sub(_apBalBefore);
      th.assertIsApproximatelyEqual(_diffApBal, _underlyingBalBefore);
	  
      let _price = await priceFeed.getPrice();
      let _icrBefore = await cdpManager.getCurrentICR(_aliceCdpId, _price);
      let _tcrBefore = await cdpManager.getTCR(_price);
	  
      // sugardaddy some collateral staking reward by increasing its PPFS again
      _oldIndex = _newIndex;
      _newIndex = _newIndex.add(_deltaIndex);
      await collToken.setEthPerShare(_newIndex);  
	  
      await ethers.provider.send("evm_increaseTime", [86400]);
      await ethers.provider.send("evm_mine");
      let _errorTolerance = 1000;// compared to decimal of 1e18
	  
      let _fees = await cdpManager.calcFeeUponStakingReward(_newIndex, _oldIndex);
      let _expectedFee = _fees[0].mul(_newIndex).div(mv._1e18BN);
      
      let _feeBalBefore = await activePool.getFeeRecipientClaimableColl();
      await cdpManager.claimStakingSplitFee();  
      let _feeBalAfter = await activePool.getFeeRecipientClaimableColl();
	  
      th.assertIsApproximatelyEqual(_feeBalAfter.sub(_feeBalBefore), _fees[0]);
	  
      // apply accumulated fee split to CDP	upon user operations  	  
      let _expectedFeeShare = _fees[0];
      await borrowerOperations.withdrawEBTC(_aliceCdpId, 1, _aliceCdpId, _aliceCdpId, { from: alice, value: 0 })
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
	  
      // ensure the index update interval is respected
      _newIndex = _newIndex.add(_deltaIndex);
      await collToken.setEthPerShare(_newIndex);  
      await assertRevert(cdpManager.claimStakingSplitFee(), "CdpManager: update index too frequent");	
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
          let _aliceColl = (await cdpManager.getEntireDebtAndColl(_aliceCdpId))[1]; 
          let _bobColl = (await cdpManager.getEntireDebtAndColl(_bobCdpId))[1]; 
          let _totalColl = await cdpManager.getEntireSystemColl(); 
          let _totalCollBeforeAdded = toBN(_aliceColl.toString()).add(toBN(_bobColl.toString()));
          th.assertIsApproximatelyEqual(_totalCollBeforeAdded, _totalColl, _errorTolerance);
          
          let difference = _totalCollBeforeAdded.sub(_totalColl);
          console.log(`[loop${i}] _totalCollBeforeAdded - _totalColl: ${difference}`)
          let _stFeePerUnitgError = await cdpManager.stFeePerUnitgError();
          console.log(`[loop${i}] stFeePerUnitgError: ${_stFeePerUnitgError}`);
          console.log(`[loop${i}] stFeePerUnitgError/1e18: ${_stFeePerUnitgError / 1e18}`);
          let differenceToError = difference.mul(mv._1e18BN).sub(_stFeePerUnitgError);
          console.log(`[loop${i}] differenceToError: ${differenceToError}`)
          console.log(`[loop${i}] differenceToError/1e18: ${differenceToError / 1e18}`)
		  
          let _underlyingBalBefore = _totalCollBeforeAdded.mul(_oldIndex).div(mv._1e18BN);
          let _aliceIcrBefore = await cdpManager.getCurrentICR(_aliceCdpId, _price);
          let _bobIcrBefore = await cdpManager.getCurrentICR(_bobCdpId, _price);
          let _tcrBefore = await cdpManager.getTCR(_price);
	  
          // sugardaddy some collateral staking reward by increasing its PPFS
          await collToken.setEthPerShare(_newIndex); 	  
          await ethers.provider.send("evm_increaseTime", [86400]);
          await ethers.provider.send("evm_mine");	  
	  
          let _fees = await cdpManager.calcFeeUponStakingReward(_newIndex, _oldIndex);  
          let _expectedFeeShare = _fees[0];
          let _expectedFee = _expectedFeeShare.mul(_newIndex).div(mv._1e18BN);
          let _feeBalBefore = await activePool.getFeeRecipientClaimableColl(); 
          await cdpManager.claimStakingSplitFee();  	 
          let _feeBalAfter = await activePool.getFeeRecipientClaimableColl();
          let _actualFee = _feeBalAfter.sub(_feeBalBefore);
	  
          //console.log('i[' + i + ']:_totalCollBeforeAdded=' + _totalCollBeforeAdded + ',_totalColl=' + _totalColl + ',diff=' + (_totalColl.sub(_totalCollBeforeAdded)) + ',_aliceColl=' + _aliceColl + ',_bobColl=' + _bobColl + ',_expectedFee=' + _expectedFee + ',_feeBalDelta=' + _actualFee + ',diffFee=' + (_actualFee.sub(_expectedFee))); 
          th.assertIsApproximatelyEqual(_actualFee, _expectedFeeShare, _errorTolerance);
	  
          // get collateral after applying accumulated split fee
          let _aliceCollAfter = (await cdpManager.getEntireDebtAndColl(_aliceCdpId))[1]; 
          let _bobCollAfter = (await cdpManager.getEntireDebtAndColl(_bobCdpId))[1];
	  
          let _stFeePerUnitg = await cdpManager.stFeePerUnitg();
          _stFeePerUnitgError = await cdpManager.stFeePerUnitgError();
          let _totalStakeAfter = await cdpManager.totalStakes();
          let _aliceExpectedFeeApplied = await cdpManager.getAccumulatedFeeSplitApplied(_aliceCdpId, _stFeePerUnitg, _stFeePerUnitgError, _totalStakeAfter);
          let _bobExpectedFeeApplied = await cdpManager.getAccumulatedFeeSplitApplied(_bobCdpId, _stFeePerUnitg, _stFeePerUnitgError, _totalStakeAfter);
	     
          let _totalCollAfter = await cdpManager.getEntireSystemColl();  	 
	  
          th.assertIsApproximatelyEqual(_aliceCollAfter, _aliceExpectedFeeApplied[1], _errorTolerance);
          th.assertIsApproximatelyEqual(_bobCollAfter, _bobExpectedFeeApplied[1], _errorTolerance);
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
          await borrowerOperations.withdrawEBTC(_aliceCdpId, 1, _aliceCdpId, _aliceCdpId, { from: alice, value: 0 })
          await borrowerOperations.withdrawEBTC(_bobCdpId, 1, _bobCdpId, _bobCdpId, { from: bob, value: 0 })	  
	  	  
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
	  
      let _aliceColl = await cdpManager.getCdpColl(_aliceCdpId);
      let _bobColl = await cdpManager.getCdpColl(_bobCdpId);
      assert.isTrue((await sortedCdps.getFirst()) == _bobCdpId);
	  
      // partially liquidate the CDP	  
      let _newPrice = dec(2800, 13);
      await priceFeed.setPrice(_newPrice);
      let _icrBefore = await cdpManager.getCurrentICR(_aliceCdpId, _newPrice);
      let _tcrBefore = await cdpManager.getTCR(_newPrice);	 
      assert.isTrue(toBN(_icrBefore.toString()).gt(LICR));
      assert.isTrue(toBN(_icrBefore.toString()).gt(_MCR));
      let _partialDebtRepaid = minDebt;
      let _expectedSeizedColl = toBN(_partialDebtRepaid.toString()).mul(_MCR).div(toBN(_newPrice));
      let _expectedLiquidatedColl = _expectedSeizedColl.mul(mv._1e18BN).div(_newIndex);
      let _collBeforeLiquidator = await collToken.balanceOf(owner);	
	  
      await cdpManager.partiallyLiquidate(_aliceCdpId, _partialDebtRepaid, _aliceCdpId, _aliceCdpId, {from: owner});
      let _collAfterLiquidator = await collToken.balanceOf(owner);	
      let _aliceCollAfterLiq = await cdpManager.getCdpColl(_aliceCdpId);  
      th.assertIsApproximatelyEqual(_collAfterLiquidator.sub(_collBeforeLiquidator), _expectedSeizedColl, _errorTolerance);
      th.assertIsApproximatelyEqual(_aliceColl.sub(_aliceCollAfterLiq), _expectedLiquidatedColl, _errorTolerance);
      _aliceColl = _aliceCollAfterLiq;
	  
      // sugardaddy some collateral staking reward by increasing its PPFS again
      _newIndex = _newIndex.add(_deltaIndex);
      await collToken.setEthPerShare(_newIndex);  
	  
      // redeem alice CDP
      // skip bootstrapping phase	  
      await ethers.provider.send("evm_increaseTime", [86400 * 15]);
      await ethers.provider.send("evm_mine");
	  
      let _redeemDebt = _partialDebtRepaid.mul(toBN("9"));
      let _expectedColl = toBN(_redeemDebt.toString()).mul(mv._1e18BN).div(toBN(_newPrice));
      let _expectedRedeemedColl = _expectedColl.mul(mv._1e18BN).div(_newIndex);
      let _expectedRedeemFloor = await cdpManager.redemptionFeeFloor();
      let _expectedBaseRate = await cdpManager.getUpdatedBaseRateFromRedemption(_expectedRedeemedColl, _newPrice);
      let _expectedCollAfterFee = _expectedRedeemedColl.sub(_expectedRedeemedColl.mul(_expectedRedeemFloor.add(_expectedBaseRate)).div(mv._1e18BN)).mul(_newIndex).div(mv._1e18BN);
      const {firstRedemptionHint, partialRedemptionHintNICR, truncatedEBTCamount, partialRedemptionNewColl} = await hintHelpers.getRedemptionHints(_redeemDebt, _newPrice, 0);
      let _collBeforeRedeemer = await collToken.balanceOf(owner); 
      await cdpManager.redeemCollateral(_redeemDebt, firstRedemptionHint, _aliceCdpId, _aliceCdpId, partialRedemptionHintNICR, 0, th._100pct, {from: owner});	  
      let _collAfterRedeemer = await collToken.balanceOf(owner);	
      let _aliceCollAfterRedeem = await cdpManager.getCdpColl(_aliceCdpId);  
      th.assertIsApproximatelyEqual(_collAfterRedeemer.sub(_collBeforeRedeemer), _expectedCollAfterFee, _errorTolerance);
      th.assertIsApproximatelyEqual(partialRedemptionNewColl.sub(_aliceCollAfterRedeem), _expectedRedeemedColl, _errorTolerance);
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
	  
      let _feeBalBefore = await activePool.getFeeRecipientClaimableColl();
      await cdpManager.claimStakingSplitFee();  
      let _feeBalAfter = await activePool.getFeeRecipientClaimableColl();
	  
      let _stFeePerUnitg = await cdpManager.stFeePerUnitg();
      let _stFeePerUnitgError = await cdpManager.stFeePerUnitgError();
      let _totalStake = await cdpManager.totalStakes();
      let _aliceExpectedFeeApplied = await cdpManager.getAccumulatedFeeSplitApplied(_aliceCdpId, _stFeePerUnitg, _stFeePerUnitgError, _totalStake);
      let _bobExpectedFeeApplied = await cdpManager.getAccumulatedFeeSplitApplied(_bobCdpId, _stFeePerUnitg, _stFeePerUnitgError, _totalStake);
	  
      th.assertIsApproximatelyEqual(_feeBalAfter.sub(_feeBalBefore), _expectedFeeShare, _errorTolerance);
	  
      // check after accumulated fee split applied to CDPs
      let _aliceCollAfter = (await cdpManager.getEntireDebtAndColl(_aliceCdpId))[1];
      th.assertIsApproximatelyEqual(_aliceCollAfter, _aliceExpectedFeeApplied[1], _errorTolerance);
      let _bobCollDebtAfter = await cdpManager.getEntireDebtAndColl(_bobCdpId);
      th.assertIsApproximatelyEqual(_bobCollDebtAfter[1], _bobExpectedFeeApplied[1], _errorTolerance);
	  
      // fully liquidate the riskiest CDP with fee split applied	  
      _newPrice = dec(1520, 13);
      await priceFeed.setPrice(_newPrice);
      let _icrBobAfter = await cdpManager.getCurrentICR(_bobCdpId, _newPrice);
      assert.isTrue(toBN(_icrBobAfter.toString()).gt(LICR));
      let _expectedLiquidatedCollBob = (_bobCollDebtAfter[0].mul(_icrBobAfter).div(toBN(_newPrice))).mul(mv._1e18BN).div(_newIndex);
      await cdpManager.liquidate(_bobCdpId, {from: owner});
      let _surplusToClaimBob = await collSurplusPool.getCollateral(bob);
      th.assertIsApproximatelyEqual(_surplusToClaimBob, _bobCollDebtAfter[1].sub(_expectedLiquidatedCollBob), _errorTolerance);
  })
  
  it("SetStakingRewardSplit() should only allow authorized caller", async() => {	  
      await assertRevert(cdpManager.setStakingRewardSplit(1, {from: alice}), "Auth: UNAUTHORIZED");   
      await assertRevert(cdpManager.setStakingRewardSplit(10001, {from: owner}), "CDPManager: new staking reward split exceeds max");
      assert.isTrue(2500 == (await cdpManager.stakingRewardSplit())); 
	  	  
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
	  
      // switch authority    
      let _setAuthSig = "0x7a9e5e4b";//bytes4(keccak256(bytes("setAuthority(address)")))
      await authority.setRoleCapability(_role123, cdpManager.address, _setAuthSig, true, {from: accounts[0]});
      assert.isTrue((await authority.canCall(alice, cdpManager.address, _setAuthSig)));
      let _newAuthority = await GovernorTester.new(alice);
      await cdpManager.setAuthority(_newAuthority.address, {from: alice});
      assert.isTrue(_newAuthority.address == (await cdpManager.authority()));
      _newSplitFee = 10000;
      await _newAuthority.setRoleCapability(_role123, cdpManager.address, _splitRewardSig, true, {from: alice});	  
      await _newAuthority.setUserRole(alice, _role123, true, {from: alice});
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
      let _cdpDebtColl = await cdpManager.getEntireDebtAndColl(_cdpId);
      let _activeColl = await activePool.getStEthColl();
      let _systemDebt = await cdpManager.getEntireSystemDebt();
      th.assertIsApproximatelyEqual(_activeColl, _cdpDebtColl[1], _errorTolerance.toNumber());
      th.assertIsApproximatelyEqual(_systemDebt, _cdpDebtColl[0], _errorTolerance.toNumber());
	  
      // rewarding: increaseCollateralRate(6)	  	  
      await ethers.provider.send("evm_increaseTime", [44823]);
      await ethers.provider.send("evm_mine");  
      _newIndex = 6;
      await collToken.setEthPerShare(_newIndex);  
	  
      // claim fee
      await cdpManager.claimStakingSplitFee();
	  
      // final check
      _cdpDebtColl = await cdpManager.getEntireDebtAndColl(_cdpId);
      _systemDebt = await cdpManager.getEntireSystemDebt();
      th.assertIsApproximatelyEqual(_systemDebt, _cdpDebtColl[0], _errorTolerance.toNumber());
	  
      _cdpColl = _cdpDebtColl[1];
      _activeColl = await activePool.getStEthColl();
      let _diff = _cdpColl.gt(_activeColl)? _cdpColl.sub(_activeColl).mul(mv._1e18BN) : _activeColl.sub(_cdpColl).mul(mv._1e18BN);
      let _divisor = _cdpColl.gt(_activeColl)? _cdpColl : _activeColl;
      let _target = _errorTolerance.mul(_divisor);
      assert.isTrue(_diff.lt(_target));  
  })
  
  
})