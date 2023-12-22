const deploymentHelper = require("../utils/deploymentHelpers.js")
const testHelpers = require("../utils/testHelpers.js")
const CdpManagerTester = artifacts.require("./CdpManagerTester.sol")
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
 * the parameter BETA in the CdpManager, which is still TBD based on economic modelling.
 * 
 */
contract('CdpManager', async accounts => {

  const ZERO_ADDRESS = th.ZERO_ADDRESS
  const [owner, A, B, C, D, E, F] = accounts.slice(0, 7);

  const [bountyAddress, lpRewardsAddress, multisig] = accounts.slice(accounts.length - 3, accounts.length)

  let priceFeed
  let ebtcToken
  let sortedCdps
  let cdpManager
  let activePool
  let collSurplusPool
  let borrowerOperations
  let hintHelpers

  let contracts

  const getOpenCdpEBTCAmount = async (totalDebt) => th.getOpenCdpEBTCAmount(contracts, totalDebt)
 
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
    contracts = await deploymentHelper.deployTesterContractsHardhat()
    let LQTYContracts = {}
    LQTYContracts.feeRecipient = contracts.feeRecipient;

    priceFeed = contracts.priceFeedTestnet
    ebtcToken = contracts.ebtcToken
    sortedCdps = contracts.sortedCdps
    cdpManager = contracts.cdpManager
    activePool = contracts.activePool
    collSurplusPool = contracts.collSurplusPool
    borrowerOperations = contracts.borrowerOperations
    hintHelpers = contracts.hintHelpers
    debtToken = ebtcToken;

    feeRecipient = LQTYContracts.feeRecipient

    await deploymentHelper.connectCoreContracts(contracts, LQTYContracts)
  })

  it("A given cdp's stake decline is negligible with adjustments and tiny liquidations", async () => {
    await priceFeed.setPrice(dec(400, 18))
  
    // Make 1 mega cdps A at ~50% total collateral
    let _aColAmt = dec(8, 19);
    let _aDebtAmt = dec(1, 22);
    await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: A});
    await contracts.collateral.deposit({from: A, value: _aColAmt});
    await borrowerOperations.openCdp(await getOpenCdpEBTCAmount(_aDebtAmt), th.DUMMY_BYTES32, th.DUMMY_BYTES32, _aColAmt, { from: A, value: 0 })
    let _aCdpId = await sortedCdps.cdpOfOwnerByIndex(A, 0);
    
    // Make 5 large cdps B, C, D, E, F at ~10% total collateral
    let _colAmt = dec(4, 19);
    let _debtAmt = dec(1, 22);
    await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: B});
    await contracts.collateral.deposit({from: B, value: _colAmt});
    await borrowerOperations.openCdp(await getOpenCdpEBTCAmount(_debtAmt), th.DUMMY_BYTES32, th.DUMMY_BYTES32, _colAmt, { from: B, value: 0 })
    let _bCdpId = await sortedCdps.cdpOfOwnerByIndex(B, 0);
    await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: C});
    await contracts.collateral.deposit({from: C, value: _colAmt});
    await borrowerOperations.openCdp(await getOpenCdpEBTCAmount(_debtAmt), th.DUMMY_BYTES32, th.DUMMY_BYTES32, _colAmt, { from: C, value: 0 })
    await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: D});
    await contracts.collateral.deposit({from: D, value: _colAmt});
    await borrowerOperations.openCdp(await getOpenCdpEBTCAmount(_debtAmt), th.DUMMY_BYTES32, th.DUMMY_BYTES32, _colAmt, { from: D, value: 0 })
    await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: E});
    await contracts.collateral.deposit({from: E, value: _colAmt});
    await borrowerOperations.openCdp(await getOpenCdpEBTCAmount(_debtAmt), th.DUMMY_BYTES32, th.DUMMY_BYTES32, _colAmt, { from: E, value: 0 })
    await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: F});
    await contracts.collateral.deposit({from: F, value: _colAmt});
    await borrowerOperations.openCdp(await getOpenCdpEBTCAmount(_debtAmt), th.DUMMY_BYTES32, th.DUMMY_BYTES32, _colAmt, { from: F, value: 0 })
  
    // Make 10 tiny cdps at relatively negligible collateral (~1e-9 of total)
    const tinyCdps = accounts.slice(10, 20)
    let _tinyCdpIds = {}
    for (account of tinyCdps) {
      await contracts.collateral.approve(borrowerOperations.address, mv._1Be18BN, {from: account});
      await contracts.collateral.deposit({from: account, value: dec(2, 20)});
      await borrowerOperations.openCdp(await getOpenCdpEBTCAmount(dec(1, 22)), th.DUMMY_BYTES32, th.DUMMY_BYTES32, dec(2, 20), { from: account, value: 0 })
      _tinyCdpIds[account] = await sortedCdps.cdpOfOwnerByIndex(account, 0);
      await debtToken.transfer(owner, (await debtToken.balanceOf(account)).sub(toBN('2')), {from: account});	  
    }

    // liquidate 1 cdp at ~50% total system collateral
    await priceFeed.setPrice(dec(50, 18))
    assert.isTrue(await cdpManager.checkRecoveryMode(await priceFeed.getPrice()))
    await debtToken.transfer(owner, (await debtToken.balanceOf(A)).sub(toBN('2')), {from: A});  
    await debtToken.transfer(owner, (await debtToken.balanceOf(C)).sub(toBN('2')), {from: C});	  
    await debtToken.transfer(owner, (await debtToken.balanceOf(D)).sub(toBN('2')), {from: D});	  
    await debtToken.transfer(owner, (await debtToken.balanceOf(E)).sub(toBN('2')), {from: E});	  
    await cdpManager.liquidate(_aCdpId, {from: owner})

    console.log(`totalStakesSnapshot after L1: ${await cdpManager.totalStakesSnapshot()}`)
    console.log(`totalCollateralSnapshot after L1: ${await cdpManager.totalCollateralSnapshot()}`)
    console.log(`Snapshots ratio after L1: ${await getSnapshotsRatio()}`)
    console.log(`B stake after L1: ${(await cdpManager.Cdps(_bCdpId))[2]}`)

    // adjust cdp B 1 wei: apply rewards
    await borrowerOperations.adjustCdp(
      _bCdpId, 0, await borrowerOperations.MIN_CHANGE(), false, th.DUMMY_BYTES32, th.DUMMY_BYTES32, 
      {from: B}
    )  // B repays borrowerOperations.MIN_CHANGE() wei
    console.log(`B stake after A1: ${(await cdpManager.Cdps(_bCdpId))[2]}`)
    console.log(`Snapshots ratio after A1: ${await getSnapshotsRatio()}`)

    // Loop over tiny cdps, and alternately:
    // - Liquidate a tiny cdp
    // - Adjust B's collateral by 1 wei
    for (let [idx, cdp] of tinyCdps.entries()) {
      await cdpManager.liquidate(_tinyCdpIds[cdp], {from: owner})
      console.log(`B stake after L${idx + 2}: ${(await cdpManager.Cdps(_bCdpId))[2]}`)
      console.log(`Snapshots ratio after L${idx + 2}: ${await getSnapshotsRatio()}`)
      await borrowerOperations.adjustCdp(
        _bCdpId, 0, await borrowerOperations.MIN_CHANGE(), false, th.DUMMY_BYTES32, th.DUMMY_BYTES32, 
        {from: B}
      )  // A repays await borrowerOperations.MIN_CHANGE() wei
      console.log(`B stake after A${idx + 2}: ${(await cdpManager.Cdps(_bCdpId))[2]}`)
    }
  })

  // TODO: stake decline for adjustments with sizable liquidations, for comparison
})