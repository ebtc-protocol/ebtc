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
    minDebt = await contracts.borrowerOperations.MIN_NET_COLL();
    _MCR = await cdpManager.MCR();
    _CCR = await cdpManager.CCR();
    LICR = await cdpManager.LICR();
    _coolDownWait = await cdpManager.waitTimeFromRMTriggerToLiquidations();
    borrowerOperations = contracts.borrowerOperations;
    collSurplusPool = contracts.collSurplusPool;
    collToken = contracts.collateral;
    hintHelpers = contracts.hintHelpers;
    authority = contracts.authority;

    await deploymentHelper.connectCoreContracts(contracts, LQTYContracts)
	
    splitFeeRecipient = await LQTYContracts.feeRecipient;
  })  
  
  it("Happy case: 2 CDPs with 1st Safe and 2nd Unsafe and ensure you must wait cooldown", async() => {      	  
      
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
      let _aliceICRBefore = await cdpManager.getCurrentICR(_aliceCdpId, _newPrice);
      let _bobICRBefore = await cdpManager.getCurrentICR(_bobCdpId, _newPrice);
      let _carolICRBefore = await cdpManager.getCurrentICR(_carolCdpId, _newPrice);
      let _tcrBefore = await cdpManager.getTCR(_newPrice);
      console.log('_aliceICRBefore=' + _aliceICRBefore + ', _bobICRBefore=' + _bobICRBefore + ', _carolICRBefore=' + _carolICRBefore + ', _tcrBefore=' + _tcrBefore);
      assert.isTrue(toBN(_tcrBefore.toString()).lt(_CCR));
      assert.isTrue(toBN(_aliceICRBefore.toString()).gt(_tcrBefore));
      assert.isTrue(toBN(_bobICRBefore.toString()).lt(_tcrBefore));
      assert.isTrue(toBN(_bobICRBefore.toString()).gt(_MCR));
      assert.isTrue(toBN(_carolICRBefore.toString()).lt(_MCR));
	  	  
      // trigger RM cooldown
      await cdpManager.checkLiquidateCoolDownAndReset();	 
      await assertRevert(cdpManager.liquidate(_bobCdpId, {from: owner}), "Grace period yet to finish");
	  
      // cooldown only apply those [> MCR & < TCR]
      await cdpManager.liquidate(_carolCdpId, {from: owner});
      assert.isFalse((await sortedCdps.contains(_carolCdpId)));
	 
      // pass the cooldown wait 
      await ethers.provider.send("evm_increaseTime", [901]);
      await ethers.provider.send("evm_mine");
      await cdpManager.liquidate(_bobCdpId, {from: owner});
      assert.isFalse((await sortedCdps.contains(_bobCdpId)));
  })
  
  
})