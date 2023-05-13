const { ethers } = require("hardhat");

const SortedCdps = artifacts.require("./SortedCdps.sol")
const CdpManager = artifacts.require("./CdpManager.sol")
const PriceFeedTestnet = artifacts.require("./PriceFeedTestnet.sol")
const EBTCToken = artifacts.require("./EBTCToken.sol")
const WETH9 = artifacts.require("./WETH9.sol")
const ActivePool = artifacts.require("./ActivePool.sol");
const CollSurplusPool = artifacts.require("./CollSurplusPool.sol")
const FunctionCaller = artifacts.require("./TestContracts/FunctionCaller.sol")
const BorrowerOperations = artifacts.require("./BorrowerOperations.sol")
const HintHelpers = artifacts.require("./HintHelpers.sol")
const Governor = artifacts.require("./Governor.sol")
const LiquidationLibrary = artifacts.require("./LiquidationLibrary.sol")

const FeeRecipient = artifacts.require("./FeeRecipient.sol")
const EBTCDeployer = artifacts.require("./EBTCDeployerTester.sol")

const ActivePoolTester = artifacts.require("./ActivePoolTester.sol")
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
    } else {
      console.log("invalid framework path:" + frameworkPath);
      return;
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

  static async deployViaCreate3(ebtcDeployer, _argTypes, _argValues, _code, _salt) {
    let _deployTx;
    if (_argTypes.length > 0 && _argValues.length > 0) {
      let _arg = web3.eth.abi.encodeParameters(_argTypes, _argValues);
      _deployTx = await ebtcDeployer.deployWithCreationCodeAndConstructorArgs(_salt, _code, _arg);
    } else {
      _deployTx = await ebtcDeployer.deployWithCreationCode(_salt, _code);
    }

    let _deployedAddr;
    for (let i = 0; i < _deployTx.logs.length; i++) {
      if (_deployTx.logs[i].event === "ContractDeployed") {
        _deployedAddr = _deployTx.logs[i].args[0]
        break;
      }
    }
    //console.log(_salt + '_deployedAddr=' + _deployedAddr);
    return _deployedAddr;
  }

  static async deployLiquityCoreHardhat() {
    const accounts = await web3.eth.getAccounts()

    const ebtcDeployer = await EBTCDeployer.new();
    let _addresses = await ebtcDeployer.getFutureEbtcAddresses();

    const collateral = await CollateralTokenTester.new();
    const functionCaller = await FunctionCaller.new();

    // deploy Governor as Authority 
    let _argTypes = ['address'];
    let _argValues = [accounts[0]];
    let _code = await ebtcDeployer.authority_creationCode();
    let _salt = await ebtcDeployer.AUTHORITY();
    let _deployedAddr = await this.deployViaCreate3(ebtcDeployer, _argTypes, _argValues, _code, _salt);
    assert.isTrue(_deployedAddr == _addresses[0]);
    const authority = await Governor.at(_deployedAddr);

    // deploy LiquidationLibrary 
    _argTypes = ['address', 'address', 'address', 'address', 'address', 'address', 'address', 'address'];
    _argValues = [_addresses[3], _addresses[7], _addresses[9], _addresses[10], _addresses[5], _addresses[6], _addresses[4], collateral.address];
    _code = await ebtcDeployer.liquidationLibrary_creationCode();
    _salt = await ebtcDeployer.LIQUIDATION_LIBRARY();
    _deployedAddr = await this.deployViaCreate3(ebtcDeployer, _argTypes, _argValues, _code, _salt);
    assert.isTrue(_deployedAddr == _addresses[1]);
    const liquidationLibrary = await LiquidationLibrary.at(_deployedAddr);

    // deploy CdpManager 
    _argTypes = [{ 'EbtcAddresses': { 'a1': 'address', 'a2': 'address', 'a3': 'address', 'a4': 'address', 'a5': 'address', 'a6': 'address', 'a7': 'address', 'a8': 'address', 'a9': 'address', 'a10': 'address', 'a11': 'address', 'a12': 'address' } }, 'address'];
    _argValues = [{ 'a1': _addresses[0], 'a2': _addresses[1], 'a3': _addresses[2], 'a4': _addresses[3], 'a5': _addresses[4], 'a6': _addresses[5], 'a7': _addresses[6], 'a8': _addresses[7], 'a9': _addresses[8], 'a10': _addresses[9], 'a11': _addresses[10], 'a12': _addresses[11] }, collateral.address];
    _code = await ebtcDeployer.cdpManager_creationCode();
    _salt = await ebtcDeployer.CDP_MANAGER();
    _deployedAddr = await this.deployViaCreate3(ebtcDeployer, _argTypes, _argValues, _code, _salt);
    assert.isTrue(_deployedAddr == _addresses[2]);
    const cdpManager = await CdpManager.at(_deployedAddr);

    // deploy BorrowOperations 
    _argTypes = ['address', 'address', 'address', 'address', 'address', 'address', 'address', 'address'];
    _argValues = [_addresses[2], _addresses[6], _addresses[7], _addresses[4], _addresses[5], _addresses[9], _addresses[10], collateral.address];
    _code = await ebtcDeployer.borrowerOperations_creationCode();
    _salt = await ebtcDeployer.BORROWER_OPERATIONS();
    _deployedAddr = await this.deployViaCreate3(ebtcDeployer, _argTypes, _argValues, _code, _salt);
    assert.isTrue(_deployedAddr == _addresses[3]);
    const borrowerOperations = await BorrowerOperations.at(_deployedAddr);

    // deploy PriceFeedTestnet 
    _argTypes = ['address'];
    _argValues = [_addresses[0]];
    _code = await ebtcDeployer.priceFeedTestnet_creationCode();
    _salt = await ebtcDeployer.PRICE_FEED();
    _deployedAddr = await this.deployViaCreate3(ebtcDeployer, _argTypes, _argValues, _code, _salt);
    assert.isTrue(_deployedAddr == _addresses[4]);
    const priceFeedTestnet = await PriceFeedTestnet.at(_deployedAddr);

    // deploy SortedCdps 
    _argTypes = ['uint256', 'address', 'address'];
    _argValues = [0, _addresses[2], _addresses[3]];
    _code = await ebtcDeployer.sortedCdps_creationCode();
    _salt = await ebtcDeployer.SORTED_CDPS();
    _deployedAddr = await this.deployViaCreate3(ebtcDeployer, _argTypes, _argValues, _code, _salt);
    assert.isTrue(_deployedAddr == _addresses[5]);
    const sortedCdps = await SortedCdps.at(_deployedAddr);

    // deploy ActivePool 
    _argTypes = ['address', 'address', 'address', 'address', 'address'];
    _argValues = [_addresses[3], _addresses[2], collateral.address, _addresses[7], _addresses[10]];
    _code = await ebtcDeployer.activePool_creationCode();
    _salt = await ebtcDeployer.ACTIVE_POOL();
    _deployedAddr = await this.deployViaCreate3(ebtcDeployer, _argTypes, _argValues, _code, _salt);
    assert.isTrue(_deployedAddr == _addresses[6]);
    const activePool = await ActivePool.at(_deployedAddr);

    // deploy CollSurplusPool 
    _argTypes = ['address', 'address', 'address', 'address'];
    _argValues = [_addresses[3], _addresses[2], _addresses[6], collateral.address];
    _code = await ebtcDeployer.collSurplusPool_creationCode();
    _salt = await ebtcDeployer.COLL_SURPLUS_POOL();
    _deployedAddr = await this.deployViaCreate3(ebtcDeployer, _argTypes, _argValues, _code, _salt);
    assert.isTrue(_deployedAddr == _addresses[7]);
    const collSurplusPool = await CollSurplusPool.at(_deployedAddr);

    // deploy HintHelper 
    _argTypes = ['address', 'address', 'address', 'address', 'address'];
    _argValues = [_addresses[5], _addresses[2], collateral.address, _addresses[6], _addresses[4]];
    _code = await ebtcDeployer.hintHelpers_creationCode();
    _salt = await ebtcDeployer.HINT_HELPERS();
    _deployedAddr = await this.deployViaCreate3(ebtcDeployer, _argTypes, _argValues, _code, _salt);
    assert.isTrue(_deployedAddr == _addresses[8]);
    const hintHelpers = await HintHelpers.at(_deployedAddr);

    // deploy EBTCToken 
    _argTypes = ['address', 'address', 'address'];
    _argValues = [_addresses[2], _addresses[3], _addresses[0]];
    _code = await ebtcDeployer.ebtcToken_creationCode();
    _salt = await ebtcDeployer.EBTC_TOKEN();
    _deployedAddr = await this.deployViaCreate3(ebtcDeployer, _argTypes, _argValues, _code, _salt);
    assert.isTrue(_deployedAddr == _addresses[9]);
    const ebtcToken = await EBTCToken.at(_deployedAddr);

    // deploy FeeRecipient 
    _argTypes = ['address', 'address', 'address', 'address', 'address'];
    _argValues = [_addresses[9], _addresses[2], _addresses[3], _addresses[6], collateral.address];
    _code = await ebtcDeployer.feeRecipient_creationCode();
    _salt = await ebtcDeployer.FEE_RECIPIENT();
    _deployedAddr = await this.deployViaCreate3(ebtcDeployer, _argTypes, _argValues, _code, _salt);
    assert.isTrue(_deployedAddr == _addresses[10]);
    const feeRecipient = await FeeRecipient.at(_deployedAddr);

    // truffle migrations
    EBTCToken.setAsDeployed(ebtcToken)
    PriceFeedTestnet.setAsDeployed(priceFeedTestnet)
    SortedCdps.setAsDeployed(sortedCdps)
    CdpManager.setAsDeployed(cdpManager)
    ActivePool.setAsDeployed(activePool)
    FeeRecipient.setAsDeployed(feeRecipient)
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

    const ebtcDeployer = await EBTCDeployer.new();
    let _addresses = await ebtcDeployer.getFutureEbtcAddresses();

    const collateral = await CollateralTokenTester.new();

    const testerContracts = {}
    testerContracts.weth = await WETH9.new()
    testerContracts.functionCaller = await FunctionCaller.new();
    testerContracts.collateral = collateral;
    testerContracts.math = await LiquityMathTester.new()

    // deploy Governor as Authority 
    let _argTypes = ['address'];
    let _argValues = [accounts[0]];
    let _code = await ebtcDeployer.authority_creationCode();
    let _salt = await ebtcDeployer.AUTHORITY();
    let _deployedAddr = await this.deployViaCreate3(ebtcDeployer, _argTypes, _argValues, _code, _salt);
    assert.isTrue(_deployedAddr == _addresses[0]);
    const authority = await Governor.at(_deployedAddr);

    // deploy LiquidationLibrary 
    _argTypes = ['address', 'address', 'address', 'address', 'address', 'address', 'address', 'address'];
    _argValues = [_addresses[3], _addresses[7], _addresses[9], _addresses[10], _addresses[5], _addresses[6], _addresses[4], collateral.address];
    _code = await ebtcDeployer.liquidationLibrary_creationCode();
    _salt = await ebtcDeployer.LIQUIDATION_LIBRARY();
    _deployedAddr = await this.deployViaCreate3(ebtcDeployer, _argTypes, _argValues, _code, _salt);
    assert.isTrue(_deployedAddr == _addresses[1]);
    const liquidationLibrary = await LiquidationLibrary.at(_deployedAddr);

    // deploy CdpManagerTester
    _argTypes = ['address', 'address', 'address', 'address', 'address', 'address', 'address', 'address', 'address'];
    _argValues = [_addresses[1], _addresses[0], _addresses[3], _addresses[7], _addresses[9], _addresses[5], _addresses[6], _addresses[4], collateral.address];
    _code = await ebtcDeployer.cdpManagerTester_creationCode();
    _salt = await ebtcDeployer.CDP_MANAGER();
    _deployedAddr = await this.deployViaCreate3(ebtcDeployer, _argTypes, _argValues, _code, _salt);
    assert.isTrue(_deployedAddr == _addresses[2]);
    const cdpManager = await CdpManagerTester.at(_deployedAddr);

    // deploy BorrowOperationsTester
    _argTypes = ['address', 'address', 'address', 'address', 'address', 'address', 'address', 'address'];
    _argValues = [_addresses[2], _addresses[6], _addresses[7], _addresses[4], _addresses[5], _addresses[9], _addresses[10], collateral.address];
    _code = await ebtcDeployer.borrowerOperationsTester_creationCode();
    _salt = await ebtcDeployer.BORROWER_OPERATIONS();
    _deployedAddr = await this.deployViaCreate3(ebtcDeployer, _argTypes, _argValues, _code, _salt);
    assert.isTrue(_deployedAddr == _addresses[3]);
    const borrowerOperations = await BorrowerOperationsTester.at(_deployedAddr);

    // deploy PriceFeedTestnet 
    _argTypes = ['address'];
    _argValues = [_addresses[0]];
    _code = await ebtcDeployer.priceFeedTestnet_creationCode();
    _salt = await ebtcDeployer.PRICE_FEED();
    _deployedAddr = await this.deployViaCreate3(ebtcDeployer, _argTypes, _argValues, _code, _salt);
    assert.isTrue(_deployedAddr == _addresses[4]);
    const priceFeedTestnet = await PriceFeedTestnet.at(_deployedAddr);

    // deploy SortedCdps 
    _argTypes = ['uint256', 'address', 'address'];
    _argValues = [0, _addresses[2], _addresses[3]];
    _code = await ebtcDeployer.sortedCdps_creationCode();
    _salt = await ebtcDeployer.SORTED_CDPS();
    _deployedAddr = await this.deployViaCreate3(ebtcDeployer, _argTypes, _argValues, _code, _salt);
    assert.isTrue(_deployedAddr == _addresses[5]);
    const sortedCdps = await SortedCdps.at(_deployedAddr);

    // deploy ActivePoolTester
    _argTypes = ['address', 'address', 'address', 'address', 'address'];
    _argValues = [_addresses[3], _addresses[2], collateral.address, _addresses[7], _addresses[10]];
    _code = await ebtcDeployer.activePoolTester_creationCode();
    _salt = await ebtcDeployer.ACTIVE_POOL();
    _deployedAddr = await this.deployViaCreate3(ebtcDeployer, _argTypes, _argValues, _code, _salt);
    assert.isTrue(_deployedAddr == _addresses[6]);
    const activePool = await ActivePoolTester.at(_deployedAddr);

    // deploy CollSurplusPool 
    _argTypes = ['address', 'address', 'address', 'address'];
    _argValues = [_addresses[3], _addresses[2], _addresses[6], collateral.address];
    _code = await ebtcDeployer.collSurplusPool_creationCode();
    _salt = await ebtcDeployer.COLL_SURPLUS_POOL();
    _deployedAddr = await this.deployViaCreate3(ebtcDeployer, _argTypes, _argValues, _code, _salt);
    assert.isTrue(_deployedAddr == _addresses[7]);
    const collSurplusPool = await CollSurplusPool.at(_deployedAddr);

    // deploy HintHelper 
    _argTypes = ['address', 'address', 'address', 'address', 'address'];
    _argValues = [_addresses[5], _addresses[2], collateral.address, _addresses[6], _addresses[4]];
    _code = await ebtcDeployer.hintHelpers_creationCode();
    _salt = await ebtcDeployer.HINT_HELPERS();
    _deployedAddr = await this.deployViaCreate3(ebtcDeployer, _argTypes, _argValues, _code, _salt);
    assert.isTrue(_deployedAddr == _addresses[8]);
    const hintHelpers = await HintHelpers.at(_deployedAddr);

    // deploy EBTCTokenTester 
    _argTypes = ['address', 'address', 'address'];
    _argValues = [_addresses[2], _addresses[3], _addresses[0]];
    _code = await ebtcDeployer.ebtcTokenTester_creationCode();
    _salt = await ebtcDeployer.EBTC_TOKEN();
    _deployedAddr = await this.deployViaCreate3(ebtcDeployer, _argTypes, _argValues, _code, _salt);
    assert.isTrue(_deployedAddr == _addresses[9]);
    const ebtcToken = await EBTCTokenTester.at(_deployedAddr);

    // deploy FeeRecipient 
    _argTypes = ['address', 'address'];
    _argValues = [accounts[0], _addresses[1]];
    _code = await ebtcDeployer.feeRecipient_creationCode();
    _salt = await ebtcDeployer.FEE_RECIPIENT();
    _deployedAddr = await this.deployViaCreate3(ebtcDeployer, _argTypes, _argValues, _code, _salt);
    assert.isTrue(_deployedAddr == _addresses[10]);
    const feeRecipient = await FeeRecipient.at(_deployedAddr);

    // Contract without testers
    testerContracts.authority = authority
    testerContracts.liquidationLibrary = liquidationLibrary
    testerContracts.priceFeedTestnet = priceFeedTestnet
    testerContracts.sortedCdps = sortedCdps
    testerContracts.collSurplusPool = collSurplusPool
    testerContracts.hintHelpers = hintHelpers
    testerContracts.feeRecipient = feeRecipient

    // Actual tester contracts
    testerContracts.cdpManager = cdpManager
    testerContracts.borrowerOperations = borrowerOperations
    testerContracts.activePool = activePool
    testerContracts.ebtcToken = ebtcToken

    return testerContracts
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

    // set contract addresses in the FunctionCaller 
    await contracts.functionCaller.setCdpManagerAddress(contracts.cdpManager.address)
    await contracts.functionCaller.setSortedCdpsAddress(contracts.sortedCdps.address)
  }

  static async connectUnipool(uniPool, LQTYContracts, uniswapPairAddr, duration) {
    await uniPool.setParams(LQTYContracts.lqtyToken.address, uniswapPairAddr, duration)
  }
}
module.exports = DeploymentHelper
