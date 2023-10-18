const deploymentHelper = require("../utils/deploymentHelpers.js")
const { TestHelper: th, MoneyValues: mv } = require("../utils/testHelpers.js")
const { toBN, dec, ZERO_ADDRESS } = th

const CdpManagerTester = artifacts.require("./CdpManagerTester")
const EBTCToken = artifacts.require("./EBTCTokenTester.sol")
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
  let _CCR;
  let collToken;

  const openCdp = async (params) => th.openCdp(contracts, params)

  beforeEach(async () => {
    await deploymentHelper.setDeployGasPrice(1000000000);
    contracts = await deploymentHelper.deployTesterContractsHardhat()
    let LQTYContracts = {}
    LQTYContracts.feeRecipient = contracts.feeRecipient;

    cdpManager = contracts.cdpManager
    priceFeed = contracts.priceFeedTestnet
    sortedCdps = contracts.sortedCdps
    debtToken = contracts.ebtcToken;
    activePool = contracts.activePool;
    defaultPool = contracts.defaultPool;
    minDebt = await contracts.borrowerOperations.MIN_NET_STETH_BALANCE();
    liqReward = await contracts.cdpManager.LIQUIDATOR_REWARD();	
    _MCR = await cdpManager.MCR();
    LICR = await cdpManager.LICR();
    _CCR = await cdpManager.CCR();
    borrowerOperations = contracts.borrowerOperations;
    collSurplusPool = contracts.collSurplusPool;
    collToken = contracts.collateral;
    liqStipend = await cdpManager.LIQUIDATOR_REWARD()
    liquidationSequencer = contracts.liquidationSequencer;

    await deploymentHelper.connectCoreContracts(contracts, LQTYContracts)
  })
  
  it("CDP needs to be active to be liquidated", async() => {	  
      await assertRevert(cdpManager.liquidate(th.DUMMY_BYTES32, {from: bob}), "CdpManager: Cdp does not exist or is closed");  
      await assertRevert(cdpManager.partiallyLiquidate(th.DUMMY_BYTES32, 123, th.DUMMY_BYTES32, th.DUMMY_BYTES32, {from: bob}), "CdpManager: Cdp does not exist or is closed");
  })
  
  it("ICR needs to be either below MCR in normal mode or below TCR in recovery mode for being liquidatable", async() => {
      await openCdp({ ICR: toBN(dec(299, 16)), extraParams: { from: alice } })
      let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);	  
      await openCdp({ ICR: toBN(dec(199, 16)), extraParams: { from: bob } })
      let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);	  
	  
      // normal mode	  
      let _aliceICR = await cdpManager.getCachedICR(_aliceCdpId, (await priceFeed.getPrice()));
      assert.isTrue(_aliceICR.gt(_MCR));
      await assertRevert(cdpManager.liquidate(_aliceCdpId, {from: bob}), "CdpManager: ICR is not below liquidation threshold in current mode");
      await assertRevert(cdpManager.partiallyLiquidate(_aliceCdpId, 123, _aliceCdpId, _aliceCdpId, {from: bob}), "CdpManager: ICR is not below liquidation threshold in current mode");  
	  
      // recovery mode	  
      let _newPrice = dec(2400, 13);
      await priceFeed.setPrice(_newPrice);
      assert.isTrue((await cdpManager.checkRecoveryMode(_newPrice)));
      await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: alice});
      await contracts.collateral.deposit({from: alice, value: dec(100, 'ether')});
      await borrowerOperations.addColl(_aliceCdpId, _aliceCdpId, _aliceCdpId, dec(100, 'ether'), { from: alice, value: 0 })
      _aliceICR = await cdpManager.getCachedICR(_aliceCdpId, _newPrice);
      let _TCR = await cdpManager.getCachedTCR(_newPrice);
      assert.isTrue(_aliceICR.gt(_TCR));
      await assertRevert(cdpManager.liquidate(_aliceCdpId, {from: bob}), "CdpManager: ICR is not below liquidation threshold in current mode");
      await assertRevert(cdpManager.partiallyLiquidate(_aliceCdpId, 123, _aliceCdpId, _aliceCdpId, {from: bob}), "CdpManager: ICR is not below liquidation threshold in current mode");	  
  })
  
  it("Liquidator should prepare enough asset for repayment", async () => {
      let {tx: opAliceTx} = await openCdp({ ICR: toBN(dec(299, 16)), extraEBTCAmount: toBN(minDebt.toString()).add(toBN(1)), extraParams: { from: alice } })
      await openCdp({ ICR: toBN(dec(199, 16)), extraParams: { from: bob } })
      let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
      assert.isTrue(await sortedCdps.contains(_aliceCdpId));
	  
      // price slump
      let _newPrice = dec(2400, 13);
      await priceFeed.setPrice(_newPrice);
	  
      // liquidator bob coming in but failed to liquidate due to insufficient debt
      await assertRevert(cdpManager.liquidate(_aliceCdpId, {from: bob}), "ERC20: burn amount exceeds balance");
      assert.isTrue(await sortedCdps.contains(_aliceCdpId));
  })
  
  it("Liquidation should spare the last CDP", async () => {
      await openCdp({ ICR: toBN(dec(299, 16)), extraParams: { from: alice } })
      let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);	  
      // price slump
      let _newPrice = dec(2400, 13);
      await priceFeed.setPrice(_newPrice);
      await assertRevert(cdpManager.liquidate(_aliceCdpId, {from: alice}), "CdpManager: Only one cdp in the system");
  })
  
  it("CDPs below MCR will be liquidated", async () => {
      let {tx: opAliceTx} = await openCdp({ ICR: toBN(dec(299, 16)), extraParams: { from: alice } })
      await openCdp({ ICR: toBN(dec(299, 16)), extraParams: { from: bob } })
      let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
      assert.isTrue(await sortedCdps.contains(_aliceCdpId));
      let _debtBorrowed = await cdpManager.getCdpDebt(_aliceCdpId);
      let _colDeposited = await cdpManager.getCdpCollShares(_aliceCdpId);
	  
      // price slump
      let _newPrice = dec(2400, 13);
      await priceFeed.setPrice(_newPrice);
	  
      // liquidator bob coming in 
      await debtToken.transfer(bob, (await debtToken.balanceOf(alice)), {from: alice});	  
      let _debtLiquidatorPre = await debtToken.balanceOf(bob);  
      let _debtSystemPre = await cdpManager.getSystemDebt();
      let _colSystemPre = await cdpManager.getSystemCollShares();
      let _ethLiquidatorPre = await web3.eth.getBalance(bob);
      let _collLiquidatorPre = await collToken.balanceOf(bob);	 	  
      let _debtInActivePoolPre = await activePool.getSystemDebt();
      let _collInActivePoolPre = await activePool.getSystemCollShares();
	  
      let _expectedDebtRepaid = _colDeposited.mul(toBN(_newPrice)).div(LICR);
	  
      const tx = await cdpManager.liquidate(_aliceCdpId, {from: bob})	  
      let _debtLiquidatorPost = await debtToken.balanceOf(bob);
      let _debtSystemPost = await cdpManager.getSystemDebt();
      let _colSystemPost = await cdpManager.getSystemCollShares();
      let _ethLiquidatorPost = await web3.eth.getBalance(bob);
      let _collLiquidatorPost = await collToken.balanceOf(bob);	  
      let _debtInActivePoolPost = await activePool.getSystemDebt();
      let _collInActivePoolPost = await activePool.getSystemCollShares();

      // check CdpLiquidated event
      const liquidationEvents = th.getAllEventsByName(tx, 'CdpLiquidated')
      assert.equal(liquidationEvents.length, 1, '!CdpLiquidated event')
      assert.equal(liquidationEvents[0].args[0], _aliceCdpId, '!liquidated CDP ID');
      assert.equal(liquidationEvents[0].args[1], alice, '!liquidated CDP owner');
      assert.equal(liquidationEvents[0].args[2].toString(), _expectedDebtRepaid.toString(), '!liquidated CDP debt');
      assert.equal(liquidationEvents[0].args[3].toString(), _colDeposited.toString(), '!liquidated CDP collateral');
	  
      // check liquidator balance change
      let _gasUsed = th.gasUsed(tx);
      let _debtDecreased = toBN(_debtLiquidatorPre.toString()).sub(toBN(_debtLiquidatorPost.toString()));
      th.assertIsApproximatelyEqual(_debtDecreased.toString(), _expectedDebtRepaid.toString());		  
      const gasUsedETH = toBN(tx.receipt.effectiveGasPrice.toString()).mul(toBN(_gasUsed.toString()));
      let _ethSeizedByLiquidator = toBN(_collLiquidatorPost.toString()).sub(toBN(_collLiquidatorPre.toString()));//.add(gasUsedETH);
      assert.equal(_ethSeizedByLiquidator.toString(), _colDeposited.add(liqReward).toString(), '!liquidator collateral balance');	
      assert.equal(liquidationEvents[0].args[5], bob, '!liquidator');	  
      let _debtToColl = _expectedDebtRepaid.mul(mv._1e18BN).div(toBN(_newPrice));
      assert.equal(liquidationEvents[0].args[6].toString(), _ethSeizedByLiquidator.sub(_debtToColl).toString(), '!liquidator premium'); 
	  
      // check system balance change
      let _debtDecreasedSystem = toBN(_debtSystemPre.toString()).sub(toBN(_debtSystemPost.toString()));
      assert.equal(_debtDecreasedSystem.toString(), _expectedDebtRepaid.toString(), '!system debt balance');	
      let _colDecreasedSystem = toBN(_colSystemPre.toString()).sub(toBN(_colSystemPost.toString())); 
      assert.equal(_colDecreasedSystem.toString(), _colDeposited.toString(), '!system collateral balance');	
      let _debtDecreasedActivePool = toBN(_debtInActivePoolPre.toString()).sub(toBN(_debtInActivePoolPost.toString())); 
      assert.equal(_debtDecreasedActivePool.toString(), _expectedDebtRepaid.toString(), '!activePool debt balance');
      let _colDecreasedActivePool = toBN(_collInActivePoolPre.toString()).sub(toBN(_collInActivePoolPost.toString())); 
      assert.equal(_colDecreasedActivePool.toString(), _colDeposited.toString(), '!activePool collateral balance');

      // Confirm target CDPs removed
      assert.isFalse(await sortedCdps.contains(_aliceCdpId))

      // Confirm removed CDP have status 'closed by liquidation' (Status enum element idx 3)
      assert.equal((await cdpManager.Cdps(_aliceCdpId))[4], '3')
  })
  
  it("Should allow non-EOA liquidator", async () => {
      let {tx: opAliceTx} = await openCdp({ ICR: toBN(dec(299, 16)), extraParams: { from: alice } })
      await openCdp({ ICR: toBN(dec(299, 16)), extraParams: { from: bob } })
      let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
      assert.isTrue(await sortedCdps.contains(_aliceCdpId));
      let _debtBorrowed = await cdpManager.getCdpDebt(_aliceCdpId);
      let _colDeposited = await cdpManager.getCdpCollShares(_aliceCdpId);
	  
      // price slump
      let _newPrice = dec(2400, 13);
      await priceFeed.setPrice(_newPrice);
	  
      // non-EOA liquidator coming in	
      const simpleLiquidationTester = await SimpleLiquidationTester.new();
      await simpleLiquidationTester.setCdpManager(cdpManager.address);
	
      await debtToken.transfer(simpleLiquidationTester.address, (await debtToken.balanceOf(alice)), {from: alice});	  
      await debtToken.transfer(simpleLiquidationTester.address, (await debtToken.balanceOf(bob)), {from: bob});	 
      let _debtLiquidatorPre = await debtToken.balanceOf(simpleLiquidationTester.address);  
      let _debtSystemPre = await cdpManager.getSystemDebt();
      let _colSystemPre = await cdpManager.getSystemCollShares();
      let _ethLiquidatorPre = await web3.eth.getBalance(simpleLiquidationTester.address);
      let _collLiquidatorPre = await collToken.balanceOf(simpleLiquidationTester.address); 	  
      let _debtInActivePoolPre = await activePool.getSystemDebt();
      let _collInActivePoolPre = await activePool.getSystemCollShares();
	  
      let _expectedDebtRepaid = _colDeposited.mul(toBN(_newPrice)).div(LICR);
	  
      const tx = await simpleLiquidationTester.liquidateCdp(_aliceCdpId, {from: owner});	  
      let _debtLiquidatorPost = await debtToken.balanceOf(simpleLiquidationTester.address);
      let _debtSystemPost = await cdpManager.getSystemDebt();
      let _colSystemPost = await cdpManager.getSystemCollShares();
      let _ethLiquidatorPost = await web3.eth.getBalance(simpleLiquidationTester.address);	
      let _collLiquidatorPost = await collToken.balanceOf(simpleLiquidationTester.address);  
      let _debtInActivePoolPost = await activePool.getSystemDebt();
      let _collInActivePoolPost = await activePool.getSystemCollShares();
	  
      // check EtherReceived event
//      const seizedEtherEvents = th.getAllEventsByName(tx, 'EtherReceived')
//      assert.equal(seizedEtherEvents.length, 1, '!EtherReceived event')
//      assert.equal(seizedEtherEvents[0].args[0], (await cdpManager.activePool()), '!Ether from Active Pool');
//      assert.equal(seizedEtherEvents[0].args[1].toString(), _colDeposited.toString(), '!liquidated CDP collateral');
	  
      // check liquidator balance change
      let _debtDecreased = toBN(_debtLiquidatorPre.toString()).sub(toBN(_debtLiquidatorPost.toString()));
      th.assertIsApproximatelyEqual(_debtDecreased.toString(), _expectedDebtRepaid.toString());		
      let _ethSeizedByLiquidator = toBN(_collLiquidatorPost.toString()).sub(toBN(_collLiquidatorPre.toString()));
      assert.equal(_ethSeizedByLiquidator.toString(), _colDeposited.add(liqReward).toString(), '!liquidator collateral balance');	 
	  
      // check system balance change
      let _debtDecreasedSystem = toBN(_debtSystemPre.toString()).sub(toBN(_debtSystemPost.toString()));
      assert.equal(_debtDecreasedSystem.toString(), _expectedDebtRepaid.toString(), '!system debt balance');	
      let _colDecreasedSystem = toBN(_colSystemPre.toString()).sub(toBN(_colSystemPost.toString())); 
      assert.equal(_colDecreasedSystem.toString(), _colDeposited.toString(), '!system collateral balance');	
      let _debtDecreasedActivePool = toBN(_debtInActivePoolPre.toString()).sub(toBN(_debtInActivePoolPost.toString())); 
      assert.equal(_debtDecreasedActivePool.toString(), _expectedDebtRepaid.toString(), '!activePool debt balance');
      let _colDecreasedActivePool = toBN(_collInActivePoolPre.toString()).sub(toBN(_collInActivePoolPost.toString())); 
      assert.equal(_colDecreasedActivePool.toString(), _colDeposited.toString(), '!activePool collateral balance');

      // Confirm target CDPs removed
      assert.isFalse(await sortedCdps.contains(_aliceCdpId))

      // Confirm removed CDP have status 'closed by liquidation' (Status enum element idx 3)
      assert.equal((await cdpManager.Cdps(_aliceCdpId))[4], '3')
  })  
  
  // with collateral token, there is no hook for liquidator to use 
  xit("Should allow non-EOA liquidator to reenter liquidate(bytes32) if everything adds-up", async () => {
      let {tx: opAliceTx} = await openCdp({ ICR: toBN(dec(299, 16)), extraParams: { from: alice } })
      await openCdp({ ICR: toBN(dec(299, 16)), extraParams: { from: bob } })
      let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
      let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
      assert.isTrue(await sortedCdps.contains(_aliceCdpId));
      assert.isTrue(await sortedCdps.contains(_bobCdpId));
      let _aliceColl = await cdpManager.getCdpCollShares(_aliceCdpId);
      let _bobColl = await cdpManager.getCdpCollShares(_bobCdpId);	  
      await openCdp({ ICR: toBN(dec(299, 16)), extraParams: { from: owner } }) 
	  
      // price slump
      let _newPrice = dec(2400, 13);
      await priceFeed.setPrice(_newPrice);
	  
      // non-EOA liquidator coming in	
      const simpleLiquidationTester = await SimpleLiquidationTester.new();
      await simpleLiquidationTester.setCdpManager(cdpManager.address);
      await simpleLiquidationTester.setReceiveType(1);//tell liquidator to try reentering liquidation
	
      await debtToken.transfer(simpleLiquidationTester.address, (await debtToken.balanceOf(alice)), {from: alice});	  
      await debtToken.transfer(simpleLiquidationTester.address, (await debtToken.balanceOf(bob)), {from: bob});	
      await debtToken.transfer(simpleLiquidationTester.address, (await debtToken.balanceOf(owner)), {from: owner});		 
	  
      // try to liquidate same cdp via reenter liquidate(), expect revert
      let _debtPre = await cdpManager.getCdpDebt(_aliceCdpId);
      await assertRevert(simpleLiquidationTester.liquidateCdp(_aliceCdpId, {from: owner}), "CdpManager: Cdp does not exist or is closed");
      assert.isTrue(await sortedCdps.contains(_aliceCdpId));
      let _debtPost = await cdpManager.getCdpDebt(_aliceCdpId);
      assert.equal(_debtPre.toString(), _debtPost.toString(), '!liquidation should revert');
	  
      // try to liquidate another cdp via reenter liquidate()
      await simpleLiquidationTester.setReEnterLiqCdpId(_bobCdpId);//tell liquidator to try reentering liquidation
      let _tx = await simpleLiquidationTester.liquidateCdp(_aliceCdpId, {from: owner});
      assert.isTrue(_tx.receipt.status);
      assert.isFalse(await sortedCdps.contains(_aliceCdpId));
      assert.isFalse(await sortedCdps.contains(_bobCdpId));
	  
      // check events on receive()
      const receiveEvents = th.getAllEventsByName(_tx, 'EtherReceived')
      assert.equal(receiveEvents.length, 2, '!EtherReceived event')
      assert.equal(receiveEvents[0].args[1].toString(), _aliceColl.toString(), '!Ether from alice CDP');
      assert.equal(receiveEvents[1].args[1].toString(), _bobColl.toString(), '!Ether from bob CDP');
  })
  
  // with collateral token, there is no hook for liquidator to use 
  xit("non-EOA liquidator might revert on Ether receive() to fail liquidation", async () => {
      let {tx: opAliceTx} = await openCdp({ ICR: toBN(dec(299, 16)), extraParams: { from: alice } })
      await openCdp({ ICR: toBN(dec(299, 16)), extraParams: { from: bob } })
      let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
      assert.isTrue(await sortedCdps.contains(_aliceCdpId));
	  
      // price slump
      let _newPrice = dec(2400, 13);
      await priceFeed.setPrice(_newPrice);
	  
      // non-EOA liquidator coming in	
      const simpleLiquidationTester = await SimpleLiquidationTester.new();
      await simpleLiquidationTester.setCdpManager(cdpManager.address);
      await simpleLiquidationTester.setReceiveType(2);//tell non-EOA liquidator to try reverting on receive()
	
      await debtToken.transfer(simpleLiquidationTester.address, (await debtToken.balanceOf(alice)), {from: alice});	  
      await debtToken.transfer(simpleLiquidationTester.address, (await debtToken.balanceOf(bob)), {from: bob});	
      let _debtPre = await cdpManager.getCdpDebt(_aliceCdpId);
      await assertRevert(simpleLiquidationTester.liquidateCdp(_aliceCdpId, {from: bob}), "ActivePool: sending ETH failed");
      assert.isTrue(await sortedCdps.contains(_aliceCdpId));
      let _debtPost = await cdpManager.getCdpDebt(_aliceCdpId);
      assert.equal(_debtPre.toString(), _debtPost.toString(), '!liquidation should revert');
  })
  
  it("liquidate(): liquidate a CDP in recovery mode", async () => {	
      await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: bob } });	  
      let bobCdpId = await sortedCdps.getFirst();
      assert.isTrue(await sortedCdps.contains(bobCdpId));	
      await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: carol } });	  
      let carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
      assert.isTrue(await sortedCdps.contains(carolCdpId));

      // mint Alice some EBTC
      await openCdp({ ICR: toBN(dec(160, 16)), extraParams: { from: alice } });	
      await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});	
      await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});  
      await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from: alice});	  
      let aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
      let aliceCdpOwner = await sortedCdps.getOwnerAddress(aliceCdpId);
      assert.isTrue(aliceCdpOwner == alice);

      // maniuplate price to liquidate alice
      let _newPrice = dec(800, 13);
      await priceFeed.setPrice(_newPrice);  
      assert.isTrue(await cdpManager.checkRecoveryMode(_newPrice));

      let aliceDebt = await cdpManager.getCdpDebt(aliceCdpId);
      let aliceColl = await cdpManager.getCdpCollShares(aliceCdpId);		  
      let prevDebtOfOwner = await debtToken.balanceOf(owner);
      assert.isTrue(toBN(prevDebtOfOwner.toString()).gt(toBN(aliceDebt.toString())));
	  
      // liquidate alice in recovery mode	  
      let prevETHOfOwner = await ethers.provider.getBalance(owner);
      let _collLiquidatorPre = await collToken.balanceOf(owner);
      let _TCR = await cdpManager.getCachedTCR(_newPrice);
      let _aliceICR = await cdpManager.getCachedICR(aliceCdpId, _newPrice);
      assert.isTrue(toBN(_aliceICR.toString()).lt(toBN(_TCR.toString())));
      assert.isTrue(toBN(_aliceICR.toString()).lt(toBN(_MCR.toString())));
      assert.isTrue(toBN(_aliceICR.toString()).lt(toBN(LICR.toString())));
	  
      let _expectedDebtRepaid = aliceColl.mul(toBN(_newPrice)).div(LICR);
	  
      let _liquidateRecoveryTx = await cdpManager.liquidate(aliceCdpId, { from: owner});	  
      let postDebtOfOwner = await debtToken.balanceOf(owner);
      let postETHOfOwner = await ethers.provider.getBalance(owner);
      let _collLiquidatorPost = await collToken.balanceOf(owner);
      assert.isFalse(await sortedCdps.contains(aliceCdpId));
      let _liquidatedEvents = th.getAllEventsByName(_liquidateRecoveryTx, 'CdpLiquidated');
      assert.equal(_liquidatedEvents.length, 1, '!CdpLiquidated event');
      assert.equal(_liquidatedEvents[0].args[0], aliceCdpId, '!liquidated CDP ID');
      assert.equal(_liquidatedEvents[0].args[1], alice, '!liquidated CDP owner');
      th.assertIsApproximatelyEqual(_liquidatedEvents[0].args[2].toString(), _expectedDebtRepaid.toString());
      assert.equal(_liquidatedEvents[0].args[3].toString(), aliceColl.toString(), '!liquidated CDP collateral');
      assert.equal(_liquidatedEvents[0].args[4].toString(), '5', '!liquidateInRecoveryMode');// alice was liquidated in recovery mode
      let _gasEtherUsed = toBN(_liquidateRecoveryTx.receipt.effectiveGasPrice.toString()).mul(toBN((th.gasUsed(_liquidateRecoveryTx)).toString()));
      let _ethSeizedByLiquidator = toBN(_collLiquidatorPost.toString()).sub(toBN(_collLiquidatorPre.toString()));

      // owner get collateral from alice by repaying the debts
      assert.equal(toBN(prevDebtOfOwner.toString()).sub(toBN(postDebtOfOwner.toString())).toString(), toBN(_expectedDebtRepaid.toString()).toString());
      assert.equal(_ethSeizedByLiquidator.toString(), toBN(aliceColl.toString()).add(liqReward).toString());
  }) 
  
  it("liquidate(): liquidate a CDP in recovery mode with some surplus to claim", async () => {	
      await openCdp({ ICR: toBN(dec(299, 16)), extraParams: { from: bob } });	  
      let bobCdpId = await sortedCdps.getFirst();
      assert.isTrue(await sortedCdps.contains(bobCdpId));	
      await openCdp({ ICR: toBN(dec(299, 16)), extraParams: { from: carol } });	  
      let carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
      assert.isTrue(await sortedCdps.contains(carolCdpId));

      // mint Alice some EBTC
      await openCdp({ ICR: toBN(dec(265, 16)), extraEBTCAmount: toBN(minDebt.toString()).add(toBN(1)), extraParams: { from: alice } });	
      await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});	
      await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});  
      await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from: alice});	  
      let aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
      let aliceCdpOwner = await sortedCdps.getOwnerAddress(aliceCdpId);
      assert.isTrue(aliceCdpOwner == alice);

      // maniuplate price to liquidate alice
      let _newPrice = dec(3100, 13);
      await priceFeed.setPrice(_newPrice);  
      assert.isTrue(await cdpManager.checkRecoveryMode(_newPrice));

      let aliceDebt = await cdpManager.getCdpDebt(aliceCdpId);
      let aliceColl = await cdpManager.getCdpCollShares(aliceCdpId);		  
      let prevDebtOfOwner = await debtToken.balanceOf(owner);
      assert.isTrue(toBN(prevDebtOfOwner.toString()).gt(toBN(aliceDebt.toString())));	  
	  	  
      // trigger cooldown and pass the liq wait
      await th.syncGlobalStateAndGracePeriod(contracts, ethers.provider);
	  
      // liquidate alice in recovery mode	  
      let prevETHOfOwner = await ethers.provider.getBalance(owner);	
      let _collLiquidatorPre = await collToken.balanceOf(owner);
      let _TCR = await cdpManager.getCachedTCR(_newPrice);
      let _aliceICR = await cdpManager.getCachedICR(aliceCdpId, _newPrice);
      assert.isTrue(toBN(_aliceICR.toString()).lt(toBN(_TCR.toString())));
      assert.isTrue(toBN(_aliceICR.toString()).gt(toBN(_MCR.toString())));
      let _cappedLiqColl = toBN(aliceDebt.toString()).mul(_MCR).div(toBN(_newPrice));
      let _liquidateRecoveryTx = await cdpManager.liquidate(aliceCdpId, { from: owner});	  
      let postDebtOfOwner = await debtToken.balanceOf(owner);
      let postETHOfOwner = await ethers.provider.getBalance(owner);	
      let _collLiquidatorPost = await collToken.balanceOf(owner);
      assert.isFalse(await sortedCdps.contains(aliceCdpId));
      let _liquidatedEvents = th.getAllEventsByName(_liquidateRecoveryTx, 'CdpLiquidated');
      assert.equal(_liquidatedEvents.length, 1, '!CdpLiquidated event');
      assert.equal(_liquidatedEvents[0].args[0], aliceCdpId, '!liquidated CDP ID');
      assert.equal(_liquidatedEvents[0].args[1], alice, '!liquidated CDP owner');
      assert.equal(_liquidatedEvents[0].args[2].toString(), aliceDebt.toString(), '!liquidated CDP debt');
      assert.equal(_liquidatedEvents[0].args[3].toString(), _cappedLiqColl.toString(), '!liquidated CDP collateral');
      assert.equal(_liquidatedEvents[0].args[4].toString(), '5', '!liquidateInRecoveryMode');// alice was liquidated in recovery mode
      let _gasEtherUsed = toBN(_liquidateRecoveryTx.receipt.effectiveGasPrice.toString()).mul(toBN((th.gasUsed(_liquidateRecoveryTx)).toString()));
      let _ethSeizedByLiquidator = toBN(_collLiquidatorPost.toString()).sub(toBN(_collLiquidatorPre.toString()));
      let _expectClaimSurplus = toBN(aliceColl.toString()).sub(_cappedLiqColl);
      let _toClaimSurplus = await collSurplusPool.getSurplusCollShares(alice);
      assert.isTrue(toBN(_toClaimSurplus.toString()).gt(toBN('0')));
      assert.equal(_toClaimSurplus.toString(), _expectClaimSurplus.toString());
      assert.equal(_liquidatedEvents[0].args[5], owner, '!liquidator');	  
      let _debtToColl = aliceDebt.mul(mv._1e18BN).div(toBN(_newPrice));
      assert.equal(_liquidatedEvents[0].args[6].toString(), _ethSeizedByLiquidator.sub(_debtToColl).toString(), '!liquidator premium');

      // owner get collateral from alice by repaying the debts
      assert.equal(toBN(prevDebtOfOwner.toString()).sub(toBN(postDebtOfOwner.toString())).toString(), toBN(aliceDebt.toString()).toString());
      assert.equal(_ethSeizedByLiquidator.toString(), toBN(aliceColl.toString()).add(liqReward).sub(toBN(_toClaimSurplus.toString())).toString());
	  
      // alice could claim whatever surplus is
      let prevETHOfAlice = await ethers.provider.getBalance(alice);	
      let _collClaimatorPre = await collToken.balanceOf(alice);
      let _claimTx = await borrowerOperations.claimSurplusCollShares({ from: alice});	
      let postETHOfAlice = await ethers.provider.getBalance(alice);
      let _collClaimatorPost = await collToken.balanceOf(alice);
      let _gasEtherUsedClaim = toBN(_claimTx.receipt.effectiveGasPrice.toString()).mul(toBN((th.gasUsed(_claimTx)).toString()));
      let _ethClaimed = toBN(_collClaimatorPost.toString()).sub(toBN(_collClaimatorPre.toString()));
      assert.equal(_ethClaimed.toString(), toBN(_toClaimSurplus.toString()).toString());
  })  
  
  it("Liquidator partially liquidate in recovery mode", async () => {
      await openCdp({ ICR: toBN(dec(299, 16)), extraEBTCAmount: toBN(minDebt.toString()).add(toBN(1)), extraParams: { from: alice } })
      let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);	  
      await openCdp({ ICR: toBN(dec(279, 16)), extraEBTCAmount: toBN(dec(1, 18)), extraParams: { from: bob } })
      let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
      assert.isTrue(await sortedCdps.contains(_aliceCdpId));
	  
      await openCdp({ ICR: toBN(dec(169, 16)), extraParams: { from: carol } })
      let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);	  
      await openCdp({ ICR: toBN(dec(159, 16)), extraParams: { from: owner } })
      let _ownerCdpId = await sortedCdps.cdpOfOwnerByIndex(owner, 0);
      assert.isFalse(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()));
	  
      // bob now sit second in sorted CDP list according to NICR
      let _firstId = await sortedCdps.getFirst();
      let _secondId = await sortedCdps.getNext(_firstId);
      assert.equal(_secondId, _bobCdpId);
      let _thirdId = await sortedCdps.getNext(_secondId);
      assert.equal(_thirdId, _carolCdpId);
      let _lastId = await sortedCdps.getLast();
      assert.equal(_lastId, _ownerCdpId);
	  
      // accumulate some interest
      await ethers.provider.send("evm_increaseTime", [8640000]);
      await ethers.provider.send("evm_mine");
	  
      // price slump to make system enter recovery mode
      let _newPrice = dec(2400, 13);
      await priceFeed.setPrice(_newPrice);
      assert.isTrue(await cdpManager.checkRecoveryMode(_newPrice));
      let _bobICR = await cdpManager.getCachedICR(_bobCdpId, _newPrice);
      assert.isTrue(toBN(_bobICR.toString()).lt(LICR));
      let _colRatio = LICR;	 
	  
      await debtToken.transfer(alice, (await debtToken.balanceOf(bob)), {from: bob});
      // liquidator alice coming in firstly partially liquidate some portion(0.5 EBTC) of bob 
      let _partialAmount = toBN("500000000000000000"); // 0.5e18
      let _debtFirstPre = await cdpManager.getCdpDebt(_bobCdpId);
      let _collFirstPre = await cdpManager.getCdpCollShares(_bobCdpId);
      let _debtInLiquidatorPre = await debtToken.balanceOf(alice);
      let _ethLiquidatorPre = await web3.eth.getBalance(alice);		
      let _collLiquidatorPre = await collToken.balanceOf(alice); 	
      let _debtToColl = _partialAmount.mul(mv._1e18BN).div(toBN(_newPrice));  
      let _liqTx = await cdpManager.partiallyLiquidate(_bobCdpId, _partialAmount, _bobCdpId, _bobCdpId, {from: alice});
      const partialLiqEvents = th.getAllEventsByName(_liqTx, 'CdpPartiallyLiquidated')
      let _liquidator = th.getEventValByName(partialLiqEvents[0], '_liquidator');
      assert.isTrue(_liquidator == alice);
      let _premiumToLiquidator = th.getEventValByName(partialLiqEvents[0], '_premiumToLiquidator');
      let _ethLiquidatorPost = await web3.eth.getBalance(alice);	
      let _collLiquidatorPost = await collToken.balanceOf(alice);	
      let _collFirstPost = await cdpManager.getCdpCollShares(_bobCdpId);  	  	  
      const gasUsedETH = toBN(_liqTx.receipt.effectiveGasPrice.toString()).mul(toBN(th.gasUsed(_liqTx).toString()));
      let _ethSeizedByLiquidator = toBN(_collLiquidatorPost.toString()).sub(toBN(_collLiquidatorPre.toString()));
      let _debtFirstPost = await cdpManager.getCdpDebt(_bobCdpId);
      let _debtInLiquidatorPost = await debtToken.balanceOf(alice);
      let _debtDecreased = toBN(_debtFirstPre.toString()).sub(toBN(_debtFirstPost.toString()));
      let _debtInLiquidatorDecreased = toBN(_debtInLiquidatorPre.toString()).sub(toBN(_debtInLiquidatorPost.toString()));
      let _collDecreased = toBN(_collFirstPre.toString()).sub(toBN(_collFirstPost.toString()));
      assert.isTrue(_premiumToLiquidator.eq(_collLiquidatorPost.sub(_collLiquidatorPre).sub(_debtToColl)));
      
      // check debt change & calculation in receovery mode
      assert.equal(_debtDecreased.toString(), _debtInLiquidatorDecreased.toString(), '!partially liquidation debt change in liquidator');
      assert.equal(_debtDecreased.toString(), _partialAmount.toString(), '!partially liquidation debt calculation');	
	  
      // check collateral change & calculation in receovery mode
      assert.equal(_collDecreased.toString(), _ethSeizedByLiquidator.toString(), '!partially liquidation collateral change in liquidator');
      assert.equal(_collDecreased.toString(), _debtDecreased.mul(_colRatio).div(toBN(dec(100,16))).mul(toBN(dec(1, 18))).div(toBN(_newPrice)).toString());	
	 
      // bob still sit on the second of list
      _firstId = await sortedCdps.getFirst();
      _secondId = await sortedCdps.getNext(_firstId);
      assert.equal(_secondId, _bobCdpId); 
  }) 
  
  it("CDP below MCR could be partially liquidated in normal mode", async () => {
      await openCdp({ ICR: toBN(dec(345, 16)), extraEBTCAmount: toBN(minDebt.toString()).add(toBN(1)), extraParams: { from: alice } })
      let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
      await openCdp({ ICR: toBN(dec(299, 16)), extraParams: { from: bob } })
      assert.isTrue(await sortedCdps.contains(_aliceCdpId));
      await openCdp({ ICR: toBN(dec(169, 16)), extraParams: { from: owner } })
      let _ownerCdpId = await sortedCdps.cdpOfOwnerByIndex(owner, 0);
	  
      // alice now sit top of sorted CDP list according to NICR
      assert.equal((await sortedCdps.getFirst()), _aliceCdpId);
	  
      // accumulate some interest
      await ethers.provider.send("evm_increaseTime", [8640000]);
      await ethers.provider.send("evm_mine");
	  
      // price slump
      let _newPrice = dec(2350, 13);
      await priceFeed.setPrice(_newPrice);
	  
      // get some redistributed debts for remaining CDP
      let _ownerDebt = await cdpManager.getCdpDebt(_ownerCdpId);
      await debtToken.transfer(owner, toBN(_ownerDebt.toString()).sub(toBN((await debtToken.balanceOf(owner)).toString())), {from: alice});	
      await th.liquidateCdps(1, _newPrice, contracts, {extraParams: {from: owner}});
      assert.isFalse(await sortedCdps.contains(_ownerCdpId));
      let _rewardEBTCDebt = await cdpManager.getPendingRedistributedDebt(_aliceCdpId);
      assert.isTrue(toBN(_rewardEBTCDebt.toString()).gt(toBN('0')));	
	  
      // liquidator bob coming in firstly partially liquidate some portion(0.1 EBTC) of alice
      let _partialAmount = toBN("100000000000000000"); // 0.1e18
      let _icr = await cdpManager.getCachedICR(_aliceCdpId, _newPrice);

      assert.isTrue(toBN(_icr.toString()).lt(_MCR));
      assert.isTrue(toBN(_icr.toString()).gt(LICR));
      let _colRatio = _icr;	 
	  
      let _debtLiquidated = _partialAmount;
      let _collLiquidated = _debtLiquidated.mul(_colRatio).div(toBN(_newPrice));
	  
      // liquidator bob coming in 
      await debtToken.transfer(bob, (await debtToken.balanceOf(alice)), {from: alice});	  
      let _debtLiquidatorPre = await debtToken.balanceOf(bob);  
      let _debtSystemPre = await cdpManager.getSystemDebt();
      let _colSystemPre = await cdpManager.getSystemCollShares();
      let _ethLiquidatorPre = await web3.eth.getBalance(bob);	
      let _collLiquidatorPre = await collToken.balanceOf(bob);	  
      let _debtInAllPoolPre = toBN((await activePool.getSystemDebt()).toString()).toString();
      let _collInAllPoolPre = toBN((await activePool.getSystemCollShares()).toString()).toString();
	  
      let _debtToColl = _partialAmount.mul(mv._1e18BN).div(toBN(_newPrice));
      const tx = await cdpManager.partiallyLiquidate(_aliceCdpId, _partialAmount, _aliceCdpId, _aliceCdpId, {from: bob}) 
      const partialLiqEvents = th.getAllEventsByName(tx, 'CdpPartiallyLiquidated')
      let _liquidator = th.getEventValByName(partialLiqEvents[0], '_liquidator');
      assert.isTrue(_liquidator == bob);
      let _premiumToLiquidator = th.getEventValByName(partialLiqEvents[0], '_premiumToLiquidator');
      let _collRemaining = await cdpManager.getCdpCollShares(_aliceCdpId); 
      let _stakeRemaining = await cdpManager.getCdpStake(_aliceCdpId);
      let _debtRemaining = await cdpManager.getCdpDebt(_aliceCdpId);
      let _debtInAllPoolPost = toBN((await activePool.getSystemDebt()).toString()).toString();
      let _collInAllPoolPost = toBN((await activePool.getSystemCollShares()).toString()).toString();
      let _additionalCol = dec(1, 'ether');
      await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: alice});
      await contracts.collateral.deposit({from: alice, value: _additionalCol});
      await borrowerOperations.addColl(_aliceCdpId, _aliceCdpId, _aliceCdpId, _additionalCol, { from: alice, value: 0 }); //apply pending rewards	  
      let _debtLiquidatorPost = await debtToken.balanceOf(bob);
      let _debtSystemPost = await cdpManager.getSystemDebt();
      let _colSystemPost = await cdpManager.getSystemCollShares();
      let _ethLiquidatorPost = await web3.eth.getBalance(bob);	
      let _collLiquidatorPost = await collToken.balanceOf(bob);
      assert.isTrue(_premiumToLiquidator.eq(_collLiquidatorPost.sub(_collLiquidatorPre).sub(_debtToColl)));

      // check CdpUpdated event
      const troveUpdatedEvents = th.getAllEventsByName(tx, 'CdpUpdated')
      assert.equal(troveUpdatedEvents.length, 2, '!CdpUpdated event') // first CdpUpdated event for syncAccounting()
      assert.equal(troveUpdatedEvents[1].args[0], _aliceCdpId, '!partially liquidated CDP ID');
      assert.equal(troveUpdatedEvents[1].args[1], alice, '!partially liquidated CDP owner');
      assert.equal(troveUpdatedEvents[1].args[5].toString(), _debtRemaining.toString(), '!partially liquidated CDP remaining debt');
      assert.equal(troveUpdatedEvents[1].args[6].toString(), _collRemaining.toString(), '!partially liquidated CDP remaining collateral');
      assert.equal(troveUpdatedEvents[1].args[7].toString(), _stakeRemaining.toString(), '!partially liquidated CDP remaining stake');
      assert.equal(troveUpdatedEvents[1].args[8], 7, '!CdpOperation.partiallyLiquidate');

      // check CdpPartiallyLiquidated event
      const liquidationEvents = th.getAllEventsByName(tx, 'CdpPartiallyLiquidated')
      assert.equal(liquidationEvents.length, 1, '!CdpPartiallyLiquidated event')
      assert.equal(liquidationEvents[0].args[0], _aliceCdpId, '!partially liquidated CDP ID');
      assert.equal(liquidationEvents[0].args[1], alice, '!partially liquidated CDP owner');
      assert.equal(liquidationEvents[0].args[2].toString(), _debtLiquidated.toString(), '!partially liquidated CDP debt');
      assert.equal(liquidationEvents[0].args[3].toString(), _collLiquidated.toString(), '!partially liquidated CDP collateral');
      assert.equal(liquidationEvents[0].args[4], 7, '!CdpOperation.partiallyLiquidate');
	  
      // check liquidator balance change
      let _gasUsed = th.gasUsed(tx);
      let _debtDecreased = toBN(_debtLiquidatorPre.toString()).sub(toBN(_debtLiquidatorPost.toString()));
      assert.equal(_debtDecreased.toString(), _debtLiquidated.toString(), '!liquidator debt balance');		  
      const gasUsedETH = toBN(tx.receipt.effectiveGasPrice.toString()).mul(toBN(_gasUsed.toString()));
      let _ethSeizedByLiquidator = toBN(_collLiquidatorPost.toString()).sub(toBN(_collLiquidatorPre.toString()));
      assert.equal(_ethSeizedByLiquidator.toString(), _collLiquidated.toString(), '!liquidator collateral balance');	 
	  
      // check system balance change
      let _debtDecreasedSystem = toBN(_debtSystemPre.toString()).sub(toBN(_debtSystemPost.toString()));
      assert.equal(_debtDecreasedSystem.toString(), _debtLiquidated.toString(), '!system debt balance');	
      let _colDecreasedSystem = toBN(_colSystemPre.toString()).sub(toBN(_colSystemPost.toString())); 
      assert.equal(_colDecreasedSystem.add(toBN(_additionalCol)).toString(), _collLiquidated.toString(), '!system collateral balance');	
      let _debtDecreasedAllPool = toBN(_debtInAllPoolPre.toString()).sub(toBN(_debtInAllPoolPost.toString())); 
      assert.equal(_debtDecreasedAllPool.toString(), _debtLiquidated.toString(), '!activePool debt balance');
      let _colDecreasedAllPool = toBN(_collInAllPoolPre.toString()).sub(toBN(_collInAllPoolPost.toString())); 
      assert.equal(_colDecreasedAllPool.toString(), _collLiquidated.toString(), '!activePool collateral balance');

      // Confirm the CDP still there
      assert.isTrue(await sortedCdps.contains(_aliceCdpId))

      // Confirm CDP have status 'active' (Status enum element idx 1)
      assert.equal((await cdpManager.Cdps(_aliceCdpId))[4], '1')
	  
      // Confirm partially liquidated CDP got higher or at least equal ICR than before
      let _aliceNewICR = await cdpManager.getCachedICR(_aliceCdpId, _newPrice);
      assert.isTrue(toBN(_icr.toString()).lte(_aliceNewICR));
	  
      // Confirm alice still on top of sorted CDP list since partially liquidation should keep its ICR NOT decreased
      assert.equal((await sortedCdps.getFirst()), _aliceCdpId);
  })
  
  it("CDP could be fully liquidated step by step via partiallyLiquidate() and liquidate() lastly", async () => {
      await openCdp({ ICR: toBN(dec(299, 16)), extraEBTCAmount: toBN(minDebt.toString()).add(toBN(1)), extraParams: { from: alice } })
      await openCdp({ ICR: toBN(dec(299, 16)), extraParams: { from: bob } })
      let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
      assert.isTrue(await sortedCdps.contains(_aliceCdpId));
      let _debtBorrowed = await cdpManager.getCdpDebt(_aliceCdpId);
      let _colDeposited = await cdpManager.getCdpCollShares(_aliceCdpId);
	  
      // accumulate some interest
      await ethers.provider.send("evm_increaseTime", [8640000]);
      await ethers.provider.send("evm_mine");
	  
      // price slump
      let _newPrice = dec(2400, 13);
      await priceFeed.setPrice(_newPrice);
	  
      // partial liquidation steps: Firstly 1/4, Secondly another 1/4, Lastly all the rest
      let _quarterDebt = _debtBorrowed.div(toBN('4'));
      let _partialAmounts = [_quarterDebt, _quarterDebt, _debtBorrowed.sub(_quarterDebt).sub(_quarterDebt)];
      let _partialLiquidations = 3;
      let _partialLiquidationTxs = [];
	  
      // liquidator bob coming in 
      await debtToken.transfer(bob, (await debtToken.balanceOf(alice)), {from: alice});	  
      let _debtLiquidatorPre = await debtToken.balanceOf(bob);  
      let _debtSystemPre = await cdpManager.getSystemDebt();
      let _colSystemPre = await cdpManager.getSystemCollShares();
      let _ethLiquidatorPre = await web3.eth.getBalance(bob);	
      let _collLiquidatorPre = await collToken.balanceOf(bob);	  
      let _debtInActivePoolPre = await activePool.getSystemDebt();
      let _collInActivePoolPre = await activePool.getSystemCollShares();
	  
      for(let i = 0;i < _partialLiquidations;i++){
          if(i < _partialLiquidations - 1){
             const tx = await cdpManager.partiallyLiquidate(_aliceCdpId, _partialAmounts[i], _aliceCdpId, _aliceCdpId, {from: bob})
             _partialLiquidationTxs.push(tx);			  
          }else{			 
             let _leftColl = (await cdpManager.getSyncedDebtAndCollShares(_aliceCdpId))[1]
             const finalTx = await cdpManager.liquidate(_aliceCdpId, {from: bob})
             _partialLiquidationTxs.push(finalTx);
          }			  
      } 
      
      let _debtLiquidatorPost = await debtToken.balanceOf(bob);
      let _debtSystemPost = await cdpManager.getSystemDebt();
      let _colSystemPost = await cdpManager.getSystemCollShares();
      let _ethLiquidatorPost = await web3.eth.getBalance(bob);	  
      let _collLiquidatorPost = await collToken.balanceOf(bob);	
      let _debtInActivePoolPost = await activePool.getSystemDebt();
      let _collInActivePoolPost = await activePool.getSystemCollShares();
	  
      // check liquidator balance change
      let _leftCollWithHalfDebtRepaid = _colDeposited.sub(_quarterDebt.add(_quarterDebt).mul(LICR).div(toBN(_newPrice)));
      let _expectedDebtRepaid = _quarterDebt.add(_quarterDebt).add(_leftCollWithHalfDebtRepaid.mul(toBN(_newPrice)).div(LICR));
      let _debtDecreased = toBN(_debtLiquidatorPre.toString()).sub(toBN(_debtLiquidatorPost.toString()));
      th.assertIsApproximatelyEqual(_debtDecreased.toString(), _expectedDebtRepaid.toString());
      let gasUsedETH = toBN('0');
      for(let i = 0;i < _partialLiquidations;i++){
          let _gasUsed = toBN(th.gasUsed(_partialLiquidationTxs[i]).toString());	
          gasUsedETH = gasUsedETH.add(toBN(_partialLiquidationTxs[i].receipt.effectiveGasPrice.toString()).mul(toBN(_gasUsed.toString())));	  		  
      }
      let _ethSeizedByLiquidator = toBN(_collLiquidatorPost.toString()).sub(toBN(_collLiquidatorPre.toString()));
      assert.equal(_ethSeizedByLiquidator.toString(), _colDeposited.add(liqReward).toString(), '!liquidator collateral balance');
	  
      // check system balance change
      let _debtDecreasedSystem = toBN(_debtSystemPre.toString()).sub(toBN(_debtSystemPost.toString()));
      assert.equal(_debtDecreasedSystem.toString(), _expectedDebtRepaid.toString(), '!system debt balance');	
      let _colDecreasedSystem = toBN(_colSystemPre.toString()).sub(toBN(_colSystemPost.toString())); 
      assert.equal(_colDecreasedSystem.toString(), _colDeposited.toString(), '!system collateral balance');
      let _debtDecreasedActivePool = toBN(_debtInActivePoolPre.toString()).sub(toBN(_debtInActivePoolPost.toString())); 
      assert.equal(_debtDecreasedActivePool.toString(), _expectedDebtRepaid.toString(), '!activePool debt balance');
      let _colDecreasedActivePool = toBN(_collInActivePoolPre.toString()).sub(toBN(_collInActivePoolPost.toString())); 
      assert.equal(_colDecreasedActivePool.toString(), _colDeposited.toString(), '!activePool collateral balance');

      // Confirm all CDPs removed
      assert.isFalse(await sortedCdps.contains(_aliceCdpId))

      // Confirm CDPs have status 'closed by liquidation' (Status enum element idx 3)
      assert.equal((await cdpManager.Cdps(_aliceCdpId))[4], '3')
  })
  
  it("Partial liquidation can not leave CDP below minimum debt size", async () => {
      await openCdp({ ICR: toBN(dec(299, 16)), extraEBTCAmount: toBN(minDebt.toString()).add(toBN(1)), extraParams: { from: alice } })
      await openCdp({ ICR: toBN(dec(299, 16)), extraParams: { from: bob } })
      let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
      let _debtBorrowed = await cdpManager.getCdpDebt(_aliceCdpId);
	  
      // price slump
      let _newPrice = dec(2400, 13);
      await priceFeed.setPrice(_newPrice);
	  
      // liquidator bob coming in
      await debtToken.transfer(bob, (await debtToken.balanceOf(alice)), {from: alice});
      await assertRevert(cdpManager.partiallyLiquidate(_aliceCdpId, _debtBorrowed, _aliceCdpId, _aliceCdpId, {from: bob}), "LiquidationLibrary: Partial debt liquidated must be less than total debt"); 
  })  
  
  it("Test sequence liquidation with extreme slashing case", async() => {
      let _errorTolerance = toBN("2000000");//compared to 1e18
      let _oldPrice = await priceFeed.getPrice();
	  
      // open CDP
      let _collAmt1 = toBN("23295194968429539453");
      let _ebtcAmt1 = toBN("149901978595855214");
      await collToken.deposit({from: owner, value: _collAmt1});
      await collToken.approve(borrowerOperations.address, mv._1Be18BN, {from: owner});
      await borrowerOperations.openCdp(_ebtcAmt1, th.DUMMY_BYTES32, th.DUMMY_BYTES32, _collAmt1);
      let _cdpId1 = await sortedCdps.cdpOfOwnerByIndex(owner, 0);
      let _cdpDebtColl1 = await cdpManager.getSyncedDebtAndCollShares(_cdpId1);
      let _systemDebt = await cdpManager.getSystemDebt();
      th.assertIsApproximatelyEqual(_systemDebt, _cdpDebtColl1[0], _errorTolerance.toNumber());	  
	  
      // slashing to one wei	  	  
      await ethers.provider.send("evm_increaseTime", [43611]);
      await ethers.provider.send("evm_mine");  
      let _newIndex = 1;
      await collToken.setEthPerShare(_newIndex);  
	  
      // open another CDP
      let _collAmt2 = toBN("6024831127370552532");
      let _ebtcAmt2 = toBN("149482624651353285");
      await collToken.deposit({from: owner, value: _collAmt2});
      await borrowerOperations.openCdp(_ebtcAmt2, th.DUMMY_BYTES32, th.DUMMY_BYTES32, _collAmt2);
      let _cdpId2 = await sortedCdps.cdpOfOwnerByIndex(owner, 1);
      let _cdpDebtColl2 = await cdpManager.getSyncedDebtAndCollShares(_cdpId2);
      _systemDebt = await cdpManager.getSystemDebt();
      th.assertIsApproximatelyEqual(_systemDebt, (_cdpDebtColl1[0].add(_cdpDebtColl2[0])), _errorTolerance.toNumber());	
	  
      // sequence liquidation	  
      let _priceDiv = toBN("1");
      let _newPrice = _oldPrice.div(_priceDiv);
      await priceFeed.setPrice(_newPrice);
      let _n = 1;
      await debtToken.unprotectedMint(owner, _systemDebt);
      let _totalSupplyBefore = await debtToken.totalSupply();
      let _balBefore = await collToken.balanceOf(owner);
      let tx = await th.liquidateCdps(_n, _newPrice, contracts, {extraParams: {from: owner}});
      let _balAfter = await collToken.balanceOf(owner);
      let _totalSupplyDiff = _totalSupplyBefore.sub(await debtToken.totalSupply());
      if (_totalSupplyDiff.lt(_systemDebt)) {
          await debtToken.unprotectedBurn(owner, _systemDebt.sub(_totalSupplyDiff));
      }
	  
      // final check
      assert.isFalse(await sortedCdps.contains(_cdpId1));
      _cdpDebtColl2 = await cdpManager.getSyncedDebtAndCollShares(_cdpId2);
      _systemDebt = await cdpManager.getSystemDebt();
      let _distributedError = (await cdpManager.lastEBTCDebtErrorRedistribution()).div(mv._1e18BN);
      th.assertIsApproximatelyEqual(_systemDebt, (_distributedError.add(_cdpDebtColl2[0])), _errorTolerance.toNumber());
	  
      const liquidationEvents = th.getAllEventsByName(tx, 'CdpLiquidated')
      let _liquidator = th.getEventValByName(liquidationEvents[0], '_liquidator');
      let _debtToBurn = th.getEventValByName(liquidationEvents[0], '_debt');
      assert.isTrue(_liquidator == owner);
      let _liqPremium1 = th.getEventValByName(liquidationEvents[0], '_premiumToLiquidator');
      let _liqPremium = _liqPremium1
      let _debtToColl = _debtToBurn.mul(mv._1e18BN).div(toBN(_newPrice));
      assert.isTrue(_liqPremium.eq(_balAfter.sub(_balBefore).sub(_debtToColl)));
  })
  
  it("Test partial liquidation with extreme slashing case", async() => {
      let _errorTolerance = toBN("2000000");//compared to 1e18
      let _oldPrice = await priceFeed.getPrice();
	  
      // open CDP
      let _collAmt1 = toBN("7082199038359602403");
      let _ebtcAmt1 = toBN("150106490695243734");
      await collToken.deposit({from: owner, value: _collAmt1});
      await collToken.approve(borrowerOperations.address, mv._1Be18BN, {from: owner});
      await borrowerOperations.openCdp(_ebtcAmt1, th.DUMMY_BYTES32, th.DUMMY_BYTES32, _collAmt1);
      let _cdpId1 = await sortedCdps.cdpOfOwnerByIndex(owner, 0);
      let _cdpDebtColl1 = await cdpManager.getSyncedDebtAndCollShares(_cdpId1);
      let _systemDebt = await cdpManager.getSystemDebt();
      th.assertIsApproximatelyEqual(_systemDebt, (await debtToken.totalSupply()), _errorTolerance.toNumber());	  
	  
      // slashing to two wei	  	  
      await ethers.provider.send("evm_increaseTime", [43567]);
      await ethers.provider.send("evm_mine");  
      let _newIndex = 2;
      await collToken.setEthPerShare(_newIndex); 
	  
      // partial liquidation	  
      let _priceDiv = toBN("1");
      let _newPrice = _oldPrice.div(_priceDiv);
      await priceFeed.setPrice(_newPrice);
      let _partialAmount = toBN("1");
      await debtToken.unprotectedMint(owner, _partialAmount);
      let _totalSupplyBefore = await debtToken.totalSupply();
      await assertRevert(cdpManager.partiallyLiquidate(_cdpId1, _partialAmount, _cdpId1, _cdpId1), "LiquidationLibrary: Coll remaining in partially liquidated CDP must be >= minimum");
      let _totalSupplyDiff = _totalSupplyBefore.sub(await debtToken.totalSupply());
      if (_totalSupplyDiff.lt(_partialAmount)) {
          await debtToken.unprotectedBurn(owner, _partialAmount.sub(_totalSupplyDiff));
      }
      let _cdpDebtColl1After = await cdpManager.getSyncedDebtAndCollShares(_cdpId1);
      assert.isTrue(_cdpDebtColl1After[0].lt(_cdpDebtColl1[1]));
	  
      // final check
      _systemDebt = await cdpManager.getSystemDebt();
      th.assertIsApproximatelyEqual(_systemDebt, (await debtToken.totalSupply()), _errorTolerance.toNumber());
  })  
  
  it("LiquidateCdps(1) in normal mode", async () => {
      await openCdp({ ICR: toBN(dec(345, 16)), extraEBTCAmount: toBN(minDebt.toString()).add(toBN(1)), extraParams: { from: alice } })
      await openCdp({ ICR: toBN(dec(299, 16)), extraParams: { from: bob } })
      await openCdp({ ICR: toBN(dec(120, 16)), extraParams: { from: owner } })
      let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
      let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
      let _ownerCdpId = await sortedCdps.cdpOfOwnerByIndex(owner, 0);
      assert.isTrue((await sortedCdps.contains(_ownerCdpId)));
      let _ownerColl = await cdpManager.getCdpCollShares(_ownerCdpId);
      let _ownerDebt = await cdpManager.getCdpDebt(_ownerCdpId);
	  
      // price slump but still in normal mode
      let _newPrice = dec(3700, 13);
      await priceFeed.setPrice(_newPrice);
      assert.isFalse((await cdpManager.checkRecoveryMode(_newPrice)));
	  
      // liquidateCdps(1)
      await debtToken.transfer(alice, toBN((await debtToken.balanceOf(owner)).toString()), {from: owner});
      let _debtBefore = await debtToken.balanceOf(alice);
      let _balBefore = await collToken.balanceOf(alice);
      let tx = await th.liquidateCdps(1, _newPrice, contracts, {extraParams: {from: alice}});
      let _debtAfter = await debtToken.balanceOf(alice);
      let _balAfter = await collToken.balanceOf(alice);
	  
      // post checks
      assert.isFalse((await sortedCdps.contains(_ownerCdpId)));
      let _liquidatedDebt = _ownerColl.mul(toBN(_newPrice)).div(LICR);
      let _badDebt = _ownerDebt.sub(_liquidatedDebt);
      assert.equal(_debtAfter.add(_liquidatedDebt).toString(), _debtBefore.toString(), '!liquidated debt');
      let _alicePendingDebt = await cdpManager.getPendingRedistributedDebt(_aliceCdpId);
      let _bobPendingDebt = await cdpManager.getPendingRedistributedDebt(_bobCdpId);
      th.assertIsApproximatelyEqual(_alicePendingDebt.add(_bobPendingDebt).toString(), _badDebt.toString());   
	  
      const liquidationEvents = th.getAllEventsByName(tx, 'CdpLiquidated')
      let _liquidator = th.getEventValByName(liquidationEvents[0], '_liquidator');
      assert.isTrue(_liquidator == alice);
      let _liqPremium1 = th.getEventValByName(liquidationEvents[0], '_premiumToLiquidator');
      let _liqPremium = _liqPremium1
      let _debtToColl = _liquidatedDebt.mul(mv._1e18BN).div(toBN(_newPrice));
      assert.isTrue(_liqPremium.eq(_balAfter.sub(_balBefore).sub(_debtToColl)));
	  
  }) 
  
  it("LiquidateCdps(n) in recovery mode", async () => {
      await openCdp({ ICR: toBN(dec(195, 16)), extraParams: { from: alice } })
      await openCdp({ ICR: toBN(dec(232, 16)), extraParams: { from: bob } })
      await openCdp({ ICR: toBN(dec(255, 16)), extraEBTCAmount: toBN(minDebt.toString()).add(toBN(1)), extraParams: { from: owner } })
      let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
      let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
      let _ownerCdpId = await sortedCdps.cdpOfOwnerByIndex(owner, 0);
      let _aliceColl = await cdpManager.getCdpCollShares(_aliceCdpId);
      let _aliceDebt = await cdpManager.getCdpDebt(_aliceCdpId);
      let _bobDebt = await cdpManager.getCdpDebt(_bobCdpId);
	  
      // price slump to recovery mode
      let _newPrice = dec(3700, 13);
      await priceFeed.setPrice(_newPrice);
      assert.isTrue((await cdpManager.checkRecoveryMode(_newPrice)));
	  
      // liquidateCdps(2) with second in the list skipped due to backToNormal
      await debtToken.transfer(owner, toBN((await debtToken.balanceOf(alice)).toString()), {from: alice});
      let _debtBefore = await debtToken.balanceOf(owner);
      let _balBefore = await collToken.balanceOf(owner);
      let tx = await th.liquidateCdps(2, _newPrice, contracts, {extraParams: {from: owner}});
      let _debtAfter = await debtToken.balanceOf(owner);
      let _balAfter = await collToken.balanceOf(owner);
	  
      // post checks
      assert.isFalse((await sortedCdps.contains(_aliceCdpId)));
      assert.isTrue((await sortedCdps.contains(_bobCdpId)));
      let _liquidatedDebt = _aliceColl.mul(toBN(_newPrice)).div(LICR);
      let _badDebt = _aliceDebt.sub(_liquidatedDebt);
      assert.equal(_debtAfter.add(_liquidatedDebt).toString(), _debtBefore.toString(), '!liquidated debt');
      let _ownerPendingDebt = await cdpManager.getPendingRedistributedDebt(_ownerCdpId);
      let _bobPendingDebt = await cdpManager.getPendingRedistributedDebt(_bobCdpId);
      th.assertIsApproximatelyEqual(_ownerPendingDebt.add(_bobPendingDebt).toString(), _badDebt.toString()); 
	  
      const liquidationEvents = th.getAllEventsByName(tx, 'CdpLiquidated')
      let _liquidator = th.getEventValByName(liquidationEvents[0], '_liquidator');
      assert.isTrue(_liquidator == owner);
      let _liqPremium1 = th.getEventValByName(liquidationEvents[0], '_premiumToLiquidator');
      let _liqPremium = _liqPremium1
      let _debtToColl = _liquidatedDebt.mul(mv._1e18BN).div(toBN(_newPrice));
      assert.isTrue(_liqPremium.eq(_balAfter.sub(_balBefore).sub(_debtToColl)));
  })
  
  it("sequenceLiqToBatchLiq(): return [N] CDP candidates for batch liquidation after stETH slash", async () => {
      // Cdps undercollateralized under minimum liq premium [<3% ICR]
      await openCdp({ ICR: toBN(dec(126, 16)), extraParams: { from: alice } })	  
      let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
      // Cdps undercollateralized [3% < ICR < 100%]
      await openCdp({ ICR: toBN(dec(500, 16)), extraParams: { from: bob } })
      let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
      // Cdps overcollateralized but liquidatable [100% <= ICR < MCR]
      await openCdp({ ICR: toBN(dec(4500, 16)), extraParams: { from: carol } })
      let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
      // Cdps overcollateralized but liquidatable in recovery mode [MCR <= ICR < TCR]
      await openCdp({ ICR: toBN(dec(4800, 16)), extraParams: { from: dennis } })
      let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);
      // Cdps overcollateralized and unliquidatable [ICR >= TCR]
      await openCdp({ ICR: toBN(dec(5400, 16)), extraEBTCAmount: toBN(minDebt.toString()).mul(toBN(3)), extraParams: { from: owner } })
      let _ownerCdpId = await sortedCdps.cdpOfOwnerByIndex(owner, 0);

      // stETH got a serious slash
      let _price = dec(7428, 13);
      let _newIndex = dec(24, 15);
      await collToken.setEthPerShare(_newIndex);
      let _tcr = await cdpManager.getSyncedTCR(_price);
      assert.isTrue(_tcr.lt(_CCR));

      // check sequenceLiqToBatchLiq() results
      // riskiest CDP at last
      let _batch1 = await th.liqSequencerCallWithPrice(1, _price, contracts, {extraParams: { from: owner }});
      assert.isTrue(_batch1[0] == _aliceCdpId);
      let _batch2 = await th.liqSequencerCallWithPrice(2, _price, contracts, {extraParams: { from: owner }});
      assert.isTrue(_batch2.length == 2 && _batch2[1] == _aliceCdpId && _batch2[0] == _bobCdpId);
      let _batch3 = await th.liqSequencerCallWithPrice(3, _price, contracts, {extraParams: { from: owner }});
      assert.isTrue(_batch3.length == 3 && _batch3[2] == _aliceCdpId && _batch3[1] == _bobCdpId && _batch3[0] == _carolCdpId);
      let _batch4 = await th.liqSequencerCallWithPrice(4, _price, contracts, {extraParams: { from: owner }});
      assert.isTrue(_batch4.length == 4 && _batch4[3] == _aliceCdpId && _batch4[2] == _bobCdpId && _batch4[1] == _carolCdpId && _batch4[0] == _dennisCdpId);
      let _batch5 = await th.liqSequencerCallWithPrice(5, _price, contracts, {extraParams: { from: owner }});
      assert.isTrue(_batch5.length == 4 && _batch5[3] == _aliceCdpId && _batch5[2] == _bobCdpId && _batch5[1] == _carolCdpId && _batch5[0] == _dennisCdpId);	  
  })
  
  it("sequenceLiqToBatchLiq(): return [N] CDP candidates for batch liquidation in Recovery Mode", async () => {
      // Cdps undercollateralized under minimum liq premium [<3% ICR]
      await openCdp({ ICR: toBN(dec(126, 16)), extraParams: { from: alice } })	  
      let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
      // Cdps undercollateralized [3% < ICR < 100%]
      await openCdp({ ICR: toBN(dec(500, 16)), extraParams: { from: bob } })
      let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
      // Cdps overcollateralized but liquidatable [100% <= ICR < MCR]
      await openCdp({ ICR: toBN(dec(4500, 16)), extraParams: { from: carol } })
      let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
      // Cdps overcollateralized but liquidatable in recovery mode [MCR <= ICR < TCR]
      await openCdp({ ICR: toBN(dec(4800, 16)), extraParams: { from: dennis } })
      let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);
      // Cdps overcollateralized and unliquidatable [ICR >= TCR]
      await openCdp({ ICR: toBN(dec(5400, 16)), extraEBTCAmount: toBN(minDebt.toString()).mul(toBN(3)), extraParams: { from: owner } })
      let _ownerCdpId = await sortedCdps.cdpOfOwnerByIndex(owner, 0);

      // price slump to Recovery Mode
      let _newPrice = dec(175, 13);
      await priceFeed.setPrice(_newPrice);
      let _tcr = await cdpManager.getCachedTCR(_newPrice);
      assert.isTrue(_tcr.gt(await cdpManager.getCachedICR(_dennisCdpId, _newPrice)));
      assert.isTrue(_tcr.lt(_CCR));

      // check sequenceLiqToBatchLiq() results
      // riskiest CDP at last
      let _batch1 = await th.liqSequencerCallWithPrice(1, _newPrice, contracts, {extraParams: { from: owner }});
      assert.isTrue(_batch1[0] == _aliceCdpId);
      let _batch2 = await th.liqSequencerCallWithPrice(2, _newPrice, contracts, {extraParams: { from: owner }});
      assert.isTrue(_batch2.length == 2 && _batch2[1] == _aliceCdpId && _batch2[0] == _bobCdpId);
      let _batch3 = await th.liqSequencerCallWithPrice(3, _newPrice, contracts, {extraParams: { from: owner }});
      assert.isTrue(_batch3.length == 3 && _batch3[2] == _aliceCdpId && _batch3[1] == _bobCdpId && _batch3[0] == _carolCdpId);
      let _batch4 = await th.liqSequencerCallWithPrice(4, _newPrice, contracts, {extraParams: { from: owner }});
      assert.isTrue(_batch4.length == 4 && _batch4[3] == _aliceCdpId && _batch4[2] == _bobCdpId && _batch4[1] == _carolCdpId && _batch4[0] == _dennisCdpId);
      let _batch5 = await th.liqSequencerCallWithPrice(5, _newPrice, contracts, {extraParams: { from: owner }});
      assert.isTrue(_batch5.length == 4 && _batch5[3] == _aliceCdpId && _batch5[2] == _bobCdpId && _batch5[1] == _carolCdpId && _batch5[0] == _dennisCdpId);	  
  })

  it("sequenceLiqToBatchLiq(): return [N] CDP candidates for batch liquidation in Normal Mode", async () => {
      // Cdps undercollateralized under minimum liq premium [<3% ICR]
      await openCdp({ ICR: toBN(dec(126, 16)), extraParams: { from: alice } })	  
      let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
      // Cdps undercollateralized [3% < ICR < 100%]
      await openCdp({ ICR: toBN(dec(500, 16)), extraParams: { from: bob } })
      let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
      // Cdps overcollateralized but liquidatable [100% <= ICR < MCR]
      await openCdp({ ICR: toBN(dec(4500, 16)), extraParams: { from: carol } })
      let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
      // Cdps overcollateralized but liquidatable in recovery mode [MCR <= ICR < TCR]
      await openCdp({ ICR: toBN(dec(4800, 16)), extraParams: { from: dennis } })
      let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);
      // Cdps overcollateralized and unliquidatable [ICR >= TCR]
      await openCdp({ ICR: toBN(dec(5800, 16)), extraEBTCAmount: toBN(minDebt.toString()).mul(toBN(4)), extraParams: { from: owner } })
      let _ownerCdpId = await sortedCdps.cdpOfOwnerByIndex(owner, 0);

      // price keep system in Normal Mode
      let _newPrice = dec(175, 13);
      await priceFeed.setPrice(_newPrice);
      let _tcr = await cdpManager.getCachedTCR(_newPrice);
      assert.isTrue(_tcr.gt(_CCR));

      // check sequenceLiqToBatchLiq() results
      // riskiest CDP at last
      let _batch1 = await th.liqSequencerCallWithPrice(1, _newPrice, contracts, {extraParams: { from: owner }});
      assert.isTrue(_batch1[0] == _aliceCdpId);
      let _batch2 = await th.liqSequencerCallWithPrice(2, _newPrice, contracts, {extraParams: { from: owner }});
      assert.isTrue(_batch2.length == 2 && _batch2[1] == _aliceCdpId && _batch2[0] == _bobCdpId);
      let _batch3 = await th.liqSequencerCallWithPrice(3, _newPrice, contracts, {extraParams: { from: owner }});
      assert.isTrue(_batch3.length == 3 && _batch3[2] == _aliceCdpId && _batch3[1] == _bobCdpId && _batch3[0] == _carolCdpId);
      let _batch4 = await th.liqSequencerCallWithPrice(4, _newPrice, contracts, {extraParams: { from: owner }});
      assert.isTrue(_batch4.length == 3 && _batch4[2] == _aliceCdpId && _batch4[1] == _bobCdpId && _batch4[0] == _carolCdpId);
      let _batch5 = await th.liqSequencerCallWithPrice(5, _newPrice, contracts, {extraParams: { from: owner }});
      assert.isTrue(_batch5.length == 3 && _batch5[2] == _aliceCdpId && _batch5[1] == _bobCdpId && _batch5[0] == _carolCdpId);	  
  })
  
  it("Full liquidation should leave zero collateral surplus if bad debt generated", async () => {
      let {tx: opAliceTx} = await openCdp({ ICR: toBN(dec(149, 16)), extraEBTCAmount: toBN(minDebt.toString()).add(toBN(1)), extraParams: { from: alice } })
      await openCdp({ extraEBTCAmount: toBN('951439999999999990'), extraParams: { from: bob, value: toBN('18311039310716208939') } })
      let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
      let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
      let _oldPrice = await priceFeed.getPrice();
      console.log('cdpCollateral=' + (await cdpManager.getSyncedCdpCollShares(_bobCdpId)));
      console.log('cdpDebt=' + (await cdpManager.getSyncedCdpDebt(_bobCdpId)));
	  
      // shuffle a bit for the share rate to trigger liquidation since ICR < LICR
      await collToken.setEthPerShare(toBN("827268193736210321"));
      let _icr = await cdpManager.getSyncedICR(_bobCdpId, _oldPrice);
      assert.isTrue(_icr.lt(LICR));
      let _tcr = await cdpManager.getSyncedTCR(_oldPrice);
      assert.isTrue(_tcr.lt(_CCR));
	  
      // full liquidation should leave bad debt and zero collateral for this CDP
      let _surplusBalBefore = await collSurplusPool.getSurplusCollShares(bob);
      let _redistributedIndexBefore = await cdpManager.systemDebtRedistributionIndex();
      await cdpManager.liquidate(_bobCdpId, {from: alice});
      let _surplusBalAfter = await collSurplusPool.getSurplusCollShares(bob);
      let _redistributedIndexAfter = await cdpManager.systemDebtRedistributionIndex();
      assert.isTrue(_surplusBalBefore.eq(_surplusBalAfter));
      assert.isTrue(_redistributedIndexAfter.gt(_redistributedIndexBefore));
  })
  
})