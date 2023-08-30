const ActivePool = artifacts.require("./ActivePoolTester.sol")
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
	
  let activePool, cdpManager, collToken, borrowerOperations

  const [owner, alice] = accounts;
  beforeEach(async () => {
    await deploymentHelper.setDeployGasPrice(1000000000)
    coreContracts = await deploymentHelper.deployTesterContractsHardhat()
	  
    activePool = coreContracts.activePool
    collToken = coreContracts.collateral;
    cdpManager = coreContracts.cdpManager;
    borrowerOperations = coreContracts.borrowerOperations;
	  
    activePoolAuthority = coreContracts.authority;
  })

  it('getSystemCollShares(): gets the recorded ETH balance', async () => {
    const recordedETHBalance = await activePool.getSystemCollShares()
    assert.equal(recordedETHBalance, 0)
  })

  it('getSystemDebt(): gets the recorded EBTC balance', async () => {
    const recordedETHBalance = await activePool.getSystemDebt()
    assert.equal(recordedETHBalance, 0)
  })
 
  it('increaseEBTC(): increases the recorded EBTC balance by the correct amount', async () => {
    const recordedEBTC_balanceBefore = await activePool.getSystemDebt()
    assert.equal(recordedEBTC_balanceBefore, 0)
	  
    const tx = await cdpManager.activePoolIncreaseSystemDebt('0x64')
    assert.isTrue(tx.receipt.status)
    const recordedEBTC_balanceAfter = await activePool.getSystemDebt()
    assert.equal(recordedEBTC_balanceAfter, 100)
  })
  // Decrease
  it('decreaseEBTC(): decreases the recorded EBTC balance by the correct amount', async () => {
    // start the pool on 100 wei
    const tx1 = await cdpManager.activePoolIncreaseSystemDebt('0x64')
    assert.isTrue(tx1.receipt.status)

    const recordedEBTC_balanceBefore = await activePool.getSystemDebt()
    assert.equal(recordedEBTC_balanceBefore, 100)
	  
    const tx2 = await cdpManager.activePoolDecreaseSystemDebt('0x64')
    assert.isTrue(tx2.receipt.status)
    const recordedEBTC_balanceAfter = await activePool.getSystemDebt()
    assert.equal(recordedEBTC_balanceAfter, 0)
  })

  // send raw ether
  it('transferSystemCollShares(): decreases the recorded ETH balance by the correct amount', async () => {
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
    const tx2 = await cdpManager.activePoolTransferSystemCollShares(alice, web3.utils.toHex(dec(1, 'ether')))
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
    await borrowerOperations.unprotectedActivePoolReceiveColl(_amount);
	
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
	  
  it("ActivePool governance permissioned: setFeeBps() should only allow authorized caller", async() => {	
    await th.assertRevert(activePool.setFeeBps(1, {from: alice}), "Auth: UNAUTHORIZED");   

    assert.isTrue(activePoolAuthority.address == (await activePool.authority()));

    let _role123 = 123;
    let _funcSig = await activePool.FUNC_SIG_FL_FEE();
    await activePoolAuthority.setRoleCapability(_role123, activePool.address, _funcSig, true, {from: accounts[0]});	  
    await activePoolAuthority.setUserRole(alice, _role123, true, {from: accounts[0]});

    assert.isTrue((await activePoolAuthority.canCall(alice, activePool.address, _funcSig)));
    await th.assertRevert(activePool.setFeeBps(10001, {from: alice}), "ERC3156FlashLender: _newFee should < 10000");

    let _newFee = await activePool.MAX_FEE_BPS();
    assert.isTrue(_newFee.gt(await activePool.feeBps()));
    await activePool.setFeeBps(_newFee, {from: alice})
    assert.isTrue(_newFee.eq(await activePool.feeBps()));

  })

  it("ActivePool governance permissioned: setFeeBps() should only allow authorized caller", async() => {	
    await th.assertRevert(activePool.setFeeBps(1, {from: alice}), "Auth: UNAUTHORIZED");   

    assert.isTrue(activePoolAuthority.address == (await activePool.authority()));

    let _role123 = 123;
    let _funcSig = await activePool.FUNC_SIG_FL_FEE();
    console.log(_funcSig);

    await activePoolAuthority.setRoleCapability(_role123, activePool.address, _funcSig, true, {from: accounts[0]});	  
    await activePoolAuthority.setUserRole(alice, _role123, true, {from: accounts[0]});

    assert.isTrue((await activePoolAuthority.canCall(alice, activePool.address, _funcSig)));
    await th.assertRevert(activePool.setFeeBps(10001, {from: alice}), "ERC3156FlashLender: _newFee should < MAX_FEE_BPS");

    let _newFee = await activePool.MAX_FEE_BPS()
    assert.isTrue(_newFee.lte(await activePool.MAX_FEE_BPS())); // starts at 10000
    await activePool.setFeeBps(_newFee, {from: alice})
    assert.isTrue(_newFee.eq(await activePool.MAX_FEE_BPS()));

  })
 
  it('sweepToken(): move unprotected token to fee recipient', async () => {
    let _sweepTokenFunc = await activePool.FUNC_SIG1();
    let _amt = 123456789;

    // expect reverts
    await th.assertRevert(activePool.sweepToken(collToken.address, _amt), 'Auth: UNAUTHORIZED');
	
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
      assert.include(err.message, "ReentrancyGuard: Reentrancy in nonReentrant call")
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


contract('Reset chain state', async accounts => {})
