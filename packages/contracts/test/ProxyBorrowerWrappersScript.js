const deploymentHelper = require("../utils/deploymentHelpers.js")
const testHelpers = require("../utils/testHelpers.js")

const CdpManagerTester = artifacts.require("CdpManagerTester")

const th = testHelpers.TestHelper

const dec = th.dec
const toBN = th.toBN
const mv = testHelpers.MoneyValues
const timeValues = testHelpers.TimeValues

const ZERO_ADDRESS = th.ZERO_ADDRESS
const assertRevert = th.assertRevert

const GAS_PRICE = 10000000000 //10GWEI


const {
  buildUserProxies,
  BorrowerOperationsProxy,
  BorrowerWrappersProxy,
  CdpManagerProxy,
  SortedCdpsProxy,
  TokenProxy,
  LQTYStakingProxy
} = require('../utils/proxyHelpers.js')

contract('BorrowerWrappers', async accounts => {

  const [
    owner, alice, bob, carol, dennis, whale,
    A, B, C, D, E,
    defaulter_1, defaulter_2,
    // frontEnd_1, frontEnd_2, frontEnd_3
  ] = accounts;

  const [bountyAddress, lpRewardsAddress, multisig] = accounts.slice(accounts.length - 3, accounts.length)

  let priceFeed
  let ebtcToken
  let sortedCdps
  let cdpManagerOriginal
  let cdpManager
  let activePool
  let defaultPool
  let collSurplusPool
  let borrowerOperations
  let borrowerWrappers
  let lqtyTokenOriginal
  let lqtyToken
  let feeRecipient
  let collToken;

  let contracts

  let liqReward

  const getOpenCdpEBTCAmount = async (totalDebt) => th.getOpenCdpEBTCAmount(contracts, totalDebt)
  const getActualDebtFromComposite = async (compositeDebt) => th.getActualDebtFromComposite(compositeDebt, contracts)
  const getNetBorrowingAmount = async (debtWithFee) => th.getNetBorrowingAmount(contracts, debtWithFee)
  const openCdp = async (params) => th.openCdp(contracts, params)

  beforeEach(async () => {
    contracts = await deploymentHelper.deployTesterContractsHardhat()
    let LQTYContracts = {}
    LQTYContracts.feeRecipient = contracts.feeRecipient;

    await deploymentHelper.connectCoreContracts(contracts, LQTYContracts)
	  
    let originalBorrowerOperations = contracts.borrowerOperations

    cdpManagerOriginal = contracts.cdpManager
    lqtyTokenOriginal = LQTYContracts.lqtyToken

    const users = [ alice, bob, carol, dennis, whale, A, B, C, D, E, defaulter_1, defaulter_2 ]
    await deploymentHelper.deployProxyScripts(contracts, LQTYContracts, owner, users)

    priceFeed = contracts.priceFeedTestnet
    ebtcToken = contracts.ebtcToken
    sortedCdps = contracts.sortedCdps
    cdpManager = contracts.cdpManager
    activePool = contracts.activePool
    defaultPool = contracts.defaultPool
    collSurplusPool = contracts.collSurplusPool
    borrowerOperations = contracts.borrowerOperations
    borrowerWrappers = contracts.borrowerWrappers
    feeRecipient = LQTYContracts.feeRecipient
    lqtyToken = LQTYContracts.lqtyToken
    dummyAddrs = "0x000000000000000000000000000000000000dEaD"
    collToken = contracts.collateral;
    liqReward = await borrowerOperations.LIQUIDATOR_REWARD(); 	
	
    // approve BorrowerOperations for CDP proxy
    for (let usr of users) {
         const usrProxyAddress = borrowerWrappers.getProxyAddressFromUser(usr)
         await collToken.nonStandardSetApproval(usrProxyAddress, originalBorrowerOperations.address, mv._1Be18BN);
    }
  })

  it('proxy owner can recover ETH', async () => {
    const amount = toBN(dec(1, 18))
    const proxyAddress = borrowerWrappers.getProxyAddressFromUser(alice)

    // send some ETH to proxy
    await web3.eth.sendTransaction({ from: owner, to: proxyAddress, value: amount, gasPrice: GAS_PRICE })
    assert.equal(await web3.eth.getBalance(proxyAddress), amount.toString())

    const balanceBefore = toBN(await web3.eth.getBalance(alice))

    // recover ETH
    const gas_Used = th.gasUsed(await borrowerWrappers.transferETH(alice, amount, { from: alice, gasPrice: GAS_PRICE }))
    
    const balanceAfter = toBN(await web3.eth.getBalance(alice))
    const expectedBalance = toBN(balanceBefore.sub(toBN(gas_Used * GAS_PRICE)))
    assert.equal(balanceAfter.sub(expectedBalance), amount.toString())
  })

  it('non proxy owner cannot recover ETH', async () => {
    const amount = toBN(dec(1, 18))
    const proxyAddress = borrowerWrappers.getProxyAddressFromUser(alice)

    // send some ETH to proxy
    await web3.eth.sendTransaction({ from: owner, to: proxyAddress, value: amount })
    assert.equal(await web3.eth.getBalance(proxyAddress), amount.toString())

    const balanceBefore = toBN(await web3.eth.getBalance(alice))

    // try to recover ETH
    const proxy = borrowerWrappers.getProxyFromUser(alice)
    const signature = 'transferETH(address,uint256)'
    const calldata = th.getTransactionData(signature, [alice, amount])
    await assertRevert(proxy.methods["execute(address,bytes)"](borrowerWrappers.scriptAddress, calldata, { from: bob }), 'ds-auth-unauthorized')

    assert.equal(await web3.eth.getBalance(proxyAddress), amount.toString())

    const balanceAfter = toBN(await web3.eth.getBalance(alice))
    assert.equal(balanceAfter, balanceBefore.toString())
  })

  // --- claimCollateralAndOpenCdp ---

  it('claimCollateralAndOpenCdp(): reverts if nothing to claim', async () => {
    // Whale opens Cdp
    await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: whale, usrProxy: borrowerWrappers.getProxyAddressFromUser(whale) } })

    // alice opens Cdp
    const { ebtcAmount, collateral } = await openCdp({ ICR: toBN(dec(15, 17)), extraParams: { from: alice, usrProxy: borrowerWrappers.getProxyAddressFromUser(alice) } })

    const proxyAddress = borrowerWrappers.getProxyAddressFromUser(alice)
    assert.equal(await web3.eth.getBalance(proxyAddress), '0')
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(proxyAddress, 0);

    // alice claims collateral and re-opens the cdp
    await assertRevert(
      borrowerWrappers.claimCollateralAndOpenCdp(ebtcAmount, alice, alice, { from: alice }),
      'CollSurplusPool: No collateral available to claim'
    )

    // check everything remain the same
    assert.equal(await web3.eth.getBalance(proxyAddress), '0')
    th.assertIsApproximatelyEqual(await collSurplusPool.getSurplusCollShares(proxyAddress), '0')
    th.assertIsApproximatelyEqual(await ebtcToken.balanceOf(proxyAddress), ebtcAmount)
    assert.equal(await cdpManager.getCdpStatus(_aliceCdpId), 1)
    th.assertIsApproximatelyEqual(await cdpManager.getCdpCollShares(_aliceCdpId), collateral)
  })

  it('claimCollateralAndOpenCdp(): without sending any value', async () => {
    // alice opens Cdp
    const { ebtcAmount, netDebt: redeemAmount, collateral } = await openCdp({extraEBTCAmount: 0, ICR: toBN(dec(3, 18)), extraParams: { from: alice, usrProxy: borrowerWrappers.getProxyAddressFromUser(alice) } })
    // Whale opens Cdp
    await openCdp({ extraEBTCAmount: redeemAmount, ICR: toBN(dec(5, 18)), extraParams: { from: whale, usrProxy: borrowerWrappers.getProxyAddressFromUser(whale) } })

    const proxyAddress = borrowerWrappers.getProxyAddressFromUser(alice)
    assert.equal(await web3.eth.getBalance(proxyAddress), '0')
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(proxyAddress, 0);
    await th.syncTwapSystemDebt(contracts, ethers.provider);

    // whale redeems 150 EBTC
    await th.redeemCollateral(whale, contracts, redeemAmount, GAS_PRICE)
    assert.equal(await web3.eth.getBalance(proxyAddress), '0')

    // surplus: 5 - 150/200
    const price = await priceFeed.getPrice();
    const expectedSurplus = collateral.sub(redeemAmount.mul(mv._1e18BN).div(price)).add(liqReward)
    th.assertIsApproximatelyEqual(await collSurplusPool.getSurplusCollShares(proxyAddress), expectedSurplus)
    assert.equal(await cdpManager.getCdpStatus(_aliceCdpId), 4) // closed by redemption

    // alice claims collateral and re-opens the cdp
    await borrowerWrappers.claimCollateralAndOpenCdp(ebtcAmount, alice, alice, 0, { from: alice })
    let _aliceCdpId2 = await sortedCdps.cdpOfOwnerByIndex(proxyAddress, 0);

    assert.equal(await web3.eth.getBalance(proxyAddress), '0')
    th.assertIsApproximatelyEqual(await collSurplusPool.getSurplusCollShares(proxyAddress), '0')
    th.assertIsApproximatelyEqual(await ebtcToken.balanceOf(proxyAddress), ebtcAmount.mul(toBN(2)))
    assert.equal(await cdpManager.getCdpStatus(_aliceCdpId2), 1)
    th.assertIsApproximatelyEqual(await cdpManager.getCdpCollShares(_aliceCdpId2), expectedSurplus.sub(liqReward))
  })

  it('claimCollateralAndOpenCdp(): sending value in the transaction', async () => {
    // alice opens Cdp
    const { ebtcAmount, netDebt: redeemAmount, collateral } = await openCdp({ ICR: toBN(dec(151, 16)), extraParams: { from: alice, usrProxy: borrowerWrappers.getProxyAddressFromUser(alice) } })
    // Whale opens Cdp
    await openCdp({ extraEBTCAmount: redeemAmount, ICR: toBN(dec(2, 18)), extraParams: { from: whale, usrProxy: borrowerWrappers.getProxyAddressFromUser(whale) } })

    const proxyAddress = borrowerWrappers.getProxyAddressFromUser(alice)
    assert.equal(await web3.eth.getBalance(proxyAddress), '0')
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(proxyAddress, 0);
    await th.syncTwapSystemDebt(contracts, ethers.provider);

    // whale redeems 150 EBTC
    await th.redeemCollateral(whale, contracts, redeemAmount, GAS_PRICE)
    assert.equal(await web3.eth.getBalance(proxyAddress), '0')

    // surplus: 5 - 150/200
    const price = await priceFeed.getPrice();
    const expectedSurplus = collateral.sub(redeemAmount.mul(mv._1e18BN).div(price)).add(liqReward)
    th.assertIsApproximatelyEqual(await collSurplusPool.getSurplusCollShares(proxyAddress), expectedSurplus)
    assert.equal(await cdpManager.getCdpStatus(_aliceCdpId), 4) // closed by redemption

    // alice claims collateral and re-opens the cdp
    await collToken.transfer(borrowerWrappers.getProxyAddressFromUser(alice), collateral, {from: alice});
    await borrowerWrappers.claimCollateralAndOpenCdp(ebtcAmount, alice, alice, collateral, { from: alice, value: 0 })
    let _aliceCdpId2 = await sortedCdps.cdpOfOwnerByIndex(proxyAddress, 0);

    assert.equal(await web3.eth.getBalance(proxyAddress), '0')
    th.assertIsApproximatelyEqual(await collSurplusPool.getSurplusCollShares(proxyAddress), '0')
    th.assertIsApproximatelyEqual(await ebtcToken.balanceOf(proxyAddress), ebtcAmount.mul(toBN(2)))
    assert.equal(await cdpManager.getCdpStatus(_aliceCdpId2), 1)
    th.assertIsApproximatelyEqual(await cdpManager.getCdpCollShares(_aliceCdpId2), expectedSurplus.add(collateral).sub(liqReward))
  })

  // --- claimSPRewardsAndRecycle ---

  xit('claimSPRewardsAndRecycle(): only owner can call it', async () => {
    // Whale opens Cdp
    await openCdp({ extraEBTCAmount: toBN(dec(1850, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: whale, usrProxy: borrowerWrappers.getProxyAddressFromUser(whale) } })

    // alice opens cdp
    await openCdp({ extraEBTCAmount: toBN(dec(150, 18)), extraParams: { from: alice, usrProxy: borrowerWrappers.getProxyAddressFromUser(alice) } })

    // Defaulter Cdp opened
    const { ebtcAmount, netDebt, collateral } = await openCdp({ ICR: toBN(dec(210, 16)), extraParams: { from: defaulter_1, usrProxy: borrowerWrappers.getProxyAddressFromUser(defaulter_1) } })
    const defaulterProxyAddress = borrowerWrappers.getProxyAddressFromUser(defaulter_1);
    let _defaulterCdpId1 = await sortedCdps.cdpOfOwnerByIndex(defaulterProxyAddress, 0);

    // price drops: defaulters' Cdps fall below MCR, alice and whale Cdp remain active
    const price = toBN(dec(1500, 13))
    await priceFeed.setPrice(price);

    // Defaulter cdp closed
    await openCdp({ ICR: toBN(dec(210, 16)), extraEBTCAmount: netDebt, extraParams: { from: owner, usrProxy: borrowerWrappers.getProxyAddressFromUser(owner) } }) 
    const liquidationTX_1 = await cdpManager.liquidate(_defaulterCdpId1, { from: owner })
    const [liquidatedDebt_1] = await th.getEmittedLiquidationValues(liquidationTX_1)

    // Bob tries to claims SP rewards in behalf of Alice
    const proxy = borrowerWrappers.getProxyFromUser(alice)
    const signature = 'claimSPRewardsAndRecycle(uint256,address,address)'
    const calldata = th.getTransactionData(signature, [th._100pct, alice, alice])
    await assertRevert(proxy.methods["execute(address,bytes)"](borrowerWrappers.scriptAddress, calldata, { from: bob }), 'ds-auth-unauthorized')
  })

  xit('claimSPRewardsAndRecycle():', async () => {
    // Whale opens Cdp
    const whaleDeposit = toBN(dec(2350, 18))
    await openCdp({ extraEBTCAmount: whaleDeposit, ICR: toBN(dec(4, 18)), extraParams: { from: whale, usrProxy: borrowerWrappers.getProxyAddressFromUser(whale) } })

    // alice opens cdp
    const aliceDeposit = toBN(dec(150, 18))
    await openCdp({ extraEBTCAmount: aliceDeposit, ICR: toBN(dec(3, 18)), extraParams: { from: alice, usrProxy: borrowerWrappers.getProxyAddressFromUser(alice) } })
    const aliceProxyAddress = borrowerWrappers.getProxyAddressFromUser(alice);
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(aliceProxyAddress, 0);

    // Defaulter Cdp opened
    const { ebtcAmount, netDebt, collateral } = await openCdp({ ICR: toBN(dec(210, 16)), extraParams: { from: defaulter_1, usrProxy: borrowerWrappers.getProxyAddressFromUser(defaulter_1) } })
    const defaulterProxyAddress = borrowerWrappers.getProxyAddressFromUser(defaulter_1);
    let _defaulterCdpId1 = await sortedCdps.cdpOfOwnerByIndex(defaulterProxyAddress, 0);

    // price drops: defaulters' Cdps fall below MCR, alice and whale Cdp remain active
    const price = toBN(dec(1500, 13))
    await priceFeed.setPrice(price);

    // Defaulter cdp closed
    await openCdp({ ICR: toBN(dec(210, 16)), extraEBTCAmount: netDebt, extraParams: { from: owner, usrProxy: borrowerWrappers.getProxyAddressFromUser(owner) } }) 
    const liquidationTX_1 = await cdpManager.liquidate(_defaulterCdpId1, { from: owner })
    const [liquidatedDebt_1] = await th.getEmittedLiquidationValues(liquidationTX_1)

    // Alice EBTCLoss is ((150/2500) * liquidatedDebt)
    const totalDeposits = whaleDeposit.add(aliceDeposit)

    // collateral * 150 / 2500 * 0.995 deprecated due to removal of stability pool
    const expectedETHGain_A = toBN('0').mul(aliceDeposit).div(totalDeposits).mul(toBN(dec(995, 15))).div(mv._1e18BN)

    const ethBalanceBefore = await web3.eth.getBalance(borrowerOperations.getProxyAddressFromUser(alice))
    const cdpCollBefore = await cdpManager.getCdpCollShares(_aliceCdpId)
    const ebtcBalanceBefore = await ebtcToken.balanceOf(alice)
    const cdpDebtBefore = await cdpManager.getCdpDebt(_aliceCdpId)
    const lqtyBalanceBefore = await lqtyToken.balanceOf(alice)
    const ICRBefore = await cdpManager.getCachedICR(_aliceCdpId, price)

    const proportionalEBTC = expectedETHGain_A.mul(price).div(ICRBefore)

    // to force LQTY issuance
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_WEEK * 2, web3.currentProvider)


    await priceFeed.setPrice(price.mul(toBN(2)));

    const ethBalanceAfter = await web3.eth.getBalance(borrowerOperations.getProxyAddressFromUser(alice))
    const cdpCollAfter = await cdpManager.getCdpCollShares(_aliceCdpId)
    const ebtcBalanceAfter = await ebtcToken.balanceOf(alice)
    const cdpDebtAfter = await cdpManager.getCdpDebt(_aliceCdpId)
    const lqtyBalanceAfter = await lqtyToken.balanceOf(alice)
    const ICRAfter = await cdpManager.getCachedICR(_aliceCdpId, price)
    const stakeAfter = await feeRecipient.stakes(alice)

    // check proxy balances remain the same
    assert.equal(ethBalanceAfter.toString(), ethBalanceBefore.toString())
    assert.equal(ebtcBalanceAfter.toString(), ebtcBalanceBefore.toString())
    assert.equal(lqtyBalanceAfter.toString(), lqtyBalanceBefore.toString())
    // check cdp has increased debt by the ICR proportional amount to ETH gain
    th.assertIsApproximatelyEqual(cdpDebtAfter, cdpDebtBefore.add(proportionalEBTC))
    // check cdp has increased collateral by the ETH gain
    th.assertIsApproximatelyEqual(cdpCollAfter, cdpCollBefore.add(expectedETHGain_A))
    // check that ICR remains constant
    th.assertIsApproximatelyEqual(ICRAfter, ICRBefore)
    // check lqty balance remains the same
    th.assertIsApproximatelyEqual(lqtyBalanceAfter, lqtyBalanceBefore)

    // LQTY staking deprecated due to removal of stability pool
//    th.assertIsApproximatelyEqual(stakeAfter, stakeBefore.add(expectedLQTYGain_A))
  })


  // --- claimStakingGainsAndRecycle ---

  xit('claimStakingGainsAndRecycle(): only owner can call it', async () => {
    // Whale opens Cdp
    await openCdp({ extraEBTCAmount: toBN(dec(1850, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: whale, usrProxy: borrowerWrappers.getProxyAddressFromUser(whale) } })

    // alice opens cdp
    await openCdp({ extraEBTCAmount: toBN(dec(150, 18)), extraParams: { from: alice, usrProxy: borrowerWrappers.getProxyAddressFromUser(alice) } })

    // Skip liquity portion
    // // mint some LQTY
    // await lqtyTokenOriginal.unprotectedMint(borrowerOperations.getProxyAddressFromUser(whale), dec(1850, 18))
    // await lqtyTokenOriginal.unprotectedMint(borrowerOperations.getProxyAddressFromUser(alice), dec(150, 18))

    // // stake LQTY
    // await feeRecipient.stake(dec(1850, 18), { from: whale })
    // await feeRecipient.stake(dec(150, 18), { from: alice })

    // Defaulter Cdp opened
    const { ebtcAmount, netDebt, totalDebt, collateral } = await openCdp({ ICR: toBN(dec(210, 16)), extraParams: { from: defaulter_1, usrProxy: borrowerWrappers.getProxyAddressFromUser(defaulter_1) } })

    // whale redeems 100 EBTC
    const redeemedAmount = toBN(dec(100, 18))
    await th.redeemCollateral(whale, contracts, redeemedAmount, GAS_PRICE)

    // Bob tries to claims staking gains in behalf of Alice
    const proxy = borrowerWrappers.getProxyFromUser(alice)
  const signature = 'claimStakingGainsAndRecycle(bytes32,bytes32,bytes32)'
    const calldata = th.getTransactionData(signature, [th._100pct, alice, alice])
    await assertRevert(proxy.methods["execute(address,bytes)"](borrowerWrappers.scriptAddress, calldata, { from: bob }), 'ds-auth-unauthorized')
  })

  xit('claimStakingGainsAndRecycle(): reverts if user has no cdp', async () => {
    const price = toBN(dec(200, 18))

    // Whale opens Cdp
    await openCdp({ extraEBTCAmount: toBN(dec(1850, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: whale, usrProxy: borrowerWrappers.getProxyAddressFromUser(whale) } })

    // Skip liquity portion
    // mint some LQTY
    await lqtyTokenOriginal.unprotectedMint(borrowerOperations.getProxyAddressFromUser(whale), dec(1850, 18))
    await lqtyTokenOriginal.unprotectedMint(borrowerOperations.getProxyAddressFromUser(alice), dec(150, 18))

    // stake LQTY
    await feeRecipient.stake(dec(1850, 18), { from: whale })
    await feeRecipient.stake(dec(150, 18), { from: alice })

    // Defaulter Cdp opened
    const { ebtcAmount, netDebt, totalDebt, collateral } = await openCdp({ ICR: toBN(dec(210, 16)), extraParams: { from: defaulter_1, usrProxy: borrowerWrappers.getProxyAddressFromUser(defaulter_1) } })
    const borrowingFee = netDebt.sub(ebtcAmount)

    // Alice EBTC gain is ((150/2000) * borrowingFee)
    const expectedEBTCGain_A = borrowingFee.mul(toBN(dec(150, 18))).div(toBN(dec(2000, 18)))

    // whale redeems 100 EBTC
    const redeemedAmount = toBN(dec(100, 18))
    await th.redeemCollateral(whale, contracts, redeemedAmount, GAS_PRICE)

    const ethBalanceBefore = await web3.eth.getBalance(borrowerOperations.getProxyAddressFromUser(alice))
    const cdpCollBefore = await cdpManager.getCdpCollShares(th.DUMMY_BYTES32)
    const ebtcBalanceBefore = await ebtcToken.balanceOf(alice)
    const cdpDebtBefore = await cdpManager.getCdpDebt(th.DUMMY_BYTES32)
    const lqtyBalanceBefore = await lqtyToken.balanceOf(alice)
    const ICRBefore = await cdpManager.getCachedICR(th.DUMMY_BYTES32, price)
    const stakeBefore = await feeRecipient.stakes(alice)

    // Alice claims staking rewards and puts them back in the system through the proxy
    await assertRevert(
      borrowerWrappers.claimStakingGainsAndRecycle(th.DUMMY_BYTES32, th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: alice }),
      'BorrowerWrappersScript: caller must have an active cdp'
    )

    const ethBalanceAfter = await web3.eth.getBalance(borrowerOperations.getProxyAddressFromUser(alice))
    const cdpCollAfter = await cdpManager.getCdpCollShares(th.DUMMY_BYTES32)
    const ebtcBalanceAfter = await ebtcToken.balanceOf(alice)
    const cdpDebtAfter = await cdpManager.getCdpDebt(th.DUMMY_BYTES32)
    const lqtyBalanceAfter = await lqtyToken.balanceOf(alice)
    const ICRAfter = await cdpManager.getCachedICR(th.DUMMY_BYTES32, price)
    const stakeAfter = await feeRecipient.stakes(alice)

    // check everything remains the same
    assert.equal(ethBalanceAfter.toString(), ethBalanceBefore.toString())
    assert.equal(ebtcBalanceAfter.toString(), ebtcBalanceBefore.toString())
    assert.equal(lqtyBalanceAfter.toString(), lqtyBalanceBefore.toString())
    th.assertIsApproximatelyEqual(cdpDebtAfter, cdpDebtBefore, 10000)
    th.assertIsApproximatelyEqual(cdpCollAfter, cdpCollBefore)
    th.assertIsApproximatelyEqual(ICRAfter, ICRBefore)
    th.assertIsApproximatelyEqual(lqtyBalanceBefore, lqtyBalanceAfter)
    // LQTY staking
    th.assertIsApproximatelyEqual(stakeAfter, stakeBefore)
  })

})
