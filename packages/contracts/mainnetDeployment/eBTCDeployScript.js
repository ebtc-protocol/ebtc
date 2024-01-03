const DeploymentHelper = require('../utils/deploymentHelpers.js')
const configParamsSepolia = require("./eBTCDeploymentParams.sepolia.js")
const configParamsGoerli = require("./eBTCDeploymentParams.goerli.js")
const configParamsMainnet = require("./eBTCDeploymentParams.mainnet.js")
const configParamsLocal = require("./eBTCDeploymentParams.local.js")
const govSig = require('./governanceSignatures.js')

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
const MULTI_CDP_GETTER_STATE_NAME = 'multiCdpGetter';
const HIGHSEC_TIMELOCK_STATE_NAME = 'highSecTimelock';
const LOWSEC_TIMELOCK_STATE_NAME = 'lowSecTimelock';

const chalk = require('chalk');

let configParams;

class EBTCDeployerScript {
    constructor(useMockCollateral, useMockPriceFeed, mainnetDeploymentHelper, deploymentState, configParams, deployerWallet) {
        this.useMockCollateral = useMockCollateral;
        this.useMockPriceFeed = useMockPriceFeed;
        this.mainnetDeploymentHelper = mainnetDeploymentHelper;
        this.deploymentState = deploymentState;

        this.ebtcDeployer = false;
        this.collateral = false;
        this.collateralAddr = false;
        this.configParams = configParams;

        this.authorityOwner = checkValidItem(configParams.externalAddress['authorityOwner']) ? configParams.externalAddress['authorityOwner'] : deployerWallet.address;
        this.feeRecipientOwner = checkValidItem(configParams.externalAddress['feeRecipientOwner']) ? configParams.externalAddress['feeRecipientOwner'] : deployerWallet.address;
        this.ecosystemMultisig = checkValidItem(configParams.externalAddress['ecosystemMultisig']) ? configParams.externalAddress['ecosystemMultisig'] : deployerWallet.address;
        this.cdpCouncilMultisig = checkValidItem(configParams.externalAddress['cdpCouncilMultisig']) ? configParams.externalAddress['cdpCouncilMultisig'] : deployerWallet.address;
        this.cdpTechOpsMultisig = checkValidItem(configParams.externalAddress['cdpTechOpsMultisig']) ? configParams.externalAddress['cdpTechOpsMultisig'] : deployerWallet.address;
        this.highSecAdmin = checkValidItem(configParams.ADDITIONAL_HIGHSEC_ADMIN) ? configParams.ADDITIONAL_HIGHSEC_ADMIN : deployerWallet.address;
        this.lowSecAdmin = checkValidItem(configParams.ADDITIONAL_LOWSEC_ADMIN) ? configParams.ADDITIONAL_LOWSEC_ADMIN : deployerWallet.address;

        this.highSecDelay = configParams.HIGHSEC_MIN_DELAY; // Deployment should fail if null
        this.lowSecDelay = configParams.LOWSEC_MIN_DELAY; // Deployment should fail if null

        this.collEthCLFeed = checkValidItem(configParams.externalAddress['collEthCLFeed']) ? configParams.externalAddress['collEthCLFeed'] : deployerWallet.address;
        this.ethBtcCLFeed = checkValidItem(configParams.externalAddress['ethBtcCLFeed']) ? configParams.externalAddress['ethBtcCLFeed'] : deployerWallet.address;
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
        let useMockPriceFeed = this.useMockPriceFeed
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
            _deployedState = await DeploymentHelper.deployBorrowerOperations(ebtcDeployer, _expectedAddr, this.feeRecipientOwner, collateralAddr);
        } else if (_stateName == EBTC_TOKEN_STATE_NAME) {
            _deployedState = await DeploymentHelper.deployEBTCToken(ebtcDeployer, _expectedAddr);
        } else if (_stateName == PRICE_FEED_STATE_NAME) {
            _deployedState = useMockPriceFeed ? await DeploymentHelper.deployPriceFeedTestnet(ebtcDeployer, _expectedAddr) :
                await DeploymentHelper.deployPriceFeed(ebtcDeployer, _expectedAddr, this.collEthCLFeed, this.ethBtcCLFeed);
        } else if (_stateName == ACTIVE_POOL_STATE_NAME) {
            _deployedState = await DeploymentHelper.deployActivePool(ebtcDeployer, _expectedAddr, collateralAddr, this.feeRecipientOwner);
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
        } else if (_stateName == MULTI_CDP_GETTER_STATE_NAME) {
            _deployedState = await DeploymentHelper.deployMultiCdpGetter(ebtcDeployer, _expectedAddr);
        } else if (_stateName == HIGHSEC_TIMELOCK_STATE_NAME) {
            let proposers = [this.ecosystemMultisig]
            let executors = [this.ecosystemMultisig]
            _deployedState = await DeploymentHelper.deployTimelock(this.highSecDelay, proposers, executors, this.highSecAdmin);
        } else if (_stateName == LOWSEC_TIMELOCK_STATE_NAME) {
            let proposers = [this.ecosystemMultisig, this.cdpCouncilMultisig, this.cdpTechOpsMultisig]
            let executors = [this.ecosystemMultisig, this.cdpCouncilMultisig, this.cdpTechOpsMultisig]
            _deployedState = await DeploymentHelper.deployTimelock(this.lowSecDelay, proposers, executors, this.lowSecAdmin);
        }
        await this.saveToDeploymentStateFile(mainnetDeploymentHelper, _stateName, deploymentState, _deployedState);
        return _deployedState;
    }

    async loadDeployedState(_stateName) {
        let useMockPriceFeed = this.useMockPriceFeed
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
            let contractName = useMockPriceFeed ? "PriceFeedTestnet" : "PriceFeed";
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
        } else if (_stateName == HIGHSEC_TIMELOCK_STATE_NAME) {
            _deployedState = await (await ethers.getContractFactory("TimelockControllerEnumerable")).attach(deploymentState[HIGHSEC_TIMELOCK_STATE_NAME]["address"])
            console.log('Sanity checking: highSecTimelock.getMinDelay()=' + (await _deployedState.getMinDelay()));
        } else if (_stateName == LOWSEC_TIMELOCK_STATE_NAME) {
            _deployedState = await (await ethers.getContractFactory("TimelockControllerEnumerable")).attach(deploymentState[LOWSEC_TIMELOCK_STATE_NAME]["address"])
            console.log('Sanity checking: lowSecTimelock.getMinDelay()=' + (await _deployedState.getMinDelay()));
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
        console.log(chalk.cyan("[Collateral]"))
        let _checkExistDeployment = checkExistingDeployment(COLLATERAL_STATE_NAME, this.deploymentState);

        if (_checkExistDeployment['_toDeploy'] && this.useMockCollateral) { // mock collateral to be deployed
            _collateral = await this.deployStateViaHelper(COLLATERAL_STATE_NAME, "");
        } else if (this.useMockCollateral) { // mock collateral already deployed
            _collateral = await (await ethers.getContractFactory("CollateralTokenTester")).attach(this.deploymentState[COLLATERAL_STATE_NAME]["address"])
        } else { // mainnet
            _collateral = await ethers.getContractAt("ICollateralToken", configParams.externalAddress[COLLATERAL_STATE_NAME])
            console.log('collateral.getOracle()=' + (await _collateral.getOracle()));
        }

        if (this.useMockCollateral) {
            await this.verifyState(_checkExistDeployment, COLLATERAL_STATE_NAME, this.mainnetDeploymentHelper, this.deploymentState, []);
        }
        this.collateral = _collateral;
        this.collateralAddr = _collateral.address
    }

    async loadOrDeployTimelocks() {
        console.log(chalk.cyan("[HighSecTimelock]"))
        let _constructorArgs = [this.highSecDelay, [this.ecosystemMultisig], [this.ecosystemMultisig], this.highSecAdmin]
        this.highSecTimelock = await this.deployOrLoadState(HIGHSEC_TIMELOCK_STATE_NAME, [], _constructorArgs)

        console.log(chalk.cyan("[LowhSecTimelock]"))
        _constructorArgs = [this.lowSecDelay, [this.ecosystemMultisig, this.cdpCouncilMultisig, this.cdpTechOpsMultisig], [this.ecosystemMultisig, this.cdpCouncilMultisig, this.cdpTechOpsMultisig], this.lowSecAdmin]
        this.lowSecTimelock = await this.deployOrLoadState(LOWSEC_TIMELOCK_STATE_NAME, [], _constructorArgs)
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
        _constructorArgs = [_expectedAddr[2], _expectedAddr[6], _expectedAddr[7], _expectedAddr[4], _expectedAddr[5], _expectedAddr[9], this.feeRecipientOwner, this.collateralAddr];
        let borrowerOperations = await this.deployOrLoadState(BORROWER_OPERATIONS_STATE_NAME, _expectedAddr, _constructorArgs);

        // deploy eBTCToken
        console.log(chalk.cyan("[EBTCToken]"))
        _constructorArgs = [_expectedAddr[2], _expectedAddr[3], _expectedAddr[0]];
        let ebtcToken = await this.deployOrLoadState(EBTC_TOKEN_STATE_NAME, _expectedAddr, _constructorArgs);

        // deploy priceFeed
        console.log(chalk.cyan("[PriceFeed]"))
        _constructorArgs = this.useMockPriceFeed ? [_expectedAddr[0]] : [ethers.constants.AddressZero, _expectedAddr[0], this.collEthCLFeed, this.ethBtcCLFeed];
        let priceFeed = await this.deployOrLoadState(PRICE_FEED_STATE_NAME, _expectedAddr, _constructorArgs);

        // deploy activePool
        console.log(chalk.cyan("[ActivePool]"))
        _constructorArgs = [_expectedAddr[3], _expectedAddr[2], this.collateralAddr, _expectedAddr[7], this.feeRecipientOwner];
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

        // deploy multiCdpGetter
        console.log(chalk.cyan("[MultiCdpGetter]"))
        _constructorArgs = [_expectedAddr[2], _expectedAddr[5]];
        let multiCdpGetter = await this.deployOrLoadState(MULTI_CDP_GETTER_STATE_NAME, _expectedAddr, _constructorArgs);

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
            feeRecipient,
            multiCdpGetter
        }
        return coreContracts;
    }

    async governanceWireUp(coreContracts, configParams, _deployer) {
        console.log(chalk.green("\nStarting governance wiring..."));
        let tx;
        const authority = coreContracts.authority;

        // === Timelocks Configuration === //

        const PROPOSER_ROLE = await this.highSecTimelock.PROPOSER_ROLE();
        const EXECUTOR_ROLE = await this.highSecTimelock.EXECUTOR_ROLE();
        const CANCELLER_ROLE = await this.highSecTimelock.CANCELLER_ROLE();
        const TIMELOCK_ADMIN_ROLE = await this.highSecTimelock.TIMELOCK_ADMIN_ROLE();

        // HIGHSEC TIMELOCK
        // ==========================
        // PROPOSERS: Ecosystem
        // CANCELLERS: Ecosystem
        // EXECUTORS: Ecosystem
        // Admin: Only Timelock
        // Delay: 7 days (mainnet)
        // ==========================

        assert.isTrue(await this.highSecTimelock.getMinDelay() == configParams.HIGHSEC_MIN_DELAY);

        assert.isTrue(await this.highSecTimelock.getRoleMemberCount(PROPOSER_ROLE) == 1);
        assert.isTrue(await this.highSecTimelock.getRoleMemberCount(EXECUTOR_ROLE) == 1);
        assert.isTrue(await this.highSecTimelock.getRoleMemberCount(CANCELLER_ROLE) == 1);

        assert.isTrue(await this.highSecTimelock.hasRole(PROPOSER_ROLE, this.ecosystemMultisig));
        assert.isTrue(await this.highSecTimelock.hasRole(EXECUTOR_ROLE, this.ecosystemMultisig));
        assert.isTrue(await this.highSecTimelock.hasRole(CANCELLER_ROLE, this.ecosystemMultisig));

        // Only after confirming that the Timelock has admin role on itself, we revoke it from the deployer
        assert.isTrue(await this.highSecTimelock.hasRole(TIMELOCK_ADMIN_ROLE, this.highSecTimelock.address));
        if (await this.highSecTimelock.hasRole(TIMELOCK_ADMIN_ROLE, _deployer.address)) {
            tx = await this.highSecTimelock.revokeRole(TIMELOCK_ADMIN_ROLE, _deployer.address);
            await tx.wait();
            console.log("Revoked TIMELOCK_ADMIN_ROLE of deployer on highSecTimelock");
        }
        assert.isFalse(await this.highSecTimelock.hasRole(TIMELOCK_ADMIN_ROLE, _deployer.address));
        assert.isTrue(await this.highSecTimelock.getRoleMemberCount(TIMELOCK_ADMIN_ROLE) == 1);

        // Print out final state for sanity check
        console.log(chalk.cyan("HIGH SEC TIMELOCK CONFIGURATION"))
        await printOutTimelockState(this.highSecTimelock);

        // LOWSEC TIMELOCK
        // ==========================
        // PROPOSERS: Ecosystem, CDP Council, CDP TechOps
        // CANCELLERS: Ecosystem
        // EXECUTORS: Ecosystem, CDP Council, CDP TechOps
        // Admin: Only Timelock
        // Delay: 2 days (mainnet)
        // ==========================

        assert.isTrue(await this.lowSecTimelock.getMinDelay() == configParams.LOWSEC_MIN_DELAY);

        assert.isTrue(await this.lowSecTimelock.getRoleMemberCount(PROPOSER_ROLE) == 3);
        assert.isTrue(await this.lowSecTimelock.getRoleMemberCount(EXECUTOR_ROLE) == 3);

        assert.isTrue(await this.lowSecTimelock.hasRole(PROPOSER_ROLE, this.ecosystemMultisig));
        assert.isTrue(await this.lowSecTimelock.hasRole(PROPOSER_ROLE, this.cdpCouncilMultisig));
        assert.isTrue(await this.lowSecTimelock.hasRole(PROPOSER_ROLE, this.cdpTechOpsMultisig));
        assert.isTrue(await this.lowSecTimelock.hasRole(EXECUTOR_ROLE, this.ecosystemMultisig));
        assert.isTrue(await this.lowSecTimelock.hasRole(EXECUTOR_ROLE, this.cdpCouncilMultisig));
        assert.isTrue(await this.lowSecTimelock.hasRole(EXECUTOR_ROLE, this.cdpTechOpsMultisig));
        assert.isTrue(await this.lowSecTimelock.hasRole(CANCELLER_ROLE, this.ecosystemMultisig));

        // We remove the canceller from the Council and TechOps
        if (await this.lowSecTimelock.hasRole(CANCELLER_ROLE, this.cdpCouncilMultisig)) {
            tx = await this.lowSecTimelock.revokeRole(CANCELLER_ROLE, this.cdpCouncilMultisig);
            await tx.wait();
            console.log("Revoked CANCELLER_ROLE of cdpCouncilMultisig on lowSecTimelock");
        }
        assert.isFalse(await this.lowSecTimelock.hasRole(CANCELLER_ROLE, this.cdpCouncilMultisig));
        if (await this.lowSecTimelock.hasRole(CANCELLER_ROLE, this.cdpTechOpsMultisig)) {
            tx = await this.lowSecTimelock.revokeRole(CANCELLER_ROLE, this.cdpTechOpsMultisig);
            await tx.wait();
            console.log("Revoked CANCELLER_ROLE of cdpTechOpsMultisig on lowSecTimelock");
        }
        assert.isFalse(await this.lowSecTimelock.hasRole(CANCELLER_ROLE, this.cdpTechOpsMultisig));
        assert.isTrue(await this.lowSecTimelock.getRoleMemberCount(CANCELLER_ROLE) == 1); // Only ecosystem should be canceller

        // Only after confirming that the Timelock has admin role on itself, we revoke it from the deployer
        assert.isTrue(await this.lowSecTimelock.hasRole(TIMELOCK_ADMIN_ROLE, this.lowSecTimelock.address));
        if (await this.lowSecTimelock.hasRole(TIMELOCK_ADMIN_ROLE, _deployer.address)) {
            tx = await this.lowSecTimelock.revokeRole(TIMELOCK_ADMIN_ROLE, _deployer.address);
            await tx.wait();
            console.log("Revoked TIMELOCK_ADMIN_ROLE of deployer on lowSecTimelock");
        }
        assert.isFalse(await this.lowSecTimelock.hasRole(TIMELOCK_ADMIN_ROLE, _deployer.address));
        assert.isTrue(await this.lowSecTimelock.getRoleMemberCount(TIMELOCK_ADMIN_ROLE) == 1); // Only timelock should be admin

        // Print out final state for sanity check
        console.log(chalk.cyan("LOW SEC TIMELOCK CONFIGURATION"))
        await printOutTimelockState(this.lowSecTimelock);

        // === CDP Authority Configuration === //


        console.log("\nCDP Authority Configuration...\n");

        console.log(chalk.cyan("\nSetting up roles\n"));

        const roleNumberToRoleNameMap = {
            0: "Admin",
            1: "eBTCToken: mint",
            2: "eBTCToken: burn",
            3: "CDPManager: all",
            4: "PriceFeed: setFallbackCaller",
            5: "BorrowerOperations+ActivePool: setFeeBps, setFlashLoansPaused, setFeeRecipientAddress",
            6: "ActivePool: sweep tokens & claim fee recipient coll",
        };

        // Get the list of role numbers
        const roleNumbers = Object.keys(roleNumberToRoleNameMap);

        // Iterate over the role numbers and set the role names
        for (const roleNumber of roleNumbers) {
            const roleName = roleNumberToRoleNameMap[roleNumber];

            // Get the current role name
            const currentRoleName = await authority.getRoleName(roleNumber);

            // If the current role name is not the same as the expected role name, set the role name
            let tx;
            if (currentRoleName != roleName) {
                console.log(`Setting role `, + roleNumber + ` as ` + roleName)
                tx = await authority.setRoleName(roleNumber, roleName);
                await tx.wait();
            }
        }

        // Asign role capabilities
        console.log(chalk.cyan("\nSetting role capabilities\n"));

        const roleNumberToRoleCapabilityMap = {
            0: [
                { target: coreContracts.authority, signature: govSig.SET_ROLE_NAME_SIG },
                { target: coreContracts.authority, signature: govSig.SET_USER_ROLE_SIG },
                { target: coreContracts.authority, signature: govSig.SET_ROLE_CAPABILITY_SIG },
                { target: coreContracts.authority, signature: govSig.SET_PUBLIC_CAPABILITY_SIG },
                { target: coreContracts.authority, signature: govSig.BURN_CAPABILITY_SIG },
                { target: coreContracts.authority, signature: govSig.TRANSFER_OWNERSHIP_SIG },
                { target: coreContracts.authority, signature: govSig.SET_AUTHORITY_SIG },
            ],
            1: [
                { target: coreContracts.ebtcToken, signature: govSig.MINT_SIG },
            ],
            2: [
                { target: coreContracts.ebtcToken, signature: govSig.BURN_SIG },
                { target: coreContracts.ebtcToken, signature: govSig.BURN2_SIG },
            ],
            3: [
                { target: coreContracts.cdpManager, signature: govSig.SET_STAKING_REWARD_SPLIT_SIG },
                { target: coreContracts.cdpManager, signature: govSig.SET_REDEMPTION_FEE_FLOOR_SIG },
                { target: coreContracts.cdpManager, signature: govSig.SET_MINUTE_DECAY_FACTOR_SIG },
                { target: coreContracts.cdpManager, signature: govSig.SET_BETA_SIG },
                { target: coreContracts.cdpManager, signature: govSig.SET_REDEMPTIONS_PAUSED_SIG },
                { target: coreContracts.cdpManager, signature: govSig.SET_GRACE_PERIOD_SIG },
            ],
            4: [
                { target: coreContracts.priceFeed, signature: govSig.SET_FALLBACK_CALLER_SIG },
            ],
            5: [
                { target: coreContracts.borrowerOperations, signature: govSig.SET_FEE_BPS_SIG },
                { target: coreContracts.borrowerOperations, signature: govSig.SET_FLASH_LOANS_PAUSED_SIG },
                { target: coreContracts.borrowerOperations, signature: govSig.SET_FEE_RECIPIENT_ADDRESS_SIG },
                { target: coreContracts.activePool, signature: govSig.SET_FEE_BPS_SIG },
                { target: coreContracts.activePool, signature: govSig.SET_FLASH_LOANS_PAUSED_SIG },
                { target: coreContracts.activePool, signature: govSig.SET_FEE_RECIPIENT_ADDRESS_SIG },
            ],
            6: [
                { target: coreContracts.activePool, signature: govSig.SWEEP_TOKEN_SIG },
                { target: coreContracts.activePool, signature: govSig.CLAIM_FEE_RECIPIENT_COLL_SIG },
                { target: coreContracts.collSurplusPool, signature: govSig.SWEEP_TOKEN_SIG },
            ],
        };

        // Iterate over the role numbers and set the role capabilities
        for (const roleNumber of Object.keys(roleNumberToRoleCapabilityMap)) {
            const roleCapabilities = roleNumberToRoleCapabilityMap[roleNumber];
            
            // Iterate over the role capabilities and set the capability if it is not already set
            for (const roleCapability of roleCapabilities) {
            const { target, signature } = roleCapability;
                if (!await authority.doesRoleHaveCapability(roleNumber, target.address, signature)) {
                    console.log(`Assigning `, + signature + ` on ` + target.address + ` to role ` + roleNumber)
                    tx = await authority.setRoleCapability(roleNumber, target.address, signature, true);
                    await tx.wait();
                }
            }
        }

        console.log(chalk.cyan("\nAssigning roles to users\n"));

        // Assign roles to Timelocks
        // HighSec timelock should have access to all functions except for minting/burning
        // LowSec timelock should have access to all functions except for minting/burning and authority admin
        // Fee recipient should be able to claim collateral and sweep
        const userAddressToRoleNumberMap = {
            [this.highSecTimelock.address]: [0, 3, 4, 5, 6],
            [this.lowSecTimelock.address]: [3, 4, 5, 6],
            [this.feeRecipientOwner]: [6],
        };
        
        // Iterate over the user addresses and set the role numbers
        for (const userAddress of Object.keys(userAddressToRoleNumberMap)) {
            const roleNumbers = userAddressToRoleNumberMap[userAddress];
        
            // Iterate over the role numbers and set the role if it is not already set
            for (const roleNumber of roleNumbers) {
                if (await authority.doesUserHaveRole(userAddress, roleNumber) != true) {
                    console.log(`Assigning `, + roleNumber + ` to user ` + userAddress)
                    tx = await authority.setUserRole(userAddress, roleNumber, true);
                    await tx.wait();
                }
            }
        }

        // console.log(chalk.cyan("\nTransfer ownership to HighSecTimelock\n"));

        // // Once manual wiring is performed, authority ownership is transferred to the HighSec Timelock
        // if (await authority.owner() != this.highSecTimelock.address) {
        //     tx = await authority.transferOwnership(this.highSecTimelock.address);
        //     await tx.wait();
        //     assert.isTrue(await authority.owner() == this.highSecTimelock.address);
        // }

        console.log("Governance wiring finalized...");
    }

    async verifyContractsViaPlugin(mainnetDeploymentHelper, name, deploymentState, constructorArgs) {
        console.log(this.configParams)
        if (!this.configParams.VERIFY_ETHERSCAN) {
            console.log('Verification disabled by config\n')
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
    // Flag if useMockCollateral and useMockPriceFeed 
    // also specify which parameter config file to use
    let useMockCollateral = true;
    let useMockPriceFeed = true;

    // let configParams = configParamsLocal;
    let configParams = configParamsSepolia;
    // let configParams = configParamsMainnet;
    // let configParams = configParamsGoerli;

    // flag override: always use mock price feed on local as no feed will exist
    if (configParams == configParamsLocal) {
        useMockPriceFeed = true;
    }

    // flag override: always use mock collateral if not on mainnet as collateral will not exist
    if (configParams != configParamsMainnet) {
        useMockCollateral = true;
    }

    const date = new Date()
    console.log(date.toUTCString())

    // connect deployer which should be the one set in your hardhat.config.js [network] section
    const deployerWallet = (await ethers.getSigners())[0]
    let _deployer = deployerWallet;

    // Log deployer properties and basic chain stats
    console.log(`deployer EOA: ${_deployer.address}`)
    let deployerETHBalance = await ethers.provider.getBalance(_deployer.address)
    console.log(`deployer EOA ETH Balance before: ${deployerETHBalance}`)

    let latestBlock = await ethers.provider.getBlockNumber()
    const chainId = await ethers.provider.getNetwork()
    console.log('ChainId=' + chainId.chainId + ',block number=' + latestBlock)
    console.log('deploy with ' + (useMockCollateral ? 'mock collateral & ' : ' existing collateral & ') + (useMockPriceFeed ? 'mock feed' : 'original feed'));

    const mdh = new MainnetDeploymentHelper(configParams, _deployer)

    // read from config
    let _gasPrice = configParams.GAS_PRICE;
    let _deployWaitMilliSeonds = configParams.DEPLOY_WAIT;

    // load deployment state
    let deploymentState = mdh.loadPreviousDeployment();
    if (configParams == configParamsLocal) {
        deploymentState = {};// always redeploy if localhost
    }
    await DeploymentHelper.setDeployGasPrice(_gasPrice);
    await DeploymentHelper.setDeployWait(_deployWaitMilliSeonds);

    let eds = new EBTCDeployerScript(useMockCollateral, useMockPriceFeed, mdh, deploymentState, configParams, _deployer);
    if (configParams == configParamsLocal) {
        eds.ecosystemMultisig = (await ethers.getSigners())[1].address;
        eds.cdpCouncilMultisig = (await ethers.getSigners())[2].address;
        eds.cdpTechOpsMultisig = (await ethers.getSigners())[3].address;
        eds.feeRecipientOwner = (await ethers.getSigners())[4].address;
    }

    console.log(`\nEcosystem Multisig: ${eds.ecosystemMultisig}`)
    console.log(`CDP Council Multisig: ${eds.cdpCouncilMultisig}`)
    console.log(`CDP TechOps Multisig: ${eds.cdpTechOpsMultisig}`)
    console.log(`Fee Recipient Multisig: ${eds.feeRecipientOwner}`)

    await eds.loadOrDeployEBTCDeployer();
    await eds.loadOrDeployCollateral();
    await eds.loadOrDeployTimelocks();
    let coreContracts = await eds.eBTCDeployCore();
    await eds.governanceWireUp(coreContracts, configParams, _deployer);
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

async function printOutTimelockState(timelock) {
    console.log("\nPROPOSER_ROLE");
    for (i = 0; i < await timelock.getRoleMemberCount(await timelock.PROPOSER_ROLE()); i++) {
        console.log(await timelock.getRoleMember(await timelock.PROPOSER_ROLE(), i));
    }
    console.log("CANCELLER_ROLE");
    for (i = 0; i < await timelock.getRoleMemberCount(await timelock.CANCELLER_ROLE()); i++) {
        console.log(await timelock.getRoleMember(await timelock.CANCELLER_ROLE(), i));
    }
    console.log("EXECUTOR_ROLE");
    for (i = 0; i < await timelock.getRoleMemberCount(await timelock.EXECUTOR_ROLE()); i++) {
        console.log(await timelock.getRoleMember(await timelock.EXECUTOR_ROLE(), i));
    }
    console.log("TIMELOCK_ADMIN_ROLE");
    for (i = 0; i < await timelock.getRoleMemberCount(await timelock.TIMELOCK_ADMIN_ROLE()); i++) {
        console.log(await timelock.getRoleMember(await timelock.TIMELOCK_ADMIN_ROLE(), i));
    }
    console.log("MIN DELAY", await timelock.getMinDelay(), "\n");
}

// cd <eBTCRoot>/packages/contracts
// you may need to clean folder <./artifacts> to get a fresh new running 
// npx hardhat run ./mainnetDeployment/eBTCDeployScript.js --network <goerli|mainnet|localhost>
// assuming you have above network configurations in hardhat.config.js
main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });

