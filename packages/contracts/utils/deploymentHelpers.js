const { ethers } = require("hardhat");

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
const LiquidationLibrary = artifacts.require("./LiquidationLibrary.sol")
const EBTCDeployer = artifacts.require("./EBTCDeployer.sol")

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
    const ebtcDeployer = await EBTCDeployer.new()

    const collateral = await CollateralTokenTester.new()
    const weth9 = await WETH9.new()
    const functionCaller = await FunctionCaller.new()

    const addr = await ebtcDeployer.getFutureEbtcAddresses()

    let code, salt, args

    const customCoerceFunc = (type, value) => {
      return value;
    };

    const abiCoder = new ethers.utils.AbiCoder(customCoerceFunc);

    // Authority
    code = Governor.bytecode
    salt = await ebtcDeployer.AUTHORITY()
    args = abiCoder.encode(["address"], [accounts[0]]);

    await ebtcDeployer.deploy(salt, code + args.substring(2))
    const authority = await Governor.at(addr.authorityAddress)

    // Liquidation Library
    code = LiquidationLibrary.bytecode
    salt = await ebtcDeployer.LIQUIDATION_LIBRARY()
    args = abiCoder.encode([
      "address",
      "address",
      "address",
      "address",
      "address",
      "address",
      "address",
      "address",
      "address",
      "address"
    ], [
      addr.borrowerOperationsAddress,
      addr.gasPoolAddress,
      addr.collSurplusPoolAddress,
      addr.ebtcTokenAddress,
      addr.feeRecipientAddress,
      addr.sortedCdpsAddress,
      addr.activePoolAddress,
      addr.defaultPoolAddress,
      addr.priceFeedAddress,
      collateral.address
    ]);

    await ebtcDeployer.deploy(salt, code + args.substring(2))
    const liquidationLibrary = await LiquidationLibrary.at(addr.liquidationLibraryAddress)

    // CDP Manager
    code = CdpManager.bytecode
    salt = await ebtcDeployer.CDP_MANAGER()
    args = abiCoder.encode([
      "address",
      "address",
      "address",
      "address",
      "address",
      "address",
      "address",
      "address",
      "address",
      "address",
      "address",
      "address"
    ], [
      addr.liquidationLibraryAddress,
      addr.authorityAddress,
      addr.borrowerOperationsAddress,
      addr.gasPoolAddress,
      addr.collSurplusPoolAddress,
      addr.ebtcTokenAddress,
      addr.feeRecipientAddress,
      addr.sortedCdpsAddress,
      addr.activePoolAddress,
      addr.defaultPoolAddress,
      addr.priceFeedAddress,
      collateral.address
    ]);

    await ebtcDeployer.deploy(salt, code + args.substring(2))
    const cdpManager = await CdpManager.at(addr.cdpManagerAddress)

    // Borrower Operations
    code = BorrowerOperations.bytecode
    salt = await ebtcDeployer.BORROWER_OPERATIONS()
    args = abiCoder.encode([
      "address",
      "address",
      "address",
      "address",
      "address",
      "address",
      "address",
      "address",
      "address",
      "address"
    ], [
      addr.cdpManagerAddress,
      addr.activePoolAddress,
      addr.defaultPoolAddress,
      addr.gasPoolAddress,
      addr.collSurplusPoolAddress,
      addr.priceFeedAddress,
      addr.sortedCdpsAddress,
      addr.ebtcTokenAddress,
      addr.feeRecipientAddress,
      collateral.address
    ]);
    await ebtcDeployer.deploy(salt, code + args.substring(2))
    const borrowerOperations = await BorrowerOperations.at(addr.borrowerOperationsAddress)

    // Price Feed
    code = PriceFeedTestnet.bytecode
    salt = await ebtcDeployer.PRICE_FEED()
    args = abiCoder.encode(["address"], [addr.authorityAddress]);

    await ebtcDeployer.deploy(salt, code + args.substring(2))
    const priceFeedTestnet = await PriceFeedTestnet.at(addr.priceFeedAddress)

    // Sorted CDPs
    code = SortedCdps.bytecode
    salt = await ebtcDeployer.SORTED_CDPS()
    args = abiCoder.encode([
      "uint256",
      "address",
      "address"
    ], [
      ethers.constants.MaxUint256,
      addr.cdpManagerAddress,
      addr.borrowerOperationsAddress
    ]);

    await ebtcDeployer.deploy(salt, code + args.substring(2))
    const sortedCdps = await SortedCdps.at(addr.sortedCdpsAddress)

    // Active Pool
    code = ActivePool.bytecode
    salt = await ebtcDeployer.ACTIVE_POOL()
    args = abiCoder.encode(
      [
        "address",
        "address",
        "address",
        "address",
        "address",
        "address"
      ], [
      addr.borrowerOperationsAddress,
      addr.cdpManagerAddress,
      addr.defaultPoolAddress,
      collateral.address,
      addr.collSurplusPoolAddress,
      addr.feeRecipientAddress
    ]);

    await ebtcDeployer.deploy(salt, code + args.substring(2))
    const activePool = await ActivePool.at(addr.activePoolAddress)

    // Gas Pool
    code = GasPool.bytecode
    salt = await ebtcDeployer.GAS_POOL()

    await ebtcDeployer.deploy(salt, code)
    const gasPool = await GasPool.at(addr.gasPoolAddress)

    // Default Pool
    code = DefaultPool.bytecode
    salt = await ebtcDeployer.DEFAULT_POOL()
    args = abiCoder.encode([
      "address",
      "address",
      "address"
    ], [
      addr.cdpManagerAddress,
      addr.activePoolAddress,
      collateral.address
    ]);

    await ebtcDeployer.deploy(salt, code + args.substring(2))
    const defaultPool = await DefaultPool.at(addr.defaultPoolAddress)

    // Coll Surplus Pool
    code = CollSurplusPool.bytecode
    salt = await ebtcDeployer.COLL_SURPLUS_POOL()
    args = abiCoder.encode([
      "address",
      "address",
      "address",
      "address"
    ], [
      addr.borrowerOperationsAddress,
      addr.cdpManagerAddress,
      addr.activePoolAddress,
      collateral.address,
    ]);

    await ebtcDeployer.deploy(salt, code + args.substring(2))
    const collSurplusPool = await CollSurplusPool.at(addr.collSurplusPoolAddress)

    // Hint Helpers
    code = HintHelpers.bytecode
    salt = await ebtcDeployer.HINT_HELPERS()
    args = abiCoder.encode([
      "address",
      "address",
      "address",
      "address",
      "address",
      "address"
    ], [
      addr.sortedCdpsAddress,
      addr.cdpManagerAddress,
      collateral.address,
      addr.activePoolAddress,
      addr.defaultPoolAddress,
      addr.priceFeedAddress
    ]);

    await ebtcDeployer.deploy(salt, code + args.substring(2))
    const hintHelpers = await HintHelpers.at(addr.hintHelpersAddress)

    // eBTCToken
    code = EBTCToken.bytecode
    salt = await ebtcDeployer.EBTC_TOKEN()
    args = abiCoder.encode([
      "address",
      "address",
      "address"
    ], [
      addr.cdpManagerAddress,
      addr.borrowerOperationsAddress,
      addr.authorityAddress
    ]);

    await ebtcDeployer.deploy(salt, code + args.substring(2))
    const ebtcToken = await EBTCToken.at(addr.ebtcTokenAddress)

    // Fee Recipient
    code = FeeRecipient.bytecode
    salt = await ebtcDeployer.FEE_RECIPIENT()
    args = abiCoder.encode([
      "address",
      "address",
      "address",
      "address",
      "address"
    ], [
      addr.ebtcTokenAddress,
      addr.cdpManagerAddress,
      addr.borrowerOperationsAddress,
      addr.activePoolAddress,
      collateral.address
    ]);

    await ebtcDeployer.deploy(salt, code + args.substring(2))
    const feeRecipient = await FeeRecipient.at(addr.feeRecipientAddress)

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
    FeeRecipient.setAsDeployed(feeRecipient)

    console.log("sortedCDPS")
    console.log(borrowerOperations.address)
    console.log(addr.borrowerOperationsAddress)
    console.log(await sortedCdps.borrowerOperationsAddress())

    const coreContracts = {
      priceFeed: priceFeedTestnet,
      priceFeedTestnet: priceFeedTestnet,
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
      authority,
      liquidationLibrary,
      feeRecipient,
      collateral
    }

    await this.configureGovernor(accounts[0], coreContracts)
    return coreContracts
  }

  static async deployTesterContractsHardhat() {
    const accounts = await web3.eth.getAccounts()
    const ebtcDeployer = await EBTCDeployer.new()

    const testerContracts = {}

    testerContracts.collateral = await CollateralTokenTester.new()
    testerContracts.weth9 = await WETH9.new()
    testerContracts.functionCaller = await FunctionCaller.new()
    testerContracts.math = await LiquityMathTester.new()

    let code, salt, args

    const customCoerceFunc = (type, value) => {
      return value;
    };

    const abiCoder = new ethers.utils.AbiCoder(customCoerceFunc);

    // Authority
    code = Governor.bytecode
    salt = await ebtcDeployer.AUTHORITY()
    args = abiCoder.encode(["address"], [accounts[0]]);

    await ebtcDeployer.deploy(salt, code + args.substring(2))
    testerContracts.authority = await Governor.at(addr.authorityAddress)


    // Liquidation Library
    code = LiquidationLibrary.bytecode
    salt = await ebtcDeployer.LIQUIDATION_LIBRARY()
    args = abiCoder.encode([
      "address",
      "address",
      "address",
      "address",
      "address",
      "address",
      "address",
      "address",
      "address",
      "address"
    ], [
      addr.borrowerOperationsAddress,
      addr.gasPoolAddress,
      addr.collSurplusPoolAddress,
      addr.ebtcTokenAddress,
      addr.feeRecipientAddress,
      addr.sortedCdpsAddress,
      addr.activePoolAddress,
      addr.defaultPoolAddress,
      addr.priceFeedAddress,
      collateral.address
    ]);

    await ebtcDeployer.deploy(salt, code + args.substring(2))
    testerContracts.liquidationLibrary = await LiquidationLibrary.at(addr.liquidationLibraryAddress)

    // CDP Manager
    code = CdpManagerTester.bytecode
    salt = await ebtcDeployer.CDP_MANAGER()
    args = abiCoder.encode([
      "address",
      "address",
      "address",
      "address",
      "address",
      "address",
      "address",
      "address",
      "address",
      "address",
      "address",
      "address"
    ], [
      addr.liquidationLibraryAddress,
      addr.authorityAddress,
      addr.borrowerOperationsAddress,
      addr.gasPoolAddress,
      addr.collSurplusPoolAddress,
      addr.ebtcTokenAddress,
      addr.feeRecipientAddress,
      addr.sortedCdpsAddress,
      addr.activePoolAddress,
      addr.defaultPoolAddress,
      addr.priceFeedAddress,
      collateral.address
    ]);

    await ebtcDeployer.deploy(salt, code + args.substring(2))
    testerContracts.cdpManager = await CdpManagerTester.at(addr.cdpManagerAddress)

    // Borrower Operations
    code = BorrowerOperationsTester.bytecode
    salt = await ebtcDeployer.BORROWER_OPERATIONS()
    args = abiCoder.encode([
      "address",
      "address",
      "address",
      "address",
      "address",
      "address",
      "address",
      "address",
      "address",
      "address"
    ], [
      addr.cdpManagerAddress,
      addr.activePoolAddress,
      addr.defaultPoolAddress,
      addr.gasPoolAddress,
      addr.collSurplusPoolAddress,
      addr.priceFeedAddress,
      addr.sortedCdpsAddress,
      addr.ebtcTokenAddress,
      addr.feeRecipientAddress,
      collateral.address
    ]);
    await ebtcDeployer.deploy(salt, code + args.substring(2))
    testerContracts.borrowerOperations = await BorrowerOperationsTester.at(addr.borrowerOperationsAddress)

    // Price Feed
    code = PriceFeedTestnet.bytecode
    salt = await ebtcDeployer.PRICE_FEED()
    args = abiCoder.encode(["address"], [addr.authorityAddress]);

    await ebtcDeployer.deploy(salt, code + args.substring(2))
    testerContracts.priceFeedTestnet = await PriceFeedTestnet.at(addr.priceFeedAddress)

    // Sorted CDPs
    code = SortedCdps.bytecode
    salt = await ebtcDeployer.SORTED_CDPS()
    args = abiCoder.encode([
      "uint256",
      "address",
      "address"
    ], [
      ethers.constants.MaxUint256,
      addr.cdpManagerAddress,
      addr.borrowerOperationsAddress
    ]);

    await ebtcDeployer.deploy(salt, code + args.substring(2))
    testerContracts.sortedCdps = await SortedCdps.at(addr.sortedCdpsAddress)

    // Active Pool
    code = ActivePoolTester.bytecode
    salt = await ebtcDeployer.ACTIVE_POOL()
    args = abiCoder.encode(
      [
        "address",
        "address",
        "address",
        "address",
        "address",
        "address"
      ], [
      addr.borrowerOperationsAddress,
      addr.cdpManagerAddress,
      addr.defaultPoolAddress,
      collateral.address,
      addr.collSurplusPoolAddress,
      addr.feeRecipientAddress
    ]);

    await ebtcDeployer.deploy(salt, code + args.substring(2))
    testerContracts.activePool = await ActivePoolTester.at(addr.activePoolAddress)

    // Gas Pool
    code = GasPool.bytecode
    salt = await ebtcDeployer.GAS_POOL()

    await ebtcDeployer.deploy(salt, code)
    testerContracts.gasPool = await GasPool.at(addr.gasPoolAddress)

    // Default Pool
    code = DefaultPoolTester.bytecode
    salt = await ebtcDeployer.DEFAULT_POOL()
    args = abiCoder.encode([
      "address",
      "address",
      "address"
    ], [
      addr.cdpManagerAddress,
      addr.activePoolAddress,
      collateral.address
    ]);

    await ebtcDeployer.deploy(salt, code + args.substring(2))
    testerContracts.defaultPool = await DefaultPoolTester.at(addr.defaultPoolAddress)

    // Coll Surplus Pool
    code = CollSurplusPool.bytecode
    salt = await ebtcDeployer.COLL_SURPLUS_POOL()
    args = abiCoder.encode([
      "address",
      "address",
      "address",
      "address"
    ], [
      addr.borrowerOperationsAddress,
      addr.cdpManagerAddress,
      addr.activePoolAddress,
      collateral.address,
    ]);

    await ebtcDeployer.deploy(salt, code + args.substring(2))
    testerContracts.collSurplusPool = await CollSurplusPool.at(addr.collSurplusPoolAddress)

    // Hint Helpers
    code = HintHelpers.bytecode
    salt = await ebtcDeployer.HINT_HELPERS()
    args = abiCoder.encode([
      "address",
      "address",
      "address",
      "address",
      "address",
      "address"
    ], [
      addr.sortedCdpsAddress,
      addr.cdpManagerAddress,
      collateral.address,
      addr.activePoolAddress,
      addr.defaultPoolAddress,
      addr.priceFeedAddress
    ]);

    await ebtcDeployer.deploy(salt, code + args.substring(2))
    testerContracts.hintHelpers = await HintHelpers.at(addr.hintHelpersAddress)

    // eBTCToken
    code = EBTCTokenTester.bytecode
    salt = await ebtcDeployer.EBTC_TOKEN()
    args = abiCoder.encode([
      "address",
      "address",
      "address"
    ], [
      addr.cdpManagerAddress,
      addr.borrowerOperationsAddress,
      addr.authorityAddress
    ]);

    await ebtcDeployer.deploy(salt, code + args.substring(2))
    testerContracts.ebtcToken = await EBTCTokenTester.at(addr.ebtcTokenAddress)

    // Fee Recipient
    code = FeeRecipient.bytecode
    salt = await ebtcDeployer.FEE_RECIPIENT()
    args = abiCoder.encode([
      "address",
      "address",
      "address",
      "address",
      "address"
    ], [
      addr.ebtcTokenAddress,
      addr.cdpManagerAddress,
      addr.borrowerOperationsAddress,
      addr.activePoolAddress,
      collateral.address
    ]);

    await ebtcDeployer.deploy(salt, code + args.substring(2))
    testerContracts.feeRecipient = await FeeRecipient.at(addr.feeRecipientAddress)

    await this.configureGovernor(accounts[0], testerContracts)

    return testerContracts
  }

  // Deploy external contracts
  // TODO: Add Governance

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

  static async deployProxyScripts(contracts, owner, users) {
    const proxies = await buildUserProxies(users)

    const borrowerWrappersScript = await BorrowerWrappersScript.new(
      contracts.borrowerOperations.address,
      contracts.cdpManager.address,
      contracts.feeRecipient.address,
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

    const lqtyStakingScript = await LQTYStakingScript.new(contracts.feeRecipient.address)
    contracts.feeRecipient = new LQTYStakingProxy(owner, proxies, lqtyStakingScript.address, contracts.feeRecipient)
  }
}
module.exports = DeploymentHelper
