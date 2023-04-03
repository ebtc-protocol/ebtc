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
    if (deploymentState[name] && deploymentState[name].address) {
      console.log(`Using previously deployed ${name} contract at address ${deploymentState[name].address}`)
      return new ethers.Contract(
        deploymentState[name].address,
        factory.interface,
        this.deployerWallet
      );
    }

    const contract = await factory.deploy(...params, {gasPrice: this.configParams.GAS_PRICE})
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
    const cdpManagerFactory = await this.getFactory("CdpManager")
    const activePoolFactory = await this.getFactory("ActivePool")
    const gasPoolFactory = await this.getFactory("GasPool")
    const defaultPoolFactory = await this.getFactory("DefaultPool")
    const collSurplusPoolFactory = await this.getFactory("CollSurplusPool")
    const borrowerOperationsFactory = await this.getFactory("BorrowerOperations")
    const hintHelpersFactory = await this.getFactory("HintHelpers")
    const ebtcTokenFactory = await this.getFactory("EBTCToken")
    const tellorCallerFactory = await this.getFactory("TellorCaller")

    console.log(deploymentState)

    // Deploy txs
    const priceFeed = await this.loadOrDeploy(priceFeedFactory, 'priceFeed', deploymentState)
    const sortedCdps = await this.loadOrDeploy(sortedCdpsFactory, 'sortedCdps', deploymentState)
    const cdpManager = await this.loadOrDeploy(cdpManagerFactory, 'cdpManager', deploymentState)
    const activePool = await this.loadOrDeploy(activePoolFactory, 'activePool', deploymentState, [configParams.externalAddrs.WETH_ERC20])
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
    console.log("0")
    const lqtyStakingFactory = await this.getFactory("LQTYStaking")
    const lockupContractFactory_Factory = await this.getFactory("LockupContractFactory")
    const communityIssuanceFactory = await this.getFactory("CommunityIssuance")
    const lqtyTokenFactory = await this.getFactory("LQTYToken")

    const lqtyStaking = await this.loadOrDeploy(lqtyStakingFactory, 'lqtyStaking', deploymentState)
    const lockupContractFactory = await this.loadOrDeploy(lockupContractFactory_Factory, 'lockupContractFactory', deploymentState)
    const communityIssuance = await this.loadOrDeploy(communityIssuanceFactory, 'communityIssuance', deploymentState)

    // Deploy LQTY Token, passing Community Issuance and Factory addresses to the constructor
    const lqtyTokenParams = [
      communityIssuance.address,
      lqtyStaking.address,
      lockupContractFactory.address,
      bountyAddress,
      lpRewardsAddress,
      multisigAddress
    ]
    const lqtyToken = await this.loadOrDeploy(
      lqtyTokenFactory,
      'lqtyToken',
      deploymentState,
      lqtyTokenParams
    )

    if (!this.configParams.ETHERSCAN_BASE_URL) {
      console.log('No Etherscan Url defined, skipping verification')
    } else {
      await this.verifyContract('lqtyStaking', deploymentState)
      await this.verifyContract('lockupContractFactory', deploymentState)
      await this.verifyContract('communityIssuance', deploymentState)
      await this.verifyContract('lqtyToken', deploymentState, lqtyTokenParams)
    }

    console.log("4")

    const EBTCContracts = {
      lqtyStaking,
      lockupContractFactory,
      communityIssuance,
      lqtyToken
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
    // Set ChainlinkAggregatorProxy and TellorCaller in the PriceFeed
    console.log("Set ChainlinkAggregatorProxy and TellorCaller in the PriceFeed")
    await this.isOwnershipRenounced(contracts.priceFeed) ||
      await this.sendAndWaitForTransaction(contracts.priceFeed.setAddresses(chainlinkProxyAddress, contracts.tellorCaller.address, {gasPrice}))

    // set CdpManager addr in SortedCdps
    console.log("set CdpManager addr in SortedCdps")
    await this.isOwnershipRenounced(contracts.sortedCdps) ||
      await this.sendAndWaitForTransaction(contracts.sortedCdps.setParams(
        maxBytes32,
        contracts.cdpManager.address,
        contracts.borrowerOperations.address, 
	{gasPrice}
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
	{gasPrice}
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
	{gasPrice}
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
	{gasPrice}
      ))
    
      console.log("set contracts in the DefaultPool")
    await this.isOwnershipRenounced(contracts.defaultPool) ||
      await this.sendAndWaitForTransaction(contracts.defaultPool.setAddresses(
        contracts.cdpManager.address,
        contracts.activePool.address,
        stEthAddress,
	{gasPrice}
      ))
    
    console.log("set contracts in the CollSurplusPool")
    await this.isOwnershipRenounced(contracts.collSurplusPool) ||
      await this.sendAndWaitForTransaction(contracts.collSurplusPool.setAddresses(
        contracts.borrowerOperations.address,
        contracts.cdpManager.address,
        contracts.activePool.address,
        stEthAddress,
	{gasPrice}
      ))

    // set contracts in HintHelpers
    console.log("set contracts in HintHelpers")
    await this.isOwnershipRenounced(contracts.hintHelpers) ||
      await this.sendAndWaitForTransaction(contracts.hintHelpers.setAddresses(
        contracts.sortedCdps.address,
        contracts.cdpManager.address,
	{gasPrice}
      ))
  }

  async connectEBTCContractsMainnet(EBTCContracts) {
    const gasPrice = this.configParams.GAS_PRICE
    // Set LQTYToken address in LCF
    console.log("Set LQTYToken address in LCF")
    const owner = await EBTCContracts.lockupContractFactory.owner()
    console.log("lockupContractFactory owner: ", owner)
    await this.isOwnershipRenounced(EBTCContracts.lockupContractFactory) ||
    await this.sendAndWaitForTransaction(EBTCContracts.lockupContractFactory.setLQTYTokenAddress(EBTCContracts.lqtyToken.address, {gasPrice}))
  }

  async connectEBTCContractsToCoreMainnet(EBTCContracts, coreContracts, configParams) {
    const gasPrice = this.configParams.GAS_PRICE
    const stEthAddress = configParams.externalAddrs.STETH_ERC20

    console.log("Set contracts in LqtyStaking")
    await this.isOwnershipRenounced(EBTCContracts.lqtyStaking) ||
      await this.sendAndWaitForTransaction(EBTCContracts.lqtyStaking.setAddresses(
        EBTCContracts.lqtyToken.address,
        coreContracts.ebtcToken.address,
        coreContracts.cdpManager.address, 
        coreContracts.borrowerOperations.address,
        coreContracts.activePool.address,
        stEthAddress,
	{gasPrice}
      ))

    console.log("Set contracts in CommunityIssuance")
    await this.isOwnershipRenounced(EBTCContracts.communityIssuance) ||
      await this.sendAndWaitForTransaction(EBTCContracts.communityIssuance.setAddresses(
        EBTCContracts.lqtyToken.address,
	{gasPrice}
      ))
  }

  async connectUnipoolMainnet(uniPool, EBTCContracts, EBTCWETHPairAddr, duration) {
    const gasPrice = this.configParams.GAS_PRICE
    await this.isOwnershipRenounced(uniPool) ||
      await this.sendAndWaitForTransaction(uniPool.setParams(EBTCContracts.lqtyToken.address, EBTCWETHPairAddr, duration, {gasPrice}))
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
      await this.hre.run("verify:verify", {
        address: deploymentState[name].address,
        constructorArguments,
      })
    } catch (error) {
      // if it was already verified, it’s like a success, so let’s move forward and save it
      if (error.name != 'NomicLabsHardhatPluginError') {
        console.error(`Error verifying: ${error.name}`)
        console.error(error)
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
