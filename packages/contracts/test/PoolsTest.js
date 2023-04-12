const ActivePool = artifacts.require("./ActivePoolTester.sol")
const DefaultPool = artifacts.require("./DefaultPoolTester.sol")
const NonPayable = artifacts.require("./NonPayable.sol")
const WETH9 = artifacts.require("./WETH9.sol")
const testHelpers = require("../utils/testHelpers.js")
const CollateralTokenTester = artifacts.require("./CollateralTokenTester.sol")
const SimpleLiquidationTester = artifacts.require("./SimpleLiquidationTester.sol")

const th = testHelpers.TestHelper
const dec = th.dec

const _minus_1_Ether = web3.utils.toWei('-1', 'ether')

contract('ActivePool', async accounts => {

  let activePool, mockBorrowerOperations, collToken

  const [owner, alice] = accounts;
  beforeEach(async () => {
    const weth9 = await WETH9.new()
    activePool = await ActivePool.new()
    mockBorrowerOperations = await NonPayable.new()
    const dumbContractAddress = (await NonPayable.new()).address
    collToken = await CollateralTokenTester.new()
    await activePool.setAddresses(mockBorrowerOperations.address, dumbContractAddress, collToken.address, collToken.address, dumbContractAddress, dumbContractAddress)
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

    // await activePool.increaseEBTCDebt(100, { from: mockBorrowerOperationsAddress })
    const increaseEBTCDebtData = th.getTransactionData('increaseEBTCDebt(uint256)', ['0x64'])
    const tx = await mockBorrowerOperations.forward(activePool.address, increaseEBTCDebtData)
    assert.isTrue(tx.receipt.status)
    const recordedEBTC_balanceAfter = await activePool.getEBTCDebt()
    assert.equal(recordedEBTC_balanceAfter, 100)
  })
  // Decrease
  it('decreaseEBTC(): decreases the recorded EBTC balance by the correct amount', async () => {
    // start the pool on 100 wei
    //await activePool.increaseEBTCDebt(100, { from: mockBorrowerOperationsAddress })
    const increaseEBTCDebtData = th.getTransactionData('increaseEBTCDebt(uint256)', ['0x64'])
    const tx1 = await mockBorrowerOperations.forward(activePool.address, increaseEBTCDebtData)
    assert.isTrue(tx1.receipt.status)

    const recordedEBTC_balanceBefore = await activePool.getEBTCDebt()
    assert.equal(recordedEBTC_balanceBefore, 100)

    //await activePool.decreaseEBTCDebt(100, { from: mockBorrowerOperationsAddress })
    const decreaseEBTCDebtData = th.getTransactionData('decreaseEBTCDebt(uint256)', ['0x64'])
    const tx2 = await mockBorrowerOperations.forward(activePool.address, decreaseEBTCDebtData)
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
    //await activePool.sendStEthColl(alice, dec(1, 'ether'), { from: mockBorrowerOperationsAddress })
    const sendETHData = th.getTransactionData('sendStEthColl(address,uint256)', [alice, web3.utils.toHex(dec(1, 'ether'))])
    const tx2 = await mockBorrowerOperations.forward(activePool.address, sendETHData, { from: owner })
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
    await collToken.transfer(activePool.address, _amount, {from: alice});
    await collToken.transfer(_flashBorrower.address, _fee, {from: alice});
    await collToken.receiveCollToInternalPool(activePool.address, _amount);
	
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
})

contract('DefaultPool', async accounts => {
 
  let defaultPool, mockCdpManager, activePool, collToken

  const [owner, alice] = accounts;
  beforeEach(async () => {
    const weth9 = await WETH9.new()
    defaultPool = await DefaultPool.new()
    mockCdpManager = await NonPayable.new()
    
    activePool = await ActivePool.new()
    const dumbContractAddress = (await NonPayable.new()).address	  
    collToken = await CollateralTokenTester.new()
	  
    await activePool.setAddresses(dumbContractAddress, mockCdpManager.address, defaultPool.address, collToken.address, dumbContractAddress, dumbContractAddress)	  
    await defaultPool.setAddresses(mockCdpManager.address, activePool.address, collToken.address)
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

    // await defaultPool.increaseEBTCDebt(100, { from: mockCdpManagerAddress })
    const increaseEBTCDebtData = th.getTransactionData('increaseEBTCDebt(uint256)', ['0x64'])
    const tx = await mockCdpManager.forward(defaultPool.address, increaseEBTCDebtData)
    assert.isTrue(tx.receipt.status)

    const recordedEBTC_balanceAfter = await defaultPool.getEBTCDebt()
    assert.equal(recordedEBTC_balanceAfter, 100)
  })
  
  it('decreaseEBTC(): decreases the recorded EBTC balance by the correct amount', async () => {
    // start the pool on 100 wei
    //await defaultPool.increaseEBTCDebt(100, { from: mockCdpManagerAddress })
    const increaseEBTCDebtData = th.getTransactionData('increaseEBTCDebt(uint256)', ['0x64'])
    const tx1 = await mockCdpManager.forward(defaultPool.address, increaseEBTCDebtData)
    assert.isTrue(tx1.receipt.status)

    const recordedEBTC_balanceBefore = await defaultPool.getEBTCDebt()
    assert.equal(recordedEBTC_balanceBefore, 100)

    // await defaultPool.decreaseEBTCDebt(100, { from: mockCdpManagerAddress })
    const decreaseEBTCDebtData = th.getTransactionData('decreaseEBTCDebt(uint256)', ['0x64'])
    const tx2 = await mockCdpManager.forward(defaultPool.address, decreaseEBTCDebtData)
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

    // send ether from pool to alice
    //await defaultPool.sendETHToActivePool(dec(1, 'ether'), { from: mockCdpManagerAddress })
    const sendETHData = th.getTransactionData('sendETHToActivePool(uint256)', [web3.utils.toHex(dec(1, 'ether'))])
//    await mockActivePool.setPayable(true)
    const tx2 = await mockCdpManager.forward(defaultPool.address, sendETHData, { from: owner })
    assert.isTrue(tx2.receipt.status)

    const defaultPool_BalanceAfterTx = web3.utils.toBN(await collToken.balanceOf(defaultPool.address))
    const activePool_Balance_AfterTx = web3.utils.toBN(await collToken.balanceOf(activePool.address))

    const activePool_BalanceChange = activePool_Balance_AfterTx.sub(activePool_Balance_BeforeTx)
    const defaultPool_BalanceChange = defaultPool_BalanceAfterTx.sub(defaultPool_BalanceBeforeTx)
    assert.equal(activePool_BalanceChange, dec(1, 'ether'))
    assert.equal(defaultPool_BalanceChange, _minus_1_Ether)
  })
})

contract('Reset chain state', async accounts => {})
