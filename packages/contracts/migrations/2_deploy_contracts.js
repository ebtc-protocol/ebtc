// Truffle migration script for deployment to Ganache

const SortedCdps = artifacts.require("./SortedCdps.sol")
const ActivePool = artifacts.require("./ActivePool.sol")
const DefaultPool = artifacts.require("./DefaultPool.sol")
const StabilityPool = artifacts.require("./StabilityPool.sol")
const CdpManager = artifacts.require("./CdpManager.sol")
const PriceFeed = artifacts.require("./PriceFeed.sol")
const EBTCToken = artifacts.require("./EBTCToken.sol")
const FunctionCaller = artifacts.require("./FunctionCaller.sol")
const BorrowerOperations = artifacts.require("./BorrowerOperations.sol")

const deploymentHelpers = require("../utils/truffleDeploymentHelpers.js")

const getAddresses = deploymentHelpers.getAddresses
const connectContracts = deploymentHelpers.connectContracts

module.exports = function(deployer) {
  deployer.deploy(BorrowerOperations)
  deployer.deploy(PriceFeed)
  deployer.deploy(SortedCdps)
  deployer.deploy(CdpManager)
  deployer.deploy(ActivePool)
  deployer.deploy(StabilityPool)
  deployer.deploy(DefaultPool)
  deployer.deploy(EBTCToken)
  deployer.deploy(FunctionCaller)

  deployer.then(async () => {
    const borrowerOperations = await BorrowerOperations.deployed()
    const priceFeed = await PriceFeed.deployed()
    const sortedCdps = await SortedCdps.deployed()
    const cdpManager = await CdpManager.deployed()
    const activePool = await ActivePool.deployed()
    const stabilityPool = await StabilityPool.deployed()
    const defaultPool = await DefaultPool.deployed()
    const ebtcToken = await EBTCToken.deployed()
    const functionCaller = await FunctionCaller.deployed()

    const liquityContracts = {
      borrowerOperations,
      priceFeed,
      ebtcToken,
      sortedCdps,
      cdpManager,
      activePool,
      stabilityPool,
      defaultPool,
      functionCaller
    }

    // Grab contract addresses
    const liquityAddresses = getAddresses(liquityContracts)
    console.log('deploy_contracts.js - Deployed contract addresses: \n')
    console.log(liquityAddresses)
    console.log('\n')

    // Connect contracts to each other
    await connectContracts(liquityContracts, liquityAddresses)
  })
}
