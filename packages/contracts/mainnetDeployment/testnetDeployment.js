const { Lido } = require("./ABIs/Lido.js")
const { TestHelper: th, TimeValues: timeVals } = require("../utils/testHelpers.js")
const MainnetDeploymentHelper = require("../utils/mainnetDeploymentHelpers.js")

const toBigNum = ethers.BigNumber.from

async function testnetDeploy(configParams) {
  const date = new Date()
  console.log(date.toUTCString())
  const deployerWallet = (await ethers.getSigners())[0]
  const mdh = new MainnetDeploymentHelper(configParams, deployerWallet)
  const gasPrice = configParams.GAS_PRICE

  let latestBlock = await ethers.provider.getBlockNumber()
  console.log('block number:', latestBlock)
  const chainId = await ethers.provider.getNetwork()
  console.log('ChainId:', chainId.chainId)

  let deploymentState = mdh.loadPreviousDeployment()

  const ZERO_ADDRESS = th.ZERO_ADDRESS

  console.log(`deployer address: ${deployerWallet.address}`)
  let deployerETHBalance = await ethers.provider.getBalance(deployerWallet.address)
  console.log(`deployerETHBalance before: ${deployerETHBalance}`)

  // Get the collateral token contract
  const collateralToken = new ethers.Contract(
    configParams.externalAddrs.WETH_ERC20, // Change for mock Collateral
    Lido.abi,
    deployerWallet
  )

  // Deploy core logic contracts
  console.log("deployEbtcCoreMainnet...")
  const ebtcCore = await mdh.deployEbtcCoreMainnet(configParams, deploymentState, chainId)
  await mdh.logContractObjects(ebtcCore)

  // Deploy EBTC Contracts
  console.log("deployEBTCContractsMainnet...")
  const EBTCContracts = await mdh.deployEBTCContractsMainnet(
    configParams.ebtcAddrs.GENERAL_SAFE, // bounty address
    ZERO_ADDRESS,  // lp rewards address
    configParams.ebtcAddrs.EBTC_SAFE, // multisig EBTC endowment address
    deploymentState,
  )

  // Connect all core contracts up
  console.log("connectCoreContractsMainnet...")
  await mdh.connectCoreContractsMainnet(ebtcCore, EBTCContracts, configParams)

  // Deploy a read-only multi-cdp getter
  console.log("deployMultiCdpGetterMainnet...")
  const multiCdpGetter = await mdh.deployMultiCdpGetterMainnet(ebtcCore, deploymentState)


  // --- PriceFeed ---
  console.log("PRICEFEED CHECKS")
  // Check Pricefeed's status and last good price
  const lastGoodPrice = await ebtcCore.priceFeed.fetchPrice()
  const priceFeedInitialTellorStatus = await ebtcCore.priceFeed._useTellor()
  th.logBN('PriceFeed first stored price', lastGoodPrice)
  console.log(`PriceFeed initial Tellor status: ${priceFeedInitialTellorStatus}`)

  // Check PriceFeed's & TellorCaller's stored addresses
  const priceFeedTellorCallerAddress = await ebtcCore.priceFeed.tellorCaller()
  assert.equal(priceFeedTellorCallerAddress, ebtcCore.tellorCaller.address)

  // Check Tellor address
  const tellorCallerTellorMasterAddress = await ebtcCore.tellorCaller.tellor()
  assert.equal(tellorCallerTellorMasterAddress, configParams.externalAddrs.TELLOR_MASTER)


  console.log("SYSTEM GLOBAL VARS CHECKS")
  // --- Sorted Cdps ---

  // Check max size
  const sortedCdpsMaxSize = (await ebtcCore.sortedCdps.data())[2]
  assert.equal(sortedCdpsMaxSize, '115792089237316195423570985008687907853269984665640564039457584007913129639935')

  // --- CdpManager ---

  const liqReserve = await ebtcCore.cdpManager.EBTC_GAS_COMPENSATION()
  const minNetDebt = await ebtcCore.cdpManager.MIN_NET_DEBT()

  th.logBN('system liquidation reserve', liqReserve)
  th.logBN('system min net debt      ', minNetDebt)
}

module.exports = {
  testnetDeploy
}
