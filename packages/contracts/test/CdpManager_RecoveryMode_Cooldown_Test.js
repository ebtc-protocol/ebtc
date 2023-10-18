const deploymentHelper = require("../utils/deploymentHelpers.js")
const { TestHelper: th, MoneyValues: mv } = require("../utils/testHelpers.js")
const { toBN, dec, ZERO_ADDRESS } = th

const CdpManagerTester = artifacts.require("./CdpManagerTester")
const EBTCToken = artifacts.require("./EBTCToken.sol")
const GovernorTester = artifacts.require("./GovernorTester.sol");

const assertRevert = th.assertRevert

contract('CdpManager - Cooldown switch with respect to Recovery Mode to ensure delay on all external liquidations (exclusively for CDPs that can be liquidated in RM)', async accounts => {
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
  let _coolDownWait;
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
    _coolDownWait = await cdpManager.recoveryModeGracePeriodDuration();
    borrowerOperations = contracts.borrowerOperations;
    collSurplusPool = contracts.collSurplusPool;
    collToken = contracts.collateral;
    hintHelpers = contracts.hintHelpers;
    authority = contracts.authority;

    await deploymentHelper.connectCoreContracts(contracts, LQTYContracts)
	
    splitFeeRecipient = await LQTYContracts.feeRecipient;
  })  
  
  it("Happy case: 3 CDPs with 1st Safe and 2 other Unsafe and ensure you must wait cooldown for one of them", async() => {      	  
      
      await openCdp({ ICR: toBN(dec(149, 16)), extraEBTCAmount: toBN(minDebt.toString()).mul(toBN("10")), extraParams: { from: alice } })
      await openCdp({ ICR: toBN(dec(139, 16)), extraParams: { from: bob } }) 
      await openCdp({ ICR: toBN(dec(129, 16)), extraParams: { from: carol } }) 
	  
      let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
      let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
      let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
      await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from : alice});
      await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});
      await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});
	  
      // price drops to trigger RM	  
      let _newPrice = dec(6000, 13);
      await priceFeed.setPrice(_newPrice);
      let _aliceICRBefore = await cdpManager.getCachedICR(_aliceCdpId, _newPrice);
      let _bobICRBefore = await cdpManager.getCachedICR(_bobCdpId, _newPrice);
      let _carolICRBefore = await cdpManager.getCachedICR(_carolCdpId, _newPrice);
      let _tcrBefore = await cdpManager.getCachedTCR(_newPrice);
      console.log('_aliceICRBefore=' + _aliceICRBefore + ', _bobICRBefore=' + _bobICRBefore + ', _carolICRBefore=' + _carolICRBefore + ', _tcrBefore=' + _tcrBefore);
      assert.isTrue(toBN(_tcrBefore.toString()).lt(_CCR));
      assert.isTrue(toBN(_aliceICRBefore.toString()).gt(_tcrBefore));
      assert.isTrue(toBN(_bobICRBefore.toString()).lt(_tcrBefore));
      assert.isTrue(toBN(_bobICRBefore.toString()).gt(_MCR));
      assert.isTrue(toBN(_carolICRBefore.toString()).lt(_MCR));
	  	  
      // trigger RM cooldown
      await cdpManager.syncGlobalAccountingAndGracePeriod();	 
      await assertRevert(cdpManager.liquidate(_bobCdpId, {from: owner}), "Grace period yet to finish");
	  
      // cooldown only apply those [> MCR & < TCR]
      await cdpManager.liquidate(_carolCdpId, {from: owner});
      assert.isFalse((await sortedCdps.contains(_carolCdpId)));
	 
      // pass the cooldown wait 
      await ethers.provider.send("evm_increaseTime", [_coolDownWait.toNumber() + 1]);
      await ethers.provider.send("evm_mine");
      await cdpManager.liquidate(_bobCdpId, {from: owner});
      assert.isFalse((await sortedCdps.contains(_bobCdpId)));
  })
  
  it("openCDP() in RM: should notifyStartGracePeriod() if RM persist or notifyEndGracePeriod() if RM exit", async() => {      	  
      
      await openCdp({ ICR: toBN(dec(149, 16)), extraEBTCAmount: toBN(minDebt.toString()).mul(toBN("10")), extraParams: { from: alice } })
      let _initVal = await cdpManager.lastGracePeriodStartTimestamp();
      assert.isTrue(_initVal.gt(toBN('0')));
      await openCdp({ ICR: toBN(dec(129, 16)), extraParams: { from: carol } }) 
	  
      // price drops to trigger RM	  
      let _newPrice = dec(6000, 13);
      await priceFeed.setPrice(_newPrice);
      let _tcrBefore = await cdpManager.getCachedTCR(_newPrice);
      assert.isTrue(toBN(_tcrBefore.toString()).lt(_CCR));
      let _stillInitVal = await cdpManager.lastGracePeriodStartTimestamp();
      assert.isTrue(_stillInitVal.eq(_initVal));
	  	  
      // trigger RM cooldown by open a new CDP
      await openCdp({ ICR: _CCR.add(toBN('1234567890123456789')), extraParams: { from: bob } }) 
      let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
      let _bobICRBefore = await cdpManager.getCachedICR(_bobCdpId, _newPrice);
      let _tcrInMiddle = await cdpManager.getCachedTCR(_newPrice);
      console.log('_tcrInMiddle=' + _tcrInMiddle);
      assert.isTrue(toBN(_tcrInMiddle.toString()).lt(_CCR));
      let _rmTriggerTimestamp = await cdpManager.lastGracePeriodStartTimestamp();
      assert.isTrue(_rmTriggerTimestamp.gt(toBN('0')));
      assert.isTrue(_rmTriggerTimestamp.lt(_initVal));
	  	  
      // trigger RM exit by open another new CDP
      await openCdp({ ICR: toBN(dec(349, 16)), extraEBTCAmount: toBN(minDebt.toString()).mul(toBN("100")), extraParams: { from: owner } }) 
      let _tcrFinal = await cdpManager.getCachedTCR(_newPrice);
      console.log('_tcrFinal=' + _tcrFinal);
      assert.isTrue(toBN(_tcrFinal.toString()).gt(_CCR));
      let _rmExitTimestamp = await cdpManager.lastGracePeriodStartTimestamp();
      assert.isTrue(_rmExitTimestamp.eq(_initVal));
  })
  
  it("closeCDP(): should always notifyEndGracePeriod() since TCR after close is aboce CCR", async() => {      	  
      
      await openCdp({ ICR: toBN(dec(155, 16)), extraEBTCAmount: toBN(minDebt.toString()).mul(toBN("10")), extraParams: { from: alice } })
      let _initVal = await cdpManager.lastGracePeriodStartTimestamp();
      assert.isTrue(_initVal.gt(toBN('0')));
      await openCdp({ ICR: toBN(dec(126, 16)), extraParams: { from: carol } })
	  
      let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
      let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
	  
      // price drops to trigger RM & cooldown
      let _originalPrice = await priceFeed.getPrice();
      let _newPrice = dec(5992, 13);
      await priceFeed.setPrice(_newPrice);
      let _tcrBefore = await cdpManager.getCachedTCR(_newPrice);
      let _aliceICRBefore = await cdpManager.getCachedICR(_aliceCdpId, _newPrice);
      console.log('_tcrBefore=' + _tcrBefore + ',_aliceICRBefore=' + _aliceICRBefore);
      assert.isTrue(toBN(_tcrBefore.toString()).lt(_CCR));
      await cdpManager.syncGlobalAccountingAndGracePeriod();
      let _rmTriggerTimestamp = await cdpManager.lastGracePeriodStartTimestamp();
      assert.isTrue(_rmTriggerTimestamp.gt(toBN('0')));
      assert.isTrue(_rmTriggerTimestamp.lt(_initVal));
	  	  
      // reset RM cooldown by close a CDP
      await priceFeed.setPrice(_originalPrice);
      await borrowerOperations.closeCdp(_carolCdpId, { from: carol } ); 
      assert.isFalse((await sortedCdps.contains(_carolCdpId)));
      let _tcrAfter = await cdpManager.getCachedTCR(_originalPrice);
      assert.isTrue(toBN(_tcrAfter.toString()).gt(_CCR));
      let _rmExitTimestamp = await cdpManager.lastGracePeriodStartTimestamp();
      assert.isTrue(_rmExitTimestamp.eq(_initVal));
  })
  
  it("adjustCDP(): should notifyStartGracePeriod() if RM persist or notifyEndGracePeriod() if RM exit", async() => {      	  
      let _dustVal = 123456789;
      await openCdp({ ICR: toBN(dec(155, 16)), extraEBTCAmount: toBN(minDebt.toString()).mul(toBN("10")), extraParams: { from: alice } })
      let _initVal = await cdpManager.lastGracePeriodStartTimestamp();
      assert.isTrue(_initVal.gt(toBN('0')));
      await openCdp({ ICR: toBN(dec(126, 16)), extraParams: { from: carol } })
	  
      let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
      let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
      let _carolDebt = await cdpManager.getCdpDebt(_carolCdpId);
	  
      // price drops to trigger RM & cooldown
      let _originalPrice = await priceFeed.getPrice();
      let _newPrice = dec(5992, 13);
      await priceFeed.setPrice(_newPrice);
      let _tcrBefore = await cdpManager.getCachedTCR(_newPrice);
      let _aliceICRBefore = await cdpManager.getCachedICR(_aliceCdpId, _newPrice);
      assert.isTrue(toBN(_tcrBefore.toString()).lt(_CCR));
      await cdpManager.syncGracePeriod();
      let _rmTriggerTimestamp = await cdpManager.lastGracePeriodStartTimestamp();
      assert.isTrue(_rmTriggerTimestamp.gt(toBN('0')));
      assert.isTrue(_rmTriggerTimestamp.lt(_initVal));
	  	  
      // reset RM cooldown by adjust a CDP in Normal Mode (withdraw more debt)
      await priceFeed.setPrice(_originalPrice);
      let _tcrAfter = await cdpManager.getCachedTCR(_originalPrice);
      assert.isTrue(toBN(_tcrAfter.toString()).gt(_CCR));	  
      await borrowerOperations.withdrawDebt(_carolCdpId, _dustVal, _carolCdpId, _carolCdpId, { from: carol } ); 
      let _rmExitTimestamp = await cdpManager.lastGracePeriodStartTimestamp();
      assert.isTrue(_rmExitTimestamp.eq(_initVal));
	  
      // price drops to trigger RM & cooldown again by adjust CDP (add more collateral)
      await priceFeed.setPrice(_newPrice);	  
      await collToken.deposit({from : carol, value: _dustVal}); 
      await borrowerOperations.addColl(_carolCdpId, _carolCdpId, _carolCdpId, _dustVal, { from: carol } );
      let _adjustRmTriggerTimestamp = await cdpManager.lastGracePeriodStartTimestamp();
      assert.isTrue(_adjustRmTriggerTimestamp.gt(_rmTriggerTimestamp));
      assert.isTrue(_adjustRmTriggerTimestamp.lt(_initVal));
	  
      // end RM cooldown by adjust a CDP in RM (repayment)
      await debtToken.approve(borrowerOperations.address, _carolDebt, {from: carol});	  
      await borrowerOperations.repayDebt(_carolCdpId, _carolDebt, _carolCdpId, _carolCdpId, { from: carol } );
      let _tcrFinal = await cdpManager.getCachedTCR(_newPrice);
      assert.isTrue(toBN(_tcrFinal.toString()).gt(_CCR));
      let _rmExitFinal = await cdpManager.lastGracePeriodStartTimestamp();
      assert.isTrue(_rmExitFinal.eq(_initVal));
	  
  })
  
  
})