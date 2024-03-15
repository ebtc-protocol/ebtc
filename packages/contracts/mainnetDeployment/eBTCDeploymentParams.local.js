const externalAddress  = {
  // No external addresses, will deploy mocks
}

const OUTPUT_FILE = './mainnetDeployment/eBTCLocalDeploymentOutput.json'

const DEPLOY_WAIT = 1000 // milli-seconds
const GAS_PRICE = 1000000000 // x Gwei
const MAX_FEE_PER_GAS = 100833966421
const TX_CONFIRMATIONS = 1

const VERIFY_ETHERSCAN = false

// Timelock configuration parameters
const HIGHSEC_MIN_DELAY = 600 // 10 mins
const LOWSEC_MIN_DELAY = 300 // 5 mins

const ADDITIONAL_HIGHSEC_ADMIN = ""
const ADDITIONAL_LOWSEC_ADMIN = ""

// Toggle if reusing Timelocks already configured or if configuration is handled manually
const SKIP_TIMELOCK_CONFIG = true

module.exports = {
  OUTPUT_FILE,
  DEPLOY_WAIT,
  GAS_PRICE,
  MAX_FEE_PER_GAS,
  TX_CONFIRMATIONS,
  VERIFY_ETHERSCAN,
  externalAddress,
  HIGHSEC_MIN_DELAY,
  LOWSEC_MIN_DELAY,
  ADDITIONAL_HIGHSEC_ADMIN,
  ADDITIONAL_LOWSEC_ADMIN,
  SKIP_TIMELOCK_CONFIG
};
