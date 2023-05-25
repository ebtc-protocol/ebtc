const externalAddress  = {
  "collEthCLFeed": "0xb4c4a493AB6356497713A78FFA6c60FB53517c63",//goerli
  "ethBtcCLFeed": "0x779877A7B0D9E8603169DdbD7836e478b4624789",//goerli
}

const OUTPUT_FILE = './mainnetDeployment/eBTCGoerliDeploymentOutput.json'

const DEPLOY_WAIT = 120000 // milli-secnds
const GAS_PRICE = 80000000000 // x Gwei
const MAX_FEE_PER_GAS = 100833966421
const TX_CONFIRMATIONS = 1

const VERIFY_ETHERSCAN = true
const ETHERSCAN_BASE_URL = 'https://goerli.etherscan.io/address'

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
