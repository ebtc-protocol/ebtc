const deploymentHelper = require("../utils/deploymentHelpers.js")
const testHelpers = require("../utils/testHelpers.js")
const CdpManagerTester = artifacts.require("./CdpManagerTester.sol")
const BorrowerOperationsTester = artifacts.require("./BorrowerOperationsTester.sol")
const EBTCToken = artifacts.require("EBTCToken")

const th = testHelpers.TestHelper
const dec = th.dec
const toBN = th.toBN
const mv = testHelpers.MoneyValues
const ZERO_ADDRESS = th.ZERO_ADDRESS

const GAS_PRICE = 10000000

const hre = require("hardhat");

contract('Gas compensation tests', async accounts => {
  const [
    owner, liquidator,
    alice, bob, carol, dennis, erin, flyn, graham, harriet, ida,
    defaulter_1, defaulter_2, defaulter_3, defaulter_4, whale] = accounts;

    const [bountyAddress, lpRewardsAddress, multisig] = accounts.slice(accounts.length - 3, accounts.length)
    const bn8 = "0x00000000219ab540356cBB839Cbe05303d7705Fa";//beacon deposit
    let bn8Signer;

  let priceFeed
  let ebtcToken
  let sortedCdps
  let cdpManager
  let activePool
  let stabilityPool
  let defaultPool
  let borrowerOperations

  let contracts
  let cdpManagerTester
  let borrowerOperationsTester

  const getOpenCdpEBTCAmount = async (totalDebt) => th.getOpenCdpEBTCAmount(contracts, totalDebt)
  const openCdp = async (params) => th.openCdp(contracts, params)

  const logICRs = (ICRList) => {
    for (let i = 0; i < ICRList.length; i++) {
      console.log(`account: ${i + 1} ICR: ${ICRList[i].toString()}`)
    }
  }

  before(async () => {
    cdpManagerTester = await CdpManagerTester.new()
    borrowerOperationsTester = await BorrowerOperationsTester.new()

    CdpManagerTester.setAsDeployed(cdpManagerTester)
    BorrowerOperationsTester.setAsDeployed(borrowerOperationsTester)
	
    await hre.network.provider.request({method: "hardhat_impersonateAccount", params: [bn8]}); 
    bn8Signer = await ethers.provider.getSigner(bn8);
  })

  beforeEach(async () => {
    contracts = await deploymentHelper.deployLiquityCore()
    contracts.cdpManager = await CdpManagerTester.new()
    contracts.ebtcToken = await EBTCToken.new(
      contracts.cdpManager.address,
      contracts.stabilityPool.address,
      contracts.borrowerOperations.address
    )
    const LQTYContracts = await deploymentHelper.deployLQTYContracts(bountyAddress, lpRewardsAddress, multisig)

    priceFeed = contracts.priceFeedTestnet
    ebtcToken = contracts.ebtcToken
    sortedCdps = contracts.sortedCdps
    cdpManager = contracts.cdpManager
    activePool = contracts.activePool
    stabilityPool = contracts.stabilityPool
    defaultPool = contracts.defaultPool
    borrowerOperations = contracts.borrowerOperations

    await deploymentHelper.connectLQTYContracts(LQTYContracts)
    await deploymentHelper.connectCoreContracts(contracts, LQTYContracts) 
    await deploymentHelper.connectLQTYContractsToCore(LQTYContracts, contracts)

    ownerSigner = await ethers.provider.getSigner(owner);
    let _ownerBal = await web3.eth.getBalance(owner);
    let _bn8Bal = await web3.eth.getBalance(bn8);
    let _ownerRicher = toBN(_ownerBal.toString()).gt(toBN(_bn8Bal.toString()));
    let _signer = _ownerRicher? ownerSigner : bn8Signer;
	
    await _signer.sendTransaction({ to: whale, value: ethers.utils.parseEther("14000")});
    await _signer.sendTransaction({ to: dennis, value: ethers.utils.parseEther("12000")});
    await _signer.sendTransaction({ to: erin, value: ethers.utils.parseEther("12000")});
    
    const signer_address = await _signer.getAddress()
    const b8nSigner_address = await bn8Signer.getAddress()

    // Ensure bn8Signer has funds if it doesn't in this fork state
    if (signer_address != b8nSigner_address) {
      await _signer.sendTransaction({ to: b8nSigner_address, value: ethers.utils.parseEther("2000000")});
    }
  })

  // --- Raw gas compensation calculations ---

  it('_getCollGasCompensation(): returns the 0.5% of collaterall if it is < $10 in value', async () => {
    /* 
    ETH:USD price = 1
    coll = 1 ETH: $1 in value
    -> Expect 0.5% of collaterall as gas compensation */
    await priceFeed.setPrice(dec(1, 18))
    // const price_1 = await priceFeed.getPrice()
    const gasCompensation_1 = (await cdpManagerTester.getCollGasCompensation(dec(1, 'ether'))).toString()
    assert.equal(gasCompensation_1, dec(5, 15))

    /* 
    ETH:USD price = 28.4
    coll = 0.1 ETH: $2.84 in value
    -> Expect 0.5% of collaterall as gas compensation */
    await priceFeed.setPrice('28400000000000000000')
    // const price_2 = await priceFeed.getPrice()
    const gasCompensation_2 = (await cdpManagerTester.getCollGasCompensation(dec(100, 'finney'))).toString()
    assert.equal(gasCompensation_2, dec(5, 14))

    /* 
    ETH:USD price = 1000000000 (1 billion)
    coll = 0.000000005 ETH (5e9 wei): $5 in value 
    -> Expect 0.5% of collaterall as gas compensation */
    await priceFeed.setPrice(dec(1, 27))
    // const price_3 = await priceFeed.getPrice()
    const gasCompensation_3 = (await cdpManagerTester.getCollGasCompensation('5000000000')).toString()
    assert.equal(gasCompensation_3, '25000000')
  })

  it('_getCollGasCompensation(): returns 0.5% of collaterall when 0.5% of collateral < $10 in value', async () => {
    const price = await priceFeed.getPrice()
    assert.equal(price, dec(200, 18))

    /* 
    ETH:USD price = 200
    coll = 9.999 ETH  
    0.5% of coll = 0.04995 ETH. USD value: $9.99
    -> Expect 0.5% of collaterall as gas compensation */
    const gasCompensation_1 = (await cdpManagerTester.getCollGasCompensation('9999000000000000000')).toString()
    assert.equal(gasCompensation_1, '49995000000000000')

    /* ETH:USD price = 200
     coll = 0.055 ETH  
     0.5% of coll = 0.000275 ETH. USD value: $0.055
     -> Expect 0.5% of collaterall as gas compensation */
    const gasCompensation_2 = (await cdpManagerTester.getCollGasCompensation('55000000000000000')).toString()
    assert.equal(gasCompensation_2, dec(275, 12))

    /* ETH:USD price = 200
    coll = 6.09232408808723580 ETH  
    0.5% of coll = 0.004995 ETH. USD value: $6.09
    -> Expect 0.5% of collaterall as gas compensation */
    const gasCompensation_3 = (await cdpManagerTester.getCollGasCompensation('6092324088087235800')).toString()
    assert.equal(gasCompensation_3, '30461620440436179')
  })

  it('getCollGasCompensation(): returns 0.5% of collaterall when 0.5% of collateral = $10 in value', async () => {
    const price = await priceFeed.getPrice()
    assert.equal(price, dec(200, 18))

    /* 
    ETH:USD price = 200
    coll = 10 ETH  
    0.5% of coll = 0.5 ETH. USD value: $10
    -> Expect 0.5% of collaterall as gas compensation */
    const gasCompensation = (await cdpManagerTester.getCollGasCompensation(dec(10, 'ether'))).toString()
    assert.equal(gasCompensation, '50000000000000000')
  })

  it('getCollGasCompensation(): returns 0.5% of collaterall when 0.5% of collateral = $10 in value', async () => {
    const price = await priceFeed.getPrice()
    assert.equal(price, dec(200, 18))

    /* 
    ETH:USD price = 200 $/E
    coll = 100 ETH  
    0.5% of coll = 0.5 ETH. USD value: $100
    -> Expect $100 gas compensation, i.e. 0.5 ETH */
    const gasCompensation_1 = (await cdpManagerTester.getCollGasCompensation(dec(100, 'ether'))).toString()
    assert.equal(gasCompensation_1, dec(500, 'finney'))

    /* 
    ETH:USD price = 200 $/E
    coll = 10.001 ETH  
    0.5% of coll = 0.050005 ETH. USD value: $10.001
    -> Expect $100 gas compensation, i.e.  0.050005  ETH */
    const gasCompensation_2 = (await cdpManagerTester.getCollGasCompensation('10001000000000000000')).toString()
    assert.equal(gasCompensation_2, '50005000000000000')

    /* 
    ETH:USD price = 200 $/E
    coll = 37.5 ETH  
    0.5% of coll = 0.1875 ETH. USD value: $37.5
    -> Expect $37.5 gas compensation i.e.  0.1875  ETH */
    const gasCompensation_3 = (await cdpManagerTester.getCollGasCompensation('37500000000000000000')).toString()
    assert.equal(gasCompensation_3, '187500000000000000')

    /* 
    ETH:USD price = 45323.54542 $/E
    coll = 94758.230582309850 ETH  
    0.5% of coll = 473.7911529 ETH. USD value: $21473894.84
    -> Expect $21473894.8385808 gas compensation, i.e.  473.7911529115490  ETH */
    await priceFeed.setPrice('45323545420000000000000')
    const gasCompensation_4 = await cdpManagerTester.getCollGasCompensation('94758230582309850000000')
    assert.isAtMost(th.getDifference(gasCompensation_4, '473791152911549000000'), 1000000)

    /* 
    ETH:USD price = 1000000 $/E (1 million)
    coll = 300000000 ETH   (300 million)
    0.5% of coll = 1500000 ETH. USD value: $150000000000
    -> Expect $150000000000 gas compensation, i.e. 1500000 ETH */
    await priceFeed.setPrice(dec(1, 24))
    const price_2 = await priceFeed.getPrice()
    const gasCompensation_5 = (await cdpManagerTester.getCollGasCompensation('300000000000000000000000000')).toString()
    assert.equal(gasCompensation_5, '1500000000000000000000000')
  })

  // --- Composite debt calculations ---

  // gets debt + 50 when 0.5% of coll < $10
  it('_getCompositeDebt(): returns (debt + 50) when collateral < $10 in value', async () => {
    const price = await priceFeed.getPrice()
    assert.equal(price, dec(200, 18))

    /* 
    ETH:USD price = 200
    coll = 9.999 ETH 
    debt = 10 EBTC
    0.5% of coll = 0.04995 ETH. USD value: $9.99
    -> Expect composite debt = 10 + 200  = 2100 EBTC*/
    const compositeDebt_1 = await cdpManagerTester.getCompositeDebt(dec(10, 18))
    assert.equal(compositeDebt_1, dec(210, 18))

    /* ETH:USD price = 200
     coll = 0.055 ETH  
     debt = 0 EBTC
     0.5% of coll = 0.000275 ETH. USD value: $0.055
     -> Expect composite debt = 0 + 200 = 200 EBTC*/
    const compositeDebt_2 = await cdpManagerTester.getCompositeDebt(0)
    assert.equal(compositeDebt_2, dec(200, 18))

    // /* ETH:USD price = 200
    // coll = 6.09232408808723580 ETH 
    // debt = 200 EBTC 
    // 0.5% of coll = 0.004995 ETH. USD value: $6.09
    // -> Expect  composite debt =  200 + 200 = 400  EBTC */
    const compositeDebt_3 = await cdpManagerTester.getCompositeDebt(dec(200, 18))
    assert.equal(compositeDebt_3, '400000000000000000000')
  })

  // returns $10 worth of ETH when 0.5% of coll == $10
  it('getCompositeDebt(): returns (debt + 50) collateral = $10 in value', async () => {
    const price = await priceFeed.getPrice()
    assert.equal(price, dec(200, 18))

    /* 
    ETH:USD price = 200
    coll = 10 ETH  
    debt = 123.45 EBTC
    0.5% of coll = 0.5 ETH. USD value: $10
    -> Expect composite debt = (123.45 + 200) = 323.45 EBTC  */
    const compositeDebt = await cdpManagerTester.getCompositeDebt('123450000000000000000')
    assert.equal(compositeDebt, '323450000000000000000')
  })

  /// *** 

  // gets debt + 50 when 0.5% of coll > 10
  it('getCompositeDebt(): returns (debt + 50) when 0.5% of collateral > $10 in value', async () => {
    const price = await priceFeed.getPrice()
    assert.equal(price, dec(200, 18))

    /* 
    ETH:USD price = 200 $/E
    coll = 100 ETH  
    debt = 2000 EBTC
    -> Expect composite debt = (2000 + 200) = 2200 EBTC  */
    const compositeDebt_1 = (await cdpManagerTester.getCompositeDebt(dec(2000, 18))).toString()
    assert.equal(compositeDebt_1, '2200000000000000000000')

    /* 
    ETH:USD price = 200 $/E
    coll = 10.001 ETH  
    debt = 200 EBTC
    -> Expect composite debt = (200 + 200) = 400 EBTC  */
    const compositeDebt_2 = (await cdpManagerTester.getCompositeDebt(dec(200, 18))).toString()
    assert.equal(compositeDebt_2, '400000000000000000000')

    /* 
    ETH:USD price = 200 $/E
    coll = 37.5 ETH  
    debt = 500 EBTC
    -> Expect composite debt = (500 + 200) = 700 EBTC  */
    const compositeDebt_3 = (await cdpManagerTester.getCompositeDebt(dec(500, 18))).toString()
    assert.equal(compositeDebt_3, '700000000000000000000')

    /* 
    ETH:USD price = 45323.54542 $/E
    coll = 94758.230582309850 ETH  
    debt = 1 billion EBTC
    -> Expect composite debt = (1000000000 + 200) = 1000000200 EBTC  */
    await priceFeed.setPrice('45323545420000000000000')
    const price_2 = await priceFeed.getPrice()
    const compositeDebt_4 = (await cdpManagerTester.getCompositeDebt(dec(1, 27))).toString()
    assert.isAtMost(th.getDifference(compositeDebt_4, '1000000200000000000000000000'), 100000000000)

    /* 
    ETH:USD price = 1000000 $/E (1 million)
    coll = 300000000 ETH   (300 million)
    debt = 54321.123456789 EBTC
   -> Expect composite debt = (54321.123456789 + 200) = 54521.123456789 EBTC */
    await priceFeed.setPrice(dec(1, 24))
    const price_3 = await priceFeed.getPrice()
    const compositeDebt_5 = (await cdpManagerTester.getCompositeDebt('54321123456789000000000')).toString()
    assert.equal(compositeDebt_5, '54521123456789000000000')
  })

  // --- Test ICRs with virtual debt ---
  it('getCurrentICR(): Incorporates virtual debt, and returns the correct ICR for new cdps', async () => {
    const price = await priceFeed.getPrice()
    await openCdp({ ICR: toBN(dec(200, 18)), extraParams: { from: whale } })

    // A opens with 1 ETH, 110 EBTC
    await openCdp({ ICR: toBN('1818181818181818181'), extraParams: { from: alice } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    const alice_ICR = (await cdpManager.getCurrentICR(_aliceCdpId, price)).toString()
    // Expect aliceICR = (1 * 200) / (110) = 181.81%
    assert.isAtMost(th.getDifference(alice_ICR, '1818181818181818181'), 1000)

    // B opens with 0.5 ETH, 50 EBTC
    await openCdp({ ICR: toBN(dec(2, 18)), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    const bob_ICR = (await cdpManager.getCurrentICR(_bobCdpId, price)).toString()
    // Expect Bob's ICR = (0.5 * 200) / 50 = 200%
    assert.isAtMost(th.getDifference(bob_ICR, dec(2, 18)), 1000)

    // F opens with 1 ETH, 100 EBTC
    await openCdp({ ICR: toBN(dec(2, 18)), extraEBTCAmount: dec(100, 18), extraParams: { from: flyn } })
    let _flynCdpId = await sortedCdps.cdpOfOwnerByIndex(flyn, 0);
    const flyn_ICR = (await cdpManager.getCurrentICR(_flynCdpId, price)).toString()
    // Expect Flyn's ICR = (1 * 200) / 100 = 200%
    assert.isAtMost(th.getDifference(flyn_ICR, dec(2, 18)), 1000)

    // C opens with 2.5 ETH, 160 EBTC
    await openCdp({ ICR: toBN(dec(3125, 15)), extraParams: { from: carol } })
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    const carol_ICR = (await cdpManager.getCurrentICR(_carolCdpId, price)).toString()
    // Expect Carol's ICR = (2.5 * 200) / (160) = 312.50%
    assert.isAtMost(th.getDifference(carol_ICR, '3125000000000000000'), 1000)

    // D opens with 1 ETH, 0 EBTC
    await openCdp({ ICR: toBN(dec(4, 18)), extraParams: { from: dennis } })
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);
    const dennis_ICR = (await cdpManager.getCurrentICR(_dennisCdpId, price)).toString()
    // Expect Dennis's ICR = (1 * 200) / (50) = 400.00%
    assert.isAtMost(th.getDifference(dennis_ICR, dec(4, 18)), 1000)

    // E opens with 4405.45 ETH, 32598.35 EBTC
    await openCdp({ ICR: toBN('27028668628933700000'), extraParams: { from: erin } })
    let _erinCdpId = await sortedCdps.cdpOfOwnerByIndex(erin, 0);
    const erin_ICR = (await cdpManager.getCurrentICR(_erinCdpId, price)).toString()
    // Expect Erin's ICR = (4405.45 * 200) / (32598.35) = 2702.87%
    assert.isAtMost(th.getDifference(erin_ICR, '27028668628933700000'), 100000)

    // H opens with 1 ETH, 180 EBTC
    await openCdp({ ICR: toBN('1111111111111111111'), extraParams: { from: harriet } })
    let _harrietCdpId = await sortedCdps.cdpOfOwnerByIndex(harriet, 0);
    const harriet_ICR = (await cdpManager.getCurrentICR(_harrietCdpId, price)).toString()
    // Expect Harriet's ICR = (1 * 200) / (180) = 111.11%
    assert.isAtMost(th.getDifference(harriet_ICR, '1111111111111111111'), 1000)
  })

  // Test compensation amounts and liquidation amounts

  it('Gas compensation from pool-offset liquidations. All collateral paid as compensation', async () => {
    await openCdp({ ICR: toBN(dec(2000, 18)), extraParams: { from: whale } })

    // A-E open cdps
    const { totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(2, 18)), extraEBTCAmount: dec(100, 18), extraParams: { from: alice } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
	
    const { totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(2, 18)), extraEBTCAmount: dec(200, 18), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
	
    const { totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(2, 18)), extraEBTCAmount: dec(300, 18), extraParams: { from: carol } })
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
	
    await openCdp({ ICR: toBN(dec(2, 18)), extraEBTCAmount: A_totalDebt, extraParams: { from: dennis } })
    await openCdp({ ICR: toBN(dec(2, 18)), extraEBTCAmount: B_totalDebt.add(C_totalDebt), extraParams: { from: erin } })

    // D, E each provide EBTC to SP
    await stabilityPool.provideToSP(A_totalDebt, ZERO_ADDRESS, { from: dennis, gasPrice: GAS_PRICE })
    await stabilityPool.provideToSP(B_totalDebt.add(C_totalDebt), ZERO_ADDRESS, { from: erin, gasPrice: GAS_PRICE })

    const EBTCinSP_0 = await stabilityPool.getTotalEBTCDeposits()

    // --- Price drops to 9.99 ---
    await priceFeed.setPrice('9990000000000000000')
    const price_1 = await priceFeed.getPrice()

    /* 
    ETH:USD price = 9.99
    -> Expect 0.5% of collaterall to be sent to liquidator, as gas compensation */

    // Check collateral value in USD is < $10
    const aliceColl = (await cdpManager.Cdps(_aliceCdpId))[1]

    assert.isFalse(await th.checkRecoveryMode(contracts))

    // Liquidate A (use 0 gas price to easily check the amount the compensation amount the liquidator receives)
    const liquidatorBalance_before_A = web3.utils.toBN(await web3.eth.getBalance(liquidator))
    let _liqAliceTx = await cdpManager.liquidate(_aliceCdpId, { from: liquidator, gasPrice: GAS_PRICE });
    const A_GAS_Used_Liquidator = th.gasUsed(_liqAliceTx)
    const liquidatorBalance_after_A = web3.utils.toBN(await web3.eth.getBalance(liquidator))
	
    // Check liquidator's balance increases by 0.5% of A's coll (1 ETH)
    const compensationReceived_A = (liquidatorBalance_after_A.sub(liquidatorBalance_before_A).add(toBN(A_GAS_Used_Liquidator * GAS_PRICE))).toString()
    const _0pt5percent_aliceColl = aliceColl.div(web3.utils.toBN('200'))
    assert.equal(compensationReceived_A, _0pt5percent_aliceColl)

    // Check SP EBTC has decreased due to the liquidation 
    const EBTCinSP_A = await stabilityPool.getTotalEBTCDeposits()
    assert.isTrue(EBTCinSP_A.lte(EBTCinSP_0))

    // Check ETH in SP has received the liquidation
    const ETHinSP_A = await stabilityPool.getETH()
    assert.equal(ETHinSP_A.toString(), aliceColl.sub(_0pt5percent_aliceColl)) // 1 ETH - 0.5%

    // --- Price drops to 3 ---
    await priceFeed.setPrice(dec(3, 18))
    const price_2 = await priceFeed.getPrice()

    /* 
    ETH:USD price = 3
    -> Expect 0.5% of collaterall to be sent to liquidator, as gas compensation */

    // Check collateral value in USD is < $10
    const bobColl = (await cdpManager.Cdps(_bobCdpId))[1]

    assert.isFalse(await th.checkRecoveryMode(contracts))
    // Liquidate B (use 0 gas price to easily check the amount the compensation amount the liquidator receives)
    const liquidatorBalance_before_B = web3.utils.toBN(await web3.eth.getBalance(liquidator))
    const B_GAS_Used_Liquidator = th.gasUsed(await cdpManager.liquidate(_bobCdpId, { from: liquidator, gasPrice: GAS_PRICE }))
    const liquidatorBalance_after_B = web3.utils.toBN(await web3.eth.getBalance(liquidator))

    // Check liquidator's balance increases by B's 0.5% of coll, 2 ETH
    const compensationReceived_B = (liquidatorBalance_after_B.sub(liquidatorBalance_before_B).add(toBN(B_GAS_Used_Liquidator * GAS_PRICE))).toString()
    const _0pt5percent_bobColl = bobColl.div(web3.utils.toBN('200'))
    assert.equal(compensationReceived_B, _0pt5percent_bobColl) // 0.5% of 2 ETH

    // Check SP EBTC has decreased due to the liquidation of B
    const EBTCinSP_B = await stabilityPool.getTotalEBTCDeposits()
    assert.isTrue(EBTCinSP_B.lt(EBTCinSP_A))

    // Check ETH in SP has received the liquidation
    const ETHinSP_B = await stabilityPool.getETH()
    assert.equal(ETHinSP_B.toString(), aliceColl.sub(_0pt5percent_aliceColl).add(bobColl).sub(_0pt5percent_bobColl)) // (1 + 2 ETH) * 0.995


    // --- Price drops to 3 ---
    await priceFeed.setPrice('3141592653589793238')
    const price_3 = await priceFeed.getPrice()

    /* 
    ETH:USD price = 3.141592653589793238
    Carol coll = 3 ETH. Value = (3 * 3.141592653589793238) = $6
    -> Expect 0.5% of collaterall to be sent to liquidator, as gas compensation */

    // Check collateral value in USD is < $10
    const carolColl = (await cdpManager.Cdps(_carolCdpId))[1]

    assert.isFalse(await th.checkRecoveryMode(contracts))
    // Liquidate B (use 0 gas price to easily check the amount the compensation amount the liquidator receives)
    const liquidatorBalance_before_C = web3.utils.toBN(await web3.eth.getBalance(liquidator))
    const C_GAS_Used_Liquidator = th.gasUsed(await cdpManager.liquidate(_carolCdpId, { from: liquidator, gasPrice: GAS_PRICE }))
    const liquidatorBalance_after_C = web3.utils.toBN(await web3.eth.getBalance(liquidator))

    // Check liquidator's balance increases by C's 0.5% of coll, 3 ETH
    const compensationReceived_C = (liquidatorBalance_after_C.sub(liquidatorBalance_before_C).add(toBN(C_GAS_Used_Liquidator * GAS_PRICE))).toString()
    const _0pt5percent_carolColl = carolColl.div(web3.utils.toBN('200'))
    assert.equal(compensationReceived_C, _0pt5percent_carolColl)

    // Check SP EBTC has decreased due to the liquidation of C
    const EBTCinSP_C = await stabilityPool.getTotalEBTCDeposits()
    assert.isTrue(EBTCinSP_C.lt(EBTCinSP_B))

    // Check ETH in SP has not changed due to the lquidation of C
    const ETHinSP_C = await stabilityPool.getETH()
    assert.equal(ETHinSP_C.toString(), aliceColl.sub(_0pt5percent_aliceColl).add(bobColl).sub(_0pt5percent_bobColl).add(carolColl).sub(_0pt5percent_carolColl)) // (1+2+3 ETH) * 0.995
  })

  it('gas compensation from pool-offset liquidations: 0.5% collateral < $10 in value. Compensates $10 worth of collateral, liquidates the remainder', async () => {
    await priceFeed.setPrice(dec(400, 18))
    await openCdp({ ICR: toBN(dec(2000, 18)), extraParams: { from: whale } })

    // A-E open cdps
    await openCdp({ ICR: toBN(dec(2, 18)), extraEBTCAmount: dec(200, 18), extraParams: { from: alice } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    await openCdp({ ICR: toBN(dec(120, 16)), extraEBTCAmount: dec(5000, 18), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    await openCdp({ ICR: toBN(dec(60, 18)), extraEBTCAmount: dec(600, 18), extraParams: { from: carol } })
    await openCdp({ ICR: toBN(dec(80, 18)), extraEBTCAmount: dec(1, 23), extraParams: { from: dennis } })
    await openCdp({ ICR: toBN(dec(80, 18)), extraEBTCAmount: dec(1, 23), extraParams: { from: erin } })

    // D, E each provide 10000 EBTC to SP
    await stabilityPool.provideToSP(dec(1, 23), ZERO_ADDRESS, { from: dennis , gasPrice: GAS_PRICE })
    await stabilityPool.provideToSP(dec(1, 23), ZERO_ADDRESS, { from: erin , gasPrice: GAS_PRICE })

    const EBTCinSP_0 = await stabilityPool.getTotalEBTCDeposits()
    const ETHinSP_0 = await stabilityPool.getETH()

    // --- Price drops to 199.999 ---
    await priceFeed.setPrice('199999000000000000000')
    const price_1 = await priceFeed.getPrice()

    /* 
    ETH:USD price = 199.999
    Alice coll = 1 ETH. Value: $199.999
    0.5% of coll  = 0.05 ETH. Value: (0.05 * 199.999) = $9.99995
    Minimum comp = $10 = 0.05000025000125001 ETH.
    -> Expect 0.05000025000125001 ETH sent to liquidator, 
    and (1 - 0.05000025000125001) = 0.94999974999875 ETH remainder liquidated */

    // Check collateral value in USD is > $10
    const aliceColl = (await cdpManager.Cdps(_aliceCdpId))[1]

    assert.isFalse(await th.checkRecoveryMode(contracts))

    const aliceICR = await cdpManager.getCurrentICR(_aliceCdpId, price_1)
    assert.isTrue(aliceICR.lt(mv._MCR))

    // Liquidate A (use 0 gas price to easily check the amount the compensation amount the liquidator receives)
    const liquidatorBalance_before_A = web3.utils.toBN(await web3.eth.getBalance(liquidator))
    const A_GAS_Used_Liquidator = th.gasUsed(await cdpManager.liquidate(_aliceCdpId, { from: liquidator, gasPrice: GAS_PRICE }))
    const liquidatorBalance_after_A = web3.utils.toBN(await web3.eth.getBalance(liquidator))

    // Check liquidator's balance increases by 0.5% of coll
    const compensationReceived_A = (liquidatorBalance_after_A.sub(liquidatorBalance_before_A).add(toBN(A_GAS_Used_Liquidator * GAS_PRICE))).toString()
    const _0pt5percent_aliceColl = aliceColl.div(web3.utils.toBN('200'))
    assert.equal(compensationReceived_A, _0pt5percent_aliceColl)

    // Check SP EBTC has decreased due to the liquidation of A
    const EBTCinSP_A = await stabilityPool.getTotalEBTCDeposits()
    assert.isTrue(EBTCinSP_A.lt(EBTCinSP_0))

    // Check ETH in SP has increased by the remainder of B's coll
    const collRemainder_A = aliceColl.sub(_0pt5percent_aliceColl)
    const ETHinSP_A = await stabilityPool.getETH()

    const SPETHIncrease_A = ETHinSP_A.sub(ETHinSP_0)

    assert.isAtMost(th.getDifference(SPETHIncrease_A, collRemainder_A), 1000)

    // --- Price drops to 15 ---
    await priceFeed.setPrice(dec(15, 18))
    const price_2 = await priceFeed.getPrice()

    /* 
    ETH:USD price = 15
    Bob coll = 15 ETH. Value: $165
    0.5% of coll  = 0.75 ETH. Value: (0.75 * 11) = $8.25
    Minimum comp = $10 =  0.66666...ETH.
    -> Expect 0.666666666666666666 ETH sent to liquidator, 
    and (15 - 0.666666666666666666) ETH remainder liquidated */

    // Check collateral value in USD is > $10
    const bobColl = (await cdpManager.Cdps(_bobCdpId))[1]

    assert.isFalse(await th.checkRecoveryMode(contracts))

    const bobICR = await cdpManager.getCurrentICR(_bobCdpId, price_2)
    assert.isTrue(bobICR.lte(mv._MCR))

    // Liquidate B (use 0 gas price to easily check the amount the compensation amount the liquidator receives)
    const liquidatorBalance_before_B = web3.utils.toBN(await web3.eth.getBalance(liquidator))
    const B_GAS_Used_Liquidator = th.gasUsed(await cdpManager.liquidate(_bobCdpId, { from: liquidator, gasPrice: GAS_PRICE }))
    const liquidatorBalance_after_B = web3.utils.toBN(await web3.eth.getBalance(liquidator))

    // Check liquidator's balance increases by $10 worth of coll
    const _0pt5percent_bobColl = bobColl.div(web3.utils.toBN('200'))
    const compensationReceived_B = (liquidatorBalance_after_B.sub(liquidatorBalance_before_B).add(toBN(B_GAS_Used_Liquidator * GAS_PRICE))).toString()
    assert.equal(compensationReceived_B, _0pt5percent_bobColl)

    // Check SP EBTC has decreased due to the liquidation of B
    const EBTCinSP_B = await stabilityPool.getTotalEBTCDeposits()
    assert.isTrue(EBTCinSP_B.lt(EBTCinSP_A))

    // Check ETH in SP has increased by the remainder of B's coll
    const collRemainder_B = bobColl.sub(_0pt5percent_bobColl)
    const ETHinSP_B = await stabilityPool.getETH()

    const SPETHIncrease_B = ETHinSP_B.sub(ETHinSP_A)

    assert.isAtMost(th.getDifference(SPETHIncrease_B, collRemainder_B), 1000)
  })

  it('gas compensation from pool-offset liquidations: 0.5% collateral > $10 in value. Compensates 0.5% of  collateral, liquidates the remainder', async () => {
    // open cdps
    await priceFeed.setPrice(dec(400, 18))
    await openCdp({ ICR: toBN(dec(200, 18)), extraParams: { from: whale } })

    // A-E open cdps
    await openCdp({ ICR: toBN(dec(2, 18)), extraEBTCAmount: dec(2000, 18), extraParams: { from: alice,} })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    await openCdp({ ICR: toBN(dec(1875, 15)), extraEBTCAmount: dec(8000, 18), extraParams: { from: bob,} })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    await openCdp({ ICR: toBN(dec(2, 18)), extraEBTCAmount: dec(600, 18), extraParams: { from: carol} })
    await openCdp({ ICR: toBN(dec(4, 18)), extraEBTCAmount: dec(1, 23), extraParams: { from: dennis} })
    await openCdp({ ICR: toBN(dec(4, 18)), extraEBTCAmount: dec(1, 23), extraParams: { from: erin} })

    // D, E each provide 10000 EBTC to SP
    await stabilityPool.provideToSP(dec(1, 23), ZERO_ADDRESS, { from: dennis, gasPrice: GAS_PRICE })
    await stabilityPool.provideToSP(dec(1, 23), ZERO_ADDRESS, { from: erin, gasPrice: GAS_PRICE })

    const EBTCinSP_0 = await stabilityPool.getTotalEBTCDeposits()
    const ETHinSP_0 = await stabilityPool.getETH()

    await priceFeed.setPrice(dec(200, 18))
    const price_1 = await priceFeed.getPrice()

    /* 
    ETH:USD price = 200
    Alice coll = 10.001 ETH. Value: $2000.2
    0.5% of coll  = 0.050005 ETH. Value: (0.050005 * 200) = $10.01
    Minimum comp = $10 = 0.05 ETH.
    -> Expect  0.050005 ETH sent to liquidator, 
    and (10.001 - 0.050005) ETH remainder liquidated */

    // Check value of 0.5% of collateral in USD is > $10
    const aliceColl = (await cdpManager.Cdps(_aliceCdpId))[1]
    const _0pt5percent_aliceColl = aliceColl.div(web3.utils.toBN('200'))

    assert.isFalse(await th.checkRecoveryMode(contracts))

    const aliceICR = await cdpManager.getCurrentICR(_aliceCdpId, price_1)
    assert.isTrue(aliceICR.lt(mv._MCR))

    // Liquidate A (use 0 gas price to easily check the amount the compensation amount the liquidator receives)
    const liquidatorBalance_before_A = web3.utils.toBN(await web3.eth.getBalance(liquidator))
    const A_GAS_Used_Liquidator = th.gasUsed(await cdpManager.liquidate(_aliceCdpId, { from: liquidator, gasPrice: GAS_PRICE }))
    const liquidatorBalance_after_A = web3.utils.toBN(await web3.eth.getBalance(liquidator))

    // Check liquidator's balance increases by 0.5% of coll
    const compensationReceived_A = (liquidatorBalance_after_A.sub(liquidatorBalance_before_A).add(toBN(A_GAS_Used_Liquidator * GAS_PRICE))).toString()
    assert.equal(compensationReceived_A, _0pt5percent_aliceColl)

    // Check SP EBTC has decreased due to the liquidation of A 
    const EBTCinSP_A = await stabilityPool.getTotalEBTCDeposits()
    assert.isTrue(EBTCinSP_A.lt(EBTCinSP_0))

    // Check ETH in SP has increased by the remainder of A's coll
    const collRemainder_A = aliceColl.sub(_0pt5percent_aliceColl)
    const ETHinSP_A = await stabilityPool.getETH()

    const SPETHIncrease_A = ETHinSP_A.sub(ETHinSP_0)

    assert.isAtMost(th.getDifference(SPETHIncrease_A, collRemainder_A), 1000)


    /* 
   ETH:USD price = 200
   Bob coll = 37.5 ETH. Value: $7500
   0.5% of coll  = 0.1875 ETH. Value: (0.1875 * 200) = $37.5
   Minimum comp = $10 = 0.05 ETH.
   -> Expect 0.1875 ETH sent to liquidator, 
   and (37.5 - 0.1875 ETH) ETH remainder liquidated */

    // Check value of 0.5% of collateral in USD is > $10
    const bobColl = (await cdpManager.Cdps(_bobCdpId))[1]
    const _0pt5percent_bobColl = bobColl.div(web3.utils.toBN('200'))

    assert.isFalse(await th.checkRecoveryMode(contracts))

    const bobICR = await cdpManager.getCurrentICR(_bobCdpId, price_1)
    assert.isTrue(bobICR.lt(mv._MCR))

    // Liquidate B (use 0 gas price to easily check the amount the compensation amount the liquidator receives)
    const liquidatorBalance_before_B = web3.utils.toBN(await web3.eth.getBalance(liquidator))
    const B_GAS_Used_Liquidator = th.gasUsed(await cdpManager.liquidate(_bobCdpId, { from: liquidator, gasPrice: GAS_PRICE }))
    const liquidatorBalance_after_B = web3.utils.toBN(await web3.eth.getBalance(liquidator))

    // Check liquidator's balance increases by 0.5% of coll
    const compensationReceived_B = (liquidatorBalance_after_B.sub(liquidatorBalance_before_B).add(toBN(B_GAS_Used_Liquidator * GAS_PRICE))).toString()
    assert.equal(compensationReceived_B, _0pt5percent_bobColl)

    // Check SP EBTC has decreased due to the liquidation of B
    const EBTCinSP_B = await stabilityPool.getTotalEBTCDeposits()
    assert.isTrue(EBTCinSP_B.lt(EBTCinSP_A))

    // Check ETH in SP has increased by the remainder of B's coll
    const collRemainder_B = bobColl.sub(_0pt5percent_bobColl)
    const ETHinSP_B = await stabilityPool.getETH()

    const SPETHIncrease_B = ETHinSP_B.sub(ETHinSP_A)

    assert.isAtMost(th.getDifference(SPETHIncrease_B, collRemainder_B), 1000)

  })

  // --- Event emission in single liquidation ---

  it('Gas compensation from pool-offset liquidations. Liquidation event emits the correct gas compensation and total liquidated coll and debt', async () => {
    await openCdp({ ICR: toBN(dec(2000, 18)), extraParams: { from: whale } })

    // A-E open cdps
    const { totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(2, 18)), extraEBTCAmount: dec(100, 18), extraParams: { from: alice } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    const { totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(2, 18)), extraEBTCAmount: dec(200, 18), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    await openCdp({ ICR: toBN(dec(2, 18)), extraEBTCAmount: dec(300, 18), extraParams: { from: carol } })
    await openCdp({ ICR: toBN(dec(2, 18)), extraEBTCAmount: A_totalDebt, extraParams: { from: dennis } })
    await openCdp({ ICR: toBN(dec(2, 18)), extraEBTCAmount: B_totalDebt, extraParams: { from: erin } })

    // D, E each provide EBTC to SP
    await stabilityPool.provideToSP(A_totalDebt, ZERO_ADDRESS, { from: dennis })
    await stabilityPool.provideToSP(B_totalDebt, ZERO_ADDRESS, { from: erin })

    const EBTCinSP_0 = await stabilityPool.getTotalEBTCDeposits()

    // th.logBN('TCR', await cdpManager.getTCR(await priceFeed.getPrice()))
    // --- Price drops to 9.99 ---
    await priceFeed.setPrice('9990000000000000000')
    const price_1 = await priceFeed.getPrice()

    /* 
    ETH:USD price = 9.99
    -> Expect 0.5% of collaterall to be sent to liquidator, as gas compensation */

    // Check collateral value in USD is < $10
    const aliceColl = (await cdpManager.Cdps(_aliceCdpId))[1]
    const aliceDebt = (await cdpManager.Cdps(_aliceCdpId))[0]

    // th.logBN('TCR', await cdpManager.getTCR(await priceFeed.getPrice()))
    assert.isFalse(await th.checkRecoveryMode(contracts))

    // Liquidate A (use 0 gas price to easily check the amount the compensation amount the liquidator receives)
    const liquidationTxA = await cdpManager.liquidate(_aliceCdpId, { from: liquidator, gasPrice: GAS_PRICE })

    const expectedGasComp_A = aliceColl.mul(th.toBN(5)).div(th.toBN(1000))
    const expectedLiquidatedColl_A = aliceColl.sub(expectedGasComp_A)
    const expectedLiquidatedDebt_A =  aliceDebt

    const [loggedDebt_A, loggedColl_A, loggedGasComp_A, ] = th.getEmittedLiquidationValues(liquidationTxA)

    assert.isAtMost(th.getDifference(expectedLiquidatedDebt_A, loggedDebt_A), 1000)
    assert.isAtMost(th.getDifference(expectedLiquidatedColl_A, loggedColl_A), 1000)
    assert.isAtMost(th.getDifference(expectedGasComp_A, loggedGasComp_A), 1000)

    // --- Price drops to 3 ---
    await priceFeed.setPrice(dec(3, 18))
    const price_2 = await priceFeed.getPrice()

    /* 
    ETH:USD price = 3
    -> Expect 0.5% of collaterall to be sent to liquidator, as gas compensation */

    // Check collateral value in USD is < $10
    const bobColl = (await cdpManager.Cdps(_bobCdpId))[1]
    const bobDebt = (await cdpManager.Cdps(_bobCdpId))[0]

    assert.isFalse(await th.checkRecoveryMode(contracts))
    // Liquidate B (use 0 gas price to easily check the amount the compensation amount the liquidator receives)
    const liquidationTxB = await cdpManager.liquidate(_bobCdpId, { from: liquidator, gasPrice: GAS_PRICE })

    const expectedGasComp_B = bobColl.mul(th.toBN(5)).div(th.toBN(1000))
    const expectedLiquidatedColl_B = bobColl.sub(expectedGasComp_B)
    const expectedLiquidatedDebt_B =  bobDebt

    const [loggedDebt_B, loggedColl_B, loggedGasComp_B, ] = th.getEmittedLiquidationValues(liquidationTxB)

    assert.isAtMost(th.getDifference(expectedLiquidatedDebt_B, loggedDebt_B), 1000)
    assert.isAtMost(th.getDifference(expectedLiquidatedColl_B, loggedColl_B), 1000)
    assert.isAtMost(th.getDifference(expectedGasComp_B, loggedGasComp_B), 1000)
  })


  it('gas compensation from pool-offset liquidations. Liquidation event emits the correct gas compensation and total liquidated coll and debt', async () => {
    await priceFeed.setPrice(dec(400, 18))
    await openCdp({ ICR: toBN(dec(2000, 18)), extraParams: { from: whale } })

    // A-E open cdps
    await openCdp({ ICR: toBN(dec(2, 18)), extraEBTCAmount: dec(200, 18), extraParams: { from: alice } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    await openCdp({ ICR: toBN(dec(120, 16)), extraEBTCAmount: dec(5000, 18), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    await openCdp({ ICR: toBN(dec(60, 18)), extraEBTCAmount: dec(600, 18), extraParams: { from: carol } })
    await openCdp({ ICR: toBN(dec(80, 18)), extraEBTCAmount: dec(1, 23), extraParams: { from: dennis } })
    await openCdp({ ICR: toBN(dec(80, 18)), extraEBTCAmount: dec(1, 23), extraParams: { from: erin } })

    // D, E each provide 10000 EBTC to SP
    await stabilityPool.provideToSP(dec(1, 23), ZERO_ADDRESS, { from: dennis })
    await stabilityPool.provideToSP(dec(1, 23), ZERO_ADDRESS, { from: erin })

    const EBTCinSP_0 = await stabilityPool.getTotalEBTCDeposits()
    const ETHinSP_0 = await stabilityPool.getETH()

    // --- Price drops to 199.999 ---
    await priceFeed.setPrice('199999000000000000000')
    const price_1 = await priceFeed.getPrice()

    /* 
    ETH:USD price = 199.999
    Alice coll = 1 ETH. Value: $199.999
    0.5% of coll  = 0.05 ETH. Value: (0.05 * 199.999) = $9.99995
    Minimum comp = $10 = 0.05000025000125001 ETH.
    -> Expect 0.05000025000125001 ETH sent to liquidator, 
    and (1 - 0.05000025000125001) = 0.94999974999875 ETH remainder liquidated */

    // Check collateral value in USD is > $10
    const aliceColl = (await cdpManager.Cdps(_aliceCdpId))[1]
    const aliceDebt = (await cdpManager.Cdps(_aliceCdpId))[0]
    const aliceCollValueInUSD = (await borrowerOperationsTester.getUSDValue(aliceColl, price_1))
    assert.isTrue(aliceCollValueInUSD.gt(th.toBN(dec(10, 18))))

    // Check value of 0.5% of collateral in USD is < $10
    const _0pt5percent_aliceColl = aliceColl.div(web3.utils.toBN('200'))

    assert.isFalse(await th.checkRecoveryMode(contracts))

    const aliceICR = await cdpManager.getCurrentICR(_aliceCdpId, price_1)
    assert.isTrue(aliceICR.lt(mv._MCR))

    // Liquidate A (use 0 gas price to easily check the amount the compensation amount the liquidator receives)
    const liquidationTxA = await cdpManager.liquidate(_aliceCdpId, { from: liquidator, gasPrice: GAS_PRICE })

    const expectedGasComp_A = _0pt5percent_aliceColl
    const expectedLiquidatedColl_A = aliceColl.sub(expectedGasComp_A)
    const expectedLiquidatedDebt_A =  aliceDebt

    const [loggedDebt_A, loggedColl_A, loggedGasComp_A, ] = th.getEmittedLiquidationValues(liquidationTxA)

    assert.isAtMost(th.getDifference(expectedLiquidatedDebt_A, loggedDebt_A), 1000)
    assert.isAtMost(th.getDifference(expectedLiquidatedColl_A, loggedColl_A), 1000)
    assert.isAtMost(th.getDifference(expectedGasComp_A, loggedGasComp_A), 1000)

      // --- Price drops to 15 ---
      await priceFeed.setPrice(dec(15, 18))
      const price_2 = await priceFeed.getPrice()

    /* 
    ETH:USD price = 15
    Bob coll = 15 ETH. Value: $165
    0.5% of coll  = 0.75 ETH. Value: (0.75 * 11) = $8.25
    Minimum comp = $10 =  0.66666...ETH.
    -> Expect 0.666666666666666666 ETH sent to liquidator, 
    and (15 - 0.666666666666666666) ETH remainder liquidated */

    // Check collateral value in USD is > $10
    const bobColl = (await cdpManager.Cdps(_bobCdpId))[1]
    const bobDebt = (await cdpManager.Cdps(_bobCdpId))[0]


    assert.isFalse(await th.checkRecoveryMode(contracts))

    const bobICR = await cdpManager.getCurrentICR(_bobCdpId, price_2)
    assert.isTrue(bobICR.lte(mv._MCR))

    // Liquidate B (use 0 gas price to easily check the amount the compensation amount the liquidator receives
    const liquidationTxB = await cdpManager.liquidate(_bobCdpId, { from: liquidator, gasPrice: GAS_PRICE })

    const _0pt5percent_bobColl = bobColl.div(web3.utils.toBN('200'))
    const expectedGasComp_B = _0pt5percent_bobColl
    const expectedLiquidatedColl_B = bobColl.sub(expectedGasComp_B)
    const expectedLiquidatedDebt_B =  bobDebt

    const [loggedDebt_B, loggedColl_B, loggedGasComp_B, ] = th.getEmittedLiquidationValues(liquidationTxB)

    assert.isAtMost(th.getDifference(expectedLiquidatedDebt_B, loggedDebt_B), 1000)
    assert.isAtMost(th.getDifference(expectedLiquidatedColl_B, loggedColl_B), 1000)
    assert.isAtMost(th.getDifference(expectedGasComp_B, loggedGasComp_B), 1000)
  })


  it('gas compensation from pool-offset liquidations: 0.5% collateral > $10 in value. Liquidation event emits the correct gas compensation and total liquidated coll and debt', async () => {
    // open cdps
    await priceFeed.setPrice(dec(400, 18))
    await openCdp({ ICR: toBN(dec(200, 18)), extraParams: { from: whale } })

    // A-E open cdps
    await openCdp({ ICR: toBN(dec(2, 18)), extraEBTCAmount: dec(2000, 18), extraParams: { from: alice } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    await openCdp({ ICR: toBN(dec(1875, 15)), extraEBTCAmount: dec(8000, 18), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    await openCdp({ ICR: toBN(dec(2, 18)), extraEBTCAmount: dec(600, 18), extraParams: { from: carol } })
    await openCdp({ ICR: toBN(dec(4, 18)), extraEBTCAmount: dec(1, 23), extraParams: { from: dennis } })
    await openCdp({ ICR: toBN(dec(4, 18)), extraEBTCAmount: dec(1, 23), extraParams: { from: erin } })

    // D, E each provide 10000 EBTC to SP
    await stabilityPool.provideToSP(dec(1, 23), ZERO_ADDRESS, { from: dennis })
    await stabilityPool.provideToSP(dec(1, 23), ZERO_ADDRESS, { from: erin })

    const EBTCinSP_0 = await stabilityPool.getTotalEBTCDeposits()
    const ETHinSP_0 = await stabilityPool.getETH()

    await priceFeed.setPrice(dec(200, 18))
    const price_1 = await priceFeed.getPrice()

    // Check value of 0.5% of collateral in USD is > $10
    const aliceColl = (await cdpManager.Cdps(_aliceCdpId))[1]
    const aliceDebt = (await cdpManager.Cdps(_aliceCdpId))[0]
    const _0pt5percent_aliceColl = aliceColl.div(web3.utils.toBN('200'))

    assert.isFalse(await th.checkRecoveryMode(contracts))

    const aliceICR = await cdpManager.getCurrentICR(_aliceCdpId, price_1)
    assert.isTrue(aliceICR.lt(mv._MCR))

    // Liquidate A (use 0 gas price to easily check the amount the compensation amount the liquidator receives)
    const liquidationTxA = await cdpManager.liquidate(_aliceCdpId, { from: liquidator, gasPrice: GAS_PRICE })
    
    const expectedGasComp_A = _0pt5percent_aliceColl
    const expectedLiquidatedColl_A = aliceColl.sub(_0pt5percent_aliceColl)
    const expectedLiquidatedDebt_A =  aliceDebt

    const [loggedDebt_A, loggedColl_A, loggedGasComp_A, ] = th.getEmittedLiquidationValues(liquidationTxA)

    assert.isAtMost(th.getDifference(expectedLiquidatedDebt_A, loggedDebt_A), 1000)
    assert.isAtMost(th.getDifference(expectedLiquidatedColl_A, loggedColl_A), 1000)
    assert.isAtMost(th.getDifference(expectedGasComp_A, loggedGasComp_A), 1000)


    /* 
   ETH:USD price = 200
   Bob coll = 37.5 ETH. Value: $7500
   0.5% of coll  = 0.1875 ETH. Value: (0.1875 * 200) = $37.5
   Minimum comp = $10 = 0.05 ETH.
   -> Expect 0.1875 ETH sent to liquidator, 
   and (37.5 - 0.1875 ETH) ETH remainder liquidated */

    // Check value of 0.5% of collateral in USD is > $10
    const bobColl = (await cdpManager.Cdps(_bobCdpId))[1]
    const bobDebt = (await cdpManager.Cdps(_bobCdpId))[0]
    const _0pt5percent_bobColl = bobColl.div(web3.utils.toBN('200'))

    assert.isFalse(await th.checkRecoveryMode(contracts))

    const bobICR = await cdpManager.getCurrentICR(_bobCdpId, price_1)
    assert.isTrue(bobICR.lt(mv._MCR))

    // Liquidate B (use 0 gas price to easily check the amount the compensation amount the liquidator receives)
    const liquidationTxB = await cdpManager.liquidate(_bobCdpId, { from: liquidator, gasPrice: GAS_PRICE })
    
    const expectedGasComp_B = _0pt5percent_bobColl
    const expectedLiquidatedColl_B = bobColl.sub(_0pt5percent_bobColl)
    const expectedLiquidatedDebt_B =  bobDebt

    const [loggedDebt_B, loggedColl_B, loggedGasComp_B, ] = th.getEmittedLiquidationValues(liquidationTxB)

    assert.isAtMost(th.getDifference(expectedLiquidatedDebt_B, loggedDebt_B), 1000)
    assert.isAtMost(th.getDifference(expectedLiquidatedColl_B, loggedColl_B), 1000)
    assert.isAtMost(th.getDifference(expectedGasComp_B, loggedGasComp_B), 1000)
  })


  // liquidateCdps - full offset
  it('liquidateCdps(): full offset.  Compensates the correct amount, and liquidates the remainder', async () => {
    await priceFeed.setPrice(dec(1000, 18))

    await openCdp({ ICR: toBN(dec(2000, 18)), extraParams: { from: whale } })

    // A-F open cdps
    await openCdp({ ICR: toBN(dec(118, 16)), extraEBTCAmount: dec(2000, 18), extraParams: { from: alice } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    await openCdp({ ICR: toBN(dec(526, 16)), extraEBTCAmount: dec(8000, 18), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    await openCdp({ ICR: toBN(dec(488, 16)), extraEBTCAmount: dec(600, 18), extraParams: { from: carol } })
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    await openCdp({ ICR: toBN(dec(545, 16)), extraEBTCAmount: dec(1, 23), extraParams: { from: dennis } })
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);
    await openCdp({ ICR: toBN(dec(10, 18)), extraEBTCAmount: dec(1, 23), extraParams: { from: erin } })
    let _erinCdpId = await sortedCdps.cdpOfOwnerByIndex(erin, 0);
    await openCdp({ ICR: toBN(dec(10, 18)), extraEBTCAmount: dec(1, 23), extraParams: { from: flyn } })
    let _flynCdpId = await sortedCdps.cdpOfOwnerByIndex(flyn, 0);

    // D, E each provide 10000 EBTC to SP
    await stabilityPool.provideToSP(dec(1, 23), ZERO_ADDRESS, { from: erin })
    await stabilityPool.provideToSP(dec(1, 23), ZERO_ADDRESS, { from: flyn })

    const EBTCinSP_0 = await stabilityPool.getTotalEBTCDeposits()

    // price drops to 200 
    await priceFeed.setPrice(dec(200, 18))
    const price = await priceFeed.getPrice()

    // Check not in Recovery Mode 
    assert.isFalse(await th.checkRecoveryMode(contracts))

    // Check A, B, C, D have ICR < MCR
    assert.isTrue((await cdpManager.getCurrentICR(_aliceCdpId, price)).lt(mv._MCR))
    assert.isTrue((await cdpManager.getCurrentICR(_bobCdpId, price)).lt(mv._MCR))
    assert.isTrue((await cdpManager.getCurrentICR(_carolCdpId, price)).lt(mv._MCR))
    assert.isTrue((await cdpManager.getCurrentICR(_dennisCdpId, price)).lt(mv._MCR))

    // Check E, F have ICR > MCR
    assert.isTrue((await cdpManager.getCurrentICR(_erinCdpId, price)).gt(mv._MCR))
    assert.isTrue((await cdpManager.getCurrentICR(_flynCdpId, price)).gt(mv._MCR))


    // --- Check value of of A's collateral is < $10, and value of B,C,D collateral are > $10  ---
    const aliceColl = (await cdpManager.Cdps(_aliceCdpId))[1]
    const bobColl = (await cdpManager.Cdps(_bobCdpId))[1]
    const carolColl = (await cdpManager.Cdps(_carolCdpId))[1]
    const dennisColl = (await cdpManager.Cdps(_dennisCdpId))[1]

    // --- Check value of 0.5% of A, B, and C's collateral is <$10, and value of 0.5% of D's collateral is > $10 ---
    const _0pt5percent_aliceColl = aliceColl.div(web3.utils.toBN('200'))
    const _0pt5percent_bobColl = bobColl.div(web3.utils.toBN('200'))
    const _0pt5percent_carolColl = carolColl.div(web3.utils.toBN('200'))
    const _0pt5percent_dennisColl = dennisColl.div(web3.utils.toBN('200'))

    const collGasCompensation = await cdpManagerTester.getCollGasCompensation(price)
    assert.equal(collGasCompensation, dec(1, 18))

    /* Expect total gas compensation = 
    0.5% of [A_coll + B_coll + C_coll + D_coll]
    */
    const expectedGasComp = _0pt5percent_aliceColl
      .add(_0pt5percent_bobColl)
      .add(_0pt5percent_carolColl)
      .add(_0pt5percent_dennisColl)

    /* Expect liquidated coll = 
    0.95% of [A_coll + B_coll + C_coll + D_coll]
    */
    const expectedLiquidatedColl = aliceColl.sub(_0pt5percent_aliceColl)
      .add(bobColl.sub(_0pt5percent_bobColl))
      .add(carolColl.sub(_0pt5percent_carolColl))
      .add(dennisColl.sub(_0pt5percent_dennisColl))

    // Liquidate cdps A-D

    const liquidatorBalance_before = web3.utils.toBN(await web3.eth.getBalance(liquidator))
    const GAS_Used_Liquidator = th.gasUsed(await cdpManager.liquidateCdps(4, { from: liquidator, gasPrice: GAS_PRICE }))
    const liquidatorBalance_after = web3.utils.toBN(await web3.eth.getBalance(liquidator))

    // Check EBTC in SP has decreased
    const EBTCinSP_1 = await stabilityPool.getTotalEBTCDeposits()
    assert.isTrue(EBTCinSP_1.lt(EBTCinSP_0))

    // Check liquidator's balance has increased by the expected compensation amount
    const compensationReceived = (liquidatorBalance_after.sub(liquidatorBalance_before).add(toBN(GAS_Used_Liquidator * GAS_PRICE))).toString()
    assert.equal(expectedGasComp, compensationReceived)

    // Check ETH in stability pool now equals the expected liquidated collateral
    const ETHinSP = (await stabilityPool.getETH()).toString()
    assert.equal(expectedLiquidatedColl, ETHinSP)
  })

  // liquidateCdps - full redistribution
  it('liquidateCdps(): full redistribution. Compensates the correct amount, and liquidates the remainder', async () => {
    await priceFeed.setPrice(dec(1000, 18))

    await openCdp({ ICR: toBN(dec(200, 18)), extraParams: { from: whale } })

    // A-D open cdps
    await openCdp({ ICR: toBN(dec(118, 16)), extraEBTCAmount: dec(2000, 18), extraParams: { from: alice } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    await openCdp({ ICR: toBN(dec(526, 16)), extraEBTCAmount: dec(8000, 18), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    await openCdp({ ICR: toBN(dec(488, 16)), extraEBTCAmount: dec(600, 18), extraParams: { from: carol } })
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    await openCdp({ ICR: toBN(dec(545, 16)), extraEBTCAmount: dec(1, 23), extraParams: { from: dennis } })
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);

    const EBTCinDefaultPool_0 = await defaultPool.getEBTCDebt()

    // price drops to 200 
    await priceFeed.setPrice(dec(200, 18))
    const price = await priceFeed.getPrice()

    // Check not in Recovery Mode 
    assert.isFalse(await th.checkRecoveryMode(contracts))

    // Check A, B, C, D have ICR < MCR
    assert.isTrue((await cdpManager.getCurrentICR(_aliceCdpId, price)).lt(mv._MCR))
    assert.isTrue((await cdpManager.getCurrentICR(_bobCdpId, price)).lt(mv._MCR))
    assert.isTrue((await cdpManager.getCurrentICR(_carolCdpId, price)).lt(mv._MCR))
    assert.isTrue((await cdpManager.getCurrentICR(_dennisCdpId, price)).lt(mv._MCR))

    // --- Check value of of A's collateral is < $10, and value of B,C,D collateral are > $10  ---
    const aliceColl = (await cdpManager.Cdps(_aliceCdpId))[1]
    const bobColl = (await cdpManager.Cdps(_bobCdpId))[1]
    const carolColl = (await cdpManager.Cdps(_carolCdpId))[1]
    const dennisColl = (await cdpManager.Cdps(_dennisCdpId))[1]

    // --- Check value of 0.5% of A, B, and C's collateral is <$10, and value of 0.5% of D's collateral is > $10 ---
    const _0pt5percent_aliceColl = aliceColl.div(web3.utils.toBN('200'))
    const _0pt5percent_bobColl = bobColl.div(web3.utils.toBN('200'))
    const _0pt5percent_carolColl = carolColl.div(web3.utils.toBN('200'))
    const _0pt5percent_dennisColl = dennisColl.div(web3.utils.toBN('200'))

    const collGasCompensation = await cdpManagerTester.getCollGasCompensation(price)
    assert.equal(collGasCompensation, dec(1 , 18))

    /* Expect total gas compensation = 
       0.5% of [A_coll + B_coll + C_coll + D_coll]
    */
    const expectedGasComp = _0pt5percent_aliceColl
          .add(_0pt5percent_bobColl)
          .add(_0pt5percent_carolColl)
          .add(_0pt5percent_dennisColl)

    /* Expect liquidated coll = 
    0.95% of [A_coll + B_coll + C_coll + D_coll]
    */
    const expectedLiquidatedColl = aliceColl.sub(_0pt5percent_aliceColl)
      .add(bobColl.sub(_0pt5percent_bobColl))
      .add(carolColl.sub(_0pt5percent_carolColl))
      .add(dennisColl.sub(_0pt5percent_dennisColl))

    // Liquidate cdps A-D
    const liquidatorBalance_before = web3.utils.toBN(await web3.eth.getBalance(liquidator))
    const GAS_Used_Liquidator = th.gasUsed(await cdpManager.liquidateCdps(4, { from: liquidator, gasPrice: GAS_PRICE }))
    const liquidatorBalance_after = web3.utils.toBN(await web3.eth.getBalance(liquidator))

    // Check EBTC in DefaultPool has decreased
    const EBTCinDefaultPool_1 = await defaultPool.getEBTCDebt()
    assert.isTrue(EBTCinDefaultPool_1.gt(EBTCinDefaultPool_0))

    // Check liquidator's balance has increased by the expected compensation amount
    const compensationReceived = (liquidatorBalance_after.sub(liquidatorBalance_before).add(toBN(GAS_Used_Liquidator * GAS_PRICE))).toString()

    assert.isAtMost(th.getDifference(expectedGasComp, compensationReceived), 1000)

    // Check ETH in defaultPool now equals the expected liquidated collateral
    const ETHinDefaultPool = (await defaultPool.getETH()).toString()
    assert.isAtMost(th.getDifference(expectedLiquidatedColl, ETHinDefaultPool), 1000)
  })

  //  --- event emission in liquidation sequence ---
  it('liquidateCdps(): full offset. Liquidation event emits the correct gas compensation and total liquidated coll and debt', async () => {
    await priceFeed.setPrice(dec(1000, 18))

    await openCdp({ ICR: toBN(dec(2000, 18)), extraParams: { from: whale } })

    // A-F open cdps
    const { totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(118, 16)), extraEBTCAmount: dec(2000, 18), extraParams: { from: alice } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    const { totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(526, 16)), extraEBTCAmount: dec(8000, 18), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    const { totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(488, 16)), extraEBTCAmount: dec(600, 18), extraParams: { from: carol } })
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    const { totalDebt: D_totalDebt } = await openCdp({ ICR: toBN(dec(545, 16)), extraEBTCAmount: dec(1, 23), extraParams: { from: dennis } })
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);
    await openCdp({ ICR: toBN(dec(10, 18)), extraEBTCAmount: dec(1, 23), extraParams: { from: erin } })
    let _erinCdpId = await sortedCdps.cdpOfOwnerByIndex(erin, 0);
    await openCdp({ ICR: toBN(dec(10, 18)), extraEBTCAmount: dec(1, 23), extraParams: { from: flyn } })
    let _flynCdpId = await sortedCdps.cdpOfOwnerByIndex(flyn, 0);

    // D, E each provide 10000 EBTC to SP
    await stabilityPool.provideToSP(dec(1, 23), ZERO_ADDRESS, { from: erin })
    await stabilityPool.provideToSP(dec(1, 23), ZERO_ADDRESS, { from: flyn })

    const EBTCinSP_0 = await stabilityPool.getTotalEBTCDeposits()

    // price drops to 200 
    await priceFeed.setPrice(dec(200, 18))
    const price = await priceFeed.getPrice()

    // Check not in Recovery Mode 
    assert.isFalse(await th.checkRecoveryMode(contracts))

    // Check A, B, C, D have ICR < MCR
    assert.isTrue((await cdpManager.getCurrentICR(_aliceCdpId, price)).lt(mv._MCR))
    assert.isTrue((await cdpManager.getCurrentICR(_bobCdpId, price)).lt(mv._MCR))
    assert.isTrue((await cdpManager.getCurrentICR(_carolCdpId, price)).lt(mv._MCR))
    assert.isTrue((await cdpManager.getCurrentICR(_dennisCdpId, price)).lt(mv._MCR))

    // Check E, F have ICR > MCR
    assert.isTrue((await cdpManager.getCurrentICR(_erinCdpId, price)).gt(mv._MCR))
    assert.isTrue((await cdpManager.getCurrentICR(_flynCdpId, price)).gt(mv._MCR))


    // --- Check value of of A's collateral is < $10, and value of B,C,D collateral are > $10  ---
    const aliceColl = (await cdpManager.Cdps(_aliceCdpId))[1]
    const bobColl = (await cdpManager.Cdps(_bobCdpId))[1]
    const carolColl = (await cdpManager.Cdps(_carolCdpId))[1]
    const dennisColl = (await cdpManager.Cdps(_dennisCdpId))[1]

    // --- Check value of 0.5% of A, B, and C's collateral is <$10, and value of 0.5% of D's collateral is > $10 ---
    const _0pt5percent_aliceColl = aliceColl.div(web3.utils.toBN('200'))
    const _0pt5percent_bobColl = bobColl.div(web3.utils.toBN('200'))
    const _0pt5percent_carolColl = carolColl.div(web3.utils.toBN('200'))
    const _0pt5percent_dennisColl = dennisColl.div(web3.utils.toBN('200'))

    const collGasCompensation = await cdpManagerTester.getCollGasCompensation(price)
    assert.equal(collGasCompensation, dec(1, 18))

    /* Expect total gas compensation = 
    0.5% of [A_coll + B_coll + C_coll + D_coll]
    */
    const expectedGasComp = _0pt5percent_aliceColl
      .add(_0pt5percent_bobColl)
      .add(_0pt5percent_carolColl)
      .add(_0pt5percent_dennisColl)

    /* Expect liquidated coll = 
       0.95% of [A_coll + B_coll + C_coll + D_coll]
    */
    const expectedLiquidatedColl = aliceColl.sub(_0pt5percent_aliceColl)
          .add(bobColl.sub(_0pt5percent_bobColl))
          .add(carolColl.sub(_0pt5percent_carolColl))
          .add(dennisColl.sub(_0pt5percent_dennisColl))

    // Expect liquidatedDebt = 51 + 190 + 1025 + 13510 = 14646 EBTC
    const expectedLiquidatedDebt = A_totalDebt.add(B_totalDebt).add(C_totalDebt).add(D_totalDebt)

    // Liquidate cdps A-D
    const liquidationTxData = await cdpManager.liquidateCdps(4, { from: liquidator, gasPrice: GAS_PRICE })

    // Get data from the liquidation event logs
    const [loggedDebt, loggedColl, loggedGasComp, ] = th.getEmittedLiquidationValues(liquidationTxData)
    
    assert.isAtMost(th.getDifference(expectedLiquidatedDebt, loggedDebt), 1000)
    assert.isAtMost(th.getDifference(expectedLiquidatedColl, loggedColl), 1000)
    assert.isAtMost(th.getDifference(expectedGasComp, loggedGasComp), 1000)
  })

  it('liquidateCdps(): full redistribution. Liquidation event emits the correct gas compensation and total liquidated coll and debt', async () => {
    await priceFeed.setPrice(dec(1000, 18))

    await openCdp({ ICR: toBN(dec(2000, 18)), extraParams: { from: whale } })

    // A-F open cdps
    const { totalDebt: A_totalDebt } = await openCdp({ ICR: toBN(dec(118, 16)), extraEBTCAmount: dec(2000, 18), extraParams: { from: alice } })
    let _aliceCdpId = await sortedCdps.cdpOfOwnerByIndex(alice, 0);
    const { totalDebt: B_totalDebt } = await openCdp({ ICR: toBN(dec(526, 16)), extraEBTCAmount: dec(8000, 18), extraParams: { from: bob } })
    let _bobCdpId = await sortedCdps.cdpOfOwnerByIndex(bob, 0);
    const { totalDebt: C_totalDebt } = await openCdp({ ICR: toBN(dec(488, 16)), extraEBTCAmount: dec(600, 18), extraParams: { from: carol } })
    let _carolCdpId = await sortedCdps.cdpOfOwnerByIndex(carol, 0);
    const { totalDebt: D_totalDebt } = await openCdp({ ICR: toBN(dec(545, 16)), extraEBTCAmount: dec(1, 23), extraParams: { from: dennis } })
    let _dennisCdpId = await sortedCdps.cdpOfOwnerByIndex(dennis, 0);
    await openCdp({ ICR: toBN(dec(10, 18)), extraEBTCAmount: dec(1, 23), extraParams: { from: erin } })
    await openCdp({ ICR: toBN(dec(10, 18)), extraEBTCAmount: dec(1, 23), extraParams: { from: flyn } })

    const EBTCinDefaultPool_0 = await defaultPool.getEBTCDebt()

    // price drops to 200 
    await priceFeed.setPrice(dec(200, 18))
    const price = await priceFeed.getPrice()

    // Check not in Recovery Mode 
    assert.isFalse(await th.checkRecoveryMode(contracts))

    // Check A, B, C, D have ICR < MCR
    assert.isTrue((await cdpManager.getCurrentICR(_aliceCdpId, price)).lt(mv._MCR))
    assert.isTrue((await cdpManager.getCurrentICR(_bobCdpId, price)).lt(mv._MCR))
    assert.isTrue((await cdpManager.getCurrentICR(_carolCdpId, price)).lt(mv._MCR))
    assert.isTrue((await cdpManager.getCurrentICR(_dennisCdpId, price)).lt(mv._MCR))

    const aliceColl = (await cdpManager.Cdps(_aliceCdpId))[1]
    const bobColl = (await cdpManager.Cdps(_bobCdpId))[1]
    const carolColl = (await cdpManager.Cdps(_carolCdpId))[1]
    const dennisColl = (await cdpManager.Cdps(_dennisCdpId))[1]

    // --- Check value of 0.5% of A, B, and C's collateral is <$10, and value of 0.5% of D's collateral is > $10 ---
    const _0pt5percent_aliceColl = aliceColl.div(web3.utils.toBN('200'))
    const _0pt5percent_bobColl = bobColl.div(web3.utils.toBN('200'))
    const _0pt5percent_carolColl = carolColl.div(web3.utils.toBN('200'))
    const _0pt5percent_dennisColl = dennisColl.div(web3.utils.toBN('200'))

    /* Expect total gas compensation = 
    0.5% of [A_coll + B_coll + C_coll + D_coll]
    */
    const expectedGasComp = _0pt5percent_aliceColl
      .add(_0pt5percent_bobColl)
      .add(_0pt5percent_carolColl)
      .add(_0pt5percent_dennisColl).toString()

    /* Expect liquidated coll = 
    0.95% of [A_coll + B_coll + C_coll + D_coll]
    */
    const expectedLiquidatedColl = aliceColl.sub(_0pt5percent_aliceColl)
      .add(bobColl.sub(_0pt5percent_bobColl))
      .add(carolColl.sub(_0pt5percent_carolColl))
      .add(dennisColl.sub(_0pt5percent_dennisColl))

    // Expect liquidatedDebt = 51 + 190 + 1025 + 13510 = 14646 EBTC
    const expectedLiquidatedDebt = A_totalDebt.add(B_totalDebt).add(C_totalDebt).add(D_totalDebt)

    // Liquidate cdps A-D
    const liquidationTxData = await cdpManager.liquidateCdps(4, { from: liquidator, gasPrice: GAS_PRICE })

    // Get data from the liquidation event logs
    const [loggedDebt, loggedColl, loggedGasComp, ] = th.getEmittedLiquidationValues(liquidationTxData)

    assert.isAtMost(th.getDifference(expectedLiquidatedDebt, loggedDebt), 1000)
    assert.isAtMost(th.getDifference(expectedLiquidatedColl, loggedColl), 1000)
    assert.isAtMost(th.getDifference(expectedGasComp, loggedGasComp), 1000)
  })

  // --- Cdp ordering by ICR tests ---

  it('Cdp ordering: same collateral, decreasing debt. Price successively increases. Cdps should maintain ordering by ICR', async () => {
    const _10_accounts = accounts.slice(1, 11)
    let _account_cdps = {};

    let debt = 50
    // create 10 cdps, constant coll, descending debt 100 to 90 EBTC
    for (const account of _10_accounts) {

      const debtString = debt.toString().concat('000000000000000000')
      await openCdp({ extraEBTCAmount: debtString, extraParams: { from: account, value: dec(30, 'ether') } })
      _account_cdps[account] = await sortedCdps.cdpOfOwnerByIndex(account, 0);

      const squeezedCdpAddr = th.squeezeAddr(account)

      debt -= 1
    }

    const initialPrice = await priceFeed.getPrice()
    const firstColl = (await cdpManager.Cdps(_account_cdps[_10_accounts[0]]))[1]

    // Vary price 200-210
    let price = 200
    while (price < 210) {

      const priceString = price.toString().concat('000000000000000000')
      await priceFeed.setPrice(priceString)

      const ICRList = []
      const coll_firstCdp = (await cdpManager.Cdps(_account_cdps[_10_accounts[0]]))[1]
      const gasComp_firstCdp = (await cdpManagerTester.getCollGasCompensation(coll_firstCdp)).toString()

      for (account of _10_accounts) {
        // Check gas compensation is the same for all cdps
        const coll = (await cdpManager.Cdps(_account_cdps[account]))[1]
        const gasCompensation = (await cdpManagerTester.getCollGasCompensation(coll)).toString()

        assert.equal(gasCompensation, gasComp_firstCdp)

        const ICR = await cdpManager.getCurrentICR(_account_cdps[account], price)
        ICRList.push(ICR)


        // Check cdp ordering by ICR is maintained
        if (ICRList.length > 1) {
          const prevICR = ICRList[ICRList.length - 2]

          try {
            assert.isTrue(ICR.gte(prevICR))
          } catch (error) {
            console.log(`ETH price at which cdp ordering breaks: ${price}`)
            logICRs(ICRList)
          }
        }

        price += 1
      }
    }
  })

  it('Cdp ordering: increasing collateral, constant debt. Price successively increases. Cdps should maintain ordering by ICR', async () => {
    const _20_accounts = accounts.slice(1, 21)
    let _account_cdps = {};

    let coll = 50
    // create 20 cdps, increasing collateral, constant debt = 100EBTC
    for (const account of _20_accounts) {

      const collString = coll.toString().concat('000000000000000000')
      await openCdp({ extraEBTCAmount: dec(100, 18), extraParams: { from: account, value: collString } })
      _account_cdps[account] = await sortedCdps.cdpOfOwnerByIndex(account, 0);

      coll += 5
    }

    const initialPrice = await priceFeed.getPrice()

    // Vary price 
    let price = 1
    while (price < 300) {

      const priceString = price.toString().concat('000000000000000000')
      await priceFeed.setPrice(priceString)

      const ICRList = []

      for (account of _20_accounts) {
        const ICR = await cdpManager.getCurrentICR(_account_cdps[account], price)
        ICRList.push(ICR)

        // Check cdp ordering by ICR is maintained
        if (ICRList.length > 1) {
          const prevICR = ICRList[ICRList.length - 2]

          try {
            assert.isTrue(ICR.gte(prevICR))
          } catch (error) {
            console.log(`ETH price at which cdp ordering breaks: ${price}`)
            logICRs(ICRList)
          }
        }

        price += 10
      }
    }
  })

  it('Cdp ordering: Constant raw collateral ratio (excluding virtual debt). Price successively increases. Cdps should maintain ordering by ICR', async () => {
    let collVals = [1, 5, 10, 25, 50, 100, 500, 1000, 5000, 10000, 50000, 100000, 500000].map(v => v * 20)
    const accountsList = accounts.slice(1, collVals.length + 1)

    let accountIdx = 0
    let _account_cdps = {};
    for (const coll of collVals) {

      const debt = coll * 110

      const account = accountsList[accountIdx]

      let _ownerBal = await web3.eth.getBalance(account);

      const collString = coll.toString().concat('000000000000000000')
      let _debtAmt = dec(100, 18);
      console.log('accountIdx=' + accountIdx + ',_debtAmt=' + _debtAmt + ',collString=' + collString);
      await bn8Signer.sendTransaction({ to: account, value: ethers.utils.parseUnits(collString, 0)});// sugardaddy the collateral Ether
      await openCdp({ extraEBTCAmount: _debtAmt, extraParams: { from: account, value: collString } })
      _account_cdps[account] = await sortedCdps.cdpOfOwnerByIndex(account, 0);

      accountIdx += 1
    }

    const initialPrice = await priceFeed.getPrice()

    // Vary price
    let price = 1
    while (price < 300) {

      const priceString = price.toString().concat('000000000000000000')
      await priceFeed.setPrice(priceString)

      const ICRList = []

      for (account of accountsList) {
        const ICR = await cdpManager.getCurrentICR(_account_cdps[account], price)
        ICRList.push(ICR)

        // Check cdp ordering by ICR is maintained
        if (ICRList.length > 1) {
          const prevICR = ICRList[ICRList.length - 2]

          try {
            assert.isTrue(ICR.gte(prevICR))
          } catch (error) {
            console.log(error)
            console.log(`ETH price at which cdp ordering breaks: ${price}`)
            logICRs(ICRList)
          }
        }

        price += 10
      }
    }
  })
})

