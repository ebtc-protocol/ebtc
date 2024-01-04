const deploymentHelper = require("../utils/deploymentHelpers.js")
const testHelpers = require("../utils/testHelpers.js")
const NonPayable = artifacts.require('NonPayable.sol')
const CollateralTokenTester = artifacts.require("./CollateralTokenTester.sol")
const ReentrancyToken = artifacts.require("./ReentrancyToken.sol")
const SimpleLiquidationTester = artifacts.require("./SimpleLiquidationTester.sol")
const Governor = artifacts.require("./Governor.sol")
const CollSurplusPool = artifacts.require("./CollSurplusPoolTester.sol")

const th = testHelpers.TestHelper
const dec = th.dec
const toBN = th.toBN
const mv = testHelpers.MoneyValues
const timeValues = testHelpers.TimeValues

const CdpManagerTester = artifacts.require("CdpManagerTester")
const EBTCToken = artifacts.require("EBTCToken")

contract('CollSurplusPool', async accounts => {
  const [
    owner,
    A, B, C, D, E] = accounts;

  const [bountyAddress, lpRewardsAddress, multisig] = accounts.slice(accounts.length - 3, accounts.length)

  let borrowerOperations
  let priceFeed
  let collSurplusPool

  let contracts
  let collToken;
  let poolAuthority;

  const getOpenCdpEBTCAmount = async (totalDebt) => th.getOpenCdpEBTCAmount(contracts, totalDebt)
  const openCdp = async (params) => th.openCdp(contracts, params)

  beforeEach(async () => {
    contracts = await deploymentHelper.deployTesterContractsHardhat()
    let LQTYContracts = {}
    LQTYContracts.feeRecipient = contracts.feeRecipient;

    priceFeed = contracts.priceFeedTestnet
    collSurplusPool = contracts.collSurplusPool
    activePool = contracts.activePool;
    borrowerOperations = contracts.borrowerOperations
    collToken = contracts.collateral;
    liqReward = await borrowerOperations.LIQUIDATOR_REWARD();
    poolAuthority = contracts.authority;
    await deploymentHelper.connectCoreContracts(contracts, LQTYContracts)
  })

  it("CollSurplusPool::getSystemCollShares(): Returns the ETH balance of the CollSurplusPool after redemption", async () => {
    const ETH_1 = await collSurplusPool.getTotalSurplusCollShares()
    assert.equal(ETH_1, '0')

    const price = toBN(dec(100, 18))
    await priceFeed.setPrice(price)

    const { collateral: B_coll, netDebt: B_netDebt } = await openCdp({ ICR: toBN(dec(200, 16)), extraParams: { from: B } })
    await openCdp({ extraEBTCAmount: B_netDebt, extraParams: { from: A, value: dec(3000, 'ether') } })
    await th.syncTwapSystemDebt(contracts, ethers.provider);

    // At ETH:USD = 100, this redemption should leave 1 ether of coll surplus
    await th.redeemCollateralAndGetTxObject(A, contracts, B_netDebt)

    const ETH_2 = await collSurplusPool.getTotalSurplusCollShares()
    th.assertIsApproximatelyEqual(ETH_2, B_coll.sub(B_netDebt.mul(mv._1e18BN).div(price)).add(liqReward))
  })

  it("CollSurplusPool: claimSurplusCollShares(): Reverts if caller is not Borrower Operations", async () => {
    await th.assertRevert(collSurplusPool.claimSurplusCollShares(A, { from: A }), 'CollSurplusPool: Caller is not Borrower Operations')
  })

  it("CollSurplusPool: claimSurplusCollShares(): Reverts if nothing to claim", async () => {
    await th.assertRevert(borrowerOperations.claimSurplusCollShares({ from: A }), 'CollSurplusPool: No collateral available to claim')
  })

  it("CollSurplusPool: claimSurplusCollShares(): Reverts if owner cannot receive ETH surplus", async () => {
    const nonPayable = await NonPayable.new()

    const price = toBN(dec(100, 18))
    await priceFeed.setPrice(price)

    // open cdp from NonPayable proxy contract
    const B_coll = toBN(dec(60, 18))
    const B_ebtcAmount = toBN(dec(3000, 18))
    const B_netDebt = await th.getAmountWithBorrowingFee(contracts, B_ebtcAmount)
    const openCdpData = th.getTransactionData('openCdp(uint256,bytes32,bytes32,uint256)', [web3.utils.toHex(B_ebtcAmount), th.DUMMY_BYTES32, th.DUMMY_BYTES32, B_coll])
    await collToken.nonStandardSetApproval(nonPayable.address, borrowerOperations.address, mv._1Be18BN);
    await collToken.approve(borrowerOperations.address, mv._1Be18BN);
    await collToken.deposit({value: B_coll});
    await collToken.transfer(nonPayable.address, B_coll);
	  
    await nonPayable.forward(borrowerOperations.address, openCdpData, { value: 0 })
    await openCdp({ extraEBTCAmount: B_netDebt, extraParams: { from: A, value: dec(3000, 'ether') } })
    await th.syncTwapSystemDebt(contracts, ethers.provider);

    // At ETH:USD = 100, this redemption should leave 1 ether of coll surplus for B
    await th.redeemCollateralAndGetTxObject(A, contracts, B_netDebt)

    const ETH_2 = await collSurplusPool.getTotalSurplusCollShares()
    let _expected = B_coll.sub(B_netDebt.mul(mv._1e18BN).div(price));
    th.assertIsApproximatelyEqual(ETH_2, _expected)

    let _collBefore = await collToken.balanceOf(nonPayable.address);
    const claimCollateralData = th.getTransactionData('claimSurplusCollShares()', [])
    await nonPayable.forward(borrowerOperations.address, claimCollateralData)
    let _collAfter = await collToken.balanceOf(nonPayable.address);
    assert.isTrue(toBN(_collAfter.toString()).gt(toBN(_collBefore.toString())));
  })

  it('CollSurplusPool: reverts trying to send ETH to it', async () => {
    await th.assertRevert(web3.eth.sendTransaction({ from: A, to: collSurplusPool.address, value: 1 }), 'CollSurplusPool: Caller is not Active Pool')
  })

  it('CollSurplusPool: increaseSurplusCollShares: reverts if caller is not Cdp Manager', async () => {
    await th.assertRevert(collSurplusPool.increaseSurplusCollShares(th.RANDOM_INDEX, A, 1, 0), 'CollSurplusPool: Caller is not CdpManager')
  })  
	  
    it('sweepToken(): move unprotected token to fee recipient', async () => {
	  
    collSurplusPool = await CollSurplusPool.new(borrowerOperations.address, borrowerOperations.address, activePool.address, collToken.address)
    let _sweepTokenFunc = await collSurplusPool.FUNC_SIG1();
    let _amt = 123456789;

    // expect reverts
    await th.assertRevert(collSurplusPool.sweepToken(collToken.address, _amt), 'Auth: UNAUTHORIZED');
	
    poolAuthority.setPublicCapability(collSurplusPool.address, _sweepTokenFunc, true);  
    await th.assertRevert(collSurplusPool.sweepToken(collToken.address, _amt), 'collSurplusPool: Cannot Sweep Collateral');	  
	  
    let _dustToken = await CollateralTokenTester.new()  
    await th.assertRevert(collSurplusPool.sweepToken(_dustToken.address, _amt), 'collSurplusPool: Attempt to sweep more than balance');	
	  
    // expect recipient get dust  
    await _dustToken.deposit({value: _amt});
    await _dustToken.transfer(collSurplusPool.address, _amt); 
    let _feeRecipient = await collSurplusPool.feeRecipientAddress();	
    let _balRecipient = await _dustToken.balanceOf(_feeRecipient);
    await collSurplusPool.sweepToken(_dustToken.address, _amt);
    let _balRecipientAfter = await _dustToken.balanceOf(_feeRecipient);
    let _diff = _balRecipientAfter.sub(_balRecipient);
    assert.isTrue(_diff.toNumber() == _amt);
	
  })
 
  it('sweepToken(): test reentrancy and failed safeTransfer() cases', async () => {
    collSurplusPool = await CollSurplusPool.new(borrowerOperations.address, borrowerOperations.address, activePool.address, poolAuthority.address)
    let _sweepTokenFunc = await collSurplusPool.FUNC_SIG1();
    let _amt = 123456789;
	  
    poolAuthority.setPublicCapability(collSurplusPool.address, _sweepTokenFunc, true);  
    let _dustToken = await ReentrancyToken.new();
	  
    // expect guard against reentrancy
    await _dustToken.deposit({value: _amt, from: owner});
    await _dustToken.transferFrom(owner, collSurplusPool.address, _amt);
    try {
      _dustToken.setSweepPool(collSurplusPool.address);
      await collSurplusPool.sweepToken(_dustToken.address, _amt)
    } catch (err) {
      //console.log("errMsg=" + err.message)
      assert.include(err.message, "ReentrancyGuard: Reentrancy in nonReentrant call")
    }
	
    // expect revert on failed safeTransfer() case 1: transfer() returns false
    try {
      _dustToken.setSweepPool("0x0000000000000000000000000000000000000000");
      await collSurplusPool.sweepToken(_dustToken.address, _amt)
    } catch (err) {
      //console.log("errMsg=" + err.message)
      assert.include(err.message, "SafeERC20: ERC20 operation did not succeed")
    }
	
    // expect revert on failed safeTransfer() case 2: no transfer() exist
    try {
      _dustToken = collSurplusPool;
      await collSurplusPool.sweepToken(_dustToken.address, _amt)
    } catch (err) {
      //console.log("errMsg=" + err.message)
      assert.include(err.message, "SafeERC20: low-level call failed")
    }	
	
    // expect safeTransfer() works with non-standard transfer() like USDT
    // https://etherscan.io/token/0xdac17f958d2ee523a2206206994597c13d831ec7#code#L126
    _dustToken = await SimpleLiquidationTester.new();
    await collSurplusPool.sweepToken(_dustToken.address, _amt);	
  })
})

contract('Reset chain state', async accounts => { })
 