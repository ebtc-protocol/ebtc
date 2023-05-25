const externalAddress  = {
  // No external addresses, will deploy mocks
}

const OUTPUT_FILE = './mainnetDeployment/eBTCLocalDeploymentOutput.json'

const DEPLOY_WAIT = 100 // milli-seocnds
const GAS_PRICE = 80000000000 // x Gwei
const MAX_FEE_PER_GAS = 100833966421
const TX_CONFIRMATIONS = 1

module.exports = {
  OUTPUT_FILE,
  DEPLOY_WAIT,
  GAS_PRICE,
  MAX_FEE_PER_GAS,
  TX_CONFIRMATIONS,
  externalAddress
};
