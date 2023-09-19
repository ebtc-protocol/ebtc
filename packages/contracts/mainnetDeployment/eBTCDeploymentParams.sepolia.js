const externalAddress  = {
}

const OUTPUT_FILE = './mainnetDeployment/eBTCSepoliaDeploymentOutput.json'

const DEPLOY_WAIT = 30000 // milli-secnds
const GAS_PRICE = 80000000000 // x Gwei
const MAX_FEE_PER_GAS = 100833966421
const TX_CONFIRMATIONS = 1

const VERIFY_ETHERSCAN = true
const ETHERSCAN_BASE_URL = 'https://sepolia.etherscan.io/address'

module.exports = {
  OUTPUT_FILE,
  DEPLOY_WAIT,
  GAS_PRICE,
  MAX_FEE_PER_GAS,
  TX_CONFIRMATIONS,
  ETHERSCAN_BASE_URL,
  VERIFY_ETHERSCAN,
  externalAddress
};
