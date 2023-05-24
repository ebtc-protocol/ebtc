const DeploymentHelper = require('../utils/deploymentHelpers.js')
const configParamsGoerli = require("./eBTCDeploymentParams.goerli.js")
const configParamsMainnet = require("./eBTCDeploymentParams.mainnet.js")

const { TestHelper: th, TimeValues: timeVals } = require("../utils/testHelpers.js")
const MainnetDeploymentHelper = require("../utils/mainnetDeploymentHelpers.js")

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
let configParams;
 
async function verifyState(_checkExistDeployment, _stateName, mainnetDeploymentHelper, deploymentState, _constructorArgs){
	
    if (_checkExistDeployment['_toVerify']){
        console.log('verifying ' + _stateName + '...');
        await verifyContractsViaPlugin(mainnetDeploymentHelper, _stateName, deploymentState, _constructorArgs);			
    }
}

async function deployStateViaHelper(testnet, mainnetDeploymentHelper, deploymentState, ebtcDeployer, _stateName, _expectedAddr, authorityOwner, feeRecipientOwner, collateralAddr){
    let _deployedState;
    console.log('deploying ' + _stateName + '...');
    if (_stateName == _governorStateName){
        _deployedState = await DeploymentHelper.deployGovernor(ebtcDeployer, _expectedAddr, authorityOwner);
    } else if(_stateName == _liquidationLibraryStateName){
        _deployedState = await DeploymentHelper.deployLiquidationLibrary(ebtcDeployer, _expectedAddr, collateralAddr);
    } else if(_stateName == _cdpManagerStateName){
        _deployedState = await DeploymentHelper.deployCdpManager(ebtcDeployer, _expectedAddr, collateralAddr);
    } else if(_stateName == _borrowerOperationsStateName){
        _deployedState = await DeploymentHelper.deployBorrowerOperations(ebtcDeployer, _expectedAddr, collateralAddr);
    } else if(_stateName == _eBTCTokenStateName){
        _deployedState = await DeploymentHelper.deployEBTCToken(ebtcDeployer, _expectedAddr);
    } else if(_stateName == _priceFeedStateName){
        _deployedState = testnet? await DeploymentHelper.deployPriceFeedTestnet(ebtcDeployer, _expectedAddr) : 
                                  await DeploymentHelper.deployPriceFeed(ebtcDeployer, _expectedAddr);
    } else if(_stateName == _activePoolStateName){
        _deployedState = await DeploymentHelper.deployActivePool(ebtcDeployer, _expectedAddr, collateralAddr);
    } else if(_stateName == _collSurplusPoolStateName){
        _deployedState = await DeploymentHelper.deployCollSurplusPool(ebtcDeployer, _expectedAddr, collateralAddr);
    } else if(_stateName == _sortedCdpsStateName){
        _deployedState = await DeploymentHelper.deploySortedCdps(ebtcDeployer, _expectedAddr);
    } else if(_stateName == _hintHelpersStateName){
        _deployedState = await DeploymentHelper.deployHintHelper(ebtcDeployer, _expectedAddr, collateralAddr);
    } else if(_stateName == _feeRecipientStateName){
        _deployedState = await DeploymentHelper.deployFeeRecipient(ebtcDeployer, _expectedAddr, feeRecipientOwner)
    } else if(_stateName == _eBTCDeployerStateName){
        _deployedState = await DeploymentHelper.deployEBTCDeployer();
    } else if(_stateName == _collateralStateName){
        _deployedState = await DeploymentHelper.deployCollateralTestnet();
    }
    await saveToDeploymentStateFile(mainnetDeploymentHelper, _stateName, deploymentState, _deployedState);
    return _deployedState;
}

async function loadDeployedState(testnet, deploymentState, _stateName){
    let _deployedState;
    if (_stateName == _governorStateName){
        _deployedState = await (await ethers.getContractFactory("Governor")).attach(deploymentState[_stateName]["address"])
        console.log('Sanity checking: authority.owner()=' + (await _deployedState.owner()));		
    } else if(_stateName == _liquidationLibraryStateName){
        _deployedState = await (await ethers.getContractFactory("LiquidationLibrary")).attach(deploymentState[_stateName]["address"])
        console.log('Sanity checking: liquidationLibrary.LIQUIDATOR_REWARD()=' + (await _deployedState.LIQUIDATOR_REWARD()));
    } else if(_stateName == _cdpManagerStateName){
        _deployedState = await (await ethers.getContractFactory("CdpManager")).attach(deploymentState[_stateName]["address"])
        console.log('Sanity checking: cdpManager.authority()=' + (await _deployedState.authority()));
    } else if(_stateName == _borrowerOperationsStateName){
        _deployedState = await (await ethers.getContractFactory("BorrowerOperations")).attach(deploymentState[_stateName]["address"])
        console.log('Sanity checking: borrowerOperations.authority()=' + (await _deployedState.authority()));
    } else if(_stateName == _eBTCTokenStateName){
        _deployedState = await (await ethers.getContractFactory("EBTCToken")).attach(deploymentState[_stateName]["address"])
        console.log('Sanity checking: ebtcToken.authority()=' + (await _deployedState.authority()));
    } else if(_stateName == _priceFeedStateName){
        let contractName = testnet? "PriceFeedTestnet" : "PriceFeed";
        _deployedState = await (await ethers.getContractFactory(contractName)).attach(deploymentState[_stateName]["address"])
        console.log('Sanity checking: priceFeed.authority()=' + (await _deployedState.authority()));
    } else if(_stateName == _activePoolStateName){
        _deployedState = await (await ethers.getContractFactory("ActivePool")).attach(deploymentState[_stateName]["address"])
        console.log('Sanity checking: activePool.authority()=' + (await _deployedState.authority()));
    } else if(_stateName == _collSurplusPoolStateName){
        _deployedState = await (await ethers.getContractFactory("CollSurplusPool")).attach(deploymentState[_stateName]["address"])
        console.log('Sanity checking: collSurplusPool.authority()=' + (await _deployedState.authority()));
    } else if(_stateName == _sortedCdpsStateName){
        _deployedState = await (await ethers.getContractFactory("SortedCdps")).attach(deploymentState[_stateName]["address"])
        console.log('Sanity checking: sortedCdps.NAME()=' + (await _deployedState.NAME()));
    } else if(_stateName == _hintHelpersStateName){
        _deployedState = await (await ethers.getContractFactory("HintHelpers")).attach(deploymentState[_stateName]["address"])
        console.log('Sanity checking: hintHelpers.NAME()=' + (await _deployedState.NAME()));
    } else if(_stateName == _feeRecipientStateName){
        _deployedState = await (await ethers.getContractFactory("FeeRecipient")).attach(deploymentState[_stateName]["address"])
        console.log('Sanity checking: feeRecipient.NAME()=' + (await _deployedState.NAME()));
    } else if(_stateName == _eBTCDeployerStateName){
        _deployedState = await (await ethers.getContractFactory("EBTCDeployerTester")).attach(deploymentState[_eBTCDeployerStateName]["address"])
    }
    return _deployedState;
}

async function deployOrLoadState(testnet, mainnetDeploymentHelper, deploymentState, ebtcDeployer, _stateName, _expectedAddr, authorityOwner, feeRecipientOwner, collateralAddr, _constructorArgs){
    let _checkExistDeployment = checkExistingDeployment(_stateName, deploymentState);
    let _deployedState;
    if (_checkExistDeployment['_toDeploy']) {
        _deployedState = await deployStateViaHelper(testnet, mainnetDeploymentHelper, deploymentState, ebtcDeployer, _stateName, _expectedAddr, authorityOwner, feeRecipientOwner, collateralAddr);
    } else{
        _deployedState = await loadDeployedState(testnet, deploymentState, _stateName)
    }
    await verifyState(_checkExistDeployment, _stateName, mainnetDeploymentHelper, deploymentState, _constructorArgs);
    return _deployedState;
}

async function eBTCDeployCore(testnet, mainnetDeploymentHelper, deploymentState, ebtcDeployer, authorityOwner, feeRecipientOwner, collateralAddr) {

    let _expectedAddr = await ebtcDeployer.getFutureEbtcAddresses();	
    
    // deploy authority(Governor)
    let _stateName = _governorStateName;
    let _constructorArgs = [authorityOwner];
    let authority = await deployOrLoadState(testnet, mainnetDeploymentHelper, deploymentState, ebtcDeployer, _stateName, authorityOwner, feeRecipientOwner, collateralAddr, _constructorArgs);
	
    // deploy liquidationLibrary
    _stateName = _liquidationLibraryStateName;
    _constructorArgs = [_expectedAddr[3], _expectedAddr[7], _expectedAddr[9], _expectedAddr[5], _expectedAddr[6], _expectedAddr[4], collateralAddr];
    let liquidationLibrary = await deployOrLoadState(testnet, mainnetDeploymentHelper, deploymentState, ebtcDeployer, _stateName, authorityOwner, feeRecipientOwner, collateralAddr, _constructorArgs);

    // deploy cdpManager
    _stateName = _cdpManagerStateName;
    _constructorArgs = [_expectedAddr[1], _expectedAddr[0], _expectedAddr[3], _expectedAddr[7], _expectedAddr[9], _expectedAddr[5], _expectedAddr[6], _expectedAddr[4], collateralAddr];
    let cdpManager = await deployOrLoadState(testnet, mainnetDeploymentHelper, deploymentState, ebtcDeployer, _stateName, authorityOwner, feeRecipientOwner, collateralAddr, _constructorArgs);

    // deploy borrowerOperations
    _stateName = _borrowerOperationsStateName;
    _constructorArgs = [_expectedAddr[2], _expectedAddr[6], _expectedAddr[7], _expectedAddr[4], _expectedAddr[5], _expectedAddr[9], _expectedAddr[10], collateralAddr];
    let borrowerOperations = await deployOrLoadState(testnet, mainnetDeploymentHelper, deploymentState, ebtcDeployer, _stateName, authorityOwner, feeRecipientOwner, collateralAddr, _constructorArgs);

    // deploy eBTCToken
    _stateName = _eBTCTokenStateName;
    _constructorArgs = [_expectedAddr[2], _expectedAddr[3], _expectedAddr[0]];
    let ebtcToken = await deployOrLoadState(testnet, mainnetDeploymentHelper, deploymentState, ebtcDeployer, _stateName, authorityOwner, feeRecipientOwner, collateralAddr, _constructorArgs);

    // deploy priceFeed
    _stateName = _priceFeedStateName;
    _constructorArgs = testnet? [_expectedAddr[0]] : [ethers.constants.AddressZero, _expectedAddr[0]];
    let priceFeed = await deployOrLoadState(testnet, mainnetDeploymentHelper, deploymentState, ebtcDeployer, _stateName, authorityOwner, feeRecipientOwner, collateralAddr, _constructorArgs);

    // deploy activePool
    _stateName = _activePoolStateName;
    _constructorArgs = [_expectedAddr[3], _expectedAddr[2], collateralAddr, _expectedAddr[7], _expectedAddr[10]];
    let activePool = await deployOrLoadState(testnet, mainnetDeploymentHelper, deploymentState, ebtcDeployer, _stateName, authorityOwner, feeRecipientOwner, collateralAddr, _constructorArgs);

    // deploy collSurplusPool
    _stateName = _collSurplusPoolStateName;
    _constructorArgs = [_expectedAddr[3], _expectedAddr[2], _expectedAddr[6], collateralAddr];
    let collSurplusPool = await deployOrLoadState(testnet, mainnetDeploymentHelper, deploymentState, ebtcDeployer, _stateName, authorityOwner, feeRecipientOwner, collateralAddr, _constructorArgs);

    // deploy sortedCdps
    _stateName = _sortedCdpsStateName;
    _constructorArgs = [0, _expectedAddr[2], _expectedAddr[3]];
    let sortedCdps = await deployOrLoadState(testnet, mainnetDeploymentHelper, deploymentState, ebtcDeployer, _stateName, authorityOwner, feeRecipientOwner, collateralAddr, _constructorArgs);

    // deploy hintHelpers
    _stateName = _hintHelpersStateName;
    _constructorArgs = [_expectedAddr[5], _expectedAddr[2], collateralAddr, _expectedAddr[6], _expectedAddr[4]];
    let hintHelpers = await deployOrLoadState(testnet, mainnetDeploymentHelper, deploymentState, ebtcDeployer, _stateName, authorityOwner, feeRecipientOwner, collateralAddr, _constructorArgs);

    // deploy feeRecipient
    _stateName = _feeRecipientStateName;
    _constructorArgs = [feeRecipientOwner, _expectedAddr[1]];
    let feeRecipient = await deployOrLoadState(testnet, mainnetDeploymentHelper, deploymentState, ebtcDeployer, _stateName, authorityOwner, feeRecipientOwner, collateralAddr, _constructorArgs);

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

    let latestBlock = await ethers.provider.getBlockNumber()
    console.log('block number:', latestBlock)
    const chainId = await ethers.provider.getNetwork()
    console.log('ChainId:', chainId.chainId)

    // Flag if testnet or mainnet deployment:
    // To simulate mainnet deployment on testnet for gas-saving,
    // simply set it to "false" but still run with "--network goerli"	
    let _testnet = true;
    configParams = _testnet? configParamsGoerli : configParamsMainnet;
    console.log('deploy to ' + (_testnet? 'testnet(goerli)' : (chainId.chainId == 5? 'mainnet (simulate with goerli)' : 'mainnet')));
  
    const mdh = new MainnetDeploymentHelper(configParams, _deployer)
    const gasPrice = configParams.GAS_PRICE
    const maxFeePerGas = configParams.MAX_FEE_PER_GAS
	
    // read from config
    let _authorityOwner = checkValidItem(configParams.externalAddress['authorityOwner'])? configParams.externalAddress['authorityOwner'] : _deployer.address;
    let _feeRecipientOwner = checkValidItem(configParams.externalAddress['feeRecipientOwner'])? configParams.externalAddress['feeRecipientOwner'] : _deployer.address;
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
        _collateral = await deployStateViaHelper(_testnet, mdh, deploymentState, ebtcDeployer, _testnet, [], _authorityOwner, _feeRecipientOwner, _collateral.address);
    } else if(_testnet){
        _collateral = await (await ethers.getContractFactory("CollateralTokenTester")).attach(deploymentState[_collateralStateName]["address"])		
    } else{
        _collateral = await ethers.getContractAt("ICollateralToken", configParams.externalAddress[_collateralStateName])
        console.log('collateral.getOracle()=' + (await _collateral.getOracle()));		
    }
    if (_testnet){
        await verifyState(_checkExistDeployment, _collateralStateName, mdh, deploymentState, []);	
    }
	
    // deploy ebtcDeployer contract to blockchain
    let ebtcDeployer = await deployOrLoadState(_testnet, mdh, deploymentState, "", _eBTCDeployerStateName, _authorityOwner, _feeRecipientOwner, _collateral.address, []);
  
    // deploy core contracts to blockchain	
    let coreContracts = await eBTCDeployCore(_testnet, mdh, deploymentState, ebtcDeployer, _authorityOwner, _feeRecipientOwner, _collateral.address)
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

