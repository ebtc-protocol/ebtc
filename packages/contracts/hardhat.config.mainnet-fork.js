require("@nomiclabs/hardhat-truffle5");
require("@nomiclabs/hardhat-ethers");
require("solidity-coverage");
require("hardhat-gas-reporter");
const accounts = require("./hardhatAccountsList2k.js");
const accountsList = accounts.accountsList

const fs = require('fs')
const alchemyUrl = () => {
    const SECRETS_FILE = "./secrets.js"
    let alchemyAPIKey = ""
    if (fs.existsSync(SECRETS_FILE)) {
        const { secrets } = require(SECRETS_FILE)
        alchemyAPIKey = secrets.alchemyAPIKey
        if (alchemyAPIKey != undefined){
            return `https://eth-mainnet.g.alchemy.com/v2/${alchemyAPIKey}`
        } else {
            throw "Add an alchemyAPIKey to ./secrets.js!"
        }
    } else {
        throw "Add a ./secrets.js file!"
    }
}

module.exports = {
    paths: {
        // contracts: "./contracts",
        // artifacts: "./artifacts"
    },
    solidity: {
        compilers: [
            {
                version: "0.4.23",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 100
                    }
                }
            },
            {
                version: "0.5.17",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 100
                    }
                }
            },
            {
                version: "0.6.11",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 100
                    }
                }
            },
        ]
    },
    networks: {
        hardhat: {
            chainId: 31337,
            accounts: accountsList,
            gas: 50000000,  // tx gas limit
            blockGasLimit: 15000000,
            initialBaseFeePerGas: 0,
            gasPrice: typeof (process.env.GAS_PRICE) == 'NaN'  ? parseInt(process.env.GAS_PRICE) : 0,
            forking: {
                url: alchemyUrl(),
                blockNumber: typeof (process.env.BLOCK_NUMBER) == 'NaN' ? parseInt(process.env.BLOCK_NUMBER) : 16141281
            }
        }
    },
    mocha: { timeout: 12000000 },
    rpc: {
        host: "localhost",
        port: 8545
    },
    gasReporter: {
        enabled: (process.env.REPORT_GAS) ? true : false
    }
};
