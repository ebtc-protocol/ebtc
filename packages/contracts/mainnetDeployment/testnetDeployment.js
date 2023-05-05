const { UniswapV2Factory } = require("./ABIs/UniswapV2Factory.js")
const { UniswapV2Pair } = require("./ABIs/UniswapV2Pair.js")
const { UniswapV2Router02 } = require("./ABIs/UniswapV2Router02.js")
const { Lido } = require("./ABIs/Lido.js")
const { TestHelper: th, TimeValues: timeVals } = require("../utils/testHelpers.js")
const MainnetDeploymentHelper = require("../utils/mainnetDeploymentHelpers.js")
const fs = require("fs");

const toBigNum = ethers.BigNumber.from
const mintAmountPerTestAccount = toBigNum("100000000000000000000")

async function testnetDeploy(configParams) {
  const date = new Date()
  console.log(date.toUTCString())
  const deployerWallet = (await ethers.getSigners())[0]
  const mdh = new MainnetDeploymentHelper(configParams, deployerWallet)
  const gasPrice = configParams.GAS_PRICE
  const maxFeePerGas = configParams.MAX_FEE_PER_GAS

  let latestBlock = await ethers.provider.getBlockNumber()
  console.log('block number:', latestBlock)
  const chainId = await ethers.provider.getNetwork()
  console.log('ChainId:', chainId.chainId)

  let deploymentState = mdh.loadPreviousDeployment()

  const ZERO_ADDRESS = th.ZERO_ADDRESS

  // Set flag for helper use
  configParams.TESTNET = true;

  // If local deployment record present, check if it exists in current environment
  if (Object.entries(deploymentState).length != 0 && chainId.chainId == 31337) {
    const priceFeedFactory = await ethers.getContractFactory("PriceFeed", deployerWallet)
    let priceFeed = new ethers.Contract(
      deploymentState["priceFeed"].address,
      priceFeedFactory.interface,
      deployerWallet
    );
    try {
      await priceFeed.status()
    } catch {
      console.log('New local environment: Deleting previous deployment record...')
      try {
        fs.unlinkSync(configParams.OUTPUT_FILE);
        console.log("File removed:", configParams.OUTPUT_FILE);
        deploymentState = {}
      } catch (err) {
        console.error(err);
      }
    }
  }

  console.log(`deployer address: ${deployerWallet.address}`)
  let deployerETHBalance = await ethers.provider.getBalance(deployerWallet.address)
  console.log(`deployerETHBalance before: ${deployerETHBalance}`)

  // Deploy or load mock WETH and collateral token contracts
  const wethTokenFactory = await mdh.getFactory("WethMock")
  const collateralTokenFactory = await mdh.getFactory("StETHMock")

  const wethToken = await mdh.loadOrDeploy(wethTokenFactory, 'wethToken', deploymentState)
  const collateralToken = await mdh.loadOrDeploy(collateralTokenFactory, 'collateralToken', deploymentState, [wethToken.address])

  // Use mock collateral and weth addresses for future referenfces
  configParams.externalAddrs.WETH_ERC20 = wethToken.address
  configParams.externalAddrs.STETH_ERC20 = collateralToken.address

  // Verify mock tokens if available
  if (!configParams.ETHERSCAN_BASE_URL) {
    console.log('No Etherscan Url defined, skipping verification')
  } else {
    await mdh.verifyContract('wethToken', deploymentState)
    await mdh.verifyContract('collateralToken', deploymentState, [wethToken.address])
  }

  // Deploy core logic contracts
  console.log("deployEbtcCoreMainnet...")
  const ebtcCore = await mdh.deployEbtcCoreMainnet(configParams, deploymentState, chainId)
  await mdh.logContractObjects(ebtcCore)

  // Deploy EBTC Contracts
  console.log("deployEBTCContractsMainnet...")
  const EBTCContracts = await mdh.deployEBTCContractsMainnet(
    configParams.ebtcAddrs.EBTC_SAFE, // bounty address
    configParams.ebtcAddrs.EBTC_SAFE,  // lp rewards address
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
  console.log("\n == PRICEFEED CHECKS ==")
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

  // Mint wETH and collateral to tester addresses if specified

  if (configParams.testAccounts) {
    // Mint enough mock assets for all test accounts
    const numAccounts = configParams.testAccounts.length
    const mintAmountTotal = mintAmountPerTestAccount.mul(toBigNum(numAccounts))

    await mdh.sendAndWaitForTransaction(wethToken.deposit(mintAmountTotal.mul(2), {maxFeePerGas}))

    await mdh.sendAndWaitForTransaction(wethToken.approve(collateralToken.address, mintAmountTotal, {maxFeePerGas}))

    await mdh.sendAndWaitForTransaction(collateralToken.deposit(mintAmountTotal, {maxFeePerGas}))

    const wethBalance = await wethToken.balanceOf(deployerWallet.address)
    const collBalance = await collateralToken.balanceOf(deployerWallet.address)

    console.log(`deployer ${deployerWallet.address} weth after mint: ${wethBalance}`)
    console.log(`deployer ${deployerWallet.address} coll after mint: ${collBalance}`)

    // Transfer to individual accounts
    console.log("Seed test accounts with mock wETH and collateral")
    for (account of configParams.testAccounts) {
      console.log("Funding ", account)
      await mdh.sendAndWaitForTransaction(wethToken.transfer(account, mintAmountPerTestAccount, {maxFeePerGas}))
      await mdh.sendAndWaitForTransaction(collateralToken.transfer(account, mintAmountPerTestAccount, {maxFeePerGas}))

      const wethBalance = await wethToken.balanceOf(account)
      const collBalance = await collateralToken.balanceOf(account)

      console.log(`${account} weth after transfer: ${wethBalance}`)
      console.log(`${account} coll after transfer: ${collBalance}\n`)
    }
  } else {
    console.log("No test accounts specified to fund with mock assets")
  }

  console.log("\n == SYSTEM GLOBAL VARS CHECKS ==")
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
