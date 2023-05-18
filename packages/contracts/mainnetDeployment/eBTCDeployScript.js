const DeploymentHelper = require('../utils/deploymentHelpers.js')
const configParams = require("./eBTCDeploymentParams.goerli.js")
//const configParams = require("./eBTCDeploymentParams.mainnet.js")

const { TestHelper: th, TimeValues: timeVals } = require("../utils/testHelpers.js")
const MainnetDeploymentHelper = require("../utils/mainnetDeploymentHelpers.js")
const fs = require("fs");

const toBigNum = ethers.BigNumber.from
const mintAmountPerTestAccount = toBigNum("100000000000000000000")

const _governorStateName = 'authority';
const _liquidationLibraryStateName = 'liquidationLibrary';
const _cdpManagerStateName = 'cdpManager';
const _borrowerOperationsStateName = 'borrowerOperations';
const _eBTCTokenStateName = 'eBTCToken';
const _priceFeedStateName = 'priceFeed';
const _activePoolStateName = 'activePool';
const _collSurplusPoolStateName = 'collSurplusPool';
const _sortedCdpsStateName = 'sortedCdps';
const _hintHelpersStateName = 'hintHelpers';
const _feeRecipientStateName = 'feeRecipient';
const _eBTCDeployerStateName = 'eBTCDeployer';
const _collateralStateName = 'collateral';
 
async function eBTCDeployCore(testnet, mainnetDeploymentHelper, deploymentState, ebtcDeployer, governanceAddr, authorityOwner, feeRecipientOwner, collateralAddr) {

    let _expectedAddr = await ebtcDeployer.getFutureEbtcAddresses();	
    
    // deploy authority(Governor)
    let _stateName = _governorStateName;
    let _constructorArgs = [authorityOwner];
    let _checkExistDeployment = checkExistingDeployment(_stateName, deploymentState);
    let authority;
    if (_checkExistDeployment['_toDeploy']) {
        authority = await DeploymentHelper.deployGovernor(ebtcDeployer, _expectedAddr, authorityOwner);
        await saveToDeploymentStateFile(mainnetDeploymentHelper, _stateName, deploymentState, authority);
    } else{
        authority = await (await ethers.getContractFactory("Governor")).attach(deploymentState[_stateName]["address"])
        console.log('Sanity checking: authorityOwner=' + authorityOwner + ', authority.owner()=' + (await authority.owner()));
    }
    if (_checkExistDeployment['_toVerify']){
        await verifyContractsViaPlugin(mainnetDeploymentHelper, _stateName, deploymentState, _constructorArgs);			
    }

    // deploy liquidationLibrary
    _stateName = _liquidationLibraryStateName;
    _constructorArgs = [_expectedAddr[3], _expectedAddr[7], _expectedAddr[9], _expectedAddr[5], _expectedAddr[6], _expectedAddr[4], collateralAddr];
    _checkExistDeployment = checkExistingDeployment(_stateName, deploymentState);
    let liquidationLibrary;
    if (_checkExistDeployment['_toDeploy']) {		
        liquidationLibrary = await DeploymentHelper.deployLiquidationLibrary(ebtcDeployer, _expectedAddr, collateralAddr);
        await saveToDeploymentStateFile(mainnetDeploymentHelper, _stateName, deploymentState, liquidationLibrary);
    } else{
        liquidationLibrary = await (await ethers.getContractFactory("LiquidationLibrary")).attach(deploymentState[_stateName]["address"])
        console.log('Sanity checking: liquidationLibrary.LIQUIDATOR_REWARD()=' + (await liquidationLibrary.LIQUIDATOR_REWARD()));
    }
    if (_checkExistDeployment['_toVerify']){
        await verifyContractsViaPlugin(mainnetDeploymentHelper, _stateName, deploymentState, _constructorArgs);			
    }

    // deploy cdpManager
    _stateName = _cdpManagerStateName;
    _constructorArgs = [_expectedAddr[1], _expectedAddr[0], _expectedAddr[3], _expectedAddr[7], _expectedAddr[9], _expectedAddr[5], _expectedAddr[6], _expectedAddr[4], collateralAddr];
    _checkExistDeployment = checkExistingDeployment(_stateName, deploymentState);
    let cdpManager;
    if (_checkExistDeployment['_toDeploy'])	{	
        cdpManager = await DeploymentHelper.deployCdpManager(ebtcDeployer, _expectedAddr, collateralAddr);
        await saveToDeploymentStateFile(mainnetDeploymentHelper, _stateName, deploymentState, cdpManager);
    } else{
        cdpManager = await (await ethers.getContractFactory("CdpManager")).attach(deploymentState[_stateName]["address"])
        console.log('Sanity checking: cdpManager.authority()=' + (await cdpManager.authority()));
    }
    if (_checkExistDeployment['_toVerify']){
        await verifyContractsViaPlugin(mainnetDeploymentHelper, _stateName, deploymentState, _constructorArgs);			
    }

    // deploy borrowerOperations
    _stateName = _borrowerOperationsStateName;
    _constructorArgs = [_expectedAddr[2], _expectedAddr[6], _expectedAddr[7], _expectedAddr[4], _expectedAddr[5], _expectedAddr[9], _expectedAddr[10], collateralAddr];
    _checkExistDeployment = checkExistingDeployment(_stateName, deploymentState);
    let borrowerOperations;
    if (_checkExistDeployment['_toDeploy'])	{	
        borrowerOperations = await DeploymentHelper.deployBorrowerOperations(ebtcDeployer, _expectedAddr, collateralAddr);
        await saveToDeploymentStateFile(mainnetDeploymentHelper, _stateName, deploymentState, borrowerOperations);
    } else{
        borrowerOperations = await (await ethers.getContractFactory("BorrowerOperations")).attach(deploymentState[_stateName]["address"])
        console.log('Sanity checking: borrowerOperations.authority()=' + (await borrowerOperations.authority()));
    }
    if (_checkExistDeployment['_toVerify']){
        await verifyContractsViaPlugin(mainnetDeploymentHelper, _stateName, deploymentState, _constructorArgs);			
    }

    // deploy eBTCToken
    _stateName = _eBTCTokenStateName;
    _constructorArgs = [_expectedAddr[2], _expectedAddr[3], _expectedAddr[0]];
    _checkExistDeployment = checkExistingDeployment(_stateName, deploymentState);
    let ebtcToken;
    if (_checkExistDeployment['_toDeploy'])	{	
        ebtcToken = await DeploymentHelper.deployEBTCToken(ebtcDeployer, _expectedAddr);
        await saveToDeploymentStateFile(mainnetDeploymentHelper, _stateName, deploymentState, ebtcToken);
    } else{
        ebtcToken = await (await ethers.getContractFactory("EBTCToken")).attach(deploymentState[_stateName]["address"])
        console.log('Sanity checking: ebtcToken.authority()=' + (await ebtcToken.authority()));
    }
    if (_checkExistDeployment['_toVerify']){
        await verifyContractsViaPlugin(mainnetDeploymentHelper, _stateName, deploymentState, _constructorArgs);			
    }

    // deploy priceFeed
    _stateName = _priceFeedStateName;
    _constructorArgs = testnet? [_expectedAddr[0]] : [ethers.constants.AddressZero, _expectedAddr[0]];
    _checkExistDeployment = checkExistingDeployment(_stateName, deploymentState);
    let priceFeed;
    if (_checkExistDeployment['_toDeploy'])	{	
        priceFeed = testnet? await DeploymentHelper.deployPriceFeedTestnet(ebtcDeployer, _expectedAddr) : 
                             await DeploymentHelper.deployPriceFeed(ebtcDeployer, _expectedAddr);
        await saveToDeploymentStateFile(mainnetDeploymentHelper, _stateName, deploymentState, priceFeed);
    } else{
        let contractName = testnet? "PriceFeedTestnet" : "PriceFeed";
        priceFeed = await (await ethers.getContractFactory(contractName)).attach(deploymentState[_stateName]["address"])
        console.log('Sanity checking: priceFeed.authority()=' + (await priceFeed.authority()));
    }
    if (_checkExistDeployment['_toVerify']){
        await verifyContractsViaPlugin(mainnetDeploymentHelper, _stateName, deploymentState, _constructorArgs);			
    }

    // deploy activePool
    _stateName = _activePoolStateName;
    _constructorArgs = [_expectedAddr[3], _expectedAddr[2], collateralAddr, _expectedAddr[7], _expectedAddr[10]];
    _checkExistDeployment = checkExistingDeployment(_stateName, deploymentState);
    let activePool;
    if (_checkExistDeployment['_toDeploy'])	{	
        activePool = await DeploymentHelper.deployActivePool(ebtcDeployer, _expectedAddr, collateralAddr);
        await saveToDeploymentStateFile(mainnetDeploymentHelper, _stateName, deploymentState, activePool);
    } else{
        activePool = await (await ethers.getContractFactory("ActivePool")).attach(deploymentState[_stateName]["address"])
        console.log('Sanity checking: activePool.authority()=' + (await activePool.authority()));
    }
    if (_checkExistDeployment['_toVerify']){
        await verifyContractsViaPlugin(mainnetDeploymentHelper, _stateName, deploymentState, _constructorArgs);			
    }

    // deploy collSurplusPool
    _stateName = _collSurplusPoolStateName;
    _constructorArgs = [_expectedAddr[3], _expectedAddr[2], _expectedAddr[6], collateralAddr];
    _checkExistDeployment = checkExistingDeployment(_stateName, deploymentState);
    let collSurplusPool;
    if (_checkExistDeployment['_toDeploy'])	{	
        collSurplusPool = await DeploymentHelper.deployCollSurplusPool(ebtcDeployer, _expectedAddr, collateralAddr);
        await saveToDeploymentStateFile(mainnetDeploymentHelper, _stateName, deploymentState, collSurplusPool);
    } else{
        collSurplusPool = await (await ethers.getContractFactory("CollSurplusPool")).attach(deploymentState[_stateName]["address"])
        console.log('Sanity checking: collSurplusPool.authority()=' + (await collSurplusPool.authority()));
    }
    if (_checkExistDeployment['_toVerify']){
        await verifyContractsViaPlugin(mainnetDeploymentHelper, _stateName, deploymentState, _constructorArgs);			
    }

    // deploy sortedCdps
    _stateName = _sortedCdpsStateName;
    _constructorArgs = [0, _expectedAddr[2], _expectedAddr[3]];
    _checkExistDeployment = checkExistingDeployment(_stateName, deploymentState);
    let sortedCdps;
    if (_checkExistDeployment['_toDeploy'])	{	
        sortedCdps = await DeploymentHelper.deploySortedCdps(ebtcDeployer, _expectedAddr);
        await saveToDeploymentStateFile(mainnetDeploymentHelper, _stateName, deploymentState, sortedCdps);
    } else{
        sortedCdps = await (await ethers.getContractFactory("SortedCdps")).attach(deploymentState[_stateName]["address"])
        console.log('Sanity checking: sortedCdps.NAME()=' + (await sortedCdps.NAME()));
    }
    if (_checkExistDeployment['_toVerify']){
        await verifyContractsViaPlugin(mainnetDeploymentHelper, _stateName, deploymentState, _constructorArgs);			
    }

    // deploy hintHelpers
    _stateName = _hintHelpersStateName;
    _constructorArgs = [_expectedAddr[5], _expectedAddr[2], collateralAddr, _expectedAddr[6], _expectedAddr[4]];
    _checkExistDeployment = checkExistingDeployment(_stateName, deploymentState);
    let hintHelpers;
    if (_checkExistDeployment['_toDeploy'])	{	
        hintHelpers = await DeploymentHelper.deployHintHelper(ebtcDeployer, _expectedAddr, collateralAddr);
        await saveToDeploymentStateFile(mainnetDeploymentHelper, _stateName, deploymentState, hintHelpers);
    } else{
        hintHelpers = await (await ethers.getContractFactory("HintHelpers")).attach(deploymentState[_stateName]["address"])
        console.log('Sanity checking: hintHelpers.NAME()=' + (await hintHelpers.NAME()));
    }
    if (_checkExistDeployment['_toVerify']){
        await verifyContractsViaPlugin(mainnetDeploymentHelper, _stateName, deploymentState, _constructorArgs);			
    }

    // deploy feeRecipient
    _stateName = _feeRecipientStateName;
    _constructorArgs = [feeRecipientOwner, _expectedAddr[1]];
    _checkExistDeployment = checkExistingDeployment(_stateName, deploymentState);
    let feeRecipient;
    if (_checkExistDeployment['_toDeploy'])	{	
        feeRecipient = await DeploymentHelper.deployFeeRecipient(ebtcDeployer, _expectedAddr, feeRecipientOwner)
        await saveToDeploymentStateFile(mainnetDeploymentHelper, _stateName, deploymentState, feeRecipient);
    } else{
        feeRecipient = await (await ethers.getContractFactory("FeeRecipient")).attach(deploymentState[_stateName]["address"])
        console.log('Sanity checking: feeRecipient.NAME()=' + (await feeRecipient.NAME()));
    }
    if (_checkExistDeployment['_toVerify']){
        await verifyContractsViaPlugin(mainnetDeploymentHelper, _stateName, deploymentState, _constructorArgs);			
    }

    const coreContracts = {
      authority,
      liquidationLibrary,
      cdpManager,
      borrowerOperations,
      priceFeed,
      sortedCdps,
      activePool,
      collSurplusPool,
      hintHelpers,
      ebtcToken,
      feeRecipient
    }

    await DeploymentHelper.configureGovernor(governanceAddr, coreContracts)
    return coreContracts;
}

async function verifyContractsViaPlugin(mainnetDeploymentHelper, name, deploymentState, constructorArgs){	
    if (!configParams.ETHERSCAN_BASE_URL) {
        console.log('No Etherscan Url defined, skipping verification')
    } else {
        await mainnetDeploymentHelper.verifyContract(name, deploymentState, constructorArgs)
        if (!checkValidItem(deploymentState[name]["verification"])){
            console.log('error verification for ' + name + ", quit deployment...")
            process.exit(0);
        }
    }
}

async function saveToDeploymentStateFile(mainnetDeploymentHelper, name, deploymentState, contract){
    deploymentState[name] = {
      address: contract.address
    }
    console.log('Deployed ' + name + ' at ' + deploymentState[name]["address"]);

    mainnetDeploymentHelper.saveDeployment(deploymentState)
}

async function main() {
    const date = new Date()
    console.log(date.toUTCString())
	
    // connect deployer which should be the one set in your hardhat.config.js [network] section
    const deployerWallet = (await ethers.getSigners())[0]
    let _deployer = deployerWallet;

    console.log(`deployer address: ${_deployer.address}`)
    let deployerETHBalance = await ethers.provider.getBalance(_deployer.address)
    console.log(`deployerETHBalance before: ${deployerETHBalance}`)
  
    const mdh = new MainnetDeploymentHelper(configParams, _deployer)
    const gasPrice = configParams.GAS_PRICE
    const maxFeePerGas = configParams.MAX_FEE_PER_GAS

    let latestBlock = await ethers.provider.getBlockNumber()
    console.log('block number:', latestBlock)
    const chainId = await ethers.provider.getNetwork()
    console.log('ChainId:', chainId.chainId)

    // flag if testnet or mainnet deployment	
    let _testnet = true;// (chainId.chainId == 5)
	
    // read from config?
    let _governance = _deployer;
    let _authorityOwner = _deployer;
    let _feeRecipientOwner = _deployer;
    let _gasPrice = configParams.GAS_PRICE;
    let _deployWaitMilliSeonds = configParams.DEPLOY_WAIT;
	
    // contract dependencies
    let _collateral;
  
    // load deployment state
    let deploymentState = mdh.loadPreviousDeployment();
    await DeploymentHelper.setDeployGasPrice(_gasPrice);
    await DeploymentHelper.setDeployWait(_deployWaitMilliSeonds);
	
    // get collateral
    let _checkExistDeployment = checkExistingDeployment(_collateralStateName, deploymentState);
    if (_checkExistDeployment['_toDeploy'] && _testnet) {
        _collateral = await DeploymentHelper.deployCollateralTestnet();
        await saveToDeploymentStateFile(mdh, _collateralStateName, deploymentState, _collateral);		
    } else if(_testnet){
        _collateral = await (await ethers.getContractFactory("CollateralTokenTester")).attach(deploymentState[_collateralStateName]["address"])		
    } else{
        //TODO connect to stETH on mainnet 
    }	
    if (_checkExistDeployment['_toVerify'] && _testnet){
        await verifyContractsViaPlugin(mdh, _collateralStateName, deploymentState, []);		
    }
	
    // deploy ebtcDeployer contract to blockchain
    let ebtcDeployer;
    _checkExistDeployment = checkExistingDeployment(_eBTCDeployerStateName, deploymentState);
    if (_checkExistDeployment['_toDeploy']) {
        ebtcDeployer = await DeploymentHelper.deployEBTCDeployer();
        await saveToDeploymentStateFile(mdh, _eBTCDeployerStateName, deploymentState, ebtcDeployer);	
    } else{
        ebtcDeployer = await (await ethers.getContractFactory("EBTCDeployerTester")).attach(deploymentState[_eBTCDeployerStateName]["address"])
    }	
    if (_checkExistDeployment['_toVerify']){
        await verifyContractsViaPlugin(mdh, _eBTCDeployerStateName, deploymentState, []);	
    }	
  
    // deploy core contracts to blockchain	
    let coreContracts = await eBTCDeployCore(_testnet, mdh, deploymentState, ebtcDeployer, _governance.address, _authorityOwner.address, _feeRecipientOwner.address, _collateral.address)
}

function checkExistingDeployment(stateName, deploymentState){
	
    let _checkExistDeployment = {'_toDeploy': true, '_toVerify': true};
    let _deployedState = deploymentState[stateName];
    //console.log('_deployedState for ' + stateName + '=' + JSON.stringify(_deployedState));
	
    if (checkValidItem(_deployedState)){
        let _deployedStateAddr = _deployedState["address"];
        if (checkValidItem(_deployedStateAddr)){
            console.log(stateName + " is already deployed at " + _deployedStateAddr); 
            _checkExistDeployment['_toDeploy'] = false;
        }
		
        let _deployedStateVerification = _deployedState["verification"];
        if (checkValidItem(_deployedStateVerification)){
            console.log(stateName + " is already verified: " + _deployedStateVerification); 
            _checkExistDeployment['_toVerify'] = false;
        }
    }
    return _checkExistDeployment;
}

function checkValidItem(item){
    return (item != undefined && typeof item != "undefined" && item != null && item != "");
}

// cd <eBTCRoot>/packages/contracts
// you may need to clean folder <./artifacts> to get a fresh new running 
// npx hardhat run ./mainnetDeployment/eBTCDeployScript.js --network <goerli|mainnet>
main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });

