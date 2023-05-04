const ActivePool = artifacts.require("./ActivePoolTester.sol")
const DefaultPool = artifacts.require("./DefaultPoolTester.sol")
const CDPMgr = artifacts.require("./CdpManagerTester.sol")
const NonPayable = artifacts.require("./NonPayable.sol")
const WETH9 = artifacts.require("./WETH9.sol")
const testHelpers = require("../utils/testHelpers.js")
const deploymentHelper = require("../utils/deploymentHelpers.js")
const CollateralTokenTester = artifacts.require("./CollateralTokenTester.sol")
const ReentrancyToken = artifacts.require("./ReentrancyToken.sol")
const SimpleLiquidationTester = artifacts.require("./SimpleLiquidationTester.sol")
const Governor = artifacts.require("./Governor.sol")

const th = testHelpers.TestHelper
const dec = th.dec

const _minus_1_Ether = web3.utils.toWei('-1', 'ether')

contract('ActivePool', async accounts => {
	
  let defaultPool, activePool, cdpManager, collToken

  const [owner, alice] = accounts;
  beforeEach(async () => {
    coreContracts = await deploymentHelper.deployTesterContractsHardhat()
	  
    activePool = coreContracts.activePool
    collToken = coreContracts.collateral;
    cdpManager = coreContracts.cdpManager;
    defaultPool = coreContracts.defaultPool;
	  
    activePoolAuthority = coreContracts.authority;
  })

  it('getStEthColl(): gets the recorded ETH balance', async () => {
    const recordedETHBalance = await activePool.getStEthColl()
    assert.equal(recordedETHBalance, 0)
  })

  it('getEBTCDebt(): gets the recorded EBTC balance', async () => {
    const recordedETHBalance = await activePool.getEBTCDebt()
    assert.equal(recordedETHBalance, 0)
  })
 
  it('increaseEBTC(): increases the recorded EBTC balance by the correct amount', async () => {
    const recordedEBTC_balanceBefore = await activePool.getEBTCDebt()
    assert.equal(recordedEBTC_balanceBefore, 0)
	  
    const tx = await cdpManager.activePoolIncreaseEBTCDebt('0x64')
    assert.isTrue(tx.receipt.status)
    const recordedEBTC_balanceAfter = await activePool.getEBTCDebt()
    assert.equal(recordedEBTC_balanceAfter, 100)
  })
  // Decrease
  it('decreaseEBTC(): decreases the recorded EBTC balance by the correct amount', async () => {
    // start the pool on 100 wei
    const tx1 = await cdpManager.activePoolIncreaseEBTCDebt('0x64')
    assert.isTrue(tx1.receipt.status)

    const recordedEBTC_balanceBefore = await activePool.getEBTCDebt()
    assert.equal(recordedEBTC_balanceBefore, 100)
	  
    const tx2 = await cdpManager.activePoolDecreaseEBTCDebt('0x64')
    assert.isTrue(tx2.receipt.status)
    const recordedEBTC_balanceAfter = await activePool.getEBTCDebt()
    assert.equal(recordedEBTC_balanceAfter, 0)
  })

  // send raw ether
  it('sendStEthColl(): decreases the recorded ETH balance by the correct amount', async () => {
    // setup: give pool 2 ether
    const activePool_initialBalance = web3.utils.toBN(await web3.eth.getBalance(activePool.address))
    assert.equal(activePool_initialBalance, 0)
    // start pool with 2 ether
    //await web3.eth.sendTransaction({ from: mockBorrowerOperationsAddress, to: activePool.address, value: dec(2, 'ether') })
    let _amt = dec(2, 'ether');
    await collToken.deposit({ from: owner, value: _amt });  
    const tx1 = await collToken.transfer(activePool.address, _amt, { from: owner, value: 0 })
    assert.isTrue(tx1.receipt.status)
    await activePool.unprotectedReceiveColl(_amt);

    const activePool_BalanceBeforeTx = web3.utils.toBN(await collToken.balanceOf(activePool.address))
    const alice_Balance_BeforeTx = web3.utils.toBN(await collToken.balanceOf(alice))

    assert.equal(activePool_BalanceBeforeTx, dec(2, 'ether'))

    // send ether from pool to alice
    const tx2 = await cdpManager.activePoolSendStEthColl(alice, web3.utils.toHex(dec(1, 'ether')))
    assert.isTrue(tx2.receipt.status)

    const activePool_BalanceAfterTx = web3.utils.toBN(await collToken.balanceOf(activePool.address))
    const alice_Balance_AfterTx = web3.utils.toBN(await collToken.balanceOf(alice))

    const alice_BalanceChange = alice_Balance_AfterTx.sub(alice_Balance_BeforeTx)
    const pool_BalanceChange = activePool_BalanceAfterTx.sub(activePool_BalanceBeforeTx)
    assert.equal(alice_BalanceChange, dec(1, 'ether'))
    assert.equal(pool_BalanceChange, _minus_1_Ether)
  })
  
  it('flashloan(): should work', async () => {
    let _amount = "123456789";
    let _flashBorrower = await SimpleLiquidationTester.new();
    let _fee = await activePool.flashFee(collToken.address, _amount);
	  
    await collToken.deposit({from: alice, value: _fee.add(web3.utils.toBN(_amount))});
    
    await collToken.transfer(defaultPool.address, _amount, {from: alice});
    await defaultPool.unprotectedReceiveColl(_amount);
    await cdpManager.defaultPoolSendToActivePool(_amount);
	
    await collToken.transfer(_flashBorrower.address, _fee, {from: alice});
	
    let _newPPFS = web3.utils.toBN('1000000000000000000');
    let _collTokenBalBefore = await collToken.balanceOf(activePool.address); 
    await _flashBorrower.initFlashLoan(activePool.address, collToken.address, _amount, _newPPFS);
    let _collTokenBalAfter = await collToken.balanceOf(activePool.address); 
    assert.isTrue(web3.utils.toBN(_collTokenBalBefore.toString()).eq(web3.utils.toBN(_collTokenBalAfter.toString())));
	
    // test edge cases
    await th.assertRevert(_flashBorrower.initFlashLoan(activePool.address, activePool.address, _amount, _newPPFS), 'ActivePool: collateral Only');
    await th.assertRevert(_flashBorrower.initFlashLoan(activePool.address, collToken.address, 0, _newPPFS), 'ActivePool: 0 Amount');
    await th.assertRevert(_flashBorrower.initFlashLoan(activePool.address, collToken.address, _newPPFS, _newPPFS), 'ActivePool: Too much');
    await th.assertRevert(_flashBorrower.initFlashLoan(activePool.address, collToken.address, _amount, 0), 'ActivePool: IERC3156: Callback failed');
    await th.assertRevert(activePool.flashFee(activePool.address, _newPPFS), 'ActivePool: collateral Only');
    assert.isTrue(web3.utils.toBN("0").eq(web3.utils.toBN((await activePool.maxFlashLoan(activePool.address)).toString())));
	
    // should revert due to invariants check
    let _manipulatedPPFS = web3.utils.toBN('2000000000000000000'); 
    await th.assertRevert(_flashBorrower.initFlashLoan(activePool.address, collToken.address, _amount, _manipulatedPPFS), 'ActivePool: Must repay Share');
  }) 
	  
  it("ActivePool governance permissioned: setFlashFee() should only allow authorized caller", async() => {	
    await th.assertRevert(activePool.setFlashFee(1, {from: alice}), "ERC3156FlashLender: sender not authorized for setFlashFee(uint256)");   

    assert.isTrue(activePoolAuthority.address == (await activePool.authority()));
    let _role123 = 123;
    let _funcSig = await activePool.FUNC_SIG_FL_FEE();
    await activePoolAuthority.setRoleCapability(_role123, activePool.address, _funcSig, true, {from: accounts[0]});	  
    await activePoolAuthority.setUserRole(alice, _role123, true, {from: accounts[0]});
    assert.isTrue((await activePoolAuthority.canCall(alice, activePool.address, _funcSig)));
    await th.assertRevert(activePool.setFlashFee(10000, {from: alice}), "ERC3156FlashLender: _newFee should < 10000");
    let _newFee = web3.utils.toBN("9999");
    assert.isTrue(_newFee.gt(await activePool.FEE_AMT()));
    await activePool.setFlashFee(_newFee, {from: alice})
    assert.isTrue(_newFee.eq(await activePool.FEE_AMT()));

  })
 
  it('sweepToken(): move unprotected token to fee recipient', async () => {
    let _sweepTokenFunc = await activePool.FUNC_SIG1();
    let _amt = 123456789;

    // expect reverts
    await th.assertRevert(activePool.sweepToken(collToken.address, _amt), 'ActivePool: sender not authorized for sweepToken(address,uint256)');
	
    activePoolAuthority.setPublicCapability(activePool.address, _sweepTokenFunc, true);  
    await th.assertRevert(activePool.sweepToken(collToken.address, _amt), 'ActivePool: Cannot Sweep Collateral');	  
	  
    let _dustToken = await CollateralTokenTester.new()  
    await th.assertRevert(activePool.sweepToken(_dustToken.address, _amt), 'ActivePool: Attempt to sweep more than balance');	
	  
    // expect recipient get dust  
    await _dustToken.deposit({value: _amt});
    await _dustToken.transfer(activePool.address, _amt); 
    let _feeRecipient = await activePool.feeRecipientAddress();	
    let _balRecipient = await _dustToken.balanceOf(_feeRecipient);
    await activePool.sweepToken(_dustToken.address, _amt);
    let _balRecipientAfter = await _dustToken.balanceOf(_feeRecipient);
    let _diff = _balRecipientAfter.sub(_balRecipient);
    assert.isTrue(_diff.toNumber() == _amt);
	
  })
 
  it('sweepToken(): test reentrancy and failed safeTransfer() cases', async () => {
    let _sweepTokenFunc = await activePool.FUNC_SIG1();
    let _amt = 123456789;
	  
    activePoolAuthority.setPublicCapability(activePool.address, _sweepTokenFunc, true);
    let _dustToken = await ReentrancyToken.new();
	  
    // expect guard against reentrancy
    await _dustToken.deposit({value: _amt, from: owner});
    await _dustToken.transferFrom(owner, activePool.address, _amt);
    try {
      _dustToken.setSweepPool(activePool.address);
      await activePool.sweepToken(_dustToken.address, _amt)
    } catch (err) {
      //console.log("errMsg=" + err.message)
      assert.include(err.message, "ReentrancyGuard: reentrant call")
    }
	
    // expect revert on failed safeTransfer() case 1: transfer() returns false
    try {
      _dustToken.setSweepPool("0x0000000000000000000000000000000000000000");
      await activePool.sweepToken(_dustToken.address, _amt)
    } catch (err) {
      //console.log("errMsg=" + err.message)
      assert.include(err.message, "SafeERC20: ERC20 operation did not succeed")
    }
	
    // expect revert on failed safeTransfer() case 2: no transfer() exist
    try {
      _dustToken = activePool;
      await activePool.sweepToken(_dustToken.address, _amt)
    } catch (err) {
      //console.log("errMsg=" + err.message)
      assert.include(err.message, "SafeERC20: low-level call failed")
    }	
	
    // expect safeTransfer() works with non-standard transfer() like USDT
    // https://etherscan.io/token/0xdac17f958d2ee523a2206206994597c13d831ec7#code#L126
    _dustToken = await SimpleLiquidationTester.new();
    await activePool.sweepToken(_dustToken.address, _amt);	
  })
})

contract('DefaultPool', async accounts => {
 
  let defaultPool, cdpManager, activePool, collToken

  const [owner, alice] = accounts;
  beforeEach(async () => {
    coreContracts = await deploymentHelper.deployTesterContractsHardhat()
	  
    defaultPool = coreContracts.defaultPool    
    activePool = coreContracts.activePool	  
    collToken = coreContracts.collateral
    cdpManager = coreContracts.cdpManager;
    defaultPoolAuthority = coreContracts.authority;
  })

  it('getStEthColl(): gets the recorded EBTC balance', async () => {
    const recordedETHBalance = await defaultPool.getStEthColl()
    assert.equal(recordedETHBalance, 0)
  })

  it('getEBTCDebt(): gets the recorded EBTC balance', async () => {
    const recordedETHBalance = await defaultPool.getEBTCDebt()
    assert.equal(recordedETHBalance, 0)
  })
 
  it('increaseEBTC(): increases the recorded EBTC balance by the correct amount', async () => {
    const recordedEBTC_balanceBefore = await defaultPool.getEBTCDebt()
    assert.equal(recordedEBTC_balanceBefore, 0)
    const tx = await cdpManager.defaultPoolIncreaseEBTCDebt('0x64')
    assert.isTrue(tx.receipt.status)

    const recordedEBTC_balanceAfter = await defaultPool.getEBTCDebt()
    assert.equal(recordedEBTC_balanceAfter, 100)
  })
  
  it('decreaseEBTC(): decreases the recorded EBTC balance by the correct amount', async () => {
    // start the pool on 100 wei
    const tx1 = await cdpManager.defaultPoolIncreaseEBTCDebt('0x64')
    assert.isTrue(tx1.receipt.status)

    const recordedEBTC_balanceBefore = await defaultPool.getEBTCDebt()
    assert.equal(recordedEBTC_balanceBefore, 100)
	  
    const tx2 = await cdpManager.defaultPoolDecreaseEBTCDebt('0x64')
    assert.isTrue(tx2.receipt.status)

    const recordedEBTC_balanceAfter = await defaultPool.getEBTCDebt()
    assert.equal(recordedEBTC_balanceAfter, 0)
  })

  // send raw ether
  it('sendETHToActivePool(): decreases the recorded ETH balance by the correct amount', async () => {
    // setup: give pool 2 ether
    const defaultPool_initialBalance = web3.utils.toBN(await web3.eth.getBalance(defaultPool.address))
    assert.equal(defaultPool_initialBalance, 0)

    // start pool with 2 ether
    //await web3.eth.sendTransaction({ from: mockActivePool.address, to: defaultPool.address, value: dec(2, 'ether') })
    let _amt = dec(2, 'ether');
    await collToken.deposit({ from: owner, value: _amt });  
    const tx1 = await collToken.transfer(defaultPool.address, _amt, { from: owner, value: 0 })
    assert.isTrue(tx1.receipt.status)
    await defaultPool.unprotectedReceiveColl(_amt);

    const defaultPool_BalanceBeforeTx = web3.utils.toBN(await collToken.balanceOf(defaultPool.address))
    const activePool_Balance_BeforeTx = web3.utils.toBN(await collToken.balanceOf(activePool.address))

    assert.equal(defaultPool_BalanceBeforeTx, dec(2, 'ether'))

    // send ether from pool
    const tx2 = await cdpManager.defaultPoolSendToActivePool(web3.utils.toHex(dec(1, 'ether')))
    assert.isTrue(tx2.receipt.status)

    const defaultPool_BalanceAfterTx = web3.utils.toBN(await collToken.balanceOf(defaultPool.address))
    const activePool_Balance_AfterTx = web3.utils.toBN(await collToken.balanceOf(activePool.address))

    const activePool_BalanceChange = activePool_Balance_AfterTx.sub(activePool_Balance_BeforeTx)
    const defaultPool_BalanceChange = defaultPool_BalanceAfterTx.sub(defaultPool_BalanceBeforeTx)
    assert.equal(activePool_BalanceChange, dec(1, 'ether'))
    assert.equal(defaultPool_BalanceChange, _minus_1_Ether)
  })
 
  it('sweepToken(): move unprotected token to fee recipient', async () => {
    let _sweepTokenFunc = await defaultPool.FUNC_SIG1();
    let _amt = 123456789;

    // expect reverts
    await th.assertRevert(defaultPool.sweepToken(collToken.address, _amt), 'DefaultPool: sender not authorized for sweepToken(address,uint256)');
	
    defaultPoolAuthority.setPublicCapability(defaultPool.address, _sweepTokenFunc, true);  
    await th.assertRevert(defaultPool.sweepToken(collToken.address, _amt), 'DefaultPool: Cannot Sweep Collateral');	  
	  
    let _dustToken = await CollateralTokenTester.new()  
    await th.assertRevert(defaultPool.sweepToken(_dustToken.address, _amt), 'DefaultPool: Attempt to sweep more than balance');	
	  
    // expect recipient get dust  
    await _dustToken.deposit({value: _amt});
    await _dustToken.transfer(defaultPool.address, _amt); 
    let _feeRecipient = await defaultPool.feeRecipientAddress();	
    let _balRecipient = await _dustToken.balanceOf(_feeRecipient);
    await defaultPool.sweepToken(_dustToken.address, _amt);
    let _balRecipientAfter = await _dustToken.balanceOf(_feeRecipient);
    let _diff = _balRecipientAfter.sub(_balRecipient);
    assert.isTrue(_diff.toNumber() == _amt);
	
  })
 
  it('sweepToken(): test reentrancy and failed safeTransfer() cases', async () => {
    let _sweepTokenFunc = await defaultPool.FUNC_SIG1();
    let _amt = 123456789;
	  
    defaultPoolAuthority.setPublicCapability(defaultPool.address, _sweepTokenFunc, true);
    let _dustToken = await ReentrancyToken.new();
	  
    // expect guard against reentrancy
    await _dustToken.deposit({value: _amt, from: owner});
    await _dustToken.transferFrom(owner, defaultPool.address, _amt);
    try {
      _dustToken.setSweepPool(defaultPool.address);
      await defaultPool.sweepToken(_dustToken.address, _amt)
    } catch (err) {
      //console.log("errMsg=" + err.message)
      assert.include(err.message, "ReentrancyGuard: reentrant call")
    }
	
    // expect revert on failed safeTransfer() case 1: transfer() returns false
    try {
      _dustToken.setSweepPool("0x0000000000000000000000000000000000000000");
      await defaultPool.sweepToken(_dustToken.address, _amt)
    } catch (err) {
      //console.log("errMsg=" + err.message)
      assert.include(err.message, "SafeERC20: ERC20 operation did not succeed")
    }
	
    // expect revert on failed safeTransfer() case 2: no transfer() exist
    try {
      _dustToken = defaultPool;
      await defaultPool.sweepToken(_dustToken.address, _amt)
    } catch (err) {
      //console.log("errMsg=" + err.message)
      assert.include(err.message, "SafeERC20: low-level call failed")
    }	
	
    // expect safeTransfer() works with non-standard transfer() like USDT
    // https://etherscan.io/token/0xdac17f958d2ee523a2206206994597c13d831ec7#code#L126
    _dustToken = await SimpleLiquidationTester.new();
    await defaultPool.sweepToken(_dustToken.address, _amt);	
  })
})

contract('Reset chain state', async accounts => {})
