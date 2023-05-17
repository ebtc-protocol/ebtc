const DeploymentHelper = require('../utils/deploymentHelpers.js')
const configParams = require("./eBTCDeploymentParams.goerli.js")
//const configParams = require("./eBTCDeploymentParams.mainnet.js")

const { TestHelper: th, TimeValues: timeVals } = require("../utils/testHelpers.js")
const MainnetDeploymentHelper = require("../utils/mainnetDeploymentHelpers.js")
const fs = require("fs");

const toBigNum = ethers.BigNumber.from
const mintAmountPerTestAccount = toBigNum("100000000000000000000")
 
async function eBTCDeployCore(testnet, ebtcDeployer, governanceAddr, authorityOwner, feeRecipientOwner, collateralAddr) {

    let _expectedAddr = await ebtcDeployer.getFutureEbtcAddresses();

    const authority = await DeploymentHelper.deployGovernor(ebtcDeployer, _expectedAddr, authorityOwner);

    const liquidationLibrary = await DeploymentHelper.deployLiquidationLibrary(ebtcDeployer, _expectedAddr, collateralAddr);

    const cdpManager = await DeploymentHelper.deployCdpManager(ebtcDeployer, _expectedAddr, collateralAddr);
    const borrowerOperations = await DeploymentHelper.deployBorrowerOperations(ebtcDeployer, _expectedAddr, collateralAddr);
    const ebtcToken = await DeploymentHelper.deployEBTCToken(ebtcDeployer, _expectedAddr);

    const priceFeed = testnet? await DeploymentHelper.deployPriceFeedTestnet(ebtcDeployer, _expectedAddr) : 
	                           await DeploymentHelper.deployPriceFeed(ebtcDeployer, _expectedAddr);

    const activePool = await DeploymentHelper.deployActivePool(ebtcDeployer, _expectedAddr, collateralAddr);
    const collSurplusPool = await DeploymentHelper.deployCollSurplusPool(ebtcDeployer, _expectedAddr, collateralAddr);

    const sortedCdps = await DeploymentHelper.deploySortedCdps(ebtcDeployer, _expectedAddr);
    const hintHelpers = await DeploymentHelper.deployHintHelper(ebtcDeployer, _expectedAddr, collateralAddr);
    
    const feeRecipient = await DeploymentHelper.deployFeeRecipient(ebtcDeployer, _expectedAddr, feeRecipientOwner)

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

    // load previous deployment
    let deploymentState = mdh.loadPreviousDeployment()
    let _eBTCDeployerStateName = 'eBTCDeployer';
    let _collateralStateName = 'collateral';

    // flag if testnet or mainnet deployment	
    let _testnet = true;// (chainId.chainId == 5)
	
    // read from config?
    let _governance = _deployer;
    let _authorityOwner = _deployer;
    let _feeRecipientOwner = _deployer;
    let _collateral;
    let _priceFeed;
	
    // get ebtcDeployer
    const ebtcDeployer = await DeploymentHelper.deployEBTCDeployer();
    await saveToDeploymentStateFile(mdh, _eBTCDeployerStateName, deploymentState, ebtcDeployer);
    await verifyContractsViaPlugin(mdh, _eBTCDeployerStateName, deploymentState, []);	
  
    // special preparation for testnet
    _collateral = _testnet? (await DeploymentHelper.deployCollateralTestnet()) : ("TODO");
    await saveToDeploymentStateFile(mdh, _collateralStateName, deploymentState, _collateral);
    await verifyContractsViaPlugin(mdh, _collateralStateName, deploymentState, []);	
  
    // deploy core contracts to blockchain	
    //await eBTCDeployCore(testnet, _governance, _authorityOwner, _feeRecipientOwner, _collateral.address)
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

