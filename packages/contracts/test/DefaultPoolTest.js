const testHelpers = require("../utils/testHelpers.js")
const deploymentHelper = require("../utils/deploymentHelpers.js")
const DefaultPool = artifacts.require("./DefaultPoolTester.sol")
const ActivePool = artifacts.require("./ActivePool.sol")
const CollateralTokenTester = artifacts.require("./CollateralTokenTester.sol")
const NonPayable = artifacts.require('NonPayable.sol')
const FeeRecipient = artifacts.require('FeeRecipient.sol')

const th = testHelpers.TestHelper
const dec = th.dec
const toBN = web3.utils.toBN

contract('DefaultPool', async accounts => {
  let defaultPool
  let nonPayable
  let mockActivePool
  let mockCdpManager
  let collToken

  let [owner] = accounts

  beforeEach('Deploy contracts', async () => {
    coreContracts = await deploymentHelper.deployTesterContractsHardhat()
	
    cdpManager = coreContracts.cdpManager;
    collToken = coreContracts.collateral;
	  
    activePool = coreContracts.activePool;
    defaultPool = coreContracts.defaultPool;
  })

  it('sendETHToActivePool(): fails if receiver cannot receive ETH', async () => {
    const amount = dec(1, 'ether')

    // start pool with `amount`
    //await web3.eth.sendTransaction({ to: defaultPool.address, from: owner, value: amount })
    await collToken.deposit({from: owner, value: amount});
    const tx = await collToken.transfer(defaultPool.address, amount, {from: owner});//mockActivePool.forward(defaultPool.address, '0x', { from: owner, value: amount })
    assert.isTrue(tx.receipt.status)
    await defaultPool.unprotectedReceiveColl(amount);

    // try to send ether from pool to non-payable
    //await th.assertRevert(defaultPool.sendETHToActivePool(amount, { from: owner }), 'DefaultPool: sending ETH failed')
    let _collBalanceBefore = await collToken.balanceOf(activePool.address);
    assert.isTrue(toBN(_collBalanceBefore.toString()).eq(toBN('0')));
    await cdpManager.defaultPoolSendToActivePool(web3.utils.toHex(amount));//, 'DefaultPool: sending ETH failed')
    let _collBalance = await collToken.balanceOf(activePool.address);
    assert.isTrue(toBN(_collBalance.toString()).eq(toBN(amount)));
  })
})

contract('Reset chain state', async accounts => { })
