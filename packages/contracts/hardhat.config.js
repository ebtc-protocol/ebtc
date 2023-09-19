require("@nomiclabs/hardhat-truffle5");
require("@nomiclabs/hardhat-ethers");
require("@nomiclabs/hardhat-etherscan");
require("solidity-coverage");
require("hardhat-gas-reporter");
require("hardhat-contract-sizer");

const accounts = require("./hardhatAccountsList2k.js");
const accountsList = accounts.accountsList;

const fs = require("fs");
const getSecret = (secretKey, defaultValue = "") => {
  const SECRETS_FILE = "./secrets.js";
  let secret = defaultValue;
  if (fs.existsSync(SECRETS_FILE)) {
    const { secrets } = require(SECRETS_FILE);
    if (secrets[secretKey]) {
      secret = secrets[secretKey];
    }
  }

  return secret;
};
const alchemyUrl = () => {
  return `https://eth-mainnet.g.alchemy.com/v2/${getSecret("alchemyAPIKey")}`;
};

const alchemyUrlGoerli = () => {
  return `https://eth-goerli.g.alchemy.com/v2/${getSecret("alchemyAPIKeyGoerli")}`;
};

const alchemyUrlSepolia = () => {
  return `https://eth-sepolia.g.alchemy.com/v2/${getSecret("alchemyAPIKeySepolia")}`;
};

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
        version: "0.8.17",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      }
    ]
  },
  networks: {
    hardhat: {
      accounts: accountsList,
      allowUnlimitedContractSize: true
    },
    mainnet: {
      url: alchemyUrl(),
      gasPrice: process.env.GAS_PRICE ? parseInt(process.env.GAS_PRICE) : 20000000000,
      accounts: [
        getSecret(
          "DEPLOYER_PRIVATEKEY",
          "0x60ddfe7f579ab6867cbe7a2dc03853dc141d7a4ab6dbefc0dae2d2b1bd4e487f"
        ),
        getSecret(
          "ACCOUNT2_PRIVATEKEY",
          "0x3ec7cedbafd0cb9ec05bf9f7ccfa1e8b42b3e3a02c75addfccbfeb328d1b383b"
        )
      ]
    },
    goerli: {
      url: alchemyUrlGoerli(),
      gas: 10000000, // tx gas limit
      accounts: [
        getSecret(
          "DEPLOYER_PRIVATEKEY",
          "0x60ddfe7f579ab6867cbe7a2dc03853dc141d7a4ab6dbefc0dae2d2b1bd4e487f"
        )
      ]
    },
    sepolia: {
      url: alchemyUrlSepolia(),
      gas: 10000000, // tx gas limit
      accounts: [
        getSecret(
          "DEPLOYER_PRIVATEKEY",
          "0x60ddfe7f579ab6867cbe7a2dc03853dc141d7a4ab6dbefc0dae2d2b1bd4e487f"
        )
      ]
    }
  },
  etherscan: {
    apiKey: getSecret("ETHERSCAN_API_KEY")
  },
  mocha: { timeout: 12000000 },
  rpc: {
    host: "localhost",
    port: 8545
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS ? true : false
  }
};
