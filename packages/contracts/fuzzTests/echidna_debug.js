const { TestHelper: { dec } } = require("../utils/testHelpers.js")

const EchidnaTester = artifacts.require('EchidnaTester')
const CdpManager = artifacts.require('CdpManager')
const EBTCToken = artifacts.require('EBTCToken')
const ActivePool = artifacts.require('ActivePool')
const DefaultPool = artifacts.require('DefaultPool')
const StabilityPool = artifacts.require('StabilityPool')

// run with:
// npx hardhat --config hardhat.config.echidna.js test fuzzTests/echidna_debug.js

contract('Echidna debugger', async accounts => {
  let echidnaTester
  let cdpManager
  let ebtcToken
  let activePool
  let defaultPool
  let stabilityPool
  let GAS_POOL_ADDRESS

  before(async () => {
    echidnaTester = await EchidnaTester.new({ value: dec(11, 25) })
    cdpManager = await CdpManager.at(await echidnaTester.cdpManager())
    ebtcToken = await EBTCToken.at(await echidnaTester.ebtcToken())
    activePool = await ActivePool.at(await echidnaTester.activePool())
    defaultPool = await DefaultPool.at(await echidnaTester.defaultPool())
    stabilityPool = await StabilityPool.at(await echidnaTester.stabilityPool())
    GAS_POOL_ADDRESS = await cdpManager.GAS_POOL_ADDRESS();
  })

  it('openCdp', async () => {
    await echidnaTester.openCdpExt(
      '28533397325200555203581702704626658822751905051193839801320459908900876958892',
      '52469987802830075086048985199642144541375565475567220729814021622139768827880',
      '9388634783070735775888100571650283386615011854365252563480851823632223689886'
    )
  })

  it('openCdp', async () => {
    await echidnaTester.openCdpExt('0', '0', '0')
  })

  it.skip('cdp order', async () => {
    const cdp1 = await echidnaTester.echidnaProxies(0)
    console.log(cdp1)
    const cdp2 = await echidnaTester.echidnaProxies(1)

    const icr1_before = await cdpManager.getCachedICR(cdp1, '1000000000000000000')
    const icr2_before = await cdpManager.getCachedICR(cdp2, '1000000000000000000')
    console.log('Cdp 1', icr1_before, icr1_before.toString())
    console.log('Cdp 2', icr2_before, icr2_before.toString())

    await echidnaTester.openCdpExt('0', '0', '30540440604590048251848424')
    await echidnaTester.openCdpExt('1', '0', '0')
    await echidnaTester.setPriceExt('78051143795343077331468494330613608802436946862454908477491916')
    const icr1_after = await cdpManager.getCachedICR(cdp1, '1000000000000000000')
    const icr2_after = await cdpManager.getCachedICR(cdp2, '1000000000000000000')
    console.log('Cdp 1', icr1_after, icr1_after.toString())
    console.log('Cdp 2', icr2_after, icr2_after.toString())

    const icr1_after_price = await cdpManager.getCachedICR(cdp1, '78051143795343077331468494330613608802436946862454908477491916')
    const icr2_after_price = await cdpManager.getCachedICR(cdp2, '78051143795343077331468494330613608802436946862454908477491916')
    console.log('Cdp 1', icr1_after_price, icr1_after_price.toString())
    console.log('Cdp 2', icr2_after_price, icr2_after_price.toString())
  })

  it.only('EBTC balance', async () => {
    await echidnaTester.openCdpExt('0', '0', '4210965169908805439447313562489173090')

    const totalSupply = await ebtcToken.totalSupply();
    const gasPoolBalance = await ebtcToken.balanceOf(GAS_POOL_ADDRESS);
    const activePoolBalance = await activePool.getSystemDebt();
    const defaultPoolBalance = await defaultPool.getSystemDebt();
    const stabilityPoolBalance = await stabilityPool.getTotalEBTCDeposits();
    const currentCdp = await echidnaTester.echidnaProxies(0);
    const cdpBalance = ebtcToken.balanceOf(currentCdp);

    console.log('totalSupply', totalSupply.toString());
    console.log('gasPoolBalance', gasPoolBalance.toString());
    console.log('activePoolBalance', activePoolBalance.toString());
    console.log('defaultPoolBalance', defaultPoolBalance.toString());
    console.log('stabilityPoolBalance', stabilityPoolBalance.toString());
    console.log('cdpBalance', cdpBalance.toString());
  })
})
