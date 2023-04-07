const SortedCdps = artifacts.require("./SortedCdps.sol")
const CdpManager = artifacts.require("./CdpManager.sol")
const PriceFeedTestnet = artifacts.require("./PriceFeedTestnet.sol")
const EBTCToken = artifacts.require("./EBTCToken.sol")
const WETH9 = artifacts.require("./WETH9.sol")
const ActivePool = artifacts.require("./ActivePool.sol");
const DefaultPool = artifacts.require("./DefaultPool.sol");
const GasPool = artifacts.require("./GasPool.sol")
const CollSurplusPool = artifacts.require("./CollSurplusPool.sol")
const FunctionCaller = artifacts.require("./TestContracts/FunctionCaller.sol")
const BorrowerOperations = artifacts.require("./BorrowerOperations.sol")
const HintHelpers = artifacts.require("./HintHelpers.sol")
const Governor = artifacts.require("./Governor.sol")

const FeeRecipient = artifacts.require("./FeeRecipient.sol")

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

-the FeeRecipient contract
*/

const ZERO_ADDRESS = '0x' + '0'.repeat(40)
const maxBytes32 = '0x' + 'f'.repeat(64)
const dummyRoleHash = "0xb41779a0"

const MINT_SIG = dummyRoleHash
const BURN_SIG = dummyRoleHash
const SET_STAKING_REWARD_SPLIT_SIG = dummyRoleHash

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
      return this.deployExternalContractsHardhat(bountyAddress, lpRewardsAddress, multisigAddress)
    } else if (frameworkPath.includes("truffle")) {
      return this.deployExternalContractsTruffle(bountyAddress, lpRewardsAddress, multisigAddress)
    }
  }

  static async configureGovernor(defaultGovernance, coreContracts) {
    const authority = coreContracts.authority;

    await authority.setRoleName(0, "Admin");
    await authority.setRoleName(1, "eBTCToken: mint");
    await authority.setRoleName(2, "eBTCToken: burn");
    await authority.setRoleName(3, "CDPManager: setStakingRewardSplit");

    await authority.setRoleCapability(1, coreContracts.ebtcToken.address, MINT_SIG, true);
    await authority.setRoleCapability(2, coreContracts.ebtcToken.address, BURN_SIG, true);
    await authority.setRoleCapability(3, coreContracts.cdpManager.address, SET_STAKING_REWARD_SPLIT_SIG, true);

    await authority.setUserRole(defaultGovernance, 0, true);
    await authority.setUserRole(defaultGovernance, 1, true);
    await authority.setUserRole(defaultGovernance, 2, true);
    await authority.setUserRole(defaultGovernance, 3, true);
  }

  static async deployLiquityCoreHardhat() {
    const accounts = await web3.eth.getAccounts()
    const authority = await Governor.new(accounts[0])

    const priceFeedTestnet = await PriceFeedTestnet.new()
    const sortedCdps = await SortedCdps.new()
    const cdpManager = await CdpManager.new()
    const weth9 = await WETH9.new()
    const activePool = await ActivePool.new()
    const gasPool = await GasPool.new()
    const defaultPool = await DefaultPool.new()
    const collSurplusPool = await CollSurplusPool.new()
    const functionCaller = await FunctionCaller.new()
    const borrowerOperations = await BorrowerOperations.new()
    const hintHelpers = await HintHelpers.new()
    const ebtcToken = await EBTCToken.new(
      cdpManager.address,
      borrowerOperations.address,
      authority.address
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
    Governor.setAsDeployed(authority)

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
      collateral,
      authority
    }

    await this.configureGovernor(accounts[0], coreContracts)
    return coreContracts
  }

  static async deployTesterContractsHardhat() {
    const accounts = await web3.eth.getAccounts()
    const testerContracts = {}

    // Contract without testers (yet)
    testerContracts.priceFeedTestnet = await PriceFeedTestnet.new()
    testerContracts.sortedCdps = await SortedCdps.new()
    testerContracts.authority = await Governor.new(accounts[0])
    // Actual tester contracts
    testerContracts.weth = await WETH9.new()
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
      testerContracts.borrowerOperations.address,
      testerContracts.authority.address
    )
    testerContracts.collateral = await CollateralTokenTester.new()
    return testerContracts
  }

  // Deploy external contracts
  // TODO: Add Governance
  static async deployExternalContractsHardhat(bountyAddress, lpRewardsAddress, multisigAddress) {
    const feeRecipient = await FeeRecipient.new()

    FeeRecipient.setAsDeployed(feeRecipient)

    const LQTYContracts = {
      feeRecipient
    }
    return LQTYContracts
  }

  static async deployLiquityCoreTruffle() {
    const priceFeedTestnet = await PriceFeedTestnet.new()
    const sortedCdps = await SortedCdps.new()
    const cdpManager = await CdpManager.new()
    const weth9 = await WETH9.new()
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

  static async deployExternalContractsTruffle(bountyAddress, lpRewardsAddress, multisigAddress) {
    const feeRecipient = await feeRecipient.new()

    const LQTYContracts = {
      feeRecipient
    }
    return LQTYContracts
  }

  static async deployEBTCToken(contracts) {
    contracts.ebtcToken = await EBTCToken.new(
      contracts.cdpManager.address,
      contracts.borrowerOperations.address,
      contracts.authority.address,
    )
    return contracts
  }

  static async deployEBTCTokenTester(contracts) {
    contracts.ebtcToken = await EBTCTokenTester.new(
      contracts.cdpManager.address,
      contracts.borrowerOperations.address,
      contracts.authority.address
    )
    return contracts
  }

  static async deployProxyScripts(contracts, LQTYContracts, owner, users) {
    const proxies = await buildUserProxies(users)

    const borrowerWrappersScript = await BorrowerWrappersScript.new(
      contracts.borrowerOperations.address,
      contracts.cdpManager.address,
      LQTYContracts.feeRecipient.address,
      contracts.collateral.address
    )
    contracts.borrowerWrappers = new BorrowerWrappersProxy(owner, proxies, borrowerWrappersScript.address)

    const borrowerOperationsScript = await BorrowerOperationsScript.new(contracts.borrowerOperations.address)
    contracts.borrowerOperations = new BorrowerOperationsProxy(owner, proxies, borrowerOperationsScript.address, contracts.borrowerOperations)

    const cdpManagerScript = await CdpManagerScript.new(contracts.cdpManager.address)
    contracts.cdpManager = new CdpManagerProxy(owner, proxies, cdpManagerScript.address, contracts.cdpManager)

    contracts.sortedCdps = new SortedCdpsProxy(owner, proxies, contracts.sortedCdps)

    const ebtcTokenScript = await TokenScript.new(contracts.ebtcToken.address)
    contracts.ebtcToken = new TokenProxy(owner, proxies, ebtcTokenScript.address, contracts.ebtcToken)

    const lqtyStakingScript = await LQTYStakingScript.new(LQTYContracts.feeRecipient.address)
    LQTYContracts.feeRecipient = new LQTYStakingProxy(owner, proxies, lqtyStakingScript.address, LQTYContracts.feeRecipient)
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
      LQTYContracts.feeRecipient.address,
      contracts.collateral.address,
      contracts.authority.address
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
      LQTYContracts.feeRecipient.address,
      contracts.collateral.address
    )

    await contracts.activePool.setAddresses(
      contracts.borrowerOperations.address,
      contracts.cdpManager.address,
      contracts.defaultPool.address,
      contracts.collateral.address,
      contracts.collSurplusPool.address,
      LQTYContracts.feeRecipient.address
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
      contracts.cdpManager.address,
      contracts.collateral.address
    )
  }

  static async connectLQTYContractsToCore(LQTYContracts, coreContracts) {
    await LQTYContracts.feeRecipient.setAddresses(
      coreContracts.ebtcToken.address,
      coreContracts.cdpManager.address, 
      coreContracts.borrowerOperations.address,
      coreContracts.activePool.address,
      coreContracts.collateral.address
    )
  }

  static async connectUnipool(uniPool, LQTYContracts, uniswapPairAddr, duration) {
    await uniPool.setParams(LQTYContracts.lqtyToken.address, uniswapPairAddr, duration)
  }
}
module.exports = DeploymentHelper
