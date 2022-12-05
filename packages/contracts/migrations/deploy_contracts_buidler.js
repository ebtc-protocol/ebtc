// Buidler-Truffle fixture for deployment to Buidler EVM

const SortedCdps = artifacts.require("./SortedCdps.sol")
const ActivePool = artifacts.require("./ActivePool.sol")
const DefaultPool = artifacts.require("./DefaultPool.sol")
const StabilityPool = artifacts.require("./StabilityPool.sol")
const CdpManager = artifacts.require("./CdpManager.sol")
const PriceFeed = artifacts.require("./PriceFeed.sol")
const EBTCToken = artifacts.require("./EBTCToken.sol")
const FunctionCaller = artifacts.require("./FunctionCaller.sol")
const BorrowerOperations = artifacts.require("./BorrowerOperations.sol")

const deploymentHelpers = require("../utils/deploymentHelpers.js")

const getAddresses = deploymentHelpers.getAddresses
const connectContracts = deploymentHelpers.connectContracts

module.exports = async () => {
  const borrowerOperations = await BorrowerOperations.new()
  const priceFeed = await PriceFeed.new()
  const sortedCdps = await SortedCdps.new()
  const cdpManager = await CdpManager.new()
  const activePool = await ActivePool.new()
  const stabilityPool = await StabilityPool.new()
  const defaultPool = await DefaultPool.new()
  const functionCaller = await FunctionCaller.new()
  const ebtcToken = await EBTCToken.new(
    cdpManager.address,
    stabilityPool.address,
    borrowerOperations.address
  )
  BorrowerOperations.setAsDeployed(borrowerOperations)
  PriceFeed.setAsDeployed(priceFeed)
  SortedCdps.setAsDeployed(sortedCdps)
  CdpManager.setAsDeployed(cdpManager)
  ActivePool.setAsDeployed(activePool)
  StabilityPool.setAsDeployed(stabilityPool)
  DefaultPool.setAsDeployed(defaultPool)
  FunctionCaller.setAsDeployed(functionCaller)
  EBTCToken.setAsDeployed(ebtcToken)

  const contracts = {
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
  const addresses = getAddresses(contracts)
  console.log('deploy_contracts.js - Deployhed contract addresses: \n')
  console.log(addresses)
  console.log('\n')

  // Connect contracts to each other via the NameRegistry records
  await connectContracts(contracts, addresses)
}
