// npx hardhat run .\scripts\tenderly.js --network tenderly
const hre = require('hardhat');
const utils = hre.ethers.utils;

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
}

// stETH
const collateral = '0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84';

async function main() {
    const EBTCDeployer = await hre.ethers.getContractFactory('EBTCDeployer');
    const ebtcDeployer = await EBTCDeployer.deploy();
    await ebtcDeployer.deployed();

    const addresses = await ebtcDeployer.getFutureEbtcAddresses();
    console.log(addresses);

    await deployAndVerify(
        ebtcDeployer, 
        'Governor', 
        await ebtcDeployer.AUTHORITY(), 
        addresses.authorityAddress, 
        utils.defaultAbiCoder.encode(['address'], [ebtcDeployer.address])
    );

    await deployAndVerify(
        ebtcDeployer, 
        'LiquidationLibrary', 
        await ebtcDeployer.LIQUIDATION_LIBRARY(), 
        addresses.liquidationLibraryAddress,
        utils.defaultAbiCoder.encode(
            [
                'address', 'address', 'address', 'address', 'address', 'address', 'address'
            ],
            [
                addresses.borrowerOperationsAddress,
                addresses.collSurplusPoolAddress,
                addresses.ebtcTokenAddress,
                addresses.sortedCdpsAddress,
                addresses.activePoolAddress,
                addresses.priceFeedAddress,
                collateral
            ]
        )
    );
}

main();
