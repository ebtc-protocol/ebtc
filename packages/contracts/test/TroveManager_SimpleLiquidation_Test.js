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
  
  it("Partially Liquidation Ratio needs to be below max(million)", async () => {
      await openTrove({ ICR: toBN(dec(299, 16)), extraParams: { from: alice } })
      let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);	  
      await assertRevert(troveManager.partiallyLiquidate(_aliceTroveId, 1000001, {from: bob}), "!partialLiqMax");
  })
  
  it("Partially Liquidation needs to leave Trove with big enough debt if not closed completely", async () => {
      await openTrove({ ICR: toBN(dec(299, 16)), extraParams: { from: alice } })
      let _aliceTroveId = await sortedTroves.troveOfOwnerByIndex(alice, 0);	  
      await assertRevert(troveManager.partiallyLiquidate(_aliceTroveId, 987654, {from: bob}), "!minDebtLeftByPartiallyLiq");
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
      const tx = await troveManager.partiallyLiquidate(_aliceTroveId, _partialRatio, {from: bob})	  
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
      assert.equal(troveUpdatedEvents[0].args[5], 4, '!TroveManagerOperation.partiallyLiquidateInNormalMode');

      // check TroveLiquidated event
      const liquidationEvents = th.getAllEventsByName(tx, 'TrovePartiallyLiquidated')
      assert.equal(liquidationEvents.length, 1, '!TrovePartiallyLiquidated event')
      assert.equal(liquidationEvents[0].args[0], _aliceTroveId, '!partially liquidated trove ID');
      assert.equal(liquidationEvents[0].args[1], alice, '!partially liquidated trove owner');
      assert.equal(liquidationEvents[0].args[2].toString(), _debtLiquidated.toString(), '!partially liquidated trove debt');
      assert.equal(liquidationEvents[0].args[3].toString(), _collLiquidated.toString(), '!partially liquidated trove collateral');
      assert.equal(liquidationEvents[0].args[4], 4, '!TroveManagerOperation.partiallyLiquidateInNormalMode');
	  
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
  
  it("Troves below MCR could be fully liquidated via partiallyLiquidate()", async () => {
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
          const tx = await troveManager.partiallyLiquidate(_aliceTroveId, _partialRatios[i], {from: bob})
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
      await assertRevert(simpleLiquidationTester.liquidateTrove(_aliceTroveId, {from: bob}), 'ReentrancyGuard: reentrant call');
      assert.isTrue(await sortedTroves.contains(_aliceTroveId));
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
  
})
