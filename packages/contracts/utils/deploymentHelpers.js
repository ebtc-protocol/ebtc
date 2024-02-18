const { ethers } = require("hardhat");

const SortedCdps = artifacts.require("./SortedCdps.sol")
const CdpManager = artifacts.require("./CdpManager.sol")
const PriceFeed = artifacts.require("./PriceFeed.sol")
const EbtcFeed = artifacts.require("./EbtcFeed.sol")
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
const LiquidationSequencer = artifacts.require("./LiquidationSequencer.sol")

const MultiCdpGetter = artifacts.require("./MultiCdpGetter.sol")

const FeeRecipient = artifacts.require("./FeeRecipient.sol")
const EBTCDeployer = artifacts.require("./EBTCDeployer.sol")

const TimelockControllerEnumerable = artifacts.require("./TimelockControllerEnumerable.sol")

const ActivePoolTester = artifacts.require("./ActivePoolTester.sol")
const EbtcMathTester = artifacts.require("./EbtcMathTester.sol")
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

const delay = ms => new Promise(res => setTimeout(res, ms));
const waitFunction = async () => {
  return delay(DeploymentHelper.deployWait);
}

class DeploymentHelper {
  // use setter below in testnet/mainnet deployment
  static deployGasPrice = 0;
  static deployWait = 0;
	
  static async setDeployWait(waitTime) {
	DeploymentHelper.deployWait = waitTime;
	console.log("set deployment waitTime=" + (waitTime / 1000) + " seconds");
  }
	
  static async setDeployGasPrice(price) {
	DeploymentHelper.deployGasPrice = price;
	console.log("set deployment gasPrice=" + (price / 1000000000) + ' GWEI');
  }

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

  static async deployViaCreate3(ebtcDeployer, _argTypes, _argValues, Artifact, _salt) {
    let _deployTx;
    let _code = Artifact.bytecode
	
    if (_argTypes.length > 0 && _argValues.length > 0) {
        let _arg = web3.eth.abi.encodeParameters(_argTypes, _argValues);
        _deployTx = await ebtcDeployer.deployWithCreationCodeAndConstructorArgs(_salt, _code, _arg);
    } else {
        _deployTx = await ebtcDeployer.deployWithCreationCode(_salt, _code);
    }
	
    let _deployedAddr;
    
    if (DeploymentHelper.deployWait > 0){
        console.log(_salt + '_deployedTx=' + DeploymentHelper.getTxHash(_deployTx) + ":wait deploy complete..." + (DeploymentHelper.deployWait / 1000) + " seconds");
        await waitFunction();
        _deployedAddr = await DeploymentHelper.mapSaltToAddress(_salt, ebtcDeployer);
    } else {	
        for (let i = 0; i < _deployTx.logs.length; i++) {
             if (_deployTx.logs[i].event === "ContractDeployed") {
                 _deployedAddr = _deployTx.logs[i].args[0]
                 break;
             }
        }
        //console.log(_salt + '_deployedAddr=' + _deployedAddr);		
    }
    return _deployedAddr;
  }

  static checkValidItem(item) {
    return (item != undefined && typeof item != "undefined" && item != null && item != "");
  }
  
  static getTxHash(tx){
    let _hash = tx["hash"];
    if (!DeploymentHelper.checkValidItem(_hash)){
        _hash = tx["tx"];
    }
    if (!DeploymentHelper.checkValidItem(_hash)){
        let _receipt = tx["receipt"];
        if (DeploymentHelper.checkValidItem(_receipt)){
            _hash = _receipt["transactionHash"];
        }
    }
    return _hash;
  }
  
  static async mapSaltToAddress(salt, ebtcDeployer){
    let _expectedAddr = await ebtcDeployer.getFutureEbtcAddresses();	 
    if (salt === (await ebtcDeployer.AUTHORITY())){
        return _expectedAddr[0];
    } else if (salt === (await ebtcDeployer.LIQUIDATION_LIBRARY())){
        return _expectedAddr[1];
    } else if (salt === (await ebtcDeployer.CDP_MANAGER())){
        return _expectedAddr[2];
    } else if (salt === (await ebtcDeployer.BORROWER_OPERATIONS())){
        return _expectedAddr[3];
    } else if (salt === (await ebtcDeployer.PRICE_FEED())){
        return _expectedAddr[4];
    } else if (salt === (await ebtcDeployer.SORTED_CDPS())){
        return _expectedAddr[5];
    } else if (salt === (await ebtcDeployer.ACTIVE_POOL())){
        return _expectedAddr[6];
    } else if (salt === (await ebtcDeployer.COLL_SURPLUS_POOL())){
        return _expectedAddr[7];
    } else if (salt === (await ebtcDeployer.HINT_HELPERS())){
        return _expectedAddr[8];
    } else if (salt === (await ebtcDeployer.EBTC_TOKEN())){
        return _expectedAddr[9];
    } else if (salt === (await ebtcDeployer.FEE_RECIPIENT())){
        return _expectedAddr[10];
    } else if (salt === (await ebtcDeployer.MULTI_CDP_GETTER())){
        return _expectedAddr[11];
    } else if (salt === (await ebtcDeployer.EBTC_FEED())){
      return _expectedAddr[12];
  }
  }

  static async deployGovernor(ebtcDeployer, _expectedAddr, ownerAddress) {
    console.log("deployGovernor: expected at " + _expectedAddr[0] + ", owner=" + ownerAddress)
    // deploy Governor as Authority 
    const _argTypes = ['address'];
    const _argValues = [ownerAddress];
     
    const _salt = await ebtcDeployer.AUTHORITY();
    const _deployedAddr = await this.deployViaCreate3(ebtcDeployer, _argTypes, _argValues, Governor, _salt);
    assert.isTrue(_deployedAddr == _expectedAddr[0]);
    return await Governor.at(_deployedAddr);
  }

  static async deployLiquidationLibrary(ebtcDeployer, _expectedAddr, collateralAddress) {
    const _argTypes = ['address', 'address', 'address', 'address', 'address', 'address', 'address'];
    const _argValues = [_expectedAddr[3], _expectedAddr[7], _expectedAddr[9], _expectedAddr[5], _expectedAddr[6], _expectedAddr[12], collateralAddress];
	  
    const _salt = await ebtcDeployer.LIQUIDATION_LIBRARY();
    const _deployedAddr = await this.deployViaCreate3(ebtcDeployer, _argTypes, _argValues, LiquidationLibrary, _salt);
    assert.isTrue(_deployedAddr == _expectedAddr[1]);
    return await LiquidationLibrary.at(_deployedAddr);
  }

  static async deployCdpManagerTester(ebtcDeployer, _expectedAddr, collateralAddress) {
    const _argTypes = ['address', 'address', 'address', 'address', 'address', 'address', 'address', 'address', 'address'];
    const _argValues = [_expectedAddr[1], _expectedAddr[0], _expectedAddr[3], _expectedAddr[7], _expectedAddr[9], _expectedAddr[5], _expectedAddr[6], _expectedAddr[4], collateralAddress];

    const _salt = await ebtcDeployer.CDP_MANAGER();
    const _deployedAddr = await this.deployViaCreate3(ebtcDeployer, _argTypes, _argValues, CdpManagerTester, _salt);
    assert.isTrue(_deployedAddr == _expectedAddr[2]);
    return await CdpManagerTester.at(_deployedAddr);
  }

  static async deployBorrowerOperationsTester(ebtcDeployer, _expectedAddr, collateralAddress) {
    // deploy BorrowOperationsTester
    const _argTypes = ['address', 'address', 'address', 'address', 'address', 'address', 'address', 'address'];
    const _argValues = [_expectedAddr[2], _expectedAddr[6], _expectedAddr[7], _expectedAddr[4], _expectedAddr[5], _expectedAddr[9], _expectedAddr[10], collateralAddress];
	  
    const _salt = await ebtcDeployer.BORROWER_OPERATIONS();
    const _deployedAddr = await this.deployViaCreate3(ebtcDeployer, _argTypes, _argValues, BorrowerOperationsTester, _salt);
    assert.isTrue(_deployedAddr == _expectedAddr[3]);
    return await BorrowerOperationsTester.at(_deployedAddr);
  }

  static async deployPriceFeedTestnet(ebtcDeployer, _expectedAddr) {
    const _argTypes = ['address'];
    const _argValues = [_expectedAddr[0]];

    const _salt = await ebtcDeployer.PRICE_FEED();
    const _deployedAddr = await this.deployViaCreate3(ebtcDeployer, _argTypes, _argValues, PriceFeedTestnet, _salt);
    assert.isTrue(_deployedAddr == _expectedAddr[4]);
    return await PriceFeedTestnet.at(_deployedAddr);

  }

  static async deployDualChainlinkPriceFeed(ebtcDeployer, _expectedAddr, _collEthCLFeed, _ethBtcCLFeed) {
    const _argTypes = ['address', 'address', 'address', 'address', 'bool'];
    const _argValues = [ethers.constants.AddressZero, _expectedAddr[0], _collEthCLFeed, _ethBtcCLFeed, false];// use address(0) for IFallbackCaller

    const _salt = await ebtcDeployer.PRICE_FEED();
    const _deployedAddr = await this.deployViaCreate3(ebtcDeployer, _argTypes, _argValues, PriceFeed, _salt);
    console.log(_deployedAddr)
    assert.isTrue(_deployedAddr == _expectedAddr[4]);
    return await PriceFeed.at(_deployedAddr);
  }

  static async deployEbtcFeed(ebtcDeployer, _expectedAddr) {
    const _argTypes = ['address', 'address', 'address'];
    const _argValues = [_expectedAddr[0], _expectedAddr[4], ethers.constants.AddressZero]; // use address(0) for secondary oracle

    const _salt = await ebtcDeployer.EBTC_FEED();
    const _deployedAddr = await this.deployViaCreate3(ebtcDeployer, _argTypes, _argValues, EbtcFeed, _salt);
    // assert.isTrue(_deployedAddr == _expectedAddr[12]);
    // return await EbtcFeed.at(_deployedAddr);
    return await EbtcFeed.at(_expectedAddr[12]);
  }


  static async deploySortedCdps(ebtcDeployer, _expectedAddr) {
    const _argTypes = ['uint256', 'address', 'address'];
    const _argValues = [0, _expectedAddr[2], _expectedAddr[3]];

    const _salt = await ebtcDeployer.SORTED_CDPS();
    const _deployedAddr = await this.deployViaCreate3(ebtcDeployer, _argTypes, _argValues, SortedCdps, _salt);
    assert.isTrue(_deployedAddr == _expectedAddr[5]);
    return await SortedCdps.at(_deployedAddr);
  }

  static async deployActivePoolTester(ebtcDeployer, _expectedAddr, collateralAddress) {
    const _argTypes = ['address', 'address', 'address', 'address'];
    const _argValues = [_expectedAddr[3], _expectedAddr[2], collateralAddress, _expectedAddr[7]];

    const _salt = await ebtcDeployer.ACTIVE_POOL();
    const _deployedAddr = await this.deployViaCreate3(ebtcDeployer, _argTypes, _argValues, ActivePoolTester, _salt);
    assert.isTrue(_deployedAddr == _expectedAddr[6]);
    return await ActivePoolTester.at(_deployedAddr);
  }

  static async deployCollSurplusPool(ebtcDeployer, _expectedAddr, collateralAddress) {
    const _argTypes = ['address', 'address', 'address', 'address'];
    const _argValues = [_expectedAddr[3], _expectedAddr[2], _expectedAddr[6], collateralAddress];
	  
    const _salt = await ebtcDeployer.COLL_SURPLUS_POOL();
    const _deployedAddr = await this.deployViaCreate3(ebtcDeployer, _argTypes, _argValues, CollSurplusPool, _salt);
    assert.isTrue(_deployedAddr == _expectedAddr[7]);
    return await CollSurplusPool.at(_deployedAddr);
  }

  static async deployHintHelper(ebtcDeployer, _expectedAddr, collateralAddress) {
    const _argTypes = ['address', 'address', 'address', 'address', 'address'];
    const _argValues = [_expectedAddr[5], _expectedAddr[2], collateralAddress, _expectedAddr[6], _expectedAddr[12]];
	  
    const _salt = await ebtcDeployer.HINT_HELPERS();
    const _deployedAddr = await this.deployViaCreate3(ebtcDeployer, _argTypes, _argValues, HintHelpers, _salt);
    assert.isTrue(_deployedAddr == _expectedAddr[8]);
    return await HintHelpers.at(_deployedAddr);
  }

  static async deployEBTCTokenTester(ebtcDeployer, _expectedAddr) {
    const _argTypes = ['address', 'address', 'address'];
    const _argValues = [_expectedAddr[2], _expectedAddr[3], _expectedAddr[0]];

    const _salt = await ebtcDeployer.EBTC_TOKEN();
    const _deployedAddr = await this.deployViaCreate3(ebtcDeployer, _argTypes, _argValues, EBTCTokenTester, _salt);
    assert.isTrue(_deployedAddr == _expectedAddr[9]);
    return await EBTCTokenTester.at(_deployedAddr);

  }
  static async deployFeeRecipient(ebtcDeployer, _expectedAddr, ownerAddress) {
    const _argTypes = ['address', 'address'];
    const _argValues = [ownerAddress, _expectedAddr[1]];

    const _salt = await ebtcDeployer.FEE_RECIPIENT();
    const _deployedAddr = await this.deployViaCreate3(ebtcDeployer, _argTypes, _argValues, FeeRecipient, _salt);
    assert.isTrue(_deployedAddr == _expectedAddr[10]);
    return await FeeRecipient.at(_deployedAddr);
  }

  static async deployMultiCdpGetter(ebtcDeployer, _expectedAddr) {
    const _argTypes = ['address', 'address'];
    const _argValues = [_expectedAddr[2], _expectedAddr[5]];
	  
    const _salt = await ebtcDeployer.MULTI_CDP_GETTER();
    const _deployedAddr = await this.deployViaCreate3(ebtcDeployer, _argTypes, _argValues, MultiCdpGetter, _salt);
    assert.isTrue(_deployedAddr == _expectedAddr[11]);
    return await FeeRecipient.at(_deployedAddr);
  }

  static async deployCdpManager(ebtcDeployer, _expectedAddr, collateralAddress) {
    const _argTypes = ['address', 'address', 'address', 'address', 'address', 'address', 'address', 'address', 'address'];
    const _argValues = [_expectedAddr[1], _expectedAddr[0], _expectedAddr[3], _expectedAddr[7], _expectedAddr[9], _expectedAddr[5], _expectedAddr[6], _expectedAddr[12], collateralAddress];

    const _salt = await ebtcDeployer.CDP_MANAGER();
    const _deployedAddr = await this.deployViaCreate3(ebtcDeployer, _argTypes, _argValues, CdpManager, _salt);
    assert.isTrue(_deployedAddr == _expectedAddr[2]);
    return await CdpManager.at(_deployedAddr);
  }

  static async deployBorrowerOperations(ebtcDeployer, _expectedAddr, feeRecipient, collateralAddress){
    const _argTypes = ['address', 'address', 'address', 'address', 'address', 'address', 'address', 'address'];
    const _argValues = [_expectedAddr[2], _expectedAddr[6], _expectedAddr[7], _expectedAddr[12], _expectedAddr[5], _expectedAddr[9], feeRecipient, collateralAddress];

    const _salt = await ebtcDeployer.BORROWER_OPERATIONS();
    const _deployedAddr = await this.deployViaCreate3(ebtcDeployer, _argTypes, _argValues, BorrowerOperations, _salt);
    assert.isTrue(_deployedAddr == _expectedAddr[3]);
    return await BorrowerOperations.at(_deployedAddr);
  }

  static async deployActivePool(ebtcDeployer, _expectedAddr, collateralAddress){
    const _argTypes = ['address', 'address', 'address', 'address'];
    const _argValues = [_expectedAddr[3], _expectedAddr[2], collateralAddress, _expectedAddr[7]];

    const _salt = await ebtcDeployer.ACTIVE_POOL();
    const _deployedAddr = await this.deployViaCreate3(ebtcDeployer, _argTypes, _argValues, ActivePool, _salt);
    assert.isTrue(_deployedAddr == _expectedAddr[6]);
    return await ActivePool.at(_deployedAddr);
  }

  static async deployEBTCToken(ebtcDeployer, _expectedAddr){
    const _argTypes = ['address', 'address', 'address'];
    const _argValues = [_expectedAddr[2], _expectedAddr[3], _expectedAddr[0]];

    const _salt = await ebtcDeployer.EBTC_TOKEN();
    const _deployedAddr = await this.deployViaCreate3(ebtcDeployer, _argTypes, _argValues, EBTCToken, _salt);
    assert.isTrue(_deployedAddr == _expectedAddr[9]);
    return await EBTCToken.at(_deployedAddr);
  }
  
  static async deployCollateralTestnet(){ 
    let _nonce = await ethers.provider.getTransactionCount((await ethers.getSigners())[0].address);  
    const collateral = await CollateralTokenTester.new({gasLimit: await CollateralTokenTester.new.estimateGas(), nonce: _nonce});
    return collateral;
  }
  
  static async deployEBTCDeployer(){  
    let _nonce = await ethers.provider.getTransactionCount((await ethers.getSigners())[0].address);
    const eBTCDeployer = await EBTCDeployer.new({gasLimit: await EBTCDeployer.new.estimateGas(), nonce: _nonce});
    return eBTCDeployer;
  }

  static async deployTimelock(delay, proposers, executors, admin) {
    let _nonce = await ethers.provider.getTransactionCount((await ethers.getSigners())[0].address);
    const timelock = await TimelockControllerEnumerable.new(
      delay,
      proposers,
      executors,
      admin,
      {gasLimit: 5000000, nonce: _nonce}); // Issue when not hardcoding gas limit
    return timelock;
  }

  /**  
    == Local Test Environment Deploy ==
    Deploy core to a local testnet. Does not handle transaction processing.
  */
  static async deployLiquityCoreHardhat() {
    const accounts = await web3.eth.getAccounts()

    const ebtcDeployer = await DeploymentHelper.deployEBTCDeployer();
    let _expectedAddr = await ebtcDeployer.getFutureEbtcAddresses();

    const collateral = await DeploymentHelper.deployCollateralTestnet();
    const functionCaller = await FunctionCaller.new();

    const authority = await DeploymentHelper.deployGovernor(ebtcDeployer, _expectedAddr, accounts[0]);

    const liquidationLibrary = await DeploymentHelper.deployLiquidationLibrary(ebtcDeployer, _expectedAddr, collateral.address);

    const cdpManager = await DeploymentHelper.deployCdpManager(ebtcDeployer, _expectedAddr, collateral.address);
    const borrowerOperations = await DeploymentHelper.deployBorrowerOperations(ebtcDeployer, _expectedAddr, collateral.address);
    const ebtcToken = await DeploymentHelper.deployEBTCToken(ebtcDeployer, _expectedAddr);

    const priceFeedTestnet = await DeploymentHelper.deployPriceFeedTestnet(ebtcDeployer, _expectedAddr);

    const activePool = await DeploymentHelper.deployActivePool(ebtcDeployer, _expectedAddr, collateral.address);
    const collSurplusPool = await DeploymentHelper.deployCollSurplusPool(ebtcDeployer, _expectedAddr, collateral.address);

    const sortedCdps = await DeploymentHelper.deploySortedCdps(ebtcDeployer, _expectedAddr);
    const hintHelpers = await DeploymentHelper.deployHintHelper(ebtcDeployer, _expectedAddr, collateral.address);
    
    const feeRecipient = await DeploymentHelper.deployFeeRecipient(ebtcDeployer, _expectedAddr, accounts[0])
	
    const liquidationSequencer = await LiquidationSequencer.new(cdpManager.address, sortedCdps.address, priceFeedTestnet.address, activePool.address, collateral.address);

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
      collateral,
      liquidationSequencer
    }

    await this.configureGovernor(accounts[0], coreContracts)
    return coreContracts
  }

  /**  
    == Local Test Environment Deploy - Extra Test Functions ==
    Deploy some contract variants that have extra functions that enable easier manipulation of contract state for testing purposes.

    CollateralTokenTester
    CdpManagerTester
    BorrowOperationsTester
    ActivePoolTester
    EBTCTokenTester
  */
  static async deployTesterContractsHardhat() {
    const accounts = await web3.eth.getAccounts()

    const ebtcDeployer = await DeploymentHelper.deployEBTCDeployer();
    let _expectedAddr = await ebtcDeployer.getFutureEbtcAddresses();

    const collateral = await DeploymentHelper.deployCollateralTestnet();

    const testerContracts = {}
    testerContracts.weth = await WETH9.new()
    testerContracts.functionCaller = await FunctionCaller.new();
    testerContracts.collateral = collateral;
    testerContracts.math = await EbtcMathTester.new()

    /**
     struct EbtcAddresses {
      address authorityAddress; 0
      address liquidationLibraryAddress; 1
      address cdpManagerAddress; 2
      address borrowerOperationsAddress; 3
      address priceFeedAddress; 4
      address sortedCdpsAddress; 5
      address activePoolAddress; 6
      address collSurplusPoolAddress; 7
      address hintHelpersAddress; 8
      address ebtcTokenAddress; 9
      address feeRecipientAddress; 10
      address multiCdpGetterAddress; 11
      address ebtcFeedAddress; 12
    }
     */

    testerContracts.authority = await DeploymentHelper.deployGovernor(ebtcDeployer, _expectedAddr, accounts[0]);
    testerContracts.liquidationLibrary = await DeploymentHelper.deployLiquidationLibrary(ebtcDeployer, _expectedAddr, collateral.address);

    testerContracts.cdpManager = await DeploymentHelper.deployCdpManagerTester(ebtcDeployer, _expectedAddr, collateral.address);
    testerContracts.borrowerOperations = await DeploymentHelper.deployBorrowerOperationsTester(ebtcDeployer, _expectedAddr, collateral.address);
    testerContracts.ebtcToken = await DeploymentHelper.deployEBTCTokenTester(ebtcDeployer, _expectedAddr);
    testerContracts.priceFeedTestnet = await DeploymentHelper.deployPriceFeedTestnet(ebtcDeployer, _expectedAddr);
    testerContracts.ebtcFeed = await DeploymentHelper.deployEbtcFeed(ebtcDeployer, _expectedAddr);
    
    testerContracts.activePool = await DeploymentHelper.deployActivePoolTester(ebtcDeployer, _expectedAddr, collateral.address);
    testerContracts.collSurplusPool = await DeploymentHelper.deployCollSurplusPool(ebtcDeployer, _expectedAddr, collateral.address);

    testerContracts.sortedCdps = await DeploymentHelper.deploySortedCdps(ebtcDeployer, _expectedAddr);
    testerContracts.hintHelpers = await DeploymentHelper.deployHintHelper(ebtcDeployer, _expectedAddr, collateral.address);
    
    testerContracts.feeRecipient = await DeploymentHelper.deployFeeRecipient(ebtcDeployer, _expectedAddr, accounts[0]);	
	
    testerContracts.liquidationSequencer = await LiquidationSequencer.new(testerContracts.cdpManager.address,
                                                                          testerContracts.sortedCdps.address, 
                                                                          testerContracts.priceFeedTestnet.address, 
                                                                          testerContracts.activePool.address, 
                                                                          collateral.address);

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
}

module.exports = DeploymentHelper
