const deploymentHelper = require("../utils/deploymentHelpers.js")
const testHelpers = require("../utils/testHelpers.js")
const TroveManagerTester = artifacts.require("./TroveManagerTester.sol")
const EBTCTokenTester = artifacts.require("./EBTCTokenTester.sol")

const th = testHelpers.TestHelper
const dec = th.dec
const toBN = th.toBN
const assertRevert = th.assertRevert
const mv = testHelpers.MoneyValues
const timeValues = testHelpers.TimeValues


/* NOTE: Some tests involving ETH redemption fees do not test for specific fee values.
 * Some only test that the fees are non-zero when they should occur.
 *
 * Specific ETH gain values will depend on the final fee schedule used, and the final choices for
 * the parameter BETA in the TroveManager, which is still TBD based on economic modelling.
 * 
 */
contract('TroveManager', async accounts => {

  const ZERO_ADDRESS = th.ZERO_ADDRESS
  const [owner, A, B, C, D, E, F] = accounts.slice(0, 7);

  const [bountyAddress, lpRewardsAddress, multisig] = accounts.slice(accounts.length - 3, accounts.length)

  let priceFeed
  let ebtcToken
  let sortedTroves
  let cdpManager
  let activePool
  let stabilityPool
  let collSurplusPool
  let defaultPool
  let borrowerOperations
  let hintHelpers

  let contracts

  const getOpenTroveEBTCAmount = async (totalDebt) => th.getOpenTroveEBTCAmount(contracts, totalDebt)
 
  const getSnapshotsRatio = async () => {
    const ratio = (await cdpManager.totalStakesSnapshot())
      .mul(toBN(dec(1, 18)))
      .div((await cdpManager.totalCollateralSnapshot()))

    return ratio
  }

  before(async () => {	  
    // let _forkBlock = hre.network.config['forking']['blockNumber'];
    // let _forkUrl = hre.network.config['forking']['url'];
    // console.log("resetting to mainnet fork: block=" + _forkBlock + ',url=' + _forkUrl);
    // await hre.network.provider.request({ method: "hardhat_reset", params: [ { forking: { jsonRpcUrl: _forkUrl, blockNumber: _forkBlock }} ] });
  })

  beforeEach(async () => {
    contracts = await deploymentHelper.deployLiquityCore()
    contracts.cdpManager = await TroveManagerTester.new()
    contracts.ebtcToken = await EBTCTokenTester.new(
      contracts.cdpManager.address,
      contracts.stabilityPool.address,
      contracts.borrowerOperations.address
    )
    const LQTYContracts = await deploymentHelper.deployLQTYContracts(bountyAddress, lpRewardsAddress, multisig)

    priceFeed = contracts.priceFeedTestnet
    ebtcToken = contracts.ebtcToken
    sortedTroves = contracts.sortedTroves
    cdpManager = contracts.cdpManager
    activePool = contracts.activePool
    stabilityPool = contracts.stabilityPool
    defaultPool = contracts.defaultPool
    collSurplusPool = contracts.collSurplusPool
    borrowerOperations = contracts.borrowerOperations
    hintHelpers = contracts.hintHelpers

    lqtyStaking = LQTYContracts.lqtyStaking
    lqtyToken = LQTYContracts.lqtyToken
    communityIssuance = LQTYContracts.communityIssuance
    lockupContractFactory = LQTYContracts.lockupContractFactory

    await deploymentHelper.connectCoreContracts(contracts, LQTYContracts)
    await deploymentHelper.connectLQTYContracts(LQTYContracts)
    await deploymentHelper.connectLQTYContractsToCore(LQTYContracts, contracts)
  })

  it("A given cdp's stake decline is negligible with adjustments and tiny liquidations", async () => {
    await priceFeed.setPrice(dec(400, 18))
  
    // Make 1 mega cdps A at ~50% total collateral
    let _aColAmt = dec(8, 19);
    let _aDebtAmt = dec(1, 22);
    await borrowerOperations.openTrove(th._100pct, await getOpenTroveEBTCAmount(_aDebtAmt), th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: A, value: _aColAmt })
    let _aTroveId = await sortedTroves.cdpOfOwnerByIndex(A, 0);
    
    // Make 5 large cdps B, C, D, E, F at ~10% total collateral
    let _colAmt = dec(4, 19);
    let _debtAmt = dec(1, 22);
    await borrowerOperations.openTrove(th._100pct, await getOpenTroveEBTCAmount(_debtAmt), th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: B, value: _colAmt })
    let _bTroveId = await sortedTroves.cdpOfOwnerByIndex(B, 0);
    await borrowerOperations.openTrove(th._100pct, await getOpenTroveEBTCAmount(_debtAmt), th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: C, value: _colAmt })
    await borrowerOperations.openTrove(th._100pct, await getOpenTroveEBTCAmount(_debtAmt), th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: D, value: _colAmt })
    await borrowerOperations.openTrove(th._100pct, await getOpenTroveEBTCAmount(_debtAmt), th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: E, value: _colAmt })
    await borrowerOperations.openTrove(th._100pct, await getOpenTroveEBTCAmount(_debtAmt), th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: F, value: _colAmt })
  
    // Make 10 tiny cdps at relatively negligible collateral (~1e-9 of total)
    const tinyTroves = accounts.slice(10, 20)
    let _tinyTroveIds = {}
    for (account of tinyTroves) {
      await borrowerOperations.openTrove(th._100pct, await getOpenTroveEBTCAmount(dec(1, 22)), th.DUMMY_BYTES32, th.DUMMY_BYTES32, { from: account, value: dec(2, 20) })
      _tinyTroveIds[account] = await sortedTroves.cdpOfOwnerByIndex(account, 0);
    }

    // liquidate 1 cdp at ~50% total system collateral
    await priceFeed.setPrice(dec(50, 18))
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))
    await cdpManager.liquidate(_aTroveId)

    console.log(`totalStakesSnapshot after L1: ${await cdpManager.totalStakesSnapshot()}`)
    console.log(`totalCollateralSnapshot after L1: ${await cdpManager.totalCollateralSnapshot()}`)
    console.log(`Snapshots ratio after L1: ${await getSnapshotsRatio()}`)
    console.log(`B pending ETH reward after L1: ${await cdpManager.getPendingETHReward(B)}`)
    console.log(`B stake after L1: ${(await cdpManager.Troves(_bTroveId))[2]}`)

    // adjust cdp B 1 wei: apply rewards
    await borrowerOperations.adjustTrove(_bTroveId, th._100pct, 0, 1, false, th.DUMMY_BYTES32, th.DUMMY_BYTES32, {from: B})  // B repays 1 wei
    console.log(`B stake after A1: ${(await cdpManager.Troves(_bTroveId))[2]}`)
    console.log(`Snapshots ratio after A1: ${await getSnapshotsRatio()}`)

    // Loop over tiny cdps, and alternately:
    // - Liquidate a tiny cdp
    // - Adjust B's collateral by 1 wei
    for (let [idx, cdp] of tinyTroves.entries()) {
      await cdpManager.liquidate(_tinyTroveIds[cdp])
      console.log(`B stake after L${idx + 2}: ${(await cdpManager.Troves(_bTroveId))[2]}`)
      console.log(`Snapshots ratio after L${idx + 2}: ${await getSnapshotsRatio()}`)
      await borrowerOperations.adjustTrove(_bTroveId, th._100pct, 0, 1, false, th.DUMMY_BYTES32, th.DUMMY_BYTES32, {from: B})  // A repays 1 wei
      console.log(`B stake after A${idx + 2}: ${(await cdpManager.Troves(_bTroveId))[2]}`)
    }
  })

  // TODO: stake decline for adjustments with sizable liquidations, for comparison
})