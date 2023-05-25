const DeploymentHelper = require('../utils/deploymentHelpers.js')
const configParamsGoerli = require("./eBTCDeploymentParams.goerli.js")
const configParamsMainnet = require("./eBTCDeploymentParams.mainnet.js")

const { TestHelper: th, TimeValues: timeVals } = require("../utils/testHelpers.js")
const MainnetDeploymentHelper = require("../utils/mainnetDeploymentHelpers.js")

const GOVERNOR_STATE_NAME = 'authority';
const LIQUIDATION_LIBRARY_STATE_NAME = 'liquidationLibrary';
const CDP_MANAGER_STATE_NAME = 'cdpManager';
const BORROWER_OPERATIONS_STATE_NAME = 'borrowerOperations';
const EBTC_TOKEN_STATE_NAME = 'eBTCToken';
const PRICE_FEED_STATE_NAME = 'priceFeed';
const ACTIVE_POOL_STATE_NAME = 'activePool';
const COLL_SURPLUS_POOL_STATE_NAME = 'collSurplusPool';
const SORTED_CDPS_STATE_NAME = 'sortedCdps';
const HINT_HELPERS_STATE_NAME = 'hintHelpers';
const FEE_RECIPIENT_STATE_NAME = 'feeRecipient';
const EBTC_DEPLOYER_STATE_NAME = 'eBTCDeployer';
const COLLATERAL_STATE_NAME = 'collateral';

const chalk = require('chalk');

let configParams;

class EBTCDeployerScript {
    constructor(testnet, mainnetDeploymentHelper, deploymentState, authorityOwner, feeRecipientOwner) {
        this.testnet = testnet;
        this.mainnetDeploymentHelper = mainnetDeploymentHelper;
        this.deploymentState = deploymentState;
        this.authorityOwner = authorityOwner;
        this.feeRecipientOwner = feeRecipientOwner;

        this.ebtcDeployer = false;
        this.collateral = false;
        this.collateralAddr = false;
    }

    async verifyState(_checkExistDeployment, _stateName, _constructorArgs) {
        let mainnetDeploymentHelper = this.mainnetDeploymentHelper;
        let deploymentState = this.deploymentState;

        if (_checkExistDeployment['_toVerify']) {
            console.log('verifying ' + _stateName + '...');
            await this.verifyContractsViaPlugin(mainnetDeploymentHelper, _stateName, deploymentState, _constructorArgs);
        }
    }

    async deployStateViaHelper(_stateName, _expectedAddr) {
        let testnet = this.testnet
        let mainnetDeploymentHelper = this.mainnetDeploymentHelper
        let deploymentState = this.deploymentState
        let ebtcDeployer = this.ebtcDeployer
        let authorityOwner = this.authorityOwner
        let feeRecipientOwner = this.feeRecipientOwner
        let collateralAddr = this.collateralAddr

        let _deployedState;
        console.log('deploying ' + _stateName + '...');
        if (_stateName == GOVERNOR_STATE_NAME) {
            _deployedState = await DeploymentHelper.deployGovernor(ebtcDeployer, _expectedAddr, authorityOwner);
        } else if (_stateName == LIQUIDATION_LIBRARY_STATE_NAME) {
            _deployedState = await DeploymentHelper.deployLiquidationLibrary(ebtcDeployer, _expectedAddr, collateralAddr);
        } else if (_stateName == CDP_MANAGER_STATE_NAME) {
            _deployedState = await DeploymentHelper.deployCdpManager(ebtcDeployer, _expectedAddr, collateralAddr);
        } else if (_stateName == BORROWER_OPERATIONS_STATE_NAME) {
            _deployedState = await DeploymentHelper.deployBorrowerOperations(ebtcDeployer, _expectedAddr, collateralAddr);
        } else if (_stateName == EBTC_TOKEN_STATE_NAME) {
            _deployedState = await DeploymentHelper.deployEBTCToken(ebtcDeployer, _expectedAddr);
        } else if (_stateName == PRICE_FEED_STATE_NAME) {
            _deployedState = testnet ? await DeploymentHelper.deployPriceFeedTestnet(ebtcDeployer, _expectedAddr) :
                await DeploymentHelper.deployPriceFeed(ebtcDeployer, _expectedAddr);
        } else if (_stateName == ACTIVE_POOL_STATE_NAME) {
            _deployedState = await DeploymentHelper.deployActivePool(ebtcDeployer, _expectedAddr, collateralAddr);
        } else if (_stateName == COLL_SURPLUS_POOL_STATE_NAME) {
            _deployedState = await DeploymentHelper.deployCollSurplusPool(ebtcDeployer, _expectedAddr, collateralAddr);
        } else if (_stateName == SORTED_CDPS_STATE_NAME) {
            _deployedState = await DeploymentHelper.deploySortedCdps(ebtcDeployer, _expectedAddr);
        } else if (_stateName == HINT_HELPERS_STATE_NAME) {
            _deployedState = await DeploymentHelper.deployHintHelper(ebtcDeployer, _expectedAddr, collateralAddr);
        } else if (_stateName == FEE_RECIPIENT_STATE_NAME) {
            _deployedState = await DeploymentHelper.deployFeeRecipient(ebtcDeployer, _expectedAddr, feeRecipientOwner)
        } else if (_stateName == EBTC_DEPLOYER_STATE_NAME) {
            _deployedState = await DeploymentHelper.deployEBTCDeployer();
        } else if (_stateName == COLLATERAL_STATE_NAME) {
            _deployedState = await DeploymentHelper.deployCollateralTestnet();
        }
        await this.saveToDeploymentStateFile(mainnetDeploymentHelper, _stateName, deploymentState, _deployedState);
        return _deployedState;
    }

    async loadDeployedState(_stateName) {
        let testnet = this.testnet
        let deploymentState = this.deploymentState
        let _deployedState;
        if (_stateName == GOVERNOR_STATE_NAME) {
            _deployedState = await (await ethers.getContractFactory("Governor")).attach(deploymentState[_stateName]["address"])
            console.log('Sanity checking: authority.owner()=' + (await _deployedState.owner()));
        } else if (_stateName == LIQUIDATION_LIBRARY_STATE_NAME) {
            _deployedState = await (await ethers.getContractFactory("LiquidationLibrary")).attach(deploymentState[_stateName]["address"])
            console.log('Sanity checking: liquidationLibrary.LIQUIDATOR_REWARD()=' + (await _deployedState.LIQUIDATOR_REWARD()));
        } else if (_stateName == CDP_MANAGER_STATE_NAME) {
            _deployedState = await (await ethers.getContractFactory("CdpManager")).attach(deploymentState[_stateName]["address"])
            console.log('Sanity checking: cdpManager.authority()=' + (await _deployedState.authority()));
        } else if (_stateName == BORROWER_OPERATIONS_STATE_NAME) {
            _deployedState = await (await ethers.getContractFactory("BorrowerOperations")).attach(deploymentState[_stateName]["address"])
            console.log('Sanity checking: borrowerOperations.authority()=' + (await _deployedState.authority()));
        } else if (_stateName == EBTC_TOKEN_STATE_NAME) {
            _deployedState = await (await ethers.getContractFactory("EBTCToken")).attach(deploymentState[_stateName]["address"])
            console.log('Sanity checking: ebtcToken.authority()=' + (await _deployedState.authority()));
        } else if (_stateName == PRICE_FEED_STATE_NAME) {
            let contractName = testnet ? "PriceFeedTestnet" : "PriceFeed";
            _deployedState = await (await ethers.getContractFactory(contractName)).attach(deploymentState[_stateName]["address"])
            console.log('Sanity checking: priceFeed.authority()=' + (await _deployedState.authority()));
        } else if (_stateName == ACTIVE_POOL_STATE_NAME) {
            _deployedState = await (await ethers.getContractFactory("ActivePool")).attach(deploymentState[_stateName]["address"])
            console.log('Sanity checking: activePool.authority()=' + (await _deployedState.authority()));
        } else if (_stateName == COLL_SURPLUS_POOL_STATE_NAME) {
            _deployedState = await (await ethers.getContractFactory("CollSurplusPool")).attach(deploymentState[_stateName]["address"])
            console.log('Sanity checking: collSurplusPool.authority()=' + (await _deployedState.authority()));
        } else if (_stateName == SORTED_CDPS_STATE_NAME) {
            _deployedState = await (await ethers.getContractFactory("SortedCdps")).attach(deploymentState[_stateName]["address"])
            console.log('Sanity checking: sortedCdps.NAME()=' + (await _deployedState.NAME()));
        } else if (_stateName == HINT_HELPERS_STATE_NAME) {
            _deployedState = await (await ethers.getContractFactory("HintHelpers")).attach(deploymentState[_stateName]["address"])
            console.log('Sanity checking: hintHelpers.NAME()=' + (await _deployedState.NAME()));
        } else if (_stateName == FEE_RECIPIENT_STATE_NAME) {
            _deployedState = await (await ethers.getContractFactory("FeeRecipient")).attach(deploymentState[_stateName]["address"])
            console.log('Sanity checking: feeRecipient.NAME()=' + (await _deployedState.NAME()));
        } else if (_stateName == EBTC_DEPLOYER_STATE_NAME) {
            _deployedState = await (await ethers.getContractFactory("EBTCDeployerTester")).attach(deploymentState[EBTC_DEPLOYER_STATE_NAME]["address"])
        }
        return _deployedState;
    }

    async deployOrLoadState(_stateName, _expectedAddr, _constructorArgs) {
        let _checkExistDeployment = checkExistingDeployment(_stateName, this.deploymentState);
        let _deployedState;
        if (_checkExistDeployment['_toDeploy']) {
            _deployedState = await this.deployStateViaHelper(_stateName, _expectedAddr);
        } else {
            _deployedState = await this.loadDeployedState(_stateName)
        }
        await this.verifyState(_checkExistDeployment, _stateName, _constructorArgs);
        return _deployedState;
    }

    async loadOrDeployEBTCDeployer() {
        console.log(chalk.cyan("[EBTCDeployer]"))
        this.ebtcDeployer = await this.deployOrLoadState(EBTC_DEPLOYER_STATE_NAME, [])
    }

    async loadOrDeployCollateral() {
        // contract dependencies
        let _collateral;

        // get collateral
        let _checkExistDeployment = checkExistingDeployment(COLLATERAL_STATE_NAME, this.deploymentState);

        console.log(chalk.cyan("[Collateral]"))
        if (_checkExistDeployment['_toDeploy'] && this.testnet) { // testnet, not deployed
            _collateral = await this.deployStateViaHelper(COLLATERAL_STATE_NAME, "");
        } else if (this.testnet) { // testnet, already deployed
            _collateral = await (await ethers.getContractFactory("CollateralTokenTester")).attach(this.deploymentState[COLLATERAL_STATE_NAME]["address"])
        } else { // mainnet
            _collateral = await ethers.getContractAt("ICollateralToken", configParams.externalAddress[COLLATERAL_STATE_NAME])
            console.log('collateral.getOracle()=' + (await _collateral.getOracle()));
        }

        if (this.testnet) {
            await this.verifyState(_checkExistDeployment, COLLATERAL_STATE_NAME, this.mainnetDeploymentHelper, this.deploymentState, []);
        }
        this.collateral = _collateral;
        this.collateralAddr = _collateral.address
    }

    async eBTCDeployCore() {

        let _expectedAddr = await this.ebtcDeployer.getFutureEbtcAddresses();

        // deploy authority(Governor)
        console.log(chalk.cyan("[Authority]"))
        let _constructorArgs = [this.authorityOwner];
        let authority = await this.deployOrLoadState(GOVERNOR_STATE_NAME, _expectedAddr, _constructorArgs);

        // deploy liquidationLibrary
        console.log(chalk.cyan("[LiquidationLibrary]"))
        _constructorArgs = [_expectedAddr[3], _expectedAddr[7], _expectedAddr[9], _expectedAddr[5], _expectedAddr[6], _expectedAddr[4], this.collateralAddr];
        let liquidationLibrary = await this.deployOrLoadState(LIQUIDATION_LIBRARY_STATE_NAME, _expectedAddr, _constructorArgs);

        // deploy cdpManager
        console.log(chalk.cyan("[CDPManager]"))
        _constructorArgs = [_expectedAddr[1], _expectedAddr[0], _expectedAddr[3], _expectedAddr[7], _expectedAddr[9], _expectedAddr[5], _expectedAddr[6], _expectedAddr[4], this.collateralAddr];
        let cdpManager = await this.deployOrLoadState(CDP_MANAGER_STATE_NAME, _expectedAddr, _constructorArgs);

        // deploy borrowerOperations
        console.log(chalk.cyan("[BorrowerOperations]"))
        _constructorArgs = [_expectedAddr[2], _expectedAddr[6], _expectedAddr[7], _expectedAddr[4], _expectedAddr[5], _expectedAddr[9], _expectedAddr[10], this.collateralAddr];
        let borrowerOperations = await this.deployOrLoadState(BORROWER_OPERATIONS_STATE_NAME, _expectedAddr, _constructorArgs);

        // deploy eBTCToken
        console.log(chalk.cyan("[EBTCToken]"))
        _constructorArgs = [_expectedAddr[2], _expectedAddr[3], _expectedAddr[0]];
        let ebtcToken = await this.deployOrLoadState(EBTC_TOKEN_STATE_NAME, _expectedAddr, _constructorArgs);

        // deploy priceFeed
        console.log(chalk.cyan("[PriceFeed]"))
        _constructorArgs = this.testnet ? [_expectedAddr[0]] : [ethers.constants.AddressZero, _expectedAddr[0]];
        let priceFeed = await this.deployOrLoadState(PRICE_FEED_STATE_NAME, _expectedAddr, _constructorArgs);

        // deploy activePool
        console.log(chalk.cyan("[ActivePool]"))
        _constructorArgs = [_expectedAddr[3], _expectedAddr[2], this.collateralAddr, _expectedAddr[7], _expectedAddr[10]];
        let activePool = await this.deployOrLoadState(ACTIVE_POOL_STATE_NAME, _expectedAddr, _constructorArgs);

        // deploy collSurplusPool
        console.log(chalk.cyan("[CollSurplusPool]"))
        _constructorArgs = [_expectedAddr[3], _expectedAddr[2], _expectedAddr[6], this.collateralAddr];
        let collSurplusPool = await this.deployOrLoadState(COLL_SURPLUS_POOL_STATE_NAME, _expectedAddr, _constructorArgs);

        // deploy sortedCdps
        console.log(chalk.cyan("[SortedCdps]"))
        _constructorArgs = [0, _expectedAddr[2], _expectedAddr[3]];
        let sortedCdps = await this.deployOrLoadState(SORTED_CDPS_STATE_NAME, _expectedAddr, _constructorArgs);

        // deploy hintHelpers
        console.log(chalk.cyan("[HintHelpers]"))
        _constructorArgs = [_expectedAddr[5], _expectedAddr[2], this.collateralAddr, _expectedAddr[6], _expectedAddr[4]];
        let hintHelpers = await this.deployOrLoadState(HINT_HELPERS_STATE_NAME, _expectedAddr, _constructorArgs);

        // deploy feeRecipient
        console.log(chalk.cyan("[FeeRecipient]"))
        _constructorArgs = [this.feeRecipientOwner, _expectedAddr[1]];
        let feeRecipient = await this.deployOrLoadState(FEE_RECIPIENT_STATE_NAME, _expectedAddr, _constructorArgs);

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

    async verifyContractsViaPlugin(mainnetDeploymentHelper, name, deploymentState, constructorArgs) {
        if (!configParams.ETHERSCAN_BASE_URL) {
            console.log('No Etherscan Url defined, skipping verification\n')
        } else {
            await mainnetDeploymentHelper.verifyContract(name, deploymentState, constructorArgs)
            if (!checkValidItem(deploymentState[name]["verification"])) {
                console.log('error verification for ' + name + ", quit deployment...")
                process.exit(0);
            }
        }
    }

    async saveToDeploymentStateFile(mainnetDeploymentHelper, name, deploymentState, contract) {
        deploymentState[name] = {
            address: contract.address
        }
        console.log('Deployed ' + chalk.yellow(name) + ' at ' + chalk.blue(deploymentState[name]["address"]) + '\n');

        mainnetDeploymentHelper.saveDeployment(deploymentState)
    }
}

async function main() {
    // Flag if testnet or mainnet deployment:
    // To simulate mainnet deployment on testnet for gas-saving,
    // simply set it to "false" but still run with "--network goerli"	
    let _testnet = true;

    const date = new Date()
    console.log(date.toUTCString())

    // connect deployer which should be the one set in your hardhat.config.js [network] section
    const deployerWallet = (await ethers.getSigners())[0]
    let _deployer = deployerWallet;

    // Log deployer properties and basic chain stats
    console.log(`deployer address: ${_deployer.address}`)
    let deployerETHBalance = await ethers.provider.getBalance(_deployer.address)
    console.log(`deployerETHBalance before: ${deployerETHBalance}`)

    let latestBlock = await ethers.provider.getBlockNumber()
    console.log('block number:', latestBlock)
    const chainId = await ethers.provider.getNetwork()
    console.log('ChainId:', chainId.chainId)
    
    configParams = _testnet ? configParamsGoerli : configParamsMainnet;
    console.log('deploy to ' + (_testnet ? 'testnet(goerli)' : (chainId.chainId == 5 ? 'mainnet (simulate with goerli)' : 'mainnet')));

    const mdh = new MainnetDeploymentHelper(configParams, _deployer)
    
    // read from config
    let _authorityOwner = checkValidItem(configParams.externalAddress['authorityOwner']) ? configParams.externalAddress['authorityOwner'] : _deployer.address;
    let _feeRecipientOwner = checkValidItem(configParams.externalAddress['feeRecipientOwner']) ? configParams.externalAddress['feeRecipientOwner'] : _deployer.address;
    let _gasPrice = configParams.GAS_PRICE;
    let _deployWaitMilliSeonds = configParams.DEPLOY_WAIT;

    // load deployment state
    let deploymentState = mdh.loadPreviousDeployment();
    await DeploymentHelper.setDeployGasPrice(_gasPrice);
    await DeploymentHelper.setDeployWait(_deployWaitMilliSeonds);

    let eds = new EBTCDeployerScript(_testnet, mdh, deploymentState, _authorityOwner, _feeRecipientOwner)
    await eds.loadOrDeployEBTCDeployer();
    await eds.loadOrDeployCollateral();
    await eds.eBTCDeployCore();
}

function checkExistingDeployment(stateName, deploymentState) {

    let _checkExistDeployment = { '_toDeploy': true, '_toVerify': true };
    let _deployedState = deploymentState[stateName];
    //console.log('_deployedState for ' + stateName + '=' + JSON.stringify(_deployedState));

    if (checkValidItem(_deployedState)) {
        let _deployedStateAddr = _deployedState["address"];
        if (checkValidItem(_deployedStateAddr)) {
            console.log(chalk.yellow(stateName) + " is already deployed at " + chalk.blue(_deployedStateAddr));
            _checkExistDeployment['_toDeploy'] = false;
        }

        let _deployedStateVerification = _deployedState["verification"];
        if (checkValidItem(_deployedStateVerification)) {
            console.log(chalk.yellow(stateName) + " is already verified: " + _deployedStateVerification);
            _checkExistDeployment['_toVerify'] = false;
        }
    }
    return _checkExistDeployment;
}

function checkValidItem(item) {
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

