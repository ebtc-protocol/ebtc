
const SortedCdps = artifacts.require("./SortedCdps.sol")
const CdpManager = artifacts.require("./CdpManager.sol")
const PriceFeedTestnet = artifacts.require("./PriceFeedTestnet.sol")
const EBTCToken = artifacts.require("./EBTCToken.sol")
const ActivePool = artifacts.require("./ActivePool.sol");
const DefaultPool = artifacts.require("./DefaultPool.sol");
const StabilityPool = artifacts.require("./StabilityPool.sol")
const FunctionCaller = artifacts.require("./FunctionCaller.sol")
const BorrowerOperations = artifacts.require("./BorrowerOperations.sol")

const deployLiquity = async () => {
  const priceFeedTestnet = await PriceFeedTestnet.new()
  const sortedCdps = await SortedCdps.new()
  const cdpManager = await CdpManager.new()
  const activePool = await ActivePool.new()
  const stabilityPool = await StabilityPool.new()
  const defaultPool = await DefaultPool.new()
  const functionCaller = await FunctionCaller.new()
  const borrowerOperations = await BorrowerOperations.new()
  const ebtcToken = await EBTCToken.new(
    cdpManager.address,
    stabilityPool.address,
    borrowerOperations.address
  )
  DefaultPool.setAsDeployed(defaultPool)
  PriceFeedTestnet.setAsDeployed(priceFeedTestnet)
  EBTCToken.setAsDeployed(ebtcToken)
  SortedCdps.setAsDeployed(sortedCdps)
  CdpManager.setAsDeployed(cdpManager)
  ActivePool.setAsDeployed(activePool)
  StabilityPool.setAsDeployed(stabilityPool)
  FunctionCaller.setAsDeployed(functionCaller)
  BorrowerOperations.setAsDeployed(borrowerOperations)

  const contracts = {
    priceFeedTestnet,
    ebtcToken,
    sortedCdps,
    cdpManager,
    activePool,
    stabilityPool,
    defaultPool,
    functionCaller,
    borrowerOperations
  }
  return contracts
}

const getAddresses = (contracts) => {
  return {
    BorrowerOperations: contracts.borrowerOperations.address,
    PriceFeedTestnet: contracts.priceFeedTestnet.address,
    EBTCToken: contracts.ebtcToken.address,
    SortedCdps: contracts.sortedCdps.address,
    CdpManager: contracts.cdpManager.address,
    StabilityPool: contracts.stabilityPool.address,
    ActivePool: contracts.activePool.address,
    DefaultPool: contracts.defaultPool.address,
    FunctionCaller: contracts.functionCaller.address
  }
}

// Connect contracts to their dependencies
const connectContracts = async (contracts, addresses) => {
  // set CdpManager addr in SortedCdps
  await contracts.sortedCdps.setCdpManager(addresses.CdpManager)

  // set contract addresses in the FunctionCaller 
  await contracts.functionCaller.setCdpManagerAddress(addresses.CdpManager)
  await contracts.functionCaller.setSortedCdpsAddress(addresses.SortedCdps)

  // set CdpManager addr in PriceFeed
  await contracts.priceFeedTestnet.setCdpManagerAddress(addresses.CdpManager)

  // set contracts in the Cdp Manager
  await contracts.cdpManager.setEBTCToken(addresses.EBTCToken)
  await contracts.cdpManager.setSortedCdps(addresses.SortedCdps)
  await contracts.cdpManager.setPriceFeed(addresses.PriceFeedTestnet)
  await contracts.cdpManager.setActivePool(addresses.ActivePool)
  await contracts.cdpManager.setDefaultPool(addresses.DefaultPool)
  await contracts.cdpManager.setStabilityPool(addresses.StabilityPool)
  await contracts.cdpManager.setBorrowerOperations(addresses.BorrowerOperations)

  // set contracts in BorrowerOperations 
  await contracts.borrowerOperations.setSortedCdps(addresses.SortedCdps)
  await contracts.borrowerOperations.setPriceFeed(addresses.PriceFeedTestnet)
  await contracts.borrowerOperations.setActivePool(addresses.ActivePool)
  await contracts.borrowerOperations.setDefaultPool(addresses.DefaultPool)
  await contracts.borrowerOperations.setCdpManager(addresses.CdpManager)

  // set contracts in the Pools
  await contracts.stabilityPool.setActivePoolAddress(addresses.ActivePool)
  await contracts.stabilityPool.setDefaultPoolAddress(addresses.DefaultPool)

  await contracts.activePool.setStabilityPoolAddress(addresses.StabilityPool)
  await contracts.activePool.setDefaultPoolAddress(addresses.DefaultPool)

  await contracts.defaultPool.setStabilityPoolAddress(addresses.StabilityPool)
  await contracts.defaultPool.setActivePoolAddress(addresses.ActivePool)
}

const connectEchidnaProxy = async (echidnaProxy, addresses) => {
  echidnaProxy.setCdpManager(addresses.CdpManager)
  echidnaProxy.setBorrowerOperations(addresses.BorrowerOperations)
}

module.exports = {
  connectEchidnaProxy: connectEchidnaProxy,
  getAddresses: getAddresses,
  deployLiquity: deployLiquity,
  connectContracts: connectContracts
}
