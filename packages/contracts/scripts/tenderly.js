// npx hardhat run .\scripts\tenderly.js --network tenderly
const hre = require('hardhat');
const ethers = hre.ethers;
const utils = hre.ethers.utils;
const BalancerVaultABI = require('./BalancerVault.json');
const ERC20ABI = require('./ERC20.json');
const BorrowerOperationsABI = require('./BorrowerOperations.json');
const ComposableStablePoolABI = require('./ComposableStablePool.json');
const ComposableStablePoolFactoryABI = require('./ComposableStablePoolFactory.json');

// stETH
const COLLATERAL = '0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84';
const COLL_ETH_ORACLE = '0x86392dc19c0b719886221c78ab11eb8cf5c52812';
const ETH_BTC_ORACLE = '0xAc559F25B1619171CbC396a50854A3240b6A4e99';
const GOVERNANCE = '0xB65cef03b9B89f99517643226d76e286ee999e77';
const WBTC = '0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599';
const BALANCER_VAULT = '0xBA12222222228d8Ba445958a75a0704d566BF2C8';
const COMPOSABLE_STABLE_POOL_FACTORY = '0xDB8d758BCb971e482B2C45f7F8a7740283A1bd3A';
const AAVE_FLASH_LENDER = '0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9';

async function deployAndVerify(deployer, contractName, salt, deployedAddress, args) {
    const factory = await ethers.getContractFactory(contractName);
    const creationCode = factory.bytecode;

    const op = await deployer.deploy(
        salt, utils.solidityPack(['bytes','bytes'], [creationCode, args])
    );

    await op.wait()

    await hre.tenderly.verify({
        address: deployedAddress,
        name: contractName
    });

    console.log('Deployed ' + contractName);
}

async function deployMockOracle(realOracle) {
    const factory = await ethers.getContractFactory('TenderlyAggregator');
    const oracle = await factory.deploy(realOracle);
    await oracle.deployed();
    await hre.tenderly.verify({
        address: oracle.address,
        name: 'TenderlyAggregator'
    });
    return oracle;
}

async function deployEbtc(ebtcDeployer) {
    const collEthOracle = await deployMockOracle(COLL_ETH_ORACLE);
    const ethBtcOracle = await deployMockOracle(ETH_BTC_ORACLE);

    // Deploy Governor
    await deployAndVerify(
        ebtcDeployer, 
        'Governor', 
        await ebtcDeployer.AUTHORITY(), 
        addresses.authorityAddress, 
        utils.defaultAbiCoder.encode(['address'], [ebtcDeployer.address])
    );

    // Deploy LiquidationLibrary
    await deployAndVerify(
        ebtcDeployer, 
        'LiquidationLibrary', 
        await ebtcDeployer.LIQUIDATION_LIBRARY(), 
        addresses.liquidationLibraryAddress,
        utils.defaultAbiCoder.encode(
            ['address', 'address', 'address', 'address', 'address', 'address', 'address'],
            [
                addresses.borrowerOperationsAddress,
                addresses.collSurplusPoolAddress,
                addresses.ebtcTokenAddress,
                addresses.sortedCdpsAddress,
                addresses.activePoolAddress,
                addresses.priceFeedAddress,
                COLLATERAL
            ]
        )
    );

    // Deploy AccruableCdpManager
    await deployAndVerify(
        ebtcDeployer,
        'CdpManager',
        await ebtcDeployer.CDP_MANAGER(),
        addresses.cdpManagerAddress,
        utils.defaultAbiCoder.encode(
            ['address', 'address', 'address', 'address', 'address', 'address', 'address', 'address', 'address'],
            [
                addresses.liquidationLibraryAddress,
                addresses.authorityAddress,
                addresses.borrowerOperationsAddress,
                addresses.collSurplusPoolAddress,
                addresses.ebtcTokenAddress,
                addresses.sortedCdpsAddress,
                addresses.activePoolAddress,
                addresses.priceFeedAddress,
                COLLATERAL
            ]
        )
    );

    // Deploy BorrowerOperations
    await deployAndVerify(
        ebtcDeployer,
        'BorrowerOperations',
        await ebtcDeployer.BORROWER_OPERATIONS(),
        addresses.borrowerOperationsAddress,
        utils.defaultAbiCoder.encode(
            ['address', 'address', 'address', 'address', 'address', 'address', 'address', 'address'],
            [
                addresses.cdpManagerAddress,
                addresses.activePoolAddress,
                addresses.collSurplusPoolAddress,
                addresses.priceFeedAddress,
                addresses.sortedCdpsAddress,
                addresses.ebtcTokenAddress,
                addresses.feeRecipientAddress,
                COLLATERAL
            ]
        )
    );
    
    // Deploy PriceFeed
    await deployAndVerify(
        ebtcDeployer,
        'PriceFeed',
        await ebtcDeployer.PRICE_FEED(),
        addresses.priceFeedAddress,
        utils.defaultAbiCoder.encode(
            ['address', 'address', 'address', 'address'],
            [
                ethers.constants.AddressZero,
                addresses.authorityAddress,
                collEthOracle.address,
                ethBtcOracle.address
            ]
        )
    );

    // Deploy SortedCdps
    await deployAndVerify(
        ebtcDeployer,
        'SortedCdps',
        await ebtcDeployer.SORTED_CDPS(),
        addresses.sortedCdpsAddress,
        utils.defaultAbiCoder.encode(
            ['uint256', 'address', 'address'],
            [ethers.constants.MaxUint256, addresses.cdpManagerAddress, addresses.borrowerOperationsAddress]
        )
    );

    // Deploy ActivePool
    await deployAndVerify(
        ebtcDeployer,
        'ActivePool',
        await ebtcDeployer.ACTIVE_POOL(),
        addresses.activePoolAddress,
        utils.defaultAbiCoder.encode(
            ['address', 'address', 'address', 'address', 'address'],
            [
                addresses.borrowerOperationsAddress,
                addresses.cdpManagerAddress,
                COLLATERAL,
                addresses.collSurplusPoolAddress,
                addresses.feeRecipientAddress
            ]
        )
    );

    // Deploy CollSurplusPool
    await deployAndVerify(
        ebtcDeployer,
        'CollSurplusPool',
        await ebtcDeployer.COLL_SURPLUS_POOL(),
        addresses.collSurplusPoolAddress,
        utils.defaultAbiCoder.encode(
            ['address', 'address', 'address', 'address'],
            [
                addresses.borrowerOperationsAddress,
                addresses.cdpManagerAddress,
                addresses.activePoolAddress,
                COLLATERAL
            ]
        )
    );

    // Deploy HintHelpers
    await deployAndVerify(
        ebtcDeployer,
        'HintHelpers',
        await ebtcDeployer.HINT_HELPERS(),
        addresses.hintHelpersAddress,
        utils.defaultAbiCoder.encode(
            ['address', 'address', 'address', 'address', 'address'],
            [
                addresses.sortedCdpsAddress,
                addresses.cdpManagerAddress,
                COLLATERAL,
                addresses.activePoolAddress,
                addresses.priceFeedAddress
            ]
        )
    );

    // Deploy EBTCToken
    await deployAndVerify(
        ebtcDeployer,
        'EBTCToken',
        await ebtcDeployer.EBTC_TOKEN(),
        addresses.ebtcTokenAddress,
        utils.defaultAbiCoder.encode(
            ['address', 'address', 'address'],
            [addresses.cdpManagerAddress, addresses.borrowerOperationsAddress, addresses.authorityAddress]
        )
    );

    // Deploy FeeRecipient
    await deployAndVerify(
        ebtcDeployer,
        'FeeRecipient',
        await ebtcDeployer.FEE_RECIPIENT(),
        addresses.feeRecipientAddress,
        utils.defaultAbiCoder.encode(
            ['address', 'address'],
            [GOVERNANCE, addresses.authorityAddress]
        )
    );

    // Deploy MultiCdpGetter
    await deployAndVerify(
        ebtcDeployer,
        'MultiCdpGetter',
        await ebtcDeployer.MULTI_CDP_GETTER(),
        addresses.multiCdpGetterAddress,
        utils.defaultAbiCoder.encode(
            ['address', 'address'],
            [addresses.cdpManagerAddress, addresses.sortedCdpsAddress]
        )
    );
}

async function generateInitLiquidity(borrowerOperationsAddress, ebtcTokenAddress, stETHWhale, wbtcWhale) {
    const stETH = await ethers.getContractAt(ERC20ABI, COLLATERAL, stETHWhale);
    const borrowerOperations = await ethers.getContractAt(BorrowerOperationsABI, borrowerOperationsAddress, stETHWhale);

    await stETH.approve(borrowerOperationsAddress, ethers.constants.MaxUint256);
    await borrowerOperations.openCdp(
        ethers.utils.parseEther("1"), 
        ethers.utils.formatBytes32String(""), 
        ethers.utils.formatBytes32String(""), 
        ethers.utils.parseEther("40")
    );

    const eBTC = await ethers.getContractAt(ERC20ABI, ebtcTokenAddress, stETHWhale);
    const wBTC = await ethers.getContractAt(ERC20ABI, WBTC, wbtcWhale);

    await eBTC.transfer(wbtcWhale.address, await eBTC.balanceOf(stETHWhale.address));

    console.log(`eBTC = ${await eBTC.balanceOf(wbtcWhale.address)}`);
    console.log(`wBTC = ${await wBTC.balanceOf(wbtcWhale.address)}`);
}

async function initBalancerPool(ebtcTokenAddress, poolId) {
    console.log(`poolId = ${poolId}`);
    const balancerVault = await ethers.getContractAt(BalancerVaultABI, BALANCER_VAULT);

    //balancerVault.
}

async function createBalancerPool(ebtcTokenAddress) {
    const composableStablePoolFactory = await ethers.getContractAt(
        ComposableStablePoolFactoryABI, COMPOSABLE_STABLE_POOL_FACTORY
    );
    const tx = await composableStablePoolFactory.create(
        "Balancer eBTC/WBTC StablePool", 
        "eBTC/WBTC",
        [WBTC, ebtcTokenAddress],
        200,
        ["0x0000000000000000000000000000000000000000", "0x0000000000000000000000000000000000000000"],
        [10800, 10800],
        false,
        400000000000000,
        "0xE6FB62c2218fd9e3c948f0549A2959B509a293C8",
        "0x817949b4ae6a127c7810488d0643f173cd01e6f36dbfcb3b9dfbc1df681a1469"
    );
    const receipt = await tx.wait();
    return receipt.events[1].topics[1];
}

async function deployAaveZap(borrowerOperationsAddress) {
    const factory = await ethers.getContractFactory('AaveZapPrototype');
    const zap = await factory.deploy({
        flashLender: AAVE_FLASH_LENDER,
        borrowerOperations: borrowerOperationsAddress
    });
    await zap.deployed();
    await hre.tenderly.verify({
        address: zap.address,
        name: 'AaveZapPrototype'
    });
    return zap;
}

async function main() {
//    const EBTCDeployer = await ethers.getContractFactory('EBTCDeployer');
//    const ebtcDeployer = await EBTCDeployer.deploy();
//    await ebtcDeployer.deployed();

//    const addresses = await ebtcDeployer.getFutureEbtcAddresses();
//    console.log(addresses);

//    await deployEbtc(ebtcDeployer);
    const ebtcTokenAddress = '0x26387f6126824133a06a53600ce6c0fe552f648e';
    const borrowerOperationsAddress = '0xf53884610cb42267f4707b88590e682ac7ac7f25';
    const stETHWhale = '0xE53FFF67f9f384d20Ebea36F43b93DC49Ed22753';
    const wbtcWhale = '0xeDCdf2e84F2a6BA94B557B03BDFb7D10ecA5aa50';

    await deployAaveZap(borrowerOperationsAddress);

    // Tenderly does not require impersonation
    /*await generateInitLiquidity(
        borrowerOperationsAddress, 
        ebtcTokenAddress,
        await ethers.getSigner(stETHWhale),
        await ethers.getSigner(wbtcWhale)
    );*/
 //   const poolId = await createBalancerPool(ebtcTokenAddress);
 //   await initBalancerPool(ebtcTokenAddress, poolId);
}

main();
