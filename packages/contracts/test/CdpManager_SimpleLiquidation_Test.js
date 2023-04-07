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

  const openCdp = async (params) => th.openCdp(contracts, params)

  beforeEach(async () => {
    contracts = await deploymentHelper.deployLiquityCore()
    contracts.cdpManager = await CdpManagerTester.new()
    contracts.ebtcToken = await EBTCToken.new(
      contracts.cdpManager.address,
      contracts.borrowerOperations.address,
      contracts.authority.address
    )
    const LQTYContracts = await deploymentHelper.deployLQTYContracts(bountyAddress, lpRewardsAddress, multisig)

    cdpManager = contracts.cdpManager
    priceFeed = contracts.priceFeedTestnet
    sortedCdps = contracts.sortedCdps
    debtToken = contracts.ebtcToken;
    activePool = contracts.activePool;
    defaultPool = contracts.defaultPool;
    minDebt = await contracts.borrowerOperations.MIN_NET_DEBT();	
    _MCR = await cdpManager.MCR();
    LICR = await cdpManager.LICR();
    borrowerOperations = contracts.borrowerOperations;
    collSurplusPool = contracts.collSurplusPool;
    collToken = contracts.collateral;

    await deploymentHelper.connectCoreContracts(contracts, LQTYContracts)
    await deploymentHelper.connectLQTYContractsToCore(LQTYContracts, contracts)
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
      let _aliceICR = await cdpManager.getCurrentICR(_aliceCdpId, (await priceFeed.getPrice()));
      assert.isTrue(_aliceICR.gt(_MCR));
      await assertRevert(cdpManager.liquidate(_aliceCdpId, {from: bob}), "!_ICR");
      await assertRevert(cdpManager.partiallyLiquidate(_aliceCdpId, 123, _aliceCdpId, _aliceCdpId, {from: bob}), "!_ICR");  
	  
      // recovery mode	  
      let _newPrice = dec(2400, 13);
      await priceFeed.setPrice(_newPrice);
      assert.isTrue((await cdpManager.checkRecoveryMode(_newPrice)));
      await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: alice});
      await contracts.collateral.deposit({from: alice, value: dec(100, 'ether')});
      await borrowerOperations.addColl(_aliceCdpId, _aliceCdpId, _aliceCdpId, dec(100, 'ether'), { from: alice, value: 0 })
      _aliceICR = await cdpManager.getCurrentICR(_aliceCdpId, _newPrice);
      let _TCR = await cdpManager.getTCR(_newPrice);
      assert.isTrue(_aliceICR.gt(_TCR));
      await assertRevert(cdpManager.liquidate(_aliceCdpId, {from: bob}), "!_ICR");
      await assertRevert(cdpManager.partiallyLiquidate(_aliceCdpId, 123, _aliceCdpId, _aliceCdpId, {from: bob}), "!_ICR");	  
  })
  
  it("Liquidator should prepare enough asset for repayment", async () => {
      let {tx: opAliceTx} = await openCdp({ ICR: toBN(dec(299, 16)), extraParams: { from: alice } })
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
      let _colDeposited = await cdpManager.getCdpColl(_aliceCdpId);
	  
      // price slump
      let _newPrice = dec(2400, 13);
      await priceFeed.setPrice(_newPrice);
	  
      // liquidator bob coming in 
      await debtToken.transfer(bob, (await debtToken.balanceOf(alice)), {from: alice});	  
      let _debtLiquidatorPre = await debtToken.balanceOf(bob);  
      let _debtSystemPre = await cdpManager.getEntireSystemDebt();
      let _colSystemPre = await cdpManager.getEntireSystemColl();
      let _ethLiquidatorPre = await web3.eth.getBalance(bob);
      let _collLiquidatorPre = await collToken.balanceOf(bob);	 	  
      let _debtInActivePoolPre = await activePool.getEBTCDebt();
      let _collInActivePoolPre = await activePool.getETH();
      const tx = await cdpManager.liquidate(_aliceCdpId, {from: bob})	  
      let _debtLiquidatorPost = await debtToken.balanceOf(bob);
      let _debtSystemPost = await cdpManager.getEntireSystemDebt();
      let _colSystemPost = await cdpManager.getEntireSystemColl();
      let _ethLiquidatorPost = await web3.eth.getBalance(bob);
      let _collLiquidatorPost = await collToken.balanceOf(bob);	  
      let _debtInActivePoolPost = await activePool.getEBTCDebt();
      let _collInActivePoolPost = await activePool.getETH();

      // check CdpLiquidated event
      const liquidationEvents = th.getAllEventsByName(tx, 'CdpLiquidated')
      assert.equal(liquidationEvents.length, 1, '!CdpLiquidated event')
      assert.equal(liquidationEvents[0].args[0], _aliceCdpId, '!liquidated CDP ID');
      assert.equal(liquidationEvents[0].args[1], alice, '!liquidated CDP owner');
      assert.equal(liquidationEvents[0].args[2].toString(), _debtBorrowed.toString(), '!liquidated CDP debt');
      assert.equal(liquidationEvents[0].args[3].toString(), _colDeposited.toString(), '!liquidated CDP collateral');
	  
      // check liquidator balance change
      let _gasUsed = th.gasUsed(tx);
      let _debtDecreased = toBN(_debtLiquidatorPre.toString()).sub(toBN(_debtLiquidatorPost.toString()));
      assert.equal(_debtDecreased.toString(), _debtBorrowed.toString(), '!liquidator debt balance');		  
      const gasUsedETH = toBN(tx.receipt.effectiveGasPrice.toString()).mul(toBN(_gasUsed.toString()));
      let _ethSeizedByLiquidator = toBN(_collLiquidatorPost.toString()).sub(toBN(_collLiquidatorPre.toString()));//.add(gasUsedETH);
      assert.equal(_ethSeizedByLiquidator.toString(), _colDeposited.toString(), '!liquidator collateral balance');	 
	  
      // check system balance change
      let _debtDecreasedSystem = toBN(_debtSystemPre.toString()).sub(toBN(_debtSystemPost.toString()));
      assert.equal(_debtDecreasedSystem.toString(), _debtBorrowed.toString(), '!system debt balance');	
      let _colDecreasedSystem = toBN(_colSystemPre.toString()).sub(toBN(_colSystemPost.toString())); 
      assert.equal(_colDecreasedSystem.toString(), _colDeposited.toString(), '!system collateral balance');	
      let _debtDecreasedActivePool = toBN(_debtInActivePoolPre.toString()).sub(toBN(_debtInActivePoolPost.toString())); 
      assert.equal(_debtDecreasedActivePool.toString(), _debtBorrowed.toString(), '!activePool debt balance');
      let _colDecreasedActivePool = toBN(_collInActivePoolPre.toString()).sub(toBN(_collInActivePoolPost.toString())); 
      assert.equal(_colDecreasedActivePool.toString(), _colDeposited.toString(), '!activePool collateral balance');

      // Confirm target CDPs removed
      assert.isFalse(await sortedCdps.contains(_aliceCdpId))

      // Confirm removed CDP have status 'closed by liquidation' (Status enum element idx 3)
      assert.equal((await cdpManager.Cdps(_aliceCdpId))[3], '3')
  })
  
  it("Should allow non-EOA liquidator", async () => {
      let {tx: opAliceTx} = await openCdp({ ICR: toBN(dec(299, 16)), extraParams: { from: alice } })
      await openCdp({ ICR: toBN(dec(299, 16)), extraParams: { from: bob } })
      let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
      assert.isTrue(await sortedCdps.contains(_aliceCdpId));
      let _debtBorrowed = await cdpManager.getCdpDebt(_aliceCdpId);
      let _colDeposited = await cdpManager.getCdpColl(_aliceCdpId);
	  
      // price slump
      let _newPrice = dec(2400, 13);
      await priceFeed.setPrice(_newPrice);
	  
      // non-EOA liquidator coming in	
      const simpleLiquidationTester = await SimpleLiquidationTester.new();
      await simpleLiquidationTester.setCdpManager(cdpManager.address);
	
      await debtToken.transfer(simpleLiquidationTester.address, (await debtToken.balanceOf(alice)), {from: alice});	  
      await debtToken.transfer(simpleLiquidationTester.address, (await debtToken.balanceOf(bob)), {from: bob});	 
      let _debtLiquidatorPre = await debtToken.balanceOf(simpleLiquidationTester.address);  
      let _debtSystemPre = await cdpManager.getEntireSystemDebt();
      let _colSystemPre = await cdpManager.getEntireSystemColl();
      let _ethLiquidatorPre = await web3.eth.getBalance(simpleLiquidationTester.address);
      let _collLiquidatorPre = await collToken.balanceOf(simpleLiquidationTester.address); 	  
      let _debtInActivePoolPre = await activePool.getEBTCDebt();
      let _collInActivePoolPre = await activePool.getETH();
      const tx = await simpleLiquidationTester.liquidateCdp(_aliceCdpId, {from: owner});	  
      let _debtLiquidatorPost = await debtToken.balanceOf(simpleLiquidationTester.address);
      let _debtSystemPost = await cdpManager.getEntireSystemDebt();
      let _colSystemPost = await cdpManager.getEntireSystemColl();
      let _ethLiquidatorPost = await web3.eth.getBalance(simpleLiquidationTester.address);	
      let _collLiquidatorPost = await collToken.balanceOf(simpleLiquidationTester.address);  
      let _debtInActivePoolPost = await activePool.getEBTCDebt();
      let _collInActivePoolPost = await activePool.getETH();
	  
      // check EtherReceived event
//      const seizedEtherEvents = th.getAllEventsByName(tx, 'EtherReceived')
//      assert.equal(seizedEtherEvents.length, 1, '!EtherReceived event')
//      assert.equal(seizedEtherEvents[0].args[0], (await cdpManager.activePool()), '!Ether from Active Pool');
//      assert.equal(seizedEtherEvents[0].args[1].toString(), _colDeposited.toString(), '!liquidated CDP collateral');
	  
      // check liquidator balance change
      let _debtDecreased = toBN(_debtLiquidatorPre.toString()).sub(toBN(_debtLiquidatorPost.toString()));
      assert.equal(_debtDecreased.toString(), _debtBorrowed.toString(), '!liquidator debt balance');		
      let _ethSeizedByLiquidator = toBN(_collLiquidatorPost.toString()).sub(toBN(_collLiquidatorPre.toString()));
      assert.equal(_ethSeizedByLiquidator.toString(), _colDeposited.toString(), '!liquidator collateral balance');	 
	  
      // check system balance change
      let _debtDecreasedSystem = toBN(_debtSystemPre.toString()).sub(toBN(_debtSystemPost.toString()));
      assert.equal(_debtDecreasedSystem.toString(), _debtBorrowed.toString(), '!system debt balance');	
      let _colDecreasedSystem = toBN(_colSystemPre.toString()).sub(toBN(_colSystemPost.toString())); 
      assert.equal(_colDecreasedSystem.toString(), _colDeposited.toString(), '!system collateral balance');	
      let _debtDecreasedActivePool = toBN(_debtInActivePoolPre.toString()).sub(toBN(_debtInActivePoolPost.toString())); 
      assert.equal(_debtDecreasedActivePool.toString(), _debtBorrowed.toString(), '!activePool debt balance');
      let _colDecreasedActivePool = toBN(_collInActivePoolPre.toString()).sub(toBN(_collInActivePoolPost.toString())); 
      assert.equal(_colDecreasedActivePool.toString(), _colDeposited.toString(), '!activePool collateral balance');

      // Confirm target CDPs removed
      assert.isFalse(await sortedCdps.contains(_aliceCdpId))

      // Confirm removed CDP have status 'closed by liquidation' (Status enum element idx 3)
      assert.equal((await cdpManager.Cdps(_aliceCdpId))[3], '3')
  })  
  
  // with collateral token, there is no hook for liquidator to use 
  xit("Should allow non-EOA liquidator to reenter liquidate(bytes32) if everything adds-up", async () => {
      let {tx: opAliceTx} = await openCdp({ ICR: toBN(dec(299, 16)), extraParams: { from: alice } })
      await openCdp({ ICR: toBN(dec(299, 16)), extraParams: { from: bob } })
      let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
      let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
      assert.isTrue(await sortedCdps.contains(_aliceCdpId));
      assert.isTrue(await sortedCdps.contains(_bobCdpId));
      let _aliceColl = await cdpManager.getCdpColl(_aliceCdpId);
      let _bobColl = await cdpManager.getCdpColl(_bobCdpId);	  
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
      let aliceCdpOwner = await sortedCdps.existCdpOwners(aliceCdpId);
      assert.isTrue(aliceCdpOwner == alice);

      // maniuplate price to liquidate alice
      let _newPrice = dec(800, 13);
      await priceFeed.setPrice(_newPrice);  
      assert.isTrue(await cdpManager.checkRecoveryMode(_newPrice));

      let aliceDebt = await cdpManager.getCdpDebt(aliceCdpId);
      let aliceColl = await cdpManager.getCdpColl(aliceCdpId);		  
      let prevDebtOfOwner = await debtToken.balanceOf(owner);
      assert.isTrue(toBN(prevDebtOfOwner.toString()).gt(toBN(aliceDebt.toString())));
	  
      // liquidate alice in recovery mode	  
      let prevETHOfOwner = await ethers.provider.getBalance(owner);
      let _collLiquidatorPre = await collToken.balanceOf(owner);
      let _TCR = await cdpManager.getTCR(_newPrice);
      let _aliceICR = await cdpManager.getCurrentICR(aliceCdpId, _newPrice);
      assert.isTrue(toBN(_aliceICR.toString()).lt(toBN(_TCR.toString())));
      assert.isTrue(toBN(_aliceICR.toString()).lt(toBN(_MCR.toString())));
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
      assert.equal(_liquidatedEvents[0].args[3].toString(), aliceColl.toString(), '!liquidated CDP collateral');
      assert.equal(_liquidatedEvents[0].args[4].toString(), '2', '!liquidateInRecoveryMode');// alice was liquidated in recovery mode
      let _gasEtherUsed = toBN(_liquidateRecoveryTx.receipt.effectiveGasPrice.toString()).mul(toBN((th.gasUsed(_liquidateRecoveryTx)).toString()));
      let _ethSeizedByLiquidator = toBN(_collLiquidatorPost.toString()).sub(toBN(_collLiquidatorPre.toString()));//.add(_gasEtherUsed);

      // owner get collateral from alice by repaying the debts
      assert.equal(toBN(prevDebtOfOwner.toString()).sub(toBN(postDebtOfOwner.toString())).toString(), toBN(aliceDebt.toString()).toString());
      assert.equal(_ethSeizedByLiquidator.toString(), toBN(aliceColl.toString()).toString());
  }) 
  
  it("liquidate(): liquidate a CDP in recovery mode with some surplus to claim", async () => {	
      await openCdp({ ICR: toBN(dec(299, 16)), extraParams: { from: bob } });	  
      let bobCdpId = await sortedCdps.getFirst();
      assert.isTrue(await sortedCdps.contains(bobCdpId));	
      await openCdp({ ICR: toBN(dec(299, 16)), extraParams: { from: carol } });	  
      let carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
      assert.isTrue(await sortedCdps.contains(carolCdpId));

      // mint Alice some EBTC
      await openCdp({ ICR: toBN(dec(245, 16)), extraParams: { from: alice } });	
      await debtToken.transfer(owner, (await debtToken.balanceOf(bob)), {from : bob});	
      await debtToken.transfer(owner, (await debtToken.balanceOf(carol)), {from : carol});  
      await debtToken.transfer(owner, (await debtToken.balanceOf(alice)), {from: alice});	  
      let aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
      let aliceCdpOwner = await sortedCdps.existCdpOwners(aliceCdpId);
      assert.isTrue(aliceCdpOwner == alice);

      // maniuplate price to liquidate alice
      let _newPrice = dec(3900, 13);
      await priceFeed.setPrice(_newPrice);  
      assert.isTrue(await cdpManager.checkRecoveryMode(_newPrice));

      let aliceDebt = await cdpManager.getCdpDebt(aliceCdpId);
      let aliceColl = await cdpManager.getCdpColl(aliceCdpId);		  
      let prevDebtOfOwner = await debtToken.balanceOf(owner);
      assert.isTrue(toBN(prevDebtOfOwner.toString()).gt(toBN(aliceDebt.toString())));
	  
      // liquidate alice in recovery mode	  
      let prevETHOfOwner = await ethers.provider.getBalance(owner);	
      let _collLiquidatorPre = await collToken.balanceOf(owner);
      let _TCR = await cdpManager.getTCR(_newPrice);
      let _aliceICR = await cdpManager.getCurrentICR(aliceCdpId, _newPrice);
      assert.isTrue(toBN(_aliceICR.toString()).lt(toBN(_TCR.toString())));
      assert.isTrue(toBN(_aliceICR.toString()).gt(toBN(_MCR.toString())));
      let _cappedLiqColl = toBN(aliceDebt.toString()).mul(toBN(dec(105, 16))).div(toBN(_newPrice)).add(mv._LIQUIDATION_REWARD);
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
      assert.equal(_liquidatedEvents[0].args[4].toString(), '2', '!liquidateInRecoveryMode');// alice was liquidated in recovery mode
      let _gasEtherUsed = toBN(_liquidateRecoveryTx.receipt.effectiveGasPrice.toString()).mul(toBN((th.gasUsed(_liquidateRecoveryTx)).toString()));
      let _ethSeizedByLiquidator = toBN(_collLiquidatorPost.toString()).sub(toBN(_collLiquidatorPre.toString()));//.add(_gasEtherUsed);
      let _expectClaimSurplus = toBN(aliceColl.toString()).sub(_cappedLiqColl);
      let _toClaimSurplus = await collSurplusPool.getCollateral(alice);
      assert.isTrue(toBN(_toClaimSurplus.toString()).gt(toBN('0')));
      assert.equal(_toClaimSurplus.toString(), _expectClaimSurplus.toString());

      // owner get collateral from alice by repaying the debts
      assert.equal(toBN(prevDebtOfOwner.toString()).sub(toBN(postDebtOfOwner.toString())).toString(), toBN(aliceDebt.toString()).toString());
      assert.equal(_ethSeizedByLiquidator.toString(), toBN(aliceColl.toString()).sub(toBN(_toClaimSurplus.toString())).toString());
	  
      // alice could claim whatever surplus is
      let prevETHOfAlice = await ethers.provider.getBalance(alice);	
      let _collClaimatorPre = await collToken.balanceOf(alice);
      let _claimTx = await borrowerOperations.claimCollateral({ from: alice});	
      let postETHOfAlice = await ethers.provider.getBalance(alice);
      let _collClaimatorPost = await collToken.balanceOf(alice);
      let _gasEtherUsedClaim = toBN(_claimTx.receipt.effectiveGasPrice.toString()).mul(toBN((th.gasUsed(_claimTx)).toString()));
      let _ethClaimed = toBN(_collClaimatorPost.toString()).sub(toBN(_collClaimatorPre.toString()));//.add(_gasEtherUsedClaim);
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
      let _bobICR = await cdpManager.getCurrentICR(_bobCdpId, _newPrice);
      assert.isTrue(toBN(_bobICR.toString()).lt(LICR));
      let _colRatio = _bobICR;	 
	  
      await debtToken.transfer(alice, (await debtToken.balanceOf(bob)), {from: bob});
      // liquidator alice coming in firstly partially liquidate some portion(0.5 EBTC) of bob 
      let _partialAmount = toBN("500000000000000000"); // 0.5e18
      let _debtFirstPre = await cdpManager.getCdpDebt(_bobCdpId);
      let _collFirstPre = await cdpManager.getCdpColl(_bobCdpId);
      let _debtInLiquidatorPre = await debtToken.balanceOf(alice);
      let _ethLiquidatorPre = await web3.eth.getBalance(alice);		
      let _collLiquidatorPre = await collToken.balanceOf(alice); 	  
      let _liqTx = await cdpManager.partiallyLiquidate(_bobCdpId, _partialAmount, _bobCdpId, _bobCdpId, {from: alice});
      let _ethLiquidatorPost = await web3.eth.getBalance(alice);	
      let _collLiquidatorPost = await collToken.balanceOf(alice);	
      let _collFirstPost = await cdpManager.getCdpColl(_bobCdpId);  	  	  
      const gasUsedETH = toBN(_liqTx.receipt.effectiveGasPrice.toString()).mul(toBN(th.gasUsed(_liqTx).toString()));
      let _ethSeizedByLiquidator = toBN(_collLiquidatorPost.toString()).sub(toBN(_collLiquidatorPre.toString()));//.add(gasUsedETH);
      let _debtFirstPost = await cdpManager.getCdpDebt(_bobCdpId);
      let _debtInLiquidatorPost = await debtToken.balanceOf(alice);
      let _debtDecreased = toBN(_debtFirstPre.toString()).sub(toBN(_debtFirstPost.toString()));
      let _debtInLiquidatorDecreased = toBN(_debtInLiquidatorPre.toString()).sub(toBN(_debtInLiquidatorPost.toString()));
      let _collDecreased = toBN(_collFirstPre.toString()).sub(toBN(_collFirstPost.toString()));
      
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
      let _newPrice = dec(2400, 13);
      await priceFeed.setPrice(_newPrice);
	  
      // FIXME get some pending rewards for remaining CDP
      await cdpManager.liquidateCdps(1, {from: owner});
      assert.isFalse(await sortedCdps.contains(_ownerCdpId));
      let _rewardETH = await cdpManager.getPendingETHReward(_aliceCdpId);
      assert.isTrue(toBN(_rewardETH.toString()).gt(toBN('0')));
      let _rewardEBTCDebt = await cdpManager.getPendingEBTCDebtReward(_aliceCdpId);
      assert.isTrue(toBN(_rewardEBTCDebt[0].toString()).gt(toBN('0')));	
	  
      // liquidator bob coming in firstly partially liquidate some portion(0.1 EBTC) of alice
      let _partialAmount = toBN("100000000000000000"); // 0.1e18
      let _icr = await cdpManager.getCurrentICR(_aliceCdpId, _newPrice);

      assert.isTrue(toBN(_icr.toString()).lt(_MCR));
      assert.isTrue(toBN(_icr.toString()).gt(LICR));
      let _colRatio = LICR;	 
	  
      let _debtLiquidated = _partialAmount;
      let _collLiquidated = _debtLiquidated.mul(_colRatio).div(toBN(_newPrice));
	  
      // liquidator bob coming in 
      await debtToken.transfer(bob, (await debtToken.balanceOf(alice)), {from: alice});	  
      let _debtLiquidatorPre = await debtToken.balanceOf(bob);  
      let _debtSystemPre = await cdpManager.getEntireSystemDebt();
      let _colSystemPre = await cdpManager.getEntireSystemColl();
      let _ethLiquidatorPre = await web3.eth.getBalance(bob);	
      let _collLiquidatorPre = await collToken.balanceOf(bob);	  
      let _debtInAllPoolPre = toBN((await activePool.getEBTCDebt()).toString()).add(toBN((await defaultPool.getEBTCDebt()).toString()));
      let _collInAllPoolPre = toBN((await activePool.getETH()).toString()).add(toBN((await defaultPool.getETH()).toString()));
      const tx = await cdpManager.partiallyLiquidate(_aliceCdpId, _partialAmount, _aliceCdpId, _aliceCdpId, {from: bob}) 
      let _collRemaining = await cdpManager.getCdpColl(_aliceCdpId); 
      let _stakeRemaining = await cdpManager.getCdpStake(_aliceCdpId);
      let _debtRemaining = await cdpManager.getCdpDebt(_aliceCdpId);
      let _debtInAllPoolPost = toBN((await activePool.getEBTCDebt()).toString()).add(toBN((await defaultPool.getEBTCDebt()).toString()));
      let _collInAllPoolPost = toBN((await activePool.getETH()).toString()).add(toBN((await defaultPool.getETH()).toString()));
      let _additionalCol = dec(1, 'ether');
      await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: alice});
      await contracts.collateral.deposit({from: alice, value: _additionalCol});
      await borrowerOperations.addColl(_aliceCdpId, _aliceCdpId, _aliceCdpId, _additionalCol, { from: alice, value: 0 }); //apply pending rewards	  
      let _debtLiquidatorPost = await debtToken.balanceOf(bob);
      let _debtSystemPost = await cdpManager.getEntireSystemDebt();
      let _colSystemPost = await cdpManager.getEntireSystemColl();
      let _ethLiquidatorPost = await web3.eth.getBalance(bob);	
      let _collLiquidatorPost = await collToken.balanceOf(bob);

      // check CdpUpdated event
      const troveUpdatedEvents = th.getAllEventsByName(tx, 'CdpUpdated')
      assert.equal(troveUpdatedEvents.length, 1, '!CdpUpdated event')
      assert.equal(troveUpdatedEvents[0].args[0], _aliceCdpId, '!partially liquidated CDP ID');
      assert.equal(troveUpdatedEvents[0].args[1], alice, '!partially liquidated CDP owner');
      assert.equal(troveUpdatedEvents[0].args[2].toString(), _debtRemaining.toString(), '!partially liquidated CDP remaining debt');
      assert.equal(troveUpdatedEvents[0].args[3].toString(), _collRemaining.toString(), '!partially liquidated CDP remaining collateral');
      assert.equal(troveUpdatedEvents[0].args[4].toString(), _stakeRemaining.toString(), '!partially liquidated CDP remaining stake');
      assert.equal(troveUpdatedEvents[0].args[5], 4, '!CdpManagerOperation.partiallyLiquidate');

      // check CdpPartiallyLiquidated event
      const liquidationEvents = th.getAllEventsByName(tx, 'CdpPartiallyLiquidated')
      assert.equal(liquidationEvents.length, 1, '!CdpPartiallyLiquidated event')
      assert.equal(liquidationEvents[0].args[0], _aliceCdpId, '!partially liquidated CDP ID');
      assert.equal(liquidationEvents[0].args[1], alice, '!partially liquidated CDP owner');
      assert.equal(liquidationEvents[0].args[2].toString(), _debtLiquidated.toString(), '!partially liquidated CDP debt');
      assert.equal(liquidationEvents[0].args[3].toString(), _collLiquidated.toString(), '!partially liquidated CDP collateral');
      assert.equal(liquidationEvents[0].args[4], 4, '!CdpManagerOperation.partiallyLiquidate');
	  
      // check liquidator balance change
      let _gasUsed = th.gasUsed(tx);
      let _debtDecreased = toBN(_debtLiquidatorPre.toString()).sub(toBN(_debtLiquidatorPost.toString()));
      assert.equal(_debtDecreased.toString(), _debtLiquidated.toString(), '!liquidator debt balance');		  
      const gasUsedETH = toBN(tx.receipt.effectiveGasPrice.toString()).mul(toBN(_gasUsed.toString()));
      let _ethSeizedByLiquidator = toBN(_collLiquidatorPost.toString()).sub(toBN(_collLiquidatorPre.toString()));//.add(gasUsedETH);
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
      assert.equal((await cdpManager.Cdps(_aliceCdpId))[3], '1')
	  
      // Confirm partially liquidated CDP got higher or at least equal ICR than before
      let _aliceNewICR = await cdpManager.getCurrentICR(_aliceCdpId, _newPrice);
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
      let _colDeposited = await cdpManager.getCdpColl(_aliceCdpId);
	  
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
      let _debtSystemPre = await cdpManager.getEntireSystemDebt();
      let _colSystemPre = await cdpManager.getEntireSystemColl();
      let _ethLiquidatorPre = await web3.eth.getBalance(bob);	
      let _collLiquidatorPre = await collToken.balanceOf(bob);	  
      let _debtInActivePoolPre = await activePool.getEBTCDebt();
      let _collInActivePoolPre = await activePool.getETH();
	  
      for(let i = 0;i < _partialLiquidations;i++){
          if(i < _partialLiquidations - 1){
             const tx = await cdpManager.partiallyLiquidate(_aliceCdpId, _partialAmounts[i], _aliceCdpId, _aliceCdpId, {from: bob})
             _partialLiquidationTxs.push(tx);			  
          }else{			 
             // pass 0 for partialLiquidate equals to full liquidation
             const finalTx = await cdpManager.partiallyLiquidate(_aliceCdpId, 0, _aliceCdpId, _aliceCdpId, {from: bob})
             _partialLiquidationTxs.push(finalTx);
          }			  
      } 
      
      let _debtLiquidatorPost = await debtToken.balanceOf(bob);
      let _debtSystemPost = await cdpManager.getEntireSystemDebt();
      let _colSystemPost = await cdpManager.getEntireSystemColl();
      let _ethLiquidatorPost = await web3.eth.getBalance(bob);	  
      let _collLiquidatorPost = await collToken.balanceOf(bob);	
      let _debtInActivePoolPost = await activePool.getEBTCDebt();
      let _collInActivePoolPost = await activePool.getETH();
	  
      // check liquidator balance change
      let _debtDecreased = toBN(_debtLiquidatorPre.toString()).sub(toBN(_debtLiquidatorPost.toString()));
      assert.equal(_debtDecreased.toString(), _debtBorrowed.toString(), '!liquidator debt balance');
      let gasUsedETH = toBN('0');
      for(let i = 0;i < _partialLiquidations;i++){
          let _gasUsed = toBN(th.gasUsed(_partialLiquidationTxs[i]).toString());	
          gasUsedETH = gasUsedETH.add(toBN(_partialLiquidationTxs[i].receipt.effectiveGasPrice.toString()).mul(toBN(_gasUsed.toString())));	  		  
      }
      let _ethSeizedByLiquidator = toBN(_collLiquidatorPost.toString()).sub(toBN(_collLiquidatorPre.toString()));//.add(gasUsedETH);
      assert.equal(_ethSeizedByLiquidator.toString(), _colDeposited.toString(), '!liquidator collateral balance');	 
	  
      // check system balance change
      let _debtDecreasedSystem = toBN(_debtSystemPre.toString()).sub(toBN(_debtSystemPost.toString()));
      assert.equal(_debtDecreasedSystem.toString(), _debtBorrowed.toString(), '!system debt balance');	
      let _colDecreasedSystem = toBN(_colSystemPre.toString()).sub(toBN(_colSystemPost.toString())); 
      assert.equal(_colDecreasedSystem.toString(), _colDeposited.toString(), '!system collateral balance');	
      let _debtDecreasedActivePool = toBN(_debtInActivePoolPre.toString()).sub(toBN(_debtInActivePoolPost.toString())); 
      assert.equal(_debtDecreasedActivePool.toString(), _debtBorrowed.toString(), '!activePool debt balance');
      let _colDecreasedActivePool = toBN(_collInActivePoolPre.toString()).sub(toBN(_collInActivePoolPost.toString())); 
      assert.equal(_colDecreasedActivePool.toString(), _colDeposited.toString(), '!activePool collateral balance');

      // Confirm all CDPs removed
      assert.isFalse(await sortedCdps.contains(_aliceCdpId))

      // Confirm CDPs have status 'closed by liquidation' (Status enum element idx 3)
      assert.equal((await cdpManager.Cdps(_aliceCdpId))[3], '3')
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
      await assertRevert(cdpManager.partiallyLiquidate(_aliceCdpId, _debtBorrowed, _aliceCdpId, _aliceCdpId, {from: bob}), "!maxDebtByPartialLiq"); 
  })
  
})