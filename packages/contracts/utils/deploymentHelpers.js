const SortedCdps = artifacts.require("./SortedCdps.sol")
const CdpManager = artifacts.require("./CdpManager.sol")
const PriceFeedTestnet = artifacts.require("./PriceFeedTestnet.sol")
const EBTCToken = artifacts.require("./EBTCToken.sol")
const ActivePool = artifacts.require("./ActivePool.sol");
const DefaultPool = artifacts.require("./DefaultPool.sol");
const GasPool = artifacts.require("./GasPool.sol")
const CollSurplusPool = artifacts.require("./CollSurplusPool.sol")
const FunctionCaller = artifacts.require("./TestContracts/FunctionCaller.sol")
const BorrowerOperations = artifacts.require("./BorrowerOperations.sol")
const HintHelpers = artifacts.require("./HintHelpers.sol")

const LQTYStaking = artifacts.require("./LQTYStaking.sol")
const LQTYToken = artifacts.require("./LQTYToken.sol")
const LockupContractFactory = artifacts.require("./LockupContractFactory.sol")
const CommunityIssuance = artifacts.require("./CommunityIssuance.sol")

const Unipool =  artifacts.require("./Unipool.sol")

const LQTYTokenTester = artifacts.require("./LQTYTokenTester.sol")
const CommunityIssuanceTester = artifacts.require("./CommunityIssuanceTester.sol")
const ActivePoolTester = artifacts.require("./ActivePoolTester.sol")
const DefaultPoolTester = artifacts.require("./DefaultPoolTester.sol")
const LiquityMathTester = artifacts.require("./LiquityMathTester.sol")
const BorrowerOperationsTester = artifacts.require("./BorrowerOperationsTester.sol")
const CdpManagerTester = artifacts.require("./CdpManagerTester.sol")
const EBTCTokenTester = artifacts.require("./EBTCTokenTester.sol")
const CollateralTokenTester = artifacts.require("./CollateralTokenTester.sol")

// Proxy scripts
const BorrowerOperationsScript = artifacts.require('BorrowerOperationsScript')
const BorrowerWrappersScript = artifacts.require('BorrowerWrappersScript')
const CdpManagerScript = artifacts.require('CdpManagerScript')
const TokenScript = artifacts.require('TokenScript')
const LQTYStakingScript = artifacts.require('LQTYStakingScript')
const {
  buildUserProxies,
  BorrowerOperationsProxy,
  BorrowerWrappersProxy,
  CdpManagerProxy,
  SortedCdpsProxy,
  TokenProxy,
  LQTYStakingProxy
} = require('../utils/proxyHelpers.js')

/* "Liquity core" consists of all contracts in the core Liquity system.

LQTY contracts consist of only those contracts related to the LQTY Token:

-the LQTY token
-the Lockup factory and lockup contracts
-the LQTYStaking contract
-the CommunityIssuance contract 
*/

const ZERO_ADDRESS = '0x' + '0'.repeat(40)
const maxBytes32 = '0x' + 'f'.repeat(64)

class DeploymentHelper {

  static async deployLiquityCore() {
    let blockNumber = await ethers.provider.getBlockNumber();
    let netwk = await ethers.provider.getNetwork();
    //let feeData = await ethers.provider.getFeeData();
    console.log(`blockNumber: ${blockNumber}, networkId: ${netwk.chainId}`)//, lastBaseFeePerGas: ${feeData.lastBaseFeePerGas}`)
	
    const cmdLineArgs = process.argv
    const frameworkPath = cmdLineArgs[1]
    // console.log(`Framework used:  ${frameworkPath}`)

    if (frameworkPath.includes("hardhat")) {
      return this.deployLiquityCoreHardhat()
    } else if (frameworkPath.includes("truffle")) {
      return this.deployLiquityCoreTruffle()
    }
  }

  static async deployLQTYContracts(bountyAddress, lpRewardsAddress, multisigAddress) {
    const cmdLineArgs = process.argv
    const frameworkPath = cmdLineArgs[1]
    // console.log(`Framework used:  ${frameworkPath}`)

    if (frameworkPath.includes("hardhat")) {
      return this.deployLQTYContractsHardhat(bountyAddress, lpRewardsAddress, multisigAddress)
    } else if (frameworkPath.includes("truffle")) {
      return this.deployLQTYContractsTruffle(bountyAddress, lpRewardsAddress, multisigAddress)
    }
  }

  static async deployLiquityCoreHardhat() {
    const priceFeedTestnet = await PriceFeedTestnet.new()
    const sortedCdps = await SortedCdps.new()
    const cdpManager = await CdpManager.new()
    const activePool = await ActivePool.new()
    const gasPool = await GasPool.new()
    const defaultPool = await DefaultPool.new()
    const collSurplusPool = await CollSurplusPool.new()
    const functionCaller = await FunctionCaller.new()
    const borrowerOperations = await BorrowerOperations.new()
    const hintHelpers = await HintHelpers.new()
    const ebtcToken = await EBTCToken.new(
      cdpManager.address,
      borrowerOperations.address
    )
    const collateral = await CollateralTokenTester.new()  
    EBTCToken.setAsDeployed(ebtcToken)
    DefaultPool.setAsDeployed(defaultPool)
    PriceFeedTestnet.setAsDeployed(priceFeedTestnet)
    SortedCdps.setAsDeployed(sortedCdps)
    CdpManager.setAsDeployed(cdpManager)
    ActivePool.setAsDeployed(activePool)
    GasPool.setAsDeployed(gasPool)
    CollSurplusPool.setAsDeployed(collSurplusPool)
    FunctionCaller.setAsDeployed(functionCaller)
    BorrowerOperations.setAsDeployed(borrowerOperations)
    HintHelpers.setAsDeployed(hintHelpers)
    CollateralTokenTester.setAsDeployed(collateral)

    const coreContracts = {
      priceFeedTestnet,
      ebtcToken,
      sortedCdps,
      cdpManager,
      activePool,
      gasPool,
      defaultPool,
      collSurplusPool,
      functionCaller,
      borrowerOperations,
      hintHelpers,
      collateral
    }
    return coreContracts
  }

  static async deployTesterContractsHardhat() {
    const testerContracts = {}

    // Contract without testers (yet)
    testerContracts.priceFeedTestnet = await PriceFeedTestnet.new()
    testerContracts.sortedCdps = await SortedCdps.new()
    // Actual tester contracts
    testerContracts.communityIssuance = await CommunityIssuanceTester.new()
    testerContracts.activePool = await ActivePoolTester.new()
    testerContracts.defaultPool = await DefaultPoolTester.new()
    testerContracts.gasPool = await GasPool.new()
    testerContracts.collSurplusPool = await CollSurplusPool.new()
    testerContracts.math = await LiquityMathTester.new()
    testerContracts.borrowerOperations = await BorrowerOperationsTester.new()
    testerContracts.cdpManager = await CdpManagerTester.new()
    testerContracts.functionCaller = await FunctionCaller.new()
    testerContracts.hintHelpers = await HintHelpers.new()
    testerContracts.ebtcToken =  await EBTCTokenTester.new(
      testerContracts.cdpManager.address,
      testerContracts.borrowerOperations.address
    )
    testerContracts.collateral = await CollateralTokenTester.new()
    return testerContracts
  }

  static async deployLQTYContractsHardhat(bountyAddress, lpRewardsAddress, multisigAddress) {
    const lqtyStaking = await LQTYStaking.new()
    const lockupContractFactory = await LockupContractFactory.new()
    const communityIssuance = await CommunityIssuance.new()

    LQTYStaking.setAsDeployed(lqtyStaking)
    LockupContractFactory.setAsDeployed(lockupContractFactory)
    CommunityIssuance.setAsDeployed(communityIssuance)

    // Deploy LQTY Token, passing Community Issuance and Factory addresses to the constructor 
    const lqtyToken = await LQTYToken.new(
      communityIssuance.address, 
      lqtyStaking.address,
      lockupContractFactory.address,
      bountyAddress,
      lpRewardsAddress,
      multisigAddress
    )
    LQTYToken.setAsDeployed(lqtyToken)

    const LQTYContracts = {
      lqtyStaking,
      lockupContractFactory,
      communityIssuance,
      lqtyToken
    }
    return LQTYContracts
  }

  static async deployLQTYTesterContractsHardhat(bountyAddress, lpRewardsAddress, multisigAddress) {
    const lqtyStaking = await LQTYStaking.new()
    const lockupContractFactory = await LockupContractFactory.new()
    const communityIssuance = await CommunityIssuanceTester.new()

    LQTYStaking.setAsDeployed(lqtyStaking)
    LockupContractFactory.setAsDeployed(lockupContractFactory)
    CommunityIssuanceTester.setAsDeployed(communityIssuance)

    // Deploy LQTY Token, passing Community Issuance and Factory addresses to the constructor 
    const lqtyToken = await LQTYTokenTester.new(
      communityIssuance.address, 
      lqtyStaking.address,
      lockupContractFactory.address,
      bountyAddress,
      lpRewardsAddress,
      multisigAddress
    )
    LQTYTokenTester.setAsDeployed(lqtyToken)

    const LQTYContracts = {
      lqtyStaking,
      lockupContractFactory,
      communityIssuance,
      lqtyToken
    }
    return LQTYContracts
  }

  static async deployLiquityCoreTruffle() {
    const priceFeedTestnet = await PriceFeedTestnet.new()
    const sortedCdps = await SortedCdps.new()
    const cdpManager = await CdpManager.new()
    const activePool = await ActivePool.new()
    const gasPool = await GasPool.new()
    const defaultPool = await DefaultPool.new()
    const collSurplusPool = await CollSurplusPool.new()
    const functionCaller = await FunctionCaller.new()
    const borrowerOperations = await BorrowerOperations.new()
    const hintHelpers = await HintHelpers.new()
    const ebtcToken = await EBTCToken.new(
      cdpManager.address,
      borrowerOperations.address
    )
    const collateral = await CollateralTokenTester.new()    
    const coreContracts = {
      priceFeedTestnet,
      ebtcToken,
      sortedCdps,
      cdpManager,
      activePool,
      gasPool,
      defaultPool,
      collSurplusPool,
      functionCaller,
      borrowerOperations,
      hintHelpers,
      collateral
    }
    return coreContracts
  }

  static async deployLQTYContractsTruffle(bountyAddress, lpRewardsAddress, multisigAddress) {
    const lqtyStaking = await lqtyStaking.new()
    const lockupContractFactory = await LockupContractFactory.new()
    const communityIssuance = await CommunityIssuance.new()

    /* Deploy LQTY Token, passing Community Issuance,  LQTYStaking, and Factory addresses 
    to the constructor  */
    const lqtyToken = await LQTYToken.new(
      communityIssuance.address, 
      lqtyStaking.address,
      lockupContractFactory.address,
      bountyAddress,
      lpRewardsAddress, 
      multisigAddress
    )

    const LQTYContracts = {
      lqtyStaking,
      lockupContractFactory,
      communityIssuance,
      lqtyToken
    }
    return LQTYContracts
  }

  static async deployEBTCToken(contracts) {
    contracts.ebtcToken = await EBTCToken.new(
      contracts.cdpManager.address,
      contracts.borrowerOperations.address
    )
    return contracts
  }

  static async deployEBTCTokenTester(contracts) {
    contracts.ebtcToken = await EBTCTokenTester.new(
      contracts.cdpManager.address,
      contracts.borrowerOperations.address
    )
    return contracts
  }

  static async deployProxyScripts(contracts, LQTYContracts, owner, users) {
    const proxies = await buildUserProxies(users)

    const borrowerWrappersScript = await BorrowerWrappersScript.new(
      contracts.borrowerOperations.address,
      contracts.cdpManager.address,
      LQTYContracts.lqtyStaking.address
    )
    contracts.borrowerWrappers = new BorrowerWrappersProxy(owner, proxies, borrowerWrappersScript.address)

    const borrowerOperationsScript = await BorrowerOperationsScript.new(contracts.borrowerOperations.address)
    contracts.borrowerOperations = new BorrowerOperationsProxy(owner, proxies, borrowerOperationsScript.address, contracts.borrowerOperations)

    const cdpManagerScript = await CdpManagerScript.new(contracts.cdpManager.address)
    contracts.cdpManager = new CdpManagerProxy(owner, proxies, cdpManagerScript.address, contracts.cdpManager)

    contracts.sortedCdps = new SortedCdpsProxy(owner, proxies, contracts.sortedCdps)

    const ebtcTokenScript = await TokenScript.new(contracts.ebtcToken.address)
    contracts.ebtcToken = new TokenProxy(owner, proxies, ebtcTokenScript.address, contracts.ebtcToken)

    const lqtyTokenScript = await TokenScript.new(LQTYContracts.lqtyToken.address)
    LQTYContracts.lqtyToken = new TokenProxy(owner, proxies, lqtyTokenScript.address, LQTYContracts.lqtyToken)

    const lqtyStakingScript = await LQTYStakingScript.new(LQTYContracts.lqtyStaking.address)
    LQTYContracts.lqtyStaking = new LQTYStakingProxy(owner, proxies, lqtyStakingScript.address, LQTYContracts.lqtyStaking)
  }

  // Connect contracts to their dependencies
  static async connectCoreContracts(contracts, LQTYContracts) {

    // set CdpManager addr in SortedCdps
    await contracts.sortedCdps.setParams(
      maxBytes32,
      contracts.cdpManager.address,
      contracts.borrowerOperations.address
    )

    // set contract addresses in the FunctionCaller 
    await contracts.functionCaller.setCdpManagerAddress(contracts.cdpManager.address)
    await contracts.functionCaller.setSortedCdpsAddress(contracts.sortedCdps.address)

    // set contracts in the Cdp Manager
    await contracts.cdpManager.setAddresses(
      contracts.borrowerOperations.address,
      contracts.activePool.address,
      contracts.defaultPool.address,
      contracts.gasPool.address,
      contracts.collSurplusPool.address,
      contracts.priceFeedTestnet.address,
      contracts.ebtcToken.address,
      contracts.sortedCdps.address,
      LQTYContracts.lqtyToken.address,
      LQTYContracts.lqtyStaking.address,
      contracts.collateral.address
    )

    // set contracts in BorrowerOperations 
    await contracts.borrowerOperations.setAddresses(
      contracts.cdpManager.address,
      contracts.activePool.address,
      contracts.defaultPool.address,
      contracts.gasPool.address,
      contracts.collSurplusPool.address,
      contracts.priceFeedTestnet.address,
      contracts.sortedCdps.address,
      contracts.ebtcToken.address,
      LQTYContracts.lqtyStaking.address,
      contracts.collateral.address
    )

    await contracts.activePool.setAddresses(
      contracts.borrowerOperations.address,
      contracts.cdpManager.address,
      contracts.defaultPool.address,
      contracts.collateral.address,
      contracts.collSurplusPool.address
    )

    await contracts.defaultPool.setAddresses(
      contracts.cdpManager.address,
      contracts.activePool.address,
      contracts.collateral.address
    )

    await contracts.collSurplusPool.setAddresses(
      contracts.borrowerOperations.address,
      contracts.cdpManager.address,
      contracts.activePool.address,
      contracts.collateral.address
    )

    // set contracts in HintHelpers
    await contracts.hintHelpers.setAddresses(
      contracts.sortedCdps.address,
      contracts.cdpManager.address
    )
  }

  static async connectLQTYContracts(LQTYContracts) {
    // Set LQTYToken address in LCF
    await LQTYContracts.lockupContractFactory.setLQTYTokenAddress(LQTYContracts.lqtyToken.address)
  }

  static async connectLQTYContractsToCore(LQTYContracts, coreContracts) {
    await LQTYContracts.lqtyStaking.setAddresses(
      LQTYContracts.lqtyToken.address,
      coreContracts.ebtcToken.address,
      coreContracts.cdpManager.address, 
      coreContracts.borrowerOperations.address,
      coreContracts.activePool.address
    )
  
    await LQTYContracts.communityIssuance.setAddresses(
      LQTYContracts.lqtyToken.address
    )
  }

  static async connectUnipool(uniPool, LQTYContracts, uniswapPairAddr, duration) {
    await uniPool.setParams(LQTYContracts.lqtyToken.address, uniswapPairAddr, duration)
  }
}
module.exports = DeploymentHelper
