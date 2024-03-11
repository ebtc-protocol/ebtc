const fs = require('fs')

const ZERO_ADDRESS = '0x' + '0'.repeat(40)
const maxBytes32 = '0x' + 'f'.repeat(64)

class MainnetDeploymentHelper {
  constructor(configParams, deployerWallet) {
    this.configParams = configParams
    this.deployerWallet = deployerWallet
    this.hre = require("hardhat")
  }

  loadPreviousDeployment() {
    let previousDeployment = {}
    if (fs.existsSync(this.configParams.OUTPUT_FILE)) {
      console.log(`Loading previous deployment...`)
      previousDeployment = require('../' + this.configParams.OUTPUT_FILE)
    }

    return previousDeployment
  }

  saveDeployment(deploymentState) {
    const deploymentStateJSON = JSON.stringify(deploymentState, null, 2)
    fs.writeFileSync(this.configParams.OUTPUT_FILE, deploymentStateJSON)

  }
  // --- Deployer methods ---

  async getFactory(name) {
    const factory = await ethers.getContractFactory(name, this.deployerWallet)
    return factory
  }

  async sendAndWaitForTransaction(txPromise) {
    const tx = await txPromise
    const minedTx = await ethers.provider.waitForTransaction(tx.hash, this.configParams.TX_CONFIRMATIONS)

    return minedTx
  }

  async loadOrDeploy(factory, name, deploymentState, params=[]) {
    console.log("loadOrDeploy: ", name, deploymentState[name])

    // If the deployment exists in file already and has an address, load it
    if (deploymentState[name] && deploymentState[name].address) {
      console.log(`Using previously deployed ${name} contract at address ${deploymentState[name].address}`)
      return new ethers.Contract(
        deploymentState[name].address,
        factory.interface,
        this.deployerWallet
      );
    }

    // Otherwise, deploy it
    const contract = await factory.deploy(...params, {maxFeePerGas: this.configParams.MAX_FEE_PER_GAS})
    console.log(`Deployed new ${name} contract at address ${contract.address}`)
    await this.deployerWallet.provider.waitForTransaction(contract.deployTransaction.hash, this.configParams.TX_CONFIRMATIONS)

    deploymentState[name] = {
      address: contract.address,
      txHash: contract.deployTransaction.hash
    }

    this.saveDeployment(deploymentState)

    return contract
  }

  async deployEbtcCoreMainnet(configParams, deploymentState, chainId) {
    // Get contract factories
    // Testnet exceptions
    let priceFeedFactory
    if (configParams.TESTNET) {
      console.log("Testnet Mode: Using PriceFeedTestnet contract for priceFeed")
      priceFeedFactory = await this.getFactory("PriceFeedTestnet")
    } else {
      console.log("Fork Mode: Using PriceFeed contract for priceFeed")
      priceFeedFactory = await this.getFactory("PriceFeed")
    }
    const sortedCdpsFactory = await this.getFactory("SortedCdps")
    const liquidationLibraryFactory = await this.getFactory("LiquidationLibrary")
    const cdpManagerFactory = await this.getFactory("CdpManager")
    const activePoolFactory = await this.getFactory("ActivePool")
    const gasPoolFactory = await this.getFactory("GasPool")
    const defaultPoolFactory = await this.getFactory("DefaultPool")
    const collSurplusPoolFactory = await this.getFactory("CollSurplusPool")
    const borrowerOperationsFactory = await this.getFactory("BorrowerOperations")
    const hintHelpersFactory = await this.getFactory("HintHelpers")
    const ebtcTokenFactory = await this.getFactory("EBTCToken")
    // TODO: Use TellorCaller instead of TellorCallerMock
    const tellorCallerFactory = await this.getFactory("TellorCallerMock")

    console.log(deploymentState)

    // Deploy txs
    const priceFeed = await this.loadOrDeploy(priceFeedFactory, 'priceFeed', deploymentState)
    const sortedCdps = await this.loadOrDeploy(sortedCdpsFactory, 'sortedCdps', deploymentState)
    const liquidationLibrary = await this.loadOrDeploy(liquidationLibraryFactory, 'liquidationLibrary', deploymentState)
    const cdpManager = await this.loadOrDeploy(cdpManagerFactory, 'cdpManager', deploymentState, [liquidationLibrary.address])
    const activePool = await this.loadOrDeploy(activePoolFactory, 'activePool', deploymentState)
    const gasPool = await this.loadOrDeploy(gasPoolFactory, 'gasPool', deploymentState)
    const defaultPool = await this.loadOrDeploy(defaultPoolFactory, 'defaultPool', deploymentState)
    const collSurplusPool = await this.loadOrDeploy(collSurplusPoolFactory, 'collSurplusPool', deploymentState)
    const borrowerOperations = await this.loadOrDeploy(borrowerOperationsFactory, 'borrowerOperations', deploymentState)
    const hintHelpers = await this.loadOrDeploy(hintHelpersFactory, 'hintHelpers', deploymentState)
    const tellorCaller = await this.loadOrDeploy(tellorCallerFactory, 'tellorCaller', deploymentState, [configParams.externalAddrs.TELLOR_MASTER])

    const ebtcTokenParams = [
      cdpManager.address,
      borrowerOperations.address
    ]
    const ebtcToken = await this.loadOrDeploy(
      ebtcTokenFactory,
      'ebtcToken',
      deploymentState,
      ebtcTokenParams
    )

    if (!this.configParams.ETHERSCAN_BASE_URL) {
      console.log('No Etherscan Url defined, skipping verification')
    } else {
      await this.verifyContract('priceFeed', deploymentState)
      await this.verifyContract('sortedCdps', deploymentState)
      await this.verifyContract('cdpManager', deploymentState)
      await this.verifyContract('activePool', deploymentState)
      await this.verifyContract('gasPool', deploymentState)
      await this.verifyContract('defaultPool', deploymentState)
      await this.verifyContract('collSurplusPool', deploymentState)
      await this.verifyContract('borrowerOperations', deploymentState)
      await this.verifyContract('hintHelpers', deploymentState)
      await this.verifyContract('tellorCaller', deploymentState, [configParams.externalAddrs.TELLOR_MASTER])
      await this.verifyContract('ebtcToken', deploymentState, ebtcTokenParams)
    }

    const coreContracts = {
      priceFeed,
      ebtcToken,
      sortedCdps,
      cdpManager,
      activePool,
      gasPool,
      defaultPool,
      collSurplusPool,
      borrowerOperations,
      hintHelpers,
      tellorCaller
    }
    return coreContracts
  }

  async deployEBTCContractsMainnet(bountyAddress, lpRewardsAddress, multisigAddress, deploymentState) {
    const lqtyStakingFactory = await this.getFactory("FeeRecipient")

    const feeRecipient = await this.loadOrDeploy(lqtyStakingFactory, 'feeRecipient', deploymentState)

    if (!this.configParams.ETHERSCAN_BASE_URL) {
      console.log('No Etherscan Url defined, skipping verification')
    } else {
      await this.verifyContract('feeRecipient', deploymentState)
    }

    console.log("4")

    const EBTCContracts = {
      feeRecipient
    }
    return EBTCContracts
  }

  async deployUnipoolMainnet(deploymentState) {
    const unipoolFactory = await this.getFactory("Unipool")
    const unipool = await this.loadOrDeploy(unipoolFactory, 'unipool', deploymentState)

    if (!this.configParams.ETHERSCAN_BASE_URL) {
      console.log('No Etherscan Url defined, skipping verification')
    } else {
      await this.verifyContract('unipool', deploymentState)
    }

    return unipool
  }

  async deployMultiCdpGetterMainnet(ebtcCore, deploymentState) {
    const multiCdpGetterFactory = await this.getFactory("MultiCdpGetter")
    const multiCdpGetterParams = [
      ebtcCore.cdpManager.address,
      ebtcCore.sortedCdps.address
    ]
    const multiCdpGetter = await this.loadOrDeploy(
      multiCdpGetterFactory,
      'multiCdpGetter',
      deploymentState,
      multiCdpGetterParams
    )

    if (!this.configParams.ETHERSCAN_BASE_URL) {
      console.log('No Etherscan Url defined, skipping verification')
    } else {
      await this.verifyContract('multiCdpGetter', deploymentState, multiCdpGetterParams)
    }

    return multiCdpGetter
  }
  // --- Connector methods ---

  async isOwnershipRenounced(contract) {
    const owner = await contract.owner()
    return owner == ZERO_ADDRESS
  }
  // Connect contracts to their dependencies
  async connectCoreContractsMainnet(contracts, EBTCContracts, configParams) {
    const chainlinkProxyAddress = configParams.externalAddrs.CHAINLINK_ETHBTC_PROXY
    const stEthAddress = configParams.externalAddrs.STETH_ERC20

    const gasPrice = this.configParams.GAS_PRICE
    const maxFeePerGas = this.configParams.MAX_FEE_PER_GAS

    // Set ChainlinkAggregatorProxy and TellorCaller in the PriceFeed
    console.log("Set ChainlinkAggregatorProxy and TellorCaller in the PriceFeed")
    await this.isOwnershipRenounced(contracts.priceFeed) ||
      await this.sendAndWaitForTransaction(contracts.priceFeed.setAddresses(chainlinkProxyAddress, contracts.tellorCaller.address, {maxFeePerGas}))

    // set CdpManager addr in SortedCdps
    console.log("set CdpManager addr in SortedCdps")
    await this.isOwnershipRenounced(contracts.sortedCdps) ||
      await this.sendAndWaitForTransaction(contracts.sortedCdps.setParams(
        maxBytes32,
        contracts.cdpManager.address,
        contracts.borrowerOperations.address, 
	{maxFeePerGas}
      ))

    // set contracts in the Cdp Manager
    console.log("set contracts in the Cdp Manager")
    await this.isOwnershipRenounced(contracts.cdpManager) ||
      await this.sendAndWaitForTransaction(contracts.cdpManager.setAddresses(
        contracts.borrowerOperations.address,
        contracts.activePool.address,
        contracts.defaultPool.address,
        contracts.gasPool.address,
        contracts.collSurplusPool.address,
        contracts.priceFeed.address,
        contracts.ebtcToken.address,
        contracts.sortedCdps.address,
        EBTCContracts.lqtyToken.address,
        EBTCContracts.lqtyStaking.address,
        stEthAddress,
	{maxFeePerGas}
      ))

    // set contracts in BorrowerOperations 
    console.log("set contracts in BorrowerOperations")
    await this.isOwnershipRenounced(contracts.borrowerOperations) ||
      await this.sendAndWaitForTransaction(contracts.borrowerOperations.setAddresses(
        contracts.cdpManager.address,
        contracts.activePool.address,
        contracts.defaultPool.address,
        contracts.gasPool.address,
        contracts.collSurplusPool.address,
        contracts.priceFeed.address,
        contracts.sortedCdps.address,
        contracts.ebtcToken.address,
        EBTCContracts.lqtyStaking.address,
        stEthAddress,
	{maxFeePerGas}
      ))

    // set contracts in the Pools
    console.log("set contracts in the ActivePool")
    await this.isOwnershipRenounced(contracts.activePool) ||
      await this.sendAndWaitForTransaction(contracts.activePool.setAddresses(
        contracts.borrowerOperations.address,
        contracts.cdpManager.address,
        contracts.defaultPool.address,
        stEthAddress,
        contracts.collSurplusPool.address,
	{maxFeePerGas}
      ))
    
      console.log("set contracts in the DefaultPool")
    await this.isOwnershipRenounced(contracts.defaultPool) ||
      await this.sendAndWaitForTransaction(contracts.defaultPool.setAddresses(
        contracts.cdpManager.address,
        contracts.activePool.address,
        stEthAddress,
	{maxFeePerGas}
      ))
    
    console.log("set contracts in the CollSurplusPool")
    await this.isOwnershipRenounced(contracts.collSurplusPool) ||
      await this.sendAndWaitForTransaction(contracts.collSurplusPool.setAddresses(
        contracts.borrowerOperations.address,
        contracts.cdpManager.address,
        contracts.activePool.address,
        stEthAddress,
	{maxFeePerGas}
      ))

    // set contracts in HintHelpers
    console.log("set contracts in HintHelpers")
    await this.isOwnershipRenounced(contracts.hintHelpers) ||
      await this.sendAndWaitForTransaction(contracts.hintHelpers.setAddresses(
        contracts.sortedCdps.address,
        contracts.cdpManager.address,
	{maxFeePerGas}
      ))
  }

  async connectEBTCContractsToCoreMainnet(EBTCContracts, coreContracts) {
    const gasPrice = this.configParams.GAS_PRICE
    await this.isOwnershipRenounced(EBTCContracts.feeRecipient) ||
      await this.sendAndWaitForTransaction(EBTCContracts.feeRecipient.setAddresses(
        EBTCContracts.lqtyToken.address,
        coreContracts.ebtcToken.address,
        coreContracts.cdpManager.address, 
        coreContracts.borrowerOperations.address,
        coreContracts.activePool.address,
        stEthAddress,
	{maxFeePerGas}
      ))
  }

  async connectUnipoolMainnet(uniPool, EBTCContracts, EBTCWETHPairAddr, duration) {
    const gasPrice = this.configParams.GAS_PRICE
    const maxFeePerGas = this.configParams.MAX_FEE_PER_GAS
    await this.isOwnershipRenounced(uniPool) ||
      await this.sendAndWaitForTransaction(uniPool.setParams(EBTCContracts.lqtyToken.address, EBTCWETHPairAddr, duration, {maxFeePerGas}))
  }

  // --- Verify on Ethrescan ---
  async verifyContract(name, deploymentState, constructorArguments=[]) {
    if (!deploymentState[name] || !deploymentState[name].address) {
      console.error(`  --> No deployment state for contract ${name}!!`)
      return
    }
    if (deploymentState[name].verification) {
      console.log(`Contract ${name} already verified`)
      return
    }

    try {
      console.log(constructorArguments)
      await this.hre.run("verify:verify", {
        address: deploymentState[name].address,
        constructorArguments,
      })
    } catch (error) {
      console.log(`Error verifying: ${error.name}-${error.message}`)	  
      // if it was already verified, it’s like a success, so let’s move forward and save it
      if (error.name != 'NomicLabsHardhatPluginError' 
          || error.message.includes('Unable to verify')
          || error.message.includes('The constructor for')
          || error.message.includes('More than one contract was found')
      ) {
        console.error(`Error stop verifying: ${error.name}`)
        console.error(error)
        console.log(constructorArguments)
        return
      }
    }

    deploymentState[name].verification = `${this.configParams.ETHERSCAN_BASE_URL}/${deploymentState[name].address}#code`

    this.saveDeployment(deploymentState)
  }

  // --- Helpers ---

  async logContractObjects (contracts) {
    console.log(`Contract objects addresses:`)
    for ( const contractName of Object.keys(contracts)) {
      console.log(`${contractName}: ${contracts[contractName].address}`);
    }
  }
}

module.exports = MainnetDeploymentHelper
