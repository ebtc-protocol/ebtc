// npx hardhat run .\scripts\tenderly.js --network tenderly
const hre = require('hardhat');
const utils = hre.ethers.utils;

// stETH
const COLLATERAL = '0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84';
const COLL_ETH_ORACLE = '0x86392dc19c0b719886221c78ab11eb8cf5c52812';
const ETH_BTC_ORACLE = '0xAc559F25B1619171CbC396a50854A3240b6A4e99';
const GOVERNANCE = '0xB65cef03b9B89f99517643226d76e286ee999e77';

async function deployAndVerify(deployer, contractName, salt, deployedAddress, args) {
    const factory = await hre.ethers.getContractFactory(contractName);
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
    const factory = await hre.ethers.getContractFactory('TenderlyAggregator');
    const oracle = await factory.deploy(realOracle);
    await oracle.deployed();
    await hre.tenderly.verify({
        address: oracle.address,
        name: 'TenderlyAggregator'
    });
    return oracle;
}

async function main() {
    const collEthOracle = await deployMockOracle(COLL_ETH_ORACLE);
    const ethBtcOracle = await deployMockOracle(ETH_BTC_ORACLE);

    const EBTCDeployer = await hre.ethers.getContractFactory('EBTCDeployer');
    const ebtcDeployer = await EBTCDeployer.deploy();
    await ebtcDeployer.deployed();

    const addresses = await ebtcDeployer.getFutureEbtcAddresses();
    console.log(addresses);

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
                hre.ethers.constants.AddressZero,
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
            [hre.ethers.constants.MaxUint256, addresses.cdpManagerAddress, addresses.borrowerOperationsAddress]
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

main();
