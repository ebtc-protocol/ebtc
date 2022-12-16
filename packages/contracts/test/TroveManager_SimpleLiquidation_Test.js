const deploymentHelper = require("../utils/deploymentHelpers.js")
const { TestHelper: th, MoneyValues: mv } = require("../utils/testHelpers.js")
const { toBN, dec, ZERO_ADDRESS } = th

const TroveManagerTester = artifacts.require("./TroveManagerTester")
const LUSDToken = artifacts.require("./LUSDToken.sol")
const SimpleLiquidationTester = artifacts.require("./SimpleLiquidationTester.sol");

const assertRevert = th.assertRevert

contract('TroveManager - Simple Liquidation without Stability Pool', async accounts => {
  const [bountyAddress, lpRewardsAddress, multisig] = accounts.slice(accounts.length - 3, accounts.length)
  const [
    owner,
    alice, bob, carol, dennis, erin, freddy, greta, harry, ida,
    whale, defaulter_1, defaulter_2, defaulter_3, defaulter_4,
    A, B, C, D, E, F, G, H, I
  ] = accounts;

  let contracts
  let troveManager
  let stabilityPool
  let priceFeed
  let sortedTroves

  const openTrove = async (params) => th.openTrove(contracts, params)

  beforeEach(async () => {
    contracts = await deploymentHelper.deployLiquityCore()
    contracts.troveManager = await TroveManagerTester.new()
    contracts.lusdToken = await LUSDToken.new(
      contracts.troveManager.address,
      contracts.stabilityPool.address,
      contracts.borrowerOperations.address
    )
    const LQTYContracts = await deploymentHelper.deployLQTYContracts(bountyAddress, lpRewardsAddress, multisig)

    troveManager = contracts.troveManager
    stabilityPool = contracts.stabilityPool
    priceFeed = contracts.priceFeedTestnet
    sortedTroves = contracts.sortedTroves
    debtToken = contracts.lusdToken;
    activePool = contracts.activePool;
    minDebt = await contracts.borrowerOperations.MIN_NET_DEBT();
    borrowerOperations = contracts.borrowerOperations;

    await deploymentHelper.connectLQTYContracts(LQTYContracts)
    await deploymentHelper.connectCoreContracts(contracts, LQTYContracts)
    await deploymentHelper.connectLQTYContractsToCore(LQTYContracts, contracts)
  })
  
  it("Trove needs to be active to be liquidated", async() => {	  
      await assertRevert(troveManager.liquidate(th.DUMMY_BYTES32, {from: bob}), "TroveManager: Trove does not exist or is closed");  
  })
  
  it("Trove ICR needs to be below MCR to be liquidated", async () => {
      await openTrove({ ICR: toBN(dec(299, 16)), extraParams: { from: alice } })
      let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);	  
      await assertRevert(troveManager.liquidate(_aliceTroveId, {from: bob}), "ICR>MCR");
  })
  
  it("Partially Liquidation ICR needs to be below MCR or TCR in recovery mode", async () => {
      await openTrove({ ICR: toBN(dec(299, 16)), extraParams: { from: alice } })
      let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);	  
      await assertRevert(troveManager.partiallyLiquidate(_aliceTroveId, 101, _aliceTroveId, _aliceTroveId, {from: bob}), "!partiallyICR");
      assert.isFalse(await troveManager.checkRecoveryMode(await priceFeed.getPrice()));
	  	  
      let _newPrice = dec(95, 18);
      await priceFeed.setPrice(_newPrice);
      assert.isTrue(await troveManager.checkRecoveryMode(_newPrice)); 
      await assertRevert(troveManager.partiallyLiquidate(_aliceTroveId, 101, _aliceTroveId, _aliceTroveId, {from: bob}), "!partiallyICR");	  
  })
  
  it("Partially Liquidation Ratio needs to be below max(million)", async () => {
      await openTrove({ ICR: toBN(dec(299, 16)), extraParams: { from: alice } })
      let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);	  
      await assertRevert(troveManager.partiallyLiquidate(_aliceTroveId, 1000001, _aliceTroveId, _aliceTroveId, {from: bob}), "!partialLiqMax");
  })
  
  it("Partially Liquidation needs to leave Trove with big enough debt if not closed completely", async () => {
      await openTrove({ ICR: toBN(dec(299, 16)), extraParams: { from: alice } })
      let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);	  
      await assertRevert(troveManager.partiallyLiquidate(_aliceTroveId, 987654, _aliceTroveId, _aliceTroveId, {from: bob}), "!minDebtLeftByPartiallyLiq");
  })
  
  it("Liquidator should prepare enough asset for repayment", async () => {
      let {tx: opAliceTx} = await openTrove({ ICR: toBN(dec(299, 16)), extraParams: { from: alice } })
      await openTrove({ ICR: toBN(dec(199, 16)), extraParams: { from: bob } })
      let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
      assert.isTrue(await sortedTroves.contains(_aliceTroveId));
	  
      // price slump by 70%
      let _newPrice = dec(60, 18);
      await priceFeed.setPrice(_newPrice);
	  
      // liquidator bob coming in 
      await assertRevert(troveManager.liquidate(_aliceTroveId, {from: bob}), 'ERC20: burn amount exceeds balance');
      assert.isTrue(await sortedTroves.contains(_aliceTroveId));
  })
  
  it("Liquidator should prepare enough asset for repayment even partially", async () => {
      let {tx: opAliceTx} = await openTrove({ ICR: toBN(dec(299, 16)), extraLUSDAmount: toBN(minDebt.toString()).add(toBN(1)), extraParams: { from: alice } })
      await openTrove({ ICR: toBN(dec(199, 16)), extraParams: { from: bob } })
      let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
      assert.isTrue(await sortedTroves.contains(_aliceTroveId));
	  
      // price slump by 70%
      let _newPrice = dec(60, 18);
      await priceFeed.setPrice(_newPrice);
	  
      // liquidator bob coming in firstly partially liquidate some portion of alice
      let _debtFirstPre = await troveManager.getTroveDebt(_aliceTroveId);
      let _debtInLiquidatorPre = await debtToken.balanceOf(bob);
      await troveManager.partiallyLiquidate(_aliceTroveId, toBN("150000"), _aliceTroveId, _aliceTroveId, {from: bob});
      let _debtFirstPost = await troveManager.getTroveDebt(_aliceTroveId);
      let _debtInLiquidatorPost = await debtToken.balanceOf(bob);
      let _debtDecreased = toBN(_debtFirstPre.toString()).sub(toBN(_debtFirstPost.toString()));
      let _debtInLiquidatorDecreased = toBN(_debtInLiquidatorPre.toString()).sub(toBN(_debtInLiquidatorPost.toString()));
      assert.equal(_debtDecreased.toString(), _debtInLiquidatorDecreased.toString(), '!partially liquidation debt change');	  
	  
      // then continue liquidation partially but failed due to not enough debt asset in hand
      let _debtPre = await troveManager.getTroveDebt(_aliceTroveId);
      await assertRevert(troveManager.partiallyLiquidate(_aliceTroveId, toBN("500000"), _aliceTroveId, _aliceTroveId, {from: bob}), 'ERC20: burn amount exceeds balance');
      let _debtPost = await troveManager.getTroveDebt(_aliceTroveId);
      assert.equal(_debtPre.toString(), _debtPost.toString(), '!partially liquidation revert');
  })
  
  it("Liquidation should spare the last CDP", async () => {
      await openTrove({ ICR: toBN(dec(299, 16)), extraParams: { from: alice } })
      let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);	  
      // price slump by 70%
      let _newPrice = dec(60, 18);
      await priceFeed.setPrice(_newPrice);
      await assertRevert(troveManager.liquidate(_aliceTroveId, {from: alice}), "TroveManager: Only one trove in the system");
  })
  
  it("Troves below MCR will be liquidated", async () => {
      let {tx: opAliceTx} = await openTrove({ ICR: toBN(dec(299, 16)), extraParams: { from: alice } })
      await openTrove({ ICR: toBN(dec(299, 16)), extraParams: { from: bob } })
      let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
      assert.isTrue(await sortedTroves.contains(_aliceTroveId));
      let _debtBorrowed = await troveManager.getTroveDebt(_aliceTroveId);
      let _colDeposited = await troveManager.getTroveColl(_aliceTroveId);
	  
      // price slump by 70%
      let _newPrice = dec(60, 18);
      await priceFeed.setPrice(_newPrice);
	  
      // liquidator bob coming in 
      await debtToken.transfer(bob, (await debtToken.balanceOf(alice)), {from: alice});	  
      let _debtLiquidatorPre = await debtToken.balanceOf(bob);  
      let _debtSystemPre = await troveManager.getEntireSystemDebt();
      let _colSystemPre = await troveManager.getEntireSystemColl();
      let _ethLiquidatorPre = await web3.eth.getBalance(bob);	  
      let _debtInActivePoolPre = await activePool.getLUSDDebt();
      let _collInActivePoolPre = await activePool.getETH();
      const tx = await troveManager.liquidate(_aliceTroveId, {from: bob})	  
      let _debtLiquidatorPost = await debtToken.balanceOf(bob);
      let _debtSystemPost = await troveManager.getEntireSystemDebt();
      let _colSystemPost = await troveManager.getEntireSystemColl();
      let _ethLiquidatorPost = await web3.eth.getBalance(bob);	  
      let _debtInActivePoolPost = await activePool.getLUSDDebt();
      let _collInActivePoolPost = await activePool.getETH();

      // check TroveLiquidated event
      const liquidationEvents = th.getAllEventsByName(tx, 'TroveLiquidated')
      assert.equal(liquidationEvents.length, 1, '!TroveLiquidated event')
      assert.equal(liquidationEvents[0].args[0], _aliceTroveId, '!liquidated trove ID');
      assert.equal(liquidationEvents[0].args[1], alice, '!liquidated trove owner');
      assert.equal(liquidationEvents[0].args[2].toString(), _debtBorrowed.toString(), '!liquidated trove debt');
      assert.equal(liquidationEvents[0].args[3].toString(), _colDeposited.toString(), '!liquidated trove collateral');
	  
      // check liquidator balance change
      let _gasUsed = th.gasUsed(tx);
      let _debtDecreased = toBN(_debtLiquidatorPre.toString()).sub(toBN(_debtLiquidatorPost.toString()));
      assert.equal(_debtDecreased.toString(), _debtBorrowed.toString(), '!liquidator debt balance');		  
      const gasUsedETH = toBN(tx.receipt.effectiveGasPrice.toString()).mul(toBN(_gasUsed.toString()));
      let _ethSeizedByLiquidator = toBN(_ethLiquidatorPost.toString()).sub(toBN(_ethLiquidatorPre.toString())).add(gasUsedETH);
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

      // Confirm all troves removed
      assert.isFalse(await sortedTroves.contains(_aliceTroveId))

      // Confirm troves have status 'closed by liquidation' (Status enum element idx 3)
      assert.equal((await troveManager.Troves(_aliceTroveId))[3], '3')
  })
  
  it("Liquidator partially liquidate in recovery mode", async () => {
      let {tx: opAliceTx} = await openTrove({ ICR: toBN(dec(299, 16)), extraLUSDAmount: toBN(minDebt.toString()).add(toBN(1)), extraParams: { from: alice } })
      let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);	  
      await openTrove({ ICR: toBN(dec(179, 16)), extraLUSDAmount: toBN(dec(700, 18)), extraParams: { from: bob } })
      let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
      assert.isTrue(await sortedTroves.contains(_aliceTroveId));
	  
      await openTrove({ ICR: toBN(dec(169, 16)), extraParams: { from: carol } })
      let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);	  
      await openTrove({ ICR: toBN(dec(159, 16)), extraParams: { from: owner } })
      let _ownerTroveId = await sortedTroves.troveOfOwnerByIndex(owner, 0);
      assert.isFalse(await troveManager.checkRecoveryMode(await priceFeed.getPrice()));
	  
      // bob now sit second in sorted CDP list according to NICR
      let _firstId = await sortedTroves.getFirst();
      let _secondId = await sortedTroves.getNext(_firstId);
      assert.equal(_secondId, _bobTroveId);
      let _thirdId = await sortedTroves.getNext(_secondId);
      assert.equal(_thirdId, _carolTroveId);
      let _lastId = await sortedTroves.getLast();
      assert.equal(_lastId, _ownerTroveId);
	  
      // price slump to make system enter recovery mode
      let _newPrice = dec(130, 18);
      await priceFeed.setPrice(_newPrice);
      assert.isTrue(await troveManager.checkRecoveryMode(_newPrice));
      let _bobICR = await troveManager.getCurrentICR(_bobTroveId, _newPrice);
      let _MCR = toBN(dec(110,16));
      assert.isTrue(toBN(_bobICR.toString()).gt(_MCR));
	  
      // liquidator alice coming in firstly partially liquidate some portion of bob
      let _partialRatio = toBN("250000");
      let _debtFirstPre = await troveManager.getTroveDebt(_bobTroveId);
      let _collFirstPre = await troveManager.getTroveColl(_bobTroveId);
      let _debtInLiquidatorPre = await debtToken.balanceOf(alice);
      let _ethLiquidatorPre = await web3.eth.getBalance(alice);	  
      let _liqTx = await troveManager.partiallyLiquidate(_bobTroveId, _partialRatio, _bobTroveId, _bobTroveId, {from: alice});
      let _ethLiquidatorPost = await web3.eth.getBalance(alice);	
      let _collFirstPost = await troveManager.getTroveColl(_bobTroveId);  	  	  
      const gasUsedETH = toBN(_liqTx.receipt.effectiveGasPrice.toString()).mul(toBN(th.gasUsed(_liqTx).toString()));
      let _ethSeizedByLiquidator = toBN(_ethLiquidatorPost.toString()).sub(toBN(_ethLiquidatorPre.toString())).add(gasUsedETH);
      let _debtFirstPost = await troveManager.getTroveDebt(_bobTroveId);
      let _debtInLiquidatorPost = await debtToken.balanceOf(alice);
      let _debtDecreased = toBN(_debtFirstPre.toString()).sub(toBN(_debtFirstPost.toString()));
      let _debtInLiquidatorDecreased = toBN(_debtInLiquidatorPre.toString()).sub(toBN(_debtInLiquidatorPost.toString()));
      let _collDecreased = toBN(_collFirstPre.toString()).sub(toBN(_collFirstPost.toString()));
      
      // check debt change & calculation in receovery mode
      assert.equal(_debtDecreased.toString(), _debtInLiquidatorDecreased.toString(), '!partially liquidation debt change in liquidator');
      assert.equal(_debtDecreased.toString(), toBN(_debtFirstPre.toString()).mul(_partialRatio).div(toBN("1000000")).toString(), '!partially liquidation debt calculation');	
	  
      // check collateral change & calculation in receovery mode when ICR > MCR
      assert.equal(_collDecreased.toString(), _ethSeizedByLiquidator.toString(), '!partially liquidation collateral change in liquidator');
      assert.equal(_collDecreased.toString(), _debtDecreased.mul(_MCR).div(toBN(dec(100,16))).mul(toBN(dec(1, 18))).div(toBN(_newPrice)).toString());	 
  })
  
  it("Troves below MCR could be partially liquidated", async () => {
      let {tx: opAliceTx} = await openTrove({ ICR: toBN(dec(299, 16)), extraLUSDAmount: toBN(minDebt.toString()).add(toBN(1)), extraParams: { from: alice } })
      await openTrove({ ICR: toBN(dec(299, 16)), extraParams: { from: bob } })
      let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
      assert.isTrue(await sortedTroves.contains(_aliceTroveId));
      let _debtBorrowed = await troveManager.getTroveDebt(_aliceTroveId);
      let _colDeposited = await troveManager.getTroveColl(_aliceTroveId);
	  
      // price slump by 70%
      let _newPrice = dec(60, 18);
      await priceFeed.setPrice(_newPrice);
	  
      // only partially (1/4 = 250000 / 1000000) liquidate alice 
      let _partialRatio = toBN("250000");// max(full) is million  
      let _icr = await troveManager.getCurrentICR(_aliceTroveId, _newPrice);
      let _debtLiquidated = _partialRatio.mul(_debtBorrowed).div(toBN("1000000"));
      let _collLiquidated = _debtLiquidated.mul(_icr).div(toBN(_newPrice));
      let _debtRemaining = _debtBorrowed.sub(_debtLiquidated);
      let _collRemaining = _colDeposited.sub(_collLiquidated);
      let _stakeRemaining = _collRemaining;
	  
      // liquidator bob coming in 
      await debtToken.transfer(bob, (await debtToken.balanceOf(alice)), {from: alice});	  
      let _debtLiquidatorPre = await debtToken.balanceOf(bob);  
      let _debtSystemPre = await troveManager.getEntireSystemDebt();
      let _colSystemPre = await troveManager.getEntireSystemColl();
      let _ethLiquidatorPre = await web3.eth.getBalance(bob);	  
      let _debtInActivePoolPre = await activePool.getLUSDDebt();
      let _collInActivePoolPre = await activePool.getETH();
      const tx = await troveManager.partiallyLiquidate(_aliceTroveId, _partialRatio, _aliceTroveId, _aliceTroveId, {from: bob})	  
      let _debtLiquidatorPost = await debtToken.balanceOf(bob);
      let _debtSystemPost = await troveManager.getEntireSystemDebt();
      let _colSystemPost = await troveManager.getEntireSystemColl();
      let _ethLiquidatorPost = await web3.eth.getBalance(bob);	  
      let _debtInActivePoolPost = await activePool.getLUSDDebt();
      let _collInActivePoolPost = await activePool.getETH();	

      // check TroveUpdated event
      const troveUpdatedEvents = th.getAllEventsByName(tx, 'TroveUpdated')
      assert.equal(troveUpdatedEvents.length, 1, '!TroveUpdated event')
      assert.equal(troveUpdatedEvents[0].args[0], _aliceTroveId, '!partially liquidated trove ID');
      assert.equal(troveUpdatedEvents[0].args[1], alice, '!partially liquidated trove owner');
      assert.equal(troveUpdatedEvents[0].args[2].toString(), _debtRemaining.toString(), '!partially liquidated trove remaining debt');
      assert.equal(troveUpdatedEvents[0].args[3].toString(), _collRemaining.toString(), '!partially liquidated trove remaining collateral');
      assert.equal(troveUpdatedEvents[0].args[4].toString(), _stakeRemaining.toString(), '!partially liquidated trove remaining stake');
      assert.equal(troveUpdatedEvents[0].args[5], 4, '!TroveManagerOperation.partiallyLiquidate');

      // check TroveLiquidated event
      const liquidationEvents = th.getAllEventsByName(tx, 'TrovePartiallyLiquidated')
      assert.equal(liquidationEvents.length, 1, '!TrovePartiallyLiquidated event')
      assert.equal(liquidationEvents[0].args[0], _aliceTroveId, '!partially liquidated trove ID');
      assert.equal(liquidationEvents[0].args[1], alice, '!partially liquidated trove owner');
      assert.equal(liquidationEvents[0].args[2].toString(), _debtLiquidated.toString(), '!partially liquidated trove debt');
      assert.equal(liquidationEvents[0].args[3].toString(), _collLiquidated.toString(), '!partially liquidated trove collateral');
      assert.equal(liquidationEvents[0].args[4], 4, '!TroveManagerOperation.partiallyLiquidate');
	  
      // check liquidator balance change
      let _gasUsed = th.gasUsed(tx);
      let _debtDecreased = toBN(_debtLiquidatorPre.toString()).sub(toBN(_debtLiquidatorPost.toString()));
      assert.equal(_debtDecreased.toString(), _debtLiquidated.toString(), '!liquidator debt balance');		  
      const gasUsedETH = toBN(tx.receipt.effectiveGasPrice.toString()).mul(toBN(_gasUsed.toString()));
      let _ethSeizedByLiquidator = toBN(_ethLiquidatorPost.toString()).sub(toBN(_ethLiquidatorPre.toString())).add(gasUsedETH);
      assert.equal(_ethSeizedByLiquidator.toString(), _collLiquidated.toString(), '!liquidator collateral balance');	 
	  
      // check system balance change
      let _debtDecreasedSystem = toBN(_debtSystemPre.toString()).sub(toBN(_debtSystemPost.toString()));
      assert.equal(_debtDecreasedSystem.toString(), _debtLiquidated.toString(), '!system debt balance');	
      let _colDecreasedSystem = toBN(_colSystemPre.toString()).sub(toBN(_colSystemPost.toString())); 
      assert.equal(_colDecreasedSystem.toString(), _collLiquidated.toString(), '!system collateral balance');	
      let _debtDecreasedActivePool = toBN(_debtInActivePoolPre.toString()).sub(toBN(_debtInActivePoolPost.toString())); 
      assert.equal(_debtDecreasedActivePool.toString(), _debtLiquidated.toString(), '!activePool debt balance');
      let _colDecreasedActivePool = toBN(_collInActivePoolPre.toString()).sub(toBN(_collInActivePoolPost.toString())); 
      assert.equal(_colDecreasedActivePool.toString(), _collLiquidated.toString(), '!activePool collateral balance');

      // Confirm the trove still there
      assert.isTrue(await sortedTroves.contains(_aliceTroveId))

      // Confirm troves have status 'active' (Status enum element idx 1)
      assert.equal((await troveManager.Troves(_aliceTroveId))[3], '1')
  })
  
  it("Troves should not deteriorate its ICR after partially liquidated", async () => {
      let {tx: opAliceTx} = await openTrove({ ICR: toBN(dec(299, 16)), extraLUSDAmount: toBN(minDebt.toString()).add(toBN(1)), extraParams: { from: alice } })
      await openTrove({ ICR: toBN(dec(259, 16)), extraParams: { from: bob } })
      let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
      assert.isTrue(await sortedTroves.contains(_aliceTroveId));
      let _debtBorrowed = await troveManager.getTroveDebt(_aliceTroveId);
      let _colDeposited = await troveManager.getTroveColl(_aliceTroveId);
	  
      await openTrove({ ICR: toBN(dec(199, 16)), extraParams: { from: carol } })
      let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);	  
      await openTrove({ ICR: toBN(dec(159, 16)), extraParams: { from: owner } })
      let _ownerTroveId = await sortedTroves.troveOfOwnerByIndex(owner, 0);
	  
      // alice now sit top of sorted CDP list according to NICR
      let _firstId = await sortedTroves.getFirst();
      assert.equal(_firstId, _aliceTroveId);
      let _lastId = await sortedTroves.getLast();
      assert.equal(_lastId, _ownerTroveId);
	  
      // price slump by 70%
      let _newPrice = dec(60, 18);
      await priceFeed.setPrice(_newPrice);
	  
      // only partially (1/4 = 250000 / 1000000) liquidate alice 
      let _partialRatio = toBN("250000");// max(full) is million  
      let _icr = await troveManager.getCurrentICR(_aliceTroveId, _newPrice);
	  
      // liquidator bob coming in 
      await debtToken.transfer(bob, (await debtToken.balanceOf(alice)), {from: alice});	
      await troveManager.partiallyLiquidate(_aliceTroveId, _partialRatio, _aliceTroveId, _aliceTroveId, {from: bob})	  
      let _icrPost = await troveManager.getCurrentICR(_aliceTroveId, _newPrice);
      assert.isTrue(toBN(_icrPost.toString()).gte(toBN(_icr.toString())));

      // alice still on top of sorted CDP list since partially liquidation should keep its ICR NOT decreased
      let _firstIdPost = await sortedTroves.getFirst();
      assert.equal(_firstId, _firstIdPost);
      let _lastIdPost = await sortedTroves.getLast();
      assert.equal(_lastId, _lastIdPost);

      // Confirm troves have status 'active' (Status enum element idx 1)
      assert.equal((await troveManager.Troves(_aliceTroveId))[3], '1')
  })
  
  it("CDP might be get fully liquidated even if called via partiallyLiquidate()", async () => {
      let {tx: opAliceTx} = await openTrove({ ICR: toBN(dec(299, 16)), extraLUSDAmount: toBN(minDebt.toString()).add(toBN(1)), extraParams: { from: alice } })
      await openTrove({ ICR: toBN(dec(259, 16)), extraParams: { from: bob } })
      let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
      assert.isTrue(await sortedTroves.contains(_aliceTroveId));
      let _debtBorrowed = await troveManager.getTroveDebt(_aliceTroveId);
      let _colDeposited = await troveManager.getTroveColl(_aliceTroveId);
	  
      // price slump to reduce TCR to 48%
      let _newPrice = dec(68, 18);
      await priceFeed.setPrice(_newPrice);
      assert.isTrue(await troveManager.checkRecoveryMode(_newPrice));
	  
      // liquidation fully 
      await debtToken.transfer(alice, (await debtToken.balanceOf(bob)), {from: bob});	 
      let _liquidateTx = await troveManager.partiallyLiquidate(_aliceTroveId, 0, _aliceTroveId, _aliceTroveId, {from: alice});
      // Confirm the CDP is fully liquidated thus closed
      assert.equal((await troveManager.Troves(_aliceTroveId))[3], '3') //closedByLiquidation
	  
      let _cdpUpdatedEvents = th.getAllEventsByName(_liquidateTx, 'TroveUpdated');
      assert.equal(_cdpUpdatedEvents[0].args[5], 2, '!TroveManagerOperation.liquidateInRecoveryMode');// not partially updated
  })
  
  it("Troves below MCR could be fully liquidated step by step via partiallyLiquidate()", async () => {
      let {tx: opAliceTx} = await openTrove({ ICR: toBN(dec(299, 16)), extraLUSDAmount: toBN(minDebt.toString()).add(toBN(1)), extraParams: { from: alice } })
      await openTrove({ ICR: toBN(dec(299, 16)), extraParams: { from: bob } })
      let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
      assert.isTrue(await sortedTroves.contains(_aliceTroveId));
      let _debtBorrowed = await troveManager.getTroveDebt(_aliceTroveId);
      let _colDeposited = await troveManager.getTroveColl(_aliceTroveId);
	  
      // price slump by 70%
      let _newPrice = dec(60, 18);
      await priceFeed.setPrice(_newPrice);
	  
      // partial liquidation steps: Firstly 1/4, Secondly another 1/4 = 1/3 * (1 - 1/4), Lastly all the rest
      let _partialRatios = [toBN("250000"), toBN("333333"), toBN("0")];// max(full) is million, 0 means fully liquidation
      let _partialLiquidations = 3;
      let _partialLiquidationTxs = [];
	  
      // liquidator bob coming in 
      await debtToken.transfer(bob, (await debtToken.balanceOf(alice)), {from: alice});	  
      let _debtLiquidatorPre = await debtToken.balanceOf(bob);  
      let _debtSystemPre = await troveManager.getEntireSystemDebt();
      let _colSystemPre = await troveManager.getEntireSystemColl();
      let _ethLiquidatorPre = await web3.eth.getBalance(bob);	  
      let _debtInActivePoolPre = await activePool.getLUSDDebt();
      let _collInActivePoolPre = await activePool.getETH();
	  
      for(let i = 0;i < _partialLiquidations;i++){
          const tx = await troveManager.partiallyLiquidate(_aliceTroveId, _partialRatios[i], _aliceTroveId, _aliceTroveId, {from: bob})
          _partialLiquidationTxs.push(tx); 		  
      } 
      
      let _debtLiquidatorPost = await debtToken.balanceOf(bob);
      let _debtSystemPost = await troveManager.getEntireSystemDebt();
      let _colSystemPost = await troveManager.getEntireSystemColl();
      let _ethLiquidatorPost = await web3.eth.getBalance(bob);	  
      let _debtInActivePoolPost = await activePool.getLUSDDebt();
      let _collInActivePoolPost = await activePool.getETH();
	  
      // check liquidator balance change
      let _debtDecreased = toBN(_debtLiquidatorPre.toString()).sub(toBN(_debtLiquidatorPost.toString()));
      assert.equal(_debtDecreased.toString(), _debtBorrowed.toString(), '!liquidator debt balance');
      let gasUsedETH = toBN('0');
      for(let i = 0;i < _partialLiquidations;i++){
          let _gasUsed = toBN(th.gasUsed(_partialLiquidationTxs[i]).toString());	
          gasUsedETH = gasUsedETH.add(toBN(_partialLiquidationTxs[i].receipt.effectiveGasPrice.toString()).mul(toBN(_gasUsed.toString())));	  		  
      }
      let _ethSeizedByLiquidator = toBN(_ethLiquidatorPost.toString()).sub(toBN(_ethLiquidatorPre.toString())).add(gasUsedETH);
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

      // Confirm all troves removed
      assert.isFalse(await sortedTroves.contains(_aliceTroveId))

      // Confirm troves have status 'closed by liquidation' (Status enum element idx 3)
      assert.equal((await troveManager.Troves(_aliceTroveId))[3], '3')
  })
  
  it("Should allow non-EOA liquidator", async () => {
      let {tx: opAliceTx} = await openTrove({ ICR: toBN(dec(299, 16)), extraParams: { from: alice } })
      await openTrove({ ICR: toBN(dec(299, 16)), extraParams: { from: bob } })
      let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
      assert.isTrue(await sortedTroves.contains(_aliceTroveId));
      let _debtBorrowed = await troveManager.getTroveDebt(_aliceTroveId);
      let _colDeposited = await troveManager.getTroveColl(_aliceTroveId);
	  
      // price slump by 70%
      let _newPrice = dec(60, 18);
      await priceFeed.setPrice(_newPrice);
	  
      // non-EOA liquidator coming in	
      const simpleLiquidationTester = await SimpleLiquidationTester.new();
      await simpleLiquidationTester.setTroveManager(troveManager.address);
	
      await debtToken.transfer(simpleLiquidationTester.address, (await debtToken.balanceOf(alice)), {from: alice});	  
      await debtToken.transfer(simpleLiquidationTester.address, (await debtToken.balanceOf(bob)), {from: bob});	 
      let _debtLiquidatorPre = await debtToken.balanceOf(simpleLiquidationTester.address);  
      let _debtSystemPre = await troveManager.getEntireSystemDebt();
      let _colSystemPre = await troveManager.getEntireSystemColl();
      let _ethLiquidatorPre = await web3.eth.getBalance(simpleLiquidationTester.address);	  
      let _debtInActivePoolPre = await activePool.getLUSDDebt();
      let _collInActivePoolPre = await activePool.getETH();
      const tx = await simpleLiquidationTester.liquidateTrove(_aliceTroveId, {from: bob})	  
      let _debtLiquidatorPost = await debtToken.balanceOf(simpleLiquidationTester.address);
      let _debtSystemPost = await troveManager.getEntireSystemDebt();
      let _colSystemPost = await troveManager.getEntireSystemColl();
      let _ethLiquidatorPost = await web3.eth.getBalance(simpleLiquidationTester.address);	  
      let _debtInActivePoolPost = await activePool.getLUSDDebt();
      let _collInActivePoolPost = await activePool.getETH();
	  
      // check EtherReceived event
      const seizedEtherEvents = th.getAllEventsByName(tx, 'EtherReceived')
      assert.equal(seizedEtherEvents.length, 1, '!EtherReceived event')
      assert.equal(seizedEtherEvents[0].args[0], (await troveManager.activePool()), '!Ether from Active Pool');
      assert.equal(seizedEtherEvents[0].args[1].toString(), _colDeposited.toString(), '!liquidated trove collateral');
	  
      // check liquidator balance change
      let _debtDecreased = toBN(_debtLiquidatorPre.toString()).sub(toBN(_debtLiquidatorPost.toString()));
      assert.equal(_debtDecreased.toString(), _debtBorrowed.toString(), '!liquidator debt balance');		
      let _ethSeizedByLiquidator = toBN(_ethLiquidatorPost.toString()).sub(toBN(_ethLiquidatorPre.toString()));
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

      // Confirm all troves removed
      assert.isFalse(await sortedTroves.contains(_aliceTroveId))

      // Confirm troves have status 'closed by liquidation' (Status enum element idx 3)
      assert.equal((await troveManager.Troves(_aliceTroveId))[3], '3')
  })  
  
  it("Should NOT allow non-EOA liquidator to reenter liquidate(bytes32) during partiallyLiquidate(bytes32, uint)", async () => {
      let {tx: opAliceTx} = await openTrove({ ICR: toBN(dec(299, 16)), extraLUSDAmount: toBN(minDebt.toString()).add(toBN(1)), extraParams: { from: alice } })
      await openTrove({ ICR: toBN(dec(299, 16)), extraParams: { from: bob } })
      let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
      assert.isTrue(await sortedTroves.contains(_aliceTroveId));
	  
      // price slump by 70%
      let _newPrice = dec(60, 18);
      await priceFeed.setPrice(_newPrice);
	  
      // non-EOA liquidator coming in	
      const simpleLiquidationTester = await SimpleLiquidationTester.new();
      await simpleLiquidationTester.setTroveManager(troveManager.address);
      await simpleLiquidationTester.setReceiveType(1);//tell liquidator to try reentering liquidation
	
      await debtToken.transfer(simpleLiquidationTester.address, (await debtToken.balanceOf(alice)), {from: alice});	  
      await debtToken.transfer(simpleLiquidationTester.address, (await debtToken.balanceOf(bob)), {from: bob});	
      let _debtPre = await troveManager.getTroveDebt(_aliceTroveId);
      await assertRevert(simpleLiquidationTester.partiallyLiquidateTrove(_aliceTroveId, toBN("333333"), {from: bob}), 'ReentrancyGuard: reentrant call');
      let _debtPost = await troveManager.getTroveDebt(_aliceTroveId);
      assert.equal(_debtPre.toString(), _debtPost.toString(), '!partially liquidation revert');
  })
  
  it("Should NOT allow non-EOA liquidator to reenter liquidate(bytes32)", async () => {
      let {tx: opAliceTx} = await openTrove({ ICR: toBN(dec(299, 16)), extraParams: { from: alice } })
      await openTrove({ ICR: toBN(dec(299, 16)), extraParams: { from: bob } })
      let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
      assert.isTrue(await sortedTroves.contains(_aliceTroveId));
	  
      // price slump by 70%
      let _newPrice = dec(60, 18);
      await priceFeed.setPrice(_newPrice);
	  
      // non-EOA liquidator coming in	
      const simpleLiquidationTester = await SimpleLiquidationTester.new();
      await simpleLiquidationTester.setTroveManager(troveManager.address);
      await simpleLiquidationTester.setReceiveType(1);//tell liquidator to try reentering liquidation
	
      await debtToken.transfer(simpleLiquidationTester.address, (await debtToken.balanceOf(alice)), {from: alice});	  
      await debtToken.transfer(simpleLiquidationTester.address, (await debtToken.balanceOf(bob)), {from: bob});	
      let _debtPre = await troveManager.getTroveDebt(_aliceTroveId);
      await assertRevert(simpleLiquidationTester.liquidateTrove(_aliceTroveId, {from: bob}), 'ReentrancyGuard: reentrant call');
      assert.isTrue(await sortedTroves.contains(_aliceTroveId));
      let _debtPost = await troveManager.getTroveDebt(_aliceTroveId);
      assert.equal(_debtPre.toString(), _debtPost.toString(), '!partially liquidation revert');
  })
  
  it("non-EOA liquidator might revert on Ether receive() to fail liquidation", async () => {
      let {tx: opAliceTx} = await openTrove({ ICR: toBN(dec(299, 16)), extraParams: { from: alice } })
      await openTrove({ ICR: toBN(dec(299, 16)), extraParams: { from: bob } })
      let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
      assert.isTrue(await sortedTroves.contains(_aliceTroveId));
	  
      // price slump by 70%
      let _newPrice = dec(60, 18);
      await priceFeed.setPrice(_newPrice);
	  
      // non-EOA liquidator coming in	
      const simpleLiquidationTester = await SimpleLiquidationTester.new();
      await simpleLiquidationTester.setTroveManager(troveManager.address);
      await simpleLiquidationTester.setReceiveType(2);//tell liquidator to try reverting
	
      await debtToken.transfer(simpleLiquidationTester.address, (await debtToken.balanceOf(alice)), {from: alice});	  
      await debtToken.transfer(simpleLiquidationTester.address, (await debtToken.balanceOf(bob)), {from: bob});	
      await assertRevert(simpleLiquidationTester.liquidateTrove(_aliceTroveId, {from: bob}), 'ActivePool: sending ETH failed');
      assert.isTrue(await sortedTroves.contains(_aliceTroveId));
  })
  
  it("liquidateSequentiallyInRecovery(): liquidate _n most risky CDPs in recovery mode", async () => {	
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: bob } });	  
      let bobTroveId = await sortedTroves.getFirst();
      assert.isTrue(await sortedTroves.contains(bobTroveId));	
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: carol } });	  
      let carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);
      assert.isTrue(await sortedTroves.contains(carolTroveId));

      // mint Alice some LUSD
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } });	
      await debtToken.transfer(alice, (await debtToken.balanceOf(bob)), {from : bob});	
      await debtToken.transfer(alice, (await debtToken.balanceOf(carol)), {from : carol});  
      let aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
      let aliceTroveOwner = await sortedTroves.existTroveOwners(aliceTroveId);
      assert.isTrue(aliceTroveOwner == alice);
      await borrowerOperations.addColl(aliceTroveId, th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: alice, value: dec(500, 'ether') })

      // maniuplate price to liquidate bob & carol
      let _newPrice = dec(10, 18);
      await priceFeed.setPrice(_newPrice);  
      assert.isTrue(await troveManager.checkRecoveryMode(_newPrice));

      let bobDebt = await troveManager.getTroveDebt(bobTroveId);
      let bobColl = await troveManager.getTroveColl(bobTroveId);
      let carolDebt = await troveManager.getTroveDebt(carolTroveId);
      let carolColl = await troveManager.getTroveColl(carolTroveId);			  
      let prevDebtOfAlice = await debtToken.balanceOf(alice);
      assert.isTrue(toBN(prevDebtOfAlice.toString()).gt(toBN(bobDebt.toString()).add(toBN(carolDebt.toString()))));
	  
      // liquidate sequentially in recovery mode	  
      let prevETHOfAlice = await ethers.provider.getBalance(alice);
      let _TCR = await troveManager.getTCR(_newPrice);
      let _bobICR = await troveManager.getCurrentICR(bobTroveId, _newPrice);
      let _carolICR = await troveManager.getCurrentICR(carolTroveId, _newPrice);
      assert.isTrue(toBN(_bobICR.toString()).lt(toBN(_TCR.toString())));
      assert.isTrue(toBN(_carolICR.toString()).lt(toBN(_TCR.toString())));
      assert.isTrue(toBN(_TCR.toString()).lt(toBN(dec(110, 16))));
      let _liquidateRecoveryTx = await troveManager.liquidateSequentiallyInRecovery(2, { from: alice});	  
      let postDebtOfAlice = await debtToken.balanceOf(alice);
      let postETHOfAlice = await await ethers.provider.getBalance(alice);
      assert.isFalse(await sortedTroves.contains(bobTroveId));
      assert.isFalse(await sortedTroves.contains(carolTroveId));
      let _liquidatedEvents = th.getAllEventsByName(_liquidateRecoveryTx, 'TroveLiquidated');
      assert.equal(_liquidatedEvents.length, 2, '!TroveLiquidated event');
      assert.equal(_liquidatedEvents[0].args[4].toString(), '2', '!liquidateInRecoveryMode');
      assert.equal(_liquidatedEvents[1].args[4].toString(), '2', '!liquidateInRecoveryMode');
      let _gasEtherUsed = toBN(_liquidateRecoveryTx.receipt.effectiveGasPrice.toString()).mul(toBN((th.gasUsed(_liquidateRecoveryTx)).toString()));
      let _ethSeizedByLiquidator = toBN(postETHOfAlice.toString()).sub(toBN(prevETHOfAlice.toString())).add(_gasEtherUsed);

      // alice get collateral from bob & carol by repaying the debts
      assert.equal(toBN(prevDebtOfAlice.toString()).sub(toBN(postDebtOfAlice.toString())).toString(), toBN(bobDebt.toString()).add(toBN(carolDebt.toString())).toString());
      assert.equal(_ethSeizedByLiquidator.toString(), toBN(bobColl.toString()).add(toBN(carolColl.toString())).toString());
      let troveIds = await troveManager.getTroveIdsCount();
      assert.isTrue(troveIds == 1); 
      let _sysDebt = await troveManager.getEntireSystemDebt();	  
      let _aliceDebt = await troveManager.getTroveDebt(aliceTroveId); 
      let _activeDebt = await activePool.getLUSDDebt();		 	  
      assert.equal(toBN(_sysDebt.toString()).toString(), toBN(_aliceDebt.toString()).toString());	 	  
      assert.equal(toBN(_sysDebt.toString()).toString(), toBN(_activeDebt.toString()).toString());	  	  
      assert.isFalse(await troveManager.checkRecoveryMode(_newPrice));
  })  
  
  it("liquidateInBatchRecovery(): liquidate CDPs in batch in recovery mode", async () => {	
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: bob } });	  
      let bobTroveId = await sortedTroves.getFirst();
      assert.isTrue(await sortedTroves.contains(bobTroveId));	
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: carol } });	  
      let carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);
      assert.isTrue(await sortedTroves.contains(carolTroveId));

      // mint Alice some LUSD
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } });	
      await debtToken.transfer(alice, (await debtToken.balanceOf(bob)), {from : bob});	
      await debtToken.transfer(alice, (await debtToken.balanceOf(carol)), {from : carol});  
      let aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
      let aliceTroveOwner = await sortedTroves.existTroveOwners(aliceTroveId);
      assert.isTrue(aliceTroveOwner == alice);
      await borrowerOperations.addColl(aliceTroveId, aliceTroveId, aliceTroveId, { from: alice, value: dec(510, 'ether') })
      await borrowerOperations.addColl(bobTroveId, bobTroveId, bobTroveId, { from: bob, value: dec(110, 'ether') })

      // maniuplate price to liquidate bob & carol
      let _newPrice = dec(11, 18);
      await priceFeed.setPrice(_newPrice);  
      assert.isTrue(await troveManager.checkRecoveryMode(_newPrice));

      let bobDebt = await troveManager.getTroveDebt(bobTroveId);
      let bobColl = await troveManager.getTroveColl(bobTroveId);
      let carolDebt = await troveManager.getTroveDebt(carolTroveId);
      let carolColl = await troveManager.getTroveColl(carolTroveId);			  
      let prevDebtOfAlice = await debtToken.balanceOf(alice);
      assert.isTrue(toBN(prevDebtOfAlice.toString()).gt(toBN(bobDebt.toString()).add(toBN(carolDebt.toString()))));
	  
      // liquidate in batch in recovery mode	  
      let prevETHOfAlice = await ethers.provider.getBalance(alice);
      let _TCR = await troveManager.getTCR(_newPrice);
      let _bobICR = await troveManager.getCurrentICR(bobTroveId, _newPrice);
      let _carolICR = await troveManager.getCurrentICR(carolTroveId, _newPrice);
      assert.isTrue(toBN(_bobICR.toString()).lt(toBN(_TCR.toString())));
      assert.isTrue(toBN(_carolICR.toString()).lt(toBN(_TCR.toString())));
      assert.isTrue(toBN(_TCR.toString()).gt(toBN(dec(110, 16))));
      let _liquidateRecoveryTx = await troveManager.liquidateInBatchRecovery([aliceTroveId, bobTroveId, carolTroveId], { from: alice});	  
      let postDebtOfAlice = await debtToken.balanceOf(alice);
      let postETHOfAlice = await await ethers.provider.getBalance(alice);
      assert.isTrue(await sortedTroves.contains(aliceTroveId));// alice is skipped in liquidation since its ICR is bigger enough
      assert.isFalse(await sortedTroves.contains(bobTroveId));
      assert.isFalse(await sortedTroves.contains(carolTroveId));
      let _liquidatedEvents = th.getAllEventsByName(_liquidateRecoveryTx, 'TroveLiquidated');
      assert.equal(_liquidatedEvents.length, 2, '!TroveLiquidated event');
      assert.equal(_liquidatedEvents[0].args[4].toString(), '2', '!liquidateInRecoveryMode');// bob was liquidated in recovery mode
      assert.equal(_liquidatedEvents[1].args[4].toString(), '1', '!liquidateInNormalMode');// carol was liquidated in normal mode
      let _gasEtherUsed = toBN(_liquidateRecoveryTx.receipt.effectiveGasPrice.toString()).mul(toBN((th.gasUsed(_liquidateRecoveryTx)).toString()));
      let _ethSeizedByLiquidator = toBN(postETHOfAlice.toString()).sub(toBN(prevETHOfAlice.toString())).add(_gasEtherUsed);

      // alice get collateral from bob & carol by repaying the debts
      assert.equal(toBN(prevDebtOfAlice.toString()).sub(toBN(postDebtOfAlice.toString())).toString(), toBN(bobDebt.toString()).add(toBN(carolDebt.toString())).toString());
      assert.equal(_ethSeizedByLiquidator.toString(), toBN(bobColl.toString()).add(toBN(carolColl.toString())).toString());
      let troveIds = await troveManager.getTroveIdsCount();
      assert.isTrue(troveIds == 1); 
      let _sysDebt = await troveManager.getEntireSystemDebt();	  
      let _aliceDebt = await troveManager.getTroveDebt(aliceTroveId); 
      let _activeDebt = await activePool.getLUSDDebt();		 	  
      assert.equal(toBN(_sysDebt.toString()).toString(), toBN(_aliceDebt.toString()).toString());	 	  
      assert.equal(toBN(_sysDebt.toString()).toString(), toBN(_activeDebt.toString()).toString());	  	  
      assert.isFalse(await troveManager.checkRecoveryMode(_newPrice));
  })     
  
  it("liquidateInBatchRecovery(): liquidate CDPs in batch in recovery mode with some collateral surplus", async () => {	
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: bob } });	  
      let bobTroveId = await sortedTroves.getFirst();
      assert.isTrue(await sortedTroves.contains(bobTroveId));	
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: carol } });	  
      let carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);
      assert.isTrue(await sortedTroves.contains(carolTroveId));

      // mint Alice some LUSD
      await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } });	
      await debtToken.transfer(alice, (await debtToken.balanceOf(bob)), {from : bob});	
      await debtToken.transfer(alice, (await debtToken.balanceOf(carol)), {from : carol});  
      let aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);
      let aliceTroveOwner = await sortedTroves.existTroveOwners(aliceTroveId);
      assert.isTrue(aliceTroveOwner == alice);
      await borrowerOperations.addColl(aliceTroveId, aliceTroveId, aliceTroveId, { from: alice, value: dec(210, 'ether') })
      await borrowerOperations.addColl(bobTroveId, bobTroveId, bobTroveId, { from: bob, value: dec(100, 'ether') })

      // maniuplate price to liquidate bob & carol
      let _newPrice = dec(20, 18);
      await priceFeed.setPrice(_newPrice);  
      assert.isTrue(await troveManager.checkRecoveryMode(_newPrice));

      let bobDebt = await troveManager.getTroveDebt(bobTroveId);
      let bobColl = await troveManager.getTroveColl(bobTroveId);	  
      let cappedBobColl = toBN(bobDebt.toString()).mul(toBN(dec(110, 16))).div(toBN(_newPrice));
      let _surplusBobColl = toBN(bobColl.toString()).sub(cappedBobColl);
      assert.isTrue(cappedBobColl.lt(toBN(bobColl.toString())));
      let carolDebt = await troveManager.getTroveDebt(carolTroveId);
      let carolColl = await troveManager.getTroveColl(carolTroveId);			  
      let prevDebtOfAlice = await debtToken.balanceOf(alice);
      assert.isTrue(toBN(prevDebtOfAlice.toString()).gt(toBN(bobDebt.toString()).add(toBN(carolDebt.toString()))));
	  
      // liquidate in batch in recovery mode	  
      let prevETHOfAlice = await ethers.provider.getBalance(alice);
      let _TCR = await troveManager.getTCR(_newPrice);
      let _bobICR = await troveManager.getCurrentICR(bobTroveId, _newPrice);
      let _carolICR = await troveManager.getCurrentICR(carolTroveId, _newPrice);
      assert.isTrue(toBN(_bobICR.toString()).lt(toBN(_TCR.toString())));
      assert.isTrue(toBN(_carolICR.toString()).lt(toBN(_TCR.toString())));
      assert.isTrue(toBN(_TCR.toString()).gt(toBN(dec(110, 16))));
      let _liquidateRecoveryTx = await troveManager.liquidateInBatchRecovery([aliceTroveId, bobTroveId, carolTroveId], { from: alice});	  
      let postDebtOfAlice = await debtToken.balanceOf(alice);
      let postETHOfAlice = await await ethers.provider.getBalance(alice);
      assert.isTrue(await sortedTroves.contains(aliceTroveId));// alice is skipped in liquidation since its ICR is bigger enough
      assert.isFalse(await sortedTroves.contains(bobTroveId));
      assert.isFalse(await sortedTroves.contains(carolTroveId));
      let _liquidatedEvents = th.getAllEventsByName(_liquidateRecoveryTx, 'TroveLiquidated');
      assert.equal(_liquidatedEvents.length, 2, '!TroveLiquidated event');
      assert.equal(_liquidatedEvents[0].args[4].toString(), '2', '!liquidateInRecoveryMode');// bob was liquidated in recovery mode
      assert.equal(_liquidatedEvents[1].args[4].toString(), '2', '!liquidateInRecoveryMode');// carol was liquidated in recovery mode
      let _gasEtherUsed = toBN(_liquidateRecoveryTx.receipt.effectiveGasPrice.toString()).mul(toBN((th.gasUsed(_liquidateRecoveryTx)).toString()));
      let _ethSeizedByLiquidator = toBN(postETHOfAlice.toString()).sub(toBN(prevETHOfAlice.toString())).add(_gasEtherUsed);
	  
      // bob got some collateral surplus left to claim
      let _bobToClaim = await contracts.collSurplusPool.getCollateral(bob);
      assert.equal(toBN(_bobToClaim.toString()).toString(), _surplusBobColl.toString());
      let prevETHOfBob = await ethers.provider.getBalance(bob);
      let _claimSurplusTx = await borrowerOperations.claimCollateral({ from: bob});
      let postETHOfBob = await ethers.provider.getBalance(bob);
      let _gasEtherUsedClaim = toBN(_claimSurplusTx.receipt.effectiveGasPrice.toString()).mul(toBN((th.gasUsed(_claimSurplusTx)).toString()));
      let _ethClaimedByBob = toBN(postETHOfBob.toString()).sub(toBN(prevETHOfBob.toString())).add(_gasEtherUsedClaim);	
      assert.equal(toBN(_bobToClaim.toString()).toString(), _ethClaimedByBob.toString());  

      // alice get collateral from bob & carol by repaying the debts
      assert.equal(toBN(prevDebtOfAlice.toString()).sub(toBN(postDebtOfAlice.toString())).toString(), toBN(bobDebt.toString()).add(toBN(carolDebt.toString())).toString());
      assert.equal(_ethSeizedByLiquidator.toString(), toBN(cappedBobColl.toString()).add(toBN(carolColl.toString())).toString());
      let troveIds = await troveManager.getTroveIdsCount();
      assert.isTrue(troveIds == 1); 
      let _sysDebt = await troveManager.getEntireSystemDebt();	  
      let _aliceDebt = await troveManager.getTroveDebt(aliceTroveId); 
      let _activeDebt = await activePool.getLUSDDebt();		 	  
      assert.equal(toBN(_sysDebt.toString()).toString(), toBN(_aliceDebt.toString()).toString());	 	  
      assert.equal(toBN(_sysDebt.toString()).toString(), toBN(_activeDebt.toString()).toString());	  	  
      assert.isFalse(await troveManager.checkRecoveryMode(_newPrice));
  })   
  
  it("liquidateSequentially(): liquidate _n most risky CDPs in normal mode", async () => {
      let {tx: opAliceTx} = await openTrove({ ICR: toBN(dec(299, 16)), extraLUSDAmount: toBN(minDebt.toString()).mul(toBN('5')), extraParams: { from: alice } })
      let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);	  
      await openTrove({ ICR: toBN(dec(179, 16)), extraLUSDAmount: toBN(dec(700, 18)), extraParams: { from: bob } })
      let _bobTroveId = await sortedTroves.troveOfOwnerByIndex(bob, 0);
      assert.isTrue(await sortedTroves.contains(_aliceTroveId));
	  
      await openTrove({ ICR: toBN(dec(169, 16)), extraParams: { from: carol } })
      let _carolTroveId = await sortedTroves.troveOfOwnerByIndex(carol, 0);	  
      await openTrove({ ICR: toBN(dec(159, 16)), extraParams: { from: owner } })
      let _ownerTroveId = await sortedTroves.troveOfOwnerByIndex(owner, 0);
	  	  
      let _newPrice = dec(120, 18);
      await priceFeed.setPrice(_newPrice);	  
	  
      let _MCR = toBN(dec(110,16));
      let _bobICR = await troveManager.getCurrentICR(_bobTroveId, _newPrice);
      let _carolICR = await troveManager.getCurrentICR(_carolTroveId, _newPrice);
      let _ownerICR = await troveManager.getCurrentICR(_ownerTroveId, _newPrice);
      assert.isTrue(toBN(_bobICR.toString()).lt(_MCR));
      assert.isTrue(toBN(_carolICR.toString()).lt(_MCR));
      assert.isTrue(toBN(_ownerICR.toString()).lt(_MCR));
	  
      let _bobDebt = await troveManager.getTroveDebt(_bobTroveId);
      let _carolDebt = await troveManager.getTroveDebt(_carolTroveId);
      let _ownerDebt = await troveManager.getTroveDebt(_ownerTroveId);
      let _liquidatedDebt = toBN(_bobDebt.toString()).add(toBN(_carolDebt.toString())).add(toBN(_ownerDebt.toString()));
	  
      let _bobColl = await troveManager.getTroveColl(_bobTroveId);
      let _carolColl = await troveManager.getTroveColl(_carolTroveId);
      let _ownerColl = await troveManager.getTroveColl(_ownerTroveId);
      let _liquidatedColl = toBN(_bobColl.toString()).add(toBN(_carolColl.toString())).add(toBN(_ownerColl.toString()));
	  	  
      let _debtInLiquidatorPre = await debtToken.balanceOf(alice);
      let _ethLiquidatorPre = await web3.eth.getBalance(alice);	  
      let _liqTx = await troveManager.liquidateSequentially(3, {from: alice});
      let _debtInLiquidatorPost = await debtToken.balanceOf(alice);  
      let _ethLiquidatorPost = await web3.eth.getBalance(alice);  	  	  
      const gasUsedETH = toBN(_liqTx.receipt.effectiveGasPrice.toString()).mul(toBN(th.gasUsed(_liqTx).toString()));
      let _ethSeizedByLiquidator = toBN(_ethLiquidatorPost.toString()).sub(toBN(_ethLiquidatorPre.toString())).add(gasUsedETH); 	  
      let _debtInLiquidatorDecreased = toBN(_debtInLiquidatorPre.toString()).sub(toBN(_debtInLiquidatorPost.toString()));
	  
      assert.equal(_debtInLiquidatorDecreased.toString(), _liquidatedDebt.toString());
      assert.equal(_ethSeizedByLiquidator.toString(), _liquidatedColl.toString());
      assert.isFalse((await sortedTroves.contains(_bobTroveId)));
      assert.isFalse((await sortedTroves.contains(_carolTroveId)));
      assert.isFalse((await sortedTroves.contains(_ownerTroveId)));
	  
  });
  
})
